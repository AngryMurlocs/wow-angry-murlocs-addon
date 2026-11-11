-- Runs the UI code paths (tabs, General status, manual sync) against frame stubs.
-- Catches Lua errors only; layout and visuals need the client (CLIENT_CHECKLIST.md).
-- From repo root: luajit Tests/UISmoke_test.lua
local Sim = dofile("Tests/sim.lua")

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

local sim = Sim.New(1)
local files = {
  "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua",
  "Modules/Professions.lua", "Modules/ProfRecipes.lua", "Modules/Options.lua",
  "Modules/UI.lua", "Modules/ProfRecipePanel.lua",
}
-- Frame stubs must honor Show/Hide/IsShown so IsTabShown + scheduled refreshes work.
local function NewFrame()
  local f = Sim.Stub()
  f._shown = true
  f._scripts = {}
  f.Show = function(self) self._shown = true end
  f.Hide = function(self) self._shown = false end
  f.IsShown = function(self) return self._shown end
  f.SetScript = function(self, ev, fn) self._scripts[ev] = fn end
  f.GetScript = function(self, ev) return self._scripts[ev] end
  f.HookScript = function(self, ev, fn)
    local prev = self._scripts[ev]
    if prev then
      self._scripts[ev] = function(...)
        prev(...)
        fn(...)
      end
    else
      self._scripts[ev] = fn
    end
  end
  f.SetText = function(self, t) self._text = t or "" end
  f.GetText = function(self) return self._text or "" end
  f.SetChecked = function(self, v) self._checked = v and true or false end
  f.GetChecked = function(self) return self._checked end
  f.SetMinMaxValues = function() end
  f.SetValueStep = function() end
  f.SetValue = function(self, v) self._value = v end
  f.GetValue = function(self) return self._value or 0 end
  f.Disable = function() end
  f.Enable = function() end
  return f
end
local env = {
  GetNumSkillLines = function() return 0 end,
  UISpecialFrames = {},
  tinsert = table.insert,
  IsShiftKeyDown = function() return false end,
  ChatFrame_SendTell = function() end,
  CreateFrame = NewFrame,
}
local alice = sim:AddClient("Alice", { extraFiles = files, env = env })
local bob = sim:AddClient("Bob", { extraFiles = files, env = env })
alice.Wanted:RecordOwnDeath("Enemy-Realm", "Z")
sim:Run(3)

local ui = bob.GR:GetModule("UI")
for _, tab in ipairs({ "general", "wanted", "prof", "opt", "general" }) do
  local ok, err = pcall(ui.ShowTab, ui, tab)
  check("tab " .. tab, ok, err)
end
ok, err = pcall(ui.ShowTab, ui, "admin")
check("tab admin without officer rights", ok, err)
check("admin redirects to general", ui.GetActiveTab and ui:GetActiveTab() == "general",
  "active=" .. tostring(ui.GetActiveTab and ui:GetActiveTab()))

-- Options categories / aliases / message kinds / layout-edit scope
do
  local options = bob.GR:GetModule("Options")
  check("Options module loaded", options ~= nil)
  ok, err = pcall(ui.ShowTab, ui, "opt")
  check("tab opt", ok, err)
  if options and options.ShowCategory then
    local expected = {
      privacy = "privacy",
      map = "map",
      lvl = "lvl",
      death = "death",
      sight = "sight",
      ui = "ui",
      notify = "lvl",
      messages = "lvl",
      layout = "ui",
      no_such_cat = "privacy",
    }
    for _, cat in ipairs({
      "privacy", "map", "lvl", "death", "sight", "ui",
      "notify", "messages", "layout", "no_such_cat",
    }) do
      ok, err = pcall(options.ShowCategory, options, cat)
      check("opt category " .. cat, ok, err)
      local active = options:GetActiveCategory()
      check("opt active after " .. cat, active == expected[cat],
        "got=" .. tostring(active) .. " want=" .. tostring(expected[cat]))
    end

    for _, kind in ipairs({ "lvl", "death", "sight", "lvl" }) do
      ok, err = pcall(options.ShowCategory, options, kind)
      check("opt section " .. kind, ok, err)
      check("opt active section " .. kind, options:GetActiveCategory() == kind,
        "got=" .. tostring(options:GetActiveCategory()))
      check("opt active msg kind " .. kind, options:GetActiveMessageKind() == kind,
        "got=" .. tostring(options:GetActiveMessageKind()))
      local panel = options.GetMessagePanel and options:GetMessagePanel(kind)
      check("opt msg panel " .. kind, panel ~= nil)
      if panel then
        if kind == "sight" then
          check("opt sight has no scale", panel._amHasScale ~= true)
        else
          check("opt " .. kind .. " has scale", panel._amHasScale == true)
          check("opt " .. kind .. " has show", panel._amShowCheck ~= nil)
          check("opt " .. kind .. " has preview", panel._amPreviewBtn ~= nil)
          check("opt " .. kind .. " has edit", panel._amEditBtn ~= nil)
        end
      end
    end

    ok, err = pcall(options.ShowCategory, options, "lvl")
    check("opt section lvl for edit", ok, err)
    if options.BeginLayoutEdit then
      ok, err = pcall(options.BeginLayoutEdit, options, "lvl")
      check("opt begin layout edit lvl", ok, err)
      check("opt layout edit on", options:IsLayoutEdit() == true)
      check("opt layout edit kind lvl", options:GetLayoutEditKind() == "lvl",
        "got=" .. tostring(options:GetLayoutEditKind()))
      local death = bob.GR:GetModule("Death")
      local lvl = bob.GR:GetModule("LevelUp")
      if death and death.IsLayoutEdit then
        check("opt death not editing during lvl", death:IsLayoutEdit() ~= true)
      end
      if lvl and lvl.IsLayoutEdit then
        check("opt lvl editing", lvl:IsLayoutEdit() == true)
      end

      ok, err = pcall(options.ShowCategory, options, "death")
      check("opt sectionwechsel ends edit", ok, err)
      check("opt layout edit off after section", options:IsLayoutEdit() ~= true)

      ok, err = pcall(options.BeginLayoutEdit, options, "death")
      check("opt begin layout edit death", ok, err)
      check("opt layout edit kind death", options:GetLayoutEditKind() == "death")
      if lvl and lvl.IsLayoutEdit then
        check("opt lvl not editing during death", lvl:IsLayoutEdit() ~= true)
      end

      ok, err = pcall(options.ShowCategory, options, "privacy")
      check("opt katwechsel ends edit", ok, err)
      check("opt layout edit off after kat", options:IsLayoutEdit() ~= true)
    end
  end
end

local carol = sim:AddClient("Carol", {
  extraFiles = files,
  env = {
    GetNumSkillLines = function() return 0 end,
    UISpecialFrames = {},
    tinsert = table.insert,
    IsShiftKeyDown = function() return false end,
    C_GuildInfo = { IsGuildOfficer = function() return true end },
    ChatFrame_SendTell = function() end,
    CreateFrame = NewFrame,
  },
})
local cui = carol.GR:GetModule("UI")
ok, err = pcall(cui.ShowTab, cui, "admin")
check("tab admin as officer", ok, err)
-- Placeholder era: ADMIN_TAB_ENABLED=false → even officers stay off admin.
check("officer admin hidden while placeholder", cui.GetActiveTab and cui:GetActiveTab() ~= "admin",
  "active=" .. tostring(cui.GetActiveTab and cui:GetActiveTab()))
ok, err = pcall(cui.RefreshAdminTabVisibility, cui)
check("RefreshAdminTabVisibility", ok, err)
local ok, err = pcall(ui.RefreshGeneral, ui)
check("general refresh", ok, err)
ok, err = pcall(ui.RunGuildDataSync, ui)
check("manual sync starts", ok, err)
check("sync busy after click", bob.Wanted:IsSyncBusy())
ok = pcall(ui.RunGuildDataSync, ui)
check("second click while busy is a no-op", ok and bob.Wanted:IsSyncBusy())
sim:Run(30)
check("manual sync completes", bob.Wanted:SyncStatusText():find("complete") ~= nil, bob.Wanted:SyncStatusText())
ok, err = pcall(ui.RefreshGeneral, ui)
check("general refresh after sync", ok, err)
ok, err = pcall(bob.Wanted.SetClassFile, bob.Wanted, "Enemy-Realm", "WARRIOR")
check("set classFile", ok, err)
check("summary still lists entry", bob.Wanted:Summary().total == 1)

-- Recipe modules load + search refresh path (cases 2–3 / R4)
do
  local recipes = bob.GR:GetModule("ProfRecipes")
  local panelOk = bob.GR:GetModule("UI") ~= nil
  check("ProfRecipes module loaded", recipes ~= nil)
  check("UI with ProfRecipePanel hooks", panelOk and type(ui.OpenRecipeDetail) == "function")
  check("AttachRecipePanel present", type(ui.AttachRecipePanel) == "function")

  ok, err = pcall(ui.ShowTab, ui, "prof")
  check("prof tab for recipe refresh", ok, err)
  ok, err = pcall(ui.ShowProfSubTab, ui, "search")
  check("show search subtab before typing", ok, err)
  local profrqBefore = sim:Count("PROFRQ")
  -- Typing path: open search + set text must not send PROFRQ
  ok, err = pcall(ui.SetSearchFilterText, ui, "heal")
  check("SetSearchFilterText ok", ok, err)
  check("case2 typing does not PROFRQ", sim:Count("PROFRQ") == profrqBefore)

  local rBefore = sim:Count("PROFRQ")
  ok, err = pcall(ui.RunRecipeDataRefresh, ui)
  check("case2 RunRecipeDataRefresh ok", ok, err)
  sim:Run(1)
  check("case2 recipe refresh sends PROFRQ", sim:Count("PROFRQ") > rBefore,
    "before=" .. rBefore .. " after=" .. sim:Count("PROFRQ"))

  -- R4: recipe/cache change while search visible must call RefreshSearchList (no click)
  ok, err = pcall(ui.ShowTab, ui, "prof")
  check("R4 prof tab", ok, err)
  if ui.ShowProfSubTab then
    ok, err = pcall(ui.ShowProfSubTab, ui, "search")
    check("R4 show search subtab", ok, err)
  end
  if ui.CloseRecipeCatalog then
    pcall(ui.CloseRecipeCatalog, ui, false)
  end
  local refreshes = 0
  local oldRefresh = ui.RefreshSearchList
  ui.RefreshSearchList = function(self, ...)
    refreshes = refreshes + 1
    return oldRefresh(self, ...)
  end
  local profrBefore = sim:Count("PROFR")
  -- Wire path: Alice publishes new ids; Bob must receive + UI schedule refresh
  local ar = alice.GR:GetModule("ProfRecipes")
  alice.GR.db.prof = alice.GR.db.prof or {}
  alice.GR.db.prof.recipeEpoch = 900
  alice.GR.db.privacy = alice.GR.db.privacy or {}
  alice.GR.db.privacy.shareProfessions = true
  ar:ApplyLocalScan("tail", { 2387, 2963 }, true)
  sim:Run(5)
  local bobEntry = recipes.GetEntry and recipes.GetEntry("Alice-Realm", "tail")
  check("R4 bob received recipe ids", bobEntry and bobEntry.ids and #bobEntry.ids == 2,
    bobEntry and tostring(#(bobEntry.ids or {})))
  check("R4 search auto-refresh on PROFR", refreshes >= 1, "refreshes=" .. tostring(refreshes))
  local bobSent = 0
  for _, m in ipairs(sim.bus) do
    if m.from == "Bob" and m.msg:match("^PROFR|") then bobSent = bobSent + 1 end
  end
  check("R4 bob did not PROFR from refresh alone", bobSent == 0, tostring(bobSent))
  check("R4 alice PROFR on bus", sim:Count("PROFR") > profrBefore)
  ui.RefreshSearchList = oldRefresh

  -- Case 3: incoming recipe data refreshes search without error
  local scope = bob.GR.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = {},
    recipes = {
      alch = { ids = { 2330 }, rev = 1, scanAt = 10, recvAt = 10, complete = true, epoch = 1 },
    },
  }
  bob.GR.db.prof = bob.GR.db.prof or {}
  bob.GR.db.prof.recipeMeta = bob.GR.db.prof.recipeMeta or {}
  recipes:OnMetaUpdate("Alice-Realm", {
    {
      recipeId = 2330,
      name = "Test Healing Potion",
      outputItemID = 118,
      qtyMin = 1,
      qtyMax = 1,
      reagents = { { itemID = 2447, qty = 1, name = "Peacebloom" } },
    },
  })
  recipes.InvalidateGuildRecipeIndex()
  bob.GR:SendMessage("PROF_RECIPES_CHANGED", "Alice-Realm", "alch")
  sim:Run(0.2)
  ok, err = pcall(ui.RefreshSearchList, ui)
  check("case3 search refresh after data", ok, err)
end

-- Case 8: bag event frame registered when panel attached
do
  ok, err = pcall(ui.ShowTab, ui, "prof")
  check("prof tab for bag hook", ok, err)
  -- EnsureCatalog via AttachRecipePanel happens in BuildProfTab; smoke that OpenRecipeDetail exists
  ok, err = pcall(function()
    ui:OpenRecipeDetail(2330, "alch", { "Alice-Realm" })
  end)
  check("OpenRecipeDetail smoke", ok, err)
  if ui.CloseRecipeCatalog then
    pcall(ui.CloseRecipeCatalog, ui, true)
  end
end

-- Member catalog categories: closed headers, search reveals, pool size fixed
do
  local scope = bob.GR.Util.GetScopeDB()
  scope.prof.cache["Alice-Realm"] = {
    list = { { key = "alch", skill = 1 } },
    recipes = {
      alch = { ids = { 101, 102, 103 }, rev = 1, scanAt = 10, recvAt = 10, complete = true, epoch = 1 },
    },
  }
  bob.GR.db.prof = bob.GR.db.prof or {}
  bob.GR.db.prof.recipeMeta = {
    [101] = { name = "Alpha Potion", categoryId = 10, categoryName = "Potions" },
    [102] = { name = "Beta Elixir", categoryId = 11, categoryName = "Elixirs" },
    [103] = { name = "Gamma Potion", categoryId = 10, categoryName = "Potions" },
  }
  check("catalog test helper", ui._TestBuildMemberCatalogRows ~= nil)
  if ui._TestBuildMemberCatalogRows then
    local flat, nRecipes, nCats, pool = ui._TestBuildMemberCatalogRows("Alice-Realm", "alch", "", {})
    check("catalog closed headers only", flat and #flat == 2, flat and #flat)
    check("catalog recipe count", nRecipes == 3, nRecipes)
    check("catalog category count", nCats == 2, nCats)
    check("catalog pool capped", pool == 14, pool)
    local expanded = { ["10"] = true }
    flat = ui._TestBuildMemberCatalogRows("Alice-Realm", "alch", "", expanded)
    local recipesShown = 0
    for i = 1, #flat do
      if flat[i].kind == "recipe" then recipesShown = recipesShown + 1 end
    end
    check("catalog expand potions shows 2", recipesShown == 2, recipesShown)
    flat = ui._TestBuildMemberCatalogRows("Alice-Realm", "alch", "Gamma", {})
    local found = false
    for i = 1, #flat do
      if flat[i].kind == "recipe" and flat[i].recipe and flat[i].recipe.name == "Gamma Potion" then
        found = true
      end
    end
    check("catalog search finds closed group recipe", found)
  end
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
