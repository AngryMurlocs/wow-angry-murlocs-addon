-- Session-only player status lines (Options → Log → Status). Never networked.
local GR = AngryMurlocs
local U = GR.Util

local ActivityLog = {
  buf = {},
  head = 0,
  size = 0,
  max = 100,
  seq = 0,
}
GR.ActivityLog = ActivityLog

function ActivityLog:Add(msg)
  msg = tostring(msg or "")
  self.seq = self.seq + 1
  self.head = (self.head % self.max) + 1
  local entry = { seq = self.seq, t = U.Now(), msg = msg }
  self.buf[self.head] = entry
  if self.size < self.max then
    self.size = self.size + 1
  end
  if GR.SendMessage then
    GR:SendMessage("ACTIVITY_LOG_CHANGED")
  end
  return entry
end

function ActivityLog:Entries(n)
  local out = {}
  local take = self.size
  if n ~= nil then
    take = math.min(tonumber(n) or 0, self.size)
  end
  local idx = self.head
  for _ = 1, take do
    out[#out + 1] = self.buf[idx]
    idx = idx - 1
    if idx < 1 then idx = self.max end
  end
  return out
end

function ActivityLog:Clear()
  wipe(self.buf)
  self.head, self.size = 0, 0
  if GR.SendMessage then
    GR:SendMessage("ACTIVITY_LOG_CHANGED")
  end
end
