-- Targeting a player whose name or class the client hides as a secret value
-- must not raise a Lua error and must not report a sighting.
-- From repo root: luajit Tests/SecretTarget_test.lua
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

-- A secret behaves like the real thing: comparing or concatenating it throws.
local SECRET = setmetatable({}, {
  __eq = function() error("attempt to compare a secret value") end,
  __concat = function() error("attempt to concatenate a secret value") end,
  __len = function() error("attempt to get length of a secret value") end,
})
local function issecretvalue(v) return v == nil and false or rawequal(v, SECRET) end

local targetName, targetClass = SECRET, SECRET
local sim = Sim.New(1)
local alice = sim:AddClient("Alice", { env = {
  issecretvalue = issecretvalue,
  UnitExists = function(u) return u == "target" end,
  UnitIsPlayer = function(u) return u == "target" end,
  UnitName = function(u) if u == "target" then return targetName end return "Alice" end,
  UnitFullName = function(u) if u == "target" then return targetName, nil end return "Alice", "Realm" end,
  UnitClass = function(u) if u == "target" then return "Rogue", targetClass end return "Mage", "MAGE" end,
} })

-- Put "Grim" on the Wanted list so a plain target would count as a sighting.
local W = alice.Wanted
W:State().wanted["Grim-Realm"] = alice.GR.WantedLogic.NewEntry()
W:State().wanted["Grim-Realm"].legacy = 3

local handler = alice.Wanted._targetFrame
check("target frame exists", handler ~= nil)

-- Fire PLAYER_TARGET_CHANGED through the module's event handler.
local fired = false
local ok, err = pcall(function()
  alice.Wanted:_OnTargetChangedForTest()
  fired = true
end)
check("no error with secret name", ok, err)
check("handler ran", fired)
check("no sighting sent", sim:Count("SIGHT") == 0, sim:Count("SIGHT"))

-- Plain values still work: the sighting is recorded and sent. The send
-- cooldown counts from session start, so let the clock pass it first.
sim:Run(61)
targetName, targetClass = "Grim", "ROGUE"
ok, err = pcall(function() alice.Wanted:_OnTargetChangedForTest() end)
sim:Run(2)
check("no error with plain name", ok, err)
check("sighting sent for plain target", sim:Count("SIGHT") == 1, sim:Count("SIGHT"))

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
