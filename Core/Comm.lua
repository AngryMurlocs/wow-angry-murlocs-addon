local GR = AngryMurlocs
local U = GR.Util
local P = GR.Protocol

-- Wire prefix kept as GildenRadar so mixed guild installs still talk
GR.PREFIX = "GildenRadar"
GR.PREFIX_NEW = "AngryMurlocs"
GR.Comm = GR.Comm or {}
local Comm = GR.Comm

local registered = false

local RATE_WINDOW = 10
local RATE_MAX = 24
local MAX_SEND = 250
local MAX_RECV = 255
local FRAG_TTL = 30
-- 2 msg/s stays below the receiver limit of RATE_MAX per RATE_WINDOW.
local SEND_INTERVAL = 0.5
local PEER_TTL = 3600
local SWEEP_EVERY = 60

local rateBuckets = {}
local fragBuf = {}
local fragSeq = 0
local peers = {}
local lastSweep = 0
local lastSendAt = -SEND_INTERVAL
local drainTicker
local queue = GR.SendQueue.New()
-- Session-only: guild peer version nag (no SavedVariables).
local versionAnnounceSent = false
local versionNagPrinted = false
local bestPeerVersion = nil

local VALID_CLASS = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
  DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
  DRUID = true, DEMONHUNTER = true, EVOKER = true,
}

local V2_TAGS = { WK = true, SR = true, WSH = true, WS = true, WSE = true }

-- Send category -> privacy setting. Checked on enqueue and again right before sending.
local GATES = {
  pos = function(p) return p.sharePosition end,
  prof = function(p) return p.shareProfessions end,
  death = function(p) return p.shareDeath end,
  sight = function(p) return p.shareSightings ~= false end,
  lvl = function(p) return p.shareLevelUp end,
}

local function Diag()
  return GR.Diag
end

local function Reject(reason, detail)
  local d = Diag()
  if d then d:Reject(reason, detail) end
end

local function Count(key)
  local d = Diag()
  if d then d:Count(key) end
end

function Comm:Allowed(category)
  local gate = GATES[category]
  if not gate then return true end
  local privacy = GR.db and GR.db.privacy
  if not privacy then return false end
  return gate(privacy) and true or false
end

local function Sweep(now)
  if (now - lastSweep) < SWEEP_EVERY then return end
  lastSweep = now
  for k, b in pairs(rateBuckets) do
    if (now - b.t) > RATE_WINDOW then rateBuckets[k] = nil end
  end
  for k, buf in pairs(fragBuf) do
    if (now - buf.t) > FRAG_TTL then fragBuf[k] = nil end
  end
  local wall = U.WallTime()
  for k, p in pairs(peers) do
    if (wall - p.t) > PEER_TTL then peers[k] = nil end
  end
end

local function AllowSender(sender, now)
  local b = rateBuckets[sender]
  if not b or (now - b.t) > RATE_WINDOW then
    rateBuckets[sender] = { t = now, n = 1 }
    return true
  end
  b.n = b.n + 1
  return b.n <= RATE_MAX
end

-- Wait after the client reports a send throttle before trying again.
local THROTTLE_BACKOFF = 1.0
-- Wait while the client blocks addon messages (AddOnMessageLockdown).
local LOCKDOWN_BACKOFF = 5.0

-- Modern clients return Enum.SendAddonMessageResult; older ones return nothing
-- or a boolean. Returns "ok", "throttled", "lockdown" or "failed".
local function SendResult(result)
  if result == nil or result == true then return "ok" end
  if result == false then return "failed" end
  local codes = Enum and Enum.SendAddonMessageResult
  if codes then
    if result == codes.Success then return "ok" end
    if result == codes.AddonMessageThrottle or result == codes.ChannelThrottle then
      return "throttled"
    end
    if result == codes.AddOnMessageLockdown then return "lockdown" end
    return "failed"
  end
  return result == 0 and "ok" or "failed"
end

local function RawSend(payload)
  if not IsInGuild() then return "failed" end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return "failed" end
  if #payload > MAX_SEND then return "failed" end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, GR.PREFIX, payload, "GUILD")
  if not ok then return "failed" end
  return SendResult(result)
end

local function Drain()
  local now = U.Now()
  -- No pre-check with C_ChatInfo.AreOutgoingAddonChatMessagesRestricted: on
  -- Forever it answered true in the open world while sending worked, which
  -- held the whole queue back (0.11.3 ingame test). The send result decides.
  if (now - lastSendAt) >= SEND_INTERVAL then
    local item = queue:Pop(now)
    while item and not Comm:Allowed(item.category) do
      Reject("privacy", item.category)
      item = queue:Pop(now)
    end
    if item then
      lastSendAt = now
      local status = RawSend(item.payload)
      if status == "ok" then
        Count("sent_" .. item.prio)
      elseif status == "throttled" or status == "lockdown" then
        -- Try the same message again later; order stays the same.
        queue:PushFront(item)
        lastSendAt = now + (status == "lockdown" and LOCKDOWN_BACKOFF or THROTTLE_BACKOFF)
        Count(status)
      else
        Reject("send_failed", item.prio)
      end
    end
  end
  if queue:Size() == 0 and drainTicker then
    drainTicker:Cancel()
    drainTicker = nil
  end
end

local function EnsureDrain()
  if not drainTicker then
    drainTicker = C_Timer.NewTicker(SEND_INTERVAL / 2, Drain)
  end
  Drain()
end

function Comm:Register()
  if registered then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(GR.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(GR.PREFIX_NEW)
    registered = true
  end
end

-- Never silently truncates; long payloads become FRAG|id|i|n|chunk messages.
local function Fragment(payload)
  if #payload <= MAX_SEND then
    return { payload }
  end
  fragSeq = fragSeq + 1
  local id = string.format("%s%d", string.sub(U.ShortName(U.PlayerName()) or "x", 1, 6), fragSeq % 100000)
  local headerBase = "FRAG|" .. id .. "|"
  local chunkSize = MAX_SEND - (#headerBase + 10)
  if chunkSize < 32 then chunkSize = 32 end
  local chunks = {}
  local pos = 1
  while pos <= #payload do
    chunks[#chunks + 1] = payload:sub(pos, pos + chunkSize - 1)
    pos = pos + chunkSize
  end
  if #chunks > 99 then return nil end
  local out = {}
  for i = 1, #chunks do
    local msg = string.format("FRAG|%s|%d|%d|%s", id, i, #chunks, chunks[i])
    if #msg > MAX_SEND then return nil end
    out[i] = msg
  end
  return out
end

-- prio: kill | ctrl | data | pos. category: privacy gate key (pos, prof, death,
-- sight, lvl) or a free label for always-allowed traffic (sync, ctrl).
function Comm:Send(payload, prio, category)
  prio = prio or "data"
  category = category or "misc"
  if type(payload) ~= "string" or payload == "" then return false end
  if not IsInGuild or not IsInGuild() then return false end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  if not Comm:Allowed(category) then
    Reject("privacy", category)
    return false
  end
  local msgs = Fragment(payload)
  if not msgs then
    Reject("too_long", prio)
    return false
  end
  local items = {}
  for i = 1, #msgs do
    items[i] = { payload = msgs[i], category = category }
  end
  local ok, why = queue:PushAll(prio, items, U.Now())
  if not ok then
    Reject("queue_" .. tostring(why), prio)
    return false
  end
  EnsureDrain()
  return true
end

Comm.SendFull = Comm.Send

function Comm:QueueSize(prio)
  return queue:Size(prio)
end

function Comm:Purge(category)
  local n = queue:Purge(function(item) return item.category == category end)
  if n > 0 then Reject("privacy_purged", category .. " x" .. n) end
  return n
end

-- fn(payload) -> true drops the queued message.
function Comm:PurgeWhere(fn)
  return queue:Purge(function(item) return fn(item.payload) end)
end

-- Drop everything whose privacy gate is closed now.
function Comm:PurgeDisallowed()
  local n = queue:Purge(function(item) return not Comm:Allowed(item.category) end)
  if n > 0 then Reject("privacy_purged", "x" .. n) end
  return n
end

-- Addon users heard from within `window` seconds (any valid message).
function Comm:Peers(window)
  local wall = U.WallTime()
  window = window or 600
  local n, v2, newest = 0, 0, nil
  for _, p in pairs(peers) do
    local age = wall - p.t
    if age <= window then
      n = n + 1
      if p.v2 then v2 = v2 + 1 end
      if not newest or age < newest then newest = age end
    end
  end
  return n, v2, newest
end

-- Broadcast own addon SemVer once per session (guild only). No reply storm.
function Comm:AnnounceVersion()
  if versionAnnounceSent then return false end
  local ver = tostring(GR.VERSION or "")
  if not U.ParseAddonVersion(ver) then return false end
  -- Wire: digits and dots only; strip accidental junk after parse rebuild.
  local p = U.ParseAddonVersion(ver)
  ver = string.format("%d.%d.%d", p[1], p[2], p[3])
  if not Comm:Send("VER|" .. ver, "ctrl", "misc") then return false end
  versionAnnounceSent = true
  return true
end

local function NotePeerVersion(ver)
  ver = tostring(ver or ""):match("^%s*([^|%s]+)")
  local parsed = ver and U.ParseAddonVersion(ver)
  if not parsed then return end
  ver = string.format("%d.%d.%d", parsed[1], parsed[2], parsed[3])
  if not bestPeerVersion or (U.CompareAddonVersion(ver, bestPeerVersion) or 0) > 0 then
    bestPeerVersion = ver
  end
  if versionNagPrinted then return end
  local cmp = U.CompareAddonVersion(bestPeerVersion, GR.VERSION)
  if cmp and cmp > 0 then
    versionNagPrinted = true
    U.Print(string.format(U.L("UPDATE_AVAILABLE"), bestPeerVersion, tostring(GR.VERSION)))
  end
end

-- Seconds since last addon message from this character (CharKey match), or nil.
function Comm:PeerAge(name)
  if not name or name == "" then return nil end
  local wall = U.WallTime()
  local want = U.CharKey(name)
  if not want then return nil end
  local best
  for sender, p in pairs(peers) do
    if U.CharKey(sender) == want and p.t then
      local age = wall - p.t
      if age >= 0 and (not best or age < best) then
        best = age
      end
    end
  end
  return best
end

local function DispatchV2(tag, rest, sender)
  local data, why
  if tag == "WK" then
    data, why = P.DecodeWK(rest)
    if data and not U.SameCharacter(data.origin, sender) then
      data, why = nil, "origin_mismatch"
    end
    if data then data.killer = U.NormalizeName(data.killer) end
  elseif tag == "SR" then
    data, why = P.DecodeSR(rest)
  elseif tag == "WSH" then
    data, why = P.DecodeWSH(rest)
  elseif tag == "WSE" then
    data, why = P.DecodeWSE(rest)
  elseif tag == "WS" then
    data, why = P.DecodeWS(rest)
    if data then data.killer = U.NormalizeName(data.killer) end
  end
  if not data then
    Reject(why == "origin_mismatch" and "origin_mismatch" or "invalid", tag .. " " .. tostring(why) .. " " .. tostring(sender))
    return
  end
  Count("recv_" .. tag)
  GR:SendMessage("WANTED_V2", tag, sender, data)
end

local function DispatchParsed(tag, rest, sender)
  if V2_TAGS[tag] then
    DispatchV2(tag, rest, sender)
    return
  end
  if tag == "POS" then
    local parts = U.Split(rest, "|")
    local mapId = tonumber(parts[1])
    local x = tonumber(parts[2])
    local y = tonumber(parts[3])
    local zone = U.SanitizeText(parts[4], 48)
    local dead = tonumber(parts[5]) == 1
    local classFile = tostring(parts[6] or "PRIEST"):upper()
    if not VALID_CLASS[classFile] then classFile = "PRIEST" end
    local level = tonumber(parts[7]) or 0
    if level < 1 then level = 1 end
    if level > U.MaxLevel() then level = U.MaxLevel() end
    if not mapId or mapId < 1 or mapId > 99999 then return end
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if x == 0 and y == 0 then return end
    GR:SendMessage("POS_UPDATE", sender, {
      mapId = mapId,
      x = x,
      y = y,
      zone = zone,
      dead = dead,
      classFile = classFile,
      level = level,
      time = U.Now(),
    })
  elseif tag == "PROF" then
    -- Keep payload separators (+ or legacy |); do not SanitizeText the whole rest
    local cleaned = tostring(rest or ""):gsub("[%c]", "")
    if #cleaned > 200 then cleaned = cleaned:sub(1, 200) end
    GR:SendMessage("PROF_UPDATE", sender, cleaned)
  elseif tag == "PROFREQ" then
    GR:SendMessage("PROF_REQUEST", sender)
  elseif tag == "PROFR" then
    -- Recipe knowledge; may be large (FRAG-reassembled). Do not 200-truncate like PROF.
    local cleaned = tostring(rest or ""):gsub("[%c]", "")
    if #cleaned > 20000 then
      Reject("too_long", "PROFR " .. tostring(sender))
      return
    end
    local recipes = GR:GetModule("ProfRecipes")
    local data, why = recipes and recipes.Decode and recipes.Decode(cleaned)
    if not data then
      Reject("invalid", "PROFR " .. tostring(why) .. " " .. tostring(sender))
      return
    end
    Count("recv_PROFR")
    GR:SendMessage("PROF_RECIPE_UPDATE", sender, data)
  elseif tag == "PROFRQ" then
    local cleaned = tostring(rest or ""):gsub("[%c]", "")
    local ver, profKey = cleaned:match("^(%d+)|([%w_]*)$")
    if not ver then
      ver, profKey = cleaned:match("^(%d+)$"), ""
    end
    if tonumber(ver) ~= 1 then return end
    Count("recv_PROFRQ")
    GR:SendMessage("PROF_RECIPE_REQUEST", sender, profKey or "")
  elseif tag == "PROFRMQ" then
    -- Recipe metadata request (IDs only). Older clients ignore unknown tags.
    local cleaned = tostring(rest or ""):gsub("[%c]", "")
    if #cleaned > 4000 then
      Reject("too_long", "PROFRMQ " .. tostring(sender))
      return
    end
    local recipes = GR:GetModule("ProfRecipes")
    local ids, why = recipes and recipes.DecodeMetaRequest and recipes.DecodeMetaRequest(cleaned)
    if not ids then
      Reject("invalid", "PROFRMQ " .. tostring(why) .. " " .. tostring(sender))
      return
    end
    Count("recv_PROFRMQ")
    GR:SendMessage("PROF_RECIPE_META_REQUEST", sender, ids)
  elseif tag == "PROFRM" then
    -- Recipe metadata batch (names/reagents). Does not grant craft knowledge.
    local cleaned = tostring(rest or ""):gsub("[%c]", "")
    if #cleaned > 20000 then
      Reject("too_long", "PROFRM " .. tostring(sender))
      return
    end
    local recipes = GR:GetModule("ProfRecipes")
    local entries, why = recipes and recipes.DecodeMetaBatch and recipes.DecodeMetaBatch(cleaned)
    if not entries then
      Reject("invalid", "PROFRM " .. tostring(why) .. " " .. tostring(sender))
      return
    end
    Count("recv_PROFRM")
    GR:SendMessage("PROF_RECIPE_META_UPDATE", sender, entries)
  elseif tag == "DEATH" then
    local parts = U.SplitKeepEmpty(rest, "|")
    local cause = parts[5]
    if cause ~= "player" and cause ~= "mob" and cause ~= "env" and cause ~= "unknown" then
      cause = (tonumber(parts[2]) == 1) and "player" or "mob"
    end
    GR:SendMessage("DEATH_UPDATE", sender, {
      killer = U.SanitizeText(parts[1] or "?", 48),
      isPlayer = cause == "player",
      zone = U.SanitizeText(parts[3] or "", 48),
      mapId = tonumber(parts[4]),
      cause = cause,
      spell = U.SanitizeText(parts[6] or "", 48),
      time = U.Now(),
    })
  elseif tag == "WANTED" or tag == "SYNCREQ" then
    -- 0.6.x Wanted wire: counts are snapshot maxima from target-based attribution
    -- and clears are unauthorized; neither is applied by 0.7+.
    Count("legacy_ignored")
  elseif tag == "LVL" then
    local level = tonumber(rest)
    if level and level >= 1 and level <= U.MaxLevel() then
      GR:SendMessage("LVL_UPDATE", sender, level)
    end
  elseif tag == "SIGHT" then
    local parts = U.SplitKeepEmpty(rest, "|")
    local target = U.NormalizeName(U.SanitizeText(parts[1] or "", 48))
    local zone = U.SanitizeText(parts[2] or "", 48)
    local ts = U.ClampTs(parts[3])
    if not target or target == "" then return end
    if not ts then
      Reject("bad_ts", "SIGHT " .. tostring(sender))
      return
    end
    GR:SendMessage("SIGHT_UPDATE", sender, {
      target = target,
      zone = zone,
      ts = ts,
      fromRemote = true,
    })
  elseif tag == "VER" then
    -- Peer addon version; no privacy payload. Older clients ignore unknown tags.
    local ver = U.SplitKeepEmpty(rest, "|")[1]
    NotePeerVersion(ver)
  end
  -- Unknown tags (incl. legacy MAIN/CRAFT) ignored for mixed clients
end

local function HandleMessage(message, sender)
  local tag, rest = message:match("^([^|]+)|?(.*)$")
  if not tag then return end
  tag = tag:upper()
  if #tag > 12 then return end

  if tag == "FRAG" then
    local parts = U.SplitKeepEmpty(rest, "|")
    local id = parts[1] or ""
    local i = tonumber(parts[2])
    local n = tonumber(parts[3])
    -- chunk may contain pipes: rejoin remaining
    local chunk
    if i and n and id ~= "" then
      local prefix = id .. "|" .. tostring(i) .. "|" .. tostring(n) .. "|"
      local idx = rest:find(prefix, 1, true)
      if idx == 1 then
        chunk = rest:sub(#prefix + 1)
      else
        chunk = parts[4] or ""
      end
    end
    if not i or not n or id == "" or n < 1 or n > 99 or i < 1 or i > n then return end
    local now = U.Now()
    local key = sender .. "::" .. id
    local buf = fragBuf[key]
    if not buf or buf.n ~= n or (now - buf.t) > FRAG_TTL then
      buf = { n = n, t = now, parts = {}, count = 0 }
      fragBuf[key] = buf
    end
    if not buf.parts[i] then
      buf.parts[i] = chunk or ""
      buf.count = buf.count + 1
    end
    -- The timeout counts from the latest part, so a long message that keeps
    -- arriving is not dropped halfway.
    buf.t = now
    if buf.count >= n then
      local full = {}
      for k = 1, n do
        if not buf.parts[k] then
          fragBuf[key] = nil
          return
        end
        full[k] = buf.parts[k]
      end
      fragBuf[key] = nil
      HandleMessage(table.concat(full), sender)
    end
    return
  end

  if V2_TAGS[tag] and peers[sender] then
    peers[sender].v2 = true
  end
  DispatchParsed(tag, rest or "", sender)
end

function Comm:OnAddonMessage(prefix, message, channel, sender)
  if prefix ~= GR.PREFIX and prefix ~= GR.PREFIX_NEW then return end
  if channel ~= "GUILD" then return end
  if not IsInGuild or not IsInGuild() then return end
  if type(message) ~= "string" or message == "" or #message > MAX_RECV then return end

  sender = U.NormalizeName(sender)
  if not sender or U.IsSelfName(sender) then return end
  local now = U.Now()
  Sweep(now)
  if not AllowSender(sender, now) then
    Reject("rate", sender)
    return
  end
  local peer = peers[sender]
  if not peer then
    peer = { t = 0 }
    peers[sender] = peer
  end
  peer.t = U.WallTime()
  Count("recv")

  HandleMessage(message, sender)
end

-- Drop all outbound traffic and peer state when the player leaves a guild.
function Comm:OnGuildLeft()
  local n = queue:Purge(function() return true end)
  if n > 0 then Reject("guild_left", "queue x" .. n) end
  wipe(peers)
  wipe(rateBuckets)
  wipe(fragBuf)
  versionAnnounceSent = false
  if drainTicker then
    drainTicker:Cancel()
    drainTicker = nil
  end
  lastSendAt = -SEND_INTERVAL
end

local function OnPrivacyChanged()
  Comm:PurgeDisallowed()
end
GR:RegisterMessage("PRIVACY_CHANGED", OnPrivacyChanged)
GR:RegisterMessage("SHARE_POS_CHANGED", OnPrivacyChanged)
GR:RegisterMessage("SHARE_PROF_CHANGED", OnPrivacyChanged)
