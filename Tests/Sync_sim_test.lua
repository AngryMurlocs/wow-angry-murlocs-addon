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

-- Local hide survives an old sync, returns on a newer kill (acceptance 10 over the wire).
do
  local sim = Sim.New(41)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(3)
  bob.Wanted:Hide(KILLER)
  local s = bob.Wanted:Summary()
  check("hide removes from Bob's list", s.total == 0 and s.hidden == 1)
  bob.Wanted:RequestSync("full")
  sim:Run(40)
  s = bob.Wanted:Summary()
  check("hide survives old sync", s.total == 0 and s.hidden == 1)
  check("hide is local only (Alice still lists)", alice.Wanted:Summary().total == 1)
  sim:Run(11)
  alice.Wanted:RecordOwnDeath(KILLER, "Hillsbrad")
  sim:Run(3)
  s = bob.Wanted:Summary()
  check("hidden entry returns on higher level", s.total == 1 and s.hidden == 0)
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

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
