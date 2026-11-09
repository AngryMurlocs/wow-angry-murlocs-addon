-- Pure Wanted rules (no WoW APIs). Safe for CLI unit tests.
--
-- Counting model (schema 2): each Wanted entry keeps one counter per origin
-- (the victim character that self-reported its own deaths) plus a frozen
-- `legacy` count migrated from 0.6.x. Level = legacy + sum(origin.n).
-- Merging takes max(n) per origin, so live delivery, relays, reloads and
-- catch-up syncs are idempotent while separate victims add up.
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local WantedLogic = {}
GR.WantedLogic = WantedLogic

-- Guild-fixed rules (not user-configurable).
WantedLogic.DEFAULTS = {
  pairCooldownSec = 10,
  maxAutoWanted = 1000, -- safety cap (all wanted entries)
  maxOrigins = 100, -- origin counters per entry
  maxSelfKills = 1000, -- own per-killer counters
  maxHidden = 1000,
  autoExpireSec = 0, -- 0 = never expire by time
  futureSkewSec = 300,
}

-- Sighting freshness (UI only; does not change the kill level).
WantedLogic.SIGHT_FRESH_SEC = 60
WantedLogic.SIGHT_WARM_SEC = 5 * 60

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

--- Always return a fresh config from DEFAULTS (ignore SavedVariables overrides).
function WantedLogic.GetFixedConfig()
  local cfg = {}
  for k, v in pairs(WantedLogic.DEFAULTS) do
    cfg[k] = v
  end
  return WantedLogic.NormalizeConfig(cfg)
end

function WantedLogic.NormalizeConfig(cfg)
  cfg = cfg or {}
  CopyDefaults(WantedLogic.DEFAULTS, cfg)
  cfg.pairCooldownSec = math.max(0, tonumber(cfg.pairCooldownSec) or WantedLogic.DEFAULTS.pairCooldownSec)
  cfg.maxAutoWanted = math.max(1, math.floor(tonumber(cfg.maxAutoWanted) or 1000))
  cfg.maxOrigins = math.max(1, math.floor(tonumber(cfg.maxOrigins) or 100))
  cfg.maxSelfKills = math.max(1, math.floor(tonumber(cfg.maxSelfKills) or 1000))
  cfg.maxHidden = math.max(1, math.floor(tonumber(cfg.maxHidden) or 1000))
  cfg.autoExpireSec = math.max(0, tonumber(cfg.autoExpireSec) or 0)
  cfg.futureSkewSec = math.max(0, tonumber(cfg.futureSkewSec) or 300)
  return cfg
end

--- Wanted level → rank key (deterministic, guild-wide).
function WantedLogic.RankFromLevel(level)
  level = math.max(0, math.floor(tonumber(level) or 0))
  local key, minLevel
  if level >= 12 then
    key, minLevel = "SCOURGE", 12
  elseif level >= 8 then
    key, minLevel = "ENEMY", 8
  elseif level >= 5 then
    key, minLevel = "BOUNTY", 5
  elseif level >= 3 then
    key, minLevel = "HUNTED", 3
  else
    key, minLevel = "MARKED", 1
  end
  return { level = level, key = key, minLevel = minLevel }
end

-- Same rule as U.CharKey (kept local so this file stays standalone).
local function CharKey(name)
  if type(name) ~= "string" then return nil end
  local first = name:match("^[^%s%-]+")
  if not first or first == "" then return nil end
  return string.lower(first)
end
WantedLogic.CharKey = CharKey

local function Short(name)
  if not name then return "" end
  return tostring(name):match("^[^%-]+") or tostring(name)
end

function WantedLogic.NewEntry()
  return {
    schema = 2,
    legacy = 0,
    origins = {},
    count = 0,
    lastKillTime = 0,
    lastVictim = "",
    lastZone = "",
    lastSeenTime = 0,
    lastSeenZone = "",
    lastSeenBy = "",
    changedAt = 0,
  }
end

function WantedLogic.Level(entry)
  if type(entry) ~= "table" then return 0 end
  local total = tonumber(entry.legacy) or 0
  if type(entry.origins) == "table" then
    for _, o in pairs(entry.origins) do
      total = total + (tonumber(o.n) or 0)
    end
  end
  return total
end

local function Recount(entry)
  entry.count = WantedLogic.Level(entry)
  local bestT, best = 0, nil
  for _, o in pairs(entry.origins or {}) do
    if (o.t or 0) > bestT then
      bestT, best = o.t, o
    end
  end
  if best then
    entry.lastKillTime = bestT
    entry.lastVictim = best.name or ""
    entry.lastZone = best.zone or ""
  end
end
WantedLogic.Recount = Recount

local function Touch(entry, now)
  local t = tonumber(now) or 0
  if t > (entry.changedAt or 0) then
    entry.changedAt = t
  end
end

--- Higher = more important. Level dominates, recency breaks ties.
--- Sighting tier from lastSeenTime: fresh | warm | stale | none.
--- fresh < 60s, warm < 5min, stale >= 5min. No sighting -> none.
function WantedLogic.SightTier(entry, now)
  local t = entry and tonumber(entry.lastSeenTime) or 0
  if t <= 0 then return "none" end
  now = tonumber(now) or 0
  local age = now - t
  if age < 0 then age = 0 end
  if age < WantedLogic.SIGHT_FRESH_SEC then return "fresh" end
  if age < WantedLogic.SIGHT_WARM_SEC then return "warm" end
  return "stale"
end

function WantedLogic.Score(entry, now)
  if not entry then return 0 end
  now = tonumber(now) or 0
  local last = tonumber(entry.lastKillTime) or 0
  local recency = 0
  if last > 0 then
    recency = math.max(0, 999 - math.floor(math.max(0, now - last) / 3600))
  end
  return WantedLogic.Level(entry) * 1000 + recency
end

--- Whether an own death may raise Wanted. d = { reliable, killer, killerIsPlayer,
--- ctxKnown, instanceType, inDuel }. Returns ok, reason.
function WantedLogic.EvaluateDeath(d)
  d = d or {}
  if d.inDuel then return false, "excluded_duel" end
  if d.instanceType == "pvp" then return false, "excluded_bg" end
  if d.instanceType == "arena" then return false, "excluded_arena" end
  if not d.ctxKnown then return false, "ctx_unknown" end
  if not d.reliable then return false, "unclear_killer" end
  if not d.killerIsPlayer then return false, "not_player" end
  if type(d.killer) ~= "string" or d.killer == "" then return false, "unclear_killer" end
  return true, "ok"
end

--- Own death (this client is the origin). selfState persists per character:
--- { seq, kills = { [killerLower] = { n, t } } }.
function WantedLogic.RecordOwnDeath(state, cfg, selfState, killer, victim, zone, ts)
  cfg = WantedLogic.NormalizeConfig(cfg)
  if not state or type(state.wanted) ~= "table" or type(selfState) ~= "table" then
    return { ok = false, reason = "bad_state" }
  end
  killer = killer and tostring(killer) or ""
  victim = victim and tostring(victim) or ""
  local vk = CharKey(victim)
  if killer == "" or not vk then
    return { ok = false, reason = "bad_names" }
  end
  if CharKey(killer) == vk then
    return { ok = false, reason = "self_kill" }
  end
  ts = tonumber(ts)
  if not ts or ts <= 0 then
    return { ok = false, reason = "bad_ts" }
  end

  selfState.kills = selfState.kills or {}
  local kk = string.lower(killer)
  local mine = selfState.kills[kk]
  if mine and mine.t and math.abs(ts - mine.t) < cfg.pairCooldownSec then
    return { ok = false, reason = "pair_cd", entryKey = killer }
  end

  local entry = state.wanted[killer]
  local isNew = entry == nil
  if not entry then
    entry = WantedLogic.NewEntry()
    state.wanted[killer] = entry
  end
  entry.origins = entry.origins or {}
  local o = entry.origins[vk]
  local n = math.max(mine and mine.n or 0, o and o.n or 0) + 1
  selfState.seq = (tonumber(selfState.seq) or 0) + 1
  selfState.kills[kk] = { n = n, t = ts }
  entry.origins[vk] = {
    name = Short(victim),
    n = n,
    seq = selfState.seq,
    t = ts,
    zone = zone or "",
    direct = true,
    own = true,
  }
  Recount(entry)
  Touch(entry, ts)

  -- Bound own counters: drop the oldest killer pairs.
  local list = {}
  for k, v in pairs(selfState.kills) do
    list[#list + 1] = { k = k, t = (type(v) == "table" and v.t) or 0 }
  end
  if #list > cfg.maxSelfKills then
    table.sort(list, function(a, b) return a.t < b.t end)
    for i = 1, #list - cfg.maxSelfKills do
      selfState.kills[list[i].k] = nil
    end
  end

  return {
    ok = true,
    reason = "recorded",
    entryKey = killer,
    origin = Short(victim),
    n = n,
    seq = selfState.seq,
    t = ts,
    zone = zone or "",
    level = entry.count,
    eventId = vk .. ":" .. selfState.seq,
    isNew = isNew,
  }
end

--- Merge one origin counter (live WK or relayed WS record).
--- opts = { direct = bool, via = senderName, selfKey = own CharKey, selfState = table }
function WantedLogic.MergeOrigin(state, cfg, killer, originName, rec, now, opts)
  cfg = WantedLogic.NormalizeConfig(cfg)
  opts = opts or {}
  if not state or type(state.wanted) ~= "table" or type(rec) ~= "table" then
    return { ok = false, reason = "bad_state" }
  end
  local vk = CharKey(originName)
  if type(killer) ~= "string" or killer == "" or not vk then
    return { ok = false, reason = "bad_names" }
  end
  if CharKey(killer) == vk then
    return { ok = false, reason = "self_kill" }
  end
  local n = tonumber(rec.n)
  local t = tonumber(rec.t)
  if not n or n < 1 or not t or t <= 0 then
    return { ok = false, reason = "invalid" }
  end
  now = tonumber(now) or 0
  if now > 0 and t > now + cfg.futureSkewSec then
    return { ok = false, reason = "future_ts" }
  end

  local entry = state.wanted[killer]
  local o = entry and entry.origins and entry.origins[vk]
  if o and (o.n or 0) >= n then
    if opts.direct and not o.direct and o.n == n then
      o.direct = true
      o.via = nil
      return { ok = false, reason = "dup", upgraded = true, entryKey = killer }
    end
    return { ok = false, reason = "dup", entryKey = killer }
  end

  local isNew = entry == nil
  if not entry then
    entry = WantedLogic.NewEntry()
    state.wanted[killer] = entry
  end
  entry.origins = entry.origins or {}
  local prev = o and o.n or 0
  entry.origins[vk] = {
    name = Short(originName),
    n = n,
    seq = tonumber(rec.seq) or 0,
    t = t,
    zone = rec.zone or "",
    direct = opts.direct and true or false,
    via = (not opts.direct) and opts.via or nil,
    own = (opts.selfKey ~= nil and opts.selfKey == vk) or nil,
  }
  if opts.selfKey and opts.selfKey == vk and type(opts.selfState) == "table" then
    -- Own counter recovered from the guild (e.g. lost SavedVariables).
    opts.selfState.kills = opts.selfState.kills or {}
    local kk = string.lower(killer)
    local mine = opts.selfState.kills[kk]
    if not mine or (mine.n or 0) < n then
      opts.selfState.kills[kk] = { n = n, t = math.max(t, mine and mine.t or 0) }
    end
    if (tonumber(opts.selfState.seq) or 0) < (tonumber(rec.seq) or 0) then
      opts.selfState.seq = tonumber(rec.seq)
    end
  end
  Recount(entry)
  Touch(entry, now > 0 and now or t)
  return {
    ok = true,
    reason = "merged",
    entryKey = killer,
    added = n - prev,
    level = entry.count,
    isNew = isNew,
  }
end

local function NewerSighting(entry, seenT, seenZone, seenBy, now, cfg)
  seenT = tonumber(seenT) or 0
  if seenT <= 0 then return false end
  if now and now > 0 and seenT > now + cfg.futureSkewSec then return false end
  if seenT <= (entry.lastSeenTime or 0) then return false end
  entry.lastSeenTime = seenT
  entry.lastSeenZone = seenZone or ""
  entry.lastSeenBy = seenBy or ""
  return true
end

--- Sighting for an existing entry only (sightings never create kills).
function WantedLogic.ApplySighting(state, cfg, killer, seenT, seenZone, seenBy, now)
  cfg = WantedLogic.NormalizeConfig(cfg)
  local entry = state and state.wanted and state.wanted[killer]
  if not entry then return false, "unknown" end
  if NewerSighting(entry, seenT, seenZone, seenBy, now, cfg) then
    Touch(entry, now)
    return true
  end
  return false, "older"
end

--- Entry header from a sync (legacy count + latest sighting).
--- Creates an entry only when it carries a legacy level.
function WantedLogic.MergeEntryHeader(state, cfg, killer, hdr, now)
  cfg = WantedLogic.NormalizeConfig(cfg)
  if not state or type(state.wanted) ~= "table" or type(hdr) ~= "table" then return false end
  if type(killer) ~= "string" or killer == "" then return false end
  local legacy = tonumber(hdr.legacy) or 0
  local entry = state.wanted[killer]
  if not entry then
    if legacy <= 0 then return false end
    entry = WantedLogic.NewEntry()
    state.wanted[killer] = entry
  end
  local changed = false
  if legacy > (entry.legacy or 0) then
    entry.legacy = legacy
    changed = true
  end
  if NewerSighting(entry, hdr.seenT, hdr.seenZone, hdr.seenBy, now, cfg) then
    changed = true
  end
  if changed then
    Recount(entry)
    Touch(entry, now)
  end
  return changed
end

--- Union two schema-2 entries (scope recovery). Returns dst (or a copy of src).
function WantedLogic.MergeEntryInto(dst, src)
  if type(src) ~= "table" then return dst end
  if type(dst) ~= "table" then
    dst = WantedLogic.NewEntry()
  end
  WantedLogic.MigrateEntryV2(dst)
  WantedLogic.MigrateEntryV2(src)
  if (src.legacy or 0) > (dst.legacy or 0) then dst.legacy = src.legacy end
  for vk, o in pairs(src.origins or {}) do
    local cur = dst.origins[vk]
    if not cur or (cur.n or 0) < (o.n or 0) then
      local copy = {}
      for k, v in pairs(o) do copy[k] = v end
      dst.origins[vk] = copy
    end
  end
  if (src.lastSeenTime or 0) > (dst.lastSeenTime or 0) then
    dst.lastSeenTime = src.lastSeenTime
    dst.lastSeenZone = src.lastSeenZone or ""
    dst.lastSeenBy = src.lastSeenBy or ""
  end
  if (dst.lastKillTime or 0) < (src.lastKillTime or 0) and not next(dst.origins) then
    dst.lastKillTime = src.lastKillTime
    dst.lastVictim = src.lastVictim or ""
    dst.lastZone = src.lastZone or ""
  end
  Recount(dst)
  Touch(dst, src.changedAt)
  return dst
end

--- 0.6.x entry → schema 2. Idempotent; returns true when converted.
function WantedLogic.MigrateEntryV2(entry)
  if type(entry) ~= "table" then return false end
  if entry.schema == 2 then return false end
  entry.legacy = math.max(tonumber(entry.legacy) or 0, tonumber(entry.count) or 0)
  entry.origins = entry.origins or {}
  entry.lastKillTime = tonumber(entry.lastKillTime) or tonumber(entry.lastTime) or 0
  entry.lastVictim = entry.lastVictim or ""
  entry.lastZone = entry.lastZone or ""
  entry.lastSeenTime = tonumber(entry.lastSeenTime) or 0
  entry.lastSeenZone = entry.lastSeenZone or ""
  entry.lastSeenBy = entry.lastSeenBy or ""
  entry.changedAt = tonumber(entry.changedAt) or entry.lastKillTime or 0
  entry.events = nil
  entry.victims = nil
  entry.killTimes = nil
  entry.source = nil
  entry.lastTime = nil
  entry.schema = 2
  Recount(entry)
  return true
end

--- Caps: origins per entry, entries, hidden markers. No time-expire.
function WantedLogic.Prune(state, cfg, now)
  cfg = WantedLogic.NormalizeConfig(cfg)
  now = tonumber(now) or 0
  local stats = { removedEntries = 0, removedOrigins = 0, removedHidden = 0 }
  if not state or type(state.wanted) ~= "table" then return stats end
  local wanted = state.wanted

  for name, e in pairs(wanted) do
    local list = {}
    for vk, o in pairs(e.origins or {}) do
      list[#list + 1] = { vk = vk, t = o.t or 0, n = o.n or 0 }
    end
    if #list > cfg.maxOrigins then
      -- Smallest counters first so the level loses as little as possible.
      table.sort(list, function(a, b)
        if a.n == b.n then return a.t < b.t end
        return a.n < b.n
      end)
      for i = 1, #list - cfg.maxOrigins do
        e.origins[list[i].vk] = nil
        stats.removedOrigins = stats.removedOrigins + 1
      end
      Recount(e)
    end
    if WantedLogic.Level(e) <= 0 then
      wanted[name] = nil
      stats.removedEntries = stats.removedEntries + 1
    end
  end

  local all = {}
  for name, e in pairs(wanted) do
    all[#all + 1] = { name = name, score = WantedLogic.Score(e, now), last = e.changedAt or 0 }
  end
  if #all > cfg.maxAutoWanted then
    table.sort(all, function(a, b)
      if a.score == b.score then
        if a.last == b.last then return a.name < b.name end
        return a.last < b.last
      end
      return a.score < b.score
    end)
    for i = 1, #all - cfg.maxAutoWanted do
      wanted[all[i].name] = nil
      stats.removedEntries = stats.removedEntries + 1
    end
  end

  -- Hidden markers outlive pruned entries so an old sync cannot resurface them.
  if type(state.hidden) == "table" then
    local hl = {}
    for k, h in pairs(state.hidden) do
      hl[#hl + 1] = { k = k, t = (type(h) == "table" and h.t) or 0 }
    end
    if #hl > cfg.maxHidden then
      table.sort(hl, function(a, b) return a.t < b.t end)
      for i = 1, #hl - cfg.maxHidden do
        state.hidden[hl[i].k] = nil
        stats.removedHidden = stats.removedHidden + 1
      end
    end
  end
  return stats
end

-- Local hide: entry stays stored and keeps syncing, but is not shown until
-- its level rises above the hidden level.
function WantedLogic.Hide(state, killer, now)
  if not state or type(state.hidden) ~= "table" then return false end
  local entry = state.wanted and state.wanted[killer]
  if not entry then return false end
  state.hidden[killer] = { level = WantedLogic.Level(entry), t = tonumber(now) or 0 }
  return true
end

function WantedLogic.IsHidden(state, killer, entry)
  local h = state and state.hidden and state.hidden[killer]
  if not h then return false end
  return WantedLogic.Level(entry) <= (tonumber(h.level) or 0)
end

function WantedLogic.UnhideAll(state)
  local n = 0
  if state and type(state.hidden) == "table" then
    for k in pairs(state.hidden) do
      state.hidden[k] = nil
      n = n + 1
    end
  end
  return n
end

--- One sync page: entries ordered by (changedAt, key) after the cursor.
--- Whole entries only; records = 1 header + origins. opts.skipOrigin(vk, o) filters.
--- Returns page, more, nextT, nextKey, records.
function WantedLogic.SyncPage(state, cursorT, cursorKey, maxRecords, opts)
  opts = opts or {}
  cursorT = tonumber(cursorT) or 0
  cursorKey = cursorKey or ""
  maxRecords = math.max(1, tonumber(maxRecords) or 120)
  local list = {}
  for key, e in pairs(state and state.wanted or {}) do
    local c = e.changedAt or 0
    if c > cursorT or (c == cursorT and key > cursorKey) then
      list[#list + 1] = { key = key, entry = e, changedAt = c }
    end
  end
  table.sort(list, function(a, b)
    if a.changedAt == b.changedAt then return a.key < b.key end
    return a.changedAt < b.changedAt
  end)
  local page, records, more = {}, 0, false
  local nextT, nextKey = cursorT, cursorKey
  for i = 1, #list do
    local item = list[i]
    local origins = {}
    for vk, o in pairs(item.entry.origins or {}) do
      if not (opts.skipOrigin and opts.skipOrigin(vk, o)) then
        origins[#origins + 1] = o
      end
    end
    table.sort(origins, function(a, b) return (a.t or 0) < (b.t or 0) end)
    local need = 1 + #origins
    if records + need > maxRecords and #page > 0 then
      more = true
      break
    end
    page[#page + 1] = { key = item.key, entry = item.entry, origins = origins }
    records = records + need
    nextT, nextKey = item.changedAt, item.key
  end
  return page, more, nextT, nextKey, records
end

--- Sorted view: { key, entry, level, score } (hidden excluded unless opts.includeHidden).
function WantedLogic.Sorted(state, now, opts)
  opts = opts or {}
  local list, hidden = {}, 0
  local filter = opts.filter and opts.filter ~= "" and string.lower(opts.filter) or nil
  for key, e in pairs(state and state.wanted or {}) do
    if WantedLogic.IsHidden(state, key, e) and not opts.includeHidden then
      hidden = hidden + 1
    elseif not filter or string.lower(key):find(filter, 1, true) then
      list[#list + 1] = { key = key, entry = e, level = WantedLogic.Level(e), score = WantedLogic.Score(e, now) }
    end
  end
  local by = opts.sortBy or "level"
  table.sort(list, function(a, b)
    if by == "seen" then
      local sa, sb = a.entry.lastSeenTime or 0, b.entry.lastSeenTime or 0
      if sa ~= sb then return sa > sb end
    end
    if a.score ~= b.score then return a.score > b.score end
    return a.key < b.key
  end)
  return list, hidden
end

--- Source breakdown for display: direct self-reports, relayed reports, legacy.
function WantedLogic.SourceSummary(entry)
  local s = { own = 0, direct = 0, relayed = 0, legacy = tonumber(entry and entry.legacy) or 0 }
  for _, o in pairs(entry and entry.origins or {}) do
    if o.own then
      s.own = s.own + (o.n or 0)
    elseif o.direct then
      s.direct = s.direct + (o.n or 0)
    else
      s.relayed = s.relayed + (o.n or 0)
    end
  end
  return s
end

return WantedLogic
