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

-- Dialog dodge ----------------------------------------------------------------
-- A toast must never hide a game dialog such as "Release spirit". Toasts sit on
-- a lower frame strata than dialogs, and if a toast overlaps an open dialog it
-- moves once to just below it for the rest of that display. Rects are screen
-- pixels { left, bottom, right, top }.

T.DODGE_GAP = 8

function T.RectsOverlap(a, b)
  return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

-- Vertical move in screen pixels (negative = down), or nil when the toast
-- overlaps no dialog. Goes below the lowest overlapping dialog, stays on screen.
function T.DodgeOffset(toastRect, dialogRects, screenBottom)
  local lowest
  for i = 1, #dialogRects do
    local d = dialogRects[i]
    if T.RectsOverlap(toastRect, d) and (not lowest or d[2] < lowest) then
      lowest = d[2]
    end
  end
  if not lowest then return nil end
  -- After moving, the toast may hit another dialog stacked further down: keep
  -- going below until its new place is free.
  local height = toastRect[4] - toastRect[2]
  local moved = true
  while moved do
    moved = false
    local top = lowest - T.DODGE_GAP
    local target = { toastRect[1], top - height, toastRect[3], top }
    for i = 1, #dialogRects do
      local d = dialogRects[i]
      if d[2] < lowest and T.RectsOverlap(target, d) then
        lowest = d[2]
        moved = true
      end
    end
  end
  local dy = (lowest - T.DODGE_GAP) - toastRect[4]
  local newBottom = toastRect[2] + dy
  if screenBottom and newBottom < screenBottom then
    dy = screenBottom - toastRect[2]
  end
  if dy >= 0 then return nil end
  return dy
end

local dialogFramesOverride
local function DialogFrames()
  if dialogFramesOverride then return dialogFramesOverride end
  local list = {}
  for i = 1, 4 do
    local f = _G["StaticPopup" .. i]
    if f then list[#list + 1] = f end
  end
  return list
end

function T._SetDialogFramesForTest(frames)
  dialogFramesOverride = frames
end

local function ScreenRect(f)
  if not f or not f.GetLeft then return nil end
  local l, b, r, t = f:GetLeft(), f:GetBottom(), f:GetRight(), f:GetTop()
  if not (l and b and r and t) then return nil end
  local s = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
  return { l * s, b * s, r * s, t * s }
end

-- Moves `frame` below an overlapping open dialog. At most once per display.
-- Returns true when it moved.
function T.TryDodge(frame)
  if not frame or frame._amDodged then return false end
  if not (frame.IsShown and frame:IsShown()) then return false end
  local rects = {}
  for _, d in ipairs(DialogFrames()) do
    if d.IsShown and d:IsShown() then
      local r = ScreenRect(d)
      if r then rects[#rects + 1] = r end
    end
  end
  if #rects == 0 then return false end
  local mine = ScreenRect(frame)
  if not mine then return false end
  local dy = T.DodgeOffset(mine, rects, 0)
  if not dy then return false end
  local p, rel, rp, x, y = frame:GetPoint(1)
  if not p then return false end
  local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
  frame:ClearAllPoints()
  frame:SetPoint(p, rel, rp, x or 0, (y or 0) + dy / scale)
  frame._amDodged = true
  return true
end

-- Called when a toast goes back to its saved position (each new display).
function T.ResetDodge(frame)
  if frame then frame._amDodged = nil end
end

-- Toasts that may need to dodge a dialog opening while they are shown.
-- skip() returns true while the player is positioning toasts in the settings.
local dodgeFrames = {}
local dialogHooked = false

local function DodgeAllSoon()
  local function Run()
    for frame, skip in pairs(dodgeFrames) do
      if not (skip and skip()) then T.TryDodge(frame) end
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
end

function T.WatchDialogs(frame, skip)
  if not frame then return end
  dodgeFrames[frame] = skip or false
  if not dialogHooked and type(hooksecurefunc) == "function" and type(StaticPopup_Show) == "function" then
    dialogHooked = true
    hooksecurefunc("StaticPopup_Show", DodgeAllSoon)
  end
end

-- Check right after a toast appeared (its rect is known one frame later).
function T.DodgeSoon(frame, skip)
  if not frame then return end
  local function Run()
    if not (skip and skip()) then T.TryDodge(frame) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
end

return T
