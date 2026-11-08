local GR = AngryMurlocs
local U = GR.Util

GR.VERSION = "0.5.7"
GR._modules = GR._modules or {}
GR._moduleOrder = GR._moduleOrder or {}

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
    craft = { point = nil },
    main = { point = nil },
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
  elseif event == "CHAT_MSG_ADDON" then
    GR.Comm:OnAddonMessage(...)
  elseif event == "PLAYER_GUILD_UPDATE" then
    MigrateLegacyToScope()
    GR:SendMessage("GUILD_UPDATE")
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

  -- #region agent log
  if lower == "dbgprobe" then
    local priv = db.privacy or {}
    local wrote = U.AgentLog("H3", "AngryMurlocs.lua:dbgprobe", "privacy_snapshot", {
      shareLevelUp = priv.shareLevelUp and true or false,
      shareDeath = priv.shareDeath and true or false,
      shareProfessions = priv.shareProfessions and true or false,
      sharePosition = priv.sharePosition and true or false,
      showLvlToasts = (db.levelUp and db.levelUp.showToasts) and true or false,
      showDeathToasts = (db.death and db.death.showToasts) and true or false,
      inGuild = (IsInGuild and IsInGuild()) and true or false,
      ioOpen = (io and io.open) and true or false,
    })
    -- Simulated wire samples: would SanitizeText on whole rest kill pipes?
    local samples = {
      { tag = "LVL", rest = "42" },
      { tag = "PROF", rest = "alch:15|herb:28|cook:9" },
      { tag = "DEATH", rest = "Boar|0|Elwynn|1429|mob|Claw" },
      { tag = "MAIN", rest = "set|Ingoo|1|123" },
      { tag = "CRAFT", rest = "create|id1|1|0|Owner|0|Sword|esc|1|0|note|open||" },
    }
    for i = 1, #samples do
      local s = samples[i]
      local sanitized = U.SanitizeText(s.rest, 200)
      local hadPipe = s.rest:find("|", 1, true) and true or false
      local stillPipe = sanitized:find("|", 1, true) and true or false
      U.AgentLog("H1", "AngryMurlocs.lua:dbgprobe", "sanitize_sample", {
        tag = s.tag,
        hadPipe = hadPipe,
        sanitizeKillsPipes = (hadPipe and not stillPipe) and true or false,
        usesWholeRestSanitize = (s.tag == "PROF") and true or false,
      })
    end
    -- Inject fake guild messages (not self) through real Comm path
    local fake = "AMDbgProbe-TestRealm"
    if GR.Comm and GR.Comm.OnAddonMessage then
      GR.Comm:OnAddonMessage(GR.PREFIX, "LVL|42", "GUILD", fake)
      GR.Comm:OnAddonMessage(GR.PREFIX, "PROF|alch:15|herb:28|cook:9", "GUILD", fake)
      GR.Comm:OnAddonMessage(GR.PREFIX, "DEATH|Boar|0|Elwynn|1429|mob|Claw", "GUILD", fake)
    end
    local lvl = GR:GetModule("LevelUp")
    if lvl and lvl.Preview then lvl:Preview() end
    local probeCache = db.prof and db.prof.cache and db.prof.cache["AMDbgProbe-TestRealm"]
    local decoded = probeCache and probeCache.list and #probeCache.list or -1
    U.Print("dbgprobe done file=" .. tostring(wrote) .. " AMDbgProbeProfs=" .. tostring(decoded) .. " — dann /reload damit Logs in SV landen.")
    return
  end
  -- #endregion

  if lower == "wanted" then
    local wanted = GR:GetModule("Wanted")
    if wanted and wanted.Toggle then
      wanted:Toggle()
    end
    return
  end

  if lower == "craft" then
    local craft = GR:GetModule("Craft")
    if craft and craft.Toggle then
      craft:Toggle()
    end
    return
  end

  if lower == "main" or lower:match("^main%s+") then
    local mains = GR:GetModule("Mains")
    if not mains then return end
    if lower == "main clear" or lower == "main off" then
      mains:ClearLocal(true)
      return
    end
    if lower == "main" then
      if mains.Toggle then
        mains:Toggle()
      else
        mains:PrintStatus()
      end
      return
    end
    local nameArg = msg:match("^[Mm][Aa][Ii][Nn]%s+(.+)$")
    if nameArg then
      nameArg = nameArg:gsub("^%s+", ""):gsub("%s+$", "")
      if nameArg:lower() == "clear" or nameArg:lower() == "off" then
        mains:ClearLocal(true)
      else
        mains:SetLocal(nameArg, true)
      end
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
