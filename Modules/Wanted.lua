local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm
local Logic = GR.WantedLogic
local P = GR.Protocol

local Wanted = GR:NewModule("Wanted")

local frame
local scrollChild
local rows = {}
local minimapBtn
local searchBox
local pageText
local statusText
local sortBtn
local PAGE_SIZE = 40
local ROW_H = 18
local SEND_CD = 60
local ALERT_CD = 20
local freshnessTicker

-- Sync tuning
local SYNC_COALESCE = 1.5
local SYNC_IDLE_TIMEOUT = 15
local SYNC_MAX_RECORDS = 120
local SYNC_AUTO_PAGES = 5
local SYNC_DELTA_MARGIN = 3600
local SYNC_RETRIES = 2
local RESPONDER_MAX_QUEUED = 150

local sendCd = {}   -- targetKey -> GetTime
local alertCd = {}  -- targetKey -> GetTime
local page = 1
local sortBy = "level"
local refreshPending = false
local responder = P.NewResponder()
local responderTicker
local sync = { state = "idle" }

local WANTED_COLS = {
  { key = "WANTED_COL_KILLER", x = 4, w = 100 },
  { key = "WANTED_COL_KILLS", x = 108, w = 40, justify = "RIGHT" },
  { key = "WANTED_COL_SEEN", x = 152, w = 90 },
  { key = "WANTED_COL_SEEN_ZONE", x = 246, w = 110 },
  { key = "WANTED_COL_SEEN_BY", x = 360, w = 90 },
  { key = "WANTED_COL_VICTIM", x = 454, w = 110 },
}

local RANK_RGB = {
  MARKED = { 0.85, 0.85, 0.75 },
  HUNTED = { 1.0, 0.85, 0.45 },
  BOUNTY = { 1.0, 0.65, 0.25 },
  ENEMY = { 1.0, 0.4, 0.25 },
  SCOURGE = { 1.0, 0.2, 0.2 },
}

local cfg = Logic.GetFixedConfig()

local function Diag()
  return GR.Diag
end

local function Reject(reason, detail)
  if GR.Diag then GR.Diag:Reject(reason, detail) end
end

local function Scope()
  local scope = U.GetScopeDB()
  if scope and not scope._schema2 then
    for _, e in pairs(scope.wanted) do
      Logic.MigrateEntryV2(e)
    end
    scope.wantedCandidates = nil
    scope._schema2 = true
  end
  return scope
end

local function State()
  local scope = Scope()
  return { wanted = scope.wanted, hidden = scope.wantedHidden }
end

local function SelfKey()
  return U.CharKey(U.PlayerName())
end

local function SelfState()
  local scope = Scope()
  local key = SelfKey() or "?"
  scope.wantedSelf[key] = scope.wantedSelf[key] or { seq = 0, kills = {} }
  return scope.wantedSelf[key]
end

local function Now()
  return U.WallTime()
end

local function RankColor(level)
  local rank = Logic.RankFromLevel(level)
  local c = RANK_RGB[rank.key] or { 1, 1, 1 }
  return c[1], c[2], c[3]
end

local function NormalizeKiller(name)
  if not name or name == "" then return nil end
  return U.NormalizeName(name)
end

local function PlayerZone()
  local z = GetZoneText and GetZoneText() or ""
  if z == "" and GetRealZoneText then
    z = GetRealZoneText() or ""
  end
  return U.SanitizeText(z, 48)
end

local function FormatAge(ts)
  if not ts or ts <= 0 then return "-" end
  local age = Now() - ts
  if age < 0 then age = 0 end
  if age < 60 then
    return string.format(U.L("AGO"), math.floor(age))
  elseif age < 3600 then
    return string.format(U.L("AGO_MIN"), math.floor(age / 60))
  elseif age < 86400 * 2 then
    return string.format(U.L("AGO_HR"), math.floor(age / 3600))
  end
  return string.format(U.L("AGO_DAY"), math.floor(age / 86400))
end
Wanted.FormatAge = FormatAge

local function SightTier(entry)
  return Logic.SightTier(entry, Now())
end

local function TierRgb(tier, r, g, b)
  if tier == "fresh" then
    return math.min(1, r * 1.05 + 0.05), math.min(1, g * 1.05 + 0.05), math.min(1, b * 1.05 + 0.08)
  end
  if tier == "stale" then
    return r * 0.75, g * 0.7, b * 0.55
  end
  return r, g, b
end

local WantedPanelShown

local function EnsureFreshnessTicker()
  if freshnessTicker then return end
  freshnessTicker = C_Timer.NewTicker(1, function()
    if not WantedPanelShown() then
      if freshnessTicker then
        freshnessTicker:Cancel()
        freshnessTicker = nil
      end
      return
    end
    Wanted:Refresh()
  end)
end

function Wanted:PruneNow()
  local stats = Logic.Prune(State(), cfg, Now())
  if stats.removedEntries > 0 or stats.removedOrigins > 0 then
    Reject("cap", string.format("entries=%d origins=%d", stats.removedEntries, stats.removedOrigins))
  end
end

local function ScheduleRefresh()
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(1, function()
    refreshPending = false
    Wanted:PruneNow()
    GR:SendMessage("WANTED_CHANGED")
  end)
end

-- Own death with a verified killer (Death module decides). Victim = this client.
function Wanted:RecordOwnDeath(killer, zone)
  local key = NormalizeKiller(killer)
  if not key then return { ok = false, reason = "bad_names" } end
  local me = U.PlayerName()
  local r = Logic.RecordOwnDeath(State(), cfg, SelfState(), key, me, zone or "", Now())
  if not r.ok then
    Reject(r.reason, key)
    return r
  end
  if Diag() then Diag():Log("wanted", "own %s n=%d seq=%d", key, r.n, r.seq) end
  ScheduleRefresh()
  GR:SendMessage("WANTED_KILL", key, U.ShortName(me), r.level, "own")
  if GR.db.privacy.shareDeath then
    local payload = P.EncodeWK({
      killer = key, origin = U.ShortName(me), n = r.n, seq = r.seq, t = r.t, zone = r.zone,
    })
    if payload then Comm:Send(payload, "kill", "death") end
  else
    Reject("privacy", "WK " .. key)
  end
  return r
end

function Wanted:ApplySighting(target, zone, reporter, ts)
  local key = NormalizeKiller(target)
  if not key then return false end
  local ok = Logic.ApplySighting(State(), cfg, key, ts, zone or "", U.NormalizeName(reporter or ""), Now())
  if ok then
    local entry = State().wanted[key]
    GR:SendMessage("SIGHT_APPLIED", key, entry.lastSeenZone, entry.lastSeenBy)
    ScheduleRefresh()
  end
  return ok
end

function Wanted:Hide(killer)
  local key = NormalizeKiller(killer)
  if not key then return end
  if Logic.Hide(State(), key, Now()) then
    U.Print(string.format(U.L("WANTED_HIDDEN"), U.ShortName(key)))
    GR:SendMessage("WANTED_CHANGED")
  end
end

function Wanted:UnhideAll()
  local n = Logic.UnhideAll(State())
  U.Print(string.format(U.L("WANTED_UNHIDDEN"), n))
  GR:SendMessage("WANTED_CHANGED")
end

function Wanted:Summary()
  local list, hidden = Logic.Sorted(State(), Now())
  return { total = #list, hidden = hidden, top = list[1] }
end

-- Sync: requester ---------------------------------------------------------

local function SyncStore()
  return Scope().sync
end

local function SetSyncState(state, extra)
  sync.state = state
  if extra then
    for k, v in pairs(extra) do sync[k] = v end
  end
  if Diag() then
    Diag():Log("sync", "%s req=%s from=%s recv=%s", state, tostring(sync.reqId),
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
  sync = { state = "pending", mode = mode, pages = 0, received = 0, startedAt = Now() }
  SetSyncState("pending")
  C_Timer.After(SYNC_COALESCE, function()
    if sync.state ~= "pending" then return end
    SendSyncRequest(cT, cK, "")
  end)
  return true
end

local answering = {} -- "requester|reqId" -> true while our response is queued

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
  Reject("yield", string.format("%s to %s x%d", data.requester, tostring(sender), n))
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
  store.lastOkAt = Now()
  SetSyncState("done", { responder = sender })
end

local function OnRecord(sender, data)
  if data.reqId == sync.reqId and (sync.state == "receiving" or sync.state == "waiting")
      and (not sync.responder or sync.responder == sender) then
    sync.received = (sync.received or 0) + 1
    ArmTimeout(SYNC_IDLE_TIMEOUT, OnSyncTimeout)
  end
  local now = Now()
  if data.kind == "E" then
    local changed = Logic.MergeEntryHeader(State(), cfg, data.killer, {
      legacy = data.legacy,
      seenT = U.ClampTs(data.seenT, now) or 0,
      seenZone = data.seenZone,
      seenBy = U.NormalizeName(data.seenBy),
    }, now)
    if changed then ScheduleRefresh() end
    return
  end
  local r = Logic.MergeOrigin(State(), cfg, data.killer, data.origin, data, now, {
    direct = U.SameCharacter(data.origin, sender),
    via = sender,
    selfKey = SelfKey(),
    selfState = SelfState(),
  })
  if r.ok then
    ScheduleRefresh()
  elseif r.reason ~= "dup" then
    Reject(r.reason, "WS " .. tostring(data.killer))
  end
end

local function OnLiveKill(sender, data)
  local r = Logic.MergeOrigin(State(), cfg, data.killer, data.origin, data, Now(), {
    direct = true,
    via = sender,
    selfKey = SelfKey(),
    selfState = SelfState(),
  })
  if not r.ok then
    if r.reason ~= "dup" then Reject(r.reason, "WK " .. tostring(data.killer)) end
    return
  end
  ScheduleRefresh()
  GR:SendMessage("WANTED_KILL", data.killer, data.origin, r.level, "direct")
end

-- Login: re-announce our own newest victim counters so members who were offline
-- when we died learn them (sync only reaches the requester). Duplicates are no-ops.
local ANNOUNCE_MAX = 20

function Wanted:AnnounceOwn()
  if not GR.db.privacy.shareDeath or not IsInGuild or not IsInGuild() then return 0 end
  local selfKey = SelfKey()
  local me = U.ShortName(U.PlayerName())
  local list = {}
  for key, e in pairs(State().wanted) do
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

-- Sync: responder ---------------------------------------------------------

local function SkipOwnIfPrivate(_, o)
  return o.own and not GR.db.privacy.shareDeath
end

local function SendResponse(p)
  if not IsInGuild or not IsInGuild() then return end
  local req = p.req
  local pageList, more, nT, nK, records = Logic.SyncPage(State(), req.cursorT, req.cursorKey,
    SYNC_MAX_RECORDS, { skipOrigin = SkipOwnIfPrivate })
  if Comm:QueueSize("data") + records + 1 > RESPONDER_MAX_QUEUED then
    P.Forget(responder, p)
    Reject("busy", "sync response skipped")
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
  if Diag() then Diag():Log("sync", "answered %s records=%d more=%s", p.requester, records, tostring(more)) end
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
  local _, _, _, _, records = Logic.SyncPage(State(), req.cursorT, req.cursorKey,
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
    Reject(why, "SR " .. tostring(sender))
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
    text = text .. " · " .. string.format(U.L("SYNC_LAST_OK"), FormatAge(last))
  end
  return text
end

-- UI ----------------------------------------------------------------------

local function ShowRowTooltip(self)
  if not self.killer then return end
  local entry = State().wanted[self.killer]
  if not entry then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(self.killer, 1, 0.2, 0.2)
  local level = Logic.Level(entry)
  local rank = Logic.RankFromLevel(level)
  GameTooltip:AddLine(string.format(U.L("WANTED_RANK_LINE"), level, U.L("WANTED_RANK_" .. rank.key)), 1, 0.7, 0.3)
  local s = Logic.SourceSummary(entry)
  if s.own > 0 then GameTooltip:AddLine(string.format(U.L("WANTED_SRC_OWN"), s.own), 0.9, 0.9, 0.9) end
  if s.direct > 0 then GameTooltip:AddLine(string.format(U.L("WANTED_SRC_DIRECT"), s.direct), 0.9, 0.9, 0.9) end
  if s.relayed > 0 then GameTooltip:AddLine(string.format(U.L("WANTED_SRC_RELAYED"), s.relayed), 0.9, 0.9, 0.9) end
  if s.legacy > 0 then GameTooltip:AddLine(string.format(U.L("WANTED_SRC_LEGACY"), s.legacy), 0.8, 0.8, 0.6) end
  GameTooltip:AddLine(U.L("WANTED_SRC_NOTE"), 0.6, 0.6, 0.6, true)
  if (entry.lastKillTime or 0) > 0 then
    GameTooltip:AddLine(string.format(U.L("WANTED_LAST_KILL"), FormatAge(entry.lastKillTime),
      entry.lastVictim ~= "" and entry.lastVictim or "?", entry.lastZone ~= "" and entry.lastZone or "?"),
      0.9, 0.9, 0.9)
  end
  if (entry.lastSeenTime or 0) > 0 then
    GameTooltip:AddLine(string.format(U.L("WANTED_SIGHT_LINE"), FormatAge(entry.lastSeenTime),
      entry.lastSeenZone ~= "" and entry.lastSeenZone or "?", U.ShortName(entry.lastSeenBy or "?")),
      0.9, 0.9, 0.9)
    local tier = SightTier(entry)
    if tier == "fresh" then
      GameTooltip:AddLine(U.L("WANTED_SIGHT_FRESH"), 0.4, 1.0, 0.5)
    elseif tier == "warm" then
      GameTooltip:AddLine(U.L("WANTED_SIGHT_WARM"), 1.0, 0.85, 0.4)
    elseif tier == "stale" then
      GameTooltip:AddLine(U.L("WANTED_SIGHT_STALE"), 1.0, 0.55, 0.25)
    end
  end
  if (entry.changedAt or 0) > 0 then
    GameTooltip:AddLine(string.format(U.L("WANTED_DATA_AGE"), FormatAge(entry.changedAt)), 0.6, 0.6, 0.6)
  end
  GameTooltip:AddLine(U.L("WANTED_CLICK_HIDE"), 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function Wanted:AttachPanel(parent)
  if frame or not parent then return frame end

  frame = parent

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  searchLabel:SetPoint("TOPLEFT", 8, -6)
  searchLabel:SetText(U.L("WANTED_SEARCH"))

  searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  searchBox:SetSize(130, 20)
  searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
  searchBox:SetAutoFocus(false)
  searchBox:SetScript("OnTextChanged", function()
    page = 1
    Wanted:Refresh()
  end)

  sortBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  sortBtn:SetSize(110, 20)
  sortBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
  sortBtn:SetScript("OnClick", function()
    sortBy = (sortBy == "level") and "seen" or "level"
    page = 1
    Wanted:Refresh()
  end)

  local prevBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  prevBtn:SetSize(24, 20)
  prevBtn:SetPoint("LEFT", sortBtn, "RIGHT", 8, 0)
  prevBtn:SetText("<")
  prevBtn:SetScript("OnClick", function()
    page = math.max(1, page - 1)
    Wanted:Refresh()
  end)

  local nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextBtn:SetSize(24, 20)
  nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
  nextBtn:SetText(">")
  nextBtn:SetScript("OnClick", function()
    page = page + 1
    Wanted:Refresh()
  end)

  local syncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  syncBtn:SetSize(80, 20)
  syncBtn:SetPoint("TOPRIGHT", -4, -4)
  syncBtn:SetText(U.L("GENERAL_SYNC"))
  syncBtn:SetScript("OnClick", function()
    local ui = GR:GetModule("UI")
    if ui and ui.RunGuildDataSync then ui:RunGuildDataSync() end
  end)
  local ui = GR:GetModule("UI")
  if ui and ui.RegisterSyncButton then ui:RegisterSyncButton(syncBtn) end

  pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  pageText:SetPoint("TOPLEFT", 8, -28)
  pageText:SetWidth(600)
  pageText:SetJustifyH("LEFT")

  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  statusText:SetPoint("TOPLEFT", 8, -42)
  statusText:SetWidth(600)
  statusText:SetJustifyH("LEFT")

  U.BuildColHeaders(frame, WANTED_COLS, 4, -56, ROW_H)

  local scroll = CreateFrame("ScrollFrame", "AngryMurlocsWantedScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -76)
  scroll:SetPoint("BOTTOMRIGHT", -24, 22)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(580, PAGE_SIZE * ROW_H)
  scroll:SetScrollChild(scrollChild)

  for i = 1, PAGE_SIZE do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetSize(580, ROW_H)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
    U.BuildColRow(row, WANTED_COLS, ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
      if not self.killer then return end
      if IsShiftKeyDown and IsShiftKeyDown() then
        Wanted:Hide(self.killer)
      end
    end)
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
  end

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 8, 6)
  hint:SetPoint("BOTTOMRIGHT", -8, 6)
  hint:SetJustifyH("LEFT")
  hint:SetText(U.L("WANTED_HINT"))

  return frame
end

WantedPanelShown = function()
  local ui = GR:GetModule("UI")
  if ui and ui.IsTabShown then
    return ui:IsTabShown("wanted")
  end
  return frame and frame:IsShown()
end

function Wanted:Refresh()
  if not frame or not WantedPanelShown() then return end
  EnsureFreshnessTicker()
  local filter = searchBox and searchBox:GetText() or ""
  local list, hidden = Logic.Sorted(State(), Now(), { filter = filter, sortBy = sortBy })
  local total = #list
  local pages = math.max(1, math.ceil(total / PAGE_SIZE))
  if page > pages then page = pages end
  if page < 1 then page = 1 end
  local first = (page - 1) * PAGE_SIZE + 1
  local last = math.min(total, page * PAGE_SIZE)

  sortBtn:SetText(sortBy == "level" and U.L("WANTED_SORT_LEVEL") or U.L("WANTED_SORT_SEEN"))
  local info
  if filter ~= "" then
    info = string.format(U.L("WANTED_PAGE_FILTER"), total, page, pages)
  elseif page == 1 and total > PAGE_SIZE then
    info = string.format(U.L("WANTED_PAGE_TOP"), PAGE_SIZE, total, pages)
  else
    info = string.format(U.L("WANTED_PAGE_INFO"), page, pages, total > 0 and first or 0, last, total)
  end
  if hidden > 0 then
    info = info .. " · " .. string.format(U.L("WANTED_HIDDEN_COUNT"), hidden)
  end
  pageText:SetText(info)
  statusText:SetText(Wanted:SyncStatusText())

  scrollChild:SetHeight(math.max(last - first + 1, 1) * ROW_H)
  for i = 1, PAGE_SIZE do
    local item = list[first + i - 1]
    local row = rows[i]
    if item and (first + i - 1) <= last then
      local e = item.entry
      row.killer = item.key
      local tier = SightTier(e)
      local seen = FormatAge(e.lastSeenTime)
      if tier == "stale" then
        seen = seen .. "*"
      elseif tier == "fresh" then
        seen = seen .. "+"
      end
      local rank = Logic.RankFromLevel(item.level)
      local r, g, b = TierRgb(tier, RankColor(item.level))
      U.SetColTexts(row.cols, {
        U.ShortName(item.key),
        string.format("Lv.%d", item.level),
        seen,
        (e.lastSeenZone ~= "" and e.lastSeenZone) or "-",
        (e.lastSeenBy ~= "" and U.ShortName(e.lastSeenBy)) or "-",
        (e.lastVictim ~= "" and e.lastVictim) or "-",
      }, r, g, b)
      row:Show()
    else
      row.killer = nil
      row:Hide()
    end
  end
end

function Wanted:ShowWindow()
  local ui = GR:GetModule("UI")
  if ui and ui.ShowTab then
    ui:ShowTab("wanted")
  end
end

function Wanted:Toggle()
  local ui = GR:GetModule("UI")
  if not ui then return end
  if ui:IsTabShown("wanted") then
    local f = ui.GetFrame and ui:GetFrame()
    if f then f:Hide() end
  else
    ui:ShowTab("wanted")
  end
end

local function MaybeAlert(targetKey, zone, reporter)
  local ui = GR.db.wantedUI
  if ui and ui.showSightAlerts == false then return end
  local now = U.Now()
  local last = alertCd[targetKey] or 0
  if (now - last) < ALERT_CD then return end
  alertCd[targetKey] = now
  U.Print(string.format(
    U.L("WANTED_SIGHT_ALERT"),
    U.ShortName(targetKey),
    zone or "?",
    U.ShortName(reporter or "?")
  ))
end

local function OnTargetChanged()
  if not UnitExists or not UnitExists("target") then return end
  if not UnitIsPlayer or not UnitIsPlayer("target") then return end

  local name, realm = UnitName("target")
  if not name or name == "" then return end
  if UnitFullName then
    local n, r = UnitFullName("target")
    if n then
      name = n
      realm = r
    end
  end
  local full
  if realm and realm ~= "" then
    full = name .. "-" .. realm
  else
    full = U.NormalizeName(name)
  end
  local key = NormalizeKiller(full)
  if not key then return end
  if not State().wanted[key] then return end

  local zone = PlayerZone()
  local me = U.NormalizeName(U.PlayerName())
  local nowSession = U.Now()
  local wall = Now()

  -- Local apply (never changes the level)
  Wanted:ApplySighting(key, zone, me, wall)

  local lastSend = sendCd[key] or 0
  if (nowSession - lastSend) >= SEND_CD and IsInGuild and IsInGuild() then
    sendCd[key] = nowSession
    Comm:Send(string.format("SIGHT|%s|%s|%d", U.SanitizeText(key, 48), U.SanitizeText(zone, 48), wall),
      "ctrl", "sight")
  end

  MaybeAlert(key, zone, me)
end

local pendingMinimapUpdate = false

local function MinimapRadius()
  local w = (Minimap and Minimap.GetWidth and Minimap:GetWidth()) or 140
  return (w / 2) + 5
end

local function UpdateMinimapButton()
  if not minimapBtn or not Minimap then return end
  if InCombatLockdown and InCombatLockdown() then
    pendingMinimapUpdate = true
    return
  end
  pendingMinimapUpdate = false
  local angle = (GR.db.minimap and GR.db.minimap.angle) or 200
  local rad = math.rad(angle)
  local r = MinimapRadius()
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function EnsureMinimapButton()
  if minimapBtn then
    UpdateMinimapButton()
    return
  end
  if not Minimap then
    C_Timer.After(1, EnsureMinimapButton)
    return
  end

  local parent = (MinimapBackdrop and MinimapBackdrop) or UIParent
  minimapBtn = CreateFrame("Button", "AngryMurlocsWantedMinimapButton", parent)
  minimapBtn:SetSize(31, 31)
  minimapBtn:SetFrameStrata("MEDIUM")
  minimapBtn:SetFrameLevel(8)
  minimapBtn:RegisterForClicks("AnyUp")
  minimapBtn:RegisterForDrag("LeftButton")
  minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture("Interface\\AddOns\\AngryMurlocs\\Media\\MinimapIcon")
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  minimapBtn.icon = icon

  local border = minimapBtn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  minimapBtn:SetScript("OnClick", function(_, button)
    local ui = GR:GetModule("UI")
    if not ui or not ui.ShowTab then return end
    if button == "RightButton" then
      ui:ShowTab("opt")
    else
      ui:ShowTab("general")
    end
  end)
  minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(U.L("WANTED_MINIMAP_TIP"), 1, 0.2, 0.2)
    GameTooltip:AddLine(U.L("MINIMAP_TIP_LMB"), 0.9, 0.9, 0.9)
    GameTooltip:AddLine(U.L("MINIMAP_TIP_RMB"), 0.9, 0.9, 0.9)
    GameTooltip:Show()
  end)
  minimapBtn:SetScript("OnLeave", GameTooltip_Hide)

  minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      if not Minimap then return end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
      GR.db.minimap = GR.db.minimap or {}
      GR.db.minimap.angle = angle
      UpdateMinimapButton()
    end)
  end)
  minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  UpdateMinimapButton()
  minimapBtn:Show()
  C_Timer.After(2, UpdateMinimapButton)
end

function Wanted:OnEnable()
  Scope()
  Wanted:PruneNow()
  C_Timer.After(0.5, EnsureMinimapButton)

  local combat = CreateFrame("Frame")
  U.SafeRegisterEvent(combat, "PLAYER_REGEN_ENABLED")
  combat:SetScript("OnEvent", function()
    if pendingMinimapUpdate then
      UpdateMinimapButton()
    end
  end)

  local targetFrame = CreateFrame("Frame")
  U.SafeRegisterEvent(targetFrame, "PLAYER_TARGET_CHANGED")
  targetFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
      OnTargetChanged()
    end
  end)

  GR:RegisterMessage("WANTED_V2", function(_, tag, sender, data)
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

  GR:RegisterMessage("SIGHT_UPDATE", function(_, sender, data)
    if not data or not data.target then return end
    -- Never rebroadcast received sightings
    if Wanted:ApplySighting(data.target, data.zone, sender, data.ts) then
      MaybeAlert(data.target, data.zone, sender)
    end
  end)

  GR:RegisterMessage("WANTED_CHANGED", function()
    Wanted:Refresh()
  end)

  GR:RegisterMessage("SYNC_STATUS", function()
    Wanted:Refresh()
  end)

  GR:RegisterMessage("GUILD_UPDATE", function()
    sync = { state = "idle" }
    responder = P.NewResponder()
    wipe(answering)
    Wanted:Refresh()
  end)
end
