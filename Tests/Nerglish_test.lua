-- From repo root: luajit Tests/Nerglish_test.lua
math.randomseed(1)

local yelled = {}
_G.C_ChatInfo = {
  SendChatMessage = function(text, channel)
    yelled[#yelled + 1] = { text = text, channel = channel }
    return true
  end,
}
-- Default: instance so legacy TryReact cases keep immediate SendChatMessage.
_G.IsInInstance = function() return true, "party" end

assert(loadfile("Localization/enUS.lua"))()
assert(loadfile("Localization/nerglish/enUS.lua"))()
AngryMurlocs = AngryMurlocs or {}
AngryMurlocs.db = { ui = { nerglishStyle = "off" } }
dofile("Core/Util.lua")
dofile("Core/Nerglish.lua")

local N = AngryMurlocs.Nerglish
assert(N)

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("OK  " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. (detail and (" — " .. detail) or ""))
  end
end

local function ForceHitRandom()
  local step = 0
  N._Random = function()
    step = step + 1
    if step == 1 then return 0 end -- pass chance
    if step == 2 then return 0.99 end -- skip legend
    return 0.1
  end
end

local function MigrateCase(ui, expect)
  local db = { ui = ui }
  N.MigrateUi(db)
  check("migrate " .. expect, db.ui.nerglishStyle == expect and db.ui.nerglishYell == nil, tostring(db.ui.nerglishStyle))
end
MigrateCase({}, "off")
MigrateCase({ nerglishYell = false }, "off")
MigrateCase({ nerglishYell = true }, "schmaeh")
MigrateCase({ nerglishStyle = "nerglish", nerglishYell = false }, "nerglish")
MigrateCase({ nerglishStyle = "schmaeh", nerglishYell = true }, "schmaeh")
MigrateCase({ nerglishStyle = "off", nerglishYell = true }, "off")
MigrateCase({ nerglishStyle = "bogus", nerglishYell = true }, "off")

AngryMurlocs.db = { ui = { nerglishStyle = "off" } }
N.ResetForTest()
ForceHitRandom()
check("off TryReact", N.TryReact("lvl", 100, { level = 12 }) == nil)
check("off TryIdle", N.TryIdle(100) == nil)
check("IsEnabled off", N.IsEnabled() == false)

yelled = {}
N._Random = function() return 0 end
-- fromInput=true: same path as Options button / keybind (immediate even outdoors).
local ty = N.TestYell(200, true)
check("TestYell off text", type(ty) == "string" and ty ~= "")
check("TestYell off YELL", yelled[1] and yelled[1].channel == "YELL")
-- Off previews nerglish; shuffle-bag may draw any pure pool (not only legend).
check("TestYell off pure", type(ty) == "string" and not ty:find("Oida", 1, true)
  and not ty:find("Teamfähig", 1, true), tostring(ty))
check("style still off", N.GetStyle() == "off")
check("TestYell throttle", N.TestYell(201, true) == nil)
check("TestYell after CD", N.TestYell(200 + N.TEST_CD, true) ~= nil)

-- Shuffle-bag: many TestYell draws can leave legend pool (not only legends).
AngryMurlocs.db.ui.nerglishStyle = "schmaeh"
N.ResetForTest()
N._Random = function() return 0.37 end
local seenKinds = {}
local legendOnly = true
for i = 1, 40 do
  local t = N.TestYell(10000 + i * N.TEST_CD, true)
  check("TestYell bag " .. i, type(t) == "string" and t ~= "")
  if type(t) == "string" then
    local isLegend = false
    for li = 1, 12 do
      if t == AngryMurlocsLocale["NERGLISH_LEGEND_" .. li]
        or t == AngryMurlocsLocaleEN["NERGLISH_LEGEND_" .. li] then
        isLegend = true
        break
      end
    end
    if not isLegend then legendOnly = false end
    seenKinds[#seenKinds + 1] = t
  end
end
check("TestYell bag not legend-only", legendOnly == false)
local uniq = {}
for _, t in ipairs(seenKinds) do uniq[t] = true end
local uniqN = 0
for _ in pairs(uniq) do uniqN = uniqN + 1 end
check("TestYell bag variety", uniqN >= 10, tostring(uniqN))

AngryMurlocs.db.ui.nerglishStyle = "schmaeh"
N.ResetForTest()
yelled = {}
ForceHitRandom()
local text = N.TryReact("lvl", 1000, { level = 12 })
check("schmaeh hit", type(text) == "string" and text ~= "")
check("schmaeh YELL", yelled[1] and yelled[1].channel == "YELL")
check("schmaeh not key", text ~= "NERGLISH_LVL_1")
check("schmaeh no brace", text and not text:find("{", 1, true))

AngryMurlocs.db.ui.nerglishStyle = "nerglish"
N.ResetForTest()
yelled = {}
ForceHitRandom()
local pure = N.TryReact("lvl", 2000, { level = 12 })
check("nerglish hit", type(pure) == "string" and pure ~= "")
check("nerglish gurgle", pure and (pure:find("Mrr", 1, true) or pure:find("Grgl", 1, true) or pure:find("Blub", 1, true)), tostring(pure))

AngryMurlocs.db.ui.nerglishStyle = "schmaeh"
N.ResetForTest()
ForceHitRandom()
check("schmaeh first", N.TryReact("sight", 3000) ~= nil)
AngryMurlocs.db.ui.nerglishStyle = "nerglish"
ForceHitRandom()
check("nerglish blocked by shared CD", N.TryReact("sight", 3100) == nil)
ForceHitRandom()
check("after CD ok", N.TryReact("sight", 3000 + N.GLOBAL_CD) ~= nil)

N.ResetForTest()
local t0 = 40000
for i = 1, N.MAX_PER_HOUR do
  AngryMurlocs.db.ui.nerglishStyle = (i % 2 == 0) and "nerglish" or "schmaeh"
  ForceHitRandom()
  check("hour mix " .. i, N.TryReact("pvp", t0 + i * N.GLOBAL_CD) ~= nil)
end
ForceHitRandom()
check("hour cap mixed", N.TryReact("pvp", t0 + (N.MAX_PER_HOUR + 1) * N.GLOBAL_CD) == nil)

N.ResetForTest()
for i = 1, N.MAX_PER_HOUR do
  AngryMurlocs.db.ui.nerglishStyle = "nerglish"
  ForceHitRandom()
  N.TryReact("loot", 50000 + i * N.GLOBAL_CD)
end
AngryMurlocs.db.ui.nerglishStyle = "off"
N._Random = function() return 0 end
check("TestYell under hour cap", type(N.TestYell(60000, true)) == "string")
ForceHitRandom()
check("auto still capped", N.TryReact("loot", 50000 + (N.MAX_PER_HOUR + 2) * N.GLOBAL_CD) == nil)

-- Outdoor HW pending: A then B → no sends → flush once sends B → second flush nothing.
_G.IsInInstance = function() return false, "none" end
AngryMurlocs.db.ui.nerglishStyle = "nerglish"
N.ResetForTest()
yelled = {}
N.Yell("A", false, 1000)
N.Yell("B", false, 1001)
check("outdoor A then B no send", #yelled == 0)
check("outdoor pending set", N.HasPendingYell() == true)
check("flush sends only B", N.FlushPendingYell(1002) == true and #yelled == 1 and yelled[1].text == "B")
check("second flush nothing", N.FlushPendingYell(1003) == false and #yelled == 1)
check("pending cleared", N.HasPendingYell() == false)

-- Instance: immediate send, no pending.
_G.IsInInstance = function() return true, "party" end
N.ResetForTest()
yelled = {}
check("instance yell now", N.Yell("INST", false, 2000) == true and #yelled == 1 and yelled[1].text == "INST")
check("instance no pending", N.HasPendingYell() == false)

-- Outdoor pending dropped when style set to Off before input.
_G.IsInInstance = function() return false, "none" end
AngryMurlocs.db.ui.nerglishStyle = "schmaeh"
N.ResetForTest()
yelled = {}
N.Yell("DROP", false, 3000)
check("pending before off", N.HasPendingYell() == true)
N.SetStyle("off")
check("pending cleared by off", N.HasPendingYell() == false)
check("flush after off silent", N.FlushPendingYell(3001) == false and #yelled == 0)

-- TTL expiry before flush.
AngryMurlocs.db.ui.nerglishStyle = "nerglish"
N.ResetForTest()
yelled = {}
N.Yell("OLD", false, 4000)
check("ttl expire", N.FlushPendingYell(4000 + N.PENDING_TTL + 1) == false and #yelled == 0)
check("ttl cleared", N.HasPendingYell() == false)

-- Restore instance default for remaining suite.
_G.IsInInstance = function() return true, "party" end

check("resolve lvl60", N.ResolveKind("lvl", { level = 60 }) == "lvl60")
check("resolve milestone", N.ResolveKind("lvl", { level = 50 }) == "lvl_m")
check("resolve death_repeat", N.ResolveKind("death", { repeatDeath = true }) == "death_repeat")

local missing = 0
local function CheckPool(prefixMap, kind)
  local size = N.POOL_SIZE[kind]
  local prefix = prefixMap[kind]
  for i = 1, size do
    local key = prefix .. tostring(i)
    local v = AngryMurlocsLocale[key]
    if type(v) ~= "string" or v == "" or v:find("{", 1, true) then
      missing = missing + 1
      print("FAIL pool " .. key)
    end
  end
end

local kinds = {
  "lvl", "lvl_m", "lvl60", "death", "death_repeat", "sight", "wanted_kill",
  "pvp", "guild_join", "loot", "achievement", "guild_goal",
  "idle_hunger", "idle_schmaeh", "idle_dumb", "idle_lazy", "legend",
}
for _, k in ipairs(kinds) do CheckPool(N.PREFIX_SCHMAEH, k) end
for _, k in ipairs(kinds) do CheckPool(N.PREFIX_PURE, k) end

local pureEn = {}
for _, k in ipairs(kinds) do
  local prefix = N.PREFIX_PURE[k]
  for i = 1, N.POOL_SIZE[k] do
    pureEn[prefix .. i] = AngryMurlocsLocale[prefix .. i]
  end
end

_G.GetLocale = function() return "deDE" end
assert(loadfile("Localization/deDE.lua"))()
assert(loadfile("Localization/nerglish/deDE.lua"))()
local pureMismatch = 0
for key, enVal in pairs(pureEn) do
  if AngryMurlocsLocale[key] ~= enVal then
    pureMismatch = pureMismatch + 1
    print("FAIL pure de!=en " .. key)
  end
end
local schmaehDe = AngryMurlocsLocale["NERGLISH_LVL_1"]
local schmaehEn = AngryMurlocsLocaleEN["NERGLISH_LVL_1"]
check("schmaeh de localized", type(schmaehDe) == "string" and schmaehDe ~= schmaehEn)

local total = 0
for _, k in ipairs(kinds) do total = total + N.POOL_SIZE[k] end
check("120 lines per style", total == 120, tostring(total))
check("all pools ok", missing == 0, tostring(missing))
check("pure en==de", pureMismatch == 0, tostring(pureMismatch))
check("no AT catalog", AngryMurlocsNerglishATCatalog == nil)

-- Keybind UI globals (set by locales; Bindings.xml wires the action in-game)
check("BINDING_HEADER en", type(BINDING_HEADER_ANGRYMURLOCS) == "string" and BINDING_HEADER_ANGRYMURLOCS ~= "")
check("BINDING_NAME de", BINDING_NAME_ANGRYMURLOCS_TEST_YELL == "Öffentlich testen (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_TEST_YELL))
check("BINDING_CYCLE de", type(BINDING_NAME_ANGRYMURLOCS_CYCLE_STYLE) == "string" and BINDING_NAME_ANGRYMURLOCS_CYCLE_STYLE:find("Schmäh", 1, true), tostring(BINDING_NAME_ANGRYMURLOCS_CYCLE_STYLE))
local bf = io.open("Bindings.xml", "rb")
local bxml = bf and bf:read("*a") or ""
if bf then bf:close() end
check("Bindings.xml present", bxml:find("ANGRYMURLOCS_TEST_YELL", 1, true) and bxml:find("TestYell", 1, true))
check("Bindings.xml fromInput", bxml:find("TestYell(nil, true)", 1, true) ~= nil)
check("Bindings.xml cycle", bxml:find("ANGRYMURLOCS_CYCLE_STYLE", 1, true) and bxml:find("CycleStyle", 1, true))
local headerCount = 0
for _ in bxml:gmatch('header%s*=%s*"ANGRYMURLOCS"') do
  headerCount = headerCount + 1
end
check("Bindings.xml header once", headerCount == 1, tostring(headerCount))
local toc = io.open("AngryMurlocs.toc", "rb")
local tocText = toc and toc:read("*a") or ""
if toc then toc:close() end
local tocListsBindings = false
for line in tocText:gmatch("[^\r\n]+") do
  if not line:match("^%s*#") and line:find("Bindings%.xml", 1) then
    tocListsBindings = true
    break
  end
end
check("TOC omits Bindings.xml", not tocListsBindings)
local jokeBindNames = {
  "ANGRYMURLOCS_JOKE_AUTO",
  "ANGRYMURLOCS_JOKE_RAID",
  "ANGRYMURLOCS_JOKE_DUNGEON",
  "ANGRYMURLOCS_JOKE_WORLD",
  "ANGRYMURLOCS_JOKE_INN",
  "ANGRYMURLOCS_JOKE_TOWN",
}
local jokeBindCats = { "auto", "raid", "dungeon", "world", "inn", "town" }
for i, bn in ipairs(jokeBindNames) do
  local cat = jokeBindCats[i]
  check("Bindings.xml " .. bn, bxml:find(bn, 1, true)
    and bxml:find('JokeYell(nil, true, "' .. cat .. '")', 1, true) ~= nil)
end
check("Bindings.xml no legacy JOKE_YELL", bxml:find("ANGRYMURLOCS_JOKE_YELL", 1, true) == nil)
check("Bindings.xml AZEROTH_AUTO", bxml:find("ANGRYMURLOCS_AZEROTH_AUTO", 1, true)
  and bxml:find("AzerothJokeYell(nil, true)", 1, true) ~= nil)

-- Joke pool 1..100 present in active locale (deDE after load above) and EN copy.
local jokeMissing = 0
for i = 1, N.JOKE_POOL_SIZE do
  local key = N.JOKE_PREFIX .. tostring(i)
  local de = AngryMurlocsLocale[key]
  local en = AngryMurlocsLocaleEN[key]
  if type(de) ~= "string" or de == "" or de:find("{", 1, true) then
    jokeMissing = jokeMissing + 1
    print("FAIL joke de " .. key)
  end
  if type(en) ~= "string" or en == "" or en:find("{", 1, true) then
    jokeMissing = jokeMissing + 1
    print("FAIL joke en " .. key)
  end
end
check("joke pool size", N.JOKE_POOL_SIZE == 100)
check("joke pool ok", jokeMissing == 0, tostring(jokeMissing))

-- Category partition: sum 100, disjoint, valid ids 1..100.
local seenJoke = {}
local catSum = 0
local catDup = 0
local catBad = 0
for _, cat in ipairs(N.JOKE_CATEGORY_IDS) do
  local ids = N.JOKE_CATEGORIES[cat]
  check("joke cat " .. cat, type(ids) == "table" and #ids > 0)
  if type(ids) == "table" then
    catSum = catSum + #ids
    for _, idx in ipairs(ids) do
      if type(idx) ~= "number" or idx < 1 or idx > N.JOKE_POOL_SIZE then
        catBad = catBad + 1
      elseif seenJoke[idx] then
        catDup = catDup + 1
      else
        seenJoke[idx] = cat
      end
    end
  end
end
check("joke cats sum 100", catSum == 100, tostring(catSum))
check("joke cats no dup", catDup == 0, tostring(catDup))
check("joke cats ids ok", catBad == 0, tostring(catBad))
local missingCat = 0
for i = 1, N.JOKE_POOL_SIZE do
  if not seenJoke[i] then missingCat = missingCat + 1 end
end
check("joke cats cover all", missingCat == 0, tostring(missingCat))

check("BINDING_JOKE_AUTO de", BINDING_NAME_ANGRYMURLOCS_JOKE_AUTO == "Schmäh · Auto (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_JOKE_AUTO))
check("BINDING_AZEROTH_AUTO de", BINDING_NAME_ANGRYMURLOCS_AZEROTH_AUTO == "Schmäh · Azeroth Auto (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_AZEROTH_AUTO))
check("BINDING_JOKE_RAID de", BINDING_NAME_ANGRYMURLOCS_JOKE_RAID == "Schmäh · Raid (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_JOKE_RAID))
check("BINDING_JOKE_DUNGEON de", BINDING_NAME_ANGRYMURLOCS_JOKE_DUNGEON == "Schmäh · Dungeon (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_JOKE_DUNGEON))
check("BINDING_JOKE_WORLD de", BINDING_NAME_ANGRYMURLOCS_JOKE_WORLD == "Schmäh · Open World (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_JOKE_WORLD))
check("BINDING_JOKE_INN de", BINDING_NAME_ANGRYMURLOCS_JOKE_INN == "Schmäh · Gasthaus (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_JOKE_INN))
check("BINDING_JOKE_TOWN de", BINDING_NAME_ANGRYMURLOCS_JOKE_TOWN == "Schmäh · Stadt & Alltag (/y)", tostring(BINDING_NAME_ANGRYMURLOCS_JOKE_TOWN))

-- Dungeon wording tweaks (#95 Tank, #99 Gruppenleiter).
local j95 = AngryMurlocsLocale["NERGLISH_JOKE_95"]
local j99 = AngryMurlocsLocale["NERGLISH_JOKE_99"]
check("joke 95 Tank", type(j95) == "string" and j95:find("Tank", 1, true) and not j95:find("Main-Tank", 1, true), tostring(j95))
check("joke 99 Gruppenleiter", type(j99) == "string" and j99:find("Gruppenleiter", 1, true) and not j99:find("Raidlead", 1, true), tostring(j99))
check("joke 95 EN tank", type(AngryMurlocsLocaleEN["NERGLISH_JOKE_95"]) == "string"
  and AngryMurlocsLocaleEN["NERGLISH_JOKE_95"]:find("tank", 1, true)
  and not AngryMurlocsLocaleEN["NERGLISH_JOKE_95"]:find("main tank", 1, true))
check("joke 99 EN group leader", type(AngryMurlocsLocaleEN["NERGLISH_JOKE_99"]) == "string"
  and AngryMurlocsLocaleEN["NERGLISH_JOKE_99"]:find("group leader", 1, true))

-- ResolveJokeCategory priority: raid > dungeon > inn > town > world.
local savedIsInInstance = _G.IsInInstance
local savedIsResting = _G.IsResting
local savedCMap = _G.C_Map
_G.IsResting = function() return false end
_G.C_Map = {
  GetBestMapForUnit = function() return 1 end,
  IsCityMap = function() return false end,
}
_G.IsInInstance = function() return true, "raid" end
check("resolve raid", N.ResolveJokeCategory() == "raid")
_G.IsInInstance = function() return true, "party" end
check("resolve dungeon", N.ResolveJokeCategory() == "dungeon")
_G.IsInInstance = function() return false, "none" end
_G.IsResting = function() return true end
check("resolve inn", N.ResolveJokeCategory() == "inn")
_G.IsResting = function() return false end
_G.C_Map.IsCityMap = function() return true end
check("resolve town", N.ResolveJokeCategory() == "town")
_G.C_Map.IsCityMap = function() return false end
check("resolve world", N.ResolveJokeCategory() == "world")
-- Resting beats city map.
_G.IsResting = function() return true end
_G.C_Map.IsCityMap = function() return true end
check("resolve resting over city", N.ResolveJokeCategory() == "inn")
_G.IsInInstance = savedIsInInstance
_G.IsResting = savedIsResting
_G.C_Map = savedCMap

-- JokeYell(category): style off ok; shared throttle; stays in category texts.
AngryMurlocs.db.ui.nerglishStyle = "off"
N.ResetForTest()
yelled = {}
N._Random = function() return 0.41 end
check("JokeYell needs category", N.JokeYell(90000, true) == nil)
local j1 = N.JokeYell(90000, true, "dungeon")
check("JokeYell dungeon text", type(j1) == "string" and j1 ~= "")
check("JokeYell dungeon YELL", yelled[1] and yelled[1].channel == "YELL")
-- Drawn line must belong to dungeon set.
local dungeonSet = {}
for _, idx in ipairs(N.JOKE_CATEGORIES.dungeon) do
  dungeonSet[AngryMurlocsLocale[N.JOKE_PREFIX .. idx]] = true
  dungeonSet[AngryMurlocsLocaleEN[N.JOKE_PREFIX .. idx]] = true
end
check("JokeYell dungeon in pool", dungeonSet[j1] == true, tostring(j1))
check("JokeYell shared throttle", N.JokeYell(90001, true, "raid") == nil)
local j2 = N.JokeYell(90000 + N.TEST_CD, true, "dungeon")
check("JokeYell after CD", type(j2) == "string" and j2 ~= "")
check("JokeYell bag distinct", j1 ~= j2, tostring(j1) .. " | " .. tostring(j2))
check("JokeYell dungeon2 in pool", dungeonSet[j2] == true, tostring(j2))
-- Independent of TestYell throttle.
check("JokeYell vs TestYell throttle", type(N.TestYell(90000 + N.TEST_CD, true)) == "string")

-- JokeYell auto uses ResolveJokeCategory pool (raid instance → raid jokes).
N.ResetForTest()
yelled = {}
_G.IsInInstance = function() return true, "raid" end
_G.IsResting = function() return false end
_G.C_Map = {
  GetBestMapForUnit = function() return 1 end,
  IsCityMap = function() return false end,
}
N._Random = function() return 0.41 end
local ja = N.JokeYell(95000, true, "auto")
local raidSet = {}
for _, idx in ipairs(N.JOKE_CATEGORIES.raid) do
  raidSet[AngryMurlocsLocale[N.JOKE_PREFIX .. idx]] = true
  raidSet[AngryMurlocsLocaleEN[N.JOKE_PREFIX .. idx]] = true
end
check("JokeYell auto raid text", type(ja) == "string" and raidSet[ja] == true, tostring(ja))
_G.IsInInstance = savedIsInInstance
_G.IsResting = savedIsResting
_G.C_Map = savedCMap

-- Azeroth pack 1..100 + contiguous categories + Auto yell.
local azMissing = 0
for i = 1, N.AZEROTH_POOL_SIZE do
  local key = N.AZEROTH_PREFIX .. tostring(i)
  local de = AngryMurlocsLocale[key]
  local en = AngryMurlocsLocaleEN[key]
  if type(de) ~= "string" or de == "" or de:find("{", 1, true) then
    azMissing = azMissing + 1
    print("FAIL azeroth de " .. key)
  end
  if type(en) ~= "string" or en == "" or en:find("{", 1, true) then
    azMissing = azMissing + 1
    print("FAIL azeroth en " .. key)
  end
end
check("azeroth pool size", N.AZEROTH_POOL_SIZE == 100)
check("azeroth pool ok", azMissing == 0, tostring(azMissing))
local seenAz = {}
local azSum = 0
local azDup = 0
local azBad = 0
for _, cat in ipairs(N.JOKE_CATEGORY_IDS) do
  local ids = N.AZEROTH_CATEGORIES[cat]
  check("azeroth cat " .. cat, type(ids) == "table" and #ids > 0)
  if type(ids) == "table" then
    azSum = azSum + #ids
    for _, idx in ipairs(ids) do
      if type(idx) ~= "number" or idx < 1 or idx > N.AZEROTH_POOL_SIZE then
        azBad = azBad + 1
      elseif seenAz[idx] then
        azDup = azDup + 1
      else
        seenAz[idx] = cat
      end
    end
  end
end
check("azeroth cats sum 100", azSum == 100, tostring(azSum))
check("azeroth cats no dup", azDup == 0, tostring(azDup))
check("azeroth cats ids ok", azBad == 0, tostring(azBad))
local azMissCat = 0
for i = 1, N.AZEROTH_POOL_SIZE do
  if not seenAz[i] then azMissCat = azMissCat + 1 end
end
check("azeroth cats cover all", azMissCat == 0, tostring(azMissCat))
check("azeroth raid range", #N.AZEROTH_CATEGORIES.raid == 20 and N.AZEROTH_CATEGORIES.raid[1] == 1
  and N.AZEROTH_CATEGORIES.raid[20] == 20)
check("azeroth dungeon range", #N.AZEROTH_CATEGORIES.dungeon == 20 and N.AZEROTH_CATEGORIES.dungeon[1] == 21
  and N.AZEROTH_CATEGORIES.dungeon[20] == 40)

N.ResetForTest()
yelled = {}
_G.IsInInstance = function() return true, "raid" end
_G.IsResting = function() return false end
_G.C_Map = {
  GetBestMapForUnit = function() return 1 end,
  IsCityMap = function() return false end,
}
N._Random = function() return 0.41 end
local az1 = N.AzerothJokeYell(96000, true)
local azRaidSet = {}
for _, idx in ipairs(N.AZEROTH_CATEGORIES.raid) do
  azRaidSet[AngryMurlocsLocale[N.AZEROTH_PREFIX .. idx]] = true
  azRaidSet[AngryMurlocsLocaleEN[N.AZEROTH_PREFIX .. idx]] = true
end
check("AzerothJokeYell raid text", type(az1) == "string" and azRaidSet[az1] == true, tostring(az1))
check("AzerothJokeYell shared throttle", N.AzerothJokeYell(96001, true) == nil)
check("Azeroth vs Wiener shared throttle", N.JokeYell(96001, true, "raid") == nil)
local az2 = N.AzerothJokeYell(96000 + N.TEST_CD, true)
check("AzerothJokeYell after CD", type(az2) == "string" and azRaidSet[az2] == true, tostring(az2))
_G.IsInInstance = savedIsInInstance
_G.IsResting = savedIsResting
_G.C_Map = savedCMap

-- CycleStyle off → nerglish → schmaeh → off
AngryMurlocs.db = { ui = { nerglishStyle = "off" } }
local printed = {}
AngryMurlocs.Util.Print = function(msg) printed[#printed + 1] = msg end
check("cycle to nerglish", N.CycleStyle() == "nerglish")
check("cycle to schmaeh", N.CycleStyle() == "schmaeh")
check("cycle to off", N.CycleStyle() == "off")
check("cycle chat feedback", #printed == 3 and type(printed[1]) == "string")

print(tostring(failures) .. " failures")
os.exit(failures == 0 and 0 or 1)
