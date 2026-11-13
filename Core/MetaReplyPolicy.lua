-- Bounded coalescing of open recipe meta/category reply work (no WoW APIs).
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local Policy = {}
GR.MetaReplyPolicy = Policy

local DEFAULTS = {
  maxOpen = 96,
  batchSize = 24,
  deadlineSec = 30,
}

local function CopyIds(ids)
  local out = {}
  if type(ids) ~= "table" then return out end
  for i = 1, #ids do
    local id = tonumber(ids[i])
    if id and id > 0 and id <= 2147483647 then
      out[#out + 1] = id
    end
  end
  return out
end

function Policy.New(opts)
  opts = opts or {}
  return {
    maxOpen = tonumber(opts.maxOpen) or DEFAULTS.maxOpen,
    batchSize = tonumber(opts.batchSize) or DEFAULTS.batchSize,
    deadlineSec = tonumber(opts.deadlineSec) or DEFAULTS.deadlineSec,
    -- id -> { meta=bool need, category=bool need, deadline=number, addedAt=number }
    open = {},
    -- observations after Add: key "id|part" -> canonical string
    seen = {},
    order = {}, -- FIFO ids for Due fairness
  }
end

local function EnsureOpen(state, id, now)
  local row = state.open[id]
  if row then return row, false end
  local n = 0
  for _ in pairs(state.open) do n = n + 1 end
  if n >= state.maxOpen then return nil, true end
  row = {
    meta = false,
    category = false,
    deadline = now + state.deadlineSec,
    addedAt = now,
  }
  state.open[id] = row
  state.order[#state.order + 1] = id
  return row, false
end

-- parts: { meta = true/false, category = true/false }
-- Returns acceptedCount, overflowCount.
function Policy.Add(state, ids, now, parts)
  now = tonumber(now) or 0
  parts = parts or { meta = true, category = true }
  ids = CopyIds(ids)
  local accepted, overflow = 0, 0
  for i = 1, #ids do
    local id = ids[i]
    local row, wasOverflow = EnsureOpen(state, id, now)
    if wasOverflow then
      overflow = overflow + 1
    elseif row then
      -- Merging must not extend the original deadline.
      if parts.meta then row.meta = true end
      if parts.category then row.category = true end
      accepted = accepted + 1
      -- Drop parts already observed after this need existed.
      local metaKey = id .. "|meta"
      local catKey = id .. "|category"
      if row.meta and state.seen[metaKey] then row.meta = false end
      if row.category and state.seen[catKey] then row.category = false end
      if not row.meta and not row.category then
        Policy.Resolve(state, { id }, "both", "suppressed", now)
      end
    end
  end
  return accepted, overflow
end

function Policy.Observe(state, id, part, canonical, now)
  id = tonumber(id)
  if not id or (part ~= "meta" and part ~= "category") then return end
  canonical = tostring(canonical or "")
  if canonical == "" then return end
  local row = state.open[id]
  if not row then return end -- observation before Add does not clear future need
  local key = id .. "|" .. part
  state.seen[key] = canonical
  if part == "meta" and row.meta then row.meta = false end
  if part == "category" and row.category then row.category = false end
  if not row.meta and not row.category then
    Policy.Resolve(state, { id }, "both", "suppressed", now)
  end
end

local function RemoveOpen(state, id)
  if not state.open[id] then return end
  state.open[id] = nil
  state.seen[id .. "|meta"] = nil
  state.seen[id .. "|category"] = nil
  for i = #state.order, 1, -1 do
    if state.order[i] == id then table.remove(state.order, i) end
  end
end

-- outcome: queued | suppressed | retry (retry keeps open)
function Policy.Resolve(state, ids, part, outcome, now)
  ids = CopyIds(ids)
  for i = 1, #ids do
    local id = ids[i]
    local row = state.open[id]
    if row then
      if outcome == "retry" then
        -- keep
      else
        if part == "meta" or part == "both" then row.meta = false end
        if part == "category" or part == "both" then row.category = false end
        if not row.meta and not row.category then
          RemoveOpen(state, id)
        end
      end
    end
  end
end

-- candidates[id] = { meta = canonicalOrNil, category = canonicalOrNil }
-- Returns list of { id, parts = {meta=, category=} } up to batchSize.
function Policy.Due(state, now, candidates)
  now = tonumber(now) or 0
  candidates = candidates or {}
  local batch = {}
  local i = 1
  while i <= #state.order and #batch < state.batchSize do
    local id = state.order[i]
    local row = state.open[id]
    if not row then
      table.remove(state.order, i)
    elseif row.deadline < now then
      RemoveOpen(state, id)
      -- do not advance i
    else
      local cand = candidates[id]
      local needMeta = row.meta and cand and cand.meta
      local needCat = row.category and cand and cand.category
      if needMeta or needCat then
        batch[#batch + 1] = {
          id = id,
          meta = needMeta and cand.meta or nil,
          category = needCat and cand.category or nil,
        }
      end
      i = i + 1
    end
  end
  return batch
end

function Policy.NextDue(state, now)
  now = tonumber(now) or 0
  local best
  for _, row in pairs(state.open) do
    if row.deadline >= now then
      if not best or row.deadline < best then best = row.deadline end
    end
  end
  return best
end

local function Clear(t)
  for k in pairs(t) do t[k] = nil end
end

function Policy.Reset(state)
  Clear(state.open)
  Clear(state.seen)
  Clear(state.order)
end

return Policy
