-- Recipe knowledge scan + guild share (Forever C_TradeSkillUI).
-- Documented APIs: GetProfessionSpells, GetRecipeInfo, GetRecipeSchematic, OpenTradeSkill.
-- No GetAllRecipeIDs on Forever dumps. Scan completeness client-confirmed only with open
-- trade skill + successful GetProfessionSpells. Do not OpenTradeSkill unsolicited.
local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local ProfRecipes = GR:NewModule("ProfRecipes")

-- PROFR knowledge wire: v2 adds owner epoch. Decode still accepts legacy v1 (epoch=0).
-- PROFRQ request wire stays version 1 (Comm rejects other request vers).
local PROFR_WIRE_VER = 2
local PROFR_WIRE_VER_LEGACY = 1
local PROFRQ_WIRE_VER = 1
local WIRE_VER = PROFR_WIRE_VER -- export alias for tests / diagnostics
local FLAG_COMPLETE = 1
local MAX_RECIPES = 500
local MAX_RECIPE_ID = 2147483647
local MAX_QTY = 999
local PROFRQ_SEND_CD = 30
local PROFRQ_REPLY_CD = 15
local PROFRMQ_SEND_CD = 20
local PROFRMQ_REPLY_CD = 12
local MAX_META_REQ_IDS = 24
local MAX_META_NAME = 64
local MAX_META_REAGENTS = 12
local META_WIRE_VER = 1
local CAT_WIRE_VER = 1
local META_MAX_ATTEMPTS = 3
local META_BUDGET_SEC = 90
-- Must fit 3 attempts inside META_BUDGET_SEC (spacing ≈ expire, with send CD 20).
local META_PENDING_EXPIRE = 25
local CHAT_SOFT_LIMIT = 240
local REFRESH_MIN_COLLECT = 6
local REFRESH_QUIET = 2.5
local REFRESH_MAX = 14
local REFRESH_SUMMARY_HOLD = 8
local SCAN_INITIAL_DELAY = 0.5
local SCAN_RETRY_DELAY = 0.8
local SCAN_MAX_EXTRA = 2
local INDEX_CACHE = nil
local INDEX_CACHE_SCOPE = nil
local INDEX_CACHE_GEN = 0
local lastMetaReqSend = 0
local lastMetaReqReply = 0
local pendingMetaReq = {} -- id -> expireAt
local metaQueue = {} -- ordered recipe IDs awaiting peer request
local metaQueueSet = {} -- id -> true
local metaAttempt = {} -- id -> { n = attemptsSent, firstSentAt = number|nil }
-- Independent category request queue (PROFRCQ); timers start on send-ack.
local lastCatReqSend = 0
local lastCatReqReply = 0
local pendingCatReq = {}
local catQueue = {}
local catQueueSet = {}
local catAttempt = {}
local catGiveUp = {}
local catDrainGen = 0
local catDrainScheduled = false
local catInFlightOp = nil
local replyPolicy = GR.MetaReplyPolicy and GR.MetaReplyPolicy.New() or nil
local replyPolicyGen = 0
local deferredCatIds = {} -- ids waiting for reply CD
local catReplyOpIds = {} -- operationId -> true (queued category replies)
local metaGiveUp = {} -- id -> true (session)
local metaDrainGen = 0
local metaDrainScheduled = false
local metaInFlightOp = nil -- one logical PROFRMQ while waiting send-ack
local recipeRefreshBusyUntil = 0
local recipeRefreshWhy = nil
local recipeRefreshGen = 0
local recipeRefreshSession = nil -- active settle session
local recipeRefreshSummary = nil -- sticky UI summary after settle
local scanOps = {} -- profKey -> { gen, triesLeft, open }
local pendingLearn = {} -- recipeId -> profKey or true
local pendingLearnGen = 0

local GATHERING_KEYS = {
  herb = true,
  mine = true,
  skin = true,
  fish = true,
  arch = true,
}

local lastReqSend = 0
local lastReqReply = 0
local lastSentFp = {} -- profKey -> content fingerprint (excludes scanAt)

local function ProfMod()
  return GR:GetModule("Professions")
end

local function Cache()
  local scope = U.GetScopeDB()
  return scope and scope.prof.cache or {}
end

local function EnsureMetaDB()
  if not GR.db then return nil end
  GR.db.prof = GR.db.prof or {}
  GR.db.prof.recipeMeta = GR.db.prof.recipeMeta or {}
  return GR.db.prof.recipeMeta
end

function ProfRecipes.IsGathering(key)
  return key ~= nil and GATHERING_KEYS[key] == true
end

function ProfRecipes.ClampQty(n)
  n = math.floor(tonumber(n) or 0)
  if n < 1 then return 1 end
  if n > MAX_QTY then return MAX_QTY end
  return n
end

-- Fixed output: crafts = ceil(desired / qtyPer), yield = crafts * qtyPer.
-- Variable/unknown: treat desired as craft count; yield range if min~=max.
function ProfRecipes.ComputeCrafts(desired, qtyMin, qtyMax)
  desired = ProfRecipes.ClampQty(desired)
  qtyMin = tonumber(qtyMin)
  qtyMax = tonumber(qtyMax)
  if qtyMin and qtyMax and qtyMin > 0 and qtyMin == qtyMax then
    local crafts = math.ceil(desired / qtyMin)
    if crafts < 1 then crafts = 1 end
    if crafts > MAX_QTY then crafts = MAX_QTY end
    return {
      mode = "fixed",
      desired = desired,
      crafts = crafts,
      qtyPer = qtyMin,
      yieldMin = crafts * qtyMin,
      yieldMax = crafts * qtyMin,
    }
  end
  local crafts = desired
  local yMin = (qtyMin and qtyMin > 0) and (crafts * qtyMin) or nil
  local yMax = (qtyMax and qtyMax > 0) and (crafts * qtyMax) or yMin
  return {
    mode = (qtyMin and qtyMax and qtyMin > 0) and "range" or "crafts",
    desired = desired,
    crafts = crafts,
    qtyPer = nil,
    yieldMin = yMin,
    yieldMax = yMax,
  }
end

function ProfRecipes.IdsEqual(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  if #a ~= #b then return false end
  for i = 1, #a do
    if tonumber(a[i]) ~= tonumber(b[i]) then return false end
  end
  return true
end

local function SortIds(ids)
  local out = {}
  for i = 1, #(ids or {}) do
    local id = tonumber(ids[i])
    if id and id > 0 and id <= MAX_RECIPE_ID then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  -- dedupe
  local dedup = {}
  local prev
  for i = 1, #out do
    if out[i] ~= prev then
      dedup[#dedup + 1] = out[i]
      prev = out[i]
    end
  end
  return dedup
end

-- Owner generation for PROFR. Survives content rev resets after SV wipe
-- because a wiped DB gets a new WallTime epoch (usually higher).
function ProfRecipes.EnsureOwnerEpoch()
  if not GR.db then return 1 end
  GR.db.prof = GR.db.prof or {}
  local e = tonumber(GR.db.prof.recipeEpoch)
  if not e or e < 1 then
    e = math.floor(tonumber(U.WallTime()) or 0)
    if e < 1 then e = 1 end
    GR.db.prof.recipeEpoch = e
  end
  return e
end

function ProfRecipes.GetOwnerEpoch()
  if not GR.db or not GR.db.prof then return 0 end
  return tonumber(GR.db.prof.recipeEpoch) or 0
end

-- Persisted last published (epoch,rev) per owner/prof so unlearn/relearn cannot
-- republish a weaker PROFR version than peers already hold. Lives under
-- scope.prof.recipeSync.catalogVersions (additive migration via EnsureScopeTable).
local function CatalogEpochBag()
  if not GR.db or not U.GetScopeDB then return nil end
  local scope = U.GetScopeDB()
  if not scope or not scope.prof or not scope.prof.recipeSync then return nil end
  local bag = scope.prof.recipeSync.catalogVersions
  if type(bag) ~= "table" then
    bag = {}
    scope.prof.recipeSync.catalogVersions = bag
  end
  return bag
end

function ProfRecipes.RememberCatalogEpoch(owner, profKey, epoch, rev)
  owner = U.NormalizeName(owner)
  if not owner or type(profKey) ~= "string" or profKey == "" then return end
  local bag = CatalogEpochBag()
  if not bag then return end
  bag[owner] = bag[owner] or {}
  local prev = bag[owner][profKey]
  local pe, pr = 0, 0
  if prev then
    pe = tonumber(prev.epoch) or 0
    pr = tonumber(prev.rev) or 0
  end
  epoch = tonumber(epoch) or 0
  rev = tonumber(rev) or 0
  if epoch > pe or (epoch == pe and rev > pr) then
    bag[owner][profKey] = { epoch = epoch, rev = rev }
  end
end

function ProfRecipes.BumpCatalogEpochForUnlearn(owner, profKey, prevRec)
  local Logic = GR.RecipeSyncLogic
  local e0 = prevRec and tonumber(prevRec.epoch) or 0
  local r0 = prevRec and tonumber(prevRec.rev) or 0
  local remembered = CatalogEpochBag()
  remembered = remembered and remembered[U.NormalizeName(owner) or ""]
  remembered = remembered and remembered[profKey]
  if remembered then
    e0 = math.max(e0, tonumber(remembered.epoch) or 0)
    r0 = math.max(r0, tonumber(remembered.rev) or 0)
  end
  local e1, r1 = 0, 1
  if Logic and Logic.BumpCatalogEpoch then
    e1, r1 = Logic.BumpCatalogEpoch(e0, r0)
  else
    e1, r1 = e0 + 1, 1
  end
  ProfRecipes.RememberCatalogEpoch(owner, profKey, e1, r1)
  return e1, r1
end

-- Drop recipe ownership for professions no longer on a confirmed non-empty list.
-- Empty/missing list does not prove unlearning (incomplete broadcast).
function ProfRecipes.PruneRecipesToProfessionList(recipes, list, owner)
  if type(recipes) ~= "table" then return recipes end
  if type(list) ~= "table" or #list == 0 then return recipes end
  local keep = {}
  for i = 1, #list do
    local p = list[i]
    local key = p and p.key
    if type(key) == "string" and key ~= "" then
      keep[key] = true
    end
  end
  if not next(keep) then return recipes end
  local out = {}
  local removed = false
  for key, rec in pairs(recipes) do
    if keep[key] then
      out[key] = rec
    else
      removed = true
      if owner then
        ProfRecipes.BumpCatalogEpochForUnlearn(owner, key, rec)
      end
    end
  end
  if removed then
    ProfRecipes.InvalidateGuildRecipeIndex()
  end
  return out
end

local function ProfessionKeysFromList(list)
  local keys = {}
  if type(list) ~= "table" then return keys end
  for i = 1, #list do
    local key = list[i] and list[i].key
    if type(key) == "string" and key ~= "" then
      keys[key] = true
    end
  end
  return keys
end

local function CurrentScopeKey()
  return U.GuildScopeKey() or ((U.RealmKey and U.RealmKey() or "Unknown") .. "::__none__")
end

-- epoch optional; defaults to EnsureOwnerEpoch().
function ProfRecipes.Encode(profKey, rev, scanAt, complete, ids, epoch)
  profKey = tostring(profKey or ""):gsub("[^%w_]", "")
  if profKey == "" then return nil end
  ids = SortIds(ids)
  if #ids > MAX_RECIPES then return nil end
  rev = math.floor(tonumber(rev) or 1)
  if rev < 1 then rev = 1 end
  scanAt = math.floor(tonumber(scanAt) or 0)
  if scanAt < 0 then scanAt = 0 end
  epoch = math.floor(tonumber(epoch) or ProfRecipes.EnsureOwnerEpoch() or 0)
  if epoch < 0 then epoch = 0 end
  local flags = complete and FLAG_COMPLETE or 0
  local parts = {}
  for i = 1, #ids do
    parts[i] = tostring(ids[i])
  end
  -- v2: ver|profKey|epoch|rev|scanAt|flags|count|ids
  return string.format(
    "%d|%s|%d|%d|%d|%d|%d|%s",
    PROFR_WIRE_VER,
    profKey,
    epoch,
    rev,
    scanAt,
    flags,
    #ids,
    table.concat(parts, "+")
  )
end

function ProfRecipes.Decode(rest)
  rest = tostring(rest or ""):gsub("[%c]", "")
  local verNum = tonumber(rest:match("^(%d+)"))
  local ver, profKey, epoch, rev, scanAt, flags, count, idPart
  if verNum == PROFR_WIRE_VER then
    ver, profKey, epoch, rev, scanAt, flags, count, idPart =
      rest:match("^(%d+)|([%w_]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    epoch = tonumber(epoch)
  elseif verNum == PROFR_WIRE_VER_LEGACY then
    ver, profKey, rev, scanAt, flags, count, idPart =
      rest:match("^(%d+)|([%w_]+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    epoch = 0
  else
    return nil, "ver"
  end
  if not ver then
    return nil, "format"
  end
  ver = tonumber(ver)
  rev = tonumber(rev)
  scanAt = tonumber(scanAt)
  flags = tonumber(flags) or 0
  count = tonumber(count) or -1
  if not rev or rev < 1 or not scanAt or scanAt < 0 then
    return nil, "fields"
  end
  if not epoch or epoch < 0 then
    epoch = 0
  end
  local ids = {}
  if idPart and idPart ~= "" then
    for piece in string.gmatch(idPart, "([^+]+)") do
      local id = tonumber(piece)
      if not id or id < 1 or id > MAX_RECIPE_ID or id ~= math.floor(id) then
        return nil, "bad_id"
      end
      ids[#ids + 1] = id
      if #ids > MAX_RECIPES then
        return nil, "too_many"
      end
    end
  end
  ids = SortIds(ids)
  if count ~= #ids then
    return nil, "count"
  end
  -- FLAG_COMPLETE is bit0; avoid depending on bit.* for LuaJIT tests.
  local complete = (flags % 2) == 1
  if not complete then
    return nil, "incomplete"
  end
  return {
    ver = ver,
    profKey = profKey,
    epoch = epoch,
    rev = rev,
    scanAt = scanAt,
    complete = true,
    ids = ids,
  }
end

function ProfRecipes.GetEntry(playerName, profKey)
  if not playerName or not profKey then return nil end
  local entry = Cache()[U.NormalizeName(playerName)]
  if not entry or type(entry.recipes) ~= "table" then return nil end
  return entry.recipes[profKey]
end

function ProfRecipes.GetStatus(playerName, profKey)
  if ProfRecipes.IsGathering(profKey) then
    return "gathering"
  end
  local rec = ProfRecipes.GetEntry(playerName, profKey)
  if not rec then
    return "none"
  end
  -- Failed/partial refresh must stay visible even when a prior confirmed list is kept.
  if rec.partialSeenAt then
    return "partial"
  end
  if rec.complete then
    if not rec.ids or #rec.ids == 0 then
      return "empty"
    end
    return "complete"
  end
  return "partial"
end

function ProfRecipes.GetMeta(recipeId)
  local meta = EnsureMetaDB()
  if not meta then return nil end
  return meta[tonumber(recipeId)]
end

local function PickMetaField(new, old)
  if new == nil then return old end
  if type(new) == "string" and new == "" then return old end
  if type(new) == "table" and next(new) == nil and type(old) == "table" and next(old) ~= nil then
    return old
  end
  return new
end

function ProfRecipes.StoreMeta(recipeId, info)
  local meta = EnsureMetaDB()
  if not meta or not recipeId or type(info) ~= "table" then return end
  recipeId = tonumber(recipeId)
  if not recipeId then return end
  local prev = meta[recipeId] or {}
  local reagents = info.reagents
  if type(reagents) == "table" and #reagents == 0 and type(prev.reagents) == "table" and #prev.reagents > 0
      and info.reagentsResolved ~= true then
    reagents = prev.reagents
  elseif reagents == nil then
    reagents = prev.reagents
  end
  local reagentsResolved = prev.reagentsResolved == true
  if info.reagentsResolved == true then
    reagentsResolved = true
  elseif info.reagentsResolved == false then
    -- explicit false only if we never confirmed before
    if not reagentsResolved then
      reagentsResolved = false
    end
  end
  -- Non-empty reagent list from any source confirms materials.
  if type(reagents) == "table" and #reagents > 0 then
    reagentsResolved = true
  end
  local categoryId = info.categoryId
  if categoryId ~= nil then
    categoryId = tonumber(categoryId)
    if not categoryId or categoryId <= 0 then categoryId = nil end
  else
    categoryId = prev.categoryId
  end
  meta[recipeId] = {
    name = PickMetaField(info.name, prev.name),
    icon = PickMetaField(info.icon, prev.icon),
    qtyMin = info.qtyMin ~= nil and info.qtyMin or prev.qtyMin,
    qtyMax = info.qtyMax ~= nil and info.qtyMax or prev.qtyMax,
    outputItemID = info.outputItemID ~= nil and info.outputItemID or prev.outputItemID,
    recipeType = PickMetaField(info.recipeType, prev.recipeType),
    reagents = reagents,
    reagentsResolved = reagentsResolved and true or nil,
    hyperlink = PickMetaField(info.hyperlink, prev.hyperlink),
    isEnchant = info.isEnchant ~= nil and info.isEnchant or prev.isEnchant,
    locale = PickMetaField(info.locale, prev.locale),
    categoryId = categoryId,
    categoryName = PickMetaField(info.categoryName, prev.categoryName),
  }
end

-- Local completeness: name + confirmed reagents (empty OK only with reagentsResolved).
function ProfRecipes.IsMetaComplete(meta)
  if type(meta) ~= "table" then return false end
  if not meta.name or meta.name == "" then return false end
  if meta.reagentsResolved ~= true then return false end
  return true
end

-- Content fingerprint for send dedup (excludes scanAt).
function ProfRecipes.ContentFingerprint(profKey, ids, complete, epoch)
  ids = SortIds(ids or {})
  local parts = {}
  for i = 1, #ids do parts[i] = tostring(ids[i]) end
  return string.format(
    "%s|%d|%s|%s",
    tostring(profKey or ""),
    complete and 1 or 0,
    tostring(tonumber(epoch) or 0),
    table.concat(parts, "+")
  )
end

local function SkillForPlayer(playerName, profKey)
  local entry = Cache()[U.NormalizeName(playerName)]
  if not entry or type(entry.list) ~= "table" then return nil, nil end
  for i = 1, #entry.list do
    local p = entry.list[i]
    if p and p.key == profKey then
      return p.skill, p.name
    end
  end
  return nil, nil
end

function ProfRecipes.GetSkill(playerName, profKey)
  return SkillForPlayer(playerName, profKey)
end

-- Bag count via GetItemCount / C_Item when present (Forever/Classic).
-- Returns number on success. nil only when no counting API works (unknown — not zero).
-- Successful API with non-number → 0 (item absent / uncached), not "?".
function ProfRecipes.GetBagCount(itemID)
  itemID = tonumber(itemID)
  if not itemID or itemID <= 0 then return nil end

  local function normalize(n)
    if type(n) ~= "number" then return nil end
    if n < 0 then return 0 end
    return n
  end

  local anyApi = false
  local anyOk = false

  local function tryCount(fn, ...)
    if type(fn) ~= "function" then return nil end
    anyApi = true
    local ok, n = pcall(fn, ...)
    if ok then
      anyOk = true
      return normalize(n)
    end
    return nil
  end

  local fn = _G.GetItemCount
  if type(fn) == "function" then
    -- Forever/Classic: numeric id; some builds want includeBank; some accept item:id.
    local v = tryCount(fn, itemID)
    if v ~= nil then return v end
    v = tryCount(fn, itemID, false)
    if v ~= nil then return v end
    v = tryCount(fn, "item:" .. tostring(itemID))
    if v ~= nil then return v end
  end

  local cItem = _G.C_Item
  if type(cItem) == "table" and type(cItem.GetItemCount) == "function" then
    local v = tryCount(cItem.GetItemCount, itemID)
    if v ~= nil then return v end
    v = tryCount(cItem.GetItemCount, itemID, false)
    if v ~= nil then return v end
  end

  -- API answered but without a number → 0 (not in bags), not "?".
  if anyOk then return 0 end
  -- No usable counter, or every call errored.
  return nil
end

-- Resolve display name for an item. Calls GetItemInfo even when uncached so the
-- client queues data; GET_ITEM_INFO_RECEIVED can refresh the UI afterward.
-- knownName: optional previously stored reagent.name from recipeMeta.
function ProfRecipes.ResolveItemName(itemID, knownName)
  itemID = tonumber(itemID)
  if knownName and knownName ~= "" then
    return knownName, true
  end
  if not itemID or itemID <= 0 then
    return nil, false
  end
  local cItem = _G.C_Item
  if type(cItem) == "table" and type(cItem.GetItemNameByID) == "function" then
    local ok, name = pcall(cItem.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then
      return name, true
    end
  end
  if _G.GetItemInfo then
    -- Always call: uncached returns nil but queues GET_ITEM_INFO_RECEIVED.
    local ok, name = pcall(_G.GetItemInfo, itemID)
    if ok and type(name) == "string" and name ~= "" then
      return name, true
    end
  end
  return nil, false
end

-- Persist resolved reagent names into recipeMeta so later opens skip placeholders.
function ProfRecipes.CacheReagentName(recipeId, itemID, name)
  recipeId = tonumber(recipeId)
  itemID = tonumber(itemID)
  if not recipeId or not itemID or not name or name == "" then return end
  local meta = ProfRecipes.GetMeta(recipeId)
  if not meta or type(meta.reagents) ~= "table" then return end
  local changed = false
  local reagents = {}
  for i = 1, #meta.reagents do
    local r = meta.reagents[i]
    local copy = {
      itemID = r and r.itemID,
      qty = r and r.qty,
      name = r and r.name,
    }
    if tonumber(copy.itemID) == itemID and (not copy.name or copy.name == "") then
      copy.name = name
      changed = true
    end
    reagents[i] = copy
  end
  if changed then
    ProfRecipes.StoreMeta(recipeId, { reagents = reagents })
  end
end

-- need/bag/missing rows for UI + short missing summary.
-- reagents: { { itemID=, qty=, name?= }, ... }; crafts = craft count multiplier.
-- bag nil = unknown inventory (never treat as 0 for "all mats present").
-- Returns rows, missingTotal, firstMissingName, firstMissingQty, allKnown, anyUnknown
function ProfRecipes.ComputeMaterialRows(reagents, crafts, getCountFn)
  crafts = math.max(1, math.floor(tonumber(crafts) or 1))
  getCountFn = getCountFn or ProfRecipes.GetBagCount
  local rows = {}
  local missingTotal = 0
  local firstMissingName
  local firstMissingQty
  local allKnown = true
  local anyUnknown = false
  if type(reagents) ~= "table" then
    return rows, missingTotal, nil, nil, true, false
  end
  for i = 1, #reagents do
    local r = reagents[i]
    local itemID = tonumber(r and r.itemID)
    local per = tonumber(r and r.qty)
    local needKnown = per ~= nil and per >= 0 and itemID ~= nil
    local need = needKnown and (per * crafts) or nil
    local bag = nil
    if itemID and getCountFn then
      local raw = getCountFn(itemID)
      if raw == nil then
        bag = nil
      else
        bag = tonumber(raw)
        if bag and bag < 0 then bag = 0 end
      end
    elseif not itemID then
      bag = nil
    end
    if not needKnown or bag == nil then
      allKnown = false
      anyUnknown = true
    end
    local missing = nil
    if needKnown and bag ~= nil then
      missing = need - bag
      if missing < 0 then missing = 0 end
    end
    local name = select(1, ProfRecipes.ResolveItemName(itemID, r and r.name))
    rows[#rows + 1] = {
      itemID = itemID,
      need = need,
      bag = bag,
      missing = missing,
      name = name,
      unknown = (not needKnown) or (bag == nil),
    }
    if missing and missing > 0 then
      missingTotal = missingTotal + missing
      if not firstMissingName then
        firstMissingName = name
        firstMissingQty = missing
      end
    end
  end
  return rows, missingTotal, firstMissingName, firstMissingQty, allKnown, anyUnknown
end

function ProfRecipes.InvalidateGuildRecipeIndex()
  INDEX_CACHE = nil
  INDEX_CACHE_SCOPE = nil
  INDEX_CACHE_GEN = INDEX_CACHE_GEN + 1
end

-- Search normalize: lowercase, collapse spaces, fold German umlauts (display unchanged).
function ProfRecipes.NormalizeSearchText(s)
  s = tostring(s or "")
  s = string.lower(s)
  -- German umlauts + ß (including already-upper folded via lower)
  s = s:gsub("ä", "ae"):gsub("ö", "oe"):gsub("ü", "ue"):gsub("ß", "ss")
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  return s
end

local function ParseItemIdFromQuery(token)
  if not token then return nil end
  local id = token:match("^item:(%d+)$")
  if id then return tonumber(id) end
  id = token:match("item:(%d+)")
  if id then return tonumber(id) end
  return nil
end

local function ParseRecipeIdFromQuery(token)
  if not token then return nil end
  local id = token:match("^recipe:(%d+)$")
  return id and tonumber(id) or nil
end

-- Match recipe against user query. Plain text (no Lua patterns). Multi-word = AND.
-- Returns matched, rank (0 exact name/id, 1 other).
function ProfRecipes.MatchRecipeQuery(query, opts)
  opts = opts or {}
  local recipeId = tonumber(opts.recipeId)
  local name = opts.name or ""
  local outputItemID = tonumber(opts.outputItemID)
  local outputName = opts.outputName or ""
  local q = ProfRecipes.NormalizeSearchText(query)
  if q == "" then
    return true, 1
  end

  local exactRecipe = ParseRecipeIdFromQuery(q)
  if exactRecipe then
    if recipeId and recipeId == exactRecipe then
      return true, 0
    end
    return false, 1
  end

  local exactItem = ParseItemIdFromQuery(q)
  if exactItem and not q:find(" ", 1, true) then
    if outputItemID and outputItemID == exactItem then
      return true, 0
    end
    return false, 1
  end

  local tokens = {}
  for tok in string.gmatch(q, "%S+") do
    tokens[#tokens + 1] = tok
  end
  if #tokens == 0 then
    return true, 1
  end

  local nameN = ProfRecipes.NormalizeSearchText(name)
  local outN = ProfRecipes.NormalizeSearchText(outputName)
  local idStr = recipeId and tostring(recipeId) or ""

  for i = 1, #tokens do
    local tok = tokens[i]
    local itemTok = ParseItemIdFromQuery(tok)
    local recipeTok = ParseRecipeIdFromQuery(tok)
    local ok = false
    if recipeTok and recipeId and recipeId == recipeTok then
      ok = true
    elseif itemTok and outputItemID and outputItemID == itemTok then
      ok = true
    elseif tok == idStr then
      ok = true
    elseif nameN:find(tok, 1, true) then
      ok = true
    elseif outN ~= "" and outN:find(tok, 1, true) then
      ok = true
    elseif tonumber(tok) and (idStr:find(tok, 1, true) or (outputItemID and tostring(outputItemID):find(tok, 1, true))) then
      ok = true
    end
    if not ok then
      return false, 1
    end
  end

  local rank = 1
  if nameN == q or idStr == q or (outputItemID and tostring(outputItemID) == q) then
    rank = 0
  end
  return true, rank
end

function ProfRecipes.CountCoverage()
  local cache = Cache()
  local chars, completeCats = {}, 0
  local nChars = 0
  for playerName, entry in pairs(cache) do
    if type(entry) == "table" and type(entry.recipes) == "table" then
      local has = false
      for profKey, rec in pairs(entry.recipes) do
        if type(rec) == "table" and type(rec.ids) == "table" and not ProfRecipes.IsGathering(profKey) then
          has = true
          if rec.complete and not rec.partialSeenAt then
            completeCats = completeCats + 1
          end
        end
      end
      if has and not chars[playerName] then
        chars[playerName] = true
        nChars = nChars + 1
      end
    end
  end
  return nChars, completeCats
end

-- Wall-clock date+time for scan age (not clock-only).
function ProfRecipes.FormatScanStamp(ts)
  ts = tonumber(ts)
  if not ts or ts <= 0 then return "?" end
  if date then
    return date("%Y-%m-%d %H:%M", ts)
  end
  return tostring(ts)
end

-- Snapshot key for request drafts (recipe/receiver/qty/mats).
function ProfRecipes.RequestDraftFingerprint(opts)
  opts = opts or {}
  local player = opts.player and U.NormalizeName(opts.player) or ""
  return table.concat({
    tostring(tonumber(opts.recipeId) or ""),
    tostring(player),
    tostring(opts.profKey or ""),
    tostring(ProfRecipes.ClampQty(opts.desired or 1)),
    (opts.matsBring ~= false) and "1" or "0",
  }, "|")
end

function ProfRecipes.PlayerKnowsRecipe(playerName, profKey, recipeId)
  local rec = ProfRecipes.GetEntry(playerName, profKey)
  if not rec or type(rec.ids) ~= "table" then return false end
  recipeId = tonumber(recipeId)
  for i = 1, #rec.ids do
    if tonumber(rec.ids[i]) == recipeId then return true end
  end
  return false
end

-- Guild-wide unique recipes from received/scanned cache only.
-- Returns sorted list: { recipeId, profKey, crafters = { names... } }
-- Cached until InvalidateGuildRecipeIndex or guild/scope change (not on every keystroke).
function ProfRecipes.BuildGuildRecipeIndex()
  local scopeKey = CurrentScopeKey()
  if INDEX_CACHE and INDEX_CACHE_SCOPE == scopeKey then
    return INDEX_CACHE
  end
  INDEX_CACHE = nil
  INDEX_CACHE_SCOPE = nil
  local cache = Cache()
  local byId = {}
  for playerName, entry in pairs(cache) do
    if type(entry) == "table" and type(entry.recipes) == "table" then
      local active = ProfessionKeysFromList(entry.list)
      local restrict = next(active) ~= nil
      for profKey, rec in pairs(entry.recipes) do
        if type(profKey) == "string"
            and not ProfRecipes.IsGathering(profKey)
            and (not restrict or active[profKey])
            and type(rec) == "table"
            and type(rec.ids) == "table" then
          for i = 1, #rec.ids do
            local id = tonumber(rec.ids[i])
            if id and id > 0 then
              local row = byId[id]
              if not row then
                row = { recipeId = id, profKey = profKey, crafters = {}, _seen = {} }
                byId[id] = row
              elseif not row.profKey then
                row.profKey = profKey
              end
              if not row._seen[playerName] then
                row._seen[playerName] = true
                row.crafters[#row.crafters + 1] = playerName
              end
            end
          end
        end
      end
    end
  end
  local out = {}
  for _, row in pairs(byId) do
    row._seen = nil
    table.sort(row.crafters, function(a, b)
      return string.lower(tostring(a)) < string.lower(tostring(b))
    end)
    out[#out + 1] = row
  end
  table.sort(out, function(a, b)
    local na = ProfRecipes.GetMeta(a.recipeId)
    local nb = ProfRecipes.GetMeta(b.recipeId)
    local sa = string.lower((na and na.name) or tostring(a.recipeId))
    local sb = string.lower((nb and nb.name) or tostring(b.recipeId))
    if sa ~= sb then return sa < sb end
    return (a.recipeId or 0) < (b.recipeId or 0)
  end)
  INDEX_CACHE = out
  INDEX_CACHE_SCOPE = scopeKey
  return out
end

local function SetSelfRecipes(profKey, ids, complete, scanAt)
  local me = U.NormalizeName(U.PlayerName())
  local cache = Cache()
  local entry = cache[me]
  if not entry then
    entry = { list = {}, classFile = U.PlayerClassFile(), time = U.WallTime() }
    cache[me] = entry
  end
  entry.recipes = entry.recipes or {}
  local prev = entry.recipes[profKey]
  ids = SortIds(ids)
  local nowScan = scanAt or U.WallTime()
  local rev = (prev and tonumber(prev.rev) or 0) + 1
  if prev and ProfRecipes.IdsEqual(prev.ids, ids) and prev.complete == complete and not prev.partialSeenAt then
    -- Same content: keep rev; only advance scanAt when newer/valid.
    rev = prev.rev or rev
    local prevScan = tonumber(prev.scanAt) or 0
    if nowScan < prevScan then
      nowScan = prevScan
    end
  end
  if not complete and prev and prev.complete and prev.ids then
    -- Incomplete scan must not wipe a confirmed list.
    entry.recipes[profKey] = {
      ids = prev.ids,
      rev = prev.rev or 1,
      scanAt = prev.scanAt,
      recvAt = prev.recvAt,
      complete = true,
      epoch = prev.epoch or ProfRecipes.EnsureOwnerEpoch(),
      partialSeenAt = nowScan,
    }
    ProfRecipes.InvalidateGuildRecipeIndex()
    return entry.recipes[profKey], false
  end
  local epoch = ProfRecipes.EnsureOwnerEpoch()
  local bag = CatalogEpochBag()
  local remembered = bag and bag[me] and bag[me][profKey]
  if remembered then
    local re = tonumber(remembered.epoch) or 0
    if re > epoch then
      epoch = re
      -- New content under a bumped unlearn epoch may restart rev at 1.
      if not (prev and ProfRecipes.IdsEqual(prev.ids, ids) and prev.complete == complete) then
        rev = math.max(rev, tonumber(remembered.rev) or 1)
        if re > (prev and tonumber(prev.epoch) or 0) then
          rev = math.max(1, tonumber(remembered.rev) or 1)
        end
      end
    end
  end
  entry.recipes[profKey] = {
    ids = ids,
    rev = rev,
    scanAt = nowScan,
    recvAt = U.WallTime(),
    complete = complete and true or false,
    epoch = epoch,
    -- Successful write clears prior partial marker.
  }
  ProfRecipes.RememberCatalogEpoch(me, profKey, epoch, rev)
  ProfRecipes.InvalidateGuildRecipeIndex()
  return entry.recipes[profKey], true
end

local function ReagentListFromSchematic(schematic)
  local out = {}
  if not schematic or type(schematic.reagentSlotSchematics) ~= "table" then
    return out
  end
  for i = 1, #schematic.reagentSlotSchematics do
    local slot = schematic.reagentSlotSchematics[i]
    if slot and slot.required ~= false then
      local qty = tonumber(slot.quantityRequired) or 0
      local reagents = slot.reagents
      local itemID
      if type(reagents) == "table" and reagents[1] then
        itemID = reagents[1].itemID
      end
      if itemID and qty > 0 then
        local name = select(1, ProfRecipes.ResolveItemName(itemID))
        out[#out + 1] = { itemID = itemID, qty = qty, name = name }
      end
    end
  end
  return out
end

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ValidIcon(icon)
  if icon == nil or icon == false or icon == 0 or icon == "" then return nil end
  if icon == QUESTION_ICON then return nil end
  return icon
end

local function ItemIconFromID(itemID)
  itemID = tonumber(itemID)
  if not itemID or itemID <= 0 then return nil end
  if GetItemIcon then
    local ok, tex = pcall(GetItemIcon, itemID)
    if ok then
      local v = ValidIcon(tex)
      if v then return v end
    end
  end
  if GetItemInfo then
    local ok, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, itemID)
    if ok then
      local v = ValidIcon(texture)
      if v then return v end
    end
  end
  return nil
end

-- Resolve display icon for a recipe (Forever: prefer output item / spell texture).
-- Returns icon, outputItemID (outputItemID may be nil).
function ProfRecipes.ResolveRecipeIcon(recipeId, recipeInfo, schematic)
  recipeId = tonumber(recipeId)
  local outputItemID = schematic and schematic.outputItemID
  local icon = ValidIcon(recipeInfo and recipeInfo.icon)
    or ValidIcon(schematic and schematic.icon)

  local api = _G.C_TradeSkillUI
  if (not icon or not outputItemID) and api and api.GetRecipeOutputItemData and recipeId then
    local ok, out = pcall(api.GetRecipeOutputItemData, recipeId)
    if ok and type(out) == "table" then
      if not outputItemID then outputItemID = out.itemID end
      icon = icon or ValidIcon(out.icon) or ItemIconFromID(out.itemID)
    end
  end

  if not icon and outputItemID then
    icon = ItemIconFromID(outputItemID)
  end

  if not icon and recipeId and GetSpellTexture then
    local ok, tex = pcall(GetSpellTexture, recipeId)
    if ok then icon = ValidIcon(tex) end
  end

  return icon or QUESTION_ICON, outputItemID
end

local function CaptureMeta(recipeId, recipeInfo, schematic, opts)
  opts = opts or {}
  local isEnchant = false
  if recipeInfo then
    isEnchant = recipeInfo.isEnchantingRecipe and true or false
  end
  local recipeType = schematic and schematic.recipeType
  if recipeType == 3 or recipeType == "Enchant" then
    isEnchant = true
  end
  local icon, outputItemID = ProfRecipes.ResolveRecipeIcon(recipeId, recipeInfo, schematic)
  if not outputItemID and schematic then
    outputItemID = schematic.outputItemID
  end
  local categoryId = recipeInfo and tonumber(recipeInfo.categoryID)
  if categoryId and categoryId <= 0 then categoryId = nil end
  -- Category name filled below once TS() is available; CaptureMeta runs after load.
  local categoryName = nil
  if categoryId then
    local api = _G.C_TradeSkillUI
    if api and type(api.GetCategoryInfo) == "function" then
      local ok, cinfo = pcall(api.GetCategoryInfo, categoryId)
      if ok and type(cinfo) == "table" and type(cinfo.name) == "string" and cinfo.name ~= "" then
        categoryName = cinfo.name
      end
    end
  end
  -- reagentsResolved only when schematic was successfully inspected (incl. confirmed empty).
  local reagentsResolved = opts.schematicOk == true
  ProfRecipes.StoreMeta(recipeId, {
    name = (schematic and schematic.name) or (recipeInfo and recipeInfo.name),
    icon = icon,
    qtyMin = schematic and schematic.quantityMin,
    qtyMax = schematic and schematic.quantityMax,
    outputItemID = outputItemID,
    recipeType = recipeType,
    reagents = ReagentListFromSchematic(schematic),
    reagentsResolved = reagentsResolved,
    hyperlink = recipeInfo and recipeInfo.hyperlink,
    isEnchant = isEnchant,
    categoryId = categoryId,
    categoryName = categoryName,
  })
end

local function TS()
  return _G.C_TradeSkillUI
end

local function LookupCategoryName(categoryId)
  categoryId = tonumber(categoryId)
  if not categoryId or categoryId <= 0 then return nil end
  local api = TS()
  if not api or type(api.GetCategoryInfo) ~= "function" then return nil end
  local ok, info = pcall(api.GetCategoryInfo, categoryId)
  if not ok or type(info) ~= "table" then return nil end
  local name = info.name
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- Iterate GetProfessions() slots without ipairs holes (nil primary slots).
local function EachProfessionIndex(fn)
  if not GetProfessions or not GetProfessionInfo then return end
  local a, b, c, d, e, f = GetProfessions()
  local slots = { a, b, c, d, e, f }
  for i = 1, 6 do
    if slots[i] then fn(slots[i]) end
  end
end

local function KeyFromProfessionIndex(idx)
  local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
  local prof = ProfMod()
  local key = prof and prof.KeyFromSkillName and prof.KeyFromSkillName(name)
  return key, name, skillLine
end

-- Resolve current open trade skill → profKey + professionID.
local function CurrentProfessionContext()
  local api = TS()
  if not api then return nil end
  local info
  if api.GetChildProfessionInfo then
    local ok, v = pcall(api.GetChildProfessionInfo)
    if ok and type(v) == "table" then info = v end
  end
  if (not info or not info.professionID or info.professionID == 0) and api.GetBaseProfessionInfo then
    local ok, v = pcall(api.GetBaseProfessionInfo)
    if ok and type(v) == "table" then info = v end
  end
  if not info then return nil end
  local name = info.professionName or info.parentProfessionName
  local prof = ProfMod()
  local key = prof and prof.KeyFromSkillName and prof.KeyFromSkillName(name)
  local professionID = info.professionID or info.parentProfessionID
  if not key or not professionID or professionID == 0 then return nil end
  return {
    profKey = key,
    professionID = professionID,
    skillLineID = info.parentProfessionID and info.professionID or nil,
    name = name,
  }
end

local function ContextFromSkillLineList(profKey)
  local api = TS()
  if not api or not api.GetAllProfessionTradeSkillLines or not api.GetProfessionInfoBySkillLineID then
    return nil
  end
  local okLines, lines = pcall(api.GetAllProfessionTradeSkillLines)
  if not okLines or type(lines) ~= "table" then return nil end
  local prof = ProfMod()
  for i = 1, #lines do
    local skillLine = tonumber(lines[i])
    if skillLine and skillLine > 0 then
      local ok, info = pcall(api.GetProfessionInfoBySkillLineID, skillLine)
      if ok and type(info) == "table" then
        local name = info.professionName or info.parentProfessionName
        local key = prof and prof.KeyFromSkillName and prof.KeyFromSkillName(name)
        if key == profKey then
          return {
            profKey = key,
            professionID = info.professionID or info.parentProfessionID,
            skillLineID = skillLine,
            name = name,
          }
        end
      end
    end
  end
  return nil
end

-- Build scan context for a profession key without requiring open UI.
local function ContextForKey(profKey)
  if not profKey then return nil end
  local open = CurrentProfessionContext()
  if open and open.profKey == profKey then
    return open
  end
  local api = TS()
  local found
  EachProfessionIndex(function(idx)
    if found then return end
    local key, name, skillLine = KeyFromProfessionIndex(idx)
    if key ~= profKey then return end
    local professionID
    if api and api.GetProfessionInfoBySkillLineID and skillLine and skillLine > 0 then
      local ok, info = pcall(api.GetProfessionInfoBySkillLineID, skillLine)
      if ok and type(info) == "table" then
        professionID = info.professionID or info.parentProfessionID
        if not skillLine or skillLine == 0 then
          -- keep skillLine from GetProfessionInfo when present
        end
      end
    end
    found = {
      profKey = key,
      professionID = professionID,
      skillLineID = skillLine,
      name = name,
    }
  end)
  if found and ((found.professionID and found.professionID > 0) or (found.skillLineID and found.skillLineID > 0)) then
    return found
  end
  return ContextFromSkillLineList(profKey) or found
end

-- Skip empty tables: Forever often returns {} from GetProfessionSpells.
local function FetchProfessionSpells(api, ctx)
  if not api or not api.GetProfessionSpells or not ctx then return nil end
  local attempts = {}
  if ctx.professionID and ctx.professionID > 0 then
    attempts[#attempts + 1] = { ctx.professionID, ctx.skillLineID }
    attempts[#attempts + 1] = { ctx.professionID }
  end
  if ctx.skillLineID and ctx.skillLineID > 0 then
    attempts[#attempts + 1] = { ctx.skillLineID }
  end
  for i = 1, #attempts do
    local a = attempts[i]
    local ok, spells = pcall(api.GetProfessionSpells, a[1], a[2])
    if ok and type(spells) == "table" and #spells > 0 then
      return spells
    end
  end
  return nil
end

local function SnapshotTradeSkillFilters(api)
  if not api then return nil end
  local snap = {}
  if api.GetShowLearned then
    local ok, v = pcall(api.GetShowLearned)
    if ok then snap.showLearned = v end
  end
  if api.GetShowUnlearned then
    local ok, v = pcall(api.GetShowUnlearned)
    if ok then snap.showUnlearned = v end
  end
  if api.GetOnlyShowMakeableRecipes then
    local ok, v = pcall(api.GetOnlyShowMakeableRecipes)
    if ok then snap.onlyMakeable = v end
  end
  if api.GetOnlyShowSkillUpRecipes then
    local ok, v = pcall(api.GetOnlyShowSkillUpRecipes)
    if ok then snap.onlySkillUp = v end
  end
  if api.GetRecipeItemNameFilter then
    local ok, v = pcall(api.GetRecipeItemNameFilter)
    if ok then snap.nameFilter = v end
  end
  return snap
end

local function RestoreTradeSkillFilters(api, snap)
  if not api or not snap then return false end
  local okAll = true
  local function restore(setter, value)
    if value == nil or not setter then return true end
    local ok = pcall(setter, value)
    if not ok then okAll = false end
    return ok
  end
  restore(api.SetShowLearned, snap.showLearned)
  restore(api.SetShowUnlearned, snap.showUnlearned)
  restore(api.SetOnlyShowMakeableRecipes, snap.onlyMakeable)
  restore(api.SetOnlyShowSkillUpRecipes, snap.onlySkillUp)
  restore(api.SetRecipeItemNameFilter, snap.nameFilter)
  return okAll
end

-- True when every filter we intend to change can be snapshotted for restore.
-- Setter without a readable getter is not mutated silently — refuse filtered complete.
local function CanSafelyMutateFilters(api, snap)
  if not api or not snap then return false end
  if api.SetShowLearned and (not api.GetShowLearned or snap.showLearned == nil) then return false end
  if api.SetShowUnlearned and (not api.GetShowUnlearned or snap.showUnlearned == nil) then return false end
  if api.SetOnlyShowMakeableRecipes and (not api.GetOnlyShowMakeableRecipes or snap.onlyMakeable == nil) then
    return false
  end
  if api.SetOnlyShowSkillUpRecipes and (not api.GetOnlyShowSkillUpRecipes or snap.onlySkillUp == nil) then
    return false
  end
  if api.SetRecipeItemNameFilter and (not api.GetRecipeItemNameFilter or snap.nameFilter == nil) then
    return false
  end
  return true
end

-- Align with Blizzard Forever Professions.SetDefaultFilters (feature-detect only).
-- Returns ok, why. On failure restores snap when possible and does not claim cleared.
local function ApplyScanFilters(api, snap)
  if not api then return false, "no_api" end
  if not CanSafelyMutateFilters(api, snap) then
    return false, "no_snap"
  end

  local function set(fn, ...)
    if not fn then return true end
    local ok = pcall(fn, ...)
    return ok
  end

  if not set(api.SetShowLearned, true) then
    RestoreTradeSkillFilters(api, snap)
    return false, "set_fail"
  end
  if not set(api.SetRecipeItemNameFilter, "") then
    RestoreTradeSkillFilters(api, snap)
    return false, "set_fail"
  end
  if not set(api.SetOnlyShowMakeableRecipes, false) then
    RestoreTradeSkillFilters(api, snap)
    return false, "set_fail"
  end
  if not set(api.SetOnlyShowSkillUpRecipes, false) then
    RestoreTradeSkillFilters(api, snap)
    return false, "set_fail"
  end
  if api.ClearRecipeCategoryFilter then
    if not set(api.ClearRecipeCategoryFilter) then
      RestoreTradeSkillFilters(api, snap)
      return false, "set_fail"
    end
  end

  -- Verify cleared state via getters when present.
  if api.GetShowLearned then
    local ok, v = pcall(api.GetShowLearned)
    if not ok or v ~= true then
      RestoreTradeSkillFilters(api, snap)
      return false, "verify_fail"
    end
  end
  if api.GetRecipeItemNameFilter then
    local ok, v = pcall(api.GetRecipeItemNameFilter)
    if not ok or (type(v) == "string" and v ~= "") then
      RestoreTradeSkillFilters(api, snap)
      return false, "verify_fail"
    end
  end
  if api.GetOnlyShowMakeableRecipes then
    local ok, v = pcall(api.GetOnlyShowMakeableRecipes)
    if not ok or v then
      RestoreTradeSkillFilters(api, snap)
      return false, "verify_fail"
    end
  end
  if api.GetOnlyShowSkillUpRecipes then
    local ok, v = pcall(api.GetOnlyShowSkillUpRecipes)
    if not ok or v then
      RestoreTradeSkillFilters(api, snap)
      return false, "verify_fail"
    end
  end
  return true, "ok"
end

-- Only positively confirmed learned recipes. Missing GetRecipeInfo / learned field
-- is unknown — never treated as learned. Returns ids, unknownCount.
local function CollectLearnedFromIds(api, recipeIds)
  local ids = {}
  local unknown = 0
  if type(recipeIds) ~= "table" then return ids, 0 end
  for i = 1, #recipeIds do
    local recipeId = tonumber(recipeIds[i])
    if recipeId and recipeId > 0 then
      local info
      local infoOk = false
      if api and api.GetRecipeInfo then
        local okInfo, ri = pcall(api.GetRecipeInfo, recipeId)
        if okInfo then
          infoOk = true
          info = ri
        end
      end
      if not infoOk or info == nil then
        unknown = unknown + 1
      elseif info.isDummyRecipe or info.isGatheringRecipe then
        -- skip non-craft entries
      elseif info.learned == true then
        ids[#ids + 1] = recipeId
        local schematic
        if api.GetRecipeSchematic then
          local okSch, sch = pcall(api.GetRecipeSchematic, recipeId, false)
          if okSch then schematic = sch end
        end
        CaptureMeta(recipeId, info, schematic)
      elseif info.learned == false then
        -- confirmed unlearned
      else
        -- learned field absent → unknown
        unknown = unknown + 1
      end
    end
  end
  return SortIds(ids), unknown
end

ProfRecipes.CollectLearnedFromIds = function(api, recipeIds)
  return CollectLearnedFromIds(api, recipeIds)
end

-- Forever Blizzard UI uses GetFilteredRecipeIDs when the profession window is open.
-- Second return true only when filters were safely cleared and verified.
local function FetchFilteredRecipeIDs(api)
  if not api or not api.GetFilteredRecipeIDs then return nil, false, "no_api" end
  local snap = SnapshotTradeSkillFilters(api)
  local okApply, whyApply = ApplyScanFilters(api, snap)
  if not okApply then
    return nil, false, whyApply or "filters_fail"
  end
  local ok, recipeIds = pcall(api.GetFilteredRecipeIDs)
  RestoreTradeSkillFilters(api, snap)
  if not ok or type(recipeIds) ~= "table" then
    return nil, false, "fetch_fail"
  end
  return recipeIds, true, "ok"
end

-- Decide whether an empty result may be stored as a confirmed complete list.
function ProfRecipes.ShouldAcceptEmptyComplete(opts)
  opts = opts or {}
  if opts.allowEmptyComplete == true then return true end
  if opts.windowOpen and opts.usedFiltered and opts.filtersCleared then
    return true
  end
  return false
end

-- Scan learned recipes for the currently open trade skill (or given ctx).
-- Returns ids, complete, why.
function ProfRecipes.ScanOpenTradeSkill(ctx)
  local api = TS()
  if not api then
    return nil, false, "no_api"
  end
  if not api.GetProfessionSpells and not api.GetFilteredRecipeIDs then
    return nil, false, "no_api"
  end
  ctx = ctx or CurrentProfessionContext()
  if not ctx then
    return nil, false, "no_ctx"
  end
  if ProfRecipes.IsGathering(ctx.profKey) then
    return {}, true, "gathering"
  end
  if (not ctx.professionID or ctx.professionID == 0) and (not ctx.skillLineID or ctx.skillLineID == 0) then
    return nil, false, "no_ctx"
  end

  local openNow = CurrentProfessionContext()
  local windowOpen = openNow and openNow.profKey == ctx.profKey
  local usedFiltered = false
  local filtersCleared = false
  local filtersFailed = false
  local rawIds

  if windowOpen and api.GetFilteredRecipeIDs then
    local recipeIds, okFiltered = FetchFilteredRecipeIDs(api)
    if okFiltered then
      usedFiltered = true
      filtersCleared = true
      rawIds = recipeIds
    else
      filtersFailed = true
    end
  end

  if not rawIds then
    rawIds = FetchProfessionSpells(api, ctx)
  end

  if not rawIds then
    return nil, false, filtersFailed and "filters_unverified" or "spells_fail"
  end

  local ids, unknown = CollectLearnedFromIds(api, rawIds)

  -- Missing recipe info must not produce a confirmed complete catalogue.
  if unknown and unknown > 0 then
    if #ids == 0 then
      return nil, false, "info_unknown"
    end
    return ids, false, "partial_unknown"
  end

  if filtersFailed then
    -- Unverified filter state: never replace a confirmed list with a subset.
    if #ids == 0 then
      return nil, false, "filters_unverified"
    end
    return ids, false, "filters_unverified"
  end

  if #ids == 0 then
    if ProfRecipes.ShouldAcceptEmptyComplete({
      windowOpen = windowOpen,
      usedFiltered = usedFiltered,
      filtersCleared = filtersCleared,
    }) then
      return ids, true, "ok_empty"
    end
    -- Do not fake a confirmed empty list while Alchemy UI clearly has recipes.
    return nil, false, "empty_suspect"
  end

  return ids, true, usedFiltered and "ok_filtered" or "ok"
end

local function ClearPendingLearnForCatalog(profKey, ids, complete)
  if not complete or not profKey then return end
  local have = {}
  for i = 1, #(ids or {}) do
    local id = tonumber(ids[i])
    if id then have[id] = true end
  end
  for id, key in pairs(pendingLearn) do
    if (key == true or key == profKey) and have[id] then
      pendingLearn[id] = nil
    end
  end
end

local function PendingLearnMissing(profKey, ids)
  local have = {}
  for i = 1, #(ids or {}) do
    local id = tonumber(ids[i])
    if id then have[id] = true end
  end
  for id, key in pairs(pendingLearn) do
    if (key == true or key == profKey) and not have[id] then
      return true
    end
  end
  return false
end

function ProfRecipes.NotePendingLearn(recipeId, profKey)
  recipeId = tonumber(recipeId)
  if not recipeId or recipeId <= 0 then return end
  pendingLearn[recipeId] = profKey or true
end

function ProfRecipes.HasPendingLearn(recipeId)
  recipeId = tonumber(recipeId)
  return recipeId and pendingLearn[recipeId] ~= nil
end

function ProfRecipes.IsConfirmedCompleteWhy(why)
  return why == "ok" or why == "ok_filtered" or why == "ok_empty" or why == "gathering"
end

function ProfRecipes:ApplyLocalScan(profKey, ids, complete, opts)
  if not profKey or ProfRecipes.IsGathering(profKey) then return end
  opts = opts or {}
  -- Never commit an empty "complete" list unless explicitly allowed (true empty after filtered clear).
  if complete and (not ids or #ids == 0) and not opts.allowEmptyComplete then
    complete = false
  end
  local prev = ProfRecipes.GetEntry(U.NormalizeName(U.PlayerName()), profKey)
  local prevComplete = prev and prev.complete and not prev.partialSeenAt
  local prevIds = prev and prev.ids
  local contentChanged = not prev
      or (prevComplete ~= (complete and true or false))
      or not ProfRecipes.IdsEqual(prevIds, ids or {})
  local firstCapture = complete and (not prevComplete)
  local entry = SetSelfRecipes(profKey, ids or {}, complete and true or false, U.WallTime())
  if complete then
    ClearPendingLearnForCatalog(profKey, ids or {}, true)
  end
  GR:SendMessage("PROF_RECIPES_CHANGED", U.NormalizeName(U.PlayerName()), profKey)
  if complete and ids and #ids > 0 and not opts.skipBroadcast then
    self:BroadcastProfession(profKey, false)
  end
  -- Chat confirm only on first complete capture or real content change (not every list event).
  -- Manual refresh with unchanged data is handled by ProfRecipePanel refresh messages.
  if complete and (firstCapture or contentChanged) then
    if ids and #ids > 0 then
      U.Print(string.format(U.L("PROF_RECIPE_CAPTURED"), #ids))
    elseif opts.allowEmptyComplete and (firstCapture or contentChanged) then
      U.Print(U.L("PROF_RECIPE_REFRESH_OK_EMPTY"))
    end
  end
  return entry, contentChanged, firstCapture
end

local function ApplyScanResult(self, profKey, ids, complete, why, opts)
  opts = opts or {}
  if ids == nil then return false, why, profKey, false end
  if complete and #ids == 0 and why ~= "gathering" and why ~= "ok_empty" then
    return false, "empty_suspect", profKey, false
  end
  self:ApplyLocalScan(profKey, ids, complete, {
    allowEmptyComplete = (why == "ok_empty" or why == "gathering"),
    skipBroadcast = opts.skipBroadcast,
    manualRefresh = opts.manualRefresh,
  })
  local confirmed = complete and ProfRecipes.IsConfirmedCompleteWhy(why)
  return true, why, profKey, confirmed
end

-- Scan currently open trade skill (event path).
function ProfRecipes:ScanAndStore(opts)
  local ctx = CurrentProfessionContext()
  if not ctx then return false, "no_ctx" end
  local ids, complete, why = ProfRecipes.ScanOpenTradeSkill(ctx)
  return ApplyScanResult(self, ctx.profKey, ids, complete, why, opts)
end

-- Scan a specific profession key (catalog refresh). Prefer open-window filtered list.
function ProfRecipes:ScanProfession(profKey, opts)
  if not profKey then return false, "no_key" end
  if ProfRecipes.IsGathering(profKey) then
    return false, "gathering"
  end
  local open = CurrentProfessionContext()
  local ctx
  if open and open.profKey == profKey then
    ctx = open
  else
    ctx = ContextForKey(profKey)
  end
  if not ctx then return false, "no_ctx" end
  if ctx.profKey ~= profKey then
    return false, "wrong_prof"
  end
  local ids, complete, why = ProfRecipes.ScanOpenTradeSkill(ctx)
  return ApplyScanResult(self, profKey, ids, complete, why, opts)
end

function ProfRecipes:BroadcastProfession(profKey, force)
  local db = GR.db
  if not db or not db.privacy.shareProfessions then return end
  if not IsInGuild or not IsInGuild() then return end
  if not profKey or ProfRecipes.IsGathering(profKey) then return end
  local me = U.NormalizeName(U.PlayerName())
  local rec = ProfRecipes.GetEntry(me, profKey)
  if not rec or not rec.complete then return end
  local epoch = tonumber(rec.epoch) or ProfRecipes.EnsureOwnerEpoch()
  local encoded = ProfRecipes.Encode(profKey, rec.rev, rec.scanAt, true, rec.ids, epoch)
  if not encoded then return end
  local fp = ProfRecipes.ContentFingerprint(profKey, rec.ids, true, epoch)
  if not force and lastSentFp[profKey] == fp then return false, "unchanged" end
  if Comm:Send("PROFR|" .. encoded, "data", "prof") then
    lastSentFp[profKey] = fp
    return true, "sent"
  end
  return false, "send_fail"
end

function ProfRecipes:ListCompleteProfessionKeys()
  local me = U.NormalizeName(U.PlayerName())
  local entry = Cache()[me]
  local out = {}
  if not entry or type(entry.recipes) ~= "table" then return out end
  local active = ProfessionKeysFromList(entry.list)
  local restrict = next(active) ~= nil
  local order = ProfMod() and ProfMod().ProfessionKeys and ProfMod().ProfessionKeys() or {}
  local seen = {}
  for i = 1, #order do
    local key = order[i]
    local rec = entry.recipes[key]
    if rec and rec.complete and not ProfRecipes.IsGathering(key)
        and (not restrict or active[key]) then
      out[#out + 1] = key
      seen[key] = true
    end
  end
  for key, rec in pairs(entry.recipes) do
    if not seen[key] and rec and rec.complete and not ProfRecipes.IsGathering(key)
        and (not restrict or active[key]) then
      out[#out + 1] = key
    end
  end
  return out
end

function ProfRecipes:BroadcastAll(force)
  local keys = self:ListCompleteProfessionKeys()
  for i = 1, #keys do
    self:BroadcastProfession(keys[i], force)
  end
  return #keys
end

-- Push each complete profession list with delay so Comm queue drains cleanly.
-- Returns number of professions scheduled.
function ProfRecipes:BroadcastAllStaggered(force, interval)
  local keys = self:ListCompleteProfessionKeys()
  if #keys == 0 then return 0 end
  interval = tonumber(interval) or 0.55
  if interval < 0.5 then interval = 0.5 end
  for i = 1, #keys do
    local key = keys[i]
    local delay = (i - 1) * interval
    if delay <= 0 then
      self:BroadcastProfession(key, force)
    else
      C_Timer.After(delay, function()
        if not ProfRecipes.enabled then return end
        ProfRecipes:BroadcastProfession(key, force)
      end)
    end
  end
  return #keys
end

function ProfRecipes:RequestAll(profKey, force)
  if not IsInGuild or not IsInGuild() then return false, "no_guild" end
  local now = U.Now()
  if not force and (now - lastReqSend) < PROFRQ_SEND_CD then
    return false, "cooldown"
  end
  lastReqSend = now
  -- PROFRQ wire version stays 1 (independent of PROFR knowledge wire).
  local body = tostring(PROFRQ_WIRE_VER) .. "|" .. (profKey and tostring(profKey) or "")
  local ok = Comm:Send("PROFRQ|" .. body, "ctrl", "sync")
  return ok and true or false, ok and "sent" or "send_fail"
end

function ProfRecipes:RequestProfession(profKey, force)
  return self:RequestAll(profKey, force)
end

-- User-clicked "Refresh recipes". Opens trade skill if needed for self.
-- Returns ok, why (for UI feedback).
function ProfRecipes:RefreshProfession(profKey, opts)
  opts = opts or {}
  if not profKey then return false, "no_key" end
  if ProfRecipes.IsGathering(profKey) then return false, "gathering" end

  -- Prefer explicit remote flag; never treat self as remote.
  local remote = opts.remote == true
  if opts.playerName and U.IsSelfName(opts.playerName) then
    remote = false
  end

  if remote then
    local ok, why = self:RequestProfession(profKey, true)
    return ok, why
  end

  local scanOpts = { skipBroadcast = true, manualRefresh = true }
  local ok, why, _, confirmed = self:ScanProfession(profKey, scanOpts)
  if ok then
    if why == "ok_empty" then
      return true, "ok_empty"
    end
    if confirmed and why ~= "ok_empty" then
      -- One send path for manual refresh (fingerprint-gated).
      self:BroadcastProfession(profKey, false)
    end
    return true, why
  end

  local function DelayedRescan(delay)
    C_Timer.After(delay or 0.8, function()
      if not ProfRecipes.enabled then return end
      local ok2, why2, _, conf2 = ProfRecipes:ScanProfession(profKey, scanOpts)
      if ok2 and conf2 and why2 ~= "ok_empty" then
        ProfRecipes:BroadcastProfession(profKey, false)
      end
      GR:SendMessage("PROF_RECIPE_REFRESH_DONE", profKey, ok2, why2 or why)
    end)
  end

  -- Window already open but scan empty/failed: wait a tick for filter list rebuild.
  if why == "empty_suspect" or why == "spells_fail" then
    local open = CurrentProfessionContext()
    if open and open.profKey == profKey then
      DelayedRescan(0.6)
      return true, "retrying"
    end
  end

  -- Solicited refresh: open profession window, then scan after list loads.
  if why == "no_ctx" or why == "spells_fail" or why == "no_api" or why == "empty_suspect" then
    local opened = self:TryOpenTradeSkillForKey(profKey)
    if not opened then
      if why == "empty_suspect" then
        return false, "empty_suspect"
      end
      return false, why == "no_api" and "no_api" or "open_fail"
    end
    DelayedRescan(0.8)
    return true, "opening"
  end
  return false, why
end

function ProfRecipes:OnRecipeUpdate(sender, data)
  if not data or not data.profKey or not data.complete then return end
  if ProfRecipes.IsGathering(data.profKey) then return end
  local cache = Cache()
  local entry = cache[sender]
  if not entry then
    entry = { list = {}, time = U.WallTime() }
    cache[sender] = entry
  end
  -- Confirmed non-empty profession list: reject ownership for dropped professions.
  local active = ProfessionKeysFromList(entry.list)
  if next(active) and not active[data.profKey] then
    return
  end
  entry.recipes = entry.recipes or {}
  local prev = entry.recipes[data.profKey]
  local incomingEpoch = tonumber(data.epoch) or 0
  if incomingEpoch < 0 then incomingEpoch = 0 end
  local prevEpoch = prev and tonumber(prev.epoch) or 0
  if prev and prev.complete and incomingEpoch < prevEpoch then
    return -- older owner generation
  end
  local newerEpoch = incomingEpoch > prevEpoch
  if prev and prev.complete and not newerEpoch and tonumber(prev.rev) and tonumber(data.rev)
      and data.rev < prev.rev then
    return -- stale revision within same generation
  end
  local incomingScan = tonumber(data.scanAt)
  if incomingScan and incomingScan < 0 then incomingScan = nil end
  if prev and prev.complete and not newerEpoch and ProfRecipes.IdsEqual(prev.ids, data.ids)
      and tonumber(prev.rev) == tonumber(data.rev) then
    -- Same content/rev/epoch: advance scanAt when newer; never roll it back.
    if incomingScan then
      local stored = tonumber(prev.scanAt) or 0
      if incomingScan > stored then
        prev.scanAt = incomingScan
      end
    end
    prev.epoch = prevEpoch
    prev.recvAt = U.WallTime()
    ProfRecipes.InvalidateGuildRecipeIndex()
    GR:SendMessage("PROF_RECIPES_CHANGED", sender, data.profKey)
    if ProfRecipes.EnsureMetaForIds then
      ProfRecipes.EnsureMetaForIds(data.ids, sender)
    end
    return
  end
  entry.recipes[data.profKey] = {
    ids = data.ids,
    rev = data.rev,
    scanAt = incomingScan or data.scanAt or 0,
    recvAt = U.WallTime(),
    complete = true,
    epoch = incomingEpoch,
  }
  ProfRecipes.InvalidateGuildRecipeIndex()
  GR:SendMessage("PROF_RECIPES_CHANGED", sender, data.profKey)
  if ProfRecipes.EnsureMetaForIds then
    ProfRecipes.EnsureMetaForIds(data.ids, sender)
  end
end

-- Build whisper/request text (no auto-send).
-- opts.L optional override for tests; defaults to U.L.
function ProfRecipes.BuildRequestText(opts)
  opts = opts or {}
  local L = opts.L or function(key) return U.L(key) end
  local qty = ProfRecipes.ClampQty(opts.desired or 1)
  local meta = opts.meta or {}
  local calc = ProfRecipes.ComputeCrafts(qty, meta.qtyMin, meta.qtyMax)
  local itemLabel = opts.link or meta.hyperlink or meta.name or opts.name or "?"
  local matsBring = opts.matsBring ~= false
  local matsPhrase
  if matsBring then
    matsPhrase = opts.matsBringPhrase or L("PROF_RECIPE_MATS_BRING")
  else
    matsPhrase = opts.matsOfferPhrase or L("PROF_RECIPE_MATS_OFFER")
  end

  local body
  if meta.isEnchant then
    body = string.format(L("PROF_RECIPE_REQ_CRAFTS"), calc.crafts, itemLabel, matsPhrase)
  elseif calc.mode == "fixed" then
    if calc.yieldMin ~= calc.desired then
      body = string.format(
        L("PROF_RECIPE_REQ_CRAFTS_YIELD"),
        calc.crafts, itemLabel, calc.yieldMin, matsPhrase
      )
    else
      body = string.format(L("PROF_RECIPE_REQ_FIXED"), calc.desired, itemLabel, matsPhrase)
    end
  elseif calc.mode == "range" and calc.yieldMin and calc.yieldMax then
    body = string.format(
      L("PROF_RECIPE_REQ_RANGE"),
      calc.crafts, itemLabel, calc.yieldMin, calc.yieldMax, matsPhrase
    )
  else
    body = string.format(L("PROF_RECIPE_REQ_CRAFTS"), calc.crafts, itemLabel, matsPhrase)
  end

  -- Soft trim without breaking |H links
  if #body > CHAT_SOFT_LIMIT then
    local linkStart, linkEnd = body:find("|H.-|h.-|h")
    if not (linkStart and linkEnd and linkEnd < CHAT_SOFT_LIMIT) then
      local nameOnly = meta.name or opts.name or "?"
      if calc.mode == "fixed" and calc.yieldMin == calc.desired then
        body = string.format(L("PROF_RECIPE_REQ_FIXED"), calc.desired, nameOnly, matsPhrase)
      else
        body = string.format(L("PROF_RECIPE_REQ_CRAFTS"), calc.crafts, nameOnly, matsPhrase)
      end
    end
    if #body > CHAT_SOFT_LIMIT then
      body = body:sub(1, CHAT_SOFT_LIMIT)
    end
  end
  return body, calc
end

function ProfRecipes:TryOpenTradeSkillForKey(profKey)
  local api = TS()
  if not api or not api.OpenTradeSkill then return false end
  local skillLine
  EachProfessionIndex(function(idx)
    if skillLine then return end
    local key, _, sl = KeyFromProfessionIndex(idx)
    if key == profKey and sl and sl > 0 then
      skillLine = sl
    end
  end)
  if not skillLine then
    local ctx = ContextFromSkillLineList(profKey)
    skillLine = ctx and ctx.skillLineID
  end
  if not skillLine or skillLine <= 0 then return false end
  local ok, result = pcall(api.OpenTradeSkill, skillLine)
  -- Some clients return nil on success; treat non-false as opened.
  return ok and result ~= false
end

local function AbortScanOps()
  for key, op in pairs(scanOps) do
    if op then op.gen = (op.gen or 0) + 1 end
    scanOps[key] = nil
  end
end

local function AbortRefreshSession()
  recipeRefreshGen = recipeRefreshGen + 1
  recipeRefreshSession = nil
  recipeRefreshBusyUntil = 0
  if recipeRefreshWhy == "requesting" then
    recipeRefreshWhy = nil
  end
end

local function AbortMetaDrain()
  metaDrainGen = metaDrainGen + 1
  metaDrainScheduled = false
  if metaInFlightOp and Comm and Comm.PurgeByOperation then
    Comm:PurgeByOperation(metaInFlightOp)
  end
  metaInFlightOp = nil
end

local function AbortCategoryDrain()
  catDrainGen = catDrainGen + 1
  catDrainScheduled = false
  if catInFlightOp and Comm and Comm.PurgeByOperation then
    Comm:PurgeByOperation(catInFlightOp)
  end
  catInFlightOp = nil
  for opId in pairs(catReplyOpIds) do
    if Comm and Comm.PurgeByOperation then Comm:PurgeByOperation(opId) end
  end
  wipe(catReplyOpIds)
  if replyPolicy and GR.MetaReplyPolicy then
    GR.MetaReplyPolicy.Reset(replyPolicy)
  end
  replyPolicyGen = replyPolicyGen + 1
  wipe(deferredCatIds)
end

function ProfRecipes.AbortAllBackgroundWork()
  AbortScanOps()
  AbortRefreshSession()
  AbortMetaDrain()
  AbortCategoryDrain()
  wipe(pendingMetaReq)
  wipe(metaQueue)
  wipe(metaQueueSet)
  wipe(metaAttempt)
  wipe(metaGiveUp)
  wipe(pendingCatReq)
  wipe(catQueue)
  wipe(catQueueSet)
  wipe(catAttempt)
  wipe(catGiveUp)
  wipe(pendingLearn)
end

local INCOMPLETE_SCAN_WHY = {
  empty_suspect = true,
  partial_unknown = true,
  info_unknown = true,
  spells_fail = true,
  filters_unverified = true,
}

local function ScanOpStillOpen(profKey)
  local open = CurrentProfessionContext()
  return open and open.profKey == profKey
end

local function FinishScanOpIfDone(profKey, gen, ok, why, ids, confirmed)
  local op = scanOps[profKey]
  if not op or op.gen ~= gen then return end
  local pendingMissing = PendingLearnMissing(profKey, ids)
  if confirmed and not pendingMissing then
    scanOps[profKey] = nil
    return
  end
  if not ScanOpStillOpen(profKey) then
    scanOps[profKey] = nil
    return
  end
  if (op.triesLeft or 0) <= 0 then
    scanOps[profKey] = nil
    return
  end
  -- Keep retrying for incomplete OR complete-but-missing-pending.
  if not ok or INCOMPLETE_SCAN_WHY[why] or (confirmed and pendingMissing) or not confirmed then
    op.triesLeft = op.triesLeft - 1
    local nextGen = gen
    C_Timer.After(SCAN_RETRY_DELAY, function()
      local cur = scanOps[profKey]
      if not ProfRecipes.enabled or not cur or cur.gen ~= nextGen then return end
      if not ScanOpStillOpen(profKey) then
        scanOps[profKey] = nil
        return
      end
      local ok2, why2, _, conf2 = ProfRecipes:ScanAndStore()
      local ctx = CurrentProfessionContext()
      local ids2 = nil
      if ctx and ctx.profKey == profKey then
        local rec = ProfRecipes.GetEntry(U.NormalizeName(U.PlayerName()), profKey)
        ids2 = rec and rec.ids
      end
      FinishScanOpIfDone(profKey, nextGen, ok2, why2, ids2, conf2)
    end)
    return
  end
  scanOps[profKey] = nil
end

function ProfRecipes:BeginScanOp(profKey, opts)
  opts = opts or {}
  if not profKey then return end
  local prev = scanOps[profKey]
  local gen = (prev and prev.gen or 0) + 1
  scanOps[profKey] = {
    gen = gen,
    triesLeft = opts.triesLeft or SCAN_MAX_EXTRA,
  }
  local delay = opts.delay or SCAN_INITIAL_DELAY
  C_Timer.After(delay, function()
    local cur = scanOps[profKey]
    if not ProfRecipes.enabled or not cur or cur.gen ~= gen then return end
    if not ScanOpStillOpen(profKey) then
      scanOps[profKey] = nil
      return
    end
    local ok, why, _, confirmed = ProfRecipes:ScanAndStore()
    local rec = ProfRecipes.GetEntry(U.NormalizeName(U.PlayerName()), profKey)
    FinishScanOpIfDone(profKey, gen, ok, why, rec and rec.ids, confirmed)
  end)
end

local function NoteRefreshPair(session, sender, profKey)
  if not session or not sender or not profKey then return end
  local key = tostring(sender) .. "\0" .. tostring(profKey)
  if session.pairSet[key] then return end
  session.pairSet[key] = true
  session.pairs[#session.pairs + 1] = key
  if not session.memberSet[sender] then
    session.memberSet[sender] = true
    session.nMembers = (session.nMembers or 0) + 1
  end
  session.nCats = (session.nCats or 0) + 1
end

local function ScheduleRefreshSettleCheck(gen)
  local function tick()
    local sess = recipeRefreshSession
    if not sess or sess.gen ~= gen or recipeRefreshWhy ~= "requesting" then return end
    local now = U.Now()
    local elapsed = now - sess.startedAt
    local quiet = (sess.lastRecv > 0) and (now - sess.lastRecv) or 0
    local have = (sess.nCats or 0) > 0
    local done = false
    if elapsed >= REFRESH_MAX then
      done = true
    elseif have and elapsed >= REFRESH_MIN_COLLECT and quiet >= REFRESH_QUIET then
      done = true
    elseif (not have) and elapsed >= REFRESH_MIN_COLLECT then
      -- Wait until min; if still nothing by max, finish as no_response via max path.
      -- At min with no replies: keep waiting until max unless we want early no-response at min.
      -- Plan: no replies → finish at min (or max). Use min.
      done = true
    end
    if done then
      if have then
        ProfRecipes:MarkRecipeRefreshDone("done", {
          members = sess.nMembers or 0,
          catalogs = sess.nCats or 0,
        })
      else
        ProfRecipes:MarkRecipeRefreshDone("no_response")
      end
      return
    end
    local nextIn = 0.5
    if have then
      local untilQuiet = REFRESH_QUIET - quiet
      local untilMin = REFRESH_MIN_COLLECT - elapsed
      local untilMax = REFRESH_MAX - elapsed
      nextIn = math.max(0.1, math.min(untilMax, math.max(untilQuiet, untilMin)))
    else
      nextIn = math.max(0.1, math.min(REFRESH_MAX - elapsed, REFRESH_MIN_COLLECT - elapsed))
    end
    C_Timer.After(nextIn, tick)
  end
  C_Timer.After(0.5, tick)
end

function ProfRecipes:OnEnable()
  if self.enabled then return end
  self.enabled = true
  EnsureMetaDB()

  GR:BindMessage(self, "PROF_RECIPE_UPDATE", function(_, sender, data)
    if U.IsSelfName(sender) then return end
    local sess = recipeRefreshSession
    local filterKey = sess and sess.profKey
    local accept = true
    if filterKey and filterKey ~= "" and data and data.profKey and data.profKey ~= filterKey then
      accept = false
    end
    ProfRecipes:OnRecipeUpdate(sender, data)
    if accept and recipeRefreshWhy == "requesting" and sess and data and data.profKey and data.complete then
      -- Count only after accept into cache (OnRecipeUpdate may reject).
      local entry = Cache()[sender]
      local rec = entry and entry.recipes and entry.recipes[data.profKey]
      if rec and rec.complete then
        NoteRefreshPair(sess, sender, data.profKey)
        sess.lastRecv = U.Now()
      end
    end
  end)

  GR:BindMessage(self, "PROF_RECIPE_REQUEST", function(_, sender, profKey)
    local now = U.Now()
    if (now - lastReqReply) < PROFRQ_REPLY_CD then return end
    lastReqReply = now
    C_Timer.After(1 + math.random() * 4, function()
      if not ProfRecipes.enabled then return end
      if profKey and profKey ~= "" then
        ProfRecipes:BroadcastProfession(profKey, true)
      else
        ProfRecipes:BroadcastAllStaggered(true, 0.55)
      end
    end)
  end)

  GR:BindMessage(self, "PROF_RECIPE_META_REQUEST", function(_, sender, ids)
    if U.IsSelfName(sender) then return end
    C_Timer.After(0.4 + math.random() * 1.2, function()
      if not ProfRecipes.enabled then return end
      ProfRecipes:OnMetaRequest(sender, ids)
    end)
  end)

  GR:BindMessage(self, "PROF_RECIPE_CATEGORY_REQUEST", function(_, sender, ids)
    if U.IsSelfName(sender) then return end
    C_Timer.After(0.4 + math.random() * 1.2, function()
      if not ProfRecipes.enabled then return end
      ProfRecipes:OnCategoryRequest(sender, ids)
    end)
  end)

  GR:BindMessage(self, "PROF_RECIPE_META_UPDATE", function(_, sender, entries)
    if U.IsSelfName(sender) then return end
    ProfRecipes:OnMetaUpdate(sender, entries)
  end)

  GR:BindMessage(self, "PROF_RECIPE_CATEGORY_UPDATE", function(_, sender, entries)
    if U.IsSelfName(sender) then return end
    ProfRecipes:OnCategoryUpdate(sender, entries)
  end)

  GR:BindMessage(self, "SHARE_PROF_CHANGED", function()
    -- Privacy off: PurgeDisallowed drops prof replies; requests stay (foundation §3).
    if Comm and Comm.PurgeDisallowed then Comm:PurgeDisallowed() end
    if GR.db and GR.db.privacy.shareProfessions then
      ProfRecipes:BroadcastAll(true)
    end
  end)

  GR:BindMessage(self, "PRIVACY_CHANGED", function()
    if Comm and Comm.PurgeDisallowed then Comm:PurgeDisallowed() end
  end)

  GR:BindMessage(self, "GUILD_UPDATE", function()
    wipe(lastSentFp)
    ProfRecipes.AbortAllBackgroundWork()
    -- Derived index must not outlive the active guild scope.
    ProfRecipes.InvalidateGuildRecipeIndex()
  end)

  local f = CreateFrame("Frame")
  self._eventFrame = f
  U.SafeRegisterEvent(f, "TRADE_SKILL_SHOW")
  U.SafeRegisterEvent(f, "TRADE_SKILL_LIST_UPDATE")
  U.SafeRegisterEvent(f, "TRADE_SKILL_CLOSE")
  U.SafeRegisterEvent(f, "NEW_RECIPE_LEARNED")
  f:SetScript("OnEvent", function(_, event, arg1)
    if not ProfRecipes.enabled then return end
    if event == "TRADE_SKILL_CLOSE" then
      AbortScanOps()
      return
    end
    if event == "NEW_RECIPE_LEARNED" then
      local recipeId = tonumber(arg1)
      local ctx = CurrentProfessionContext()
      ProfRecipes.NotePendingLearn(recipeId, ctx and ctx.profKey)
    end
    local ctx = CurrentProfessionContext()
    if not ctx or not ctx.profKey then return end
    -- Profession switch: bump other ops.
    for key, op in pairs(scanOps) do
      if key ~= ctx.profKey and op then
        op.gen = (op.gen or 0) + 1
        scanOps[key] = nil
      end
    end
    -- Coalesce into one op per profession.
    if scanOps[ctx.profKey] then return end
    ProfRecipes:BeginScanOp(ctx.profKey)
  end)
end

function ProfRecipes:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  ProfRecipes.AbortAllBackgroundWork()
  GR:UnbindMessages(self)
  GR:ReleaseEventFrame(self._eventFrame)
  self._eventFrame = nil
end

local function SanitizeMetaName(s)
  s = tostring(s or ""):gsub("[%c|;^=!]", "")
  if #s > MAX_META_NAME then s = s:sub(1, MAX_META_NAME) end
  return s
end

local function EncodeReagents(reagents)
  if type(reagents) ~= "table" then return "" end
  local parts = {}
  local n = math.min(#reagents, MAX_META_REAGENTS)
  for i = 1, n do
    local r = reagents[i]
    local itemID = tonumber(r and r.itemID) or 0
    local qty = tonumber(r and r.qty) or 0
    local name = SanitizeMetaName(r and r.name)
    if itemID > 0 and qty > 0 then
      parts[#parts + 1] = string.format("%d:%d:%s", itemID, qty, name)
    end
  end
  return table.concat(parts, "!")
end

local function DecodeReagents(part)
  local out = {}
  if not part or part == "" then return out end
  for piece in string.gmatch(part, "([^!]+)") do
    local itemID, qty, name = piece:match("^(%d+):(%d+):(.*)$")
    itemID, qty = tonumber(itemID), tonumber(qty)
    if itemID and qty and itemID > 0 and qty > 0 then
      out[#out + 1] = {
        itemID = itemID,
        qty = qty,
        name = (name and name ~= "") and name or nil,
      }
    end
  end
  return out
end

-- Wire: ver|id|name|icon|out|qmin|qmax|enchant|locale|reags  (records joined by ;)
function ProfRecipes.EncodeMetaBatch(entries)
  if type(entries) ~= "table" or #entries == 0 then return nil end
  local parts = {}
  local n = math.min(#entries, MAX_META_REQ_IDS)
  for i = 1, n do
    local e = entries[i]
    local id = tonumber(e and e.recipeId or e and e.id)
    if id and id > 0 then
      local name = SanitizeMetaName(e.name)
      local icon = tonumber(e.icon) or 0
      local out = tonumber(e.outputItemID) or 0
      local qmin = tonumber(e.qtyMin) or 0
      local qmax = tonumber(e.qtyMax) or 0
      local ench = e.isEnchant and 1 or 0
      local locale = SanitizeMetaName(e.locale or "")
      if #locale > 8 then locale = locale:sub(1, 8) end
      parts[#parts + 1] = string.format(
        "%d|%s|%d|%d|%d|%d|%d|%s|%s",
        id, name, icon, out, qmin, qmax, ench, locale, EncodeReagents(e.reagents)
      )
    end
  end
  if #parts == 0 then return nil end
  return tostring(META_WIRE_VER) .. "|" .. table.concat(parts, ";")
end

function ProfRecipes.DecodeMetaBatch(rest)
  rest = tostring(rest or ""):gsub("[%c]", "")
  if #rest > 20000 then return nil, "too_long" end
  local ver, body = rest:match("^(%d+)|(.*)$")
  ver = tonumber(ver)
  if ver ~= META_WIRE_VER then return nil, "ver" end
  if not body or body == "" then return nil, "empty" end
  local out = {}
  for record in string.gmatch(body, "([^;]+)") do
    local id, name, icon, outItem, qmin, qmax, ench, locale, reags =
      record:match("^(%d+)|([^|]*)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|(.*)$")
    id = tonumber(id)
    if id and id > 0 then
      out[#out + 1] = {
        recipeId = id,
        name = (name and name ~= "") and name or nil,
        icon = tonumber(icon),
        outputItemID = tonumber(outItem),
        qtyMin = tonumber(qmin),
        qtyMax = tonumber(qmax),
        isEnchant = tonumber(ench) == 1,
        locale = (locale and locale ~= "") and locale or nil,
        reagents = DecodeReagents(reags),
      }
      if #out > MAX_META_REQ_IDS then
        return nil, "too_many"
      end
    end
  end
  if #out == 0 then return nil, "empty" end
  return out
end

function ProfRecipes.EncodeMetaRequest(ids)
  ids = SortIds(ids)
  if #ids == 0 then return nil end
  if #ids > MAX_META_REQ_IDS then
    local trimmed = {}
    for i = 1, MAX_META_REQ_IDS do trimmed[i] = ids[i] end
    ids = trimmed
  end
  local parts = {}
  for i = 1, #ids do parts[i] = tostring(ids[i]) end
  return tostring(META_WIRE_VER) .. "|" .. table.concat(parts, "+")
end

function ProfRecipes.DecodeMetaRequest(rest)
  rest = tostring(rest or ""):gsub("[%c]", "")
  if #rest > 4000 then return nil, "too_long" end
  local ver, idPart = rest:match("^(%d+)|(.*)$")
  ver = tonumber(ver)
  if ver ~= META_WIRE_VER then return nil, "ver" end
  local ids = {}
  if idPart and idPart ~= "" then
    for piece in string.gmatch(idPart, "([^+]+)") do
      local id = tonumber(piece)
      if id and id > 0 and id <= MAX_RECIPE_ID then
        ids[#ids + 1] = id
        if #ids > MAX_META_REQ_IDS then return nil, "too_many" end
      end
    end
  end
  ids = SortIds(ids)
  if #ids == 0 then return nil, "empty" end
  return ids
end

-- Same ID-list wire as meta requests; separate tag PROFRCQ.
function ProfRecipes.EncodeCategoryRequest(ids)
  return ProfRecipes.EncodeMetaRequest(ids)
end

function ProfRecipes.DecodeCategoryRequest(rest)
  return ProfRecipes.DecodeMetaRequest(rest)
end

-- Wire PROFRC: ver|id|catId|catName;…  (category only; older clients ignore tag)
function ProfRecipes.EncodeCategoryBatch(entries)
  if type(entries) ~= "table" or #entries == 0 then return nil end
  local parts = {}
  local n = math.min(#entries, MAX_META_REQ_IDS)
  for i = 1, n do
    local e = entries[i]
    local id = tonumber(e and e.recipeId or e and e.id)
    local catId = tonumber(e and e.categoryId)
    local catName = SanitizeMetaName(e and e.categoryName)
    if id and id > 0 and catId and catId > 0 and catName ~= "" then
      parts[#parts + 1] = string.format("%d|%d|%s", id, catId, catName)
    end
  end
  if #parts == 0 then return nil end
  return tostring(CAT_WIRE_VER) .. "|" .. table.concat(parts, ";")
end

function ProfRecipes.DecodeCategoryBatch(rest)
  rest = tostring(rest or ""):gsub("[%c]", "")
  if #rest > 20000 then return nil, "too_long" end
  local ver, body = rest:match("^(%d+)|(.*)$")
  ver = tonumber(ver)
  if ver ~= CAT_WIRE_VER then return nil, "ver" end
  if not body or body == "" then return nil, "empty" end
  local out = {}
  for record in string.gmatch(body, "([^;]+)") do
    local id, catId, catName = record:match("^(%d+)|(%d+)|([^|]*)$")
    id, catId = tonumber(id), tonumber(catId)
    if id and id > 0 and catId and catId > 0 and catName and catName ~= "" then
      out[#out + 1] = {
        recipeId = id,
        categoryId = catId,
        categoryName = catName,
      }
      if #out > MAX_META_REQ_IDS then
        return nil, "too_many"
      end
    end
  end
  if #out == 0 then return nil, "empty" end
  return out
end

local function MetaShouldGiveUp(id, now)
  if metaGiveUp[id] then return true end
  local att = metaAttempt[id]
  if not att then return false end
  if (att.n or 0) >= META_MAX_ATTEMPTS then return true end
  if att.firstSentAt and (now - att.firstSentAt) >= META_BUDGET_SEC then return true end
  return false
end

local function EnqueueMetaIds(ids)
  for i = 1, #(ids or {}) do
    local id = tonumber(ids[i])
    if id and not metaQueueSet[id] and not metaGiveUp[id] and not pendingMetaReq[id] then
      if #metaQueue >= MAX_RECIPES then
        break -- drop newest overflow
      end
      metaQueue[#metaQueue + 1] = id
      metaQueueSet[id] = true
    end
  end
end

local function DequeueMetaId(id)
  if not metaQueueSet[id] then return end
  metaQueueSet[id] = nil
  for i = 1, #metaQueue do
    if metaQueue[i] == id then
      table.remove(metaQueue, i)
      break
    end
  end
end

local function ScheduleMetaDrain(delay)
  if metaDrainScheduled then return end
  metaDrainScheduled = true
  local gen = metaDrainGen
  C_Timer.After(delay or 0.05, function()
    metaDrainScheduled = false
    if not ProfRecipes.enabled or gen ~= metaDrainGen then return end
    ProfRecipes._DrainMetaQueue()
  end)
end

-- Resolve metadata for recipe IDs via local client APIs (no knowledge grant).
-- Returns meta, complete (IsMetaComplete).
function ProfRecipes.EnsureMetaResolved(recipeId)
  recipeId = tonumber(recipeId)
  if not recipeId or recipeId <= 0 then return nil, false end
  local existing = ProfRecipes.GetMeta(recipeId)
  if existing and ProfRecipes.IsMetaComplete(existing) then
    return existing, true
  end
  local api = TS()
  if not api or not api.GetRecipeInfo then
    return existing, false
  end
  local okInfo, info = pcall(api.GetRecipeInfo, recipeId)
  if not okInfo or not info then
    return existing, false
  end
  local schematic
  local schematicOk = false
  if api.GetRecipeSchematic then
    local okSch, sch = pcall(api.GetRecipeSchematic, recipeId, false)
    if okSch and sch ~= nil then
      schematic = sch
      schematicOk = true
    end
  end
  CaptureMeta(recipeId, info, schematic, { schematicOk = schematicOk })
  local meta = ProfRecipes.GetMeta(recipeId)
  return meta, ProfRecipes.IsMetaComplete(meta)
end

-- Category-only resolve: never loads schematics / reagents / PROFRMQ.
-- Returns true when both categoryId and localized categoryName are cached.
function ProfRecipes.EnsureCategoryResolved(recipeId)
  recipeId = tonumber(recipeId)
  if not recipeId or recipeId <= 0 then return false end
  local meta = ProfRecipes.GetMeta(recipeId)
  local catId = meta and tonumber(meta.categoryId)
  local catName = meta and meta.categoryName
  if catId and catId > 0 and type(catName) == "string" and catName ~= "" then
    return true
  end
  local api = TS()
  if (not catId or catId <= 0) and api and type(api.GetRecipeInfo) == "function" then
    local okInfo, info = pcall(api.GetRecipeInfo, recipeId)
    if okInfo and type(info) == "table" then
      catId = tonumber(info.categoryID)
    end
  end
  if not catId or catId <= 0 then return false end
  if not catName or catName == "" then
    catName = LookupCategoryName(catId)
  end
  if type(catName) ~= "string" or catName == "" then
    ProfRecipes.StoreMeta(recipeId, { categoryId = catId })
    return false
  end
  ProfRecipes.StoreMeta(recipeId, { categoryId = catId, categoryName = catName })
  return true
end

-- Returns categoryKey, categoryName, resolved.
-- Unknown / incomplete → "other", localized Sonstiges, false.
function ProfRecipes.ResolveRecipeCategory(recipeId, profKey)
  recipeId = tonumber(recipeId)
  local otherName = U.L("PROF_RECIPE_CAT_OTHER")
  if not recipeId or recipeId <= 0 then
    return "other", otherName, false
  end
  ProfRecipes.EnsureCategoryResolved(recipeId)
  local meta = ProfRecipes.GetMeta(recipeId)
  local catId = meta and tonumber(meta.categoryId)
  local catName = meta and meta.categoryName
  if catId and catId > 0 and type(catName) == "string" and catName ~= "" then
    return tostring(catId), catName, true
  end
  return "other", otherName, false
end

local function CatShouldGiveUp(id, now)
  if catGiveUp[id] then return true end
  local att = catAttempt[id]
  if not att or not att.firstSentAt then return false end
  if (att.n or 0) >= META_MAX_ATTEMPTS then return true end
  return (now - att.firstSentAt) >= META_BUDGET_SEC
end

local function DequeueCatId(id)
  if not catQueueSet[id] then return end
  catQueueSet[id] = nil
  for i = #catQueue, 1, -1 do
    if catQueue[i] == id then table.remove(catQueue, i) end
  end
end

local function EnqueueCatIds(ids)
  if type(ids) ~= "table" then return end
  for i = 1, #ids do
    local id = tonumber(ids[i])
    if id and not catQueueSet[id] and not catGiveUp[id] and not pendingCatReq[id] then
      if ProfRecipes.EnsureCategoryResolved(id) then
        -- already local
      else
        catQueueSet[id] = true
        catQueue[#catQueue + 1] = id
      end
    end
  end
end

local function ScheduleCatDrain(delay)
  if catDrainScheduled then return end
  catDrainScheduled = true
  local gen = catDrainGen
  C_Timer.After(math.max(0, delay or 0), function()
    catDrainScheduled = false
    if not ProfRecipes.enabled or gen ~= catDrainGen then return end
    ProfRecipes._DrainCategoryQueue()
  end)
end

function ProfRecipes._DrainCategoryQueue()
  if not IsInGuild or not IsInGuild() then return false, "no_guild" end
  if not Comm or not Comm.Send then return false, "no_comm" end
  if catInFlightOp then return false, "in_flight" end
  local now = U.Now()
  if (now - lastCatReqSend) < PROFRMQ_SEND_CD then
    ScheduleCatDrain(PROFRMQ_SEND_CD - (now - lastCatReqSend) + 0.05)
    return false, "cooldown"
  end
  for id, exp in pairs(pendingCatReq) do
    if exp <= now then pendingCatReq[id] = nil end
  end
  local want = {}
  local i = 1
  while i <= #catQueue and #want < MAX_META_REQ_IDS do
    local id = catQueue[i]
    local att = catAttempt[id]
    if CatShouldGiveUp(id, now) or (att and (att.n or 0) >= META_MAX_ATTEMPTS) then
      catGiveUp[id] = true
      DequeueCatId(id)
    elseif pendingCatReq[id] then
      i = i + 1
    elseif ProfRecipes.EnsureCategoryResolved(id) then
      DequeueCatId(id)
    else
      want[#want + 1] = id
      i = i + 1
    end
  end
  if #want == 0 then
    if #catQueue > 0 then ScheduleCatDrain(PROFRMQ_SEND_CD) end
    return false, "none"
  end
  local body = ProfRecipes.EncodeCategoryRequest(want)
  if not body then return false, "encode" end
  local opId = "catreq-" .. tostring(now) .. "-" .. tostring(want[1])
  local scopeKey = U.GuildScopeKey and U.GuildScopeKey()
  -- Stamp in-flight before Send so sync onAck (instant success) can clear it.
  catInFlightOp = opId
  local ok = Comm:Send("PROFRCQ|" .. body, "ctrl", "sync", {
    scopeKey = scopeKey,
    operationId = opId,
    onAck = function(success)
      if catInFlightOp == opId then catInFlightOp = nil end
      if not ProfRecipes.enabled then return end
      if not success then
        ScheduleCatDrain(1)
        return
      end
      -- Attempt budget / pending window start only after full send-ack.
      local t = U.Now()
      lastCatReqSend = t
      local expire = t + META_PENDING_EXPIRE
      for j = 1, #want do
        local id = want[j]
        pendingCatReq[id] = expire
        local att = catAttempt[id] or { n = 0 }
        att.n = (att.n or 0) + 1
        if not att.firstSentAt then att.firstSentAt = t end
        catAttempt[id] = att
      end
      local gen = catDrainGen
      C_Timer.After(META_PENDING_EXPIRE, function()
        if gen ~= catDrainGen then return end
        local now2 = U.Now()
        for id, exp in pairs(pendingCatReq) do
          if exp <= now2 then
            pendingCatReq[id] = nil
            if CatShouldGiveUp(id, now2) then
              catGiveUp[id] = true
              DequeueCatId(id)
            end
          end
        end
        ScheduleCatDrain(0.05)
      end)
      if #catQueue > 0 then ScheduleCatDrain(PROFRMQ_SEND_CD + 0.05) end
    end,
  })
  if not ok then
    if catInFlightOp == opId then catInFlightOp = nil end
    return false, "send_fail"
  end
  return true, "queued"
end

function ProfRecipes.EnsureCategoriesForIds(ids)
  if type(ids) ~= "table" then return 0, {} end
  local n, missing = 0, {}
  for i = 1, #ids do
    local id = tonumber(ids[i])
    if id then
      if ProfRecipes.EnsureCategoryResolved(id) then
        n = n + 1
        DequeueCatId(id)
        pendingCatReq[id] = nil
      elseif not catGiveUp[id] then
        missing[#missing + 1] = id
      end
    end
  end
  if #missing > 0 then
    EnqueueCatIds(missing)
    ProfRecipes._DrainCategoryQueue()
  end
  return n, missing
end

function ProfRecipes.RetryCategoriesForIds(ids)
  if type(ids) ~= "table" then return end
  for i = 1, #ids do
    local id = tonumber(ids[i])
    if id then
      catGiveUp[id] = nil
      catAttempt[id] = nil
    end
  end
  return ProfRecipes.EnsureCategoriesForIds(ids)
end

local function CanonicalCategory(meta)
  if not meta then return nil end
  local catId = tonumber(meta.categoryId)
  local catName = meta.categoryName
  if catId and catId > 0 and type(catName) == "string" and catName ~= "" then
    return string.format("%d|%s", catId, catName)
  end
  return nil
end

local BuildMetaEntries, SendMetaReply, DrainReplyPolicy

local function SendCategoryReply(ids)
  local entries = {}
  for i = 1, math.min(#ids, MAX_META_REQ_IDS) do
    local id = tonumber(ids[i])
    local meta = id and ProfRecipes.GetMeta(id)
    ProfRecipes.EnsureCategoryResolved(id)
    meta = ProfRecipes.GetMeta(id)
    if meta and tonumber(meta.categoryId) and meta.categoryName and meta.categoryName ~= "" then
      entries[#entries + 1] = {
        recipeId = id,
        categoryId = meta.categoryId,
        categoryName = meta.categoryName,
      }
    end
  end
  if #entries == 0 then return false end
  local catBody = ProfRecipes.EncodeCategoryBatch(entries)
  if not catBody then return false end
  local opId = "catrep-" .. tostring(U.Now()) .. "-" .. tostring(entries[1].recipeId)
  catReplyOpIds[opId] = true
  local ok = Comm:Send("PROFRC|" .. catBody, "data", "prof", {
    scopeKey = U.GuildScopeKey and U.GuildScopeKey(),
    operationId = opId,
    onAck = function()
      catReplyOpIds[opId] = nil
    end,
  })
  if not ok then catReplyOpIds[opId] = nil end
  return ok
end

function DrainReplyPolicy(now)
  if not replyPolicy or not GR.MetaReplyPolicy then return end
  if not GR.db or not GR.db.privacy or not GR.db.privacy.shareProfessions then return end
  local candidates = {}
  for id, row in pairs(replyPolicy.open) do
    local meta = ProfRecipes.GetMeta(id)
    candidates[id] = {
      meta = nil,
      category = row.category and CanonicalCategory(meta) or nil,
    }
    if row.meta and meta and meta.name and meta.name ~= "" and meta.reagentsResolved == true then
      candidates[id].meta = true
    end
  end
  local batch = GR.MetaReplyPolicy.Due(replyPolicy, now, candidates)
  if #batch == 0 then return end
  local catIds, metaIds = {}, {}
  for i = 1, #batch do
    if batch[i].category then catIds[#catIds + 1] = batch[i].id end
    if batch[i].meta then metaIds[#metaIds + 1] = batch[i].id end
  end
  if #metaIds > 0 then
    if SendMetaReply(BuildMetaEntries(metaIds)) then
      GR.MetaReplyPolicy.Resolve(replyPolicy, metaIds, "meta", "queued", now)
      GR.MetaReplyPolicy.Resolve(replyPolicy, metaIds, "category", "queued", now)
      lastMetaReqReply = now
    else
      GR.MetaReplyPolicy.Resolve(replyPolicy, metaIds, "meta", "retry", now)
    end
  end
  if #catIds > 0 then
    if SendCategoryReply(catIds) then
      GR.MetaReplyPolicy.Resolve(replyPolicy, catIds, "category", "queued", now)
      lastCatReqReply = now
    else
      GR.MetaReplyPolicy.Resolve(replyPolicy, catIds, "category", "retry", now)
    end
  end
end

function ProfRecipes._DrainMetaQueue()
  if not IsInGuild or not IsInGuild() then return false, "no_guild" end
  if not Comm or not Comm.Send then return false, "no_comm" end
  if metaInFlightOp then return false, "in_flight" end
  local now = U.Now()
  if (now - lastMetaReqSend) < PROFRMQ_SEND_CD then
    ScheduleMetaDrain(PROFRMQ_SEND_CD - (now - lastMetaReqSend) + 0.05)
    return false, "cooldown"
  end
  -- Expire stale pending markers.
  for id, exp in pairs(pendingMetaReq) do
    if exp <= now then pendingMetaReq[id] = nil end
  end
  local want = {}
  local i = 1
  while i <= #metaQueue and #want < MAX_META_REQ_IDS do
    local id = metaQueue[i]
    local att = metaAttempt[id]
    if MetaShouldGiveUp(id, now) or (att and (att.n or 0) >= META_MAX_ATTEMPTS) then
      metaGiveUp[id] = true
      DequeueMetaId(id)
      -- do not advance i: remove shifts list
    elseif pendingMetaReq[id] then
      i = i + 1
    else
      want[#want + 1] = id
      i = i + 1
    end
  end
  if #want == 0 then
    if #metaQueue > 0 then
      ScheduleMetaDrain(PROFRMQ_SEND_CD)
    end
    return false, "none"
  end
  local body = ProfRecipes.EncodeMetaRequest(want)
  if not body then return false, "encode" end
  local opId = "metareq-" .. tostring(now) .. "-" .. tostring(want[1])
  local scopeKey = U.GuildScopeKey and U.GuildScopeKey()
  -- Stamp in-flight before Send so sync onAck (instant success) can clear it.
  metaInFlightOp = opId
  local ok = Comm:Send("PROFRMQ|" .. body, "ctrl", "sync", {
    scopeKey = scopeKey,
    operationId = opId,
    onAck = function(success)
      if metaInFlightOp == opId then metaInFlightOp = nil end
      if not ProfRecipes.enabled then return end
      if not success then
        ScheduleMetaDrain(1)
        return
      end
      -- Attempt budget / pending window start only after full send-ack.
      local t = U.Now()
      lastMetaReqSend = t
      local expire = t + META_PENDING_EXPIRE
      for j = 1, #want do
        local id = want[j]
        pendingMetaReq[id] = expire
        local att = metaAttempt[id] or { n = 0 }
        att.n = (att.n or 0) + 1
        if not att.firstSentAt then att.firstSentAt = t end
        metaAttempt[id] = att
      end
      local gen = metaDrainGen
      C_Timer.After(META_PENDING_EXPIRE, function()
        if gen ~= metaDrainGen then return end
        local now2 = U.Now()
        for id, exp in pairs(pendingMetaReq) do
          if exp <= now2 then
            pendingMetaReq[id] = nil
            if MetaShouldGiveUp(id, now2) then
              metaGiveUp[id] = true
              DequeueMetaId(id)
            end
          end
        end
        ScheduleMetaDrain(0.05)
      end)
      if #metaQueue > 0 then
        ScheduleMetaDrain(PROFRMQ_SEND_CD + 0.05)
      end
    end,
  })
  if not ok then
    if metaInFlightOp == opId then metaInFlightOp = nil end
    return false, "send_fail"
  end
  return true, "queued"
end

-- Compat: enqueue missing IDs then drain (only marks pending for IDs actually sent).
function ProfRecipes._RequestMetaFromPeers(ids, peerHint)
  EnqueueMetaIds(ids)
  local ok, why = ProfRecipes._DrainMetaQueue()
  return ok, why, peerHint
end

function ProfRecipes.EnsureMetaForIds(ids, peerHint)
  if type(ids) ~= "table" then return 0 end
  local n = 0
  local missing = {}
  for i = 1, #ids do
    local id = tonumber(ids[i])
    if id then
      local _, ok = ProfRecipes.EnsureMetaResolved(id)
      if ok then
        n = n + 1
        DequeueMetaId(id)
      elseif not metaGiveUp[id] then
        missing[#missing + 1] = id
      end
    end
  end
  if #missing > 0 then
    ProfRecipes._RequestMetaFromPeers(missing, peerHint)
  end
  return n, missing
end

function BuildMetaEntries(ids)
  local entries = {}
  for i = 1, math.min(#ids, MAX_META_REQ_IDS) do
    local id = tonumber(ids[i])
    local meta = id and ProfRecipes.GetMeta(id)
    if meta and meta.name and meta.name ~= "" and meta.reagentsResolved == true then
      entries[#entries + 1] = {
        recipeId = id,
        name = meta.name,
        icon = meta.icon,
        outputItemID = meta.outputItemID,
        qtyMin = meta.qtyMin,
        qtyMax = meta.qtyMax,
        isEnchant = meta.isEnchant,
        locale = meta.locale or (GetLocale and GetLocale()) or nil,
        reagents = meta.reagents,
      }
    end
  end
  return entries
end

function SendMetaReply(entries)
  if #entries == 0 then return false end
  local encoded = ProfRecipes.EncodeMetaBatch(entries)
  if not encoded then return false end
  local opId = "metarep-" .. tostring(U.Now()) .. "-" .. tostring(entries[1].recipeId)
  catReplyOpIds[opId] = true
  local ok = Comm:Send("PROFRM|" .. encoded, "data", "prof", {
    scopeKey = U.GuildScopeKey and U.GuildScopeKey(),
    operationId = opId,
    onAck = function() catReplyOpIds[opId] = nil end,
  })
  if not ok then catReplyOpIds[opId] = nil end
  -- Piggyback categories for the same recipes when known.
  local catEntries = {}
  for i = 1, #entries do
    local id = tonumber(entries[i].recipeId)
    local meta = id and ProfRecipes.GetMeta(id)
    if meta and tonumber(meta.categoryId) and meta.categoryName and meta.categoryName ~= "" then
      catEntries[#catEntries + 1] = {
        recipeId = id,
        categoryId = meta.categoryId,
        categoryName = meta.categoryName,
      }
    end
  end
  if #catEntries > 0 then
    local ids = {}
    for i = 1, #catEntries do ids[i] = catEntries[i].recipeId end
    SendCategoryReply(ids)
  end
  return ok
end

function ProfRecipes:OnMetaRequest(sender, ids)
  if sender ~= "__policy__" and U.IsSelfName(sender) then return end
  if type(ids) ~= "table" or #ids == 0 then return end
  if not GR.db or not GR.db.privacy or not GR.db.privacy.shareProfessions then return end
  local now = U.Now()
  if not replyPolicy and GR.MetaReplyPolicy then
    replyPolicy = GR.MetaReplyPolicy.New()
  end
  if replyPolicy and GR.MetaReplyPolicy and sender ~= "__policy__" then
    GR.MetaReplyPolicy.Add(replyPolicy, ids, now, { meta = true, category = true })
    -- last*Reply == 0 means never replied; do not treat as still in cooldown.
    if lastMetaReqReply > 0 and (now - lastMetaReqReply) < PROFRMQ_REPLY_CD then
      local gen = replyPolicyGen
      C_Timer.After(PROFRMQ_REPLY_CD - (now - lastMetaReqReply) + 0.05, function()
        if not ProfRecipes.enabled or gen ~= replyPolicyGen then return end
        DrainReplyPolicy(U.Now())
      end)
      return
    end
    lastMetaReqReply = now
    DrainReplyPolicy(now)
    return
  end
  if lastMetaReqReply > 0 and (now - lastMetaReqReply) < PROFRMQ_REPLY_CD then return end
  lastMetaReqReply = now
  SendMetaReply(BuildMetaEntries(ids))
end

function ProfRecipes:OnCategoryRequest(sender, ids)
  if U.IsSelfName(sender) then return end
  if type(ids) ~= "table" or #ids == 0 then return end
  if not GR.db or not GR.db.privacy or not GR.db.privacy.shareProfessions then return end
  local now = U.Now()
  if not replyPolicy and GR.MetaReplyPolicy then
    replyPolicy = GR.MetaReplyPolicy.New()
  end
  -- Category-only: never schedule material replies.
  if replyPolicy and GR.MetaReplyPolicy then
    GR.MetaReplyPolicy.Add(replyPolicy, ids, now, { meta = false, category = true })
    local lastReply = math.max(lastCatReqReply or 0, lastMetaReqReply or 0)
    if lastReply > 0 and (now - lastReply) < PROFRMQ_REPLY_CD then
      local gen = replyPolicyGen
      C_Timer.After(PROFRMQ_REPLY_CD - (now - lastReply) + 0.05, function()
        if not ProfRecipes.enabled or gen ~= replyPolicyGen then return end
        DrainReplyPolicy(U.Now())
      end)
      return
    end
    lastCatReqReply = now
    DrainReplyPolicy(now)
    return
  end
  if lastCatReqReply > 0 and (now - lastCatReqReply) < PROFRMQ_REPLY_CD then return end
  lastCatReqReply = now
  SendCategoryReply(ids)
end

function ProfRecipes:OnMetaUpdate(sender, entries)
  if U.IsSelfName(sender) then return end
  if type(entries) ~= "table" then return end
  local myLocale = GetLocale and GetLocale() or nil
  local changed = false
  for i = 1, #entries do
    local e = entries[i]
    local id = e and tonumber(e.recipeId)
    if id then
      pendingMetaReq[id] = nil
      local prev = ProfRecipes.GetMeta(id)
      local name = e.name
      if prev and prev.name and prev.name ~= "" then
        name = prev.name
      elseif name and e.locale and myLocale and e.locale ~= myLocale then
        -- keep as fallback with locale marker
      end
      local icon = e.icon
      if type(icon) == "number" and icon <= 0 then icon = nil end
      local out = e.outputItemID
      if type(out) == "number" and out <= 0 then out = nil end
      local qmin = e.qtyMin
      if type(qmin) == "number" and qmin <= 0 then qmin = nil end
      local qmax = e.qtyMax
      if type(qmax) == "number" and qmax <= 0 then qmax = nil end
      local reagents = (type(e.reagents) == "table" and #e.reagents > 0) and e.reagents or nil
      -- Peer empty reagents stay unknown (wire cannot confirm no-mats).
      ProfRecipes.StoreMeta(id, {
        name = name,
        icon = icon,
        outputItemID = out,
        qtyMin = qmin,
        qtyMax = qmax,
        isEnchant = e.isEnchant,
        locale = e.locale,
        reagents = reagents,
        reagentsResolved = reagents and true or nil,
      })
      if ProfRecipes.IsMetaComplete(ProfRecipes.GetMeta(id)) then
        DequeueMetaId(id)
        metaAttempt[id] = nil
        metaGiveUp[id] = nil
        if replyPolicy and GR.MetaReplyPolicy then
          GR.MetaReplyPolicy.Observe(replyPolicy, id, "meta", "complete", U.Now())
        end
      end
      changed = true
    end
  end
  if changed then
    ProfRecipes.InvalidateGuildRecipeIndex()
    GR:SendMessage("PROF_RECIPE_META_CHANGED", sender)
    ScheduleMetaDrain(0.05)
  end
end

function ProfRecipes:OnCategoryUpdate(sender, entries)
  if U.IsSelfName(sender) then return end
  if type(entries) ~= "table" then return end
  local changed = false
  for i = 1, #entries do
    local e = entries[i]
    local id = e and tonumber(e.recipeId)
    local catId = e and tonumber(e.categoryId)
    local catName = e and e.categoryName
    if id and catId and catId > 0 and type(catName) == "string" and catName ~= "" then
      pendingCatReq[id] = nil
      DequeueCatId(id)
      catAttempt[id] = nil
      catGiveUp[id] = nil
      local canon = string.format("%d|%s", catId, catName)
      if replyPolicy and GR.MetaReplyPolicy then
        GR.MetaReplyPolicy.Observe(replyPolicy, id, "category", canon, U.Now())
      end
      local prev = ProfRecipes.GetMeta(id)
      local had = prev and tonumber(prev.categoryId) and prev.categoryName and prev.categoryName ~= ""
      if not had then
        -- Prefer locally resolved name when EnsureCategoryResolved can fill it.
        ProfRecipes.EnsureCategoryResolved(id)
        local localMeta = ProfRecipes.GetMeta(id)
        if localMeta and tonumber(localMeta.categoryId) == catId and localMeta.categoryName and localMeta.categoryName ~= "" then
          changed = true
        else
          ProfRecipes.StoreMeta(id, { categoryId = catId, categoryName = catName })
          changed = true
        end
      elseif tonumber(prev.categoryId) == catId then
        -- Keep existing complete pair; identical peer is a no-op for UI.
      else
        -- Do not arbitrarily replace a complete local pair with a conflicting peer.
      end
    end
  end
  if changed then
    GR:SendMessage("PROF_RECIPE_CATEGORY_CHANGED", sender)
  end
end

function ProfRecipes:IsRecipeRefreshBusy()
  return U.Now() < (recipeRefreshBusyUntil or 0)
end

function ProfRecipes:GetRecipeRefreshStatus()
  if self:IsRecipeRefreshBusy() then
    return "busy", recipeRefreshWhy or "requesting"
  end
  return "idle", recipeRefreshWhy
end

-- Sticky settle summary for search UI (nil when expired / none).
function ProfRecipes:GetRecipeRefreshSummary()
  local s = recipeRefreshSummary
  if not s then return nil end
  if U.Now() >= (s.untilAt or 0) then
    recipeRefreshSummary = nil
    return nil
  end
  return s
end

function ProfRecipes:ClearRecipeRefreshSummary()
  recipeRefreshSummary = nil
end

-- Guild-wide / filtered recipe catalogue refresh (search UI button).
function ProfRecipes:RequestRecipeDataRefresh(profKey, force)
  if not IsInGuild or not IsInGuild() then
    return false, "no_guild"
  end
  if profKey and profKey ~= "" and ProfRecipes.IsGathering(profKey) then
    return false, "gathering"
  end
  if self:IsRecipeRefreshBusy() and not force then
    return false, "busy"
  end
  local ok, why
  if profKey and profKey ~= "" then
    ok, why = self:RequestProfession(profKey, force)
  else
    ok, why = self:RequestAll(nil, force)
  end
  if ok and why == "sent" then
    recipeRefreshGen = recipeRefreshGen + 1
    local gen = recipeRefreshGen
    local untilAt = U.Now() + REFRESH_MAX
    recipeRefreshBusyUntil = untilAt
    recipeRefreshWhy = "requesting"
    recipeRefreshSummary = nil
    recipeRefreshSession = {
      gen = gen,
      profKey = (profKey and profKey ~= "") and profKey or nil,
      startedAt = U.Now(),
      lastRecv = 0,
      pairSet = {},
      pairs = {},
      memberSet = {},
      nMembers = 0,
      nCats = 0,
    }
    ScheduleRefreshSettleCheck(gen)
    GR:SendMessage("PROF_RECIPE_REFRESH_STATUS", "requesting", profKey)
  elseif why == "cooldown" then
    recipeRefreshWhy = "cooldown"
  end
  return ok, why
end

function ProfRecipes:MarkRecipeRefreshDone(why, stats)
  local gen = recipeRefreshSession and recipeRefreshSession.gen
  recipeRefreshBusyUntil = 0
  recipeRefreshWhy = why or "done"
  recipeRefreshSession = nil
  local members = stats and stats.members or 0
  local catalogs = stats and stats.catalogs or 0
  if why == "done" then
    recipeRefreshSummary = {
      why = "done",
      members = members,
      catalogs = catalogs,
      untilAt = U.Now() + REFRESH_SUMMARY_HOLD,
    }
  elseif why == "no_response" then
    recipeRefreshSummary = {
      why = "no_response",
      members = 0,
      catalogs = 0,
      untilAt = U.Now() + REFRESH_SUMMARY_HOLD,
    }
  end
  GR:SendMessage("PROF_RECIPE_REFRESH_STATUS", recipeRefreshWhy, members, catalogs)
  return gen
end

ProfRecipes.MAX_QTY = MAX_QTY
ProfRecipes.MAX_RECIPES = MAX_RECIPES
ProfRecipes.MAX_META_REQ_IDS = MAX_META_REQ_IDS
ProfRecipes.META_MAX_ATTEMPTS = META_MAX_ATTEMPTS
ProfRecipes.META_BUDGET_SEC = META_BUDGET_SEC
ProfRecipes.REFRESH_MIN_COLLECT = REFRESH_MIN_COLLECT
ProfRecipes.REFRESH_QUIET = REFRESH_QUIET
ProfRecipes.REFRESH_MAX = REFRESH_MAX
ProfRecipes.REFRESH_SUMMARY_HOLD = REFRESH_SUMMARY_HOLD
ProfRecipes.WIRE_VER = WIRE_VER
ProfRecipes.PROFR_WIRE_VER = PROFR_WIRE_VER
ProfRecipes.PROFR_WIRE_VER_LEGACY = PROFR_WIRE_VER_LEGACY
ProfRecipes.META_WIRE_VER = META_WIRE_VER
ProfRecipes.CAT_WIRE_VER = CAT_WIRE_VER
ProfRecipes.FLAG_COMPLETE = FLAG_COMPLETE
ProfRecipes.GATHERING_KEYS = GATHERING_KEYS
ProfRecipes._metaQueue = metaQueue
ProfRecipes._metaGiveUp = metaGiveUp
ProfRecipes._pendingLearn = pendingLearn
ProfRecipes._lastSentFp = lastSentFp
