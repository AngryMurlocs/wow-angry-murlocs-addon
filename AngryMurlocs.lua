local GR = AngryMurlocs
local U = GR.Util

GR.VERSION = "0.6.0"
GR._modules = GR._modules or {}
GR._moduleOrder = GR._moduleOrder or {}

local lastGuildSyncAt = 0
local GUILD_SYNC_DEBOUNCE = 50
local guildSyncPending = false

local function RunGuildSync(force)
  if not IsInGuild or not IsInGuild() then return end
  local now = (GetTime and GetTime()) or 0
  if not force and (now - lastGuildSyncAt) < GUILD_SYNC_DEBOUNCE then return end
  lastGuildSyncAt = now
  if U.RecoverWantedScopes then U.RecoverWantedScopes() end
  local prof = GR:GetModule("Professions")
  if prof then
    if prof.ClearEmptyRemoteStubs then prof:ClearEmptyRemoteStubs() end
    if prof.RequestAll then prof:RequestAll() end
    if prof.Broadcast then prof:Broadcast(true) end
  end
  local wanted = GR:GetModule("Wanted")
  if wanted and wanted.RequestSync then wanted:RequestSync() end
end

local function ScheduleGuildSync(delay, force)
  if guildSyncPending and not force then return end
  guildSyncPending = true
  C_Timer.After(delay or 4, function()
    guildSyncPending = false
    RunGuildSync(force)
  end)
end

local defaults = {
  map = {
    showPins = true,
    pinSize = 18,
  },
  privacy = {
    sharePosition = true,
    suppressInCombat = true,
    suppressInBg = true,
    shareProfessions = true,
    shareDeath = true,
    shareLevelUp = true,
    shareSightings = true,
  },
  wantedUI = {
    showSightAlerts = true,
  },
  prof = {
    cache = {},
  },
  wanted = {}, -- legacy 0.4 flat; migrated into scopes
  scopes = {},
  minimap = {
    angle = 220,
  },
  frames = {
    professions = { point = nil },
    wanted = { point = nil },
  },
  levelUp = {
    showToasts = true,
    point = nil,
    scale = 1,
    duration = 8.0,
    locked = false,
  },
  death = {
    showToasts = true,
    point = nil,
    scale = 1,
    duration = 10.0,
    locked = false,
  },
}

local function CopyDefaults(src, dst)
  if type(src) ~= "table" then return end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function DeepCopy(src)
  if type(src) ~= "table" then return src end
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = DeepCopy(v)
  end
  return dst
end

local function TableIsEmpty(t)
  return type(t) ~= "table" or next(t) == nil
end

local function MigrateLegacyToScope()
  local db = GR.db
  if not db then return end
  db.scopes = db.scopes or {}
  local key = U.GuildScopeKey()
  if not key then return end
  local scope = db.scopes[key]
  if not scope then
    scope = {}
    db.scopes[key] = scope
  end
  U.EnsureScopeTable(scope)

  if not TableIsEmpty(db.wanted) and TableIsEmpty(scope.wanted) then
    for k, v in pairs(db.wanted) do
      scope.wanted[k] = DeepCopy(v)
    end
    wipe(db.wanted)
    db._migratedWantedToScope = true
  end
end

function GR:NewModule(name)
  local mod = { name = name }
  self._modules[name] = mod
  self._moduleOrder[#self._moduleOrder + 1] = name
  return mod
end

function GR:GetModule(name)
  return self._modules[name]
end

function GR:EnableModules()
  MigrateLegacyToScope()
  for i = 1, #self._moduleOrder do
    local mod = self._modules[self._moduleOrder[i]]
    if mod and mod.OnEnable then
      local ok, err = pcall(mod.OnEnable, mod)
      if not ok then
        U.Print("Module " .. mod.name .. " error: " .. tostring(err))
      end
    end
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon ~= "AngryMurlocs" then return end
    if TableIsEmpty(AngryMurlocsDB) then
      if type(GildenRadarDB) == "table" and not TableIsEmpty(GildenRadarDB) then
        AngryMurlocsDB = DeepCopy(GildenRadarDB)
      elseif type(MurlocsHelperDB) == "table" and not TableIsEmpty(MurlocsHelperDB) then
        AngryMurlocsDB = DeepCopy(MurlocsHelperDB)
      end
    end
    AngryMurlocsDB = AngryMurlocsDB or {}
    CopyDefaults(defaults, AngryMurlocsDB)
    GR.db = AngryMurlocsDB
    GR.db._agentDebug = nil
    if GR.db.map then
      local ps = tonumber(GR.db.map.pinSize)
      -- Migrate prior defaults (≤14) / invalid → 18
      if not ps or ps <= 14 or ps > 24 then
        GR.db.map.pinSize = 18
      end
    end
    -- Migrate old toast duration defaults → longer defaults
    if GR.db.levelUp then
      local d = tonumber(GR.db.levelUp.duration)
      if not d or d == 4.5 then
        GR.db.levelUp.duration = 8.0
      end
    end
    if GR.db.death then
      local d = tonumber(GR.db.death.duration)
      if not d or d == 5.5 then
        GR.db.death.duration = 10.0
      end
    end
    GR.Comm:Register()
  elseif event == "PLAYER_LOGIN" then
    GR:EnableModules()
    U.Print(string.format(U.L("LOADED"), GR.VERSION))
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Every loading screen: debounced guild data sync
    ScheduleGuildSync(4, false)
  elseif event == "CHAT_MSG_ADDON" then
    GR.Comm:OnAddonMessage(...)
  elseif event == "PLAYER_GUILD_UPDATE" then
    MigrateLegacyToScope()
    if U.RecoverWantedScopes then U.RecoverWantedScopes() end
    GR:SendMessage("GUILD_UPDATE")
    lastGuildSyncAt = 0
    ScheduleGuildSync(2, true)
  end
end)

SLASH_ANGRYMURLOCS1 = "/am"
SLASH_ANGRYMURLOCS2 = "/angrymurlocs"
SLASH_ANGRYMURLOCS3 = "/gr"
SlashCmdList["ANGRYMURLOCS"] = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local lower = msg:lower()
  local db = GR.db
  if not db then
    U.Print("Not ready yet.")
    return
  end

  if lower == "" then
    local ui = GR:GetModule("UI")
    if ui and ui.Toggle then
      ui:Toggle()
    else
      U.Print(U.L("HELP"))
    end
    return
  end

  if lower == "help" then
    U.Print(U.L("HELP"))
    return
  end

  if lower == "config" or lower == "options" or lower == "settings" then
    local options = GR:GetModule("Options")
    if options and options.Open then
      options:Open()
    end
    return
  end

  if lower == "wanted" then
    local wanted = GR:GetModule("Wanted")
    if wanted and wanted.Toggle then
      wanted:Toggle()
    end
    return
  end

  if lower == "share on" or lower == "share" then
    db.privacy.sharePosition = true
    U.Print(U.L("SHARE_POS_ON"))
    GR:SendMessage("SHARE_POS_CHANGED")
    return
  end
  if lower == "share off" then
    db.privacy.sharePosition = false
    U.Print(U.L("SHARE_POS_OFF"))
    GR:SendMessage("SHARE_POS_CHANGED")
    return
  end

  if lower == "map" then
    db.map.showPins = not db.map.showPins
    U.Print(db.map.showPins and U.L("MAP_ON") or U.L("MAP_OFF"))
    GR:SendMessage("MAP_SETTINGS_CHANGED")
    return
  end

  if lower == "prof" then
    local ui = GR:GetModule("UI")
    if ui and ui.ShowProf then
      ui:ShowProf()
    end
    return
  end

  if lower == "prof share on" then
    db.privacy.shareProfessions = true
    U.Print(U.L("SHARE_PROF_ON"))
    GR:SendMessage("SHARE_PROF_CHANGED")
    return
  end
  if lower == "prof share off" then
    db.privacy.shareProfessions = false
    U.Print(U.L("SHARE_PROF_OFF"))
    return
  end

  U.Print(U.L("HELP"))
end
