-- Shared helpers for virtual recipe/category scroll lists (no WoW network).
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local RecipeListView = {}
GR.RecipeListView = RecipeListView

--- firstIndex (1-based) for a vertical scroll offset and row height.
function RecipeListView.FirstVisibleIndex(scrollY, rowHeight, total)
  rowHeight = tonumber(rowHeight) or 1
  if rowHeight < 1 then rowHeight = 1 end
  local y = tonumber(scrollY) or 0
  if y < 0 then y = 0 end
  local first = math.floor(y / rowHeight) + 1
  if first < 1 then first = 1 end
  total = tonumber(total) or 0
  if total > 0 and first > total then first = total end
  return first
end

--- Clamp scroll so last rows stay reachable with a fixed pool of poolSize rows.
function RecipeListView.ClampScroll(scrollY, rowHeight, total, poolSize)
  rowHeight = tonumber(rowHeight) or 1
  poolSize = tonumber(poolSize) or 1
  total = tonumber(total) or 0
  local maxY = math.max(0, (total - poolSize) * rowHeight)
  if total <= poolSize then maxY = 0 end
  -- Prefer content height based max when child is taller than viewport:
  -- callers may also clamp via GetVerticalScrollRange.
  local y = tonumber(scrollY) or 0
  if y < 0 then y = 0 end
  if y > maxY then y = maxY end
  return y, maxY
end

--- Content height for N logical rows.
function RecipeListView.ContentHeight(total, rowHeight)
  rowHeight = tonumber(rowHeight) or 1
  total = tonumber(total) or 0
  return math.max(total, 1) * rowHeight
end
