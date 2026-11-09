-- Wanted guild sync: attaches methods onto the Wanted module (no second NewModule).
local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm
local Logic = GR.WantedLogic
local P = GR.Protocol

local Wanted = GR:GetModule("Wanted")
assert(Wanted, "WantedSync requires Wanted module")

local cfg = Wanted.cfg

-- Sync tuning
local SYNC_COALESCE = 1.5
local SYNC_IDLE_TIMEOUT = 15
local SYNC_MAX_RECORDS = 120
local SYNC_AUTO_PAGES = 5
local SYNC_DELTA_MARGIN = 3600
local SYNC_RETRIES = 2
local RESPONDER_MAX_QUEUED = 150

local responder = P.NewResponder()
local responderTicker
local sync = { state = "idle" }
local answering = {} -- "requester|reqId" -> true while our response is queued

local function SyncStore()
  return Wanted:Scope().sync
end

local function SetSyncState(state, extra)
  sync.state = state
  if extra then
    for k, v in pairs(extra) do sync[k] = v end
  end
  if Wanted:Diag() then
    Wanted:Diag():Log("sync", "%s req=%s from=%s recv=%s", state, tostring(sync.reqId),
      tostring(sync.responder), tostring(sync.received))
  end
  GR:SendMessage("SYNC_STATUS", sync.state)
end

function Wanted:IsSyncBusy()
  return sync.state == "pending" or sync.state == "waiting" or sync.state == "receiving"
end

local function ArmTimeout(sec, fn)
  local token = {}
  sync.timerToken = token
  C_Timer.After(sec, function()
    if sync.timerToken ~= token then return end
    fn()
  end)
end

local OnSyncTimeout

local function SendSyncRequest(cursorT, cursorKey, target, isRetry)
  sync.reqId = "r" .. tostring(math.random(1, 99999999))
  if not isRetry then sync.pages = (sync.pages or 0) + 1 end
  sync.cursorT, sync.cursorKey = cursorT, cursorKey
  local payload = P.EncodeSR(sync.reqId, cursorT, cursorKey, target or "")
  if not payload or not Comm:Send(payload, "ctrl", "sync") then
    SetSyncState("failed")
    return
  end
  SetSyncState("waiting")
  ArmTimeout(SYNC_IDLE_TIMEOUT, OnSyncTimeout)
end

OnSyncTimeout = function()
  if sync.state == "waiting" then
    local _, v2 = 0, 0
    if Comm.Peers then _, v2 = Comm:Peers(300) end
    if (sync.pages or 0) <= 1 and v2 > 0 and (sync.retries or 0) < SYNC_RETRIES then
      -- 0.7+ members are online but busy (login storm): ask again later.
      sync.retries = (sync.retries or 0) + 1
      local cT, cK = sync.cursorT, sync.cursorKey
      local token = {}
      sync.timerToken = token
      C_Timer.After(5 + math.random() * 10, function()
        if sync.timerToken ~= token or sync.state ~= "waiting" then return end
        SendSyncRequest(cT, cK, "", true)
      end)
      return
    end
    if (sync.pages or 0) > 1 then
      SyncStore().cursor = { t = sync.cursorT, k = sync.cursorKey }
      SetSyncState("partial")
    else
      SetSyncState("noreply")
    end
  elseif sync.state == "receiving" then
    SetSyncState("incomplete")
  end
end

-- mode: "delta" (login / guild change) or "full" (manual; resumes a partial full sync).
function Wanted:RequestSync(mode)
  mode = mode or "full"
  if not IsInGuild or not IsInGuild() then
    SetSyncState("noguild")
    return false
  end
  if Wanted:IsSyncBusy() then return false end
  local store = SyncStore()
  local cT, cK = 0, ""
  if mode == "full" then
    if store.cursor then
      cT, cK = store.cursor.t or 0, store.cursor.k or ""
    end
  elseif (store.lastOkAt or 0) > 0 then
    cT = math.max(0, store.lastOkAt - SYNC_DELTA_MARGIN)
  end
  sync = { state = "pending", mode = mode, pages = 0, received = 0, startedAt = Wanted:Now() }
  SetSyncState("pending")
  C_Timer.After(SYNC_COALESCE, function()
    if sync.state ~= "pending" then return end
    SendSyncRequest(cT, cK, "")
  end)
  return true
end

-- Two members answered the same request: the one with the lower character key
-- keeps sending, the other drops its still-queued records.
local function YieldIfDuplicate(sender, data)
  local pk = string.lower(data.requester) .. "|" .. data.reqId
  if not answering[pk] then return end
  local mine, theirs = U.CharKey(U.PlayerName()), U.CharKey(sender)
  if not theirs or not mine or theirs >= mine then return end
  answering[pk] = nil
  local reqId = data.reqId
  local n = Comm:PurgeWhere(function(payload)
    local tag, rest = payload:match("^(%u+)|(.*)$")
    if tag == "WS" then
      return rest:sub(1, #reqId + 1) == reqId .. "|"
    elseif tag == "WSE" then
      return P.Split(rest)[2] == reqId
    end
    return false
  end)
  Wanted:Reject("yield", string.format("%s to %s x%d", data.requester, tostring(sender), n))
end

local function OnHeader(sender, data)
  P.OnHeaderSeen(responder, data.requester, data.reqId)
  YieldIfDuplicate(sender, data)
  if data.reqId ~= sync.reqId or not U.IsSelfName(data.requester) then return end
  if sync.state == "receiving" and sync.responder and sender ~= sync.responder then
    -- Same tie-break as YieldIfDuplicate: follow the responder that keeps sending.
    local cur, new = U.CharKey(sync.responder), U.CharKey(sender)
    if not (new and cur and new < cur) then return end
    SetSyncState("receiving", { responder = sender, expected = data.count, received = 0 })
    ArmTimeout(SYNC_IDLE_TIMEOUT, OnSyncTimeout)
    return
  end
  if sync.state ~= "waiting" then return end
  SetSyncState("receiving", { responder = sender, expected = data.count, received = 0 })
  ArmTimeout(SYNC_IDLE_TIMEOUT, OnSyncTimeout)
end

local function OnEnd(sender, data)
  if data.reqId ~= sync.reqId or not U.IsSelfName(data.requester) then return end
  if sync.state ~= "receiving" and sync.state ~= "waiting" then return end
  if sync.responder and sender ~= sync.responder then return end
  sync.timerToken = nil
  local store = SyncStore()
  if data.more then
    if (sync.pages or 0) < SYNC_AUTO_PAGES then
      SendSyncRequest(data.cursorT, data.cursorKey, sender)
      return
    end
    store.cursor = { t = data.cursorT, k = data.cursorKey }
    SetSyncState("partial", { responder = sender })
    return
  end
  store.cursor = nil
  store.lastOkAt = Wanted:Now()
  SetSyncState("done", { responder = sender })
end

local function OnRecord(sender, data)
  if data.reqId == sync.reqId and (sync.state == "receiving" or sync.state == "waiting")
      and (not sync.responder or sync.responder == sender) then
    sync.received = (sync.received or 0) + 1
    ArmTimeout(SYNC_IDLE_TIMEOUT, OnSyncTimeout)
  end
  local now = Wanted:Now()
  if data.kind == "E" then
    local changed = Logic.MergeEntryHeader(Wanted:State(), cfg, data.killer, {
      legacy = data.legacy,
      seenT = U.ClampTs(data.seenT, now) or 0,
      seenZone = data.seenZone,
      seenBy = U.NormalizeName(data.seenBy),
    }, now)
    if changed then Wanted:ScheduleRefresh() end
    return
  end
  local r = Logic.MergeOrigin(Wanted:State(), cfg, data.killer, data.origin, data, now, {
    direct = U.SameCharacter(data.origin, sender),
    via = sender,
    selfKey = Wanted:SelfKey(),
    selfState = Wanted:SelfState(),
  })
  if r.ok then
    Wanted:ScheduleRefresh()
  elseif r.reason ~= "dup" then
    Wanted:Reject(r.reason, "WS " .. tostring(data.killer))
  end
end

local function OnLiveKill(sender, data)
  local r = Logic.MergeOrigin(Wanted:State(), cfg, data.killer, data.origin, data, Wanted:Now(), {
    direct = true,
    via = sender,
    selfKey = Wanted:SelfKey(),
    selfState = Wanted:SelfState(),
  })
  if not r.ok then
    if r.reason ~= "dup" then Wanted:Reject(r.reason, "WK " .. tostring(data.killer)) end
    return
  end
  Wanted:ScheduleRefresh()
  GR:SendMessage("WANTED_KILL", data.killer, data.origin, r.level, "direct")
end

-- Login: re-announce our own newest victim counters so members who were offline
-- when we died learn them (sync only reaches the requester). Duplicates are no-ops.
local ANNOUNCE_MAX = 20

function Wanted:AnnounceOwn()
  if not GR.db.privacy.shareDeath or not IsInGuild or not IsInGuild() then return 0 end
  local selfKey = self:SelfKey()
  local me = U.ShortName(U.PlayerName())
  local list = {}
  for key, e in pairs(self:State().wanted) do
    local o = e.origins and e.origins[selfKey]
    if o and o.own and (o.n or 0) > 0 then
      list[#list + 1] = { key = key, o = o }
    end
  end
  table.sort(list, function(a, b) return (a.o.t or 0) > (b.o.t or 0) end)
  local sent = 0
  for i = 1, math.min(#list, ANNOUNCE_MAX) do
    local o = list[i].o
    local payload = P.EncodeWK({
      killer = list[i].key, origin = me, n = o.n, seq = o.seq or 1, t = o.t or 1, zone = o.zone or "",
    })
    if payload and Comm:Send(payload, "data", "death") then sent = sent + 1 end
  end
  return sent
end

local function SkipOwnIfPrivate(_, o)
  return o.own and not GR.db.privacy.shareDeath
end

local function SendResponse(p)
  if not IsInGuild or not IsInGuild() then return end
  local req = p.req
  local pageList, more, nT, nK, records = Logic.SyncPage(Wanted:State(), req.cursorT, req.cursorKey,
    SYNC_MAX_RECORDS, { skipOrigin = SkipOwnIfPrivate })
  if Comm:QueueSize("data") + records + 1 > RESPONDER_MAX_QUEUED then
    P.Forget(responder, p)
    Wanted:Reject("busy", "sync response skipped")
    return
  end
  local reqId = req.reqId
  local header = P.EncodeWSH(p.requester, reqId, records)
  if not header or not Comm:Send(header, "ctrl", "sync") then
    P.Forget(responder, p)
    return
  end
  local now = U.Now()
  for k, t in pairs(answering) do
    if (now - t) > 300 then answering[k] = nil end
  end
  answering[string.lower(p.requester) .. "|" .. reqId] = now
  for i = 1, #pageList do
    local item = pageList[i]
    local e = item.entry
    local hdr = P.EncodeWSEntry(reqId, item.key, e.legacy or 0, e.lastSeenTime or 0,
      e.lastSeenZone or "", e.lastSeenBy or "")
    if hdr then Comm:Send(hdr, "data", "sync") end
    for j = 1, #item.origins do
      local o = item.origins[j]
      local rec = P.EncodeWSOrigin(reqId, item.key, o.name or "?", o.n, o.seq or 1, o.t, o.zone or "")
      if rec then Comm:Send(rec, "data", o.own and "death" or "sync") end
    end
  end
  local tail = P.EncodeWSE(p.requester, reqId, records, more, nT, nK)
  if tail then Comm:Send(tail, "data", "sync") end
  if Wanted:Diag() then Wanted:Diag():Log("sync", "answered %s records=%d more=%s", p.requester, records, tostring(more)) end
end

local function ProcessDue()
  local due = P.TakeDue(responder, U.Now())
  for i = 1, #due do
    SendResponse(due[i])
  end
  if P.PendingCount(responder) == 0 and responderTicker then
    responderTicker:Cancel()
    responderTicker = nil
  end
end

local function OnSyncRequest(sender, req)
  if not IsInGuild or not IsInGuild() then return end
  if req.target ~= "" and not U.SameCharacter(req.target, U.PlayerName()) then return end
  local _, _, _, _, records = Logic.SyncPage(Wanted:State(), req.cursorT, req.cursorKey,
    SYNC_MAX_RECORDS, { skipOrigin = SkipOwnIfPrivate })
  local delay
  if req.target ~= "" then
    delay = 0.5
  elseif records > 0 then
    delay = 1 + math.random() * 4
  else
    -- Members without data answer last, only if nobody else did.
    delay = 5 + math.random() * 3
  end
  local ok, why = P.OnRequest(responder, sender,
    { reqId = req.reqId, cursorT = req.cursorT, cursorKey = req.cursorKey, target = "" },
    U.Now(), U.PlayerName(), delay, req.target ~= "" and 2 or math.random())
  if not ok then
    Wanted:Reject(why, "SR " .. tostring(sender))
    return
  end
  if not responderTicker then
    responderTicker = C_Timer.NewTicker(0.1, ProcessDue)
  end
end

function Wanted:SyncStatusText()
  local state = sync.state or "idle"
  local text
  if state == "done" then
    text = string.format(U.L("SYNC_DONE"), sync.received or 0, U.ShortName(sync.responder or "?"))
  elseif state == "receiving" then
    text = string.format(U.L("SYNC_RECEIVING"), sync.received or 0, sync.expected or 0,
      U.ShortName(sync.responder or "?"))
  elseif state == "partial" then
    text = string.format(U.L("SYNC_PARTIAL"), sync.received or 0)
  elseif state == "incomplete" then
    text = string.format(U.L("SYNC_INCOMPLETE"), sync.received or 0, sync.expected or 0)
  else
    text = U.L("SYNC_STATE_" .. string.upper(state))
  end
  local last = SyncStore().lastOkAt
  if last and last > 0 then
    text = text .. " · " .. string.format(U.L("SYNC_LAST_OK"), Wanted.FormatAge(last))
  end
  return text
end

function Wanted:GetLastSyncOkAt()
  return SyncStore().lastOkAt
end

function Wanted:_EnableSync()
  GR:BindMessage(self, "WANTED_V2", function(_, tag, sender, data)
    if tag == "WK" then
      OnLiveKill(sender, data)
    elseif tag == "SR" then
      OnSyncRequest(sender, data)
    elseif tag == "WSH" then
      OnHeader(sender, data)
    elseif tag == "WS" then
      OnRecord(sender, data)
    elseif tag == "WSE" then
      OnEnd(sender, data)
    end
  end)

  GR:BindMessage(self, "GUILD_UPDATE", function()
    sync = { state = "idle" }
    responder = P.NewResponder()
    wipe(answering)
    if Wanted.Refresh then Wanted:Refresh() end
  end)
end

function Wanted:_DisableSync()
  if responderTicker then
    responderTicker:Cancel()
    responderTicker = nil
  end
  sync.timerToken = nil
end
