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
      SetFont = function() return true end,
      SetFontObject = function() end,
      SetTextColor = function() end,
      SetJustifyH = function() end,
      SetJustifyV = function() end,
      SetWordWrap = function() end,
      SetMaxLines = function() end,
      SetShadowColor = function() end,
      SetShadowOffset = function() end,
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

local okLvl, errLvl = pcall(function() lvl:Preview() end)
local okDeath, errDeath = pcall(function() death:Preview() end)
check("lvl Preview ok", okLvl, errLvl)
check("death Preview ok", okDeath, errDeath)

check("lvl showToasts unchanged", bob.GR.db.levelUp.showToasts == beforeLvl.showToasts)
check("lvl point unchanged", bob.GR.db.levelUp.point and bob.GR.db.levelUp.point[5] == beforeLvl.point[5])
check("lvl locked unchanged", bob.GR.db.levelUp.locked == true)
check("death showToasts unchanged", bob.GR.db.death.showToasts == beforeDeath.showToasts)
check("death point unchanged", bob.GR.db.death.point and bob.GR.db.death.point[5] == beforeDeath.point[5])

-- Appearance reset keeps lock
lvl:ResetAppearance()
check("appearance keeps locked", bob.GR.db.levelUp.locked == true)
check("appearance resets scale", bob.GR.db.levelUp.scale == 1)

-- Reset while a toast is showing must free the shared queue for the next item.
do
  bob.GR.db.death.showToasts = true
  bob.GR.db.levelUp.showToasts = true
  local TQ = bob.GR.ToastQueue
  TQ._ResetForTest()
  -- Re-bind handlers after queue reset (OnEnable already ran once).
  death:OnDisable()
  lvl:OnDisable()
  death:OnEnable()
  lvl:OnEnable()
  local clock = 1000
  bob.env.GetTime = function() return clock end
  _G.GetTime = function() return clock end
  TQ.Enqueue({ kind = "death", victim = "Alice", cause = "unknown", eventId = "e1" })
  check("reset-queue: death showing", TQ.IsShowing())
  death:ResetAppearance()
  check("reset-queue: not showing after reset", not TQ.IsShowing())
  clock = 2000
  TQ.Enqueue({ kind = "lvl", level = 12, eventId = "e2" })
  check("reset-queue: lvl drains after reset", TQ.IsShowing() or TQ.Size() == 0)
  if TQ.IsShowing() then
    lvl:ResetAppearance()
  end
  check("reset-queue: free after lvl reset", not TQ.IsShowing())
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
