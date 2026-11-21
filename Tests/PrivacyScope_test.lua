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
  local files = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua", "Modules/Professions.lua" }
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

-- Stranger without a guild: no wire traffic, receive ignored.
do
  local sim = Sim.New(5)
  local solo = sim:AddClient("Solo", { guild = false })
  local Comm = solo.GR.Comm
  local before = #sim.bus
  check("noguild: Send refused", Comm:Send("LVL|10", "ctrl", "lvl") == false)
  check("noguild: POS refused", Comm:Send("POS|1415|0.5|0.5|Z|0|MAGE|10", "pos", "pos") == false)
  check("noguild: WK refused", Comm:Send(
    "WK|Enemy-Realm|Solo|1|1|" .. sim:Wall() .. "|Z", "kill", "death") == false)
  if solo.Wanted and solo.Wanted.RequestSync then
    check("noguild: sync refused", solo.Wanted:RequestSync("full") == false)
  end
  Comm:OnAddonMessage("GildenRadar", "LVL|5", "GUILD", "Spy-Realm")
  local peers = select(1, Comm:Peers(600))
  check("noguild: receive ignored", peers == 0, peers)
  sim:Run(5)
  check("noguild: bus stays empty", #sim.bus == before, #sim.bus)
end

-- Guild leave: purge outbound queue and stop further sends.
do
  local sim = Sim.New(6)
  local alice = sim:AddClient("Alice")
  sim:AddClient("Bob")
  local Comm = alice.GR.Comm
  for i = 1, 30 do
    Comm:Send("LVL|" .. i, "ctrl", "lvl")
  end
  check("leave: queue filled", Comm:QueueSize() > 0, Comm:QueueSize())
  alice.guild = nil
  Comm:OnGuildLeft()
  check("leave: queue purged", Comm:QueueSize() == 0, Comm:QueueSize())
  local afterLeave = #sim.bus
  check("leave: new Send refused", Comm:Send("LVL|99", "ctrl", "lvl") == false)
  sim:Run(20)
  check("leave: no further bus traffic", #sim.bus == afterLeave, #sim.bus)
  Comm:OnAddonMessage("GildenRadar", "LVL|1", "GUILD", "Bob-Realm")
  check("leave: receive ignored", select(1, Comm:Peers(600)) == 0)
end

-- Queued POS keeps coords after shareDeath off, but dead bit must clear at drain.
do
  local RESULT = {
    Success = 0,
    AddonMessageThrottle = 3,
  }
  local function LastPos(sim)
    for i = #sim.bus, 1, -1 do
      local m = sim.bus[i]
      if m.msg:match("^POS|") then return m.msg end
    end
  end
  local function DeadField(msg)
    if type(msg) ~= "string" then return nil end
    local parts = {}
    for p in (msg:sub(5) .. "|"):gmatch("([^|]*)|") do
      parts[#parts + 1] = p
    end
    return parts[5]
  end

  do
    local sim = Sim.New(7)
    local alice
    local block = true
    alice = sim:AddClient("Alice", {
      env = {
        Enum = { SendAddonMessageResult = RESULT },
        C_ChatInfo = {
          RegisterAddonMessagePrefix = function() return true end,
          SendAddonMessage = function(prefix, msg, channel)
            if block then return RESULT.AddonMessageThrottle end
            sim:Deliver(alice, prefix, msg, channel)
            return RESULT.Success
          end,
        },
      },
    })
    check("dead-strip: enqueue", alice.GR.Comm:Send(
      "POS|1415|0.5000|0.5000|Elwynn|1|MAGE|60", "pos", "pos") == true)
    check("dead-strip: queued while blocked", alice.GR.Comm:QueueSize() >= 1)
    alice.GR.db.privacy.shareDeath = false
    alice.GR:SendMessage("PRIVACY_CHANGED")
    block = false
    sim:Run(5)
    local msg = LastPos(sim)
    check("dead-strip: POS still sent", msg ~= nil, msg)
    check("dead-strip: dead bit cleared", DeadField(msg) == "0", msg)
  end

  do
    local sim = Sim.New(8)
    local alice
    local block = true
    alice = sim:AddClient("Alice", {
      env = {
        Enum = { SendAddonMessageResult = RESULT },
        C_ChatInfo = {
          RegisterAddonMessagePrefix = function() return true end,
          SendAddonMessage = function(prefix, msg, channel)
            if block then return RESULT.AddonMessageThrottle end
            sim:Deliver(alice, prefix, msg, channel)
            return RESULT.Success
          end,
        },
      },
    })
    alice.GR.Comm:Send("POS|1415|0.5000|0.5000|Elwynn|1|MAGE|60", "pos", "pos")
    check("dead-keep: shareDeath still on", alice.GR.db.privacy.shareDeath == true)
    block = false
    sim:Run(5)
    local msg = LastPos(sim)
    check("dead-keep: dead bit preserved", DeadField(msg) == "1", msg)
  end
end

-- Empty GetNormalizedRealmName must fall back to GetRealmName (no ::Guild scope).
do
  local GOOD = "GoodRealm::Angry Murlocs"
  local sim = Sim.New(9)
  local db = Sim.DefaultDB()
  db.scopes = {
    [GOOD] = {
      wanted = {
        ["Enemy-Realm"] = { count = 3, legacy = 3, origins = {}, schema = 2 },
      },
      wantedHidden = {},
      wantedSelf = {},
      prof = {
        cache = {
          ["Mate-Realm"] = {
            list = { { key = "alch", name = "Alchemy", skill = 100 } },
            recipes = { alch = { ids = { 1 }, complete = true, epoch = 1, rev = 1 } },
            time = 1,
          },
        },
      },
      sync = {},
    },
  }
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/Professions.lua" },
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "Good Realm" end,
      UnitFullName = function(u)
        if u == "player" then return "Alice", "GoodRealm" end
        return nil
      end,
    },
  })
  local U = alice.GR.Util
  check("empty-norm: RealmKey from GetRealmName", U.RealmKey() == "GoodRealm", tostring(U.RealmKey()))
  check("empty-norm: GuildScopeKey", U.GuildScopeKey() == GOOD, tostring(U.GuildScopeKey()))
  check("empty-norm: no ::Angry Murlocs key", alice.GR.db.scopes["::Angry Murlocs"] == nil)
  check("empty-norm: wanted count", Sim.Level(alice, "Enemy-Realm") == 3, Sim.Level(alice, "Enemy-Realm"))
  local prof = alice.GR:GetModule("Professions")
  check("empty-norm: professions visible", prof:GetAll()["Mate-Realm"] ~= nil)
end

-- Both realm APIs empty: no new scope; lists appear once realm arrives.
do
  local GOOD = "LateRealm::Angry Murlocs"
  local OTHER = "OtherRealm::Angry Murlocs"
  local sim = Sim.New(10)
  local db = Sim.DefaultDB()
  db.scopes = {
    [GOOD] = {
      wanted = {
        ["Foe-Realm"] = { count = 2, legacy = 2, origins = {}, schema = 2 },
      },
      wantedHidden = {},
      wantedSelf = {},
      prof = {
        cache = {
          ["Crafter-Realm"] = {
            list = { { key = "tail", name = "Tailoring", skill = 50 } },
            time = 1,
          },
        },
      },
      sync = {},
    },
    [OTHER] = {
      wanted = {
        ["OtherFoe-Realm"] = { count = 9, legacy = 9, origins = {}, schema = 2 },
      },
      wantedHidden = {},
      wantedSelf = {},
      prof = { cache = {} },
      sync = {},
    },
  }
  local norm, plain = "", ""
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/Professions.lua" },
    env = {
      GetNormalizedRealmName = function() return norm end,
      GetRealmName = function() return plain end,
      UnitFullName = function(u)
        if u == "player" then return "Alice", (plain ~= "" and plain:gsub("%s", "") or nil) end
        return nil
      end,
    },
  })
  local U = alice.GR.Util
  local beforeKeys = {}
  for k in pairs(alice.GR.db.scopes) do beforeKeys[k] = true end
  check("boot-empty: RealmKey nil", U.RealmKey() == nil)
  check("boot-empty: GuildScopeKey nil", U.GuildScopeKey() == nil)
  check("boot-empty: GetScopeDB nil", U.GetScopeDB() == nil)
  check("boot-empty: wanted empty view", Sim.Level(alice, "Foe-Realm") == 0)
  local nKeys = 0
  for k in pairs(alice.GR.db.scopes) do
    nKeys = nKeys + 1
    if not beforeKeys[k] then
      fails = fails + 1
      print("FAIL boot-empty: new scope " .. tostring(k))
    end
  end
  check("boot-empty: no new scope keys", nKeys == 2, nKeys)

  norm, plain = "LateRealm", "Late Realm"
  check("boot-ready: RealmKey", U.RealmKey() == "LateRealm")
  check("boot-ready: GuildScopeKey", U.GuildScopeKey() == GOOD)
  check("boot-ready: wanted restored", Sim.Level(alice, "Foe-Realm") == 2, Sim.Level(alice, "Foe-Realm"))
  local prof = alice.GR:GetModule("Professions")
  check("boot-ready: professions restored", prof:GetAll()["Crafter-Realm"] ~= nil)
  check("boot-ready: other realm untouched", Sim.Level(alice, "OtherFoe-Realm") == 0)
  check("boot-ready: still no :: key", alice.GR.db.scopes["::Angry Murlocs"] == nil)
  check("boot-ready: other guild scope kept", alice.GR.db.scopes[OTHER] ~= nil
    and alice.GR.db.scopes[OTHER].wanted["OtherFoe-Realm"] ~= nil)
end

-- Club id path: permanent empty realm + immediate club id.
do
  local CLUB = "club:71037"
  local OLD = "CAMWOWEU4Realm6PvP::Angry Murlocs"
  local EMPTY = "::Angry Murlocs"
  local sim = Sim.New(11)
  local db = Sim.DefaultDB()
  db.scopes = {
    [OLD] = {
      wanted = {
        ["FoeA-Realm"] = { schema = 2, legacy = 5, origins = { alice = { n = 2, seq = 2, t = 1 } } },
      },
      wantedHidden = {
        ["FoeA-Realm"] = { level = 5, t = 10 },
      },
      wantedSelf = {
        ["alice"] = { seq = 3, kills = { ["foea"] = { n = 2, t = 1 } } },
      },
      prof = {
        cache = {
          ["Crafter-Realm"] = {
            list = { { key = "alch", name = "Alchemy", skill = 100 } },
            recipes = { alch = { ids = { 9, 8 }, complete = true, epoch = 4, rev = 2 } },
            time = 50,
          },
        },
        recipeSync = {
          catalogVersions = {
            ["Crafter-Realm"] = { alch = { epoch = 4, rev = 2 } },
          },
          profiles = {},
          ownProfileRev = {},
          progress = {},
          inventoryRev = 0,
        },
      },
      sync = {},
    },
    [EMPTY] = {
      wanted = {
        ["FoeA-Realm"] = { schema = 2, legacy = 5, origins = { bob = { n = 3, seq = 1, t = 2 } } },
        ["FoeB-Realm"] = { schema = 2, legacy = 1, origins = {}, },
      },
      wantedHidden = {
        ["FoeA-Realm"] = { level = 5, t = 20 },
      },
      wantedSelf = {},
      prof = { cache = {} },
      sync = {},
    },
  }
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/Professions.lua" },
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
      GetRealmID = function() return 0 end,
      UnitFullName = function(u)
        if u == "player" then return "Alice", "Endstation" end
        return nil
      end,
      C_Club = {
        GetGuildClubId = function() return 71037 end,
      },
    },
  })
  local U = alice.GR.Util
  check("club-imm: RealmKey nil", U.RealmKey() == nil)
  check("club-imm: GuildScopeKey club", U.GuildScopeKey() == CLUB, tostring(U.GuildScopeKey()))
  check("club-imm: GetScopeDB", U.GetScopeDB() ~= nil)
  check("club-imm: unconfirmed wanted empty", Sim.Level(alice, "FoeA-Realm") == 0)
  local cands = U.ListImportCandidates()
  check("club-imm: two candidates", #cands == 2, #cands)
  local ok = U.ImportScopes(cands, CLUB)
  check("club-imm: import ok", ok == true)
  -- max origin n for Alice/Bob: legacy 5 + max(2,3)=3 → level 8? Level = legacy + sum origins
  -- MergeEntryInto max per origin: alice n=2, bob n=3, legacy max 5 → Level = 5+2+3 = 10
  check("club-imm: merged wanted level", Sim.Level(alice, "FoeA-Realm") == 10, Sim.Level(alice, "FoeA-Realm"))
  check("club-imm: second killer kept", Sim.Level(alice, "FoeB-Realm") == 1)
  local scope = U.GetScopeDB()
  local hide = scope.wantedHidden["FoeA-Realm"]
  check("club-imm: hide level/t", hide and hide.level == 5 and hide.t == 20, hide and (hide.level .. "/" .. hide.t))
  check("club-imm: originals kept", db.scopes[OLD].wanted["FoeA-Realm"] ~= nil
    and db.scopes[EMPTY].wanted["FoeB-Realm"] ~= nil)
  check("club-imm: recipes kept", scope.prof.cache["Crafter-Realm"].recipes.alch.epoch == 4)
  check("club-imm: catalogVersions", scope.prof.recipeSync.catalogVersions["Crafter-Realm"].alch.rev == 2)
  -- One-shot: clear dest hide, re-import must not restore it.
  scope.wantedHidden["FoeA-Realm"] = nil
  local ok2, err2 = U.ImportScope(OLD, CLUB)
  check("club-imm: second import skipped", ok2 == false and err2 == "already", tostring(err2))
  check("club-imm: hide stays cleared", scope.wantedHidden["FoeA-Realm"] == nil)
  -- Next own kill increments.
  local r = alice.Wanted:RecordOwnDeath("FoeA-Realm", "Hillsbrad")
  check("club-imm: own kill ok", r and r.ok, r and tostring(r.ok))
  check("club-imm: level after kill", Sim.Level(alice, "FoeA-Realm") == 11, Sim.Level(alice, "FoeA-Realm"))
  -- Hide still applies at level 5 stamp; entry visible once level > hide.level.
  check("club-imm: not hidden after level-up",
    not alice.GR.WantedLogic.IsHidden({ hidden = { ["FoeA-Realm"] = { level = 5, t = 20 } }, wanted = scope.wanted },
      "FoeA-Realm", scope.wanted["FoeA-Realm"]))
  check("club-imm: display name", scope.guildDisplayName == "Angry Murlocs")
  -- Rename: same club key.
  alice.guild = "Angry Murlocs Renamed"
  U.RefreshGuildDisplayName(scope)
  check("club-rename: same key", U.GuildScopeKey() == CLUB)
  check("club-rename: display updated", scope.guildDisplayName == "Angry Murlocs Renamed")
  check("club-rename: wanted still there", Sim.Level(alice, "FoeA-Realm") == 11)
end

-- Realm present, club id later: no Realm::Guild writes/sync key before club.
do
  local CLUB = "club:99"
  local REALM_GUILD = "GoodRealm::Angry Murlocs"
  local sim = Sim.New(12)
  local db = Sim.DefaultDB()
  local clubId = nil
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/Professions.lua" },
    env = {
      GetNormalizedRealmName = function() return "GoodRealm" end,
      GetRealmName = function() return "Good Realm" end,
      C_Club = {
        GetGuildClubId = function() return clubId end,
      },
    },
  })
  local U = alice.GR.Util
  check("late-club: hold GuildScopeKey nil", U.GuildScopeKey() == nil)
  check("late-club: GetScopeDB nil", U.GetScopeDB() == nil)
  check("late-club: no Realm::Guild bucket", db.scopes[REALM_GUILD] == nil)
  -- Simulate a write attempt while holding.
  local scopeNil = U.GetScopeDB()
  if scopeNil then
    scopeNil.wanted = scopeNil.wanted or {}
    scopeNil.wanted["ShouldNot"] = { schema = 2, legacy = 1, origins = {} }
  end
  check("late-club: still no Realm::Guild", db.scopes[REALM_GUILD] == nil)

  clubId = 99
  check("late-club: key is club", U.GuildScopeKey() == CLUB, tostring(U.GuildScopeKey()))
  local scope = U.GetScopeDB()
  check("late-club: club scope open", scope ~= nil)
  check("late-club: still no Realm::Guild", db.scopes[REALM_GUILD] == nil)
  check("late-club: display name", scope.guildDisplayName == "Angry Murlocs")
end

-- Unconfirmed same-name orphan stays out; other club never offered.
do
  local sim = Sim.New(13)
  local db = Sim.DefaultDB()
  db.scopes = {
    ["OtherRealm::Angry Murlocs"] = {
      wanted = { ["X-Realm"] = { schema = 2, legacy = 7, origins = {} } },
      wantedHidden = {},
      wantedSelf = {},
      prof = { cache = {} },
      sync = {},
    },
    ["club:1"] = {
      wanted = { ["Y-Realm"] = { schema = 2, legacy = 3, origins = {} } },
      wantedHidden = {},
      wantedSelf = {},
      prof = { cache = {} },
      sync = {},
      guildDisplayName = "Angry Murlocs",
    },
  }
  db.scopeImported = { ["Already::Angry Murlocs"] = "club:1" }
  local alice = sim:AddClient("Alice", {
    db = db,
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
      C_Club = { GetGuildClubId = function() return 2 end },
    },
  })
  local U = alice.GR.Util
  check("sep: live key club:2", U.GuildScopeKey() == "club:2")
  check("sep: unconfirmed not merged", Sim.Level(alice, "X-Realm") == 0)
  check("sep: other club data not visible", Sim.Level(alice, "Y-Realm") == 0)
  local cands = U.ListImportCandidates()
  local hasOtherClub, hasImported = false, false
  for i = 1, #cands do
    if cands[i] == "club:1" then hasOtherClub = true end
    if cands[i] == "Already::Angry Murlocs" then hasImported = true end
  end
  check("sep: candidates exclude other club", not hasOtherClub)
  check("sep: candidates exclude imported", not hasImported)
  check("sep: realm orphan listed", #cands == 1 and cands[1] == "OtherRealm::Angry Murlocs", table.concat(cands, ","))
  local okClub = U.ImportScope("club:1", "club:2")
  check("sep: refuse other club import", okClub == false)
  -- Accept after guild switch aborts.
  local pendingDest = "club:2"
  alice.env.C_Club.GetGuildClubId = function() return 3 end
  local okSwitch, errSwitch = U.ImportScope("OtherRealm::Angry Murlocs", pendingDest)
  check("sep: dest_changed abort", okSwitch == false and errSwitch == "dest_changed", tostring(errSwitch))
  check("sep: orphan untouched", db.scopes["OtherRealm::Angry Murlocs"].wanted["X-Realm"] ~= nil)
end

-- Hide merge: higher level wins; equal level → newer t. Bare true ignored.
do
  local sim = Sim.New(14)
  local db = Sim.DefaultDB()
  db.scopes = {
    ["R::Angry Murlocs"] = {
      wanted = {
        ["H1-Realm"] = { schema = 2, legacy = 3, origins = {} },
        ["H2-Realm"] = { schema = 2, legacy = 4, origins = {} },
      },
      wantedHidden = {
        ["H1-Realm"] = { level = 2, t = 5 },
        ["H2-Realm"] = { level = 4, t = 1 },
        ["Bad-Realm"] = true,
      },
      wantedSelf = {},
      prof = { cache = {} },
      sync = {},
    },
  }
  local alice = sim:AddClient("Alice", {
    db = db,
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
      C_Club = { GetGuildClubId = function() return 5 end },
    },
  })
  local U = alice.GR.Util
  local dest = U.GetScopeDB()
  dest.wantedHidden["H1-Realm"] = { level = 3, t = 1 }
  dest.wantedHidden["H2-Realm"] = { level = 4, t = 9 }
  U.ImportScope("R::Angry Murlocs", "club:5")
  dest = U.GetScopeDB()
  check("hide: higher level wins", dest.wantedHidden["H1-Realm"].level == 3)
  check("hide: tie uses newer t", dest.wantedHidden["H2-Realm"].t == 9)
  check("hide: bare true ignored", dest.wantedHidden["Bad-Realm"] == nil)
  local e = dest.wanted["H1-Realm"]
  -- Stamp hide at level 3; Level(e)=3 → hidden; bump legacy to reveal.
  dest.wantedHidden["H1-Realm"] = { level = 3, t = 1 }
  check("hide: at stamp level hidden", alice.GR.WantedLogic.IsHidden(
    { hidden = dest.wantedHidden, wanted = dest.wanted }, "H1-Realm", e) == true)
  e.legacy = 4
  check("hide: level-up reveals", alice.GR.WantedLogic.IsHidden(
    { hidden = dest.wantedHidden, wanted = dest.wanted }, "H1-Realm", e) == false)
end

-- Legacy client without C_Club still uses realm::guild immediately.
do
  local sim = Sim.New(15)
  local alice = sim:AddClient("Alice", {
    env = {
      GetNormalizedRealmName = function() return "LegacyRealm" end,
      GetRealmName = function() return "Legacy Realm" end,
      -- no C_Club
    },
  })
  local U = alice.GR.Util
  check("legacy: no club api", U.ClubApiPresent() == false)
  check("legacy: realm guild key", U.GuildScopeKey() == "LegacyRealm::Angry Murlocs", tostring(U.GuildScopeKey()))
  check("legacy: GetScopeDB", U.GetScopeDB() ~= nil)
end

-- Leave with stale GetGuildClubId: no active key; GetScopeDB nil.
do
  local sim = Sim.New(16)
  local clubId = 42
  local alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/Professions.lua" },
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
      C_Club = { GetGuildClubId = function() return clubId end },
    },
  })
  local U = alice.GR.Util
  check("stale-leave: in guild key", U.GuildScopeKey() == "club:42")
  local scope = U.GetScopeDB()
  scope.wanted["Keep-Realm"] = { schema = 2, legacy = 2, origins = {} }
  check("stale-leave: wanted while guilded", Sim.Level(alice, "Keep-Realm") == 2)
  alice.guild = nil
  clubId = 42 -- API still returns id after leave
  check("stale-leave: GuildScopeKey nil", U.GuildScopeKey() == nil)
  check("stale-leave: GetScopeDB nil", U.GetScopeDB() == nil)
  check("stale-leave: view empty", Sim.Level(alice, "Keep-Realm") == 0)
  check("stale-leave: SV bucket kept", alice.GR.db.scopes["club:42"].wanted["Keep-Realm"] ~= nil)
end

-- Atomic import: failed merge publishes nothing; live dest unchanged.
do
  local sim = Sim.New(17)
  local db = Sim.DefaultDB()
  db.scopes = {
    ["Old::Angry Murlocs"] = {
      wanted = { ["Z-Realm"] = { schema = 2, legacy = 1, origins = {} } },
      wantedHidden = {},
      wantedSelf = {},
      prof = { cache = {} },
      sync = {},
    },
  }
  local alice = sim:AddClient("Alice", {
    db = db,
    env = {
      GetNormalizedRealmName = function() return "" end,
      GetRealmName = function() return "" end,
      C_Club = { GetGuildClubId = function() return 8 end },
    },
  })
  local U = alice.GR.Util
  local live = U.GetScopeDB()
  live.wanted["Pre-Realm"] = { schema = 2, legacy = 9, origins = {} }
  local logic = alice.GR.WantedLogic
  local saved = logic.MergeEntryInto
  logic.MergeEntryInto = function() error("boom") end
  local ok, err = U.ImportScope("Old::Angry Murlocs", "club:8")
  logic.MergeEntryInto = saved
  check("atomic: merge_failed", ok == false and err == "merge_failed", tostring(err))
  check("atomic: not marked imported", db.scopeImported == nil or db.scopeImported["Old::Angry Murlocs"] == nil)
  live = U.GetScopeDB()
  check("atomic: pre entry kept", live.wanted["Pre-Realm"] ~= nil and Sim.Level(alice, "Pre-Realm") == 9)
  check("atomic: orphan not published", live.wanted["Z-Realm"] == nil)
  check("atomic: source untouched", db.scopes["Old::Angry Murlocs"].wanted["Z-Realm"] ~= nil)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
