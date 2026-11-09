-- Shared UI colors and layout helpers for AngryMurlocs (Forever 16001).
local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Theme = GR.Theme or {}
local T = GR.Theme

T.INSET = 8
T.GAP = 16

T.BG = { 0.08, 0.09, 0.10, 0.92 }
T.BG_ALT = { 0.11, 0.12, 0.14, 0.55 }
T.BG_HOVER = { 0.16, 0.22, 0.18, 0.75 }
T.BG_SELECT = { 0.12, 0.28, 0.16, 0.85 }
T.BORDER = { 0.28, 0.32, 0.28, 0.9 }
T.ACCENT = { 0.25, 0.78, 0.35, 1 }
T.TEXT = { 0.92, 0.92, 0.90 }
T.MUTED = { 0.62, 0.64, 0.60 }
T.ON = { 0.35, 0.85, 0.45 }
T.OFF = { 0.75, 0.45, 0.40 }
T.WARN = { 1.0, 0.55, 0.25 }
T.DANGER = { 1.0, 0.30, 0.22 }
T.FRESH = { 0.45, 0.95, 0.55 }
T.WARM = { 0.95, 0.85, 0.40 }
T.STALE = { 0.70, 0.65, 0.55 }

local function Solid(tex, c)
  if not tex or not c then return end
  tex:SetTexture("Interface\\Buttons\\WHITE8x8")
  tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

local function EnsureBg(frame)
  if frame._amBg then return frame._amBg end
  local tex = frame:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  frame._amBg = tex
  return tex
end

local function EnsureBorder(frame)
  if frame._amBorder then return frame._amBorder end
  local edges = {}
  for i = 1, 4 do
    edges[i] = frame:CreateTexture(nil, "BORDER")
  end
  edges[1]:SetPoint("TOPLEFT")
  edges[1]:SetPoint("TOPRIGHT")
  edges[1]:SetHeight(1)
  edges[2]:SetPoint("BOTTOMLEFT")
  edges[2]:SetPoint("BOTTOMRIGHT")
  edges[2]:SetHeight(1)
  edges[3]:SetPoint("TOPLEFT")
  edges[3]:SetPoint("BOTTOMLEFT")
  edges[3]:SetWidth(1)
  edges[4]:SetPoint("TOPRIGHT")
  edges[4]:SetPoint("BOTTOMRIGHT")
  edges[4]:SetWidth(1)
  frame._amBorder = edges
  return edges
end

function T.ApplyPanelBackdrop(frame, bg)
  if not frame then return end
  Solid(EnsureBg(frame), bg or T.BG)
  local edges = EnsureBorder(frame)
  for i = 1, 4 do
    Solid(edges[i], T.BORDER)
  end
end

function T.StyleTabButton(btn, active)
  if not btn then return end
  if not btn._amUnderline then
    local u = btn:CreateTexture(nil, "OVERLAY")
    u:SetHeight(2)
    u:SetPoint("BOTTOMLEFT", 4, 1)
    u:SetPoint("BOTTOMRIGHT", -4, 1)
    Solid(u, T.ACCENT)
    btn._amUnderline = u
  end
  if not btn._amActiveBg then
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Solid(bg, T.BG_SELECT)
    btn._amActiveBg = bg
  end
  btn:Enable()
  if active then
    btn._amUnderline:Show()
    btn._amActiveBg:Show()
  else
    btn._amUnderline:Hide()
    btn._amActiveBg:Hide()
  end
end

function T.ApplyRowChrome(row, index, selected)
  if not row then return end
  local bg = EnsureBg(row)
  row._amRowIndex = index
  row._amSelected = selected and true or false
  local c
  if selected then
    c = T.BG_SELECT
  elseif (index % 2) == 0 then
    c = T.BG_ALT
  else
    c = { 0, 0, 0, 0 }
  end
  Solid(bg, c)
end

function T.RowHoverEnter(row)
  if not row or row._amSelected then return end
  Solid(EnsureBg(row), T.BG_HOVER)
end

function T.RowHoverLeave(row)
  if not row then return end
  T.ApplyRowChrome(row, row._amRowIndex or 0, row._amSelected)
end

function T.SetTextColor(fs, palette)
  if not fs or not palette then return end
  fs:SetTextColor(palette[1], palette[2], palette[3])
end

function T.OnOffColor(on)
  return on and T.ON or T.OFF
end

function T.Truncate(text, maxChars)
  text = tostring(text or "")
  maxChars = maxChars or 18
  if #text <= maxChars then return text, false end
  return text:sub(1, math.max(1, maxChars - 1)) .. "...", true
end

function T.SetTruncatedText(fs, text, maxChars)
  if not fs then return end
  local shown = T.Truncate(text, maxChars)
  fs:SetText(shown)
  fs._amFullText = text
end

function T.StatusCard(parent, width, height)
  local card = CreateFrame("Frame", nil, parent)
  card:SetSize(width, height)
  T.ApplyPanelBackdrop(card, T.BG_ALT)
  card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  card.value:SetPoint("TOP", 0, -10)
  card.value:SetTextColor(T.TEXT[1], T.TEXT[2], T.TEXT[3])
  card.label = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  card.label:SetPoint("BOTTOM", 0, 8)
  card.label:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
  card:EnableMouse(true)
  return card
end
