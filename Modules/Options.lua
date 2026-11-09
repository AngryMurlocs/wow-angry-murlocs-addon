local GR = AngryMurlocs
local U = GR.Util
local T = GR.Theme

local Options = GR:NewModule("Options")

local optionsPanel
local optionsCategory
local attached
local optCatBtns = {}
local optCatHosts = {}
local activeOptCat = "privacy"
local detailHost
local layoutCallbacks = {}

local CAT_ALIASES = {
  notify = "lvl",
  messages = "lvl",
  layout = "ui",
}

local layoutEditing = false
local layoutEditKind = nil
local layoutEditBtns = {}

local soundMenu
local soundMenuKind
local soundPickBtns = {}

local GROUP_GAP = 30
local HINT_GAP = 8
local NAV_W = 130
local NAV_ROW_H = 22
local SCROLLBAR_W = 24
local TILE_H = 52
local CB_MIN_H = 26
local BTN_H = 22
local SLIDER_H = 28
local LABEL_MIN_H = 14

local PIN_PREVIEW_CLASS = "MAGE"
local PIN_BASE_BODY = "Interface\\AddOns\\AngryMurlocs\\Media\\Pins\\"
local PIN_BASE_HEADS = "Interface\\AddOns\\AngryMurlocs\\Media\\PinsHeads\\"
local CIRCLE_TEX = "Interface\\AddOns\\AngryMurlocs\\Media\\circle"
local RING_INNER_FRAC = 0.68
local GOLD_R, GOLD_G, GOLD_B = 1, 0.92, 0.12
local HEAD_UV_MAGE = { 0.0766, 0.9703, 0.0277, 0.9645 }
local BODY_UV_MAGE = { 0.1258, 0.8430, 0.0008, 0.9992 }

local function HideSoundMenu()
  if soundMenu then
    soundMenu:Hide()
  end
  soundMenuKind = nil
end

local function RefreshLayoutEditButtons()
  local label = layoutEditing and U.L("OPT_LAYOUT_EDIT_DONE") or U.L("OPT_LAYOUT_EDIT")
  for _, btn in pairs(layoutEditBtns) do
    if btn and btn.SetText then
      btn:SetText(label)
    end
  end
end

local function EndLayoutEditMode()
  if not layoutEditing then return end
  layoutEditing = false
  layoutEditKind = nil
  local lvl = GR:GetModule("LevelUp")
  local death = GR:GetModule("Death")
  if lvl and lvl.EndLayoutEdit then lvl:EndLayoutEdit() end
  if death and death.EndLayoutEdit then death:EndLayoutEdit() end
  if GR.ToastQueue and GR.ToastQueue.Resume then
    GR.ToastQueue.Resume()
  end
  RefreshLayoutEditButtons()
end

local function BeginLayoutEditMode(kind)
  if kind ~= "lvl" and kind ~= "death" then return end
  if layoutEditing and layoutEditKind == kind then
    EndLayoutEditMode()
    return
  end
  if layoutEditing then
    EndLayoutEditMode()
  end
  layoutEditing = true
  layoutEditKind = kind
  if GR.ToastQueue then
    GR.ToastQueue.Pause()
    GR.ToastQueue.FinishCurrent()
  end
  if kind == "lvl" then
    local lvl = GR:GetModule("LevelUp")
    if lvl and lvl.BeginLayoutEdit then lvl:BeginLayoutEdit() end
  elseif kind == "death" then
    local death = GR:GetModule("Death")
    if death and death.BeginLayoutEdit then death:BeginLayoutEdit() end
  end
  RefreshLayoutEditButtons()
end

local function DismissOverlays()
  HideSoundMenu()
  EndLayoutEditMode()
end

function Options:EndLayoutEdit()
  DismissOverlays()
end

function Options:DismissOverlays()
  DismissOverlays()
end

function Options:IsLayoutEdit()
  return layoutEditing
end

function Options:GetLayoutEditKind()
  return layoutEditKind
end

function Options:IsSoundMenuShown()
  return soundMenu and soundMenu:IsShown() and true or false
end

function Options:BeginLayoutEdit(kind)
  BeginLayoutEditMode(kind)
end

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

function Options:OpenAddonWindow()
  local ui = GR:GetModule("UI")
  if ui and ui.ShowTab then
    ui:ShowTab("opt")
  end
end

function Options:Open()
  if optionsCategory and Settings and Settings.OpenToCategory then
    local id = optionsCategory
    if type(optionsCategory.GetID) == "function" then
      id = optionsCategory:GetID()
    end
    local ok = pcall(Settings.OpenToCategory, id)
    if ok then return end
  end
  if optionsPanel and InterfaceOptionsFrame_OpenToCategory then
    local ok = pcall(InterfaceOptionsFrame_OpenToCategory, optionsPanel)
    if ok then return end
  end
  Options:OpenAddonWindow()
end

local function ResolveCategoryId(id)
  id = CAT_ALIASES[id] or id
  if not optCatHosts[id] then
    return "privacy"
  end
  return id
end

local function ContentInnerWidth()
  local inset = (T and T.INSET) or 8
  local w = detailHost and detailHost.GetWidth and detailHost:GetWidth() or 0
  if not w or w < 80 then
    w = 470
  end
  return math.max(160, math.floor(w - SCROLLBAR_W - inset))
end

local function ApplyContentWidths()
  local innerW = ContentInnerWidth()
  for _, host in pairs(optCatHosts) do
    if host._amContent then
      host._amContent:SetWidth(innerW)
    end
  end
  for i = 1, #layoutCallbacks do
    layoutCallbacks[i](innerW)
  end
end

function Options:ShowCategory(id)
  id = ResolveCategoryId(id)
  HideSoundMenu()
  EndLayoutEditMode()
  activeOptCat = id
  for catId, host in pairs(optCatHosts) do
    if catId == id then host:Show() else host:Hide() end
  end
  for catId, btn in pairs(optCatBtns) do
    local active = catId == id
    btn._amNavActive = active
    if T and T.StyleNavRow then
      T.StyleNavRow(btn, active)
    elseif T and T.StyleTabButton then
      T.StyleTabButton(btn, active)
    end
  end
  local host = optCatHosts[id]
  if host and host._amContent then
    local h = host._amHeight or host._amContent:GetHeight() or 200
    if h < 80 then h = 80 end
    host._amContent:SetHeight(h)
    if host._amScroll and host._amScroll.SetVerticalScroll then
      host._amScroll:SetVerticalScroll(0)
    end
  end
  ApplyContentWidths()
end

function Options:GetActiveCategory()
  return activeOptCat
end

-- Compat: message kinds are first-class sidebar sections.
function Options:ShowMessageKind(kind)
  if kind ~= "lvl" and kind ~= "death" and kind ~= "sight" then
    kind = "lvl"
  end
  Options:ShowCategory(kind)
end

function Options:GetActiveMessageKind()
  if activeOptCat == "lvl" or activeOptCat == "death" or activeOptCat == "sight" then
    return activeOptCat
  end
  return nil
end

function Options:GetMessagePanel(kind)
  local host = optCatHosts[kind]
  return host and host._amPanel or nil
end

local function EnsureSoundMenu()
  if soundMenu then return soundMenu end
  soundMenu = CreateFrame("Frame", "AngryMurlocsOptSoundMenu", UIParent)
  soundMenu:SetFrameStrata("DIALOG")
  soundMenu:SetSize(200, 120)
  if T and T.ApplyPanelBackdrop then
    T.ApplyPanelBackdrop(soundMenu, T.BG)
  end
  soundMenu:Hide()
  soundMenu:EnableMouse(true)
  soundMenu.buttons = {}

  if GR.Sounds and GR.Sounds.Ensure then GR.Sounds.Ensure() end
  local list = (GR.Sounds and GR.Sounds.List and GR.Sounds.List()) or {}
  local y = -4
  for i = 1, #list do
    local entry = list[i]
    local b = CreateFrame("Button", nil, soundMenu, "UIPanelButtonTemplate")
    b:SetSize(188, 18)
    b:SetPoint("TOPLEFT", 6, y)
    b:SetText(U.L("OPT_SOUND_ID_" .. entry.id) or entry.id)
    b._amSoundId = entry.id
    b:SetScript("OnClick", function(self)
      local kind = soundMenuKind
      if kind and GR.Sounds and GR.Sounds.SetId then
        GR.Sounds.SetId(kind, self._amSoundId)
      end
      local pick = kind and soundPickBtns[kind]
      if pick and pick._amRefresh then pick._amRefresh() end
      HideSoundMenu()
    end)
    soundMenu.buttons[i] = b
    y = y - 20
  end
  soundMenu:SetHeight(math.abs(y) + 8)
  return soundMenu
end

local function ToggleSoundMenu(kind, anchor)
  if soundMenu and soundMenu:IsShown() and soundMenuKind == kind then
    HideSoundMenu()
    return
  end
  local menu = EnsureSoundMenu()
  soundMenuKind = kind
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  menu:Show()
  if menu.Raise then menu:Raise() end
end

local function RefreshLooks()
  local lvl = GR:GetModule("LevelUp")
  local death = GR:GetModule("Death")
  if lvl and lvl.RefreshLayout then lvl:RefreshLayout() end
  if death and death.RefreshLayout then death:RefreshLayout() end
end

function Options:AttachPanel(parent)
  if attached or not parent then return end
  attached = true

  local inset = (T and T.INSET) or 8

  local nav = CreateFrame("Frame", nil, parent)
  nav:SetPoint("TOPLEFT", 0, 0)
  nav:SetPoint("BOTTOMLEFT", 0, 0)
  nav:SetWidth(NAV_W)

  detailHost = CreateFrame("Frame", nil, parent)
  detailHost:SetPoint("TOPLEFT", nav, "TOPRIGHT", 4, 0)
  detailHost:SetPoint("BOTTOMRIGHT", 0, 0)
  detailHost:SetScript("OnSizeChanged", function()
    ApplyContentWidths()
  end)

  local sectionIds = { "privacy", "map", "lvl", "death", "sight", "ui" }
  for i = 1, #sectionIds do
    local id = sectionIds[i]
    local host = CreateFrame("Frame", nil, detailHost)
    host:SetAllPoints()
    host:Hide()
    optCatHosts[id] = host

    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_W, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ContentInnerWidth(), 400)
    scroll:SetScrollChild(content)
    host._amContent = content
    host._amScroll = scroll
  end

  -- Sidebar nav items (flat rows, not UIPanel buttons)
  local navY = -4
  local function NavButton(id, key, indent)
    local b = CreateFrame("Button", nil, nav)
    local w = NAV_W - 4 - (indent or 0)
    b:SetSize(w, NAV_ROW_H)
    b:SetPoint("TOPLEFT", 2 + (indent or 0), navY)
    b._amNavText = U.L(key)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function()
      Options:ShowCategory(id)
    end)
    if T and T.WireNavRowHover then T.WireNavRowHover(b) end
    if T and T.StyleNavRow then T.StyleNavRow(b, false) end
    optCatBtns[id] = b
    navY = navY - (NAV_ROW_H + 2)
    return b
  end

  local function NavHeader(key)
    local h = nav:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 8, navY - 4)
    h:SetWidth(NAV_W - 12)
    h:SetJustifyH("LEFT")
    h:SetText(U.L(key))
    if T and T.SetTextColor and T.MUTED then
      T.SetTextColor(h, T.MUTED)
    end
    navY = navY - 18
    return h
  end

  NavButton("privacy", "OPT_SEC_PRIVACY")
  NavButton("map", "OPT_SEC_MAP")
  NavHeader("OPT_SEC_NOTIFY")
  NavButton("lvl", "GENERAL_KIND_LVL", 10)
  NavButton("death", "GENERAL_KIND_DEATH", 10)
  NavButton("sight", "GENERAL_KIND_SIGHT", 10)
  navY = navY - 12
  NavButton("ui", "OPT_SEC_LAYOUT")

  local function BuildHelpers(content)
    local y = -4
    local innerW = ContentInnerWidth()
    local firstGroup = true

    -- y = next free top edge. Place reserves height before the next widget.
    local function Place(height, gapBefore, gapAfter)
      y = y - (gapBefore or 0)
      local top = y
      y = y - height - (gapAfter or 4)
      return top
    end

    local function MeasureFS(fs, fallback)
      local h = fs and fs.GetStringHeight and fs:GetStringHeight() or 0
      if not h or h < 8 then h = fallback or LABEL_MIN_H end
      return h
    end

    local function PageTitle(key)
      local top = Place(0, 4, 0)
      local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
      h:SetPoint("TOPLEFT", 8, top)
      h:SetText(U.L(key))
      if T and T.SetTextColor and T.ACCENT then
        T.SetTextColor(h, T.ACCENT)
      else
        h:SetTextColor(0.25, 0.78, 0.35)
      end
      local th = MeasureFS(h, 18)
      y = top - th - 8
      firstGroup = true
      return h
    end

    local function GroupLabel(key)
      local gap = firstGroup and 10 or GROUP_GAP
      firstGroup = false
      local top = Place(0, gap, 0)
      local h = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      h:SetPoint("TOPLEFT", 8, top)
      h:SetText(U.L(key))
      if T and T.SetTextColor and T.TEXT then
        T.SetTextColor(h, T.TEXT)
      end
      local th = MeasureFS(h, 14)
      y = top - th - 6
      return h
    end

    local function Check(labelKey, getter, setter, indent)
      local x = indent or 8
      local top = Place(0, 2, 0)
      local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
      cb:SetPoint("TOPLEFT", x, top)
      local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      text:SetPoint("TOPLEFT", cb, "TOPRIGHT", 4, -2)
      text:SetWidth(math.max(80, innerW - x - 36))
      text:SetJustifyH("LEFT")
      if text.SetWordWrap then text:SetWordWrap(true) end
      text:SetText(U.L(labelKey))
      local cbH = (cb.GetHeight and cb:GetHeight()) or CB_MIN_H
      if cbH < CB_MIN_H then cbH = CB_MIN_H end
      local th = MeasureFS(text, 12)
      local rowH = math.max(cbH, th + 2)
      y = top - rowH - 4
      cb:SetScript("OnShow", function(self)
        self:SetChecked(getter())
      end)
      cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
      end)
      return cb, text
    end

    local function CheckIndent(labelKey, getter, setter)
      return Check(labelKey, getter, setter, 28)
    end

    local sliderSeq = 0
    local function Slider(labelKey, minV, maxV, step, getter, setter, fmt, lowHighFmt)
      local labelTop = Place(0, 4, 0)
      local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      label:SetPoint("TOPLEFT", 16, labelTop)
      local valueText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      valueText:SetPoint("LEFT", label, "RIGHT", 8, 0)
      local lh = MeasureFS(label, LABEL_MIN_H)
      y = labelTop - lh - 2

      sliderSeq = sliderSeq + 1
      local name = "AngryMurlocsOptSlider_" .. tostring(content):gsub("[^%w]", "") .. "_" .. sliderSeq
      local sliderTop = Place(SLIDER_H, 0, 6)
      local slider = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
      slider:SetPoint("TOPLEFT", 16, sliderTop)
      local sliderW = math.min(220, math.max(140, innerW - 32))
      slider:SetWidth(sliderW)
      slider:SetMinMaxValues(minV, maxV)
      slider:SetValueStep(step)
      if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
      end
      local low = lowHighFmt and lowHighFmt(minV) or tostring(minV)
      local high = lowHighFmt and lowHighFmt(maxV) or tostring(maxV)
      if _G[name .. "Low"] then _G[name .. "Low"]:SetText(low) end
      if _G[name .. "High"] then _G[name .. "High"]:SetText(high) end
      if _G[name .. "Text"] then _G[name .. "Text"]:SetText("") end

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

    local function Button(labelKey, onClick, width, gapBefore)
      local top = Place(BTN_H, gapBefore or 4, 6)
      local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
      local bw = width or 140
      if bw > innerW - 32 then bw = math.max(100, innerW - 32) end
      btn:SetSize(bw, BTN_H)
      btn:SetPoint("TOPLEFT", 16, top)
      btn:SetText(U.L(labelKey))
      btn:SetScript("OnClick", onClick)
      return btn
    end

    local function FitResetButtons(defs)
      local pad = 16
      local gap = 8
      local avail = math.max(100, innerW - pad)
      local preferred = {}
      local total = 0
      for i = 1, #defs do
        preferred[i] = defs[i].width or 170
        total = total + preferred[i]
      end
      total = total + gap * (#defs - 1)
      local btns = {}
      if #defs >= 2 and total <= avail then
        local yRow = Place(BTN_H, 4, 6)
        local x = pad
        for i = 1, #defs do
          local d = defs[i]
          local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
          btn:SetSize(preferred[i], BTN_H)
          btn:SetPoint("TOPLEFT", x, yRow)
          btn:SetText(U.L(d.key))
          btn:SetScript("OnClick", d.onClick)
          btns[i] = btn
          x = x + preferred[i] + gap
        end
      else
        for i = 1, #defs do
          local d = defs[i]
          local bw = math.min(preferred[i], avail)
          if bw < 120 then bw = avail end
          local top = Place(BTN_H, 4, 4)
          local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
          btn:SetSize(bw, BTN_H)
          btn:SetPoint("TOPLEFT", pad, top)
          btn:SetText(U.L(d.key))
          btn:SetScript("OnClick", d.onClick)
          btns[i] = btn
        end
      end
      return btns
    end

    local function Note(labelKey, indent)
      indent = indent or 36
      local top = Place(0, 2, 0)
      local note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      note:SetPoint("TOPLEFT", indent, top)
      local nw = math.max(80, innerW - indent - 8)
      note:SetWidth(nw)
      note:SetJustifyH("LEFT")
      if note.SetWordWrap then note:SetWordWrap(true) end
      note:SetText(U.L(labelKey))
      local h = MeasureFS(note, 28)
      y = top - h - 4
      return note
    end

    local function Hint(labelKey, indent)
      indent = indent or 16
      local top = Place(0, 4, 0)
      local hint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      hint:SetPoint("TOPLEFT", indent, top)
      local nw = math.max(80, innerW - indent - 8)
      hint:SetWidth(nw)
      hint:SetJustifyH("LEFT")
      if hint.SetWordWrap then hint:SetWordWrap(true) end
      hint:SetText(U.L(labelKey))
      if T and T.SetTextColor and T.MUTED then
        T.SetTextColor(hint, T.MUTED)
      end
      local h = MeasureFS(hint, 16)
      y = top - h - HINT_GAP
      return hint
    end

    local function Finish()
      local height = math.abs(y) + 24
      content:SetWidth(innerW)
      content:SetHeight(height)
      return height
    end

    return {
      Place = Place,
      PageTitle = PageTitle,
      GroupLabel = GroupLabel,
      Check = Check,
      CheckIndent = CheckIndent,
      Slider = Slider,
      Button = Button,
      FitResetButtons = FitResetButtons,
      Note = Note,
      Hint = Hint,
      Finish = Finish,
      innerW = function() return innerW end,
      y = function() return y end,
      content = content,
    }
  end

  -- Freigaben
  do
    local host = optCatHosts.privacy
    local content = host._amContent
    local H = BuildHelpers(content)
    H.PageTitle("OPT_SEC_PRIVACY")
    H.GroupLabel("OPT_GRP_POS")
    H.Check("OPT_SHARE_POS", function()
      return GR.db.privacy.sharePosition
    end, function(v)
      GR.db.privacy.sharePosition = v and true or false
      GR:SendMessage("SHARE_POS_CHANGED")
    end)
    H.CheckIndent("OPT_POS_OOC", function()
      return GR.db.privacy.suppressInCombat ~= false
    end, function(v)
      GR.db.privacy.suppressInCombat = v and true or false
      GR:SendMessage("PRIVACY_CHANGED")
    end)
    H.CheckIndent("OPT_POS_NO_BG", function()
      return GR.db.privacy.suppressInBg ~= false
    end, function(v)
      GR.db.privacy.suppressInBg = v and true or false
    end)
    H.CheckIndent("OPT_SUPPRESS_INSTANCE", function()
      return GR.db.privacy.suppressInInstance == true
    end, function(v)
      GR.db.privacy.suppressInInstance = v and true or false
    end)

    H.GroupLabel("OPT_GRP_MORE_DATA")
    H.Check("OPT_SHARE_PROF", function()
      return GR.db.privacy.shareProfessions
    end, function(v)
      GR.db.privacy.shareProfessions = v and true or false
      GR:SendMessage("SHARE_PROF_CHANGED")
    end)
    H.Check("OPT_SHARE_DEATH", function()
      return GR.db.privacy.shareDeath
    end, function(v)
      GR.db.privacy.shareDeath = v and true or false
      GR:SendMessage("PRIVACY_CHANGED")
    end)
    H.Note("OPT_SHARE_DEATH_NOTE")
    H.Check("OPT_SHARE_LVL", function()
      return GR.db.privacy.shareLevelUp
    end, function(v)
      GR.db.privacy.shareLevelUp = v and true or false
      GR:SendMessage("PRIVACY_CHANGED")
    end)
    H.Check("OPT_SHARE_SIGHT", function()
      return GR.db.privacy.shareSightings ~= false
    end, function(v)
      GR.db.privacy.shareSightings = v and true or false
      GR:SendMessage("PRIVACY_CHANGED")
    end)
    H.Note("OPT_PRIVACY_NOTE")
    host._amHeight = H.Finish()
  end

  -- Karte
  do
    local host = optCatHosts.map
    local content = host._amContent
    local H = BuildHelpers(content)
    local innerW = H.innerW()
    H.PageTitle("OPT_SEC_MAP")
    H.Check("OPT_SHOW_PINS", function()
      return GR.db.map.showPins
    end, function(v)
      GR.db.map.showPins = v and true or false
      GR:SendMessage("MAP_SETTINGS_CHANGED")
    end)

    H.GroupLabel("OPT_PIN_STYLE")
    H.Hint("OPT_PIN_STYLE_HINT")

    local styleBtns = {}
    local styleTiles = {}
    local function CurrentPinStyle()
      local cur = GR.db.map and GR.db.map.pinStyle or "heads"
      if cur ~= "body" and cur ~= "heads" and cur ~= "rings" then
        return "heads"
      end
      return cur
    end
    local function RefreshStyleBtns()
      local cur = CurrentPinStyle()
      for id, b in pairs(styleBtns) do
        if T and T.StyleTabButton then
          T.StyleTabButton(b, id == cur)
        end
      end
    end
    local function SetPinStyle(style)
      GR.db.map = GR.db.map or {}
      GR.db.map.pinStyle = style
      RefreshStyleBtns()
      GR:SendMessage("MAP_SETTINGS_CHANGED")
    end

    local styleY = H.Place(TILE_H, 8, 8)
    local styleDefs = {
      { id = "heads", key = "OPT_PIN_STYLE_HEADS" },
      { id = "body", key = "OPT_PIN_STYLE_BODY" },
      { id = "rings", key = "OPT_PIN_STYLE_RINGS" },
    }
    local pad = 8
    local gap = 8
    local n = #styleDefs
    local tileW = math.floor((innerW - pad * 2 - gap * (n - 1)) / n)
    if tileW < 90 then tileW = 90 end
    local r, g, b = U.ClassColor(PIN_PREVIEW_CLASS)

    local function LayoutPinTiles(w)
      local tw = math.floor((w - pad * 2 - gap * (n - 1)) / n)
      if tw < 90 then tw = 90 end
      for i = 1, #styleTiles do
        local tile = styleTiles[i]
        tile:SetWidth(tw)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", pad + (i - 1) * (tw + gap), styleY)
      end
    end

    for i = 1, #styleDefs do
      local d = styleDefs[i]
      local tile = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
      tile:SetSize(tileW, TILE_H)
      tile:SetPoint("TOPLEFT", pad + (i - 1) * (tileW + gap), styleY)
      tile:SetText("")
      tile:SetScript("OnClick", function()
        SetPinStyle(d.id)
      end)
      tile:SetScript("OnShow", RefreshStyleBtns)

      local preview = CreateFrame("Frame", nil, tile)
      preview:SetSize(28, 28)
      preview:SetPoint("TOP", 0, -4)
      preview:EnableMouse(false)

      local glow = preview:CreateTexture(nil, "BACKGROUND")
      local icon = preview:CreateTexture(nil, "ARTWORK")
      if d.id == "rings" then
        glow:SetTexture(CIRCLE_TEX)
        glow:SetAllPoints()
        glow:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 1)
        icon:SetTexture(CIRCLE_TEX)
        local inner = 28 * RING_INNER_FRAC
        icon:SetSize(inner, inner)
        icon:SetPoint("CENTER")
        icon:SetVertexColor(r * 0.78, g * 0.78, b * 0.78, 1)
      else
        local base = (d.id == "body") and PIN_BASE_BODY or PIN_BASE_HEADS
        local uv = (d.id == "body") and BODY_UV_MAGE or HEAD_UV_MAGE
        icon:SetTexture(base .. PIN_PREVIEW_CLASS)
        icon:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
        icon:SetAllPoints()
        glow:SetTexture(base .. PIN_PREVIEW_CLASS)
        glow:SetTexCoord(uv[1], uv[2], uv[3], uv[4])
        glow:SetPoint("CENTER")
        glow:SetSize(36, 36)
        glow:SetVertexColor(r, g, b, 0.55)
        if glow.SetBlendMode then
          pcall(glow.SetBlendMode, glow, "ADD")
        end
      end

      local label = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("BOTTOM", 0, 6)
      label:SetWidth(tileW - 8)
      label:SetText(U.L(d.key))

      styleBtns[d.id] = tile
      styleTiles[i] = tile
    end
    layoutCallbacks[#layoutCallbacks + 1] = LayoutPinTiles

    H.Slider("OPT_PIN_SIZE", 8, 24, 1, function()
      return GR.db.map.pinSize or 18
    end, function(v)
      GR.db.map.pinSize = v
      GR:SendMessage("MAP_SETTINGS_CHANGED")
    end)

    H.Check("OPT_PIN_CLUSTERING", function()
      return not GR.db.map or GR.db.map.pinClustering ~= false
    end, function(v)
      GR.db.map = GR.db.map or {}
      GR.db.map.pinClustering = v and true or false
      GR:SendMessage("MAP_SETTINGS_CHANGED")
    end)
    host._amHeight = H.Finish()
  end

  local function SoundRow(H, content, kind)
    if GR.Sounds and GR.Sounds.Ensure then GR.Sounds.Ensure() end
    local innerW = H.innerW()
    H.Check("OPT_SOUND_ENABLE", function()
      local c = GR.Sounds and GR.Sounds.Get and GR.Sounds.Get(kind)
      return c and c.enabled == true
    end, function(v)
      if GR.Sounds and GR.Sounds.SetEnabled then GR.Sounds.SetEnabled(kind, v) end
    end)
    local pickW = math.min(220, math.max(120, innerW - 140))
    local sideBySide = pickW + 16 + 108 <= innerW
    local rowTop = H.Place(BTN_H, 4, 6)
    local pick = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    pick:SetSize(pickW, BTN_H)
    pick:SetPoint("TOPLEFT", 16, rowTop)
    local function RefreshPick()
      local c = GR.Sounds and GR.Sounds.Get and GR.Sounds.Get(kind)
      local id = c and c.id or "?"
      pick:SetText(string.format(U.L("OPT_SOUND_PICK"), U.L("OPT_SOUND_ID_" .. id) or id))
    end
    pick._amRefresh = RefreshPick
    pick:SetScript("OnShow", RefreshPick)
    pick:SetScript("OnClick", function(self)
      ToggleSoundMenu(kind, self)
    end)
    soundPickBtns[kind] = pick

    local prev = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    prev:SetSize(100, BTN_H)
    if sideBySide then
      prev:SetPoint("LEFT", pick, "RIGHT", 8, 0)
    else
      local prevTop = H.Place(BTN_H, 4, 6)
      prev:SetPoint("TOPLEFT", 16, prevTop)
    end
    prev:SetText(U.L("OPT_SOUND_PREVIEW"))
    prev:SetScript("OnClick", function()
      if GR.Sounds and GR.Sounds.Preview then GR.Sounds.Preview(kind) end
    end)
  end

  local function BuildToastSection(kind)
    local host = optCatHosts[kind]
    local content = host._amContent
    host._amPanel = content
    local H = BuildHelpers(content)
    local cfgFn = (kind == "lvl") and EnsureLvlCfg or EnsureDeathCfg
    local previewMod = (kind == "lvl") and "LevelUp" or "Death"
    local defaultDur = (kind == "lvl") and 8.0 or 10.0
    local titleKey = (kind == "lvl") and "GENERAL_KIND_LVL" or "GENERAL_KIND_DEATH"
    H.PageTitle(titleKey)

    H.GroupLabel("OPT_GRP_SHOW")
    local showCb, showText = H.Check("OPT_SHOW_MSG", function()
      return cfgFn().showToasts
    end, function(v)
      cfgFn().showToasts = v and true or false
    end)
    local previewBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    previewBtn:SetSize(100, BTN_H)
    previewBtn:SetPoint("LEFT", showText, "RIGHT", 12, 0)
    previewBtn:SetText(U.L("OPT_PREVIEW"))
    previewBtn:SetScript("OnClick", function()
      local mod = GR:GetModule(previewMod)
      if mod and mod.Preview then mod:Preview() end
    end)
    content._amShowCheck = showCb
    content._amPreviewBtn = previewBtn

    H.GroupLabel("OPT_GRP_SOUND")
    SoundRow(H, content, kind)

    H.GroupLabel("OPT_GRP_LOOK")
    H.Slider("OPT_SCALE", 0.6, 1.6, 0.1, function()
      return cfgFn().scale or 1
    end, function(v)
      cfgFn().scale = v
      RefreshLooks()
    end, function(v)
      return string.format("%d%%", math.floor(v * 100 + 0.5))
    end, function(v)
      return string.format("%d%%", math.floor(v * 100 + 0.5))
    end)
    content._amHasScale = true
    H.Slider("OPT_DURATION", 1.5, 15, 0.5, function()
      return cfgFn().duration or defaultDur
    end, function(v)
      cfgFn().duration = v
    end, function(v)
      return string.format("%.1fs", v)
    end)

    H.GroupLabel("OPT_GRP_POS")
    H.Check("OPT_LOCK_POS", function()
      return cfgFn().locked
    end, function(v)
      cfgFn().locked = v and true or false
      RefreshLooks()
    end)
    local editBtn = H.Button("OPT_LAYOUT_EDIT", function()
      BeginLayoutEditMode(kind)
    end, 180)
    layoutEditBtns[kind] = editBtn
    content._amEditBtn = editBtn

    H.FitResetButtons({
      {
        key = "OPT_RESET_POS",
        width = 170,
        onClick = function()
          local mod = GR:GetModule(previewMod)
          if mod and mod.ResetPosition then mod:ResetPosition() end
          U.Print(U.L("OPT_RESET_DONE"))
        end,
      },
      {
        key = "OPT_RESET_LOOK",
        width = 210,
        onClick = function()
          local mod = GR:GetModule(previewMod)
          if mod and mod.ResetAppearance then mod:ResetAppearance() end
          U.Print(U.L("OPT_RESET_DONE"))
        end,
      },
    })

    host._amHeight = H.Finish()
  end

  BuildToastSection("lvl")
  BuildToastSection("death")

  -- Sichtungen
  do
    local host = optCatHosts.sight
    local content = host._amContent
    host._amPanel = content
    local H = BuildHelpers(content)
    H.PageTitle("GENERAL_KIND_SIGHT")
    H.GroupLabel("OPT_GRP_SHOW")
    local showCb = H.Check("OPT_SHOW_SIGHT_ALERT", function()
      return not GR.db.wantedUI or GR.db.wantedUI.showSightAlerts ~= false
    end, function(v)
      GR.db.wantedUI = GR.db.wantedUI or {}
      GR.db.wantedUI.showSightAlerts = v and true or false
    end)
    content._amShowCheck = showCb
    content._amHasScale = false

    H.GroupLabel("OPT_GRP_SOUND")
    SoundRow(H, content, "sight")
    host._amHeight = H.Finish()
  end

  -- Oberfläche
  do
    local host = optCatHosts.ui
    local content = host._amContent
    local H = BuildHelpers(content)
    H.PageTitle("OPT_SEC_LAYOUT")

    H.GroupLabel("OPT_GRP_WINDOW")
    H.Hint("OPT_LAYOUT_HINT_WINDOW")
    H.Button("OPT_RESET_POS", function()
      GR.db.frames = GR.db.frames or {}
      GR.db.frames.main = GR.db.frames.main or {}
      GR.db.frames.main.point = nil
      if AngryMurlocsFrame then
        U.ApplyPoint(AngryMurlocsFrame, nil, function(f)
          f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end)
      end
      U.Print(U.L("OPT_RESET_DONE"))
    end, 200, HINT_GAP)

    H.GroupLabel("OPT_GRP_MINIMAP")
    local lockCb
    local lockText
    local function MinimapVisible()
      return not (GR.db.minimap and GR.db.minimap.hide)
    end
    local function RefreshMinimapLockEnabled()
      local on = MinimapVisible()
      if lockCb then
        if on then lockCb:Enable() else lockCb:Disable() end
      end
      if lockText then
        if on then
          if T and T.SetTextColor and T.TEXT then
            T.SetTextColor(lockText, T.TEXT)
          else
            lockText:SetTextColor(1, 1, 1)
          end
        else
          if T and T.SetTextColor and T.MUTED then
            T.SetTextColor(lockText, T.MUTED)
          else
            lockText:SetTextColor(0.5, 0.5, 0.5)
          end
        end
      end
    end

    local showCb, showText = H.Check("OPT_MINIMAP_SHOW", function()
      return MinimapVisible()
    end, function(v)
      GR.db.minimap = GR.db.minimap or {}
      GR.db.minimap.hide = not v
      local mm = GR:GetModule("MinimapButton")
      if mm and mm.ApplySettings then mm:ApplySettings() end
      RefreshMinimapLockEnabled()
    end)
    showCb:HookScript("OnShow", function()
      RefreshMinimapLockEnabled()
    end)

    lockCb, lockText = H.Check("OPT_MINIMAP_LOCK", function()
      return GR.db.minimap and GR.db.minimap.locked == true
    end, function(v)
      if not MinimapVisible() then return end
      GR.db.minimap = GR.db.minimap or {}
      GR.db.minimap.locked = v and true or false
      local mm = GR:GetModule("MinimapButton")
      if mm and mm.ApplySettings then mm:ApplySettings() end
    end)
    lockCb:HookScript("OnShow", function()
      RefreshMinimapLockEnabled()
    end)
    lockCb:HookScript("OnClick", function(self)
      if not MinimapVisible() then
        self:SetChecked(GR.db.minimap and GR.db.minimap.locked == true)
      end
    end)

    host._amHeight = H.Finish()
  end

  ApplyContentWidths()
  Options:ShowCategory("privacy")
end

function Options:OnEnable()
  if self.enabled then return end
  self.enabled = true

  local panel = CreateFrame("Frame")
  panel.name = "AngryMurlocs"
  optionsPanel = panel

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("AngryMurlocs")

  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", 16, -44)
  sub:SetWidth(500)
  sub:SetJustifyH("LEFT")
  sub:SetText(U.L("OPT_BLIZZARD_HINT"))

  local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  btn:SetSize(200, 24)
  btn:SetPoint("TOPLEFT", 16, -80)
  btn:SetText(U.L("OPT_OPEN_WINDOW"))
  btn:SetScript("OnClick", function()
    Options:OpenAddonWindow()
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    optionsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function Options:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  DismissOverlays()
end
