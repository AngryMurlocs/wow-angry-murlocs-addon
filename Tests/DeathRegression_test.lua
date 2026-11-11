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
  World(a, { dead = true, instance = "pvp" })
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
  check("delayed recap retains excluded BG context", Sim.Entries(a) == 0)
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
  check("new death supersedes pending resolution", #a.deaths == 1 and #b.deaths == 1)
  check("exhausted retries publish honest unknown", a.deaths[1] and a.deaths[1].data.cause == "unknown")
end

print(string.format("\n%d failures", failures))
if failures > 0 then os.exit(1) end
