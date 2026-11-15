-- Wanted sight map pins: wire coords, privacy strip, pin store TTL, fade curve.
-- From repo root: luajit Tests/SightPins_test.lua
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

-- Pure fade curve (no sim).
do
  AngryMurlocs = AngryMurlocs or {}
  AngryMurlocs.Util = AngryMurlocs.Util or {
    ClassColor = function() return 1, 1, 1 end,
    L = function(k) return k end,
    Now = function() return 0 end,
    WallTime = function() return 0 end,
  }
  AngryMurlocs.NewModule = AngryMurlocs.NewModule or function(self, name)
    local m = { name = name }
    self._modules = self._modules or {}
    self._modules[name] = m
    return m
  end
  -- Reload MapPins into this stub only if not already from a prior dofile conflict.
  if not (AngryMurlocs._modules and AngryMurlocs._modules.MapPins and AngryMurlocs._modules.MapPins.SightPinFadeFactor) then
    dofile("Modules/MapPins.lua")
  end
  local M = AngryMurlocs._modules.MapPins
  check("sight full at 0", M.SightPinFadeFactor(0) == 1)
  check("sight full at 1799", M.SightPinFadeFactor(1799) == 1)
  check("sight fade starts at 1800", M.SightPinFadeFactor(1800) < 1 or M.SightPinFadeFactor(1800) == 1)
  check("sight full boundary 1800 is full", M.SightPinFadeFactor(1800) == 1)
  check("sight fading at 1801", M.SightPinFadeFactor(1801) < 1)
  local at2h = M.SightPinFadeFactor(2 * 3600)
  check("sight paler at 2h", at2h < 1 and at2h > M.SIGHT_PIN_FADE_MIN, at2h)
  local almost = M.SightPinFadeFactor(10800 - 1)
  check("sight visible at 2:59:59", almost > 0 and almost >= M.SIGHT_PIN_FADE_MIN - 0.001, almost)
  check("sight gone at 3h", M.SightPinFadeFactor(10800) == 0)
  check("sight gone past 3h", M.SightPinFadeFactor(12000) == 0)
  check("sight constants", M.SIGHT_PIN_FULL_SEC == 1800 and M.SIGHT_PIN_GONE_SEC == 10800)
end

local RESULT = {
  Success = 0,
  AddonMessageThrottle = 3,
  GeneralError = 9,
}

local function SeedWanted(c, killer)
  local e = c.GR.WantedLogic.NewEntry()
  e.legacy = 2
  c.Wanted:State().wanted[killer] = e
end

local function LastSight(sim)
  for i = #sim.bus, 1, -1 do
    local m = sim.bus[i]
    if m.msg:match("^SIGHT|") then return m.msg end
  end
end

local function PosEnv(mapId, x, y, fail)
  return {
    UnitAffectingCombat = function() return false end,
    IsInInstance = function() return false, "none" end,
    UnitLevel = function() return 60 end,
    UnitIsDeadOrGhost = function() return false end,
    UnitExists = function(u) return u == "target" end,
    UnitIsPlayer = function(u) return u == "target" end,
    UnitName = function(u)
      if u == "target" then return "Rivalo" end
      return nil
    end,
    UnitFullName = function(u)
      if u == "target" then return "Rivalo", "Realm" end
      return nil
    end,
    UnitClass = function(u)
      if u == "target" then return "Rogue", "ROGUE" end
      return "Mage", "MAGE"
    end,
    C_Map = {
      GetBestMapForUnit = function()
        if fail then error("map secret") end
        return mapId
      end,
      GetPlayerMapPosition = function()
        if fail then error("pos secret") end
        return {
          GetXY = function() return x, y end,
        }
      end,
      GetMapInfo = function() return { mapType = 3 } end,
    },
  }
end

-- Old receiver ignores coords; new receiver stores pin.
do
  local sim = Sim.New(20)
  local alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Positions.lua", "Modules/Wanted.lua" },
    env = PosEnv(1434, 0.42, 0.55, false),
  })
  local bob = sim:AddClient("Bob", {
    extraFiles = { "Modules/Positions.lua", "Modules/Wanted.lua" },
    env = PosEnv(1434, 0.1, 0.1, false),
  })
  SeedWanted(alice, "Rivalo-Realm")
  SeedWanted(bob, "Rivalo-Realm")
  sim:Run(61)
  alice.Wanted:_OnTargetChangedForTest()
  sim:Run(2)
  local msg = LastSight(sim)
  check("new sender has coords", msg and msg:match("^SIGHT|[^|]+|[^|]+|%d+|%d+|") ~= nil, msg)
  local pin = bob.Wanted:GetSightPins()["Rivalo-Realm"]
  check("receiver got pin", pin ~= nil and pin.mapId == 1434, pin and pin.mapId)
  check("at most one pin key", (function()
    local n = 0
    for _ in pairs(bob.Wanted:GetSightPins()) do n = n + 1 end
    return n == 1
  end)())
end

-- Zone-only older client style message still applies; no pin.
do
  local sim = Sim.New(21)
  local bob = sim:AddClient("Bob", {
    extraFiles = { "Modules/Wanted.lua" },
  })
  SeedWanted(bob, "Rivalo-Realm")
  local wall = bob.Wanted:Now()
  bob.GR.Comm:OnAddonMessage("GildenRadar",
    string.format("SIGHT|Rivalo-Realm|Stranglethorn|%d", wall + 1),
    "GUILD", "Alice-Realm")
  check("zone-only applies", bob.Wanted:State().wanted["Rivalo-Realm"].lastSeenTime == wall + 1)
  check("zone-only no pin", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
end

-- Pos read failure still sends exactly one zone-only SIGHT.
do
  local sim = Sim.New(22)
  local alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Positions.lua", "Modules/Wanted.lua" },
    env = PosEnv(1434, 0.5, 0.5, true),
  })
  local bob = sim:AddClient("Bob", {
    extraFiles = { "Modules/Wanted.lua" },
  })
  SeedWanted(alice, "Rivalo-Realm")
  SeedWanted(bob, "Rivalo-Realm")
  sim:Run(61)
  alice.Wanted:_OnTargetChangedForTest()
  sim:Run(2)
  check("pos fail still one SIGHT", sim:Count("SIGHT") == 1, sim:Count("SIGHT"))
  local msg = LastSight(sim)
  check("pos fail zone-only wire", msg and not msg:match("^SIGHT|[^|]+|[^|]+|%d+|%d+"), msg)
  check("bob got zone sight", bob.Wanted:State().wanted["Rivalo-Realm"].lastSeenZone ~= nil)
  check("bob no pin on pos fail", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
end

-- Newer zone-only clears existing pin; duplicate does not extend.
do
  local sim = Sim.New(23)
  local bob = sim:AddClient("Bob", { extraFiles = { "Modules/Wanted.lua" } })
  SeedWanted(bob, "Rivalo-Realm")
  local t0 = bob.Wanted:Now()
  bob.Wanted:ApplySighting("Rivalo-Realm", "ZoneA", "Alice-Realm", t0 + 1, 1434, 0.2, 0.3)
  check("pin after coords", bob.Wanted:GetSightPins()["Rivalo-Realm"] ~= nil)
  local ts1 = bob.Wanted:GetSightPins()["Rivalo-Realm"].ts
  bob.Wanted:ApplySighting("Rivalo-Realm", "ZoneA", "Alice-Realm", t0 + 1, 1434, 0.9, 0.9)
  check("duplicate no replace", bob.Wanted:GetSightPins()["Rivalo-Realm"].ts == ts1)
  bob.Wanted:ApplySighting("Rivalo-Realm", "ZoneB", "Carol-Realm", t0 + 10)
  check("newer zone clears pin", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
end

-- Newer coords replace and restart TTL ts.
do
  local sim = Sim.New(24)
  local bob = sim:AddClient("Bob", { extraFiles = { "Modules/Wanted.lua" } })
  SeedWanted(bob, "Rivalo-Realm")
  local t0 = bob.Wanted:Now()
  bob.Wanted:ApplySighting("Rivalo-Realm", "A", "Alice-Realm", t0 + 1, 1434, 0.1, 0.1)
  bob.Wanted:ApplySighting("Rivalo-Realm", "B", "Alice-Realm", t0 + 50, 1434, 0.7, 0.8)
  local pin = bob.Wanted:GetSightPins()["Rivalo-Realm"]
  check("replaced coords", pin and pin.x == 0.7 and pin.ts == t0 + 50, pin and pin.x)
end

-- Invalid strip at Drain when sharePosition revoked while queued.
do
  local sim = Sim.New(25)
  local alice
  local block = true
  alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Positions.lua", "Modules/Wanted.lua" },
    env = (function()
      local e = PosEnv(1434, 0.33, 0.44, false)
      e.Enum = { SendAddonMessageResult = RESULT }
      e.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel)
          if block then return RESULT.AddonMessageThrottle end
          sim:Deliver(alice, prefix, msg, channel)
          return RESULT.Success
        end,
      }
      return e
    end)(),
  })
  SeedWanted(alice, "Rivalo-Realm")
  sim:Run(61)
  alice.Wanted:_OnTargetChangedForTest()
  check("queued while throttled", alice.GR.Comm:QueueSize() >= 1)
  alice.GR.db.privacy.sharePosition = false
  block = false
  sim:Run(5)
  local msg = LastSight(sim)
  check("drain stripped coords", msg and not msg:match("^SIGHT|[^|]+|[^|]+|%d+|%d+"), msg)
end

-- Wall-clock prune at 2:59:59 keep / 3:00:00 gone.
do
  local sim = Sim.New(26)
  local bob = sim:AddClient("Bob", { extraFiles = { "Modules/Wanted.lua" } })
  SeedWanted(bob, "Rivalo-Realm")
  local t0 = bob.Wanted:Now()
  bob.Wanted:ApplySighting("Rivalo-Realm", "Z", "Alice-Realm", t0, 1434, 0.5, 0.5)
  sim.clock = 10799
  bob.Wanted:PruneSightPins()
  check("pin at 2:59:59", bob.Wanted:GetSightPins()["Rivalo-Realm"] ~= nil)
  sim.clock = 10800
  bob.Wanted:PruneSightPins()
  check("pin gone at 3:00:00", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
end

-- Sync-newer lastSeenTime invalidates pin (WANTED_CHANGED path uses PruneSightPins).
do
  local sim = Sim.New(27)
  local bob = sim:AddClient("Bob", { extraFiles = { "Modules/Wanted.lua" } })
  SeedWanted(bob, "Rivalo-Realm")
  local t0 = bob.Wanted:Now()
  bob.Wanted:ApplySighting("Rivalo-Realm", "Z", "Alice-Realm", t0 + 1, 1434, 0.5, 0.5)
  local entry = bob.Wanted:State().wanted["Rivalo-Realm"]
  entry.lastSeenTime = t0 + 100
  entry.lastSeenZone = "Elsewhere"
  bob.Wanted:PruneSightPins()
  check("newer entry clears pin", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
end

-- Guild change clears pins.
do
  local sim = Sim.New(28)
  local bob = sim:AddClient("Bob", { extraFiles = { "Modules/Wanted.lua" } })
  SeedWanted(bob, "Rivalo-Realm")
  local t0 = bob.Wanted:Now()
  bob.Wanted:ApplySighting("Rivalo-Realm", "Z", "Alice-Realm", t0 + 1, 1434, 0.5, 0.5)
  bob.GR:SendMessage("GUILD_UPDATE")
  check("guild change clears pins", next(bob.Wanted:GetSightPins()) == nil)
end

-- shareSightings off → no send.
do
  local sim = Sim.New(29)
  local db = Sim.DefaultDB()
  db.privacy.shareSightings = false
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Positions.lua", "Modules/Wanted.lua" },
    env = PosEnv(1434, 0.5, 0.5, false),
  })
  SeedWanted(alice, "Rivalo-Realm")
  sim:Run(61)
  alice.Wanted:_OnTargetChangedForTest()
  sim:Run(2)
  check("no send when shareSightings off", sim:Count("SIGHT") == 0)
  check("local pin still with coords", alice.Wanted:GetSightPins()["Rivalo-Realm"] ~= nil)
end

-- Invalid mapId / (0,0) ignored; zone still applies.
do
  local sim = Sim.New(30)
  local bob = sim:AddClient("Bob", { extraFiles = { "Modules/Wanted.lua" } })
  SeedWanted(bob, "Rivalo-Realm")
  local wall = bob.Wanted:Now() + 5
  bob.GR.Comm:OnAddonMessage("GildenRadar",
    string.format("SIGHT|Rivalo-Realm|Z|%d|0|0.5|0.5", wall),
    "GUILD", "Alice-Realm")
  check("mapId 0 no pin", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
  check("mapId 0 still zone", bob.Wanted:State().wanted["Rivalo-Realm"].lastSeenTime == wall)
  bob.GR.Comm:OnAddonMessage("GildenRadar",
    string.format("SIGHT|Rivalo-Realm|Z2|%d|1434|0|0", wall + 1),
    "GUILD", "Alice-Realm")
  check("(0,0) no pin", bob.Wanted:GetSightPins()["Rivalo-Realm"] == nil)
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
