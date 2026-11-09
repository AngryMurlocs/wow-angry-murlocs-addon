-- Death attribution with the real Death/Wanted/Comm code and stubbed unit APIs.
-- Forever: no CLEU; unit tokens never blame players; Death Recap can attribute.
-- From repo root: luajit Tests/Attribution_test.lua
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

-- units: { target = { name, player, hostile }, attacking = {...} }
local function SetWorld(c, w)
  local env = c.env
  local function U(unit) return w.units and w.units[unit] end
  env.UnitAffectingCombat = function() return w.combat and true or false end
  env.UnitExists = function(unit) return unit == "player" or U(unit) ~= nil end
  env.UnitIsPlayer = function(unit) local u = U(unit); return u and u.player or false end
  env.UnitCanAttack = function(_, unit) local u = U(unit); return u and u.hostile or false end
  env.UnitName = function(unit)
    if unit == "player" then return c.name end
    local u = U(unit)
    return u and u.name or nil
  end
  env.UnitFullName = function(unit)
    if unit == "player" then return c.name, "Realm" end
    local u = U(unit)
    if u then return u.name, u.realm end
    return nil
  end
  if w.noInstanceApi then
    env.IsInInstance = false
  else
    env.IsInInstance = function()
      if w.instance then return true, w.instance end
      return false, "none"
    end
  end
  env.IsFalling = function() return false end
  env.UnitIsDeadOrGhost = function() return false end
end

local function NewPair(seed, db)
  local sim = Sim.New(seed)
  local files = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua", "Modules/Death.lua" }
  local alice = sim:AddClient("Alice", { db = db, extraFiles = files })
  local bob = sim:AddClient("Bob", { extraFiles = files })
  bob.deaths = {}
  bob.GR:RegisterMessage("DEATH_UPDATE", function(_, victim, data)
    bob.deaths[#bob.deaths + 1] = { victim = victim, data = data }
  end)
  return sim, alice, bob
end

local function Death(c) return c.GR:GetModule("Death") end

-- 1) Hostile player in target while in combat: NOT blamed, NOT counted.
do
  local sim, alice, bob = NewPair(1)
  SetWorld(alice, { combat = true, units = { target = { name = "Ganker", realm = "Realm", player = true, hostile = true } } })
  local info = Death(alice).ResolveDeath()
  check("target player: cause unknown", info.cause == "unknown", info.cause)
  check("target player: not reliable", info.reliable == false)
  check("target player: kept only as suspect", info.suspect == "Ganker-Realm", info.suspect)
  check("target player: killer not named", info.killer ~= "Ganker-Realm")
  Death(alice):BroadcastLocalDeath()
  sim:Run(5)
  check("target player: no Wanted entry", Sim.Entries(alice) == 0)
  check("target player: no WK sent", sim:Count("WK") == 0)
  check("target player: diag unclear_killer", (alice.GR.Diag.counters.reject_unclear_killer or 0) == 1)
  local d = bob.deaths[1]
  check("target player: guild toast without name", d and d.data.cause == "unknown" and d.data.killer == "?"
    and d.data.isPlayer == false, d and d.data.killer)
  check("target player: Bob no Wanted entry", Sim.Entries(bob) == 0)
end

-- 2) "attacking" hostile player: same treatment.
do
  local sim, alice = NewPair(2)
  SetWorld(alice, { combat = true, units = { attacking = { name = "Rogue", realm = "Realm", player = true, hostile = true } } })
  Death(alice):BroadcastLocalDeath()
  sim:Run(3)
  check("attacking player: no Wanted entry", Sim.Entries(alice) == 0)
  check("attacking player: no WK", sim:Count("WK") == 0)
end

-- 3) Mob in target: never Wanted.
do
  local sim, alice, bob = NewPair(3)
  SetWorld(alice, { combat = true, units = { target = { name = "Defias Thug", player = false, hostile = true } } })
  local info = Death(alice).ResolveDeath()
  check("mob: cause mob, unreliable", info.cause == "mob" and info.reliable == false)
  Death(alice):BroadcastLocalDeath()
  sim:Run(3)
  check("mob: no Wanted entry", Sim.Entries(alice) == 0)
  check("mob: guild toast mob", bob.deaths[1] and bob.deaths[1].data.cause == "mob")
end

-- 4) Friendly player in target (healer) while a mob kills you: never blamed.
do
  local sim, alice = NewPair(4)
  SetWorld(alice, { combat = true, units = { target = { name = "Healer", realm = "Realm", player = true, hostile = false } } })
  local info = Death(alice).ResolveDeath()
  check("friendly target: not blamed", info.cause ~= "player" and info.suspect == nil)
  Death(alice):BroadcastLocalDeath()
  sim:Run(3)
  check("friendly target: no Wanted entry", Sim.Entries(alice) == 0)
end

-- 5) Out of combat, nothing known: environment, no Wanted.
do
  local sim, alice = NewPair(5)
  SetWorld(alice, { combat = false, units = {} })
  local info = Death(alice).ResolveDeath()
  check("no combat: env", info.cause == "env")
  Death(alice):BroadcastLocalDeath()
  sim:Run(3)
  check("no combat: no Wanted", Sim.Entries(alice) == 0)
end

-- 6) Death context
do
  local _, alice = NewPair(6)
  SetWorld(alice, { noInstanceApi = true })
  local ctx = Death(alice).DeathContext()
  check("ctx: missing IsInInstance -> unknown", ctx.ctxKnown == false)
  SetWorld(alice, { instance = "pvp" })
  ctx = Death(alice).DeathContext()
  check("ctx: battleground", ctx.ctxKnown and ctx.instanceType == "pvp")
  SetWorld(alice, {})
  ctx = Death(alice).DeathContext()
  check("ctx: open world", ctx.ctxKnown and ctx.instanceType == "none")
end

-- 7) Decision table (what a reliable source would be allowed to count)
do
  local L = AngryMurlocs and AngryMurlocs.WantedLogic
  if not L then
    AngryMurlocs = {}
    dofile("Core/WantedLogic.lua")
    L = AngryMurlocs.WantedLogic
  end
  local base = { reliable = true, killer = "Enemy-Realm", killerIsPlayer = true, ctxKnown = true, instanceType = "none", inDuel = false }
  local function With(k, v)
    local d = {}
    for a, b in pairs(base) do d[a] = b end
    d[k] = v
    return d
  end
  check("eval: reliable open world counts", (L.EvaluateDeath(base)))
  check("eval: unreliable", select(2, L.EvaluateDeath(With("reliable", false))) == "unclear_killer")
  check("eval: duel", select(2, L.EvaluateDeath(With("inDuel", true))) == "excluded_duel")
  check("eval: bg", select(2, L.EvaluateDeath(With("instanceType", "pvp"))) == "excluded_bg")
  check("eval: arena", select(2, L.EvaluateDeath(With("instanceType", "arena"))) == "excluded_arena")
  check("eval: unknown ctx", select(2, L.EvaluateDeath(With("ctxKnown", false))) == "ctx_unknown")
  check("eval: npc", select(2, L.EvaluateDeath(With("killerIsPlayer", false))) == "not_player")
  check("eval: empty killer", select(2, L.EvaluateDeath(With("killer", ""))) == "unclear_killer")
end

-- 8) shareDeath off: DEATH not sent, POS dead flag is covered by Positions (client check).
do
  local db = Sim.DefaultDB()
  db.privacy.shareDeath = false
  local sim, alice, bob = NewPair(8, db)
  SetWorld(alice, { combat = false, units = {} })
  Death(alice):BroadcastLocalDeath()
  sim:Run(3)
  check("shareDeath off: no DEATH on wire", sim:Count("DEATH") == 0)
  check("shareDeath off: Bob saw nothing", #bob.deaths == 0)
end

-- 9) Recap event mapping (pure): Creature -> mob toast, Player -> reliable Wanted.
do
  local _, alice = NewPair(9)
  local Map = Death(alice).AttributionFromRecapEvents
  local mob = Map({
    { event = "SWING_DAMAGE", sourceName = "Trash", sourceGUID = "Creature-0-1-0-0-1-0", amount = 10 },
    { event = "SPELL_PERIODIC_DAMAGE", sourceName = "Fleischfressendes Unkraut",
      sourceGUID = "Creature-0-1-0-0-123-0", amount = 34, spellName = "Absorb" },
  })
  check("recap map: last creature is mob", mob and mob.cause == "mob" and mob.reliable == false
    and mob.killer == "Fleischfressendes Unkraut", mob and mob.killer)
  check("recap map: mob spell from event", mob and mob.spell == "Absorb", mob and mob.spell)

  local pvp = Map({
    { event = "SPELL_DAMAGE", sourceName = "Ganker", sourceGUID = "Player-1-ABCDEF",
      spellName = "Eviscerate", overkill = 5 },
  })
  check("recap map: player reliable", pvp and pvp.cause == "player" and pvp.reliable == true
    and pvp.killer == "Ganker" and pvp.isPlayer == true)

  local env = Map({
    { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "FALLING", amount = 50 },
  })
  check("recap map: env fall", env and env.cause == "env" and env.reliable == false)

  check("recap map: empty", Map({}) == nil)
  check("recap map: nil", Map(nil) == nil)
end

-- 10) ResolveDeath uses injected C_DeathRecap (Forever path).
do
  local sim, alice, bob = NewPair(10)
  SetWorld(alice, { combat = true, units = { target = { name = "WrongGuy", realm = "Realm", player = true, hostile = true } } })
  alice.env.C_DeathRecap = {
    GetRecapEvents = function()
      return {
        { event = "SPELL_DAMAGE", sourceName = "RealKiller", sourceGUID = "Player-1-DEADBEEF",
          spellName = "Sinister Strike", overkill = 12 },
      }
    end,
    HasRecapEvents = function() return true end,
  }
  local info = Death(alice).ResolveDeath()
  check("recap resolve: player not target", info.cause == "player" and info.killer == "RealKiller"
    and info.reliable == true and info.source == "recap", info and info.killer)
  Death(alice):BroadcastLocalDeath()
  sim:Run(5)
  check("recap resolve: Wanted counted", Sim.Entries(alice) >= 1)
  check("recap resolve: WK sent", sim:Count("WK") >= 1)
  local d = bob.deaths[1]
  check("recap resolve: guild toast player", d and d.data.cause == "player" and d.data.isPlayer == true
    and tostring(d.data.killer):find("RealKiller"), d and d.data.killer)
end

-- 11) Recap mob: toast mob, no Wanted — even with hostile player targeted.
do
  local sim, alice, bob = NewPair(11)
  SetWorld(alice, { combat = true, units = { target = { name = "Ganker", realm = "Realm", player = true, hostile = true } } })
  alice.env.C_DeathRecap = {
    GetRecapEvents = function()
      return {
        { event = "SPELL_PERIODIC_DAMAGE", sourceName = "Fleischfressendes Unkraut",
          sourceGUID = "Creature-0-1-0-0-99-0", amount = 34 },
      }
    end,
  }
  local info = Death(alice).ResolveDeath()
  check("recap mob: not player target", info.cause == "mob" and info.killer == "Fleischfressendes Unkraut"
    and info.reliable == false)
  Death(alice):BroadcastLocalDeath()
  sim:Run(3)
  check("recap mob: no Wanted", Sim.Entries(alice) == 0)
  check("recap mob: guild toast mob", bob.deaths[1] and bob.deaths[1].data.cause == "mob")
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
