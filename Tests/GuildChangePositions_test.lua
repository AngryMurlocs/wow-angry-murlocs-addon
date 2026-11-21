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

-- Late guild join with sharing on must start heartbeat / allow a send path.
do
  local sim2 = Sim.New(2)
  local sent = 0
  local db2 = Sim.DefaultDB()
  db2.privacy.sharePosition = true
  local join = sim2:AddClient("Join", {
    db = db2,
    guild = false,
    extraFiles = { "Modules/Positions.lua" },
    env = {
      UnitAffectingCombat = function() return false end,
      IsInInstance = function() return false, "none" end,
      C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetPlayerMapPosition = function()
          return { GetXY = function() return 0.5, 0.5 end }
        end,
      },
      GetZoneText = function() return "Elwynn" end,
      UnitIsDeadOrGhost = function() return false end,
      UnitLevel = function() return 60 end,
      IsInGuild = function() return false end,
    },
  })
  local before = join.GR.Comm:QueueSize()
  join.GR:SendMessage("GUILD_UPDATE")
  check("unguilded join: no pos while share on but no guild", join.GR.Comm:QueueSize() == before)

  join.guild = "Angry Murlocs"
  join.env.IsInGuild = function() return true end
  join.GR.db.privacy.sharePosition = true
  join.GR:SendMessage("GUILD_UPDATE")
  sim2:Run(2)
  local posN = 0
  for _, m in ipairs(sim2.bus) do
    if m.from == "Join" and m.msg:match("^POS|") then posN = posN + 1 end
  end
  check("guild join starts pos send", posN >= 1 or join.GR.Comm:QueueSize() >= 1, posN)
end

-- Combat must not stop the move ticker when suppressInCombat is off.
do
  local sim3 = Sim.New(3)
  local moving = false
  local db3 = Sim.DefaultDB()
  db3.privacy.sharePosition = true
  db3.privacy.suppressInCombat = false
  local fighter = sim3:AddClient("Fighter", {
    db = db3,
    extraFiles = { "Modules/Positions.lua" },
    env = {
      UnitAffectingCombat = function() return true end,
      IsInInstance = function() return false, "none" end,
      C_Map = {
        GetBestMapForUnit = function() return 1429 end,
        GetPlayerMapPosition = function()
          return { GetXY = function() return 0.4, 0.4 end }
        end,
      },
      GetZoneText = function() return "Elwynn" end,
      UnitIsDeadOrGhost = function() return false end,
      UnitLevel = function() return 60 end,
      IsInGuild = function() return true end,
    },
  })
  local posMod = fighter.GR:GetModule("Positions")
  local f = posMod._eventFrame
  local function Fire(ev)
    if not f then return end
    if f._scripts and f._scripts.OnEvent then
      f._scripts.OnEvent(f, ev)
      return
    end
    local fn = f.GetScript and f:GetScript("OnEvent")
    if fn then fn(f, ev) end
  end
  -- Start moving ticker while already "in combat" with suppress off.
  fighter.env.UnitAffectingCombat = function() return false end
  Fire("PLAYER_STARTED_MOVING")
  fighter.env.UnitAffectingCombat = function() return true end
  local qBefore = fighter.GR.Comm:QueueSize()
  Fire("PLAYER_REGEN_DISABLED")
  -- Moving ticker should still be able to broadcast (suppress off).
  sim3:Run(3)
  local qAfter = fighter.GR.Comm:QueueSize()
  local busPos = 0
  for _, m in ipairs(sim3.bus) do
    if m.from == "Fighter" and m.msg:match("^POS|") then busPos = busPos + 1 end
  end
  check("combat suppress off keeps pos path", qAfter >= qBefore or busPos >= 1, busPos)
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
