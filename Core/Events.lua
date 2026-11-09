local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR._messages = GR._messages or {}

function GR:RegisterMessage(msg, handler)
  if not self._messages[msg] then
    self._messages[msg] = {}
  end
  self._messages[msg][#self._messages[msg] + 1] = handler
end

function GR:UnregisterMessage(msg, handler)
  local list = self._messages[msg]
  if not list then return end
  if handler == nil then
    wipe(list)
    return
  end
  for i = #list, 1, -1 do
    if list[i] == handler then
      table.remove(list, i)
    end
  end
end

-- Bind a handler to a module so OnDisable can clear it via UnbindMessages.
function GR:BindMessage(mod, msg, handler)
  if not mod then return end
  mod._boundMessages = mod._boundMessages or {}
  mod._boundMessages[#mod._boundMessages + 1] = { msg = msg, handler = handler }
  self:RegisterMessage(msg, handler)
end

function GR:UnbindMessages(mod)
  if not mod or not mod._boundMessages then return end
  for i = 1, #mod._boundMessages do
    local e = mod._boundMessages[i]
    self:UnregisterMessage(e.msg, e.handler)
  end
  wipe(mod._boundMessages)
end

function GR:ReleaseEventFrame(f)
  if not f then return end
  f:UnregisterAllEvents()
  f:SetScript("OnEvent", nil)
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
