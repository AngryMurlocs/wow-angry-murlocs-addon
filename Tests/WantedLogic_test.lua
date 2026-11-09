-- From repo root: luajit Tests/WantedLogic_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/WantedLogic.lua")

local L = AngryMurlocs.WantedLogic
assert(L, "WantedLogic missing")

local fails = 0
local function check(name, cond)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name)
  end
end

local function NewState()
  return { wanted = {}, hidden = {} }
end

local function CountKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Simulated SavedVariables round trip (reload).
local function Clone(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = Clone(x) end
  return c
end

local cfg = L.GetFixedConfig()
check("fixed pairCD 10", cfg.pairCooldownSec == 10)
check("fixed max 1000", cfg.maxAutoWanted == 1000)
check("fixed expire off", cfg.autoExpireSec == 0)
check("fixed ignores overrides", L.GetFixedConfig().pairCooldownSec == 10)

-- Acceptance 1: one valid death -> exactly one kill, level 1
do
  local s, me = NewState(), {}
  local r = L.RecordOwnDeath(s, cfg, me, "Enemy-Realm", "Victim-Realm", "Hillsbrad", 1000)
  check("A1 recorded", r.ok and r.isNew)
  check("A1 level 1", s.wanted["Enemy-Realm"].count == 1)
  check("A1 event id origin:seq", r.eventId == "victim:1")
end

-- Acceptance 2: identical event via live, catch-up relay and reload -> still one kill
do
  local victimState, me = NewState(), {}
  local r = L.RecordOwnDeath(victimState, cfg, me, "Enemy-Realm", "Victim-Realm", "Z", 1000)
  local peer = NewState()
  local rec = { n = r.n, seq = r.seq, t = r.t, zone = r.zone }
  local live = L.MergeOrigin(peer, cfg, "Enemy-Realm", "Victim-Realm", rec, 1001, { direct = true, via = "Victim-Realm" })
  local relay = L.MergeOrigin(peer, cfg, "Enemy-Realm", "Victim", rec, 1002, { direct = false, via = "Other-Realm" })
  local reloaded = Clone(peer)
  local again = L.MergeOrigin(reloaded, cfg, "Enemy-Realm", "Victim Realm-Realm", rec, 2000, { direct = true })
  check("A2 live merged", live.ok and live.added == 1)
  check("A2 relay dup", not relay.ok and relay.reason == "dup")
  check("A2 reload dup", not again.ok and again.reason == "dup")
  check("A2 level 1", reloaded.wanted["Enemy-Realm"].count == 1)
end

-- Acceptance 3: two different deaths after pair CD -> two kills
do
  local s, me = NewState(), {}
  L.RecordOwnDeath(s, cfg, me, "Ganker", "Me", "Z", 1000)
  local blocked = L.RecordOwnDeath(s, cfg, me, "Ganker", "Me", "Z", 1005)
  check("A3 pair cd blocks within 10s", not blocked.ok and blocked.reason == "pair_cd")
  local second = L.RecordOwnDeath(s, cfg, me, "Ganker", "Me", "Z", 1011)
  check("A3 same minute after CD counts", second.ok and second.n == 2)
  check("A3 level 2", s.wanted["Ganker"].count == 2)
  check("A3 distinct event ids", second.eventId == "me:2")
end

-- Acceptance 4: two separate offline states -> both events survive the merge
do
  local a, b = NewState(), NewState()
  local legacy = { schema = 2, legacy = 2, origins = {}, changedAt = 1 }
  a.wanted.K = Clone(legacy)
  b.wanted.K = Clone(legacy)
  L.Recount(a.wanted.K); L.Recount(b.wanted.K)
  L.RecordOwnDeath(a, cfg, {}, "K", "VictimA", "Z", 5000)
  L.RecordOwnDeath(b, cfg, {}, "K", "VictimB", "Z", 5001)
  local merged = Clone(a)
  for vk, o in pairs(b.wanted.K.origins) do
    L.MergeOrigin(merged, cfg, "K", o.name, o, 6000, { direct = false, via = "B" })
  end
  L.MergeEntryHeader(merged, cfg, "K", { legacy = b.wanted.K.legacy }, 6000)
  check("A4 offline union level 4", merged.wanted.K.count == 4)
  -- Overlapping snapshots of the same origin never add up.
  local o = NewState()
  L.MergeOrigin(o, cfg, "K", "V", { n = 2, seq = 5, t = 100 }, 200, {})
  L.MergeOrigin(o, cfg, "K", "V", { n = 3, seq = 6, t = 150 }, 200, {})
  L.MergeOrigin(o, cfg, "K", "V", { n = 2, seq = 5, t = 100 }, 200, {})
  check("A4 overlap max not sum", o.wanted.K.count == 3)
end

-- Acceptance 5: excluded contexts / unclear killer never count
do
  local base = { reliable = true, killer = "X", killerIsPlayer = true, ctxKnown = true, instanceType = "none" }
  local function with(over)
    local d = Clone(base)
    for k, v in pairs(over) do d[k] = v end
    return d
  end
  check("A5 valid ok", (L.EvaluateDeath(base)))
  local ok, why = L.EvaluateDeath(with({ reliable = false }))
  check("A5 unclear killer", not ok and why == "unclear_killer")
  ok, why = L.EvaluateDeath(with({ killerIsPlayer = false }))
  check("A5 npc", not ok and why == "not_player")
  ok, why = L.EvaluateDeath(with({ inDuel = true }))
  check("A5 duel", not ok and why == "excluded_duel")
  ok, why = L.EvaluateDeath(with({ instanceType = "pvp" }))
  check("A5 bg", not ok and why == "excluded_bg")
  ok, why = L.EvaluateDeath(with({ instanceType = "arena" }))
  check("A5 arena", not ok and why == "excluded_arena")
  ok, why = L.EvaluateDeath(with({ ctxKnown = false }))
  check("A5 unknown context", not ok and why == "ctx_unknown")
  ok, why = L.EvaluateDeath(with({ killer = "" }))
  check("A5 empty killer", not ok)
end

-- Validation guards
do
  local s = NewState()
  local fut = L.MergeOrigin(s, cfg, "K", "V", { n = 1, seq = 1, t = 99999 }, 1000, {})
  check("future ts rejected", not fut.ok and fut.reason == "future_ts")
  local self = L.MergeOrigin(s, cfg, "Same-Realm", "Same", { n = 1, seq = 1, t = 10 }, 1000, {})
  check("self kill rejected", not self.ok and self.reason == "self_kill")
  check("no entry created on reject", s.wanted.K == nil)
  local hdr = L.MergeEntryHeader(s, cfg, "Nobody", { legacy = 0, seenT = 50 }, 1000)
  check("header w/o legacy creates nothing", not hdr and s.wanted.Nobody == nil)
end

-- Relayed -> direct upgrade does not count twice
do
  local s = NewState()
  L.MergeOrigin(s, cfg, "K", "V", { n = 1, seq = 1, t = 10 }, 100, { direct = false, via = "R" })
  local up = L.MergeOrigin(s, cfg, "K", "V", { n = 1, seq = 1, t = 10 }, 100, { direct = true })
  check("upgrade flag only", up.upgraded and s.wanted.K.count == 1 and s.wanted.K.origins.v.direct)
end

-- Own counter recovers from guild data (lost SavedVariables)
do
  local s, me = NewState(), {}
  L.MergeOrigin(s, cfg, "K", "Me", { n = 3, seq = 7, t = 10 }, 100, { direct = false, selfKey = "me", selfState = me })
  local r = L.RecordOwnDeath(s, cfg, me, "K", "Me", "Z", 200)
  check("own counter continues at 4", r.ok and r.n == 4 and r.seq == 8)
end

-- Migration 0.6.1 -> schema 2 is idempotent
do
  local e = { count = 5, lastTime = 100, lastKillTime = 100, events = { x = true }, victims = { a = 1 }, killTimes = { 1 }, source = "auto" }
  check("migrate converts", L.MigrateEntryV2(e))
  check("migrate keeps level", e.count == 5 and e.legacy == 5)
  check("migrate drops event maps", e.events == nil and e.victims == nil and e.killTimes == nil)
  check("migrate twice no-op", not L.MigrateEntryV2(e) and L.Level(e) == 5)
end

-- Scope recovery union
do
  local a = { schema = 2, legacy = 1, origins = { v = { name = "V", n = 2, t = 10 } } }
  local b = { schema = 2, legacy = 3, origins = { v = { name = "V", n = 1, t = 5 }, w = { name = "W", n = 1, t = 20 } } }
  local m = L.MergeEntryInto(a, b)
  check("merge entry union", L.Level(m) == 3 + 2 + 1)
end

-- Caps: entries 1000-style cap, origins per entry
do
  local s = NewState()
  local small = L.NormalizeConfig({ maxAutoWanted = 3, maxOrigins = 2 })
  for i = 1, 8 do
    L.MergeOrigin(s, small, "W" .. i, "V", { n = i, seq = i, t = 100 + i }, 1000, {})
  end
  for i = 1, 4 do
    L.MergeOrigin(s, small, "W8", "O" .. i, { n = 1, seq = 1, t = 200 + i }, 1000, {})
  end
  local st = L.Prune(s, small, 1000)
  check("entry cap <=3", CountKeys(s.wanted) == 3)
  check("strongest kept", s.wanted.W8 ~= nil and s.wanted.W1 == nil)
  check("origin cap <=2", CountKeys(s.wanted.W8.origins) == 2)
  check("prune reports origin loss", st.removedOrigins > 0)
end

-- No time expire
do
  local s = NewState()
  L.MergeOrigin(s, cfg, "Old", "V", { n = 2, seq = 1, t = 1000 }, 1000, {})
  L.Prune(s, cfg, 1000 + 400 * 86400)
  check("no expire", s.wanted.Old ~= nil)
end

-- Local hide markers still exist in logic, but Sorted always lists entries (UI hide removed).
do
  local s = NewState()
  L.MergeOrigin(s, cfg, "K", "V", { n = 2, seq = 2, t = 100 }, 200, {})
  L.Hide(s, "K", 300)
  check("hide marker set", L.IsHidden(s, "K", s.wanted.K))
  local list, hidden = L.Sorted(s, 400)
  check("Sorted ignores hide markers", #list == 1 and hidden == 0)
  check("unhide all", L.UnhideAll(s) == 1)
  check("unhidden", not L.IsHidden(s, "K", s.wanted.K))
end

-- Acceptance 7: more than 40 entries -> sorted list keeps all, top 40 is a view
do
  local s = NewState()
  for i = 1, 95 do
    L.MergeOrigin(s, cfg, string.format("K%03d", i), "V", { n = (i % 7) + 1, seq = 1, t = 100 + i }, 1000, {})
  end
  local list = L.Sorted(s, 1000)
  check("A7 total 95 stored", #list == 95)
  check("A7 sorted by level", list[1].level >= list[40].level and list[40].level >= list[95].level)
  local f = L.Sorted(s, 1000, { filter = "k09" })
  check("search filter", #f == 6)
end

-- Sync paging covers every entry once, even with identical changedAt
do
  local s = NewState()
  for i = 1, 300 do
    local e = L.NewEntry()
    e.legacy = 1
    e.changedAt = 777
    L.Recount(e)
    s.wanted["L" .. i] = e
  end
  local seen, pages, cT, cK, more = {}, 0, 0, "", true
  while more and pages < 20 do
    local page
    page, more, cT, cK = L.SyncPage(s, cT, cK, 120)
    pages = pages + 1
    for i = 1, #page do
      seen[page[i].key] = (seen[page[i].key] or 0) + 1
    end
  end
  local dupes = 0
  for _, c in pairs(seen) do if c > 1 then dupes = dupes + 1 end end
  check("paging all 300", CountKeys(seen) == 300)
  check("paging no dupes", dupes == 0)
  check("paging 3 pages", pages == 3)
  local skip = L.SyncPage(s, 0, "", 1000, { skipOrigin = function() return true end })
  check("skipOrigin keeps headers", #skip == 300)
end

-- Ranks
check("rank 1 MARKED", L.RankFromLevel(1).key == "MARKED")
check("rank 3 HUNTED", L.RankFromLevel(3).key == "HUNTED")
check("rank 5 BOUNTY", L.RankFromLevel(5).key == "BOUNTY")
check("rank 8 ENEMY", L.RankFromLevel(8).key == "ENEMY")
check("rank 12 SCOURGE", L.RankFromLevel(12).key == "SCOURGE")

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
