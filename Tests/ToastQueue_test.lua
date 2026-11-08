-- From repo root: luajit Tests/ToastQueue_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/Toasts.lua")

local T = AngryMurlocs.ToastQueue
local fails = 0
local function check(name, cond, extra)
  if cond then print("OK  " .. name) else fails = fails + 1 print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or "")) end
end

-- Push ordering
do
  local q = {}
  T.Push(q, { kind = "lvl", id = 1 }, 20)
  T.Push(q, { kind = "lvl", id = 2 }, 20)
  T.Push(q, { kind = "death", id = "d1" }, 20)
  check("death before lvls", q[1].kind == "death" and q[2].id == 1 and q[3].id == 2)
  T.Push(q, { kind = "death", id = "d2" }, 20)
  check("second death before lvls", q[1].id == "d1" and q[2].id == "d2" and q[3].kind == "lvl")
end

-- Cap drops oldest lvl first
do
  local q = {}
  for i = 1, 18 do T.Push(q, { kind = "death", id = "d" .. i }, 20) end
  T.Push(q, { kind = "lvl", id = "L1" }, 20)
  T.Push(q, { kind = "lvl", id = "L2" }, 20)
  T.Push(q, { kind = "lvl", id = "L3" }, 20)
  check("cap 20", #q == 20)
  local hasL1 = false
  for i = 1, #q do if q[i].id == "L1" then hasL1 = true end end
  check("oldest lvl dropped", not hasL1)
  local hasL3 = false
  for i = 1, #q do if q[i].id == "L3" then hasL3 = true end end
  check("newest lvl kept", hasL3)
end

-- Cap with only deaths: drop oldest
do
  local q = {}
  for i = 1, 22 do T.Push(q, { kind = "death", id = i }, 20) end
  check("death-only cap", #q == 20 and q[1].id == 3 and q[20].id == 22)
end

-- CanShow gates
do
  local st = { items = { { kind = "lvl" } }, showing = false, lastAt = 0 }
  check("can show", T.CanShow(st, 10, false, 1.5))
  check("blocked combat", not T.CanShow(st, 10, true, 1.5))
  st.showing = true
  check("blocked showing", not T.CanShow(st, 10, false, 1.5))
  st.showing = false
  st.lastAt = 9
  check("blocked cooldown", not T.CanShow(st, 10, false, 1.5))
  check("cooldown elapsed", T.CanShow(st, 10.5, false, 1.5))
  st.items = {}
  check("blocked empty", not T.CanShow(st, 100, false, 1.5))
end

-- Runtime enqueue with stub handlers
do
  T._ResetForTest()
  local shown = {}
  T.Register("death", function(item, done)
    shown[#shown + 1] = item
    done()
  end)
  T.Register("lvl", function(item, done)
    shown[#shown + 1] = item
    done()
  end)
  -- No GetTime/C_Timer in this env: drain still runs synchronously when cooldown allows
  _G.GetTime = function() return 100 end
  _G.UnitAffectingCombat = function() return false end
  T.Enqueue({ kind = "lvl", id = "a" })
  T.Enqueue({ kind = "death", id = "b" })
  -- first enqueue drained immediately; second may be blocked by cooldown (lastAt just set)
  local st = T._StateForTest()
  check("runtime queued remaining under cooldown", T.Size() + (st.showing and 1 or 0) >= 1)
  check("first shown was death or lvl", shown[1] and (shown[1].kind == "death" or shown[1].kind == "lvl"))
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
