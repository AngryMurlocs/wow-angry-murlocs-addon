-- Local diagnostics: counters always (memory only), ring buffer only when enabled.
-- Nothing here is ever sent anywhere.
local GR = AngryMurlocs
local U = GR.Util

local Diag = {
  buf = {},
  head = 0,
  size = 0,
  max = 200,
  counters = {},
  deaths = {},
  maxDeaths = 5,
}
GR.Diag = Diag

function Diag:Enabled()
  return GR.db and GR.db.diag and GR.db.diag.enabled == true
end

function Diag:SetEnabled(on)
  if not GR.db then return end
  GR.db.diag = GR.db.diag or {}
  GR.db.diag.enabled = on and true or false
  if not on then
    wipe(self.buf)
    self.head, self.size = 0, 0
  end
  GR:SendMessage("DIAG_CHANGED", self:Enabled())
end

function Diag:Count(key, n)
  self.counters[key] = (self.counters[key] or 0) + (n or 1)
end

function Diag:Log(kind, fmt, ...)
  self:Count(kind)
  if not self:Enabled() then return end
  local msg = tostring(fmt or "")
  if select("#", ...) > 0 then
    local ok, s = pcall(string.format, msg, ...)
    msg = ok and s or msg
  end
  self.head = (self.head % self.max) + 1
  self.buf[self.head] = { t = U.Now(), kind = kind, msg = msg }
  if self.size < self.max then self.size = self.size + 1 end
end

-- Rejected input or suppressed send with a stable reason key.
function Diag:Reject(reason, detail)
  self:Count("reject_" .. tostring(reason))
  self:Log("reject", "%s %s", tostring(reason), tostring(detail or ""))
end

function Diag:Entries(n)
  local out = {}
  n = math.min(n or self.size, self.size)
  local idx = self.head
  for _ = 1, n do
    out[#out + 1] = self.buf[idx]
    idx = idx - 1
    if idx < 1 then idx = self.max end
  end
  return out
end

function Diag:AddDeath(snapshot)
  table.insert(self.deaths, 1, snapshot)
  while #self.deaths > self.maxDeaths do
    self.deaths[#self.deaths] = nil
  end
end

function Diag:Show(n)
  U.Print(string.format(U.L("DIAG_STATE"), self:Enabled() and U.L("GENERAL_ON") or U.L("GENERAL_OFF")))
  local keys = {}
  for k in pairs(self.counters) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for i = 1, #keys do
    parts[#parts + 1] = keys[i] .. "=" .. self.counters[keys[i]]
  end
  if GR.Comm and GR.Comm.QueueSize then
    parts[#parts + 1] = "queue=" .. GR.Comm:QueueSize()
  end
  U.Print(#parts > 0 and table.concat(parts, " ") or "-")
  local entries = self:Entries(n or 20)
  for i = #entries, 1, -1 do
    local e = entries[i]
    U.Print(string.format("[%.1f] %s: %s", e.t or 0, e.kind or "?", e.msg or ""))
  end
end

function Diag:ShowDeaths()
  if #self.deaths == 0 then
    U.Print(U.L("DIAG_NO_DEATH"))
    return
  end
  for i = 1, #self.deaths do
    local d = self.deaths[i]
    U.Print(string.format("#%d %s", i, d.header or ""))
    for j = 1, #(d.lines or {}) do
      U.Print("  " .. d.lines[j])
    end
  end
end
