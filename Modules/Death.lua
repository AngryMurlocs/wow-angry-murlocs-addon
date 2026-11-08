local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Death = GR:NewModule("Death")

-- Last damaging hit on the player (killing-blow candidate)
local lastHit = {
  name = nil,
  isPlayer = false,
  cause = "env", -- player | mob | env
  spell = nil,
  envType = nil,
  t = 0,
}

-- Forever (no CLEU): recent env hint from mirror timers / IsFalling
local envHint = {
  spell = nil,
  t = 0,
}
local ENV_HINT_TTL = 5
local toast
local tracker
local fallElapsed = 0

local ENV_KEYS = {
  FALLING = "DEATH_ENV_FALL",
  FALL = "DEATH_ENV_FALL",
  ["2"] = "DEATH_ENV_FALL",
  DROWNING = "DEATH_ENV_DROWN",
  DROWN = "DEATH_ENV_DROWN",
  ["1"] = "DEATH_ENV_DROWN",
  FATIGUE = "DEATH_ENV_FATIGUE",
  EXHAUSTED = "DEATH_ENV_FATIGUE",
  EXHAUSTION = "DEATH_ENV_FATIGUE",
  ["0"] = "DEATH_ENV_FATIGUE",
  LAVA = "DEATH_ENV_LAVA",
  ["3"] = "DEATH_ENV_LAVA",
  SLIME = "DEATH_ENV_SLIME",
  ["4"] = "DEATH_ENV_SLIME",
  FIRE = "DEATH_ENV_FIRE",
  ["5"] = "DEATH_ENV_FIRE",
}

local function Cfg()
  GR.db.death = GR.db.death or {}
  local c = GR.db.death
  if c.showToasts == nil then c.showToasts = true end
  if c.scale == nil then c.scale = 1 end
  if c.duration == nil then c.duration = 10.0 end
  if c.locked == nil then c.locked = false end
  return c
end

local function DefaultPoint(f)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
end

local function ApplyToastLayout(f)
  local c = Cfg()
  U.ApplyPoint(f, c.point, DefaultPoint)
  f:SetScale(U.Clamp(tonumber(c.scale) or 1, 0.6, 1.6))
  if f.hint then
    f.hint:SetShown(not c.locked)
  end
end

local function RaiseToast(f)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(500)
  if f.Raise then f:Raise() end
end

local function EnsureToast()
  if toast then
    ApplyToastLayout(toast)
    RaiseToast(toast)
    return toast
  end
  toast = CreateFrame("Frame", "AngryMurlocsDeathToast", UIParent, BackdropTemplate and "BackdropTemplate" or nil)
  toast:SetSize(520, 56)
  RaiseToast(toast)
  if toast.SetBackdrop then
    toast:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    toast:SetBackdropColor(0.15, 0.02, 0.02, 0.9)
    toast:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
  end
  toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  toast.text:SetPoint("CENTER", 0, 4)
  toast.text:SetWidth(500)
  do
    local path, _, flags = toast.text:GetFont()
    if path then toast.text:SetFont(path, 20, flags) end
  end

  toast.hint = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  toast.hint:SetPoint("BOTTOM", 0, 6)
  toast.hint:SetText(U.L("TOAST_DRAG_HINT"))

  U.MakeMovable(toast, {
    getPoint = function() return Cfg().point end,
    setPoint = function(pt) Cfg().point = pt end,
    isLocked = function() return Cfg().locked end,
    defaultFn = DefaultPoint,
  })

  ApplyToastLayout(toast)
  toast:Hide()
  return toast
end

local function SpellForCause(cause, spell)
  if cause == "player" or cause == "mob" then
    if type(spell) ~= "string" or spell == "" or spell == U.L("UNKNOWN_KILLER") then
      return U.L("DEATH_MELEE")
    end
    return spell
  end
  if type(spell) ~= "string" or spell == "" then
    return U.L("DEATH_CAUSE_ENV")
  end
  return spell
end

local function FormatDeathLine(victim, cause, killer, spell, zone)
  zone = (zone and zone ~= "") and zone or "?"
  killer = killer or U.L("UNKNOWN_KILLER")
  spell = SpellForCause(cause, spell)
  local body
  if cause == "player" then
    body = string.format(U.L("DEATH_TOAST_PLAYER"), victim, killer, spell, zone)
  elseif cause == "mob" then
    body = string.format(U.L("DEATH_TOAST_MOB"), victim, killer, spell, zone)
  else
    body = string.format(U.L("DEATH_TOAST_ENV"), victim, spell, zone)
  end
  -- Badge always from code so old locale copies still show TOT/DEAD first.
  return string.format("|cffff3333%s|r  %s", U.L("DEATH_BADGE"), body)
end

local function ShowDeathToast(victim, cause, killer, spell, zone)
  if not Cfg().showToasts then return end
  local f = EnsureToast()
  ApplyToastLayout(f)
  RaiseToast(f)
  if f._hide then f._hide:Cancel() f._hide = nil end
  if f._fadeAfter then f._fadeAfter:Cancel() f._fadeAfter = nil end
  if UIFrameFadeRemoveFrame then
    UIFrameFadeRemoveFrame(f)
  end
  f.text:SetText(FormatDeathLine(victim, cause, killer, spell, zone))
  f:SetAlpha(1)
  f:Show()
  local dur = U.Clamp(tonumber(Cfg().duration) or 10.0, 1.5, 15)
  f._hide = C_Timer.NewTimer(dur, function()
    if UIFrameFadeOut then
      UIFrameFadeOut(f, 0.5, 1, 0)
      f._fadeAfter = C_Timer.NewTimer(0.55, function()
        f._fadeAfter = nil
        f:Hide()
      end)
    else
      f:Hide()
    end
  end)
end

local function CacheHit(name, isPlayer, cause, spell, envType)
  lastHit.name = name
  lastHit.isPlayer = isPlayer and true or false
  lastHit.cause = cause or "mob"
  lastHit.spell = spell
  lastHit.envType = envType
  lastHit.t = U.Now()
end

local function CacheEnvHint(spell)
  if type(spell) ~= "string" or spell == "" then return end
  envHint.spell = spell
  envHint.t = U.Now()
end

local function EnvLabelFromType(envType)
  local key = ENV_KEYS[tostring(envType or ""):upper()]
  return key and U.L(key) or U.L("DEATH_ENV_OTHER")
end

local function IsPlayerSource(sourceGUID, sourceFlags)
  if sourceGUID and tostring(sourceGUID):find("^Player%-") then
    return true
  end
  if sourceFlags and bit and bit.band and COMBATLOG_OBJECT_TYPE_PLAYER then
    return bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0
  end
  return false
end

local function SpellFromCleu(subevent, ...)
  -- vararg starts at first post-dest field (index 12 of full CLEU)
  if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
    return U.L("DEATH_MELEE")
  end
  if subevent == "ENVIRONMENTAL_DAMAGE" then
    local envType = ...
    return EnvLabelFromType(envType)
  end
  -- SPELL_*, RANGE_*, SPELL_PERIODIC_*: spellId, spellName, spellSchool
  local spellId, spellName = ...
  if type(spellName) == "string" and spellName ~= "" then
    return spellName
  end
  if type(spellId) == "string" and spellId ~= "" then
    return spellId -- legacy CLEU oddity
  end
  return U.L("DEATH_MELEE")
end

local function HandleCleu(subevent, sourceGUID, sourceName, sourceFlags, destGUID, ...)
  if not subevent then return end
  local playerGUID = UnitGUID("player")
  if destGUID and playerGUID and destGUID ~= playerGUID then return end

  if subevent == "ENVIRONMENTAL_DAMAGE" then
    local envType = ...
    local spell = SpellFromCleu(subevent, ...)
    CacheHit(U.L("DEATH_CAUSE_ENV"), false, "env", spell, envType)
    return
  end

  local isDamage = tostring(subevent):find("_DAMAGE") or subevent == "SWING_DAMAGE" or tostring(subevent):find("_MISSED")
  if not isDamage then return end
  if not sourceName or sourceName == "" then return end

  local spell = SpellFromCleu(subevent, ...)
  local player = IsPlayerSource(sourceGUID, sourceFlags)
  CacheHit(sourceName, player, player and "player" or "mob", spell, nil)
end

local function OnCombatLog()
  if not CombatLogGetCurrentEventInfo then return end
  local args = { CombatLogGetCurrentEventInfo() }
  -- 2=subevent, 4=sourceGUID, 5=sourceName, 6=sourceFlags, 8=destGUID; 12+ payload
  HandleCleu(args[2], args[4], args[5], args[6], args[8], unpack(args, 12))
end

local function OnCombatLogLegacy(...)
  local args = { ... }
  HandleCleu(args[2], args[4], args[5], args[6], args[8], unpack(args, 12))
end

local function MirrorTimerToSpell(timer)
  local t = tostring(timer or ""):upper()
  if t == "BREATH" then
    return U.L("DEATH_ENV_DROWN")
  end
  if t == "EXHAUSTION" or t == "FATIGUE" then
    return U.L("DEATH_ENV_FATIGUE")
  end
  return nil
end

local function OnMirrorTimerStart(timer)
  local spell = MirrorTimerToSpell(timer)
  if spell then CacheEnvHint(spell) end
end

local function PollFalling(elapsed)
  fallElapsed = fallElapsed + (elapsed or 0)
  if fallElapsed < 0.5 then return end
  fallElapsed = 0
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  if IsFalling and IsFalling() then
    CacheEnvHint(U.L("DEATH_ENV_FALL"))
  end
end

local function FreshEnvHint()
  if envHint.t > 0 and envHint.spell and (U.Now() - envHint.t) < ENV_HINT_TTL then
    return envHint.spell
  end
  return nil
end

local function ResolveDeath()
  if lastHit.t > 0 and (U.Now() - lastHit.t) < 15 then
    local cause = lastHit.cause or (lastHit.isPlayer and "player" or "mob")
    return {
      killer = lastHit.name or U.L("UNKNOWN_KILLER"),
      isPlayer = lastHit.isPlayer,
      cause = cause,
      spell = SpellForCause(cause, lastHit.spell),
    }
  end

  -- No CLEU on Forever: self-report from combat state + unit tokens only.
  if UnitAffectingCombat("player") then
    if UnitExists("attacking") then
      local n = UnitName("attacking")
      local p = UnitIsPlayer("attacking")
      local cause = p and "player" or "mob"
      return {
        killer = n or U.L("UNKNOWN_KILLER"),
        isPlayer = p,
        cause = cause,
        spell = U.L("DEATH_MELEE"),
      }
    end
    if UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
      local n = UnitName("target")
      local p = UnitIsPlayer("target")
      local cause = p and "player" or "mob"
      return {
        killer = n or U.L("UNKNOWN_KILLER"),
        isPlayer = p,
        cause = cause,
        spell = U.L("DEATH_MELEE"),
      }
    end
  end

  local hint = FreshEnvHint()
  if hint then
    return {
      killer = U.L("UNKNOWN_KILLER"),
      isPlayer = false,
      cause = "env",
      spell = hint,
    }
  end

  return {
    killer = U.L("UNKNOWN_KILLER"),
    isPlayer = false,
    cause = "env",
    spell = U.L("DEATH_CAUSE_ENV"),
  }
end

local function Sanitize(s)
  return U.SanitizeText(s, 48)
end

function Death:BroadcastLocalDeath()
  local info = ResolveDeath()
  local zone = GetZoneText and GetZoneText() or ""
  local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
  local cause = info.cause or "env"
  local spell = SpellForCause(cause, info.spell)
  local me = U.ShortName(U.PlayerName())

  ShowDeathToast(me, cause, info.killer, spell, zone)

  local playerKill = cause == "player"
    and info.killer
    and info.killer ~= ""
    and info.killer ~= U.L("UNKNOWN_KILLER")

  if playerKill then
    local wanted = GR:GetModule("Wanted")
    if wanted and wanted.AddKill then
      wanted:AddKill(info.killer, U.NormalizeName(U.PlayerName()), zone, true)
    end
  end

  local db = GR.db
  if not db or not db.privacy.shareDeath or not IsInGuild() then return end

  Comm:Send(string.format(
    "DEATH|%s|%d|%s|%d|%s|%s",
    Sanitize(info.killer),
    info.isPlayer and 1 or 0,
    Sanitize(zone),
    mapId or 0,
    Sanitize(cause),
    Sanitize(spell)
  ))

  if playerKill then
    Comm:Send(string.format(
      "WANTED|add|%s|%s|%s",
      Sanitize(info.killer),
      Sanitize(me),
      Sanitize(zone)
    ))
  end
end

function Death:Preview()
  Cfg().showToasts = true
  ShowDeathToast(
    U.ShortName(U.PlayerName()),
    "mob",
    "Preview",
    U.L("DEATH_MELEE"),
    GetZoneText and GetZoneText() or "?"
  )
end

function Death:ResetLayout()
  local c = Cfg()
  c.point = nil
  c.scale = 1
  c.duration = 10.0
  c.locked = false
  if toast then ApplyToastLayout(toast) end
end

function Death:OnEnable()
  Cfg()

  GR:RegisterMessage("DEATH_UPDATE", function(_, victim, data)
    local cause = data.cause or (data.isPlayer and "player" or "mob")
    ShowDeathToast(
      U.ShortName(victim),
      cause,
      data.killer or "?",
      SpellForCause(cause, data.spell),
      data.zone or ""
    )
  end)

  local f = CreateFrame("Frame")
  -- Forever: COMBAT_LOG_EVENT_UNFILTERED RegisterEvent -> ADDON_ACTION_FORBIDDEN
  -- (chat: func=Frame:RegisterEvent during EnableModules, before LOADED). Skip CLEU.
  -- Forever: CLEU RegisterEvent -> ADDON_ACTION_FORBIDDEN — skip CLEU.
  U.SafeRegisterEvent(f, "PLAYER_DEAD")
  U.SafeRegisterEvent(f, "MIRROR_TIMER_START")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_DEAD" then
      Death:BroadcastLocalDeath()
    elseif event == "MIRROR_TIMER_START" then
      OnMirrorTimerStart(...)
    end
  end)

  if not tracker then
    tracker = CreateFrame("Frame")
    tracker:SetScript("OnUpdate", function(_, elapsed)
      PollFalling(elapsed)
    end)
  end
end
