local GR = AngryMurlocs
local U = GR.Util

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
local rateBuckets = {}
local fragBuf = {}
local fragSeq = 0

local VALID_CLASS = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
  DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
  DRUID = true, DEMONHUNTER = true, EVOKER = true,
}

local VALID_CRAFT_ACTION = {
  create = true, claim = true, unclaim = true,
  assign = true, done = true, reopen = true, cancel = true,
}

local function AllowSender(sender)
  if not sender then return false end
  local now = GetTime and GetTime() or 0
  local b = rateBuckets[sender]
  if not b or (now - b.t) > RATE_WINDOW then
    rateBuckets[sender] = { t = now, n = 1 }
    return true
  end
  b.n = b.n + 1
  local ok = b.n <= RATE_MAX
  -- #region agent log
  if not ok then
    U.AgentLog("H2", "Comm.lua:AllowSender", "rate_limit_drop", {
      sender = U.ShortName(sender),
      n = b.n,
      max = RATE_MAX,
      window = RATE_WINDOW,
    })
  end
  -- #endregion
  return ok
end

local function RawSend(payload)
  if not IsInGuild() then return false end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  if type(payload) ~= "string" or payload == "" then return false end
  if #payload > MAX_SEND then return false end
  C_ChatInfo.SendAddonMessage(GR.PREFIX, payload, "GUILD")
  return true
end

function Comm:Register()
  if registered then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(GR.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(GR.PREFIX_NEW)
    registered = true
  end
end

-- Safe send: never silently truncates. Fragments when needed.
function Comm:SendFull(payload)
  if not IsInGuild() then return false end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  if type(payload) ~= "string" or payload == "" then return false end

  if #payload <= MAX_SEND then
    return RawSend(payload)
  end

  fragSeq = fragSeq + 1
  local id = string.format("%s%d", string.sub(U.ShortName(U.PlayerName()) or "x", 1, 6), fragSeq % 100000)
  -- FRAG|id|i|n|chunk  — reserve header room
  local headerBase = "FRAG|" .. id .. "|"
  -- worst case: FRAG|id|99|99|  (~20+ chars); use 40 to be safe
  local chunkSize = MAX_SEND - (#headerBase + 10)
  if chunkSize < 32 then chunkSize = 32 end

  local chunks = {}
  local pos = 1
  while pos <= #payload do
    chunks[#chunks + 1] = payload:sub(pos, pos + chunkSize - 1)
    pos = pos + chunkSize
  end
  local n = #chunks
  if n > 99 then
    return false
  end
  for i = 1, n do
    local msg = string.format("FRAG|%s|%d|%d|%s", id, i, n, chunks[i])
    if #msg > MAX_SEND then
      return false
    end
    if not RawSend(msg) then
      return false
    end
  end
  return true
end

function Comm:Send(payload)
  return Comm:SendFull(payload)
end

local function DispatchParsed(tag, rest, sender)
  -- #region agent log
  local pipeCount = 0
  if rest then
    for _ in string.gmatch(rest, "|") do pipeCount = pipeCount + 1 end
  end
  local sanitizedWould = U.SanitizeText(rest or "", 200)
  local sanitizeKillsPipes = (pipeCount > 0) and (not sanitizedWould:find("|", 1, true))
  if tag ~= "POS" then
    U.AgentLog("H1", "Comm.lua:DispatchParsed", "dispatch_enter", {
      tag = tag,
      restLen = #(rest or ""),
      pipeCount = pipeCount,
      sanitizeKillsPipes = sanitizeKillsPipes and true or false,
      sender = U.ShortName(sender),
    })
  end
  -- #endregion
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
    if level > 80 then level = 80 end
    if not mapId or mapId < 1 or mapId > 99999 then return end
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
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
    -- Keep | delimiters (key:skill|key:skill); SanitizeText would strip them
    local cleaned = tostring(rest or ""):gsub("[%c]", "")
    if #cleaned > 200 then cleaned = cleaned:sub(1, 200) end
    -- #region agent log
    local cleanedPipes = 0
    for _ in string.gmatch(cleaned, "|") do cleanedPipes = cleanedPipes + 1 end
    U.AgentLog("H6", "Comm.lua:PROF", "prof_cleaned", {
      cleanedLen = #cleaned,
      cleanedPipes = cleanedPipes,
      sender = U.ShortName(sender),
    })
    -- #endregion
    GR:SendMessage("PROF_UPDATE", sender, cleaned)
  elseif tag == "PROFREQ" then
    GR:SendMessage("PROF_REQUEST", sender)
  elseif tag == "DEATH" then
    local parts = U.Split(rest, "|")
    local cause = parts[5]
    if cause ~= "player" and cause ~= "mob" and cause ~= "env" then
      cause = (tonumber(parts[2]) == 1) and "player" or "mob"
    end
    -- #region agent log
    U.AgentLog("H1", "Comm.lua:DEATH", "death_dispatch_ok", {
      partCount = #parts,
      cause = tostring(cause or ""),
      sender = U.ShortName(sender),
    })
    -- #endregion
    GR:SendMessage("DEATH_UPDATE", sender, {
      killer = U.SanitizeText(parts[1] or "?", 48),
      isPlayer = tonumber(parts[2]) == 1 or cause == "player",
      zone = U.SanitizeText(parts[3] or "", 48),
      mapId = tonumber(parts[4]),
      cause = cause,
      spell = U.SanitizeText(parts[6] or "", 48),
      time = U.Now(),
    })
  elseif tag == "WANTED" then
    local parts = U.Split(rest, "|")
    local action = (parts[1] or ""):lower()
    if action ~= "add" and action ~= "clear" then return end
    local killer = U.SanitizeText(parts[2] or "", 48)
    if action == "clear" and (killer == "*" or killer == "") then return end
    local victim = U.SanitizeText(parts[3] or sender, 48)
    if action == "add" then
      if killer == "" then return end
      if string.lower(U.ShortName(victim)) ~= string.lower(U.ShortName(sender)) then return end
    end
    GR:SendMessage("WANTED_UPDATE", sender, {
      action = action,
      killer = killer,
      victim = victim,
      zone = U.SanitizeText(parts[4] or "", 48),
    })
  elseif tag == "LVL" then
    local level = tonumber(rest)
    -- #region agent log
    U.AgentLog("H1", "Comm.lua:LVL", "lvl_parse", {
      rest = tostring(rest or ""),
      level = level or -1,
      ok = (level and level >= 1 and level <= 80) and true or false,
      sender = U.ShortName(sender),
    })
    -- #endregion
    if level and level >= 1 and level <= 80 then
      GR:SendMessage("LVL_UPDATE", sender, level)
    end
  elseif tag == "SIGHT" then
    local parts = U.SplitKeepEmpty(rest, "|")
    local target = U.NormalizeName(U.SanitizeText(parts[1] or "", 48))
    local zone = U.SanitizeText(parts[2] or "", 48)
    local ts = tonumber(parts[3]) or 0
    if not target or target == "" then return end
    if ts < 0 then return end
    GR:SendMessage("SIGHT_UPDATE", sender, {
      target = target,
      zone = zone,
      ts = ts,
      fromRemote = true,
    })
  elseif tag == "MAIN" then
    local parts = U.SplitKeepEmpty(rest, "|")
    local action = (parts[1] or ""):lower()
    if action ~= "set" and action ~= "clear" then return end
    local mainName = ""
    local ver, ts
    if action == "set" then
      mainName = U.NormalizeName(U.SanitizeText(parts[2] or "", 48))
      ver = tonumber(parts[3]) or 0
      ts = tonumber(parts[4]) or 0
      if not mainName or mainName == "" then return end
    else
      ver = tonumber(parts[2]) or 0
      ts = tonumber(parts[3]) or 0
    end
    if ver < 1 then return end
    GR:SendMessage("MAIN_UPDATE", sender, {
      action = action,
      char = sender,
      main = mainName,
      ver = ver,
      ts = ts,
    })
  elseif tag == "CRAFT" then
    local parts = U.SplitKeepEmpty(rest, "|")
    local action = (parts[1] or ""):lower()
    if not VALID_CRAFT_ACTION[action] then return end
    local id = U.SanitizeText(parts[2] or "", 64)
    local ver = tonumber(parts[3]) or 0
    if id == "" or ver < 1 then return end
    local data = {
      action = action,
      id = id,
      ver = ver,
      ts = tonumber(parts[4]) or 0,
      owner = U.NormalizeName(U.SanitizeText(parts[5] or "", 48)),
      itemId = tonumber(parts[6]) or 0,
      itemName = U.SanitizeText(parts[7] or "", 64),
      itemLinkEsc = tostring(parts[8] or ""),
      qty = tonumber(parts[9]) or 1,
      mats = tonumber(parts[10]) == 1,
      note = U.SanitizeText(parts[11] or "", 80),
      status = U.SanitizeText(parts[12] or "open", 16),
      assignee = U.NormalizeName(U.SanitizeText(parts[13] or "", 48)),
      claimant = U.NormalizeName(U.SanitizeText(parts[14] or "", 48)),
    }
    if data.qty < 1 then data.qty = 1 end
    if data.qty > 999 then data.qty = 999 end
    local st = data.status
    if st ~= "open" and st ~= "taken" and st ~= "done" and st ~= "cancelled" then
      data.status = "open"
    end
    GR:SendMessage("CRAFT_UPDATE", sender, data)
  elseif tag == "SYNCREQ" then
    local kind = (rest or ""):lower()
    kind = U.SanitizeText(kind, 16)
    if kind == "main" or kind == "craft" or kind == "wanted" then
      GR:SendMessage("SYNCREQ_UPDATE", sender, kind)
    end
  end
  -- Unknown tags ignored for older/newer mixed clients
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
      local assembled = table.concat(full)
      HandleMessage(assembled, sender)
    end
    return
  end

  DispatchParsed(tag, rest or "", sender)
end

function Comm:OnAddonMessage(prefix, message, channel, sender)
  if prefix ~= GR.PREFIX and prefix ~= GR.PREFIX_NEW then return end
  if channel ~= "GUILD" then return end
  if type(message) ~= "string" or message == "" or #message > MAX_RECV then return end

  sender = U.NormalizeName(sender)
  if U.IsSelfName(sender) then return end
  if not AllowSender(sender) then return end

  HandleMessage(message, sender)
end
