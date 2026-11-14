-- Positive regressions for 0.11.9 recipe reply/category sync fixes.
-- From repo root: luajit Tests/ProfReplySync_test.lua
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

local RESULT = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 }

local function MakeClient(sim, name, guild)
  return sim:AddClient(name, {
    guild = guild or "Angry Murlocs",
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel)
          -- Deliver from this client; resolved below after client exists.
        end,
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

local function CountTag(bus, tag, fromName)
  local n = 0
  for _, m in ipairs(bus) do
    if m.msg:match("^" .. tag .. "|") and (not fromName or m.from == fromName) then
      n = n + 1
    end
  end
  return n
end

local function EnqueueTimes(bus, tag, fromName)
  local times = {}
  for _, m in ipairs(bus) do
    if m.msg:match("^" .. tag .. "|") and (not fromName or m.from == fromName) then
      times[#times + 1] = m.t
    end
  end
  return times
end

-- 1) Category backfill after catalog ingest with complete mats, missing category
do
  local sim = Sim.New(40)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  R.StoreMeta(4242, {
    name = "Test Potion",
    reagents = { { itemID = 1, qty = 1, name = "Herb" } },
    reagentsResolved = true,
  })
  local bodies = {}
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    bodies[#bodies + 1] = { body = body, scope = opts and opts.scopeKey }
    return realSend(self, body, prio, cat, opts)
  end
  R:OnRecipeUpdate("Bob-Realm", {
    profKey = "alch",
    rev = 1,
    scanAt = 1,
    complete = true,
    epoch = 1,
    ids = { 4242 },
  })
  sim:Run(1)
  local nReq = 0
  for i = 1, #bodies do
    if tostring(bodies[i].body):find("^PROFRCQ|") then nReq = nReq + 1 end
  end
  check("1: PROFRCQ queued after catalog", nReq >= 1, nReq)
  -- Peer category reply ingest fills local meta
  R:OnCategoryUpdate("Carol-Realm", {
    { recipeId = 4242, categoryId = 55, categoryName = "Potions" },
  })
  local meta = R.GetMeta(4242)
  check("1: category stored after reply", meta and tonumber(meta.categoryId) == 55 and meta.categoryName == "Potions")
  alice.GR.Comm.Send = realSend
end

-- 2) One meta request → exactly one PROFRM and one PROFRC (no duplicate)
do
  local sim = Sim.New(41)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  R.StoreMeta(100, {
    name = "Elixir",
    icon = 1,
    outputItemID = 2,
    qtyMin = 1,
    qtyMax = 1,
    reagents = { { itemID = 9, qty = 1, name = "X" } },
    reagentsResolved = true,
    locale = "enUS",
    categoryId = 55,
    categoryName = "Potions",
  })
  local okM, okC = 0, 0
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    local ok = realSend(self, body, prio, cat, opts)
    if ok and tostring(body):find("^PROFRM|") then okM = okM + 1 end
    if ok and tostring(body):find("^PROFRC|") then okC = okC + 1 end
    return ok
  end
  R:OnMetaRequest("Bob-Realm", { 100 })
  sim:Run(2)
  check("2: exactly one PROFRM", okM == 1, okM)
  check("2: exactly one PROFRC", okC == 1, okC)
  alice.GR.Comm.Send = realSend
end

-- 3) Shared reply timer: batches spaced by reply CD
do
  local sim = Sim.New(42)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  local function storeKnown(id)
    R.StoreMeta(id, {
      name = "R" .. id,
      reagents = { { itemID = 1, qty = 1, name = "A" } },
      reagentsResolved = true,
      locale = "enUS",
      categoryId = 10,
      categoryName = "Cat",
    })
  end
  for id = 1, 72 do storeKnown(id) end
  local times = {}
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    local ok = realSend(self, body, prio, cat, opts)
    if ok and tostring(body):find("^PROFRM|") then
      times[#times + 1] = sim.clock
    end
    return ok
  end
  -- Queue 72 ids before the first drain fires so remaining work respects reply CD.
  R:OnMetaRequest("Bob-Realm", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 })
  R:OnMetaRequest("Bob-Realm", { 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48 })
  R:OnMetaRequest("Bob-Realm", { 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72 })
  sim:Run(40)
  check("3: three PROFRM batches", #times == 3, #times)
  if #times >= 3 then
    local gap1 = times[2] - times[1]
    local gap2 = times[3] - times[2]
    check("3: gap1 >= reply CD", gap1 >= (R.PROFRMQ_REPLY_CD - 0.2), gap1)
    check("3: gap2 >= reply CD", gap2 >= (R.PROFRMQ_REPLY_CD - 0.2), gap2)
  else
    check("3: gap1 >= reply CD", false)
    check("3: gap2 >= reply CD", false)
  end
  alice.GR.Comm.Send = realSend
end

-- 3b) Category-only reply batches spaced by reply CD (no PROFRM)
do
  local sim = Sim.New(48)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  local function storeKnown(id)
    R.StoreMeta(id, {
      name = "C" .. id,
      categoryId = 10,
      categoryName = "Cat",
    })
  end
  for id = 1, 72 do storeKnown(id) end
  local times = {}
  local sawM = false
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    local ok = realSend(self, body, prio, cat, opts)
    if ok and tostring(body):find("^PROFRC|") then
      times[#times + 1] = sim.clock
    end
    if ok and tostring(body):find("^PROFRM|") then
      sawM = true
    end
    return ok
  end
  R:OnCategoryRequest("Bob-Realm", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 })
  R:OnCategoryRequest("Carol-Realm", { 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48 })
  R:OnCategoryRequest("Dave-Realm", { 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72 })
  sim:Run(40)
  check("3b: three PROFRC batches", #times == 3, #times)
  if #times >= 3 then
    local gap1 = times[2] - times[1]
    local gap2 = times[3] - times[2]
    check("3b: gap1 >= reply CD", gap1 >= (R.PROFRMQ_REPLY_CD - 0.2), gap1)
    check("3b: gap2 >= reply CD", gap2 >= (R.PROFRMQ_REPLY_CD - 0.2), gap2)
  else
    check("3b: gap1 >= reply CD", false)
    check("3b: gap2 >= reply CD", false)
  end
  check("3b: no PROFRM", not sawM)
  alice.GR.Comm.Send = realSend
end

-- 4) Conflicting peer category keeps local value and still replies with local
do
  local sim = Sim.New(43)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  R.StoreMeta(2, {
    name = "Local",
    reagents = { { itemID = 1, qty = 1, name = "A" } },
    reagentsResolved = true,
    locale = "enUS",
    categoryId = 55,
    categoryName = "Potions",
  })
  -- Open need, then force cooldown path by stamping a prior reply via a quick drain
  R:OnCategoryRequest("Bob-Realm", { 2 })
  sim:Run(0.2)
  -- Clear bus tracking via send spy for the second wave
  local sent = {}
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    local ok = realSend(self, body, prio, cat, opts)
    if ok then sent[#sent + 1] = body end
    return ok
  end
  -- New request while / after cooldown; inject conflicting peer while need exists
  R.AbortAllBackgroundWork()
  -- Re-enable policy after abort
  R:OnCategoryRequest("Bob-Realm", { 2 })
  -- While waiting, conflicting observe
  R:OnCategoryUpdate("Peer-Realm", {
    { recipeId = 2, categoryId = 99, categoryName = "Other" },
  })
  local meta = R.GetMeta(2)
  check("4: local category 55 kept", meta and tonumber(meta.categoryId) == 55, meta and tostring(meta.categoryId))
  sim:Run(15)
  local sawLocal = false
  for i = 1, #sent do
    if tostring(sent[i]):find("^PROFRC|") and tostring(sent[i]):find("55") then
      sawLocal = true
    end
  end
  check("4: local category reply sent", sawLocal)
  alice.GR.Comm.Send = realSend
end

-- 5) Guild switch invalidates delayed request handler
do
  local sim = Sim.New(44)
  local alice = MakeClient(sim, "Alice", "Old Guild")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  R.StoreMeta(5, {
    name = "X",
    reagents = { { itemID = 1, qty = 1, name = "A" } },
    reagentsResolved = true,
    locale = "enUS",
    categoryId = 1,
    categoryName = "C",
  })
  local scopes = {}
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    local ok = realSend(self, body, prio, cat, opts)
    if ok and tostring(body):find("^PROFRC|") then
      scopes[#scopes + 1] = opts and opts.scopeKey
    end
    return ok
  end
  -- Fire message bus path with delay (not direct OnCategoryRequest)
  alice.GR:SendMessage("PROF_RECIPE_CATEGORY_REQUEST", "Bob-Realm", { 5 })
  sim:Run(0.1) -- before jitter fires
  alice.guild = "New Guild"
  alice.GR:SendMessage("GUILD_UPDATE")
  sim:Run(3)
  local bad = 0
  for i = 1, #scopes do
    if scopes[i] and tostring(scopes[i]):find("New Guild") then bad = bad + 1 end
  end
  check("5: no stale reply under new guild", bad == 0 and #scopes == 0, "scopes=" .. #scopes .. " bad=" .. bad)
  alice.GR.Comm.Send = realSend
end

-- 6) Request send_fail retries without burning attempt budget
do
  local sim = Sim.New(45)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  R.StoreMeta(4242, { name = "P", reagents = { { itemID = 1, qty = 1 } }, reagentsResolved = true })
  local attempts = 0
  local allow = false
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    if tostring(body):find("^PROFRCQ|") then
      attempts = attempts + 1
      if not allow then
        return false
      end
    end
    return realSend(self, body, prio, cat, opts)
  end
  R.EnsureCategoriesForIds({ 4242 })
  check("6: first send attempted", attempts == 1, attempts)
  local att = R._catAttempt[4242]
  check("6: fail does not burn attempt", att == nil or (att.n or 0) == 0, att and tostring(att.n))
  allow = true
  sim:Run(2)
  check("6: retry after queue frees", attempts >= 2, attempts)
  alice.GR.Comm.Send = realSend
end

-- A) Need epoch: old category observe does not kill later category Add
do
  local P = AngryMurlocs and AngryMurlocs.MetaReplyPolicy
  -- Load policy in isolation if needed
  if not P then
    AngryMurlocs = AngryMurlocs or {}
    dofile("Core/MetaReplyPolicy.lua")
    P = AngryMurlocs.MetaReplyPolicy
  end
  local s = P.New()
  P.Add(s, { 4 }, 0, { meta = true, category = true })
  P.Observe(s, 4, "category", "55|Potions", 1, "55|Potions")
  P.Add(s, { 4 }, 2, { category = true })
  local batch = P.Due(s, 2, { [4] = { category = "55|Potions" } })
  check("A: later category need due", #batch == 1 and batch[1].category == "55|Potions")
end

-- B) Reply send_fail retries; abort clears scheduled flag
do
  local sim = Sim.New(46)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  R.StoreMeta(8, {
    name = "Z",
    reagents = { { itemID = 1, qty = 1, name = "A" } },
    reagentsResolved = true,
    locale = "enUS",
    categoryId = 3,
    categoryName = "C",
  })
  local tries = 0
  local allow = false
  local realSend = alice.GR.Comm.Send
  alice.GR.Comm.Send = function(self, body, prio, cat, opts)
    if tostring(body):find("^PROFRC|") then
      tries = tries + 1
      if not allow then return false end
    end
    return realSend(self, body, prio, cat, opts)
  end
  R:OnCategoryRequest("Bob-Realm", { 8 })
  sim:Run(0.5)
  check("B: first reply attempt failed", tries >= 1, tries)
  allow = true
  sim:Run(R.PROFRMQ_REPLY_CD + 1)
  check("B: reply queued before deadline", tries >= 2, tries)
  local genBefore = R._replyPolicyGen()
  R.AbortAllBackgroundWork()
  check("B: abort clears drain flag", R._replyDrainScheduled() == false)
  check("B: abort bumps gen", R._replyPolicyGen() > genBefore)
  alice.GR.Comm.Send = realSend
end

-- Refresh path must not reset active catAttempt counters
do
  local sim = Sim.New(47)
  local alice = MakeClient(sim, "Alice")
  WireDeliver(sim, alice)
  local R = alice.GR:GetModule("ProfRecipes")
  local scope = alice.GR.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = { { key = "alch", skill = 1 } },
    recipes = { alch = { ids = { 4242 }, complete = true, rev = 1, scanAt = 1 } },
  }
  -- Block sends so onAck cannot rewrite attempt counters during ensure.
  alice.GR.Comm.Send = function() return false end
  R._catAttempt[4242] = { n = 2, firstSentAt = 1 }
  R._catGiveUp[4242] = true
  R.EnsureCategoriesForKnownRecipes("alch", { clearGiveUp = true })
  check("refresh keeps attempt n", R._catAttempt[4242] and R._catAttempt[4242].n == 2)
  check("refresh clears give-up", R._catGiveUp[4242] == nil)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
