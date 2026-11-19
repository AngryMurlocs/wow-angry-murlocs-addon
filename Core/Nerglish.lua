-- Rare Murloc yells (/y). No wire, no toast rewrite.
local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Nerglish = GR.Nerglish or {}
local N = GR.Nerglish

local CHANCE = 0.15
local LEGEND_CHANCE = 0.08
local GLOBAL_CD = 300
local MAX_PER_HOUR = 3

local POOL_SIZE = {
  lvl = 6,
  lvl_m = 3,
  lvl60 = 3,
  death = 6,
  death_repeat = 6,
  sight = 6,
  wanted_kill = 3,
  pvp = 3,
  guild_join = 6,
  loot = 6,
  achievement = 6,
  guild_goal = 6,
  idle_hunger = 12,
  idle_schmaeh = 12,
  idle_dumb = 12,
  idle_lazy = 12,
  legend = 12,
}

local PREFIX = {
  lvl = "NERGLISH_LVL_",
  lvl_m = "NERGLISH_LVL_M_",
  lvl60 = "NERGLISH_LVL60_",
  death = "NERGLISH_DEATH_",
  death_repeat = "NERGLISH_DEATH_REPEAT_",
  sight = "NERGLISH_SIGHT_",
  wanted_kill = "NERGLISH_WANTED_KILL_",
  pvp = "NERGLISH_PVP_",
  guild_join = "NERGLISH_GUILD_JOIN_",
  loot = "NERGLISH_LOOT_",
  achievement = "NERGLISH_ACHIEVEMENT_",
  guild_goal = "NERGLISH_GUILD_GOAL_",
  idle_hunger = "NERGLISH_IDLE_HUNGER_",
  idle_schmaeh = "NERGLISH_IDLE_SCHMAEH_",
  idle_dumb = "NERGLISH_IDLE_DUMB_",
  idle_lazy = "NERGLISH_IDLE_LAZY_",
  legend = "NERGLISH_LEGEND_",
}

local IDLE_KINDS = { "idle_hunger", "idle_schmaeh", "idle_dumb", "idle_lazy" }

local TEST_CD = 2

local state = {
  lastReactAt = 0,
  hourStamps = {},
  lastVariant = {},
  lastTestAt = 0,
}

function N._Random()
  return math.random()
end

local function ClearTable(t)
  for k in pairs(t) do t[k] = nil end
end

function N.ResetForTest()
  state.lastReactAt = 0
  state.lastTestAt = 0
  ClearTable(state.hourStamps)
  ClearTable(state.lastVariant)
end

local function L(key)
  local U = GR.Util
  if U and U.L then return U.L(key) end
  if AngryMurlocsLocale and AngryMurlocsLocale[key] ~= nil then return AngryMurlocsLocale[key] end
  if AngryMurlocsLocaleEN and AngryMurlocsLocaleEN[key] ~= nil then return AngryMurlocsLocaleEN[key] end
  return key
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

local function AntiSpamAllows(now)
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

local function PickIndex(poolId, size)
  local last = state.lastVariant[poolId]
  local choices = {}
  for i = 1, size do
    if i ~= last then choices[#choices + 1] = i end
  end
  if #choices == 0 then
    for i = 1, size do choices[#choices + 1] = i end
  end
  local r = Clamp01(N._Random())
  return choices[math.floor(r * #choices) + 1]
end

local function BookReact(now, poolId, index)
  state.lastReactAt = now
  state.hourStamps[#state.hourStamps + 1] = now
  state.lastVariant[poolId] = index
end

function N.ResolveKind(kind, facts)
  facts = type(facts) == "table" and facts or {}
  if kind == "lvl" then
    local level = tonumber(facts.level)
    if level and level == 60 then return "lvl60" end
    if level and level > 0 and (level % 10) == 0 then return "lvl_m" end
    return "lvl"
  end
  if kind == "death" then
    if facts.repeatDeath == true then return "death_repeat" end
    return "death"
  end
  return kind
end

function N.Yell(text)
  if type(text) ~= "string" or text == "" then return false end
  if not C_ChatInfo or type(C_ChatInfo.SendChatMessage) ~= "function" then
    return false
  end
  local ok = pcall(C_ChatInfo.SendChatMessage, text, "YELL")
  return ok and true or false
end

local function PickLine(kind)
  local size = POOL_SIZE[kind]
  local prefix = PREFIX[kind]
  if not size or not prefix then return nil, nil, nil end
  local index = PickIndex(kind, size)
  local key = prefix .. tostring(index)
  local text = L(key)
  if type(text) ~= "string" or text == "" or text == key then
    return nil, nil, nil
  end
  if text:find("{", 1, true) then return nil, nil, nil end
  return text, kind, index
end

local function PickLegend()
  return PickLine("legend")
end

local function AfterPick(now, poolId, index, text)
  N.Yell(text)
  BookReact(now, poolId, index)
  return text
end

function N.IsEnabled(db)
  db = db or GR.db
  local ui = db and db.ui
  return ui and ui.nerglishYell == true
end

--- kind + optional facts. Yells on success. Returns yelled text or nil.
function N.TryReact(kind, now, facts)
  now = tonumber(now) or 0
  if not N.IsEnabled() then return nil end
  kind = N.ResolveKind(kind, facts)
  if not POOL_SIZE[kind] or not PREFIX[kind] then return nil end
  if not AntiSpamAllows(now) then return nil end
  if N._Random() >= CHANCE then return nil end

  local text, poolId, index
  if N._Random() < LEGEND_CHANCE then
    text, poolId, index = PickLegend()
  end
  if not text then
    text, poolId, index = PickLine(kind)
  end
  if not text then return nil end
  return AfterPick(now, poolId, index, text)
end

--- Idle chatter. Same anti-spam / legend rules.
function N.TryIdle(now)
  now = tonumber(now) or 0
  if not N.IsEnabled() then return nil end
  if not AntiSpamAllows(now) then return nil end
  if N._Random() >= CHANCE then return nil end

  local text, poolId, index
  if N._Random() < LEGEND_CHANCE then
    text, poolId, index = PickLegend()
  end
  if not text then
    local r = Clamp01(N._Random())
    local sub = IDLE_KINDS[math.floor(r * #IDLE_KINDS) + 1]
    text, poolId, index = PickLine(sub)
  end
  if not text then return nil end
  return AfterPick(now, poolId, index, text)
end

--- Forced test yell (Options). Bypasses chance/CD/hour; 2s click throttle only.
function N.TestYell(now)
  now = tonumber(now)
  if not now then
    local U = GR.Util
    now = (U and U.Now and U.Now()) or 0
  end
  if state.lastTestAt > 0 and (now - state.lastTestAt) < TEST_CD then
    return nil
  end
  local text, poolId, index = PickLegend()
  if not text then return nil end
  N.Yell(text)
  state.lastTestAt = now
  if poolId and index then
    state.lastVariant[poolId] = index
  end
  return text
end

N.CHANCE = CHANCE
N.LEGEND_CHANCE = LEGEND_CHANCE
N.GLOBAL_CD = GLOBAL_CD
N.MAX_PER_HOUR = MAX_PER_HOUR
N.TEST_CD = TEST_CD
N.POOL_SIZE = POOL_SIZE
N.PREFIX = PREFIX
N.IDLE_KINDS = IDLE_KINDS
