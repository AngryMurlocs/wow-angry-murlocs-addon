local GR = AngryMurlocs
local U = GR.Util

local MinimapButton = GR:NewModule("MinimapButton")

local minimapBtn
local pendingMinimapUpdate = false

local function MinimapCfg()
  GR.db = GR.db or {}
  GR.db.minimap = GR.db.minimap or {}
  return GR.db.minimap
end

local function MinimapRadius()
  local w = (Minimap and Minimap.GetWidth and Minimap:GetWidth()) or 140
  return (w / 2) + 5
end

local function StopMinimapDrag()
  if not minimapBtn then return end
  minimapBtn:SetScript("OnUpdate", nil)
  if minimapBtn.StopMovingOrSizing then
    minimapBtn:StopMovingOrSizing()
  end
end

local function UpdateMinimapButton()
  if not minimapBtn or not Minimap then return end
  if InCombatLockdown and InCombatLockdown() then
    pendingMinimapUpdate = true
    return
  end
  pendingMinimapUpdate = false
  local cfg = MinimapCfg()
  if cfg.hide then
    StopMinimapDrag()
    minimapBtn:Hide()
    return
  end
  minimapBtn:Show()
  local angle = cfg.angle or 200
  local rad = math.rad(angle)
  local r = MinimapRadius()
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

function MinimapButton:ApplySettings()
  local cfg = MinimapCfg()
  if cfg.locked then
    StopMinimapDrag()
  end
  UpdateMinimapButton()
end

local function EnsureMinimapButton()
  if minimapBtn then
    MinimapButton:ApplySettings()
    return
  end
  if not Minimap then
    C_Timer.After(1, EnsureMinimapButton)
    return
  end

  local parent = Minimap or UIParent
  minimapBtn = CreateFrame("Button", "AngryMurlocsMinimapButton", parent)
  minimapBtn:SetSize(31, 31)
  minimapBtn:SetFrameStrata("MEDIUM")
  minimapBtn:SetFrameLevel(8)
  minimapBtn:RegisterForClicks("AnyUp")
  minimapBtn:RegisterForDrag("LeftButton")
  minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture("Interface\\AddOns\\AngryMurlocs\\Media\\MinimapIcon")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  minimapBtn.icon = icon

  local border = minimapBtn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  minimapBtn:SetScript("OnClick", function(_, button)
    local ui = GR:GetModule("UI")
    if not ui or not ui.ShowTab then return end
    if button == "RightButton" then
      ui:ShowTab("opt")
    else
      ui:ShowTab("general")
    end
  end)
  minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(U.L("WANTED_MINIMAP_TIP"), 1, 0.2, 0.2)
    GameTooltip:AddLine(U.L("MINIMAP_TIP_LMB"), 0.9, 0.9, 0.9)
    GameTooltip:AddLine(U.L("MINIMAP_TIP_RMB"), 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  minimapBtn:SetScript("OnLeave", GameTooltip_Hide)

  minimapBtn:SetScript("OnDragStart", function(self)
    local cfg = MinimapCfg()
    if cfg.hide or cfg.locked then return end
    self:SetScript("OnUpdate", function()
      if not Minimap then return end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
      MinimapCfg().angle = angle
      UpdateMinimapButton()
    end)
  end)
  minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  -- Apply hide/lock before first Show so delayed create respects SV.
  MinimapButton:ApplySettings()
  C_Timer.After(2, function()
    MinimapButton:ApplySettings()
  end)
end

function MinimapButton:OnEnable()
  if self.enabled then return end
  self.enabled = true

  C_Timer.After(0.5, EnsureMinimapButton)

  local combat = CreateFrame("Frame")
  self._combatFrame = combat
  U.SafeRegisterEvent(combat, "PLAYER_REGEN_ENABLED")
  combat:SetScript("OnEvent", function()
    if pendingMinimapUpdate then
      UpdateMinimapButton()
    end
  end)
end

function MinimapButton:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  StopMinimapDrag()
  GR:ReleaseEventFrame(self._combatFrame)
  self._combatFrame = nil
end
