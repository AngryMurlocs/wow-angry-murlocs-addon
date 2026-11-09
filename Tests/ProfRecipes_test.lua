-- Recipe encode/decode, qty math, gathering status (no network).
-- From repo root: luajit Tests/ProfRecipes_test.lua

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

package.path = package.path
dofile("Localization/enUS.lua")
dofile("Core/Util.lua")

local GR = AngryMurlocs
GR.VERSION = "test"
GR.Comm = {
  Send = function() return true end,
}
function GR:NewModule(name)
  local m = {}
  GR._modules = GR._modules or {}
  GR._modules[name] = m
  return m
end
function GR:GetModule(name)
  return GR._modules and GR._modules[name]
end
function GR:BindMessage() end
function GR:UnbindMessages() end
function GR:ReleaseEventFrame() end
function GR:SendMessage() end
function GR:RegisterMessage() end

_G.CreateFrame = function()
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == "string" and k:match("^%u") then
        local f = function() return t end
        rawset(t, k, f)
        return f
      end
    end,
  })
end
_G.IsInGuild = function() return true end
_G.C_Timer = { After = function(_, fn) if fn then fn() end end }

dofile("Modules/ProfRecipes.lua")
local R = GR:GetModule("ProfRecipes")

check("gathering herb", R.IsGathering("herb"))
check("gathering fish", R.IsGathering("fish"))
check("not gathering alch", not R.IsGathering("alch"))
check("not gathering nil", not R.IsGathering(nil))

local c = R.ComputeCrafts(5, 2, 2)
check("fixed crafts ceil", c.mode == "fixed" and c.crafts == 3, c.crafts)
check("fixed yield 6", c.yieldMin == 6 and c.yieldMax == 6)
check("fixed qtyPer 2", c.qtyPer == 2)

local c2 = R.ComputeCrafts(4, 2, 2)
check("exact crafts", c2.crafts == 2 and c2.yieldMin == 4)

local c3 = R.ComputeCrafts(3, 1, 3)
check("range mode", c3.mode == "range" and c3.crafts == 3)
check("range yields", c3.yieldMin == 3 and c3.yieldMax == 9)

local c4 = R.ComputeCrafts(2, nil, nil)
check("unknown crafts mode", c4.mode == "crafts" and c4.crafts == 2)

check("clamp low", R.ClampQty(0) == 1)
check("clamp high", R.ClampQty(9999) == R.MAX_QTY)

local ids = { 300, 100, 200, 100 }
GR.db = GR.db or { privacy = { shareProfessions = true }, scopes = {}, prof = { recipeMeta = {} } }
GR.db.prof.recipeEpoch = 1700000100
local enc = R.Encode("tail", 2, 1700000000, true, ids, 1700000100)
check("encode non-nil", type(enc) == "string" and enc ~= "")
check("encode wire v2", enc:match("^2|") ~= nil, enc and enc:sub(1, 10))

local data, why = R.Decode(enc)
check("decode ok", data ~= nil, why)
check("decode key", data and data.profKey == "tail")
check("decode rev", data and data.rev == 2)
check("decode epoch", data and data.epoch == 1700000100)
check("decode complete", data and data.complete == true)
check("decode sorted dedupe", data and #data.ids == 3 and data.ids[1] == 100 and data.ids[3] == 300)

-- Legacy v1 still decodes (epoch 0)
local legacy = "1|tail|2|1700000000|1|3|100+200+300"
local leg, lwhy = R.Decode(legacy)
check("decode legacy v1", leg ~= nil and leg.epoch == 0 and leg.rev == 2, lwhy)

local badCount = "1|tail|1|1|1|2|10+20+30"
local d2, w2 = R.Decode(badCount)
check("reject count mismatch", d2 == nil and w2 == "count")

local incomplete = "1|tail|1|1|0|1|10"
local d3, w3 = R.Decode(incomplete)
check("reject incomplete flag", d3 == nil and w3 == "incomplete")

local tooMany = {}
for i = 1, R.MAX_RECIPES + 1 do tooMany[i] = i end
check("encode rejects too many", R.Encode("alch", 1, 1, true, tooMany) == nil)

check("ids equal", R.IdsEqual({1, 2}, {1, 2}))
check("ids unequal", not R.IdsEqual({1, 2}, {1, 3}))

local L = function(key)
  return AngryMurlocsLocale[key] or key
end
local text, calc = R.BuildRequestText({
  desired = 5,
  meta = { name = "Bolt", qtyMin = 2, qtyMax = 2 },
  matsBring = true,
  L = L,
})
check("request text has crafts", calc.crafts == 3 and calc.yieldMin == 6)
check("request text non-empty", type(text) == "string" and #text > 10)
check("request mentions yield or crafts", text:find("3") ~= nil)

-- Empty complete policy
check("reject empty complete by default",
  not R.ShouldAcceptEmptyComplete({}))
check("reject empty when spells-only",
  not R.ShouldAcceptEmptyComplete({ windowOpen = true, usedFiltered = false, filtersCleared = false }))
check("accept empty after cleared filtered scan",
  R.ShouldAcceptEmptyComplete({ windowOpen = true, usedFiltered = true, filtersCleared = true }))

-- Stub Forever: empty GetProfessionSpells + GetFilteredRecipeIDs with learned recipes
_G.C_TradeSkillUI = {
  GetProfessionSpells = function() return {} end,
  GetFilteredRecipeIDs = function() return { 2330, 2337 } end,
  GetRecipeInfo = function(id)
    return {
      recipeID = id,
      name = "Recipe" .. tostring(id),
      learned = true,
      isDummyRecipe = false,
      isGatheringRecipe = false,
    }
  end,
  GetRecipeSchematic = function(id)
    return {
      recipeID = id,
      name = "Recipe" .. tostring(id),
      quantityMin = 1,
      quantityMax = 1,
      reagentSlotSchematics = {},
    }
  end,
  GetBaseProfessionInfo = function()
    return {
      professionName = "Alchemy",
      professionID = 171,
      parentProfessionID = 171,
    }
  end,
  GetShowLearned = function() return true end,
  GetShowUnlearned = function() return true end,
  GetRecipeItemNameFilter = function() return "" end,
  GetOnlyShowMakeableRecipes = function() return false end,
  GetOnlyShowSkillUpRecipes = function() return false end,
  SetShowLearned = function() end,
  SetShowUnlearned = function() end,
  SetRecipeItemNameFilter = function() end,
  SetOnlyShowMakeableRecipes = function() end,
  SetOnlyShowSkillUpRecipes = function() end,
}

-- KeyFromSkillName via Professions stub
GR:NewModule("Professions").KeyFromSkillName = function(name)
  if name and string.lower(name):find("alch") then return "alch" end
  return "alch"
end
GR:GetModule("Professions").DisplayName = function(key) return key end

local ctx = {
  profKey = "alch",
  professionID = 171,
  skillLineID = 171,
  name = "Alchemy",
}
local scanIds, scanComplete, scanWhy = R.ScanOpenTradeSkill(ctx)
check("filtered scan finds recipes", scanIds and #scanIds == 2, scanWhy)
check("filtered scan complete", scanComplete == true)
check("filtered why", scanWhy == "ok_filtered")

-- Empty spells only (no filtered API): empty table skipped → spells_fail
_G.C_TradeSkillUI.GetFilteredRecipeIDs = nil
_G.C_TradeSkillUI.GetProfessionSpells = function() return {} end
local eIds, eComplete, eWhy = R.ScanOpenTradeSkill(ctx)
check("empty spells table is fail", eIds == nil and eWhy == "spells_fail", eWhy)

-- Spells return IDs but all unlearned → empty_suspect (do not store fake complete)
_G.C_TradeSkillUI.GetProfessionSpells = function() return { 99 } end
_G.C_TradeSkillUI.GetRecipeInfo = function(id)
  return { recipeID = id, name = "X", learned = false }
end
local uIds, uComplete, uWhy = R.ScanOpenTradeSkill(ctx)
check("unlearned-only is empty_suspect", uIds == nil and uWhy == "empty_suspect", uWhy)

-- Icon resolve: output item beats question mark
_G.C_TradeSkillUI.GetRecipeOutputItemData = function(id)
  return { icon = 134400, itemID = 118 }
end
_G.GetItemIcon = function(itemID)
  return "Interface\\Icons\\INV_Potion_52"
end
local icon, outId = R.ResolveRecipeIcon(2330, { learned = true }, {})
check("resolve icon from output", icon == 134400 or icon == "Interface\\Icons\\INV_Potion_52", tostring(icon))
check("resolve output item id", outId == 118)

local icon2 = R.ResolveRecipeIcon(2330, { icon = 132847 }, nil)
check("resolve prefers recipeInfo.icon", icon2 == 132847)

_G.C_TradeSkillUI.GetRecipeOutputItemData = function() return nil end
_G.GetItemIcon = nil
_G.GetSpellTexture = nil
local icon3 = R.ResolveRecipeIcon(1, nil, nil)
check("resolve fallback question", icon3 == "Interface\\Icons\\INV_Misc_QuestionMark")

-- Staggered broadcast key order
GR:GetModule("Professions").ProfessionKeys = function()
  return { "alch", "bs", "tail", "cook" }
end
_G.UnitName = function() return "Tester" end
_G.UnitFullName = function() return "Tester", "Realm" end
_G.GetRealmName = function() return "Realm" end
_G.GetGuildInfo = function() return "G" end
_G.IsInGuild = function() return true end
GR.db = {
  privacy = { shareProfessions = true },
  scopes = {},
  prof = { recipeMeta = {} },
}
-- Seed self cache via ApplyLocalScan path helpers: poke scope cache
local scope = AngryMurlocs.Util.GetScopeDB()
local me = AngryMurlocs.Util.NormalizeName(AngryMurlocs.Util.PlayerName())
scope.prof.cache[me] = {
  list = {},
  recipes = {
    tail = { ids = { 1 }, rev = 1, scanAt = 1, recvAt = 1, complete = true },
    alch = { ids = { 2 }, rev = 1, scanAt = 1, recvAt = 1, complete = true },
    herb = { ids = {}, rev = 1, scanAt = 1, recvAt = 1, complete = true }, -- gathering skip
    zz = { ids = { 3 }, rev = 1, scanAt = 1, recvAt = 1, complete = true }, -- unknown key after order
  },
}
local keys = R:ListCompleteProfessionKeys()
check("list keys order alch then tail", keys[1] == "alch" and keys[2] == "tail", table.concat(keys, ","))
check("list keys skips gathering", not (function()
  for i = 1, #keys do if keys[i] == "herb" then return true end end
end)())
check("list keys includes extra", (function()
  for i = 1, #keys do if keys[i] == "zz" then return true end end
end)())

local sent = {}
local realSend = R.BroadcastProfession
R.enabled = true
function R:BroadcastProfession(key, force)
  sent[#sent + 1] = key
end
local n = R:BroadcastAllStaggered(true, 0.55)
check("stagger schedules all", n == #keys)
check("stagger first immediate", sent[1] == keys[1])
-- C_Timer stub runs After callbacks immediately
check("stagger all sent via timer stub", #sent == #keys, #sent)
R.BroadcastProfession = realSend
R.enabled = false

-- On-demand: RequestProfession sends PROFRQ with one profKey (not empty = all)
do
  _G.GetTime = _G.GetTime or function() return 100 end
  local bodies = {}
  local realCommSend = GR.Comm.Send
  GR.Comm.Send = function(_, body)
    bodies[#bodies + 1] = body
    return true
  end
  R.enabled = true
  local ok, why = R:RequestProfession("alch", true)
  check("request profession ok", ok == true, why)
  check("request profession why sent", why == "sent")
  check("request profession wire has key", bodies[1] and bodies[1]:find("PROFRQ|1|alch", 1, true) ~= nil, bodies[1])
  local okAll, whyAll = R:RequestAll(nil, true)
  check("request all ok", okAll == true, whyAll)
  check("request all empty key", bodies[2] and bodies[2]:find("PROFRQ|1|", 1, true) ~= nil
    and not bodies[2]:match("PROFRQ|1|%w"), bodies[2])
  GR.Comm.Send = realCommSend
  R.enabled = false
end

-- Empty PROFRQ reply path uses staggered broadcast (not burst BroadcastAll)
do
  local staggerCalls = 0
  local broadcastAllCalls = 0
  local realStagger = R.BroadcastAllStaggered
  local realAll = R.BroadcastAll
  function R:BroadcastAllStaggered(force, interval)
    staggerCalls = staggerCalls + 1
    check("empty reply stagger force", force == true)
    check("empty reply stagger interval", interval == 0.55, tostring(interval))
    return 0
  end
  function R:BroadcastAll()
    broadcastAllCalls = broadcastAllCalls + 1
    return 0
  end
  R.enabled = true
  -- Simulate OnEnable handler body for empty profKey
  R:BroadcastAllStaggered(true, 0.55)
  check("empty reply uses stagger", staggerCalls == 1)
  check("empty reply skips burst BroadcastAll", broadcastAllCalls == 0)
  R.BroadcastAllStaggered = realStagger
  R.BroadcastAll = realAll
  R.enabled = false
end

-- Material rows / missing summary
do
  local reagents = {
    { itemID = 10, qty = 2 },
    { itemID = 20, qty = 1 },
  }
  local counts = { [10] = 3, [20] = 0 }
  local rows, missingTotal, firstName, firstQty = R.ComputeMaterialRows(reagents, 3, function(id)
    return counts[id] or 0
  end)
  check("mat rows count", #rows == 2)
  check("mat need scales", rows[1].need == 6 and rows[2].need == 3)
  check("mat bag", rows[1].bag == 3 and rows[2].bag == 0)
  check("mat missing", rows[1].missing == 3 and rows[2].missing == 3)
  check("mat missing total", missingTotal == 6)
  check("mat first missing qty", firstQty == 3)
end

-- Item name resolve + meta cache fallback
do
  _G.GetItemInfo = function(id)
    if id == 765 then return "Silverleaf" end
    return nil
  end
  local n1, ok1 = R.ResolveItemName(765)
  check("resolve from GetItemInfo", ok1 and n1 == "Silverleaf", n1)
  local n2, ok2 = R.ResolveItemName(999, "Cached Herb")
  check("resolve prefers knownName", ok2 and n2 == "Cached Herb", n2)
  local n3, ok3 = R.ResolveItemName(404)
  check("resolve miss returns nil", not ok3 and n3 == nil)

  GR.db.prof.recipeMeta[42] = {
    name = "Test Recipe",
    reagents = { { itemID = 765, qty = 2 }, { itemID = 2447, qty = 1 } },
  }
  R.CacheReagentName(42, 765, "Silverleaf")
  R.CacheReagentName(42, 2447, "Peacebloom")
  local meta = R.GetMeta(42)
  check("cache reagent name 765", meta.reagents[1].name == "Silverleaf")
  check("cache reagent name 2447", meta.reagents[2].name == "Peacebloom")
  local rows2 = R.ComputeMaterialRows(meta.reagents, 1, function() return 0 end)
  check("mat row uses cached name", rows2[1].name == "Silverleaf" and rows2[2].name == "Peacebloom")
  _G.GetItemInfo = nil
end

-- Guild recipe index aggregates unique recipes + crafters
do
  local scope = AngryMurlocs.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = {},
    recipes = {
      alch = { ids = { 100, 200 }, rev = 1, complete = true },
      herb = { ids = { 999 }, rev = 1, complete = true }, -- gathering ignored
    },
  }
  scope.prof.cache["Bob-Realm"] = {
    list = {},
    recipes = {
      alch = { ids = { 100 }, rev = 1, complete = true },
      tail = { ids = { 300 }, rev = 1, complete = false },
    },
  }
  GR.db.prof.recipeMeta[100] = { name = "Minor Healing Potion" }
  GR.db.prof.recipeMeta[200] = { name = "Elixir" }
  GR.db.prof.recipeMeta[300] = { name = "Linen Cloak" }
  local idx = R.BuildGuildRecipeIndex()
  local byId = {}
  for i = 1, #idx do byId[idx[i].recipeId] = idx[i] end
  check("index has shared recipe", byId[100] ~= nil)
  check("index crafter count 2", byId[100] and #byId[100].crafters == 2, byId[100] and #byId[100].crafters)
  check("index skips gathering id", byId[999] == nil)
  check("index includes partial", byId[300] ~= nil)
  check("index one row per recipe", byId[200] ~= nil and #byId[200].crafters == 1)
end

-- Case 6: missing recipe info is not confirmed learned; prior confirmed kept
do
  local api = {
    GetRecipeInfo = function(id)
      if id == 1 then return { recipeID = 1, name = "A", learned = true } end
      return nil -- missing details for id 2
    end,
    GetRecipeSchematic = function() return { name = "A", quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} } end,
  }
  local ids, unknown = R.CollectLearnedFromIds(api, { 1, 2 })
  check("case6 learned only confirmed", #ids == 1 and ids[1] == 1, table.concat(ids or {}, ","))
  check("case6 unknown counted", unknown == 1, tostring(unknown))

  local apiNoField = {
    GetRecipeInfo = function(id)
      return { recipeID = id, name = "X" } -- no learned field
    end,
  }
  local ids2, unk2 = R.CollectLearnedFromIds(apiNoField, { 9 })
  check("case6 missing learned field unknown", #ids2 == 0 and unk2 == 1)
end

-- Case 7: failed filter clear + subset must not erase confirmed second recipe
do
  local me = AngryMurlocs.Util.NormalizeName(AngryMurlocs.Util.PlayerName())
  local scope = AngryMurlocs.Util.GetScopeDB()
  scope.prof.cache[me] = scope.prof.cache[me] or { list = {}, recipes = {} }
  scope.prof.cache[me].recipes.alch = {
    ids = { 2330, 2337 },
    rev = 3,
    scanAt = 50,
    recvAt = 50,
    complete = true,
  }
  local setFails = true
  _G.C_TradeSkillUI = {
    GetProfessionSpells = function() return { 2330 } end, -- subset only
    GetFilteredRecipeIDs = function() return { 2330 } end,
    GetRecipeInfo = function(id)
      return { recipeID = id, name = "R" .. id, learned = true }
    end,
    GetRecipeSchematic = function(id)
      return { recipeID = id, name = "R" .. id, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} }
    end,
    GetBaseProfessionInfo = function()
      return { professionName = "Alchemy", professionID = 171, parentProfessionID = 171 }
    end,
    GetShowLearned = function() return true end,
    GetShowUnlearned = function() return true end,
    GetRecipeItemNameFilter = function() return "x" end,
    GetOnlyShowMakeableRecipes = function() return false end,
    GetOnlyShowSkillUpRecipes = function() return false end,
    SetShowLearned = function() end,
    SetShowUnlearned = function() end,
    SetRecipeItemNameFilter = function()
      if setFails then error("filter set failed") end
    end,
    SetOnlyShowMakeableRecipes = function() end,
    SetOnlyShowSkillUpRecipes = function() end,
  }
  local sIds, sComplete, sWhy = R.ScanOpenTradeSkill(ctx)
  check("case7 scan not complete", sComplete == false, tostring(sWhy))
  R:ApplyLocalScan("alch", sIds or { 2330 }, false, {})
  local kept = R.GetEntry(me, "alch")
  check("case7 kept both recipes", kept and #kept.ids == 2 and kept.ids[1] == 2330 and kept.ids[2] == 2337)
  check("case7 partial visible", R.GetStatus(me, "alch") == "partial")
  check("case7 complete flag retained", kept.complete == true and kept.partialSeenAt ~= nil)
end

-- Case 12: same rev/ids, newer scanAt wins; older does not roll back
do
  local scope = AngryMurlocs.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = {},
    recipes = {
      alch = { ids = { 10, 20 }, rev = 5, scanAt = 100, recvAt = 100, complete = true },
    },
  }
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch",
    rev = 5,
    scanAt = 200,
    complete = true,
    ids = { 10, 20 },
  })
  local e = scope.prof.cache["Alice-Realm"].recipes.alch
  check("case12 scanAt advances to 200", e.scanAt == 200, tostring(e.scanAt))
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch",
    rev = 5,
    scanAt = 150,
    complete = true,
    ids = { 10, 20 },
  })
  e = scope.prof.cache["Alice-Realm"].recipes.alch
  check("case12 older scanAt ignored", e.scanAt == 200, tostring(e.scanAt))
end

-- Material example 5 desired / yield 2 / 3 herbs / bag 7 → 3 crafts, need 9, missing 2
do
  local calc = R.ComputeCrafts(5, 2, 2)
  local rows, missingTotal = R.ComputeMaterialRows({ { itemID = 1, qty = 3, name = "Herb" } }, calc.crafts, function()
    return 7
  end)
  check("mat example crafts 3", calc.crafts == 3 and calc.yieldMin == 6)
  check("mat example need 9", rows[1].need == 9)
  check("mat example missing 2", rows[1].missing == 2 and missingTotal == 2)
end

-- Unknown bag count is not zero when counter returns nil
do
  local rows, _, _, _, allKnown, anyUnknown = R.ComputeMaterialRows(
    { { itemID = 5, qty = 1 } },
    1,
    function() return nil end
  )
  check("unknown bag nil", rows[1].bag == nil and rows[1].unknown == true)
  check("unknown not allKnown", allKnown == false and anyUnknown == true)
end

-- GetBagCount: real API stubs
do
  local saved = _G.GetItemCount
  _G.GetItemCount = function(id)
    if id == 765 then return 7 end
    if id == 2447 then return nil end -- success, no number
    error("boom")
  end
  check("GetBagCount number", R.GetBagCount(765) == 7)
  check("GetBagCount nil result is 0", R.GetBagCount(2447) == 0)
  _G.GetItemCount = function() error("fail") end
  _G.C_Item = nil
  check("GetBagCount all pcall fail is nil", R.GetBagCount(1) == nil)
  _G.GetItemCount = nil
  _G.C_Item = nil
  check("GetBagCount no API is nil", R.GetBagCount(1) == nil)
  _G.GetItemCount = saved
end

-- Case 1: Alice shares recipe IDs; Bob has empty meta DB and resolves via PROFRM
do
  GR.db.prof.recipeMeta = {} -- Bob starts without metadata
  local enc = R.EncodeMetaBatch({
    {
      recipeId = 2330,
      name = "Test Healing Potion",
      icon = 134400,
      outputItemID = 118,
      qtyMin = 1,
      qtyMax = 1,
      isEnchant = false,
      locale = "enUS",
      reagents = { { itemID = 2447, qty = 1, name = "Peacebloom" }, { itemID = 765, qty = 1, name = "Silverleaf" } },
    },
  })
  check("meta encode non-nil", type(enc) == "string" and enc ~= "")
  local entries, mwhy = R.DecodeMetaBatch(enc)
  check("meta decode ok", entries ~= nil and #entries == 1, mwhy)
  R:OnMetaUpdate("Alice-Realm", entries)
  local meta = R.GetMeta(2330)
  check("case1 bob resolves name", meta and meta.name == "Test Healing Potion", meta and meta.name)
  check("case1 bob sees reagents", meta and meta.reagents and #meta.reagents == 2)
  check("case1 bob output item", meta and meta.outputItemID == 118)
  -- Knowledge must not be granted by meta alone
  check("case1 meta is not knowledge", R.GetEntry("Alice-Realm", "alch") == nil
    or not (function()
      local e = R.GetEntry("Alice-Realm", "alch")
      if not e or not e.ids then return false end
      for i = 1, #e.ids do if e.ids[i] == 2330 then return true end end
      return false
    end)())

  local req = R.EncodeMetaRequest({ 2330, 999 })
  local rids = R.DecodeMetaRequest(req)
  check("meta request roundtrip", rids and #rids == 2 and rids[1] == 999 and rids[2] == 2330,
    rids and table.concat(rids, ","))
end

-- Case 4/5: multi-word AND search, item link / dual recipes
do
  local name = "Test Healing Potion"
  local ok1 = select(1, R.MatchRecipeQuery("Healing Test", {
    recipeId = 2330, name = name, outputItemID = 118, outputName = "Healing Potion",
  }))
  check("case4 healing test matches", ok1 == true)
  local ok2 = select(1, R.MatchRecipeQuery("Healing MissingWord", {
    recipeId = 2330, name = name, outputItemID = 118, outputName = "Healing Potion",
  }))
  check("case4 missing word excludes", ok2 == false)
  local ok3 = select(1, R.MatchRecipeQuery("item:118", {
    recipeId = 2330, name = name, outputItemID = 118,
  }))
  check("case5 item:118 matches recipe A", ok3 == true)
  local ok4 = select(1, R.MatchRecipeQuery("item:118", {
    recipeId = 2337, name = "Other Potion", outputItemID = 118,
  }))
  check("case5 item:118 matches recipe B", ok4 == true)
  local ok5 = select(1, R.MatchRecipeQuery("recipe:2330", {
    recipeId = 2330, name = name, outputItemID = 118,
  }))
  check("case5 recipe:2330 exact", ok5 == true)
  local ok6 = select(1, R.MatchRecipeQuery("recipe:2330", {
    recipeId = 2337, name = name, outputItemID = 118,
  }))
  check("case5 recipe:2330 excludes other", ok6 == false)
  local ok7 = select(1, R.MatchRecipeQuery("Äther", {
    recipeId = 1, name = "Großer Äther", outputItemID = 1,
  }))
  check("umlaut normalize search", ok7 == true)
end

-- Case 9/10 draft fingerprint drift
do
  local fp1 = R.RequestDraftFingerprint({
    recipeId = 2330, player = "Alice-Realm", profKey = "alch", desired = 1, matsBring = true,
  })
  local fp2 = R.RequestDraftFingerprint({
    recipeId = 2330, player = "Alice-Realm", profKey = "alch", desired = 2, matsBring = true,
  })
  local fp3 = R.RequestDraftFingerprint({
    recipeId = 2330, player = "Carol-Realm", profKey = "alch", desired = 2, matsBring = true,
  })
  check("case9 qty changes fingerprint", fp1 ~= fp2)
  check("case10 crafter changes fingerprint", fp2 ~= fp3)
end

-- Case 11: complete empty catalogue removes knowledge
do
  local scope = AngryMurlocs.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = {},
    recipes = {
      alch = { ids = { 2330 }, rev = 1, scanAt = 10, recvAt = 10, complete = true },
    },
  }
  check("case11 knows before", R.PlayerKnowsRecipe("Alice-Realm", "alch", 2330) == true)
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch", rev = 2, scanAt = 20, complete = true, ids = {},
  })
  check("case11 knows after empty", R.PlayerKnowsRecipe("Alice-Realm", "alch", 2330) == false)
end

-- Case 2 helper: RequestRecipeDataRefresh uses PROFRQ (throttled)
do
  local bodies = {}
  local realCommSend = GR.Comm.Send
  GR.Comm.Send = function(_, body)
    bodies[#bodies + 1] = body
    return true
  end
  R.enabled = true
  _G.GetTime = function() return 500 end
  -- reset cooldown by forcing
  local ok, why = R:RequestRecipeDataRefresh("alch", true)
  check("case2 recipe refresh sent", ok == true and why == "sent", why)
  check("case2 uses PROFRQ", bodies[1] and bodies[1]:find("PROFRQ|1|alch", 1, true) ~= nil, bodies[1])
  check("case2 busy after send", R:IsRecipeRefreshBusy() == true)
  local ok2, why2 = R:RequestRecipeDataRefresh("alch", false)
  check("case2 second click busy/cd", ok2 == false and (why2 == "busy" or why2 == "cooldown"), why2)
  GR.Comm.Send = realCommSend
  R.enabled = false
  R:MarkRecipeRefreshDone("done")
end

-- R1: guild scope change must not keep prior guild index
do
  _G.GetGuildInfo = function() return "Angry Murlocs" end
  local scopeA = AngryMurlocs.Util.GetScopeDB()
  scopeA.prof.cache["Alice-Realm"] = {
    list = { { key = "tail", skill = 150, name = "Tailoring" } },
    recipes = {
      tail = { ids = { 2387 }, rev = 1, scanAt = 10, recvAt = 10, complete = true, epoch = 1 },
    },
  }
  R.InvalidateGuildRecipeIndex()
  local before = R.BuildGuildRecipeIndex()
  check("R1 index has Alice in guild A", #before == 1 and before[1].crafters[1] == "Alice-Realm")

  _G.GetGuildInfo = function() return "Other Guild" end
  -- Simulate real GUILD_UPDATE handler body
  R.InvalidateGuildRecipeIndex()
  local scopeB = AngryMurlocs.Util.GetScopeDB()
  check("R1 scope B cache empty", next(scopeB.prof.cache) == nil)
  local after = R.BuildGuildRecipeIndex()
  check("R1 index empty in guild B", #after == 0, tostring(#after))

  _G.GetGuildInfo = function() return "Angry Murlocs" end
  R.InvalidateGuildRecipeIndex()
  local back = R.BuildGuildRecipeIndex()
  check("R1 return to A restores index", #back == 1 and back[1].crafters[1] == "Alice-Realm")
  _G.GetGuildInfo = function() return "G" end
end

-- R2: owner epoch allows rev1 after SV wipe; older epoch cannot roll back
do
  local scope = AngryMurlocs.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = {},
    recipes = {
      alch = {
        ids = { 1, 2, 3, 4, 5 },
        rev = 5,
        scanAt = 1700000040,
        recvAt = 1700000040,
        complete = true,
        epoch = 100,
      },
    },
  }
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch",
    rev = 1,
    scanAt = 1700000042,
    complete = true,
    epoch = 200,
    ids = { 10, 20, 30, 40, 50, 60 },
  })
  local e = scope.prof.cache["Alice-Realm"].recipes.alch
  check("R2 new epoch rev1 accepted", e and e.rev == 1 and e.epoch == 200 and #e.ids == 6,
    e and (tostring(e.rev) .. " e=" .. tostring(e.epoch) .. " n=" .. tostring(#e.ids)))
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch",
    rev = 5,
    scanAt = 1700000040,
    complete = true,
    epoch = 100,
    ids = { 1, 2, 3, 4, 5 },
  })
  e = scope.prof.cache["Alice-Realm"].recipes.alch
  check("R2 old epoch rejected", e.rev == 1 and e.epoch == 200 and #e.ids == 6)
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch",
    rev = 1,
    scanAt = 1700000050,
    complete = true,
    epoch = 200,
    ids = { 10, 20, 30, 40, 50, 60 },
  })
  e = scope.prof.cache["Alice-Realm"].recipes.alch
  check("R2 identical repeat stable", e.rev == 1 and #e.ids == 6 and e.scanAt == 1700000050)
end

-- R3: confirmed profession drop removes recipe ownership from index + list keys
do
  local scope = AngryMurlocs.Util.GetScopeDB()
  local me = AngryMurlocs.Util.NormalizeName(AngryMurlocs.Util.PlayerName())
  scope.prof.cache[me] = {
    list = {
      { key = "tail", skill = 150, name = "Tailoring" },
      { key = "alch", skill = 1, name = "Alchemy" },
    },
    recipes = {
      tail = { ids = { 2387 }, rev = 1, scanAt = 1, recvAt = 1, complete = true, epoch = 1 },
      alch = { ids = { 2330 }, rev = 1, scanAt = 1, recvAt = 1, complete = true, epoch = 1 },
    },
  }
  -- Drop tail, keep alch
  local newList = { { key = "alch", skill = 1, name = "Alchemy" } }
  scope.prof.cache[me].list = newList
  scope.prof.cache[me].recipes = R.PruneRecipesToProfessionList(scope.prof.cache[me].recipes, newList)
  check("R3 prune removes tail recipes", scope.prof.cache[me].recipes.tail == nil)
  check("R3 prune keeps alch", scope.prof.cache[me].recipes.alch ~= nil)
  local keys = R:ListCompleteProfessionKeys()
  local hasTail, hasAlch = false, false
  for i = 1, #keys do
    if keys[i] == "tail" then hasTail = true end
    if keys[i] == "alch" then hasAlch = true end
  end
  check("R3 list keys no tail", not hasTail)
  check("R3 list keys has alch", hasAlch)

  scope.prof.cache["Alice-Realm"] = {
    list = { { key = "alch", skill = 1, name = "Alchemy" } },
    recipes = {
      tail = { ids = { 2387 }, rev = 2, scanAt = 99, recvAt = 99, complete = true, epoch = 5 },
      alch = { ids = { 2330 }, rev = 1, scanAt = 1, recvAt = 1, complete = true, epoch = 5 },
    },
  }
  R.InvalidateGuildRecipeIndex()
  local idx = R.BuildGuildRecipeIndex()
  local byId = {}
  for i = 1, #idx do byId[idx[i].recipeId] = idx[i] end
  check("R3 index hides dropped tail id", byId[2387] == nil)
  check("R3 index keeps alch id", byId[2330] ~= nil)
  -- Late PROFR for dropped profession rejected
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "tail", rev = 9, scanAt = 200, complete = true, epoch = 9, ids = { 2387 },
  })
  check("R3 late PROFR for dropped prof ignored",
    scope.prof.cache["Alice-Realm"].recipes.tail.rev == 2)
end

print(string.format("%d failures", fails))
if fails > 0 then os.exit(1) end
