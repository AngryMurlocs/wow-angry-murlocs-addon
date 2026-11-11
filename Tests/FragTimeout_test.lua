-- A long message split into parts is put back together as long as the parts
-- keep coming, even if the whole message takes longer than 30 seconds.
-- From repo root: luajit Tests/FragTimeout_test.lua
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
local bob = sim:AddClient("Bob")
local levels = {}
bob.GR:RegisterMessage("LVL_UPDATE", function(_, _, level) levels[#levels + 1] = level end)

local function Part(id, i, n, chunk)
  bob.GR.Comm:OnAddonMessage("GildenRadar", string.format("FRAG|%s|%d|%d|%s", id, i, n, chunk), "GUILD", "Alice-Realm")
end

-- Parts 20 s apart: 40 s in total, but never 30 s without a new part.
Part("a1", 1, 3, "LV")
sim:Run(20)
Part("a1", 2, 3, "L|")
sim:Run(20)
Part("a1", 3, 3, "42")
check("slow but steady message arrives", levels[1] == 42, levels[1])

-- A part after a silence of more than 30 s starts over; the message is lost.
Part("b1", 1, 2, "LVL|")
sim:Run(31)
Part("b1", 2, 2, "50")
check("stale parts are dropped", levels[2] == nil, levels[2])

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
