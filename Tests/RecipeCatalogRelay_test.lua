-- PROFRO catalog relay: owner parse, merge provenance, rotation, scope, privacy.
-- From repo root: luajit Tests/RecipeCatalogRelay_test.lua
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

local function wipe(t)
  if not t then return end
  for k in pairs(t) do t[k] = nil end
end

local RESULT = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 }

local function MakeClient(sim, name, guild)
  return sim:AddClient(name, {
    guild = guild or "Angry Murlocs",
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() return RESULT.Success end,
      },
    },
  })
end

local function WireDeliver(sim, client)
  client.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel)
    sim:Deliver(client, prefix, msg, channel)
    return RESULT.Success
  end
end

local function SeedCatalog(R, owner, profKey, ids, epoch, rev)
  local cache = R.GetCache and R.GetCache()
  -- Use OnRecipeUpdate direct to seed under owner.
  R:OnRecipeUpdate(owner, {
    profKey = profKey,
    rev = rev or 1,
    scanAt = 1,
    complete = true,
    epoch = epoch or 0,
    ids = ids or { 1, 2 },
  }, "direct")
end

-- Owner sanitize
do
  local sim = Sim.New(70)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  local o, w = R.ParseRelayOwner("")
  check("reject empty owner", o == nil and w == "owner")
  o, w = R.ParseRelayOwner("a|b")
  check("reject pipe in owner", o == nil)
  o, w = R.ParseRelayOwner(string.rep("x", 65))
  check("reject long owner", o == nil)
  o, w = R.ParseRelayOwner("Bob")
  check("accept short owner", o == "Bob-Realm", o)
end

-- Merge: same epoch+rev divergent IDs — relay keeps, direct corrects
do
  local sim = Sim.New(71)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  local owner = "Carol-Realm"
  R:OnRecipeUpdate(owner, {
    profKey = "alch", rev = 2, scanAt = 1, complete = true, epoch = 5, ids = { 10, 20 },
  }, "direct")
  R:OnRecipeUpdate(owner, {
    profKey = "alch", rev = 2, scanAt = 2, complete = true, epoch = 5, ids = { 99 },
  }, "relay")
  local rec = R.GetEntry(owner, "alch")
  check("relay does not overwrite divergent same-ver", rec and rec.ids[1] == 10 and #rec.ids == 2)

  R:OnRecipeUpdate(owner, {
    profKey = "alch", rev = 2, scanAt = 3, complete = true, epoch = 5, ids = { 30, 40 },
  }, "direct")
  rec = R.GetEntry(owner, "alch")
  check("direct corrects divergent same-ver", rec and rec.ids[1] == 30 and #rec.ids == 2)

  -- Reverse order: relay first, then direct
  local owner2 = "Dave-Realm"
  R:OnRecipeUpdate(owner2, {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 1 },
  }, "relay")
  R:OnRecipeUpdate(owner2, {
    profKey = "alch", rev = 1, scanAt = 2, complete = true, epoch = 1, ids = { 7, 8 },
  }, "direct")
  rec = R.GetEntry(owner2, "alch")
  check("direct after relay wins", rec and rec.ids[1] == 7 and #rec.ids == 2)
end

-- Epoch 0 relay then Alice live with higher epoch wins
do
  local sim = Sim.New(72)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  local owner = "AlicePeer-Realm"
  -- Simulate Bob relaying Alice's legacy row (epoch 0) via OnRecipeUpdate relay
  R:OnRecipeUpdate(owner, {
    profKey = "alch", rev = 3, scanAt = 1, complete = true, epoch = 0, ids = { 1, 2, 3 },
  }, "relay")
  R:OnRecipeUpdate(owner, {
    profKey = "alch", rev = 1, scanAt = 9, complete = true, epoch = 100, ids = { 50 },
  }, "direct")
  local rec = R.GetEntry(owner, "alch")
  check("live epoch beats relay epoch0", rec and tonumber(rec.epoch) == 100 and rec.ids[1] == 50)

  -- Encode path: missing epoch must become 0 on relay encode
  local enc = R.Encode("alch", 1, 1, true, { 1 }, nil)
  -- When Encode gets nil epoch it uses EnsureOwnerEpoch — RelayProfession passes or 0.
  local body = R.Encode("alch", 1, 1, true, { 1 }, tonumber(nil) or 0)
  local data = R.Decode(body)
  check("explicit epoch 0 in encode", data and tonumber(data.epoch) == 0, data and data.epoch)
end

-- Rotation: 25 catalogs, two waves
do
  local sim = Sim.New(73)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  wipe(R._relayCursor)
  for i = 1, 25 do
    local owner = string.format("Peer%02d-Realm", i)
    R:OnRecipeUpdate(owner, {
      profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { i },
    }, "direct")
  end
  local scope = alice.GR.Util.GuildScopeKey()
  local cands = R.ListRelayCandidates("alch")
  check("25 candidates", #cands == 25, #cands)
  local w1 = R.TakeRelayWindow(cands, scope, "alch")
  check("wave1 size 24", #w1 == 24, #w1)
  local seen = {}
  for i = 1, #w1 do seen[w1[i].owner] = true end
  local w2 = R.TakeRelayWindow(cands, scope, "alch")
  check("wave2 size 24", #w2 == 24, #w2)
  local foundSkipped = false
  for i = 1, #w2 do
    if not seen[w2[i].owner] then foundSkipped = true end
  end
  check("wave2 includes catalog skipped by wave1", foundSkipped)
end

-- PROFRO ingest attributes to owner; PeerAge only wire sender
do
  local sim = Sim.New(74)
  local bob = MakeClient(sim, "Bob")
  local req = MakeClient(sim, "Req")
  WireDeliver(sim, bob)
  WireDeliver(sim, req)
  local Rbob = bob.GR:GetModule("ProfRecipes")
  local Rreq = req.GR:GetModule("ProfRecipes")
  Rbob:OnEnable()
  Rreq:OnEnable()
  -- Seed Alice catalog on Bob
  Rbob:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 11, 12 },
  }, "direct")
  local ok = Rbob:RelayProfession("Alice-Realm", "alch", { scopeKey = bob.GR.Util.GuildScopeKey() })
  check("relay send ok", ok)
  sim:Run(2)
  local rec = Rreq.GetEntry("Alice-Realm", "alch")
  check("req has Alice via PROFRO", rec and rec.ids[1] == 11, rec and rec.ids[1])
  local ageAlice = req.GR.Comm:PeerAge("Alice-Realm")
  local ageBob = req.GR.Comm:PeerAge("Bob-Realm")
  check("Alice not PeerAge from PROFRO", ageAlice == nil, ageAlice)
  check("Bob PeerAge from wire", ageBob ~= nil, ageBob)
  check("Alice still relay-eligible", not Rreq.IsPeerOnlineForRelay("Alice-Realm"))
end

-- Guild A → nil drops queued scoped fragments
do
  local sim = Sim.New(75)
  local alice = MakeClient(sim, "Alice")
  alice.env.Enum = { SendAddonMessageResult = RESULT }
  -- Hold sends in throttle so items stay queued
  alice.env.C_ChatInfo.SendAddonMessage = function() return RESULT.AddonMessageThrottle end
  local scope = alice.GR.Util.GuildScopeKey()
  local big = "PROFRO|Carol-Realm|" .. string.rep("X", 400)
  alice.GR.Comm:Send(big, "data", "prof", { scopeKey = scope, operationId = "relayout" })
  check("frag queued", alice.GR.Comm:QueueSize() >= 1)
  alice.guild = nil -- GuildScopeKey → nil
  sim:Run(3)
  check("A to nil purged scoped queue", alice.GR.Comm:QueueSize() == 0, alice.GR.Comm:QueueSize())
end

-- Guild A → B mid-wave: no send into B for old scopeKey
do
  local sim = Sim.New(76)
  local alice = MakeClient(sim, "Alice")
  local sent = {}
  alice.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel)
    sent[#sent + 1] = msg
    return RESULT.Success
  end
  local scopeA = alice.GR.Util.GuildScopeKey()
  alice.GR.Comm:Send("PROFR|1|alch|1|1|1|1|1|1", "data", "prof", { scopeKey = scopeA })
  -- Change guild before drain (immediate send may already fire)
  -- Queue with throttle first
  alice.env.C_ChatInfo.SendAddonMessage = function() return RESULT.AddonMessageThrottle end
  alice.GR.Comm:Send("PROFRO|Zed-Realm|1|alch|1|1|1|1|1|9", "data", "prof", { scopeKey = scopeA })
  local qBefore = alice.GR.Comm:QueueSize()
  check("queued under A", qBefore >= 1, qBefore)
  alice.guild = "Other Guild"
  local scopeB = alice.GR.Util.GuildScopeKey()
  check("scope changed", scopeB ~= scopeA, scopeB)
  alice.env.C_ChatInfo.SendAddonMessage = function(prefix, msg)
    sent[#sent + 1] = msg
    return RESULT.Success
  end
  sim:Run(3)
  local leaked = false
  for i = 1, #sent do
    if sent[i]:find("Zed%-Realm") then leaked = true end
  end
  check("no old-scope PROFRO after A to B", not leaked and alice.GR.Comm:QueueSize() == 0)
end

-- PROFRQ filtered: only that profKey in outbound PROFRO
do
  local sim = Sim.New(77)
  local bob = MakeClient(sim, "Bob")
  WireDeliver(sim, bob)
  local R = bob.GR:GetModule("ProfRecipes")
  R:OnEnable()
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 1 },
  }, "direct")
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "tail", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 2 },
  }, "direct")
  local bodies = {}
  local realSend = bob.GR.Comm.Send
  bob.GR.Comm.Send = function(self, body, prio, cat, opts)
    bodies[#bodies + 1] = body
    return realSend(self, body, prio, cat, opts)
  end
  -- Force reply CD clear and deterministic delay
  bob.env.math = math
  local oldRandom = math.random
  math.random = function() return 0 end
  bob.GR:SendMessage("PROF_RECIPE_REQUEST", "Req-Realm", "alch")
  sim:Run(8)
  math.random = oldRandom
  local bad = false
  local saw = false
  for i = 1, #bodies do
    local b = bodies[i]
    if b:find("^PROFRO|") then
      saw = true
      if b:find("|tail|") or (b:find("tail") and not b:find("alch")) then
        bad = true
      end
      if not b:find("|alch|") then bad = true end
    end
  end
  check("filtered PROFRQ emitted PROFRO", saw)
  check("filtered PROFRO only alch", not bad)
end

-- shareProfessions false: may ask; no PROFR/PROFRO replies; mid-wave flip
do
  local sim = Sim.New(78)
  local bob = MakeClient(sim, "Bob")
  WireDeliver(sim, bob)
  local R = bob.GR:GetModule("ProfRecipes")
  R:OnEnable()
  -- Seed own complete catalog
  local me = bob.GR.Util.NormalizeName(bob.GR.Util.PlayerName())
  R:OnRecipeUpdate(me, {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 1 },
  }, "direct")
  -- Fix cache under player key used by GetEntry/ListComplete
  local scope = bob.GR.Util.GetScopeDB()
  scope.prof = scope.prof or {}
  scope.prof.cache = scope.prof.cache or {}
  scope.prof.cache[me] = {
    list = { { key = "alch", skill = 1, max = 1 } },
    recipes = {
      alch = { ids = { 1 }, rev = 1, scanAt = 1, complete = true, epoch = 1 },
    },
  }
  bob.GR.db.privacy.shareProfessions = false
  local bodies = {}
  local realSend = bob.GR.Comm.Send
  bob.GR.Comm.Send = function(self, body, prio, cat, opts)
    bodies[#bodies + 1] = { body = body, cat = cat }
    return realSend(self, body, prio, cat, opts)
  end
  local ok, why = R:RequestAll("alch", true)
  check("ask allowed when privacy off", ok and why == "sent", tostring(why))
  local asked = false
  for i = 1, #bodies do
    if bodies[i].body:find("^PROFRQ|") then asked = true end
  end
  check("PROFRQ sent under privacy off", asked)

  wipe(bodies)
  math.random = function() return 0 end
  bob.GR:SendMessage("PROF_RECIPE_REQUEST", "Req-Realm", "alch")
  sim:Run(8)
  local replied = false
  for i = 1, #bodies do
    if bodies[i].body:find("^PROFR|") or bodies[i].body:find("^PROFRO|") then
      replied = true
    end
  end
  check("no catalog reply when privacy off", not replied)

  -- Mid-wave: enable, schedule, then disable before stagger fires
  bob.GR.db.privacy.shareProfessions = true
  R:OnRecipeUpdate("Alice-Realm", {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 9 },
  }, "direct")
  wipe(bodies)
  -- Hold outbound so we can flip privacy while queued
  bob.env.C_ChatInfo.SendAddonMessage = function() return RESULT.AddonMessageThrottle end
  bob.GR:SendMessage("PROF_RECIPE_REQUEST", "Req-Realm", "")
  sim:Run(6) -- past 1s delay; Broadcast/Relay may enqueue
  bob.GR.db.privacy.shareProfessions = false
  bob.GR:SendMessage("SHARE_PROF_CHANGED")
  if bob.GR.Comm.PurgeDisallowed then bob.GR.Comm:PurgeDisallowed() end
  wipe(bodies)
  bob.env.C_ChatInfo.SendAddonMessage = function(prefix, msg)
    bodies[#bodies + 1] = { body = msg }
    return RESULT.Success
  end
  sim:Run(20)
  local midLeak = false
  for i = 1, #bodies do
    local b = bodies[i].body or ""
    if b:find("^PROFR|") or b:find("^PROFRO|") or b:find("^FRAG|") then
      midLeak = true
    end
  end
  check("privacy mid-wave blocks remaining catalog sends", not midLeak,
    midLeak and (bodies[1] and bodies[1].body:sub(1, 40)))
end

-- Refresh settle: open FRAG defers no_response past min collect
do
  local sim = Sim.New(79)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  R:OnEnable()
  -- Stub HasOpenFrag open then closed
  local open = true
  alice.GR.Comm.HasOpenFrag = function() return open end
  local statuses = {}
  local busSend = alice.GR.SendMessage
  function alice.GR:SendMessage(msg, a, b, c)
    if msg == "PROF_RECIPE_REFRESH_STATUS" then statuses[#statuses + 1] = a end
    return busSend(self, msg, a, b, c)
  end
  -- RequestAll needs Comm.Send success for PROFRQ
  R:RequestRecipeDataRefresh("alch", true)
  sim:Run(R.REFRESH_MIN_COLLECT + 0.6)
  local earlyNo = false
  for i = 1, #statuses do if statuses[i] == "no_response" then earlyNo = true end end
  check("frag open defers no_response at min", not earlyNo, table.concat(statuses, ","))
  -- Complete catalog after second 6
  open = false
  alice.GR:SendMessage("PROF_RECIPE_UPDATE", "Carol-Realm", {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 3 },
  }, "direct")
  sim:Run(R.REFRESH_QUIET + 1)
  local summary = R:GetRecipeRefreshSummary()
  check("late catalog counted after frag", summary and summary.why == "done" and (summary.catalogs or 0) >= 1)

  -- Gap > quiet with frag open between catalogs
  open = false
  wipe(statuses)
  R:ClearRecipeRefreshSummary()
  R:RequestRecipeDataRefresh("alch", true)
  sim:Run(0.2)
  alice.GR:SendMessage("PROF_RECIPE_UPDATE", "Carol-Realm", {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 3 },
  }, "direct")
  open = true -- second catalog still fragmenting
  sim:Run(R.REFRESH_MIN_COLLECT + R.REFRESH_QUIET + 1)
  local midDone = false
  for i = 1, #statuses do if statuses[i] == "done" then midDone = true end end
  check("quiet settle deferred while frag open", not midDone)
  open = false
  alice.GR:SendMessage("PROF_RECIPE_UPDATE", "Dave-Realm", {
    profKey = "alch", rev = 1, scanAt = 1, complete = true, epoch = 1, ids = { 4 },
  }, "direct")
  sim:Run(R.REFRESH_QUIET + 1)
  summary = R:GetRecipeRefreshSummary()
  check("both catalogs in summary", summary and summary.why == "done" and (summary.catalogs or 0) >= 2,
    summary and tostring(summary.catalogs))
end

-- Same guild name, different club ids: no catalog bus cross-talk.
do
  local sim = Sim.New(90)
  local seen = { Bob = 0, Carol = 0 }
  local alice = sim:AddClient("Alice", {
    guild = "Angry Murlocs", guildClubId = 301,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
  })
  local bob = sim:AddClient("Bob", {
    guild = "Angry Murlocs", guildClubId = 301,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
  })
  local carol = sim:AddClient("Carol", {
    guild = "Angry Murlocs", guildClubId = 302,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
  })
  local function wrap(c)
    local orig = c.GR.Comm.OnAddonMessage
    c.GR.Comm.OnAddonMessage = function(self, prefix, message, channel, sender)
      seen[c.name] = (seen[c.name] or 0) + 1
      return orig(self, prefix, message, channel, sender)
    end
  end
  wrap(bob)
  wrap(carol)
  local scope = alice.GR.Util.GuildScopeKey()
  check("club-bus: alice club scope", scope == "club:301", tostring(scope))
  alice.GR.Comm:Send("PROFR|1|alch|1|1|1|1|1|1", "data", "prof", { scopeKey = scope })
  sim:Run(5)
  check("club-bus: same club receives", seen.Bob >= 1, seen.Bob)
  check("club-bus: other club isolated", seen.Carol == 0, seen.Carol)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
