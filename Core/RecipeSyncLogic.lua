-- Versioned recipe-cache relay decisions (no WoW APIs).
-- Catalog identity toward legacy PROFR remains (epoch, rev) only.
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local Logic = {}
GR.RecipeSyncLogic = Logic

local MAX_IDS = 500
local MAX_ID = 2147483647
local MAX_VER = 9007199254740991 -- 2^53-1

local function FiniteInt(n, minV, maxV)
  n = tonumber(n)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = math.floor(n)
  if minV and n < minV then return nil end
  if maxV and n > maxV then return nil end
  return n
end

function Logic.Fingerprint(ids)
  local canon, why = Logic.CanonicalIds(ids)
  if not canon then return nil, why end
  -- Adler-32 + count + payload length (not a security hash).
  local a, b = 1, 0
  local MOD = 65521
  local payload = table.concat(canon, "+")
  for j = 1, #payload do
    a = (a + payload:byte(j)) % MOD
    b = (b + a) % MOD
  end
  local sum = (b * 65536 + a) % 4294967296
  return string.format("%08x:%d:%d", sum, #canon, #payload)
end

function Logic.CanonicalIds(ids)
  if type(ids) ~= "table" then return nil, "type" end
  local seen, out = {}, {}
  for i = 1, #ids do
    local id = FiniteInt(ids[i], 1, MAX_ID)
    if not id then return nil, "bad_id" end
    if not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  table.sort(out)
  if #out > MAX_IDS then return nil, "too_many" end
  return out
end

-- Catalog version compare: epoch then rev (legacy PROFR).
function Logic.CompareVersion(a, b)
  local ae = FiniteInt(a and a.epoch, 0, MAX_VER) or 0
  local be = FiniteInt(b and b.epoch, 0, MAX_VER) or 0
  if ae ~= be then return ae < be and -1 or 1 end
  local ar = FiniteInt(a and a.rev, 0, MAX_VER) or 0
  local br = FiniteInt(b and b.rev, 0, MAX_VER) or 0
  if ar == br then return 0 end
  return ar < br and -1 or 1
end

function Logic.ValidateRecord(record)
  if type(record) ~= "table" then return nil, "type" end
  local kind = record.kind or "catalog"
  if kind ~= "catalog" and kind ~= "profile" and kind ~= "legacy" then
    return nil, "kind"
  end
  local owner = tostring(record.owner or "")
  if owner == "" then return nil, "owner" end
  local epoch = FiniteInt(record.epoch, 0, MAX_VER)
  local rev = FiniteInt(record.rev, 0, MAX_VER)
  if not epoch or not rev then return nil, "version" end
  local ids, why = Logic.CanonicalIds(record.ids or {})
  if not ids then return nil, why end
  return {
    kind = kind,
    owner = owner,
    profKey = record.profKey and tostring(record.profKey) or nil,
    epoch = epoch,
    rev = rev,
    ids = ids,
    fingerprint = Logic.Fingerprint(ids),
    count = #ids,
  }
end

-- context: { ownerIsSelf, sourceKind = "relay"|"direct"|"self" }
function Logic.Decide(current, incoming, context)
  context = context or {}
  local inc, why = Logic.ValidateRecord(incoming)
  if not inc then return "reject", why end
  if context.ownerIsSelf and context.sourceKind == "relay" then
    return "reject", "self_relay"
  end
  if not current then return "accept", "missing" end
  local cur = Logic.ValidateRecord(current)
  if not cur then return "accept", "bad_current" end
  local cmp = Logic.CompareVersion(cur, inc)
  if cmp > 0 then return "reject", "older" end
  if cmp < 0 then return "accept", "newer" end
  if cur.fingerprint == inc.fingerprint then return "same", "equal" end
  return "conflict", "same_version_diff_content"
end

-- Bump catalog epoch for unlearn/relearn; never decrease. Rev may reset under new epoch.
function Logic.BumpCatalogEpoch(prevEpoch, prevRev)
  local e = FiniteInt(prevEpoch, 0, MAX_VER) or 0
  local r = FiniteInt(prevRev, 0, MAX_VER) or 0
  return e + 1, 1, e, r
end

function Logic.RecordKey(record)
  local r = Logic.ValidateRecord(record)
  if not r then return nil end
  return string.format("%s|%s|%s", r.kind, r.owner, tostring(r.profKey or ""))
end

return Logic
