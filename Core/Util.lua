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

-- Strip spaces/hyphens/apostrophes for Forever name-format compares.
local function CompactName(s)
  if not s or s == "" then return nil end
  return string.lower(tostring(s)):gsub("[%s%-%']", "")
end

-- Robust self check (Forever sender/realm formats vary).
-- Handles Ingoo-Endstation (local) vs Ingoo Endstation-Realm (wire).
function U.IsSelfName(name)
  if not name or name == "" then return false end
  local meRaw = U.PlayerName()
  local me = U.NormalizeName(meRaw)
  if me and name == me then return true end
  if me and string.lower(name) == string.lower(me) then return true end

  local meShort = FoldNameKey(me)
  local themShort = FoldNameKey(name)
  if meShort and themShort and meShort == themShort then return true end

  local unit = UnitName("player")
  if unit and FoldNameKey(unit) == themShort then return true end

  local meFullC = CompactName(me)
  local meShortC = CompactName(U.ShortName(me))
  local themShortC = CompactName(U.ShortName(name))
  local themFullC = CompactName(name)
  if meFullC and themShortC and meFullC == themShortC then return true end
  if meShortC and themShortC and meShortC == themShortC then return true end
  if meFullC and themFullC and meFullC == themFullC then return true end
  -- themShort is local-name+false-realm mashed (ingooendstation) matching meFullC
  if meShortC and themShortC and themShortC:sub(1, #meShortC) == meShortC and meFullC == themShortC then
    return true
  end
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

function U.WallTime()
  return (time and time()) or 0
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

-- Keep empty fields (unlike U.Split).
function U.SplitKeepEmpty(str, sep)
  local t = {}
  if str == nil then return t end
  sep = sep or "|"
  str = tostring(str)
  local start = 1
  while true do
    local i = str:find(sep, start, true)
    if not i then
      t[#t + 1] = str:sub(start)
      break
    end
    t[#t + 1] = str:sub(start, i - 1)
    start = i + #sep
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

-- Escape pipe as literal \124 so item links survive TAG|field protocol.
function U.EscapeField(s, maxLen)
  s = tostring(s or ""):gsub("[%c]", "")
  s = s:gsub("|", "\\124")
  if maxLen and #s > maxLen then
    s = s:sub(1, maxLen)
  end
  return s
end

function U.UnescapeField(s)
  return tostring(s or ""):gsub("\\124", "|")
end

function U.RealmKey()
  local realm = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName and GetRealmName()) or "Unknown"
  return tostring(realm):gsub("%s", "")
end

function U.GuildScopeKey()
  local guild = GetGuildInfo and GetGuildInfo("player")
  if not guild or guild == "" then
    return nil
  end
  return U.RealmKey() .. "::" .. tostring(guild)
end

function U.EnsureScopeTable(scope)
  scope.wanted = scope.wanted or {}
  return scope
end

local function MergeWantedEntry(dst, src)
  if not src then return end
  if not dst then
    return {
      count = src.count or 0,
      lastVictim = src.lastVictim or "",
      lastZone = src.lastZone or "",
      lastTime = src.lastTime or 0,
      lastSeenTime = src.lastSeenTime or 0,
      lastSeenZone = src.lastSeenZone or "",
      lastSeenBy = src.lastSeenBy or "",
    }
  end
  local dc = dst.count or 0
  local sc = src.count or 0
  if sc > dc then dst.count = sc end
  if (src.lastTime or 0) >= (dst.lastTime or 0) then
    if src.lastVictim and src.lastVictim ~= "" then dst.lastVictim = src.lastVictim end
    if src.lastZone and src.lastZone ~= "" then dst.lastZone = src.lastZone end
    dst.lastTime = src.lastTime or dst.lastTime
  end
  if (src.lastSeenTime or 0) >= (dst.lastSeenTime or 0) then
    dst.lastSeenTime = src.lastSeenTime or dst.lastSeenTime
    if src.lastSeenZone and src.lastSeenZone ~= "" then dst.lastSeenZone = src.lastSeenZone end
    if src.lastSeenBy and src.lastSeenBy ~= "" then dst.lastSeenBy = src.lastSeenBy end
  end
  return dst
end

function U.MergeWantedMaps(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return dst end
  for k, v in pairs(src) do
    dst[k] = MergeWantedEntry(dst[k], v)
  end
  return dst
end

-- Move __none__ + orphan guild scopes into current guild wanted (never wipe).
function U.RecoverWantedScopes()
  if not GR.db then return end
  GR.db.scopes = GR.db.scopes or {}
  local guildKey = U.GuildScopeKey()
  if not guildKey then return end
  local scope = GR.db.scopes[guildKey]
  if not scope then
    scope = {}
    GR.db.scopes[guildKey] = scope
  end
  U.EnsureScopeTable(scope)
  local realm = U.RealmKey()
  local noneKey = realm .. "::__none__"
  local noneScope = GR.db.scopes[noneKey]
  if noneScope and noneScope.wanted and next(noneScope.wanted) then
    U.MergeWantedMaps(scope.wanted, noneScope.wanted)
    wipe(noneScope.wanted)
  end
  -- Orphan scopes: same guild name suffix, or any non-empty wanted on realm if current empty
  local guildSuffix = guildKey:match("::(.+)$")
  local currentEmpty = not next(scope.wanted)
  for key, other in pairs(GR.db.scopes) do
    if key ~= guildKey and type(other) == "table" and type(other.wanted) == "table" and next(other.wanted) then
      local sameGuild = guildSuffix and key:find("::" .. guildSuffix, 1, true)
      local sameRealm = key:sub(1, #realm + 2) == (realm .. "::")
      if sameGuild or (currentEmpty and sameRealm) then
        U.MergeWantedMaps(scope.wanted, other.wanted)
      end
    end
  end
end

function U.GetScopeDB()
  if not GR.db then return nil end
  GR.db.scopes = GR.db.scopes or {}
  local key = U.GuildScopeKey()
  if not key then
    -- Offline / no guild: ephemeral bucket (not persisted across guild joins meaningfully)
    key = U.RealmKey() .. "::__none__"
  else
    U.RecoverWantedScopes()
  end
  local scope = GR.db.scopes[key]
  if not scope then
    scope = {}
    GR.db.scopes[key] = scope
  end
  return U.EnsureScopeTable(scope)
end

-- Pixel column helpers (proportional fonts break %-Ns padding)
function U.MakeColFS(parent, template, x, w, y, rowH)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x or 0, y or 0)
  fs:SetSize(w or 80, rowH or 20)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("MIDDLE")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
  return fs
end

function U.BuildColHeaders(parent, cols, originX, originY, rowH)
  local headers = {}
  originX = originX or 0
  originY = originY or 0
  for i = 1, #cols do
    local col = cols[i]
    local fs = U.MakeColFS(parent, "GameFontNormal", originX + (col.x or 0), col.w or 80, originY, rowH or 20)
    if col.justify then fs:SetJustifyH(col.justify) end
    if col.key then fs:SetText(U.L(col.key)) end
    headers[i] = fs
  end
  return headers
end

function U.BuildColRow(row, cols, rowH)
  row.cols = row.cols or {}
  for i = 1, #cols do
    local col = cols[i]
    local fs = U.MakeColFS(row, "GameFontHighlightSmall", col.x or 0, col.w or 80, 0, rowH or 20)
    if col.justify then fs:SetJustifyH(col.justify) end
    row.cols[i] = fs
  end
  return row.cols
end

function U.SetColTexts(rowCols, values, r, g, b)
  if not rowCols then return end
  for i = 1, #rowCols do
    local fs = rowCols[i]
    if fs then
      fs:SetText(values and values[i] or "")
      if r then fs:SetTextColor(r, g or r, b or r) end
    end
  end
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
