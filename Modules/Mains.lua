local GR = AngryMurlocs
local U = GR.Util
local Comm = GR.Comm

local Mains = GR:NewModule("Mains")

local frame
local editBox
local syncBusy = false

local function EnsureDB()
  local scope = U.GetScopeDB()
  return scope and scope.mains or {}
end

local function Me()
  return U.NormalizeName(U.PlayerName())
end

function Mains:GetMain(charName)
  local key = U.NormalizeName(charName)
  if not key then return nil end
  local db = EnsureDB()
  local e = db[key]
  if e and e.main and e.main ~= "" then
    return e.main
  end
  return nil
end

function Mains:GetLabel(charName)
  local main = Mains:GetMain(charName)
  if not main then return nil end
  return string.format(U.L("MAIN_LABEL"), U.ShortName(charName), U.ShortName(main))
end

function Mains:ApplyRemote(char, action, main, ver, ts)
  local key = U.NormalizeName(char)
  if not key then return false end
  -- Protocol: only the sending character may change their own mapping
  -- (enforced in Comm by setting char=sender; double-check here)
  local db = EnsureDB()
  local cur = db[key]
  ver = tonumber(ver) or 0
  ts = tonumber(ts) or 0
  if ver < 1 then return false end
  if cur and (cur.ver or 0) > ver then
    return false
  end
  if cur and (cur.ver or 0) == ver and (cur.ts or 0) >= ts then
    return false
  end

  if action == "clear" then
    if cur then
      -- Keep tombstone so stale sync cannot resurrect
      db[key] = { main = nil, ver = ver, ts = ts, cleared = true }
    else
      db[key] = { main = nil, ver = ver, ts = ts, cleared = true }
    end
  else
    main = U.NormalizeName(main)
    if not main or main == "" then return false end
    db[key] = { main = main, ver = ver, ts = ts, cleared = false }
  end
  GR:SendMessage("MAINS_CHANGED")
  return true
end

local function NextVer(char)
  local db = EnsureDB()
  local cur = db[char]
  return ((cur and cur.ver) or 0) + 1
end

function Mains:SetLocal(mainName, broadcast)
  local me = Me()
  mainName = U.NormalizeName(mainName)
  if not mainName or mainName == "" then
    U.Print(U.L("MAIN_NEED_NAME"))
    return
  end
  local ver = NextVer(me)
  local ts = U.WallTime()
  Mains:ApplyRemote(me, "set", mainName, ver, ts)
  if broadcast and IsInGuild and IsInGuild() then
    Comm:Send(string.format(
      "MAIN|set|%s|%d|%d",
      U.SanitizeText(mainName, 48),
      ver,
      ts
    ))
  end
  U.Print(string.format(U.L("MAIN_SET_OK"), U.ShortName(me), U.ShortName(mainName)))
  if frame and frame:IsShown() then
    Mains:Refresh()
  end
end

function Mains:ClearLocal(broadcast)
  local me = Me()
  local ver = NextVer(me)
  local ts = U.WallTime()
  Mains:ApplyRemote(me, "clear", nil, ver, ts)
  if broadcast and IsInGuild and IsInGuild() then
    Comm:Send(string.format("MAIN|clear|%d|%d", ver, ts))
  end
  U.Print(U.L("MAIN_CLEARED"))
  if frame and frame:IsShown() then
    Mains:Refresh()
  end
end

function Mains:PrintStatus()
  local me = Me()
  local main = Mains:GetMain(me)
  if main then
    U.Print(string.format(U.L("MAIN_STATUS"), U.ShortName(me), U.ShortName(main)))
  else
    U.Print(U.L("MAIN_NONE"))
  end
end

-- On SYNCREQ each client broadcasts only THEIR OWN mapping (sender == char).
function Mains:BroadcastOwn()
  if not IsInGuild or not IsInGuild() then return end
  local me = Me()
  local db = EnsureDB()
  local e = db[me]
  if not e or not e.ver then return end
  if e.cleared or not e.main then
    Comm:Send(string.format("MAIN|clear|%d|%d", e.ver, e.ts or 0))
  else
    Comm:Send(string.format(
      "MAIN|set|%s|%d|%d",
      U.SanitizeText(e.main, 48),
      e.ver,
      e.ts or 0
    ))
  end
end

function Mains:RequestSync()
  if syncBusy then return end
  if not IsInGuild or not IsInGuild() then return end
  syncBusy = true
  Comm:Send("SYNCREQ|main")
  -- Also announce own mapping after short delay
  C_Timer.After(1.5 + math.random() * 2, function()
    Mains:BroadcastOwn()
    syncBusy = false
  end)
end

local function EnsureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "AngryMurlocsMainFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(380, 180)
  GR.db.frames = GR.db.frames or {}
  GR.db.frames.main = GR.db.frames.main or {}
  U.MakeMovable(frame, {
    getPoint = function() return GR.db.frames.main.point end,
    setPoint = function(pt) GR.db.frames.main.point = pt end,
    defaultFn = function(f) f:SetPoint("CENTER", UIParent, "CENTER", 80, 40) end,
  })
  frame:Hide()
  tinsert(UISpecialFrames, "AngryMurlocsMainFrame")
  frame.TitleText:SetText(U.L("MAIN_WINDOW_TITLE"))

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -32)
  hint:SetWidth(340)
  hint:SetJustifyH("LEFT")
  hint:SetText(U.L("MAIN_HINT"))

  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 16, -70)
  label:SetText(U.L("MAIN_EDIT_LABEL"))

  editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  editBox:SetSize(220, 20)
  editBox:SetPoint("LEFT", label, "RIGHT", 8, 0)
  editBox:SetAutoFocus(false)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.status:SetPoint("TOPLEFT", 16, -100)
  frame.status:SetWidth(340)
  frame.status:SetJustifyH("LEFT")

  local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  saveBtn:SetSize(100, 22)
  saveBtn:SetPoint("BOTTOMLEFT", 12, 12)
  saveBtn:SetText(U.L("MAIN_SAVE"))
  saveBtn:SetScript("OnClick", function()
    local t = editBox:GetText() or ""
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then
      U.Print(U.L("MAIN_NEED_NAME"))
      return
    end
    Mains:SetLocal(t, true)
  end)

  local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearBtn:SetSize(100, 22)
  clearBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
  clearBtn:SetText(U.L("MAIN_CLEAR_BTN"))
  clearBtn:SetScript("OnClick", function()
    Mains:ClearLocal(true)
  end)

  return frame
end

function Mains:Refresh()
  if not frame or not frame:IsShown() then return end
  local me = Me()
  local main = Mains:GetMain(me)
  if main then
    frame.status:SetText(string.format(U.L("MAIN_STATUS"), me, main))
    if editBox and (editBox:GetText() or "") == "" then
      editBox:SetText(U.ShortName(main))
    end
  else
    frame.status:SetText(U.L("MAIN_NONE"))
  end
end

function Mains:Toggle()
  EnsureFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    Mains:Refresh()
  end
end

function Mains:OnEnable()
  EnsureDB()

  GR:RegisterMessage("MAIN_UPDATE", function(_, sender, data)
    if not data then return end
    -- Only accept mapping for the sender's own character
    if U.NormalizeName(data.char or "") ~= U.NormalizeName(sender) then
      return
    end
    Mains:ApplyRemote(sender, data.action, data.main, data.ver, data.ts)
  end)

  GR:RegisterMessage("SYNCREQ_UPDATE", function(_, sender, kind)
    if kind ~= "main" then return end
    C_Timer.After(0.5 + math.random() * 2.5, function()
      Mains:BroadcastOwn()
    end)
  end)

  GR:RegisterMessage("MAINS_CHANGED", function()
    if frame and frame:IsShown() then
      Mains:Refresh()
    end
    local ui = GR:GetModule("UI")
    if ui and ui.RefreshList then
      ui:RefreshList()
    end
  end)

  GR:RegisterMessage("GUILD_UPDATE", function()
    EnsureDB()
  end)

  C_Timer.After(6, function()
    Mains:RequestSync()
  end)
end
