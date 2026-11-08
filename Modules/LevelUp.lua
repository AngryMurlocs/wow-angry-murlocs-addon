local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local LevelUp = GR:NewModule("LevelUp")

local toast
local queue = {}
local hideTimer
local fadeAfter

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
  local c = Cfg()
  U.ApplyPoint(f, c.point, DefaultPoint)
  f:SetScale(U.Clamp(tonumber(c.scale) or 1, 0.6, 1.6))
  if f.hint then
    f.hint:SetShown(not c.locked)
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
    isLocked = function() return Cfg().locked end,
    defaultFn = DefaultPoint,
  })

  ApplyToastLayout(toast)
  toast:Hide()
  return toast
end

local ShowNext

local function DisplayToast(name, level)
  local f = EnsureToast()
  ApplyToastLayout(f)
  RaiseToast(f)

  CancelToastTimers()
  if UIFrameFadeRemoveFrame then
    UIFrameFadeRemoveFrame(f)
  end

  local lvl = tonumber(level) or 1
  f.text:SetText(string.format(U.L("LVL_TOAST"), name, lvl))
  f:SetAlpha(1)
  f:Show()

  local dur = U.Clamp(tonumber(Cfg().duration) or 8.0, 1.5, 15)
  hideTimer = C_Timer.NewTimer(dur, function()
    if UIFrameFadeOut then
      UIFrameFadeOut(f, 0.4, 1, 0)
      fadeAfter = C_Timer.NewTimer(0.45, function()
        fadeAfter = nil
        f:Hide()
        ShowNext()
      end)
    else
      f:Hide()
      ShowNext()
    end
  end)
end

function ShowNext()
  if UnitAffectingCombat("player") then return end
  if #queue == 0 then return end
  if toast and toast:IsShown() and toast:GetAlpha() > 0.1 then return end

  local item = table.remove(queue, 1)
  DisplayToast(item.name, item.level)
end

local function Enqueue(name, level)
  local cfg = Cfg()
  if not cfg.showToasts then return end
  queue[#queue + 1] = { name = U.ShortName(name), level = level }
  if not UnitAffectingCombat("player") then
    ShowNext()
  end
end

function LevelUp:Preview()
  Cfg().showToasts = true
  Cfg().point = nil -- force default; saved off-screen kills preview
  DisplayToast(U.ShortName(U.PlayerName()), UnitLevel("player") or 1)
  if toast and toast.ClampToScreen then
    toast:ClampToScreen()
  end
end

function LevelUp:ResetLayout()
  local c = Cfg()
  c.point = nil
  c.scale = 1
  c.duration = 8.0
  c.locked = false
  if toast then ApplyToastLayout(toast) end
end

function LevelUp:OnEnable()
  Cfg()

  GR:RegisterMessage("LVL_UPDATE", function(_, sender, level)
    Enqueue(sender, level)
  end)

  local f = CreateFrame("Frame")
  U.SafeRegisterEvent(f, "PLAYER_LEVEL_UP")
  U.SafeRegisterEvent(f, "PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
      local level = ...
      level = tonumber(level) or UnitLevel("player")
      Enqueue(U.PlayerName(), level)
      if GR.db and GR.db.privacy and GR.db.privacy.shareLevelUp and IsInGuild and IsInGuild() then
        Comm:Send("LVL|" .. tostring(level))
      end
    elseif event == "PLAYER_REGEN_ENABLED" then
      ShowNext()
    end
  end)
end
