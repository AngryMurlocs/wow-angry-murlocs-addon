local GR = AngryMurlocs
local U = GR.Util
local T = GR.Theme

local UI = GR:NewModule("UI")

local frame
local generalPanel
local profPanel
local wantedPanel
local optPanel
local adminPanel
local adminEvents
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
local ROW_H = 28
local NUM_ROWS = 40
local PROF_ONLINE_SEC = 600
local profPage = 1
local profSortBy = "online" -- online | name
local profMemberChrome = {} -- members chrome hidden while catalog / other sub-tab
local profSearchChrome = {}
local profSubTab = "members" -- members | search
local profSubBtnMembers
local profSubBtnSearch
local membersHost
local searchHost
local searchFilterBox
local searchProfKey = ""
local searchRows = {}
local searchPage = 1
local searchPageText
local searchPrevBtn
local searchNextBtn
local searchEmptyText
local searchRecipeStatusFS
local searchBackBtn
local searchNameHdr
local searchProfHdr
local searchCraftHdr
local SEARCH_NUM_ROWS = 12
local SEARCH_ROW_H = 26
local profNavSnap = nil
local PROF_ICON = 18
local PROF_SLOT_W = 92
local PROF_SEC_MAX = 3

local activity = {}
local ACTIVITY_MAX = 20
local FEED_ROWS = 20
local FEED_LINE_H = 18

local syncButtons = {}

local gen = {}

-- Name column only; profession icons are built per row.
local COLS = {
  { key = "COL_NAME", x = 4, w = 150 },
}

local TAB_TITLES = {
  general = "TAB_GENERAL",
  prof = "TAB_PROF",
  wanted = "TAB_WANTED",
  opt = "TAB_OPT",
  admin = "TAB_ADMIN",
}

-- Hide Admin while the panel is only a placeholder. Keep officer gate for later.
local ADMIN_TAB_ENABLED = false

local function CanShowAdminTab()
  return ADMIN_TAB_ENABLED and U.IsGuildOfficer and U.IsGuildOfficer()
end

local function ApplyAdminTabButton()
  local btn = tabBtns.admin
  if not btn then return end
  if CanShowAdminTab() then
    btn:Show()
  else
    btn:Hide()
  end
end

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
  p:SetPoint("TOPLEFT", 8, -56)
  p:SetPoint("BOTTOMRIGHT", -8, 8)
  p:Hide()
  return p
end

local function UpdateTabButtons()
  ApplyAdminTabButton()
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
  -- Recipes: on-demand via catalog open / recipe-search refresh (no Wanted-tied blast).
  if wanted and wanted.RequestSync then wanted:RequestSync("full") end
  UI:UpdateSyncButtons()
end

-- Recipe-search catalogue refresh (separate from Wanted sync status).
function UI:RunRecipeDataRefresh()
  local R = GR:GetModule("ProfRecipes")
  if not R or not R.RequestRecipeDataRefresh then return end
  local ok, why = R:RequestRecipeDataRefresh(searchProfKey ~= "" and searchProfKey or nil, false)
  if searchRecipeStatusFS then
    if why == "sent" or why == "requesting" then
      searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_DATA_STATUS_LOADING"))
    elseif why == "cooldown" or why == "busy" then
      searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_DATA_STATUS_CD"))
    elseif why == "no_guild" then
      searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_REFRESH_NO_GUILD"))
    elseif not ok then
      searchRecipeStatusFS:SetText(string.format(U.L("PROF_RECIPE_REFRESH_FAIL"), tostring(why or "?")))
    end
  end
  if ok then
    UI:RefreshSearchList()
  end
  return ok, why
end

function UI:UpdateRecipeDataRefreshStatus(status)
  if not searchRecipeStatusFS then return end
  if status == "requesting" or status == "busy" then
    searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_DATA_STATUS_LOADING"))
  elseif status == "done" then
    searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_DATA_STATUS_DONE"))
  elseif status == "timeout" then
    searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_DATA_STATUS_TIMEOUT"))
  elseif status == "cooldown" then
    searchRecipeStatusFS:SetText(U.L("PROF_RECIPE_DATA_STATUS_CD"))
  elseif not status or status == "idle" then
    searchRecipeStatusFS:SetText("")
  end
end

local function ScheduleProfViewRefresh()
  if UI._profRefreshPending then return end
  UI._profRefreshPending = true
  C_Timer.After(0.05, function()
    UI._profRefreshPending = false
    if not UI:IsTabShown("prof") then return end
    if UI.IsRecipeCatalogOpen and UI:IsRecipeCatalogOpen() then
      UI:RefreshRecipeCatalog()
      return
    end
    if (profSubTab or "members") == "search" then
      UI:RefreshSearchList()
    else
      UI:RefreshList()
    end
  end)
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

-- Bottom panel on General: "closed" | "details" | "help" (session-local).
local function CaptureFeedScroll()
  if gen.feedScroll and gen.feedScroll.GetVerticalScroll then
    gen._feedScrollY = gen.feedScroll:GetVerticalScroll()
  end
end

local function RestoreFeedScroll()
  if not gen.feedScroll or gen._feedScrollY == nil then return end
  local y = gen._feedScrollY
  C_Timer.After(0, function()
    if not gen.feedScroll or not gen.feedScroll.SetVerticalScroll then return end
    local maxY = 0
    if gen.feedScroll.GetVerticalScrollRange then
      maxY = gen.feedScroll:GetVerticalScrollRange() or 0
    end
    if y > maxY then y = maxY end
    if y < 0 then y = 0 end
    gen.feedScroll:SetVerticalScroll(y)
  end)
end

local function MarkBottomButtons()
  local mode = gen.bottomMode or "closed"
  -- LockHighlight marks active; keep Enable so same-button click can close.
  if gen.detailsBtn then
    gen.detailsBtn:SetText(U.L("GENERAL_DETAILS"))
    gen.detailsBtn:Enable()
    if mode == "details" then
      if gen.detailsBtn.LockHighlight then gen.detailsBtn:LockHighlight() end
    else
      if gen.detailsBtn.UnlockHighlight then gen.detailsBtn:UnlockHighlight() end
    end
  end
  if gen.helpBtn then
    gen.helpBtn:SetText(U.L("GENERAL_HELP_BTN"))
    gen.helpBtn:Enable()
    if mode == "help" then
      if gen.helpBtn.LockHighlight then gen.helpBtn:LockHighlight() end
    else
      if gen.helpBtn.UnlockHighlight then gen.helpBtn:UnlockHighlight() end
    end
  end
end

local function ApplyBottomLayout()
  if not generalPanel or not gen.bottomPanel or not gen.feedScroll then return end
  CaptureFeedScroll()
  local mode = gen.bottomMode or "closed"
  local btnH, btnPad, gap = 20, 8, 4

  if gen.detailsBtn then
    gen.detailsBtn:ClearAllPoints()
    gen.detailsBtn:SetPoint("BOTTOMLEFT", generalPanel, "BOTTOMLEFT", T.INSET, btnPad)
  end
  if gen.helpBtn then
    gen.helpBtn:ClearAllPoints()
    gen.helpBtn:SetPoint("LEFT", gen.detailsBtn, "RIGHT", 6, 0)
  end
  MarkBottomButtons()

  if mode == "closed" then
    gen.bottomPanel:Hide()
    gen.feedScroll:ClearAllPoints()
    gen.feedScroll:SetPoint("TOPLEFT", generalPanel, "TOPLEFT", T.INSET, gen.feedTopY or -80)
    gen.feedScroll:SetPoint("BOTTOMRIGHT", generalPanel, "BOTTOMRIGHT", -28, btnPad + btnH + gap)
    RestoreFeedScroll()
    return
  end

  local showDetails = (mode == "details")
  if gen.statusHdr then
    if showDetails then gen.statusHdr:Show() else gen.statusHdr:Hide() end
  end
  if gen.detailsProto then
    if showDetails then gen.detailsProto:Show() else gen.detailsProto:Hide() end
  end
  if gen.detailsWanted then
    if showDetails then gen.detailsWanted:Show() else gen.detailsWanted:Hide() end
  end
  if gen.detailsShares then
    if showDetails then gen.detailsShares:Show() else gen.detailsShares:Hide() end
  end
  if gen.commandsHdr then
    if showDetails then gen.commandsHdr:Hide() else gen.commandsHdr:Show() end
  end
  if gen.helpText then
    if showDetails then gen.helpText:Hide() else gen.helpText:Show() end
  end

  local panelW = math.max(120, (generalPanel:GetWidth() or 600) - 2 * T.INSET)
  local innerW = math.max(80, panelW - 2 * T.INSET)
  local contentH
  if showDetails then
    if gen.detailsProto then gen.detailsProto:SetWidth(innerW) end
    if gen.detailsWanted then gen.detailsWanted:SetWidth(innerW) end
    if gen.detailsShares then gen.detailsShares:SetWidth(innerW) end
    local h1 = (gen.detailsProto and gen.detailsProto:GetStringHeight()) or 12
    local h2 = (gen.detailsWanted and gen.detailsWanted:GetStringHeight()) or 12
    local h3 = (gen.detailsShares and gen.detailsShares:GetStringHeight()) or 12
    contentH = math.max(58, 16 + 4 + h1 + 4 + h2 + 4 + h3 + 10)
  else
    if gen.helpText then
      gen.helpText:SetWidth(innerW)
      gen.helpText:SetText(U.L("GENERAL_HELP"))
    end
    local hh = (gen.helpText and gen.helpText:GetStringHeight()) or 48
    contentH = math.max(78, 16 + 4 + hh + 12)
  end

  local parentH = generalPanel:GetHeight() or 400
  local maxPanel = math.max(48, parentH - 160)
  local needScroll = contentH > maxPanel
  local panelH = needScroll and maxPanel or contentH

  if gen.bottomChild then
    gen.bottomChild:SetWidth(innerW + 4)
    gen.bottomChild:SetHeight(contentH)
  end
  if gen.bottomScroll then
    if needScroll then
      gen.bottomScroll:Show()
    else
      gen.bottomScroll:SetVerticalScroll(0)
      -- keep scrollframe; content fits
    end
  end

  gen.bottomPanel:SetHeight(panelH)
  gen.bottomPanel:ClearAllPoints()
  gen.bottomPanel:SetPoint("BOTTOMLEFT", generalPanel, "BOTTOMLEFT", T.INSET, btnPad + btnH + gap)
  gen.bottomPanel:SetPoint("BOTTOMRIGHT", generalPanel, "BOTTOMRIGHT", -T.INSET, btnPad + btnH + gap)
  gen.bottomPanel:Show()

  if gen.feedTopY then
    gen.feedScroll:ClearAllPoints()
    gen.feedScroll:SetPoint("TOPLEFT", generalPanel, "TOPLEFT", T.INSET, gen.feedTopY)
    gen.feedScroll:SetPoint("BOTTOMRIGHT", generalPanel, "BOTTOMRIGHT", -28, btnPad + btnH + gap + panelH + gap)
  else
    gen.feedScroll:SetPoint("BOTTOMRIGHT", generalPanel, "BOTTOMRIGHT", -28, btnPad + btnH + gap + panelH + gap)
  end
  RestoreFeedScroll()
end

local function SetBottomMode(mode)
  if mode ~= "details" and mode ~= "help" then
    mode = "closed"
  end
  CaptureFeedScroll()
  -- Toggle off if clicking the already-active mode
  if gen.bottomMode == mode then
    mode = "closed"
  end
  gen.bottomMode = mode
  ApplyBottomLayout()
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
    gen.detailsWanted:SetText(string.format(U.L("GENERAL_WANTED_SUMMARY"), s.total, top))
  end
  -- Help text is only rebuilt when the help panel opens (ApplyBottomLayout).
  -- Remeasure details panel if open; never change bottomMode here.
  if gen.bottomMode == "details" then
    ApplyBottomLayout()
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

local function EnsureDiscordPopup()
  if StaticPopupDialogs and StaticPopupDialogs["ANGRYMURLOCS_DISCORD"] then return end
  if not StaticPopupDialogs then return end
  StaticPopupDialogs["ANGRYMURLOCS_DISCORD"] = {
    text = U.L("GENERAL_DISCORD_POPUP"),
    button1 = OKAY or "OK",
    hasEditBox = true,
    editBoxWidth = 280,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(dialog)
      local url = GR.DISCORD_INVITE or ""
      local box = dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
      if box then
        box:SetText(url)
        box:HighlightText()
        box:SetFocus()
      end
    end,
    EditBoxOnEscapePressed = function(editBox)
      editBox:GetParent():Hide()
    end,
  }
end

local function CopyDiscordInvite()
  local url = GR.DISCORD_INVITE
  if not url or url == "" then return end
  if SetClipboardData then
    pcall(SetClipboardData, url)
  end
  U.Print(U.L("GENERAL_DISCORD_COPIED"))
  EnsureDiscordPopup()
  if StaticPopup_Show then
    StaticPopup_Show("ANGRYMURLOCS_DISCORD")
  end
end

local function BuildGeneralPanel(parent)
  -- A) Header
  gen.guildText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gen.guildText:SetPoint("TOPLEFT", T.INSET, -4)
  gen.guildText:SetWidth(400)
  gen.guildText:SetJustifyH("LEFT")

  gen.discordBtn = CreateFrame("Button", nil, parent)
  gen.discordBtn:SetSize(32, 32)
  gen.discordBtn:SetPoint("TOPRIGHT", -T.INSET, -2)
  gen.discordBtn:SetNormalTexture("Interface\\AddOns\\AngryMurlocs\\Media\\Discord")
  gen.discordBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  gen.discordBtn:SetScript("OnClick", CopyDiscordInvite)
  gen.discordBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(U.L("GENERAL_DISCORD_TIP"), 1, 1, 1)
    GameTooltip:Show()
  end)
  gen.discordBtn:SetScript("OnLeave", GameTooltip_Hide)

  gen.versionText = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.versionText:SetPoint("TOPRIGHT", gen.discordBtn, "TOPLEFT", -6, -4)
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

  -- Bottom: Details / Hilfe buttons + shared panel (status XOR commands)
  gen.bottomPanel = CreateFrame("Frame", nil, parent)
  gen.bottomPanel:SetHeight(58)
  T.ApplyPanelBackdrop(gen.bottomPanel, T.BG_ALT)
  gen.bottomPanel:Hide()

  gen.bottomScroll = CreateFrame("ScrollFrame", "AngryMurlocsGeneralBottomScroll", gen.bottomPanel, "UIPanelScrollFrameTemplate")
  gen.bottomScroll:SetPoint("TOPLEFT", 4, -4)
  gen.bottomScroll:SetPoint("BOTTOMRIGHT", -24, 4)

  gen.bottomChild = CreateFrame("Frame", nil, gen.bottomScroll)
  gen.bottomChild:SetSize(520, 58)
  gen.bottomScroll:SetScrollChild(gen.bottomChild)

  local contentParent = gen.bottomChild

  gen.statusHdr = contentParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  gen.statusHdr:SetPoint("TOPLEFT", T.INSET, -2)
  gen.statusHdr:SetText(U.L("GENERAL_STATUS_HDR"))
  T.SetTextColor(gen.statusHdr, T.ACCENT)

  gen.detailsProto = contentParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.detailsProto:SetPoint("TOPLEFT", gen.statusHdr, "BOTTOMLEFT", 0, -4)
  gen.detailsProto:SetJustifyH("LEFT")

  gen.detailsWanted = contentParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.detailsWanted:SetPoint("TOPLEFT", gen.detailsProto, "BOTTOMLEFT", 0, -4)
  gen.detailsWanted:SetJustifyH("LEFT")

  gen.detailsShares = contentParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gen.detailsShares:SetPoint("TOPLEFT", gen.detailsWanted, "BOTTOMLEFT", 0, -4)
  gen.detailsShares:SetJustifyH("LEFT")

  gen.commandsHdr = contentParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  gen.commandsHdr:SetPoint("TOPLEFT", T.INSET, -2)
  gen.commandsHdr:SetText(U.L("GENERAL_COMMANDS_HDR"))
  T.SetTextColor(gen.commandsHdr, T.ACCENT)
  gen.commandsHdr:Hide()

  gen.helpText = contentParent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gen.helpText:SetPoint("TOPLEFT", gen.commandsHdr, "BOTTOMLEFT", 0, -4)
  gen.helpText:SetJustifyH("LEFT")
  if gen.helpText.SetWordWrap then gen.helpText:SetWordWrap(true) end
  gen.helpText:Hide()

  gen.detailsBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.detailsBtn:SetSize(90, 20)
  gen.detailsBtn:SetText(U.L("GENERAL_DETAILS"))
  gen.detailsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(U.L("GENERAL_DETAILS_TIP"), 1, 1, 1)
    GameTooltip:Show()
  end)
  gen.detailsBtn:SetScript("OnLeave", GameTooltip_Hide)
  gen.detailsBtn:SetScript("OnClick", function()
    SetBottomMode("details")
  end)

  gen.helpBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  gen.helpBtn:SetSize(90, 20)
  gen.helpBtn:SetText(U.L("GENERAL_HELP_BTN"))
  gen.helpBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if gen.bottomMode == "help" then
      GameTooltip:SetText(U.L("GENERAL_HELP_HIDE"), 1, 1, 1)
    else
      GameTooltip:SetText(U.L("GENERAL_HELP_SHOW"), 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  gen.helpBtn:SetScript("OnLeave", GameTooltip_Hide)
  gen.helpBtn:SetScript("OnClick", function()
    SetBottomMode("help")
  end)

  -- D) Activity fills remaining space
  local feedHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  feedHdr:SetPoint("TOPLEFT", T.INSET, actionY - 22 - T.GAP)
  feedHdr:SetText(U.L("GENERAL_FEED"))
  T.SetTextColor(feedHdr, T.ACCENT)

  gen.feedTopY = actionY - 22 - T.GAP - 16
  gen.feedScroll = CreateFrame("ScrollFrame", "AngryMurlocsFeedScroll", parent, "UIPanelScrollFrameTemplate")
  gen.feedScroll:SetPoint("TOPLEFT", T.INSET, gen.feedTopY)
  gen.feedScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 32)

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

  if not gen.bottomMode then
    gen.bottomMode = "closed"
  end
  ApplyBottomLayout()

  parent:HookScript("OnSizeChanged", function()
    if gen.bottomMode and gen.bottomMode ~= "closed" then
      ApplyBottomLayout()
    end
  end)
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

local function TrimSearchQuery(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ResetSearchScroll()
  local scroll = searchHost and searchHost.scroll
  if scroll and scroll.SetVerticalScroll then
    scroll:SetVerticalScroll(0)
  end
end

local function ClearSearchRow(row)
  if not row then return end
  row.recipeId = nil
  row.profKey = nil
  row.crafters = nil
  row._amRecipeName = nil
  row._amProfBrowseKey = nil
  row._amBrowseRecipeCount = nil
  row._amBrowseCrafterCount = nil
end

-- Aggregate index into profession categories (unique crafters per category).
local function BuildSearchProfessionCategories(index, prof)
  local R = GR:GetModule("ProfRecipes")
  local byKey = {}
  for i = 1, #index do
    local row = index[i]
    local pk = row.profKey
    if type(pk) == "string" and not (R and R.IsGathering and R.IsGathering(pk)) then
      local cat = byKey[pk]
      if not cat then
        cat = { profKey = pk, recipeCount = 0, crafters = {}, _seen = {} }
        byKey[pk] = cat
      end
      cat.recipeCount = cat.recipeCount + 1
      local crafters = row.crafters or {}
      for ci = 1, #crafters do
        local name = crafters[ci]
        if name and not cat._seen[name] then
          cat._seen[name] = true
          cat.crafters[#cat.crafters + 1] = name
        end
      end
    end
  end

  local order, known = {}, {}
  local keys = (prof and prof.ProfessionKeys and prof.ProfessionKeys()) or {}
  for i = 1, #keys do
    local k = keys[i]
    if byKey[k] then
      order[#order + 1] = byKey[k]
      known[k] = true
    end
  end
  local extras = {}
  for k, cat in pairs(byKey) do
    if not known[k] then extras[#extras + 1] = cat end
  end
  table.sort(extras, function(a, b)
    local na = string.lower((prof and prof.DisplayName and prof.DisplayName(a.profKey)) or a.profKey or "")
    local nb = string.lower((prof and prof.DisplayName and prof.DisplayName(b.profKey)) or b.profKey or "")
    if na ~= nb then return na < nb end
    return tostring(a.profKey) < tostring(b.profKey)
  end)
  for i = 1, #extras do order[#order + 1] = extras[i] end
  for i = 1, #order do
    order[i]._seen = nil
    table.sort(order[i].crafters, function(a, b)
      return string.lower(tostring(a)) < string.lower(tostring(b))
    end)
  end
  return order
end

-- Members-overview profession filter only (recipe search uses categories + Back).
local function EnsureProfMenu(parent)
  if not profMenu then
    profMenu = CreateFrame("Frame", "AngryMurlocsProfMenu", parent)
    profMenu:SetFrameStrata("DIALOG")
    profMenu:SetSize(180, 280)
    T.ApplyPanelBackdrop(profMenu, T.BG)
    profMenu:Hide()
    profMenu:EnableMouse(true)
    -- No OnLeave auto-hide: hovering child buttons fires parent OnLeave and closes the menu.
    profMenu.buttons = {}

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
      b._amKey = key
      b:SetScript("OnClick", function()
        profKeyFilter = key
        profPage = 1
        if profKeyBtn then profKeyBtn:SetText(ProfKeyLabel()) end
        HideProfMenu()
        UI:RefreshList()
      end)
      profMenu.buttons[i] = b
      y = y - 20
    end
    profMenu:SetHeight(math.abs(y) + 8)
  end
  return profMenu
end

local function UpdateSearchBackChrome()
  if not searchRecipeStatusFS then return end
  local refresh = searchHost and searchHost._amRefreshBtn
  local drilled = searchProfKey ~= ""
  if searchBackBtn then
    if drilled then searchBackBtn:Show() else searchBackBtn:Hide() end
  end
  searchRecipeStatusFS:ClearAllPoints()
  if drilled and searchBackBtn then
    searchRecipeStatusFS:SetPoint("LEFT", searchBackBtn, "RIGHT", 8, 0)
  else
    searchRecipeStatusFS:SetPoint("TOPLEFT", T.INSET, -28)
  end
  if refresh then
    searchRecipeStatusFS:SetPoint("RIGHT", refresh, "LEFT", -8, 0)
  end
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

local function HideProfFilterPopup()
  local popup = membersHost and membersHost._amFilterPopup
  if popup and popup.Hide then
    popup:Hide()
  end
end

local function UpdateProfFilterStatus()
  local fs = membersHost and membersHost._amFilterStatus
  if not fs then return end
  local parts = {}
  if profMinSkill then
    parts[#parts + 1] = string.format(U.L("PROF_FILTER_STATUS_MIN"), profMinSkill)
  end
  if profActiveOnly then
    parts[#parts + 1] = U.L("PROF_FILTER_STATUS_ACTIVE")
  end
  if profSortBy and profSortBy ~= "online" then
    local sortLabel = U.L("PROF_SORT_NAME")
    parts[#parts + 1] = string.format(U.L("PROF_FILTER_STATUS_SORT"), sortLabel)
  end
  if #parts == 0 then
    fs:SetText("")
    fs:Hide()
  else
    fs:SetText(table.concat(parts, " · "))
    fs:Show()
  end
end

local function ResetProfFilters()
  profKeyFilter = ""
  profMinSkill = nil
  profActiveOnly = false
  profSortBy = "online"
  profPage = 1
  if filterBox then filterBox:SetText("") end
  if profMinBox then profMinBox:SetText("") end
  if profActiveCb then profActiveCb:SetChecked(false) end
  if profKeyBtn then profKeyBtn:SetText(ProfKeyLabel()) end
  HideProfFilterPopup()
  UpdateProfFilterStatus()
  UI:RefreshList()
end

local function MarkProfSubTabs()
  local mode = profSubTab or "members"
  if T and T.StyleTabButton then
    T.StyleTabButton(profSubBtnMembers, mode == "members")
    T.StyleTabButton(profSubBtnSearch, mode == "search")
  else
    if profSubBtnMembers then
      if mode == "members" then
        if profSubBtnMembers.LockHighlight then profSubBtnMembers:LockHighlight() end
      else
        if profSubBtnMembers.UnlockHighlight then profSubBtnMembers:UnlockHighlight() end
      end
    end
    if profSubBtnSearch then
      if mode == "search" then
        if profSubBtnSearch.LockHighlight then profSubBtnSearch:LockHighlight() end
      else
        if profSubBtnSearch.UnlockHighlight then profSubBtnSearch:UnlockHighlight() end
      end
    end
  end
end

local function SplitPrimarySecondary(list)
  local primary = {}
  local secondary = {}
  local secKeys = { cook = true, aid = true, fish = true }
  for i = 1, #(list or {}) do
    local p = list[i]
    if p and p.key then
      if secKeys[p.key] then
        secondary[#secondary + 1] = p
      else
        primary[#primary + 1] = p
      end
    end
  end
  return primary, secondary
end

local function WireProfIconButton(btn, row)
  btn:RegisterForClicks("LeftButtonUp")
  btn:SetScript("OnEnter", function(self)
    T.RowHoverEnter(row)
    if not self.profKey or not row.fullName then return end
    local prof = GR:GetModule("Professions")
    local label = (prof and prof.DisplayName and prof.DisplayName(self.profKey)) or self.profKey
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.skill then
      GameTooltip:AddLine(string.format(U.L("PROF_SKILL_SEP"), label, self.skill), 1, 1, 1)
    else
      GameTooltip:AddLine(label, 1, 1, 1)
    end
    GameTooltip:AddLine(string.format(U.L("PROF_RECIPE_OPEN_TIP"), label), T.FRESH[1], T.FRESH[2], T.FRESH[3])
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    T.RowHoverLeave(row)
    GameTooltip_Hide()
  end)
  btn:SetScript("OnClick", function(self)
    if not row.fullName or not self.profKey then return end
    if UI.OpenRecipeCatalog then
      HideWhisperMenu()
      UI:OpenRecipeCatalog(row.fullName, self.profKey)
    end
  end)
end

local function BuildProfPanel(parent)
  -- Sub-tabs (fixed position/width)
  profSubBtnMembers = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  profSubBtnMembers:SetSize(120, 20)
  profSubBtnMembers:SetPoint("TOPLEFT", T.INSET, -2)
  profSubBtnMembers:SetText(U.L("PROF_SUB_MEMBERS"))
  profSubBtnMembers:SetScript("OnClick", function()
    UI:ShowProfSubTab("members")
  end)

  profSubBtnSearch = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  profSubBtnSearch:SetSize(120, 20)
  profSubBtnSearch:SetPoint("LEFT", profSubBtnMembers, "RIGHT", 6, 0)
  profSubBtnSearch:SetText(U.L("PROF_SUB_SEARCH"))
  profSubBtnSearch:SetScript("OnClick", function()
    UI:ShowProfSubTab("search")
  end)

  membersHost = CreateFrame("Frame", nil, parent)
  membersHost:SetPoint("TOPLEFT", 0, -26)
  membersHost:SetPoint("BOTTOMRIGHT", 0, 0)

  searchHost = CreateFrame("Frame", nil, parent)
  searchHost:SetPoint("TOPLEFT", 0, -26)
  searchHost:SetPoint("BOTTOMRIGHT", 0, 0)
  searchHost:Hide()

  -- ===== Members chrome =====
  local filterLabel = membersHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  filterLabel:SetPoint("TOPLEFT", T.INSET, -4)
  filterLabel:SetText(U.L("PROF_SEARCH"))

  filterBox = CreateFrame("EditBox", nil, membersHost, "InputBoxTemplate")
  filterBox:SetSize(140, 20)
  filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 6, 0)
  filterBox:SetAutoFocus(false)
  filterBox:SetScript("OnTextChanged", function()
    profPage = 1
    UI:RefreshList()
  end)

  profKeyBtn = CreateFrame("Button", nil, membersHost, "UIPanelButtonTemplate")
  profKeyBtn:SetSize(120, 20)
  profKeyBtn:SetPoint("LEFT", filterBox, "RIGHT", T.INSET, 0)
  profKeyBtn:SetText(ProfKeyLabel())
  profKeyBtn:SetScript("OnClick", function(self)
    HideProfFilterPopup()
    local menu = EnsureProfMenu(parent)
    if menu:IsShown() then
      menu:Hide()
    else
      menu:ClearAllPoints()
      menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
      menu:Show()
    end
  end)

  local profFilterBtn = CreateFrame("Button", nil, membersHost, "UIPanelButtonTemplate")
  profFilterBtn:SetSize(70, 20)
  profFilterBtn:SetPoint("LEFT", profKeyBtn, "RIGHT", T.INSET, 0)
  profFilterBtn:SetText(U.L("PROF_FILTER"))

  local refreshBtn = CreateFrame("Button", nil, membersHost, "UIPanelButtonTemplate")
  refreshBtn:SetSize(80, 20)
  refreshBtn:SetPoint("TOPRIGHT", -4, -2)
  refreshBtn:SetText(U.L("GENERAL_SYNC"))
  refreshBtn:SetScript("OnClick", function()
    UI:RunGuildDataSync()
    UI:RefreshList()
  end)
  UI:RegisterSyncButton(refreshBtn)

  -- Extra filters live in a dismissible popup (min skill / active-only / sort / reset).
  local profFilterPopup = CreateFrame("Frame", "AngryMurlocsProfFilterPopup", membersHost)
  profFilterPopup:SetSize(280, 118)
  profFilterPopup:SetPoint("TOPLEFT", profFilterBtn, "BOTTOMLEFT", 0, -2)
  profFilterPopup:SetFrameStrata("DIALOG")
  if T and T.ApplyPanelBackdrop then
    T.ApplyPanelBackdrop(profFilterPopup, T.BG)
  end
  profFilterPopup:Hide()
  membersHost._amFilterPopup = profFilterPopup
  profFilterBtn:SetScript("OnClick", function()
    if profFilterPopup:IsShown() then
      HideProfFilterPopup()
    else
      HideProfMenu()
      HideWhisperMenu()
      profFilterPopup:Show()
    end
  end)

  local minLabel = profFilterPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  minLabel:SetPoint("TOPLEFT", 10, -12)
  minLabel:SetText(U.L("PROF_MIN_SKILL"))

  profMinBox = CreateFrame("EditBox", nil, profFilterPopup, "InputBoxTemplate")
  profMinBox:SetSize(48, 20)
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
    UpdateProfFilterStatus()
    UI:RefreshList()
  end)

  profActiveCb = CreateFrame("CheckButton", nil, profFilterPopup, "UICheckButtonTemplate")
  profActiveCb:SetSize(24, 24)
  profActiveCb:SetPoint("TOPLEFT", 6, -38)
  profActiveCb:SetScript("OnClick", function(self)
    profActiveOnly = self:GetChecked() and true or false
    profPage = 1
    UpdateProfFilterStatus()
    UI:RefreshList()
  end)
  local activeLabel = profFilterPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  activeLabel:SetPoint("LEFT", profActiveCb, "RIGHT", 2, 0)
  activeLabel:SetWidth(230)
  activeLabel:SetJustifyH("LEFT")
  activeLabel:SetText(U.L("PROF_ACTIVE_ONLY"))

  profSortBtn = CreateFrame("Button", nil, profFilterPopup, "UIPanelButtonTemplate")
  profSortBtn:SetSize(160, 20)
  profSortBtn:SetPoint("TOPLEFT", 10, -68)
  profSortBtn:SetScript("OnClick", function()
    profSortBy = (profSortBy == "online") and "name" or "online"
    profPage = 1
    UpdateProfFilterStatus()
    UI:RefreshList()
  end)

  local resetBtn = CreateFrame("Button", nil, profFilterPopup, "UIPanelButtonTemplate")
  resetBtn:SetSize(90, 20)
  resetBtn:SetPoint("LEFT", profSortBtn, "RIGHT", 6, 0)
  resetBtn:SetText(U.L("PROF_FILTER_CLEAR"))
  resetBtn:SetScript("OnClick", ResetProfFilters)

  local profFilterStatusFS = membersHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  profFilterStatusFS:SetPoint("TOPLEFT", T.INSET, -28)
  profFilterStatusFS:SetPoint("RIGHT", membersHost, "RIGHT", -12, 0)
  profFilterStatusFS:SetJustifyH("LEFT")
  T.SetTextColor(profFilterStatusFS, T.MUTED)
  profFilterStatusFS:Hide()
  membersHost._amFilterStatus = profFilterStatusFS

  local nameHdr = membersHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameHdr:SetPoint("TOPLEFT", 8, -48)
  nameHdr:SetWidth(150)
  nameHdr:SetJustifyH("LEFT")
  nameHdr:SetText(U.L("COL_NAME"))
  T.SetTextColor(nameHdr, T.ACCENT)

  local profHdr = membersHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  profHdr:SetPoint("TOPLEFT", 162, -48)
  profHdr:SetText(U.L("TAB_PROF"))
  T.SetTextColor(profHdr, T.ACCENT)

  local scroll = CreateFrame("ScrollFrame", "AngryMurlocsProfMemberScroll", membersHost, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -68)
  scroll:SetPoint("BOTTOMRIGHT", -24, 28)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(580, NUM_ROWS * ROW_H)
  scroll:SetScrollChild(scrollChild)

  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(580, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
    row:RegisterForClicks("LeftButtonUp")
    row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", 4, 0)
    row.nameFS:SetWidth(150)
    row.nameFS:SetJustifyH("LEFT")
    if row.nameFS.SetWordWrap then row.nameFS:SetWordWrap(false) end

    row.primary = {}
    for s = 1, 2 do
      local slot = CreateFrame("Button", nil, row)
      slot:SetSize(PROF_SLOT_W, ROW_H)
      slot:SetPoint("LEFT", 158 + (s - 1) * (PROF_SLOT_W + 4), 0)
      slot.icon = slot:CreateTexture(nil, "ARTWORK")
      slot.icon:SetSize(PROF_ICON, PROF_ICON)
      slot.icon:SetPoint("LEFT", 2, 0)
      slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      slot.skillFS = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      slot.skillFS:SetPoint("LEFT", slot.icon, "RIGHT", 3, 0)
      slot.skillFS:SetWidth(64)
      slot.skillFS:SetJustifyH("LEFT")
      WireProfIconButton(slot, row)
      slot:Hide()
      row.primary[s] = slot
    end

    row.secondary = {}
    for s = 1, PROF_SEC_MAX do
      local slot = CreateFrame("Button", nil, row)
      slot:SetSize(PROF_ICON + 4, ROW_H)
      slot:SetPoint("LEFT", 158 + 2 * (PROF_SLOT_W + 4) + 8 + (s - 1) * (PROF_ICON + 6), 0)
      slot.icon = slot:CreateTexture(nil, "ARTWORK")
      slot.icon:SetSize(PROF_ICON, PROF_ICON)
      slot.icon:SetPoint("CENTER")
      slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      WireProfIconButton(slot, row)
      slot:Hide()
      row.secondary[s] = slot
    end

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

  emptyText = membersHost:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER", scroll, "CENTER", 0, 10)
  emptyText:SetText(U.L("PROF_EMPTY"))
  emptyText:Hide()

  emptyResetBtn = CreateFrame("Button", nil, membersHost, "UIPanelButtonTemplate")
  emptyResetBtn:SetSize(140, 20)
  emptyResetBtn:SetPoint("TOP", emptyText, "BOTTOM", 0, -8)
  emptyResetBtn:SetText(U.L("PROF_RESET"))
  emptyResetBtn:Hide()
  emptyResetBtn:SetScript("OnClick", ResetProfFilters)

  profPageText = membersHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  profPageText:SetPoint("BOTTOMLEFT", T.INSET, 8)
  profPageText:SetWidth(400)
  profPageText:SetJustifyH("LEFT")

  profPrevBtn = CreateFrame("Button", nil, membersHost, "UIPanelButtonTemplate")
  profPrevBtn:SetSize(24, 20)
  profPrevBtn:SetPoint("BOTTOMRIGHT", -56, 6)
  profPrevBtn:SetText("<")
  profPrevBtn:SetScript("OnClick", function()
    profPage = math.max(1, profPage - 1)
    UI:RefreshList()
  end)

  profNextBtn = CreateFrame("Button", nil, membersHost, "UIPanelButtonTemplate")
  profNextBtn:SetSize(24, 20)
  profNextBtn:SetPoint("LEFT", profPrevBtn, "RIGHT", 4, 0)
  profNextBtn:SetText(">")
  profNextBtn:SetScript("OnClick", function()
    profPage = profPage + 1
    UI:RefreshList()
  end)

  for i = #profMemberChrome, 1, -1 do profMemberChrome[i] = nil end
  profMemberChrome[#profMemberChrome + 1] = membersHost

  -- ===== Recipe search chrome =====
  -- Row 1: search label + box (categories replace profession dropdown).
  local sLabel = searchHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sLabel:SetPoint("TOPLEFT", T.INSET, -4)
  sLabel:SetText(U.L("PROF_SEARCH_ITEM"))

  searchFilterBox = CreateFrame("EditBox", nil, searchHost, "InputBoxTemplate")
  searchFilterBox:SetSize(340, 20)
  searchFilterBox:SetPoint("LEFT", sLabel, "RIGHT", 6, 0)
  searchFilterBox:SetAutoFocus(false)
  searchFilterBox:SetScript("OnTextChanged", function()
    searchPage = 1
    ResetSearchScroll()
    UI:RefreshSearchList()
  end)

  -- Row 2: Back (when drilled) + coverage/status left, refresh right.
  local sRefresh = CreateFrame("Button", nil, searchHost, "UIPanelButtonTemplate")
  sRefresh:SetSize(180, 20)
  sRefresh:SetPoint("TOPRIGHT", -4, -26)
  sRefresh:SetText(U.L("PROF_RECIPE_DATA_REFRESH"))
  sRefresh:SetScript("OnClick", function()
    UI:RunRecipeDataRefresh()
  end)
  searchHost._amRefreshBtn = sRefresh

  searchBackBtn = CreateFrame("Button", nil, searchHost, "UIPanelButtonTemplate")
  searchBackBtn:SetSize(80, 20)
  searchBackBtn:SetPoint("TOPLEFT", T.INSET, -26)
  searchBackBtn:SetText(U.L("PROF_RECIPE_BACK"))
  searchBackBtn:Hide()
  searchBackBtn:SetScript("OnClick", function()
    searchProfKey = ""
    searchPage = 1
    ResetSearchScroll()
    UI:RefreshSearchList()
  end)

  searchRecipeStatusFS = searchHost:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  searchRecipeStatusFS:SetJustifyH("LEFT")
  searchRecipeStatusFS:SetText("")
  UpdateSearchBackChrome()

  searchNameHdr = searchHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  searchNameHdr:SetPoint("TOPLEFT", 8, -54)
  searchNameHdr:SetWidth(260)
  searchNameHdr:SetJustifyH("LEFT")
  searchNameHdr:SetText(U.L("PROF_COL_RECIPE"))
  T.SetTextColor(searchNameHdr, T.ACCENT)

  searchProfHdr = searchHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  searchProfHdr:SetPoint("TOPLEFT", 280, -54)
  searchProfHdr:SetWidth(140)
  searchProfHdr:SetJustifyH("LEFT")
  searchProfHdr:SetText(U.L("PROF_COL_PROF"))
  T.SetTextColor(searchProfHdr, T.ACCENT)

  searchCraftHdr = searchHost:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  searchCraftHdr:SetPoint("TOPLEFT", 430, -54)
  searchCraftHdr:SetWidth(120)
  searchCraftHdr:SetJustifyH("RIGHT")
  searchCraftHdr:SetText(U.L("PROF_COL_CRAFTERS"))
  T.SetTextColor(searchCraftHdr, T.ACCENT)

  local sScroll = CreateFrame("ScrollFrame", "AngryMurlocsProfSearchScroll", searchHost, "UIPanelScrollFrameTemplate")
  sScroll:SetPoint("TOPLEFT", 4, -74)
  sScroll:SetPoint("BOTTOMRIGHT", -24, 28)
  local sChild = CreateFrame("Frame", nil, sScroll)
  sChild:SetSize(580, SEARCH_NUM_ROWS * SEARCH_ROW_H)
  sScroll:SetScrollChild(sChild)
  searchHost.scroll = sScroll
  searchHost.scrollChild = sChild

  for i = 1, SEARCH_NUM_ROWS do
    local row = CreateFrame("Button", nil, sChild)
    row:SetSize(580, SEARCH_ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * SEARCH_ROW_H))
    row:RegisterForClicks("LeftButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.nameFS:SetWidth(240)
    row.nameFS:SetJustifyH("LEFT")
    row.profFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.profFS:SetPoint("LEFT", 280, 0)
    row.profFS:SetWidth(140)
    row.profFS:SetJustifyH("LEFT")
    row.countFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.countFS:SetPoint("LEFT", 430, 0)
    row.countFS:SetWidth(120)
    row.countFS:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
      T.RowHoverEnter(self)
      if self._amProfBrowseKey then
        local prof = GR:GetModule("Professions")
        local title = (prof and prof.DisplayName and prof.DisplayName(self._amProfBrowseKey)) or self._amProfBrowseKey
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title or "", 1, 1, 1)
        local rc = tonumber(self._amBrowseRecipeCount) or 0
        local cc = tonumber(self._amBrowseCrafterCount) or 0
        local recipeLine = rc == 1 and U.L("PROF_RECIPE_COUNT_ONE") or string.format(U.L("PROF_RECIPE_COUNT"), rc)
        local craftLine = cc == 1 and U.L("PROF_CRAFTER_COUNT_ONE") or string.format(U.L("PROF_CRAFTER_COUNT"), cc)
        GameTooltip:AddLine(recipeLine .. " · " .. craftLine, T.TEXT[1], T.TEXT[2], T.TEXT[3])
        GameTooltip:Show()
        return
      end
      if not self.recipeId then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self._amRecipeName or "", 1, 1, 1)
      if self.crafters then
        for ci = 1, #self.crafters do
          GameTooltip:AddLine(U.ShortName(self.crafters[ci]), T.TEXT[1], T.TEXT[2], T.TEXT[3])
        end
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
      T.RowHoverLeave(self)
      GameTooltip_Hide()
    end)
    row:SetScript("OnClick", function(self)
      if self._amProfBrowseKey then
        searchProfKey = self._amProfBrowseKey
        searchPage = 1
        ResetSearchScroll()
        UI:RefreshSearchList()
        return
      end
      if not self.recipeId or not self.profKey or not self.crafters then return end
      if UI.OpenRecipeDetail then
        UI:OpenRecipeDetail(self.recipeId, self.profKey, self.crafters)
      end
    end)
    searchRows[i] = row
  end

  searchEmptyText = searchHost:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  searchEmptyText:SetPoint("CENTER", sScroll, "CENTER", 0, 0)
  searchEmptyText:SetWidth(420)
  searchEmptyText:Hide()

  searchPageText = searchHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchPageText:SetPoint("BOTTOMLEFT", T.INSET, 8)
  searchPageText:SetWidth(400)
  searchPageText:SetJustifyH("LEFT")

  searchPrevBtn = CreateFrame("Button", nil, searchHost, "UIPanelButtonTemplate")
  searchPrevBtn:SetSize(24, 20)
  searchPrevBtn:SetPoint("BOTTOMRIGHT", -56, 6)
  searchPrevBtn:SetText("<")
  searchPrevBtn:SetScript("OnClick", function()
    searchPage = math.max(1, searchPage - 1)
    UI:RefreshSearchList()
  end)

  searchNextBtn = CreateFrame("Button", nil, searchHost, "UIPanelButtonTemplate")
  searchNextBtn:SetSize(24, 20)
  searchNextBtn:SetPoint("LEFT", searchPrevBtn, "RIGHT", 4, 0)
  searchNextBtn:SetText(">")
  searchNextBtn:SetScript("OnClick", function()
    searchPage = searchPage + 1
    UI:RefreshSearchList()
  end)

  for i = #profSearchChrome, 1, -1 do profSearchChrome[i] = nil end
  profSearchChrome[#profSearchChrome + 1] = searchHost

  MarkProfSubTabs()
end

local function BuildAdminPanel(parent)
  local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  hint:SetPoint("TOPLEFT", 12, -12)
  hint:SetPoint("TOPRIGHT", -12, -12)
  hint:SetJustifyH("LEFT")
  hint:SetJustifyV("TOP")
  hint:SetText(U.L("ADMIN_PLACEHOLDER"))
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
  frame:HookScript("OnHide", function()
    HideProfFilterPopup()
    HideProfMenu()
    HideWhisperMenu()
    local options = GR:GetModule("Options")
    if options and options.DismissOverlays then
      options:DismissOverlays()
    elseif options and options.EndLayoutEdit then
      options:EndLayoutEdit()
    end
  end)

  frame.TitleText:SetText(U.L("WINDOW_TITLE"))

  local function TabBtn(id, labelKey, x, w)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w or 85, 24)
    b:SetPoint("TOPLEFT", x, -26)
    b:SetText(U.L(labelKey))
    b:SetScript("OnClick", function()
      if activeTab == id then return end
      UI:ShowTab(id)
    end)
    tabBtns[id] = b
    return b
  end
  TabBtn("general", "TAB_GENERAL", 12, 128)
  TabBtn("prof", "TAB_PROF", 146, 128)
  TabBtn("wanted", "TAB_WANTED", 280, 118)
  TabBtn("opt", "TAB_OPT", 404, 138)
  local adminBtn = TabBtn("admin", "TAB_ADMIN", 548, 74)
  adminBtn:Hide()

  generalPanel = MakeContentPanel(frame)
  profPanel = MakeContentPanel(frame)
  wantedPanel = MakeContentPanel(frame)
  optPanel = MakeContentPanel(frame)
  adminPanel = MakeContentPanel(frame)

  BuildGeneralPanel(generalPanel)
  BuildProfPanel(profPanel)
  BuildAdminPanel(adminPanel)
  if UI.AttachRecipePanel then
    UI:AttachRecipePanel(profPanel)
  end

  local wanted = GR:GetModule("Wanted")
  if wanted and wanted.AttachPanel then
    wanted:AttachPanel(wantedPanel)
  end

  local options = GR:GetModule("Options")
  if options and options.AttachPanel then
    options:AttachPanel(optPanel)
  end

  ApplyAdminTabButton()
  return frame
end

local function FormatProfs(list)
  if not list or #list == 0 then
    return "-", "-", "-", "", nil, nil, nil
  end
  local prof = GR:GetModule("Professions")
  local displayName = prof and prof.DisplayName
  local primary = {}
  local primaryKeys = {}
  local secondary = {}
  local secondaryKeys = {}
  local tip = {}
  local secKeys = { cook = true, aid = true, fish = true }
  for i = 1, #list do
    local p = list[i]
    local labelName = (displayName and p.key and displayName(p.key)) or p.name or p.key
    local label = string.format(U.L("PROF_SKILL_SEP"), labelName, tonumber(p.skill) or 0)
    tip[#tip + 1] = label
    if secKeys[p.key] then
      secondary[#secondary + 1] = label
      secondaryKeys[#secondaryKeys + 1] = p.key
    else
      primary[#primary + 1] = label
      primaryKeys[#primaryKeys + 1] = p.key
    end
  end
  return primary[1] or "-", primary[2] or "-",
    (#secondary > 0 and table.concat(secondary, ", ") or "-"),
    table.concat(tip, "\n"),
    primaryKeys[1], primaryKeys[2], secondaryKeys[1]
end

function UI:SetProfMemberListVisible(visible)
  -- Back-compat alias
  self:SetProfBaseListsVisible(visible)
end

function UI:SetProfBaseListsVisible(visible)
  if visible then
    UpdateProfFilterStatus()
    self:RefreshProfSubTab()
  else
    HideProfFilterPopup()
    if membersHost then membersHost:Hide() end
    if searchHost then searchHost:Hide() end
    if emptyText then emptyText:Hide() end
    if emptyResetBtn then emptyResetBtn:Hide() end
    if searchEmptyText then searchEmptyText:Hide() end
  end
end

function UI:CaptureProfNav()
  local memberScrollY = 0
  if scrollChild and scrollChild.GetParent then
    local sf = scrollChild:GetParent()
    if sf and sf.GetVerticalScroll then
      memberScrollY = sf:GetVerticalScroll() or 0
    end
  end
  local searchScrollY = 0
  if searchHost and searchHost.scroll and searchHost.scroll.GetVerticalScroll then
    searchScrollY = searchHost.scroll:GetVerticalScroll() or 0
  end
  profNavSnap = {
    subTab = profSubTab,
    filter = filterBox and filterBox:GetText() or "",
    profKey = profKeyFilter,
    minSkill = profMinSkill,
    activeOnly = profActiveOnly,
    sortBy = profSortBy,
    page = profPage,
    memberScrollY = memberScrollY,
    searchFilter = searchFilterBox and searchFilterBox:GetText() or "",
    searchProfKey = searchProfKey,
    searchPage = searchPage,
    searchScrollY = searchScrollY,
  }
end

function UI:RestoreProfNav()
  local snap = profNavSnap
  if not snap then
    self:RefreshProfSubTab()
    return
  end
  profSubTab = snap.subTab or "members"
  profKeyFilter = snap.profKey or ""
  profMinSkill = snap.minSkill
  profActiveOnly = snap.activeOnly and true or false
  profSortBy = snap.sortBy or "online"
  profPage = snap.page or 1
  searchProfKey = snap.searchProfKey or ""
  searchPage = snap.searchPage or 1
  if filterBox then filterBox:SetText(snap.filter or "") end
  if profMinBox then
    if snap.minSkill then
      profMinBox:SetText(tostring(snap.minSkill))
    else
      profMinBox:SetText("")
    end
  end
  if profActiveCb then profActiveCb:SetChecked(profActiveOnly) end
  if profKeyBtn then profKeyBtn:SetText(ProfKeyLabel()) end
  if searchFilterBox then searchFilterBox:SetText(snap.searchFilter or "") end
  UpdateProfFilterStatus()
  self:RefreshProfSubTab()
  C_Timer.After(0, function()
    if snap.subTab == "search" then
      if searchHost and searchHost.scroll and searchHost.scroll.SetVerticalScroll then
        searchHost.scroll:SetVerticalScroll(snap.searchScrollY or 0)
      end
    else
      if scrollChild and scrollChild.GetParent then
        local sf = scrollChild:GetParent()
        if sf and sf.SetVerticalScroll then
          sf:SetVerticalScroll(snap.memberScrollY or 0)
        end
      end
    end
  end)
end

function UI:ShowProfSubTab(id)
  if id ~= "search" then id = "members" end
  if self.IsRecipeCatalogOpen and self:IsRecipeCatalogOpen() then
    self:CloseRecipeCatalog(false)
  end
  profSubTab = id
  HideProfFilterPopup()
  HideProfMenu()
  HideWhisperMenu()
  MarkProfSubTabs()
  self:RefreshProfSubTab()
end

function UI:RefreshProfSubTab()
  MarkProfSubTabs()
  if (profSubTab or "members") == "search" then
    if membersHost then membersHost:Hide() end
    if searchHost then searchHost:Show() end
    self:RefreshSearchList()
  else
    if searchHost then searchHost:Hide() end
    if membersHost then membersHost:Show() end
    self:RefreshList()
  end
end

function UI:SetSearchFilterText(text)
  if not searchFilterBox then return end
  searchFilterBox:SetText(text or "")
  searchPage = 1
  if ResetSearchScroll then ResetSearchScroll() end
  self:RefreshSearchList()
end

function UI:RefreshSearchList()
  if not frame or not self:IsTabShown("prof") then return end
  if self.IsRecipeCatalogOpen and self:IsRecipeCatalogOpen() then return end
  if (profSubTab or "members") ~= "search" then return end
  local R = GR:GetModule("ProfRecipes")
  local prof = GR:GetModule("Professions")

  -- Gathering is not recipe-capable; clear stale filter if somehow set.
  if searchProfKey ~= "" and R and R.IsGathering and R.IsGathering(searchProfKey) then
    searchProfKey = ""
  end

  UpdateSearchBackChrome()

  local index = (R and R.BuildGuildRecipeIndex and R.BuildGuildRecipeIndex()) or {}
  local q = TrimSearchQuery(searchFilterBox and searchFilterBox:GetText() or "")
  local browseCats = (q == "" and searchProfKey == "")

  if searchNameHdr and searchProfHdr and searchCraftHdr then
    if browseCats then
      searchNameHdr:SetText(U.L("PROF_COL_PROF"))
      searchProfHdr:SetText(U.L("PROF_COL_RECIPES"))
      searchCraftHdr:SetText(U.L("PROF_COL_CRAFTERS"))
    else
      searchNameHdr:SetText(U.L("PROF_COL_RECIPE"))
      searchProfHdr:SetText(U.L("PROF_COL_PROF"))
      searchCraftHdr:SetText(U.L("PROF_COL_CRAFTERS"))
    end
  end

  local filtered = {}
  if browseCats then
    filtered = BuildSearchProfessionCategories(index, prof)
  else
    for i = 1, #index do
      local row = index[i]
      if searchProfKey == "" or row.profKey == searchProfKey then
        local meta = R.GetMeta and R.GetMeta(row.recipeId)
        local name = (meta and meta.name) or string.format(U.L("PROF_RECIPE_ID"), row.recipeId)
        local outputName = nil
        if meta and meta.outputItemID and R.ResolveItemName then
          outputName = select(1, R.ResolveItemName(meta.outputItemID, nil))
        end
        local ok, rank = true, 1
        if R.MatchRecipeQuery then
          ok, rank = R.MatchRecipeQuery(q, {
            recipeId = row.recipeId,
            name = name,
            outputItemID = meta and meta.outputItemID,
            outputName = outputName,
          })
        end
        if ok then
          filtered[#filtered + 1] = {
            recipeId = row.recipeId,
            profKey = row.profKey,
            crafters = row.crafters,
            name = name,
            rank = rank or 1,
            icon = (meta and meta.icon) or (R.ResolveRecipeIcon and R.ResolveRecipeIcon(row.recipeId, meta)) or "Interface\\Icons\\INV_Misc_QuestionMark",
          }
        end
      end
    end
    table.sort(filtered, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      local na = string.lower(a.name or "")
      local nb = string.lower(b.name or "")
      if na ~= nb then return na < nb end
      return (a.recipeId or 0) < (b.recipeId or 0)
    end)
  end

  local total = #filtered
  local pages = math.max(1, math.ceil(total / SEARCH_NUM_ROWS))
  if searchPage > pages then searchPage = pages end
  if searchPage < 1 then searchPage = 1 end
  local first = (searchPage - 1) * SEARCH_NUM_ROWS + 1
  local last = math.min(total, searchPage * SEARCH_NUM_ROWS)

  if searchRecipeStatusFS and R and R.CountCoverage and (not R.IsRecipeRefreshBusy or not R:IsRecipeRefreshBusy()) then
    local nChars, nCats = R.CountCoverage()
    if nChars > 0 or nCats > 0 then
      local st = R.GetRecipeRefreshStatus and select(1, R:GetRecipeRefreshStatus())
      if st == "idle" or not st then
        searchRecipeStatusFS:SetText(string.format(U.L("PROF_SEARCH_COVERAGE"), nChars, nCats))
      end
    end
  end

  if searchPageText then
    if total == 0 then
      searchPageText:SetText("")
    else
      searchPageText:SetText(string.format(U.L("PROF_PAGE_RANGE"), first, last, total, searchPage, pages))
    end
  end
  if searchPrevBtn then
    if searchPage <= 1 then searchPrevBtn:Disable() else searchPrevBtn:Enable() end
  end
  if searchNextBtn then
    if searchPage >= pages then searchNextBtn:Disable() else searchNextBtn:Enable() end
  end

  if searchHost and searchHost.scrollChild then
    searchHost.scrollChild:SetHeight(math.max(last - first + 1, 1) * SEARCH_ROW_H)
  end

  if total == 0 then
    searchEmptyText:Show()
    if #index == 0 then
      searchEmptyText:SetText(U.L("PROF_SEARCH_EMPTY"))
    else
      searchEmptyText:SetText(U.L("PROF_SEARCH_NO_MATCH"))
    end
  else
    searchEmptyText:Hide()
  end

  for i = 1, SEARCH_NUM_ROWS do
    local row = searchRows[i]
    ClearSearchRow(row)
    local data = filtered[first + i - 1]
    if data and (first + i - 1) <= last then
      if browseCats then
        row._amProfBrowseKey = data.profKey
        row._amBrowseRecipeCount = data.recipeCount
        row._amBrowseCrafterCount = #(data.crafters or {})
        row.nameFS:SetText((prof and prof.DisplayName and prof.DisplayName(data.profKey)) or data.profKey)
        local rc = data.recipeCount or 0
        if rc == 1 then
          row.profFS:SetText(U.L("PROF_RECIPE_COUNT_ONE"))
        else
          row.profFS:SetText(string.format(U.L("PROF_RECIPE_COUNT"), rc))
        end
        local n = #(data.crafters or {})
        if n <= 1 then
          row.countFS:SetText(U.L("PROF_CRAFTER_COUNT_ONE"))
        else
          row.countFS:SetText(string.format(U.L("PROF_CRAFTER_COUNT"), n))
        end
        row.icon:SetTexture((prof and prof.IconPath and prof.IconPath(data.profKey)) or "Interface\\Icons\\INV_Misc_QuestionMark")
      else
        row.recipeId = data.recipeId
        row.profKey = data.profKey
        row.crafters = data.crafters
        row._amRecipeName = data.name
        row.nameFS:SetText(data.name)
        row.profFS:SetText((prof and prof.DisplayName and prof.DisplayName(data.profKey)) or data.profKey)
        local n = #(data.crafters or {})
        if n <= 1 then
          row.countFS:SetText(U.L("PROF_CRAFTER_COUNT_ONE"))
        else
          row.countFS:SetText(string.format(U.L("PROF_CRAFTER_COUNT"), n))
        end
        row.icon:SetTexture(data.icon)
      end
      T.ApplyRowChrome(row, i, false)
      row:Show()
    else
      row:Hide()
    end
  end
end

function UI:GetFrame()
  return EnsureFrame()
end

function UI:IsTabShown(id)
  return frame and frame:IsShown() and activeTab == id
end

function UI:GetActiveTab()
  return activeTab
end

function UI:RefreshAdminTabVisibility()
  if not frame then return end
  ApplyAdminTabButton()
  if activeTab == "admin" and not CanShowAdminTab() then
    self:ShowTab("general")
  else
    UpdateTabButtons()
  end
end

function UI:ShowTab(id)
  EnsureFrame()
  if id == "admin" and not CanShowAdminTab() then
    id = "general"
  elseif id ~= "general" and id ~= "prof" and id ~= "wanted" and id ~= "opt" and id ~= "admin" then
    id = "general"
  end
  if id ~= "prof" and self.IsRecipeCatalogOpen and self:IsRecipeCatalogOpen() then
    self:CloseRecipeCatalog()
  end
  activeTab = id
  HideProfFilterPopup()
  HideProfMenu()
  HideWhisperMenu()
  if id ~= "opt" then
    local options = GR:GetModule("Options")
    if options and options.DismissOverlays then
      options:DismissOverlays()
    elseif options and options.EndLayoutEdit then
      options:EndLayoutEdit()
    end
  end

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
  if adminPanel then
    if id == "admin" then adminPanel:Show() else adminPanel:Hide() end
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
    if self.IsRecipeCatalogOpen and self:IsRecipeCatalogOpen() then
      self:RefreshRecipeCatalog()
    else
      self:RefreshProfSubTab()
    end
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

-- Class for name coloring: cached on entry, else Positions (exact / fuzzy), then persist.
local function ResolveProfClass(name, entry)
  if entry and entry.classFile then
    return entry.classFile
  end
  local pos = GR:GetModule("Positions")
  if not pos then return nil end
  local p = pos.Get and pos:Get(name)
  if p and p.classFile then
    if entry then entry.classFile = p.classFile end
    return p.classFile
  end
  local pc = pos.GetCache and pos:GetCache()
  if type(pc) == "table" then
    local short = string.lower(U.ShortName(name) or "")
    for pname, pdata in pairs(pc) do
      if pdata and pdata.classFile then
        if U.SameCharacter(pname, name)
            or string.lower(U.ShortName(pname) or "") == short then
          if entry then entry.classFile = pdata.classFile end
          return pdata.classFile
        end
      end
    end
  end
  return nil
end

function UI:RefreshList()
  if not frame or not self:IsTabShown("prof") then return end
  if self.IsRecipeCatalogOpen and self:IsRecipeCatalogOpen() then
    return
  end
  if (profSubTab or "members") ~= "members" then return end
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
    if profSortBtn then
      profSortBtn:SetText(profSortBy == "online" and U.L("PROF_SORT_ONLINE") or U.L("PROF_SORT_NAME"))
    end
    UpdateProfFilterStatus()
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

  if scrollChild then
    scrollChild:SetHeight(math.max(last - first + 1, 1) * ROW_H)
  end

  for i = 1, NUM_ROWS do
    local name = names[first + i - 1]
    if name and (first + i - 1) <= last then
      local entry = cache[name]
      local _, _, _, tip = FormatProfs(entry.list)
      local primary, secondary = SplitPrimarySecondary(entry.list)
      local online = IsProfOnline(name, me)
      local short = U.ShortName(name)
      if name == me or U.IsSelfName(name) then
        short = U.ShortName(me) .. " (" .. U.L("YOU") .. ")"
      end
      local mark = online and "*" or "·"
      short = mark .. " " .. short
      local classFile = ResolveProfClass(name, entry)
      local r, g, b = U.ClassColor(classFile)
      rows[i].fullName = name
      rows[i].online = online
      rows[i].tipProfs = tip
      T.ApplyRowChrome(rows[i], i, false)
      if rows[i].nameFS then
        local sn = short
        if #sn > 22 then sn = sn:sub(1, 21) .. "..." end
        rows[i].nameFS:SetText(sn)
        rows[i].nameFS:SetTextColor(r, g, b)
      end
      for s = 1, 2 do
        local slot = rows[i].primary and rows[i].primary[s]
        local p = primary[s]
        if slot then
          if p and p.key then
            slot.profKey = p.key
            slot.skill = tonumber(p.skill) or 0
            slot.icon:SetTexture((prof and prof.IconPath and prof.IconPath(p.key)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            slot.skillFS:SetText(tostring(slot.skill))
            slot:Show()
          else
            slot.profKey = nil
            slot.skill = nil
            slot:Hide()
          end
        end
      end
      for s = 1, PROF_SEC_MAX do
        local slot = rows[i].secondary and rows[i].secondary[s]
        local p = secondary[s]
        if slot then
          if p and p.key then
            slot.profKey = p.key
            slot.skill = tonumber(p.skill) or 0
            slot.icon:SetTexture((prof and prof.IconPath and prof.IconPath(p.key)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            slot:Show()
          else
            slot.profKey = nil
            slot.skill = nil
            slot:Hide()
          end
        end
      end
      rows[i]:Show()
    else
      rows[i].fullName = nil
      rows[i].online = nil
      rows[i].tipProfs = nil
      if rows[i].primary then
        for s = 1, 2 do
          if rows[i].primary[s] then
            rows[i].primary[s].profKey = nil
            rows[i].primary[s]:Hide()
          end
        end
      end
      if rows[i].secondary then
        for s = 1, PROF_SEC_MAX do
          if rows[i].secondary[s] then
            rows[i].secondary[s].profKey = nil
            rows[i].secondary[s]:Hide()
          end
        end
      end
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

  local function RefreshAdminAccess()
    UI:RefreshAdminTabVisibility()
  end
  GR:BindMessage(self, "GUILD_UPDATE", RefreshAdminAccess)

  if not adminEvents then
    adminEvents = CreateFrame("Frame")
    adminEvents:SetScript("OnEvent", RefreshAdminAccess)
  end
  U.SafeRegisterEvent(adminEvents, "GUILD_ROSTER_UPDATE")
  U.SafeRegisterEvent(adminEvents, "GUILD_RANKS_UPDATE")
  U.SafeRegisterEvent(adminEvents, "GUILD_RANKS_UPDATE_ACTIVE_PLAYER")
  RefreshAdminAccess()

  -- Stacked with ProfRecipePanel handlers (BindMessage appends). Catalog-closed
  -- panel early-return must not prevent search/members refresh.
  GR:BindMessage(self, "PROF_CACHE_CHANGED", function()
    ScheduleProfViewRefresh()
  end)
  GR:BindMessage(self, "PROF_RECIPES_CHANGED", function()
    ScheduleProfViewRefresh()
  end)
  GR:BindMessage(self, "PROF_RECIPE_META_CHANGED", function()
    ScheduleProfViewRefresh()
  end)
  GR:BindMessage(self, "PROF_RECIPE_REFRESH_STATUS", function(_, status)
    UI:UpdateRecipeDataRefreshStatus(status)
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
  if adminEvents then
    adminEvents:UnregisterAllEvents()
  end
end
