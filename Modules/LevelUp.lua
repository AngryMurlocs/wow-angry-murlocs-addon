local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local LevelUp = GR:NewModule("LevelUp")

local toast
local hideTimer
local fadeAfter
local layoutEdit = false
local displayDone
local muteNextSound = false

local function Cfg()
  GR.db.levelUp = GR.db.levelUp or {}
  local c = GR.db.levelUp
  if c.showToasts == nil then c.showToasts = true end
  if c.scale == nil then c.scale = 1 end
  if c.duration == nil then c.duration = 8.0 end
  if c.locked == nil then c.locked = false end
  return c
end

local function DefaultPoint(f)
  f:SetPoint("TOP", UIParent, "TOP", 0, -180)
end

local function ApplyToastLayout(f)
  if not f then return end
  local c = Cfg()
  U.ApplyPoint(f, c.point, DefaultPoint)
  f:SetScale(U.Clamp(tonumber(c.scale) or 1, 0.6, 1.6))
  if f.hint then
    f.hint:SetShown(layoutEdit or not c.locked)
  end
end

local function RaiseToast(f)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(500)
  if f.Raise then f:Raise() end
end

local function CancelToastTimers()
  if hideTimer then
    hideTimer:Cancel()
    hideTimer = nil
  end
  if fadeAfter then
    fadeAfter:Cancel()
    fadeAfter = nil
  end
end

local function FinishDisplay()
  CancelToastTimers()
  if toast then
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(toast) end
    toast:SetAlpha(1)
    toast:Hide()
  end
  local d = displayDone
  displayDone = nil
  if d then d() end
end

local function EnsureToast()
  if toast then
    ApplyToastLayout(toast)
    RaiseToast(toast)
    return toast
  end
  toast = CreateFrame("Frame", "AngryMurlocsLevelUpToast", UIParent, BackdropTemplate and "BackdropTemplate" or nil)
  toast:SetSize(360, 56)
  RaiseToast(toast)

  if toast.SetBackdrop then
    toast:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    toast:SetBackdropColor(0.05, 0.12, 0.05, 0.92)
    toast:SetBackdropBorderColor(0.2, 0.7, 0.2, 1)
  end

  toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  toast.text:SetPoint("CENTER", 0, 4)
  toast.text:SetWidth(340)
  do
    local path, _, flags = toast.text:GetFont()
    if path then toast.text:SetFont(path, 20, flags) end
  end

  toast.hint = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  toast.hint:SetPoint("BOTTOM", 0, 6)
  toast.hint:SetText(U.L("TOAST_DRAG_HINT"))

  U.MakeMovable(toast, {
    getPoint = function() return Cfg().point end,
    setPoint = function(pt) Cfg().point = pt end,
    isLocked = function()
      if layoutEdit then return false end
      return Cfg().locked
    end,
    defaultFn = DefaultPoint,
  })

  ApplyToastLayout(toast)
  toast:Hide()
  return toast
end

local function DisplayToast(item, done)
  if not layoutEdit and AngryMurlocsDeathToast and AngryMurlocsDeathToast.Hide then
    AngryMurlocsDeathToast:Hide()
  end
  local f = EnsureToast()
  ApplyToastLayout(f)
  RaiseToast(f)

  CancelToastTimers()
  if UIFrameFadeRemoveFrame then
    UIFrameFadeRemoveFrame(f)
  end

  displayDone = done
  local lvl = tonumber(item.level) or 1
  f.text:SetText(string.format(U.L("LVL_TOAST"), item.name, lvl))
  f:SetAlpha(1)
  f:Show()

  if not muteNextSound and not layoutEdit and not (item and item._preview) then
    if GR.Sounds and GR.Sounds.Play then GR.Sounds.Play("lvl") end
  end
  muteNextSound = false

  if layoutEdit then
    return
  end

  local dur = U.Clamp(tonumber(Cfg().duration) or 8.0, 1.5, 15)
  hideTimer = C_Timer.NewTimer(dur, function()
    local function Finish()
      FinishDisplay()
    end
    if UIFrameFadeOut then
      UIFrameFadeOut(f, 0.4, 1, 0)
      fadeAfter = C_Timer.NewTimer(0.45, function()
        fadeAfter = nil
        Finish()
      end)
    else
      Finish()
    end
  end)
end

local function Enqueue(name, level)
  local cfg = Cfg()
  if not cfg.showToasts then return end
  if GR.ToastQueue then
    GR.ToastQueue.Enqueue({
      kind = "lvl",
      name = U.ShortName(name),
      level = level,
    })
    return
  end
  DisplayToast({ name = U.ShortName(name), level = level })
end

-- Visual preview: no SV mutation, silent. Does not change showToasts/point.
function LevelUp:Preview()
  if layoutEdit then
    muteNextSound = true
    DisplayToast({
      name = U.ShortName(U.PlayerName()),
      level = UnitLevel("player") or 1,
      _preview = true,
    }, nil)
    if toast and toast.ClampToScreen then toast:ClampToScreen() end
    return
  end
  if GR.ToastQueue then
    GR.ToastQueue.Pause()
    GR.ToastQueue.FinishCurrent()
  else
    FinishDisplay()
  end
  muteNextSound = true
  DisplayToast({
    name = U.ShortName(U.PlayerName()),
    level = UnitLevel("player") or 1,
    _preview = true,
  }, function()
    if GR.ToastQueue and not layoutEdit then
      GR.ToastQueue.Resume()
    end
  end)
  if toast and toast.ClampToScreen then
    toast:ClampToScreen()
  end
end

function LevelUp:RefreshLayout()
  if toast then ApplyToastLayout(toast) end
end

function LevelUp:BeginLayoutEdit()
  -- Caller (Options) must Pause + FinishCurrent first.
  layoutEdit = true
  CancelToastTimers()
  muteNextSound = true
  DisplayToast({
    name = U.ShortName(U.PlayerName()),
    level = UnitLevel("player") or 1,
    _preview = true,
  }, nil)
  ApplyToastLayout(toast)
end

function LevelUp:EndLayoutEdit()
  if not layoutEdit then return end
  layoutEdit = false
  FinishDisplay()
  if toast then
    toast:StopMovingOrSizing()
    ApplyToastLayout(toast)
  end
end

function LevelUp:IsLayoutEdit()
  return layoutEdit
end

function LevelUp:ResetPosition()
  Cfg().point = nil
  if toast then ApplyToastLayout(toast) end
end

function LevelUp:ResetAppearance()
  local c = Cfg()
  c.scale = 1
  c.duration = 8.0
  -- locked intentionally preserved
  if toast then ApplyToastLayout(toast) end
end

function LevelUp:ResetLayout()
  self:ResetPosition()
  self:ResetAppearance()
end

function LevelUp:OnEnable()
  if self.enabled then return end
  self.enabled = true

  Cfg()
  if GR.ToastQueue then
    GR.ToastQueue.Register("lvl", DisplayToast)
    GR.ToastQueue.RegisterFinishHook("lvl", FinishDisplay)
  end

  GR:BindMessage(self, "LVL_UPDATE", function(_, sender, level)
    if U.IsSelfName(sender) then return end
    Enqueue(sender, level)
  end)

  local f = CreateFrame("Frame")
  self._eventFrame = f
  U.SafeRegisterEvent(f, "PLAYER_LEVEL_UP")
  U.SafeRegisterEvent(f, "PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
      local level = ...
      level = tonumber(level) or UnitLevel("player")
      Enqueue(U.PlayerName(), level)
      GR:SendMessage("LVL_UPDATE", U.PlayerName(), level)
      if GR.db and GR.db.privacy and GR.db.privacy.shareLevelUp and IsInGuild and IsInGuild() then
        Comm:Send("LVL|" .. tostring(level), "ctrl", "lvl")
      end
    elseif event == "PLAYER_REGEN_ENABLED" then
      if GR.ToastQueue then GR.ToastQueue.OnCombatEnd() end
    end
  end)
end

function LevelUp:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  if layoutEdit then
    self:EndLayoutEdit()
    if GR.ToastQueue and GR.ToastQueue.Resume then GR.ToastQueue.Resume() end
  end
  GR:UnbindMessages(self)
  GR:ReleaseEventFrame(self._eventFrame)
  self._eventFrame = nil
end
