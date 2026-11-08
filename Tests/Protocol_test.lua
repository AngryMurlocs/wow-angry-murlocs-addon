-- From repo root: luajit Tests/Protocol_test.lua
AngryMurlocs = AngryMurlocs or {}
dofile("Core/Protocol.lua")

local P = AngryMurlocs.Protocol
assert(P, "Protocol missing")

local fails = 0
local function check(name, cond)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name)
  end
end

local function Rest(payload)
  return payload:match("^%u+|(.*)$")
end

-- WK round trip
do
  local wire = P.EncodeWK({ killer = "Enemy-Realm", origin = "Victim", n = 3, seq = 7, t = 1700000000, zone = "Hillsbrad" })
  check("WK encodes", wire ~= nil and wire:sub(1, 3) == "WK|")
  local r = P.DecodeWK(Rest(wire))
  check("WK roundtrip", r and r.killer == "Enemy-Realm" and r.origin == "Victim" and r.n == 3
    and r.seq == 7 and r.t == 1700000000 and r.zone == "Hillsbrad")
  local e = P.DecodeWK(Rest(P.EncodeWK({ killer = "A", origin = "B", n = 1, seq = 1, t = 5, zone = "" })))
  check("WK empty zone ok", e and e.zone == "")
end

-- WK rejections
do
  local _, why = P.DecodeWK("Enemy|Victim|1|1|100")
  check("WK field count", why == "field_count")
  _, why = P.DecodeWK("|Victim|1|1|100|z")
  check("WK empty killer", why == "bad_name")
  _, why = P.DecodeWK("Enemy|Victim|0|1|100|z")
  check("WK n=0 rejected", why == "bad_number")
  _, why = P.DecodeWK("Enemy|Victim|1001|1|100|z")
  check("WK n>max rejected", why == "bad_number")
  _, why = P.DecodeWK("Enemy|Victim|1.5|1|100|z")
  check("WK fraction rejected", why == "bad_number")
  _, why = P.DecodeWK("Enemy|Victim|abc|1|100|z")
  check("WK NaN rejected", why == "bad_number")
  _, why = P.DecodeWK("Enemy|enemy|1|1|100|z")
  check("WK self kill rejected", why == "self_kill")
  _, why = P.DecodeWK(string.rep("x", 49) .. "|Victim|1|1|100|z")
  check("WK long name rejected", why == "bad_name")
  _, why = P.DecodeWK("Enemy|Victim|1|1|100|" .. string.rep("z", 49))
  check("WK long zone rejected", why == "bad_zone")
end

-- Encoders strip separators so a name cannot inject fields
do
  local wire = P.EncodeWK({ killer = "Ev|il", origin = "Vic\ntim", n = 1, seq = 1, t = 1, zone = "a|b" })
  local r = P.DecodeWK(Rest(wire))
  check("WK clean injection", r and r.killer == "Evil" and r.origin == "Victim" and r.zone == "ab")
end

-- Max sizes stay within one addon message
do
  local long = string.rep("W", 60)
  local wk = P.EncodeWK({ killer = long, origin = long, n = 1000, seq = P.MAX_INT, t = P.MAX_INT, zone = long })
  check("WK max <= 250", wk ~= nil and #wk <= P.MAX_PAYLOAD)
  local wso = P.EncodeWSOrigin("abcdefghijkl", long, long, 1000, P.MAX_INT, P.MAX_INT, long)
  check("WS O max <= 250", wso ~= nil and #wso <= P.MAX_PAYLOAD)
  local wse = P.EncodeWSEntry("abcdefghijkl", long, 1000, P.MAX_INT, long, long)
  check("WS E max <= 250", wse ~= nil and #wse <= P.MAX_PAYLOAD)
  local sr = P.EncodeSR("abcdefghijkl", P.MAX_INT, long, long)
  check("SR max <= 250", sr ~= nil and #sr <= P.MAX_PAYLOAD)
  local wsend = P.EncodeWSE(long, "abcdefghijkl", P.MAX_COUNT, true, P.MAX_INT, long)
  check("WSE max <= 250", wsend ~= nil and #wsend <= P.MAX_PAYLOAD)
end

-- SR
do
  local r = P.DecodeSR(Rest(P.EncodeSR("r1a2", 1234, "enemy", "")))
  check("SR roundtrip", r and r.version == 2 and r.reqId == "r1a2" and r.cursorT == 1234
    and r.cursorKey == "enemy" and r.target == "")
  local _, why = P.DecodeSR("1|r1|0||")
  check("SR v1 rejected", why == "version")
  _, why = P.DecodeSR("2|bad id|0||")
  check("SR bad reqId", why == "bad_reqid")
  _, why = P.DecodeSR("2|" .. string.rep("a", 13) .. "|0||")
  check("SR long reqId", why == "bad_reqid")
  _, why = P.DecodeSR("2|r1|-5||")
  check("SR negative cursor", why == "bad_number")
  local fut = P.DecodeSR("3|r1|0||")
  check("SR newer version accepted", fut and fut.version == 3)
end

-- WSH / WSE
do
  local h = P.DecodeWSH(Rest(P.EncodeWSH("Asker", "q1", 42)))
  check("WSH roundtrip", h and h.requester == "Asker" and h.reqId == "q1" and h.count == 42)
  check("WSH invalid", P.DecodeWSH("Asker|q1|-1") == nil)
  local e = P.DecodeWSE(Rest(P.EncodeWSE("Asker", "q1", 120, true, 999, "zed")))
  check("WSE roundtrip", e and e.count == 120 and e.more == true and e.cursorT == 999 and e.cursorKey == "zed")
  local e2 = P.DecodeWSE(Rest(P.EncodeWSE("Asker", "q1", 3, false, 0, "")))
  check("WSE no more", e2 and e2.more == false and e2.cursorKey == "")
  check("WSE more=2 invalid", P.DecodeWSE("Asker|q1|3|2|0|") == nil)
end

-- WS
do
  local en = P.DecodeWS(Rest(P.EncodeWSEntry("q1", "Enemy", 4, 500, "Duskwood", "Scout")))
  check("WS E roundtrip", en and en.kind == "E" and en.killer == "Enemy" and en.legacy == 4
    and en.seenT == 500 and en.seenZone == "Duskwood" and en.seenBy == "Scout")
  local o = P.DecodeWS(Rest(P.EncodeWSOrigin("q1", "Enemy", "Victim", 2, 9, 600, "Arathi")))
  check("WS O roundtrip", o and o.kind == "O" and o.origin == "Victim" and o.n == 2 and o.seq == 9 and o.t == 600)
  local _, why = P.DecodeWS("q1|X|Enemy")
  check("WS bad kind", why == "bad_kind")
  _, why = P.DecodeWS("q1|O|Enemy|enemy|1|1|1|")
  check("WS O self kill", why == "self_kill")
  _, why = P.DecodeWS("q1|O|Enemy|Victim|0|1|1|")
  check("WS O n=0", why == "invalid")
  _, why = P.DecodeWS("bad id|E|Enemy|0|0||")
  check("WS bad reqId", why == "bad_reqid")
end

-- Responder: dedup, cap, targeting, suppression
do
  local st = P.NewResponder()
  local req = { reqId = "a1", cursorT = 0, cursorKey = "", target = "" }
  local ok, pk = P.OnRequest(st, "Asker", req, 100, "Me", 2)
  check("responder accepts", ok and pk == "asker|a1")
  local ok2, why2 = P.OnRequest(st, "Asker", { reqId = "a2", cursorT = 0, cursorKey = "", target = "" }, 101, "Me", 2)
  check("responder dedups same cursor", not ok2 and why2 == "dup_req")
  local ok3 = P.OnRequest(st, "Asker", { reqId = "a3", cursorT = 0, cursorKey = "", target = "" }, 161, "Me", 2)
  check("responder dedup expires after 60s", ok3)

  local _, nt = P.OnRequest(st, "Other", { reqId = "b1", cursorT = 0, cursorKey = "", target = "Someone" }, 162, "Me", 0)
  check("responder ignores other target", nt == "not_target")
  local okT = P.OnRequest(st, "Other", { reqId = "b2", cursorT = 0, cursorKey = "", target = "me" }, 162, "Me", 0)
  check("responder accepts own target (case-insensitive)", okT)

  check("pending 3", P.PendingCount(st) == 3)
  local okB, whyB = P.OnRequest(st, "Third", { reqId = "c1", cursorT = 5, cursorKey = "", target = "" }, 163, "Me", 1)
  check("responder busy at cap", not okB and whyB == "busy")

  check("header suppresses pending", P.OnHeaderSeen(st, "ASKER", "a1") == true)
  check("header unknown ignored", P.OnHeaderSeen(st, "Nobody", "zz") == false)
  check("pending 2 after suppression", P.PendingCount(st) == 2)

  local due = P.TakeDue(st, 162.5)
  check("TakeDue only due", #due == 1 and due[1].requester == "Other")
  due = P.TakeDue(st, 200)
  check("TakeDue rest", #due == 1 and due[1].requester == "Asker" and due[1].req.reqId == "a3")
  check("pending empty", P.PendingCount(st) == 0)
end

-- Full responder: higher random prio evicts the lowest; evicted request may come again
do
  local st = P.NewResponder()
  local function Req(id) return { reqId = id, cursorT = 0, cursorKey = "", target = "" } end
  P.OnRequest(st, "A", Req("a"), 0, "Me", 5, 0.2)
  P.OnRequest(st, "B", Req("b"), 0, "Me", 5, 0.5)
  P.OnRequest(st, "C", Req("c"), 0, "Me", 5, 0.7)
  local okLow, whyLow = P.OnRequest(st, "D", Req("d"), 0, "Me", 5, 0.1)
  check("evict: lower prio refused", not okLow and whyLow == "busy")
  local okHi, pk, evicted = P.OnRequest(st, "E", Req("e"), 0, "Me", 5, 0.9)
  check("evict: higher prio accepted", okHi and pk == "e|e" and evicted == "a|a")
  check("evict: still capped", P.PendingCount(st) == 3)
  local okAgain = P.OnRequest(st, "A", Req("a2"), 1, "Me", 5, 0.95)
  check("evict: evicted requester not deduped", okAgain)
  local due = P.TakeDue(st, 10)
  P.Forget(st, due[1])
  local okForgot = P.OnRequest(st, due[1].requester, Req("z"), 11, "Me", 0, 0.1)
  check("forget: unsent response can be requested again", okForgot)
end

-- Flood of distinct requesters never exceeds the pending cap
do
  local st = P.NewResponder()
  local accepted = 0
  for i = 1, 50 do
    if P.OnRequest(st, "R" .. i, { reqId = "x" .. i, cursorT = i, cursorKey = "", target = "" }, 10, "Me", 3) then
      accepted = accepted + 1
    end
  end
  check("flood capped at 3", accepted == P.RESPONDER_MAX_PENDING and P.PendingCount(st) == 3)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
