-- Map positions of the old guild are dropped as soon as the guild changes.
-- From repo root: luajit Tests/GuildChangePositions_test.lua
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
local db = Sim.DefaultDB()
db.privacy.sharePosition = false
local alice = sim:AddClient("Alice", {
  db = db,
  extraFiles = { "Modules/Positions.lua" },
  env = { UnitAffectingCombat = function() return false end, IsInInstance = function() return false, "none" end },
})
local GR = alice.GR
local pos = GR:GetModule("Positions")

local cleared = 0
GR:RegisterMessage("POS_CACHE_CLEARED", function() cleared = cleared + 1 end)

GR:SendMessage("POS_UPDATE", "Bob-Realm", { mapId = 1429, x = 0.5, y = 0.5, time = 0 })
check("position cached", pos:Get("Bob-Realm") ~= nil)

GR:SendMessage("GUILD_UPDATE")
check("cache empty after guild change", next(pos:GetCache()) == nil)
check("map told to clear pins", cleared == 1, cleared)

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
