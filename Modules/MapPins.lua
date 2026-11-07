local GR = AngryMurlocs
local U = GR.Util

local MapPins = GR:NewModule("MapPins")

local pool = {}
local active = {}
local canvasHooked = false

local CIRCLE_TEX = "Interface\\AddOns\\AngryMurlocs\\Media\\circle"
local DEFAULT_SIZE = 8
local NEAR_SELF = 0.01

local function TintCircle(tex, r, g, b, a)
  tex:SetTexture(CIRCLE_TEX)
  tex:SetTexCoord(0, 1, 0, 1)
  tex:SetVertexColor(r, g, b, a or 1)
end

local function PlayerViewPos(viewMapId)
  if not viewMapId or not C_Map or not C_Map.GetPlayerMapPosition then return end
  local pos = C_Map.GetPlayerMapPosition(viewMapId, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if not x or not y or (x == 0 and y == 0) then return end
  return x, y
end

local function AcquirePin()
  local pin = table.remove(pool)
  if pin then
    pin:Show()
    return pin
  end

  pin = CreateFrame("Frame", nil, nil)
  pin:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
  pin:EnableMouse(true)

  local border = pin:CreateTexture(nil, "BORDER")
  border:SetAllPoints()
  TintCircle(border, 0, 0, 0, 1)
  pin.border = border

  local tex = pin:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 1, -1)
  tex:SetPoint("BOTTOMRIGHT", -1, 1)
  TintCircle(tex, 0.8, 0.8, 0.8, 1)
  pin.tex = tex

  pin:SetScript("OnEnter", function(self)
    if not self.data then return end
    local d = self.data
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = U.ClassColor(d.classFile)
    GameTooltip:AddLine(U.ShortName(self.member), r, g, b)
    local mains = GR:GetModule("Mains")
    if mains then
      local main = mains:GetMain(self.member)
      if main then
        GameTooltip:AddLine(string.format(U.L("MAIN_TOOLTIP"), U.ShortName(self.member), main), 0.6, 0.9, 1)
      end
    end

    local className = d.classFile or "?"
    if LOCALIZED_CLASS_NAMES_MALE and d.classFile and LOCALIZED_CLASS_NAMES_MALE[d.classFile] then
      className = LOCALIZED_CLASS_NAMES_MALE[d.classFile]
    end
    if d.level then
      GameTooltip:AddLine(string.format("%s %d %s", U.L("LEVEL"), d.level, className), 1, 1, 1)
    else
      GameTooltip:AddLine(U.L("CLASS") .. ": " .. className, 1, 1, 1)
    end

    if d.zone and d.zone ~= "" then
      GameTooltip:AddLine(U.L("ZONE") .. ": " .. d.zone, 0.9, 0.9, 0.9)
    end
    if d.dead then
      GameTooltip:AddLine(U.L("DEAD"), 1, 0.2, 0.2)
    end
    local age = math.floor(U.Now() - (d.time or U.Now()))
    GameTooltip:AddLine(string.format(U.L("AGO"), age), 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  pin:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return pin
end

local function ReleasePin(pin)
  pin:Hide()
  pin:ClearAllPoints()
  pin:SetParent(nil)
  pin.data = nil
  pin.member = nil
  pool[#pool + 1] = pin
end

local function PurgeSelfFromCache()
  local positions = GR:GetModule("Positions")
  local cache = positions and positions:GetCache()
  if cache then
    for name in pairs(cache) do
      if U.IsSelfName(name) then
        cache[name] = nil
      end
    end
  end
  -- Hard-release sticky self frames
  for name, pin in pairs(active) do
    if U.IsSelfName(name) then
      ReleasePin(pin)
      active[name] = nil
    end
  end
end

local function ReleaseAll()
  for name, pin in pairs(active) do
    ReleasePin(pin)
    active[name] = nil
  end
end

local function DiscardPool()
  ReleaseAll()
  wipe(pool)
end

local function MapShown()
  return WorldMapFrame and WorldMapFrame:IsShown()
end

local function GetCanvas()
  if not WorldMapFrame then return end
  if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child then
    return WorldMapFrame.ScrollContainer.Child
  end
  if WorldMapFrame.GetCanvas then
    return WorldMapFrame:GetCanvas()
  end
end

local function CurrentMapId()
  if WorldMapFrame and WorldMapFrame.GetMapID then
    return WorldMapFrame:GetMapID()
  end
end

local function ProjectToView(fromMapId, x, y, toMapId)
  if not fromMapId or not toMapId or not x or not y then return end
  if fromMapId == toMapId then return x, y end
  if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
  local ok, continentID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, fromMapId, CreateVector2D(x, y))
  if not ok or not continentID or not worldPos then return end
  local ok2, _, mapPos = pcall(C_Map.GetMapPosFromWorldPos, continentID, worldPos, toMapId)
  if not ok2 or not mapPos then return end
  local nx, ny = mapPos:GetXY()
  if not nx or not ny then return end
  if nx < -0.05 or nx > 1.05 or ny < -0.05 or ny > 1.05 then return end
  return nx, ny
end

function MapPins:Refresh()
  if not GR.db or not GR.db.map.showPins or not MapShown() then
    ReleaseAll()
    return
  end

  local canvas = GetCanvas()
  local mapId = CurrentMapId()
  if not canvas or not mapId then
    ReleaseAll()
    return
  end

  PurgeSelfFromCache()

  local size = GR.db.map.pinSize or DEFAULT_SIZE
  if size > 12 then size = 12 end
  local cw, ch = canvas:GetWidth(), canvas:GetHeight()
  if not cw or cw == 0 then return end

  local playerX, playerY = PlayerViewPos(mapId)

  local seen = {}
  local positions = GR:GetModule("Positions")
  local cache = positions and positions:GetCache() or {}

  for name, data in pairs(cache) do
    if U.IsSelfName(name) then
      -- skip (purged above)
    elseif data.x and data.y then
      local px, py = ProjectToView(data.mapId, data.x, data.y, mapId)
      if px and py then
        -- Fallback: hide pins sitting on the player (ghost self / name mismatch)
        if playerX and playerY
            and math.abs(px - playerX) < NEAR_SELF
            and math.abs(py - playerY) < NEAR_SELF then
          -- skip
        else
          seen[name] = true
          local pin = active[name]
          if not pin then
            pin = AcquirePin()
            active[name] = pin
          end
          pin:SetParent(canvas)
          pin:SetFrameStrata("HIGH")
          pin:SetFrameLevel((canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 100)
          pin:SetSize(size, size)
          pin.data = data
          pin.member = name

          local r, g, b = U.ClassColor(data.classFile)
          local a = data.dead and 0.45 or 1
          TintCircle(pin.border, 0, 0, 0, 1)
          TintCircle(pin.tex, r, g, b, a)

          pin:ClearAllPoints()
          pin:SetPoint("CENTER", canvas, "TOPLEFT", px * cw, -py * ch)
          pin:Show()
        end
      end
    end
  end

  for name, pin in pairs(active) do
    if not seen[name] or U.IsSelfName(name) then
      ReleasePin(pin)
      active[name] = nil
    end
  end
end

local function HookMap()
  if canvasHooked or not WorldMapFrame then return end
  canvasHooked = true

  WorldMapFrame:HookScript("OnShow", function()
    MapPins:Refresh()
  end)
  WorldMapFrame:HookScript("OnHide", function()
    ReleaseAll()
  end)

  if WorldMapFrame.OnMapChanged then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
      MapPins:Refresh()
    end)
  end
end

function MapPins:OnEnable()
  DiscardPool()
  HookMap()

  GR:RegisterMessage("POS_CACHE_CHANGED", function()
    PurgeSelfFromCache()
    if MapShown() then
      MapPins:Refresh()
    end
  end)
  GR:RegisterMessage("POS_REMOVED", function()
    if MapShown() then
      MapPins:Refresh()
    end
  end)
  GR:RegisterMessage("POS_CACHE_CLEARED", function()
    ReleaseAll()
  end)
  GR:RegisterMessage("MAP_SETTINGS_CHANGED", function()
    DiscardPool()
    MapPins:Refresh()
  end)
  -- Refresh via OnShow / OnMapChanged / POS_* messages (no polling ticker)
end
