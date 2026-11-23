-- Multi-client simulation of live kills + guild sync with the real Comm/Wanted code.
-- From repo root: luajit Tests/Sync_sim_test.lua
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

local KILLER = "Enemy-Realm"

local function SyncState(c)
  return c.Wanted:SyncStatusText()
end

-- Acceptance 2: live + catch-up + reload counts one kill once.
do
  local sim = Sim.New(7)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  local r = alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  check("A2 own death recorded", r and r.ok and r.level == 1)
  sim:Run(3)
  check("A2 live kill reached Bob", Sim.Level(bob, KILLER) == 1, Sim.Level(bob, KILLER))

  local carol = sim:AddClient("Carol")
  carol.Wanted:RequestSync("delta")
  sim:Run(40)
  check("A2 Carol catch-up level 1", Sim.Level(carol, KILLER) == 1, Sim.Level(carol, KILLER))
  check("A2 Carol sync done", SyncState(carol):find("complete") ~= nil, SyncState(carol))
  check("A2 Bob unchanged by Carol's sync", Sim.Level(bob, KILLER) == 1)
  check("A2 Alice unchanged", Sim.Level(alice, KILLER) == 1)

  carol = sim:Reload(carol)
  check("A2 Carol after reload 1", Sim.Level(carol, KILLER) == 1)
  carol.Wanted:RequestSync("full")
  sim:Run(40)
  check("A2 Carol after reload + full sync still 1", Sim.Level(carol, KILLER) == 1, Sim.Level(carol, KILLER))
  bob = sim:Reload(bob)
  check("A2 Bob after reload 1", Sim.Level(bob, KILLER) == 1)
end

-- Acceptance 3 over the wire: second kill after the pair cooldown = 2 everywhere.
do
  local sim = Sim.New(11)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(5)
  local early = alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  check("A3 within pair CD rejected", early and not early.ok and early.reason == "pair_cd", early and early.reason)
  sim:Run(10)
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(3)
  check("A3 Alice level 2", Sim.Level(alice, KILLER) == 2)
  check("A3 Bob level 2", Sim.Level(bob, KILLER) == 2, Sim.Level(bob, KILLER))
end

-- Acceptance 4: separate offline histories add up (different victims).
do
  local sim = Sim.New(13)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  bob.online = false
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(3)
  alice.online = false
  bob = sim:Reload(bob)
  bob.Wanted:RecordOwnDeath(KILLER, "Arathi")
  sim:Run(3)
  check("A4 Bob alone sees 1", Sim.Level(bob, KILLER) == 1)
  alice = sim:Reload(alice)
  -- same order as the login path (RunGuildSync)
  alice.Wanted:RequestSync("delta")
  check("A4 Alice announces own counter", alice.Wanted:AnnounceOwn() == 1)
  sim:Run(40)
  check("A4 Alice merged 2", Sim.Level(alice, KILLER) == 2, Sim.Level(alice, KILLER))
  check("A4 Bob learned Alice's offline kill", Sim.Level(bob, KILLER) == 2, Sim.Level(bob, KILLER))
  local carol = sim:AddClient("Carol")
  carol.Wanted:RequestSync("full")
  sim:Run(40)
  check("A4 Carol merged 2", Sim.Level(carol, KILLER) == 2, Sim.Level(carol, KILLER))
end

-- Acceptance 6: one responder per request (suppression), across many seeds.
do
  local dupHeaders, dupEnds, wrong, notDone = 0, 0, 0, 0
  for seed = 1, 50 do
    -- 0.5 s channel latency: pessimistic for guild addon messages
    local sim = Sim.New(100 + seed, 0.5)
    local alice = sim:AddClient("Alice")
    sim:AddClient("Bob")
    sim:AddClient("Dave")
    sim:AddClient("Erin")
    alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
    sim:Run(5)
    local carol = sim:AddClient("Carol")
    local hBefore, eBefore = sim:Count("WSH"), sim:Count("WSE")
    carol.Wanted:RequestSync("full")
    sim:Run(40)
    if sim:Count("WSH") - hBefore > 1 then dupHeaders = dupHeaders + 1 end
    if sim:Count("WSE") - eBefore > 1 then dupEnds = dupEnds + 1 end
    if Sim.Level(carol, KILLER) ~= 1 then wrong = wrong + 1 end
    if not SyncState(carol):find("complete") then notDone = notDone + 1 end
  end
  print(string.format("    suppression: %d/50 runs with a second header, %d/50 with a second full response",
    dupHeaders, dupEnds))
  check("A6 second full response rare (<=2/50)", dupEnds <= 2, dupEnds)
  check("A6 level correct in all runs", wrong == 0, wrong)
  check("A6 sync complete in all runs", notDone == 0, notDone)
end

-- Acceptance 6 (simulated): N members log in at once -> bounded traffic, no loop.
for _, N in ipairs({ 12, 30 }) do
  local sim = Sim.New(53 + N, 0.2)
  local clients = {}
  for i = 1, N do
    clients[i] = sim:AddClient("M" .. string.format("%02d", i))
  end
  for i = 1, N do
    sim:Run(11)
    clients[i].Wanted:RecordOwnDeath("Killer" .. i .. "-Realm", "Z")
  end
  sim:Run(5)
  local busStart = #sim.bus
  local srStart = sim:Count("SR")
  -- everyone reloads within the same second (login path order)
  for i = 1, N do
    clients[i] = sim:Reload(clients[i])
  end
  for i = 1, N do
    clients[i].Wanted:RequestSync("delta")
    clients[i].Wanted:AnnounceOwn()
  end
  sim:Run(400)
  local msgs = #sim.bus - busStart
  local sr = sim:Count("SR") - srStart
  local done, other = 0, {}
  for i = 1, N do
    local st = SyncState(clients[i])
    if st:find("complete") then done = done + 1 else other[#other + 1] = st end
  end
  local tag = "A6 storm " .. N
  print(string.format("    login storm %d: %d messages, %d SR, %d/%d complete", N, msgs, sr, done, N))
  check(tag .. ": all complete", done == N, table.concat(other, " | "))
  check(tag .. ": SR bounded (<= 3 per member)", sr <= 3 * N, sr)
  check(tag .. ": all levels " .. N, (function()
    for i = 1, N do
      local sum = 0
      for k in pairs(clients[i].GR.Util.GetScopeDB().wanted) do sum = sum + Sim.Level(clients[i], k) end
      if sum ~= N then return false end
    end
    return true
  end)())
  local before = #sim.bus
  sim:Run(300)
  check(tag .. ": no further traffic (no sync loop)", #sim.bus == before, #sim.bus - before)
  local maxQueue = 0
  for i = 1, N do
    local q = clients[i].GR.Comm:QueueSize()
    if q > maxQueue then maxQueue = q end
  end
  check(tag .. ": queues drained", maxQueue == 0, maxQueue)
end

-- No responder: alone in the guild -> visible "no responding member", button unlocks.
do
  local sim = Sim.New(17)
  local alone = sim:AddClient("Alone")
  alone.Wanted:RequestSync("delta")
  sim:Run(1)
  check("noreply busy while waiting", alone.Wanted:IsSyncBusy())
  sim:Run(20)
  check("noreply status", SyncState(alone):find("no responding") ~= nil, SyncState(alone))
  check("noreply unlocks", not alone.Wanted:IsSyncBusy())
end

-- Not in a guild.
do
  local sim = Sim.New(19)
  local solo = sim:AddClient("Solo", { guild = false })
  check("noguild refused", solo.Wanted:RequestSync("full") == false)
  check("noguild status", SyncState(solo):find("not in a guild") ~= nil, SyncState(solo))
end

-- Paging: 300 entries reach the requester completely (auto pages, then resume).
do
  local sim = Sim.New(23)
  local bob = sim:AddClient("Bob")
  local scope = bob.GR.Util.GetScopeDB()
  local L = bob.GR.WantedLogic
  local cfg = L.GetFixedConfig()
  local state = { wanted = scope.wanted, hidden = scope.wantedHidden }
  for i = 1, 300 do
    L.MergeOrigin(state, cfg, "Killer" .. i .. "-Realm", "Victim" .. (i % 7), { n = 1, seq = i, t = sim:Wall() - i, zone = "Z" },
      sim:Wall(), { direct = true, via = "Victim" .. (i % 7) })
  end
  check("paging source has 300", Sim.Entries(bob) == 300)
  local carol = sim:AddClient("Carol")
  carol.Wanted:RequestSync("full")
  local rounds = 0
  while rounds < 6 do
    sim:Run(120)
    if not carol.Wanted:IsSyncBusy() and not SyncState(carol):find("partial") then break end
    if SyncState(carol):find("partial") then
      carol.Wanted:RequestSync("full")
    end
    rounds = rounds + 1
  end
  check("paging all 300 received", Sim.Entries(carol) == 300, Sim.Entries(carol))
  check("paging ends complete", SyncState(carol):find("complete") ~= nil, SyncState(carol))
  local sum = 0
  for k in pairs(carol.GR.Util.GetScopeDB().wanted) do sum = sum + Sim.Level(carol, k) end
  check("paging no double counts (sum 300)", sum == 300, sum)
end

-- Privacy: shareDeath off -> no WK on the wire, own origins not served in sync.
do
  local sim = Sim.New(29)
  local db = Sim.DefaultDB()
  db.privacy.shareDeath = false
  local alice = sim:AddClient("Alice", { db = db })
  local bob = sim:AddClient("Bob")
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(3)
  check("privacy local level 1", Sim.Level(alice, KILLER) == 1)
  check("privacy no WK sent", sim:Count("WK") == 0)
  check("privacy Bob sees nothing live", Sim.Level(bob, KILLER) == 0)
  bob.online = false
  local carol = sim:AddClient("Carol")
  carol.Wanted:RequestSync("full")
  sim:Run(40)
  check("privacy own origin not served", Sim.Level(carol, KILLER) == 0, Sim.Level(carol, KILLER))
end

-- Legacy 0.6.x Wanted wire is ignored.
do
  local sim = Sim.New(31)
  local bob = sim:AddClient("Bob")
  bob.GR.Comm:OnAddonMessage("GildenRadar", "WANTED|kill|Enemy-Realm|Victim|5|1700000000|Zone", "GUILD", "Old-Realm")
  bob.GR.Comm:OnAddonMessage("GildenRadar", "WANTED|clear|Enemy-Realm", "GUILD", "Old-Realm")
  bob.GR.Comm:OnAddonMessage("GildenRadar", "SYNCREQ|0", "GUILD", "Old-Realm")
  sim:Run(5)
  check("legacy WANTED ignored", Sim.Entries(bob) == 0)
  check("legacy counted in diag", (bob.GR.Diag.counters.legacy_ignored or 0) == 3)
  check("legacy SYNCREQ not answered", sim:Count("WSH") == 0)
end

-- Forged live kill: origin must be the sender.
do
  local sim = Sim.New(37)
  local bob = sim:AddClient("Bob")
  bob.GR.Comm:OnAddonMessage("GildenRadar", "WK|Enemy-Realm|Alice|1|1|" .. sim:Wall() .. "|Z", "GUILD", "Mallory-Realm")
  sim:Run(2)
  check("forged WK rejected", Sim.Level(bob, KILLER) == 0)
  check("forged WK diag reason", (bob.GR.Diag.counters.reject_origin_mismatch or 0) == 1)
end

-- ClassFile can be set locally on a Wanted entry (no hide UI).
do
  local sim = Sim.New(41)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(3)
  check("bob has killer", bob.Wanted:Summary().total == 1)
  bob.Wanted:SetClassFile(KILLER, "MAGE")
  local entry = bob.Wanted:State().wanted[KILLER]
  check("classFile stored", entry and entry.classFile == "MAGE")
end

-- Send rate: never more than 2 messages per second from one client.
do
  local sim = Sim.New(43)
  local bob = sim:AddClient("Bob")
  for i = 1, 40 do
    bob.GR.Comm:Send("LVL|" .. (i % 60 + 1), "ctrl", "lvl")
  end
  sim:Run(25)
  local times = {}
  for _, m in ipairs(sim.bus) do if m.from == "Bob" then times[#times + 1] = m.t end end
  local maxIn10 = 0
  for i = 1, #times do
    local n = 0
    for j = i, #times do if times[j] - times[i] < 10 then n = n + 1 end end
    if n > maxIn10 then maxIn10 = n end
  end
  -- first message leaves immediately, then the ctrl lane holds 30
  check("rate: ctrl cap bounded", #times == 31, #times)
  check("rate: <=21 per 10s (receiver limit 24)", maxIn10 <= 21, maxIn10)
end

local function WaitReqId(sim, client)
  client.Wanted:RequestSync("full")
  -- RequestSync coalesces 1.5s before sending SR.
  sim:Run(3)
  local P = client.GR.Protocol
  for _, m in ipairs(sim.bus) do
    if m.from == client.name and m.msg:sub(1, 3) == "SR|" then
      local d = P.DecodeSR(m.msg:sub(4))
      if d and d.reqId then return d.reqId, P end
    end
  end
  return nil, P
end

-- Short sync page must not mark success / lastOkAt.
do
  local sim = Sim.New(61)
  local carol = sim:AddClient("Carol")
  local reqId, P = WaitReqId(sim, carol)
  check("short-page: have reqId", reqId ~= nil, tostring(reqId))
  local wall = sim:Wall()
  local beforeOk = carol.Wanted:GetLastSyncOkAt() or 0
  carol.GR.Comm:OnAddonMessage("GildenRadar", P.EncodeWSH("Carol", reqId, 2), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSOrigin(reqId, "Foe-Realm", "Alice", 1, 1, wall, "Elwynn"), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSE("Carol", reqId, 2, false, 0, ""), "GUILD", "Alice-Realm")
  sim:Run(2)
  check("short-page: level still 1", Sim.Level(carol, "Foe-Realm") == 1)
  check("short-page: incomplete", SyncState(carol):find("incomplete") ~= nil, SyncState(carol))
  check("short-page: lastOk untouched", (carol.Wanted:GetLastSyncOkAt() or 0) == beforeOk)
end

-- Full page still completes.
do
  local sim = Sim.New(62)
  local carol = sim:AddClient("Carol")
  local reqId, P = WaitReqId(sim, carol)
  local wall = sim:Wall()
  carol.GR.Comm:OnAddonMessage("GildenRadar", P.EncodeWSH("Carol", reqId, 2), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSOrigin(reqId, "Foe-Realm", "Alice", 1, 1, wall, "Elwynn"), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSOrigin(reqId, "Other-Realm", "Bob", 1, 1, wall, "Westfall"), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSE("Carol", reqId, 2, false, 0, ""), "GUILD", "Alice-Realm")
  sim:Run(2)
  check("full-page: complete", SyncState(carol):find("complete") ~= nil, SyncState(carol))
  check("full-page: lastOk set", (carol.Wanted:GetLastSyncOkAt() or 0) > 0)
end

-- Legacy-0 entry header sight applies after first origin (not before).
do
  local sim = Sim.New(63)
  local carol = sim:AddClient("Carol")
  local reqId, P = WaitReqId(sim, carol)
  local wall = sim:Wall()
  local seenT = wall - 10
  carol.GR.Comm:OnAddonMessage("GildenRadar", P.EncodeWSH("Carol", reqId, 2), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSEntry(reqId, "SightFoe-Realm", 0, seenT, "Elwynn", "Alice-Realm"), "GUILD", "Alice-Realm")
  check("sight-header: no entry yet", Sim.Level(carol, "SightFoe-Realm") == 0)
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSOrigin(reqId, "SightFoe-Realm", "Alice", 1, 1, wall, "Elwynn"), "GUILD", "Alice-Realm")
  carol.GR.Comm:OnAddonMessage("GildenRadar",
    P.EncodeWSE("Carol", reqId, 2, false, 0, ""), "GUILD", "Alice-Realm")
  sim:Run(2)
  local e = carol.Wanted:State().wanted["SightFoe-Realm"]
  check("sight-header: level 1", Sim.Level(carol, "SightFoe-Realm") == 1)
  check("sight-header: lastSeenTime", e and e.lastSeenTime == seenT, e and e.lastSeenTime)
  check("sight-header: zone", e and e.lastSeenZone == "Elwynn", e and e.lastSeenZone)
  check("sight-header: complete", SyncState(carol):find("complete") ~= nil, SyncState(carol))
end

local OLD_SCOPE = "CAMWOWEU4Realm6PvP::Angry Murlocs"
local CLUB = "215871062"
local LEGACY_REALM = "CAMWOWEU4Realm6PvP"
local LEGACY_ROK = "Rok-" .. LEGACY_REALM

local function EmptyRealmOpts(name)
  return {
    guild = "Angry Murlocs",
    guildClubId = CLUB,
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
      UnitFullName = function(unit)
        if unit == "player" then return name, "" end
        return nil
      end,
    },
  }
end

local function LevelAny(c, name)
  local U = c.GR.Util
  local scope = U.GetScopeDB()
  if not scope or not scope.wanted then return 0 end
  local key = U.ResolveKeyedName(scope.wanted, name)
  local e = scope.wanted[key]
  return e and c.GR.WantedLogic.Level(e) or 0
end

-- Imported Rok legacy: sight before next kill; level 2; sync + empty-realm reload.
do
  local sim = Sim.New(70)
  local alice = sim:AddClient("Alice", EmptyRealmOpts("Alice"))
  local bob = sim:AddClient("Bob", EmptyRealmOpts("Bob"))
  local U = alice.GR.Util
  check("rok: RealmKey nil", U.RealmKey() == nil)
  check("rok: club", U.GuildScopeKey() == "club:" .. CLUB)
  local db = alice.GR.db
  db.scopes[OLD_SCOPE] = {
    wanted = {
      [LEGACY_ROK] = {
        schema = 2,
        legacy = 0,
        origins = {
          ["alice"] = { name = "Alice", n = 1, seq = 1, t = sim:Wall() - 100, zone = "Hillsbrad", direct = true, own = true },
        },
        count = 1,
        lastKillTime = sim:Wall() - 100,
        lastVictim = "Alice",
        lastZone = "Hillsbrad",
        lastSeenTime = 0,
        lastSeenZone = "",
        lastSeenBy = "",
        changedAt = sim:Wall() - 100,
      },
    },
    wantedHidden = {},
    wantedSelf = {},
    prof = { cache = {} },
  }
  -- Origin key must match current CharKey("Alice") after identity change.
  local vk = alice.GR.WantedLogic.CharKey("Alice")
  db.scopes[OLD_SCOPE].wanted[LEGACY_ROK].origins = {
    [vk] = { name = "Alice", n = 1, seq = 1, t = sim:Wall() - 100, zone = "Hillsbrad", direct = true, own = true },
  }
  local ok, err = U.ImportScope(OLD_SCOPE, "club:" .. CLUB)
  check("rok: import", ok == true, tostring(err))
  local scope = U.GetScopeDB()
  local key = U.ResolveKeyedName(scope.wanted, "Rok")
  check("rok: folded key", key ~= nil and LevelAny(alice, "Rok") == 1, key)
  local seenOk = alice.Wanted:ApplySighting("Rok", "Hillsbrad", "Bob", sim:Wall(), 1434, 0.4, 0.5)
  check("rok: sight before kill", seenOk == true)
  local e = scope.wanted[key] or scope.wanted[U.ResolveKeyedName(scope.wanted, "Rok")]
  key = U.ResolveKeyedName(alice.Wanted:State().wanted, "Rok")
  e = alice.Wanted:State().wanted[key]
  check("rok: sight time set", e and (e.lastSeenTime or 0) > 0, e and e.lastSeenTime)
  sim:Run(15)
  local r2 = alice.Wanted:RecordOwnDeath("Rok", "Hillsbrad")
  check("rok: second kill", r2 and r2.ok and r2.level == 2, r2 and r2.reason)
  sim:Run(3)
  check("rok: bob level 2", LevelAny(bob, "Rok") == 2, LevelAny(bob, "Rok"))
  bob.Wanted:RequestSync("full")
  sim:Run(40)
  check("rok: after sync still 2", LevelAny(bob, "Rok") == 2)
  bob = sim:Reload(bob)
  check("rok: reload RealmKey nil", bob.GR.Util.RealmKey() == nil)
  check("rok: reload club", bob.GR.Util.GuildScopeKey() == "club:" .. CLUB)
  check("rok: after reload 2", LevelAny(bob, "Rok") == 2)
end

-- Two victims same first name → two origin counters (direct + announce + sync).
do
  local sim = Sim.New(71)
  local mond = sim:AddClient("Mani-Mond", EmptyRealmOpts("Mani-Mond"))
  local stein = sim:AddClient("Mani-Stein", EmptyRealmOpts("Mani-Stein"))
  local carol = sim:AddClient("Carol", EmptyRealmOpts("Carol"))
  local K = "FoeX"
  local r1 = mond.Wanted:RecordOwnDeath(K, "ZoneA")
  check("dual: mond recorded", r1 and r1.ok and r1.level == 1)
  sim:Run(3)
  local r2 = stein.Wanted:RecordOwnDeath(K, "ZoneB")
  check("dual: stein recorded", r2 and r2.ok)
  sim:Run(3)
  check("dual: level 2 on mond", LevelAny(mond, K) == 2, LevelAny(mond, K))
  check("dual: level 2 on carol", LevelAny(carol, K) == 2, LevelAny(carol, K))
  local e = mond.Wanted:State().wanted[K] or mond.Wanted:State().wanted[mond.GR.Util.ResolveKeyedName(mond.Wanted:State().wanted, K)]
  local origins = e and e.origins or {}
  local nOrig = 0
  for _ in pairs(origins) do nOrig = nOrig + 1 end
  check("dual: two origins", nOrig == 2, tostring(nOrig))
  -- Login re-announce idempotent.
  local before = LevelAny(carol, K)
  check("dual: announce count", mond.Wanted:AnnounceOwn() >= 1)
  sim:Run(5)
  check("dual: after announce still 2", LevelAny(carol, K) == before)
  carol.Wanted:RequestSync("full")
  sim:Run(40)
  check("dual: after sync 2", LevelAny(carol, K) == 2)
end

-- Old v2 direct with shortened origin must not merge into a specific namesake.
do
  local sim = Sim.New(72)
  local carol = sim:AddClient("Carol", EmptyRealmOpts("Carol"))
  local P = carol.GR.Protocol
  local wall = sim:Wall()
  local prefix = carol.GR.PREFIX or "GildenRadar"
  -- Short origin "Mani" while both Mani-Mond and Mani-Stein exist as peers conceptually.
  carol.GR.Comm:OnAddonMessage(prefix, P.EncodeWK({
    killer = "ShortFoe", origin = "Mani", n = 1, seq = 1, t = wall, zone = "A",
  }), "GUILD", "Mani-Mond")
  sim:Run(1)
  local e = carol.Wanted:State().wanted["ShortFoe"]
  check("v2short: entry level 1", e and carol.GR.WantedLogic.Level(e) == 1)
  local vkShort = carol.GR.WantedLogic.CharKey("Mani")
  local vkMond = carol.GR.WantedLogic.CharKey("Mani-Mond")
  check("v2short: short key != mond", vkShort ~= vkMond, tostring(vkShort) .. "/" .. tostring(vkMond))
  check("v2short: origin under short key", e and e.origins[vkShort] ~= nil)
  check("v2short: not under mond key", e and e.origins[vkMond] == nil)
end

-- Relayed WS origin uses same identity rules as direct.
do
  local sim = Sim.New(73)
  local carol = sim:AddClient("Carol", EmptyRealmOpts("Carol"))
  local P = carol.GR.Protocol
  local wall = sim:Wall()
  local prefix = carol.GR.PREFIX or "GildenRadar"
  local reqId = "rel1"
  carol.GR.Comm:OnAddonMessage(prefix, P.EncodeWSH("Carol", reqId, 2), "GUILD", "Alice")
  carol.GR.Comm:OnAddonMessage(prefix,
    P.EncodeWSEntry(reqId, "RelayFoe", 0, 0, "", ""), "GUILD", "Alice")
  carol.GR.Comm:OnAddonMessage(prefix,
    P.EncodeWSOrigin(reqId, "RelayFoe", "Mani-Mond", 1, 1, wall, "A"), "GUILD", "Alice")
  carol.GR.Comm:OnAddonMessage(prefix,
    P.EncodeWSOrigin(reqId, "RelayFoe", "Mani-Stein", 1, 1, wall, "B"), "GUILD", "Alice")
  carol.GR.Comm:OnAddonMessage(prefix, P.EncodeWSE("Carol", reqId, 3, false, 0, ""), "GUILD", "Alice")
  sim:Run(2)
  check("relay: level 2", LevelAny(carol, "RelayFoe") == 2, LevelAny(carol, "RelayFoe"))
  local e = carol.Wanted:State().wanted["RelayFoe"]
  local nOrig = 0
  for _ in pairs(e and e.origins or {}) do nOrig = nOrig + 1 end
  check("relay: two origins", nOrig == 2, tostring(nOrig))
end

-- Split store fold: hidden, seq, kills survive double load.
do
  local sim = Sim.New(74)
  local alice = sim:AddClient("Alice", EmptyRealmOpts("Alice"))
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  local vk = alice.GR.WantedLogic.CharKey("Alice")
  local t0 = sim:Wall() - 50
  scope.wanted[LEGACY_ROK] = {
    schema = 2, legacy = 0,
    origins = { [vk] = { name = "Alice", n = 2, seq = 5, t = t0, zone = "Z", direct = true, own = true } },
    count = 2, lastKillTime = t0, lastVictim = "Alice", lastZone = "Z",
    lastSeenTime = t0 + 1, lastSeenZone = "Z", lastSeenBy = "Bob", changedAt = t0,
  }
  scope.wanted["Rok"] = {
    schema = 2, legacy = 0,
    origins = { [vk] = { name = "Alice", n = 1, seq = 2, t = t0 - 10, zone = "Y", direct = true, own = true } },
    count = 1, lastKillTime = t0 - 10, lastVictim = "Alice", lastZone = "Y",
    lastSeenTime = 0, lastSeenZone = "", lastSeenBy = "", changedAt = t0 - 10,
  }
  scope.wantedHidden[LEGACY_ROK] = { level = 2, t = t0 }
  scope.wantedHidden["Rok"] = { level = 1, t = t0 - 5 }
  scope.wantedSelf[vk] = {
    seq = 5,
    kills = {
      [string.lower(LEGACY_ROK)] = { n = 2, t = t0 },
      ["rok"] = { n = 1, t = t0 - 10 },
    },
  }
  U.FoldScopeCharacterKeys(scope)
  local key = U.ResolveKeyedName(scope.wanted, "Rok")
  check("split: one wanted entry", (function()
    local n = 0 for _ in pairs(scope.wanted) do n = n + 1 end return n == 1
  end)())
  check("split: max n=2", LevelAny(alice, "Rok") == 2)
  check("split: hidden kept", scope.wantedHidden[key] and scope.wantedHidden[key].level == 2)
  check("split: self seq", scope.wantedSelf[vk] and scope.wantedSelf[vk].seq == 5)
  local kills = scope.wantedSelf[vk].kills
  local kn = 0
  for _ in pairs(kills) do kn = kn + 1 end
  check("split: one killer bag", kn == 1, tostring(kn))
  local _, krec = next(kills)
  check("split: kill n=2", krec and krec.n == 2)
  -- Double load idempotent.
  U.FoldScopeCharacterKeys(scope)
  U.FoldScopeCharacterKeys(scope)
  check("split: still level 2", LevelAny(alice, "Rok") == 2)
  check("split: still seq 5", scope.wantedSelf[vk].seq == 5)
  alice = sim:Reload(alice)
  check("split: reload empty realm", alice.GR.Util.RealmKey() == nil)
  check("split: after reload level 2", LevelAny(alice, "Rok") == 2)
  alice = sim:Reload(alice)
  check("split: second reload level 2", LevelAny(alice, "Rok") == 2)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
