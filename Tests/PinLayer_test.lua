-- From repo root: luajit Tests/PinLayer_test.lua
AngryMurlocs = AngryMurlocs or {}
AngryMurlocs.Util = { ClassColor = function() return 1, 1, 1 end, L = function(k) return k end, Now = function() return 0 end }
AngryMurlocs.NewModule = function(self, name)
  local m = { name = name }
  self._modules = self._modules or {}
  self._modules[name] = m
  return m
end
dofile("Modules/MapPins.lua")

local M = AngryMurlocs._modules.MapPins
local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or ""))
  end
end

local function allAt(levels, expected)
  if #levels ~= #expected then return false end
  for i = 1, #levels do
    if levels[i] ~= expected[i] then return false end
  end
  return true
end

do
  local levels, hover = M.LayerLevels(5, 10, 2014)
  check("under dig-site band", allAt(levels, { 2012, 2012, 2012, 2012, 2012 }), levels[1])
  check("hover stays under band start", hover == 2013)
  for i = 1, #levels do
    check("pin " .. i .. " below symbols", levels[i] < 2014)
  end
  check("hover below symbols", hover < 2014)
end

do
  local levels, hover = M.LayerLevels(3, 10, nil)
  check("no band sits on canvas", allAt(levels, { 11, 11, 11 }))
  check("no band hover stays put", hover == 11)
end

do
  local levels, hover = M.LayerLevels(4, 3000, 2014)
  check("canvas already above band", allAt(levels, { 3001, 3001, 3001, 3001 }))
  check("clamped hover does not climb", hover == 3001)
end

do
  local levels, hover = M.LayerLevels(0, 10, 2014)
  check("empty list", #levels == 0)
  check("empty hover still under band", hover == 2013)
end

do
  local levels, hover = M.LayerLevels(2, 10, 13)
  check("tight gap rest", allAt(levels, { 11, 11 }))
  check("tight gap hover", hover == 12 and hover < 13)
end

do
  local levels, hover = M.LayerLevels(2, 10, 12)
  check("one free level shared", allAt(levels, { 11, 11 }))
  check("one free level no extra hover", hover == 11 and hover < 12)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
