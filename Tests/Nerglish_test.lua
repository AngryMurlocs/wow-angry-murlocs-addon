-- From repo root: luajit Tests/Nerglish_test.lua
math.randomseed(1)

local yelled = {}
_G.C_ChatInfo = {
  SendChatMessage = function(text, channel)
    yelled[#yelled + 1] = { text = text, channel = channel }
    return true
  end,
}

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
local ty = N.TestYell(200)
check("TestYell off text", type(ty) == "string" and ty ~= "")
check("TestYell off YELL", yelled[1] and yelled[1].channel == "YELL")
check("TestYell off pure", ty == AngryMurlocsLocale["NERGLISH_PURE_LEGEND_1"]
  or (type(ty) == "string" and not ty:find("Oida", 1, true)))
check("style still off", N.GetStyle() == "off")
check("TestYell throttle", N.TestYell(201) == nil)
check("TestYell after CD", N.TestYell(200 + N.TEST_CD) ~= nil)

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
check("TestYell under hour cap", type(N.TestYell(60000)) == "string")
ForceHitRandom()
check("auto still capped", N.TryReact("loot", 50000 + (N.MAX_PER_HOUR + 2) * N.GLOBAL_CD) == nil)

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

print(tostring(failures) .. " failures")
os.exit(failures == 0 and 0 or 1)
