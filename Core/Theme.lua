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

-- Flat options sidebar row (no UIPanel chrome). Active = green fill + left accent bar.
function T.StyleNavRow(btn, active)
  if not btn then return end
  if not btn._amNavBg then
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Solid(bg, { 0, 0, 0, 0 })
    btn._amNavBg = bg
  end
  if not btn._amNavAccent then
    local bar = btn:CreateTexture(nil, "ARTWORK")
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    Solid(bar, T.ACCENT)
    btn._amNavAccent = bar
  end
  if not btn._amNavLabel then
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    btn._amNavLabel = fs
    if btn.GetFontString and btn:GetFontString() then
      -- Prefer custom label; hide template text if any.
      btn:GetFontString():SetAlpha(0)
    end
  end
  if btn._amNavText then
    btn._amNavLabel:SetText(btn._amNavText)
  end
  btn:Enable()
  if active then
    Solid(btn._amNavBg, T.BG_SELECT)
    btn._amNavAccent:Show()
    T.SetTextColor(btn._amNavLabel, T.TEXT)
  else
    Solid(btn._amNavBg, { 0, 0, 0, 0 })
    btn._amNavAccent:Hide()
    T.SetTextColor(btn._amNavLabel, T.TEXT)
  end
end

function T.WireNavRowHover(btn)
  if not btn or btn._amNavHoverWired then return end
  btn._amNavHoverWired = true
  btn:SetScript("OnEnter", function(self)
    if self._amNavActive then return end
    if self._amNavBg then
      Solid(self._amNavBg, T.BG_HOVER)
    end
  end)
  btn:SetScript("OnLeave", function(self)
    if self._amNavActive then return end
    if self._amNavBg then
      Solid(self._amNavBg, { 0, 0, 0, 0 })
    end
  end)
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
  -- Subtle bottom divider for calmer table rows.
  if not row._amRowDivider then
    local div = row:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("BOTTOMLEFT", 2, 0)
    div:SetPoint("BOTTOMRIGHT", -2, 0)
    row._amRowDivider = div
  end
  Solid(row._amRowDivider, { T.BORDER[1], T.BORDER[2], T.BORDER[3], 0.45 })
end

function T.StylePrimaryButton(btn)
  if not btn then return end
  if not btn._amPrimaryBg then
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Solid(bg, T.BG_SELECT)
    btn._amPrimaryBg = bg
  end
  btn._amPrimaryBg:Show()
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

-- Illustrated toast frames (death / level-up). The art lives in Media/Toasts as
-- 1024x512 textures with the 3:1 image in the top 341 rows. `box` is the calm
-- dark panel of the art where the text goes, as fractions of the image:
-- center x, center y, width, height.
T.TOAST_W = 720
T.TOAST_H = 240
T.TOAST_FONT = "Interface\\AddOns\\AngryMurlocs\\Media\\Fonts\\Cinzel-Bold.ttf"
T.TOAST_TEXT = { 0.914, 0.886, 0.831 } -- #E9E2D4

local TOAST_ART_V = 341 / 512

local function ToastFont(fs, size, fallbackTemplate)
  local ok = fs:SetFont(T.TOAST_FONT, size, "")
  if ok == false and fallbackTemplate then
    fs:SetFontObject(fallbackTemplate)
  end
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
end

-- titleSize: optional larger first line (f.title), e.g. the death badge. Then
-- the block is anchored at the top center of the box instead of centered.
function T.CreateArtToast(globalName, art, box, textSize, titleSize, maxLines)
  local W, H = T.TOAST_W, T.TOAST_H
  local f = CreateFrame("Frame", globalName, UIParent)
  f:SetSize(W, H)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\AddOns\\AngryMurlocs\\Media\\Toasts\\" .. art)
  bg:SetTexCoord(0, 1, 0, TOAST_ART_V)
  f.bg = bg

  local cx, cy, bw, bh = box[1] * W, box[2] * H, box[3] * W, box[4] * H

  local text = f:CreateFontString(nil, "OVERLAY")
  ToastFont(text, textSize or 16, GameFontHighlight)
  text:SetTextColor(T.TOAST_TEXT[1], T.TOAST_TEXT[2], T.TOAST_TEXT[3])
  if not titleSize then
    text:SetPoint("CENTER", f, "TOPLEFT", cx, -cy)
  end
  text:SetWidth(bw)
  text:SetJustifyH("CENTER")
  text:SetJustifyV("MIDDLE")
  if text.SetWordWrap then text:SetWordWrap(true) end
  if text.SetMaxLines then text:SetMaxLines(maxLines or 3) end
  f.text = text

  if titleSize then
    local title = f:CreateFontString(nil, "OVERLAY")
    ToastFont(title, titleSize, GameFontNormalLarge)
    title:SetTextColor(T.TOAST_TEXT[1], T.TOAST_TEXT[2], T.TOAST_TEXT[3])
    -- Anchored top center of the box, the text follows below, so the block
    -- uses the full height of the dark panel.
    title:SetPoint("TOP", f, "TOPLEFT", cx, -(cy - bh / 2) - 2)
    text:SetPoint("TOP", title, "BOTTOM", 0, -2)
    title:SetWidth(bw)
    title:SetJustifyH("CENTER")
    f.title = title
  end

  local hint = f:CreateFontString(nil, "OVERLAY")
  ToastFont(hint, 10, GameFontDisableSmall)
  hint:SetTextColor(T.TOAST_TEXT[1], T.TOAST_TEXT[2], T.TOAST_TEXT[3], 0.7)
  hint:SetPoint("BOTTOM", f, "TOPLEFT", cx, -(cy + bh / 2))
  f.hint = hint

  return f
end
