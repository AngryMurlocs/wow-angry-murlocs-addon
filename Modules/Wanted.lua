local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm
local Logic = GR.WantedLogic
local P = GR.Protocol

local Wanted = GR:NewModule("Wanted")

local SEND_CD = 60
local ALERT_CD = 20

local sendCd = {}   -- targetKey -> GetTime
local alertCd = {}  -- targetKey -> GetTime

Wanted.cfg = Logic.GetFixedConfig()
local cfg = Wanted.cfg

function Wanted:Diag()
  return GR.Diag
end

function Wanted:Reject(reason, detail)
  if GR.Diag then GR.Diag:Reject(reason, detail) end
end

function Wanted:Scope()
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

function Wanted:State()
  local scope = self:Scope()
  return { wanted = scope.wanted, hidden = scope.wantedHidden }
end

function Wanted:SelfKey()
  return U.CharKey(U.PlayerName())
end

function Wanted:SelfState()
  local scope = self:Scope()
  local key = self:SelfKey() or "?"
  scope.wantedSelf[key] = scope.wantedSelf[key] or { seq = 0, kills = {} }
  return scope.wantedSelf[key]
end

function Wanted:Now()
  return U.WallTime()
end

function Wanted:NormalizeKiller(name)
  if not name or name == "" then return nil end
  return U.NormalizeName(name)
end

function Wanted:PlayerZone()
  local z = GetZoneText and GetZoneText() or ""
  if z == "" and GetRealZoneText then
    z = GetRealZoneText() or ""
  end
  return U.SanitizeText(z, 48)
end

local function FormatAge(ts)
  if not ts or ts <= 0 then return "-" end
  local age = Wanted:Now() - ts
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

local refreshPending = false

function Wanted:PruneNow()
  local stats = Logic.Prune(self:State(), cfg, self:Now())
  if stats.removedEntries > 0 or stats.removedOrigins > 0 then
    self:Reject("cap", string.format("entries=%d origins=%d", stats.removedEntries, stats.removedOrigins))
  end
end

function Wanted:ScheduleRefresh()
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
  local key = self:NormalizeKiller(killer)
  if not key then return { ok = false, reason = "bad_names" } end
  local me = U.PlayerName()
  local r = Logic.RecordOwnDeath(self:State(), cfg, self:SelfState(), key, me, zone or "", self:Now())
  if not r.ok then
    self:Reject(r.reason, key)
    return r
  end
  if self:Diag() then self:Diag():Log("wanted", "own %s n=%d seq=%d", key, r.n, r.seq) end
  self:ScheduleRefresh()
  GR:SendMessage("WANTED_KILL", key, U.ShortName(me), r.level, "own")
  if GR.db.privacy.shareDeath then
    local payload = P.EncodeWK({
      killer = key, origin = U.ShortName(me), n = r.n, seq = r.seq, t = r.t, zone = r.zone,
    })
    if payload then Comm:Send(payload, "kill", "death") end
  else
    self:Reject("privacy", "WK " .. key)
  end
  return r
end

function Wanted:ApplySighting(target, zone, reporter, ts)
  local key = self:NormalizeKiller(target)
  if not key then return false end
  local ok = Logic.ApplySighting(self:State(), cfg, key, ts, zone or "", U.NormalizeName(reporter or ""), self:Now())
  if ok then
    local entry = self:State().wanted[key]
    GR:SendMessage("SIGHT_APPLIED", key, entry.lastSeenZone, entry.lastSeenBy)
    self:ScheduleRefresh()
  end
  return ok
end

function Wanted:SetClassFile(killer, classFile)
  local key = self:NormalizeKiller(killer)
  if not key or not classFile or classFile == "" then return false end
  local entry = self:State().wanted[key]
  if not entry then return false end
  if entry.classFile == classFile then return false end
  entry.classFile = classFile
  GR:SendMessage("WANTED_CHANGED")
  return true
end

function Wanted:Summary()
  local list = Logic.Sorted(self:State(), self:Now(), { includeHidden = true })
  return { total = #list, hidden = 0, top = list[1] }
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
  if GR.Sounds and GR.Sounds.Play then
    GR.Sounds.Play("sight")
  end
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
  local key = Wanted:NormalizeKiller(full)
  if not key then return end
  if not Wanted:State().wanted[key] then return end

  if UnitClass then
    local _, classFile = UnitClass("target")
    if classFile then
      Wanted:SetClassFile(key, classFile)
    end
  end

  local zone = Wanted:PlayerZone()
  local me = U.NormalizeName(U.PlayerName())
  local nowSession = U.Now()
  local wall = Wanted:Now()

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

function Wanted:OnEnable()
  if self.enabled then return end
  self.enabled = true

  self:Scope()
  self:PruneNow()
  -- Local hide feature removed; clear any leftover markers from older versions.
  local st = self:State()
  if st and type(st.hidden) == "table" then
    wipe(st.hidden)
  end

  local targetFrame = CreateFrame("Frame")
  self._targetFrame = targetFrame
  U.SafeRegisterEvent(targetFrame, "PLAYER_TARGET_CHANGED")
  targetFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_TARGET_CHANGED" then
      OnTargetChanged()
    end
  end)

  GR:BindMessage(self, "SIGHT_UPDATE", function(_, sender, data)
    if not data or not data.target then return end
    -- Never rebroadcast received sightings
    if Wanted:ApplySighting(data.target, data.zone, sender, data.ts) then
      MaybeAlert(data.target, data.zone, sender)
    end
  end)

  if self._EnableSync then self:_EnableSync() end
  if self._EnablePanel then self:_EnablePanel() end
end

function Wanted:OnDisable()
  if not self.enabled then return end
  self.enabled = false
  if self._DisableSync then self:_DisableSync() end
  if self._DisablePanel then self:_DisablePanel() end
  GR:UnbindMessages(self)
  GR:ReleaseEventFrame(self._targetFrame)
  self._targetFrame = nil
end
