-- From repo root: luajit Tests/Sounds_test.lua
AngryMurlocs = AngryMurlocs or {}
AngryMurlocs.db = {}
dofile("Core/Sounds.lua")

local S = AngryMurlocs.Sounds
local fails = 0
local function check(name, cond, extra)
  if cond then print("OK  " .. name) else fails = fails + 1 print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or "")) end
end

S.Ensure()
local lvl = S.Get("lvl")
check("default lvl enabled false", lvl.enabled == false)
check("default lvl id set", lvl.id == "levelup")

-- Play with default off stays silent (no error without PlaySoundFile)
local played = S.Play("lvl")
check("play while disabled returns false", played == false)

-- Preview ignores enabled
_G.PlaySoundFile = function() return true end
check("preview plays while disabled", S.Preview("lvl") == true)

S.SetEnabled("lvl", true)
check("play when enabled", S.Play("lvl") == true)

check("invalid id silent", S.PlayId("nope") == false)

-- Missing API safe
_G.PlaySoundFile = nil
check("missing API no error", pcall(function() S.PlayId("levelup") end))

-- Ensure fills nil tables
AngryMurlocs.db.sounds = {}
S.Ensure()
check("ensure fills death", AngryMurlocs.db.sounds.death and AngryMurlocs.db.sounds.death.enabled == false)

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
