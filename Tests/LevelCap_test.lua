-- Level-ups and map positions accept levels above 80 when the client allows
-- them (GetMaxPlayerLevel), and still reject nonsense values.
-- From repo root: luajit Tests/LevelCap_test.lua
local Sim = dofile("Tests/sim.lua")

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

local sim = Sim.New(1)
local alice = sim:AddClient("Alice")
local bob = sim:AddClient("Bob", { env = { GetMaxPlayerLevel = function() return 90 end } })

local levels, posLevels = {}, {}
bob.GR:RegisterMessage("LVL_UPDATE", function(_, _, level) levels[#levels + 1] = level end)
bob.GR:RegisterMessage("POS_UPDATE", function(_, _, data) posLevels[#posLevels + 1] = data.level end)

for _, lvl in ipairs({ 60, 85, 90, 91, 0 }) do
  alice.GR.Comm:Send("LVL|" .. lvl, "ctrl", "misc")
end
alice.GR.Comm:Send("POS|1429|0.5|0.5|Elwynn|0|MAGE|85", "pos", "misc")
sim:Run(10)

check("level 60 accepted", levels[1] == 60, levels[1])
check("level 85 accepted with max 90", levels[2] == 85, levels[2])
check("level 90 accepted", levels[3] == 90, levels[3])
check("level 91 and 0 rejected", #levels == 3, #levels)
check("position keeps level 85", posLevels[1] == 85, posLevels[1])

-- Without GetMaxPlayerLevel the old limit of 80 still applies.
do
  local U = alice.GR.Util
  check("fallback max level 80", U.MaxLevel() == 80, U.MaxLevel())
  check("bob max level 90", bob.GR.Util.MaxLevel() == 90, bob.GR.Util.MaxLevel())
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
