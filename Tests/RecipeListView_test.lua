-- Virtual list helpers.
-- From repo root: luajit Tests/RecipeListView_test.lua
local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

AngryMurlocs = {}
dofile("Core/RecipeListView.lua")
local V = AngryMurlocs.RecipeListView

check("first at 0", V.FirstVisibleIndex(0, 24, 100) == 1)
check("first after one row", V.FirstVisibleIndex(24, 24, 100) == 2)
check("content height", V.ContentHeight(10, 24) == 240)
local y, maxY = V.ClampScroll(9999, 24, 20, 14)
check("clamp scroll", y == maxY and maxY == (20 - 14) * 24)

print(string.format("%d failures", fails))
if fails > 0 then os.exit(1) end
