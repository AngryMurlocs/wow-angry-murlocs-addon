local GR = AngryMurlocs
local U = GR.Util

local MapPins = GR:NewModule("MapPins")

local pool = {}
local active = {}
local canvasHooked = false

local PIN_BASE_BODY = "Interface\\AddOns\\AngryMurlocs\\Media\\Pins\\"
local PIN_BASE_HEADS = "Interface\\AddOns\\AngryMurlocs\\Media\\PinsHeads\\"
local CIRCLE_TEX = "Interface\\AddOns\\AngryMurlocs\\Media\\circle"
local GLOW_SCALE = 1.32 -- silhouette bloom behind icon
local RING_INNER_FRAC = 0.68 -- class fill vs gold outer (thicker rim)
local GOLD_R, GOLD_G, GOLD_B = 1, 0.92, 0.12 -- brighter gold for contrast
local DEFAULT_SIZE = 18
local MIN_SIZE = 8
local MAX_SIZE = 24
local NEAR_SELF = 0.01
-- Match Positions.STALE: full alpha until FADE_START, then fade to FADE_MIN by STALE_SEC.
MapPins.STALE_SEC = 60
MapPins.FADE_START_SEC = 45
MapPins.FADE_MIN = 0.25
local BASE_LEVEL = 100
local HOVER_LEVEL = 200
local CLUSTER_GAP_PX = 2 -- screen pixels between pin edges
local CLUSTER_SPAN = 2 -- pile diameter, in pin widths; longer chains stay put
local PI = 3.141592653589793
local fadeTicker

local CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
  "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

-- Opaque-bbox TexCoords (left, right, top, bottom) so class art fills the pin equally.
-- Heads: alpha bounds of Media/PinsHeads, one pixel of margin where it fits.
-- Body: alpha bounds of Media/Pins plus ~5% pad.
local HEAD_UV = {
  DEATHKNIGHT = { 0.0234, 0.9922, 0.0000, 1.0000 },
  DEMONHUNTER = { 0.0234, 0.9922, 0.0000, 1.0000 },
  DRUID       = { 0.0234, 0.9922, 0.0000, 1.0000 },
  EVOKER      = { 0.0234, 0.9922, 0.0000, 1.0000 },
  HUNTER      = { 0.0234, 0.9922, 0.0000, 1.0000 },
  MAGE        = { 0.0234, 0.9922, 0.0000, 1.0000 },
  MONK        = { 0.0234, 0.9922, 0.0000, 1.0000 },
  PALADIN     = { 0.0234, 0.9922, 0.0000, 1.0000 },
  PRIEST      = { 0.0234, 0.9922, 0.0000, 1.0000 },
  ROGUE       = { 0.0234, 0.9922, 0.0000, 1.0000 },
  SHAMAN      = { 0.0234, 0.9922, 0.0000, 1.0000 },
  WARLOCK     = { 0.0234, 0.9922, 0.0000, 1.0000 },
  WARRIOR     = { 0.0234, 0.9922, 0.0000, 1.0000 },
}

local BODY_UV = {
  DEATHKNIGHT = { 0.1094, 0.8438, 0.0000, 1.0000 },
  DEMONHUNTER = { 0.1258, 0.8430, 0.0008, 0.9992 },
  DRUID       = { 0.1102, 0.8430, 0.0008, 0.9992 },
  EVOKER      = { 0.1414, 0.8430, 0.0008, 0.9992 },
  HUNTER      = { 0.1109, 0.8422, 0.0172, 0.9984 },
  MAGE        = { 0.1258, 0.8430, 0.0008, 0.9992 },
  MONK        = { 0.1102, 0.8273, 0.0008, 0.9992 },
  PALADIN     = { 0.1266, 0.8422, 0.0172, 0.9984 },
  PRIEST      = { 0.1398, 0.8445, 0.0000, 1.0000 },
  ROGUE       = { 0.1258, 0.8430, 0.0008, 0.9992 },
  SHAMAN      = { 0.1414, 0.8430, 0.0008, 0.9992 },
  WARLOCK     = { 0.1250, 0.8438, 0.0000, 1.0000 },
  WARRIOR     = { 0.1102, 0.8430, 0.0008, 0.9992 },
}

local function PinStyle()
  local s = GR.db and GR.db.map and GR.db.map.pinStyle
  if s == "body" or s == "heads" or s == "rings" then
    return s
  end
  return "heads"
end

local function ClassPinPath(base, classFile)
  if classFile then
    for i = 1, #CLASSES do
      if CLASSES[i] == classFile then
        return base .. classFile
      end
    end
  end
  return base .. "WARRIOR"
end

local function ClassUV(style, classFile)
  local map = (style == "body") and BODY_UV or HEAD_UV
  local uv = classFile and map[classFile]
  if uv then return uv[1], uv[2], uv[3], uv[4] end
  uv = map.WARRIOR
  if uv then return uv[1], uv[2], uv[3], uv[4] end
  return 0, 1, 0, 1
end

--- Slot offsets for a stacked group. oy is up (WoW point offset). step is center distance.
function MapPins.ClusterSlots(count, step)
  count = math.floor(tonumber(count) or 0)
  step = tonumber(step) or 0
  if step < 0 then step = 0 end
  local slots = {}
  if count < 1 then return slots end
  if count == 1 then
    slots[1] = { 0, 0 }
  elseif count == 2 then
    slots[1] = { -step / 2, 0 }
    slots[2] = { step / 2, 0 }
  elseif count == 3 then
    slots[1] = { 0, step * 0.55 }
    slots[2] = { -step / 2, -step * 0.4 }
    slots[3] = { step / 2, -step * 0.4 }
  elseif count == 4 then
    local h = step / 2
    slots[1] = { -h, h }
    slots[2] = { h, h }
    slots[3] = { -h, -h }
    slots[4] = { h, -h }
  elseif count == 5 then
    local h = step / 2
    slots[1] = { -h, h }
    slots[2] = { h, h }
    slots[3] = { -step, -h }
    slots[4] = { 0, -h }
    slots[5] = { step, -h }
  else
    slots[1] = { 0, 0 }
    local nRing = count - 1
    local denom = 2 * math.sin(PI / nRing)
    local radius = step
    if denom > 0 then
      local need = step / denom
      if need > radius then radius = need end
    end
    for i = 0, nRing - 1 do
      local ang = (PI / 2) - i * (2 * PI / nRing)
      slots[i + 2] = { radius * math.cos(ang), radius * math.sin(ang) }
    end
  end
  return slots
end

local function PointDist2(a, b)
  local dx = (a.x or 0) - (b.x or 0)
  local dy = (a.y or 0) - (b.y or 0)
  return dx * dx + dy * dy
end

--- Group a pile, not a chain. Centers closer than pinSize join only while the
--- whole pile stays within CLUSTER_SPAN pin-widths. Names sort into stable slots.
--- points: { { name, x, y } } with y positive south.
--- Returns name -> { ox, oy, cx, cy }. Anchor from canvas TOPLEFT: (cx + ox, -cy + oy).
function MapPins.ClusterOffsets(points, pinSize, gap)
  local n = points and #points or 0
  local parent = {}
  local members = {}
  for i = 1, n do
    parent[i] = i
    members[i] = { i }
  end
  local function find(i)
    while parent[i] ~= i do
      parent[i] = parent[parent[i]]
      i = parent[i]
    end
    return i
  end
  local limit = tonumber(pinSize) or 0
  if limit < 0 then limit = 0 end
  local limit2 = limit * limit
  local span = limit * CLUSTER_SPAN
  local span2 = span * span
  for i = 1, n do
    for j = i + 1, n do
      if PointDist2(points[i], points[j]) < limit2 then
        local ra, rb = find(i), find(j)
        if ra ~= rb then
          local wide = false
          local ga, gb = members[ra], members[rb]
          for a = 1, #ga do
            for b = 1, #gb do
              if PointDist2(points[ga[a]], points[gb[b]]) > span2 then
                wide = true
                break
              end
            end
            if wide then break end
          end
          if not wide then
            parent[rb] = ra
            for b = 1, #gb do
              ga[#ga + 1] = gb[b]
            end
            members[rb] = nil
          end
        end
      end
    end
  end
  local groups = {}
  for i = 1, n do
    local r = find(i)
    local g = groups[r]
    if not g then
      g = {}
      groups[r] = g
    end
    g[#g + 1] = points[i]
  end
  local step = limit + (tonumber(gap) or 0)
  if step < 0 then step = 0 end
  local out = {}
  for _, g in pairs(groups) do
    table.sort(g, function(a, b)
      return tostring(a.name) < tostring(b.name)
    end)
    local sx, sy = 0, 0
    for i = 1, #g do
      sx = sx + (g[i].x or 0)
      sy = sy + (g[i].y or 0)
    end
    local cx, cy = sx / #g, sy / #g
    local slots = MapPins.ClusterSlots(#g, step)
    for i = 1, #g do
      local s = slots[i] or { 0, 0 }
      out[g[i].name] = { ox = s[1], oy = s[2], cx = cx, cy = cy }
    end
  end
  return out
end

--- Pure fade curve for tests: 1 until FADE_START, linear down to FADE_MIN at STALE.
function MapPins.FadeFactor(ageSec)
  ageSec = tonumber(ageSec) or 0
  if ageSec < 0 then ageSec = 0 end
  if ageSec <= MapPins.FADE_START_SEC then return 1 end
  if ageSec >= MapPins.STALE_SEC then return MapPins.FADE_MIN end
  local t = (ageSec - MapPins.FADE_START_SEC) / (MapPins.STALE_SEC - MapPins.FADE_START_SEC)
  return 1 - t * (1 - MapPins.FADE_MIN)
end

local function PinAge(data)
  return U.Now() - (data and data.time or U.Now())
end

local function PinFreshKey(ageSec)
  if ageSec < MapPins.FADE_START_SEC then return "PIN_FRESH" end
  if ageSec < MapPins.STALE_SEC then return "PIN_AGING" end
  return "PIN_EXPIRING"
end

local function FormatPinAge(ageSec)
  ageSec = math.max(0, math.floor(ageSec or 0))
  if ageSec < 60 then
    return string.format(U.L("AGO"), ageSec)
  end
  return string.format(U.L("AGO_MIN"), math.floor(ageSec / 60))
end

local function BindPinArt(pin, classFile, style)
  local key = (style or "") .. "|" .. tostring(classFile or "")
  if pin._artKey == key then return end
  pin._artKey = key
  local r, g, b = U.ClassColor(classFile)

  if style == "rings" then
    if pin.glow then
      pin.glow:SetTexture(CIRCLE_TEX)
      pin.glow:SetTexCoord(0, 1, 0, 1)
      if pin.glow.SetBlendMode then
        pcall(pin.glow.SetBlendMode, pin.glow, "BLEND")
      end
      pin.glow:Show()
    end
    pin.tex:SetTexture(CIRCLE_TEX)
    pin.tex:SetTexCoord(0, 1, 0, 1)
    pin._fillR, pin._fillG, pin._fillB = r * 0.78, g * 0.78, b * 0.78
    pin._glowR, pin._glowG, pin._glowB = GOLD_R, GOLD_G, GOLD_B
    pin._rings = true
    return
  end

  local base = (style == "body") and PIN_BASE_BODY or PIN_BASE_HEADS
  local path = ClassPinPath(base, classFile)
  local uL, uR, uT, uB = ClassUV(style, classFile)
  pin.tex:SetTexture(path)
  pin.tex:SetTexCoord(uL, uR, uT, uB)
  pin._fillR, pin._fillG, pin._fillB = 1, 1, 1
  if pin.glow then
    -- Same TGA + UV as icon → glow follows silhouette
    pin.glow:SetTexture(path)
    pin.glow:SetTexCoord(uL, uR, uT, uB)
    if pin.glow.SetBlendMode then
      pcall(pin.glow.SetBlendMode, pin.glow, "ADD")
    end
    pin.glow:Show()
  end
  pin._glowR, pin._glowG, pin._glowB = r, g, b
  pin._rings = false
end

local function ApplyPinFade(pin, dead, ageSec)
  local fade = MapPins.FadeFactor(ageSec or 0)
  local a = (dead and 0.45 or 1) * fade
  local fr = pin._fillR or 1
  local fg = pin._fillG or 1
  local fb = pin._fillB or 1
  pin.tex:SetVertexColor(fr, fg, fb, a)
  if pin.glow then
    local ga
    if pin._rings then
      ga = (dead and 0.5 or 1) * fade
    else
      ga = (dead and 0.25 or 0.65) * fade
    end
    pin.glow:SetVertexColor(pin._glowR or 1, pin._glowG or 1, pin._glowB or 1, ga)
  end
end

local function ApplyPinArt(pin, classFile, dead, ageSec)
  local style = PinStyle()
  BindPinArt(pin, classFile, style)
  ApplyPinFade(pin, dead, ageSec)
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

  -- Glow / gold rim layer (texture + blend set in ApplyPinArt)
  local glow = pin:CreateTexture(nil, "BACKGROUND")
  glow:SetSize(DEFAULT_SIZE * GLOW_SCALE, DEFAULT_SIZE * GLOW_SCALE)
  glow:SetPoint("CENTER")
  glow:SetTexture(CIRCLE_TEX)
  glow:SetVertexColor(0.8, 0.8, 0.8, 0.65)
  pin.glow = glow

  local tex = pin:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  tex:SetTexture(CIRCLE_TEX)
  tex:SetVertexColor(1, 1, 1, 1)
  pin.tex = tex

  pin:SetScript("OnEnter", function(self)
    if not self.data then return end
    local d = self.data
    if self.baseLevel then
      self:SetFrameLevel(self.baseLevel + HOVER_LEVEL)
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = U.ClassColor(d.classFile)
    GameTooltip:AddLine(U.ShortName(self.member), r, g, b)

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
    local age = PinAge(d)
    GameTooltip:AddLine(FormatPinAge(age), 0.6, 0.6, 0.6)
    local freshen = PinFreshKey(age)
    local fr, fg, fb = 0.4, 1.0, 0.5
    if freshen == "PIN_AGING" then
      fr, fg, fb = 1.0, 0.85, 0.4
    elseif freshen == "PIN_EXPIRING" then
      fr, fg, fb = 1.0, 0.45, 0.25
    end
    GameTooltip:AddLine(U.L(freshen), fr, fg, fb)
    GameTooltip:Show()
  end)
  pin:SetScript("OnLeave", function(self)
    if self.baseLevel then
      self:SetFrameLevel(self.baseLevel)
    end
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
  pin._artKey = nil
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

local refreshPending = false
local function ScheduleRefresh()
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0.25, function()
    refreshPending = false
    if MapShown() then
      MapPins:Refresh()
    end
  end)
end

local function GetScrollContainer()
  if WorldMapFrame and WorldMapFrame.ScrollContainer then
    return WorldMapFrame.ScrollContainer
  end
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

local function GetCanvasScale()
  -- Forever / retail: scale lives on WorldMapFrame (not only ScrollContainer)
  if WorldMapFrame and WorldMapFrame.GetCanvasScale then
    local scale = WorldMapFrame:GetCanvasScale()
    if scale and scale > 0 then return scale end
  end
  local sc = GetScrollContainer()
  if sc and sc.GetCanvasScale then
    local scale = sc:GetCanvasScale()
    if scale and scale > 0 then return scale end
  end
  return 1
end

local function ClampPinSize(size)
  size = tonumber(size) or DEFAULT_SIZE
  if size < MIN_SIZE then return MIN_SIZE end
  if size > MAX_SIZE then return MAX_SIZE end
  return size
end

local function SyncPinLayers(pin, size)
  size = size or pin:GetWidth() or DEFAULT_SIZE
  if PinStyle() == "rings" then
    -- Outer gold = party size; class fill inset for thicker rim
    if pin.glow then
      pin.glow:ClearAllPoints()
      pin.glow:SetSize(size, size)
      pin.glow:SetPoint("CENTER")
    end
    if pin.tex then
      local inner = size * RING_INNER_FRAC
      pin.tex:ClearAllPoints()
      pin.tex:SetSize(inner, inner)
      pin.tex:SetPoint("CENTER")
    end
    return
  end
  if pin.tex then
    pin.tex:ClearAllPoints()
    pin.tex:SetAllPoints()
  end
  if pin.glow then
    local g = size * GLOW_SCALE
    pin.glow:ClearAllPoints()
    pin.glow:SetSize(g, g)
    pin.glow:SetPoint("CENTER")
  end
end

local function ScreenPinSize()
  -- Slider applies to all styles (heads / body / rings)
  return ClampPinSize(GR.db and GR.db.map and GR.db.map.pinSize)
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

function MapPins:SyncSizes()
  if not next(active) then return end
  local scale = GetCanvasScale()
  local size = ScreenPinSize() / scale
  for _, pin in pairs(active) do
    pin:SetScale(1)
    pin:SetSize(size, size)
    SyncPinLayers(pin, size)
  end
end

local function EnsureFadeTicker()
  if fadeTicker then return end
  if not next(active) or not MapShown() then return end
  fadeTicker = C_Timer.NewTicker(1, function()
    if not MapShown() or not next(active) then
      if fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
      end
      return
    end
    for _, pin in pairs(active) do
      if pin.data then
        ApplyPinFade(pin, pin.data.dead, PinAge(pin.data))
      end
    end
  end)
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

  local scale = GetCanvasScale()
  local size = ScreenPinSize() / scale
  local cw, ch = canvas:GetWidth(), canvas:GetHeight()
  if not cw or cw == 0 then
    ReleaseAll()
    return
  end

  local playerX, playerY = PlayerViewPos(mapId)

  local seen = {}
  local positions = GR:GetModule("Positions")
  local cache = positions and positions:GetCache() or {}
  local canvasBase = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + BASE_LEVEL

  -- Time order only sets frame level. Pile slots sort by name so they stay put.
  local order = {}
  for name, data in pairs(cache) do
    if not U.IsSelfName(name) and data.x and data.y then
      order[#order + 1] = { name = name, data = data, t = data.time or 0 }
    end
  end
  table.sort(order, function(a, b)
    if a.t == b.t then return a.name < b.name end
    return a.t < b.t
  end)

  local visible = {}
  for i = 1, #order do
    local name, data = order[i].name, order[i].data
    local px, py = ProjectToView(data.mapId, data.x, data.y, mapId)
    if px and py then
      -- Fallback: hide pins sitting on the player (ghost self / name mismatch)
      if not (playerX and playerY
          and math.abs(px - playerX) < NEAR_SELF
          and math.abs(py - playerY) < NEAR_SELF) then
        visible[#visible + 1] = { name = name, data = data, x = px * cw, y = py * ch, order = i }
      end
    end
  end
  local clustering = not GR.db.map or GR.db.map.pinClustering ~= false
  local laid
  if clustering then
    laid = MapPins.ClusterOffsets(visible, size, CLUSTER_GAP_PX / scale)
  else
    laid = {}
    for i = 1, #visible do
      local item = visible[i]
      laid[item.name] = { ox = 0, oy = 0, cx = item.x, cy = item.y }
    end
  end

  for i = 1, #visible do
    local item = visible[i]
    local name, data = item.name, item.data
    local lay = laid[name]
    seen[name] = true
    local pin = active[name]
    if not pin then
      pin = AcquirePin()
      active[name] = pin
    end
    pin:SetParent(canvas)
    pin:SetFrameStrata("HIGH")
    pin.baseLevel = canvasBase + (item.order or i)
    pin:SetFrameLevel(pin.baseLevel)
    pin:SetScale(1)
    pin:SetSize(size, size)
    SyncPinLayers(pin, size)
    pin.data = data
    pin.member = name

    ApplyPinArt(pin, data.classFile, data.dead, PinAge(data))

    local ax = lay and lay.cx or item.x
    local ay = lay and lay.cy or item.y
    local ox = lay and lay.ox or 0
    local oy = lay and lay.oy or 0
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", ax + ox, -ay + oy)
    pin:Show()
  end

  for name, pin in pairs(active) do
    if not seen[name] or U.IsSelfName(name) then
      ReleasePin(pin)
      active[name] = nil
    end
  end

  EnsureFadeTicker()
end

local function HookMap()
  if canvasHooked or not WorldMapFrame then return end
  canvasHooked = true

  WorldMapFrame:HookScript("OnShow", function()
    MapPins:Refresh()
  end)
  WorldMapFrame:HookScript("OnHide", function()
    if fadeTicker then
      fadeTicker:Cancel()
      fadeTicker = nil
    end
    ReleaseAll()
  end)

  if WorldMapFrame.OnMapChanged then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
      MapPins:Refresh()
    end)
  end

  -- Forever: scale notifications are on WorldMapFrame (Leatrix/MoveAny pattern).
  -- Refresh, not SyncSizes: pile offsets are in canvas pixels and must track zoom.
  if WorldMapFrame.OnCanvasScaleChanged then
    hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function()
      MapPins:Refresh()
    end)
  end
  WorldMapFrame:HookScript("OnSizeChanged", function()
    MapPins:Refresh()
  end)

  local sc = GetScrollContainer()
  if sc and sc.OnCanvasScaleChanged then
    hooksecurefunc(sc, "OnCanvasScaleChanged", function()
      MapPins:Refresh()
    end)
  end
end

function MapPins:OnEnable()
  if self.enabled then return end
  self.enabled = true

  DiscardPool()
  HookMap()

  GR:BindMessage(self, "POS_CACHE_CHANGED", function()
    PurgeSelfFromCache()
    if MapShown() then
      ScheduleRefresh()
    end
  end)
  GR:BindMessage(self, "POS_REMOVED", function()
    if MapShown() then
      ScheduleRefresh()
    end
  end)
  GR:BindMessage(self, "POS_CACHE_CLEARED", function()
    ReleaseAll()
  end)
  GR:BindMessage(self, "MAP_SETTINGS_CHANGED", function()
    DiscardPool()
    MapPins:Refresh()
  end)
  -- Refresh via OnShow / OnMapChanged / scale / POS_* messages (no polling ticker)
end

function MapPins:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  GR:UnbindMessages(self)
  if fadeTicker then
    fadeTicker:Cancel()
    fadeTicker = nil
  end
  ReleaseAll()
  -- WorldMapFrame hooks stay (HookScript cannot cleanly unhook); canvasHooked keeps HookMap idempotent.
end
