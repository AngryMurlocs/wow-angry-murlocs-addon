-- From repo root: luajit Tests/PinCluster_test.lua
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

local function near(a, b)
  return math.abs(a - b) < 0.001
end

local function pt(name, x, y)
  return { name = name, x = x, y = y }
end

local function sameAnchor(out, names)
  local a = out[names[1]]
  for i = 2, #names do
    local b = out[names[i]]
    if not (near(a.cx, b.cx) and near(a.cy, b.cy)) then return false end
  end
  return true
end

do
  local out = M.ClusterOffsets({ pt("A", 10, 20) }, 18, 2)
  check("single stays", out.A and near(out.A.ox, 0) and near(out.A.oy, 0) and near(out.A.cx, 10))
end

do
  local out = M.ClusterOffsets({ pt("B", 0, 0), pt("A", 0, 0) }, 18, 2)
  check("pair shares anchor", sameAnchor(out, { "A", "B" }))
  check("pair side by side", near(out.A.ox, -10) and near(out.B.ox, 10) and near(out.A.oy, 0) and near(out.B.oy, 0))
  check("pair name order", out.A.ox < out.B.ox)
end

do
  local out = M.ClusterOffsets({ pt("A", 0, 0), pt("B", 100, 0) }, 18, 2)
  check("far pair stays apart", near(out.A.cx, 0) and near(out.B.cx, 100) and near(out.A.ox, 0) and near(out.B.ox, 0))
end

do
  local out = M.ClusterOffsets({ pt("C", 5, 5), pt("A", 5, 5), pt("B", 5, 5) }, 18, 2)
  local ups, downs = 0, 0
  for _, name in ipairs({ "A", "B", "C" }) do
    if out[name].oy > 0 then ups = ups + 1 else downs = downs + 1 end
  end
  check("triangle one top", ups == 1 and downs == 2, ups)
  check("triangle shared anchor", sameAnchor(out, { "A", "B", "C" }))
end

do
  local out = M.ClusterOffsets({
    pt("D", 0, 0), pt("C", 0, 0), pt("B", 0, 0), pt("A", 0, 0),
  }, 18, 2)
  local ups = 0
  for _, name in ipairs({ "A", "B", "C", "D" }) do
    if out[name].oy > 0 then ups = ups + 1 end
  end
  check("grid two and two", ups == 2)
end

do
  local names = { "A", "B", "C", "D", "E" }
  local pts = {}
  for i = 1, #names do pts[i] = pt(names[i], 3, 3) end
  local out = M.ClusterOffsets(pts, 18, 2)
  local ups = 0
  for i = 1, #names do
    if out[names[i]].oy > 0 then ups = ups + 1 end
  end
  check("five is two over three", ups == 2)
end

do
  local names = { "A", "B", "C", "D", "E", "F" }
  local pts = {}
  for i = 1, #names do pts[i] = pt(names[i], 0, 0) end
  local out = M.ClusterOffsets(pts, 18, 2)
  local center = 0
  for i = 1, #names do
    if near(out[names[i]].ox, 0) and near(out[names[i]].oy, 0) then center = center + 1 end
  end
  check("six has one center", center == 1)
  local step = 20
  local minD = 999
  for i = 1, #names do
    for j = i + 1, #names do
      local dx = out[names[i]].ox - out[names[j]].ox
      local dy = out[names[i]].oy - out[names[j]].oy
      local d = math.sqrt(dx * dx + dy * dy)
      if d < minD then minD = d end
    end
  end
  check("six slots do not overlap", minD >= step - 0.05, minD)
end

do
  -- Road: each step is 0.9 pin. A chain must not collapse into one circle.
  local pin = 18
  local pts = {}
  for i = 1, 5 do pts[i] = pt(string.char(64 + i), (i - 1) * pin * 0.9, 0) end
  local out = M.ClusterOffsets(pts, pin, 2)
  local anchors = {}
  for i = 1, 5 do
    local key = string.format("%.2f", out[pts[i].name].cx)
    anchors[key] = true
  end
  local n = 0
  for _ in pairs(anchors) do n = n + 1 end
  check("road is not one pile", n > 1, n)
end

do
  local out = M.ClusterOffsets({ pt("Z", 0, 0), pt("A", 0, 0) }, 18, 2)
  check("stable name slots", out.A.ox < out.Z.ox)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
