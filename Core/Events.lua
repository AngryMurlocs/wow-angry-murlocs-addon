local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR._messages = GR._messages or {}

function GR:RegisterMessage(msg, handler)
  if not self._messages[msg] then
    self._messages[msg] = {}
  end
  self._messages[msg][#self._messages[msg] + 1] = handler
end

function GR:SendMessage(msg, ...)
  local list = self._messages[msg]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], msg, ...)
    if not ok and GR.Util then
      GR.Util.Print("Event error [" .. tostring(msg) .. "]: " .. tostring(err))
    end
  end
end
