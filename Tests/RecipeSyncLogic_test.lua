-- From repo root: luajit Tests/RecipeSyncLogic_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/RecipeSyncLogic.lua")
local L = AngryMurlocs.RecipeSyncLogic

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
  local ids, why = L.CanonicalIds({ 3, 1, 2, 2, 1 })
  check("canonical sort uniq", ids and ids[1] == 1 and ids[2] == 2 and ids[3] == 3 and #ids == 3)
  check("reject too big id", select(2, L.CanonicalIds({ 2147483648 })) == "bad_id")
end

do
  check("newer epoch wins", L.CompareVersion({ epoch = 1, rev = 99 }, { epoch = 2, rev = 1 }) < 0)
  check("same epoch higher rev", L.CompareVersion({ epoch = 1, rev = 2 }, { epoch = 1, rev = 5 }) < 0)
  check("equal", L.CompareVersion({ epoch = 1, rev = 2 }, { epoch = 1, rev = 2 }) == 0)
end

do
  local e1, r1 = L.BumpCatalogEpoch(1, 10)
  check("bump epoch", e1 == 2 and r1 == 1)
  -- Old PROFR peer with rev=10 must lose to new epoch.
  check("old peer accepts relearn", L.CompareVersion({ epoch = 1, rev = 10 }, { epoch = e1, rev = r1 }) < 0)
  check("same epoch rev1 rejected", L.CompareVersion({ epoch = 1, rev = 10 }, { epoch = 1, rev = 1 }) > 0)
end

do
  local cur = { kind = "catalog", owner = "Alice", profKey = "alch", epoch = 1, rev = 10, ids = { 1, 2 } }
  local inc = { kind = "catalog", owner = "Alice", profKey = "alch", epoch = 2, rev = 1, ids = { 9 } }
  local act = L.Decide(cur, inc, { sourceKind = "relay" })
  check("decide accept newer epoch", act == "accept")
  act = L.Decide(cur, { kind = "catalog", owner = "Alice", profKey = "alch", epoch = 1, rev = 1, ids = { 9 } }, {})
  check("decide reject weaker rev", act == "reject")
  act = L.Decide(cur, cur, { ownerIsSelf = true, sourceKind = "relay" })
  check("reject self relay", act == "reject")
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end

