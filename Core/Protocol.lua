-- Wire protocol v2 for Wanted events + sync (no WoW APIs). Safe for CLI unit tests.
--
--   WK|killer|origin|n|seq|t|zone                   live self-report by the victim (origin)
--   SR|2|reqId|cursorT|cursorKey|target             sync request (target "" = anyone)
--   WSH|requester|reqId|count                       response header (suppresses other responders)
--   WS|reqId|E|killer|legacy|seenT|seenZone|seenBy  entry record
--   WS|reqId|O|killer|origin|n|seq|t|zone           origin counter record (relayed)
--   WSE|requester|reqId|count|more|cursorT|cursorKey response end
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local P = {}
GR.Protocol = P

P.VERSION = 2
P.MAX_PAYLOAD = 250
P.MAX_NAME = 48
P.MAX_ZONE = 48
P.MAX_N = 1000
P.MAX_INT = 2147483647
P.MAX_COUNT = 10000

P.RESPONDER_MAX_PENDING = 3
P.REQUEST_DEDUP_SEC = 60

local function Clean(s, maxLen)
  s = tostring(s or ""):gsub("|", ""):gsub("[%c]", "")
  if maxLen and #s > maxLen then
    s = s:sub(1, maxLen)
  end
  return s
end
P.Clean = Clean

local function SplitKeepEmpty(str)
  local t = {}
  str = tostring(str or "")
  local start = 1
  while true do
    local i = str:find("|", start, true)
    if not i then
      t[#t + 1] = str:sub(start)
      break
    end
    t[#t + 1] = str:sub(start, i - 1)
    start = i + 1
  end
  return t
end
P.Split = SplitKeepEmpty

local function Int(s, lo, hi)
  local v = tonumber(s)
  if not v or v ~= v or math.floor(v) ~= v then return nil end
  if lo and v < lo then return nil end
  if hi and v > hi then return nil end
  return v
end

-- Required name field: present, no separators, within length.
local function Name(s)
  if type(s) ~= "string" or s == "" then return nil end
  if #s > P.MAX_NAME then return nil end
  if s:find("[|%c]") then return nil end
  return s
end

local function Zone(s)
  if s == nil then return "" end
  if type(s) ~= "string" or #s > P.MAX_ZONE then return nil end
  if s:find("[|%c]") then return nil end
  return s
end

local function ReqId(s)
  if type(s) ~= "string" or s == "" or #s > 12 then return nil end
  if not s:match("^%w+$") then return nil end
  return s
end

local function Finish(payload)
  if #payload > P.MAX_PAYLOAD then return nil, "too_long" end
  return payload
end

-- WK ---------------------------------------------------------------------

function P.EncodeWK(r)
  return Finish(string.format("WK|%s|%s|%d|%d|%d|%s",
    Clean(r.killer, P.MAX_NAME), Clean(r.origin, P.MAX_NAME),
    r.n, r.seq, r.t, Clean(r.zone, P.MAX_ZONE)))
end

function P.DecodeWK(rest)
  local p = SplitKeepEmpty(rest)
  if #p ~= 6 then return nil, "field_count" end
  local r = {
    killer = Name(p[1]),
    origin = Name(p[2]),
    n = Int(p[3], 1, P.MAX_N),
    seq = Int(p[4], 1, P.MAX_INT),
    t = Int(p[5], 1, P.MAX_INT),
    zone = Zone(p[6]),
  }
  if not r.killer or not r.origin then return nil, "bad_name" end
  if not r.n or not r.seq or not r.t then return nil, "bad_number" end
  if not r.zone then return nil, "bad_zone" end
  if string.lower(r.killer) == string.lower(r.origin) then return nil, "self_kill" end
  return r
end

-- SR ---------------------------------------------------------------------

function P.EncodeSR(reqId, cursorT, cursorKey, target)
  return Finish(string.format("SR|%d|%s|%d|%s|%s",
    P.VERSION, reqId, cursorT or 0, Clean(cursorKey, P.MAX_NAME), Clean(target, P.MAX_NAME)))
end

function P.DecodeSR(rest)
  local p = SplitKeepEmpty(rest)
  if #p ~= 5 then return nil, "field_count" end
  local ver = Int(p[1], 1, 999)
  if not ver or ver < P.VERSION then return nil, "version" end
  local r = {
    version = ver,
    reqId = ReqId(p[2]),
    cursorT = Int(p[3], 0, P.MAX_INT),
    cursorKey = (p[4] == "" and "") or Name(p[4]),
    target = (p[5] == "" and "") or Name(p[5]),
  }
  if not r.reqId then return nil, "bad_reqid" end
  if not r.cursorT then return nil, "bad_number" end
  if not r.cursorKey or not r.target then return nil, "bad_name" end
  return r
end

-- WSH / WSE --------------------------------------------------------------

function P.EncodeWSH(requester, reqId, count)
  return Finish(string.format("WSH|%s|%s|%d", Clean(requester, P.MAX_NAME), reqId, count or 0))
end

function P.DecodeWSH(rest)
  local p = SplitKeepEmpty(rest)
  if #p ~= 3 then return nil, "field_count" end
  local r = { requester = Name(p[1]), reqId = ReqId(p[2]), count = Int(p[3], 0, P.MAX_COUNT) }
  if not r.requester or not r.reqId or not r.count then return nil, "invalid" end
  return r
end

function P.EncodeWSE(requester, reqId, count, more, cursorT, cursorKey)
  return Finish(string.format("WSE|%s|%s|%d|%d|%d|%s",
    Clean(requester, P.MAX_NAME), reqId, count or 0, more and 1 or 0,
    cursorT or 0, Clean(cursorKey, P.MAX_NAME)))
end

function P.DecodeWSE(rest)
  local p = SplitKeepEmpty(rest)
  if #p ~= 6 then return nil, "field_count" end
  local r = {
    requester = Name(p[1]),
    reqId = ReqId(p[2]),
    count = Int(p[3], 0, P.MAX_COUNT),
    more = Int(p[4], 0, 1),
    cursorT = Int(p[5], 0, P.MAX_INT),
    cursorKey = (p[6] == "" and "") or Name(p[6]),
  }
  if not r.requester or not r.reqId or not r.count or not r.more or not r.cursorT or not r.cursorKey then
    return nil, "invalid"
  end
  r.more = r.more == 1
  return r
end

-- WS ---------------------------------------------------------------------

function P.EncodeWSEntry(reqId, killer, legacy, seenT, seenZone, seenBy)
  return Finish(string.format("WS|%s|E|%s|%d|%d|%s|%s",
    reqId, Clean(killer, P.MAX_NAME), legacy or 0, seenT or 0,
    Clean(seenZone, P.MAX_ZONE), Clean(seenBy, P.MAX_NAME)))
end

function P.EncodeWSOrigin(reqId, killer, origin, n, seq, t, zone)
  return Finish(string.format("WS|%s|O|%s|%s|%d|%d|%d|%s",
    reqId, Clean(killer, P.MAX_NAME), Clean(origin, P.MAX_NAME),
    n, seq, t, Clean(zone, P.MAX_ZONE)))
end

function P.DecodeWS(rest)
  local p = SplitKeepEmpty(rest)
  local reqId = ReqId(p[1])
  if not reqId then return nil, "bad_reqid" end
  local kind = p[2]
  if kind == "E" then
    if #p ~= 7 then return nil, "field_count" end
    local r = {
      reqId = reqId,
      kind = "E",
      killer = Name(p[3]),
      legacy = Int(p[4], 0, P.MAX_N),
      seenT = Int(p[5], 0, P.MAX_INT),
      seenZone = Zone(p[6]),
      seenBy = (p[7] == "" and "") or Name(p[7]),
    }
    if not r.killer or not r.legacy or not r.seenT or not r.seenZone or not r.seenBy then
      return nil, "invalid"
    end
    return r
  elseif kind == "O" then
    if #p ~= 8 then return nil, "field_count" end
    local r = {
      reqId = reqId,
      kind = "O",
      killer = Name(p[3]),
      origin = Name(p[4]),
      n = Int(p[5], 1, P.MAX_N),
      seq = Int(p[6], 1, P.MAX_INT),
      t = Int(p[7], 1, P.MAX_INT),
      zone = Zone(p[8]),
    }
    if not r.killer or not r.origin or not r.n or not r.seq or not r.t or not r.zone then
      return nil, "invalid"
    end
    if string.lower(r.killer) == string.lower(r.origin) then return nil, "self_kill" end
    return r
  end
  return nil, "bad_kind"
end

-- Responder policy -------------------------------------------------------
-- Bounds how many sync requests one client answers: dedup per requester+cursor,
-- a small pending cap, and cancellation once another member's WSH is seen.

function P.NewResponder()
  return { recent = {}, pending = {} }
end

local function PendingCount(st)
  local n = 0
  for _ in pairs(st.pending) do n = n + 1 end
  return n
end
P.PendingCount = PendingCount

-- prio: random per responder. When full, a higher prio evicts the lowest pending
-- one, so during a login storm different responders keep different requesters
-- instead of all keeping the first few.
function P.OnRequest(st, sender, req, now, me, delay, prio)
  if req.target ~= "" and string.lower(req.target) ~= string.lower(me or "") then
    return false, "not_target"
  end
  for k, t in pairs(st.recent) do
    if (now - t) >= P.REQUEST_DEDUP_SEC then st.recent[k] = nil end
  end
  local key = string.lower(sender) .. "|" .. tostring(req.cursorT) .. "|" .. string.lower(req.cursorKey or "")
  if st.recent[key] then return false, "dup_req" end
  prio = prio or 0
  local evicted
  if PendingCount(st) >= P.RESPONDER_MAX_PENDING then
    local minPk, minP
    for pk, p in pairs(st.pending) do
      if not minP or p.prio < minP.prio then minPk, minP = pk, p end
    end
    if not minP or prio <= minP.prio then return false, "busy" end
    st.pending[minPk] = nil
    st.recent[minP.rkey] = nil
    evicted = minPk
  end
  st.recent[key] = now
  local pk = string.lower(sender) .. "|" .. req.reqId
  st.pending[pk] = { requester = sender, req = req, due = now + (delay or 0), prio = prio, rkey = key }
  return true, pk, evicted
end

-- A taken response that could not be sent: allow the same request again.
function P.Forget(st, p)
  if p and p.rkey then st.recent[p.rkey] = nil end
end

function P.OnHeaderSeen(st, requester, reqId)
  local pk = string.lower(requester) .. "|" .. reqId
  if st.pending[pk] then
    st.pending[pk] = nil
    return true
  end
  return false
end

-- Returns and removes the pending responses that are due.
function P.TakeDue(st, now)
  local due = {}
  for pk, p in pairs(st.pending) do
    if p.due <= now then
      due[#due + 1] = p
      st.pending[pk] = nil
    end
  end
  table.sort(due, function(a, b) return a.due < b.due end)
  return due
end

return P
