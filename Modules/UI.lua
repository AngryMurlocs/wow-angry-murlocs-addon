local GR = AngryMurlocs
local U = GR.Util
local T = GR.Theme

local UI = GR:NewModule("UI")

local frame
local generalPanel
local profPanel
local wantedPanel
local optPanel
local scrollChild
local filterBox
local emptyText
local emptyResetBtn
local profPageText
local profSortBtn
local profPrevBtn
local profNextBtn
local profKeyFilter = ""
local profMinSkill = nil
local profActiveOnly = false
local profKeyBtn
local profMinBox
local profActiveCb
local profMenu
local whisperMenu
local tabBtns = {}
local activeTab
local rows = {}
local ROW_H = 26
local NUM_ROWS = 40
local PROF_ONLINE_SEC = 600
local profPage = 1
local profSortBy = "online" -- online | name

local activity = {}
local ACTIVITY_MAX = 20
local FEED_ROWS = 20
local FEED_LINE_H = 18

local syncButtons = {}

local gen = {}

local COLS = {
  { key = "COL_NAME", x = 4, w = 140 },
  { key = "COL_PROF1", x = 148, w = 130 },
  { key = "COL_PROF2", x = 282, w = 130 },
  { key = "COL_SEC", x = 416, w = 140 },
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
    T.StyleTabButton(btn, id == activeTab)
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

local function FormatRelAge(ts)
  local wanted = WantedModule()
  if wanted and wanted.FormatAge then
    return wanted.FormatAge(ts)
  end
  if not ts or ts <= 0 then return "-" end
  local age = U.WallTime() - ts
  if age < 0 then age = 0 end
  if age < 60 then return string.format(U.L("AGO"), math.floor(age)) end
  if age < 3600 then return string.format(U.L("AGO_MIN"), math.floor(age / 60)) end
  return string.format(U.L("AGO_HR"), math.floor(age / 3600))
end

local function ShortSyncStatus()
  local wanted = WantedModule()
  local busy = wanted and wanted.IsSyncBusy and wanted:IsSyncBusy()
  local text
  if busy then
    text = U.L("GENERAL_SYNC_SHORT_BUSY")
  else
    local full = wanted and wanted.SyncStatusText and wanted:SyncStatusText() or ""
    local lower = string.lower(full)
    if full == "" or lower:find("not run", 1, true) or lower:find("noch nicht", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_IDLE")
    elseif lower:find("noreply", 1, true) or lower:find("kein antwort", 1, true) or lower:find("no responding", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_NOREPLY")
    elseif lower:find("not in a guild", 1, true) or lower:find("nicht in einer gilde", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_NOGUILD")
    elseif lower:find("failed", 1, true) or lower:find("fehlgeschlagen", 1, true) or lower:find("could not", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_FAILED")
    elseif lower:find("partial", 1, true) or lower:find("teil", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_PARTIAL")
    elseif lower:find("incomplete", 1, true) or lower:find("unvollständig", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_INCOMPLETE")
    elseif lower:find("complete", 1, true) or lower:find("vollständig", 1, true) then
      text = U.L("GENERAL_SYNC_SHORT_DONE")
    else
      text = full
    end
  end
  local lastOk = nil
  if wanted and wanted.GetLastSyncOkAt then
    lastOk = wanted:GetLastSyncOkAt()
  end
  -- Prefer parsing from SyncStatusText append when helper missing.
  if (not lastOk or lastOk <= 0) and wanted and wanted.SyncStatusText then
    -- SyncStore lastOkAt exposed via FormatAge in status; skip if unknown.
  end
  return text, lastOk
end

function UI:RegisterSyncButton(btn)
  syncButtons[#syncButtons + 1] = btn
  UI:UpdateSyncButtons()
end

function UI:UpdateSyncButtons()
  local wanted = WantedModule()
  local busy = wanted and wanted.IsSyncBusy and wanted:IsSyncBusy()
  for i = 1, #syncButtons do
    local btn = syncButtons[i]
    if busy then
      btn:Disable()
      if btn._amIsGeneralSync then
        btn:SetText(U.L("GENERAL_SYNC_RUNNING"))
      end
    else
      btn:Enable()
      if btn._amIsGeneralSync then
        btn:SetText(U.L("GENERAL_SYNC"))
      elseif btn.GetText and (btn:GetText() == U.L("GENERAL_SYNC_RUNNING")) then
        btn:SetText(U.L("GENERAL_SYNC"))
      end
    end
  end
end

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

local function KindLabel(kind)
  if kind == "sight" then return U.L("GENERAL_KIND_SIGHT") end
  if kind == "death" then return U.L("GENERAL_KIND_DEATH") end
  if kind == "lvl" then return U.L("GENERAL_KIND_LVL") end
  return U.L("GENERAL_KIND_WANTED")
end

local function FormatActivityLine(entry)
  if type(entry) == "string" then return entry end
  local player = U.ShortName(entry.player or "?")
  local age = FormatRelAge(entry.at or 0)
  return string.format(U.L("GENERAL_FEED_LINE"), KindLabel(entry.kind), player, age)
end

local function ActivitySame(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  return a.kind == b.kind and a.player == b.player and a.at == b.at
    and a.zone == b.zone and a.level == b.level and a.origin == b.origin
end

local function PushActivity(entry)
  if not entry then return end
  if type(entry) == "string" then
    if entry == "" then return end
    entry = { kind = "note", player = entry, at = U.WallTime() }
  end
  entry.at = entry.at or U.WallTime()
  if activity[1] and ActivitySame(activity[1], entry) then return end
  table.insert(activity, 1, entry)
  while #activity > ACTIVITY_MAX do
    activity[#activity] = nil
  end
  if UI:IsTabShown("general") then
    UI:RefreshGeneral()
  end
end

-- Exported for tests.
function UI.MatchesProfessionFilter(name, entry, opts)
  opts = opts or {}
  local filter = opts.text and opts.text ~= "" and string.lower(opts.text) or nil
  local key = opts.profKey and opts.profKey ~= "" and opts.profKey or nil
  local minSkill = tonumber(opts.minSkill)
  local activeOnly = opts.activeOnly and true or false
  local me = opts.me
  local isOnline = opts.isOnline

  if activeOnly and isOnline and not isOnline(name, me) then
    return false
  end

  if key or minSkill then
    local list = entry and entry.list or {}
    local ok = false
    for i = 1, #list do
      local p = list[i]
      local skill = tonumber(p.skill) or 0
      if key then
        if p.key == key and (not minSkill or skill >= minSkill) then
          ok = true
          break
        end
      else
        if not minSkill or skill >= minSkill then
          ok = true
          break
        end
      end
    end
    if not ok then return false end
  end

  if not filter then return true end
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

local function SetDetailsExpanded(expanded)
  gen.detailsOpen = expanded and true or false
  if gen.detailsBtn then
    gen.detailsBtn:SetText(expanded and U.L("GENERAL_DETAILS_HIDE") or U.L("GENERAL_DETAILS_SHOW"))
  end
  if gen.detailsFrame then
    if expanded then gen.detailsFrame:Show() else gen.detailsFrame:Hide() end
  end
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

  if gen.versionText then
    gen.versionText:SetText(string.format(U.L("GENERAL_VERSION"), tostring(GR.VERSION or "?")))
  end

  local wanted = WantedModule()
  local n, v2, newest = 0, 0, nil
  if GR.Comm and GR.Comm.Peers then
    n, v2, newest = GR.Comm:Peers(600)
  end
  local pins = CountPins()

  if gen.syncText then
    local short = ShortSyncStatus()
    local lastLine = ""
    if wanted and wanted.GetLastSyncOkAt then
      local last = wanted:GetLastSyncOkAt()
      if last and last > 0 then
        lastLine = " · " .. string.format(U.L("GENERAL_SYNC_LAST"), FormatRelAge(last))
      end
    else
      -- Fallback: append age from full status when last complete phrase exists.
      local full = wanted and wanted.SyncStatusText and wanted:SyncStatusText() or ""
      local age = full:match("·%s*(.+)$")
      if age and age ~= "" then
        lastLine = " · " .. age
      end
    end
    gen.syncText:SetText(short .. lastLine)
    T.SetTextColor(gen.syncText, T.MUTED)
  end

  if gen.cardActive then
    gen.cardActive.value:SetText(tostring(n))
  end
  if gen.cardPins then
    gen.cardPins.value:SetText(tostring(pins))
  end
  if gen.cardWanted and wanted and wanted.Summary then
    local s = wanted:Summary()
    gen.cardWanted.value:SetText(tostring(s.total or 0))
  end

  if gen.detailsProto then
    local age = newest and FormatRelAge(newest) or "-"
    gen.detailsProto:SetText(string.format(U.L("GENERAL_PROTO"), v2, age))
  end
  if gen.detailsShares and GR.db and GR.db.privacy then
    local p = GR.db.privacy
    gen.detailsShares:SetText(string.format(U.L("GENERAL_SHARES"),
      OnOffLabel(p.sharePosition), OnOffLabel(p.shareDeath), OnOffLabel(p.shareProfessions),
      OnOffLabel(p.shareSightings ~= false), OnOffLabel(p.shareLevelUp)))
  end
  if gen.detailsWanted and wanted and wanted.Summary then
    local s = wanted:Summary()
    local top = "-"
    if s.top then
      top = string.format("%s %d", U.ShortName(s.top.key), s.top.level)
    end
    gen.detailsWanted:SetText(string.format(U.L("GENERAL_WANTED_SUMMARY"), s.total, s.hidden, top))
  end
  if gen.detailsHelp then
    gen.detailsHelp:SetText(U.L("GENERAL_HELP"))
  end

  local sharePos = GR.db and GR.db.privacy and GR.db.privacy.sharePosition
  local showPins = GR.db and GR.db.map and GR.db.map.showPins
  if gen.posBtn then
    gen.posBtn:SetText(U.L("GENERAL_POS") .. ": " .. OnOffLabel(sharePos))
    local c = T.OnOffColor(sharePos)
    if gen.posBtn.GetFontString and gen.posBtn:GetFontString() then
      gen.posBtn:GetFontString():SetTextColor(c[1], c[2], c[3])
    end
  end
  if gen.pinsBtn then
    gen.pinsBtn:SetText(U.L("GENERAL_PINS") .. ": " .. OnOffLabel(showPins))
    local c = T.OnOffColor(showPins)
    if gen.pinsBtn.GetFontString and gen.pinsBtn:GetFontString() then
      gen.pinsBtn:GetFontString():SetTextColor(c[1], c[2], c[3])
    end
  end

  UI:UpdateSyncButtons()

  if not gen.feedLines then return end
  local count = #activity
  if gen.feedEmpty then
    if count == 0 then gen.feedEmpty:Show() else gen.feedEmpty:Hide() end
  end
  if gen.feedChild then
    gen.feedChild:SetHeight(math.max(count, 1) * FEED_LINE_H)
  end
  for i = 1, FEED_ROWS do
    local line = gen.feedLines[i]
    local entry = activity[i]
    if entry then
      line:SetText(FormatActivityLine(entry))
      line:Show()
    else
      line:SetText("")
      line:Hide()
    end
  end
end

local function BuildGeneralPanel(parent)
  -- A) Header
  gen.guildText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gen.guildText:SetPoint("TOPLEFT", T.INSET, -4)
  gen.guildText:SetWidth(420)
  gen.guildText:SetJustifyH("LEFT")

  gen.versionText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.versionText:SetPoint("TOPRIGHT", -T.INSET, -6)
  gen.versionText:SetJustifyH("RIGHT")

  gen.syncText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.syncText:SetPoint("TOPLEFT", T.INSET, -22)
  gen.syncText:SetPoint("RIGHT", parent, "RIGHT", -T.INSET, 0)
  gen.syncText:SetJustifyH("LEFT")
  T.SetTextColor(gen.syncText, T.MUTED)

  -- B) Status cards
  local cardW = 196
  local cardH = 58
  local cardY = -22 - T.GAP
  gen.cardActive = T.StatusCard(parent, cardW, cardH)
  gen.cardActive:SetPoint("TOPLEFT", T.INSET, cardY)
  gen.cardActive.label:SetText(U.L("GENERAL_CARD_ACTIVE"))
  gen.cardActive:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(U.L("GENERAL_CARD_ACTIVE_TIP"), nil, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  gen.cardActive:SetScript("OnLeave", GameTooltip_Hide)

  gen.cardPins = T.StatusCard(parent, cardW, cardH)
  gen.cardPins:SetPoint("LEFT", gen.cardActive, "RIGHT", T.INSET, 0)
  gen.cardPins.label:SetText(U.L("GENERAL_CARD_PINS"))
  gen.cardPins:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(U.L("GENERAL_CARD_PINS_TIP"), nil, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  gen.cardPins:SetScript("OnLeave", GameTooltip_Hide)

  gen.cardWanted = T.StatusCard(parent, cardW, cardH)
  gen.cardWanted:SetPoint("LEFT", gen.cardPins, "RIGHT", T.INSET, 0)
  gen.cardWanted.label:SetText(U.L("GENERAL_CARD_WANTED"))
  gen.cardWanted:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(U.L("GENERAL_CARD_WANTED_TIP"), nil, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  gen.cardWanted:SetScript("OnLeave", GameTooltip_Hide)

  -- C) Quick actions
  local actionY = cardY - cardH - T.GAP
  gen.posBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.posBtn:SetSize(200, 22)
  gen.posBtn:SetPoint("TOPLEFT", T.INSET, actionY)
  gen.posBtn:SetScript("OnClick", function()
    if not GR.db or not GR.db.privacy then return end
    GR.db.privacy.sharePosition = not GR.db.privacy.sharePosition
    GR:SendMessage("SHARE_POS_CHANGED")
    UI:RefreshGeneral()
  end)

  gen.pinsBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.pinsBtn:SetSize(200, 22)
  gen.pinsBtn:SetPoint("LEFT", gen.posBtn, "RIGHT", T.INSET, 0)
  gen.pinsBtn:SetScript("OnClick", function()
    if not GR.db or not GR.db.map then return end
    GR.db.map.showPins = not GR.db.map.showPins
    GR:SendMessage("MAP_SETTINGS_CHANGED")
    UI:RefreshGeneral()
  end)

  gen.syncBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.syncBtn:SetSize(180, 22)
  gen.syncBtn:SetPoint("LEFT", gen.pinsBtn, "RIGHT", T.INSET, 0)
  gen.syncBtn:SetText(U.L("GENERAL_SYNC"))
  gen.syncBtn._amIsGeneralSync = true
  gen.syncBtn:SetScript("OnClick", function()
    UI:RunGuildDataSync()
    UI:RefreshGeneral()
  end)
  UI:RegisterSyncButton(gen.syncBtn)

  -- Details toggle + collapsible block at bottom
  gen.detailsFrame = CreateFrame("Frame", nil, parent)
  gen.detailsFrame:SetPoint("BOTTOMLEFT", T.INSET, 8)
  gen.detailsFrame:SetPoint("BOTTOMRIGHT", -T.INSET, 8)
  gen.detailsFrame:SetHeight(72)
  T.ApplyPanelBackdrop(gen.detailsFrame, T.BG_ALT)
  gen.detailsFrame:Hide()

  gen.detailsProto = gen.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.detailsProto:SetPoint("TOPLEFT", T.INSET, -6)
  gen.detailsProto:SetPoint("RIGHT", -T.INSET, 0)
  gen.detailsProto:SetJustifyH("LEFT")

  gen.detailsWanted = gen.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.detailsWanted:SetPoint("TOPLEFT", gen.detailsProto, "BOTTOMLEFT", 0, -4)
  gen.detailsWanted:SetPoint("RIGHT", -T.INSET, 0)
  gen.detailsWanted:SetJustifyH("LEFT")

  gen.detailsShares = gen.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.detailsShares:SetPoint("TOPLEFT", gen.detailsWanted, "BOTTOMLEFT", 0, -4)
  gen.detailsShares:SetPoint("RIGHT", -T.INSET, 0)
  gen.detailsShares:SetJustifyH("LEFT")

  gen.detailsHelp = gen.detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.detailsHelp:SetPoint("TOPLEFT", gen.detailsShares, "BOTTOMLEFT", 0, -4)
  gen.detailsHelp:SetPoint("RIGHT", -T.INSET, 0)
  gen.detailsHelp:SetJustifyH("LEFT")

  gen.detailsBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.detailsBtn:SetSize(100, 20)
  gen.detailsBtn:SetPoint("BOTTOMLEFT", T.INSET, 8)
  gen.detailsBtn:SetText(U.L("GENERAL_DETAILS_SHOW"))
  gen.detailsBtn:SetScript("OnClick", function()
    SetDetailsExpanded(not gen.detailsOpen)
    if gen.detailsOpen then
      gen.detailsBtn:ClearAllPoints()
      gen.detailsBtn:SetPoint("BOTTOMLEFT", gen.detailsFrame, "TOPLEFT", 0, 4)
      gen.feedScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8 + gen.detailsFrame:GetHeight() + 28)
    else
      gen.detailsBtn:ClearAllPoints()
      gen.detailsBtn:SetPoint("BOTTOMLEFT", T.INSET, 8)
      gen.feedScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 28)
    end
  end)

  -- D) Activity fills remaining space
  local feedHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  feedHdr:SetPoint("TOPLEFT", T.INSET, actionY - 22 - T.GAP)
  feedHdr:SetText(U.L("GENERAL_FEED"))
  T.SetTextColor(feedHdr, T.ACCENT)

  gen.feedScroll = CreateFrame("ScrollFrame", "AngryMurlocsFeedScroll", parent, "UIPanelScrollFrameTemplate")
  gen.feedScroll:SetPoint("TOPLEFT", T.INSET, actionY - 22 - T.GAP - 16)
  gen.feedScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 28)

  gen.feedChild = CreateFrame("Frame", nil, gen.feedScroll)
  gen.feedChild:SetSize(560, FEED_ROWS * FEED_LINE_H)
  gen.feedScroll:SetScrollChild(gen.feedChild)

  gen.feedLines = {}
  for i = 1, FEED_ROWS do
    local fs = gen.feedChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 0, -((i - 1) * FEED_LINE_H))
    fs:SetWidth(540)
    fs:SetJustifyH("LEFT")
    fs:Hide()
    gen.feedLines[i] = fs
  end

  gen.feedEmpty = gen.feedChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.feedEmpty:SetPoint("TOPLEFT", 0, 0)
  gen.feedEmpty:SetText(U.L("GENERAL_FEED_EMPTY"))

  SetDetailsExpanded(false)
end

local function IsProfOnline(name, me)
  if name == me or U.IsSelfName(name) then return true end
  local age = GR.Comm and GR.Comm.PeerAge and GR.Comm:PeerAge(name)
  return age ~= nil and age <= PROF_ONLINE_SEC
end

local function ProfKeyLabel()
  if not profKeyFilter or profKeyFilter == "" then
    return U.L("PROF_ALL")
  end
  local prof = GR:GetModule("Professions")
  return (prof and prof.DisplayName and prof.DisplayName(profKeyFilter)) or profKeyFilter
end

local function HideProfMenu()
  if profMenu then profMenu:Hide() end
end

local function HideWhisperMenu()
  if whisperMenu then whisperMenu:Hide() end
end

local function EnsureProfMenu(parent)
  if profMenu then return profMenu end
  profMenu = CreateFrame("Frame", "AngryMurlocsProfMenu", parent)
  profMenu:SetFrameStrata("DIALOG")
  profMenu:SetSize(180, 280)
  T.ApplyPanelBackdrop(profMenu, T.BG)
  profMenu:Hide()
  profMenu:EnableMouse(true)
  profMenu:SetScript("OnLeave", function(self)
    if not MouseIsOver or not MouseIsOver(self) then self:Hide() end
  end)

  local keys = { "" }
  local prof = GR:GetModule("Professions")
  local list = prof and prof.ProfessionKeys and prof.ProfessionKeys() or {}
  for i = 1, #list do keys[#keys + 1] = list[i] end

  local y = -4
  for i = 1, #keys do
    local key = keys[i]
    local b = CreateFrame("Button", nil, profMenu, "UIPanelButtonTemplate")
    b:SetSize(168, 18)
    b:SetPoint("TOPLEFT", 6, y)
    if key == "" then
      b:SetText(U.L("PROF_ALL"))
    else
      b:SetText((prof and prof.DisplayName and prof.DisplayName(key)) or key)
    end
    b:SetScript("OnClick", function()
      profKeyFilter = key
      profPage = 1
      if profKeyBtn then profKeyBtn:SetText(ProfKeyLabel()) end
      HideProfMenu()
      UI:RefreshList()
    end)
    y = y - 20
  end
  profMenu:SetHeight(math.abs(y) + 8)
  return profMenu
end

local function EnsureWhisperMenu(parent)
  if whisperMenu then return whisperMenu end
  whisperMenu = CreateFrame("Frame", "AngryMurlocsWhisperMenu", parent)
  whisperMenu:SetFrameStrata("DIALOG")
  whisperMenu:SetSize(120, 28)
  T.ApplyPanelBackdrop(whisperMenu, T.BG)
  whisperMenu:Hide()
  local b = CreateFrame("Button", nil, whisperMenu, "UIPanelButtonTemplate")
  b:SetSize(108, 20)
  b:SetPoint("CENTER")
  b:SetText(U.L("PROF_WHISPER"))
  whisperMenu.btn = b
  b:SetScript("OnClick", function()
    local name = whisperMenu.targetName
    HideWhisperMenu()
    if not name or name == "" then return end
    local short = U.ShortName(name)
    if ChatFrame_SendTell then
      ChatFrame_SendTell(short)
    elseif ChatFrameEditBox and ChatFrameEditBox.SetText then
      -- Forever fallback
      if ChatFrameEditBox.Show then ChatFrameEditBox:Show() end
      ChatFrameEditBox:SetText("/w " .. short .. " ")
    end
  end)
  return whisperMenu
end

local function ResetProfFilters()
  profKeyFilter = ""
  profMinSkill = nil
  profActiveOnly = false
  profPage = 1
  if filterBox then filterBox:SetText("") end
  if profMinBox then profMinBox:SetText("") end
  if profActiveCb then profActiveCb:SetChecked(false) end
  if profKeyBtn then profKeyBtn:SetText(ProfKeyLabel()) end
  UI:RefreshList()
end

local function BuildProfPanel(parent)
  local filterLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  filterLabel:SetPoint("TOPLEFT", T.INSET, -4)
  filterLabel:SetText(U.L("PROF_SEARCH"))

  filterBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  filterBox:SetSize(130, 20)
  filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 6, 0)
  filterBox:SetAutoFocus(false)
  filterBox:SetScript("OnTextChanged", function()
    profPage = 1
    UI:RefreshList()
  end)

  profKeyBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  profKeyBtn:SetSize(130, 20)
  profKeyBtn:SetPoint("LEFT", filterBox, "RIGHT", T.INSET, 0)
  profKeyBtn:SetText(ProfKeyLabel())
  profKeyBtn:SetScript("OnClick", function(self)
    local menu = EnsureProfMenu(parent)
    if menu:IsShown() then
      menu:Hide()
    else
      menu:ClearAllPoints()
      menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
      menu:Show()
    end
  end)

  local minLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  minLabel:SetPoint("LEFT", profKeyBtn, "RIGHT", T.INSET, 0)
  minLabel:SetText(U.L("PROF_MIN_SKILL"))

  profMinBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  profMinBox:SetSize(50, 20)
  profMinBox:SetPoint("LEFT", minLabel, "RIGHT", 6, 0)
  profMinBox:SetAutoFocus(false)
  profMinBox:SetNumeric(true)
  profMinBox:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if t == "" then
      profMinSkill = nil
    else
      profMinSkill = tonumber(t)
    end
    profPage = 1
    UI:RefreshList()
  end)

  local refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  refreshBtn:SetSize(80, 20)
  refreshBtn:SetPoint("TOPRIGHT", -4, -2)
  refreshBtn:SetText(U.L("GENERAL_SYNC"))
  refreshBtn:SetScript("OnClick", function()
    UI:RunGuildDataSync()
    UI:RefreshList()
  end)
  UI:RegisterSyncButton(refreshBtn)

  -- Row 2
  profActiveCb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  profActiveCb:SetSize(24, 24)
  profActiveCb:SetPoint("TOPLEFT", T.INSET, -28)
  profActiveCb:SetScript("OnClick", function(self)
    profActiveOnly = self:GetChecked() and true or false
    profPage = 1
    UI:RefreshList()
  end)
  local activeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  activeLabel:SetPoint("LEFT", profActiveCb, "RIGHT", 2, 0)
  activeLabel:SetText(U.L("PROF_ACTIVE_ONLY"))

  local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  resetBtn:SetSize(120, 18)
  resetBtn:SetPoint("LEFT", activeLabel, "RIGHT", T.INSET, 0)
  resetBtn:SetText(U.L("PROF_RESET"))
  resetBtn:SetScript("OnClick", ResetProfFilters)

  profSortBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  profSortBtn:SetSize(150, 18)
  profSortBtn:SetPoint("LEFT", resetBtn, "RIGHT", T.INSET, 0)
  profSortBtn:SetScript("OnClick", function()
    profSortBy = (profSortBy == "online") and "name" or "online"
    profPage = 1
    UI:RefreshList()
  end)

  U.BuildColHeaders(parent, COLS, 4, -54, ROW_H)

  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -74)
  scroll:SetPoint("BOTTOMRIGHT", -24, 28)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(580, NUM_ROWS * ROW_H)
  scroll:SetScrollChild(scrollChild)

  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(580, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
    U.BuildColRow(row, COLS, ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", function(self)
      T.RowHoverEnter(self)
      if not self.fullName then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.fullName, 1, 1, 1)
      if self.online then
        GameTooltip:AddLine(U.L("PROF_ONLINE"), T.FRESH[1], T.FRESH[2], T.FRESH[3])
      else
        GameTooltip:AddLine(U.L("PROF_OFFLINE"), T.MUTED[1], T.MUTED[2], T.MUTED[3])
      end
      if self.tipProfs then
        GameTooltip:AddLine(self.tipProfs, T.TEXT[1], T.TEXT[2], T.TEXT[3], true)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
      T.RowHoverLeave(self)
      GameTooltip_Hide()
    end)
    row:SetScript("OnClick", function(self)
      if not self.fullName then return end
      local menu = EnsureWhisperMenu(parent)
      menu.targetName = self.fullName
      menu:ClearAllPoints()
      menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 40, 0)
      menu:Show()
    end)
    rows[i] = row
  end

  emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER", scroll, "CENTER", 0, 10)
  emptyText:SetText(U.L("PROF_EMPTY"))
  emptyText:Hide()

  emptyResetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  emptyResetBtn:SetSize(140, 20)
  emptyResetBtn:SetPoint("TOP", emptyText, "BOTTOM", 0, -8)
  emptyResetBtn:SetText(U.L("PROF_RESET"))
  emptyResetBtn:Hide()
  emptyResetBtn:SetScript("OnClick", ResetProfFilters)

  profPageText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  profPageText:SetPoint("BOTTOMLEFT", T.INSET, 8)
  profPageText:SetWidth(400)
  profPageText:SetJustifyH("LEFT")

  profPrevBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  profPrevBtn:SetSize(24, 20)
  profPrevBtn:SetPoint("BOTTOMRIGHT", -56, 6)
  profPrevBtn:SetText("<")
  profPrevBtn:SetScript("OnClick", function()
    profPage = math.max(1, profPage - 1)
    UI:RefreshList()
  end)

  profNextBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  profNextBtn:SetSize(24, 20)
  profNextBtn:SetPoint("LEFT", profPrevBtn, "RIGHT", 4, 0)
  profNextBtn:SetText(">")
  profNextBtn:SetScript("OnClick", function()
    profPage = profPage + 1
    UI:RefreshList()
  end)
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
      if activeTab == id then return end
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
  BuildProfPanel(profPanel)

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
    return "-", "-", "-", ""
  end
  local prof = GR:GetModule("Professions")
  local displayName = prof and prof.DisplayName
  local primary = {}
  local secondary = {}
  local tip = {}
  local secKeys = { cook = true, aid = true, fish = true }
  for i = 1, #list do
    local p = list[i]
    local labelName = (displayName and p.key and displayName(p.key)) or p.name or p.key
    local label = string.format(U.L("PROF_SKILL_SEP"), labelName, tonumber(p.skill) or 0)
    tip[#tip + 1] = label
    if secKeys[p.key] then
      secondary[#secondary + 1] = label
    else
      primary[#primary + 1] = label
    end
  end
  return primary[1] or "-", primary[2] or "-", (#secondary > 0 and table.concat(secondary, ", ") or "-"), table.concat(tip, "\n")
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
  HideProfMenu()
  HideWhisperMenu()

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

function UI:RefreshList()
  if not frame or not self:IsTabShown("prof") then return end
  local prof = GR:GetModule("Professions")
  local cache = prof and prof:GetAll() or {}
  local filter = filterBox and filterBox:GetText() or ""
  local hasFilters = (filter ~= "") or (profKeyFilter ~= "") or (profMinSkill ~= nil) or profActiveOnly

  local me = U.NormalizeName(U.PlayerName())
  local names = {}
  local totalCache = 0
  for name, entry in pairs(cache) do
    totalCache = totalCache + 1
    if not (U.IsSelfName(name) and name ~= me) then
      if UI.MatchesProfessionFilter(name, entry, {
        text = filter,
        profKey = profKeyFilter,
        minSkill = profMinSkill,
        activeOnly = profActiveOnly,
        me = me,
        isOnline = IsProfOnline,
      }) then
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
    if total == 0 then
      profPageText:SetText("")
    else
      profPageText:SetText(string.format(U.L("PROF_PAGE_RANGE"), first, last, total, profPage, pages))
    end
  end
  if profPrevBtn then
    if profPage <= 1 then profPrevBtn:Disable() else profPrevBtn:Enable() end
  end
  if profNextBtn then
    if profPage >= pages then profNextBtn:Disable() else profNextBtn:Enable() end
  end

  if total == 0 then
    emptyText:Show()
    if totalCache == 0 then
      emptyText:SetText(U.L("PROF_EMPTY"))
      emptyResetBtn:Hide()
    else
      emptyText:SetText(U.L("PROF_EMPTY_FILTER"))
      if hasFilters then emptyResetBtn:Show() else emptyResetBtn:Hide() end
    end
  else
    emptyText:Hide()
    emptyResetBtn:Hide()
  end

  scrollChild:SetHeight(math.max(last - first + 1, 1) * ROW_H)

  for i = 1, NUM_ROWS do
    local name = names[first + i - 1]
    if name and (first + i - 1) <= last then
      local entry = cache[name]
      local p1, p2, sec, tip = FormatProfs(entry.list)
      local online = IsProfOnline(name, me)
      local short = U.ShortName(name)
      if name == me or U.IsSelfName(name) then
        short = U.ShortName(me) .. " (" .. U.L("YOU") .. ")"
      end
      local mark = online and "*" or "·"
      short = mark .. " " .. short
      local r, g, b = U.ClassColor(entry.classFile)
      rows[i].fullName = name
      rows[i].online = online
      rows[i].tipProfs = tip
      T.ApplyRowChrome(rows[i], i, false)
      if rows[i].cols then
        local sn, _ = T.Truncate(short, 18)
        local t1 = T.Truncate(p1, 16)
        local t2 = T.Truncate(p2, 16)
        local t3 = T.Truncate(sec, 18)
        rows[i].cols[1]:SetText(sn)
        rows[i].cols[1]:SetTextColor(r, g, b)
        rows[i].cols[2]:SetText(t1)
        rows[i].cols[2]:SetTextColor(T.TEXT[1], T.TEXT[2], T.TEXT[3])
        rows[i].cols[3]:SetText(t2)
        rows[i].cols[3]:SetTextColor(T.TEXT[1], T.TEXT[2], T.TEXT[3])
        rows[i].cols[4]:SetText(t3)
        rows[i].cols[4]:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
      end
      rows[i]:Show()
    else
      rows[i].fullName = nil
      rows[i].online = nil
      rows[i].tipProfs = nil
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
  if self.enabled then return end
  self.enabled = true

  GR:BindMessage(self, "PROF_CACHE_CHANGED", function()
    if UI:IsTabShown("prof") then
      UI:RefreshList()
    end
  end)

  GR:BindMessage(self, "POS_CACHE_CHANGED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:BindMessage(self, "POS_REMOVED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:BindMessage(self, "POS_CACHE_CLEARED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:BindMessage(self, "SHARE_POS_CHANGED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)
  GR:BindMessage(self, "MAP_SETTINGS_CHANGED", function()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end)

  GR:BindMessage(self, "SIGHT_APPLIED", function(_, target, zone, reporter)
    PushActivity({
      kind = "sight",
      player = target or "?",
      zone = zone,
      reporter = reporter,
      at = U.WallTime(),
    })
  end)

  GR:BindMessage(self, "DEATH_UPDATE", function(_, victim)
    PushActivity({ kind = "death", player = victim or "?", at = U.WallTime() })
  end)

  GR:BindMessage(self, "LVL_UPDATE", function(_, sender, level)
    PushActivity({ kind = "lvl", player = sender or "?", level = tonumber(level) or 0, at = U.WallTime() })
  end)

  GR:BindMessage(self, "WANTED_KILL", function(_, killer, origin, level, kind)
    PushActivity({
      kind = kind == "own" and "wanted_own" or "wanted",
      player = killer or "?",
      origin = origin,
      level = tonumber(level) or 0,
      at = U.WallTime(),
    })
  end)

  local function RefreshGeneralIfShown()
    if UI:IsTabShown("general") then
      UI:RefreshGeneral()
    end
  end
  GR:BindMessage(self, "SYNC_STATUS", function()
    UI:UpdateSyncButtons()
    RefreshGeneralIfShown()
  end)
  GR:BindMessage(self, "WANTED_CHANGED", RefreshGeneralIfShown)
  GR:BindMessage(self, "PRIVACY_CHANGED", RefreshGeneralIfShown)
end

function UI:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  GR:UnbindMessages(self)
end
