-- Local Murloc yell triggers (no wire). Pairs with Core/Nerglish.lua.
local GR = AngryMurlocs
local U = GR.Util

local Mod = GR:NewModule("NerglishEvents")

local IDLE_MIN = 8 * 60
local IDLE_SPAN = 4 * 60 -- 8–12 min
local RARE_QUALITY = (Enum and Enum.ItemQuality and Enum.ItemQuality.Rare) or 3
local ACHIEVE_POINTS_MIN = 25

local rosterReady = false
local knownMembers = {}
local lastPvpKills = nil
local idleTimer

local function Now()
  return U.Now and U.Now() or (GetTime and GetTime()) or 0
end

local function React(kind, facts)
  if not GR.Nerglish or not GR.Nerglish.TryReact then return end
  GR.Nerglish.TryReact(kind, Now(), facts)
end

local function SessionPvpKills()
  if type(GetPVPSessionStats) ~= "function" then return nil end
  local ok, hk = pcall(GetPVPSessionStats)
  if not ok then return nil end
  return tonumber(hk)
end

local function SnapshotRoster()
  wipe(knownMembers)
  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    return
  end
  local n = GetNumGuildMembers() or 0
  for i = 1, n do
    local name = GetGuildRosterInfo(i)
    local key = name and U.CharKey(name)
    if key then knownMembers[key] = true end
  end
end

local function OnGuildRoster()
  if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
    return
  end
  if not rosterReady then
    SnapshotRoster()
    rosterReady = true
    return
  end
  local n = GetNumGuildMembers() or 0
  local seen = {}
  for i = 1, n do
    local name = GetGuildRosterInfo(i)
    local key = name and U.CharKey(name)
    if key then
      seen[key] = true
      if not knownMembers[key] then
        knownMembers[key] = true
        React("guild_join", { player = U.ShortName(name) })
        break
      end
    end
  end
  for key in pairs(knownMembers) do
    if not seen[key] then knownMembers[key] = nil end
  end
end

local function ItemIdFromMessage(msg)
  if type(msg) ~= "string" then return nil end
  local id = msg:match("|Hitem:(%d+)")
  return tonumber(id)
end

local function ItemQuality(itemId)
  if not itemId then return nil end
  if C_Item and type(C_Item.GetItemQualityByID) == "function" then
    local ok, q = pcall(C_Item.GetItemQualityByID, itemId)
    if ok then return tonumber(q) end
  end
  return nil
end

local function OnLoot(_, ...)
  local msg = ...
  if type(msg) ~= "string" then return end
  -- Self loot only: message usually contains player name or "You" / localized self.
  local selfName = U.ShortName(U.PlayerName())
  local lower = string.lower(msg)
  local isSelf = false
  if selfName and lower:find(string.lower(selfName), 1, true) then
    isSelf = true
  elseif msg:find("^You ") or msg:find("^Ihr ") or msg:find("^Du ") then
    isSelf = true
  elseif LOOT_ITEM_SELF and type(LOOT_ITEM_SELF) == "string" then
    -- Fallback: any item link in a loot message while we cannot parse self — skip unless selfName matched.
  end
  if not isSelf then return end
  local itemId = ItemIdFromMessage(msg)
  local q = ItemQuality(itemId)
  if q and q >= RARE_QUALITY then
    local itemName = msg:match("%[(.-)%]")
    React("loot", { item = itemName, player = selfName })
  end
end

local function OnAchievement(_, id)
  id = tonumber(id)
  if not id or type(GetAchievementInfo) ~= "function" then return end
  local ok, _, _, points = pcall(GetAchievementInfo, id)
  if not ok then return end
  points = tonumber(points) or 0
  if points >= ACHIEVE_POINTS_MIN then
    React("achievement")
  end
end

local function OnPvpKills()
  local hk = SessionPvpKills()
  if hk == nil then return end
  if lastPvpKills ~= nil and hk > lastPvpKills then
    React("pvp")
  end
  lastPvpKills = hk
end

local function ScheduleIdle()
  if idleTimer and idleTimer.Cancel then
    idleTimer:Cancel()
  end
  idleTimer = nil
  if not C_Timer or not C_Timer.NewTimer then return end
  local delay = IDLE_MIN + (math.random() * IDLE_SPAN)
  idleTimer = C_Timer.NewTimer(delay, function()
    idleTimer = nil
    if GR.Nerglish and GR.Nerglish.TryIdle then
      GR.Nerglish.TryIdle(Now())
    end
    ScheduleIdle()
  end)
end

function Mod:OnEnable()
  if self.enabled then return end
  self.enabled = true

  rosterReady = false
  wipe(knownMembers)
  lastPvpKills = SessionPvpKills()

  if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
    pcall(C_GuildInfo.GuildRoster)
  end

  local f = CreateFrame("Frame")
  self._eventFrame = f
  U.SafeRegisterEvent(f, "PLAYER_PVP_KILLS_CHANGED")
  U.SafeRegisterEvent(f, "GUILD_ROSTER_UPDATE")
  U.SafeRegisterEvent(f, "CHAT_MSG_LOOT")
  U.SafeRegisterEvent(f, "CHAT_MSG_GUILD_ACHIEVEMENT")
  U.SafeRegisterEvent(f, "ACHIEVEMENT_EARNED")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_PVP_KILLS_CHANGED" then
      OnPvpKills()
    elseif event == "GUILD_ROSTER_UPDATE" then
      OnGuildRoster()
    elseif event == "CHAT_MSG_LOOT" then
      OnLoot(_, ...)
    elseif event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
      local msg = ...
      local goal = type(msg) == "string" and msg:match("%[(.-)%]") or nil
      React("guild_goal", { goal = goal })
    elseif event == "ACHIEVEMENT_EARNED" then
      OnAchievement(_, ...)
    end
  end)

  ScheduleIdle()
end

function Mod:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  if idleTimer and idleTimer.Cancel then
    idleTimer:Cancel()
  end
  idleTimer = nil
  if self._eventFrame then
    self._eventFrame:UnregisterAllEvents()
    self._eventFrame:SetScript("OnEvent", nil)
    self._eventFrame = nil
  end
end
