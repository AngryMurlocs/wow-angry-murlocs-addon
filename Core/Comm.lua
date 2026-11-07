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
local rateBuckets = {}

local VALID_CLASS = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
  DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
  DRUID = true, DEMONHUNTER = true, EVOKER = true,
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
  return b.n <= RATE_MAX
end

function Comm:Register()
  if registered then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(GR.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(GR.PREFIX_NEW)
    registered = true
  end
end

function Comm:Send(payload)
  if not IsInGuild() then return end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
  if type(payload) ~= "string" or payload == "" then return end
  if #payload > 250 then
    payload = payload:sub(1, 250)
  end
  C_ChatInfo.SendAddonMessage(GR.PREFIX, payload, "GUILD")
end

function Comm:OnAddonMessage(prefix, message, channel, sender)
  if prefix ~= GR.PREFIX and prefix ~= GR.PREFIX_NEW then return end
  if channel ~= "GUILD" then return end
  if type(message) ~= "string" or message == "" or #message > 255 then return end

  sender = U.NormalizeName(sender)
  if U.IsSelfName(sender) then return end
  if not AllowSender(sender) then return end

  local tag, rest = message:match("^([^|]+)|?(.*)$")
  if not tag then return end
  tag = tag:upper()
  if #tag > 12 then return end

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
    GR:SendMessage("PROF_UPDATE", sender, U.SanitizeText(rest, 200))
  elseif tag == "PROFREQ" then
    GR:SendMessage("PROF_REQUEST", sender)
  elseif tag == "DEATH" then
    local parts = U.Split(rest, "|")
    local cause = parts[5]
    if cause ~= "player" and cause ~= "mob" and cause ~= "env" then
      cause = (tonumber(parts[2]) == 1) and "player" or "mob"
    end
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
    -- Remote wipe-all is an abuse vector — ignore clear|*
    if action == "clear" and (killer == "*" or killer == "") then return end
    local victim = U.SanitizeText(parts[3] or sender, 48)
    if action == "add" then
      if killer == "" then return end
      -- Only the victim may report themselves
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
    if level and level >= 1 and level <= 80 then
      GR:SendMessage("LVL_UPDATE", sender, level)
    end
  end
end
