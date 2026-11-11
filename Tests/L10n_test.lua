-- Every U.L("KEY") used in addon code must exist in enUS and deDE, and both
-- translations must use the same format specifiers in the same order.
-- Run from repo root: luajit Tests/L10n_test.lua

local function ReadFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function LoadLocale(path, locale, base)
  _G.GetLocale = function() return locale end
  _G.AngryMurlocsLocale = base
  local chunk = assert(loadfile(path))
  chunk()
  return _G.AngryMurlocsLocale
end

local en = LoadLocale("Localization/enUS.lua", "enUS", nil)
local de = LoadLocale("Localization/deDE.lua", "deDE", {})

local failures = 0
local function Fail(msg)
  failures = failures + 1
  print("FAIL " .. msg)
end

local files = {}
for line in ReadFile("AngryMurlocs.toc"):gmatch("[^\r\n]+") do
  if not line:match("^##") and line:match("%.lua$") and not line:match("^Localization") then
    files[#files + 1] = (line:gsub("\\", "/"))
  end
end

local used = {}
for _, path in ipairs(files) do
  local src = ReadFile(path)
  for key in src:gmatch('U%.L%(%s*"([%w_]+)"') do
    used[key] = used[key] or path
  end
  for key in src:gmatch('[^%w_%.]L%(%s*"([%w_]+)"') do
    used[key] = used[key] or path
  end
end

-- Keys built at runtime ("PREFIX_" .. suffix)
for key in pairs(used) do
  if key:sub(-1) == "_" then used[key] = nil end
end
for _, s in ipairs({ "IDLE", "PENDING", "WAITING", "NOREPLY", "NOGUILD", "FAILED" }) do
  used["SYNC_STATE_" .. s] = "Modules/WantedSync.lua (dynamic)"
end
-- Death spellKind → locale keys (U.L(key) dynamic; not grepped as literals)
for _, key in ipairs({
  "DEATH_MELEE", "DEATH_RANGED", "DEATH_UNKNOWN_ATTACK",
  "DEATH_ENV_FALL", "DEATH_ENV_DROWN", "DEATH_ENV_FATIGUE",
  "DEATH_ENV_LAVA", "DEATH_ENV_SLIME", "DEATH_ENV_FIRE", "DEATH_ENV_OTHER",
  "DEATH_CAUSE_ENV",
}) do
  used[key] = "Modules/Death.lua (spellKind)"
end
_G.AngryMurlocs = nil
local logic = dofile("Core/WantedLogic.lua")
logic = logic or (_G.AngryMurlocs and _G.AngryMurlocs.WantedLogic)
for level = 0, 1000, 1 do
  local rank = logic.RankFromLevel(level)
  used["WANTED_RANK_" .. rank.key] = "Core/WantedLogic.lua (dynamic)"
end

local count = 0
for key, path in pairs(used) do
  count = count + 1
  if en[key] == nil then Fail("enUS missing " .. key .. " (" .. path .. ")") end
  if de[key] == nil then Fail("deDE missing " .. key .. " (" .. path .. ")") end
end

local function Specs(s)
  local out = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%[%-%d%.]*[sdif]") do
    out[#out + 1] = spec:sub(-1)
  end
  return table.concat(out)
end

for key, v in pairs(de) do
  if type(v) == "string" and type(en[key]) == "string" then
    if Specs(v) ~= Specs(en[key]) then
      Fail("format mismatch " .. key .. ": en=" .. Specs(en[key]) .. " de=" .. Specs(v))
    end
  end
end

print(string.format("L10n: %d keys used, %d failures", count, failures))
if failures > 0 then os.exit(1) end
