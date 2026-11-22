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
check("TestYell off pure", ty == AngryMurlocsLocale["NERGLISH_PURE_LEGEND_1"]
  or (type(ty) == "string" and not ty:find("Oida", 1, true)))
check("style still off", N.GetStyle() == "off")
check("TestYell throttle", N.TestYell(201, true) == nil)
check("TestYell after CD", N.TestYell(200 + N.TEST_CD, true) ~= nil)

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
