-- From repo root: luajit Tests/MetaReplyPolicy_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/MetaReplyPolicy.lua")
local P = AngryMurlocs.MetaReplyPolicy

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

do
  local s = P.New({ maxOpen = 3, batchSize = 2, deadlineSec = 30 })
  local a, o = P.Add(s, { 1, 2 }, 0, { meta = true, category = false })
  check("add two", a == 2 and o == 0)
  a, o = P.Add(s, { 1, 3 }, 5, { meta = true })
  check("merge keeps deadline", s.open[1].deadline == 30)
  a, o = P.Add(s, { 4 }, 0, { meta = true })
  check("overflow", a == 0 and o == 1)
end

do
  local s = P.New()
  P.Add(s, { 10 }, 0, { meta = true, category = true })
  P.Observe(s, 10, "meta", "canon-meta", 1)
  check("observe clears meta only", s.open[10] and s.open[10].meta == false and s.open[10].category == true)
  P.Observe(s, 10, "category", "canon-cat", 2)
  check("observe clears row", s.open[10] == nil)
end

do
  local s = P.New()
  P.Observe(s, 7, "meta", "early", 0)
  P.Add(s, { 7 }, 1, { meta = true })
  check("observe before add does not auto-clear", s.open[7] and s.open[7].meta == true)
end

do
  local s = P.New({ batchSize = 2 })
  P.Add(s, { 1, 2, 3 }, 0, { category = true })
  local cand = {
    [1] = { category = "c1" },
    [2] = { category = "c2" },
    [3] = { category = "c3" },
  }
  local batch = P.Due(s, 0, cand)
  check("batch size", #batch == 2)
  P.Resolve(s, { batch[1].id, batch[2].id }, "category", "queued", 0)
  batch = P.Due(s, 0, cand)
  check("next due after resolve", #batch == 1 and batch[1].id == 3)
end

do
  local s = P.New({ deadlineSec = 10 })
  P.Add(s, { 9 }, 0, { meta = true })
  local batch = P.Due(s, 11, { [9] = { meta = "m" } })
  check("expired dropped", #batch == 0 and s.open[9] == nil)
end

do
  local s = P.New()
  P.Add(s, { 1 }, 0, { category = true })
  -- category-only: no meta candidate should not force meta send
  local batch = P.Due(s, 0, { [1] = { category = "Potions" } })
  check("category only due", #batch == 1 and batch[1].meta == nil and batch[1].category == "Potions")
end

P.Reset(P.New())
check("reset ok", true)

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
