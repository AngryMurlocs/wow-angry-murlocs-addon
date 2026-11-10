local GR = AngryMurlocs
local U = GR.Util

GR.VERSION = "0.10.1"
GR.DISCORD_INVITE = "https://discord.gg/2Yh4gn8aQt"
GR._modules = GR._modules or {}
GR._moduleOrder = GR._moduleOrder or {}

local SCHEMA = 2

-- Guild data sync runs once per session (login / reload) and on guild change,
-- not on every loading screen. Random delay spreads simultaneous logins.
local initialSyncDone = false
local guildSyncPending = false
local lastGuildKey

local function RunGuildSync()
  if not IsInGuild or not IsInGuild() then return end
  lastGuildKey = U.GuildScopeKey()
  if U.RecoverWantedScopes then U.RecoverWantedScopes() end
  local prof = GR:GetModule("Professions")
  if prof then
    if prof.MigrateCache then prof:MigrateCache() end
    if prof.ClearEmptyRemoteStubs then prof:ClearEmptyRemoteStubs() end
    if prof.RequestAll then prof:RequestAll() end
  end
  -- Recipe lists sync on-demand when a catalog is opened (PROFRQ per profession).
  local wanted = GR:GetModule("Wanted")
  if wanted and wanted.RequestSync then wanted:RequestSync("delta") end
  if wanted and wanted.AnnounceOwn then wanted:AnnounceOwn() end
end

local function ScheduleGuildSync(minDelay)
  if guildSyncPending then return end
  guildSyncPending = true
  C_Timer.After((minDelay or 4) + math.random() * 6, function()
    guildSyncPending = false
    RunGuildSync()
  end)
end

local defaults = {
  map = {
    showPins = true,
    pinSize = 18,
    pinStyle = "heads",
  },
  privacy = {
    sharePosition = true,
    suppressInCombat = true,
    suppressInBg = true,
    suppressInInstance = false,
    shareProfessions = true,
    shareDeath = true,
    shareLevelUp = true,
    shareSightings = true,
  },
  wantedUI = {
    showSightAlerts = true,
  },
  -- autoWanted overrides ignored; WantedLogic.GetFixedConfig() is source of truth
  autoWanted = {},
  prof = {
    cache = {},
    recipeMeta = {},
  },
  wanted = {}, -- legacy 0.4 flat; migrated into scopes
  scopes = {},
  minimap = {
    angle = 220,
  },
  frames = {
    main = { point = nil },
    professions = { point = nil }, -- legacy; migrated into main
    wanted = { point = nil }, -- legacy unused
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
  diag = {
    enabled = false,
  },
  -- One-shot migration flags (nil = not yet run). Never re-overwrite user prefs after set.
  migrations = {
    pinSizeV18 = nil,
    toastDurV2 = nil,
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
      local copy = DeepCopy(v)
      GR.WantedLogic.MigrateEntryV2(copy)
      scope.wanted[k] = copy
    end
    wipe(db.wanted)
    db._migratedWantedToScope = true
  end
end

-- Versioned, repeatable: entries already on schema 2 are left as they are.
-- Privacy settings, pins and toast layout are not touched.
local function MigrateSchema(db)
  if (tonumber(db.schema) or 1) >= SCHEMA then return end
  for _, scope in pairs(db.scopes or {}) do
    if type(scope) == "table" and type(scope.wanted) == "table" then
      for _, entry in pairs(scope.wanted) do
        GR.WantedLogic.MigrateEntryV2(entry)
      end
      scope.wantedCandidates = nil
      scope._schema2 = true
    end
  end
  db.schema = SCHEMA
end

function GR:NewModule(name)
  local mod = { name = name, enabled = false }
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
    GR.db.migrations = GR.db.migrations or {}
    local mig = GR.db.migrations
    -- One-shot: old pin defaults (≤14) / invalid → 18
    if not mig.pinSizeV18 then
      GR.db.map = GR.db.map or {}
      local ps = tonumber(GR.db.map.pinSize)
      if not ps or ps <= 14 or ps > 24 then
        GR.db.map.pinSize = 18
      end
      mig.pinSizeV18 = true
    end
    -- One-shot: old toast duration defaults → longer defaults
    if not mig.toastDurV2 then
      GR.db.levelUp = GR.db.levelUp or {}
      local ld = tonumber(GR.db.levelUp.duration)
      if not ld or ld == 4.5 then
        GR.db.levelUp.duration = 8.0
      end
      GR.db.death = GR.db.death or {}
      local dd = tonumber(GR.db.death.duration)
      if not dd or dd == 5.5 then
        GR.db.death.duration = 10.0
      end
      mig.toastDurV2 = true
    end
    -- Discard per-user Auto-Wanted overrides (guild-fixed rules in WantedLogic)
    GR.db.autoWanted = {}
    MigrateSchema(GR.db)
    GR.Comm:Register()
  elseif event == "PLAYER_LOGIN" then
    GR:EnableModules()
    U.Print(string.format(U.L("LOADED"), GR.VERSION))
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not initialSyncDone then
      initialSyncDone = true
      ScheduleGuildSync(4)
    end
  elseif event == "CHAT_MSG_ADDON" then
    GR.Comm:OnAddonMessage(...)
  elseif event == "PLAYER_GUILD_UPDATE" then
    local key = U.GuildScopeKey()
    if key == lastGuildKey then return end
    lastGuildKey = key
    if not key and GR.Comm and GR.Comm.OnGuildLeft then
      GR.Comm:OnGuildLeft()
    end
    MigrateLegacyToScope()
    if GR.db then GR.db._recoveredWantedScopes = nil end
    if U.RecoverWantedScopes then U.RecoverWantedScopes() end
    GR:SendMessage("GUILD_UPDATE")
    if initialSyncDone and key then
      ScheduleGuildSync(2)
    end
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

  if lower == "sync" then
    local ui = GR:GetModule("UI")
    if ui and ui.RunGuildDataSync then
      ui:RunGuildDataSync()
    end
    return
  end

  local diagArg = lower:match("^diag%s*(%a*)$")
  if diagArg then
    local diag = GR.Diag
    if diagArg == "on" then
      diag:SetEnabled(true)
      U.Print(U.L("DIAG_ON"))
    elseif diagArg == "off" then
      diag:SetEnabled(false)
      U.Print(U.L("DIAG_OFF"))
    elseif diagArg == "death" then
      diag:ShowDeaths()
    else
      diag:Show(20)
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
    GR:SendMessage("SHARE_PROF_CHANGED")
    return
  end

  U.Print(U.L("HELP"))
end
