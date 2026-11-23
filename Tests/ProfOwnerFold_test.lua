-- Profession cache owner fold: alias keys (Name vs Name-Realm) collapse to one row.
-- From repo root: luajit Tests/ProfOwnerFold_test.lua
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
    },
  })
end

local function CountOwners(cache)
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  return n
end

local function SkillOf(entry, key)
  if type(entry) ~= "table" or type(entry.list) ~= "table" then return nil end
  for i = 1, #entry.list do
    local row = entry.list[i]
    if type(row) == "table" and row.key == key then
      return tonumber(row.skill)
    end
  end
  return nil
end

-- CharIdentity folds live-realm suffix; keeps distinct surnames / boundaries apart.
do
  local sim = Sim.New(90)
  local alice = MakeClient(sim, "Alice")
  local U = alice.GR.Util
  check("identity Alice", U.CharIdentity("Alice") == "alice")
  check("identity Alice-Realm", U.CharIdentity("Alice-Realm") == "alice")
  check("identity Baba Bing-Realm", U.CharIdentity("Baba Bing-Realm") == "baba|bing")
  check("identity Baba Bing", U.CharIdentity("Baba Bing") == "baba|bing")
  check("identity Baba Other distinct",
    U.CharIdentity("Baba Bing") ~= U.CharIdentity("Baba Other"))
  check("boundary Lina-Roth != Linar-Oth",
    U.CharIdentity("Lina-Roth") ~= U.CharIdentity("Linar-Oth"),
    tostring(U.CharIdentity("Lina-Roth")) .. "/" .. tostring(U.CharIdentity("Linar-Oth")))
  check("boundary Ingoo-Endstation == Ingoo Endstation-Realm",
    U.CharIdentity("Ingoo-Endstation") == U.CharIdentity("Ingoo Endstation-Realm"),
    tostring(U.CharIdentity("Ingoo-Endstation")) .. "/" .. tostring(U.CharIdentity("Ingoo Endstation-Realm")))
end

-- Prune: Alice + Alice-Realm + empty classFile stub → one owner, best skills.
do
  local sim = Sim.New(91)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Alice"] = {
    list = { { key = "eng", skill = 210 }, { key = "mine", skill = 247 } },
    time = 10,
    classFile = "MAGE",
  }
  scope.prof.cache["Alice-Realm"] = {
    list = { { key = "eng", skill = 216 }, { key = "mine", skill = 265 } },
    time = 20,
  }
  -- Empty alias with classFile (would survive ClearEmptyRemoteStubs alone).
  scope.prof.cache["alice-Realm"] = {
    list = {},
    time = 5,
    classFile = "MAGE",
  }
  P:PruneCharacterDuplicates()
  local cache = scope.prof.cache
  check("prune one owner", CountOwners(cache) == 1, tostring(CountOwners(cache)))
  local kept
  for _, e in pairs(cache) do kept = e break end
  check("prune keeps newer skills", SkillOf(kept, "eng") == 216 and SkillOf(kept, "mine") == 265,
    tostring(SkillOf(kept, "eng")) .. "/" .. tostring(SkillOf(kept, "mine")))
  check("prune keeps classFile", kept and kept.classFile == "MAGE")
end

-- Distinct characters with same first token stay separate.
do
  local sim = Sim.New(92)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Baba Bing-Realm"] = {
    list = { { key = "eng", skill = 100 } },
    time = 1,
  }
  scope.prof.cache["Baba Other-Realm"] = {
    list = { { key = "alch", skill = 50 } },
    time = 1,
  }
  P:PruneCharacterDuplicates()
  check("no false merge Baba*", CountOwners(scope.prof.cache) == 2,
    tostring(CountOwners(scope.prof.cache)))
end

-- PROF_UPDATE writes into existing alias owner.
do
  local sim = Sim.New(93)
  local alice = MakeClient(sim, "Alice")
  local bob = MakeClient(sim, "Bob")
  local P = alice.GR:GetModule("Professions")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Bob-Realm"] = {
    list = { { key = "tail", skill = 10 } },
    time = 1,
  }
  -- Wire sender form without forcing a second key when alias exists.
  alice.GR:SendMessage("PROF_UPDATE", "Bob", "tail:234+cook:1")
  check("update folded to one key", CountOwners(scope.prof.cache) == 1,
    tostring(CountOwners(scope.prof.cache)))
  local owner = P:ResolveCacheOwner("Bob-Realm") or P:ResolveCacheOwner("Bob")
  local entry = owner and scope.prof.cache[owner]
  check("update skill applied", entry and SkillOf(entry, "tail") == 234,
    tostring(entry and SkillOf(entry, "tail")))
end

-- Recipe stub uses ResolveCacheOwner (no second empty key).
do
  local sim = Sim.New(94)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Carol-Realm"] = {
    list = { { key = "tail", skill = 100 } },
    time = 1,
  }
  R:OnRecipeUpdate("Carol", {
    profKey = "tail",
    ids = { 1, 2, 3 },
    rev = 1,
    scanAt = 1,
    complete = true,
    epoch = 1,
  }, "direct")
  check("recipe stub no alias key", CountOwners(scope.prof.cache) == 1,
    tostring(CountOwners(scope.prof.cache)))
  local owner = P:ResolveCacheOwner("Carol") or P:ResolveCacheOwner("Carol-Realm")
  local entry = owner and scope.prof.cache[owner]
  check("recipes on existing owner",
    entry and entry.recipes and entry.recipes.tail and #entry.recipes.tail.ids == 3)
end

-- ImportScope merges alias owners from source into live dest by identity.
do
  local sim = Sim.New(95)
  local alice = MakeClient(sim, "Alice")
  local U = alice.GR.Util
  local P = alice.GR:GetModule("Professions")
  local db = alice.GR.db
  db.prof._movedToScope = true
  local dest = U.GuildScopeKey()
  local src = "OldRealm::Angry Murlocs"
  check("import dest scope", type(dest) == "string" and dest ~= "")
  db.scopes = db.scopes or {}
  db.scopes[dest] = U.EnsureScopeTable(db.scopes[dest] or {})
  db.scopes[src] = U.EnsureScopeTable({})
  db.scopes[dest].prof.cache["Dana-Realm"] = {
    list = { { key = "eng", skill = 50 } },
    time = 5,
  }
  db.scopes[src].prof.cache["Dana"] = {
    list = { { key = "eng", skill = 80 } },
    time = 10,
  }
  local ok, err = U.ImportScope(src, dest)
  check("import ok", ok == true, tostring(err))
  local cache = db.scopes[dest].prof.cache
  -- MergeProfCacheBag folds by identity; prune cleans any leftover exact aliases.
  P:PruneCharacterDuplicates()
  check("import+prune one Dana", CountOwners(cache) == 1, tostring(CountOwners(cache)))
  local kept
  for _, e in pairs(cache) do kept = e break end
  check("import kept higher skill", SkillOf(kept, "eng") == 80, tostring(SkillOf(kept, "eng")))
end

-- P1: self Baba-Bing must not absorb foreign Baba-Other via IsSelfName.
do
  local sim = Sim.New(96)
  local self = MakeClient(sim, "Baba-Bing")
  local P = self.GR:GetModule("Professions")
  local U = self.GR.Util
  local scope = U.GetScopeDB()
  self.GR.db.prof._movedToScope = true
  local me = U.NormalizeName(U.PlayerName())
  scope.prof.cache[me] = {
    list = { { key = "eng", skill = 200 } },
    time = 10,
  }
  scope.prof.cache["Baba-Other-Realm"] = {
    list = { { key = "eng", skill = 55 } },
    time = 20,
  }
  check("self vs other identity distinct",
    U.CharIdentity(me) ~= U.CharIdentity("Baba-Other-Realm"),
    tostring(U.CharIdentity(me)) .. "/" .. tostring(U.CharIdentity("Baba-Other-Realm")))
  P:PruneCharacterDuplicates()
  check("self/other both keys kept", CountOwners(scope.prof.cache) == 2,
    tostring(CountOwners(scope.prof.cache)))
  check("self keeps skill 200", SkillOf(scope.prof.cache[me], "eng") == 200,
    tostring(SkillOf(scope.prof.cache[me], "eng")))
  check("other keeps skill 55", SkillOf(scope.prof.cache["Baba-Other-Realm"], "eng") == 55,
    tostring(SkillOf(scope.prof.cache["Baba-Other-Realm"], "eng")))
end

-- P1: newer empty import stub must not wipe filled dest list.
do
  local sim = Sim.New(97)
  local alice = MakeClient(sim, "Alice")
  local U = alice.GR.Util
  local P = alice.GR:GetModule("Professions")
  local db = alice.GR.db
  db.prof._movedToScope = true
  local dest = U.GuildScopeKey()
  local src = "EmptyStub::Angry Murlocs"
  db.scopes[dest] = U.EnsureScopeTable(db.scopes[dest] or {})
  db.scopes[src] = U.EnsureScopeTable({})
  db.scopes[dest].prof.cache["Dana-Realm"] = {
    list = { { key = "tail", skill = 200 } },
    time = 5,
  }
  db.scopes[src].prof.cache["Dana"] = {
    list = {},
    time = 99,
  }
  local ok, err = U.ImportScope(src, dest)
  check("empty-stub import ok", ok == true, tostring(err))
  P:PruneCharacterDuplicates()
  local cache = db.scopes[dest].prof.cache
  local kept
  for _, e in pairs(cache) do kept = e break end
  check("empty stub did not wipe skills", SkillOf(kept, "tail") == 200,
    tostring(SkillOf(kept, "tail")))
end

-- P1: empty realm APIs — Baba Bing / Baba Bing-Realm fold; Baba Other stays apart.
do
  local sim = Sim.New(98)
  local alice = sim:AddClient("Alice", {
    guild = "Angry Murlocs",
    guildClubId = "215871062",
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() return RESULT.Success end,
      },
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
    },
  })
  local P = alice.GR:GetModule("Professions")
  local U = alice.GR.Util
  check("empty-realm identity Baba Bing", U.CharIdentity("Baba Bing") == "baba|bing")
  check("empty-realm identity Baba Bing-Realm", U.CharIdentity("Baba Bing-Realm") == "baba|bing")
  check("empty-realm Ingoo-Endstation kept",
    U.CharIdentity("Ingoo-Endstation") == "ingoo|endstation")
  check("empty-realm Ingoo wire equals Forever",
    U.CharIdentity("Ingoo-Endstation") == U.CharIdentity("Ingoo Endstation-Realm"))
  check("empty-realm Lina != Linar",
    U.CharIdentity("Lina-Roth") ~= U.CharIdentity("Linar-Oth"))
  check("empty-realm Baba Other distinct",
    U.CharIdentity("Baba Bing") ~= U.CharIdentity("Baba Other"))
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Baba Bing"] = {
    list = { { key = "eng", skill = 100 } },
    time = 1,
  }
  scope.prof.cache["Baba Other"] = {
    list = { { key = "alch", skill = 40 } },
    time = 1,
  }
  alice.GR:SendMessage("PROF_UPDATE", "Baba Bing-Realm", "eng:150+cook:1")
  check("empty-realm one Baba Bing", CountOwners(scope.prof.cache) == 2,
    tostring(CountOwners(scope.prof.cache)))
  local bing = P:ResolveCacheOwner("Baba Bing") or P:ResolveCacheOwner("Baba Bing-Realm")
  check("empty-realm skill folded", bing and SkillOf(scope.prof.cache[bing], "eng") == 150,
    tostring(bing and SkillOf(scope.prof.cache[bing], "eng")))
end

-- P2: GetStatus sees recipes written under resolved alias owner.
do
  local sim = Sim.New(99)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Bob"] = {
    list = { { key = "tail", skill = 100 } },
    time = 1,
  }
  R:OnRecipeUpdate("Bob-Realm", {
    profKey = "tail",
    ids = { 10, 11 },
    rev = 1,
    scanAt = 1,
    complete = true,
    epoch = 1,
  }, "direct")
  check("status Bob complete", R.GetStatus("Bob", "tail") == "complete",
    tostring(R.GetStatus("Bob", "tail")))
  check("status Bob-Realm complete", R.GetStatus("Bob-Realm", "tail") == "complete",
    tostring(R.GetStatus("Bob-Realm", "tail")))
end

-- P2: catalog floor on alias blocks older epoch after resolve.
do
  local sim = Sim.New(100)
  local alice = MakeClient(sim, "Alice")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  U.EnsureScopeTable(scope)
  scope.prof.cache["Baba-Bing"] = {
    list = { { key = "tail", skill = 50 } },
    time = 1,
  }
  scope.prof.recipeSync.catalogVersions["Baba Bing-Realm"] = {
    tail = { epoch = 5, rev = 1 },
  }
  R:OnRecipeUpdate("Baba-Bing", {
    profKey = "tail",
    ids = { 1 },
    rev = 1,
    scanAt = 1,
    complete = true,
    epoch = 2,
  }, "relay")
  local rec = R.GetEntry("Baba-Bing", "tail")
  check("floor rejects older epoch", rec == nil, rec and tostring(rec.epoch))
end

-- P2: merge drops recipes for professions no longer on confirmed list.
do
  local sim = Sim.New(101)
  local alice = MakeClient(sim, "Alice")
  local P = alice.GR:GetModule("Professions")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local scope = U.GetScopeDB()
  alice.GR.db.prof._movedToScope = true
  scope.prof.cache["Eve"] = {
    list = { { key = "eng", skill = 100 } },
    time = 20,
  }
  scope.prof.cache["Eve-Realm"] = {
    list = { { key = "eng", skill = 90 }, { key = "tail", skill = 80 } },
    time = 10,
    recipes = {
      eng = { ids = { 1 }, rev = 1, complete = true, epoch = 1, scanAt = 1, recvAt = 1 },
      tail = { ids = { 2, 3, 4 }, rev = 1, complete = true, epoch = 1, scanAt = 1, recvAt = 1 },
    },
  }
  P:PruneCharacterDuplicates()
  check("recipe-prune one owner", CountOwners(scope.prof.cache) == 1,
    tostring(CountOwners(scope.prof.cache)))
  local owner = P:ResolveCacheOwner("Eve") or P:ResolveCacheOwner("Eve-Realm")
  local entry = owner and scope.prof.cache[owner]
  check("recipe-prune kept eng", entry and entry.recipes and entry.recipes.eng ~= nil)
  check("recipe-prune dropped tail", entry and (not entry.recipes or entry.recipes.tail == nil))
  -- Stale tail:1 update must not resurrect the catalog without a scan.
  alice.GR:SendMessage("PROF_UPDATE", "Eve-Realm", "eng:100+cook:1")
  R:OnRecipeUpdate("Eve", {
    profKey = "tail",
    ids = { 2, 3, 4 },
    rev = 1,
    scanAt = 1,
    complete = true,
    epoch = 1,
  }, "relay")
  entry = owner and scope.prof.cache[P:ResolveCacheOwner("Eve") or owner]
  check("tail not resurrected", entry and (not entry.recipes or entry.recipes.tail == nil))
end

local OLD_SCOPE = "CAMWOWEU4Realm6PvP::Angry Murlocs"
local CLUB = "215871062"
local LEGACY_REALM = "CAMWOWEU4Realm6PvP"

local function EmptyRealmClubOpts(extra)
  local env = {
    Enum = { SendAddonMessageResult = RESULT },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function() return RESULT.Success end,
    },
    GetNormalizedRealmName = function() return "" end,
    GetRealmName = function() return "" end,
  }
  if extra then for k, v in pairs(extra) do env[k] = v end end
  return {
    guild = "Angry Murlocs",
    guildClubId = CLUB,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = env,
  }
end

-- Verified legacy Tara catalog reachable as Tara; Mond/Stein stay apart.
do
  local sim = Sim.New(110)
  local alice = sim:AddClient("Alice", EmptyRealmClubOpts())
  local P = alice.GR:GetModule("Professions")
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  check("tara: RealmKey nil", U.RealmKey() == nil)
  check("tara: club scope", U.GuildScopeKey() == "club:" .. CLUB, tostring(U.GuildScopeKey()))
  check("tara: legacy strip on", U.VerifiedLegacyRealmSuffix() == LEGACY_REALM,
    tostring(U.VerifiedLegacyRealmSuffix()))
  local legacyOwner = "Tara-" .. LEGACY_REALM
  check("tara: identity folds", U.CharIdentity(legacyOwner) == U.CharIdentity("Tara"),
    tostring(U.CharIdentity(legacyOwner)))
  local db = alice.GR.db
  db.scopes[OLD_SCOPE] = {
    wanted = {}, wantedHidden = {}, wantedSelf = {},
    prof = {
      cache = {
        [legacyOwner] = {
          list = { { key = "alch", skill = 300 } },
          time = 50,
          recipes = {
            alch = {
              ids = { 101, 102, 103 },
              rev = 2,
              complete = true,
              epoch = 3,
              scanAt = 50,
              recvAt = 50,
            },
          },
        },
      },
    },
  }
  local ok, err = U.ImportScope(OLD_SCOPE, "club:" .. CLUB)
  check("tara: import ok", ok == true, tostring(err))
  P:PruneCharacterDuplicates()
  local scope = U.GetScopeDB()
  local owner = P:ResolveCacheOwner("Tara") or P:ResolveCacheOwner(legacyOwner)
  check("tara: resolved owner", owner ~= nil, tostring(owner))
  local entry = R.GetEntry("Tara", "alch")
  check("tara: GetEntry finds catalog", entry and entry.complete and entry.ids and #entry.ids == 3,
    entry and tostring(#(entry.ids or {})))
  alice.GR:SendMessage("PROF_UPDATE", "Tara", "alch:310+cook:1")
  P:PruneCharacterDuplicates()
  owner = P:ResolveCacheOwner("Tara")
  check("tara: update same owner", owner and SkillOf(scope.prof.cache[owner], "alch") == 310,
    tostring(owner and SkillOf(scope.prof.cache[owner], "alch")))
  -- Control: Tara-Mond / Tara-Stein distinct.
  scope.prof.cache["Tara-Mond"] = { list = { { key = "alch", skill = 10 } }, time = 1 }
  scope.prof.cache["Tara-Stein"] = { list = { { key = "alch", skill = 20 } }, time = 1 }
  P:PruneCharacterDuplicates()
  check("tara: Mond != Stein identity",
    U.CharIdentity("Tara-Mond") ~= U.CharIdentity("Tara-Stein"))
  check("tara: Mond owner distinct",
    P:ResolveCacheOwner("Tara-Mond") ~= P:ResolveCacheOwner("Tara-Stein"))
  -- Reload keeps empty realm + modules.
  alice = sim:Reload(alice)
  check("tara: reload RealmKey nil", alice.GR.Util.RealmKey() == nil)
  check("tara: reload club", alice.GR.Util.GuildScopeKey() == "club:" .. CLUB)
  R = alice.GR:GetModule("ProfRecipes")
  entry = R.GetEntry("Tara", "alch")
  check("tara: after reload catalog", entry and entry.ids and #entry.ids == 3)
end

-- Negatives: scopeImported alone must not enable legacy strip.
do
  local sim = Sim.New(111)
  local alice = sim:AddClient("Alice", EmptyRealmClubOpts({
    -- other club
  }))
  alice.guildClubId = "999"
  alice.env.C_Club.GetGuildClubId = function() return "999" end
  local U = alice.GR.Util
  alice.GR.db.scopeImported = { [OLD_SCOPE] = "club:" .. CLUB }
  check("neg-switch: no legacy suffix", U.VerifiedLegacyRealmSuffix() == nil,
    tostring(U.VerifiedLegacyRealmSuffix()))
  check("neg-switch: Tara legacy stays distinct",
    U.CharIdentity("Tara-" .. LEGACY_REALM) ~= U.CharIdentity("Tara"))
end

do
  local sim = Sim.New(112)
  local alice = sim:AddClient("Alice", {
    guild = "Angry Murlocs",
    guildClubId = CLUB,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() return RESULT.Success end,
      },
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
    },
  })
  -- Club id pending.
  alice.env.C_Club.GetGuildClubId = function() return nil end
  alice.guildClubId = nil
  local U = alice.GR.Util
  alice.GR.db.scopeImported = { [OLD_SCOPE] = "club:" .. CLUB }
  check("neg-pending: GuildScopeKey nil", U.GuildScopeKey() == nil)
  check("neg-pending: no legacy suffix", U.VerifiedLegacyRealmSuffix() == nil)
  check("neg-pending: Tara legacy distinct",
    U.CharIdentity("Tara-" .. LEGACY_REALM) ~= U.CharIdentity("Tara"))
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
