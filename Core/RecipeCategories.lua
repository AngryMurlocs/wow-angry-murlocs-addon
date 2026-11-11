-- Pure recipe category grouping (no WoW APIs). Safe for CLI unit tests.
-- Group recipes by WoW category keys; Flatten builds visible header/recipe rows.
local GR = AngryMurlocs or {}
AngryMurlocs = GR
local RecipeCategories = {}
GR.RecipeCategories = RecipeCategories

local OTHER_KEY = "other"

local function Lower(s)
  return string.lower(tostring(s or ""))
end

local function RecipeSortKey(row)
  return Lower(row and row.name), tonumber(row and row.recipeId) or 0
end

local function CompareRecipes(a, b, searching)
  if searching then
    local ra = tonumber(a and a.rank) or 1
    local rb = tonumber(b and b.rank) or 1
    if ra ~= rb then return ra < rb end
  end
  local na, ida = RecipeSortKey(a)
  local nb, idb = RecipeSortKey(b)
  if na ~= nb then return na < nb end
  return ida < idb
end

local function CompareGroups(a, b)
  local aOther = a.key == OTHER_KEY
  local bOther = b.key == OTHER_KEY
  if aOther ~= bOther then return not aOther end
  local na = Lower(a.name)
  local nb = Lower(b.name)
  if na ~= nb then return na < nb end
  return tostring(a.key or "") < tostring(b.key or "")
end

--- Group recipe rows by resolveCategory(row) -> categoryKey, categoryName.
-- rows: { { recipeId, name, ... }, ... }. Extra fields are preserved on recipes.
-- Returns ordered groups: { key, name, count, recipes }.
function RecipeCategories.Group(rows, resolveCategory)
  local groups = {}
  if type(rows) ~= "table" then return groups end
  local byKey = {}
  local order = {}
  for i = 1, #rows do
    local row = rows[i]
    if type(row) == "table" then
      local key, name
      if type(resolveCategory) == "function" then
        key, name = resolveCategory(row)
      end
      key = tostring(key or "")
      if key == "" then key = OTHER_KEY end
      name = tostring(name or "")
      if name == "" then name = key end
      local g = byKey[key]
      if not g then
        g = { key = key, name = name, recipes = {} }
        byKey[key] = g
        order[#order + 1] = key
      elseif name ~= "" and (not g.name or g.name == "" or g.name == g.key) then
        g.name = name
      end
      g.recipes[#g.recipes + 1] = row
    end
  end
  for i = 1, #order do
    local g = byKey[order[i]]
    g.count = #g.recipes
    groups[#groups + 1] = g
  end
  table.sort(groups, CompareGroups)
  RecipeCategories.SortGroupRecipes(groups, false)
  return groups
end

--- Sort recipes inside groups. searching=true uses within-group rank then name.
function RecipeCategories.SortGroupRecipes(groups, searching)
  if type(groups) ~= "table" then return groups end
  for i = 1, #groups do
    local recipes = groups[i].recipes
    if type(recipes) == "table" then
      table.sort(recipes, function(a, b)
        return CompareRecipes(a, b, searching)
      end)
    end
  end
  return groups
end

--- Flatten groups to visible rows.
-- expanded: map categoryKey -> true when open (ignored when searching).
-- searching: show matching recipes even if group closed; does not mutate expanded.
-- Returns { { kind="category", key, name, count, expanded }, { kind="recipe", recipe }, ... }
function RecipeCategories.Flatten(groups, expanded, searching)
  local out = {}
  if type(groups) ~= "table" then return out end
  expanded = type(expanded) == "table" and expanded or {}
  searching = searching and true or false
  for i = 1, #groups do
    local g = groups[i]
    if type(g) == "table" and type(g.recipes) == "table" and #g.recipes > 0 then
      local isOpen = searching or expanded[g.key] == true
      out[#out + 1] = {
        kind = "category",
        key = g.key,
        name = g.name,
        count = g.count or #g.recipes,
        expanded = isOpen,
      }
      if isOpen then
        for j = 1, #g.recipes do
          out[#out + 1] = {
            kind = "recipe",
            recipe = g.recipes[j],
          }
        end
      end
    end
  end
  return out
end

RecipeCategories.OTHER_KEY = OTHER_KEY
