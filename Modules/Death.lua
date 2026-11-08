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
  if cause == "unknown" then
    body = string.format(U.L("DEATH_TOAST_UNKNOWN"), victim, zone)
  elseif cause == "player" then
    body = string.format(U.L("DEATH_TOAST_PLAYER"), victim, killer, spell, zone)
  elseif cause == "mob" then
    body = string.format(U.L("DEATH_TOAST_MOB"), victim, killer, spell, zone)
  else
    body = string.format(U.L("DEATH_TOAST_ENV"), victim, spell, zone)
  end
  -- Badge always from code so old locale copies still show TOT/DEAD first.
  return string.format("|cffff3333%s|r  %s", U.L("DEATH_BADGE"), body)
end

local function DisplayDeathToast(item, done)
  if AngryMurlocsLevelUpToast and AngryMurlocsLevelUpToast.Hide then
    AngryMurlocsLevelUpToast:Hide()
  end
  local f = EnsureToast()
  ApplyToastLayout(f)
  RaiseToast(f)
  if f._hide then f._hide:Cancel() f._hide = nil end
  if f._fadeAfter then f._fadeAfter:Cancel() f._fadeAfter = nil end
  if UIFrameFadeRemoveFrame then
    UIFrameFadeRemoveFrame(f)
  end
  f.text:SetText(FormatDeathLine(item.victim, item.cause, item.killer, item.spell, item.zone))
  f:SetAlpha(1)
  f:Show()
  local dur = U.Clamp(tonumber(Cfg().duration) or 10.0, 1.5, 15)
  f._hide = C_Timer.NewTimer(dur, function()
    local function Finish()
      f:Hide()
      if done then done() end
    end
    if UIFrameFadeOut then
      UIFrameFadeOut(f, 0.5, 1, 0)
      f._fadeAfter = C_Timer.NewTimer(0.55, function()
        f._fadeAfter = nil
        Finish()
      end)
    else
      Finish()
    end
  end)
end

local function ShowDeathToast(victim, cause, killer, spell, zone)
  if not Cfg().showToasts then return end
  if GR.ToastQueue then
    GR.ToastQueue.Enqueue({
      kind = "death",
      victim = victim,
      cause = cause,
      killer = killer,
      spell = spell,
      zone = zone,
    })
    return
  end
  DisplayDeathToast({ victim = victim, cause = cause, killer = killer, spell = spell, zone = zone })
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

local function UnitKillerName(unit)
  if not unit or not UnitExists or not UnitExists(unit) then return nil end
  local name, realm = UnitName(unit)
  if UnitFullName then
    local n, r = UnitFullName(unit)
    if n then
      name = n
      realm = r
    end
  end
  if not name or name == "" then return nil end
  if realm and realm ~= "" then
    return U.NormalizeName(name .. "-" .. realm)
  end
  return U.NormalizeName(name)
end

-- reliable = the killer comes from a damage source record (CLEU killing blow).
-- Target / unit-token guesses are never reliable: target switches, DoTs, pets,
-- NPC and environment deaths would blame whoever happens to be targeted.
local function ResolveDeath()
  if lastHit.t > 0 and (U.Now() - lastHit.t) < 15 then
    local cause = lastHit.cause or (lastHit.isPlayer and "player" or "mob")
    return {
      killer = lastHit.name or U.L("UNKNOWN_KILLER"),
      isPlayer = lastHit.isPlayer,
      cause = cause,
      spell = SpellForCause(cause, lastHit.spell),
      reliable = true,
    }
  end

  -- No CLEU on Forever: only unit tokens. A hostile player there is a suspect,
  -- not a killer, so it is neither named nor counted.
  if UnitAffectingCombat("player") then
    for _, unit in ipairs({ "attacking", "target" }) do
      if UnitExists(unit) and (unit == "attacking" or (UnitCanAttack and UnitCanAttack("player", unit))) then
        if UnitIsPlayer(unit) then
          return {
            killer = U.L("UNKNOWN_KILLER"),
            isPlayer = false,
            cause = "unknown",
            spell = "",
            reliable = false,
            suspect = UnitKillerName(unit),
          }
        end
        return {
          killer = UnitKillerName(unit) or U.L("UNKNOWN_KILLER"),
          isPlayer = false,
          cause = "mob",
          spell = U.L("DEATH_MELEE"),
          reliable = false,
        }
      end
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

-- Missing IsInInstance means unknown context, which never counts as open world.
local function DeathContext()
  local ctx = { ctxKnown = false, instanceType = "unknown", inDuel = Death._inDuel and true or false }
  if IsInInstance then
    local inInst, instType = IsInInstance()
    ctx.ctxKnown = true
    ctx.instanceType = inInst and (instType or "unknown") or "none"
    if inInst and not instType then ctx.ctxKnown = false end
  end
  return ctx
end

-- Diagnostics: candidate killer sources, registered only while /am diag is on.
local DIAG_EVENTS = {
  "UNIT_COMBAT",
  "CHAT_MSG_COMBAT_HOSTILE_DEATH",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
  "CHAT_MSG_COMBAT_MISC_INFO",
  "CHAT_MSG_SYSTEM",
}
local DIAG_WINDOW = 10
local DIAG_KEEP = 60
local diagFrame
local diagRegistered = {}
local diagEvents = {}

local function DiagArgs(...)
  local parts = {}
  for i = 1, math.min(select("#", ...), 8) do
    parts[#parts + 1] = tostring((select(i, ...)))
  end
  local s = table.concat(parts, " | "):gsub("[%c]", " ")
  if #s > 160 then s = s:sub(1, 160) end
  return s
end

local function SetDeathCapture(on)
  if on then
    if not diagFrame then
      diagFrame = CreateFrame("Frame")
      diagFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_COMBAT" and (...) ~= "player" then return end
        diagEvents[#diagEvents + 1] = { t = U.Now(), text = event .. " " .. DiagArgs(...) }
        while #diagEvents > DIAG_KEEP do table.remove(diagEvents, 1) end
      end)
    end
    wipe(diagRegistered)
    for i = 1, #DIAG_EVENTS do
      if U.SafeRegisterEvent(diagFrame, DIAG_EVENTS[i]) then
        diagRegistered[#diagRegistered + 1] = DIAG_EVENTS[i]
      end
    end
  elseif diagFrame then
    diagFrame:UnregisterAllEvents()
    wipe(diagRegistered)
    wipe(diagEvents)
  end
end

local function SnapshotDeath(info, ctx, zone, verdict)
  local diag = GR.Diag
  if not diag or not diag:Enabled() then return end
  local now = U.Now()
  local lines = {}
  lines[#lines + 1] = string.format("apis: C_DeathInfo=%s GetDeathRecapLink=%s GetServerTime=%s CLEUinfo=%s",
    tostring(C_DeathInfo ~= nil), tostring(GetDeathRecapLink ~= nil),
    tostring(GetServerTime ~= nil), tostring(CombatLogGetCurrentEventInfo ~= nil))
  lines[#lines + 1] = string.format("units: attacking=%s target=%s targetPlayer=%s canAttack=%s",
    tostring(UnitExists("attacking")), tostring(UnitName("target")),
    tostring(UnitIsPlayer("target")), tostring(UnitCanAttack and UnitCanAttack("player", "target")))
  lines[#lines + 1] = "registered: " .. (#diagRegistered > 0 and table.concat(diagRegistered, ",") or "-")
  for i = 1, #diagEvents do
    local e = diagEvents[i]
    if (now - e.t) <= DIAG_WINDOW then
      lines[#lines + 1] = string.format("-%.1fs %s", now - e.t, e.text)
    end
  end
  diag:AddDeath({
    header = string.format("%s %s cause=%s reliable=%s suspect=%s ctx=%s duel=%s -> %s",
      date and date("%H:%M:%S") or "", zone or "?", tostring(info.cause), tostring(info.reliable),
      tostring(info.suspect), tostring(ctx.instanceType), tostring(ctx.inDuel), verdict),
    lines = lines,
  })
end

function Death:BroadcastLocalDeath()
  local info = ResolveDeath()
  local ctx = DeathContext()
  local zone = GetZoneText and GetZoneText() or ""
  local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
  local cause = info.cause or "env"
  local spell = SpellForCause(cause, info.spell)
  local me = U.ShortName(U.PlayerName())

  ShowDeathToast(me, cause, info.killer, spell, zone)
  GR:SendMessage("DEATH_UPDATE", U.NormalizeName(U.PlayerName()), {
    killer = info.killer or "?",
    isPlayer = cause == "player",
    zone = zone,
    cause = cause,
    spell = spell,
  })

  local verdict = "no_player"
  if cause == "player" or cause == "unknown" then
    local ok, why = GR.WantedLogic.EvaluateDeath({
      reliable = info.reliable,
      killer = info.killer,
      killerIsPlayer = cause == "player",
      ctxKnown = ctx.ctxKnown,
      instanceType = ctx.instanceType,
      inDuel = ctx.inDuel,
    })
    verdict = ok and "counted" or why
    if ok then
      local wanted = GR:GetModule("Wanted")
      if wanted and wanted.RecordOwnDeath then
        wanted:RecordOwnDeath(info.killer, zone)
      end
    elseif GR.Diag then
      GR.Diag:Reject(why, tostring(info.suspect or info.killer))
    end
  end
  SnapshotDeath(info, ctx, zone, verdict)

  if not IsInGuild() then return end
  Comm:Send(string.format(
    "DEATH|%s|%d|%s|%d|%s|%s",
    cause == "unknown" and "?" or Sanitize(info.killer),
    cause == "player" and 1 or 0,
    Sanitize(zone),
    mapId or 0,
    Sanitize(cause),
    Sanitize(spell)
  ), "kill", "death")
end

Death.ResolveDeath = ResolveDeath
Death.DeathContext = DeathContext

function Death:Preview()
  Cfg().showToasts = true
  DisplayDeathToast({
    victim = U.ShortName(U.PlayerName()),
    cause = "mob",
    killer = "Preview",
    spell = U.L("DEATH_MELEE"),
    zone = GetZoneText and GetZoneText() or "?",
  })
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
  if GR.ToastQueue then
    GR.ToastQueue.Register("death", DisplayDeathToast)
  end

  GR:RegisterMessage("DEATH_UPDATE", function(_, victim, data)
    if U.IsSelfName(victim) then return end
    data = data or {}
    local cause = data.cause or (data.isPlayer and "player" or "mob")
    ShowDeathToast(
      U.ShortName(victim),
      cause,
      data.killer or "?",
      SpellForCause(cause, data.spell),
      data.zone or ""
    )
  end)

  Death._inDuel = false
  local f = CreateFrame("Frame")
  -- Forever: CLEU RegisterEvent -> ADDON_ACTION_FORBIDDEN — skip CLEU.
  U.SafeRegisterEvent(f, "PLAYER_DEAD")
  U.SafeRegisterEvent(f, "MIRROR_TIMER_START")
  U.SafeRegisterEvent(f, "DUEL_REQUESTED")
  U.SafeRegisterEvent(f, "DUEL_FINISHED")
  U.SafeRegisterEvent(f, "DUEL_TO_THE_DEATH_REQUESTED")
  U.SafeRegisterEvent(f, "PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_DEAD" then
      Death:BroadcastLocalDeath()
    elseif event == "MIRROR_TIMER_START" then
      OnMirrorTimerStart(...)
    elseif event == "DUEL_REQUESTED" or event == "DUEL_TO_THE_DEATH_REQUESTED" then
      Death._inDuel = true
    elseif event == "DUEL_FINISHED" then
      Death._inDuel = false
    elseif event == "PLAYER_REGEN_ENABLED" then
      if GR.ToastQueue then GR.ToastQueue.OnCombatEnd() end
    end
  end)

  if not tracker then
    tracker = CreateFrame("Frame")
    tracker:SetScript("OnUpdate", function(_, elapsed)
      PollFalling(elapsed)
    end)
  end

  GR:RegisterMessage("DIAG_CHANGED", function(_, on)
    SetDeathCapture(on)
  end)
  if GR.Diag and GR.Diag:Enabled() then
    SetDeathCapture(true)
  end
end
