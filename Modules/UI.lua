local GR = AngryMurlocs
local U = GR.Util

local UI = GR:NewModule("UI")

local frame
local generalPanel
local profPanel
local wantedPanel
local optPanel
local scrollChild
local filterBox
local emptyText
local profPageText
local profSortBtn
local tabBtns = {}
local activeTab
local rows = {}
local ROW_H = 20
local NUM_ROWS = 40
local PROF_ONLINE_SEC = 600
local profPage = 1
local profSortBy = "online" -- online | name

local activity = {}
local ACTIVITY_MAX = 20
local FEED_ROWS = 8

local syncButtons = {}

local gen = {
  guildText = nil,
  peersText = nil,
  syncText = nil,
  wantedText = nil,
  shareText = nil,
  posBtn = nil,
  pinsBtn = nil,
  feedLines = nil,
  feedEmpty = nil,
  versionText = nil,
}

local COLS = {
  { key = "COL_NAME", x = 4, w = 150 },
  { key = "COL_PROF1", x = 158, w = 120 },
  { key = "COL_PROF2", x = 282, w = 120 },
  { key = "COL_SEC", x = 406, w = 150 },
}

local TAB_TITLES = {
  general = "TAB_GENERAL",
  prof = "TAB_PROF",
  wanted = "TAB_WANTED",
  opt = "TAB_OPT",
}

local function MainPointGet()
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.main = GR.db.frames.main or {}
  if GR.db.frames.main.point then
    return GR.db.frames.main.point
  end
  local old = GR.db.frames.professions and GR.db.frames.professions.point
  if old then
    GR.db.frames.main.point = old
    return old
  end
end

local function MainPointSet(pt)
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.main = GR.db.frames.main or {}
  GR.db.frames.main.point = pt
end

local function MakeContentPanel(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", 8, -52)
  p:SetPoint("BOTTOMRIGHT", -8, 8)
  p:Hide()
  return p
end

local function UpdateTabButtons()
  for id, btn in pairs(tabBtns) do
    if id == activeTab then
      btn:Disable()
    else
      btn:Enable()
    end
  end
end

local function CountPins()
  local n = 0
  local pos = GR:GetModule("Positions")
  local cache = pos and pos.GetCache and pos:GetCache() or {}
  for _ in pairs(cache) do
    n = n + 1
  end
  return n
end

local function OnOffLabel(on)
  return on and U.L("GENERAL_ON") or U.L("GENERAL_OFF")
end

local function WantedModule()
  return GR:GetModule("Wanted")
end

function UI:RegisterSyncButton(btn)
  syncButtons[#syncButtons + 1] = btn
  UI:UpdateSyncButtons()
end

function UI:UpdateSyncButtons()
  local wanted = WantedModule()
  local busy = wanted and wanted.IsSyncBusy and wanted:IsSyncBusy()
  for i = 1, #syncButtons do
    if busy then syncButtons[i]:Disable() else syncButtons[i]:Enable() end
  end
end

-- Manual sync: professions request + Wanted full sync (resumes a partial one).
function UI:RunGuildDataSync()
  local wanted = WantedModule()
  if wanted and wanted.IsSyncBusy and wanted:IsSyncBusy() then return end
  local prof = GR:GetModule("Professions")
  if prof then
    if prof.ClearEmptyRemoteStubs then prof:ClearEmptyRemoteStubs() end
    prof:RequestAll()
    prof:Broadcast(false)
  end
  if wanted and wanted.RequestSync then wanted:RequestSync("full") end
  UI:UpdateSyncButtons()
end

function UI:RefreshGeneral()
  if not generalPanel then return end

  local guildName = GetGuildInfo and GetGuildInfo("player")
  if gen.guildText then
    if guildName and guildName ~= "" then
      gen.guildText:SetText(string.format(U.L("GENERAL_GUILD"), guildName))
    else
      gen.guildText:SetText(U.L("NOT_IN_GUILD"))
    end
  end

  local wanted = WantedModule()
  if gen.peersText then
    local n, v2, newest = 0, 0, nil
    if GR.Comm and GR.Comm.Peers then
      n, v2, newest = GR.Comm:Peers(600)
    end
    local age = newest and wanted and wanted.FormatAge and wanted.FormatAge(U.WallTime() - newest) or "-"
    gen.peersText:SetText(string.format(U.L("GENERAL_PEERS"), n, v2, age, CountPins()))
  end

  if gen.syncText and wanted and wanted.SyncStatusText then
    gen.syncText:SetText(U.L("GENERAL_SYNC_LABEL") .. ": " .. wanted:SyncStatusText())
  end

  if gen.wantedText and wanted and wanted.Summary then
    local s = wanted:Summary()
    local top = "-"
    if s.top then
      top = string.format("%s Lv.%d", U.ShortName(s.top.key), s.top.level)
    end
    gen.wantedText:SetText(string.format(U.L("GENERAL_WANTED_SUMMARY"), s.total, s.hidden, top))
  end

  if gen.shareText and GR.db and GR.db.privacy then
    local p = GR.db.privacy
    gen.shareText:SetText(string.format(U.L("GENERAL_SHARES"),
      OnOffLabel(p.sharePosition), OnOffLabel(p.shareDeath), OnOffLabel(p.shareProfessions),
      OnOffLabel(p.shareSightings ~= false), OnOffLabel(p.shareLevelUp)))
  end

  local sharePos = GR.db and GR.db.privacy and GR.db.privacy.sharePosition
  local showPins = GR.db and GR.db.map and GR.db.map.showPins
  if gen.posBtn then
    gen.posBtn:SetText(U.L("GENERAL_POS") .. ": " .. OnOffLabel(sharePos))
  end
  if gen.pinsBtn then
    gen.pinsBtn:SetText(U.L("GENERAL_PINS") .. ": " .. OnOffLabel(showPins))
  end

  if gen.versionText then
    gen.versionText:SetText(string.format(U.L("GENERAL_VERSION"), tostring(GR.VERSION or "?")))
  end

  if not gen.feedLines then return end
  local n = #activity
  if gen.feedEmpty then
    if n == 0 then gen.feedEmpty:Show() else gen.feedEmpty:Hide() end
  end
  for i = 1, FEED_ROWS do
    local line = gen.feedLines[i]
    local entry = activity[i]
    if entry then
      line:SetText(entry)
      line:Show()
    else
      line:SetText("")
      line:Hide()
    end
  end
end

local function PushActivity(text)
  if not text or text == "" then return end
  if activity[1] == text then return end
  table.insert(activity, 1, text)
  while #activity > ACTIVITY_MAX do
    activity[#activity] = nil
  end
  if UI:IsTabShown("general") then
    UI:RefreshGeneral()
  end
end

local function BuildGeneralPanel(parent)
  local y = -4

  local statusHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statusHdr:SetPoint("TOPLEFT", 8, y)
  statusHdr:SetText(U.L("GENERAL_STATUS"))
  y = y - 18

  gen.guildText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gen.guildText:SetPoint("TOPLEFT", 8, y)
  gen.guildText:SetWidth(400)
  gen.guildText:SetJustifyH("LEFT")
  y = y - 16

  local function InfoLine()
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 8, y)
    fs:SetWidth(600)
    fs:SetJustifyH("LEFT")
    y = y - 14
    return fs
  end
  gen.peersText = InfoLine()
  gen.syncText = InfoLine()
  gen.wantedText = InfoLine()
  gen.shareText = InfoLine()
  y = y - 6

  gen.posBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.posBtn:SetSize(200, 22)
  gen.posBtn:SetPoint("TOPLEFT", 8, y)
  gen.posBtn:SetScript("OnClick", function()
    if not GR.db or not GR.db.privacy then return end
    GR.db.privacy.sharePosition = not GR.db.privacy.sharePosition
    GR:SendMessage("SHARE_POS_CHANGED")
    UI:RefreshGeneral()
  end)

  gen.pinsBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.pinsBtn:SetSize(200, 22)
  gen.pinsBtn:SetPoint("LEFT", gen.posBtn, "RIGHT", 8, 0)
  gen.pinsBtn:SetScript("OnClick", function()
    if not GR.db or not GR.db.map then return end
    GR.db.map.showPins = not GR.db.map.showPins
    GR:SendMessage("MAP_SETTINGS_CHANGED")
    UI:RefreshGeneral()
  end)
  y = y - 30

  local syncBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  syncBtn:SetSize(120, 22)
  syncBtn:SetPoint("TOPLEFT", 8, y)
  syncBtn:SetText(U.L("GENERAL_SYNC"))
  syncBtn:SetScript("OnClick", function()
    UI:RunGuildDataSync()
    UI:RefreshGeneral()
  end)
  UI:RegisterSyncButton(syncBtn)
  y = y - 28

  local feedHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  feedHdr:SetPoint("TOPLEFT", 8, y)
  feedHdr:SetText(U.L("GENERAL_FEED"))
  y = y - 16

  local feedScroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  feedScroll:SetPoint("TOPLEFT", 8, y)
  feedScroll:SetPoint("RIGHT", parent, "RIGHT", -28, 0)
  feedScroll:SetHeight(FEED_ROWS * 16 + 4)

  local feedChild = CreateFrame("Frame", nil, feedScroll)
  feedChild:SetSize(560, FEED_ROWS * 16)
  feedScroll:SetScrollChild(feedChild)

  gen.feedLines = {}
  for i = 1, FEED_ROWS do
    local fs = feedChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 0, -((i - 1) * 16))
    fs:SetWidth(540)
    fs:SetJustifyH("LEFT")
    fs:Hide()
    gen.feedLines[i] = fs
  end

  gen.feedEmpty = feedChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.feedEmpty:SetPoint("TOPLEFT", 0, 0)
  gen.feedEmpty:SetText(U.L("GENERAL_FEED_EMPTY"))
  y = y - (FEED_ROWS * 16 + 16)

  local helpText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  helpText:SetPoint("TOPLEFT", 8, y)
  helpText:SetWidth(400)
  helpText:SetJustifyH("LEFT")
  helpText:SetText(U.L("GENERAL_HELP"))

  gen.versionText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.versionText:SetPoint("BOTTOMRIGHT", -8, 6)
  gen.versionText:SetJustifyH("RIGHT")
end

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "AngryMurlocsFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(640, 460)
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.main = GR.db.frames.main or {}
  U.MakeMovable(frame, {
    getPoint = MainPointGet,
    setPoint = MainPointSet,
    defaultFn = function(f) f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end,
  })
  frame:Hide()
  tinsert(UISpecialFrames, "AngryMurlocsFrame")

  frame.TitleText:SetText(U.L("WINDOW_TITLE"))

  local function TabBtn(id, labelKey, x, w)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w or 85, 20)
    b:SetPoint("TOPLEFT", x, -28)
    b:SetText(U.L(labelKey))
    b:SetScript("OnClick", function()
      UI:ShowTab(id)
    end)
    tabBtns[id] = b
    return b
  end
  TabBtn("general", "TAB_GENERAL", 12, 85)
  TabBtn("prof", "TAB_PROF", 100, 85)
  TabBtn("wanted", "TAB_WANTED", 188, 85)
  TabBtn("opt", "TAB_OPT", 276, 95)

  generalPanel = MakeContentPanel(frame)
  profPanel = MakeContentPanel(frame)
  wantedPanel = MakeContentPanel(frame)
  optPanel = MakeContentPanel(frame)

  BuildGeneralPanel(generalPanel)

  -- Professions content
  local filterLabel = profPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  filterLabel:SetPoint("TOPLEFT", 8, -4)
  filterLabel:SetText(U.L("FILTER"))

  filterBox = CreateFrame("EditBox", nil, profPanel, "InputBoxTemplate")
  filterBox:SetSize(140, 20)
  filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 8, 0)
  filterBox:SetAutoFocus(false)
  filterBox:SetScript("OnTextChanged", function()
    profPage = 1
    UI:RefreshList()
  end)

  profSortBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
  profSortBtn:SetSize(110, 20)
  profSortBtn:SetPoint("LEFT", filterBox, "RIGHT", 8, 0)
  profSortBtn:SetScript("OnClick", function()
    profSortBy = (profSortBy == "online") and "name" or "online"
    profPage = 1
    UI:RefreshList()
  end)

  local prevBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
  prevBtn:SetSize(24, 20)
  prevBtn:SetPoint("LEFT", profSortBtn, "RIGHT", 6, 0)
  prevBtn:SetText("<")
  prevBtn:SetScript("OnClick", function()
    profPage = math.max(1, profPage - 1)
    UI:RefreshList()
  end)

  local nextBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
  nextBtn:SetSize(24, 20)
  nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
  nextBtn:SetText(">")
  nextBtn:SetScript("OnClick", function()
    profPage = profPage + 1
    UI:RefreshList()
  end)

  local refreshBtn = CreateFrame("Button", nil, profPanel, "UIPanelButtonTemplate")
  refreshBtn:SetSize(80, 20)
  refreshBtn:SetPoint("TOPRIGHT", -4, -2)
  refreshBtn:SetText(U.L("GENERAL_SYNC"))
  refreshBtn:SetScript("OnClick", function()
    UI:RunGuildDataSync()
    UI:RefreshList()
  end)
  UI:RegisterSyncButton(refreshBtn)

  profPageText = profPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  profPageText:SetPoint("TOPLEFT", 8, -26)
  profPageText:SetWidth(580)
  profPageText:SetJustifyH("LEFT")

  U.BuildColHeaders(profPanel, COLS, 4, -42, ROW_H)

  local scroll = CreateFrame("ScrollFrame", nil, profPanel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -62)
  scroll:SetPoint("BOTTOMRIGHT", -24, 4)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(580, NUM_ROWS * ROW_H)
  scroll:SetScrollChild(scrollChild)

  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(580, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
    U.BuildColRow(row, COLS, ROW_H)
    row:SetScript("OnEnter", function(self)
      if not self.fullName then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.fullName, 1, 1, 1)
      if self.online then
        GameTooltip:AddLine(U.L("PROF_ONLINE"), 0.4, 1.0, 0.5)
      else
        GameTooltip:AddLine(U.L("PROF_OFFLINE"), 0.7, 0.7, 0.7)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
  end

  emptyText = profPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER", scroll, "CENTER")
  emptyText:SetText(U.L("NO_DATA"))
  emptyText:Hide()

  local wanted = GR:GetModule("Wanted")
  if wanted and wanted.AttachPanel then
    wanted:AttachPanel(wantedPanel)
  end

  local options = GR:GetModule("Options")
  if options and options.AttachPanel then
    options:AttachPanel(optPanel)
  end

  return frame
end

local function FormatProfs(list)
  if not list or #list == 0 then
    return "-", "-", "-"
  end
  local prof = GR:GetModule("Professions")
  local displayName = prof and prof.DisplayName
  local primary = {}
  local secondary = {}
  local secKeys = { cook = true, aid = true, fish = true }
  for i = 1, #list do
    local p = list[i]
    local labelName = (displayName and p.key and displayName(p.key)) or p.name or p.key
    local label = labelName .. " " .. tostring(p.skill)
    if secKeys[p.key] then
      secondary[#secondary + 1] = label
    else
      primary[#primary + 1] = label
    end
  end
  return primary[1] or "-", primary[2] or "-", (#secondary > 0 and table.concat(secondary, ", ") or "-")
end

local function MatchesFilter(name, entry, filter)
  if not filter or filter == "" then return true end
  filter = filter:lower()
  if name:lower():find(filter, 1, true) then return true end
  local fKey, fSkill = filter:match("^(%S+)%s+(%d+)$")
  if fKey and fSkill then
    fSkill = tonumber(fSkill)
    for i = 1, #(entry.list or {}) do
      local p = entry.list[i]
      local n = (p.name or ""):lower()
      if (p.key == fKey or n:find(fKey, 1, true)) and p.skill >= fSkill then
        return true
      end
    end
    return false
  end
  for i = 1, #(entry.list or {}) do
    local p = entry.list[i]
    if (p.key and p.key:find(filter, 1, true)) or ((p.name or ""):lower():find(filter, 1, true)) then
      return true
    end
  end
  return false
end

function UI:GetFrame()
  return EnsureFrame()
end

function UI:IsTabShown(id)
  return frame and frame:IsShown() and activeTab == id
end

function UI:ShowTab(id)
  EnsureFrame()
  if id ~= "general" and id ~= "prof" and id ~= "wanted" and id ~= "opt" then
    id = "general"
  end
  activeTab = id

  if generalPanel then
    if id == "general" then generalPanel:Show() else generalPanel:Hide() end
  end
  if profPanel then
    if id == "prof" then profPanel:Show() else profPanel:Hide() end
  end
  if wantedPanel then
    if id == "wanted" then wantedPanel:Show() else wantedPanel:Hide() end
  end
  if optPanel then
    if id == "opt" then optPanel:Show() else optPanel:Hide() end
  end

  UpdateTabButtons()

  local titleKey = TAB_TITLES[id]
  if titleKey then
    frame.TitleText:SetText(U.L("WINDOW_TITLE") .. " — " .. U.L(titleKey))
  else
    frame.TitleText:SetText(U.L("WINDOW_TITLE"))
  end

  frame:Show()

  if id == "general" then
    self:RefreshGeneral()
  elseif id == "prof" then
    local prof = GR:GetModule("Professions")
    if prof then
      if prof.ClearEmptyRemoteStubs then prof:ClearEmptyRemoteStubs() end
      prof:Broadcast(false)
      prof:RequestAll()
    end
    self:RefreshList()
  elseif id == "wanted" then
    local wanted = GR:GetModule("Wanted")
    if wanted and wanted.Refresh then
      wanted:Refresh()
    end
  elseif id == "opt" then
    if optPanel then
      optPanel:Hide()
      optPanel:Show()
    end
  end
end

local function IsProfOnline(name, me)
  if name == me or U.IsSelfName(name) then return true end
  local age = GR.Comm and GR.Comm.PeerAge and GR.Comm:PeerAge(name)
  return age ~= nil and age <= PROF_ONLINE_SEC
end

function UI:RefreshList()
  if not frame or not self:IsTabShown("prof") then return end
  local prof = GR:GetModule("Professions")
  local cache = prof and prof:GetAll() or {}
  local filter = filterBox and filterBox:GetText() or ""

  local me = U.NormalizeName(U.PlayerName())
  local names = {}
  for name, entry in pairs(cache) do
    if not (U.IsSelfName(name) and name ~= me) then
      if MatchesFilter(name, entry, filter) then
        names[#names + 1] = name
      end
    end
  end
  table.sort(names, function(a, b)
    if profSortBy == "online" then
      local oa, ob = IsProfOnline(a, me), IsProfOnline(b, me)
      if oa ~= ob then return oa end
    end
    return string.lower(U.ShortName(a)) < string.lower(U.ShortName(b))
  end)

  local total = #names
  local pages = math.max(1, math.ceil(total / NUM_ROWS))
  if profPage > pages then profPage = pages end
  if profPage < 1 then profPage = 1 end
  local first = (profPage - 1) * NUM_ROWS + 1
  local last = math.min(total, profPage * NUM_ROWS)

  if profSortBtn then
    profSortBtn:SetText(profSortBy == "online" and U.L("PROF_SORT_ONLINE") or U.L("PROF_SORT_NAME"))
  end
  if profPageText then
    if filter ~= "" then
      profPageText:SetText(string.format(U.L("PROF_PAGE_FILTER"), total, profPage, pages))
    elseif profPage == 1 and total > NUM_ROWS then
      profPageText:SetText(string.format(U.L("PROF_PAGE_TOP"), NUM_ROWS, total, pages))
    else
      profPageText:SetText(string.format(U.L("PROF_PAGE_INFO"), profPage, pages, total > 0 and first or 0, last, total))
    end
  end

  if total == 0 then
    emptyText:Show()
  else
    emptyText:Hide()
  end

  scrollChild:SetHeight(math.max(last - first + 1, 1) * ROW_H)

  for i = 1, NUM_ROWS do
    local name = names[first + i - 1]
    if name and (first + i - 1) <= last then
      local entry = cache[name]
      local p1, p2, sec = FormatProfs(entry.list)
      local online = IsProfOnline(name, me)
      local short = U.ShortName(name)
      if name == me or U.IsSelfName(name) then
        short = U.ShortName(me) .. " (" .. U.L("YOU") .. ")"
      end
      if not online then
        short = short .. " ·"
      end
      local r, g, b = U.ClassColor(entry.classFile)
      if not online then
        r, g, b = r * 0.55, g * 0.55, b * 0.55
      end
      rows[i].fullName = name
      rows[i].online = online
      U.SetColTexts(rows[i].cols, { short, p1, p2, sec }, r, g, b)
      rows[i]:Show()
    else
      rows[i].fullName = nil
      rows[i].online = nil
      rows[i]:Hide()
    end
  end
end

function UI:Toggle()
  EnsureFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    self:ShowTab(activeTab or "general")
  end
end

function UI:ShowProf()
  self:ShowTab("prof")
end

function UI:OnEnable()
  GR:RegisterMessage("PROF_CACHE_CHANGED", function()
    if UI:IsTabShown("prof") then
      UI:RefreshList()
    end
  end)

  GR:RegisterMessage("POS_CACHE_CHANGED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:RegisterMessage("POS_REMOVED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:RegisterMessage("POS_CACHE_CLEARED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:RegisterMessage("SHARE_POS_CHANGED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:RegisterMessage("MAP_SETTINGS_CHANGED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)

  GR:RegisterMessage("SIGHT_APPLIED", function(_, target, zone, reporter)
    PushActivity(string.format(
      U.L("GENERAL_ACT_SIGHT"),
      U.ShortName(target or "?"),
      zone ~= "" and zone or "?",
      U.ShortName(reporter or "?")
    ))
  end)

  GR:RegisterMessage("DEATH_UPDATE", function(_, victim)
    PushActivity(string.format(U.L("GENERAL_ACT_DEATH"), U.ShortName(victim or "?")))
  end)

  GR:RegisterMessage("LVL_UPDATE", function(_, sender, level)
    PushActivity(string.format(
      U.L("GENERAL_ACT_LVL"),
      U.ShortName(sender or "?"),
      tonumber(level) or 0
    ))
  end)

  GR:RegisterMessage("WANTED_KILL", function(_, killer, origin, level, kind)
    PushActivity(string.format(
      U.L(kind == "own" and "GENERAL_ACT_WANTED_OWN" or "GENERAL_ACT_WANTED"),
      U.ShortName(killer or "?"),
      tonumber(level) or 0,
      U.ShortName(origin or "?")
    ))
  end)

  local function RefreshGeneralIfShown()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end
  GR:RegisterMessage("SYNC_STATUS", function()
    UI:UpdateSyncButtons()
    RefreshGeneralIfShown()
  end)
  GR:RegisterMessage("WANTED_CHANGED", RefreshGeneralIfShown)
  GR:RegisterMessage("PRIVACY_CHANGED", RefreshGeneralIfShown)
end
