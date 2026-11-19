-- Local optional Nerglish chat flavor. No wire, no toast rewrite, no Print here.
local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Nerglish = GR.Nerglish or {}
local N = GR.Nerglish

local CHANCE = { subtle = 0.30, playful = 0.70 }
local GLOBAL_CD = 180
local MAX_PER_HOUR = 6
local NORMAL_SIZE = 3
local RARE_LO, RARE_HI = 1, 10
local RARE_SUBTLE_HI = 5 -- short rares only for Subtle
local LEGEND_LO, LEGEND_HI = 11, 16

local RARITY_PLAYFUL = {
  { id = "normal", p = 0.80 },
  { id = "rare", p = 0.17 },
  { id = "legend", p = 0.03 },
}
local RARITY_SUBTLE = {
  { id = "normal", p = 0.85 },
  { id = "rare", p = 0.15 },
}

local state = {
  lastReactAt = 0,
  hourStamps = {},
  lastVariant = {},
}

function N._Random()
  return math.random()
end

local function ClearTable(t)
  for k in pairs(t) do t[k] = nil end
end

function N.ResetForTest()
  state.lastReactAt = 0
  ClearTable(state.hourStamps)
  ClearTable(state.lastVariant)
end

function N.Normalize(style)
  if style == "subtle" or style == "playful" or style == "off" then
    return style
  end
  return "off"
end

function N.GetStyle(db)
  db = db or GR.db
  local ui = db and db.ui
  return N.Normalize(ui and ui.nerglishStyle)
end

local function L(key)
  local U = GR.Util
  if U and U.L then return U.L(key) end
  if AngryMurlocsLocale and AngryMurlocsLocale[key] ~= nil then return AngryMurlocsLocale[key] end
  if AngryMurlocsLocaleEN and AngryMurlocsLocaleEN[key] ~= nil then return AngryMurlocsLocaleEN[key] end
  return key
end

local function ValidName(s)
  if type(s) ~= "string" then return false end
  if s == "" or s == "?" then return false end
  return true
end

--- Strip WoW UI escape codes / raw pipes from external names.
function N.Sanitize(s)
  if s == nil then return nil end
  s = tostring(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  s = s:gsub("|T.-|t", "")
  s = s:gsub("|H.-|h", "")
  s = s:gsub("|h", "")
  s = s:gsub("|+", "")
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  if s == "" then return nil end
  return s
end

local function KindPrefix(kind, level)
  if kind == "sight" then return "NERGLISH_SIGHT_" end
  if kind == "death" then return "NERGLISH_DEATH_" end
  if kind == "lvl_milestone" then return "NERGLISH_LVL_M_" end
  if kind == "lvl" then
    local lvl = tonumber(level)
    if lvl and lvl > 0 and (lvl % 10) == 0 then
      return "NERGLISH_LVL_M_"
    end
    return "NERGLISH_LVL_"
  end
  return nil
end

local function CountHour(now)
  local cut = now - 3600
  local stamps = state.hourStamps
  local n = 0
  for i = #stamps, 1, -1 do
    if stamps[i] < cut then
      table.remove(stamps, i)
    else
      n = n + 1
    end
  end
  return n
end

local function AntiSpamAllows(now, preview)
  if preview then return true end
  if state.lastReactAt > 0 and (now - state.lastReactAt) < GLOBAL_CD then
    return false
  end
  if CountHour(now) >= MAX_PER_HOUR then
    return false
  end
  return true
end

local function Clamp01(r)
  if r < 0 then return 0 end
  if r >= 1 then return 0.999999 end
  return r
end

local function PickRarity(style)
  local rows = (style == "playful") and RARITY_PLAYFUL or RARITY_SUBTLE
  local r = Clamp01(N._Random())
  local acc = 0
  for i = 1, #rows do
    acc = acc + rows[i].p
    if r < acc then return rows[i].id end
  end
  return rows[#rows].id
end

local function PickIndex(poolId, lo, hi)
  local last = state.lastVariant[poolId]
  local choices = {}
  for i = lo, hi do
    if i ~= last then choices[#choices + 1] = i end
  end
  if #choices == 0 then
    for i = lo, hi do choices[#choices + 1] = i end
  end
  local r = Clamp01(N._Random())
  return choices[math.floor(r * #choices) + 1]
end

local function BookReact(now, poolId, index, preview)
  if preview then return end
  state.lastReactAt = now
  state.hourStamps[#state.hourStamps + 1] = now
  state.lastVariant[poolId] = index
end

function N.Fill(tmpl, map)
  if type(tmpl) ~= "string" or tmpl == "" then return nil end
  map = type(map) == "table" and map or {}
  local missing = false
  local out = tmpl:gsub("{(%w+)}", function(k)
    local v = map[k]
    if v == nil or v == "" then
      missing = true
      return ""
    end
    return tostring(v)
  end)
  if missing then return nil end
  if out:find("{", 1, true) then return nil end
  return out
end

local function LocaleKey(prefix, style, rarity, index)
  if rarity == "normal" then
    local tag = (style == "playful") and "PLAYFUL_" or "SUBTLE_"
    return prefix .. tag .. tostring(index)
  end
  if rarity == "rare" then
    return prefix .. "RARE_" .. string.format("%02d", index)
  end
  if rarity == "legend" then
    return prefix .. "LEGEND_" .. string.format("%02d", index)
  end
  return nil
end

local function PoolBounds(style, rarity)
  if rarity == "normal" then return 1, NORMAL_SIZE end
  if rarity == "rare" then
    if style == "subtle" then return RARE_LO, RARE_SUBTLE_HI end
    return RARE_LO, RARE_HI
  end
  if rarity == "legend" then return LEGEND_LO, LEGEND_HI end
  return nil
end

local function ResolveTemplate(kind, prefix, style, rarity, map)
  local lo, hi = PoolBounds(style, rarity)
  if not lo then return nil end
  local poolId = prefix .. rarity
  local index = PickIndex(poolId, lo, hi)
  local key = LocaleKey(prefix, style, rarity, index)
  if not key then return nil end
  local tmpl = L(key)
  if type(tmpl) ~= "string" or tmpl == "" or tmpl == key then
    return nil
  end
  if kind == "sight" then
    if tmpl:find("{", 1, true) then return nil end
    return { cry = tmpl, poolId = poolId, index = index }
  end
  local text = N.Fill(tmpl, map)
  if not text then return nil end
  return { text = text, poolId = poolId, index = index }
end

--- facts: { kind, player|victim, level, zone, target, reporter, preview }
function N.TryReact(facts, now)
  facts = type(facts) == "table" and facts or {}
  now = tonumber(now) or 0
  local style = N.GetStyle()
  if style == "off" then return nil end

  local kind = facts.kind
  local prefix = KindPrefix(kind, facts.level)
  if not prefix then return nil end

  local map = {}
  if kind == "death" then
    local victim = N.Sanitize(facts.victim or facts.player)
    if not ValidName(victim) then return nil end
    map.player = victim
    local zone = N.Sanitize(facts.zone)
    if zone then map.zone = zone end
  elseif kind == "lvl" or kind == "lvl_milestone" then
    local player = N.Sanitize(facts.player or facts.victim)
    local level = tonumber(facts.level)
    if not ValidName(player) then return nil end
    if not level or level < 1 then return nil end
    map.player = player
    map.level = level
  elseif kind ~= "sight" then
    return nil
  end

  local preview = facts.preview == true
  if not AntiSpamAllows(now, preview) then return nil end

  if not preview then
    local chance = CHANCE[style] or 0
    if N._Random() >= chance then return nil end
  end

  local rarity = PickRarity(style)
  local result = ResolveTemplate(kind, prefix, style, rarity, map)
  if not result and rarity ~= "normal" then
    result = ResolveTemplate(kind, prefix, style, "normal", map)
  end
  if not result then return nil end

  BookReact(now, result.poolId, result.index, preview)
  if result.cry then return { cry = result.cry } end
  return { text = result.text }
end

N.CHANCE = CHANCE
N.GLOBAL_CD = GLOBAL_CD
N.MAX_PER_HOUR = MAX_PER_HOUR
N.NORMAL_SIZE = NORMAL_SIZE
N.POOL_SIZE = NORMAL_SIZE
N.RARE_SUBTLE_HI = RARE_SUBTLE_HI
N.RARITY_PLAYFUL = RARITY_PLAYFUL
N.RARITY_SUBTLE = RARITY_SUBTLE
