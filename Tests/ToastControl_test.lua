-- R1/R2 toast control: showToasts at display time; orphan preview timers.
-- From repo root: luajit Tests/ToastControl_test.lua
local Sim = dofile("Tests/sim.lua")

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or ""))
  end
end

local serial = 0
local function newClient()
  serial = serial + 1
  local sim = Sim.New(800 + serial)
  local frames, sounds, world = {}, {}, { combat = false }
  local clientEnv
  local function frameFactory(_, name)
    local f = Sim.Stub()
    f._scripts, f._shown = {}, false
    f.SetScript = function(self, event, fn) self._scripts[event] = fn end
    f.GetScript = function(self, event) return self._scripts[event] end
    f.Show = function(self) self._shown = true; self._shownAt = sim.clock end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.CreateFontString = function()
      local region = Sim.Stub()
      region.SetText = function(self, text) self._text = text end
      region.GetText = function(self) return self._text end
      region.GetFont = function() return "test-font", 20, "" end
      return region
    end
    if name then
      frames[name] = f
      if clientEnv then clientEnv[name] = f end
    end
    return f
  end
  local c = sim:AddClient("Alice", {
    extraFiles = { "Modules/Death.lua", "Modules/LevelUp.lua", "Modules/Options.lua" },
    env = {
      CreateFrame = frameFactory,
      UnitAffectingCombat = function() return world.combat end,
      UnitIsDeadOrGhost = function() return false end,
      UnitLevel = function() return 10 end,
      IsInInstance = function() return false, "none" end,
      UIFrameFadeOut = function() end,
      UIFrameFadeRemoveFrame = function() end,
    },
  })
  clientEnv = c.env
  for name, f in pairs(frames) do clientEnv[name] = f end
  c.GR.Sounds.Play = function(kind) sounds[#sounds + 1] = kind end
  return sim, c, frames, sounds, world
end

local function deathMessage(c)
  c.GR:SendMessage("DEATH_UPDATE", "Bob-Realm", {
    cause = "mob", killer = "Wolf", spell = "Melee", zone = "Hillsbrad",
  })
end

-- R1: queued before opt-out, displayed after opt-out.
do
  local _, c, frames, sounds, world = newClient()
  world.combat = true
  deathMessage(c)
  check("R1 setup: combat queues a death", c.GR.ToastQueue.Size() == 1)
  c.GR.db.death.showToasts = false
  world.combat = false
  c.GR.ToastQueue.OnCombatEnd()
  local f = frames.AngryMurlocsDeathToast
  check("R1 disabled pending death stays hidden", not (f and f:IsShown()),
    "shown=" .. tostring(f and f:IsShown()))
  check("R1 disabled pending death plays no sound", #sounds == 0, "sound count=" .. #sounds)
end

-- Control: already disabled + level-up independent.
do
  local _, c, frames, _, world = newClient()
  c.GR.db.death.showToasts = false
  world.combat = true
  deathMessage(c)
  check("control: already-disabled death is not queued", c.GR.ToastQueue.Size() == 0)
  world.combat = false
  c.GR:SendMessage("LVL_UPDATE", "Bob-Realm", 12)
  check("control: level-up remains available", frames.AngryMurlocsLevelUpToast:IsShown())
end

-- R1: after skip, a later enabled level-up still shows (after toast cooldown).
do
  local sim, c, frames, sounds, world = newClient()
  world.combat = true
  deathMessage(c)
  c.GR.db.death.showToasts = false
  world.combat = false
  c.GR.ToastQueue.OnCombatEnd()
  check("R1 skip then queue empty", c.GR.ToastQueue.Size() == 0)
  sim:Run(1.6)
  c.GR:SendMessage("LVL_UPDATE", "Bob-Realm", 12)
  local lvl = frames.AngryMurlocsLevelUpToast
  check("R1 skip then level-up shows", lvl and lvl:IsShown(),
    "shown=" .. tostring(lvl and lvl:IsShown()))
  local deathSounds = 0
  for i = 1, #sounds do
    if sounds[i] == "death" then deathSounds = deathSounds + 1 end
  end
  check("R1 skip then no death sound", deathSounds == 0, "deathSounds=" .. deathSounds)
end

-- R1: showToasts true still displays.
do
  local _, c, frames, sounds, world = newClient()
  world.combat = true
  deathMessage(c)
  world.combat = false
  c.GR.ToastQueue.OnCombatEnd()
  local f = frames.AngryMurlocsDeathToast
  check("R1 enabled death shows", f and f:IsShown())
  check("R1 enabled death plays sound", #sounds >= 1 and sounds[1] == "death")
end

-- R2a: death preview then level-up preview; orphan timer must not resume.
do
  local sim, c, frames = newClient()
  c.GR.db.death.duration, c.GR.db.levelUp.duration = 1.5, 15
  c.GR:GetModule("Death"):Preview()
  sim:Run(0.5)
  c.GR:GetModule("LevelUp"):Preview()
  deathMessage(c)
  check("R2a setup: real death waits during preview",
    c.GR.ToastQueue.IsPaused() and c.GR.ToastQueue.Size() == 1)
  sim:Run(1.7)
  check("R2a newer preview retains queue pause", c.GR.ToastQueue.IsPaused(),
    "paused=" .. tostring(c.GR.ToastQueue.IsPaused()))
  check("R2a newer preview remains visible", frames.AngryMurlocsLevelUpToast:IsShown(),
    "shown=" .. tostring(frames.AngryMurlocsLevelUpToast and frames.AngryMurlocsLevelUpToast:IsShown()))
end

-- R2b: death preview then level-up layout editor.
do
  local sim, c, frames = newClient()
  c.GR.db.death.duration = 1.5
  c.GR:GetModule("Death"):Preview()
  sim:Run(0.5)
  local options = c.GR:GetModule("Options")
  options:BeginLayoutEdit("lvl")
  deathMessage(c)
  check("R2b setup: layout editor pauses queue",
    options:IsLayoutEdit() and c.GR.ToastQueue.IsPaused())
  sim:Run(1.7)
  check("R2b editor retains pause", c.GR.ToastQueue.IsPaused(),
    "paused=" .. tostring(c.GR.ToastQueue.IsPaused()))
  check("R2b editable level-up frame remains visible",
    frames.AngryMurlocsLevelUpToast:IsShown())
end

-- R2c: level-up preview then death layout editor.
do
  local sim, c, frames = newClient()
  c.GR.db.levelUp.duration = 1.5
  c.GR:GetModule("LevelUp"):Preview()
  sim:Run(0.5)
  local options = c.GR:GetModule("Options")
  options:BeginLayoutEdit("death")
  c.GR:SendMessage("LVL_UPDATE", "Bob-Realm", 12)
  check("R2c setup: death editor pauses queue",
    options:IsLayoutEdit() and c.GR.ToastQueue.IsPaused())
  sim:Run(1.7)
  check("R2c death editor retains pause", c.GR.ToastQueue.IsPaused())
  check("R2c editable death frame remains visible",
    frames.AngryMurlocsDeathToast:IsShown())
end

-- Control: editor alone keeps pause; end resumes once.
do
  local sim, c, frames = newClient()
  local options = c.GR:GetModule("Options")
  options:BeginLayoutEdit("lvl")
  deathMessage(c)
  sim:Run(3)
  check("control: editor without prior preview stays paused", c.GR.ToastQueue.IsPaused())
  check("control: editor without prior preview stays visible",
    frames.AngryMurlocsLevelUpToast:IsShown())
  options:EndLayoutEdit()
  check("control: leaving editor resumes queue", not c.GR.ToastQueue.IsPaused())
end

-- After preview ends naturally, queued death shows once.
do
  local sim, c, frames, sounds = newClient()
  c.GR.db.levelUp.duration = 1.5
  c.GR:GetModule("LevelUp"):Preview()
  deathMessage(c)
  check("post-preview setup queued", c.GR.ToastQueue.Size() == 1 and c.GR.ToastQueue.IsPaused())
  sim:Run(2.2)
  check("post-preview queue resumed", not c.GR.ToastQueue.IsPaused())
  check("post-preview death shown once", frames.AngryMurlocsDeathToast and frames.AngryMurlocsDeathToast:IsShown())
  local deathSounds = 0
  for i = 1, #sounds do
    if sounds[i] == "death" then deathSounds = deathSounds + 1 end
  end
  check("post-preview death sound once", deathSounds == 1, "count=" .. deathSounds)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
