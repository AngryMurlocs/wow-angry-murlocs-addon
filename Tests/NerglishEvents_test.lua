-- Guild roster join detection for NerglishEvents.
-- From repo root: luajit Tests/NerglishEvents_test.lua
local Sim = dofile("Tests/sim.lua")

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" — " .. tostring(extra)) or ""))
  end
end

do
  local roster = { "Anna-Realm", "Berta-Realm" }
  local reacts = {}
  local sim = Sim.New(1)
  local db = Sim.DefaultDB()
  db.ui = { nerglishStyle = "nerglish" }
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/NerglishEvents.lua" },
    env = {
      GetNumGuildMembers = function() return #roster end,
      GetGuildRosterInfo = function(i) return roster[i] end,
      C_GuildInfo = { GuildRoster = function() end },
    },
  })
  local N = alice.GR.Nerglish
  N.TryReact = function(kind, _, facts)
    reacts[#reacts + 1] = { kind = kind, player = facts and facts.player }
    return "x"
  end
  local mod = alice.GR:GetModule("NerglishEvents")
  check("module enabled", mod and mod.enabled)

  reacts = {}
  mod:_OnGuildRosterForTest() -- first pass: snapshot
  check("snapshot no react", #reacts == 0, #reacts)

  roster = { "Anna-Realm", "Berta-Realm", "Clara-Realm" }
  mod:_OnGuildRosterForTest()
  check("one join react", #reacts == 1 and reacts[1].player == "Clara", reacts[1] and reacts[1].player)

  reacts = {}
  mod:_OnGuildRosterForTest()
  check("stable roster no join", #reacts == 0, #reacts)

  -- False cleanup would drop Anna/Berta and re-fire them as joins on next pass.
  roster = { "Anna-Realm", "Berta-Realm", "Clara-Realm" }
  reacts = {}
  mod:_OnGuildRosterForTest()
  check("no false joins for known members", #reacts == 0, #reacts)
end

print(tostring(fails) .. " failures")
os.exit(fails == 0 and 0 or 1)
