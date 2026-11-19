-- Death attribution regressions using the real modules and simulated WoW APIs.
-- Run from addon root: luajit Tests/DeathRegression_test.lua
local Sim = dofile("Tests/sim.lua")
local failures, serial = 0, 0
local function check(label, ok, detail)
  if ok then print("OK  " .. label) else
    failures = failures + 1
    print("FAIL " .. label .. (detail and (" (" .. tostring(detail) .. ")") or ""))
  end
end
local function Frame()
  local f = Sim.Stub()
  f._scripts = {}
  f.SetScript = function(self, name, fn) self._scripts[name] = fn end
  return f
end
local function World(c, w)
  w = w or {}
  local e = c.env
  local function unit(token) return w.units and w.units[token] end
  e.UnitAffectingCombat = function() return w.combat or false end
  e.UnitExists = function(token) return token == "player" or unit(token) ~= nil end
  e.UnitIsPlayer = function(token) local u = unit(token); return u and u.player or false end
  e.UnitCanAttack = function(_, token) local u = unit(token); return u and u.hostile or false end
  e.UnitName = function(token) local u = unit(token); return token == "player" and c.name or (u and u.name) end
  e.UnitFullName = function(token)
    if token == "player" then return c.name, "Realm" end
    local u = unit(token); if u then return u.name, u.realm end
  end
  e.IsInInstance = function() return w.instance ~= nil, w.instance or "none" end
  e.IsFalling = function() return w.falling or false end
  e.UnitIsDeadOrGhost = function() return w.dead or false end
end
local function Pair()
  serial = serial + 1
  local sim = Sim.New(400 + serial)
  local files = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua", "Modules/Death.lua" }
  local a = sim:AddClient("Alice", { extraFiles = files, env = { CreateFrame = Frame } })
  local b = sim:AddClient("Bob", { extraFiles = files, env = { CreateFrame = Frame } })
  for _, c in ipairs({ a, b }) do
    World(c)
    c.toasts, c.deaths = {}, {}
    c.GR.ToastQueue.Enqueue = function(item) c.toasts[#c.toasts + 1] = item; return true end
    c.GR:RegisterMessage("DEATH_UPDATE", function(_, victim, data)
      c.deaths[#c.deaths + 1] = { victim = victim, data = data }
    end)
  end
  return sim, a, b, a.GR:GetModule("Death")
end
local function Recap(c, events)
  c.env.C_DeathRecap = { GetRecapEvents = function() return events end }
end
local function Event(d, name, ...)
  local f = d._eventFrame
  f._scripts.OnEvent(f, name, ...)
end
local function Hit(name, guid, stamp, overkill)
  return { event = "SPELL_DAMAGE", sourceName = name, sourceGUID = guid,
    spellName = "Fireball", timestamp = stamp, overkill = overkill, amount = 100 }
end

do
  local sim, a, b, d = Pair()
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 0),
    Hit("EarlierPlayer", "Player-1-ABCDEF", sim:Wall() - 2, -1) })
  d:BroadcastLocalDeath()
  sim:Run(3)
  check("fatal mob beats older player, including overkill zero", a.deaths[1].data.killer == "FatalWolf")
  check("older player does not receive Wanted", Sim.Entries(a) == 0 and sim:Count("WK") == 0)
  check("guild receives fatal mob", b.deaths[1] and b.deaths[1].data.cause == "mob")
end
do
  local _, a, _, d = Pair()
  local map = d.AttributionFromRecapEvents
  local fall = { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "FALLING", timestamp = 12, overkill = 1, amount = 100 }
  local wolf = Hit("Wolf", "Creature-0-1-0-0-1-0", 11, -1)
  check("fall first beats prior mob", map({ fall, wolf }).cause == "env")
  check("fall last beats prior mob", map({ wolf, fall }).cause == "env")
  local newer = Hit("Newer", "Creature-0-1-0-0-1-0", 12)
  local older = Hit("Older", "Creature-0-1-0-0-2-0", 11)
  check("timestamps support newest-first", map({ newer, older }).killer == "Newer")
  check("timestamps support oldest-first", map({ older, newer }).killer == "Newer")
  newer.timestamp, older.timestamp = nil, nil
  check("without metadata Recap first entry wins", map({ newer, older }).killer == "Newer")
  check("named heals are not damage", map({ { event = "SPELL_HEAL", sourceName = "Healer", sourceGUID = "Player-1-ABCDEF", amount = 100 } }) == nil)
  check("misses are not damage", map({ { event = "SWING_MISSED", sourceName = "Missed", sourceGUID = "Player-1-ABCDEF" } }) == nil)
  check("zero damage is not a killing hit", map({ Hit("Zero", "Player-1-ABCDEF") , { event = "SWING_DAMAGE", amount = 0, sourceName = "ZeroHit", sourceGUID = "Player-1-ABCD01" } }).killer == "Zero")
  check("empty damage record does not become environment", map({ { event = "SPELL_DAMAGE", amount = 100 } }).cause == "unknown")
end
do
  local _, a, _, d = Pair()
  local map = d.AttributionFromRecapEvents
  a.env.C_Spell = { GetSpellInfo = function(id) if id == 133 then return { name = "Fireball" } end end }
  local hit = Hit("Mage", "Creature-0-1-0-0-1-0")
  hit.spellName, hit.spellId = nil, 133
  local atk = map({ hit })
  check("spell ID kept on attribution", atk and atk.spellId == 133 and (atk.spell == nil or atk.spell == ""), atk and atk.spellId)
  check("spell ID resolves at display", d.ResolveAttackLine("mob", atk.spellKind, 133, nil) == "Fireball")
  a.env.C_Spell = false
  atk = map({ hit })
  check("unavailable spell API keeps kind", atk and atk.spellKind == "UNKNOWN_ATTACK", atk and atk.spellKind)
  check("unavailable spell API display unknown",
    d.ResolveAttackLine("mob", "UNKNOWN_ATTACK", 133, "") == a.GR.Util.L("DEATH_UNKNOWN_ATTACK"))
  hit.event = "RANGE_DAMAGE"
  atk = map({ hit })
  check("ranged attack is never guessed melee", atk and atk.spellKind == "RANGED", atk and atk.spellKind)
  hit.event = "SWING_DAMAGE"
  atk = map({ hit })
  check("actual swing is melee kind", atk and atk.spellKind == "MELEE", atk and atk.spellKind)
  check("actual swing display melee", d.ResolveAttackLine("mob", "MELEE", nil, nil) == a.GR.Util.L("DEATH_MELEE"))
end
do
  local _, a, _, d = Pair()
  check("no data is unknown", d.ResolveDeath().cause == "unknown")
  World(a, { combat = true, units = { target = { name = "UninvolvedWolf", hostile = true } } })
  check("target mob is not a proven killer", d.ResolveDeath().cause == "unknown")
  check("target mob has no invented melee attack", d.ResolveDeath().spell == "" or d.ResolveDeath().spell == nil)
end
do
  local sim, a, _, d = Pair()
  sim:Run(1)
  Event(d, "MIRROR_TIMER_START", "BREATH", 60000, 60000, -1, 0, "Breath")
  Event(d, "MIRROR_TIMER_STOP", "BREATH")
  check("full stopped breath bar is not drowning", d.ResolveDeath().cause == "unknown")
  World(a, { falling = true })
  sim:Run(0.6)
  World(a, { dead = true, combat = true, units = { target = { name = "OldTarget", hostile = true } } })
  check("fall hint without damage evidence does not name target", d.ResolveDeath().cause == "unknown")
  Recap(a, { Hit("OldWolf", "Creature-0-1-0-0-1-0", sim:Wall(), -1) })
  check("fall hint makes incomplete old-mob recap inconclusive", d.ResolveDeath().cause == "unknown")
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  check("confirmed fatal mob survives fall hint", d.ResolveDeath().cause == "mob")
  Recap(a, { Hit("FatalPlayer", "Player-1-ABCDEF", sim:Wall(), 1) })
  check("confirmed fatal player survives fall hint", d.ResolveDeath().reliable == true and d.ResolveDeath().cause == "player")
end
do
  local sim, a, _, d = Pair()
  local ids = {}
  a.env.C_DeathRecap = { GetRecapEvents = function(id)
    ids[#ids + 1] = id or "default"
    if not id then error("current recap unavailable") end
    return { Hit("Historic", "Player-1-ABCDEF", sim:Wall() - 3600, 1) }
  end }
  check("no historical ID fallback", d.ResolveDeath().cause == "unknown" and #ids == 1 and ids[1] == "default")
  Recap(a, { Hit("Historic", "Player-1-ABCDEF", sim:Wall() - 3600, 1) })
  check("stale epoch recap cannot establish current killer", d.ResolveDeath().cause == "unknown")
  Recap(a, { Hit("Current", "Player-1-ABCDEF", sim:Wall(), 1) })
  check("current epoch recap still works", d.ResolveDeath().killer == "Current")
end
do
  local sim, a, b, d = Pair()
  a.env.GetZoneText = function() return "" end
  Recap(a, { { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "FALLING", amount = 100, overkill = 0 } })
  d:BroadcastLocalDeath()
  sim:Run(3)
  local info = b.deaths[1] and b.deaths[1].data
  check("empty zone preserves remote cause", info and info.cause == "env")
  check("empty zone preserves remote spell", info and info.spell == a.GR.Util.L("DEATH_ENV_FALL"))
  check("empty zone remains empty", info and info.zone == "" and info.mapId == 0)
end
do
  local sim, a, _, d = Pair()
  local ready = false
  World(a, { dead = true })
  a.env.GetZoneText = function() return "DeathZone" end
  a.env.C_DeathRecap = { GetRecapEvents = function()
    if ready then return { Hit("ActualKiller", "Player-1-ABCDEF", sim:Wall(), 1) } end
    return {}
  end }
  Event(d, "PLAYER_DEAD")
  check("empty recap is not broadcast prematurely", #a.deaths == 0)
  ready = true
  World(a, { dead = true })
  a.env.GetZoneText = function() return "LaterZone" end
  sim:Run(2)
  check("delayed recap publishes exactly once", #a.deaths == 1 and a.deaths[1].data.killer == "ActualKiller")
  check("delayed recap retains death location", a.deaths[1] and a.deaths[1].data.zone == "DeathZone")
end
do
  local sim, a, b, d = Pair()
  local ready = false
  World(a, { dead = true, instance = "pvp" })
  a.env.GetZoneText = function() return "Warsong Gulch" end
  a.env.C_DeathRecap = { GetRecapEvents = function()
    if ready then return { Hit("BgKiller", "Player-1-ABCDEF", sim:Wall(), 1) } end
    return {}
  end }
  Event(d, "PLAYER_DEAD")
  check("empty BG recap is not broadcast prematurely", #a.deaths == 0)
  ready = true
  World(a, { dead = true, instance = "pvp" })
  sim:Run(2)
  check("delayed BG recap does not publish DEATH locally", #a.deaths == 0)
  check("delayed BG recap sends no DEATH on wire", sim:Count("DEATH") == 0)
  check("delayed BG recap leaves peer with no death toast", #b.deaths == 0)
  check("delayed BG recap never receives Wanted", Sim.Entries(a) == 0 and sim:Count("WK") == 0)
end
do
  local sim, a, b, d = Pair()
  World(a, { instance = "arena" })
  Recap(a, { Hit("ArenaKiller", "Player-1-ABCDEF", sim:Wall(), 1) })
  d:BroadcastLocalDeath()
  sim:Run(2)
  check("arena death does not publish DEATH locally", #a.deaths == 0)
  check("arena death sends no DEATH on wire", sim:Count("DEATH") == 0)
  check("arena death leaves peer with no death toast", #b.deaths == 0)
  check("arena death never receives Wanted", Sim.Entries(a) == 0 and sim:Count("WK") == 0)
end
do
  local sim, a, _, d = Pair()
  Recap(a, { Hit("NonlethalPlayer", "Player-1-ABCDEF", sim:Wall(), -1) })
  d:BroadcastLocalDeath()
  sim:Run(2)
  check("explicitly nonlethal player hit stays unknown", a.deaths[1].data.cause == "unknown")
  check("explicitly nonlethal player never receives Wanted", Sim.Entries(a) == 0)
end
do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  World(a)
  Event(d, "PLAYER_ALIVE")
  sim:Run(2)
  check("resurrection cancels pending resolution", #a.deaths == 0)
end
do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  -- PLAYER_ALIVE can also accompany releasing the spirit; still being a ghost
  -- must not discard a death whose recap is not ready yet.
  Event(d, "PLAYER_ALIVE")
  sim:Run(2)
  check("release as ghost retains pending death", #a.deaths == 1)
end
do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  d:OnDisable()
  sim:Run(2)
  check("disable cancels pending resolution", #a.deaths == 0)
end
do
  local sim, a, b, d = Pair()
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  Event(d, "PLAYER_DEAD")
  sim:Run(3)
  check("repeat PLAYER_DEAD keeps single pending resolution", #a.deaths == 1 and #b.deaths == 1)
  check("exhausted retries publish honest unknown", a.deaths[1] and a.deaths[1].data.cause == "unknown")
end

do
  local sim, a, b, d = Pair()
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  d:BroadcastLocalDeath()
  sim:Run(2)
  check("own death is not toasted locally", #a.toasts == 0)
  check("guild still receives own death", b.deaths[1] and b.deaths[1].data.cause == "mob"
    and b.deaths[1].data.killer == "FatalWolf")
end
do
  local sim = Sim.New(880)
  local function LFrame()
    local f = Sim.Stub()
    f._scripts = {}
    f.SetScript = function(self, name, fn) self._scripts[name] = fn end
    return f
  end
  local a = sim:AddClient("Alice", { extraFiles = { "Modules/LevelUp.lua" }, env = { CreateFrame = LFrame } })
  local b = sim:AddClient("Bob", { extraFiles = { "Modules/LevelUp.lua" }, env = { CreateFrame = LFrame } })
  a.toasts = {}
  a.GR.ToastQueue.Enqueue = function(item) a.toasts[#a.toasts + 1] = item return true end
  local got = {}
  b.GR:RegisterMessage("LVL_UPDATE", function(_, sender, level)
    got[#got + 1] = { sender = sender, level = level }
  end)
  local frame = a.GR:GetModule("LevelUp")._eventFrame
  frame._scripts.OnEvent(frame, "PLAYER_LEVEL_UP", 42)
  sim:Run(2)
  check("own level-up is not toasted locally", #a.toasts == 0)
  check("guild still receives own level-up", got[1] and got[1].level == 42 and tostring(got[1].sender):find("Alice"))
end
do
  local _, a, _, d = Pair()
  a.env.GetPlayerInfoByGUID = function(guid)
    if guid == "Player-1-ABCDEF" then
      return "Warrior", "WARRIOR", "Human", "Human", 2, "Ganker", nil
    end
  end
  local info = d.AttributionFromRecapEvents({
    Hit(nil, "Player-1-ABCDEF", nil, 1),
  })
  check("player guid names killer via GetPlayerInfoByGUID", info and info.cause == "player"
    and info.reliable and info.killer == "Ganker-Realm", info and info.killer)
  local named = d.AttributionFromRecapEvents({ Hit("PlainName", "Player-1-ABCDEF", nil, 1) })
  check("plain recap name is kept", named and named.killer == "PlainName")
end
do
  local _, a, _, d = Pair()
  a.env.UnitFactionGroup = function() return "Horde" end
  local info = d.ResolveDeath()
  a.env.C_DeathRecap = { GetRecapEvents = function()
    return { { event = "SPELL_DAMAGE", sourceName = "Ganker", sourceFlags = 0x548, amount = 50, overkill = 1 } }
  end }
  info = d.ResolveDeath()
  check("player flag without guid is a reliable player", info and info.cause == "player"
    and info.reliable and info.killer == "Ganker", info and info.killer)
  check("horde victim, hostile killer is Alliance", info and info.faction == "A", info and info.faction)
  local line = d.FormatDeathLine("Bob", info.cause, info.killer, "Hit", "Zone", info.faction, nil)
  check("alliance killer is blue", line:find("|cff0070dd", 1, true) and line:find("Alliance", 1, true), line)
  a.env.UnitFactionGroup = function() return "Alliance" end
  info = d.ResolveDeath()
  check("alliance victim, hostile killer is Horde", info and info.faction == "H")
  line = d.FormatDeathLine("Bob", info.cause, info.killer, "Hit", "Zone", info.faction, nil)
  check("horde killer is not blue", not line:find("|cff0070dd", 1, true), line)
end
do
  local sim, a, _, d = Pair()
  local SECRET = {}
  a.env.issecretvalue = function(v) return v == SECRET end
  World(a, { combat = true, units = { target = { name = "WrongTarget", realm = "Realm", player = true, hostile = true } } })
  Recap(a, { { event = "SPELL_DAMAGE", sourceName = SECRET, sourceGUID = SECRET, amount = 80, overkill = 1 } })
  local info = d.ResolveDeath()
  check("secret identity waits", info and info.pending and info.cause == "unknown" and info.killer == nil, info and info.cause)
  check("secret identity does not use the target", info and info.suspect ~= "WrongTarget-Realm")
  World(a, { dead = true, combat = true, units = { target = { name = "WrongTarget", realm = "Realm", player = true, hostile = true } } })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.3)
  check("secret identity is not published early", #a.deaths == 0)
  sim:Run(10)
  check("secret identity ends unknown", a.deaths[1] and a.deaths[1].data.cause == "unknown"
    and a.deaths[1].data.killer == "?")
  check("secret identity never wanted the target", Sim.Entries(a) == 0)
end
do
  local sim, a, b, d = Pair()
  local petGuid = "Pet-0-1-0-0-9-0"
  World(a, {})
  a.env.UnitFactionGroup = function() return "Horde" end
  a.env.UnitExists = function(token) return token == "player" or token == "targetpet" end
  a.env.UnitGUID = function(token)
    if token == "targetpet" then return petGuid end
  end
  a.env.UnitOwnerGUID = function(token)
    if token == "targetpet" then return "Player-1-OWNER" end
  end
  a.env.GetPlayerInfoByGUID = function(guid)
    if guid == "Player-1-OWNER" then
      return "Hunter", "HUNTER", "Human", "Human", 2, "Hunter", "Realm"
    end
  end
  a.env.UnitTokenFromGUID = nil
  Recap(a, { { event = "SPELL_DAMAGE", sourceName = "Wolf", sourceGUID = petGuid,
    sourceFlags = 0x1140, spellName = "Bite", amount = 40, overkill = 2 } })
  local info = d.ResolveDeath()
  check("pet kill names the owner", info and info.cause == "player" and info.reliable
    and info.killer == "Hunter-Realm" and info.pet == "Wolf", info and info.killer)
  check("pet owner on the alliance side", info and info.faction == "A")
  local line = d.FormatDeathLine("Bob", info.cause, info.killer, "Bite", "Zone", info.faction, info.pet)
  check("pet toast shows owner, pet, and blue", line:find("Hunter", 1, true) and line:find("Wolf", 1, true)
    and line:find("|cff0070dd", 1, true) and line:find("Alliance", 1, true), line)
  d:BroadcastLocalDeath()
  sim:Run(2)
  check("pet owner is wanted", Sim.Entries(a) >= 1)
  check("guild death names the owner", b.deaths[1] and b.deaths[1].data.killer == "Hunter-Realm"
    and b.deaths[1].data.cause == "player" and b.deaths[1].data.pet == "Wolf"
    and b.deaths[1].data.faction == "A")
end
do
  local sim, a, _, d = Pair()
  local petGuid = "Pet-0-1-0-0-9-0"
  World(a, { dead = true })
  a.env.UnitTokenFromGUID = function() return "pet1" end
  a.env.UnitOwnerGUID = function() return nil end
  Recap(a, { { event = "SPELL_DAMAGE", sourceName = "Wolf", sourceGUID = petGuid,
    sourceFlags = 0x1140, amount = 40, overkill = 2 } })
  check("missing owner keeps waiting", d.ResolveDeath().pending and d.ResolveDeath().cause == "mob")
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("missing owner is not published early", #a.deaths == 0)
  sim:Run(10)
  check("missing owner stays a mob", a.deaths[1] and a.deaths[1].data.cause == "mob"
    and a.deaths[1].data.killer == "Wolf")
  check("missing owner is not wanted", Sim.Entries(a) == 0)
end
do
  local _, a, _, d = Pair()
  a.env.UnitFactionGroup = function() return "Horde" end
  Recap(a, { Hit("Trash", "Creature-0-1-0-0-1-0", nil, 1) })
  local info = d.ResolveDeath()
  check("npc has no faction and no owner", info and info.cause == "mob" and info.faction == nil and not info.companion)
end
do
  local sim, _, b = Pair()
  b.GR.Comm:OnAddonMessage("GildenRadar", "DEATH|Wolf|0|Zone|0|mob|Bite||||", "GUILD", "Alice-Realm")
  sim:Run(1)
  local item = b.toasts[#b.toasts]
  check("old death wire has no faction", item and item.faction == nil and item.pet == nil, item and item.faction)
  local line = b.GR:GetModule("Death").FormatDeathLine("Bob", "mob", "Wolf", "Bite", "Zone", nil, nil)
  check("old death line is not blue", not line:find("|cff0070dd", 1, true))
end

-- A diagnostic must describe the same read that decided the published death.
for _, diagOn in ipairs({ false, true }) do
  local sim, a, _, d = Pair()
  a.GR.Diag:SetEnabled(diagOn)
  World(a, { dead = true })
  local reads = 0
  a.env.C_DeathRecap = { GetRecapEvents = function()
    reads = reads + 1
    if reads == 1 then return {} end
    return { Hit("RetryWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) }
  end }
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("retry reads fresh recap with diag=" .. tostring(diagOn), reads == 2
    and #a.deaths == 1 and a.deaths[1].data.killer == "RetryWolf", reads)
end
do
  local _, a, _, d = Pair()
  a.GR.Diag:SetEnabled(true)
  Recap(a, {})
  d:BroadcastLocalDeath()
  local dump = table.concat(a.GR.Diag.deaths[1].lines, "\n")
  check("empty recap diagnostic has no invented pick", dump:find("result=empty", 1, true)
    and not dump:find("recap[1]", 1, true), dump)
end
do
  local sim, a, _, d = Pair()
  a.GR.Diag:SetEnabled(true)
  local reads = 0
  a.env.C_DeathRecap = { GetRecapEvents = function()
    reads = reads + 1
    return { Hit(reads == 1 and "OriginalWolf" or "DifferentWolf",
      "Creature-0-1-0-0-1-0", sim:Wall(), 1) }
  end }
  d:BroadcastLocalDeath()
  local diag = a.GR.Diag.deaths[1]
  local dump = diag and table.concat(diag.lines, "\n") or ""
  check("diagnostics do not fetch a different recap", reads == 1, reads)
  check("diagnostics describe published killer", dump:find("OriginalWolf", 1, true)
    and not dump:find("DifferentWolf", 1, true), dump)
end
do
  local sim, a, _, d = Pair()
  a.GR.Diag:SetEnabled(true)
  Recap(a, { Hit("StaleWolf", "Creature-0-1-0-0-1-0", sim:Wall()-3600, 1) })
  d:BroadcastLocalDeath()
  local dump = table.concat(a.GR.Diag.deaths[1].lines, "\n")
  check("rejected recap diagnostic explains timestamp rejection",
    dump:find("epoch_out_of_window", 1, true) and dump:find("delta=-3600", 1, true), dump)
  check("diagnostic records death wall time", dump:find("deathWall=" .. sim:Wall(), 1, true), dump)
end
do
  local sim, a, _, d = Pair()
  local secret = setmetatable({}, { __tostring = function() error("secret formatted") end })
  a.env.issecretvalue = function(v) return rawequal(v, secret) end
  a.GR.Diag:SetEnabled(true)
  Recap(a, { { event = "SWING_DAMAGE", sourceName = secret, sourceGUID = secret,
    amount = secret, overkill = secret, timestamp = secret } })
  local ok, err = pcall(function() d:BroadcastLocalDeath() end)
  check("recap diagnostics never format secret fields", ok, err)
  check("diagnostics preserve secret unknown attribution", a.deaths[1]
    and a.deaths[1].data.cause == "unknown" and Sim.Entries(a) == 0)
end

local function Swing(stamp, overkill, name, guid)
  local hit = Hit(name or "MineWorker", guid or "Creature-0-1-0-0-1-0", stamp, overkill)
  hit.event, hit.spellName = "SWING_DAMAGE", nil
  return hit
end

-- Reproduce the epoch rejection and exercise the actual event -> wire -> toast path.
for _, diagOn in ipairs({ false, true }) do
  local sim, a, b, d = Pair()
  sim:Run(30)
  a.GR.Diag:SetEnabled(diagOn)
  World(a, { dead = true })
  Recap(a, { Swing(sim:Wall()-10, 0) })
  Event(d, "PLAYER_DEAD")
  sim:Run(3)
  local sent = a.deaths[1] and a.deaths[1].data
  local received = b.deaths[1] and b.deaths[1].data
  local toast = b.toasts[1]
  check("older NPC recap is recovered with diag=" .. tostring(diagOn), sent
    and sent.cause == "mob" and sent.killer == "MineWorker" and not sent.isPlayer)
  check("recovered NPC wire carries melee", received and received.cause == "mob"
    and received.spellKind == "MELEE" and received.killer == "MineWorker")
  check("recovered NPC recipient toast carries killer and attack", toast and toast.cause == "mob"
    and toast.killer == "MineWorker" and toast.spellKind == "MELEE")
  check("recovered NPC is published once without self-toast", #a.deaths == 1 and #b.deaths == 1
    and #b.toasts == 1 and #a.toasts == 0 and sim:Count("DEATH") == 1)
  check("recovered NPC never creates Wanted", Sim.Entries(a) == 0 and Sim.Entries(b) == 0 and sim:Count("WK") == 0)
  if diagOn then
    local dump = table.concat(a.GR.Diag.deaths[1].lines, "\n")
    check("NPC recovery diagnostic explains both decisions", dump:find("epoch_out_of_window", 1, true)
      and dump:find("npc_recovered", 1, true) and dump:find("delta=-10", 1, true), dump)
  end
end

for _, case in ipairs({
  { "inclusive NPC past boundary", -15, "mob" },
  { "outside NPC past boundary", -15.01, "unknown" },
  { "inclusive existing future boundary", 2, "mob" },
  { "outside future boundary", 2.01, "unknown" },
  { "hour-old NPC", -3600, "unknown" },
}) do
  local sim, a, _, d = Pair()
  sim:Run(30)
  Recap(a, { Swing(sim:Wall()+case[2], 1) })
  local info = d.ResolveDeath()
  check(case[1], info.cause == case[3] and not info.reliable and not info.isPlayer, info.cause)
end

-- Public mapper behaviour for absent/relative clocks is retained, never extended.
do
  local sim, a, b, d = Pair()
  sim:Step(30)
  local deathWall = sim:Wall()
  World(a, { dead = true })
  Recap(a, { Swing(deathWall-10, 1) })
  Event(d, "PLAYER_DEAD")
  sim:Step(0.2)
  check("NPC recovery does not shorten existing unknown retries", #a.deaths == 0)
  Recap(a, { Hit("DelayedPlayer", "Player-1-ABCDEF", deathWall, 1) })
  sim:Run(3)
  check("later reliable player wins before final NPC recovery", #a.deaths == 1
    and a.deaths[1].data.cause == "player" and a.deaths[1].data.killer == "DelayedPlayer"
    and Sim.Level(a, "DelayedPlayer-Realm") == 1 and Sim.Level(b, "DelayedPlayer-Realm") == 1)
end
do
  local sim, a, _, d = Pair()
  sim:Run(30)
  for _, guid in ipairs({ "Player-1-ABCDEF", "Creature-0-1-0-0-1-0" }) do
    Recap(a, { Swing(sim:Wall()*1000, 1, "Milliseconds", guid) })
    check("milliseconds never gain acceptance: " .. guid, d.ResolveDeath().cause == "unknown")
  end
  for _, guid in ipairs({ "Creature-0-1-0-0-1-0", "Vehicle-0-1-0-0-1-0", "Pet-0-1-0-0-1-0" }) do
    Recap(a, { Swing(sim:Wall()-10, 1, "Npc", guid) })
    check("non-player GUID recovers: " .. guid, d.ResolveDeath().cause == "mob")
  end
  Recap(a, { Swing(sim:Wall()-10, -1) })
  check("explicitly nonlethal NPC never recovers", d.ResolveDeath().cause == "unknown")
  local nameless = Swing(sim:Wall()-10, 1)
  nameless.sourceName = nil
  Recap(a, { nameless })
  check("nameless old NPC stays unknown", d.ResolveDeath().cause == "unknown")
  local flagPlayer = Swing(sim:Wall()-10, 1)
  flagPlayer.sourceFlags = 0x548
  Recap(a, { flagPlayer })
  check("player flag cannot use NPC window", d.ResolveDeath().cause == "unknown")
  local pet = Swing(sim:Wall()-10, 1, "Pet", "Pet-0-1-0-0-9-0")
  pet.sourceFlags = 0x1140
  Recap(a, { pet })
  check("unresolved player pet cannot use NPC window", d.ResolveDeath().cause == "unknown")
end

for _, oldIsPlayer in ipairs({ false, true }) do
  local sim, a, b, d = Pair()
  sim:Run(30)
  local oldGuid = oldIsPlayer and "Player-1-ABCDEF" or "Creature-0-1-0-0-1-0"
  local newGuid = oldIsPlayer and "Creature-0-1-0-0-1-0" or "Player-1-ABCDEF"
  Recap(a, { Swing(sim:Wall()-60, 1, "Old", oldGuid), Swing(sim:Wall()-1, nil, "Recent", newGuid) })
  d:BroadcastLocalDeath()
  sim:Run(3)
  check("mixed recap never reselects after stale winner: " .. oldGuid,
    a.deaths[1].data.cause == "unknown" and b.deaths[1].data.cause == "unknown"
    and Sim.Entries(a) == 0 and sim:Count("WK") == 0)
end

-- A new NPC path must not mask secrets or an environmental contradiction.
do
  local sim, a, _, d = Pair()
  sim:Run(30)
  local secret = {}
  a.env.issecretvalue = function(v) return rawequal(v, secret) end
  for _, field in ipairs({ "sourceName", "sourceGUID", "sourceFlags", "amount", "overkill", "currentHP",
    "spellName", "spellId", "spellID", "environmentalType", "envType" }) do
    local hit = Swing(sim:Wall()-10, 1)
    hit[field] = secret
    Recap(a, { hit })
    check("old NPC with secret " .. field .. " is not recovered", d.ResolveDeath().cause == "unknown")
  end
  Recap(a, { Swing(sim:Wall()-10, 1), secret })
  check("secret event blocks NPC recovery", d.ResolveDeath().cause == "unknown")
  a.env.C_DeathRecap = { GetRecapEvents = function() return secret end }
  a.env.DeathRecap_GetEvents = function() return { Swing(sim:Wall()-10, 1) } end
  check("secret current recap blocks recovery from legacy fallback", d.ResolveDeath().cause == "unknown")
  a.env.DeathRecap_GetEvents = nil
  Recap(a, { Swing(sim:Wall()-10, 1) })
  Event(d, "MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
  check("environment hint blocks even lethal NPC recovery", d.ResolveDeath().cause == "unknown")
  Recap(a, { { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "DROWNING",
    timestamp = sim:Wall(), amount = 100, overkill = 0 } })
  check("existing environmental result stays intact", d.ResolveDeath().cause == "env")
end

-- The boundary belongs to the previous life, not to a retry or duplicate event.
for _, stopTimer in ipairs({ false, true }) do
  local sim, a, _, d = Pair()
  sim:Step(30)
  Event(d, "MIRROR_TIMER_START", "BREATH", 0, 60000, -1, 0, "Breath")
  sim:Step(4.5)
  World(a, { dead = true })
  Recap(a, { Swing(sim:Wall()-10, 1) })
  Event(d, "PLAYER_DEAD")
  if stopTimer then
    Event(d, "MIRROR_TIMER_STOP", "BREATH")
    check("direct resolver retains active death hint", d.ResolveDeath().cause == "unknown")
    Event(d, "PLAYER_DEAD") -- duplicate must also retain the death's hint
  end
  sim:Run(2)
  check("death hint survives retry expiry/stop=" .. tostring(stopTimer), #a.deaths == 1
    and a.deaths[1].data.cause == "unknown")
  -- It must not leak into a different life.
  World(a)
  Event(d, "PLAYER_ALIVE")
  sim:Step(20)
  World(a, { dead = true })
  Recap(a, { Swing(sim:Wall()-10, 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("NPC hint block resets on resurrection=" .. tostring(stopTimer), #a.deaths == 2
    and a.deaths[2].data.cause == "mob")
end
do
  local sim, a, b, d = Pair()
  sim:Run(30)
  local firstDeath = sim:Wall()
  World(a, { dead = true })
  Recap(a, { Swing(firstDeath, 1, "FirstWolf") })
  Event(d, "PLAYER_DEAD")
  World(a)
  Event(d, "PLAYER_ALIVE")
  sim:Run(8)
  local secondDeath = sim:Wall()
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD") -- unchanged recap belongs to the first death
  sim:Run(3)
  check("previous death recap inside NPC window stays unknown", #a.deaths == 2
    and a.deaths[2].data.cause == "unknown" and #b.deaths == 2)
  World(a)
  Event(d, "PLAYER_UNGHOST")
  sim:Run(10)
  local boundary = secondDeath
  Recap(a, { Swing(boundary+2, 1) })
  check("previous-life boundary plus skew is excluded", d.ResolveDeath().cause == "unknown")
  Recap(a, { Swing(sim:Wall()-10, 1, "NewWolf") })
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("new life can recover a newer NPC hit", #a.deaths == 3 and a.deaths[3].data.cause == "mob"
    and a.deaths[3].data.killer == "NewWolf")
end
do
  local sim, a, _, d = Pair()
  sim:Run(30)
  World(a, { dead = true })
  local stamp = sim:Wall()-10
  Recap(a, {})
  Event(d, "PLAYER_DEAD")
  Event(d, "PLAYER_ALIVE") -- ghost release, still dead
  sim:Step(0.1)
  Event(d, "PLAYER_DEAD") -- duplicate before pending resolution completes
  Recap(a, { Swing(stamp, 1) })
  sim:Run(2)
  check("ghost and repeated death preserve recovery boundary", #a.deaths == 1
    and a.deaths[1].data.cause == "mob")
end
do
  local sim, a, _, d = Pair()
  sim:Run(30)
  local enabledAt = sim:Wall()
  d:OnDisable()
  d:OnEnable()
  sim:Step(10)
  Recap(a, { Swing(enabledAt+2, 1) })
  check("reload boundary plus skew is excluded", d.ResolveDeath().cause == "unknown")
  Recap(a, { Swing(enabledAt+2.01, 1) })
  check("hit after reload boundary can recover", d.ResolveDeath().cause == "mob")
  Recap(a, { Swing(enabledAt-1, 1) })
  check("pre-reload hit cannot recover", d.ResolveDeath().cause == "unknown")
  a.env.GetServerTime = function() return enabledAt-5 end
  Recap(a, { Swing(enabledAt-15, 1) })
  check("clock rollback cannot recover", d.ResolveDeath().cause == "unknown")
end
do
  local sim, a, b, d = Pair()
  sim:Run(30)
  World(a, { dead = true })
  Recap(a, { Hit("CurrentPlayer", "Player-1-ABCDEF", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(3)
  check("valid player remains the same killer", a.deaths[1].data.cause == "player"
    and a.deaths[1].data.killer == "CurrentPlayer" and b.deaths[1].data.killer == "CurrentPlayer")
  check("valid player still counts exactly once", Sim.Level(a, "CurrentPlayer-Realm") == 1
    and Sim.Level(b, "CurrentPlayer-Realm") == 1 and sim:Count("WK") == 1)
end
do
  local sim, a, _, d = Pair()
  sim:Step(30)
  local originalDeath = sim:Wall()
  Recap(a, { Swing(originalDeath+1, 1, "OldWolf") })
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  World(a)
  Event(d, "PLAYER_ALIVE")
  -- One death observed during a clock rollback must not lower the boundary
  -- and admit an earlier life's recap once the clock catches up.
  a.env.GetServerTime = function() return originalDeath-5 end
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  World(a)
  Event(d, "PLAYER_ALIVE")
  a.env.GetServerTime = function() return originalDeath+8 end
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("death during clock rollback cannot lower NPC life boundary", #a.deaths == 3
    and a.deaths[3].data.cause == "unknown")
end

do
  local sim, a, _, d = Pair()
  sim:Step(30)
  local originalDeath = sim:Wall()
  World(a, { dead = true })
  Recap(a, {})
  Event(d, "PLAYER_DEAD")
  a.env.GetServerTime = function() return originalDeath-5 end
  Recap(a, { Swing(originalDeath-15, 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("duplicate death during rollback cannot recover NPC", #a.deaths == 1
    and a.deaths[1].data.cause == "unknown")
end

-- One death event per life: duplicate PLAYER_DEAD must not republish.
do
  local sim, a, b, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("valid mob publishes once immediately", #a.deaths == 1 and a.deaths[1].data.killer == "FatalWolf")
  local id1 = a.deaths[1].data.eventId
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("repeat PLAYER_DEAD after publish stays one local update", #a.deaths == 1)
  check("repeat PLAYER_DEAD after publish stays one DEATH wire", sim:Count("DEATH") == 1)
  check("repeat PLAYER_DEAD after publish stays one guild toast", #b.toasts == 1)
  check("repeat PLAYER_DEAD after publish no self toast", #a.toasts == 0)
  check("repeat PLAYER_DEAD after publish no Wanted", Sim.Entries(a) == 0 and sim:Count("WK") == 0)
  check("repeat PLAYER_DEAD after publish keeps same eventId", a.deaths[1].data.eventId == id1)
end

do
  local sim, a, b, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("Ganker", "Player-1-ABCDEF", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  local lvlA = Sim.Level(a, "Ganker-Realm")
  local lvlB = Sim.Level(b, "Ganker-Realm")
  check("valid player Wanted once locally", lvlA == 1)
  check("valid player Wanted once on guild peer", lvlB == 1)
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("repeat PLAYER_DEAD does not add second Wanted", Sim.Level(a, "Ganker-Realm") == 1
    and Sim.Level(b, "Ganker-Realm") == 1)
  check("repeat PLAYER_DEAD player death still one wire", sim:Count("DEATH") == 1 and #a.deaths == 1)
end

do
  local sim, a, b, d = Pair()
  World(a, { dead = true })
  Recap(a, {})
  Event(d, "PLAYER_DEAD")
  sim:Run(0.2)
  Event(d, "PLAYER_DEAD")
  sim:Run(0.85)
  check("SHORT duplicate does not restart deadline", #a.deaths == 1)
  sim:Run(2)
  check("SHORT duplicate ends as single unknown", #a.deaths == 1 and #b.deaths == 1
    and a.deaths[1].data.cause == "unknown")
end

do
  local sim, a, b, d = Pair()
  local SECRET = {}
  a.env.issecretvalue = function(v) return v == SECRET end
  World(a, { dead = true })
  Recap(a, { { event = "SPELL_DAMAGE", sourceName = SECRET, sourceGUID = SECRET,
    amount = 80, overkill = 1 } })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.3)
  Event(d, "PLAYER_DEAD")
  check("LONG duplicate keeps pending before settle", #a.deaths == 0)
  a.env.issecretvalue = function() return false end
  Recap(a, { Hit("Ganker", "Player-1-ABCDEF", sim:Wall(), 1) })
  sim:Run(10)
  check("LONG duplicate settles once after secrets clear", #a.deaths == 1 and #b.deaths == 1
    and a.deaths[1].data.killer == "Ganker")
  check("LONG duplicate single Wanted", Sim.Level(a, "Ganker-Realm") == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, {})
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("unknown already published", #a.deaths == 1 and a.deaths[1].data.cause == "unknown")
  Recap(a, { Hit("LatePlayer", "Player-1-ABCDEF", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("late recap after publish does not republish", #a.deaths == 1)
  check("late recap after publish adds no Wanted", Sim.Entries(a) == 0)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, {})
  Event(d, "PLAYER_DEAD")
  Event(d, "PLAYER_ALIVE")
  check("ghost release before publish keeps pending", #a.deaths == 0)
  sim:Run(2)
  check("ghost release before publish still publishes once", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  Event(d, "PLAYER_ALIVE")
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("ghost release after publish does not republish", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  Event(d, "PLAYER_UNGHOST")
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("PLAYER_UNGHOST while dead does not unlock cycle", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  a.env.UnitIsDeadOrGhost = function() return nil end
  Event(d, "PLAYER_UNGHOST")
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("PLAYER_UNGHOST with nil DeadOrGhost keeps lock", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  local SECRET = {}
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  a.env.issecretvalue = function(v) return v == SECRET end
  a.env.UnitIsDeadOrGhost = function() return SECRET end
  Event(d, "PLAYER_UNGHOST")
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("PLAYER_UNGHOST with secret DeadOrGhost keeps lock", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  a.env.UnitIsDeadOrGhost = function() error("dead api failed") end
  local okUnghost = pcall(function() Event(d, "PLAYER_UNGHOST") end)
  local okDead = pcall(function() Event(d, "PLAYER_DEAD") end)
  local okTick = pcall(function() sim:Run(1) end)
  check("PLAYER_UNGHOST with DeadOrGhost error does not throw", okUnghost)
  check("PLAYER_DEAD after DeadOrGhost error does not throw", okDead)
  check("DeadOrGhost error during ticker does not throw", okTick)
  check("PLAYER_UNGHOST with DeadOrGhost error keeps lock", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FirstWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  a.env.UnitIsDeadOrGhost = function() return true end
  Event(d, "PLAYER_ALIVE")
  sim:Run(0.6)
  check("alive event while still dead keeps lock", #a.deaths == 1)
  a.env.UnitIsDeadOrGhost = function() return false end
  sim:Run(0.6)
  Recap(a, { Hit("SecondWolf", "Creature-0-1-0-0-2-0", sim:Wall(), 1) })
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("ticker confirmed alive unlocks next death", #a.deaths == 2
    and a.deaths[2].data.killer == "SecondWolf")
end

do
  local sim, a, b, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("Ganker", "Player-1-ABCDEF", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  World(a)
  Event(d, "PLAYER_ALIVE")
  sim:Run(0.2)
  World(a, { dead = true })
  -- Different killer so existing Wanted pair-cooldown does not hide a death-cycle bug.
  Recap(a, { Hit("Other", "Player-1-ABCD02", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("two real deaths after rez publish twice", #a.deaths == 2 and #b.deaths == 2)
  check("two real deaths use distinct eventIds", a.deaths[1].data.eventId ~= a.deaths[2].data.eventId)
  check("fast second death is not suppressed by a death cooldown", sim:Count("DEATH") == 2)
  check("two real deaths Wanted for each killer", Sim.Level(a, "Ganker-Realm") == 1
    and Sim.Level(a, "Other-Realm") == 1
    and Sim.Level(b, "Ganker-Realm") == 1
    and Sim.Level(b, "Other-Realm") == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  local ready = false
  a.env.C_DeathRecap = { GetRecapEvents = function()
    if ready then return { Hit("ActualKiller", "Player-1-ABCDEF", sim:Wall(), 1) } end
    return {}
  end }
  Event(d, "PLAYER_DEAD")
  sim:Run(0.2)
  World(a)
  Event(d, "PLAYER_ALIVE")
  ready = true
  sim:Run(2)
  check("rez during retry cancels old callback", #a.deaths == 0)
  World(a, { dead = true })
  Recap(a, { Hit("NextKiller", "Player-1-ABCD02", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("new death after mid-retry rez publishes once", #a.deaths == 1
    and a.deaths[1].data.killer == "NextKiller")
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, {})
  Event(d, "PLAYER_DEAD")
  d:OnDisable()
  sim:Run(2)
  check("disable while pending publishes nothing", #a.deaths == 0)
  d:OnEnable()
  World(a, { dead = true })
  Recap(a, { Hit("AfterEnable", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("enable while still dead does not late-report old death", #a.deaths == 0)
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("enable while still dead ignores further PLAYER_DEAD", #a.deaths == 0)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  d:OnDisable()
  d:OnEnable()
  World(a, { dead = true })
  Event(d, "PLAYER_DEAD")
  sim:Run(2)
  check("disable/enable after publish while dead does not republish", #a.deaths == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  d:OnDisable()
  World(a)
  d:OnEnable()
  World(a, { dead = true })
  Recap(a, { Hit("NextWolf", "Creature-0-1-0-0-2-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("disable then rez then enable alive allows new death", #a.deaths == 2
    and a.deaths[2].data.killer == "NextWolf")
end

do
  local sim, a, _, d = Pair()
  d:OnDisable()
  World(a, { dead = true })
  Recap(a, { Hit("AlreadyDead", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  d:OnEnable()
  sim:Run(2)
  check("module start while dead does not invent a death", #a.deaths == 0)
  World(a)
  Event(d, "PLAYER_ALIVE")
  sim:Run(0.05)
  World(a, { dead = true })
  Recap(a, { Hit("FreshWolf", "Creature-0-1-0-0-2-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("after start-dead then rez a new death publishes", #a.deaths == 1
    and a.deaths[1].data.killer == "FreshWolf")
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  local reentered = false
  a.GR:RegisterMessage("DEATH_UPDATE", function()
    if reentered then return end
    reentered = true
    Event(d, "PLAYER_DEAD")
  end)
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("reentrant PLAYER_DEAD during publish stays once", #a.deaths == 1)
end

do
  local sim, a, b, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  local data = a.deaths[1].data
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", data)
  b.GR:SendMessage("DEATH_UPDATE", "Alice-Realm", data)
  check("receiver same eventId still one toast", #b.toasts == 1)
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  local phase = 0
  a.env.UnitIsDeadOrGhost = function()
    phase = phase + 1
    if phase <= 2 then return nil end
    if phase == 3 then error("transient dead api") end
    return true
  end
  local ready = false
  a.env.C_DeathRecap = { GetRecapEvents = function()
    if ready then return { Hit("Recovered", "Player-1-ABCDEF", sim:Wall(), 1) } end
    return {}
  end }
  Event(d, "PLAYER_DEAD")
  sim:Run(0.4)
  ready = true
  World(a, { dead = true })
  a.env.UnitIsDeadOrGhost = function() return true end
  Recap(a, { Hit("Recovered", "Player-1-ABCDEF", sim:Wall(), 1) })
  sim:Run(2)
  check("transient nil/error DeadOrGhost does not lose death", #a.deaths == 1
    and a.deaths[1].data.killer == "Recovered")
end

do
  local sim, a, _, d = Pair()
  World(a, { dead = true })
  Recap(a, { Hit("FatalWolf", "Creature-0-1-0-0-1-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  World(a, { dead = true, falling = true })
  a.env.UnitIsDeadOrGhost = function() return nil end
  sim:Run(0.6)
  Event(d, "PLAYER_DEAD")
  sim:Run(1)
  check("nil DeadOrGhost over ticker keeps lock", #a.deaths == 1)
  a.env.UnitIsDeadOrGhost = function() return false end
  sim:Run(0.6)
  World(a, { dead = true })
  Recap(a, { Hit("AfterNil", "Creature-0-1-0-0-9-0", sim:Wall(), 1) })
  Event(d, "PLAYER_DEAD")
  sim:Run(0.05)
  check("after nil ticker period confirmed alive allows next death", #a.deaths == 2
    and a.deaths[2].data.killer == "AfterNil")
end

print(string.format("\n%d failures", failures))
if failures > 0 then os.exit(1) end
