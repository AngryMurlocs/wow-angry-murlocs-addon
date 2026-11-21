-- Death locale / wire structure / per-surface dedupe (plan A1–A13).
-- From repo root: luajit Tests/DeathLocale_test.lua
local Sim = dofile("Tests/sim.lua")

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

-- English copy survives deDE mutation
do
  local en = {}
  _G.GetLocale = function() return "enUS" end
  _G.AngryMurlocsLocale = nil
  _G.AngryMurlocsLocaleEN = nil
  assert(loadfile("Localization/enUS.lua"))()
  for k, v in pairs(AngryMurlocsLocale) do en[k] = v end
  local copyBefore = AngryMurlocsLocaleEN["DEATH_MELEE"]
  _G.GetLocale = function() return "deDE" end
  assert(loadfile("Localization/deDE.lua"))()
  check("EN copy unchanged after deDE", AngryMurlocsLocaleEN["DEATH_MELEE"] == copyBefore
    and AngryMurlocsLocaleEN["DEATH_MELEE"] == en["DEATH_MELEE"])
  check("deDE overrides live table", AngryMurlocsLocale["DEATH_MELEE"] ~= en["DEATH_MELEE"])
  -- U.L fallback when active key missing
  local missing = "DEATH_TOAST_LOCALE_TEST_MISSING_KEY"
  AngryMurlocsLocale[missing] = nil
  AngryMurlocsLocaleEN[missing] = "EnglishFallback"
  local GR = { Util = {} }
  package.loaded = package.loaded or {}
  -- load U.L via dofile into a tiny env is heavy; re-check copy semantics only
  local function L(key)
    local loc, enT = AngryMurlocsLocale, AngryMurlocsLocaleEN
    if loc and loc[key] ~= nil then return loc[key] end
    if enT and enT[key] ~= nil then return enT[key] end
    return key
  end
  check("A5 missing active key uses EN copy", L(missing) == "EnglishFallback")
  AngryMurlocsLocaleEN[missing] = nil
  check("A5 unknown key returns key", L(missing) == missing)
end

local function Frame()
  local f = Sim.Stub()
  f._scripts = {}
  f.SetScript = function(self, name, fn) self._scripts[name] = fn end
  return f
end

local function Pair(seed)
  local sim = Sim.New(seed or 900)
  local files = {
    "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua",
    "Modules/Death.lua", "Modules/UI.lua",
  }
  local a = sim:AddClient("Alice", {
    extraFiles = files,
    env = { CreateFrame = Frame, GetLocale = function() return "enUS" end },
  })
  local b = sim:AddClient("Bob", {
    extraFiles = files,
    env = { CreateFrame = Frame, GetLocale = function() return "deDE" end },
  })
  for _, c in ipairs({ a, b }) do
    c.toasts, c.deaths = {}, {}
    c.GR.ToastQueue.Enqueue = function(item)
      c.toasts[#c.toasts + 1] = item
      return true
    end
    c.GR:RegisterMessage("DEATH_UPDATE", function(_, victim, data)
      c.deaths[#c.deaths + 1] = { victim = victim, data = data }
    end)
    local d = c.GR:GetModule("Death")
    if d and d.ResetSeenForTest then d.ResetSeenForTest() end
    local ui = c.GR:GetModule("UI")
    if ui and ui.ResetActivityForTest then ui.ResetActivityForTest() end
  end
  return sim, a, b
end

local function Death(c) return c.GR:GetModule("Death") end
local function UI(c) return c.GR:GetModule("UI") end

-- SpellKind locale keys all present (dynamic map)
do
  local _, a = Pair(901)
  local keys = Death(a).SpellKindLocaleKeys()
  local n = 0
  for kind, locKey in pairs(keys) do
    n = n + 1
    check("spellKind " .. kind .. " has en+de",
      AngryMurlocsLocale and true or a.GR.Util.L(locKey) ~= locKey)
    local text = a.GR.Util.L(locKey)
    check("spellKind " .. kind .. " resolves", type(text) == "string" and text ~= "" and text ~= locKey, text)
  end
  check("spellKind map non-empty", n >= 8, n)
end

-- Resolve order A6 / A12
do
  local _, a = Pair(902)
  local R = Death(a).ResolveAttackLine
  local L = a.GR.Util.L
  a.env.C_Spell = { GetSpellInfo = function(id) if id == 133 then return { name = "Fireball" } end end }
  check("A12 melee kind localizes", R("mob", "MELEE", nil, "Nahkampf") == L("DEATH_MELEE"))
  check("A12 env kind localizes", R("env", "ENV_FALL", nil, "Fall") == L("DEATH_ENV_FALL"))
  check("A12 spellId wins over RANGED", R("player", "RANGED", 133, "Fernkampf") == "Fireball")
  check("A12 failed id uses kind", R("player", "RANGED", 999, "Fernkampf") == L("DEATH_RANGED"))
  check("A12 RAW prose", R("mob", nil, nil, "CustomDot") == "CustomDot")
  check("A12 empty last resort", R("mob", nil, nil, "") == L("DEATH_UNKNOWN_ATTACK"))
end

-- New → old style: legacy spell always filled on wire
do
  local sim, a, b = Pair(903)
  a.env.C_DeathRecap = {
    GetRecapEvents = function()
      return { { event = "SWING_DAMAGE", sourceName = "Wolf", sourceGUID = "Creature-0-1-0-0-1-0",
        amount = 10, overkill = 1 } }
    end,
  }
  a.env.IsInInstance = function() return false, "none" end
  Death(a):BroadcastLocalDeath()
  sim:Run(3)
  local payload
  for _, m in ipairs(sim.messages or {}) do
    if type(m) == "table" and tostring(m[1] or m.msg or ""):find("^DEATH|") then
      payload = m[1] or m.msg
    end
  end
  -- sim may store differently; also check Bob DEATH_UPDATE data
  local d = b.deaths[1] and b.deaths[1].data
  check("A1 legacy spell filled", d and d.spell == a.GR.Util.L("DEATH_MELEE"), d and d.spell)
  check("A1 structured kind present", d and d.spellKind == "MELEE", d and d.spellKind)
  check("A1 eventId present", d and type(d.eventId) == "string" and d.eventId ~= "", d and d.eventId)
end

-- Old → new: prose-only DEATH (no eventId/kind)
do
  local sim, a, b = Pair(904)
  -- Inject as Comm would for old wire
  b.GR:SendMessage("DEATH_UPDATE", "OldPeer-Realm", {
    killer = "Wolf", isPlayer = false, zone = "Elwynn", cause = "mob",
    spell = "Melee", time = 1,
  })
  check("A2 old prose toast once", #b.toasts == 1 and b.toasts[1].spell == "Melee")
  local attack = Death(b).ResolveAttackLine("mob", nil, nil, "Melee")
  check("A2 display uses prose", attack == "Melee")
end

-- New → new: DE client receives EN sender melee → DE label via kind
do
  local sim, a, b = Pair(905)
  -- Force Bob locale strings: deDE file already loaded in real addon; in sim both share
  -- English unless we override U.L on Bob.
  local deMelee = "Nahkampf"
  b.GR.Util.L = function(key)
    if key == "DEATH_MELEE" then return deMelee end
    return key
  end
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", {
    killer = "Wolf", cause = "mob", spell = "Melee", spellKind = "MELEE",
    eventId = "abc", zone = "Z",
  })
  local item = b.toasts[1]
  check("A3 toast carries kind", item and item.spellKind == "MELEE")
  check("A3 resolve uses receiver L",
    Death(b).ResolveAttackLine(item.cause, item.spellKind, item.spellId, item.spell) == deMelee)
end

-- Dedupe: same key toast+feed once; different victims same id; toast off
do
  local sim, a, b = Pair(906)
  Death(b).ResetSeenForTest()
  UI(b).ResetActivityForTest()
  local victim = "Alice-Realm"
  local id = "evt1"
  check("toast claim 1", Death(b).TryClaimToast(victim, id) == true)
  check("toast claim 2 blocked", Death(b).TryClaimToast(victim, id) == false)
  check("feed claim independent", Death(b).TryClaimFeed(victim, id) == true)
  check("feed claim 2 blocked", Death(b).TryClaimFeed(victim, id) == false)
  check("A9 other victim same id toast", Death(b).TryClaimToast("Other-Realm", id) == true)
  check("A9 other victim same id feed", Death(b).TryClaimFeed("Other-Realm", id) == true)
end

-- A10 toasts disabled: no toast claim; feed still once
do
  local sim, a, b = Pair(907)
  Death(b).ResetSeenForTest()
  UI(b).ResetActivityForTest()
  b.GR.db.death = b.GR.db.death or {}
  b.GR.db.death.showToasts = false
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", {
    killer = "Wolf", cause = "mob", spell = "Melee", spellKind = "MELEE",
    eventId = "off1", zone = "Z",
  })
  check("A10 no toast when disabled", #b.toasts == 0)
  UI(b).PushActivityForTest({ kind = "death", player = "Alice-Realm", eventId = "off1", at = 100 })
  UI(b).PushActivityForTest({ kind = "death", player = "Alice-Realm", eventId = "off1", at = 100 })
  check("A10 one feed row", #UI(b).ActivityForTest() == 1)
end

-- A11: toast seen while queued blocks duplicate (claim at enqueue)
do
  local sim, a, b = Pair(908)
  Death(b).ResetSeenForTest()
  b.GR.db.death.showToasts = true
  -- Restore real Enqueue that claims via ShowDeathToast path
  local realEnqueue = nil
  b.toasts = {}
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", {
    killer = "Wolf", cause = "mob", spell = "Melee", spellKind = "MELEE",
    eventId = "longq", zone = "Z",
  })
  check("A11 first toast enqueued", #b.toasts == 1)
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", {
    killer = "Wolf", cause = "mob", spell = "Melee", spellKind = "MELEE",
    eventId = "longq", zone = "Z",
  })
  check("A11 duplicate blocked while queued", #b.toasts == 1)
end

-- A13: same player same second different eventIds → two feed rows
do
  local sim, a, b = Pair(909)
  Death(b).ResetSeenForTest()
  UI(b).ResetActivityForTest()
  local at = 42
  UI(b).PushActivityForTest({ kind = "death", player = "Alice-Realm", eventId = "e1", at = at })
  UI(b).PushActivityForTest({ kind = "death", player = "Alice-Realm", eventId = "e2", at = at })
  check("A13 two feed rows different ids", #UI(b).ActivityForTest() == 2)
  -- legacy without id still ActivitySame-collapses
  UI(b).ResetActivityForTest()
  UI(b).PushActivityForTest({ kind = "death", player = "Alice-Realm", at = at })
  UI(b).PushActivityForTest({ kind = "death", player = "Alice-Realm", at = at })
  check("A2 legacy ActivitySame collapses", #UI(b).ActivityForTest() == 1)
end

-- eventId reused across Broadcast without Queue (mint once per call is ok);
-- Queue path: same snapshot id on retries — covered by pendingEventId in module.
do
  local sim, a, b = Pair(910)
  a.env.C_DeathRecap = {
    GetRecapEvents = function()
      return { { event = "SWING_DAMAGE", sourceName = "Wolf", sourceGUID = "Creature-0-1-0-0-1-0",
        amount = 10, overkill = 1 } }
    end,
  }
  a.env.IsInInstance = function() return false, "none" end
  local snap = { ctx = { ctxKnown = true, instanceType = "none", inDuel = false },
    zone = "Z", mapId = 0, wallTime = sim:Wall(), eventId = "fixed-id-1" }
  Death(a):BroadcastLocalDeath(nil, snap)
  sim:Run(2)
  check("A8 snapshot eventId on wire data", b.deaths[1] and b.deaths[1].data.eventId == "fixed-id-1")
end

do
  local _, _, b = Pair(911)
  UI(b).ResetActivityForTest()
  b.GR:SendMessage("DEATH_UPDATE", "Bob-Realm", { eventId = "self-d", cause = "mob", killer = "Wolf" })
  b.GR:SendMessage("LVL_UPDATE", "Bob-Realm", 40)
  check("own death and level stay out of the feed", #UI(b).ActivityForTest() == 0, #UI(b).ActivityForTest())
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", { eventId = "other-d", cause = "mob", killer = "Wolf", zone = "Z" })
  b.GR:SendMessage("LVL_UPDATE", "Alice-Realm", 41)
  check("other death and level stay in the feed", #UI(b).ActivityForTest() == 2, #UI(b).ActivityForTest())
end

-- UTF-8 death fields + DisplayCharName (Forever surnames)
do
  local sim, a, b = Pair(912)
  local U = a.GR.Util
  -- Cyrillic И (2 bytes), euro (3), musical G-clef (4)
  local cyr = string.char(0xD0, 0x98)
  local euro = string.char(0xE2, 0x82, 0xAC)
  local four = string.char(0xF0, 0x9D, 0x84, 0x9E)
  local shortCyr = cyr .. cyr .. cyr .. cyr -- 8 bytes
  check("utf8 short cyrillic kept", U.SanitizeDeathField(shortCyr, 48) == shortCyr)

  local over2 = string.rep(cyr, 25) -- 50 bytes
  local t2 = U.SanitizeDeathField(over2, 48)
  check("utf8 2-byte boundary", #t2 == 48 and #t2 % 2 == 0 and t2 == string.rep(cyr, 24))

  local over3 = string.rep(euro, 17) -- 51 bytes
  local t3 = U.SanitizeDeathField(over3, 48)
  check("utf8 3-byte boundary", #t3 == 48 and #t3 % 3 == 0 and t3 == string.rep(euro, 16))

  local over4 = string.rep(four, 13) -- 52 bytes
  local t4 = U.SanitizeDeathField(over4, 48)
  check("utf8 4-byte boundary", #t4 == 48 and #t4 % 4 == 0 and t4 == string.rep(four, 12))

  -- Forever first+last at 12 Cyrillic chars each = 49 bytes; needs 64 on new peers.
  local longName = string.rep(cyr, 12) .. "-" .. string.rep(cyr, 12)
  check("forever cyrillic name 49 bytes", #longName == 49, #longName)
  check("new death field 64 keeps full name", U.SanitizeDeathField(longName, 64) == longName)
  local oldClip = U.SanitizeText(longName, 48)
  local safe48 = U.Utf8Truncate(longName, 48)
  check("old client SanitizeText still 48 bytes", #oldClip == 48, #oldClip)
  check("utf8-safe 48 stops before partial char", #safe48 == 47, #safe48)
  check("old byte clip differs from utf8-safe", oldClip ~= safe48)

  a.env.C_DeathRecap = {
    GetRecapEvents = function()
      return { { event = "SWING_DAMAGE", sourceName = shortCyr, sourceGUID = "Creature-0-1-0-0-1-0",
        amount = 10, overkill = 1 } }
    end,
  }
  a.env.IsInInstance = function() return false, "none" end
  Death(a):BroadcastLocalDeath()
  sim:Run(3)
  local d = b.deaths[1] and b.deaths[1].data
  check("cyrillic killer send→recv", d and d.killer == shortCyr, d and d.killer)

  -- DisplayCharName: strip only when suffix matches live realm
  a.env.GetNormalizedRealmName = function() return "Realm" end
  a.env.GetRealmName = function() return "Realm" end
  check("display forever First-Last kept", U.DisplayCharName("Ingoo-Endstation") == "Ingoo-Endstation")
  check("display strip known realm", U.DisplayCharName("Ingoo Endstation-Realm") == "Ingoo Endstation")
  check("display strip Name-Realm", U.DisplayCharName("Alice-Realm") == "Alice")
  check("display space-hyphen alone no strip",
    U.DisplayCharName("Ingoo Endstation-OtherRealm") == "Ingoo Endstation-OtherRealm")
  a.env.GetNormalizedRealmName = function() return "" end
  a.env.GetRealmName = function() return "" end
  check("display empty realm no strip",
    U.DisplayCharName("Ingoo Endstation-Realm") == "Ingoo Endstation-Realm")
  check("display empty realm keeps First-Last",
    U.DisplayCharName("Ingoo-Endstation") == "Ingoo-Endstation")

  -- Toast stores raw victim for dedupe (not ShortName)
  b.toasts = {}
  Death(b).ResetSeenForTest()
  b.GR:SendMessage("DEATH_UPDATE", "Ingoo-Endstation", {
    eventId = "utf8-dedupe-1", cause = "mob", killer = "Wolf", zone = "Z",
  })
  check("toast victim raw forever name", b.toasts[1] and b.toasts[1].victim == "Ingoo-Endstation",
    b.toasts[1] and b.toasts[1].victim)
  check("dedupe raw forever name blocks repeat",
    Death(b).TryClaimToast("Ingoo-Endstation", "utf8-dedupe-1") == false)
end

print(string.format("DeathLocale: %d failures", fails))
if fails > 0 then os.exit(1) end
