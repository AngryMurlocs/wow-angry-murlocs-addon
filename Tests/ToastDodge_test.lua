-- Toasts move out of the way of open game dialogs (release spirit, invites)
-- only when they really overlap, once per display, and never in layout edit.
-- From repo root: luajit Tests/ToastDodge_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/Toasts.lua")
local T = AngryMurlocs.ToastQueue

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

-- Rects in screen pixels: { left, bottom, right, top }
local dialog = { 660, 700, 1260, 820 }        -- release spirit window, top center
local toastCenter = { 600, 600, 1320, 840 }   -- 720x240 toast at top center
local toastLeft = { 20, 600, 740, 840 }       -- moved to the far left, no overlap? (overlaps 660-740)
local toastFarLeft = { 0, 600, 600, 840 }     -- clearly left of the dialog

check("overlap detected", T.RectsOverlap(toastCenter, dialog) == true)
check("no overlap when apart", T.RectsOverlap(toastFarLeft, dialog) == false)
check("touching edges do not overlap", T.RectsOverlap({ 0, 0, 660, 10 }, { 660, 0, 700, 10 }) == false)

-- Centered toast moves below the dialog: new top = 700 - gap(8) = 692, so dy = 692 - 840 = -148
check("dodge below dialog", T.DodgeOffset(toastCenter, { dialog }, 0) == -148, T.DodgeOffset(toastCenter, { dialog }, 0))
check("no dodge without overlap", T.DodgeOffset(toastFarLeft, { dialog }, 0) == nil)
check("no dodge without dialogs", T.DodgeOffset(toastCenter, {}, 0) == nil)
check("partial overlap still dodges", T.DodgeOffset(toastLeft, { dialog }, 0) == -148)

-- Two stacked dialogs: go below the lower one (bottom 560) -> top 552, dy = -288
local second = { 660, 560, 1260, 690 }
check("below the lowest dialog", T.DodgeOffset(toastCenter, { dialog, second }, 0) == -288,
  T.DodgeOffset(toastCenter, { dialog, second }, 0))

-- Not enough room below: stays on screen (bottom at screen bottom 0)
local lowDialog = { 660, 100, 1260, 820 }
check("clamped to screen bottom", T.DodgeOffset(toastCenter, { lowDialog }, 0) == -600,
  T.DodgeOffset(toastCenter, { lowDialog }, 0))

-- Runtime: frame stubs with a point, a rect and a scale
local function Frame(rect, scale)
  local f = { rect = rect, scale = scale or 1, shown = true, point = { "TOP", "UIParent", "TOP", 0, -120 } }
  function f:IsShown() return self.shown end
  function f:GetEffectiveScale() return self.scale end
  function f:GetLeft() return self.rect[1] / self.scale end
  function f:GetBottom() return self.rect[2] / self.scale end
  function f:GetRight() return self.rect[3] / self.scale end
  function f:GetTop() return self.rect[4] / self.scale end
  function f:GetNumPoints() return 1 end
  function f:GetPoint() return unpack(self.point) end
  function f:ClearAllPoints() end
  function f:SetPoint(p, rel, rp, x, y)
    local dy = y - self.point[5]
    self.point = { p, rel, rp, x, y }
    self.rect = { self.rect[1], self.rect[2] + dy * self.scale, self.rect[3], self.rect[4] + dy * self.scale }
  end
  return f
end

do
  local popup = Frame(dialog)
  T._SetDialogFramesForTest({ popup })
  local toast = Frame({ 600, 600, 1320, 840 })
  check("runtime dodge moves toast", T.TryDodge(toast) == true)
  check("moved by -148", toast.point[5] == -120 - 148, toast.point[5])
  check("only once per display", T.TryDodge(toast) == false)
  T.ResetDodge(toast)
  check("reset allows the next display to check again", toast._amDodged == nil)
end

do
  local popup = Frame(dialog)
  T._SetDialogFramesForTest({ popup })
  local toast = Frame({ 0, 600, 600, 840 })
  check("far-left toast stays", T.TryDodge(toast) == false and toast.point[5] == -120)
end

do
  local popup = Frame(dialog)
  popup.shown = false
  T._SetDialogFramesForTest({ popup })
  local toast = Frame({ 600, 600, 1320, 840 })
  check("hidden dialog ignored", T.TryDodge(toast) == false)
end

do
  -- Toast drawn at scale 1.5: offsets are in the toast's own units
  local popup = Frame(dialog)
  T._SetDialogFramesForTest({ popup })
  local toast = Frame({ 600, 600, 1320, 840 }, 1.5)
  T.TryDodge(toast)
  check("scaled offset", math.abs(toast.point[5] - (-120 - 148 / 1.5)) < 0.001, toast.point[5])
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
