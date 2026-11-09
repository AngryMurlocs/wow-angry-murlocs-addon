-- Multi-client simulator: each client loads the real addon files into its own
-- global environment (setfenv), with a shared virtual clock and a shared guild
-- addon channel. WoW APIs are stubbed only as far as the loaded code needs.
-- This is a simulation, not a client test: no real WoW API behaviour is checked.

local Sim = {}
Sim.__index = Sim

local WALL0 = 1700000000
local LATENCY = 0.05

local FILES = {
  "Localization/enUS.lua",
  "Core/Util.lua",
  "Core/Theme.lua",
  "Core/Protocol.lua",
  "Core/Queue.lua",
  "Core/Events.lua",
  "Core/Diag.lua",
  "Core/Comm.lua",
  "Core/WantedLogic.lua",
}

local function DeepCopy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = DeepCopy(x) end
  return c
end
Sim.DeepCopy = DeepCopy

-- Frame stub: capitalized keys are callable stubs (methods or child regions such
-- as TitleText); calling one returns nil, Create* calls return a new stub.
-- Lowercase fields stay nil until assigned.
local Stub
local function Callable(create)
  local s = Stub()
  getmetatable(s).__call = function() if create then return Stub() end return nil end
  return s
end
Stub = function()
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) ~= "string" or not k:match("^%u") then return nil end
      local v = Callable(k:match("^Create") ~= nil)
      rawset(t, k, v)
      return v
    end,
  })
end
Sim.Stub = Stub

function Sim.New(seed, latency)
  math.randomseed(seed or 1)
  local s = setmetatable({ clock = 0, timers = {}, seq = 0, clients = {}, bus = {}, latency = latency or LATENCY }, Sim)
  return s
end

function Sim:Wall()
  return WALL0 + math.floor(self.clock)
end

function Sim:Schedule(delay, fn, interval)
  self.seq = self.seq + 1
  local t = { at = self.clock + math.max(delay or 0, 0), fn = fn, interval = interval, seq = self.seq }
  t.Cancel = function(timer) timer.cancelled = true end
  t.IsCancelled = function(timer) return timer.cancelled end
  self.timers[#self.timers + 1] = t
  return t
end

function Sim:Step(dt)
  local target = self.clock + dt
  while true do
    local nextT, idx
    for i, t in ipairs(self.timers) do
      if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at
          or (t.at == nextT.at and t.seq < nextT.seq)) then
        nextT, idx = t, i
      end
    end
    if not nextT then break end
    table.remove(self.timers, idx)
    if nextT.at > self.clock then self.clock = nextT.at end
    nextT.fn(nextT)
    if nextT.interval and not nextT.cancelled then
      nextT.at = self.clock + nextT.interval
      self.seq = self.seq + 1
      nextT.seq = self.seq
      self.timers[#self.timers + 1] = nextT
    end
  end
  self.clock = target
  -- drop cancelled timers
  for i = #self.timers, 1, -1 do
    if self.timers[i].cancelled then table.remove(self.timers, i) end
  end
end

function Sim:Run(seconds)
  local steps = math.ceil(seconds / 0.05)
  for _ = 1, steps do self:Step(0.05) end
end

function Sim:Deliver(from, prefix, msg, channel)
  if not from.online then return end
  self.bus[#self.bus + 1] = { t = self.clock, from = from.name, msg = msg }
  for _, c in ipairs(self.clients) do
    if c ~= from and c.online and c.guild and c.guild == from.guild then
      self:Schedule(self.latency, function()
        if c.online then
          c.GR.Comm:OnAddonMessage(prefix, msg, channel, from.name .. "-Realm")
        end
      end)
    end
  end
end

-- Messages on the bus whose tag matches (e.g. "WSH").
function Sim:Count(tag, filter)
  local n = 0
  for _, m in ipairs(self.bus) do
    if m.msg:match("^" .. tag .. "|") and (not filter or filter(m)) then n = n + 1 end
  end
  return n
end

local function DefaultDB()
  return {
    privacy = {
      sharePosition = true, shareProfessions = true, shareDeath = true,
      shareLevelUp = true, shareSightings = true,
    },
    scopes = {},
    diag = { enabled = false },
    wantedUI = {},
    schema = 2,
  }
end
Sim.DefaultDB = DefaultDB

-- opts: { guild = "Murlocs", db = savedTable, extraFiles = {...}, env = {...} }
function Sim:AddClient(name, opts)
  opts = opts or {}
  local sim = self
  local c = { name = name, guild = opts.guild ~= false and (opts.guild or "Angry Murlocs") or nil, online = true, prints = {} }
  local env = setmetatable({}, { __index = _G })
  env._G = env
  -- isolate from any addon table the test file itself loaded into _G
  env.AngryMurlocs = false
  env.AngryMurlocsLocale = false
  env.GetTime = function() return sim.clock end
  env.GetServerTime = function() return sim:Wall() end
  env.time = function() return sim:Wall() end
  env.date = os.date
  env.GetLocale = function() return "enUS" end
  env.GetNormalizedRealmName = function() return "Realm" end
  env.GetRealmName = function() return "Realm" end
  env.GetGuildInfo = function() return c.guild end
  env.IsInGuild = function() return c.guild ~= nil end
  env.UnitFullName = function(unit)
    if unit == "player" then return name, "Realm" end
    return nil
  end
  env.UnitName = function(unit)
    if unit == "player" then return name end
    return nil
  end
  env.GetZoneText = function() return "Hillsbrad" end
  env.UnitClass = function() return "Mage", "MAGE" end
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.prints[#c.prints + 1] = m end }
  env.CreateFrame = function() return Stub() end
  env.UIParent = Stub()
  env.Minimap = Stub()
  env.GameTooltip = Stub()
  env.C_Timer = {
    After = function(d, fn) sim:Schedule(d, fn) end,
    NewTimer = function(d, fn) return sim:Schedule(d, fn) end,
    NewTicker = function(i, fn) return sim:Schedule(i, fn, i) end,
  }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel) sim:Deliver(c, prefix, msg, channel) end,
  }
  for k, v in pairs(opts.env or {}) do env[k] = v end

  local function Load(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk()
  end
  for _, f in ipairs(FILES) do Load(f) end

  local GR = env.AngryMurlocs
  GR._modules, GR._moduleOrder = {}, {}
  function GR:NewModule(n)
    local mod = { name = n }
    self._modules[n] = mod
    self._moduleOrder[#self._moduleOrder + 1] = n
    return mod
  end
  function GR:GetModule(n) return self._modules[n] end
  GR.db = opts.db or DefaultDB()
  GR.VERSION = "sim"

  for _, f in ipairs(opts.extraFiles or {
    "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua",
  }) do Load(f) end
  for _, n in ipairs(GR._moduleOrder) do
    local mod = GR._modules[n]
    if mod.OnEnable then mod:OnEnable() end
  end

  c.env, c.GR = env, GR
  c.Wanted = GR:GetModule("Wanted")
  self.clients[#self.clients + 1] = c
  return c
end

-- Simulated /reload: same SavedVariables, fresh code state.
function Sim:Reload(c)
  c.online = false
  local db = DeepCopy(c.GR.db)
  local idx
  for i, x in ipairs(self.clients) do if x == c then idx = i end end
  table.remove(self.clients, idx)
  return self:AddClient(c.name, { guild = c.guild, db = db })
end

function Sim.Level(c, killer)
  local scope = c.GR.Util.GetScopeDB()
  local e = scope.wanted[killer]
  return e and c.GR.WantedLogic.Level(e) or 0
end

function Sim.Entries(c)
  local n = 0
  for _ in pairs(c.GR.Util.GetScopeDB().wanted) do n = n + 1 end
  return n
end

return Sim
