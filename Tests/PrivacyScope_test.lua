-- Privacy purge, guild/realm scope separation, schema-2 migration, profession scope.
-- Real Comm/Util/Wanted/Professions code in the simulator.
-- From repo root: luajit Tests/PrivacyScope_test.lua
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

-- Acceptance 9: turning a share off drops queued messages of that kind.
do
  local sim = Sim.New(1)
  local alice = sim:AddClient("Alice")
  sim:AddClient("Bob")
  local Comm = alice.GR.Comm
  for i = 1, 10 do Comm:Send("LVL|" .. i, "ctrl", "lvl") end
  for i = 1, 5 do Comm:Send("WK|Enemy" .. i .. "-Realm|Alice|1|" .. i .. "|" .. sim:Wall() .. "|Z", "kill", "death") end
  Comm:Send("POS|1415|0.5|0.5|Elwynn|0|MAGE|10", "pos", "pos")
  alice.GR.db.privacy.shareDeath = false
  alice.GR:SendMessage("PRIVACY_CHANGED")
  alice.GR.db.privacy.sharePosition = false
  alice.GR:SendMessage("SHARE_POS_CHANGED")
  sim:Run(30)
  local wk, pos = 0, 0
  for _, m in ipairs(sim.bus) do
    if m.msg:match("^WK|") then wk = wk + 1 end
    if m.msg:match("^POS|") then pos = pos + 1 end
  end
  -- the first queued message may already have left before the toggle
  check("purge: at most 1 WK left before toggle", wk <= 1, wk)
  check("purge: no POS after toggle", pos == 0, pos)
  check("purge: other categories still sent", sim:Count("LVL") >= 9, sim:Count("LVL"))
  check("purge: new death sends refused", Comm:Send("WK|X-Realm|Alice|1|9|1|Z", "kill", "death") == false)
end

-- Acceptance 11: scope recovery only within the same realm + guild.
do
  local sim = Sim.New(2)
  local db = Sim.DefaultDB()
  local function Entry(level)
    return { count = level, lastTime = 1600000000 }
  end
  db.scopes = {
    ["Realm::Angry Murlocs"] = { wanted = { ["A-Realm"] = Entry(1) } },
    ["Realm::angry murlocs"] = { wanted = { ["B-Realm"] = Entry(2) } },
    ["Realm::AngryMurlocs"] = { wanted = { ["C-Realm"] = Entry(3) } },
    ["Realm::__none__"] = { wanted = { ["D-Realm"] = Entry(4) } },
    ["Realm::Other Guild"] = { wanted = { ["E-Realm"] = Entry(5) } },
    ["OtherRealm::Angry Murlocs"] = { wanted = { ["F-Realm"] = Entry(6) } },
    ["OtherRealm::__none__"] = { wanted = { ["G-Realm"] = Entry(7) } },
  }
  db.schema = 1
  local alice = sim:AddClient("Alice", { db = db })
  local cur = alice.GR.db.scopes["Realm::Angry Murlocs"].wanted
  check("scope: own entry kept", cur["A-Realm"] ~= nil)
  check("scope: case variant merged", cur["B-Realm"] ~= nil)
  check("scope: space variant merged", cur["C-Realm"] ~= nil)
  check("scope: same-realm __none__ merged", cur["D-Realm"] ~= nil)
  check("scope: other guild NOT merged", cur["E-Realm"] == nil)
  check("scope: other realm NOT merged", cur["F-Realm"] == nil and cur["G-Realm"] == nil)
  check("scope: other guild untouched", alice.GR.db.scopes["Realm::Other Guild"].wanted["E-Realm"] ~= nil)
  check("scope: other realm untouched", alice.GR.db.scopes["OtherRealm::Angry Murlocs"].wanted["F-Realm"] ~= nil)
  check("migrate: legacy level kept", Sim.Level(alice, "B-Realm") == 2, Sim.Level(alice, "B-Realm"))
  check("migrate: schema 2 entry", cur["A-Realm"].schema == 2 and cur["A-Realm"].legacy == 1
    and cur["A-Realm"].events == nil and cur["A-Realm"].lastTime == nil)
  check("migrate: privacy untouched", alice.GR.db.privacy.shareDeath == true and alice.GR.db.privacy.sharePosition == true)
end

-- Migration is repeatable: a second load with the same SavedVariables changes nothing.
do
  local sim = Sim.New(3)
  local db = Sim.DefaultDB()
  db.scopes = { ["Realm::Angry Murlocs"] = { wanted = {
    ["Enemy-Realm"] = { count = 4, lastTime = 1600000000, events = { x = 1 }, victims = { "V" } },
  } } }
  local alice = sim:AddClient("Alice", { db = db })
  check("migrate: level 4 after first load", Sim.Level(alice, "Enemy-Realm") == 4)
  alice = sim:Reload(alice)
  check("migrate: level 4 after reload", Sim.Level(alice, "Enemy-Realm") == 4)
  local r = alice.Wanted:RecordOwnDeath("Enemy-Realm", "Z")
  check("migrate: new kill adds on top of legacy", r.ok and Sim.Level(alice, "Enemy-Realm") == 5)
end

-- Profession cache moves once into the active guild scope; other guild stays empty.
do
  local sim = Sim.New(4)
  local db = Sim.DefaultDB()
  db.prof = { cache = { ["Smith-Realm"] = { list = { { key = "BS", rank = 300 } }, time = 1 } } }
  local files = { "Modules/Wanted.lua", "Modules/Professions.lua" }
  local alice = sim:AddClient("Alice", { db = db, extraFiles = files, env = {
    GetNumSkillLines = function() return 0 end,
  } })
  sim:Run(3)
  local prof = alice.GR:GetModule("Professions")
  check("prof: cache moved to guild scope", prof:GetAll()["Smith-Realm"] ~= nil)
  check("prof: global cache marked moved", alice.GR.db.prof._movedToScope == true)
  alice.guild = "Other Guild"
  check("prof: other guild sees no foreign cache", prof:GetAll()["Smith-Realm"] == nil)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
