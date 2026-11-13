-- Bounded priority send queue (no WoW APIs). Safe for CLI unit tests.
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local Queue = {}
GR.SendQueue = Queue

Queue.ORDER = { "kill", "ctrl", "data", "pos" }
Queue.CAPS = { kill = 20, ctrl = 30, data = 300, pos = 1 }
-- A waiting position update jumps ahead of bulk data after this many seconds.
Queue.POS_MAX_WAIT = 5

local Q = {}
Q.__index = Q

function Queue.New(opts)
  opts = opts or {}
  local q = setmetatable({ lanes = {}, caps = {}, dropped = 0 }, Q)
  for i = 1, #Queue.ORDER do
    local p = Queue.ORDER[i]
    q.lanes[p] = {}
    q.caps[p] = (opts.caps and opts.caps[p]) or Queue.CAPS[p]
  end
  return q
end

function Q:Free(prio)
  local lane = self.lanes[prio]
  if not lane then return 0 end
  return self.caps[prio] - #lane
end

-- items: list of { payload, category, scopeKey?, operationId? } pushed atomically
-- (fragments stay together). Optional meta is copied so PushFront / Purge keep it.
-- The pos lane keeps only the newest position update.
function Q:PushAll(prio, items, now)
  local lane = self.lanes[prio]
  if not lane or #items == 0 then return false, "bad_prio" end
  if prio == "pos" then
    for i = #lane, 1, -1 do lane[i] = nil end
  end
  if #items > self.caps[prio] - #lane then
    self.dropped = self.dropped + #items
    return false, "full"
  end
  for i = 1, #items do
    local it = items[i]
    lane[#lane + 1] = {
      payload = it.payload,
      category = it.category,
      prio = prio,
      enq = now or 0,
      scopeKey = it.scopeKey,
      operationId = it.operationId,
    }
  end
  return true
end

function Q:Push(prio, payload, category, now)
  return self:PushAll(prio, { { payload = payload, category = category } }, now)
end

function Q:Pop(now)
  local pos = self.lanes.pos
  if pos[1] and now and (now - (pos[1].enq or 0)) >= Queue.POS_MAX_WAIT
      and #self.lanes.kill == 0 then
    return table.remove(pos, 1)
  end
  for i = 1, #Queue.ORDER do
    local lane = self.lanes[Queue.ORDER[i]]
    if lane[1] then
      return table.remove(lane, 1)
    end
  end
  return nil
end

-- Puts a popped item back at the front of its lane (send was throttled).
-- Ignores the cap: the item was already counted when it was queued.
function Q:PushFront(item)
  local lane = item and self.lanes[item.prio]
  if not lane then return false end
  table.insert(lane, 1, item)
  return true
end

-- Removes queued items for which fn(item) is true. Returns count removed.
function Q:Purge(fn)
  local n = 0
  for _, lane in pairs(self.lanes) do
    for i = #lane, 1, -1 do
      if fn(lane[i]) then
        table.remove(lane, i)
        n = n + 1
      end
    end
  end
  return n
end

function Q:Size(prio)
  if prio then return #(self.lanes[prio] or {}) end
  local n = 0
  for _, lane in pairs(self.lanes) do n = n + #lane end
  return n
end

return Queue
