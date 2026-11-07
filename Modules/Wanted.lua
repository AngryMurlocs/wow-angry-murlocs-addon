local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Wanted = GR:NewModule("Wanted")

local frame
local scrollChild
local rows = {}
local minimapBtn
local NUM_ROWS = 40
local ROW_H = 18
local STALE_SEC = 30 * 60
local SEND_CD = 60
local ALERT_CD = 20

local sendCd = {}   -- targetKey -> GetTime
local alertCd = {}  -- targetKey -> GetTime

local function EnsureDB()
  local scope = U.GetScopeDB()
  if scope then
    return scope.wanted
  end
  GR.db.wanted = GR.db.wanted or {}
  return GR.db.wanted
end

local function NormalizeKiller(name)
  if not name or name == "" then return nil end
  return U.NormalizeName(name)
end

local function PlayerZone()
  local z = GetZoneText and GetZoneText() or ""
  if z == "" and GetRealZoneText then
    z = GetRealZoneText() or ""
  end
  return U.SanitizeText(z, 48)
end

local function IsStale(entry)
  local t = entry and entry.lastSeenTime or 0
  if not t or t <= 0 then return false end
  return (U.WallTime() - t) > STALE_SEC
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
  entry.lastTime = U.WallTime()
  GR:SendMessage("WANTED_CHANGED")
  if frame and frame:IsShown() then
    Wanted:Refresh()
  end
end

function Wanted:ApplySighting(target, zone, reporter, ts, fromRemote)
  local key = NormalizeKiller(target)
  if not key then return end
  local db = EnsureDB()
  local entry = db[key]
  if not entry then
    -- Sightings only for existing Wanted entries
    return false
  end
  ts = tonumber(ts) or U.WallTime()
  -- Prefer newer wall timestamps; ignore clearly older
  if entry.lastSeenTime and entry.lastSeenTime > ts then
    return false
  end
  entry.lastSeenTime = ts
  entry.lastSeenZone = zone or ""
  entry.lastSeenBy = U.NormalizeName(reporter or "")
  GR:SendMessage("WANTED_CHANGED")
  if frame and frame:IsShown() then
    Wanted:Refresh()
  end
  return true
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
  end
  GR:SendMessage("WANTED_CHANGED")
  Wanted:Refresh()
end

function Wanted:GetSorted()
  local db = EnsureDB()
  local list = {}
  for name, e in pairs(db) do
    list[#list + 1] = {
      name = name,
      count = e.count or 0,
      lastVictim = e.lastVictim,
      lastZone = e.lastZone,
      lastTime = e.lastTime,
      lastSeenTime = e.lastSeenTime,
      lastSeenZone = e.lastSeenZone,
      lastSeenBy = e.lastSeenBy,
      stale = IsStale(e),
    }
  end
  table.sort(list, function(a, b)
    if a.count == b.count then
      return U.ShortName(a.name) < U.ShortName(b.name)
    end
    return a.count > b.count
  end)
  return list
end

local function FormatSeenAge(ts)
  if not ts or ts <= 0 then return "-" end
  local age = U.WallTime() - ts
  if age < 0 then age = 0 end
  if age < 60 then
    return string.format(U.L("AGO"), math.floor(age))
  elseif age < 3600 then
    return string.format(U.L("AGO_MIN"), math.floor(age / 60))
  else
    return string.format(U.L("AGO_HR"), math.floor(age / 3600))
  end
end

local function EnsureFrame()
  if frame then return frame end

  frame = CreateFrame("Frame", "AngryMurlocsWantedFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(640, 420)
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
  header:SetText(string.format(
    "%-14s %5s %-10s %-12s %-12s %s",
    U.L("WANTED_COL_KILLER"),
    U.L("WANTED_COL_KILLS"),
    U.L("WANTED_COL_SEEN"),
    U.L("WANTED_COL_SEEN_ZONE"),
    U.L("WANTED_COL_SEEN_BY"),
    U.L("WANTED_COL_VICTIM")
  ))

  local scroll = CreateFrame("ScrollFrame", "AngryMurlocsWantedScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -72)
  scroll:SetPoint("BOTTOMRIGHT", -32, 40)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(580, NUM_ROWS * ROW_H)
  scroll:SetScrollChild(scrollChild)

  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(560, ROW_H)
    row:SetPoint("TOPLEFT", 4, -((i - 1) * ROW_H))
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetAllPoints()
    row.text:SetJustifyH("LEFT")
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      if not self.killer then return end
      if IsShiftKeyDown and IsShiftKeyDown() then
        Wanted:Clear(self.killer, true)
      end
    end)
    row:SetScript("OnEnter", function(self)
      if not self.killer then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.killer, 1, 0.2, 0.2)
      if self.seenBy and self.seenBy ~= "" then
        GameTooltip:AddLine(U.L("WANTED_COL_SEEN_BY") .. ": " .. self.seenBy, 0.9, 0.9, 0.9)
      end
      if self.seenZone and self.seenZone ~= "" then
        GameTooltip:AddLine(U.L("ZONE") .. ": " .. self.seenZone, 0.8, 0.8, 0.8)
      end
      if self.stale then
        GameTooltip:AddLine(U.L("WANTED_STALE"), 1, 0.6, 0.2)
      end
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
  scrollChild:SetHeight(math.max(#list, 1) * ROW_H)
  for i = 1, NUM_ROWS do
    local e = list[i]
    if e then
      rows[i].killer = e.name
      rows[i].seenBy = e.lastSeenBy
      rows[i].seenZone = e.lastSeenZone
      rows[i].stale = e.stale
      local seen = FormatSeenAge(e.lastSeenTime)
      if e.stale and e.lastSeenTime and e.lastSeenTime > 0 then
        seen = seen .. "*"
      end
      rows[i].text:SetText(string.format(
        "%-14s %5d %-10s %-12s %-12s %s",
        U.ShortName(e.name):sub(1, 14),
        e.count,
        seen:sub(1, 10),
        (e.lastSeenZone or "-"):sub(1, 12),
        U.ShortName(e.lastSeenBy or "-"):sub(1, 12),
        (e.lastVictim or "-"):sub(1, 12)
      ))
      if e.stale then
        rows[i].text:SetTextColor(0.7, 0.55, 0.35)
      else
        rows[i].text:SetTextColor(1, 1, 1)
      end
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

local function MaybeAlert(targetKey, zone, reporter)
  local ui = GR.db.wantedUI
  if ui and ui.showSightAlerts == false then return end
  local now = U.Now()
  local last = alertCd[targetKey] or 0
  if (now - last) < ALERT_CD then return end
  alertCd[targetKey] = now
  U.Print(string.format(
    U.L("WANTED_SIGHT_ALERT"),
    U.ShortName(targetKey),
    zone or "?",
    U.ShortName(reporter or "?")
  ))
end

local function OnTargetChanged()
  if not UnitExists or not UnitExists("target") then return end
  if not UnitIsPlayer or not UnitIsPlayer("target") then return end

  local name, realm = UnitName("target")
  if not name or name == "" then return end
  if UnitFullName then
    local n, r = UnitFullName("target")
    if n then
      name = n
      realm = r
    end
  end
  local full
  if realm and realm ~= "" then
    full = name .. "-" .. realm
  else
    full = U.NormalizeName(name)
  end
  local key = NormalizeKiller(full)
  if not key then return end

  local db = EnsureDB()
  if not db[key] then return end

  local zone = PlayerZone()
  local me = U.NormalizeName(U.PlayerName())
  local nowSession = U.Now()
  local wall = U.WallTime()

  -- Local apply (does not bump kill count)
  Wanted:ApplySighting(key, zone, me, wall, false)

  local lastSend = sendCd[key] or 0
  local canSend = (nowSession - lastSend) >= SEND_CD
  local share = GR.db.privacy and GR.db.privacy.shareSightings ~= false

  if canSend and share and IsInGuild and IsInGuild() then
    sendCd[key] = nowSession
    local payload = string.format(
      "SIGHT|%s|%s|%d",
      U.SanitizeText(key, 48),
      U.SanitizeText(zone, 48),
      wall
    )
    Comm:Send(payload)
  end

  MaybeAlert(key, zone, me)
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

  local parent = (MinimapBackdrop and MinimapBackdrop) or UIParent
  minimapBtn = CreateFrame("Button", "AngryMurlocsWantedMinimapButton", parent)
  minimapBtn:SetSize(31, 31)
  minimapBtn:SetFrameStrata("MEDIUM")
  minimapBtn:SetFrameLevel(8)
  minimapBtn:RegisterForClicks("AnyUp")
  minimapBtn:RegisterForDrag("LeftButton")
  minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

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

  local targetFrame = CreateFrame("Frame")
  U.SafeRegisterEvent(targetFrame, "PLAYER_TARGET_CHANGED")
  targetFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
      OnTargetChanged()
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

  GR:RegisterMessage("SIGHT_UPDATE", function(_, sender, data)
    if not data or not data.target then return end
    -- Never rebroadcast received sightings
    local ok = Wanted:ApplySighting(data.target, data.zone, sender, data.ts, true)
    if ok then
      MaybeAlert(data.target, data.zone, sender)
    end
  end)

  GR:RegisterMessage("WANTED_CHANGED", function()
    if frame and frame:IsShown() then
      Wanted:Refresh()
    end
  end)

  GR:RegisterMessage("GUILD_UPDATE", function()
    -- Scope switches with guild; refresh UI
    if frame and frame:IsShown() then
      Wanted:Refresh()
    end
  end)
end
