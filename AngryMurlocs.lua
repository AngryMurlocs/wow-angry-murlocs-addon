local GR = AngryMurlocs
local U = GR.Util

GR.VERSION = "0.11.29"
GR.DISCORD_INVITE = "https://discord.murlocs.eu"
GR._modules = GR._modules or {}
GR._moduleOrder = GR._moduleOrder or {}

local SCHEMA = 2

-- Guild data sync runs once per session (login / reload) and on guild change,
-- not on every loading screen. Random delay spreads simultaneous logins.
local initialSyncDone = false
local guildSyncPending = false
local guildScopeWaitPending = false
local lastGuildKey

local function RunGuildSync()
  if not IsInGuild or not IsInGuild() then return end
  local key = U.GuildScopeKey and U.GuildScopeKey()
  if not key then return end
  lastGuildKey = key
  if U.RecoverWantedScopes then U.RecoverWantedScopes() end
  local prof = GR:GetModule("Professions")
  if prof then
    if prof.MigrateCache then prof:MigrateCache() end
    -- Per-guild key canon (independent of account _movedToScope).
    if prof.MigrateAllScopeKeys then
      prof:MigrateAllScopeKeys()
    elseif prof.MigrateActiveScopeKeys then
      prof:MigrateActiveScopeKeys()
    end
    if prof.ClearEmptyRemoteStubs then prof:ClearEmptyRemoteStubs() end
    if prof.RequestAll then prof:RequestAll() end
  end
  -- Recipe lists sync on-demand when a catalog is opened (PROFRQ per profession).
  local wanted = GR:GetModule("Wanted")
  if wanted and wanted.RequestSync then wanted:RequestSync("delta") end
  if wanted and wanted.AnnounceOwn then wanted:AnnounceOwn() end
end

local function ScheduleGuildSync(minDelay)
  if not U.GuildScopeKey or not U.GuildScopeKey() then return false end
  if guildSyncPending then return true end
  guildSyncPending = true
  C_Timer.After((minDelay or 4) + math.random() * 6, function()
    guildSyncPending = false
    RunGuildSync()
  end)
  return true
end

local defaults = {
  map = {
    showPins = true,
    showSightPins = true,
    pinSize = 26,
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
  ui = {
    nerglishStyle = "off", -- "off" | "nerglish" | "schmaeh"
  },
  levelUp = {
    showToasts = true,
    point = nil,
    scale = 1,
    duration = 8.0,
    locked = false,
    toastStyle = "art", -- "art" | "classic"
  },
  death = {
    showToasts = true,
    point = nil,
    scale = 1,
    duration = 10.0,
    locked = false,
    toastStyle = "art", -- "art" | "classic"
  },
  diag = {
    enabled = false,
  },
  -- One-shot migration flags (nil = not yet run). Never re-overwrite user prefs after set.
  migrations = {
    pinSizeV18 = nil,
    pinSizeV20 = nil,
    pinSizeV26 = nil,
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

-- Auto-import only VERIFIED_SCOPE_IMPORTS keys whose expected club id matches dest.
-- dest must be the ready club:<id> key (from OnGuildScopeReady `key` or GuildScopeKey).
-- Never use live GuildId() as fallback — stale API can lie when dest is nil/realm.
local function ImportVerifiedForDest(dest)
  if not U.RunVerifiedScopeImport then return false end
  local ok = U.RunVerifiedScopeImport(dest)
  if ok then
    U.Print(U.L("SCOPE_IMPORT_DONE"))
  end
  return ok
end

-- /am import: same verified auto path (no popup).
function GR.OfferScopeImport()
  local dest = U.GuildScopeKey and U.GuildScopeKey()
  if not dest then return end
  if ImportVerifiedForDest(dest) then
    GR:SendMessage("GUILD_UPDATE")
  end
end

-- Club id / realm can be missing at Forever login; wait until GuildScopeKey is
-- final before sync/SV use. Activate scope, auto-import verified orphans, then sync.
local function OnGuildScopeReady(oldKey, key)
  if GR.db then GR.db._recoveredWantedScopes = nil end
  MigrateLegacyToScope()
  if U.RecoverWantedScopes then U.RecoverWantedScopes() end
  if U.GetScopeDB then U.GetScopeDB() end
  -- dest = ready key only (ClubIdFromScopeKey inside RunVerifiedScopeImport).
  local imported = ImportVerifiedForDest(key)
  if oldKey ~= key or imported then
    GR:SendMessage("GUILD_UPDATE")
  end
  if not initialSyncDone then
    initialSyncDone = true
    ScheduleGuildSync(4)
  elseif key and key ~= oldKey then
    ScheduleGuildSync(2)
  end
  C_Timer.After(2, function()
    if GR.Comm and GR.Comm.AnnounceVersion and U.GuildScopeKey and U.GuildScopeKey() then
      GR.Comm:AnnounceVersion()
    end
  end)
end

-- Tests fire PLAYER_ENTERING_WORLD / INITIAL_CLUBS_LOADED on this frame.
GR.OnGuildScopeReady = OnGuildScopeReady

local function TryWakeGuildScope()
  local key = U.GuildScopeKey and U.GuildScopeKey()
  if not key then return false end
  if key == lastGuildKey and initialSyncDone then return true end
  local oldKey = lastGuildKey
  lastGuildKey = key
  OnGuildScopeReady(oldKey, key)
  return true
end

local function ArmGuildScopeWait()
  if guildScopeWaitPending then return end
  if TryWakeGuildScope() then return end
  guildScopeWaitPending = true
  local tries = 0
  local function tick()
    tries = tries + 1
    if TryWakeGuildScope() then
      guildScopeWaitPending = false
      return
    end
    if tries >= 30 then
      guildScopeWaitPending = false
      return
    end
    C_Timer.After(2, tick)
  end
  C_Timer.After(2, tick)
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
-- GetGuildClubId requires clubs initialized (Forever ClubDocumentation).
U.SafeRegisterEvent(frame, "INITIAL_CLUBS_LOADED")

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
    -- Before CopyDefaults: old nerglishYell must map before style default "off" lands.
    if GR.Nerglish and GR.Nerglish.MigrateUi then
      GR.Nerglish.MigrateUi(AngryMurlocsDB)
    end
    CopyDefaults(defaults, AngryMurlocsDB)
    GR.db = AngryMurlocsDB
    if GR.Nerglish and GR.Nerglish.MigrateUi then
      GR.Nerglish.MigrateUi(GR.db)
    end
    -- Leftover debug data from 0.11.x and older
    GR.db._agentDebug = nil
    GR.db.migrations = GR.db.migrations or {}
    local mig = GR.db.migrations
    -- One-shot: old pin defaults (≤14) / invalid → 18
    if not mig.pinSizeV18 then
      GR.db.map = GR.db.map or {}
      local ps = tonumber(GR.db.map.pinSize)
      if not ps or ps <= 14 or ps > 40 then
        GR.db.map.pinSize = 18
      end
      mig.pinSizeV18 = true
    end
    -- One-shot: previous default 18 → 20. Any other saved size stays.
    if not mig.pinSizeV20 then
      GR.db.map = GR.db.map or {}
      if tonumber(GR.db.map.pinSize) == 18 then
        GR.db.map.pinSize = 20
      end
      mig.pinSizeV20 = true
    end
    -- One-shot: previous default 20 → 26. Any other saved size stays.
    if not mig.pinSizeV26 then
      GR.db.map = GR.db.map or {}
      if tonumber(GR.db.map.pinSize) == 20 then
        GR.db.map.pinSize = 26
      end
      mig.pinSizeV26 = true
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
  elseif event == "PLAYER_ENTERING_WORLD" or event == "INITIAL_CLUBS_LOADED" then
    if not initialSyncDone then
      if not TryWakeGuildScope() then
        ArmGuildScopeWait()
      end
    else
      TryWakeGuildScope()
    end
  elseif event == "CHAT_MSG_ADDON" then
    GR.Comm:OnAddonMessage(...)
  elseif event == "PLAYER_GUILD_UPDATE" then
    local key = U.GuildScopeKey()
    local oldKey = lastGuildKey
    if key == oldKey then
      -- Still waiting for club id while guilded.
      if not key then ArmGuildScopeWait() end
      return
    end
    lastGuildKey = key
    if not key then
      -- Leave (including stale club API still returning an id): drop views + wire.
      if GR.Comm and GR.Comm.OnGuildLeft then
        GR.Comm:OnGuildLeft()
      end
      ArmGuildScopeWait()
      GR:SendMessage("GUILD_UPDATE")
    else
      -- Guild switch or first ready key: full reset of prior guild wire state.
      if oldKey and GR.Comm and GR.Comm.OnGuildLeft then
        GR.Comm:OnGuildLeft()
      end
      OnGuildScopeReady(oldKey, key)
    end
  end
end)

GR._bootFrame = frame

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

  if lower == "import" then
    GR.OfferScopeImport()
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
