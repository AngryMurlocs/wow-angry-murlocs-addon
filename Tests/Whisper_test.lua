-- Whisper buttons open a whisper on Forever (ChatFrameUtil) and on older
-- clients (ChatFrame_SendTell / ChatFrameEditBox).
-- From repo root: luajit Tests/Whisper_test.lua
local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

local function LoadUtil(env)
  env = setmetatable(env, { __index = _G })
  env.AngryMurlocs = false
  env.AngryMurlocsLocale = false
  local chunk = assert(loadfile("Core/Util.lua"))
  setfenv(chunk, env)
  chunk()
  return env.AngryMurlocs.Util
end

local function EditBox(text)
  local box = { text = text or "", shown = false }
  function box:GetText() return self.text end
  function box:SetText(t) self.text = t end
  function box:Show() self.shown = true end
  return box
end

-- Forever: only ChatFrameUtil exists.
do
  local calls = {}
  local U = LoadUtil({ ChatFrameUtil = {
    SendTell = function(name) calls[#calls + 1] = "tell " .. name end,
    SendTellWithMessage = function(name, text) calls[#calls + 1] = "msg " .. name .. " " .. text end,
    GetActiveWindow = function() return nil end,
  } })
  check("forever whisper", U.OpenWhisper("Bob") == true and calls[1] == "tell Bob", calls[1])
  check("forever whisper with text", U.OpenWhisper("Bob", "hi") == true and calls[2] == "msg Bob hi", calls[2])
  check("forever chat not busy", U.ChatBusy() == false)
end

-- Forever with an open chat line that already has text: busy.
do
  local U = LoadUtil({ ChatFrameUtil = { GetActiveWindow = function() return EditBox("typing") end } })
  check("forever chat busy", U.ChatBusy() == true)
end

-- Older client: ChatFrame_SendTell plus edit box for the text.
do
  local box = EditBox()
  local told
  local U = LoadUtil({
    ChatFrame_SendTell = function(name) told = name end,
    ChatFrameEditBox = box,
  })
  check("old whisper", U.OpenWhisper("Bob", "hi") == true and told == "Bob" and box.text == "hi", box.text)
end

-- Oldest fallback: only the edit box.
do
  local box = EditBox()
  local U = LoadUtil({ ChatFrameEditBox = box })
  check("edit box fallback", U.OpenWhisper("Bob") == true and box.text == "/w Bob " and box.shown, box.text)
end

-- Nothing available: reports failure instead of erroring.
do
  local U = LoadUtil({})
  check("no chat api", U.OpenWhisper("Bob") == false)
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
