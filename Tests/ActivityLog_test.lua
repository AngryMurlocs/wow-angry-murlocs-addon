-- ActivityLog ring + U.Status contract (no network).
-- From repo root: luajit Tests/ActivityLog_test.lua

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

local function wipe(t)
  if not t then return end
  for k in pairs(t) do t[k] = nil end
end
_G.wipe = wipe

dofile("Localization/enUS.lua")
dofile("Core/Util.lua")

local clockNow = 100
_G.GetTime = function() return clockNow end

local GR = AngryMurlocs
GR.VERSION = "test"
GR.db = { diag = { enabled = false }, privacy = {}, scopes = {} }
GR.Comm = {
  Send = function()
    error("Comm.Send must not be called from U.Status")
  end,
}

local messages = {}
function GR:SendMessage(msg, ...)
  messages[#messages + 1] = { msg = msg, n = select("#", ...), a = ... }
end
function GR:RegisterMessage() end
function GR:BindMessage() end

local chat = {}
_G.DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = m end,
}

dofile("Core/Events.lua")
-- Re-install stub SendMessage after Events (tests control notify capture).
function GR:SendMessage(msg, ...)
  messages[#messages + 1] = { msg = msg, n = select("#", ...), a = ... }
end

dofile("Core/ActivityLog.lua")
dofile("Core/Diag.lua")

local Log = GR.ActivityLog
local U = GR.Util

-- Empty start
check("starts empty", #Log:Entries() == 0)

-- Entries() all / Entries(n) cap, newest first
Log:Add("a")
Log:Add("b")
Log:Add("c")
local all = Log:Entries()
check("Entries all count", #all == 3, #all)
check("Entries newest first", all[1].msg == "c" and all[2].msg == "b" and all[3].msg == "a")
local limited = Log:Entries(2)
check("Entries n at most n", #limited == 2 and limited[1].msg == "c" and limited[2].msg == "b")

-- Capacity 100; 101 evicts oldest
Log:Clear()
wipe(messages)
for i = 1, 101 do
  Log:Add(tostring(i))
end
local retained = Log:Entries()
check("capacity 100 after 101 adds", #retained == 100, #retained)
check("newest is 101", retained[1].msg == "101")
check("oldest retained is 2", retained[100].msg == "2")
check("evicted 1", retained[100].msg ~= "1")

-- Clear + seq continues; notify after mutation
wipe(messages)
local seqBefore = retained[1].seq
Log:Clear()
check("clear empties", #Log:Entries() == 0)
check("clear notifies", #messages >= 1 and messages[#messages].msg == "ACTIVITY_LOG_CHANGED")
wipe(messages)
local after = Log:Add("again")
check("add after clear works", after and after.msg == "again" and #Log:Entries() == 1)
check("seq continues after clear", after.seq == seqBefore + 1, tostring(after.seq) .. " vs " .. tostring(seqBefore + 1))
check("add notifies", #messages >= 1 and messages[#messages].msg == "ACTIVITY_LOG_CHANGED")

-- U.Status: entry with Diag off; no chat; no Comm
wipe(chat)
wipe(messages)
Log:Clear()
wipe(messages)
GR.Diag:SetEnabled(false)
check("diag off", GR.Diag:Enabled() == false)
local entry = U.Status("status-line")
check("U.Status returns entry", entry and entry.msg == "status-line")
check("U.Status stored", #Log:Entries() == 1 and Log:Entries()[1].msg == "status-line")
check("U.Status no chat", #chat == 0, #chat)
-- Comm.Send would error if called; reaching here is enough.
check("U.Status notifies", #messages >= 1 and messages[#messages].msg == "ACTIVITY_LOG_CHANGED")

-- Clear leaves Diag alone
GR.Diag:SetEnabled(true)
GR.Diag:Log("kind", "diag-msg")
GR.Diag:Count("x", 3)
local diagN = #GR.Diag:Entries()
local diagCount = GR.Diag.counters.x
Log:Add("s1")
Log:Clear()
check("clear leaves diag entries", #GR.Diag:Entries() == diagN)
check("clear leaves diag counters", GR.Diag.counters.x == diagCount)

print(string.format("%d failures", fails))
if fails > 0 then os.exit(1) end
