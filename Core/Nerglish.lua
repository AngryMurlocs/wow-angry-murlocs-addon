-- Rare Murloc yells (/y). Styles: off | nerglish | schmaeh. No wire, no toast rewrite.
local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Nerglish = GR.Nerglish or {}
local N = GR.Nerglish

local CHANCE = 0.15
local LEGEND_CHANCE = 0.08
local GLOBAL_CD = 300
local MAX_PER_HOUR = 3
local TEST_CD = 2
-- Outdoor SAY/YELL needs a hardware event; auto yells wait at most this long.
local PENDING_TTL = GLOBAL_CD

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

local PREFIX_SCHMAEH = {
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

local PREFIX_PURE = {
  lvl = "NERGLISH_PURE_LVL_",
  lvl_m = "NERGLISH_PURE_LVL_M_",
  lvl60 = "NERGLISH_PURE_LVL60_",
  death = "NERGLISH_PURE_DEATH_",
  death_repeat = "NERGLISH_PURE_DEATH_REPEAT_",
  sight = "NERGLISH_PURE_SIGHT_",
  wanted_kill = "NERGLISH_PURE_WANTED_KILL_",
  pvp = "NERGLISH_PURE_PVP_",
  guild_join = "NERGLISH_PURE_GUILD_JOIN_",
  loot = "NERGLISH_PURE_LOOT_",
  achievement = "NERGLISH_PURE_ACHIEVEMENT_",
  guild_goal = "NERGLISH_PURE_GUILD_GOAL_",
  idle_hunger = "NERGLISH_PURE_IDLE_HUNGER_",
  idle_schmaeh = "NERGLISH_PURE_IDLE_SCHMAEH_",
  idle_dumb = "NERGLISH_PURE_IDLE_DUMB_",
  idle_lazy = "NERGLISH_PURE_IDLE_LAZY_",
  legend = "NERGLISH_PURE_LEGEND_",
}

local IDLE_KINDS = { "idle_hunger", "idle_schmaeh", "idle_dumb", "idle_lazy" }

local state = {
  lastReactAt = 0,
  hourStamps = {},
  lastVariant = {},
  lastTestAt = 0,
  -- Outdoor auto-yell waiting for next click/key: { text=, at= } or nil.
  pending = nil,
}

local hwFrame = nil

function N._Random()
  return math.random()
end

local function ClearTable(t)
  for k in pairs(t) do t[k] = nil end
end

local function DisarmHw()
  if not hwFrame then return end
  hwFrame:Hide()
  hwFrame:EnableKeyboard(false)
  hwFrame:EnableMouse(false)
  if hwFrame.EnableMouseWheel then hwFrame:EnableMouseWheel(false) end
  hwFrame:SetScript("OnKeyDown", nil)
  hwFrame:SetScript("OnMouseDown", nil)
  if hwFrame.SetScript then
    hwFrame:SetScript("OnMouseWheel", nil)
  end
end

function N.ClearPendingYell()
  state.pending = nil
  DisarmHw()
end

function N.ResetForTest()
  state.lastReactAt = 0
  state.lastTestAt = 0
  ClearTable(state.hourStamps)
  ClearTable(state.lastVariant)
  N.ClearPendingYell()
end

function N.Normalize(style)
  if style == "off" or style == "nerglish" or style == "schmaeh" then
    return style
  end
  return "off"
end

--- Migrate old ui.nerglishYell → nerglishStyle. Safe to call more than once.
function N.MigrateUi(db)
  if type(db) ~= "table" then return end
  db.ui = type(db.ui) == "table" and db.ui or {}
  local ui = db.ui
  local cur = ui.nerglishStyle
  if cur == "off" or cur == "nerglish" or cur == "schmaeh" then
    -- keep chosen style
  elseif cur ~= nil then
    ui.nerglishStyle = "off"
  elseif ui.nerglishYell == true then
    ui.nerglishStyle = "schmaeh"
  else
    ui.nerglishStyle = "off"
  end
  ui.nerglishStyle = N.Normalize(ui.nerglishStyle)
  ui.nerglishYell = nil
end

function N.GetStyle(db)
  db = db or GR.db
  local ui = db and db.ui
  return N.Normalize(ui and ui.nerglishStyle)
end

function N.IsEnabled(db)
  return N.GetStyle(db) ~= "off"
end

local function L(key)
  local U = GR.Util
  if U and U.L then return U.L(key) end
  if AngryMurlocsLocale and AngryMurlocsLocale[key] ~= nil then return AngryMurlocsLocale[key] end
  if AngryMurlocsLocaleEN and AngryMurlocsLocaleEN[key] ~= nil then return AngryMurlocsLocaleEN[key] end
  return key
end

local STYLE_CYCLE = { "off", "nerglish", "schmaeh" }
local STYLE_LABEL = {
  off = "OPT_NERGLISH_OFF",
  nerglish = "OPT_NERGLISH_PURE",
  schmaeh = "OPT_NERGLISH_SCHMAEH",
}

--- Set style; clears any pending outdoor yell on change (incl. Off).
function N.SetStyle(style)
  if not GR.db then return nil end
  GR.db.ui = GR.db.ui or {}
  local nextStyle = N.Normalize(style)
  local cur = N.GetStyle()
  if nextStyle ~= cur or nextStyle == "off" then
    N.ClearPendingYell()
  end
  GR.db.ui.nerglishStyle = nextStyle
  GR.db.ui.nerglishYell = nil
  return nextStyle
end

--- Cycle off → nerglish → schmaeh → off. Returns new style. Prints a short chat line.
function N.CycleStyle()
  if not GR.db then return nil end
  local cur = N.GetStyle()
  local nextStyle = "off"
  for i = 1, #STYLE_CYCLE do
    if STYLE_CYCLE[i] == cur then
      nextStyle = STYLE_CYCLE[(i % #STYLE_CYCLE) + 1]
      break
    end
  end
  N.SetStyle(nextStyle)
  local labelKey = STYLE_LABEL[nextStyle] or "OPT_NERGLISH_OFF"
  local U = GR.Util
  if U and U.Print then
    U.Print(string.format(L("NERGLISH_STYLE_SET"), L(labelKey)))
  end
  return nextStyle
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

local function VariantKey(style, poolId)
  return tostring(style) .. ":" .. tostring(poolId)
end

local function PickIndex(style, poolId, size)
  local vk = VariantKey(style, poolId)
  local last = state.lastVariant[vk]
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

local function BookReact(now, style, poolId, index)
  state.lastReactAt = now
  state.hourStamps[#state.hourStamps + 1] = now
  state.lastVariant[VariantKey(style, poolId)] = index
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

local function NowFallback()
  local U = GR.Util
  if U and U.Now then return U.Now() end
  if GetTime then return GetTime() end
  return 0
end

local function InInstance()
  if type(IsInInstance) ~= "function" then return false end
  local ok, inInst = pcall(IsInInstance)
  if not ok then return false end
  return inInst and true or false
end

local function SendYellNow(text)
  if not C_ChatInfo or type(C_ChatInfo.SendChatMessage) ~= "function" then
    return false
  end
  local ok = pcall(C_ChatInfo.SendChatMessage, text, "YELL")
  return ok and true or false
end

--- Flush one pending outdoor yell if still valid. Used by HW listener and tests.
function N.FlushPendingYell(now)
  now = tonumber(now) or NowFallback()
  local p = state.pending
  if not p or type(p.text) ~= "string" or p.text == "" then
    N.ClearPendingYell()
    return false
  end
  if N.GetStyle() == "off" then
    N.ClearPendingYell()
    return false
  end
  local at = tonumber(p.at) or 0
  if at > 0 and (now - at) > PENDING_TTL then
    N.ClearPendingYell()
    return false
  end
  local text = p.text
  N.ClearPendingYell()
  return SendYellNow(text)
end

local function OnHardware()
  N.FlushPendingYell()
end

local function EnsureHwFrame()
  if hwFrame or type(CreateFrame) ~= "function" then return hwFrame end
  local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent)
  if not ok or not frame then return nil end
  hwFrame = frame
  if hwFrame.SetFrameStrata then hwFrame:SetFrameStrata("TOOLTIP") end
  if hwFrame.SetAllPoints and UIParent then hwFrame:SetAllPoints(UIParent) end
  hwFrame:Hide()
  return hwFrame
end

local function ArmHw()
  local f = EnsureHwFrame()
  if not f then return end
  f:SetScript("OnKeyDown", function(self)
    if self.SetPropagateKeyboardInput then
      pcall(self.SetPropagateKeyboardInput, self, true)
    end
    OnHardware()
  end)
  f:SetScript("OnMouseDown", function()
    OnHardware()
  end)
  if f.EnableMouseWheel then
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function()
      OnHardware()
    end)
  end
  f:EnableKeyboard(true)
  f:EnableMouse(true)
  f:Show()
  if f.EnableKeyboard then f:EnableKeyboard(true) end
end

--- Yell text. fromInput=true: send now (button/keybind). Else outdoor queues one pending slot.
--- Optional now stamps the pending TTL. Returns true if sent or queued.
function N.Yell(text, fromInput, now)
  if type(text) ~= "string" or text == "" then return false end
  if not C_ChatInfo or type(C_ChatInfo.SendChatMessage) ~= "function" then
    return false
  end
  if fromInput or InInstance() then
    return SendYellNow(text)
  end
  now = tonumber(now) or NowFallback()
  state.pending = { text = text, at = now }
  ArmHw()
  return true
end

function N.HasPendingYell()
  return state.pending ~= nil
end

local function PrefixMap(style)
  if style == "nerglish" then return PREFIX_PURE end
  if style == "schmaeh" then return PREFIX_SCHMAEH end
  return nil
end

local function PickLine(kind, style)
  local size = POOL_SIZE[kind]
  local map = PrefixMap(style)
  local prefix = map and map[kind]
  if not size or not prefix then return nil, nil, nil end
  local index = PickIndex(style, kind, size)
  local key = prefix .. tostring(index)
  local text = L(key)
  if type(text) ~= "string" or text == "" or text == key then
    return nil, nil, nil
  end
  if text:find("{", 1, true) then return nil, nil, nil end
  return text, kind, index
end

local function PickLegend(style)
  return PickLine("legend", style)
end

local function AfterPick(now, style, poolId, index, text, bookLimits)
  N.Yell(text, false, now)
  if bookLimits then
    BookReact(now, style, poolId, index)
  else
    state.lastVariant[VariantKey(style, poolId)] = index
  end
  return text
end

--- kind + optional facts. Yells on success. Returns yelled text or nil.
function N.TryReact(kind, now, facts)
  now = tonumber(now) or 0
  local style = N.GetStyle()
  if style == "off" then return nil end
  kind = N.ResolveKind(kind, facts)
  if not POOL_SIZE[kind] then return nil end
  if not AntiSpamAllows(now) then return nil end
  if N._Random() >= CHANCE then return nil end

  local text, poolId, index
  if N._Random() < LEGEND_CHANCE then
    text, poolId, index = PickLegend(style)
  end
  if not text then
    text, poolId, index = PickLine(kind, style)
  end
  if not text then return nil end
  return AfterPick(now, style, poolId, index, text, true)
end

function N.TryIdle(now)
  now = tonumber(now) or 0
  local style = N.GetStyle()
  if style == "off" then return nil end
  if not AntiSpamAllows(now) then return nil end
  if N._Random() >= CHANCE then return nil end

  local text, poolId, index
  if N._Random() < LEGEND_CHANCE then
    text, poolId, index = PickLegend(style)
  end
  if not text then
    local r = Clamp01(N._Random())
    local sub = IDLE_KINDS[math.floor(r * #IDLE_KINDS) + 1]
    text, poolId, index = PickLine(sub, style)
  end
  if not text then return nil end
  return AfterPick(now, style, poolId, index, text, true)
end

--- Forced test yell. Bypasses auto limits; 2s click throttle. Off → preview nerglish.
--- fromInput=true: send immediately (Options button / keybind hardware path).
function N.TestYell(now, fromInput)
  now = tonumber(now)
  if not now then
    now = NowFallback()
  end
  if state.lastTestAt > 0 and (now - state.lastTestAt) < TEST_CD then
    return nil
  end
  local style = N.GetStyle()
  if style == "off" then style = "nerglish" end
  local text, poolId, index = PickLegend(style)
  if not text then return nil end
  N.Yell(text, fromInput and true or false, now)
  state.lastTestAt = now
  if poolId and index then
    state.lastVariant[VariantKey(style, poolId)] = index
  end
  return text
end

N.CHANCE = CHANCE
N.LEGEND_CHANCE = LEGEND_CHANCE
N.GLOBAL_CD = GLOBAL_CD
N.MAX_PER_HOUR = MAX_PER_HOUR
N.TEST_CD = TEST_CD
N.PENDING_TTL = PENDING_TTL
N.POOL_SIZE = POOL_SIZE
N.PREFIX_SCHMAEH = PREFIX_SCHMAEH
N.PREFIX_PURE = PREFIX_PURE
N.IDLE_KINDS = IDLE_KINDS
N.PREFIX = PREFIX_SCHMAEH
