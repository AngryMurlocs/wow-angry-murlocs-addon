-- Pure category grouping / flatten.
-- From repo root: luajit Tests/RecipeCategories_test.lua

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
dofile("Core/RecipeCategories.lua")
local RC = AngryMurlocs.RecipeCategories

local function resolveFromRow(row)
  return row.catKey, row.catName
end

do
  local rows = {
    { recipeId = 2, name = "Beta", catKey = "potion", catName = "Potions" },
    { recipeId = 1, name = "Alpha", catKey = "potion", catName = "Potions" },
  }
  local groups = RC.Group(rows, resolveFromRow)
  check("same category one group", #groups == 1)
  check("count 2", groups[1] and groups[1].count == 2)
  check("alpha first in group", groups[1] and groups[1].recipes[1].name == "Alpha")
end

do
  local rows = {
    { recipeId = 1, name = "Zulu", catKey = nil, catName = nil },
    { recipeId = 2, name = "Alpha", catKey = "", catName = "" },
  }
  local groups = RC.Group(rows, resolveFromRow)
  check("unknown -> other", #groups == 1 and groups[1].key == RC.OTHER_KEY)
  check("other keeps both", groups[1].count == 2)
end

do
  local rows = {
    { recipeId = 1, name = "A", catKey = "other", catName = "Other" },
    { recipeId = 2, name = "B", catKey = "elixirs", catName = "Elixirs" },
    { recipeId = 3, name = "C", catKey = "potions", catName = "Potions" },
  }
  local groups = RC.Group(rows, resolveFromRow)
  check("other last", groups[#groups].key == "other")
  check("elixirs before potions", groups[1].key == "elixirs" and groups[2].key == "potions")
end

do
  local groups = RC.Group({}, resolveFromRow)
  check("empty input", #groups == 0)
  local groups2 = RC.Group(nil, resolveFromRow)
  check("nil input", #groups2 == 0)
  local rows = { { recipeId = 9, name = nil, catKey = "x", catName = "X" } }
  local g = RC.Group(rows, resolveFromRow)
  check("missing recipe name kept", g[1] and g[1].count == 1 and g[1].recipes[1].recipeId == 9)
end

do
  local rows = {
    { recipeId = 1, name = "A", catKey = "p", catName = "P", crafters = { "Bob" } },
  }
  local g = RC.Group(rows, resolveFromRow)
  check("preserves crafters", g[1].recipes[1].crafters and g[1].recipes[1].crafters[1] == "Bob")
end

do
  local rows = {
    { recipeId = 1, name = "A", catKey = "p", catName = "P" },
    { recipeId = 2, name = "B", catKey = "p", catName = "P" },
  }
  local groups = RC.Group(rows, resolveFromRow)
  local expanded = {}
  local flat = RC.Flatten(groups, expanded, false)
  check("closed only headers", #flat == 1 and flat[1].kind == "category" and flat[1].expanded == false)
  expanded.p = true
  flat = RC.Flatten(groups, expanded, false)
  check("open shows recipes", #flat == 3 and flat[2].kind == "recipe")
end

do
  local rows = {
    { recipeId = 1, name = "Hidden", catKey = "p", catName = "P", rank = 1 },
    { recipeId = 2, name = "Exact", catKey = "p", catName = "P", rank = 0 },
  }
  local groups = RC.Group(rows, resolveFromRow)
  RC.SortGroupRecipes(groups, true)
  local expanded = {} -- closed
  local before = expanded.p
  local flat = RC.Flatten(groups, expanded, true)
  check("search shows closed recipes", #flat == 3 and flat[2].kind == "recipe")
  check("search rank0 before rank1 in group", flat[2].recipe.name == "Exact" and flat[3].recipe.name == "Hidden")
  check("search does not mutate expanded", expanded.p == before)
end

do
  local rows = {
    { recipeId = 1, name = "ZExact", catKey = "zeta", catName = "Zeta", rank = 0 },
    { recipeId = 2, name = "AFuzzy", catKey = "alpha", catName = "Alpha", rank = 1 },
  }
  local groups = RC.Group(rows, resolveFromRow)
  RC.SortGroupRecipes(groups, true)
  local flat = RC.Flatten(groups, {}, true)
  -- Categories stay alphabetical: Alpha before Zeta even though Zeta has exact match.
  check("categories alpha not by rank", flat[1].key == "alpha" and flat[3].key == "zeta")
end

print(string.format("%d failures", fails))
if fails > 0 then os.exit(1) end
