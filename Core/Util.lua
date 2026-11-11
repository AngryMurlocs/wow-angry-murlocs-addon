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
  if locale and locale[key] ~= nil then return locale[key] end
  local en = AngryMurlocsLocaleEN
  if en and en[key] ~= nil then return en[key] end
  return key
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

-- Forever (Retail rules) can hand out "secret" values that throw on compare,
-- concat or length. Returns nil for a secret, the value otherwise.
function U.Plain(v)
  if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
  return v
end

-- Chat line the player is typing in, if any. Forever moved the old
-- ChatFrame_* helpers to ChatFrameUtil and has no ChatFrameEditBox.
function U.ActiveChatEditBox()
  local util = ChatFrameUtil
  if util and type(util.GetActiveWindow) == "function" then
    local ok, box = pcall(util.GetActiveWindow)
    if ok and box then return box end
    return nil
  end
  return ChatFrameEditBox
end

-- True when the open chat line already has text we must not overwrite.
function U.ChatBusy()
  local box = U.ActiveChatEditBox()
  if not box or type(box.GetText) ~= "function" then return false end
  local ok, text = pcall(box.GetText, box)
  return ok and type(text) == "string" and text:match("%S") ~= nil
end

-- Opens a whisper to `target`, optionally with `text` ready to send.
-- Returns false when the client offers no way to do it.
function U.OpenWhisper(target, text)
  if not target or target == "" then return false end
  local util = ChatFrameUtil
  if text and text ~= "" then
    local withMsg = (util and util.SendTellWithMessage) or ChatFrame_SendTellWithMessage
    if type(withMsg) == "function" and pcall(withMsg, target, text) then return true end
  end
  local tell = (util and util.SendTell) or ChatFrame_SendTell
  if type(tell) == "function" and pcall(tell, target) then
    if text and text ~= "" then
      local box = U.ActiveChatEditBox() or ChatFrameEditBox
      if box and box.SetText then box:SetText(text) end
    end
    return true
  end
  local box = ChatFrameEditBox
  if box and box.SetText then
    if box.Show then box:Show() end
    box:SetText((text and text ~= "") and text or ("/w " .. target .. " "))
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

-- Server clock when available so timestamps from different clients compare.
function U.WallTime()
  if GetServerTime then
    local t = GetServerTime()
    if t and t > 0 then return t end
  end
  return (time and time()) or 0
end

U.MAX_FUTURE_SKEW = 300

-- Remote timestamp guard: nil for missing/negative or more than 5 min in the future.
function U.ClampTs(ts, now)
  ts = tonumber(ts)
  if not ts or ts <= 0 then return nil end
  now = now or U.WallTime()
  if ts > now + U.MAX_FUTURE_SKEW then return nil end
  return ts
end

-- Character identity inside one realm+guild scope. Character names contain no
-- spaces or hyphens, so the first token survives Forever's varying
-- "Name-Realm" / "Name Realm-Realm" sender formats.
function U.CharKey(name)
  if type(name) ~= "string" then return nil end
  local first = name:match("^[^%s%-]+")
  if not first or first == "" then return nil end
  return string.lower(first)
end

function U.SameCharacter(a, b)
  local ka, kb = U.CharKey(a), U.CharKey(b)
  return ka ~= nil and ka == kb
end

-- Highest character level the client allows (Forever may go above 80).
-- Never below 80, so older clients keep their old limit.
function U.MaxLevel()
  local max = 80
  if type(GetMaxPlayerLevel) == "function" then
    local ok, n = pcall(GetMaxPlayerLevel)
    n = ok and tonumber(n) or nil
    if n and n > max and n <= 1000 then max = math.floor(n) end
  end
  return max
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

-- Guild lead / officer for UI gates (UX). Positive hits only (OR):
-- IsGuildLeader, C_GuildInfo.IsGuildOfficer (Forever / Gethe forever @ 9dc84f0d),
-- C_GuildInfo.CanEditOfficerNote / CanEditOfficerNote. Not a security boundary alone.
function U.IsGuildOfficer()
  if not IsInGuild or not IsInGuild() then
    return false
  end
  if IsGuildLeader and IsGuildLeader() then
    return true
  end
  if C_GuildInfo and type(C_GuildInfo.IsGuildOfficer) == "function" then
    if C_GuildInfo.IsGuildOfficer() then
      return true
    end
  end
  if C_GuildInfo and type(C_GuildInfo.CanEditOfficerNote) == "function" then
    if C_GuildInfo.CanEditOfficerNote() then
      return true
    end
  elseif CanEditOfficerNote and CanEditOfficerNote() then
    return true
  end
  return false
end

function U.EnsureScopeTable(scope)
  scope.wanted = scope.wanted or {}
  scope.wantedHidden = scope.wantedHidden or {}
  scope.wantedSelf = scope.wantedSelf or {}
  scope.prof = scope.prof or {}
  scope.prof.cache = scope.prof.cache or {}
  scope.sync = scope.sync or {}
  return scope
end

-- Scope keys that denote the same realm + guild (spacing/case variants only).
local function ScopeKeyFold(key)
  return string.lower(tostring(key or "")):gsub("%s", "")
end

-- Fold __none__ (no-guild period on this realm) and same realm+guild key variants
-- into the current guild scope. Other guilds and other realms are never touched.
function U.RecoverWantedScopes()
  if not GR.db then return end
  if GR.db._recoveredWantedScopes then return end
  GR.db.scopes = GR.db.scopes or {}
  local guildKey = U.GuildScopeKey()
  if not guildKey then return end
  local scope = GR.db.scopes[guildKey]
  if not scope then
    scope = {}
    GR.db.scopes[guildKey] = scope
  end
  U.EnsureScopeTable(scope)
  local logic = GR.WantedLogic
  local noneKey = U.RealmKey() .. "::__none__"
  local guildFold = ScopeKeyFold(guildKey)
  for key, other in pairs(GR.db.scopes) do
    local merge = key ~= guildKey and type(other) == "table"
      and (key == noneKey or ScopeKeyFold(key) == guildFold)
    if merge and type(other.wanted) == "table" and next(other.wanted) and logic then
      for k, v in pairs(other.wanted) do
        if logic.MigrateEntryV2 then logic.MigrateEntryV2(v) end
        scope.wanted[k] = logic.MergeEntryInto(scope.wanted[k], v)
      end
      wipe(other.wanted)
    end
  end
  GR.db._recoveredWantedScopes = true
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

-- SemVer X.Y.Z for addon version nags. Pre-release suffix (-beta…) is stripped.
-- Returns {major, minor, patch} or nil.
function U.ParseAddonVersion(s)
  if type(s) ~= "string" then
    if type(s) == "number" then s = tostring(s) else return nil end
  end
  s = s:match("^%s*(.-)%s*$") or ""
  if s == "" then return nil end
  s = s:match("^([^%-+]+)") or s
  local parts = {}
  for n in s:gmatch("%d+") do
    local v = tonumber(n)
    if not v or v ~= v or v < 0 then return nil end
    parts[#parts + 1] = math.floor(v)
    if #parts >= 3 then break end
  end
  if #parts == 0 then return nil end
  while #parts < 3 do parts[#parts + 1] = 0 end
  return parts
end

-- -1 if a < b, 0 if equal, 1 if a > b, nil if either unparsable.
function U.CompareAddonVersion(a, b)
  local pa, pb = U.ParseAddonVersion(a), U.ParseAddonVersion(b)
  if not pa or not pb then return nil end
  for i = 1, 3 do
    if pa[i] < pb[i] then return -1 end
    if pa[i] > pb[i] then return 1 end
  end
  return 0
end
