local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Craft = GR:NewModule("Craft")

local frame
local listChild
local rows = {}
local NUM_ROWS = 30
local ROW_H = 22
local MAX_CRAFT = 50
local selectedId
local itemBox, qtyBox, noteBox, matsCheck
local detailText
local syncBusy = false
local localSeq = 0

local function EnsureDB()
  local scope = U.GetScopeDB()
  return scope and scope.craft or {}
end

local function Me()
  return U.NormalizeName(U.PlayerName())
end

local function SameName(a, b)
  if not a or not b then return false end
  return string.lower(U.NormalizeName(a)) == string.lower(U.NormalizeName(b))
end

local function StatusLabel(st)
  if st == "taken" then return U.L("CRAFT_STATUS_TAKEN") end
  if st == "done" then return U.L("CRAFT_STATUS_DONE") end
  if st == "cancelled" then return U.L("CRAFT_STATUS_CANCELLED") end
  return U.L("CRAFT_STATUS_OPEN")
end

local function RebuildLink(rec)
  if not rec then return nil end
  if rec.itemLinkEsc and rec.itemLinkEsc ~= "" then
    return U.UnescapeField(rec.itemLinkEsc)
  end
  if rec.itemId and rec.itemId > 0 then
    local name = rec.itemName or ("item:" .. tostring(rec.itemId))
    return string.format("|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r", rec.itemId, name)
  end
  return nil
end

local function ParseItemFromEdit(text)
  text = tostring(text or "")
  local link = text:match("(|c%x+|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h|r)")
  if link then
    local id = tonumber(link:match("item:(%d+)"))
    local name = link:match("%[(.-)%]") or ""
    return id, name, link
  end
  local id = tonumber(text:match("(%d+)"))
  if id then
    return id, text, nil
  end
  return nil, nil, nil
end

local function PruneOld(db)
  local list = {}
  for id, rec in pairs(db) do
    list[#list + 1] = rec
  end
  if #list <= MAX_CRAFT then return end
  table.sort(list, function(a, b)
    return (a.ts or 0) < (b.ts or 0)
  end)
  local remove = #list - MAX_CRAFT
  for i = 1, remove do
    local r = list[i]
    if r and (r.status == "done" or r.status == "cancelled") then
      db[r.id] = nil
    end
  end
end

local function NewId()
  localSeq = localSeq + 1
  return string.format("%s-%d-%d", U.ShortName(Me()), U.WallTime(), localSeq)
end

local function EncodeWire(rec, action, claimant)
  -- CRAFT|action|id|ver|ts|owner|itemId|itemName|itemLinkEsc|qty|mats|note|status|assignee|claimant
  return string.format(
    "CRAFT|%s|%s|%d|%d|%s|%d|%s|%s|%d|%d|%s|%s|%s|%s",
    action,
    U.SanitizeText(rec.id, 64),
    rec.ver or 1,
    rec.ts or 0,
    U.SanitizeText(rec.owner or "", 48),
    tonumber(rec.itemId) or 0,
    U.SanitizeText(rec.itemName or "", 64),
    tostring(rec.itemLinkEsc or ""),
    tonumber(rec.qty) or 1,
    rec.mats and 1 or 0,
    U.SanitizeText(rec.note or "", 80),
    U.SanitizeText(rec.status or "open", 16),
    U.SanitizeText(rec.assignee or "", 48),
    U.SanitizeText(claimant or "", 48)
  )
end

local function Broadcast(rec, action, claimant)
  if not IsInGuild or not IsInGuild() then return end
  Comm:Send(EncodeWire(rec, action, claimant))
end

function Craft:GetSorted()
  local db = EnsureDB()
  local list = {}
  for _, rec in pairs(db) do
    if rec and rec.id and rec.status ~= "cancelled" then
      list[#list + 1] = rec
    elseif rec and rec.id and rec.status == "cancelled" then
      -- show cancelled briefly if recent
      if (U.WallTime() - (rec.ts or 0)) < 3600 then
        list[#list + 1] = rec
      end
    end
  end
  table.sort(list, function(a, b)
    return (a.ts or 0) > (b.ts or 0)
  end)
  return list
end

function Craft:ApplyRemote(sender, data)
  if not data or not data.id then return false end
  local action = data.action
  local db = EnsureDB()
  local cur = db[data.id]
  local ver = tonumber(data.ver) or 0
  if ver < 1 then return false end

  -- Version gate: reject stale
  if cur and (cur.ver or 0) > ver then
    return false
  end
  if cur and (cur.ver or 0) == ver then
    return false
  end

  local meSender = U.NormalizeName(sender)

  if action == "create" then
    if not SameName(data.owner, meSender) then return false end
    if not data.itemId or data.itemId < 1 then return false end
    local claimants = (cur and cur.claimants) or {}
    local assignee = nil
    if data.assignee and data.assignee ~= "" then
      assignee = U.NormalizeName(data.assignee)
    end
    db[data.id] = {
      id = data.id,
      ver = ver,
      ts = data.ts or U.WallTime(),
      status = data.status or "open",
      owner = U.NormalizeName(data.owner),
      itemId = data.itemId,
      itemName = data.itemName or "",
      itemLinkEsc = data.itemLinkEsc or "",
      qty = data.qty or 1,
      mats = data.mats and true or false,
      note = data.note or "",
      claimants = claimants,
      assignee = assignee,
    }
  elseif action == "claim" then
    if not cur then return false end
    local claimName = U.NormalizeName((data.claimant and data.claimant ~= "") and data.claimant or sender)
    if not SameName(claimName, sender) then return false end
    cur.ver = ver
    cur.ts = data.ts or cur.ts
    cur.claimants = cur.claimants or {}
    cur.claimants[claimName] = true
  elseif action == "unclaim" then
    if not cur then return false end
    local claimName = U.NormalizeName((data.claimant and data.claimant ~= "") and data.claimant or sender)
    if not SameName(claimName, sender) then return false end
    cur.ver = ver
    cur.ts = data.ts or cur.ts
    cur.claimants = cur.claimants or {}
    cur.claimants[claimName] = nil
  elseif action == "assign" then
    if not cur then return false end
    if not SameName(cur.owner, sender) then return false end
    cur.ver = ver
    cur.ts = data.ts or cur.ts
    cur.assignee = U.NormalizeName(data.assignee or "")
    if cur.assignee == "" then cur.assignee = nil end
    cur.status = "taken"
  elseif action == "done" then
    if not cur then return false end
    if not SameName(cur.owner, sender) then return false end
    cur.ver = ver
    cur.ts = data.ts or cur.ts
    cur.status = "done"
  elseif action == "reopen" then
    if not cur then return false end
    if not SameName(cur.owner, sender) then return false end
    cur.ver = ver
    cur.ts = data.ts or cur.ts
    cur.status = "open"
    cur.assignee = nil
  elseif action == "cancel" then
    if not cur then return false end
    if not SameName(cur.owner, sender) then return false end
    cur.ver = ver
    cur.ts = data.ts or cur.ts
    cur.status = "cancelled"
  else
    return false
  end

  PruneOld(db)
  GR:SendMessage("CRAFT_CHANGED")
  return true
end

function Craft:CreateLocal(itemText, qty, mats, note)
  local idNum, name, link = ParseItemFromEdit(itemText)
  if not idNum then
    U.Print(U.L("CRAFT_NEED_ITEM"))
    return
  end
  qty = tonumber(qty) or 1
  qty = U.Clamp(qty, 1, 999)
  note = U.SanitizeText(note or "", 80)
  local me = Me()
  local rec = {
    id = NewId(),
    ver = 1,
    ts = U.WallTime(),
    status = "open",
    owner = me,
    itemId = idNum,
    itemName = name or "",
    itemLinkEsc = link and U.EscapeField(link, 180) or "",
    qty = qty,
    mats = mats and true or false,
    note = note,
    claimants = {},
    assignee = nil,
  }
  local db = EnsureDB()
  db[rec.id] = rec
  PruneOld(db)
  Broadcast(rec, "create")
  GR:SendMessage("CRAFT_CHANGED")
  selectedId = rec.id
  U.Print(U.L("CRAFT_CREATED"))
end

local function Bump(rec)
  rec.ver = (rec.ver or 0) + 1
  rec.ts = U.WallTime()
end

function Craft:Claim(id)
  local db = EnsureDB()
  local rec = db[id]
  if not rec or rec.status ~= "open" then return end
  local me = Me()
  rec.claimants = rec.claimants or {}
  rec.claimants[me] = true
  Bump(rec)
  Broadcast(rec, "claim", me)
  GR:SendMessage("CRAFT_CHANGED")
end

function Craft:Unclaim(id)
  local db = EnsureDB()
  local rec = db[id]
  if not rec then return end
  local me = Me()
  rec.claimants = rec.claimants or {}
  rec.claimants[me] = nil
  Bump(rec)
  Broadcast(rec, "unclaim", me)
  GR:SendMessage("CRAFT_CHANGED")
end

function Craft:Assign(id, assignee)
  local db = EnsureDB()
  local rec = db[id]
  if not rec then return end
  if not SameName(rec.owner, Me()) then
    U.Print(U.L("CRAFT_OWNER_ONLY"))
    return
  end
  assignee = U.NormalizeName(assignee)
  if not assignee then return end
  rec.assignee = assignee
  rec.status = "taken"
  Bump(rec)
  Broadcast(rec, "assign")
  GR:SendMessage("CRAFT_CHANGED")
end

function Craft:SetStatus(id, status)
  local db = EnsureDB()
  local rec = db[id]
  if not rec then return end
  if not SameName(rec.owner, Me()) then
    U.Print(U.L("CRAFT_OWNER_ONLY"))
    return
  end
  local action
  if status == "done" then action = "done"
  elseif status == "open" then
    action = "reopen"
    rec.assignee = nil
  elseif status == "cancelled" then action = "cancel"
  else return end
  rec.status = status == "open" and "open" or status
  if status == "cancelled" then rec.status = "cancelled" end
  if status == "done" then rec.status = "done" end
  Bump(rec)
  Broadcast(rec, action)
  GR:SendMessage("CRAFT_CHANGED")
end

function Craft:BroadcastAll()
  if not IsInGuild or not IsInGuild() then return end
  local list = Craft:GetSorted()
  local delay = 0
  local me = Me()
  for i = 1, math.min(#list, 20) do
    local rec = list[i]
    delay = delay + 0.4
    C_Timer.After(delay, function()
      if SameName(rec.owner, me) then
        Broadcast(rec, "create")
      elseif rec.claimants and rec.claimants[me] then
        Bump(rec)
        Broadcast(rec, "claim", me)
        GR:SendMessage("CRAFT_CHANGED")
      end
    end)
  end
end

function Craft:RequestSync()
  if syncBusy then return end
  if not IsInGuild or not IsInGuild() then return end
  syncBusy = true
  Comm:Send("SYNCREQ|craft")
  C_Timer.After(2 + math.random() * 2, function()
    Craft:BroadcastAll()
    syncBusy = false
  end)
end

local function ClaimantList(rec)
  local t = {}
  for name, v in pairs(rec.claimants or {}) do
    if v then t[#t + 1] = name end
  end
  table.sort(t)
  return t
end

local function RefreshDetail()
  if not detailText then return end
  local db = EnsureDB()
  local rec = selectedId and db[selectedId]
  if not rec then
    detailText:SetText(U.L("CRAFT_SELECT_HINT"))
    return
  end
  local claimants = ClaimantList(rec)
  local claimStr = #claimants > 0 and table.concat(
    (function()
      local s = {}
      for i = 1, #claimants do s[i] = U.ShortName(claimants[i]) end
      return s
    end)(),
    ", "
  ) or "-"
  local link = RebuildLink(rec) or rec.itemName or "?"
  -- Strip color for plain status line; keep name
  local age = U.WallTime() - (rec.ts or 0)
  detailText:SetText(string.format(
    "%s\n%s: %s\n%s: %d\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s",
    link:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""),
    U.L("CRAFT_COL_QTY"), tostring(rec.qty),
    U.L("CRAFT_COL_OWNER"), U.ShortName(rec.owner),
    U.L("CRAFT_COL_MATS"), rec.mats and U.L("CRAFT_MATS_YES") or U.L("CRAFT_MATS_NO"),
    U.L("CRAFT_COL_NOTE"), rec.note ~= "" and rec.note or "-",
    U.L("CRAFT_COL_STATUS"), StatusLabel(rec.status),
    U.L("CRAFT_COL_ASSIGNEE"), rec.assignee and U.ShortName(rec.assignee) or "-",
    U.L("CRAFT_COL_CLAIMANTS"), claimStr,
    string.format(U.L("AGO"), math.max(0, math.floor(age)))
  ))
end

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "AngryMurlocsCraftFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(620, 480)
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.craft = GR.db.frames.craft or {}
  U.MakeMovable(frame, {
    getPoint = function() return GR.db.frames.craft.point end,
    setPoint = function(pt) GR.db.frames.craft.point = pt end,
    defaultFn = function(f) f:SetPoint("CENTER", UIParent, "CENTER", -40, 20) end,
  })
  frame:Hide()
  tinsert(UISpecialFrames, "AngryMurlocsCraftFrame")
  frame.TitleText:SetText(U.L("CRAFT_WINDOW_TITLE"))

  -- Create form
  local formY = -28
  local itemLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  itemLabel:SetPoint("TOPLEFT", 14, formY)
  itemLabel:SetText(U.L("CRAFT_ITEM"))

  itemBox = CreateFrame("EditBox", "AngryMurlocsCraftItemBox", frame, "InputBoxTemplate")
  itemBox:SetSize(280, 20)
  itemBox:SetPoint("TOPLEFT", 90, formY + 2)
  itemBox:SetAutoFocus(false)

  -- Shift-click item insert when focused
  if not Craft._linkHooked then
    Craft._linkHooked = true
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if itemBox and itemBox:IsVisible() and itemBox:HasFocus() and link then
        itemBox:SetText(link)
        return true
      end
    end)
  end

  local qtyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  qtyLabel:SetPoint("TOPLEFT", 380, formY)
  qtyLabel:SetText(U.L("CRAFT_QTY"))

  qtyBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  qtyBox:SetSize(40, 20)
  qtyBox:SetPoint("TOPLEFT", 430, formY + 2)
  qtyBox:SetAutoFocus(false)
  qtyBox:SetText("1")
  qtyBox:SetNumeric(true)

  matsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  matsCheck:SetPoint("TOPLEFT", 14, formY - 26)
  matsCheck:SetChecked(true)
  local matsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  matsLabel:SetPoint("LEFT", matsCheck, "RIGHT", 2, 0)
  matsLabel:SetText(U.L("CRAFT_MATS"))

  noteBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  noteBox:SetSize(200, 20)
  noteBox:SetPoint("LEFT", matsLabel, "RIGHT", 12, 0)
  noteBox:SetAutoFocus(false)
  noteBox:SetMaxLetters(80)

  local createBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  createBtn:SetSize(100, 22)
  createBtn:SetPoint("TOPRIGHT", -14, formY - 24)
  createBtn:SetText(U.L("CRAFT_CREATE"))
  createBtn:SetScript("OnClick", function()
    Craft:CreateLocal(itemBox:GetText(), qtyBox:GetText(), matsCheck:GetChecked(), noteBox:GetText())
    itemBox:SetText("")
    noteBox:SetText("")
    qtyBox:SetText("1")
    Craft:Refresh()
  end)

  -- List
  local scroll = CreateFrame("ScrollFrame", "AngryMurlocsCraftScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -90)
  scroll:SetPoint("BOTTOMRIGHT", -32, 160)

  listChild = CreateFrame("Frame", nil, scroll)
  listChild:SetSize(560, NUM_ROWS * ROW_H)
  scroll:SetScrollChild(listChild)

  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, listChild)
    row:SetSize(540, ROW_H)
    row:SetPoint("TOPLEFT", 4, -((i - 1) * ROW_H))
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetAllPoints()
    row.text:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function(self)
      if self.id then
        selectedId = self.id
        Craft:Refresh()
      end
    end)
    row:SetScript("OnEnter", function(self)
      if not self.id then return end
      local db = EnsureDB()
      local rec = db[self.id]
      if not rec then return end
      local link = RebuildLink(rec)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if link and GameTooltip.SetHyperlink then
        pcall(GameTooltip.SetHyperlink, GameTooltip, link:match("|H(.-)|h") or link)
      else
        GameTooltip:AddLine(rec.itemName or "?", 1, 1, 1)
      end
      GameTooltip:AddLine(U.ShortName(rec.owner), 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
  end

  detailText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detailText:SetPoint("BOTTOMLEFT", 14, 70)
  detailText:SetWidth(400)
  detailText:SetJustifyH("LEFT")
  detailText:SetJustifyV("TOP")

  local function ActionBtn(text, x, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetPoint("BOTTOMLEFT", x, 12)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  ActionBtn(U.L("CRAFT_CLAIM"), 12, function()
    if selectedId then Craft:Claim(selectedId) Craft:Refresh() end
  end)
  ActionBtn(U.L("CRAFT_UNCLAIM"), 108, function()
    if selectedId then Craft:Unclaim(selectedId) Craft:Refresh() end
  end)
  ActionBtn(U.L("CRAFT_ASSIGN"), 204, function()
    if not selectedId then return end
    local db = EnsureDB()
    local rec = db[selectedId]
    if not rec then return end
    local claimants = ClaimantList(rec)
    if #claimants == 0 then
      U.Print(U.L("CRAFT_NO_CLAIMANTS"))
      return
    end
    -- Assign first claimant; if multiple, cycle via next unassigned preference:
    -- Prefer selected via simple pick: first in list (owner can unclaim/reopen)
    -- Better: assign the first; show print of who. For multi, use next after current.
    local pick = claimants[1]
    if #claimants > 1 then
      -- If already has assignee in list, pick next
      if rec.assignee then
        for i = 1, #claimants do
          if SameName(claimants[i], rec.assignee) then
            pick = claimants[(i % #claimants) + 1]
            break
          end
        end
      end
    end
    Craft:Assign(selectedId, pick)
    Craft:Refresh()
    U.Print(string.format(U.L("CRAFT_ASSIGNED_TO"), U.ShortName(pick)))
  end)
  ActionBtn(U.L("CRAFT_DONE"), 300, function()
    if selectedId then Craft:SetStatus(selectedId, "done") Craft:Refresh() end
  end)
  ActionBtn(U.L("CRAFT_REOPEN"), 396, function()
    if selectedId then Craft:SetStatus(selectedId, "open") Craft:Refresh() end
  end)
  ActionBtn(U.L("CRAFT_CANCEL"), 492, function()
    if selectedId then Craft:SetStatus(selectedId, "cancelled") Craft:Refresh() end
  end)

  return frame
end

function Craft:Refresh()
  if not frame or not frame:IsShown() then return end
  local list = Craft:GetSorted()
  listChild:SetHeight(math.max(#list, 1) * ROW_H)
  for i = 1, NUM_ROWS do
    local rec = list[i]
    if rec then
      rows[i].id = rec.id
      local name = (rec.itemName and rec.itemName ~= "" and rec.itemName) or ("#" .. tostring(rec.itemId))
      rows[i].text:SetText(string.format(
        "[%s] x%d  %s  (%s)  %s",
        StatusLabel(rec.status),
        rec.qty or 1,
        name:sub(1, 28),
        U.ShortName(rec.owner),
        rec.mats and U.L("CRAFT_MATS_YES") or U.L("CRAFT_MATS_NO")
      ))
      if selectedId == rec.id then
        rows[i].text:SetTextColor(1, 0.82, 0)
      else
        rows[i].text:SetTextColor(1, 1, 1)
      end
      rows[i]:Show()
    else
      rows[i].id = nil
      rows[i]:Hide()
    end
  end
  RefreshDetail()
end

function Craft:Toggle()
  EnsureFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    Craft:Refresh()
  end
end

function Craft:OnEnable()
  EnsureDB()

  GR:RegisterMessage("CRAFT_UPDATE", function(_, sender, data)
    Craft:ApplyRemote(sender, data)
  end)

  GR:RegisterMessage("SYNCREQ_UPDATE", function(_, sender, kind)
    if kind ~= "craft" then return end
    C_Timer.After(0.8 + math.random() * 3, function()
      Craft:BroadcastAll()
    end)
  end)

  GR:RegisterMessage("CRAFT_CHANGED", function()
    if frame and frame:IsShown() then
      Craft:Refresh()
    end
  end)

  GR:RegisterMessage("GUILD_UPDATE", function()
    EnsureDB()
  end)

  C_Timer.After(8, function()
    Craft:RequestSync()
  end)
end
