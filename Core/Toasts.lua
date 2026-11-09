-- Shared toast queue (pure logic + thin runtime drain).
-- Display frames stay in Death / LevelUp; they register a show(kind, item, done) handler.
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local T = {}
GR.ToastQueue = T

T.COOLDOWN_SEC = 1.5
T.MAX = 20

-- Pure: insert item into list. Death jumps ahead of pending level-ups.
-- Over max: drop oldest level-up first, else oldest entry.
function T.Push(items, item, max)
  items = items or {}
  max = max or T.MAX
  item = item or {}
  if item.kind == "death" then
    local at = #items + 1
    for i = 1, #items do
      if items[i].kind == "lvl" then
        at = i
        break
      end
    end
    table.insert(items, at, item)
  else
    items[#items + 1] = item
  end
  while #items > max do
    local drop = 1
    for i = 1, #items do
      if items[i].kind == "lvl" then
        drop = i
        break
      end
    end
    table.remove(items, drop)
  end
  return items
end

function T.CanShow(state, now, inCombat, cooldown)
  if state.paused then return false end
  if inCombat then return false end
  if state.showing then return false end
  if #(state.items or {}) == 0 then return false end
  cooldown = cooldown or T.COOLDOWN_SEC
  local last = state.lastAt or 0
  if (now - last) < cooldown then return false end
  return true
end

-- Runtime ----------------------------------------------------------------

local state = { items = {}, showing = false, lastAt = -1000, paused = false }
local handlers = {}
local finishHooks = {}
local drainPending
local activeDone

function T.Register(kind, handler)
  handlers[kind] = handler
end

-- Optional: modules register to force-hide current toast when FinishCurrent runs.
function T.RegisterFinishHook(kind, fn)
  finishHooks[kind] = fn
end

local function InCombat()
  return UnitAffectingCombat and UnitAffectingCombat("player")
end

local function Now()
  return (GetTime and GetTime()) or 0
end

local function Drain()
  drainPending = nil
  if state.paused then return end
  if not T.CanShow(state, Now(), InCombat(), T.COOLDOWN_SEC) then
    if state.showing == false and #(state.items) > 0 and not InCombat() and not state.paused then
      local wait = T.COOLDOWN_SEC - (Now() - (state.lastAt or 0))
      if wait > 0.05 and C_Timer and C_Timer.After then
        drainPending = true
        C_Timer.After(wait + 0.01, Drain)
      end
    end
    return
  end
  local item = table.remove(state.items, 1)
  local fn = handlers[item.kind]
  if not fn then return Drain() end
  state.showing = true
  state.lastAt = Now()
  activeDone = function()
    activeDone = nil
    state.showing = false
    if not state.paused then
      Drain()
    end
  end
  fn(item, activeDone)
end

function T.Enqueue(item)
  if not item or not item.kind then return false end
  if not handlers[item.kind] then return false end
  T.Push(state.items, item, T.MAX)
  Drain()
  return true
end

function T.Pause()
  state.paused = true
end

function T.Resume()
  state.paused = false
  Drain()
end

function T.IsPaused()
  return state.paused and true or false
end

-- Force current display to finish so showing is released (edit mode / preview).
-- Prefer Pause() before FinishCurrent so done() does not drain the next item.
function T.FinishCurrent()
  if not state.showing then return end
  for _, fn in pairs(finishHooks) do
    if type(fn) == "function" then
      pcall(fn)
    end
  end
  -- Hooks should invoke the display done callback; clear if they did not.
  if state.showing then
    activeDone = nil
    state.showing = false
  end
end

function T.OnCombatEnd()
  Drain()
end

function T.Size()
  return #state.items
end

function T.IsShowing()
  return state.showing
end

-- Tests: replace runtime state.
function T._ResetForTest()
  state = { items = {}, showing = false, lastAt = -1000, paused = false }
  handlers = {}
  finishHooks = {}
  drainPending = nil
  activeDone = nil
end

function T._StateForTest()
  return state
end

return T
