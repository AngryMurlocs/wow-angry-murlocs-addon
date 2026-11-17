local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Death = GR:NewModule("Death")

-- Forever (no CLEU): recent env hint from mirror timers / IsFalling
local envHint = {
  spell = nil,
  t = 0,
}
local ENV_HINT_TTL = 5
local toast
local fallTicker
local resolveTimer
local deathSerial = 0
local layoutEdit = false
local displayDone
local muteNextSound = false
local previewGen = 0

-- Wire / attribution spellKind codes (not locale keys). RAW = use legacy spell text.
local SPELLKIND_LOCALE = {
  MELEE = "DEATH_MELEE",
  RANGED = "DEATH_RANGED",
  UNKNOWN_ATTACK = "DEATH_UNKNOWN_ATTACK",
  ENV_FALL = "DEATH_ENV_FALL",
  ENV_DROWN = "DEATH_ENV_DROWN",
  ENV_FATIGUE = "DEATH_ENV_FATIGUE",
  ENV_LAVA = "DEATH_ENV_LAVA",
  ENV_SLIME = "DEATH_ENV_SLIME",
  ENV_FIRE = "DEATH_ENV_FIRE",
  ENV_OTHER = "DEATH_ENV_OTHER",
}

local MELEE_ENV_KINDS = {
  MELEE = true,
  ENV_FALL = true,
  ENV_DROWN = true,
  ENV_FATIGUE = true,
  ENV_LAVA = true,
  ENV_SLIME = true,
  ENV_FIRE = true,
  ENV_OTHER = true,
}

local ENV_TO_KIND = {
  FALLING = "ENV_FALL",
  FALL = "ENV_FALL",
  ["2"] = "ENV_FALL",
  DROWNING = "ENV_DROWN",
  DROWN = "ENV_DROWN",
  ["1"] = "ENV_DROWN",
  FATIGUE = "ENV_FATIGUE",
  EXHAUSTED = "ENV_FATIGUE",
  EXHAUSTION = "ENV_FATIGUE",
  ["0"] = "ENV_FATIGUE",
  LAVA = "ENV_LAVA",
  ["3"] = "ENV_LAVA",
  SLIME = "ENV_SLIME",
  ["4"] = "ENV_SLIME",
  FIRE = "ENV_FIRE",
  ["5"] = "ENV_FIRE",
}

-- Per-surface dedupe: key = normalize(victim)|eventId
local seenToast = {}
local seenFeed = {}
local eventIdSerial = 0
local pendingEventId -- reused across resolve retries for one death

local function ToastStyle()
  local s = GR.db.death and GR.db.death.toastStyle
  if s == "classic" then return "classic" end
  return "art"
end

local function Cfg()
  GR.db.death = GR.db.death or {}
  local c = GR.db.death
  if c.showToasts == nil then c.showToasts = true end
  if c.scale == nil then c.scale = 1 end
  if c.duration == nil then c.duration = 10.0 end
  if c.locked == nil then c.locked = false end
  c.toastStyle = ToastStyle()
  return c
end

local function DefaultPoint(f)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
end

local function ApplyToastLayout(f)
  if not f then return end
  local c = Cfg()
  U.ApplyPoint(f, c.point, DefaultPoint)
  f:SetScale(U.Clamp(tonumber(c.scale) or 1, 0.6, 1.6))
  if f.hint then
    f.hint:SetShown(layoutEdit or not c.locked)
  end
end

local function RaiseToast(f)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(500)
  if f.Raise then f:Raise() end
end

local function CancelDeathToastTimers()
  if toast then
    if toast._hide then toast._hide:Cancel() toast._hide = nil end
    if toast._fadeAfter then toast._fadeAfter:Cancel() toast._fadeAfter = nil end
  end
end

local function FinishDisplay()
  CancelDeathToastTimers()
  if toast then
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(toast) end
    toast:SetAlpha(1)
    toast:Hide()
  end
  local d = displayDone
  displayDone = nil
  if d then d() end
end

-- Drop orphan preview/edit timers without Resume (sibling takeover).
function Death:CancelPreview()
  previewGen = previewGen + 1
  CancelDeathToastTimers()
  displayDone = nil
  if not layoutEdit and toast then
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(toast) end
    toast:SetAlpha(1)
    toast:Hide()
  end
end

local function CancelSiblingPreview()
  local lvl = GR:GetModule("LevelUp")
  if lvl and lvl.CancelPreview then lvl:CancelPreview() end
end

local function DiscardToast()
  if not toast then return end
  CancelDeathToastTimers()
  if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(toast) end
  toast:Hide()
  toast:SetParent(nil)
  toast = nil
end

local function EnsureToast()
  local style = ToastStyle()
  if toast and toast._amToastStyle ~= style then
    DiscardToast()
  end
  if toast then
    ApplyToastLayout(toast)
    RaiseToast(toast)
    return toast
  end
  if style == "classic" then
    toast = GR.Theme.CreateClassicToast("AngryMurlocsDeathToastClassic", "death")
  else
    -- Art and text box: see GR.Theme.CreateArtToast and art/build_toasts.py
    toast = GR.Theme.CreateArtToast("AngryMurlocsDeathToast", "death", { 0.55, 0.52, 0.38, 0.46 },
      { textSize = 15, titleSize = 22, maxLines = 4, anchor = "top" })
  end
  RaiseToast(toast)
  toast.hint:SetText(U.L("TOAST_DRAG_HINT"))

  U.MakeMovable(toast, {
    getPoint = function() return Cfg().point end,
    setPoint = function(pt) Cfg().point = pt end,
    isLocked = function()
      if layoutEdit then return false end
      return Cfg().locked
    end,
    defaultFn = DefaultPoint,
  })

  ApplyToastLayout(toast)
  toast:Hide()
  return toast
end

function Death:HideToast()
  if toast then toast:Hide() end
end

local function EnvKindFromType(envType)
  return ENV_TO_KIND[tostring(envType or ""):upper()] or "ENV_OTHER"
end

local function ResolveSpellIdLocal(spellId)
  spellId = tonumber(spellId)
  if not spellId then return nil end
  if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
    if ok and type(info) == "table" then
      local name = info.name
      if type(issecretvalue) == "function" and issecretvalue(name) then name = nil end
      if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$")
        if name ~= "" then return name end
      end
    end
  end
  if type(GetSpellInfo) == "function" then
    local ok, name = pcall(GetSpellInfo, spellId)
    if ok and type(name) == "string" then
      if type(issecretvalue) == "function" and issecretvalue(name) then return nil end
      name = name:match("^%s*(.-)%s*$")
      if name ~= "" then return name end
    end
  end
  return nil
end

-- Locked attack-line resolve (receiver locale). See AGENTS.md synced notifications.
-- 1) confirmed melee/env kind → U.L
-- 2) spell-like → spellId first, then kind / legacy prose / unknown
-- 3) RAW / prose-only → legacy spell text
local function ResolveAttackLine(cause, spellKind, spellId, legacySpell)
  if cause == "unknown" then return "" end
  spellKind = tostring(spellKind or "")
  if spellKind ~= "" and MELEE_ENV_KINDS[spellKind] then
    local key = SPELLKIND_LOCALE[spellKind]
    return key and U.L(key) or U.L("DEATH_ENV_OTHER")
  end
  local legacy = type(legacySpell) == "string" and legacySpell or ""
  if legacy == U.L("UNKNOWN_KILLER") then legacy = "" end
  local hasId = tonumber(spellId) ~= nil
  local spellLike = hasId or spellKind == "RANGED" or spellKind == "UNKNOWN_ATTACK"
    or (cause == "player" or cause == "mob")
  if spellLike and (hasId or spellKind == "RANGED" or spellKind == "UNKNOWN_ATTACK" or legacy == "") then
    if hasId then
      local name = ResolveSpellIdLocal(spellId)
      if name then return name end
    end
    if spellKind == "RANGED" or spellKind == "UNKNOWN_ATTACK" then
      return U.L(SPELLKIND_LOCALE[spellKind])
    end
    if legacy ~= "" then return legacy end
    if cause == "env" then return U.L("DEATH_CAUSE_ENV") end
    return U.L("DEATH_UNKNOWN_ATTACK")
  end
  if legacy ~= "" then return legacy end
  if cause == "env" then return U.L("DEATH_CAUSE_ENV") end
  if cause == "player" or cause == "mob" then return U.L("DEATH_UNKNOWN_ATTACK") end
  return ""
end

local ALLIANCE_COLOR = "|cff0070dd"

local function KillerForDisplay(killer, faction, pet, cause)
  if type(killer) ~= "string" or killer == "" or killer == "?" then
    killer = U.L("UNKNOWN_KILLER")
  elseif cause == "player" and type(pet) == "string" and pet ~= "" then
    killer = string.format(U.L("DEATH_KILLER_PET"), killer, pet)
  end
  if faction == "A" then
    return ALLIANCE_COLOR .. killer .. " " .. U.L("DEATH_SIDE_ALLIANCE")
  end
  return killer
end

local function FormatDeathLine(victim, cause, killer, spell, zone, faction, pet)
  zone = (zone and zone ~= "") and zone or "?"
  killer = KillerForDisplay(killer, faction, pet, cause)
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
  return body
end

local function NewEventId()
  eventIdSerial = eventIdSerial + 1
  local t = math.floor((U.WallTime() or 0) * 1000) % 1000000000
  local r = math.random(1, 0x7FFFFFFF)
  return string.format("%x-%x-%x", t, r, eventIdSerial)
end

function Death.DedupeKey(victim, eventId)
  if type(eventId) ~= "string" or eventId == "" then return nil end
  local v = U.NormalizeName(victim) or tostring(victim or "")
  if v == "" then return nil end
  return v .. "|" .. eventId
end

function Death.TryClaimToast(victim, eventId)
  local key = Death.DedupeKey(victim, eventId)
  if not key then return true end -- no id: allow (legacy heuristic elsewhere)
  if seenToast[key] then return false end
  seenToast[key] = true
  return true
end

function Death.TryClaimFeed(victim, eventId)
  local key = Death.DedupeKey(victim, eventId)
  if not key then return true end
  if seenFeed[key] then return false end
  seenFeed[key] = true
  return true
end

function Death.ResetSeenForTest()
  wipe(seenToast)
  wipe(seenFeed)
  eventIdSerial = 0
  pendingEventId = nil
end

function Death.SpellKindLocaleKeys()
  return SPELLKIND_LOCALE
end

function Death.ResolveAttackLine(cause, spellKind, spellId, legacySpell)
  return ResolveAttackLine(cause, spellKind, spellId, legacySpell)
end

function Death.FormatDeathLine(victim, cause, killer, spell, zone, faction, pet)
  return FormatDeathLine(victim, cause, killer, spell, zone, faction, pet)
end

local function DisplayDeathToast(item, done)
  item = item or {}
  if not layoutEdit and not item._preview and not Cfg().showToasts then
    if done then done() end
    return
  end
  if not layoutEdit then
    local lvl = GR:GetModule("LevelUp")
    if lvl and lvl.HideToast then lvl:HideToast() end
  end
  local f = EnsureToast()
  ApplyToastLayout(f)
  RaiseToast(f)
  CancelDeathToastTimers()
  if UIFrameFadeRemoveFrame then
    UIFrameFadeRemoveFrame(f)
  end
  displayDone = done
  local attack = ResolveAttackLine(item.cause, item.spellKind, item.spellId, item.spell)
  local body = FormatDeathLine(item.victim, item.cause, item.killer, attack, item.zone, item.faction, item.pet)
  if f._amToastStyle == "classic" then
    body = body:gsub("\n", " · ")
    f.text:SetText("|cffff3333" .. U.L("DEATH_BADGE") .. "|r  " .. body)
  else
    -- Badge on its own larger line above the text (TOT / DEAD)
    if f.title then f.title:SetText("|cffff3333" .. U.L("DEATH_BADGE") .. "|r") end
    f.text:SetText(body)
  end
  f:SetAlpha(1)
  f:Show()

  if not muteNextSound and not layoutEdit and not item._preview then
    if GR.Sounds and GR.Sounds.Play then GR.Sounds.Play("death") end
  end
  muteNextSound = false

  if layoutEdit then
    return
  end

  local dur = U.Clamp(tonumber(Cfg().duration) or 10.0, 1.5, 15)
  f._hide = C_Timer.NewTimer(dur, function()
    local function Finish()
      FinishDisplay()
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

function Death:RebuildToast()
  local wasEdit = layoutEdit
  DiscardToast()
  if wasEdit then
    muteNextSound = true
    DisplayDeathToast({
      victim = U.ShortName(U.PlayerName()),
      cause = "mob",
      killer = "Preview",
      spell = U.L("DEATH_MELEE"),
      zone = GetZoneText and GetZoneText() or "?",
      _preview = true,
    }, nil)
  end
end

-- item: victim, cause, killer, spellKind, spellId, spell (legacy prose), zone, eventId
local function ShowDeathToast(item)
  item = item or {}
  if not Cfg().showToasts then return end
  if item.eventId and item.eventId ~= "" then
    if not Death.TryClaimToast(item.victim, item.eventId) then return end
  end
  if GR.ToastQueue then
    GR.ToastQueue.Enqueue({
      kind = "death",
      victim = item.victim,
      cause = item.cause,
      killer = item.killer,
      spell = item.spell,
      spellKind = item.spellKind,
      spellId = item.spellId,
      zone = item.zone,
      eventId = item.eventId,
      faction = item.faction,
      pet = item.pet,
    })
    return
  end
  DisplayDeathToast(item)
end

local function CacheEnvHint(kind)
  if type(kind) ~= "string" or kind == "" then return end
  envHint.spell = kind
  envHint.t = U.Now()
end

local function MirrorTimerToKind(timer)
  local t = tostring(timer or ""):upper()
  if t == "BREATH" then return "ENV_DROWN" end
  if t == "EXHAUSTION" or t == "FATIGUE" then return "ENV_FATIGUE" end
  return nil
end

local function OnMirrorTimerStart(timer, value, _, scale, paused)
  local kind = MirrorTimerToKind(timer)
  if not kind then return end
  if type(issecretvalue) == "function" and (issecretvalue(value) or issecretvalue(scale) or issecretvalue(paused)) then return end
  -- A visible breath bar is not drowning damage. Only a depleted, running
  -- timer is even a hint; it never establishes a killing blow by itself.
  if type(value) == "number" and value <= 0 and type(scale) == "number" and scale < 0
    and (paused == nil or paused == false or paused == 0) then
    CacheEnvHint(kind)
  elseif envHint.spell == kind then
    envHint.spell, envHint.t = nil, 0
  end
end

local function OnMirrorTimerStop(timer)
  if envHint.spell == MirrorTimerToKind(timer) then
    envHint.spell, envHint.t = nil, 0
  end
end

local function PollFalling()
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  if IsFalling and IsFalling() then
    CacheEnvHint("ENV_FALL")
  elseif envHint.spell == "ENV_FALL" then
    envHint.spell, envHint.t = nil, 0
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

local function Plain(v)
  if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
  return v
end

-- Fetch Death Recap event tables (Forever: CLEU off, Recap often still works).
local function FetchRecapEvents()
  if C_DeathRecap and type(C_DeathRecap.GetRecapEvents) == "function" then
    local ok, events = pcall(C_DeathRecap.GetRecapEvents)
    events = ok and Plain(events) or nil
    if type(events) == "table" and #events > 0 then
      return events, "C_DeathRecap.GetRecapEvents"
    end
  end
  if type(DeathRecap_GetEvents) == "function" then
    local ok, events = pcall(DeathRecap_GetEvents)
    events = ok and Plain(events) or nil
    if type(events) == "table" and #events > 0 then
      return events, "DeathRecap_GetEvents"
    end
  end
  -- ID 1 can describe a historical death. Never substitute it for the current
  -- default recap, which may still be unavailable on the PLAYER_DEAD frame.
  return nil
end

local function PlainNumber(v)
  v = Plain(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function PlainName(v)
  v = Plain(v)
  if type(v) ~= "string" then return nil end
  v = v:match("^%s*(.-)%s*$")
  return v ~= "" and v or nil
end

local function IsSecret(v)
  return type(issecretvalue) == "function" and v ~= nil and issecretvalue(v) or false
end

-- Combat-log source flags. Single bits, so a missing bit library still works.
local FLAG_FRIENDLY = 0x10
local FLAG_HOSTILE = 0x40
local FLAG_CONTROL_PLAYER = 0x100
local FLAG_TYPE_PLAYER = 0x400
local FLAG_TYPE_PET = 0x1000
local FLAG_TYPE_GUARDIAN = 0x2000

local function HasBit(flags, mask)
  if type(flags) ~= "number" or type(mask) ~= "number" or mask == 0 then return false end
  if bit and type(bit.band) == "function" then
    return bit.band(flags, mask) == mask
  end
  return math.floor(flags / mask) % 2 == 1
end

local function RecapEventFields(ev)
  local rawName = ev.sourceName
  if rawName == nil then rawName = ev[5] end
  local rawGuid = ev.sourceGUID
  if rawGuid == nil then rawGuid = ev[4] end
  return {
    event = PlainName(Plain(ev.event) or Plain(ev[2])),
    sourceName = PlainName(rawName),
    sourceGUID = PlainName(rawGuid),
    nameSecret = IsSecret(rawName),
    guidSecret = IsSecret(rawGuid),
    sourceFlags = PlainNumber(ev.sourceFlags),
    spellName = PlainName(ev.spellName),
    spellId = PlainNumber(Plain(ev.spellId) or Plain(ev.spellID)),
    environmentalType = Plain(Plain(ev.environmentalType) or Plain(ev.envType)),
    timestamp = PlainNumber(ev.timestamp),
    timestampSecret = IsSecret(ev.timestamp),
    overkill = PlainNumber(ev.overkill),
    amount = PlainNumber(ev.amount),
    currentHP = PlainNumber(ev.currentHP),
  }
end

local function IsRecapDamageEvent(evName)
  evName = tostring(evName or "")
  if evName == "" then return false end
  if evName == "ENVIRONMENTAL_DAMAGE" then return true end
  return evName:match("_DAMAGE$") ~= nil or evName == "DAMAGE_SHIELD" or evName == "DAMAGE_SPLIT"
end

-- Structured attack facts from a recap hit (no U.L; keep spellId).
local function AttackFromRecap(f)
  local evName = tostring(f.event or "")
  if evName == "ENVIRONMENTAL_DAMAGE" then
    return { spellKind = EnvKindFromType(f.environmentalType), spellId = nil, spell = nil }
  end
  if evName == "SWING_DAMAGE" then
    return { spellKind = "MELEE", spellId = f.spellId, spell = nil }
  end
  local kind = nil
  if not f.spellName then
    kind = (evName == "RANGE_DAMAGE") and "RANGED" or "UNKNOWN_ATTACK"
  elseif evName == "RANGE_DAMAGE" and not f.spellId then
    kind = "RANGED"
  end
  return { spellKind = kind, spellId = f.spellId, spell = f.spellName }
end

-- Name is the 6th return, realm the 7th. Realm is appended before normalize.
local function NameFromPlayerGUID(guid)
  if type(guid) ~= "string" or not guid:find("^Player%-") then return nil end
  if type(GetPlayerInfoByGUID) ~= "function" then return nil end
  local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
  if not ok then return nil end
  name = PlainName(name)
  if not name then return nil end
  realm = PlainName(realm)
  if realm then return U.NormalizeName(name .. "-" .. realm) end
  return U.NormalizeName(name)
end

local function SameGuid(unit, guid)
  if type(UnitGUID) ~= "function" then return false end
  if UnitExists and not UnitExists(unit) then return false end
  local ok, got = pcall(UnitGUID, unit)
  got = ok and PlainName(got) or nil
  return got == guid
end

-- Owner only from a unit whose GUID is this pet. Never from the current target.
local function TokenForGUID(guid)
  if type(guid) ~= "string" or guid == "" then return nil end
  if type(UnitTokenFromGUID) == "function" then
    local ok, token = pcall(UnitTokenFromGUID, guid)
    token = ok and PlainName(token) or nil
    if token then return token end
  end
  if SameGuid("targetpet", guid) then return "targetpet" end
  if SameGuid("focuspet", guid) then return "focuspet" end
  if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for i = 1, #plates do
        local plate = plates[i]
        local token = type(plate) == "table" and (plate.namePlateUnitToken or plate.unitToken) or nil
        if type(token) == "string" and SameGuid(token, guid) then return token end
      end
    end
  end
  return nil
end

local function OwnerNameFromPetGUID(guid)
  local token = TokenForGUID(guid)
  if not token or type(UnitOwnerGUID) ~= "function" then return nil end
  local ok, ownerGuid = pcall(UnitOwnerGUID, token)
  ownerGuid = ok and PlainName(ownerGuid) or nil
  if not ownerGuid then return nil end
  return NameFromPlayerGUID(ownerGuid)
end

local function IsPlayerControlledCompanion(guid, flags)
  if not HasBit(flags, FLAG_CONTROL_PLAYER) then return false end
  if HasBit(flags, FLAG_TYPE_PET) or HasBit(flags, FLAG_TYPE_GUARDIAN) then return true end
  if guid:find("^Pet%-") or guid:find("^Vehicle%-") then return true end
  return false
end

local function SelfSide()
  if type(UnitFactionGroup) ~= "function" then return nil end
  local ok, fac = pcall(UnitFactionGroup, "player")
  if not ok then return nil end
  fac = Plain(fac)
  if fac == "Alliance" then return "A" end
  if fac == "Horde" then return "H" end
  return nil
end

-- Hostile/friendly is relative to the dead player. Absolute side is what we send.
local function FactionFromFlags(flags)
  if type(flags) ~= "number" then return nil end
  local side = SelfSide()
  if not side then return nil end
  local hostile = HasBit(flags, FLAG_HOSTILE)
  local friendly = HasBit(flags, FLAG_FRIENDLY)
  if hostile == friendly then return nil end
  if friendly then return side end
  return side == "A" and "H" or "A"
end

local function ApplyFaction(info)
  if type(info) ~= "table" or info.faction then return info end
  if info.cause ~= "player" and not info.companion then return info end
  info.faction = FactionFromFlags(info.flags)
  return info
end

local function HitResult(pick, atk, extra)
  local info = {
    killer = extra.killer,
    isPlayer = extra.isPlayer and true or false,
    cause = extra.cause,
    spell = atk.spell,
    spellKind = atk.spellKind,
    spellId = atk.spellId,
    reliable = extra.reliable and true or false,
    source = "recap",
    lethal = pick.lethal,
    timestamp = pick.timestamp,
    suspect = extra.suspect,
    flags = pick.sourceFlags,
    pet = extra.pet,
    companion = extra.companion and true or false,
    pending = extra.pending and true or false,
  }
  return info
end

-- Recap event list -> attribution. Owner lookup uses unit tokens when present.
-- A Player-* GUID, or a plain name plus the player flag, is a reliable player kill.
local function AttributionFromRecapEvents(events, context)
  events = Plain(events)
  if type(events) ~= "table" then return nil end
  local pick
  -- Blizzard's recap marks its first entry as causedDeath. Explicit lethal
  -- fields and timestamps also support clients returning a different order.
  for i = 1, #events do
    local ev = Plain(events[i])
    if type(ev) == "table" then
      local f = RecapEventFields(ev)
      if context then
        -- Keep only plain fields, never raw API tables, for the later dump.
        context.events[#context.events + 1] = f
        f.index = i
        f.hasSecret = f.nameSecret or f.guidSecret
        for _, key in ipairs({ "event", 2, "sourceFlags", "timestamp", "amount", "overkill", "currentHP" }) do
          if IsSecret(ev[key]) then f.hasSecret = true end
        end
        context.hasSecret = context.hasSecret or f.hasSecret
      end
      if IsRecapDamageEvent(f.event) and (f.amount == nil or f.amount > 0) then
        f.lethal = (f.overkill ~= nil and f.overkill >= 0) or (f.currentHP ~= nil and f.currentHP <= 0)
        if not pick or (f.lethal and not pick.lethal)
          or (f.lethal == pick.lethal and f.timestamp and pick.timestamp and f.timestamp > pick.timestamp) then
          pick = f
        end
      end
    elseif context and IsSecret(events[i]) then
      context.hasSecret = true
    end
  end
  if context then context.pickedFields = pick end
  if not pick then return nil end

  local guid = tostring(pick.sourceGUID or "")
  local name = pick.sourceName
  local atk = AttackFromRecap(pick)

  -- A recap containing only explicitly nonlethal hits is incomplete. Its last
  -- known attacker is a suspect, not a killing-blow source for toast or Wanted.
  if not pick.lethal and pick.overkill ~= nil and pick.overkill < 0 then
    return {
      killer = nil, isPlayer = false, cause = "unknown",
      spell = "", spellKind = nil, spellId = nil,
      reliable = false, source = "recap", suspect = name,
      lethal = false, timestamp = pick.timestamp,
    }
  end

  if pick.event == "ENVIRONMENTAL_DAMAGE" then
    return {
      killer = nil, isPlayer = false, cause = "env",
      spell = atk.spell, spellKind = atk.spellKind, spellId = atk.spellId,
      reliable = false, source = "recap",
      lethal = pick.lethal, timestamp = pick.timestamp,
    }
  end

  -- A player-controlled pet or guardian belongs to its owner, not to the pet name.
  if IsPlayerControlledCompanion(guid, pick.sourceFlags) then
    if not pick.guidSecret and guid ~= "" then
      local owner = OwnerNameFromPetGUID(guid)
      if owner then
        return HitResult(pick, atk, {
          killer = owner, isPlayer = true, cause = "player", reliable = true,
          pet = name, companion = true,
        })
      end
      return HitResult(pick, atk, {
        killer = name, isPlayer = false, cause = "mob", reliable = false,
        pet = name, companion = true, pending = true,
      })
    end
    return HitResult(pick, atk, {
      killer = name, isPlayer = false, cause = "mob", reliable = false,
      pet = name, companion = true, pending = pick.nameSecret or pick.guidSecret,
    })
  end

  local playerGuid = guid:find("^Player%-") ~= nil
  if playerGuid or (name and HasBit(pick.sourceFlags, FLAG_TYPE_PLAYER)) then
    local killer = name
    if playerGuid and not killer then
      killer = NameFromPlayerGUID(guid)
    end
    if killer then
      return HitResult(pick, atk, {
        killer = killer, isPlayer = true, cause = "player", reliable = true,
      })
    end
    return HitResult(pick, atk, { cause = "unknown", pending = true })
  end

  if guid:find("^Creature%-") or guid:find("^Vehicle%-") or guid:find("^Pet%-") then
    return HitResult(pick, atk, {
      killer = name, isPlayer = false, cause = "mob", reliable = false,
    })
  end

  -- Secret name or GUID may become readable after combat. Do not guess a target.
  if pick.nameSecret or pick.guidSecret then
    return HitResult(pick, atk, { cause = "unknown", pending = true })
  end

  -- An incomplete identity does not prove either a mob or an environmental kill.
  return HitResult(pick, atk, { cause = "unknown", suspect = name })
end

local function ReadRecapAttribution(deathWall, context)
  context = context or {}
  context.events = {}
  local events, src = FetchRecapEvents()
  context.source = src
  context.deathWall = deathWall or U.WallTime()
  local info = AttributionFromRecapEvents(events, context)
  context.picked = info
  context.pending = info and info.pending or false
  if not info then
    context.rejectReason = events and "no_damage_candidate" or "empty"
    return nil
  end
  -- Known epoch timestamps must match this death. Relative-time client formats
  -- are not compared to a different clock domain.
  deathWall = context.deathWall
  if info.timestamp and info.timestamp >= 1000000000 and deathWall >= 1000000000
    and (info.timestamp < deathWall - 2 or info.timestamp > deathWall + 2) then
    context.rejectReason = "epoch_out_of_window"
    return nil
  end
  context.rejectReason = info.pending and "pending" or (info.cause == "unknown" and "incomplete" or "accepted")
  return info
end

-- reliable = Death Recap with Player-* GUID. Forever has no usable combat log.
-- Target / unit-token guesses are never reliable: target switches, DoTs, pets,
-- NPC and environment deaths would blame whoever happens to be targeted.
local function ResolveRecapDeath(deathWall, context)
  -- Forever (no CLEU): Death Recap is the honest killer source for toast + Wanted.
  local hint = FreshEnvHint()
  local recap = ReadRecapAttribution(deathWall, context)
  if recap then
    -- A recent fall/depleted timer can contradict an incomplete recap, but is
    -- never sufficient to override an explicitly lethal mob/player hit.
    -- A still-secret identity keeps waiting; the fall hint must not replace it.
    if recap.pending or not hint or recap.lethal or recap.cause == "env" then
      return ApplyFaction(recap)
    end
    return {
      killer = nil, isPlayer = false, cause = "unknown",
      spell = "", spellKind = nil, spellId = nil,
      reliable = false, source = "hint", envHint = hint,
    }
  end

  -- Unit tokens: hostile player is a suspect only — never counted / named as killer.
  if UnitAffectingCombat("player") then
    for _, unit in ipairs({ "attacking", "target" }) do
      if UnitExists(unit) and (unit == "attacking" or (UnitCanAttack and UnitCanAttack("player", unit))) then
        return {
          killer = nil,
          isPlayer = false,
          cause = "unknown",
          spell = "",
          spellKind = nil,
          spellId = nil,
          reliable = false,
          suspect = UnitKillerName(unit),
          envHint = hint,
          source = "unit",
        }
      end
    end
  end

  return {
    killer = nil,
    isPlayer = false,
    cause = "unknown",
    spell = "",
    spellKind = nil,
    spellId = nil,
    reliable = false,
    envHint = hint,
    source = "fallback",
  }
end

local function ResolveDeath(deathWall)
  local context = {}
  local info = ResolveRecapDeath(deathWall, context)
  return info, context
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
  "CHAT_MSG_COMBAT_MISC_INFO",
  "CHAT_MSG_SYSTEM",
}
local DIAG_WINDOW = 10
local DIAG_KEEP = 60
local diagFrame
local diagRegistered = {}
local diagEvents = {}

-- Forever: UNIT_COMBAT amount can be secret; table.concat rejects secrets.
local function DiagSafeArg(v)
  if type(issecretvalue) == "function" and issecretvalue(v) then
    return "<secret:" .. type(v) .. ">", true
  end
  local ok, s = pcall(tostring, v)
  if not ok then
    return "<tostring-err>", true
  end
  if type(issecretvalue) == "function" and issecretvalue(s) then
    return "<secret:" .. type(v) .. ">", true
  end
  return s, false
end

local function DiagArgs(...)
  local parts = {}
  for i = 1, math.min(select("#", ...), 8) do
    parts[#parts + 1] = (DiagSafeArg((select(i, ...))))
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

-- Diag-only dump of Recap tables (attribution itself uses the same FetchRecapEvents).
local function ClipDiag(s, maxLen)
  s = tostring(s or ""):gsub("[%c]", " ")
  maxLen = maxLen or 80
  if #s > maxLen then s = s:sub(1, maxLen) end
  return s
end

local function GuidKind(guid)
  guid = tostring(guid or "")
  if guid == "" then return "-" end
  local kind = guid:match("^([%w]+)%-")
  return kind or "?"
end

local function AppendRecapDump(lines, context)
  local hasCRecap = C_DeathRecap ~= nil
  local hasGetEvents = hasCRecap and type(C_DeathRecap.GetRecapEvents) == "function"
  local hasHasEvents = hasCRecap and type(C_DeathRecap.HasRecapEvents) == "function"
  local hasLegacy = type(DeathRecap_GetEvents) == "function"
  local hasLink = type(GetDeathRecapLink) == "function"
  lines[#lines + 1] = string.format(
    "recap apis: C_DeathRecap=%s GetRecapEvents=%s HasRecapEvents=%s DeathRecap_GetEvents=%s GetDeathRecapLink=%s",
    tostring(hasCRecap), tostring(hasGetEvents), tostring(hasHasEvents),
    tostring(hasLegacy), tostring(hasLink)
  )

  if not context then
    lines[#lines + 1] = "recap: supplied attribution (no snapshot)"
    return
  end
  lines[#lines + 1] = string.format("recap: via=%s deathWall=%s result=%s pending=%s",
    tostring(context.source or "none"), tostring(context.deathWall),
    tostring(context.rejectReason), tostring(context.pending))
  for _, f in ipairs(context.events) do
    local reason = "not_selected"
    if f == context.pickedFields then
      reason = context.rejectReason
    elseif not IsRecapDamageEvent(f.event) then
      reason = "not_damage"
    elseif f.amount and f.amount <= 0 then
      reason = "nonpositive_damage"
    end
    local delta = "n/a"
    if f.timestamp and f.timestamp >= 1000000000 and f.timestamp < 100000000000
      and context.deathWall >= 1000000000 then
      delta = tostring(f.timestamp - context.deathWall)
    end
    lines[#lines + 1] = string.format(
      "recap[%d]: event=%s source=%s guid=%s amount=%s timestamp=%s delta=%s lethal=%s overkill=%s secret=%s result=%s",
      f.index, ClipDiag(f.event, 40), ClipDiag(f.sourceName, 40), GuidKind(f.sourceGUID),
      tostring(f.amount), f.timestampSecret and "secret" or tostring(f.timestamp), delta,
      tostring(f.lethal), tostring(f.overkill), tostring(f.hasSecret), tostring(reason))
  end
end

local function SnapshotDeath(info, ctx, zone, verdict, recapContext)
  local diag = GR.Diag
  if not diag or not diag:Enabled() then return end
  local now = U.Now()
  local lines = {}
  lines[#lines + 1] = string.format(
    "apis: C_DeathInfo=%s C_DeathRecap=%s GetDeathRecapLink=%s DeathRecap_GetEvents=%s GetServerTime=%s CLEUinfo=%s",
    tostring(C_DeathInfo ~= nil),
    tostring(C_DeathRecap ~= nil),
    tostring(GetDeathRecapLink ~= nil),
    tostring(DeathRecap_GetEvents ~= nil),
    tostring(GetServerTime ~= nil),
    tostring(CombatLogGetCurrentEventInfo ~= nil)
  )
  lines[#lines + 1] = string.format("units: attacking=%s target=%s targetPlayer=%s canAttack=%s",
    tostring(Plain(UnitExists("attacking"))), tostring(Plain(UnitName("target"))),
    tostring(Plain(UnitIsPlayer("target"))), tostring(Plain(UnitCanAttack and UnitCanAttack("player", "target"))))
  AppendRecapDump(lines, recapContext)
  lines[#lines + 1] = "registered: " .. (#diagRegistered > 0 and table.concat(diagRegistered, ",") or "-")
  for i = 1, #diagEvents do
    local e = diagEvents[i]
    if (now - e.t) <= DIAG_WINDOW then
      lines[#lines + 1] = string.format("-%.1fs %s", now - e.t, e.text)
    end
  end
  diag:AddDeath({
    header = string.format("%s %s cause=%s reliable=%s source=%s suspect=%s ctx=%s duel=%s -> %s",
      date and date("%H:%M:%S") or "", zone or "?", tostring(info.cause), tostring(info.reliable),
      tostring(info.source), tostring(info.suspect), tostring(ctx.instanceType), tostring(ctx.inDuel), verdict),
    lines = lines,
  })
end

local function CaptureDeathContext()
  return {
    ctx = DeathContext(),
    zone = GetZoneText and GetZoneText() or "",
    mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0,
    wallTime = U.WallTime(),
  }
end

function Death:BroadcastLocalDeath(info, snapshot, recapContext)
  snapshot = snapshot or CaptureDeathContext()
  if not info then info, recapContext = ResolveDeath(snapshot.wallTime) end
  ApplyFaction(info)
  local ctx, zone, mapId = snapshot.ctx, snapshot.zone, snapshot.mapId
  local cause = info.cause or "unknown"
  local spellKind = info.spellKind
  local spellId = info.spellId
  -- Compat: always fill legacy spell with sender-locale display prose for old peers.
  local legacySpell = ResolveAttackLine(cause, spellKind, spellId, info.spell)
  local eventId = snapshot.eventId or pendingEventId or NewEventId()
  snapshot.eventId = eventId
  pendingEventId = nil
  local fullName = U.NormalizeName(U.PlayerName())
  local killerWire = (cause == "unknown" or not info.killer or info.killer == "") and "?" or Sanitize(info.killer)
  local faction = (info.faction == "A" or info.faction == "H") and info.faction or nil
  local pet = (type(info.pet) == "string" and info.pet ~= "") and info.pet or nil

  -- No local toast. Guildmates still get DEATH_UPDATE and the guild message.
  GR:SendMessage("DEATH_UPDATE", fullName, {
    killer = killerWire,
    isPlayer = cause == "player",
    zone = zone,
    mapId = mapId,
    cause = cause,
    spell = legacySpell,
    spellKind = spellKind,
    spellId = spellId,
    eventId = eventId,
    faction = faction,
    pet = pet,
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
  SnapshotDeath(info, ctx, zone, verdict, recapContext)

  if not IsInGuild() then return end
  -- DEATH|killer|isPlayer|zone|mapId|cause|spell|eventId|spellKind|spellId|faction|pet
  Comm:Send(string.format(
    "DEATH|%s|%d|%s|%d|%s|%s|%s|%s|%s|%s|%s",
    killerWire,
    cause == "player" and 1 or 0,
    Sanitize(zone),
    mapId or 0,
    Sanitize(cause),
    Sanitize(legacySpell),
    Sanitize(eventId),
    Sanitize(spellKind or ""),
    spellId and tostring(math.floor(tonumber(spellId) or 0)) or "",
    faction or "",
    Sanitize(pet or "")
  ), "kill", "death")
end

local function CancelPendingDeath()
  deathSerial = deathSerial + 1
  pendingEventId = nil
  if resolveTimer then resolveTimer:Cancel() resolveTimer = nil end
end

local function ClearDeathEvidence()
  envHint.spell, envHint.t = nil, 0
end

-- Drop the wait flag once retries are exhausted. A pet with no owner stays a mob.
local function ReleasePending(info)
  if not info or not info.pending then return info end
  info.pending = false
  if info.cause == "player" and info.reliable then return info end
  if info.companion then
    info.cause = "mob"
    info.isPlayer = false
    info.reliable = false
    return info
  end
  info.cause = "unknown"
  info.isPlayer = false
  info.reliable = false
  info.killer = nil
  return info
end

local function QueueLocalDeath()
  CancelPendingDeath()
  local serial = deathSerial
  local snapshot = CaptureDeathContext()
  snapshot.eventId = NewEventId()
  pendingEventId = snapshot.eventId
  -- Short waits when the recap is simply empty. Longer waits while a name,
  -- GUID, or pet owner is still secret.
  local SHORT = { 0.15, 0.35, 0.5 }
  local LONG = { 0.2, 0.5, 1.0, 2.0, 4.0 }
  local attempt = 0
  local function TryResolve()
    resolveTimer = nil
    if serial ~= deathSerial or not Death.enabled then return end
    if attempt > 0 and UnitIsDeadOrGhost and not UnitIsDeadOrGhost("player") then return end
    local info, recapContext = ResolveDeath(snapshot.wallTime)
    local waits = (info and info.pending) and LONG or SHORT
    local settled = info and not info.pending and (
      info.source == "cleu" or (info.source == "recap" and info.cause ~= "unknown") or attempt >= #waits
    )
    if not settled and info and info.pending and attempt >= #waits then
      ReleasePending(info)
      settled = true
    end
    if not settled and info and not info.pending and attempt >= #SHORT then
      settled = true
    end
    if settled then
      Death:BroadcastLocalDeath(info, snapshot, recapContext)
      ClearDeathEvidence()
      return
    end
    attempt = attempt + 1
    local delay = waits[attempt]
    if not delay then
      if info and info.pending then ReleasePending(info) end
      Death:BroadcastLocalDeath(info, snapshot, recapContext)
      ClearDeathEvidence()
      return
    end
    resolveTimer = C_Timer.NewTimer(delay, TryResolve)
  end
  TryResolve()
end

Death.ResolveDeath = ResolveDeath
Death.DeathContext = DeathContext
Death.AttributionFromRecapEvents = AttributionFromRecapEvents
Death.ReadRecapAttribution = ReadRecapAttribution

function Death:Preview()
  CancelSiblingPreview()
  if layoutEdit then
    muteNextSound = true
    DisplayDeathToast({
      victim = U.ShortName(U.PlayerName()),
      cause = "mob",
      killer = "Preview",
      spell = U.L("DEATH_MELEE"),
      zone = GetZoneText and GetZoneText() or "?",
      _preview = true,
    }, nil)
    if toast and toast.ClampToScreen then toast:ClampToScreen() end
    return
  end
  if GR.ToastQueue then
    GR.ToastQueue.Pause()
    GR.ToastQueue.FinishCurrent()
  else
    FinishDisplay()
  end
  previewGen = previewGen + 1
  local token = previewGen
  muteNextSound = true
  DisplayDeathToast({
    victim = U.ShortName(U.PlayerName()),
    cause = "mob",
    killer = "Preview",
    spell = U.L("DEATH_MELEE"),
    zone = GetZoneText and GetZoneText() or "?",
    _preview = true,
  }, function()
    if token ~= previewGen then return end
    if GR.ToastQueue and not layoutEdit then
      GR.ToastQueue.Resume()
    end
  end)
  if toast and toast.ClampToScreen then
    toast:ClampToScreen()
  end
end

function Death:RefreshLayout()
  if toast then ApplyToastLayout(toast) end
end

function Death:BeginLayoutEdit()
  -- Caller (Options) must Pause + FinishCurrent first.
  CancelSiblingPreview()
  previewGen = previewGen + 1
  layoutEdit = true
  CancelDeathToastTimers()
  displayDone = nil
  muteNextSound = true
  DisplayDeathToast({
    victim = U.ShortName(U.PlayerName()),
    cause = "mob",
    killer = "Preview",
    spell = U.L("DEATH_MELEE"),
    zone = GetZoneText and GetZoneText() or "?",
    _preview = true,
  }, nil)
  ApplyToastLayout(toast)
end

function Death:EndLayoutEdit()
  if not layoutEdit then return end
  layoutEdit = false
  FinishDisplay()
  if toast then
    toast:StopMovingOrSizing()
    ApplyToastLayout(toast)
  end
end

function Death:IsLayoutEdit()
  return layoutEdit
end

function Death:ResetPosition()
  Cfg().point = nil
  if toast then ApplyToastLayout(toast) end
end

function Death:ResetAppearance()
  local c = Cfg()
  c.scale = 1
  c.duration = 10.0
  c.toastStyle = "art"
  DiscardToast()
end

function Death:ResetLayout()
  self:ResetPosition()
  self:ResetAppearance()
end

function Death:OnEnable()
  if self.enabled then return end
  self.enabled = true

  Cfg()
  if GR.ToastQueue then
    GR.ToastQueue.Register("death", DisplayDeathToast)
    GR.ToastQueue.RegisterFinishHook("death", FinishDisplay)
  end

  GR:BindMessage(self, "DEATH_UPDATE", function(_, victim, data)
    if U.IsSelfName(victim) then return end
    data = data or {}
    local cause = data.cause or (data.isPlayer and "player" or "mob")
    ShowDeathToast({
      victim = U.ShortName(victim),
      cause = cause,
      killer = data.killer,
      spell = data.spell,
      spellKind = data.spellKind,
      spellId = data.spellId,
      zone = data.zone or "",
      eventId = data.eventId,
      faction = data.faction,
      pet = data.pet,
    })
  end)

  Death._inDuel = false
  local f = CreateFrame("Frame")
  self._eventFrame = f
  -- Forever: CLEU RegisterEvent -> ADDON_ACTION_FORBIDDEN — skip CLEU.
  U.SafeRegisterEvent(f, "PLAYER_DEAD")
  U.SafeRegisterEvent(f, "PLAYER_ALIVE")
  U.SafeRegisterEvent(f, "PLAYER_UNGHOST")
  U.SafeRegisterEvent(f, "MIRROR_TIMER_START")
  U.SafeRegisterEvent(f, "MIRROR_TIMER_STOP")
  U.SafeRegisterEvent(f, "MIRROR_TIMER_PAUSE")
  U.SafeRegisterEvent(f, "DUEL_REQUESTED")
  U.SafeRegisterEvent(f, "DUEL_FINISHED")
  U.SafeRegisterEvent(f, "DUEL_TO_THE_DEATH_REQUESTED")
  U.SafeRegisterEvent(f, "PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_DEAD" then
      QueueLocalDeath()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
      -- PLAYER_ALIVE also accompanies releasing spirit. Ghosts are still dead
      -- and must retain the pending report until the recap/retry completes.
      if event == "PLAYER_UNGHOST" or not UnitIsDeadOrGhost or not UnitIsDeadOrGhost("player") then
        CancelPendingDeath()
        ClearDeathEvidence()
      end
    elseif event == "MIRROR_TIMER_START" then
      OnMirrorTimerStart(...)
    elseif event == "MIRROR_TIMER_STOP" then
      OnMirrorTimerStop(...)
    elseif event == "MIRROR_TIMER_PAUSE" then
      local timer, paused = ...
      if paused and paused ~= 0 then OnMirrorTimerStop(timer) end
    elseif event == "DUEL_REQUESTED" or event == "DUEL_TO_THE_DEATH_REQUESTED" then
      Death._inDuel = true
    elseif event == "DUEL_FINISHED" then
      Death._inDuel = false
    elseif event == "PLAYER_REGEN_ENABLED" then
      if GR.ToastQueue then GR.ToastQueue.OnCombatEnd() end
    end
  end)

  if not fallTicker then
    fallTicker = C_Timer.NewTicker(0.5, PollFalling)
  end

  GR:BindMessage(self, "DIAG_CHANGED", function(_, on)
    SetDeathCapture(on)
  end)
  if GR.Diag and GR.Diag:Enabled() then
    SetDeathCapture(true)
  end
end

function Death:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  CancelPendingDeath()
  ClearDeathEvidence()
  if layoutEdit then
    self:EndLayoutEdit()
    if GR.ToastQueue and GR.ToastQueue.Resume then GR.ToastQueue.Resume() end
  end
  GR:UnbindMessages(self)
  GR:ReleaseEventFrame(self._eventFrame)
  self._eventFrame = nil
  if fallTicker then
    fallTicker:Cancel()
    fallTicker = nil
  end
  SetDeathCapture(false)
end
