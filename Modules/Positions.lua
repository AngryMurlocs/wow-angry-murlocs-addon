local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Positions = GR:NewModule("Positions")

local MOVE_DELTA = 0.005
local HEARTBEAT = 25
local STALE = 60
local TICK_MOVING = 2.5

local cache = {}
local lastSent = { mapId = nil, x = nil, y = nil, t = 0 }
local ticker = nil
local movingTicker = nil
local cachedZoneMapId = nil

local function InvalidateZoneMapCache()
  cachedZoneMapId = nil
end

function Positions:GetCache()
  return cache
end

function Positions:Get(name)
  return cache[name]
end

local function ClearStale()
  if not next(cache) then return end
  local now = U.Now()
  for name, data in pairs(cache) do
    if now - (data.time or 0) > STALE then
      cache[name] = nil
      GR:SendMessage("POS_REMOVED", name)
    end
  end
end

local function SharingPosition()
  return GR.db and GR.db.privacy.sharePosition
      and IsInGuild and IsInGuild()
end

local function StopHeartbeat()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function EnsureHeartbeat()
  if ticker then return end
  if not SharingPosition() and not next(cache) then return end
  ticker = C_Timer.NewTicker(HEARTBEAT, function()
    if SharingPosition() then
      Positions:Broadcast(false)
    end
    ClearStale()
    if not SharingPosition() and not next(cache) then
      StopHeartbeat()
    end
  end)
end

local function ShouldSuppressPos()
  local privacy = GR.db and GR.db.privacy
  if privacy and privacy.suppressInCombat ~= false and UnitAffectingCombat("player") then
    return true
  end
  local _, instanceType = IsInInstance()
  if privacy and privacy.suppressInInstance
      and (instanceType == "party" or instanceType == "raid") then
    return true
  end
  if privacy and privacy.suppressInBg ~= false
      and (instanceType == "pvp" or instanceType == "arena") then
    return true
  end
  return false
end

local function ResolveZoneMapId()
  if cachedZoneMapId then
    local pos = C_Map.GetPlayerMapPosition(cachedZoneMapId, "player")
    if pos then
      local x, y = pos:GetXY()
      if x and y and not (x == 0 and y == 0) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return cachedZoneMapId
      end
    end
    cachedZoneMapId = nil
  end

  local mapId = C_Map.GetBestMapForUnit("player")
  if not mapId then return end
  -- Prefer zone map over continent (1414 Kalimdor / 1415 EK hide zone detail)
  if C_Map.GetMapInfo then
    local info = C_Map.GetMapInfo(mapId)
    local mapType = info and info.mapType
    local isContinent = mapType == 2 or (Enum and Enum.UIMapType and mapType == Enum.UIMapType.Continent)
    if isContinent and C_Map.GetMapChildrenInfo then
      local children = C_Map.GetMapChildrenInfo(mapId, Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3, true)
      if children then
        for i = 1, #children do
          local childId = children[i].mapID
          local cpos = C_Map.GetPlayerMapPosition(childId, "player")
          if cpos then
            local cx, cy = cpos:GetXY()
            if cx and cy and not (cx == 0 and cy == 0) and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
              mapId = childId
              break
            end
          end
        end
      end
    end
  end
  cachedZoneMapId = mapId
  return mapId
end

local function ReadLocalPos()
  if not C_Map or not C_Map.GetBestMapForUnit then return end
  local mapId = ResolveZoneMapId()
  if not mapId then return end
  local pos = C_Map.GetPlayerMapPosition(mapId, "player")
  if not pos then return end
  local x, y = pos:GetXY()
  if not x or not y then return end
  -- Instance / no coords
  if x == 0 and y == 0 then return end
  local zone = GetZoneText and GetZoneText() or ""
  local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false
  return mapId, x, y, zone, dead
end

local function ShouldSend(mapId, x, y)
  local now = U.Now()
  if now - lastSent.t >= HEARTBEAT then
    return true
  end
  if lastSent.mapId ~= mapId then
    return true
  end
  if not lastSent.x or not lastSent.y then
    return true
  end
  local dx = math.abs(x - lastSent.x)
  local dy = math.abs(y - lastSent.y)
  return (dx >= MOVE_DELTA) or (dy >= MOVE_DELTA)
end

function Positions:Broadcast(force)
  local db = GR.db
  if not db or not db.privacy.sharePosition then return end
  if not IsInGuild() then return end
  if ShouldSuppressPos() then return end

  local mapId, x, y, zone, dead = ReadLocalPos()
  if not mapId then return end

  if not force and not ShouldSend(mapId, x, y) then
    return
  end

  x = U.Round(x, 4)
  y = U.Round(y, 4)
  -- The dead flag belongs to the death category, not to position sharing.
  dead = dead and db.privacy.shareDeath and true or false
  local level = UnitLevel("player") or 0
  local payload = string.format(
    "POS|%d|%.4f|%.4f|%s|%d|%s|%d",
    mapId,
    x,
    y,
    (zone or ""):gsub("|", ""),
    dead and 1 or 0,
    U.PlayerClassFile(),
    level
  )
  Comm:Send(payload, "pos", "pos")
  lastSent.mapId = mapId
  lastSent.x = x
  lastSent.y = y
  lastSent.t = U.Now()
end

local function StartMovingTicker()
  if not SharingPosition() then return end
  if ShouldSuppressPos() then return end
  if movingTicker then return end
  movingTicker = C_Timer.NewTicker(TICK_MOVING, function()
    Positions:Broadcast(false)
  end)
end

local function StopMovingTicker()
  if movingTicker then
    movingTicker:Cancel()
    movingTicker = nil
  end
end

local function ResumeAfterSuppress()
  StopMovingTicker()
  if ShouldSuppressPos() then return end
  Positions:Broadcast(true)
  if IsPlayerMoving and IsPlayerMoving() then
    StartMovingTicker()
  end
end

function Positions:OnEnable()
  if self.enabled then return end
  self.enabled = true

  GR:BindMessage(self, "POS_UPDATE", function(_, sender, data)
    -- Never cache own position (map shows player arrow only)
    if not sender or U.IsSelfName(sender) then return end
    cache[sender] = data
    EnsureHeartbeat()
    GR:SendMessage("POS_CACHE_CHANGED", sender, data)
  end)

  GR:BindMessage(self, "GUILD_CHANGED", function()
    wipe(cache)
    StopMovingTicker()
    if not SharingPosition() then StopHeartbeat() end
    GR:SendMessage("POS_CACHE_CLEARED")
  end)

  GR:BindMessage(self, "SHARE_POS_CHANGED", function()
    if SharingPosition() then
      EnsureHeartbeat()
      Positions:Broadcast(true)
    else
      StopMovingTicker()
      if not next(cache) then StopHeartbeat() end
    end
  end)

  local f = CreateFrame("Frame")
  self._eventFrame = f
  U.SafeRegisterEvent(f, "PLAYER_STARTED_MOVING")
  U.SafeRegisterEvent(f, "PLAYER_STOPPED_MOVING")
  U.SafeRegisterEvent(f, "ZONE_CHANGED_NEW_AREA")
  U.SafeRegisterEvent(f, "PLAYER_ENTERING_WORLD")
  U.SafeRegisterEvent(f, "PLAYER_DEAD")
  U.SafeRegisterEvent(f, "PLAYER_UNGHOST")
  U.SafeRegisterEvent(f, "PLAYER_REGEN_DISABLED")
  U.SafeRegisterEvent(f, "PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      StopMovingTicker()
      return
    end

    if event == "PLAYER_REGEN_ENABLED" then
      ResumeAfterSuppress()
      return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
      InvalidateZoneMapCache()
      if ShouldSuppressPos() then
        StopMovingTicker()
      else
        ResumeAfterSuppress()
      end
      return
    end

    if event == "PLAYER_STARTED_MOVING" then
      if not SharingPosition() or ShouldSuppressPos() then
        StopMovingTicker()
        return
      end
      StartMovingTicker()
      Positions:Broadcast(false)
    elseif event == "PLAYER_STOPPED_MOVING" then
      StopMovingTicker()
      Positions:Broadcast(true)
    elseif (event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST") and not GR.db.privacy.shareDeath then
      -- An immediate update at death time would reveal the death; heartbeat continues.
      return
    else
      Positions:Broadcast(true)
    end
  end)

  EnsureHeartbeat()

  C_Timer.After(3, function()
    if not Positions.enabled then return end
    if SharingPosition() then
      EnsureHeartbeat()
      Positions:Broadcast(true)
    end
  end)
end

function Positions:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  GR:UnbindMessages(self)
  GR:ReleaseEventFrame(self._eventFrame)
  self._eventFrame = nil
  StopMovingTicker()
  StopHeartbeat()
end
