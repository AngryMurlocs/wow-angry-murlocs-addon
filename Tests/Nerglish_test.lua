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
AngryMurlocs.db = { ui = { nerglishYell = false } }
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
    return 0.1 -- pick index
  end
end

N.ResetForTest()
ForceHitRandom()
check("disabled TryReact nil", N.TryReact("lvl", 500, { level = 12 }) == nil)
check("disabled TryIdle nil", N.TryIdle(500) == nil)
check("IsEnabled false", N.IsEnabled() == false)

AngryMurlocs.db.ui.nerglishYell = true
check("IsEnabled true", N.IsEnabled() == true)

N.ResetForTest()
yelled = {}
ForceHitRandom()
local text = N.TryReact("lvl", 1000, { level = 12 })
check("lvl hit returns text", type(text) == "string" and text ~= "")
check("yell used YELL", yelled[1] and yelled[1].channel == "YELL")
check("yell text match", yelled[1] and yelled[1].text == text)
check("no placeholder", text and not text:find("{", 1, true))

check("resolve lvl60", N.ResolveKind("lvl", { level = 60 }) == "lvl60")
check("resolve milestone", N.ResolveKind("lvl", { level = 50 }) == "lvl_m")
check("resolve lvl", N.ResolveKind("lvl", { level = 51 }) == "lvl")
check("resolve death_repeat", N.ResolveKind("death", { repeatDeath = true }) == "death_repeat")
check("resolve death", N.ResolveKind("death", {}) == "death")

N.ResetForTest()
ForceHitRandom()
local t60 = N.TryReact("lvl", 2000, { level = 60 })
check("lvl60 pool line", type(t60) == "string")

N.ResetForTest()
ForceHitRandom()
local trep = N.TryReact("death", 3000, { repeatDeath = true })
check("death_repeat line", type(trep) == "string")

-- CD
N.ResetForTest()
ForceHitRandom()
check("first ok", N.TryReact("sight", 4000) ~= nil)
ForceHitRandom()
check("cd blocks", N.TryReact("sight", 4100) == nil)
ForceHitRandom()
check("after cd", N.TryReact("sight", 4000 + N.GLOBAL_CD) ~= nil)

-- Hour cap
N.ResetForTest()
ForceHitRandom()
local t0 = 50000
for i = 1, N.MAX_PER_HOUR do
  ForceHitRandom()
  check("hour " .. i, N.TryReact("pvp", t0 + i * N.GLOBAL_CD) ~= nil)
end
ForceHitRandom()
check("hour cap", N.TryReact("pvp", t0 + (N.MAX_PER_HOUR + 1) * N.GLOBAL_CD) == nil)

-- Chance miss
N.ResetForTest()
N._Random = function() return 0.99 end
check("chance miss", N.TryReact("loot", 60000) == nil)

-- Legend roll
N.ResetForTest()
yelled = {}
local s = 0
N._Random = function()
  s = s + 1
  if s == 1 then return 0 end -- chance
  if s == 2 then return 0 end -- legend
  return 0.05
end
local leg = N.TryReact("guild_join", 70000)
check("legend hit", type(leg) == "string")
check("legend is legend pool", leg == AngryMurlocsLocale["NERGLISH_LEGEND_1"]
  or (type(leg) == "string" and leg:find("MRRR", 1, true)))

-- Idle
N.ResetForTest()
ForceHitRandom()
-- ForceHitRandom: step1 chance, step2 skip legend, step3 index — idle needs extra random for sub-pool
s = 0
N._Random = function()
  s = s + 1
  if s == 1 then return 0 end -- chance
  if s == 2 then return 0.99 end -- no legend
  if s == 3 then return 0 end -- idle_hunger
  return 0.1
end
local idle = N.TryIdle(80000)
check("idle hit", type(idle) == "string")

-- TestYell: bypass anti-spam, 2s throttle
N.ResetForTest()
yelled = {}
N._Random = function() return 0 end
local ty = N.TestYell(90000)
check("TestYell text", type(ty) == "string" and ty ~= "")
check("TestYell YELL", yelled[1] and yelled[1].channel == "YELL")
check("TestYell throttle", N.TestYell(90001) == nil)
check("TestYell after CD", N.TestYell(90000 + N.TEST_CD) ~= nil)

-- Pool completeness
local missing = 0
local function CheckPool(kind)
  local size = N.POOL_SIZE[kind]
  local prefix = N.PREFIX[kind]
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
for _, k in ipairs(kinds) do CheckPool(k) end

_G.GetLocale = function() return "deDE" end
assert(loadfile("Localization/nerglish/deDE.lua"))()
for _, k in ipairs(kinds) do CheckPool(k) end

local total = 0
for _, k in ipairs(kinds) do total = total + N.POOL_SIZE[k] end
check("120 lines mapped", total == 120, tostring(total))
check("all pools en+de", missing == 0, tostring(missing))

print(tostring(failures) .. " failures")
os.exit(failures == 0 and 0 or 1)
