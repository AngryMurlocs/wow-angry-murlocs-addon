-- Wanted list UI: attaches onto the Wanted module (no second NewModule).
local GR = AngryMurlocs
local U = GR.Util
local T = GR.Theme
local Logic = GR.WantedLogic

local Wanted = GR:GetModule("Wanted")
assert(Wanted, "WantedPanel requires Wanted module")

local frame
local scrollFrame
local scrollChild
local rows = {}
local searchBox
local pageText
local statusText
local sortBtn
local prevBtn
local nextBtn
local emptyText
local unhideBtn
local recentCb
local recentOnly = false
local selectedKiller = nil
local detailFrame
local detailLines = {}
local detailHideBtn
local colHeaders
local PAGE_SIZE = 40
local ROW_H = 28
local DETAIL_H = 110
local freshnessTicker
local page = 1
local sortBy = "level"

local WANTED_COLS = {
  { key = "WANTED_COL_KILLER", x = 4, w = 140 },
  { key = "WANTED_COL_THREAT", x = 150, w = 130 },
  { key = "WANTED_COL_SEEN", x = 286, w = 160 },
  { key = "WANTED_COL_SEEN_ZONE", x = 452, w = 120 },
}

local RANK_RGB = {
  MARKED = { 0.85, 0.85, 0.75 },
  HUNTED = { 1.0, 0.85, 0.45 },
  BOUNTY = { 1.0, 0.65, 0.25 },
  ENEMY = { 1.0, 0.4, 0.25 },
  SCOURGE = { 1.0, 0.2, 0.2 },
}

local function RankColor(level)
  local rank = Logic.RankFromLevel(level)
  local c = RANK_RGB[rank.key] or { 1, 1, 1 }
  return c[1], c[2], c[3]
end

local function SightTier(entry)
  return Logic.SightTier(entry, Wanted:Now())
end

local function FormatSightCell(entry)
  local tier = SightTier(entry)
  if tier == "none" then
    return U.L("WANTED_SIGHT_NONE"), "none"
  end
  local age = Wanted.FormatAge(entry.lastSeenTime)
  if tier == "fresh" then
    return string.format(U.L("WANTED_SIGHT_FRESH_AGE"), age), tier
  elseif tier == "warm" then
    return string.format(U.L("WANTED_SIGHT_WARM_AGE"), age), tier
  end
  return string.format(U.L("WANTED_SIGHT_STALE_AGE"), age), tier
end

local function SightColor(tier)
  if tier == "fresh" then return T.FRESH end
  if tier == "warm" then return T.WARM end
  if tier == "stale" then return T.STALE end
  return T.MUTED
end

local function ThreatLabel(level)
  local rank = Logic.RankFromLevel(level)
  return string.format(U.L("WANTED_THREAT_CELL"), level, U.L("WANTED_RANK_" .. rank.key))
end

local function SetDetailOpen(open)
  if not detailFrame or not scrollFrame then return end
  if open then
    detailFrame:Show()
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 28 + DETAIL_H + 8)
  else
    detailFrame:Hide()
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 28)
  end
end

local function FillDetail(killer)
  if not detailFrame then return end
  if not killer then
    SetDetailOpen(false)
    for i = 1, #detailLines do
      detailLines[i]:SetText("")
    end
    return
  end
  local entry = Wanted:State().wanted[killer]
  if not entry then
    selectedKiller = nil
    SetDetailOpen(false)
    return
  end
  SetDetailOpen(true)
  local level = Logic.Level(entry)
  local rank = Logic.RankFromLevel(level)
  local s = Logic.SourceSummary(entry)
  detailLines[1]:SetText(U.ShortName(killer) .. " — " .. string.format(U.L("WANTED_RANK_LINE"), level, U.L("WANTED_RANK_" .. rank.key)))
  detailLines[2]:SetText(string.format(U.L("WANTED_COL_SEEN_BY") .. ": %s",
    (entry.lastSeenBy ~= "" and U.ShortName(entry.lastSeenBy)) or "-"))
  detailLines[3]:SetText(string.format(U.L("WANTED_COL_VICTIM") .. ": %s",
    (entry.lastVictim ~= "" and entry.lastVictim) or "-"))
  if (entry.lastKillTime or 0) > 0 then
    detailLines[4]:SetText(string.format(U.L("WANTED_LAST_KILL"), Wanted.FormatAge(entry.lastKillTime),
      entry.lastVictim ~= "" and entry.lastVictim or "?", entry.lastZone ~= "" and entry.lastZone or "?"))
  else
    detailLines[4]:SetText(U.L("WANTED_SIGHT_NONE"))
  end
  local src = {}
  if s.own > 0 then src[#src + 1] = string.format(U.L("WANTED_SRC_OWN"), s.own) end
  if s.direct > 0 then src[#src + 1] = string.format(U.L("WANTED_SRC_DIRECT"), s.direct) end
  if s.relayed > 0 then src[#src + 1] = string.format(U.L("WANTED_SRC_RELAYED"), s.relayed) end
  if s.legacy > 0 then src[#src + 1] = string.format(U.L("WANTED_SRC_LEGACY"), s.legacy) end
  detailLines[5]:SetText((#src > 0 and table.concat(src, " · ")) or U.L("WANTED_SRC_NOTE"))
  if detailHideBtn then
    detailHideBtn.killer = killer
    detailHideBtn:Show()
  end
end

local function RefreshAges()
  if not frame or not Wanted:_PanelShown() then return end
  local st = Wanted:State()
  local wanted = st and st.wanted
  if not wanted then return end
  for i = 1, PAGE_SIZE do
    local row = rows[i]
    if row and row.killer and row:IsShown() then
      local e = wanted[row.killer]
      if e and row.cols and row.cols[3] then
        local seen, tier = FormatSightCell(e)
        local shown = T.Truncate(seen, 22)
        row.cols[3]:SetText(shown)
        local c = SightColor(tier)
        row.cols[3]:SetTextColor(c[1], c[2], c[3])
      end
    end
  end
end

local function EnsureFreshnessTicker()
  if freshnessTicker then return end
  freshnessTicker = C_Timer.NewTicker(1, function()
    if not Wanted:_PanelShown() then
      if freshnessTicker then
        freshnessTicker:Cancel()
        freshnessTicker = nil
      end
      return
    end
    RefreshAges()
  end)
end

local function ShowRowTooltip(self)
  if not self.killer then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(U.ShortName(self.killer), 1, 0.85, 0.4)
  GameTooltip:AddLine(U.L("WANTED_DETAIL_HINT"), 0.7, 0.7, 0.7)
  GameTooltip:AddLine(U.L("WANTED_CLICK_HIDE"), 0.6, 0.6, 0.6)
  if self.fullSight then
    GameTooltip:AddLine(self.fullSight, 0.9, 0.9, 0.9, true)
  end
  if self.fullZone then
    GameTooltip:AddLine(self.fullZone, 0.8, 0.8, 0.8)
  end
  GameTooltip:Show()
end

function Wanted:_PanelShown()
  local ui = GR:GetModule("UI")
  if ui and ui.IsTabShown then
    return ui:IsTabShown("wanted")
  end
  return frame and frame:IsShown()
end

function Wanted:AttachPanel(parent)
  if frame or not parent then return frame end

  frame = parent

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  searchLabel:SetPoint("TOPLEFT", T.INSET, -4)
  searchLabel:SetText(U.L("WANTED_SEARCH"))

  searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  searchBox:SetSize(120, 20)
  searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
  searchBox:SetAutoFocus(false)
  searchBox:SetScript("OnTextChanged", function()
    page = 1
    Wanted:Refresh()
  end)

  sortBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  sortBtn:SetSize(130, 20)
  sortBtn:SetPoint("LEFT", searchBox, "RIGHT", T.INSET, 0)
  sortBtn:SetScript("OnClick", function()
    sortBy = (sortBy == "level") and "seen" or "level"
    page = 1
    Wanted:Refresh()
  end)

  recentCb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  recentCb:SetSize(24, 24)
  recentCb:SetPoint("LEFT", sortBtn, "RIGHT", 4, 0)
  recentCb:SetScript("OnClick", function(self)
    recentOnly = self:GetChecked() and true or false
    page = 1
    Wanted:Refresh()
  end)
  local recentLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  recentLabel:SetPoint("LEFT", recentCb, "RIGHT", 0, 0)
  recentLabel:SetWidth(200)
  recentLabel:SetJustifyH("LEFT")
  recentLabel:SetText(U.L("WANTED_FILTER_RECENT"))

  local syncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  syncBtn:SetSize(80, 20)
  syncBtn:SetPoint("TOPRIGHT", -4, -4)
  syncBtn:SetText(U.L("GENERAL_SYNC"))
  syncBtn:SetScript("OnClick", function()
    local ui = GR:GetModule("UI")
    if ui and ui.RunGuildDataSync then ui:RunGuildDataSync() end
  end)
  local ui = GR:GetModule("UI")
  if ui and ui.RegisterSyncButton then ui:RegisterSyncButton(syncBtn) end

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusText:SetPoint("TOPLEFT", T.INSET, -28)
  statusText:SetWidth(500)
  statusText:SetJustifyH("LEFT")

  unhideBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  unhideBtn:SetSize(200, 18)
  unhideBtn:SetPoint("TOPRIGHT", -4, -26)
  unhideBtn:Hide()
  unhideBtn:SetScript("OnClick", function()
    Wanted:UnhideAll()
    Wanted:Refresh()
  end)

  colHeaders = U.BuildColHeaders(frame, WANTED_COLS, 4, -48, ROW_H)

  scrollFrame = CreateFrame("ScrollFrame", "AngryMurlocsWantedScroll", frame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 4, -70)
  scrollFrame:SetPoint("BOTTOMRIGHT", -24, 28)

  scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetSize(580, PAGE_SIZE * ROW_H)
  scrollFrame:SetScrollChild(scrollChild)

  for i = 1, PAGE_SIZE do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(580, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
    U.BuildColRow(row, WANTED_COLS, ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      if not self.killer then return end
      if IsShiftKeyDown and IsShiftKeyDown() then
        Wanted:Hide(self.killer)
        if selectedKiller == self.killer then
          selectedKiller = nil
          FillDetail(nil)
        end
        return
      end
      if selectedKiller == self.killer then
        selectedKiller = nil
        FillDetail(nil)
      else
        selectedKiller = self.killer
        FillDetail(self.killer)
      end
      Wanted:Refresh()
    end)
    row:SetScript("OnEnter", function(self)
      T.RowHoverEnter(self)
      ShowRowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
      T.RowHoverLeave(self)
      GameTooltip_Hide()
    end)
    rows[i] = row
  end

  emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER", scrollFrame, "CENTER")
  emptyText:Hide()

  detailFrame = CreateFrame("Frame", nil, frame)
  detailFrame:SetPoint("BOTTOMLEFT", T.INSET, 28)
  detailFrame:SetPoint("BOTTOMRIGHT", -T.INSET, 28)
  detailFrame:SetHeight(DETAIL_H)
  T.ApplyPanelBackdrop(detailFrame, T.BG_ALT)
  detailFrame:Hide()

  local dy = -6
  for i = 1, 5 do
    local fs = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", T.INSET, dy)
    fs:SetPoint("RIGHT", detailFrame, "RIGHT", -100, 0)
    fs:SetJustifyH("LEFT")
    detailLines[i] = fs
    dy = dy - 16
  end

  detailHideBtn = CreateFrame("Button", nil, detailFrame, "UIPanelButtonTemplate")
  detailHideBtn:SetSize(150, 20)
  detailHideBtn:SetPoint("BOTTOMRIGHT", -T.INSET, T.INSET)
  detailHideBtn:SetText(U.L("WANTED_DETAIL_HIDE"))
  detailHideBtn:SetScript("OnClick", function(self)
    if self.killer then
      Wanted:Hide(self.killer)
      selectedKiller = nil
      FillDetail(nil)
    end
  end)

  pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pageText:SetPoint("BOTTOMLEFT", T.INSET, 8)
  pageText:SetWidth(360)
  pageText:SetJustifyH("LEFT")

  prevBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  prevBtn:SetSize(24, 20)
  prevBtn:SetPoint("BOTTOMRIGHT", -56, 6)
  prevBtn:SetText("<")
  prevBtn:SetScript("OnClick", function()
    page = math.max(1, page - 1)
    Wanted:Refresh()
  end)

  nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextBtn:SetSize(24, 20)
  nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
  nextBtn:SetText(">")
  nextBtn:SetScript("OnClick", function()
    page = page + 1
    Wanted:Refresh()
  end)

  return frame
end

function Wanted:Refresh()
  if not frame or not self:_PanelShown() then return end
  EnsureFreshnessTicker()
  local filter = searchBox and searchBox:GetText() or ""
  local list, hidden = Logic.Sorted(self:State(), self:Now(), { filter = filter, sortBy = sortBy })
  if recentOnly then
    local filtered = {}
    for i = 1, #list do
      local tier = SightTier(list[i].entry)
      if tier == "fresh" or tier == "warm" then
        filtered[#filtered + 1] = list[i]
      end
    end
    list = filtered
  end

  local total = #list
  local pages = math.max(1, math.ceil(total / PAGE_SIZE))
  if page > pages then page = pages end
  if page < 1 then page = 1 end
  local first = (page - 1) * PAGE_SIZE + 1
  local last = math.min(total, page * PAGE_SIZE)

  if sortBtn then
    sortBtn:SetText(sortBy == "level" and U.L("WANTED_SORT_LEVEL") or U.L("WANTED_SORT_SEEN"))
  end

  if pageText then
    if total == 0 then
      pageText:SetText("")
    else
      pageText:SetText(string.format(U.L("WANTED_PAGE_RANGE"), first, last, total, page, pages))
    end
  end
  if statusText then
    statusText:SetText(Wanted:SyncStatusText())
  end
  if unhideBtn then
    if hidden > 0 then
      unhideBtn:SetText(string.format(U.L("WANTED_UNHIDE_BTN"), hidden))
      unhideBtn:Show()
    else
      unhideBtn:Hide()
    end
  end
  if prevBtn then
    if page <= 1 then prevBtn:Disable() else prevBtn:Enable() end
  end
  if nextBtn then
    if page >= pages then nextBtn:Disable() else nextBtn:Enable() end
  end

  if emptyText then
    if total == 0 then
      emptyText:Show()
      local rawTotal = 0
      for _ in pairs(self:State().wanted or {}) do rawTotal = rawTotal + 1 end
      if rawTotal == 0 and hidden == 0 then
        emptyText:SetText(U.L("WANTED_EMPTY"))
      else
        emptyText:SetText(U.L("WANTED_EMPTY_FILTER"))
      end
    else
      emptyText:Hide()
    end
  end

  if selectedKiller then
    local still = self:State().wanted[selectedKiller]
    if not still or Logic.IsHidden(self:State(), selectedKiller, still) then
      selectedKiller = nil
      FillDetail(nil)
    else
      FillDetail(selectedKiller)
    end
  else
    SetDetailOpen(false)
  end

  scrollChild:SetHeight(math.max(last - first + 1, 1) * ROW_H)
  for i = 1, PAGE_SIZE do
    local item = list[first + i - 1]
    local row = rows[i]
    if item and (first + i - 1) <= last then
      local e = item.entry
      row.killer = item.key
      local seen, tier = FormatSightCell(e)
      local zone = (e.lastSeenZone ~= "" and e.lastSeenZone) or "-"
      local threat = ThreatLabel(item.level)
      local nameShown = T.Truncate(U.ShortName(item.key), 16)
      local threatShown = T.Truncate(threat, 16)
      local seenShown = T.Truncate(seen, 22)
      local zoneShown = T.Truncate(zone, 14)
      row.fullSight = seen
      row.fullZone = zone
      T.ApplyRowChrome(row, i, selectedKiller == item.key)
      if row.cols then
        row.cols[1]:SetText(nameShown)
        row.cols[1]:SetTextColor(T.TEXT[1], T.TEXT[2], T.TEXT[3])
        row.cols[2]:SetText(threatShown)
        local tr, tg, tb = RankColor(item.level)
        row.cols[2]:SetTextColor(tr, tg, tb)
        row.cols[3]:SetText(seenShown)
        local sc = SightColor(tier)
        row.cols[3]:SetTextColor(sc[1], sc[2], sc[3])
        row.cols[4]:SetText(zoneShown)
        row.cols[4]:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
      end
      row:Show()
    else
      row.killer = nil
      row.fullSight = nil
      row.fullZone = nil
      row:Hide()
    end
  end
end

function Wanted:ShowWindow()
  local ui = GR:GetModule("UI")
  if ui and ui.ShowTab then
    ui:ShowTab("wanted")
  end
end

function Wanted:Toggle()
  local ui = GR:GetModule("UI")
  if not ui then return end
  if ui:IsTabShown("wanted") then
    local f = ui.GetFrame and ui:GetFrame()
    if f then f:Hide() end
  else
    ui:ShowTab("wanted")
  end
end

function Wanted:_EnablePanel()
  GR:BindMessage(self, "WANTED_CHANGED", function()
    Wanted:Refresh()
  end)

  GR:BindMessage(self, "SYNC_STATUS", function()
    Wanted:Refresh()
  end)
end

function Wanted:_DisablePanel()
  if freshnessTicker then
    freshnessTicker:Cancel()
    freshnessTicker = nil
  end
end
