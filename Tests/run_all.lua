-- From repo root: luajit Tests/run_all.lua   (or lua5.1 Tests/run_all.lua)
local exe = arg and arg[-1] or "luajit"
local tests = {
  "Tests/WantedLogic_test.lua",
  "Tests/Protocol_test.lua",
  "Tests/Queue_test.lua",
  "Tests/Attribution_test.lua",
  "Tests/DeathRegression_test.lua",
  "Tests/VersionNag_test.lua",
  "Tests/Sync_sim_test.lua",
  "Tests/PrivacyScope_test.lua",
  "Tests/UISmoke_test.lua",
  "Tests/GuildOfficer_test.lua",
  "Tests/ProfFilter_test.lua",
  "Tests/ProfRecipes_test.lua",
  "Tests/Freshness_test.lua",
  "Tests/PinFade_test.lua",
  "Tests/PinCluster_test.lua",
  "Tests/ToastQueue_test.lua",
  "Tests/Sounds_test.lua",
  "Tests/ToastPreview_test.lua",
  "Tests/ToastControl_test.lua",
  "Tests/L10n_test.lua",
  "Tests/Version_test.lua",
  "Tests/SendThrottle_test.lua",
  "Tests/LevelCap_test.lua",
  "Tests/GuildChangePositions_test.lua",
  "Tests/SecretTarget_test.lua",
  "Tests/FragTimeout_test.lua",
}

local failed = {}
for _, t in ipairs(tests) do
  local p = assert(io.popen('"' .. exe .. '" ' .. t .. " 2>&1"))
  local out = p:read("*a")
  p:close()
  local summary = out:match("(%d+ failures)") or "?"
  local fail = out:find("FAIL") ~= nil or out:find("%f[%d]0 failures") == nil
  if fail then failed[#failed + 1] = t end
  print(string.format("%-34s %s %s", t, fail and "FAIL" or "ok  ", summary))
  if fail then print(out) end
end

print(string.format("\n%d/%d test files passed", #tests - #failed, #tests))
if #failed > 0 then os.exit(1) end
