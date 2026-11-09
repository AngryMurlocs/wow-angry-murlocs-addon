-- Preview must not mutate showToasts / point.
-- From repo root: luajit Tests/ToastPreview_test.lua
local Sim = dofile("Tests/sim.lua")

local fails = 0
local function check(name, cond, extra)
  if cond then print("OK  " .. name) else fails = fails + 1 print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or "")) end
end

local function NewFrame()
  local f = Sim.Stub()
  f._shown = false
  f._scripts = {}
  f.Show = function(self) self._shown = true end
  f.Hide = function(self) self._shown = false end
  f.IsShown = function(self) return self._shown end
  f.SetScript = function(self, ev, fn) self._scripts[ev] = fn end
  f.SetText = function(self, t) self._text = t or "" end
  f.GetText = function(self) return self._text or "" end
  f.SetAlpha = function() end
  f.SetScale = function() end
  f.SetSize = function() end
  f.SetPoint = function() end
  f.ClearAllPoints = function() end
  f.SetMovable = function() end
  f.EnableMouse = function() end
  f.RegisterForDrag = function() end
  f.SetFrameStrata = function() end
  f.SetFrameLevel = function() end
  f.CreateFontString = function()
    return {
      SetPoint = function() end,
      SetText = function() end,
      SetWidth = function() end,
      SetShown = function() end,
      GetFont = function() return nil end,
      SetFont = function() end,
    }
  end
  f.CreateTexture = function()
    return { SetAllPoints = function() end, SetTexture = function() end, SetVertexColor = function() end, SetSize = function() end, SetPoint = function() end, SetTexCoord = function() end }
  end
  return f
end

local sim = Sim.New(1)
local db = Sim.DefaultDB()
db.levelUp = { showToasts = false, point = { "TOP", nil, "TOP", 0, -50 }, scale = 1.2, duration = 5, locked = true }
db.death = { showToasts = false, point = { "TOP", nil, "TOP", 0, -80 }, scale = 1.1, duration = 6, locked = true }
local bob = sim:AddClient("Bob", {
  extraFiles = { "Modules/LevelUp.lua", "Modules/Death.lua" },
  db = db,
  env = {
    CreateFrame = NewFrame,
    UnitLevel = function() return 10 end,
  },
})

local lvl = bob.GR:GetModule("LevelUp")
local death = bob.GR:GetModule("Death")

local beforeLvl = Sim.DeepCopy(bob.GR.db.levelUp)
local beforeDeath = Sim.DeepCopy(bob.GR.db.death)

pcall(function() lvl:Preview() end)
pcall(function() death:Preview() end)

check("lvl showToasts unchanged", bob.GR.db.levelUp.showToasts == beforeLvl.showToasts)
check("lvl point unchanged", bob.GR.db.levelUp.point and bob.GR.db.levelUp.point[5] == beforeLvl.point[5])
check("lvl locked unchanged", bob.GR.db.levelUp.locked == true)
check("death showToasts unchanged", bob.GR.db.death.showToasts == beforeDeath.showToasts)
check("death point unchanged", bob.GR.db.death.point and bob.GR.db.death.point[5] == beforeDeath.point[5])

-- Appearance reset keeps lock
lvl:ResetAppearance()
check("appearance keeps locked", bob.GR.db.levelUp.locked == true)
check("appearance resets scale", bob.GR.db.levelUp.scale == 1)

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
