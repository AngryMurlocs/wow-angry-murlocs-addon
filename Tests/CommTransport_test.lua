-- Send-ack, scope/operation purge, privacy vs requests.
-- From repo root: luajit Tests/CommTransport_test.lua
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

local RESULT = {
  Success = 0,
  AddonMessageThrottle = 3,
  ChannelThrottle = 8,
  GeneralError = 9,
  AddOnMessageLockdown = 11,
}

-- All-fragment send-ack: onAck(true) only after every fragment leaves.
do
  local sim = Sim.New(10)
  local alice
  local acks = {}
  alice = sim:AddClient("Alice", { env = {
    Enum = { SendAddonMessageResult = RESULT },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function(prefix, msg, channel)
        sim:Deliver(alice, prefix, msg, channel)
        return RESULT.Success
      end,
    },
  } })
  -- Force multi-fragment payload (>250 bytes).
  local body = "BIG|" .. string.rep("x", 600)
  local queued = alice.GR.Comm:Send(body, "data", "misc", {
    operationId = "big1",
    onAck = function(ok) acks[#acks + 1] = ok end,
  })
  check("big enqueue", queued == true)
  local frames = alice.GR.Comm:EstimateFrames(body)
  check("estimate frames >1", frames and frames > 1, frames)
  sim:Run(30)
  check("one ack true", #acks == 1 and acks[1] == true, #acks)
  check("queue empty after ack", alice.GR.Comm:QueueSize() == 0)
end

-- Final fragment failure fails the whole op (no success ack).
do
  local sim = Sim.New(11)
  local alice
  local acks = {}
  local n = 0
  alice = sim:AddClient("Alice", { env = {
    Enum = { SendAddonMessageResult = RESULT },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function(prefix, msg, channel)
        n = n + 1
        if n == 2 then return RESULT.GeneralError end
        sim:Deliver(alice, prefix, msg, channel)
        return RESULT.Success
      end,
    },
  } })
  local body = "BIG|" .. string.rep("y", 600)
  alice.GR.Comm:Send(body, "data", "misc", {
    operationId = "bigfail",
    onAck = function(ok) acks[#acks + 1] = ok end,
  })
  sim:Run(20)
  check("fail ack false", #acks == 1 and acks[1] == false, tostring(acks[1]))
  check("queue cleared after op fail", alice.GR.Comm:QueueSize() == 0)
end

-- Throttle is waiting: eventually ack true, no early false.
do
  local sim = Sim.New(12)
  local alice
  local acks = {}
  local tokens, refillAt = 0, 0
  alice = sim:AddClient("Alice", { env = {
    Enum = { SendAddonMessageResult = RESULT },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function() return true end,
      SendAddonMessage = function(prefix, msg, channel)
        if sim.clock < 5 then return RESULT.AddonMessageThrottle end
        if sim.clock >= refillAt + 1 then
          tokens = math.min(3, tokens + 1)
          refillAt = sim.clock
        end
        if tokens <= 0 then return RESULT.AddonMessageThrottle end
        tokens = tokens - 1
        sim:Deliver(alice, prefix, msg, channel)
        return RESULT.Success
      end,
    },
  } })
  alice.GR.Comm:Send("TST|throttle-ack", "data", "misc", {
    operationId = "th1",
    onAck = function(ok) acks[#acks + 1] = ok end,
  })
  sim:Run(3)
  check("no ack during throttle", #acks == 0)
  sim:Run(20)
  check("ack after throttle clears", #acks == 1 and acks[1] == true)
end

-- Privacy off: purge prof reply, keep sync request.
do
  local sim = Sim.New(13)
  local alice = sim:AddClient("Alice")
  -- Hold drain by making SendAddonMessage always throttle until we purge.
  alice.env.Enum = { SendAddonMessageResult = RESULT }
  alice.env.C_ChatInfo.SendAddonMessage = function()
    return RESULT.AddonMessageThrottle
  end
  alice.env.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end

  local reqQ = alice.GR.Comm:Send("PROFRCQ|1|1", "ctrl", "sync", { operationId = "req1" })
  local repQ = alice.GR.Comm:Send("PROFRC|1|1|55|Potions", "data", "prof", { operationId = "rep1" })
  check("both queued under throttle", reqQ and repQ and alice.GR.Comm:QueueSize() >= 2)

  alice.GR.db.privacy.shareProfessions = false
  alice.GR:SendMessage("PRIVACY_CHANGED")
  local left = alice.GR.Comm:QueueSize()
  -- Only sync request should remain (prof purged).
  check("privacy keeps request", left >= 1, left)

  -- Prove request still sendable after privacy off.
  local sent = {}
  alice.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel)
    sent[#sent + 1] = msg
    sim:Deliver(alice, prefix, msg, channel)
    return RESULT.Success
  end
  sim:Run(5)
  local sawReq = false
  for i = 1, #sent do
    if sent[i]:find("^PROFRCQ|") then sawReq = true end
    if sent[i]:find("^PROFRC|") then
      check("privacy must not send reply", false, sent[i])
    end
  end
  check("request still sent", sawReq)
end

-- PurgeByOperation removes queued work.
do
  local sim = Sim.New(14)
  local alice = sim:AddClient("Alice")
  alice.env.Enum = { SendAddonMessageResult = RESULT }
  alice.env.C_ChatInfo.SendAddonMessage = function() return RESULT.AddonMessageThrottle end
  alice.env.C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
  alice.GR.Comm:Send("X|1", "data", "misc", { operationId = "killme" })
  check("op queued", alice.GR.Comm:QueueSize() >= 1)
  local n = alice.GR.Comm:PurgeByOperation("killme")
  check("purge by op", n >= 1 and alice.GR.Comm:QueueSize() == 0)
end

-- Guild scope change drops old-scope queued ops.
do
  local sim = Sim.New(15)
  local alice = sim:AddClient("Alice")
  alice.env.Enum = { SendAddonMessageResult = RESULT }
  alice.env.C_ChatInfo.SendAddonMessage = function() return RESULT.AddonMessageThrottle end
  local oldScope = alice.GR.Util.GuildScopeKey()
  alice.GR.Comm:Send("OLD|1", "data", "misc", { scopeKey = oldScope, operationId = "oldscope" })
  check("old scope queued", alice.GR.Comm:QueueSize() >= 1)
  local n = alice.GR.Comm:PurgeByScope(oldScope)
  check("purge by scope", n >= 1 and alice.GR.Comm:QueueSize() == 0)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
