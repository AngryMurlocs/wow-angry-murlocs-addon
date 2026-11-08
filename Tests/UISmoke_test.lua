-- Runs the UI code paths (tabs, General status, manual sync) against frame stubs.
-- Catches Lua errors only; layout and visuals need the client (CLIENT_CHECKLIST.md).
-- From repo root: luajit Tests/UISmoke_test.lua
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

local sim = Sim.New(1)
local files = { "Modules/Wanted.lua", "Modules/Professions.lua", "Modules/UI.lua" }
local env = {
  GetNumSkillLines = function() return 0 end,
  UISpecialFrames = {},
  tinsert = table.insert,
  IsShiftKeyDown = function() return false end,
}
local alice = sim:AddClient("Alice", { extraFiles = files, env = env })
local bob = sim:AddClient("Bob", { extraFiles = files, env = env })
alice.Wanted:RecordOwnDeath("Enemy-Realm", "Z")
sim:Run(3)

local ui = bob.GR:GetModule("UI")
for _, tab in ipairs({ "general", "wanted", "prof", "general" }) do
  local ok, err = pcall(ui.ShowTab, ui, tab)
  check("tab " .. tab, ok, err)
end
local ok, err = pcall(ui.RefreshGeneral, ui)
check("general refresh", ok, err)
ok, err = pcall(ui.RunGuildDataSync, ui)
check("manual sync starts", ok, err)
check("sync busy after click", bob.Wanted:IsSyncBusy())
ok = pcall(ui.RunGuildDataSync, ui)
check("second click while busy is a no-op", ok and bob.Wanted:IsSyncBusy())
sim:Run(30)
check("manual sync completes", bob.Wanted:SyncStatusText():find("complete") ~= nil, bob.Wanted:SyncStatusText())
ok, err = pcall(ui.RefreshGeneral, ui)
check("general refresh after sync", ok, err)
ok, err = pcall(bob.Wanted.Hide, bob.Wanted, "Enemy-Realm")
check("hide", ok, err)
ok, err = pcall(bob.Wanted.UnhideAll, bob.Wanted)
check("unhide all", ok, err)
check("summary after unhide", bob.Wanted:Summary().total == 1)

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
