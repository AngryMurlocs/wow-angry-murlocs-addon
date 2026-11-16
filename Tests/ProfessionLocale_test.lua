-- Profession locale keys: resolve, legacy slugs, migrate, wire alias, offline stubs.
-- From repo root: luajit Tests/ProfessionLocale_test.lua
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
        SendAddonMessage = function() return RESULT.Success end,
      },
      GetLocale = function() return "deDE" end,
    },
  })
end

-- Resolver: EN/DE/FR names + ID + legacy slugs
do
  local sim = Sim.New(80)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")

  check("schneiderei → tail", P.KeyFromSkillName("Schneiderei") == "tail")
  check("tailoring → tail", P.KeyFromSkillName("Tailoring") == "tail")
  check("couture → tail", P.KeyFromSkillName("Couture") == "tail")
  check("id 197 → tail", P.ResolveProfessionKey("???", 197) == "tail")
  check("unknown child + parent 197 → tail",
    P.ResolveProfessionKey("CoutureInconnue", { 197, 999001 }) == "tail")
  check("canonical couture", P.CanonicalProfKey("couture") == "tail")
  check("legacy ingnierie", P.CanonicalProfKey("ingnierie") == "eng")
  check("legacy dpeage", P.CanonicalProfKey("dpeage") == "skin")
  check("legacy pche", P.CanonicalProfKey("pche") == "fish")
  check("legacy archologie", P.CanonicalProfKey("archologie") == "arch")
  check("legacy calligraphie", P.CanonicalProfKey("calligraphie") == "insc")
  check("IconPath tail", P.IconPath("tail"):find("Tailoring") ~= nil)
  check("DisplayName deDE Schneiderei", P.DisplayName("tail") == "Schneiderei")

  -- Unknown accented name keeps old slug (no new fold on fallback).
  local slug = P.KeyFromSkillName("Café Mystère")
  check("unknown accented uses legacy slug",
    type(slug) == "string" and slug ~= "" and slug ~= "cafe mystere" and #slug <= 12,
    tostring(slug))

  -- Ingénierie with accent fold → eng via name table
  check("Ingenierie folded → eng", P.KeyFromSkillName("Ingénierie") == "eng")
end

-- Decode collapses dual keys; remembers wire alias from raw
do
  local sim = Sim.New(81)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local list = P.Decode("couture:50+tail:200")
  check("decode collapse one row", #list == 1 and list[1].key == "tail",
    list and list[1] and list[1].key)
  check("decode keeps higher skill", list[1].skill == 200, tostring(list[1] and list[1].skill))
end

-- Offline catalog-only stub survives ClearEmptyRemoteStubs after migrate
do
  local sim = Sim.New(82)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  local owner = "Fran-Realm"
  scope.prof.cache[owner] = {
    list = {},
    recipes = {
      couture = {
        ids = { 1, 2, 3 },
        rev = 1,
        scanAt = 1,
        recvAt = 1,
        complete = true,
        epoch = 1,
      },
    },
  }
  P.MigrateScopeProfessionKeys(scope)
  check("migrate couture→tail recipes",
    scope.prof.cache[owner].recipes.tail
      and not scope.prof.cache[owner].recipes.couture)
  check("migrate records wireAlias",
    scope.prof.cache[owner].wireAlias
      and scope.prof.cache[owner].wireAlias.tail == "couture")
  P:ClearEmptyRemoteStubs()
  check("offline catalog stub kept", scope.prof.cache[owner] ~= nil)
  local entry = R.GetEntry(owner, "tail")
  check("catalog findable under tail", entry and entry.complete and #entry.ids == 3)
end

-- Two guilds migrate with _movedToScope already set
do
  local sim = Sim.New(83)
  local alice = MakeClient(sim, "Alice", "GuildA")
  local P = alice.GR:GetModule("Professions")
  local U = alice.GR.Util
  alice.GR.db.prof._movedToScope = true
  local scopeA = U.GetScopeDB()
  local keyA = U.GuildScopeKey()
  check("guild A scope exists", scopeA ~= nil and keyA ~= nil, tostring(keyA))
  scopeA.prof.cache["Bob-Realm"] = {
    list = { { key = "couture", skill = 100, name = "Couture" } },
    recipes = {
      couture = { ids = { 10 }, rev = 1, scanAt = 1, recvAt = 1, complete = true, epoch = 0 },
    },
  }
  -- Second guild scope
  local keyB = "Realm::GuildB"
  alice.GR.db.scopes[keyB] = {
    wanted = {}, wantedHidden = {}, wantedSelf = {},
    prof = {
      cache = {
        ["Carol-Realm"] = {
          list = { { key = "ingnierie", skill = 50, name = "ingnierie" } },
          recipes = {
            ingnierie = { ids = { 20 }, rev = 2, scanAt = 1, recvAt = 1, complete = true, epoch = 1 },
          },
        },
      },
      recipeSync = { catalogVersions = {} },
    },
  }
  U.EnsureScopeTable(alice.GR.db.scopes[keyB])
  P:MigrateAllScopeKeys()
  check("guild A migrated", scopeA.prof.keysCanon == 1
    and scopeA.prof.cache["Bob-Realm"].list[1].key == "tail")
  check("guild B migrated", alice.GR.db.scopes[keyB].prof.keysCanon == 1
    and alice.GR.db.scopes[keyB].prof.cache["Carol-Realm"].recipes.eng)
  -- Second pass idempotent
  local nA = #scopeA.prof.cache["Bob-Realm"].recipes.tail.ids
  P:MigrateAllScopeKeys()
  check("second migrate same counts",
    #scopeA.prof.cache["Bob-Realm"].recipes.tail.ids == nA
      and scopeA.prof.cache["Bob-Realm"].list[1].key == "tail")
end

-- Wire alias request: PROFRQ|1|couture after reload-like seed
do
  local sim = Sim.New(84)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  local owner = "Fran-Realm"
  scope.prof.cache[owner] = {
    list = { { key = "tail", skill = 50, name = "Schneiderei" } },
    raw = "couture:50",
    wireAlias = { tail = "couture" },
    recipes = {},
  }
  scope.prof.keysCanon = 1
  local sent = {}
  alice.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel)
    sent[#sent + 1] = msg
    return RESULT.Success
  end
  R.enabled = true
  local ok, why = R:RequestProfession("tail", true, { playerName = owner })
  check("request sent", ok and why == "sent")
  local body = sent[1] or ""
  check("first PROFRQ uses couture", body:find("PROFRQ|1|couture", 1, true) ~= nil, body)
end

-- Screenshot-ish: three crafters, couture third adds 11th recipe → one tail row
do
  local sim = Sim.New(85)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  local P = alice.GR:GetModule("Professions")
  local U = alice.GR.Util
  P.MigrateScopeProfessionKeys(U.GetScopeDB())

  local function seed(owner, key, ids)
    R:OnRecipeUpdate(owner, {
      profKey = key, rev = 1, scanAt = 1, complete = true, epoch = 1, ids = ids,
    }, "direct")
    local cache = U.GetScopeDB().prof.cache
    cache[owner].list = { { key = P.CanonicalProfKey(key), skill = 50, name = key } }
  end

  seed("A-Realm", "tail", { 1, 2, 3, 4, 5 })
  seed("B-Realm", "tail", { 6, 7, 8, 9, 10 })
  seed("C-Realm", "couture", { 11 })

  local idx = R.BuildGuildRecipeIndex()
  local byProf = {}
  local nRecipes = 0
  local crafters = {}
  for i = 1, #idx do
    local row = idx[i]
    byProf[row.profKey] = (byProf[row.profKey] or 0) + 1
    nRecipes = nRecipes + 1
    for _, c in ipairs(row.crafters) do crafters[c] = true end
  end
  local nCrafters = 0
  for _ in pairs(crafters) do nCrafters = nCrafters + 1 end
  check("one profession key in index", byProf.tail == 11 and not byProf.couture,
    tostring(byProf.tail))
  check("eleven recipes", nRecipes == 11)
  check("three crafters", nCrafters == 3)

  -- Duplicate recipe from third → still 10 unique if only overlapping
  seed("D-Realm", "couture", { 1 })
  R.InvalidateGuildRecipeIndex()
  idx = R.BuildGuildRecipeIndex()
  local n2 = #idx
  local crafters2 = {}
  for i = 1, #idx do
    for _, c in ipairs(idx[i].crafters) do crafters2[c] = true end
  end
  local nC2 = 0
  for _ in pairs(crafters2) do nC2 = nC2 + 1 end
  check("duplicate keeps 11 recipes", n2 == 11, tostring(n2))
  check("four crafters after overlap", nC2 == 4, tostring(nC2))
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
