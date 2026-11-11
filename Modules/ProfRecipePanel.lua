-- Recipe list + shared detail on the Professions tab (attaches to UI module).
-- Members path: icon → member recipe list → detail.
-- Search path: recipe row → detail (same detail pane).
local GR = AngryMurlocs
local U = GR.Util
local T = GR.Theme

local UI = GR:GetModule("UI")
assert(UI, "ProfRecipePanel requires UI module")

local catalog
local listRows = {}
local matRows = {}
local NUM_LIST_ROWS = 14
local LIST_ROW_H = 24
local NUM_MAT_ROWS = 12
local MAT_ROW_H = 20
local fetchGen = 0

local state = {
  open = false,
  view = "list", -- list | detail
  source = "members", -- members | search
  player = nil,
  profKey = nil,
  selectedId = nil,
  filter = "",
  desired = 1,
  matsBring = true,
  page = 1,
  crafters = nil, -- { names } when multi-crafter
  fetchPending = nil,
  quietFetch = false,
  listScrollY = 0,
  comboValid = true,
  draftFingerprint = nil,
  draftStale = false,
  draftText = nil,
  pendingMatIds = nil,
  bagRefreshPending = false,
}

local function Recipes()
  return GR:GetModule("ProfRecipes")
end

local function Professions()
  return GR:GetModule("Professions")
end

local function Comm()
  return GR.Comm
end

local function IsSelf(name)
  return U.IsSelfName(name)
end

local function IsOnline(name)
  if IsSelf(name) then return true end
  local age = Comm() and Comm().PeerAge and Comm():PeerAge(name)
  return age ~= nil and age <= 600
end

local function DisplayProf(key)
  local p = Professions()
  return (p and p.DisplayName and p.DisplayName(key)) or key
end

local function HidePreview()
  if catalog and catalog.preview then
    catalog.preview:Hide()
  end
end

local function SetBaseListsVisible(visible)
  if UI.SetProfBaseListsVisible then
    UI:SetProfBaseListsVisible(visible)
  elseif UI.SetProfMemberListVisible then
    UI:SetProfMemberListVisible(visible)
  end
end

local function RecipeName(id)
  local R = Recipes()
  local meta = R and R.GetMeta and R.GetMeta(id)
  if meta and meta.name and meta.name ~= "" then
    return meta.name
  end
  return string.format(U.L("PROF_RECIPE_ID"), tonumber(id) or 0)
end

local function RecipeIcon(id)
  local R = Recipes()
  local meta = R and R.GetMeta and R.GetMeta(id)
  if meta and meta.icon and meta.icon ~= 0 and meta.icon ~= ""
      and meta.icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
    return meta.icon
  end
  if R and R.ResolveRecipeIcon then
    local icon, outputItemID = R.ResolveRecipeIcon(id, meta, {
      outputItemID = meta and meta.outputItemID,
      icon = meta and meta.icon,
      name = meta and meta.name,
    })
    if icon and icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
      if R.StoreMeta then
        R.StoreMeta(id, {
          icon = icon,
          outputItemID = outputItemID or (meta and meta.outputItemID),
          name = meta and meta.name,
        })
      end
      return icon
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ChatTarget(name)
  if not name then return nil end
  return U.NormalizeName(name) or name
end

local function DraftFingerprint()
  local R = Recipes()
  if R and R.RequestDraftFingerprint then
    return R.RequestDraftFingerprint({
      recipeId = state.selectedId,
      player = state.player,
      profKey = state.profKey,
      desired = state.desired,
      matsBring = state.matsBring,
    })
  end
  return ""
end

local function PlayerKnowsRecipe(player, profKey, recipeId)
  local R = Recipes()
  if R and R.PlayerKnowsRecipe then
    return R.PlayerKnowsRecipe(player, profKey, recipeId)
  end
  return false
end

local function ValidateCrafterCombo()
  state.comboValid = true
  if not state.selectedId or not state.player or not state.profKey then
    return
  end
  if state.crafters and #state.crafters > 0 then
    local valid = {}
    local seen = {}
    for i = 1, #state.crafters do
      local name = state.crafters[i]
      local key = U.NormalizeName(name)
      if name and not seen[key] and PlayerKnowsRecipe(name, state.profKey, state.selectedId) then
        seen[key] = true
        valid[#valid + 1] = name
      end
    end
    state.crafters = valid
  end
  if not PlayerKnowsRecipe(state.player, state.profKey, state.selectedId) then
    state.comboValid = false
  end
end

local function UpdatePreviewChrome()
  if not catalog or not catalog.preview then return end
  if catalog.previewStaleFS then
    if state.draftStale then
      catalog.previewStaleFS:SetText(U.L("PROF_RECIPE_STALE_DRAFT"))
      catalog.previewStaleFS:Show()
    else
      catalog.previewStaleFS:SetText("")
      catalog.previewStaleFS:Hide()
    end
  end
  if catalog.previewApplyBtn then
    if state.draftStale then
      catalog.previewApplyBtn:Disable()
    else
      catalog.previewApplyBtn:Enable()
    end
  end
  if catalog.previewRebuildBtn then
    if state.draftStale then
      catalog.previewRebuildBtn:Show()
      catalog.previewRebuildBtn:Enable()
    else
      catalog.previewRebuildBtn:Hide()
    end
  end
  if catalog.previewMetaFS then
    local target = ChatTarget(state.player) or "?"
    catalog.previewMetaFS:SetText(string.format("%s · x%d", target, state.desired or 1))
  end
end

local function MarkDraftStaleIfNeeded()
  if not catalog or not catalog.preview or not catalog.preview:IsShown() then return end
  if not state.draftFingerprint then return end
  if DraftFingerprint() ~= state.draftFingerprint then
    state.draftStale = true
    if catalog.previewEdit then
      state.draftText = catalog.previewEdit:GetText()
    end
    UpdatePreviewChrome()
  end
end

local function FilteredIds()
  local R = Recipes()
  local rec = R and R.GetEntry and R.GetEntry(state.player, state.profKey)
  local ids = (rec and rec.ids) or {}
  local q = state.filter or ""
  local ranked = {}
  for i = 1, #ids do
    local id = ids[i]
    local meta = R and R.GetMeta and R.GetMeta(id)
    local name = (meta and meta.name) or RecipeName(id)
    local outputName = nil
    if meta and meta.outputItemID and R.ResolveItemName then
      outputName = select(1, R.ResolveItemName(meta.outputItemID, nil))
    end
    local ok, rank = true, 1
    if R and R.MatchRecipeQuery then
      ok, rank = R.MatchRecipeQuery(q, {
        recipeId = id,
        name = name,
        outputItemID = meta and meta.outputItemID,
        outputName = outputName,
      })
    elseif q ~= "" then
      local ql = string.lower(q)
      ok = string.find(string.lower(name), ql, 1, true) ~= nil
          or string.find(tostring(id), ql, 1, true) ~= nil
    end
    if ok then
      ranked[#ranked + 1] = { id = id, rank = rank or 1, name = name }
    end
  end
  table.sort(ranked, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    local na = string.lower(a.name or "")
    local nb = string.lower(b.name or "")
    if na ~= nb then return na < nb end
    return (a.id or 0) < (b.id or 0)
  end)
  local out = {}
  for i = 1, #ranked do out[i] = ranked[i].id end
  return out, rec
end

local function FormatDataAge(rec)
  if not rec then return U.L("PROF_RECIPE_STATUS_NONE") end
  local scanAt = tonumber(rec.scanAt)
  local recvAt = tonumber(rec.recvAt)
  local parts = {}
  if rec.partialSeenAt then
    parts[#parts + 1] = U.L("PROF_RECIPE_STATUS_PARTIAL")
  elseif rec.complete then
    parts[#parts + 1] = U.L("PROF_RECIPE_STATUS_COMPLETE")
  else
    parts[#parts + 1] = U.L("PROF_RECIPE_STATUS_PARTIAL")
  end
  local R = Recipes()
  local fmt = R and R.FormatScanStamp
  if scanAt and scanAt > 0 then
    local stamp = fmt and fmt(scanAt) or tostring(scanAt)
    parts[#parts + 1] = string.format(U.L("PROF_RECIPE_SCAN_DATE"), stamp)
  end
  if recvAt and recvAt > 0 and (not scanAt or recvAt ~= scanAt) then
    local stamp = fmt and fmt(recvAt) or tostring(recvAt)
    parts[#parts + 1] = string.format(U.L("PROF_RECIPE_RECV_AT"), stamp)
  end
  return table.concat(parts, " · ")
end

local function CaptureListScroll()
  if catalog and catalog.listScroll and catalog.listScroll.GetVerticalScroll then
    state.listScrollY = catalog.listScroll:GetVerticalScroll() or 0
  end
end

local function RestoreListScroll()
  if not catalog or not catalog.listScroll or not catalog.listScroll.SetVerticalScroll then return end
  local y = state.listScrollY or 0
  C_Timer.After(0, function()
    if not catalog or not catalog.listScroll then return end
    local maxY = 0
    if catalog.listScroll.GetVerticalScrollRange then
      maxY = catalog.listScroll:GetVerticalScrollRange() or 0
    end
    if y > maxY then y = maxY end
    if y < 0 then y = 0 end
    catalog.listScroll:SetVerticalScroll(y)
  end)
end

local function ShowListView()
  state.view = "list"
  if catalog.listPane then catalog.listPane:Show() end
  if catalog.detailPane then catalog.detailPane:Hide() end
end

local function ShowDetailView()
  state.view = "detail"
  if catalog.listPane then catalog.listPane:Hide() end
  if catalog.detailPane then catalog.detailPane:Show() end
end

local function CrafterLabel(name)
  local full = ChatTarget(name) or name or "?"
  local entry = Professions() and Professions():GetAll() and Professions():GetAll()[U.NormalizeName(name)]
  local r, g, b = U.ClassColor(entry and entry.classFile)
  return full, r, g, b
end

local function UpdateCrafterButton()
  if not catalog or not catalog.crafterBtn then return end
  local n = state.crafters and #state.crafters or 0
  local label, r, g, b = CrafterLabel(state.player)
  if n > 1 then
    catalog.crafterBtn:Show()
    catalog.crafterBtn:SetText(U.ShortName(state.player or "?"))
    if catalog.crafterBtn.SetTooltip then
      -- no-op for stubs
    end
    catalog.crafterBtn:SetScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        GameTooltip:Show()
      end
    end)
    catalog.crafterBtn:SetScript("OnLeave", function()
      if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    catalog.crafterLine:Hide()
  else
    catalog.crafterBtn:Hide()
    if catalog.crafterLine then
      catalog.crafterLine:Show()
      catalog.crafterLine:SetText(string.format(U.L("PROF_RECIPE_CRAFTER"), label))
      if r then catalog.crafterLine:SetTextColor(r, g, b) end
    end
  end
end

local function EnsureCrafterMenu()
  if catalog.crafterMenu then return catalog.crafterMenu end
  local menu = CreateFrame("Frame", "AngryMurlocsCrafterMenu", catalog)
  menu:SetFrameStrata("DIALOG")
  menu:SetSize(160, 40)
  T.ApplyPanelBackdrop(menu, T.BG)
  menu:Hide()
  menu:EnableMouse(true)
  catalog.crafterMenu = menu
  menu.buttons = {}
  return menu
end

local function HideCrafterMenu()
  if catalog and catalog.crafterMenu then catalog.crafterMenu:Hide() end
end

local function RebuildCrafterMenu()
  local menu = EnsureCrafterMenu()
  for i = 1, #menu.buttons do
    menu.buttons[i]:Hide()
  end
  local list = state.crafters or { state.player }
  local y = -4
  for i = 1, #list do
    local name = list[i]
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
      b:SetSize(148, 18)
      menu.buttons[i] = b
    end
    b:SetPoint("TOPLEFT", 6, y)
    b:SetText(U.ShortName(name))
    b:SetScript("OnClick", function()
      state.player = name
      HideCrafterMenu()
      UpdateCrafterButton()
      MarkDraftStaleIfNeeded()
      UI:RefreshRecipeCatalog()
    end)
    b:Show()
    y = y - 20
  end
  menu:SetHeight(math.abs(y) + 8)
end

local RefreshDetail
local RefreshList
local RefreshHeader

RefreshDetail = function()
  if not catalog or not catalog.detailPane then return end
  local id = state.selectedId
  local R = Recipes()
  local meta = id and R and R.GetMeta and R.GetMeta(id) or nil
  ValidateCrafterCombo()

  if not id then
    catalog.detailName:SetText(U.L("PROF_RECIPE_PICK"))
    catalog.detailProf:SetText("")
    catalog.detailYield:SetText("")
    catalog.matSummary:SetText("")
    catalog.whisperBtn:Disable()
    catalog.requestBtn:Disable()
    for i = 1, NUM_MAT_ROWS do
      if matRows[i] then matRows[i]:Hide() end
    end
    return
  end

  catalog.detailName:SetText(RecipeName(id))
  catalog.detailProf:SetText(DisplayProf(state.profKey))

  local calc = R.ComputeCrafts(state.desired, meta and meta.qtyMin, meta and meta.qtyMax)
  if meta and meta.isEnchant then
    catalog.detailYield:SetText(string.format(U.L("PROF_RECIPE_ENCHANT_YIELDS"), calc.crafts))
  elseif calc.mode == "fixed" then
    catalog.detailYield:SetText(string.format(
      U.L("PROF_RECIPE_YIELD_FIXED"),
      calc.crafts, calc.qtyPer, calc.yieldMin
    ))
  elseif calc.mode == "range" then
    catalog.detailYield:SetText(string.format(
      U.L("PROF_RECIPE_YIELD_RANGE"),
      calc.crafts, calc.yieldMin or 0, calc.yieldMax or 0
    ))
  else
    catalog.detailYield:SetText(string.format(U.L("PROF_RECIPE_YIELD_CRAFTS"), calc.crafts))
  end

  local function EnsureMatRow(i)
    local row = matRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, catalog.matChild)
    row:SetSize(560, MAT_ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * MAT_ROW_H))
    row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", 4, 0)
    row.nameFS:SetWidth(280)
    row.nameFS:SetJustifyH("LEFT")
    row.needFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.needFS:SetPoint("LEFT", 300, 0)
    row.needFS:SetWidth(70)
    row.needFS:SetJustifyH("RIGHT")
    row.bagFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bagFS:SetPoint("LEFT", 380, 0)
    row.bagFS:SetWidth(70)
    row.bagFS:SetJustifyH("RIGHT")
    row.missFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.missFS:SetPoint("LEFT", 460, 0)
    row.missFS:SetWidth(70)
    row.missFS:SetJustifyH("RIGHT")
    matRows[i] = row
    return row
  end

  for i = 1, #matRows do
    matRows[i]:Hide()
  end

  state.pendingMatIds = {}
  local function MatLabel(data)
    if data and data.name and data.name ~= "" then return data.name end
    return string.format(U.L("PROF_RECIPE_ITEM_ID"), (data and data.itemID) or 0)
  end

  local reagents = meta and meta.reagents
  if type(reagents) == "table" and #reagents > 0 then
    local rows, missingTotal, firstName, firstQty, allKnown, anyUnknown =
      R.ComputeMaterialRows(reagents, calc.crafts)
    catalog.matChild:SetHeight(math.max(#rows, 1) * MAT_ROW_H + 4)
    local firstMissingLabel
    local unk = U.L("PROF_MAT_UNKNOWN")
    for i = 1, #rows do
      local row = EnsureMatRow(i)
      local data = rows[i]
      local label = MatLabel(data)
      if data.name and data.itemID and R.CacheReagentName then
        R.CacheReagentName(id, data.itemID, data.name)
      elseif data.itemID and not data.name then
        state.pendingMatIds[data.itemID] = true
      end
      row.nameFS:SetText(label)
      row.needFS:SetText(data.need ~= nil and tostring(data.need) or unk)
      row.bagFS:SetText(data.bag ~= nil and tostring(data.bag) or unk)
      row.missFS:SetText(data.missing ~= nil and tostring(data.missing) or unk)
      if data.unknown or data.missing == nil then
        row.missFS:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
      elseif data.missing > 0 then
        row.missFS:SetTextColor(T.OFF[1], T.OFF[2], T.OFF[3])
        if not firstMissingLabel then
          firstMissingLabel = label
          if not firstQty then firstQty = data.missing end
        end
      else
        row.missFS:SetTextColor(T.ON[1], T.ON[2], T.ON[3])
      end
      row:Show()
    end
    local summaryName = firstName or firstMissingLabel
    if anyUnknown or not allKnown then
      catalog.matSummary:SetText(U.L("PROF_MAT_SUMMARY_UNKNOWN"))
      catalog.matSummary:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
    elseif missingTotal <= 0 then
      catalog.matSummary:SetText(U.L("PROF_MAT_OK"))
      catalog.matSummary:SetTextColor(T.ON[1], T.ON[2], T.ON[3])
    elseif summaryName and firstQty and missingTotal == firstQty then
      catalog.matSummary:SetText(string.format(U.L("PROF_MAT_SUMMARY_ONE"), firstQty, summaryName))
      catalog.matSummary:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3])
    else
      local nMissingKinds = 0
      for i = 1, #rows do
        if rows[i].missing and rows[i].missing > 0 then nMissingKinds = nMissingKinds + 1 end
      end
      catalog.matSummary:SetText(string.format(
        U.L("PROF_MAT_SUMMARY_MORE"),
        nMissingKinds,
        firstQty or 0,
        summaryName or "?"
      ))
      catalog.matSummary:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3])
    end
  else
    catalog.matChild:SetHeight(40)
    catalog.matSummary:SetText(U.L("PROF_RECIPE_MATS_UNKNOWN"))
    catalog.matSummary:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
  end

  UpdateCrafterButton()
  if catalog.crafterStatusFS then
    local rec = R and R.GetEntry and R.GetEntry(state.player, state.profKey)
    catalog.crafterStatusFS:SetText(FormatDataAge(rec))
  end

  local selfChar = IsSelf(state.player)
  if not state.comboValid then
    catalog.whisperBtn:Disable()
    catalog.requestBtn:Disable()
    catalog.offlineHint:SetText(U.L("PROF_RECIPE_INVALID_COMBO"))
    catalog.offlineHint:Show()
  elseif selfChar then
    catalog.whisperBtn:Disable()
    catalog.requestBtn:Disable()
    catalog.offlineHint:SetText(U.L("PROF_RECIPE_SELF_HINT"))
    catalog.offlineHint:Show()
  else
    catalog.whisperBtn:Enable()
    catalog.requestBtn:Enable()
    if not IsOnline(state.player) then
      catalog.offlineHint:SetText(U.L("PROF_RECIPE_OFFLINE_HINT"))
      catalog.offlineHint:Show()
    else
      catalog.offlineHint:Hide()
    end
  end
  MarkDraftStaleIfNeeded()
end

RefreshList = function()
  if not catalog or not state.open or state.view ~= "list" then return end
  local ids = FilteredIds()
  local total = #ids
  local pages = math.max(1, math.ceil(total / NUM_LIST_ROWS))
  if state.page > pages then state.page = pages end
  if state.page < 1 then state.page = 1 end
  local first = (state.page - 1) * NUM_LIST_ROWS + 1
  local last = math.min(total, state.page * NUM_LIST_ROWS)

  catalog.pageText:SetText(total > 0
    and string.format(U.L("PROF_PAGE_RANGE"), first, last, total, state.page, pages)
    or "")
  if state.page <= 1 then catalog.prevBtn:Disable() else catalog.prevBtn:Enable() end
  if state.page >= pages then catalog.nextBtn:Disable() else catalog.nextBtn:Enable() end

  catalog.listChild:SetHeight(math.max(last - first + 1, 1) * LIST_ROW_H)

  for i = 1, NUM_LIST_ROWS do
    local row = listRows[i]
    local id = ids[first + i - 1]
    if id and (first + i - 1) <= last then
      row.recipeId = id
      row.nameFS:SetText(RecipeName(id))
      local tex = RecipeIcon(id)
      row.icon:SetTexture(tex)
      local selected = state.selectedId == id
      T.ApplyRowChrome(row, i, selected)
      row:Show()
    else
      row.recipeId = nil
      row:Hide()
    end
  end
  RestoreListScroll()
end

RefreshHeader = function()
  if not catalog then return end
  local R = Recipes()
  local name = state.player or "?"
  local short = U.ShortName(name)
  if IsSelf(name) then
    short = short .. " (" .. U.L("YOU") .. ")"
  end
  local entry = Professions() and Professions():GetAll()[U.NormalizeName(name)]
  local r, g, b = U.ClassColor(entry and entry.classFile)
  catalog.headerName:SetText(short)
  catalog.headerName:SetTextColor(r, g, b)

  local skill = R and R.GetSkill and select(1, R.GetSkill(name, state.profKey))
  local profLabel = DisplayProf(state.profKey)
  if skill then
    catalog.headerProf:SetText(string.format(U.L("PROF_SKILL_SEP"), profLabel, skill))
  else
    catalog.headerProf:SetText(profLabel)
  end

  local status = R and R.GetStatus and R.GetStatus(name, state.profKey) or "none"
  local rec = R and R.GetEntry and R.GetEntry(name, state.profKey)
  if state.fetchPending == "request" and (status == "none" or status == "partial") then
    catalog.headerStatus:SetText(U.L("PROF_RECIPE_STATUS_REQUESTING"))
    catalog.emptyText:SetText(U.L("PROF_RECIPE_EMPTY_REQUESTING"))
    catalog.emptyText:Show()
  elseif state.fetchPending == "scan" and (status == "none" or status == "partial") then
    catalog.headerStatus:SetText(U.L("PROF_RECIPE_STATUS_SCANNING"))
    catalog.emptyText:SetText(U.L("PROF_RECIPE_EMPTY_SCANNING"))
    catalog.emptyText:Show()
  elseif status == "gathering" then
    catalog.headerStatus:SetText(U.L("PROF_RECIPE_STATUS_GATHERING"))
    catalog.emptyText:SetText(U.L("PROF_RECIPE_EMPTY_GATHERING"))
    catalog.emptyText:Show()
  elseif status == "none" then
    catalog.headerStatus:SetText(U.L("PROF_RECIPE_STATUS_NONE"))
    catalog.emptyText:SetText(IsSelf(name)
      and U.L("PROF_RECIPE_EMPTY_SCAN_HINT")
      or U.L("PROF_RECIPE_EMPTY_MEMBER"))
    catalog.emptyText:Show()
  elseif status == "partial" then
    catalog.headerStatus:SetText(FormatDataAge(rec))
    catalog.emptyText:SetText(U.L("PROF_RECIPE_EMPTY_PARTIAL"))
    catalog.emptyText:Show()
  elseif status == "empty" then
    catalog.headerStatus:SetText(FormatDataAge(rec))
    catalog.emptyText:SetText(U.L("PROF_RECIPE_EMPTY_NONE_LEARNED"))
    catalog.emptyText:Show()
  else
    catalog.headerStatus:SetText(FormatDataAge(rec))
    local ids = FilteredIds()
    if #ids == 0 and state.filter ~= "" then
      catalog.emptyText:SetText(U.L("PROF_RECIPE_EMPTY_FILTER"))
      catalog.emptyText:Show()
    else
      catalog.emptyText:Hide()
    end
  end

  if IsSelf(name) then
    catalog.refreshBtn:Show()
    catalog.openBtn:Show()
  else
    catalog.refreshBtn:Show()
    catalog.openBtn:Hide()
  end
end

function UI:RefreshRecipeCatalog()
  if not state.open then return end
  if state.view == "list" then
    ShowListView()
    RefreshHeader()
    RefreshList()
  else
    ShowDetailView()
    RefreshDetail()
  end
end

local function OpenWhisper()
  local name = state.player
  if not name or IsSelf(name) or not state.comboValid then return end
  U.OpenWhisper(ChatTarget(name))
end

local function BuildCurrentRequestText()
  local R = Recipes()
  local meta = (R and R.GetMeta and R.GetMeta(state.selectedId)) or {}
  return R.BuildRequestText({
    desired = state.desired,
    meta = meta,
    name = RecipeName(state.selectedId),
    link = meta.hyperlink,
    matsBring = state.matsBring,
    matsBringPhrase = U.L("PROF_RECIPE_MATS_BRING"),
    matsOfferPhrase = U.L("PROF_RECIPE_MATS_OFFER"),
  })
end

local function ShowRequestPreview()
  if not catalog or not state.selectedId or IsSelf(state.player) then return end
  ValidateCrafterCombo()
  if not state.comboValid then
    U.Print(U.L("PROF_RECIPE_INVALID_COMBO"))
    return
  end
  -- Keep edited text if reopening same fingerprint; otherwise create fresh.
  local fp = DraftFingerprint()
  if state.draftFingerprint == fp and state.draftText and not state.draftStale then
    catalog.previewEdit:SetText(state.draftText)
  elseif state.draftFingerprint == fp and state.draftStale and state.draftText then
    catalog.previewEdit:SetText(state.draftText)
  else
    local text = BuildCurrentRequestText()
    catalog.previewEdit:SetText(text)
    state.draftText = text
    state.draftFingerprint = fp
    state.draftStale = false
  end
  catalog.preview:Show()
  UpdatePreviewChrome()
end

local function RebuildRequestPreview()
  if not catalog or not state.selectedId then return end
  ValidateCrafterCombo()
  if not state.comboValid then
    U.Print(U.L("PROF_RECIPE_INVALID_COMBO"))
    return
  end
  local text = BuildCurrentRequestText()
  catalog.previewEdit:SetText(text)
  state.draftText = text
  state.draftFingerprint = DraftFingerprint()
  state.draftStale = false
  UpdatePreviewChrome()
end

local function ApplyPreviewToChat()
  if not catalog then return end
  if state.draftStale then
    U.Print(U.L("PROF_RECIPE_STALE_DRAFT"))
    return
  end
  ValidateCrafterCombo()
  if not state.comboValid then
    U.Print(U.L("PROF_RECIPE_INVALID_COMBO"))
    return
  end
  if state.draftFingerprint and state.draftFingerprint ~= DraftFingerprint() then
    state.draftStale = true
    UpdatePreviewChrome()
    U.Print(U.L("PROF_RECIPE_STALE_DRAFT"))
    return
  end
  local text = catalog.previewEdit:GetText() or ""
  local name = state.player
  if not name or text == "" then return end
  local target = ChatTarget(name)
  state.draftText = text
  HidePreview()
  if U.ChatBusy() then
    U.Print(U.L("PROF_RECIPE_CHAT_BUSY"))
    catalog.preview:Show()
    UpdatePreviewChrome()
    return
  end
  U.OpenWhisper(target, text)
end

local function ClearFetchPending()
  state.fetchPending = nil
  state.quietFetch = false
  fetchGen = fetchGen + 1
end

local function ArmFetchTimeout(seconds)
  fetchGen = fetchGen + 1
  local gen = fetchGen
  C_Timer.After(seconds or 15, function()
    if gen ~= fetchGen then return end
    if not state.open or not state.fetchPending then return end
    ClearFetchPending()
    UI:RefreshRecipeCatalog()
  end)
end

local function MaybeAutoFetchRecipes()
  local R = Recipes()
  if not R or not state.player or not state.profKey then return end
  if R.IsGathering and R.IsGathering(state.profKey) then return end
  local status = R.GetStatus and R.GetStatus(state.player, state.profKey) or "none"
  if status ~= "none" and status ~= "partial" then return end

  if IsSelf(state.player) then
    if not R.RefreshProfession then return end
    state.quietFetch = true
    state.fetchPending = "scan"
    ArmFetchTimeout(20)
    UI:RefreshRecipeCatalog()
    local ok, why = R:RefreshProfession(state.profKey, {
      remote = false,
      playerName = state.player,
    })
    if why == "opening" or why == "retrying" then
      return
    end
    ClearFetchPending()
    UI:RefreshRecipeCatalog()
    return
  end

  if not R.RequestProfession then return end
  state.quietFetch = true
  state.fetchPending = "request"
  UI:RefreshRecipeCatalog()
  local ok, why = R:RequestProfession(state.profKey, false)
  if not ok or why ~= "sent" then
    ClearFetchPending()
    UI:RefreshRecipeCatalog()
    return
  end
  ArmFetchTimeout(15)
end

local function SetDesired(n)
  state.desired = Recipes().ClampQty(n)
  if catalog.qtyBox then
    catalog.qtyBox:SetText(tostring(state.desired))
  end
  MarkDraftStaleIfNeeded()
  RefreshDetail()
end

local function EnterDetail(recipeId)
  CaptureListScroll()
  state.selectedId = recipeId
  state.desired = state.desired or 1
  if catalog.qtyBox then catalog.qtyBox:SetText(tostring(state.desired)) end
  ShowDetailView()
  RefreshDetail()
end

local function BackFromDetail()
  HidePreview()
  HideCrafterMenu()
  if state.source == "search" then
    UI:CloseRecipeCatalog(true)
    return
  end
  -- members: return to member recipe list
  state.selectedId = nil
  ShowListView()
  RefreshHeader()
  RefreshList()
end

local function BackFromList()
  UI:CloseRecipeCatalog(true)
end

local function EnsureCatalog(parent)
  if catalog then return catalog end

  catalog = CreateFrame("Frame", nil, parent)
  catalog:SetAllPoints()
  catalog:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)
  catalog:Hide()
  T.ApplyPanelBackdrop(catalog, T.BG)

  -- ===== List pane (member recipes) =====
  local listPane = CreateFrame("Frame", nil, catalog)
  listPane:SetAllPoints()
  catalog.listPane = listPane

  local back = CreateFrame("Button", nil, listPane, "UIPanelButtonTemplate")
  back:SetSize(70, 20)
  back:SetPoint("TOPLEFT", T.INSET, -4)
  back:SetText(U.L("PROF_RECIPE_BACK"))
  back:SetScript("OnClick", BackFromList)

  catalog.headerName = listPane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  catalog.headerName:SetPoint("LEFT", back, "RIGHT", 10, 0)
  catalog.headerName:SetWidth(180)
  catalog.headerName:SetJustifyH("LEFT")

  catalog.headerProf = listPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  catalog.headerProf:SetPoint("LEFT", catalog.headerName, "RIGHT", 8, 0)
  catalog.headerProf:SetWidth(200)
  catalog.headerProf:SetJustifyH("LEFT")

  catalog.headerStatus = listPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  catalog.headerStatus:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -4)
  catalog.headerStatus:SetPoint("RIGHT", listPane, "RIGHT", -T.INSET, 0)
  catalog.headerStatus:SetJustifyH("LEFT")

  catalog.refreshBtn = CreateFrame("Button", nil, listPane, "UIPanelButtonTemplate")
  catalog.refreshBtn:SetSize(140, 20)
  catalog.refreshBtn:SetPoint("TOPRIGHT", -T.INSET, -4)
  catalog.refreshBtn:SetText(U.L("PROF_RECIPE_REFRESH"))
  catalog.refreshBtn:SetScript("OnClick", function()
    local R = Recipes()
    if not R or not state.profKey then return end
    local isSelf = IsSelf(state.player)
    state.quietFetch = false
    state.fetchPending = isSelf and "scan" or "request"
    local ok, why = R:RefreshProfession(state.profKey, {
      remote = not isSelf,
      playerName = state.player,
    })
    if why == "opening" or why == "retrying" then
      ArmFetchTimeout(20)
      U.Print(U.L("PROF_RECIPE_REFRESH_OPENING"))
    elseif why == "sent" then
      ArmFetchTimeout(15)
      U.Print(U.L("PROF_RECIPE_REFRESH_SENT"))
    elseif why == "ok_empty" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_REFRESH_OK_EMPTY"))
    elseif ok and why ~= "empty_suspect" then
      ClearFetchPending()
      U.Print(string.format(U.L("PROF_RECIPE_REFRESH_OK"), DisplayProf(state.profKey)))
    elseif why == "cooldown" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_REFRESH_CD"))
    elseif why == "no_api" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_REFRESH_NO_API"))
    elseif why == "empty_suspect" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_REFRESH_EMPTY_SUSPECT"))
    elseif why == "open_fail" or why == "no_ctx" or why == "spells_fail" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_REFRESH_NEED_OPEN"))
    elseif why == "gathering" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_EMPTY_GATHERING"))
    elseif why == "no_guild" then
      ClearFetchPending()
      U.Print(U.L("PROF_RECIPE_REFRESH_NO_GUILD"))
    else
      ClearFetchPending()
      U.Print(string.format(U.L("PROF_RECIPE_REFRESH_FAIL"), tostring(why or "?")))
    end
    UI:RefreshRecipeCatalog()
  end)

  catalog.openBtn = CreateFrame("Button", nil, listPane, "UIPanelButtonTemplate")
  catalog.openBtn:SetSize(140, 20)
  catalog.openBtn:SetPoint("TOPRIGHT", catalog.refreshBtn, "BOTTOMRIGHT", 0, -2)
  catalog.openBtn:SetText(U.L("PROF_RECIPE_OPEN_SKILL"))
  catalog.openBtn:SetScript("OnClick", function()
    local R = Recipes()
    if R and R.TryOpenTradeSkillForKey then
      R:TryOpenTradeSkillForKey(state.profKey)
    end
  end)

  local searchLabel = listPane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  searchLabel:SetPoint("TOPLEFT", catalog.headerStatus, "BOTTOMLEFT", 0, -8)
  searchLabel:SetText(U.L("PROF_SEARCH"))

  catalog.searchBox = CreateFrame("EditBox", nil, listPane, "InputBoxTemplate")
  catalog.searchBox:SetSize(200, 20)
  catalog.searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
  catalog.searchBox:SetAutoFocus(false)
  catalog.searchBox:SetScript("OnTextChanged", function(self)
    state.filter = self:GetText() or ""
    state.page = 1
    RefreshList()
    RefreshHeader()
  end)

  catalog.pageText = listPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  catalog.pageText:SetPoint("LEFT", catalog.searchBox, "RIGHT", 12, 0)
  catalog.pageText:SetWidth(220)
  catalog.pageText:SetJustifyH("LEFT")

  catalog.prevBtn = CreateFrame("Button", nil, listPane, "UIPanelButtonTemplate")
  catalog.prevBtn:SetSize(24, 18)
  catalog.prevBtn:SetPoint("TOPRIGHT", -56, -52)
  catalog.prevBtn:SetText("<")
  catalog.prevBtn:SetScript("OnClick", function()
    state.page = math.max(1, state.page - 1)
    RefreshList()
  end)

  catalog.nextBtn = CreateFrame("Button", nil, listPane, "UIPanelButtonTemplate")
  catalog.nextBtn:SetSize(24, 18)
  catalog.nextBtn:SetPoint("LEFT", catalog.prevBtn, "RIGHT", 4, 0)
  catalog.nextBtn:SetText(">")
  catalog.nextBtn:SetScript("OnClick", function()
    state.page = state.page + 1
    RefreshList()
  end)

  local scroll = CreateFrame("ScrollFrame", "AngryMurlocsRecipeListScroll", listPane, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  catalog.listScroll = scroll

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(560, NUM_LIST_ROWS * LIST_ROW_H)
  scroll:SetScrollChild(child)
  catalog.listChild = child

  for i = 1, NUM_LIST_ROWS do
    local row = CreateFrame("Button", nil, child)
    row:SetSize(560, LIST_ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * LIST_ROW_H))
    row:RegisterForClicks("LeftButtonUp")
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 2, 0)
    row.icon = icon
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    fs:SetPoint("RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    row.nameFS = fs
    row:SetScript("OnEnter", function(self)
      T.RowHoverEnter(self)
      if not self.recipeId then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(RecipeName(self.recipeId), 1, 1, 1)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
      T.RowHoverLeave(self)
      GameTooltip_Hide()
    end)
    row:SetScript("OnClick", function(self)
      if not self.recipeId then return end
      EnterDetail(self.recipeId)
    end)
    listRows[i] = row
  end

  catalog.emptyText = listPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  catalog.emptyText:SetPoint("CENTER", scroll, "CENTER", 0, 0)
  catalog.emptyText:SetWidth(420)
  catalog.emptyText:Hide()

  -- ===== Detail pane (shared) =====
  local detail = CreateFrame("Frame", nil, catalog)
  detail:SetAllPoints()
  detail:Hide()
  catalog.detailPane = detail

  local dBack = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
  dBack:SetSize(70, 20)
  dBack:SetPoint("TOPLEFT", T.INSET, -4)
  dBack:SetText(U.L("PROF_RECIPE_BACK"))
  dBack:SetScript("OnClick", BackFromDetail)

  catalog.detailName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  catalog.detailName:SetPoint("LEFT", dBack, "RIGHT", 10, 0)
  catalog.detailName:SetWidth(280)
  catalog.detailName:SetJustifyH("LEFT")

  catalog.detailProf = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  catalog.detailProf:SetPoint("LEFT", catalog.detailName, "RIGHT", 8, 0)
  catalog.detailProf:SetWidth(140)
  catalog.detailProf:SetJustifyH("LEFT")

  catalog.crafterLine = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  catalog.crafterLine:SetPoint("TOPLEFT", dBack, "BOTTOMLEFT", 0, -6)
  catalog.crafterLine:SetWidth(320)
  catalog.crafterLine:SetJustifyH("LEFT")

  catalog.crafterBtn = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
  catalog.crafterBtn:SetSize(160, 20)
  catalog.crafterBtn:SetPoint("TOPLEFT", dBack, "BOTTOMLEFT", 0, -4)
  catalog.crafterBtn:Hide()
  catalog.crafterBtn:SetScript("OnClick", function(self)
    local menu = EnsureCrafterMenu()
    if menu:IsShown() then
      menu:Hide()
    else
      RebuildCrafterMenu()
      menu:ClearAllPoints()
      menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
      menu:Show()
    end
  end)

  catalog.crafterStatusFS = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  catalog.crafterStatusFS:SetPoint("TOPLEFT", catalog.crafterBtn, "BOTTOMLEFT", 0, -2)
  catalog.crafterStatusFS:SetPoint("RIGHT", detail, "RIGHT", -T.INSET, 0)
  catalog.crafterStatusFS:SetJustifyH("LEFT")

  catalog.detailYield = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  catalog.detailYield:SetPoint("TOPLEFT", catalog.crafterStatusFS, "BOTTOMLEFT", 0, -6)
  catalog.detailYield:SetPoint("RIGHT", detail, "RIGHT", -T.INSET, 0)
  catalog.detailYield:SetJustifyH("LEFT")

  local qtyLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  qtyLabel:SetPoint("TOPLEFT", catalog.detailYield, "BOTTOMLEFT", 0, -8)
  qtyLabel:SetText(U.L("PROF_RECIPE_QTY"))

  catalog.qtyMinus = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
  catalog.qtyMinus:SetSize(24, 20)
  catalog.qtyMinus:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
  catalog.qtyMinus:SetText("-")
  catalog.qtyMinus:SetScript("OnClick", function()
    SetDesired(state.desired - 1)
  end)

  catalog.qtyBox = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
  catalog.qtyBox:SetSize(50, 20)
  catalog.qtyBox:SetPoint("LEFT", catalog.qtyMinus, "RIGHT", 4, 0)
  catalog.qtyBox:SetAutoFocus(false)
  catalog.qtyBox:SetNumeric(true)
  catalog.qtyBox:SetText("1")
  catalog.qtyBox:SetScript("OnEnterPressed", function(self)
    local n = tonumber(self:GetText())
    SetDesired(n or 1)
    self:ClearFocus()
  end)
  catalog.qtyBox:SetScript("OnEditFocusLost", function(self)
    local n = tonumber(self:GetText())
    SetDesired(n or state.desired)
  end)

  catalog.qtyPlus = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
  catalog.qtyPlus:SetSize(24, 20)
  catalog.qtyPlus:SetPoint("LEFT", catalog.qtyBox, "RIGHT", 4, 0)
  catalog.qtyPlus:SetText("+")
  catalog.qtyPlus:SetScript("OnClick", function()
    SetDesired(state.desired + 1)
  end)

  -- Mat column headers
  local matHdrY = -110
  local hdrName = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrName:SetPoint("TOPLEFT", T.INSET, matHdrY)
  hdrName:SetWidth(280)
  hdrName:SetJustifyH("LEFT")
  hdrName:SetText(U.L("PROF_MAT_NAME"))
  T.SetTextColor(hdrName, T.ACCENT)

  local hdrNeed = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrNeed:SetPoint("TOPLEFT", T.INSET + 300, matHdrY)
  hdrNeed:SetWidth(70)
  hdrNeed:SetJustifyH("RIGHT")
  hdrNeed:SetText(U.L("PROF_MAT_NEED"))
  T.SetTextColor(hdrNeed, T.ACCENT)

  local hdrBag = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrBag:SetPoint("TOPLEFT", T.INSET + 380, matHdrY)
  hdrBag:SetWidth(70)
  hdrBag:SetJustifyH("RIGHT")
  hdrBag:SetText(U.L("PROF_MAT_BAG"))
  T.SetTextColor(hdrBag, T.ACCENT)

  local hdrMiss = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hdrMiss:SetPoint("TOPLEFT", T.INSET + 460, matHdrY)
  hdrMiss:SetWidth(70)
  hdrMiss:SetJustifyH("RIGHT")
  hdrMiss:SetText(U.L("PROF_MAT_MISSING"))
  T.SetTextColor(hdrMiss, T.ACCENT)

  -- Sticky action bar at bottom
  local actionBar = CreateFrame("Frame", nil, detail)
  actionBar:SetPoint("BOTTOMLEFT", T.INSET, 4)
  actionBar:SetPoint("BOTTOMRIGHT", -T.INSET, 4)
  actionBar:SetHeight(56)
  T.ApplyPanelBackdrop(actionBar, T.BG_ALT)
  catalog.actionBar = actionBar

  catalog.matSummary = actionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  catalog.matSummary:SetPoint("TOPLEFT", 8, -6)
  catalog.matSummary:SetPoint("RIGHT", -8, 0)
  catalog.matSummary:SetJustifyH("LEFT")

  catalog.matsBringCb = CreateFrame("CheckButton", nil, actionBar, "UICheckButtonTemplate")
  catalog.matsBringCb:SetSize(22, 22)
  catalog.matsBringCb:SetPoint("BOTTOMLEFT", 6, 4)
  catalog.matsBringCb:SetChecked(true)
  catalog.matsBringCb:SetScript("OnClick", function(self)
    state.matsBring = self:GetChecked() and true or false
    MarkDraftStaleIfNeeded()
  end)
  local matsLabel = actionBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  matsLabel:SetPoint("LEFT", catalog.matsBringCb, "RIGHT", 2, 0)
  matsLabel:SetText(U.L("PROF_RECIPE_MATS_BRING_CB"))

  catalog.whisperBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
  catalog.whisperBtn:SetSize(120, 22)
  catalog.whisperBtn:SetPoint("BOTTOMRIGHT", -128, 6)
  catalog.whisperBtn:SetText(U.L("PROF_WHISPER"))
  catalog.whisperBtn:SetScript("OnClick", OpenWhisper)

  catalog.requestBtn = CreateFrame("Button", nil, actionBar, "UIPanelButtonTemplate")
  catalog.requestBtn:SetSize(110, 22)
  catalog.requestBtn:SetPoint("BOTTOMRIGHT", -8, 6)
  catalog.requestBtn:SetText(U.L("PROF_RECIPE_REQUEST"))
  catalog.requestBtn:SetScript("OnClick", ShowRequestPreview)

  catalog.offlineHint = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  catalog.offlineHint:SetPoint("BOTTOMLEFT", actionBar, "TOPLEFT", 0, 4)
  catalog.offlineHint:SetPoint("RIGHT", detail, "RIGHT", -T.INSET, 0)
  catalog.offlineHint:SetJustifyH("LEFT")
  catalog.offlineHint:Hide()

  local matScroll = CreateFrame("ScrollFrame", "AngryMurlocsMatScroll", detail, "UIPanelScrollFrameTemplate")
  matScroll:SetPoint("TOPLEFT", T.INSET, matHdrY - 16)
  matScroll:SetPoint("BOTTOMRIGHT", -28, 72)
  catalog.matScroll = matScroll

  local matChild = CreateFrame("Frame", nil, matScroll)
  matChild:SetSize(560, NUM_MAT_ROWS * MAT_ROW_H)
  matScroll:SetScrollChild(matChild)
  catalog.matChild = matChild

  for i = 1, NUM_MAT_ROWS do
    local row = CreateFrame("Frame", nil, matChild)
    row:SetSize(560, MAT_ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * MAT_ROW_H))
    row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", 4, 0)
    row.nameFS:SetWidth(280)
    row.nameFS:SetJustifyH("LEFT")
    row.needFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.needFS:SetPoint("LEFT", 300, 0)
    row.needFS:SetWidth(70)
    row.needFS:SetJustifyH("RIGHT")
    row.bagFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bagFS:SetPoint("LEFT", 380, 0)
    row.bagFS:SetWidth(70)
    row.bagFS:SetJustifyH("RIGHT")
    row.missFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.missFS:SetPoint("LEFT", 460, 0)
    row.missFS:SetWidth(70)
    row.missFS:SetJustifyH("RIGHT")
    row:Hide()
    matRows[i] = row
  end

  -- Request preview dialog
  local preview = CreateFrame("Frame", "AngryMurlocsRecipePreview", catalog)
  preview:SetFrameStrata("DIALOG")
  preview:SetSize(440, 200)
  preview:SetPoint("CENTER")
  T.ApplyPanelBackdrop(preview, T.BG)
  preview:Hide()
  catalog.preview = preview

  local prevTitle = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  prevTitle:SetPoint("TOPLEFT", 10, -10)
  prevTitle:SetText(U.L("PROF_RECIPE_REQUEST_PREVIEW"))

  catalog.previewMetaFS = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  catalog.previewMetaFS:SetPoint("TOPLEFT", 10, -28)
  catalog.previewMetaFS:SetWidth(420)
  catalog.previewMetaFS:SetJustifyH("LEFT")

  catalog.previewStaleFS = preview:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  catalog.previewStaleFS:SetPoint("TOPLEFT", 10, -44)
  catalog.previewStaleFS:SetWidth(420)
  catalog.previewStaleFS:SetJustifyH("LEFT")
  catalog.previewStaleFS:Hide()

  local edit = CreateFrame("EditBox", nil, preview, "InputBoxTemplate")
  edit:SetMultiLine(true)
  edit:SetSize(420, 80)
  edit:SetPoint("TOPLEFT", 10, -60)
  edit:SetAutoFocus(false)
  catalog.previewEdit = edit

  local applyBtn = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
  applyBtn:SetSize(130, 22)
  applyBtn:SetPoint("BOTTOMLEFT", 10, 10)
  applyBtn:SetText(U.L("PROF_RECIPE_TO_CHAT"))
  applyBtn:SetScript("OnClick", ApplyPreviewToChat)
  catalog.previewApplyBtn = applyBtn

  local rebuildBtn = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
  rebuildBtn:SetSize(110, 22)
  rebuildBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
  rebuildBtn:SetText(U.L("PROF_RECIPE_REBUILD"))
  rebuildBtn:SetScript("OnClick", RebuildRequestPreview)
  rebuildBtn:Hide()
  catalog.previewRebuildBtn = rebuildBtn

  local cancelBtn = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
  cancelBtn:SetSize(100, 22)
  cancelBtn:SetPoint("LEFT", rebuildBtn, "RIGHT", 8, 0)
  cancelBtn:SetText(U.L("PROF_RECIPE_CANCEL"))
  cancelBtn:SetScript("OnClick", HidePreview)

  return catalog
end

function UI:AttachRecipePanel(parent)
  EnsureCatalog(parent)

  if not catalog._amItemInfoFrame then
    local f = CreateFrame("Frame")
    catalog._amItemInfoFrame = f
    if U.SafeRegisterEvent(f, "GET_ITEM_INFO_RECEIVED") then
      f:SetScript("OnEvent", function(_, event, itemID, success)
        if event ~= "GET_ITEM_INFO_RECEIVED" then return end
        if not state.open or state.view ~= "detail" or not state.selectedId then return end
        itemID = tonumber(itemID)
        if not itemID then return end
        if success == false then return end
        if state.pendingMatIds and state.pendingMatIds[itemID] then
          local R = Recipes()
          if R and R.ResolveItemName and R.CacheReagentName then
            local name = select(1, R.ResolveItemName(itemID))
            if name then R.CacheReagentName(state.selectedId, itemID, name) end
          end
          RefreshDetail()
        end
      end)
    end
  end

  if not catalog._amBagFrame then
    local bf = CreateFrame("Frame")
    catalog._amBagFrame = bf
    local function OnBagEvent(event)
      if event ~= "BAG_UPDATE" and event ~= "PLAYERBANKSLOTS_CHANGED" then return end
      if not state.open or state.view ~= "detail" then return end
      if state.bagRefreshPending then return end
      state.bagRefreshPending = true
      C_Timer.After(0.05, function()
        state.bagRefreshPending = false
        if state.open and state.view == "detail" then
          RefreshDetail()
        end
      end)
    end
    if U.SafeRegisterEvent(bf, "BAG_UPDATE") then
      bf:SetScript("OnEvent", function(_, event)
        OnBagEvent(event)
      end)
    end
    U.SafeRegisterEvent(bf, "PLAYERBANKSLOTS_CHANGED")
  end

  GR:BindMessage(UI, "PROF_RECIPES_CHANGED", function(_, sender, profKey)
    if not state.open then return end
    if state.fetchPending
        and (not profKey or profKey == state.profKey)
        and (not sender or U.NormalizeName(sender) == U.NormalizeName(state.player)) then
      ClearFetchPending()
    elseif state.fetchPending and not sender and not profKey then
      ClearFetchPending()
    end
    UI:RefreshRecipeCatalog()
  end)
  GR:BindMessage(UI, "PROF_RECIPE_REFRESH_DONE", function(_, profKey, ok, why)
    if not state.open then return end
    local quiet = state.quietFetch
    if state.fetchPending and (not profKey or profKey == state.profKey) then
      ClearFetchPending()
    end
    if not quiet then
      if ok and why == "ok_empty" then
        U.Print(U.L("PROF_RECIPE_REFRESH_OK_EMPTY"))
      elseif ok then
        U.Print(string.format(U.L("PROF_RECIPE_REFRESH_OK"), DisplayProf(profKey or state.profKey)))
      elseif why == "empty_suspect" then
        U.Print(U.L("PROF_RECIPE_REFRESH_EMPTY_SUSPECT"))
      elseif why == "spells_fail" or why == "no_ctx" then
        U.Print(U.L("PROF_RECIPE_REFRESH_NEED_OPEN"))
      else
        U.Print(string.format(U.L("PROF_RECIPE_REFRESH_FAIL"), tostring(why or "?")))
      end
    end
    UI:RefreshRecipeCatalog()
  end)
end

-- restoreNav: when true, ask UI to restore sub-tab filters/scroll
function UI:CloseRecipeCatalog(restoreNav)
  if not state.open then return end
  state.open = false
  state.view = "list"
  state.player = nil
  state.profKey = nil
  state.selectedId = nil
  state.crafters = nil
  ClearFetchPending()
  HidePreview()
  HideCrafterMenu()
  if catalog then catalog:Hide() end
  SetBaseListsVisible(true)
  if restoreNav and UI.RestoreProfNav then
    UI:RestoreProfNav()
  elseif UI.RefreshProfSubTab then
    UI:RefreshProfSubTab()
  elseif UI.RefreshList then
    UI:RefreshList()
  end
end

function UI:IsRecipeCatalogOpen()
  return state.open
end

function UI:OpenRecipeCatalog(playerName, profKey)
  if not playerName or not profKey then return end
  if not catalog then return end
  if UI.CaptureProfNav then UI:CaptureProfNav() end
  state.open = true
  state.source = "members"
  state.view = "list"
  state.player = playerName
  state.profKey = profKey
  state.selectedId = nil
  state.crafters = { playerName }
  state.filter = ""
  state.desired = 1
  state.matsBring = true
  state.page = 1
  state.listScrollY = 0
  ClearFetchPending()
  if catalog.searchBox then catalog.searchBox:SetText("") end
  if catalog.qtyBox then catalog.qtyBox:SetText("1") end
  if catalog.matsBringCb then catalog.matsBringCb:SetChecked(true) end
  HidePreview()
  HideCrafterMenu()
  SetBaseListsVisible(false)
  catalog:Show()
  ShowListView()
  UI:RefreshRecipeCatalog()
  MaybeAutoFetchRecipes()
end

-- From recipe search: open shared detail with crafter list.
function UI:OpenRecipeDetail(recipeId, profKey, crafters)
  recipeId = tonumber(recipeId)
  if not recipeId or not profKey then return end
  if not catalog then return end
  if UI.CaptureProfNav then UI:CaptureProfNav() end
  local list = {}
  if type(crafters) == "table" then
    for i = 1, #crafters do
      if crafters[i] then list[#list + 1] = crafters[i] end
    end
  end
  if #list == 0 then return end
  state.open = true
  state.source = "search"
  state.view = "detail"
  state.selectedId = recipeId
  state.profKey = profKey
  state.crafters = list
  state.player = list[1]
  state.filter = ""
  state.desired = 1
  state.matsBring = true
  state.page = 1
  ClearFetchPending()
  if catalog.qtyBox then catalog.qtyBox:SetText("1") end
  if catalog.matsBringCb then catalog.matsBringCb:SetChecked(true) end
  HidePreview()
  HideCrafterMenu()
  SetBaseListsVisible(false)
  catalog:Show()
  ShowDetailView()
  RefreshDetail()
end
