local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Professions = GR:NewModule("Professions")

-- skillLine -> short key for compact payload
-- ASCII-only bare keys (Forever Lua rejects umlaut identifiers; KeyFromSkillName folds ae/oe/ue)
local KEY_BY_NAME = {
  alchemy = "alch",
  alchemie = "alch",
  alchimie = "alch", -- Forever / Classic deDE
  blacksmithing = "bs",
  schmiedekunst = "bs",
  enchanting = "ench",
  verzauberkunst = "ench",
  engineering = "eng",
  ingenieurskunst = "eng",
  herbalism = "herb",
  kraeuterkunde = "herb",
  leatherworking = "lw",
  lederverarbeitung = "lw",
  mining = "mine",
  bergbau = "mine",
  skinning = "skin",
  kuerschnerei = "skin",
  tailoring = "tail",
  schneiderei = "tail",
  cooking = "cook",
  kochkunst = "cook",
  ["first aid"] = "aid",
  ["erste hilfe"] = "aid",
  erstehilfe = "aid",
  firstaid = "aid",
  fishing = "fish",
  angeln = "fish",
  -- TBC+ (optional on Forever)
  jewelcrafting = "jc",
  juwelenschleifen = "jc",
  inscription = "insc",
  inschriftenkunde = "insc",
  archaeology = "arch",
  archaeologie = "arch", -- folded from Archäologie
}

local NAME_BY_KEY = {
  alch = "Alchemy",
  bs = "Blacksmithing",
  ench = "Enchanting",
  eng = "Engineering",
  herb = "Herbalism",
  lw = "Leatherworking",
  mine = "Mining",
  skin = "Skinning",
  tail = "Tailoring",
  cook = "Cooking",
  aid = "First Aid",
  fish = "Fishing",
  jc = "Jewelcrafting",
  insc = "Inscription",
  arch = "Archaeology",
}

local NAME_BY_KEY_DE = {
  alch = "Alchimie", -- match Forever UI
  bs = "Schmiedekunst",
  ench = "Verzauberkunst",
  eng = "Ingenieurskunst",
  herb = "Kraeuterkunde",
  lw = "Lederverarbeitung",
  mine = "Bergbau",
  skin = "Kuerschnerei",
  tail = "Schneiderei",
  cook = "Kochkunst",
  aid = "Erste Hilfe",
  fish = "Angeln",
  jc = "Juwelenschleifen",
  insc = "Inschriftenkunde",
  arch = "Archaeologie",
}

-- Classic/Forever trade-skill icons (Interface\Icons).
local ICON_BY_KEY = {
  alch = "Interface\\Icons\\Trade_Alchemy",
  bs = "Interface\\Icons\\Trade_BlackSmithing",
  ench = "Interface\\Icons\\Trade_Engraving",
  eng = "Interface\\Icons\\Trade_Engineering",
  herb = "Interface\\Icons\\Trade_Herbalism",
  lw = "Interface\\Icons\\Trade_LeatherWorking",
  mine = "Interface\\Icons\\Trade_Mining",
  skin = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  tail = "Interface\\Icons\\Trade_Tailoring",
  cook = "Interface\\Icons\\INV_Misc_Food_15",
  aid = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
  fish = "Interface\\Icons\\Trade_Fishing",
  jc = "Interface\\Icons\\INV_Misc_Gem_01",
  insc = "Interface\\Icons\\INV_Inscription_Tradeskill01",
  arch = "Interface\\Icons\\Trade_Archaeology",
}

local function DisplayName(key)
  if GetLocale() == "deDE" then
    return NAME_BY_KEY_DE[key] or key
  end
  return NAME_BY_KEY[key] or key
end

local function IconPath(key)
  if not key then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  return ICON_BY_KEY[key] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FoldSkillName(name)
  if not name then return nil end
  local s = tostring(name)
  -- strip UI escape sequences
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  s = s:match("^%s*(.-)%s*$") or s
  local lower = s:lower()
  -- byte-safe fold for deDE skill names (ae/oe/ue/ss)
  lower = lower
    :gsub("\195\164", "ae")
    :gsub("\195\182", "oe")
    :gsub("\195\188", "ue")
    :gsub("\195\159", "ss")
  -- NBSP -> space, collapse whitespace
  lower = lower:gsub("\194\160", " "):gsub("%s+", " ")
  return lower
end

local function KeyFromSkillName(name)
  local lower = FoldSkillName(name)
  if not lower then return nil end
  local hit = KEY_BY_NAME[lower]
  if hit then return hit end
  -- also try without spaces (Erstehilfe / FirstAid)
  hit = KEY_BY_NAME[lower:gsub("%s+", "")]
  if hit then return hit end
  -- Forever unknown skill name: still transmit via compact fallback key
  local slug = lower:gsub("%s+", ""):gsub("[^%w]", "")
  if slug == "" then return nil end
  if #slug > 12 then slug = slug:sub(1, 12) end
  return slug
end

local function MergeProf(byKey, key, skill, name)
  if not key or skill == nil then return end
  skill = tonumber(skill) or 0
  local prev = byKey[key]
  if not prev or skill > (prev.skill or 0) then
    byKey[key] = { key = key, skill = skill, name = name or DisplayName(key) }
  end
end

local function CollectLocal()
  local byKey = {}

  if GetProfessions and GetProfessionInfo then
    local prof1, prof2, arch, fish, cook, firstAid = GetProfessions()
    local indices = { prof1, prof2, cook, firstAid, fish }
    for i = 1, #indices do
      local idx = indices[i]
      if idx then
        local name, _, skillLevel = GetProfessionInfo(idx)
        MergeProf(byKey, KeyFromSkillName(name), skillLevel, name)
      end
    end
  end

  -- Fallback / supplement: skill lines (Forever may skip some GetProfessions slots)
  if GetNumSkillLines and GetSkillLineInfo then
    local n = GetNumSkillLines() or 0
    for i = 1, n do
      local name, isHeader, _, skillRank = GetSkillLineInfo(i)
      if name and not isHeader then
        MergeProf(byKey, KeyFromSkillName(name), skillRank, name)
      end
    end
  end

  local list = {}
  for _, entry in pairs(byKey) do
    list[#list + 1] = entry
  end
  table.sort(list, function(a, b)
    return (a.key or "") < (b.key or "")
  end)
  return list
end

local VALID_CLASS = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
  DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
  DRUID = true, DEMONHUNTER = true, EVOKER = true,
}

-- Field separator is '+' (not '|') so payloads survive SanitizeText / tag splits.
-- Decode still accepts legacy '|' from older clients.
-- Optional leading CLASS token: WARRIOR+alch:300+bs:200
local function Encode(list, classFile)
  local parts = {}
  if classFile and VALID_CLASS[classFile] then
    parts[#parts + 1] = classFile
  end
  for i = 1, #list do
    parts[#parts + 1] = list[i].key .. ":" .. tostring(list[i].skill)
  end
  return table.concat(parts, "+")
end

local function Decode(rest)
  local out = {}
  local classFile
  if not rest or rest == "" then return out, classFile end
  -- Normalize legacy pipe payloads to '+'
  rest = tostring(rest):gsub("|", "+")
  for piece in string.gmatch(rest, "([^+]+)") do
    local key, skill = piece:match("^([%w_]+):(%d+)$")
    if key and skill then
      out[#out + 1] = {
        key = key,
        skill = tonumber(skill),
        name = DisplayName(key),
      }
    else
      local cf = string.upper(piece)
      if not classFile and VALID_CLASS[cf] then
        classFile = cf
      end
    end
  end
  return out, classFile
end

-- 0.6.x kept one account-wide cache; move it once into the guild scope that is
-- active at first 0.7 login (it was wiped on every guild change before).
function Professions:MigrateCache()
  local db = GR.db
  if not db or not db.prof or db.prof._movedToScope then return end
  if not U.GuildScopeKey() then return end
  local scope = U.GetScopeDB()
  if not scope then return end
  local old = db.prof.cache
  if type(old) == "table" then
    for name, entry in pairs(old) do
      if not scope.prof.cache[name] then
        if type(entry) == "table" then entry.time = nil end
        scope.prof.cache[name] = entry
      end
    end
    wipe(old)
  end
  db.prof._movedToScope = true
end

local function Cache()
  local scope = U.GetScopeDB()
  return scope and scope.prof.cache or {}
end

function Professions:GetAll()
  if not GR.db then return {} end
  return Cache()
end

-- Drop remote stubs with empty lists (no classFile = not self) so Sync can refill cleanly.
function Professions:ClearEmptyRemoteStubs()
  if not GR.db then return end
  local cache = Cache()
  local me = U.NormalizeName(U.PlayerName())
  for name, entry in pairs(cache) do
    if name ~= me and entry and not entry.classFile then
      local list = entry.list
      if not list or #list == 0 then
        cache[name] = nil
      end
    end
  end
  Professions:PruneSelfDuplicates()
end

-- Forever: local key Ingoo-Endstation vs wire Ingoo Endstation-Realm → one self row.
function Professions:PruneSelfDuplicates()
  if not GR.db then return end
  local cache = Cache()
  local me = U.NormalizeName(U.PlayerName())
  local canon = cache[me]
  local toRemove = {}
  for name, entry in pairs(cache) do
    if name ~= me and U.IsSelfName(name) then
      if (not canon or not canon.list or #canon.list == 0) and entry and entry.list and #entry.list > 0 then
        cache[me] = {
          list = entry.list,
          classFile = entry.classFile or U.PlayerClassFile(),
          time = entry.time or U.WallTime(),
          raw = entry.raw,
        }
        canon = cache[me]
      end
      toRemove[#toRemove + 1] = name
    end
  end
  for i = 1, #toRemove do
    cache[toRemove[i]] = nil
  end
end

local lastProfReqSend = 0
local lastProfReqReply = 0
local lastSentEncoded
local PROFREQ_SEND_CD = 30
local PROFREQ_REPLY_CD = 15

-- force=false only sends when the encoded list changed since the last send.
function Professions:Broadcast(force)
  local db = GR.db
  if not db or not db.privacy.shareProfessions then return end
  if not IsInGuild() then return end
  Professions:MigrateCache()
  Professions:PruneSelfDuplicates()
  local list = CollectLocal()
  local classFile = U.PlayerClassFile()
  local encoded = Encode(list, classFile)
  local me = U.NormalizeName(U.PlayerName())
  local prevSelf = Cache()[me]
  local recipes = prevSelf and prevSelf.recipes
  local recipesMod = GR:GetModule("ProfRecipes")
  if recipesMod and recipesMod.PruneRecipesToProfessionList then
    recipes = recipesMod.PruneRecipesToProfessionList(recipes, list)
  end
  Cache()[me] = {
    list = list,
    classFile = classFile,
    time = U.WallTime(),
    recipes = recipes,
  }
  GR:SendMessage("PROF_CACHE_CHANGED", me)
  if not force and encoded == lastSentEncoded then return end
  if Comm:Send("PROF|" .. encoded, "data", "prof") then
    lastSentEncoded = encoded
  end
end

function Professions:RequestAll()
  if not IsInGuild() then return end
  local now = U.Now()
  if (now - lastProfReqSend) < PROFREQ_SEND_CD then return end
  lastProfReqSend = now
  Comm:Send("PROFREQ", "ctrl", "sync")
end

-- Persist class from map pins onto the professions row (survives POS expire).
function Professions:ApplyClassFile(who, classFile)
  if not who or not classFile or classFile == "" then return false end
  local cache = Cache()
  if not cache then return false end
  local entry = cache[who]
  if not entry then
    local short = string.lower(U.ShortName(who) or "")
    for name, e in pairs(cache) do
      if e and (U.SameCharacter(name, who) or string.lower(U.ShortName(name) or "") == short) then
        entry = e
        break
      end
    end
  end
  if not entry then return false end
  if entry.classFile == classFile then return false end
  entry.classFile = classFile
  return true
end

function Professions:OnEnable()
  if self.enabled then return end
  self.enabled = true

  C_Timer.After(2, function()
    if not Professions.enabled then return end
    Professions:MigrateCache()
    Professions:PruneSelfDuplicates()
  end)

  GR:BindMessage(self, "POS_CACHE_CHANGED", function(_, sender, data)
    local cf = data and data.classFile
    if not cf or not sender then return end
    if Professions:ApplyClassFile(sender, cf) then
      GR:SendMessage("PROF_CACHE_CHANGED", sender)
    end
  end)

  GR:BindMessage(self, "PROF_UPDATE", function(_, sender, rest)
    if U.IsSelfName(sender) then
      Professions:PruneSelfDuplicates()
      return
    end
    local raw = tostring(rest or "")
    if #raw > 200 then raw = raw:sub(1, 200) end
    local list, classFile = Decode(raw)
    local cache = Cache()
    local prev = cache[sender]
    if #list == 0 then
      if raw ~= "" then
        GR.db.prof._decodeMiss = (GR.db.prof._decodeMiss or 0) + 1
      end
      -- Never replace a good cache entry with an empty decode
      if prev and prev.list and #prev.list > 0 then
        prev.raw = raw
        prev.time = U.WallTime()
        if classFile then prev.classFile = classFile end
        GR:SendMessage("PROF_CACHE_CHANGED", sender)
        return
      end
    end
    local recipes = prev and prev.recipes
    local recipesMod = GR:GetModule("ProfRecipes")
    if recipesMod and recipesMod.PruneRecipesToProfessionList then
      recipes = recipesMod.PruneRecipesToProfessionList(recipes, list)
    end
    cache[sender] = {
      list = list,
      raw = raw,
      time = U.WallTime(),
      classFile = classFile or (prev and prev.classFile),
      recipes = recipes,
    }
    GR:SendMessage("PROF_CACHE_CHANGED", sender)
  end)

  -- Spread replies so a login request does not trigger a burst from everyone.
  GR:BindMessage(self, "PROF_REQUEST", function()
    local now = U.Now()
    if (now - lastProfReqReply) < PROFREQ_REPLY_CD then return end
    lastProfReqReply = now
    C_Timer.After(1 + math.random() * 4, function()
      if not Professions.enabled then return end
      Professions:Broadcast(true)
    end)
  end)

  GR:BindMessage(self, "SHARE_PROF_CHANGED", function()
    if GR.db.privacy.shareProfessions then
      Professions:Broadcast(true)
    end
  end)

  GR:BindMessage(self, "GUILD_UPDATE", function()
    Professions:MigrateCache()
    lastSentEncoded = nil
  end)

  local loginBroadcastDone = false
  local f = CreateFrame("Frame")
  self._eventFrame = f
  U.SafeRegisterEvent(f, "SKILL_LINES_CHANGED")
  U.SafeRegisterEvent(f, "PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
      -- Forever: skill lines often ready later than +5s. Later passes only send on change.
      C_Timer.After(5, function()
        if not Professions.enabled then return end
        Professions:Broadcast(not loginBroadcastDone)
        loginBroadcastDone = true
      end)
      C_Timer.After(20, function()
        if not Professions.enabled then return end
        Professions:Broadcast(false)
      end)
      C_Timer.After(45, function()
        if not Professions.enabled then return end
        Professions:Broadcast(false)
      end)
    else
      -- Debounce skill ups
      if Professions._debounce then return end
      Professions._debounce = true
      C_Timer.After(2, function()
        Professions._debounce = false
        if not Professions.enabled then return end
        Professions:Broadcast(false)
      end)
    end
  end)
end

function Professions:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  GR:UnbindMessages(self)
  GR:ReleaseEventFrame(self._eventFrame)
  self._eventFrame = nil
end

local PROF_KEYS_ORDER = {
  "alch", "bs", "ench", "eng", "herb", "lw", "mine", "skin", "tail",
  "cook", "aid", "fish", "jc", "insc", "arch",
}

function Professions.ProfessionKeys()
  return PROF_KEYS_ORDER
end

Professions.DisplayName = DisplayName
Professions.IconPath = IconPath
Professions.KeyFromSkillName = KeyFromSkillName
Professions.Decode = Decode
Professions.Encode = Encode
