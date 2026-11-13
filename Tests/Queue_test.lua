-- From repo root: luajit Tests/Queue_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/Queue.lua")

local Queue = AngryMurlocs.SendQueue
assert(Queue, "SendQueue missing")

local fails = 0
local function check(name, cond)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name)
  end
end

-- Priority order
do
  local q = Queue.New()
  q:Push("pos", "P", "pos", 0)
  q:Push("data", "D", "misc", 0)
  q:Push("ctrl", "C", "sync", 0)
  q:Push("kill", "K", "death", 0)
  local order = {}
  for _ = 1, 4 do order[#order + 1] = q:Pop(1).payload end
  check("order kill>ctrl>data>pos", table.concat(order) == "KCDP")
  check("empty pop nil", q:Pop(1) == nil)
end

-- Caps and dropped counter
do
  local q = Queue.New({ caps = { kill = 2, ctrl = 2, data = 3, pos = 1 } })
  check("kill 1", q:Push("kill", "a", "death", 0))
  check("kill 2", q:Push("kill", "b", "death", 0))
  local ok, why = q:Push("kill", "c", "death", 0)
  check("kill cap full", not ok and why == "full")
  check("dropped counted", q.dropped == 1)
  check("free 0", q:Free("kill") == 0)
  check("bad prio", select(2, q:Push("nope", "x", "misc", 0)) == "bad_prio")
end

-- Fragments are atomic: all or nothing
do
  local q = Queue.New({ caps = { kill = 20, ctrl = 30, data = 3, pos = 1 } })
  q:Push("data", "x", "misc", 0)
  local frags = { { payload = "f1", category = "prof" }, { payload = "f2", category = "prof" }, { payload = "f3", category = "prof" } }
  local ok = q:PushAll("data", frags, 0)
  check("fragments rejected when not all fit", not ok and q:Size("data") == 1)
  q:Pop(0)
  ok = q:PushAll("data", frags, 0)
  check("fragments accepted together", ok and q:Size("data") == 3)
  check("fragments in order", q:Pop(0).payload == "f1" and q:Pop(0).payload == "f2" and q:Pop(0).payload == "f3")
end

-- Position lane keeps only the newest update
do
  local q = Queue.New()
  q:Push("pos", "POS|1", "pos", 0)
  q:Push("pos", "POS|2", "pos", 1)
  q:Push("pos", "POS|3", "pos", 2)
  check("pos replaced", q:Size("pos") == 1 and q:Pop(2).payload == "POS|3")
end

-- Position fairness: waits behind data, but jumps ahead after POS_MAX_WAIT
do
  local q = Queue.New()
  for i = 1, 50 do q:Push("data", "D" .. i, "misc", 0) end
  q:Push("pos", "POS", "pos", 0)
  check("pos waits behind data early", q:Pop(1).payload == "D1")
  check("pos jumps after wait", q:Pop(Queue.POS_MAX_WAIT).payload == "POS")
  check("data resumes", q:Pop(Queue.POS_MAX_WAIT + 1).payload == "D2")
end

-- Kill reports are never overtaken by an aged position update
do
  local q = Queue.New()
  q:Push("pos", "POS", "pos", 0)
  q:Push("kill", "WK", "death", 10)
  check("kill before aged pos", q:Pop(10).payload == "WK")
end

-- Purge by category (privacy toggle off)
do
  local q = Queue.New()
  q:Push("kill", "WK|a", "death", 0)
  q:Push("kill", "DEATH|b", "death", 0)
  q:Push("data", "PROF|x", "prof", 0)
  q:Push("pos", "POS|1", "pos", 0)
  local n = q:Purge(function(it) return it.category == "death" end)
  check("purge removed 2", n == 2)
  check("purge kept others", q:Size() == 2 and q:Size("kill") == 0)
  local first = q:Pop(0)
  check("purge kept data", first.payload == "PROF|x")
end

-- Flood: bounded memory regardless of input volume
do
  local q = Queue.New()
  local accepted = 0
  for i = 1, 5000 do
    if q:Push("data", "D" .. i, "misc", 0) then accepted = accepted + 1 end
  end
  check("flood capped at data cap", accepted == Queue.CAPS.data and q:Size("data") == Queue.CAPS.data)
  check("flood dropped counted", q.dropped == 5000 - Queue.CAPS.data)
  check("flood kill still accepted", q:Push("kill", "WK", "death", 0) and q:Pop(0).payload == "WK")
end

-- PushFront: a throttled item goes back to the front of its lane
do
  local q = Queue.New()
  q:Push("data", "A", "misc", 0)
  q:Push("data", "B", "misc", 0)
  local a = q:Pop(0)
  check("pushfront ok", q:PushFront(a) == true)
  check("pushfront keeps order", q:Pop(0).payload == "A" and q:Pop(0).payload == "B")
  check("pushfront bad item", q:PushFront({ prio = "nope" }) == false)
end

-- scopeKey / operationId survive PushAll -> Pop -> PushFront -> Pop
do
  local q = Queue.New()
  local ok = q:PushAll("ctrl", {
    { payload = "RQ1", category = "sync", scopeKey = "Realm::Old", operationId = "opA" },
    { payload = "RQ2", category = "sync", scopeKey = "Realm::Old", operationId = "opA" },
  }, 0)
  check("meta pushall ok", ok)
  local a = q:Pop(0)
  check("meta on first frag", a.scopeKey == "Realm::Old" and a.operationId == "opA" and a.payload == "RQ1")
  q:PushFront(a)
  local b = q:Pop(0)
  check("meta after pushfront", b.scopeKey == "Realm::Old" and b.operationId == "opA" and b.payload == "RQ1")
  local c = q:Pop(0)
  check("meta on second frag", c.operationId == "opA" and c.payload == "RQ2")
  local n = q:Purge(function(it) return it.operationId == "opA" end)
  check("purge by operation empty", n == 0 and q:Size() == 0)
end

-- Items without meta keep previous behaviour
do
  local q = Queue.New()
  q:Push("data", "X", "misc", 0)
  local it = q:Pop(0)
  check("no meta fields", it.scopeKey == nil and it.operationId == nil and it.payload == "X")
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
