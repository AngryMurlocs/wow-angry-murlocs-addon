local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Wanted = GR:NewModule("Wanted")

local frame
local rows = {}
local minimapBtn
local NUM_ROWS = 12
local ROW_H = 18

local function EnsureDB()
  GR.db.wanted = GR.db.wanted or {}
  return GR.db.wanted
end

local function NormalizeKiller(name)
  if not name or name == "" then return nil end
  return U.NormalizeName(name)
end

function Wanted:AddKill(killer, victim, zone, fromSelf)
  local key = NormalizeKiller(killer)
  if not key then return end
  local db = EnsureDB()
  local entry = db[key]
  if not entry then
    entry = { count = 0, lastVictim = "", lastZone = "", lastTime = 0 }
    db[key] = entry
  end
  entry.count = (entry.count or 0) + 1
  entry.lastVictim = U.ShortName(victim or "")
  entry.lastZone = zone or ""
  entry.lastTime = time and time() or 0
  GR:SendMessage("WANTED_CHANGED")
  if frame and frame:IsShown() then
    Wanted:Refresh()
  end
end

function Wanted:Clear(killer, broadcast)
  local db = EnsureDB()
  if killer then
    local key = NormalizeKiller(killer)
    if key then db[key] = nil end
    if broadcast then
      Comm:Send("WANTED|clear|" .. (killer:gsub("|", "")) .. "||")
    end
  else
    wipe(db)
    -- Never broadcast clear|* (remote wipe-all rejected by peers)
  end
  GR:SendMessage("WANTED_CHANGED")
  Wanted:Refresh()
end

function Wanted:GetSorted()
  local db = EnsureDB()
  local list = {}
  for name, e in pairs(db) do
    list[#list + 1] = { name = name, count = e.count or 0, lastVictim = e.lastVictim, lastZone = e.lastZone, lastTime = e.lastTime }
  end
  table.sort(list, function(a, b)
    if a.count == b.count then
      return U.ShortName(a.name) < U.ShortName(b.name)
    end
    return a.count > b.count
  end)
  return list
end

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "AngryMurlocsWantedFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(460, 340)
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.wanted = GR.db.frames.wanted or {}
  U.MakeMovable(frame, {
    getPoint = function() return GR.db.frames.wanted.point end,
    setPoint = function(pt) GR.db.frames.wanted.point = pt end,
    defaultFn = function(f) f:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end,
  })
  frame:Hide()
  tinsert(UISpecialFrames, "AngryMurlocsWantedFrame")

  frame.TitleText:SetText("Wanted")

  local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 16, -32)
  sub:SetText(U.L("WANTED_SUB"))

  local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", 16, -52)
  header:SetText(string.format("%-16s  %5s  %-14s  %s", U.L("WANTED_COL_KILLER"), U.L("WANTED_COL_KILLS"), U.L("WANTED_COL_VICTIM"), U.L("ZONE")))

  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(420, ROW_H)
    row:SetPoint("TOPLEFT", 16, -56 - i * ROW_H)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetAllPoints()
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
      if self.killer then
        Wanted:Clear(self.killer, true)
      end
    end)
    row:SetScript("OnEnter", function(self)
      if not self.killer then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(U.ShortName(self.killer), 1, 0.2, 0.2)
      GameTooltip:AddLine(U.L("WANTED_CLICK_CLEAR"), 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
  end

  local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearBtn:SetSize(120, 22)
  clearBtn:SetPoint("BOTTOMLEFT", 12, 12)
  clearBtn:SetText(U.L("WANTED_CLEAR_ALL"))
  clearBtn:SetScript("OnClick", function()
    Wanted:Clear(nil, true)
  end)

  local closeHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  closeHint:SetPoint("BOTTOMRIGHT", -16, 16)
  closeHint:SetText(U.L("WANTED_HINT"))

  return frame
end

function Wanted:Refresh()
  if not frame or not frame:IsShown() then return end
  local list = Wanted:GetSorted()
  for i = 1, NUM_ROWS do
    local e = list[i]
    if e then
      rows[i].killer = e.name
      rows[i].text:SetText(string.format(
        "%-16s  %5d  %-14s  %s",
        U.ShortName(e.name):sub(1, 16),
        e.count,
        (e.lastVictim or "-"):sub(1, 14),
        (e.lastZone or "-"):sub(1, 18)
      ))
      rows[i]:Show()
    else
      rows[i].killer = nil
      rows[i]:Hide()
    end
  end
end

function Wanted:Toggle()
  EnsureFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    Wanted:Refresh()
  end
end

local pendingMinimapUpdate = false

local function MinimapRadius()
  local w = (Minimap and Minimap.GetWidth and Minimap:GetWidth()) or 140
  return (w / 2) + 5
end

local function UpdateMinimapButton()
  if not minimapBtn or not Minimap then return end
  if InCombatLockdown and InCombatLockdown() then
    pendingMinimapUpdate = true
    return
  end
  pendingMinimapUpdate = false
  local angle = (GR.db.minimap and GR.db.minimap.angle) or 200
  local rad = math.rad(angle)
  local r = MinimapRadius()
  -- Only SetPoint — never SetParent/Strata/Level here (Forbidden on Forever)
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function EnsureMinimapButton()
  if minimapBtn then
    UpdateMinimapButton()
    return
  end
  if not Minimap then
    C_Timer.After(1, EnsureMinimapButton)
    return
  end

  -- Parent once: Backdrop preferred, else UIParent (avoid Minimap secure reparent)
  local parent = (MinimapBackdrop and MinimapBackdrop) or UIParent
  minimapBtn = CreateFrame("Button", "AngryMurlocsWantedMinimapButton", parent)
  minimapBtn:SetSize(31, 31)
  minimapBtn:SetFrameStrata("MEDIUM")
  minimapBtn:SetFrameLevel(8)
  minimapBtn:RegisterForClicks("AnyUp")
  minimapBtn:RegisterForDrag("LeftButton")
  minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- LibDBIcon layout: icon inset + TrackingBorder at TOPLEFT (0,0)
  local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  minimapBtn.icon = icon

  local border = minimapBtn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  minimapBtn:SetScript("OnClick", function()
    Wanted:Toggle()
  end)
  minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(U.L("WANTED_MINIMAP_TIP"), 1, 0.2, 0.2)
    GameTooltip:Show()
  end)
  minimapBtn:SetScript("OnLeave", GameTooltip_Hide)

  minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      if not Minimap then return end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
      GR.db.minimap = GR.db.minimap or {}
      GR.db.minimap.angle = angle
      UpdateMinimapButton()
    end)
  end)
  minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  UpdateMinimapButton()
  minimapBtn:Show()

  C_Timer.After(2, UpdateMinimapButton)
end

function Wanted:OnEnable()
  EnsureDB()
  C_Timer.After(0.5, EnsureMinimapButton)

  local combat = CreateFrame("Frame")
  U.SafeRegisterEvent(combat, "PLAYER_REGEN_ENABLED")
  combat:SetScript("OnEvent", function()
    if pendingMinimapUpdate then
      UpdateMinimapButton()
    end
  end)

  GR:RegisterMessage("WANTED_UPDATE", function(_, sender, data)
    if not data then return end
    if data.action == "add" and data.killer and data.killer ~= "" then
      local victim = data.victim or sender
      if not sender or string.lower(U.ShortName(victim)) ~= string.lower(U.ShortName(sender)) then
        return
      end
      Wanted:AddKill(data.killer, victim, data.zone or "", false)
    elseif data.action == "clear" and data.killer and data.killer ~= "" and data.killer ~= "*" then
      Wanted:Clear(data.killer, false)
    end
  end)

  GR:RegisterMessage("WANTED_CHANGED", function()
    if frame and frame:IsShown() then
      Wanted:Refresh()
    end
  end)
end
