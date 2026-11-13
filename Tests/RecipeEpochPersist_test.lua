-- Elevated catalog (epoch,rev) persists across unlearn + /reload for old PROFR peers.
-- From repo root: luajit Tests/RecipeEpochPersist_test.lua
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

do
  local sim = Sim.New(30)
  local alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
  })
  local R = alice.GR:GetModule("ProfRecipes")
  local U = alice.GR.Util
  local me = U.NormalizeName(U.PlayerName())
  local scope = U.GetScopeDB()
  check("recipeSync bag", scope.prof.recipeSync and scope.prof.recipeSync.catalogVersions)

  -- Seed published catalog at rev=10 (as peers already hold).
  scope.prof.cache[me] = {
    list = { { key = "alch", name = "Alchemy", skill = 1 } },
    classFile = "MAGE",
    time = 1,
    recipes = {
      alch = {
        ids = { 100, 200 },
        rev = 10,
        scanAt = 10,
        recvAt = 10,
        complete = true,
        epoch = 1,
      },
    },
  }
  R.RememberCatalogEpoch(me, "alch", 1, 10)

  -- Unlearn alchemy: prune bumps epoch (never same-epoch rev=1).
  local pruned = R.PruneRecipesToProfessionList(
    scope.prof.cache[me].recipes,
    { { key = "tail", name = "Tailoring", skill = 1 } },
    me
  )
  scope.prof.cache[me].recipes = pruned
  local bag = scope.prof.recipeSync.catalogVersions[me]
  local ver = bag and bag.alch
  check("unlearn bumps epoch", ver and ver.epoch == 2 and ver.rev == 1,
    ver and (tostring(ver.epoch) .. "/" .. tostring(ver.rev)))

  -- Old PROFR peer with rev=10 accepts post-relearn stock under new epoch.
  local Logic = alice.GR.RecipeSyncLogic
  local cmp = Logic.CompareVersion({ epoch = 1, rev = 10 }, { epoch = ver.epoch, rev = ver.rev })
  check("old peer accepts relearn stock", cmp < 0)

  -- /reload: elevated version must still be the floor.
  local saved = Sim.DeepCopy(alice.GR.db)
  alice.online = false
  for i, x in ipairs(sim.clients) do
    if x == alice then table.remove(sim.clients, i) break end
  end
  alice = sim:AddClient("Alice", {
    db = saved,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
  })
  R = alice.GR:GetModule("ProfRecipes")
  U = alice.GR.Util
  me = U.NormalizeName(U.PlayerName())
  scope = U.GetScopeDB()
  bag = scope.prof.recipeSync.catalogVersions[me]
  ver = bag and bag.alch
  check("reload keeps elevated epoch/rev", ver and ver.epoch == 2 and ver.rev == 1,
    ver and (tostring(ver.epoch) .. "/" .. tostring(ver.rev)))

  -- Weaker remember must not invent lower than stored/published.
  R.RememberCatalogEpoch(me, "alch", 1, 1)
  ver = scope.prof.recipeSync.catalogVersions[me].alch
  check("never invent lower than stored", ver.epoch == 2 and ver.rev == 1,
    tostring(ver.epoch) .. "/" .. tostring(ver.rev))
end

-- Legacy catalogEpoch bag folds into recipeSync.catalogVersions via EnsureScopeTable.
do
  local sim = Sim.New(31)
  local db = Sim.DefaultDB()
  -- GuildScopeKey in sim = Realm::Angry Murlocs
  db.scopes = {
    ["Realm::Angry Murlocs"] = {
      wanted = {},
      wantedHidden = {},
      wantedSelf = {},
      prof = {
        cache = {},
        catalogEpoch = {
          Alice = { alch = { epoch = 3, rev = 4 } },
        },
      },
      sync = {},
    },
  }
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
  })
  local scope = alice.GR.Util.GetScopeDB()
  local v = scope.prof.recipeSync
    and scope.prof.recipeSync.catalogVersions
    and scope.prof.recipeSync.catalogVersions.Alice
    and scope.prof.recipeSync.catalogVersions.Alice.alch
  check("migrate catalogEpoch into recipeSync", v and v.epoch == 3 and v.rev == 4,
    v and (tostring(v.epoch) .. "/" .. tostring(v.rev)))
  check("legacy bag cleared", scope.prof.catalogEpoch == nil)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
