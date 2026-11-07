local GR = AngryMurlocs
local U = GR.Util

GR.VERSION = "0.4.0"
GR._modules = GR._modules or {}
GR._moduleOrder = GR._moduleOrder or {}

local defaults = {
  map = {
    showPins = true,
    pinSize = 8,
  },
  privacy = {
    sharePosition = true,
    suppressInCombat = true,
    suppressInBg = true,
    shareProfessions = true,
    shareDeath = true,
    shareLevelUp = true,
  },
  prof = {
    cache = {},
  },
  wanted = {},
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
    duration = 4.5,
    locked = false,
  },
  death = {
    showToasts = true,
    point = nil,
    scale = 1,
    duration = 5.5,
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
    -- One-shot migrate: GildenRadarDB → MurlocsHelperDB
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
    GR.db._agentDebug = nil -- drop legacy debug buffer
    if GR.db.map and (not GR.db.map.pinSize or GR.db.map.pinSize > 12) then
      GR.db.map.pinSize = 8
    end
    GR.Comm:Register()
  elseif event == "PLAYER_LOGIN" then
    GR:EnableModules()
    U.Print(string.format(U.L("LOADED"), GR.VERSION))
  elseif event == "CHAT_MSG_ADDON" then
    GR.Comm:OnAddonMessage(...)
  elseif event == "PLAYER_GUILD_UPDATE" then
    GR:SendMessage("GUILD_UPDATE")
  end
end)

SLASH_ANGRYMURLOCS1 = "/am"
SLASH_ANGRYMURLOCS2 = "/angrymurlocs"
SLASH_ANGRYMURLOCS3 = "/gr"
SlashCmdList["ANGRYMURLOCS"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local db = GR.db
  if not db then
    U.Print("Not ready yet.")
    return
  end

  if msg == "" then
    local ui = GR:GetModule("UI")
    if ui and ui.Toggle then
      ui:Toggle()
    else
      U.Print(U.L("HELP"))
    end
    return
  end

  if msg == "help" then
    U.Print(U.L("HELP"))
    return
  end

  if msg == "wanted" then
    local wanted = GR:GetModule("Wanted")
    if wanted and wanted.Toggle then
      wanted:Toggle()
    end
    return
  end

  if msg == "share on" or msg == "share" then
    db.privacy.sharePosition = true
    U.Print(U.L("SHARE_POS_ON"))
    GR:SendMessage("SHARE_POS_CHANGED")
    return
  end
  if msg == "share off" then
    db.privacy.sharePosition = false
    U.Print(U.L("SHARE_POS_OFF"))
    GR:SendMessage("SHARE_POS_CHANGED")
    return
  end

  if msg == "map" then
    db.map.showPins = not db.map.showPins
    U.Print(db.map.showPins and U.L("MAP_ON") or U.L("MAP_OFF"))
    GR:SendMessage("MAP_SETTINGS_CHANGED")
    return
  end

  if msg == "prof" then
    local ui = GR:GetModule("UI")
    if ui and ui.ShowProf then
      ui:ShowProf()
    end
    return
  end

  if msg == "prof share on" then
    db.privacy.shareProfessions = true
    U.Print(U.L("SHARE_PROF_ON"))
    GR:SendMessage("SHARE_PROF_CHANGED")
    return
  end
  if msg == "prof share off" then
    db.privacy.shareProfessions = false
    U.Print(U.L("SHARE_PROF_OFF"))
    return
  end

  U.Print(U.L("HELP"))
end
