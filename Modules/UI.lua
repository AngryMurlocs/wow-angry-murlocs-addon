local GR = AngryMurlocs
local U = GR.Util

local UI = GR:NewModule("UI")

local frame
local scrollChild
local filterBox
local rows = {}
local ROW_H = 20
local NUM_ROWS = 16

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "AngryMurlocsFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(560, 420)
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.professions = GR.db.frames.professions or {}
  U.MakeMovable(frame, {
    getPoint = function() return GR.db.frames.professions.point end,
    setPoint = function(pt) GR.db.frames.professions.point = pt end,
    defaultFn = function(f) f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end,
  })
  frame:Hide()
  tinsert(UISpecialFrames, "AngryMurlocsFrame")

  frame.TitleText:SetText(U.L("WINDOW_TITLE"))

  local filterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  filterLabel:SetPoint("TOPLEFT", 16, -32)
  filterLabel:SetText(U.L("FILTER"))

  filterBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  filterBox:SetSize(200, 20)
  filterBox:SetPoint("LEFT", filterLabel, "RIGHT", 8, 0)
  filterBox:SetAutoFocus(false)
  filterBox:SetScript("OnTextChanged", function()
    UI:RefreshList()
  end)

  local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshBtn:SetSize(100, 22)
  refreshBtn:SetPoint("TOPRIGHT", -12, -30)
  refreshBtn:SetText("Sync")
  refreshBtn:SetScript("OnClick", function()
    local prof = GR:GetModule("Professions")
    if prof then
      prof:RequestAll()
      prof:Broadcast(true)
    end
    UI:RefreshList()
  end)

  local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", 16, -58)
  header:SetText(string.format(
    "%-16s  %-18s  %-18s  %s",
    U.L("COL_NAME"),
    U.L("COL_PROF1"),
    U.L("COL_PROF2"),
    U.L("COL_SEC")
  ))

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -78)
  scroll:SetPoint("BOTTOMRIGHT", -32, 16)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(500, NUM_ROWS * ROW_H)
  scroll:SetScrollChild(scrollChild)

  for i = 1, NUM_ROWS do
    local row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row:SetPoint("TOPLEFT", 4, -((i - 1) * ROW_H))
    row:SetJustifyH("LEFT")
    row:SetWidth(500)
    rows[i] = row
  end

  frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  frame.empty:SetPoint("CENTER", scroll, "CENTER")
  frame.empty:SetText(U.L("NO_DATA"))
  frame.empty:Hide()

  return frame
end

local function FormatProfs(list)
  if not list or #list == 0 then
    return "-", "-", "-"
  end
  local primary = {}
  local secondary = {}
  local secKeys = { cook = true, aid = true, fish = true }
  for i = 1, #list do
    local p = list[i]
    local label = (p.name or p.key) .. " " .. tostring(p.skill)
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
  -- min skill: alchemy 200 / alch 200
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

function UI:RefreshList()
  if not frame or not frame:IsShown() then return end
  local prof = GR:GetModule("Professions")
  local cache = prof and prof:GetAll() or {}
  local filter = filterBox and filterBox:GetText() or ""

  local names = {}
  for name, entry in pairs(cache) do
    if MatchesFilter(name, entry, filter) then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  if #names == 0 then
    frame.empty:Show()
  else
    frame.empty:Hide()
  end

  for i = 1, NUM_ROWS do
    local name = names[i]
    if name then
      local entry = cache[name]
      local p1, p2, sec = FormatProfs(entry.list)
      local short = U.ShortName(name)
      local me = U.NormalizeName(U.PlayerName())
      if name == me then
        short = short .. " (" .. U.L("YOU") .. ")"
      end
      local r, g, b = U.ClassColor(entry.classFile)
      rows[i]:SetText(string.format("%-16s  %-18s  %-18s  %s", short:sub(1, 16), p1, p2, sec))
      rows[i]:SetTextColor(r, g, b)
      rows[i]:Show()
    else
      rows[i]:Hide()
    end
  end
end

function UI:Toggle()
  EnsureFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    self:ShowProf()
  end
end

function UI:ShowProf()
  EnsureFrame()
  frame:Show()
  local prof = GR:GetModule("Professions")
  if prof then
    prof:Broadcast(true)
    prof:RequestAll()
  end
  self:RefreshList()
end

function UI:OnEnable()
  GR:RegisterMessage("PROF_CACHE_CHANGED", function()
    if frame and frame:IsShown() then
      UI:RefreshList()
    end
  end)
end
