local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Professions = GR:NewModule("Professions")

-- Forever/Classic skill-line / base profession IDs (GetProfessionInfo skillLine,
-- GetBaseProfessionInfo.professionID). Alchemy 171 exercised in tests; others are
-- the same Classic lines Forever returns for primary crafts. Not Enum.Profession.
local KEY_BY_ID = {
  [171] = "alch",
  [164] = "bs",
  [333] = "ench",
  [202] = "eng",
  [182] = "herb",
  [165] = "lw",
  [186] = "mine",
  [393] = "skin",
  [197] = "tail",
  [185] = "cook",
  [129] = "aid",
  [356] = "fish",
  [755] = "jc",
  [773] = "insc",
  [794] = "arch",
}

-- Folded lowercase name → short key (EN/DE/FR + Forever variants).
local KEY_BY_NAME = {
  alchemy = "alch",
  alchemie = "alch",
  alchimie = "alch",
  blacksmithing = "bs",
  schmiedekunst = "bs",
  forge = "bs",
  enchanting = "ench",
  verzauberkunst = "ench",
  enchantement = "ench",
  engineering = "eng",
  ingenieurskunst = "eng",
  ingenierie = "eng",
  herbalism = "herb",
  kraeuterkunde = "herb",
  herboristerie = "herb",
  leatherworking = "lw",
  lederverarbeitung = "lw",
  ["travail du cuir"] = "lw",
  travailducuirs = "lw", -- "travail du cuir" with spaces removed
  mining = "mine",
  bergbau = "mine",
  minage = "mine",
  skinning = "skin",
  kuerschnerei = "skin",
  depecage = "skin",
  tailoring = "tail",
  schneiderei = "tail",
  couture = "tail",
  cooking = "cook",
  kochkunst = "cook",
  cuisine = "cook",
  ["first aid"] = "aid",
  ["erste hilfe"] = "aid",
  erstehilfe = "aid",
  firstaid = "aid",
  secourisme = "aid",
  fishing = "fish",
  angeln = "fish",
  peche = "fish",
  jewelcrafting = "jc",
  juwelenschleifen = "jc",
  joaillerie = "jc",
  inscription = "insc",
  inschriftenkunde = "insc",
  calligraphie = "insc",
  archaeology = "arch",
  archaeologie = "arch",
  archeologie = "arch",
}

-- 0.11.14 fallback slugs (accent bytes stripped by [^%w], then 12-char cut).
local LEGACY_SLUG_TO_KEY = {
  couture = "tail",
  forge = "bs",
  enchantement = "ench",
  ingnierie = "eng",
  herboristeri = "herb",
  travailducui = "lw",
  minage = "mine",
  dpeage = "skin",
  pche = "fish",
  archologie = "arch",
  calligraphie = "insc",
  cuisine = "cook",
  secourisme = "aid",
  joaillerie = "jc",
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
  alch = "Alchimie",
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

local NAME_BY_KEY_FR = {
  alch = "Alchimie",
  bs = "Forge",
  ench = "Enchantement",
  eng = "Ingenierie",
  herb = "Herboristerie",
  lw = "Travail du cuir",
  mine = "Minage",
  skin = "Depecage",
  tail = "Couture",
  cook = "Cuisine",
  aid = "Secourisme",
  fish = "Peche",
  jc = "Joaillerie",
  insc = "Calligraphie",
  arch = "Archeologie",
}

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

local PROF_KEYS_ORDER = {
  "alch", "bs", "ench", "eng", "herb", "lw", "mine", "skin", "tail",
  "cook", "aid", "fish", "jc", "insc", "arch",
}

local CANON_KEYS = {}
for i = 1, #PROF_KEYS_ORDER do
  CANON_KEYS[PROF_KEYS_ORDER[i]] = true
end

local function DisplayName(key)
  local loc = GetLocale and GetLocale() or "enUS"
  if loc == "deDE" then
    return NAME_BY_KEY_DE[key] or key
  end
  if loc == "frFR" then
    return NAME_BY_KEY_FR[key] or key
  end
  return NAME_BY_KEY[key] or key
end

local function IconPath(key)
  if not key then return "Interface\\Icons\\INV_Misc_QuestionMark" end
  return ICON_BY_KEY[key] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- deDE umlaut fold only (0.11.14 behavior for fallback slug).
local function FoldSkillNameLegacy(name)
  if not name then return nil end
  local s = tostring(name)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  s = s:match("^%s*(.-)%s*$") or s
  local lower = s:lower()
  lower = lower
    :gsub("\195\164", "ae")
    :gsub("\195\182", "oe")
    :gsub("\195\188", "ue")
    :gsub("\195\159", "ss")
  lower = lower:gsub("\194\160", " "):gsub("%s+", " ")
  return lower
end

-- Lookup fold: legacy + common Latin accents (FR).
local function FoldSkillNameLookup(name)
  local lower = FoldSkillNameLegacy(name)
  if not lower then return nil end
  -- UTF-8 Latin-1 supplements commonly used in FR profession names
  lower = lower
    :gsub("\195\169", "e") -- é
    :gsub("\195\168", "e") -- è
    :gsub("\195\170", "e") -- ê
    :gsub("\195\171", "e") -- ë
    :gsub("\195\160", "a") -- à
    :gsub("\195\162", "a") -- â
    :gsub("\195\174", "i") -- î
    :gsub("\195\175", "i") -- ï
    :gsub("\195\180", "o") -- ô
    :gsub("\195\185", "u") -- ù
    :gsub("\195\187", "u") -- û
    :gsub("\195\167", "c") -- ç
  return lower
end

local function LegacySlugFromName(name)
  local lower = FoldSkillNameLegacy(name)
  if not lower then return nil end
  local slug = lower:gsub("%s+", ""):gsub("[^%w]", "")
  if slug == "" then return nil end
  if #slug > 12 then slug = slug:sub(1, 12) end
  return slug
end

local function LookupNameKey(name)
  local lower = FoldSkillNameLookup(name)
  if not lower then return nil end
  local hit = KEY_BY_NAME[lower]
  if hit then return hit end
  hit = KEY_BY_NAME[lower:gsub("%s+", "")]
  if hit then return hit end
  return nil
end

function Professions.CanonicalProfKey(key)
  if type(key) ~= "string" or key == "" then return key end
  if CANON_KEYS[key] then return key end
  local viaLegacy = LEGACY_SLUG_TO_KEY[key]
  if viaLegacy then return viaLegacy end
  local viaName = KEY_BY_NAME[key] or KEY_BY_NAME[key:lower()]
  if viaName then return viaName end
  return key
end

local function KeyFromIdList(ids)
  if type(ids) ~= "table" then
    local n = tonumber(ids)
    if n and n > 0 and KEY_BY_ID[n] then return KEY_BY_ID[n] end
    return nil
  end
  for i = 1, #ids do
    local n = tonumber(ids[i])
    if n and n > 0 and KEY_BY_ID[n] then
      return KEY_BY_ID[n]
    end
  end
  return nil
end

-- ids: single id, or ordered list (parent first, then child, then skillLine).
function Professions.ResolveProfessionKey(name, ids)
  local fromId = KeyFromIdList(ids)
  if fromId then return fromId end
  local fromName = LookupNameKey(name)
  if fromName then return fromName end
  local slug = LegacySlugFromName(name)
  if not slug then return nil end
  local viaLegacy = LEGACY_SLUG_TO_KEY[slug]
  if viaLegacy then return viaLegacy end
  return slug
end

local function KeyFromSkillName(name)
  return Professions.ResolveProfessionKey(name, nil)
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
        local name, _, skillLevel, _, _, _, skillLine = GetProfessionInfo(idx)
        local key = Professions.ResolveProfessionKey(name, skillLine)
        MergeProf(byKey, key, skillLevel, name)
      end
    end
  end

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

-- Collapse alias duplicates; keep higher skill; DisplayName from canon key.
local function CanonicalizeProfessionList(list)
  local byKey = {}
  local order = {}
  if type(list) ~= "table" then return {} end
  for i = 1, #list do
    local p = list[i]
    if type(p) == "table" and type(p.key) == "string" and p.key ~= "" then
      local canon = Professions.CanonicalProfKey(p.key)
      local skill = tonumber(p.skill) or 0
      local prev = byKey[canon]
      if not prev then
        byKey[canon] = {
          key = canon,
          skill = skill,
          name = DisplayName(canon),
        }
        order[#order + 1] = canon
      elseif skill > (prev.skill or 0) then
        prev.skill = skill
      end
    end
  end
  local out = {}
  for i = 1, #order do
    out[#out + 1] = byKey[order[i]]
  end
  return out
end

local function Decode(rest)
  local out = {}
  local classFile
  if not rest or rest == "" then return out, classFile end
  rest = tostring(rest):gsub("|", "+")
  for piece in string.gmatch(rest, "([^+]+)") do
    local key, skill = piece:match("^([%w_]+):(%d+)$")
    if key and skill then
      out[#out + 1] = {
        key = key,
        skill = tonumber(skill),
        name = DisplayName(Professions.CanonicalProfKey(key)),
      }
    else
      local cf = string.upper(piece)
      if not classFile and VALID_CLASS[cf] then
        classFile = cf
      end
    end
  end
  return CanonicalizeProfessionList(out), classFile
end

-- Keys as they appeared on the wire (before canon), for targeted PROFRQ.
local function ParseRawWireKeys(raw)
  local keys = {}
  if not raw or raw == "" then return keys end
  local rest = tostring(raw):gsub("|", "+")
  for piece in string.gmatch(rest, "([^+]+)") do
    local key = piece:match("^([%w_]+):%d+$")
    if key then keys[#keys + 1] = key end
  end
  return keys
end

local function RememberWireAlias(entry, wireKey)
  if type(entry) ~= "table" or type(wireKey) ~= "string" or wireKey == "" then return end
  local canon = Professions.CanonicalProfKey(wireKey)
  if canon == wireKey then return end
  if not CANON_KEYS[canon] then return end
  entry.wireAlias = entry.wireAlias or {}
  -- Prefer first-seen legacy key; do not overwrite with another alias.
  if not entry.wireAlias[canon] then
    entry.wireAlias[canon] = wireKey
  end
end

local function RememberWireAliasesFromRaw(entry, raw)
  local keys = ParseRawWireKeys(raw)
  for i = 1, #keys do
    RememberWireAlias(entry, keys[i])
  end
end

function Professions.WireRequestKey(entry, canonKey)
  if type(canonKey) ~= "string" or canonKey == "" then return canonKey end
  canonKey = Professions.CanonicalProfKey(canonKey)
  if type(entry) == "table" then
    local wa = entry.wireAlias
    if type(wa) == "table" and type(wa[canonKey]) == "string" and wa[canonKey] ~= "" then
      return wa[canonKey]
    end
    if type(entry.raw) == "string" and entry.raw ~= "" then
      local keys = ParseRawWireKeys(entry.raw)
      for i = 1, #keys do
        if Professions.CanonicalProfKey(keys[i]) == canonKey and keys[i] ~= canonKey then
          return keys[i]
        end
      end
    end
  end
  return canonKey
end

local function CatalogVersionBetter(a, b)
  -- true if a should win over b (both may be nil).
  if not a then return false end
  if not b then return true end
  local ae, ar = tonumber(a.epoch) or 0, tonumber(a.rev) or 0
  local be, br = tonumber(b.epoch) or 0, tonumber(b.rev) or 0
  if ae ~= be then return ae > be end
  if ar ~= br then return ar > br end
  return false
end

local function RecipeRecBetter(a, b, preferAOnTie)
  if not a then return false end
  if not b then return true end
  local ac = a.complete and true or false
  local bc = b.complete and true or false
  if ac ~= bc then return ac end
  local ae, ar = tonumber(a.epoch) or 0, tonumber(a.rev) or 0
  local be, br = tonumber(b.epoch) or 0, tonumber(b.rev) or 0
  if ae ~= be then return ae > be end
  if ar ~= br then return ar > br end
  -- Same version divergent: keep preferA (catalog already under canon).
  return preferAOnTie and true or false
end

local function HasCompleteRecipeCatalog(entry)
  if type(entry) ~= "table" or type(entry.recipes) ~= "table" then return false end
  for _, rec in pairs(entry.recipes) do
    if type(rec) == "table" and rec.complete and type(rec.ids) == "table" then
      return true
    end
  end
  return false
end

function Professions.MigrateScopeProfessionKeys(scope)
  if type(scope) ~= "table" or type(scope.prof) ~= "table" then return false end
  if scope.prof.keysCanon == 1 then return false end
  local cache = scope.prof.cache
  if type(cache) ~= "table" then
    scope.prof.keysCanon = 1
    return false
  end
  local changed = false
  local versions = scope.prof.recipeSync and scope.prof.recipeSync.catalogVersions

  for owner, entry in pairs(cache) do
    if type(entry) == "table" then
      RememberWireAliasesFromRaw(entry, entry.raw)

      -- List keys → canon; remember aliases; collapse.
      if type(entry.list) == "table" then
        for i = 1, #entry.list do
          local p = entry.list[i]
          if type(p) == "table" and type(p.key) == "string" then
            RememberWireAlias(entry, p.key)
          end
        end
        local newList = CanonicalizeProfessionList(entry.list)
        -- Detect change cheaply
        if #newList ~= #entry.list then
          changed = true
        else
          for i = 1, #newList do
            if not entry.list[i] or entry.list[i].key ~= newList[i].key
                or (tonumber(entry.list[i].skill) or 0) ~= newList[i].skill then
              changed = true
              break
            end
          end
        end
        entry.list = newList
      end

      -- recipes[old] → recipes[canon]
      if type(entry.recipes) == "table" then
        local moved = {}
        local keys = {}
        for k in pairs(entry.recipes) do keys[#keys + 1] = k end
        for i = 1, #keys do
          local oldKey = keys[i]
          local rec = entry.recipes[oldKey]
          local canon = Professions.CanonicalProfKey(oldKey)
          if canon ~= oldKey then
            RememberWireAlias(entry, oldKey)
            changed = true
            local preferCanon = moved[canon] ~= nil or (entry.recipes[canon] and canon == oldKey)
            -- When merging into existing canon bucket, prefer the one already under canon.
            local existing = moved[canon] or (canon ~= oldKey and entry.recipes[canon]) or nil
            local existingWasCanon = existing ~= nil and (moved[canon] ~= nil or entry.recipes[canon] ~= nil)
            if existing then
              if RecipeRecBetter(rec, existing, not existingWasCanon) then
                moved[canon] = rec
              else
                moved[canon] = existing
              end
            else
              moved[canon] = rec
            end
            entry.recipes[oldKey] = nil
          else
            if not moved[canon] then
              moved[canon] = rec
            end
          end
        end
        -- Clear and rewrite
        for k in pairs(entry.recipes) do entry.recipes[k] = nil end
        for k, rec in pairs(moved) do
          entry.recipes[k] = rec
        end
      end

      -- catalogVersions[owner]
      if type(versions) == "table" and type(versions[owner]) == "table" then
        local bag = versions[owner]
        local moved = {}
        local keys = {}
        for k in pairs(bag) do keys[#keys + 1] = k end
        for i = 1, #keys do
          local oldKey = keys[i]
          local ver = bag[oldKey]
          local canon = Professions.CanonicalProfKey(oldKey)
          if canon ~= oldKey then
            changed = true
            local existing = moved[canon] or bag[canon]
            if CatalogVersionBetter(ver, existing) then
              moved[canon] = ver
            elseif existing then
              moved[canon] = existing
            else
              moved[canon] = ver
            end
            bag[oldKey] = nil
          else
            if not moved[canon] then moved[canon] = ver end
          end
        end
        for k in pairs(bag) do bag[k] = nil end
        for k, ver in pairs(moved) do bag[k] = ver end
      end
    end
  end

  scope.prof.keysCanon = 1
  if changed then
    local recipesMod = GR:GetModule("ProfRecipes")
    if recipesMod and recipesMod.InvalidateGuildRecipeIndex then
      recipesMod.InvalidateGuildRecipeIndex()
    end
  end
  return changed
end

function Professions:MigrateActiveScopeKeys()
  if not GR.db then return end
  local scope = U.GetScopeDB and U.GetScopeDB()
  if scope then
    Professions.MigrateScopeProfessionKeys(scope)
  end
end

-- Also migrate every stored guild scope (two-guild acceptance / guild switch).
function Professions:MigrateAllScopeKeys()
  if not GR.db or type(GR.db.scopes) ~= "table" then
    Professions:MigrateActiveScopeKeys()
    return
  end
  for _, scope in pairs(GR.db.scopes) do
    if type(scope) == "table" then
      Professions.MigrateScopeProfessionKeys(scope)
    end
  end
end

-- 0.6.x kept one account-wide cache; move it once into the guild scope that is
-- active at first 0.7 login (it was wiped on every guild change before).
function Professions:MigrateCache()
  local db = GR.db
  if not db or not db.prof or db.prof._movedToScope then
    -- Profession-key migrate is independent of this account flag.
    return
  end
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
  Professions:MigrateActiveScopeKeys()
  return Cache()
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

local function MergeProfEntryInto(dst, src, ownerKey)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  local st = tonumber(src.time) or 0
  local dt = tonumber(dst.time) or 0
  local sn, ss = ProfListScore(src.list)
  local dn, ds = ProfListScore(dst.list)
  -- Never replace a filled list with an empty newer stub.
  local takeList = (sn > 0) and (
    dn == 0
    or st > dt
    or (st == dt and (sn > dn or (sn == dn and ss > ds)))
  )
  if takeList and src.list ~= nil then
    dst.list = src.list
  end
  if st > dt then
    dst.time = src.time
    if src.raw ~= nil then dst.raw = src.raw end
  elseif dst.raw == nil and src.raw ~= nil then
    dst.raw = src.raw
  end
  if src.classFile and not dst.classFile then
    dst.classFile = src.classFile
  end
  if type(src.recipes) == "table" then
    dst.recipes = dst.recipes or {}
    for pk, bag in pairs(src.recipes) do
      if type(pk) == "string" and type(bag) == "table" then
        local cur = dst.recipes[pk]
        local ce, cr = tonumber(cur and cur.epoch) or 0, tonumber(cur and cur.rev) or 0
        local ve, vr = tonumber(bag.epoch) or 0, tonumber(bag.rev) or 0
        if not cur or ve > ce or (ve == ce and vr > cr) then
          dst.recipes[pk] = bag
        end
      end
    end
  end
  if type(src.wireAlias) == "table" then
    dst.wireAlias = dst.wireAlias or {}
    for ck, wk in pairs(src.wireAlias) do
      if type(ck) == "string" and type(wk) == "string" and not dst.wireAlias[ck] then
        dst.wireAlias[ck] = wk
      end
    end
  end
  if type(dst.list) == "table" and #dst.list > 0 and type(dst.recipes) == "table" then
    local recipesMod = GR:GetModule("ProfRecipes")
    if recipesMod and recipesMod.PruneRecipesToProfessionList then
      dst.recipes = recipesMod.PruneRecipesToProfessionList(dst.recipes, dst.list, ownerKey)
    end
  end
end

-- Self-alias for cache fold: same CharIdentity only (not IsSelfName /
-- FoldNameKey first-token, which merges Baba-Bing with Baba-Other).
local function IsSelfCacheAlias(name, me)
  if not me or not name then return false end
  if name == me then return true end
  local a, b = U.CharIdentity(me), U.CharIdentity(name)
  return a ~= nil and a == b
end

local function MergeCatalogVersionsInto(winnerKey, loserKeys)
  if not winnerKey or type(loserKeys) ~= "table" then return end
  local scope = U.GetScopeDB()
  local bag = scope and scope.prof and scope.prof.recipeSync and scope.prof.recipeSync.catalogVersions
  if type(bag) ~= "table" then return end
  bag[winnerKey] = bag[winnerKey] or {}
  local win = bag[winnerKey]
  for i = 1, #loserKeys do
    local lk = loserKeys[i]
    if lk and lk ~= winnerKey and type(bag[lk]) == "table" then
      for pk, ver in pairs(bag[lk]) do
        if type(pk) == "string" and type(ver) == "table" then
          local cur = win[pk]
          local ce, cr = tonumber(cur and cur.epoch) or 0, tonumber(cur and cur.rev) or 0
          local ve, vr = tonumber(ver.epoch) or 0, tonumber(ver.rev) or 0
          if ve > ce or (ve == ce and vr > cr) then
            win[pk] = { epoch = ve, rev = vr }
          end
        end
      end
      bag[lk] = nil
    end
  end
end

-- Existing cache key for this character identity, or nil.
function Professions:ResolveCacheOwner(name)
  if not name or name == "" or not GR.db then return nil end
  local cache = Cache()
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

-- Drop remote stubs that are truly empty (no list and no complete recipe catalogs).
function Professions:ClearEmptyRemoteStubs()
  if not GR.db then return end
  Professions:MigrateActiveScopeKeys()
  local cache = Cache()
  local me = U.NormalizeName(U.PlayerName())
  for name, entry in pairs(cache) do
    if name ~= me and entry and not entry.classFile then
      local list = entry.list
      local emptyList = not list or #list == 0
      if emptyList and not HasCompleteRecipeCatalog(entry) then
        cache[name] = nil
      end
    end
  end
  Professions:PruneCharacterDuplicates()
end

-- Fold alias keys (Name vs Name-Realm, Forever wire forms) into one owner each.
function Professions:PruneCharacterDuplicates()
  if not GR.db then return end
  Professions:MigrateActiveScopeKeys()
  local cache = Cache()
  local me = U.NormalizeName(U.PlayerName())

  local groups = {}
  for name, entry in pairs(cache) do
    if type(name) == "string" and type(entry) == "table" then
      local id = U.CharIdentity(name) or ("\0" .. string.lower(name))
      local g = groups[id]
      if not g then
        g = {}
        groups[id] = g
      end
      g[#g + 1] = name
    end
  end

  for _, keys in pairs(groups) do
    -- Lone self-alias still moves onto the canonical me key.
    if #keys == 1 then
      local only = keys[1]
      if me and only ~= me and IsSelfCacheAlias(only, me) then
        local entry = cache[only]
        if type(cache[me]) ~= "table" then
          cache[me] = {
            list = entry.list,
            classFile = entry.classFile or U.PlayerClassFile(),
            time = entry.time or U.WallTime(),
            raw = entry.raw,
            recipes = entry.recipes,
            wireAlias = entry.wireAlias,
          }
        else
          MergeProfEntryInto(cache[me], entry, me)
        end
        cache[only] = nil
        MergeCatalogVersionsInto(me, { only })
      end
    elseif #keys > 1 then
      local winner = keys[1]
      for i = 2, #keys do
        local k = keys[i]
        if me and k == me then
          winner = k
        elseif not (me and winner == me) then
          local a, b = cache[k], cache[winner]
          local at, bt = tonumber(a and a.time) or 0, tonumber(b and b.time) or 0
          local an, ascore = ProfListScore(a and a.list)
          local bn, bscore = ProfListScore(b and b.list)
          -- Prefer filled lists over empty newer stubs when picking the key.
          if an == 0 and bn > 0 then
            -- keep winner
          elseif bn == 0 and an > 0 then
            winner = k
          elseif at > bt or (at == bt and (an > bn or (an == bn and ascore > bscore))) then
            winner = k
          elseif me and IsSelfCacheAlias(k, me) and cache[me] then
            winner = me
          end
        end
      end
      if me then
        for i = 1, #keys do
          if IsSelfCacheAlias(keys[i], me) then
            if type(cache[me]) == "table" or keys[i] == me then
              winner = me
            end
            break
          end
        end
      end
      if me and winner ~= me then
        local selfAlias = false
        for i = 1, #keys do
          if IsSelfCacheAlias(keys[i], me) then selfAlias = true break end
        end
        if selfAlias then
          if type(cache[me]) ~= "table" then
            cache[me] = {
              list = cache[winner].list,
              classFile = cache[winner].classFile or U.PlayerClassFile(),
              time = cache[winner].time or U.WallTime(),
              raw = cache[winner].raw,
              recipes = cache[winner].recipes,
              wireAlias = cache[winner].wireAlias,
            }
          end
          winner = me
        end
      end
      local winEntry = cache[winner]
      if type(winEntry) ~= "table" then
        winEntry = {
          list = {},
          time = U.WallTime(),
          classFile = me and U.PlayerClassFile() or nil,
        }
        cache[winner] = winEntry
      end
      local losers = {}
      for i = 1, #keys do
        local k = keys[i]
        if k ~= winner and type(cache[k]) == "table" then
          losers[#losers + 1] = k
          MergeProfEntryInto(winEntry, cache[k], winner)
          cache[k] = nil
        end
      end
      MergeCatalogVersionsInto(winner, losers)
      if type(winEntry.list) == "table" and #winEntry.list > 0 and type(winEntry.recipes) == "table" then
        local recipesMod = GR:GetModule("ProfRecipes")
        if recipesMod and recipesMod.PruneRecipesToProfessionList then
          winEntry.recipes = recipesMod.PruneRecipesToProfessionList(winEntry.recipes, winEntry.list, winner)
        end
      end
    end
  end
end

function Professions:PruneSelfDuplicates()
  return Professions:PruneCharacterDuplicates()
end

local lastProfReqSend = 0
local lastProfReqReply = 0
local lastSentEncoded
local PROFREQ_SEND_CD = 30
local PROFREQ_REPLY_CD = 15

function Professions:Broadcast(force)
  local db = GR.db
  if not db or not db.privacy.shareProfessions then return end
  if not IsInGuild() then return end
  Professions:MigrateCache()
  Professions:MigrateActiveScopeKeys()
  Professions:PruneCharacterDuplicates()
  local list = CollectLocal()
  local classFile = U.PlayerClassFile()
  local encoded = Encode(list, classFile)
  local me = U.NormalizeName(U.PlayerName())
  local prevSelf = Cache()[me]
  local recipes = prevSelf and prevSelf.recipes
  local recipesMod = GR:GetModule("ProfRecipes")
  if recipesMod and recipesMod.PruneRecipesToProfessionList then
    recipes = recipesMod.PruneRecipesToProfessionList(recipes, list, me)
  end
  Cache()[me] = {
    list = list,
    classFile = classFile,
    time = U.WallTime(),
    recipes = recipes,
    wireAlias = prevSelf and prevSelf.wireAlias,
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

function Professions:ApplyClassFile(who, classFile)
  if not who or not classFile or classFile == "" then return false end
  local cache = Cache()
  if not cache then return false end
  local owner = Professions:ResolveCacheOwner(who) or who
  local entry = cache[owner]
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
    Professions:MigrateAllScopeKeys()
    Professions:PruneCharacterDuplicates()
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
      Professions:PruneCharacterDuplicates()
      return
    end
    Professions:MigrateActiveScopeKeys()
    local raw = tostring(rest or "")
    if #raw > 200 then raw = raw:sub(1, 200) end
    local list, classFile = Decode(raw)
    local cache = Cache()
    local owner = Professions:ResolveCacheOwner(sender) or sender
    local prev = cache[owner]
    if #list == 0 then
      if raw ~= "" then
        GR.db.prof._decodeMiss = (GR.db.prof._decodeMiss or 0) + 1
      end
      if prev and prev.list and #prev.list > 0 then
        prev.raw = raw
        prev.time = U.WallTime()
        if classFile then prev.classFile = classFile end
        RememberWireAliasesFromRaw(prev, raw)
        Professions:PruneCharacterDuplicates()
        GR:SendMessage("PROF_CACHE_CHANGED", owner)
        return
      end
    end
    local recipes = prev and prev.recipes
    local recipesMod = GR:GetModule("ProfRecipes")
    if recipesMod and recipesMod.PruneRecipesToProfessionList then
      recipes = recipesMod.PruneRecipesToProfessionList(recipes, list, owner)
    end
    local entry = {
      list = list,
      raw = raw,
      time = U.WallTime(),
      classFile = classFile or (prev and prev.classFile),
      recipes = recipes,
      wireAlias = prev and prev.wireAlias,
    }
    RememberWireAliasesFromRaw(entry, raw)
    -- Also remember aliases from the raw pieces even after Decode collapsed them.
    local rawKeys = ParseRawWireKeys(raw)
    for i = 1, #rawKeys do
      RememberWireAlias(entry, rawKeys[i])
    end
    cache[owner] = entry
    if owner ~= sender and cache[sender] and cache[sender] ~= entry then
      MergeProfEntryInto(entry, cache[sender], owner)
      cache[sender] = nil
    end
    Professions:PruneCharacterDuplicates()
    GR:SendMessage("PROF_CACHE_CHANGED", owner)
  end)

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
    Professions:MigrateActiveScopeKeys()
    lastSentEncoded = nil
  end)

  local loginBroadcastDone = false
  local f = CreateFrame("Frame")
  self._eventFrame = f
  U.SafeRegisterEvent(f, "SKILL_LINES_CHANGED")
  U.SafeRegisterEvent(f, "PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
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

function Professions.ProfessionKeys()
  return PROF_KEYS_ORDER
end

Professions.DisplayName = DisplayName
Professions.IconPath = IconPath
Professions.KeyFromSkillName = KeyFromSkillName
Professions.Decode = Decode
Professions.Encode = Encode
Professions.CanonicalizeProfessionList = CanonicalizeProfessionList
Professions.KEY_BY_ID = KEY_BY_ID
