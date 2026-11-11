-- Outgoing addon messages survive the client's send throttle and the
-- "outgoing addon messages restricted" state instead of being lost.
-- From repo root: luajit Tests/SendThrottle_test.lua
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

local RESULT = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 }

local function Tagged(sim)
  local out = {}
  for _, m in ipairs(sim.bus) do
    local n = m.msg:match("^TST|(%d+)$")
    if n then out[#out + 1] = tonumber(n) end
  end
  return out
end

-- Throttle: the client accepts 3 messages, then 1 per second. Nothing is lost
-- and the order stays the same.
do
  local sim = Sim.New(1)
  local tokens, refillAt = 3, 0
  local calls = 0
  local alice
  alice = sim:AddClient("Alice", { env = {
    Enum = { SendAddonMessageResult = RESULT },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function(prefix, msg, channel)
        calls = calls + 1
        if sim.clock >= refillAt + 1 then
          tokens = math.min(3, tokens + math.floor(sim.clock - refillAt))
          refillAt = sim.clock
        end
        if tokens <= 0 then return RESULT.AddonMessageThrottle end
        tokens = tokens - 1
        sim:Deliver(alice, prefix, msg, channel)
        return RESULT.Success
      end,
    },
  } })
  sim:AddClient("Bob")

  for i = 1, 8 do
    check("queue " .. i, alice.GR.Comm:Send("TST|" .. i, "data", "misc") == true)
  end
  sim:Run(30)
  local got = Tagged(sim)
  check("all 8 arrive despite throttle", #got == 8, #got)
  local inOrder = true
  for i = 1, #got do
    if got[i] ~= i then inOrder = false end
  end
  check("order kept", inOrder, table.concat(got, ","))
  check("throttle was hit", calls > 8, calls)
  check("queue empty", alice.GR.Comm:QueueSize() == 0)
end

-- Restricted: nothing is sent while restricted; everything goes out afterwards.
do
  local sim = Sim.New(2)
  local restricted = true
  local alice
  alice = sim:AddClient("Alice", { env = {
    Enum = { SendAddonMessageResult = RESULT },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      AreOutgoingAddonChatMessagesRestricted = function() return restricted end,
      SendAddonMessage = function(prefix, msg, channel)
        if restricted then return RESULT.GeneralError end
        sim:Deliver(alice, prefix, msg, channel)
        return RESULT.Success
      end,
    },
  } })
  sim:AddClient("Bob")

  for i = 1, 3 do alice.GR.Comm:Send("TST|" .. i, "data", "misc") end
  sim:Run(5)
  check("nothing sent while restricted", #Tagged(sim) == 0, #Tagged(sim))
  check("still queued", alice.GR.Comm:QueueSize() == 3, alice.GR.Comm:QueueSize())
  restricted = false
  sim:Run(5)
  check("all sent after restriction ends", #Tagged(sim) == 3, #Tagged(sim))
end

-- Older clients return nothing from SendAddonMessage: still counts as sent.
do
  local sim = Sim.New(3)
  local alice = sim:AddClient("Alice")
  sim:AddClient("Bob")
  for i = 1, 3 do alice.GR.Comm:Send("TST|" .. i, "data", "misc") end
  sim:Run(5)
  check("nil result counts as sent", #Tagged(sim) == 3, #Tagged(sim))
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
