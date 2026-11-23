local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Util = GR.Util or {}
local U = GR.Util

function U.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffAngryMurlocs|r: " .. tostring(msg))
  end
end

-- Player-facing status: Options → Log → Status only (no chat, no network).
function U.Status(msg)
  local log = AngryMurlocs and AngryMurlocs.ActivityLog
  if log and log.Add then
    return log:Add(msg)
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

-- Strip spaces; reject nil / empty / whitespace-only (Forever can return "").
local function CleanRealm(raw)
  if type(raw) ~= "string" then return nil end
  local s = raw:gsub("%s", "")
  if s == "" then return nil end
  return s
end

function U.NormalizeName(name)
  if not name or name == "" then return name end
  if not name:find("-", 1, true) then
    local realm = CleanRealm(GetNormalizedRealmName and GetNormalizedRealmName())
      or CleanRealm(GetRealmName and GetRealmName())
    if realm then
      return name .. "-" .. realm
    end
  end
  return name
end

function U.ShortName(full)
  if not full then return "?" end
  return full:match("^([^-]+)") or full
end

-- Toast/UI display only. Keeps Forever first-last (First-Last). Strips a trailing
-- -Realm only when that suffix matches the live realm key — never by shape alone.
function U.DisplayCharName(full)
  if not full or full == "" then return "?" end
  local name, suffix = full:match("^(.-)%-([^%-]+)$")
  if not name or name == "" or not suffix then return full end
  local known = U.RealmKey()
  if not known then return full end
  if CleanRealm(suffix) == known then
    return name
  end
  return full
end

local function FoldNameKey(name)
  if not name then return nil end
  local s = U.ShortName(name)
  s = string.lower(s)
  s = s:gsub("[%s']", "")
  return s
end

-- Strip spaces/hyphens/apostrophes (display helpers / legacy compares only).
-- Not used for CharIdentity: Lina-Roth and Linar-Oth both mash to linaroth.
local function CompactName(s)
  if not s or s == "" then return nil end
  return string.lower(tostring(s)):gsub("[%s%-%']", "")
end

--- Historical realm suffix from VERIFIED_SCOPE_IMPORTS for the *live* club only.
--- Nil when GuildScopeKey is missing, not a club, or club id is not in the map.
--- scopeImported alone never activates this (guild switch / pending club).
function U.VerifiedLegacyRealmSuffix()
  local scopeKey = U.GuildScopeKey and U.GuildScopeKey()
  if not scopeKey or not U.IsClubScopeKey(scopeKey) then return nil end
  local clubId = U.ClubIdFromScopeKey(scopeKey)
  if not clubId then return nil end
  local map = U.VERIFIED_SCOPE_IMPORTS or {}
  for legacyKey, expectedClub in pairs(map) do
    if expectedClub == clubId and type(legacyKey) == "string" then
      local realm = legacyKey:match("^([^:]+)::")
      realm = CleanRealm(realm)
      if realm then return realm end
    end
  end
  return nil
end

-- Drop a proven realm suffix (live RealmKey, club-gated legacy, or wire
-- "First Last-Token" when RealmKey is empty). Bare Forever First-Last kept.
local function StripProvenRealmSuffix(full)
  if not full or full == "" then return full end
  local left, suffix = tostring(full):match("^(.-)%-([^%-]+)$")
  if not left or left == "" or not suffix then return full end
  local clean = CleanRealm(suffix)
  if not clean then return full end
  local cleanL = string.lower(clean)
  local live = U.RealmKey and U.RealmKey()
  if live and cleanL == string.lower(live) then return left end
  local legacy = U.VerifiedLegacyRealmSuffix and U.VerifiedLegacyRealmSuffix()
  if legacy and cleanL == string.lower(legacy) then return left end
  if not live and left:find("%s") then return left end
  return full
end

-- Token identity: lower tokens joined with "|". Preserves name boundaries
-- (Lina-Roth ≠ Linar-Oth; Ingoo-Endstation == Ingoo Endstation after strip).
local function TokenIdentity(name)
  if not name or name == "" then return nil end
  local base = StripProvenRealmSuffix(name)
  local parts = {}
  for tok in tostring(base):gmatch("[^%s%-']+") do
    if tok ~= "" then parts[#parts + 1] = string.lower(tok) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "|")
end

-- Stable owner / character fold. Boundary-safe (not CompactName mash).
function U.CharIdentity(name)
  if not name or name == "" then return nil end
  return TokenIdentity(name)
end

-- Robust self check (Forever sender/realm formats vary).
-- Full CharIdentity only — first-token fold would treat Mani-Stein as Mani-Mond.
function U.IsSelfName(name)
  if not name or name == "" then return false end
  local meRaw = U.PlayerName()
  local me = U.NormalizeName(meRaw)
  if me and name == me then return true end
  if me and string.lower(name) == string.lower(me) then return true end
  local meId = U.CharIdentity(me)
  local themId = U.CharIdentity(name)
  if meId and themId and meId == themId then return true end
  local unit = UnitName("player")
  if unit then
    local unitId = U.CharIdentity(unit)
    if unitId and themId and unitId == themId then return true end
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

-- Character identity key inside one guild scope (boundary-safe CharIdentity).
function U.CharKey(name)
  return U.CharIdentity(name)
end

function U.SameCharacter(a, b)
  local ka, kb = U.CharKey(a), U.CharKey(b)
  return ka ~= nil and ka == kb
end

-- Prefer a stable map key when folding aliases (no legacy/live realm suffix).
local function PreferCharMapKey(a, b)
  local legacy = U.VerifiedLegacyRealmSuffix()
  local live = U.RealmKey()
  local function score(k)
    local s = 0
    if legacy and k:find("-" .. legacy, 1, true) then s = s - 100 end
    if live and k:find("-" .. live, 1, true) then s = s - 50 end
    s = s - #k
    return s
  end
  if score(a) >= score(b) then return a end
  return b
end

--- Resolve name to an existing key in map with the same CharIdentity, else name.
function U.ResolveKeyedName(map, name)
  if type(name) ~= "string" or name == "" then return name end
  if type(map) == "table" and map[name] ~= nil then return name end
  local id = U.CharIdentity(name)
  if not id or type(map) ~= "table" then return name end
  for k, v in pairs(map) do
    if type(k) == "string" and v ~= nil and U.CharIdentity(k) == id then
      return k
    end
  end
  return name
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

-- Truncate to maxBytes on a UTF-8 character boundary (never mid-codepoint).
function U.Utf8Truncate(s, maxBytes)
  s = tostring(s or "")
  if not maxBytes or #s <= maxBytes then return s end
  local i, last = 1, 0
  while i <= #s do
    local c = s:byte(i)
    if not c then break end
    local len = 1
    if c >= 0xF0 then
      len = 4
    elseif c >= 0xE0 then
      len = 3
    elseif c >= 0xC0 then
      len = 2
    end
    if i + len - 1 > #s then break end
    if last + len > maxBytes then break end
    last = last + len
    i = i + len
  end
  return s:sub(1, last)
end

-- Death wire fields only: same strip as SanitizeText, UTF-8-safe length.
-- Killer/pet may use 64; older peers still clip those at 48 bytes.
function U.SanitizeDeathField(s, maxLen)
  s = tostring(s or ""):gsub("|", ""):gsub("[%c]", "")
  return U.Utf8Truncate(s, maxLen)
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

--- Normalized realm without spaces, or nil if both client APIs are empty/missing.
function U.RealmKey()
  local realm = CleanRealm(GetNormalizedRealmName and GetNormalizedRealmName())
  if realm then return realm end
  return CleanRealm(GetRealmName and GetRealmName())
end

function U.ClubApiPresent()
  return C_Club ~= nil and type(C_Club.GetGuildClubId) == "function"
end

--- Stable guild club id as string, or nil if missing / not ready.
function U.GuildId()
  if not U.ClubApiPresent() then return nil end
  local id = C_Club.GetGuildClubId()
  if id == nil or id == false then return nil end
  if id == 0 or id == "0" then return nil end
  local s = tostring(id)
  if s == "" then return nil end
  return s
end

function U.PlayerGuildName()
  local guild = GetGuildInfo and GetGuildInfo("player")
  if not guild or guild == "" then return nil end
  return tostring(guild)
end

function U.IsClubScopeKey(key)
  return type(key) == "string" and string.sub(key, 1, 5) == "club:"
end

function U.ClubIdFromScopeKey(key)
  if not U.IsClubScopeKey(key) then return nil end
  return string.sub(key, 6)
end

--- Active guild SV key: club:<id> when club API yields an id; else realm::guild
--- when no club API. Requires live membership — stale GetGuildClubId after leave
--- does not keep a key. While club API exists but id is not ready, returns nil
--- (do not open Realm::Guild as a temporary bucket).
function U.GuildScopeKey()
  if IsInGuild and not IsInGuild() then
    return nil
  end
  local guild = U.PlayerGuildName()
  if not guild then return nil end
  local id = U.GuildId()
  if id then
    return "club:" .. id
  end
  if U.ClubApiPresent() then
    return nil
  end
  local realm = U.RealmKey()
  if not realm then return nil end
  return realm .. "::" .. guild
end

function U.RefreshGuildDisplayName(scope)
  if type(scope) ~= "table" then return end
  local name = U.PlayerGuildName()
  if name then
    scope.guildDisplayName = name
  end
  local id = U.GuildId()
  if id and GR.db then
    GR.db.clubNames = GR.db.clubNames or {}
    if name then
      GR.db.clubNames[id] = name
    end
  end
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

local function DeepCopyValue(src)
  if type(src) ~= "table" then return src end
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = DeepCopyValue(v)
  end
  return dst
end

local function FoldCatalogVer(dstBag, srcBag)
  if type(srcBag) ~= "table" then return end
  for owner, bag in pairs(srcBag) do
    if type(owner) == "string" and type(bag) == "table" then
      dstBag[owner] = dstBag[owner] or {}
      for pk, ver in pairs(bag) do
        if type(pk) == "string" and type(ver) == "table" then
          local cur = dstBag[owner][pk]
          local ce, cr = tonumber(cur and cur.epoch) or 0, tonumber(cur and cur.rev) or 0
          local ve, vr = tonumber(ver.epoch) or 0, tonumber(ver.rev) or 0
          if ve > ce or (ve == ce and vr > cr) then
            dstBag[owner][pk] = { epoch = ve, rev = vr }
          end
        end
      end
    end
  end
end

function U.EnsureScopeTable(scope)
  scope.wanted = scope.wanted or {}
  scope.wantedHidden = scope.wantedHidden or {}
  scope.wantedSelf = scope.wantedSelf or {}
  scope.prof = scope.prof or {}
  scope.prof.cache = scope.prof.cache or {}
  -- Additive recipe-sync bag (relay progress + elevated catalog versions).
  -- Idempotent; never wipes existing cache / catalog data.
  local rs = scope.prof.recipeSync
  if type(rs) ~= "table" then
    rs = {}
    scope.prof.recipeSync = rs
  end
  rs.profiles = type(rs.profiles) == "table" and rs.profiles or {}
  rs.ownProfileRev = type(rs.ownProfileRev) == "table" and rs.ownProfileRev or {}
  rs.inventoryRev = tonumber(rs.inventoryRev) or 0
  rs.progress = type(rs.progress) == "table" and rs.progress or {}
  rs.catalogVersions = type(rs.catalogVersions) == "table" and rs.catalogVersions or {}
  -- Fold any earlier catalogEpoch bag into recipeSync.catalogVersions (never lower).
  local legacy = scope.prof.catalogEpoch
  if type(legacy) == "table" then
    FoldCatalogVer(rs.catalogVersions, legacy)
    scope.prof.catalogEpoch = nil
  end
  scope.sync = scope.sync or {}
  return scope
end

-- Scope keys that denote the same realm + guild (spacing/case variants only).
local function ScopeKeyFold(key)
  return string.lower(tostring(key or "")):gsub("%s", "")
end

local function FoldGuildName(name)
  return string.lower(tostring(name or "")):gsub("%s", "")
end

local function GuildNameFromRealmScopeKey(key)
  if type(key) ~= "string" or U.IsClubScopeKey(key) then return nil end
  return key:match("::(.+)$")
end

-- Fold __none__ (no-guild period on this realm) and same realm+guild key variants
-- into the current guild scope. Other guilds and other realms are never touched.
-- Club scopes do not auto-fold realm orphans (those need explicit import).
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
  U.RefreshGuildDisplayName(scope)
  if U.IsClubScopeKey(guildKey) then
    GR.db._recoveredWantedScopes = true
    return
  end
  local realm = U.RealmKey()
  if not realm then return end
  local logic = GR.WantedLogic
  local noneKey = realm .. "::__none__"
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
  if key then
    U.RecoverWantedScopes()
    local scope = GR.db.scopes[key]
    if not scope then
      scope = {}
      GR.db.scopes[key] = scope
    end
    U.EnsureScopeTable(scope)
    U.RefreshGuildDisplayName(scope)
    U.FoldScopeCharacterKeys(scope)
    return scope
  end
  -- In guild but waiting for club id: no Realm::Guild / empty invent.
  if U.PlayerGuildName() and U.ClubApiPresent() then
    return nil
  end
  local realm = U.RealmKey()
  -- No inventing ::Guild / Unknown:: / empty-realm keys while booting.
  if not realm then return nil end
  -- Offline / no guild: ephemeral bucket on this realm only.
  key = realm .. "::__none__"
  local scope = GR.db.scopes[key]
  if not scope then
    scope = {}
    GR.db.scopes[key] = scope
  end
  return U.EnsureScopeTable(scope)
end

--- Exact legacy scope key -> expected club id (string, no "club:" prefix).
--- Client-confirmed: Forever WTF clubNames["215871062"] = "Angry Murlocs"
--- (and scopes["club:215871062"].guildDisplayName). "::Angry Murlocs" omitted until
--- provenance of that empty-realm bucket is separately proven.
U.VERIFIED_SCOPE_IMPORTS = {
  ["CAMWOWEU4Realm6PvP::Angry Murlocs"] = "215871062",
}

--- Name-matched realm/`::` orphans for the current guild. Club keys excluded.
--- Already-imported sources are omitted. Name is display-only, not proof.
--- Prefer ListVerifiedImportSources for auto-import (verified keys only).
function U.ListImportCandidates()
  local dest = U.GuildScopeKey()
  if not dest or not GR.db then return {} end
  local guild = U.PlayerGuildName()
  if not guild then return {} end
  local fold = FoldGuildName(guild)
  local imported = GR.db.scopeImported or {}
  local out = {}
  for key, scope in pairs(GR.db.scopes or {}) do
    if key ~= dest and type(scope) == "table" and not imported[key] and not U.IsClubScopeKey(key) then
      local srcGuild = GuildNameFromRealmScopeKey(key)
      if srcGuild and FoldGuildName(srcGuild) == fold then
        out[#out + 1] = key
      end
    end
  end
  table.sort(out)
  return out
end

--- Sources whose VERIFIED_SCOPE_IMPORTS entry equals expectedClubId.
--- No name matching. Skips missing, already-imported, and club:* keys.
function U.ListVerifiedImportSources(expectedClubId)
  if type(expectedClubId) ~= "string" or expectedClubId == "" or not GR.db then
    return {}
  end
  local map = U.VERIFIED_SCOPE_IMPORTS or {}
  local imported = GR.db.scopeImported or {}
  local scopes = GR.db.scopes or {}
  local out = {}
  for srcKey, wantId in pairs(map) do
    if wantId == expectedClubId
      and type(srcKey) == "string"
      and not U.IsClubScopeKey(srcKey)
      and not imported[srcKey]
      and type(scopes[srcKey]) == "table" then
      out[#out + 1] = srcKey
    end
  end
  table.sort(out)
  return out
end

--- Import verified orphans into dest. dest must be club:<id>; id comes only from
--- ClubIdFromScopeKey(dest) — never from live GuildId() (stale API / nil dest).
--- Returns true when at least one source imported successfully.
function U.RunVerifiedScopeImport(dest)
  local id = U.ClubIdFromScopeKey(dest)
  if not id then return false end
  local sources = U.ListVerifiedImportSources(id)
  if #sources == 0 then return false end
  return U.ImportScopes(sources, dest) == true
end

function U.CountScopeWanted(scope)
  local n = 0
  if type(scope) == "table" and type(scope.wanted) == "table" then
    for _ in pairs(scope.wanted) do n = n + 1 end
  end
  return n
end

function U.CountScopeProf(scope)
  local n = 0
  local cache = scope and scope.prof and scope.prof.cache
  if type(cache) == "table" then
    for _ in pairs(cache) do n = n + 1 end
  end
  return n
end

-- wantedHidden values are { level, t }. Never store bare true (IsHidden reads h.level).
local function MergeHiddenBag(dst, src)
  if type(src) ~= "table" then return end
  for k, h in pairs(src) do
    if type(h) == "table" then
      local level = tonumber(h.level)
      if level then
        local t = tonumber(h.t) or 0
        local cur = dst[k]
        if type(cur) ~= "table" then
          dst[k] = { level = level, t = t }
        else
          local cl = tonumber(cur.level) or 0
          local ct = tonumber(cur.t) or 0
          if level > cl or (level == cl and t > ct) then
            dst[k] = { level = level, t = t }
          end
        end
      end
    end
  end
end

local function MergeWantedSelfBag(dst, src)
  if type(src) ~= "table" then return end
  for charKey, bag in pairs(src) do
    if type(charKey) == "string" and type(bag) == "table" then
      local cur = dst[charKey]
      if type(cur) ~= "table" then
        cur = { seq = 0, kills = {} }
        dst[charKey] = cur
      end
      cur.kills = type(cur.kills) == "table" and cur.kills or {}
      local sseq = tonumber(bag.seq) or 0
      if sseq > (tonumber(cur.seq) or 0) then
        cur.seq = sseq
      end
      if type(bag.kills) == "table" then
        for kk, rec in pairs(bag.kills) do
          if type(rec) == "table" then
            local sn = tonumber(rec.n) or 0
            local st = tonumber(rec.t) or 0
            local mine = cur.kills[kk]
            if type(mine) ~= "table" then
              cur.kills[kk] = { n = sn, t = st }
            else
              local mn = tonumber(mine.n) or 0
              local mt = tonumber(mine.t) or 0
              cur.kills[kk] = { n = math.max(mn, sn), t = math.max(mt, st) }
            end
          end
        end
      end
    end
  end
end

-- Fold killer keys inside one wantedSelf bag (keys are opponents).
local function FoldSelfKillKeys(kills)
  if type(kills) ~= "table" then return end
  local groups = {}
  for kk, rec in pairs(kills) do
    if type(kk) == "string" and type(rec) == "table" then
      local id = U.CharIdentity(kk) or ("\0" .. string.lower(kk))
      local g = groups[id]
      if not g then
        groups[id] = { key = kk, rec = rec }
      else
        local sn = tonumber(rec.n) or 0
        local st = tonumber(rec.t) or 0
        local mn = tonumber(g.rec.n) or 0
        local mt = tonumber(g.rec.t) or 0
        g.rec = { n = math.max(mn, sn), t = math.max(mt, st) }
        g.key = PreferCharMapKey(g.key, kk)
      end
    end
  end
  wipe(kills)
  for _, g in pairs(groups) do
    kills[string.lower(g.key)] = g.rec
  end
end

local function MergeOneHidden(a, b)
  if type(a) ~= "table" then return b end
  if type(b) ~= "table" then return a end
  local al, at = tonumber(a.level) or 0, tonumber(a.t) or 0
  local bl, bt = tonumber(b.level) or 0, tonumber(b.t) or 0
  if bl > al or (bl == al and bt > at) then
    return { level = bl, t = bt }
  end
  return { level = al, t = at }
end

local function MergeOneSelfBag(a, b)
  local hold = { bag = { seq = 0, kills = {} } }
  if type(a) == "table" then MergeWantedSelfBag(hold, { bag = a }) end
  if type(b) == "table" then MergeWantedSelfBag(hold, { bag = b }) end
  FoldSelfKillKeys(hold.bag.kills)
  return hold.bag
end

--- Merge wanted / wantedHidden / wantedSelf keys that share CharIdentity.
--- wanted → MergeEntryInto; hidden → level/t max; self → MergeWantedSelfBag.
--- Idempotent. Killer keys inside wantedSelf bags also fold by identity.
function U.FoldScopeCharacterKeys(scope)
  if type(scope) ~= "table" then return end
  local logic = GR.WantedLogic
  if type(scope.wanted) == "table" and logic and logic.MergeEntryInto then
    local groups = {}
    for k, v in pairs(scope.wanted) do
      if type(k) == "string" and type(v) == "table" then
        if logic.MigrateEntryV2 then logic.MigrateEntryV2(v) end
        local id = U.CharIdentity(k) or ("\0" .. string.lower(k))
        local g = groups[id]
        if not g then
          groups[id] = { key = k, entry = v }
        else
          g.entry = logic.MergeEntryInto(g.entry, v)
          g.key = PreferCharMapKey(g.key, k)
        end
      end
    end
    wipe(scope.wanted)
    for _, g in pairs(groups) do
      scope.wanted[g.key] = g.entry
    end
  end
  if type(scope.wantedHidden) == "table" then
    local groups = {}
    for k, h in pairs(scope.wantedHidden) do
      if type(k) == "string" and type(h) == "table" then
        local id = U.CharIdentity(k) or ("\0" .. string.lower(k))
        local g = groups[id]
        if not g then
          groups[id] = { key = k, h = h }
        else
          g.h = MergeOneHidden(g.h, h)
          g.key = PreferCharMapKey(g.key, k)
        end
      end
    end
    wipe(scope.wantedHidden)
    for _, g in pairs(groups) do
      scope.wantedHidden[g.key] = g.h
    end
  end
  if type(scope.wantedSelf) == "table" then
    local groups = {}
    for k, bag in pairs(scope.wantedSelf) do
      if type(k) == "string" and type(bag) == "table" then
        FoldSelfKillKeys(bag.kills)
        -- Bag keys are CharIdentity strings (or legacy first-token); group by id.
        local id = k
        if not string.find(k, "|", 1, true) then
          id = U.CharIdentity(k) or k
        end
        local g = groups[id]
        if not g then
          groups[id] = { key = id, bag = DeepCopyValue(bag) }
          FoldSelfKillKeys(groups[id].bag.kills)
        else
          g.bag = MergeOneSelfBag(g.bag, bag)
        end
      end
    end
    wipe(scope.wantedSelf)
    for id, g in pairs(groups) do
      FoldSelfKillKeys(g.bag.kills)
      scope.wantedSelf[id] = g.bag
    end
  end
end

local function MergeRecipeMap(dstRecipes, srcRecipes)
  if type(srcRecipes) ~= "table" then return end
  dstRecipes = dstRecipes or {}
  for pk, bag in pairs(srcRecipes) do
    if type(pk) == "string" and type(bag) == "table" then
      local cur = dstRecipes[pk]
      local ce, cr = tonumber(cur and cur.epoch) or 0, tonumber(cur and cur.rev) or 0
      local ve, vr = tonumber(bag.epoch) or 0, tonumber(bag.rev) or 0
      if not cur or ve > ce or (ve == ce and vr > cr) then
        dstRecipes[pk] = DeepCopyValue(bag)
      end
    end
  end
  return dstRecipes
end

local function ProfListScore(list)
  if type(list) ~= "table" then return 0, 0 end
  local n, sum = 0, 0
  for i = 1, #list do
    local row = list[i]
    if type(row) == "table" then
      n = n + 1
      sum = sum + (tonumber(row.skill) or 0)
    end
  end
  return n, sum
end

local function FindProfCacheOwner(cache, name)
  if type(cache) ~= "table" or type(name) ~= "string" then return nil end
  if type(cache[name]) == "table" then return name end
  local id = U.CharIdentity(name)
  if not id then return nil end
  for k, entry in pairs(cache) do
    if type(k) == "string" and type(entry) == "table" and U.CharIdentity(k) == id then
      return k
    end
  end
  return nil
end

local function MergeProfCacheBag(dstCache, srcCache)
  if type(srcCache) ~= "table" then return end
  for owner, entry in pairs(srcCache) do
    if type(owner) == "string" and type(entry) == "table" then
      local destKey = FindProfCacheOwner(dstCache, owner) or owner
      local cur = dstCache[destKey]
      if type(cur) ~= "table" then
        dstCache[destKey] = DeepCopyValue(entry)
      else
        local st = tonumber(entry.time) or 0
        local ct = tonumber(cur.time) or 0
        local sn, ss = ProfListScore(entry.list)
        local cn, cs = ProfListScore(cur.list)
        -- Never replace a filled list with an empty newer stub.
        local takeList = (sn > 0) and (
          cn == 0
          or st > ct
          or (st == ct and (sn > cn or (sn == cn and ss > cs)))
        )
        if takeList and entry.list ~= nil then
          cur.list = DeepCopyValue(entry.list)
        end
        if st > ct then
          cur.time = entry.time
        end
        if entry.classFile and not cur.classFile then
          cur.classFile = entry.classFile
        end
        if type(entry.wireAlias) == "table" then
          cur.wireAlias = cur.wireAlias or {}
          for ck, wk in pairs(entry.wireAlias) do
            if type(ck) == "string" and type(wk) == "string" and not cur.wireAlias[ck] then
              cur.wireAlias[ck] = wk
            end
          end
        end
        -- Recipe catalogs: epoch/rev only; never dropped by a newer list timestamp.
        if type(entry.recipes) == "table" then
          cur.recipes = MergeRecipeMap(cur.recipes or {}, entry.recipes)
        end
        if type(cur.list) == "table" and #cur.list > 0 and type(cur.recipes) == "table" then
          local recipesMod = GR:GetModule("ProfRecipes")
          if recipesMod and recipesMod.PruneRecipesToProfessionList then
            cur.recipes = recipesMod.PruneRecipesToProfessionList(cur.recipes, cur.list, destKey)
          end
        end
      end
    end
  end
end

local function MergeRecipeSyncBag(dstScope, srcScope)
  U.EnsureScopeTable(dstScope)
  local srs = srcScope and srcScope.prof and srcScope.prof.recipeSync
  if type(srs) ~= "table" then
    local legacy = srcScope and srcScope.prof and srcScope.prof.catalogEpoch
    if type(legacy) == "table" then
      FoldCatalogVer(dstScope.prof.recipeSync.catalogVersions, legacy)
    end
    return
  end
  local drs = dstScope.prof.recipeSync
  FoldCatalogVer(drs.catalogVersions, srs.catalogVersions)
  if type(srs.profiles) == "table" then
    for k, v in pairs(srs.profiles) do
      if drs.profiles[k] == nil then
        drs.profiles[k] = DeepCopyValue(v)
      end
    end
  end
end

local function MergeScopeInto(dest, src)
  local logic = GR.WantedLogic
  if type(src.wanted) == "table" and logic and logic.MergeEntryInto then
    for k, v in pairs(src.wanted) do
      local copy = DeepCopyValue(v)
      if logic.MigrateEntryV2 then logic.MigrateEntryV2(copy) end
      dest.wanted[k] = logic.MergeEntryInto(dest.wanted[k], copy)
    end
  end
  if type(src.wantedHidden) == "table" then
    MergeHiddenBag(dest.wantedHidden, src.wantedHidden)
  end
  if type(src.wantedSelf) == "table" then
    MergeWantedSelfBag(dest.wantedSelf, src.wantedSelf)
  end
  if type(src.prof) == "table" and type(src.prof.cache) == "table" then
    MergeProfCacheBag(dest.prof.cache, src.prof.cache)
  end
  MergeRecipeSyncBag(dest, src)
end

--- Copy-merge one orphan scope into the current guild scope. Originals untouched.
--- Merges into a deep copy of dest and publishes only after full success.
--- expectedDestKey: if set, abort when live GuildScopeKey differs (guild switched).
--- Returns ok, errCode.
function U.ImportScope(srcKey, expectedDestKey)
  if not GR.db then return false, "no_db" end
  local destKey = U.GuildScopeKey()
  if not destKey then return false, "no_dest" end
  if expectedDestKey and expectedDestKey ~= destKey then
    return false, "dest_changed"
  end
  if type(srcKey) ~= "string" or srcKey == "" or srcKey == destKey then
    return false, "bad_src"
  end
  if U.IsClubScopeKey(srcKey) then
    return false, "other_club"
  end
  GR.db.scopeImported = GR.db.scopeImported or {}
  if GR.db.scopeImported[srcKey] then
    return false, "already"
  end
  local src = GR.db.scopes and GR.db.scopes[srcKey]
  if type(src) ~= "table" then return false, "missing" end

  GR.db.scopes = GR.db.scopes or {}
  local live = GR.db.scopes[destKey]
  local draft = DeepCopyValue(type(live) == "table" and live or {})
  U.EnsureScopeTable(draft)

  if not pcall(MergeScopeInto, draft, src) then
    return false, "merge_failed"
  end
  U.FoldScopeCharacterKeys(draft)
  -- Re-check membership/dest before publish (guild may have changed mid-merge).
  local liveKey = U.GuildScopeKey()
  if not liveKey or liveKey ~= destKey then
    return false, "dest_changed"
  end
  if expectedDestKey and expectedDestKey ~= liveKey then
    return false, "dest_changed"
  end

  GR.db.scopes[destKey] = draft
  GR.db.scopeImported[srcKey] = destKey
  U.RefreshGuildDisplayName(draft)
  return true
end

function U.ImportScopes(srcKeys, expectedDestKey)
  if type(srcKeys) ~= "table" then return false, "bad_src" end
  local any = false
  for i = 1, #srcKeys do
    local ok, err = U.ImportScope(srcKeys[i], expectedDestKey)
    if err == "dest_changed" or err == "merge_failed" then
      return false, err
    end
    if ok then any = true end
  end
  return any, any and nil or "none"
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
