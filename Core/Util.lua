local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Util = GR.Util or {}
local U = GR.Util

function U.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffAngryMurlocs|r: " .. tostring(msg))
  end
end

function U.L(key)
  local locale = AngryMurlocsLocale
  return (locale and locale[key]) or key
end

function U.PlayerName()
  local name, realm = UnitFullName("player")
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name or UnitName("player") or "?"
end

function U.NormalizeName(name)
  if not name or name == "" then return name end
  if not name:find("-", 1, true) then
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName and GetRealmName())
    if realm then
      return name .. "-" .. tostring(realm):gsub("%s", "")
    end
  end
  return name
end

function U.ShortName(full)
  if not full then return "?" end
  return full:match("^([^-]+)") or full
end

local function FoldNameKey(name)
  if not name then return nil end
  local s = U.ShortName(name)
  s = string.lower(s)
  s = s:gsub("[%s']", "")
  return s
end

-- Robust self check (Forever sender/realm formats vary).
function U.IsSelfName(name)
  if not name or name == "" then return false end
  local me = U.NormalizeName(U.PlayerName())
  if me and name == me then return true end
  local key = FoldNameKey(name)
  if not key then return false end
  if me and FoldNameKey(me) == key then return true end
  local unit = UnitName("player")
  if unit and FoldNameKey(unit) == key then return true end
  if me and string.lower(name) == string.lower(me) then return true end
  return false
end

function U.PlayerClassFile()
  local _, classFile = UnitClass("player")
  return classFile or "PRIEST"
end

function U.ClassColor(classFile)
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then
    return c.r, c.g, c.b
  end
  return 0.8, 0.8, 0.8
end

function U.Now()
  return GetTime()
end

function U.Round(n, places)
  local m = 10 ^ (places or 0)
  return math.floor(n * m + 0.5) / m
end

function U.Split(str, sep)
  local t = {}
  if not str or str == "" then return t end
  for part in string.gmatch(str, "([^" .. (sep or "|") .. "]+)") do
    t[#t + 1] = part
  end
  return t
end

function U.SanitizeText(s, maxLen)
  s = tostring(s or ""):gsub("|", ""):gsub("[%c]", "")
  if maxLen and #s > maxLen then
    s = s:sub(1, maxLen)
  end
  return s
end

-- Forever may block some RegisterEvent calls (ADDON_ACTION_FORBIDDEN).
function U.SafeRegisterEvent(frame, event)
  local ok = pcall(function()
    frame:RegisterEvent(event)
  end)
  return ok
end

-- Saved layout: point = { point, relativeToName, relativePoint, x, y }
function U.CapturePoint(frame)
  local p, _, rp, x, y = frame:GetPoint(1)
  return { p or "CENTER", "UIParent", rp or "CENTER", x or 0, y or 0 }
end

function U.ApplyPoint(frame, pt, defaultFn)
  frame:ClearAllPoints()
  if type(pt) == "table" and pt[1] then
    frame:SetPoint(pt[1], UIParent, pt[3] or pt[1], pt[4] or 0, pt[5] or 0)
  elseif defaultFn then
    defaultFn(frame)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- opts: getPoint(), setPoint(pt), isLocked(), defaultFn(), hintFontString (optional)
function U.MakeMovable(frame, opts)
  opts = opts or {}
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if opts.isLocked and opts.isLocked() then return end
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if opts.setPoint then
      opts.setPoint(U.CapturePoint(self))
    end
  end)
  if opts.getPoint then
    U.ApplyPoint(frame, opts.getPoint(), opts.defaultFn)
  elseif opts.defaultFn then
    opts.defaultFn(frame)
  end
end

function U.Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end
