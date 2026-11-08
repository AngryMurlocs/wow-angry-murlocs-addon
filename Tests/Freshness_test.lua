-- From repo root: luajit Tests/Freshness_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Modules/WantedLogic.lua")

local L = AngryMurlocs.WantedLogic
local fails = 0
local function check(name, cond)
  if cond then print("OK  " .. name) else fails = fails + 1 print("FAIL " .. name) end
end

local now = 100000
local function E(seen) return { lastSeenTime = seen } end

check("none when no sighting", L.SightTier(E(0), now) == "none")
check("none when nil entry", L.SightTier(nil, now) == "none")
check("fresh at 0s", L.SightTier(E(now), now) == "fresh")
check("fresh at 59s", L.SightTier(E(now - 59), now) == "fresh")
check("warm at 60s", L.SightTier(E(now - 60), now) == "warm")
check("warm at 299s", L.SightTier(E(now - 299), now) == "warm")
check("stale at 300s", L.SightTier(E(now - 300), now) == "stale")
check("stale at 1h", L.SightTier(E(now - 3600), now) == "stale")
check("future treated as fresh", L.SightTier(E(now + 30), now) == "fresh")
check("constants", L.SIGHT_FRESH_SEC == 60 and L.SIGHT_WARM_SEC == 300)

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
