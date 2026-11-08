local GR = AngryMurlocs
local U = GR.Util

local Options = GR:NewModule("Options")

local function EnsureDeathCfg()
  GR.db.death = GR.db.death or {}
  local c = GR.db.death
  if c.showToasts == nil then c.showToasts = true end
  if c.scale == nil then c.scale = 1 end
  if c.duration == nil then c.duration = 10.0 end
  if c.locked == nil then c.locked = false end
  return c
end

local function EnsureLvlCfg()
  GR.db.levelUp = GR.db.levelUp or {}
  local c = GR.db.levelUp
  if c.showToasts == nil then c.showToasts = true end
  if c.scale == nil then c.scale = 1 end
  if c.duration == nil then c.duration = 8.0 end
  if c.locked == nil then c.locked = false end
  return c
end

function Options:OnEnable()
  local panel = CreateFrame("Frame")
  panel.name = "AngryMurlocs"

  local scroll = CreateFrame("ScrollFrame", "AngryMurlocsOptionsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(520, 920)
  scroll:SetScrollChild(content)

  local y = -16
  local function Next(dy)
    y = y - (dy or 28)
    return y
  end

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, y)
  title:SetText("AngryMurlocs")

  local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 16, Next(24))
  sub:SetText("Angry Murlocs — Forever")

  local function Header(key)
    local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h:SetPoint("TOPLEFT", 16, Next(32))
    h:SetText(U.L(key))
    return h
  end

  local function Check(labelKey, getter, setter)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, Next(28))
    local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(U.L(labelKey))
    cb:SetScript("OnShow", function(self)
      self:SetChecked(getter())
    end)
    cb:SetScript("OnClick", function(self)
      setter(self:GetChecked())
    end)
    return cb
  end

  local sliderSeq = 0
  local function Slider(labelKey, minV, maxV, step, getter, setter, fmt)
    local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", 24, Next(30))
    local valueText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", label, "RIGHT", 8, 0)

    sliderSeq = sliderSeq + 1
    local name = "AngryMurlocsOptSlider" .. sliderSeq
    local slider = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 24, Next(28))
    slider:SetWidth(220)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then
      slider:SetObeyStepOnDrag(true)
    end
    _G[name .. "Low"]:SetText(tostring(minV))
    _G[name .. "High"]:SetText(tostring(maxV))
    _G[name .. "Text"]:SetText("")

    local function RefreshLabel(v)
      label:SetText(U.L(labelKey))
      valueText:SetText(fmt and fmt(v) or tostring(v))
    end

    slider:SetScript("OnShow", function(self)
      local v = getter()
      self:SetValue(v)
      RefreshLabel(v)
    end)
    slider:SetScript("OnValueChanged", function(_, value)
      local v = value
      if step >= 1 then
        v = math.floor(value + 0.5)
      else
        v = math.floor(value * 10 + 0.5) / 10
      end
      setter(v)
      RefreshLabel(v)
    end)
    return slider
  end

  local function Button(labelKey, onClick, width)
    local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    btn:SetSize(width or 140, 22)
    btn:SetPoint("TOPLEFT", 24, Next(30))
    btn:SetText(U.L(labelKey))
    btn:SetScript("OnClick", onClick)
    return btn
  end

  Header("OPT_SEC_PRIVACY")
  Check("OPT_SHARE_POS", function()
    return GR.db.privacy.sharePosition
  end, function(v)
    GR.db.privacy.sharePosition = v and true or false
    GR:SendMessage("SHARE_POS_CHANGED")
  end)
  Check("OPT_POS_OOC", function()
    return GR.db.privacy.suppressInCombat ~= false
  end, function(v)
    GR.db.privacy.suppressInCombat = v and true or false
  end)
  Check("OPT_POS_NO_BG", function()
    return GR.db.privacy.suppressInBg ~= false
  end, function(v)
    GR.db.privacy.suppressInBg = v and true or false
  end)
  Check("OPT_SHARE_PROF", function()
    return GR.db.privacy.shareProfessions
  end, function(v)
    GR.db.privacy.shareProfessions = v and true or false
    GR:SendMessage("SHARE_PROF_CHANGED")
  end)
  Check("OPT_SHARE_DEATH", function()
    return GR.db.privacy.shareDeath
  end, function(v)
    GR.db.privacy.shareDeath = v and true or false
  end)
  Check("OPT_SHARE_LVL", function()
    return GR.db.privacy.shareLevelUp
  end, function(v)
    GR.db.privacy.shareLevelUp = v and true or false
  end)
  Check("OPT_SHARE_SIGHT", function()
    return GR.db.privacy.shareSightings ~= false
  end, function(v)
    GR.db.privacy.shareSightings = v and true or false
  end)
  Check("OPT_SHOW_SIGHT_ALERT", function()
    return not GR.db.wantedUI or GR.db.wantedUI.showSightAlerts ~= false
  end, function(v)
    GR.db.wantedUI = GR.db.wantedUI or {}
    GR.db.wantedUI.showSightAlerts = v and true or false
  end)

  Header("OPT_SEC_MAP")
  Check("OPT_SHOW_PINS", function()
    return GR.db.map.showPins
  end, function(v)
    GR.db.map.showPins = v and true or false
    GR:SendMessage("MAP_SETTINGS_CHANGED")
  end)
  Slider("OPT_PIN_SIZE", 8, 24, 1, function()
    return GR.db.map.pinSize or 18
  end, function(v)
    GR.db.map.pinSize = v
    GR:SendMessage("MAP_SETTINGS_CHANGED")
  end)

  Header("OPT_SEC_LVL_TOAST")
  Check("OPT_SHOW_LVL_TOAST", function()
    return EnsureLvlCfg().showToasts
  end, function(v)
    EnsureLvlCfg().showToasts = v and true or false
  end)
  Check("OPT_LOCK_LVL_TOAST", function()
    return EnsureLvlCfg().locked
  end, function(v)
    EnsureLvlCfg().locked = v and true or false
  end)
  Slider("OPT_SCALE_LVL_TOAST", 0.6, 1.6, 0.1, function()
    return EnsureLvlCfg().scale or 1
  end, function(v)
    EnsureLvlCfg().scale = v
  end, function(v) return string.format("%.1f", v) end)
  Slider("OPT_DUR_LVL_TOAST", 1.5, 15, 0.5, function()
    return EnsureLvlCfg().duration or 8.0
  end, function(v)
    EnsureLvlCfg().duration = v
  end, function(v) return string.format("%.1fs", v) end)
  Button("OPT_PREVIEW_LVL", function()
    local mod = GR:GetModule("LevelUp")
    if mod and mod.Preview then mod:Preview() end
  end)

  Header("OPT_SEC_DEATH_TOAST")
  Check("OPT_SHOW_DEATH_TOAST", function()
    return EnsureDeathCfg().showToasts
  end, function(v)
    EnsureDeathCfg().showToasts = v and true or false
  end)
  Check("OPT_LOCK_DEATH_TOAST", function()
    return EnsureDeathCfg().locked
  end, function(v)
    EnsureDeathCfg().locked = v and true or false
  end)
  Slider("OPT_SCALE_DEATH_TOAST", 0.6, 1.6, 0.1, function()
    return EnsureDeathCfg().scale or 1
  end, function(v)
    EnsureDeathCfg().scale = v
  end, function(v) return string.format("%.1f", v) end)
  Slider("OPT_DUR_DEATH_TOAST", 1.5, 15, 0.5, function()
    return EnsureDeathCfg().duration or 10.0
  end, function(v)
    EnsureDeathCfg().duration = v
  end, function(v) return string.format("%.1fs", v) end)
  Button("OPT_PREVIEW_DEATH", function()
    local mod = GR:GetModule("Death")
    if mod and mod.Preview then mod:Preview() end
  end)

  Header("OPT_SEC_LAYOUT")
  local hint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 24, Next(28))
  hint:SetWidth(460)
  hint:SetJustifyH("LEFT")
  hint:SetText(U.L("OPT_LAYOUT_HINT"))

  Button("OPT_RESET_LAYOUT", function()
    local death = GR:GetModule("Death")
    local lvl = GR:GetModule("LevelUp")
    if death and death.ResetLayout then death:ResetLayout() end
    if lvl and lvl.ResetLayout then lvl:ResetLayout() end
    GR.db.frames = GR.db.frames or {}
    GR.db.frames.professions = GR.db.frames.professions or {}
    GR.db.frames.wanted = GR.db.frames.wanted or {}
    GR.db.frames.craft = GR.db.frames.craft or {}
    GR.db.frames.main = GR.db.frames.main or {}
    GR.db.frames.professions.point = nil
    GR.db.frames.wanted.point = nil
    GR.db.frames.craft.point = nil
    GR.db.frames.main.point = nil
    if AngryMurlocsFrame then
      U.ApplyPoint(AngryMurlocsFrame, nil, function(f)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end)
    end
    if AngryMurlocsWantedFrame then
      U.ApplyPoint(AngryMurlocsWantedFrame, nil, function(f)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      end)
    end
    if AngryMurlocsCraftFrame then
      U.ApplyPoint(AngryMurlocsCraftFrame, nil, function(f)
        f:SetPoint("CENTER", UIParent, "CENTER", -40, 20)
      end)
    end
    if AngryMurlocsMainFrame then
      U.ApplyPoint(AngryMurlocsMainFrame, nil, function(f)
        f:SetPoint("CENTER", UIParent, "CENTER", 80, 40)
      end)
    end
    U.Print(U.L("OPT_RESET_DONE"))
  end, 180)

  content:SetHeight(math.abs(y) + 80)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end
