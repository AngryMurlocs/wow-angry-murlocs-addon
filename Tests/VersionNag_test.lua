-- SemVer compare + guild VER peer nag.
-- From repo root: luajit Tests/VersionNag_test.lua
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

-- Load Util into a minimal env for pure compare tests.
do
  local env = setmetatable({}, { __index = _G })
  env.AngryMurlocs = false
  env.AngryMurlocsLocale = false
  local chunk = assert(loadfile("Core/Util.lua"))
  setfenv(chunk, env)
  chunk()
  local U = env.AngryMurlocs.Util

  check("0.9.0 < 0.10.0", U.CompareAddonVersion("0.9.0", "0.10.0") == -1)
  check("0.10.0 < 0.10.1", U.CompareAddonVersion("0.10.0", "0.10.1") == -1)
  check("0.10.1 == 0.10.1", U.CompareAddonVersion("0.10.1", "0.10.1") == 0)
  check("0.10.1 > 0.10.0", U.CompareAddonVersion("0.10.1", "0.10.0") == 1)
  check("pad minor", U.CompareAddonVersion("1", "1.0.0") == 0)
  check("strip beta", U.CompareAddonVersion("1.2.3-beta.1", "1.2.3") == 0)
  check("nil junk", U.CompareAddonVersion("sim", "0.1.0") == nil)
  check("parse 0.10.1", (function()
    local p = U.ParseAddonVersion("0.10.1")
    return p and p[1] == 0 and p[2] == 10 and p[3] == 1
  end)())
end

-- Peer with newer VER → exactly one chat nag; older/same → none.
do
  local sim = Sim.New(1)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  alice.GR.VERSION = "0.10.1"
  bob.GR.VERSION = "0.11.0"

  check("announce sends VER", bob.GR.Comm:AnnounceVersion() == true)
  sim:Run(1)
  check("bus has VER", sim:Count("VER") >= 1)
  local nag = 0
  for _, line in ipairs(alice.prints) do
    if tostring(line):find("0%.11%.0", 1, false) and tostring(line):find("0%.10%.1", 1, false) then
      nag = nag + 1
    end
  end
  check("alice nags once for newer peer", nag == 1, nag)

  -- Second newer peer must not print again this session.
  local carol = sim:AddClient("Carol")
  carol.GR.VERSION = "0.12.0"
  check("carol announce", carol.GR.Comm:AnnounceVersion() == true)
  sim:Run(1)
  local nag2 = 0
  for _, line in ipairs(alice.prints) do
    if tostring(line):find("Update via CurseForge", 1, true)
      or tostring(line):find("0.12.0", 1, true) then
      if tostring(line):find("available", 1, true) or tostring(line):find("CurseForge", 1, true) then
        nag2 = nag2 + 1
      end
    end
  end
  -- Still only the first UPDATE_AVAILABLE line (session flag).
  local updates = 0
  for _, line in ipairs(alice.prints) do
    if tostring(line):find("Update via CurseForge", 1, true) then updates = updates + 1 end
  end
  check("still one update nag this session", updates == 1, updates)
end

do
  local sim = Sim.New(2)
  local alice = sim:AddClient("Alice")
  local bob = sim:AddClient("Bob")
  alice.GR.VERSION = "0.10.1"
  bob.GR.VERSION = "0.10.1"
  bob.GR.Comm:AnnounceVersion()
  sim:Run(1)
  local updates = 0
  for _, line in ipairs(alice.prints) do
    if tostring(line):find("Update via CurseForge", 1, true) then updates = updates + 1 end
  end
  check("same version: no nag", updates == 0)

  local old = sim:AddClient("Oldie")
  old.GR.VERSION = "0.9.0"
  old.GR.Comm:AnnounceVersion()
  sim:Run(1)
  updates = 0
  for _, line in ipairs(alice.prints) do
    if tostring(line):find("Update via CurseForge", 1, true) then updates = updates + 1 end
  end
  check("older peer: no nag", updates == 0)
end

do
  local sim = Sim.New(3)
  local solo = sim:AddClient("Solo", { guild = false })
  solo.GR.VERSION = "0.10.1"
  check("no guild: announce false", solo.GR.Comm:AnnounceVersion() == false)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
