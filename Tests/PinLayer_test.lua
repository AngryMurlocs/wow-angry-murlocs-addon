-- From repo root: luajit Tests/PinLayer_test.lua
AngryMurlocs = AngryMurlocs or {}
AngryMurlocs.Util = { ClassColor = function() return 1, 1, 1 end, L = function(k) return k end, Now = function() return 0 end }
AngryMurlocs.NewModule = function(self, name)
  local m = { name = name }
  self._modules = self._modules or {}
  self._modules[name] = m
  return m
end
dofile("Modules/MapPins.lua")

local M = AngryMurlocs._modules.MapPins
local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or ""))
  end
end

local function allAt(levels, expected)
  if #levels ~= #expected then return false end
  for i = 1, #levels do
    if levels[i] ~= expected[i] then return false end
  end
  return true
end

do
  local levels, hover = M.LayerLevels(5, 10, 2014)
  check("under dig-site band", allAt(levels, { 2012, 2012, 2012, 2012, 2012 }), levels[1])
  check("hover stays under band start", hover == 2013)
  for i = 1, #levels do
    check("pin " .. i .. " below symbols", levels[i] < 2014)
  end
  check("hover below symbols", hover < 2014)
end

do
  local levels, hover = M.LayerLevels(3, 10, nil)
  check("no band sits on canvas", allAt(levels, { 11, 11, 11 }))
  check("no band hover stays put", hover == 11)
end

do
  local levels, hover = M.LayerLevels(4, 3000, 2014)
  check("canvas already above band", allAt(levels, { 3001, 3001, 3001, 3001 }))
  check("clamped hover does not climb", hover == 3001)
end

do
  local levels, hover = M.LayerLevels(0, 10, 2014)
  check("empty list", #levels == 0)
  check("empty hover still under band", hover == 2013)
end

do
  local levels, hover = M.LayerLevels(2, 10, 13)
  check("tight gap rest", allAt(levels, { 11, 11 }))
  check("tight gap hover", hover == 12 and hover < 13)
end

do
  local levels, hover = M.LayerLevels(2, 10, 12)
  check("one free level shared", allAt(levels, { 11, 11 }))
  check("one free level no extra hover", hover == 11 and hover < 12)
end

-- Glow visibility: BindPinArt / BindSightPinArt own Show/Hide across Refresh.
do
  local Sim = dofile("Tests/sim.lua")
  local sim = Sim.New(17)
  local pinFrames = {}

  local function NewTexture()
    local t = Sim.Stub()
    t._shown = true
    t.Show = function(self) self._shown = true end
    t.Hide = function(self) self._shown = false end
    t.IsShown = function(self) return self._shown end
    t.SetSize = function() end
    t.SetPoint = function() end
    t.SetAllPoints = function() end
    t.ClearAllPoints = function() end
    t.SetTexture = function() end
    t.SetVertexColor = function() end
    t.SetTexCoord = function() end
    t.SetBlendMode = function() end
    t.SetAlpha = function() end
    return t
  end

  local function NewFrame()
    local f = Sim.Stub()
    f._shown = true
    f._w, f._h = 26, 26
    f._parent = nil
    f._points = {}
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.SetSize = function(self, w, h) self._w, self._h = w, h end
    f.GetWidth = function(self) return self._w or 26 end
    f.GetHeight = function(self) return self._h or 26 end
    f.SetParent = function(self, p) self._parent = p end
    f.SetScale = function() end
    f.SetFrameLevel = function() end
    f.SetFrameStrata = function() end
    f.EnableMouse = function() end
    f.ClearAllPoints = function(self) self._points = {} end
    f.SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end
    f.SetScript = function() end
    f.CreateTexture = function() return NewTexture() end
    pinFrames[#pinFrames + 1] = f
    return f
  end

  local canvas = NewFrame()
  -- canvas is not a map pin; drop it from pin tracking
  pinFrames[#pinFrames] = nil
  canvas.GetWidth = function() return 1000 end
  canvas.GetHeight = function() return 1000 end
  canvas.GetFrameLevel = function() return 10 end
  canvas.GetFrameStrata = function() return "MEDIUM" end

  local worldMap = {
    IsShown = function() return true end,
    GetMapID = function() return 1429 end,
    GetCanvasScale = function() return 1 end,
    ScrollContainer = { Child = canvas },
    HookScript = function() end,
  }

  local db = Sim.DefaultDB()
  db.map = {
    showPins = true,
    showSightPins = true,
    pinSize = 26,
    pinClustering = false,
    pinStyle = "heads",
  }

  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Positions.lua", "Modules/MapPins.lua" },
    env = {
      CreateFrame = NewFrame,
      WorldMapFrame = worldMap,
      GameTooltip = {
        SetOwner = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
    },
  })

  local GR = alice.GR
  local pins = GR:GetModule("MapPins")
  local cache = GR:GetModule("Positions"):GetCache()
  local sightStore = {}
  GR._modules.Wanted = {
    GetSightPins = function() return sightStore end,
    PruneSightPins = function() return false end,
    RemoveSightPin = function(_, key) sightStore[key] = nil end,
  }

  local MEMBER = "Bob-Realm"
  local SIGHT_KEY = "Rivalo-Realm"

  local function clearGuild()
    for k in pairs(cache) do cache[k] = nil end
  end

  local function clearSight()
    for k in pairs(sightStore) do sightStore[k] = nil end
  end

  local function setGuild(classFile)
    clearGuild()
    cache[MEMBER] = {
      mapId = 1429, x = 0.40, y = 0.50, time = 1,
      classFile = classFile or "MAGE", level = 60,
    }
  end

  local function setSight()
    clearSight()
    sightStore[SIGHT_KEY] = {
      mapId = 1429, x = 0.55, y = 0.45, zone = "Elwynn",
      by = "Alice-Realm", ts = sim:Wall(),
    }
  end

  local function findGuildPin()
    for i = 1, #pinFrames do
      local p = pinFrames[i]
      if p.glow and p.member == MEMBER and p.kind ~= "sight" then
        return p
      end
    end
  end

  local function findSightPin()
    for i = 1, #pinFrames do
      local p = pinFrames[i]
      if p.glow and p.kind == "sight" and p.member == SIGHT_KEY then
        return p
      end
    end
  end

  local function glowShown(pin)
    return pin and pin.glow and pin.glow:IsShown()
  end

  local function assertStyleTwice(style, expectOn)
    GR.db.map.pinStyle = style
    setGuild("MAGE")
    clearSight()
    pins:Refresh()
    local p1 = findGuildPin()
    local g1 = glowShown(p1)
    pins:Refresh()
    local p2 = findGuildPin()
    local g2 = glowShown(p2)
    check(style .. " glow pass1", g1 == expectOn, tostring(g1))
    check(style .. " glow pass2", g2 == expectOn, tostring(g2))
    check(style .. " same pin", p1 ~= nil and p1 == p2)
  end

  assertStyleTwice("heads", false)
  assertStyleTwice("body", false)
  assertStyleTwice("rings", true)

  -- Style cycle on one guild pin
  setGuild("WARRIOR")
  clearSight()
  GR.db.map.pinStyle = "rings"
  pins:Refresh()
  local cyclePin = findGuildPin()
  check("cycle rings on", glowShown(cyclePin) == true)

  GR.db.map.pinStyle = "heads"
  pins:Refresh()
  check("cycle heads off", findGuildPin() == cyclePin and glowShown(cyclePin) == false)

  GR.db.map.pinStyle = "body"
  pins:Refresh()
  check("cycle body off", findGuildPin() == cyclePin and glowShown(cyclePin) == false)

  GR.db.map.pinStyle = "rings"
  pins:Refresh()
  check("cycle rings back on", findGuildPin() == cyclePin and glowShown(cyclePin) == true)

  -- Pool reuse: empty Refresh releases into pool before next kind.
  GR.db.map.pinStyle = "rings"
  setGuild("PALADIN")
  clearSight()
  pins:Refresh()
  local originalPin = findGuildPin()
  check("pool seed rings on", originalPin ~= nil and glowShown(originalPin) == true)

  clearGuild()
  pins:Refresh() -- release into pool

  setSight()
  pins:Refresh()
  local sightPin = findSightPin()
  check("pool sight same frame", sightPin == originalPin)
  check("pool sight glow off", glowShown(sightPin) == false)

  clearSight()
  pins:Refresh() -- re-pool

  GR.db.map.pinStyle = "heads"
  setGuild("HUNTER")
  pins:Refresh()
  local headsPin = findGuildPin()
  check("pool heads same frame", headsPin == originalPin)
  check("pool heads glow off", glowShown(headsPin) == false)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
