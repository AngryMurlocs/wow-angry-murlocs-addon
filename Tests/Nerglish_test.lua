-- From repo root: luajit Tests/Nerglish_test.lua
_G.GetLocale = function() return "enUS" end
assert(loadfile("Localization/enUS.lua"))()
assert(loadfile("Localization/nerglish/enUS.lua"))()

AngryMurlocs = AngryMurlocs or {}
AngryMurlocs.Util = AngryMurlocs.Util or {}
function AngryMurlocs.Util.L(key)
  local locale = AngryMurlocsLocale
  if locale and locale[key] ~= nil then return locale[key] end
  local en = AngryMurlocsLocaleEN
  if en and en[key] ~= nil then return en[key] end
  return key
end

AngryMurlocs.db = { ui = { nerglishStyle = "off" } }
dofile("Core/Nerglish.lua")

local N = AngryMurlocs.Nerglish
local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or ""))
  end
end

local function RandAlwaysZero()
  N._Random = function() return 0 end
end

local function Tokens(s)
  local t = {}
  for k in tostring(s):gmatch("{(%w+)}") do t[k] = true end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return table.concat(keys, ",")
end

N.ResetForTest()
check("off returns nil", N.TryReact({ kind = "lvl", player = "Alice", level = 60 }, 1000) == nil)

AngryMurlocs.db.ui.nerglishStyle = "subtle"
RandAlwaysZero()
N.ResetForTest()
local r = N.TryReact({ kind = "lvl", player = "Alice", level = 61 }, 1000)
check("subtle lvl hit", r and r.text == "Mrrgl! Alice reached level 61.", r and r.text)

N.ResetForTest()
r = N.TryReact({ kind = "lvl", player = "Bob", level = 50 }, 1000)
check("milestone pool at 50", r and r.text:find("Milestone", 1, true) ~= nil, r and r.text)

N.ResetForTest()
r = N.TryReact({ kind = "death", victim = "Carol", zone = "Elwynn" }, 1000)
check("death subtle", r and r.text == "Mrrgl… Carol has fallen (Elwynn).", r and r.text)

N.ResetForTest()
r = N.TryReact({ kind = "sight" }, 1000)
check("sight cry", r and r.cry == "Mrrgl!", r and r.cry)

N.ResetForTest()
check("missing player nil", N.TryReact({ kind = "lvl", player = "?", level = 10 }, 1000) == nil)
check("bad level nil", N.TryReact({ kind = "lvl", player = "Alice", level = 0 }, 1000) == nil)
check("empty zone nil for normal death", N.TryReact({ kind = "death", victim = "Carol", zone = "" }, 1000) == nil)

N.ResetForTest()
N._Random = function() return 0.99 end
check("chance miss", N.TryReact({ kind = "lvl", player = "Alice", level = 12 }, 1000) == nil)

AngryMurlocs.db.ui.nerglishStyle = "playful"
RandAlwaysZero()
N.ResetForTest()
check("first playful hit", N.TryReact({ kind = "lvl", player = "Alice", level = 12 }, 1000) ~= nil)
check("global CD blocks", N.TryReact({ kind = "lvl", player = "Bob", level = 13 }, 1100) == nil)
check("after CD ok", N.TryReact({ kind = "lvl", player = "Bob", level = 13 }, 1000 + N.GLOBAL_CD) ~= nil)

N.ResetForTest()
local t0 = 10000
for i = 1, N.MAX_PER_HOUR do
  check("hour fill " .. i, N.TryReact({ kind = "sight" }, t0 + i * N.GLOBAL_CD) ~= nil)
end
check("hour cap blocks", N.TryReact({ kind = "sight" }, t0 + (N.MAX_PER_HOUR + 1) * N.GLOBAL_CD) == nil)

N.ResetForTest()
check("preview1", N.TryReact({ kind = "lvl", player = "Alice", level = 12, preview = true }, 20000) ~= nil)
check("preview2 no CD", N.TryReact({ kind = "lvl", player = "Bob", level = 13, preview = true }, 20001) ~= nil)
check("live after preview", N.TryReact({ kind = "lvl", player = "Dan", level = 14 }, 20002) ~= nil)

N.ResetForTest()
RandAlwaysZero()
local c1 = N.TryReact({ kind = "sight" }, 40000)
local c2 = N.TryReact({ kind = "sight" }, 40000 + N.GLOBAL_CD)
check("no immediate same cry", c1 and c2 and c1.cry ~= c2.cry)

check("normalize junk", N.Normalize("nope") == "off")
check("Sanitize strips color", N.Sanitize("|cffff0000X|r") == "X")
check("Sanitize empty nil", N.Sanitize("|cffffffff|r") == nil)

local alert = string.format(AngryMurlocs.Util.L("WANTED_SIGHT_ALERT"), "Charly", "Westfall", "Dave")
N.ResetForTest()
AngryMurlocs.db.ui.nerglishStyle = "playful"
RandAlwaysZero()
local sight = N.TryReact({ kind = "sight" }, 50000)
local line = (sight and sight.cry or "") .. " " .. alert
check("wanted keeps alert", line:find("Wanted sighting: Charly near Westfall", 1, true) ~= nil)
check("wanted has cry", line:find("MRRRRGL!", 1, true) == 1)

check("Fill order", N.Fill("Level {level} for {player}!", { player = "A", level = 5 }) == "Level 5 for A!")
check("Fill missing nil", N.Fill("Hi {player}", {}) == nil)

-- Sanitize in TryReact
N.ResetForTest()
RandAlwaysZero()
local san = N.TryReact({ kind = "lvl", player = "|cff00ff00Alice|r", level = 12 }, 55000)
check("sanitized name in text", san and san.text:find("Alice", 1, true) and not san.text:find("|", 1, true), san and san.text)

-- Rarity rare / legend
AngryMurlocs.db.ui.nerglishStyle = "playful"
N.ResetForTest()
do
  local seq = { 0.0, 0.85, 0.0 }
  local i = 0
  N._Random = function() i = i + 1; return seq[i] or 0 end
  local rare = N.TryReact({ kind = "lvl", player = "Alice", level = 12 }, 60000)
  check("playful rare", rare and rare.text:find("fish as a reward", 1, true) ~= nil, rare and rare.text)
end

N.ResetForTest()
do
  local seq = { 0.0, 0.98, 0.0 }
  local i = 0
  N._Random = function() i = i + 1; return seq[i] or 0 end
  local leg = N.TryReact({ kind = "lvl", player = "Alice", level = 12 }, 70000)
  check("playful legend mixed case", leg and leg.text:find("can't stop dancing", 1, true) ~= nil, leg and leg.text)
  check("legend not all caps body", leg and leg.text:find("IS LEVEL", 1, true) == nil, leg and leg.text)
end

AngryMurlocs.db.ui.nerglishStyle = "subtle"
N.ResetForTest()
do
  local seq = { 0.0, 0.99, 0.0 }
  local i = 0
  N._Random = function() i = i + 1; return seq[i] or 0 end
  local s = N.TryReact({ kind = "lvl", player = "Alice", level = 12 }, 80000)
  check("subtle never legend", s and s.text:find("can't stop dancing", 1, true) == nil, s and s.text)
  check("subtle rare short pool", s and s.text:find("fish as a reward", 1, true) ~= nil, s and s.text)
end

-- Missing rare key => fallback normal
AngryMurlocs.db.ui.nerglishStyle = "playful"
N.ResetForTest()
do
  local saved = AngryMurlocsLocale["NERGLISH_LVL_RARE_01"]
  AngryMurlocsLocale["NERGLISH_LVL_RARE_01"] = nil
  if AngryMurlocsLocaleEN then AngryMurlocsLocaleEN["NERGLISH_LVL_RARE_01"] = nil end
  local seq = { 0.0, 0.85, 0.0, 0.0 } -- rare pick fails, then normal pick
  local i = 0
  N._Random = function() i = i + 1; return seq[i] or 0 end
  local fb = N.TryReact({ kind = "lvl", player = "Alice", level = 12 }, 85000)
  check("missing rare falls back normal", fb and fb.text:find("hits level 12", 1, true) ~= nil, fb and fb.text)
  AngryMurlocsLocale["NERGLISH_LVL_RARE_01"] = saved
  if AngryMurlocsLocaleEN then AngryMurlocsLocaleEN["NERGLISH_LVL_RARE_01"] = saved end
end

-- Key + token parity en/de
local expected = {}
local function AddRange(prefix, mid, lo, hi)
  for i = lo, hi do
    local key
    if mid == "SUBTLE_" or mid == "PLAYFUL_" then
      key = prefix .. mid .. tostring(i)
    else
      key = prefix .. mid .. string.format("%02d", i)
    end
    expected[key] = true
  end
end
for _, pref in ipairs({ "NERGLISH_LVL_", "NERGLISH_LVL_M_", "NERGLISH_DEATH_", "NERGLISH_SIGHT_" }) do
  AddRange(pref, "SUBTLE_", 1, 3)
  AddRange(pref, "PLAYFUL_", 1, 3)
  AddRange(pref, "RARE_", 1, 10)
  AddRange(pref, "LEGEND_", 11, 16)
end

_G.GetLocale = function() return "deDE" end
local enSnap = {}
for k, v in pairs(AngryMurlocsLocaleEN) do enSnap[k] = v end
_G.AngryMurlocsLocale = {}
for k, v in pairs(enSnap) do AngryMurlocsLocale[k] = v end
assert(loadfile("Localization/deDE.lua"))()
assert(loadfile("Localization/nerglish/deDE.lua"))()
local de = AngryMurlocsLocale
local en = AngryMurlocsLocaleEN

local missing = 0
for key in pairs(expected) do
  if en[key] == nil then missing = missing + 1; print("FAIL en missing " .. key) end
  if de[key] == nil then missing = missing + 1; print("FAIL de missing " .. key) end
  if en[key] and de[key] and Tokens(en[key]) ~= Tokens(de[key]) then
    missing = missing + 1
    print("FAIL token mismatch " .. key .. " en=" .. Tokens(en[key]) .. " de=" .. Tokens(de[key]))
  end
end
fails = fails + missing
check("all nerglish keys en+de+tokens", missing == 0, tostring(missing))

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
