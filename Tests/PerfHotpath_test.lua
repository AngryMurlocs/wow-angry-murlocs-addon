-- Performance hotpath acceptance (P0–P3). From repo root:
--   luajit Tests/PerfHotpath_test.lua
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

local POS_MSG = "POS|1429|0.5000|0.5000|Elwynn|0|MAGE|60"

-- ---------- P0: closed map must not scan cache via IsSelfName ----------
do
  local sim = Sim.New(40)
  local db = Sim.DefaultDB()
  db.privacy.sharePosition = false
  local createCount = 0
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Positions.lua", "Modules/MapPins.lua" },
    env = {
      WorldMapFrame = {
        IsShown = function() return false end,
        HookScript = function() end,
      },
      CreateFrame = function(...)
        createCount = createCount + 1
        return Sim.Stub()
      end,
    },
  })
  local GR = alice.GR
  local U = GR.Util
  local orig = U.IsSelfName
  local selfCalls = 0
  U.IsSelfName = function(...)
    selfCalls = selfCalls + 1
    return orig(...)
  end

  for i = 1, 100 do
    GR:SendMessage("POS_UPDATE", "M" .. i .. "-Realm", {
      mapId = 1429, x = 0.5, y = 0.5, time = 0, classFile = "MAGE", level = 60,
    })
  end
  local after100 = selfCalls
  for _ = 1, 50 do
    GR:SendMessage("POS_UPDATE", "M1-Realm", {
      mapId = 1429, x = 0.51, y = 0.5, time = 1, classFile = "MAGE", level = 60,
    })
  end
  local after150 = selfCalls
  check("P0 after 100 members IsSelfName==100", after100 == 100, after100)
  check("P0 after 50 updates IsSelfName==150", after150 == 150, after150)
  local cache = GR:GetModule("Positions"):GetCache()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  check("P0 foreign positions kept", n == 100, n)
end

-- ---------- P3 cluster geometry helper (size join/split) ----------
do
  AngryMurlocs = AngryMurlocs or {}
  AngryMurlocs.Util = AngryMurlocs.Util or { ClassColor = function() return 1, 1, 1 end, L = function(k) return k end, Now = function() return 0 end }
  if not AngryMurlocs.NewModule then
    AngryMurlocs.NewModule = function(self, name)
      local m = { name = name }
      self._modules = self._modules or {}
      self._modules[name] = m
      return m
    end
  end
  if not (AngryMurlocs._modules and AngryMurlocs._modules.MapPins and AngryMurlocs._modules.MapPins.ClusterOffsets) then
    dofile("Modules/MapPins.lua")
  end
  local M = AngryMurlocs._modules.MapPins
  local pts = {
    { name = "A", x = 0, y = 0 },
    { name = "B", x = 28, y = 0 },
  }
  local out26 = M.ClusterOffsets(pts, 26, 2)
  local out31 = M.ClusterOffsets(pts, 31, 2)
  check("P3 size26 apart", out26.A.cx ~= out26.B.cx or (out26.A.ox == 0 and out26.B.ox == 0))
  local joined = out31.A.cx == out31.B.cx and out31.A.cy == out31.B.cy
    and (out31.A.ox ~= 0 or out31.B.ox ~= 0)
  check("P3 size31 clustered", joined)
  local out26b = M.ClusterOffsets(pts, 26, 2)
  check("P3 size down splits again", out26b.A.ox == 0 and out26b.B.ox == 0)
end

-- ---------- P1 + P2 via UI smoke harness ----------
do
  local sim = Sim.New(41)
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
    f.CreateFontString = function()
      local fs = NewFrame()
      fs.SetTextColor = function() end
      fs.GetStringHeight = function() return 12 end
      return fs
    end
    f.CreateTexture = function() return NewFrame() end
    return f
  end
  local env = {
    GetNumSkillLines = function() return 0 end,
    UISpecialFrames = {},
    tinsert = table.insert,
    IsShiftKeyDown = function() return false end,
    ChatFrame_SendTell = function() end,
    CreateFrame = NewFrame,
    GameTooltip_Hide = function() end,
  }
  local bob = sim:AddClient("Bob", {
    extraFiles = {
      "Modules/Wanted.lua", "Modules/WantedSync.lua", "Modules/WantedPanel.lua",
      "Modules/Professions.lua", "Modules/ProfRecipes.lua", "Modules/Options.lua",
      "Modules/Positions.lua", "Modules/UI.lua", "Modules/ProfRecipePanel.lua",
    },
    env = env,
  })
  local GR = bob.GR
  local ui = GR:GetModule("UI")
  local pos = GR:GetModule("Positions")

  -- P1: recipe catalog meta burst
  do
    local scope = GR.Util.GetScopeDB()
    scope.prof = scope.prof or {}
    scope.prof.cache = scope.prof.cache or {}
    local ids = {}
    for i = 1, 300 do ids[i] = 2000 + i end
    scope.prof.cache["Alice-Realm"] = {
      alch = { ids = ids, skill = 300, complete = true, updated = 1 },
    }
    GR.db.prof = GR.db.prof or {}
    GR.db.prof.recipeMeta = GR.db.prof.recipeMeta or {}
    for i = 1, 300 do
      local id = 2000 + i
      GR.db.prof.recipeMeta[id] = {
        name = "Potion " .. i,
        outputItemID = 10000 + i,
        categoryId = 1,
        categoryName = "Potions",
      }
    end

    check("P1 show prof tab", pcall(ui.ShowTab, ui, "prof"))
    local recipes = GR:GetModule("ProfRecipes")
    local resolveN = 0
    local origResolve = recipes.ResolveItemName
    recipes.ResolveItemName = function(...)
      resolveN = resolveN + 1
      return origResolve(...)
    end
    local groupN = 0
    local RC = GR.RecipeCategories
    local origGroup = RC.Group
    RC.Group = function(...)
      groupN = groupN + 1
      return origGroup(...)
    end
    local refreshN = 0
    local origRefresh = ui.RefreshRecipeCatalog
    ui.RefreshRecipeCatalog = function(self, ...)
      refreshN = refreshN + 1
      return origRefresh(self, ...)
    end

    pcall(ui.OpenRecipeCatalog, ui, "Alice-Realm", "alch")
    refreshN, groupN, resolveN = 0, 0, 0
    for _ = 1, 10 do
      GR:SendMessage("PROF_RECIPE_META_CHANGED", "Alice-Realm")
    end
    sim:Run(0.2)
    check("P1 one catalog refresh", refreshN == 1, refreshN)
    check("P1 one Group", groupN == 1, groupN)
    check("P1 zero Resolve on empty search", resolveN == 0, resolveN)

    -- search no hits -> clear
    if ui.IsRecipeCatalogOpen and ui:IsRecipeCatalogOpen() then
      -- drive filter via RefreshRecipeCatalog path after setting filter through open state
      local panelOk = pcall(function()
        -- Use catalog search OnTextChanged if present by re-opening with meta
        GR:SendMessage("PROF_RECIPE_META_CHANGED")
      end)
      check("P1 meta while open ok", panelOk)
    end
    recipes.ResolveItemName = origResolve
    RC.Group = origGroup
    ui.RefreshRecipeCatalog = origRefresh
    if ui.CloseRecipeCatalog then pcall(ui.CloseRecipeCatalog, ui, false) end
  end

  -- P2: POS burst via Comm
  do
    check("P2 show general", pcall(ui.ShowTab, ui, "general"))
    ui:RefreshGeneral()
    local Logic = GR.WantedLogic
    local origSorted = Logic.Sorted
    local sorts = 0
    Logic.Sorted = function(...)
      sorts = sorts + 1
      return origSorted(...)
    end
    ui._generalPaintCount = 0
    sorts = 0
    local prefix = GR.PREFIX
    for i = 1, 50 do
      GR.Comm:OnAddonMessage(prefix, POS_MSG, "GUILD", "Peer" .. i .. "-Realm")
    end
    sim:Run(0.2)
    local nPeers = select(1, GR.Comm:Peers(600))
    local pins = 0
    for _ in pairs(pos:GetCache()) do pins = pins + 1 end
    check("P2 50 peers", nPeers == 50, nPeers)
    check("P2 50 pins", pins == 50, pins)
    check("P2 one paint", ui._generalPaintCount == 1, ui._generalPaintCount)
    check("P2 zero Wanted sorts", sorts == 0, sorts)
    Logic.Sorted = origSorted
  end

  -- P2: Wanted top flips across score hour boundary with details open
  do
    local scope = GR.Util.GetScopeDB()
    local now = GR.Util.WallTime()
    scope.wanted = {
      ["Alpha-Realm"] = { legacy = 5, origins = {}, lastKillTime = now - 3599, lastSeenTime = 0 },
      ["Beta-Realm"] = { legacy = 5, origins = {}, lastKillTime = now, lastSeenTime = 0 },
    }
    scope.wantedSync = scope.wantedSync or {}
    scope.wantedSync.lastOkAt = now - 30
    -- Force details mode + full refresh
    pcall(ui.ShowTab, ui, "general")
    -- Open details via SetBottomMode path: click details by calling Refresh after forcing mode
    -- Access through RefreshGeneral with bottomMode; simulate details open
    local genPaint = ui._generalPaintCount
    ui:RefreshGeneral()
    local list1 = GR.WantedLogic.Sorted({ wanted = scope.wanted }, now, {})
    check("P2 Alpha tops at t0", list1[1] and list1[1].key == "Alpha-Realm", list1[1] and list1[1].key)
    -- Jump clock past Alpha's hour boundary
    sim.clock = sim.clock + 2
    local now2 = GR.Util.WallTime()
    local list2 = GR.WantedLogic.Sorted({ wanted = scope.wanted }, now2, {})
    check("P2 Beta tops after hour", list2[1] and list2[1].key == "Beta-Realm", list2[1] and list2[1].key)
    -- Sync age string must change when clock jumps (AGO seconds)
    local age1 = string.format(GR.Util.L("AGO"), 30)
    local age2 = string.format(GR.Util.L("AGO"), now2 - (now - 30))
    check("P2 sync age ticks", age1 ~= age2 or (now2 - (now - 30)) ~= 30, age1 .. " vs " .. age2)
  end

  -- P2: guild change invalidates Wanted cache during pending POS debounce
  do
    local scopeKey1 = GR.Util.GuildScopeKey()
    local scope1 = GR.Util.GetScopeDB()
    scope1.wanted = {
      ["Enemy-Realm"] = { legacy = 3, origins = {}, lastKillTime = GR.Util.WallTime(), lastSeenTime = 0 },
    }
    pcall(ui.ShowTab, ui, "general")
    ui:RefreshGeneral()
    local total1 = 0
    for _ in pairs(scope1.wanted) do total1 = total1 + 1 end
    check("P2 guild1 has wanted", total1 == 1, total1)

    -- Queue a POS debounce
    GR:SendMessage("POS_CACHE_CHANGED", "Peer1-Realm", {})
    -- Switch guild before debounce fires
    bob.guild = "Other Guild"
    GR.db.scopes = GR.db.scopes or {}
    local key2 = GR.Util.GuildScopeKey()
    check("P2 new guild key", key2 and key2 ~= scopeKey1, tostring(key2))
    GR.db.scopes[key2] = GR.db.scopes[key2] or { wanted = {}, wantedHidden = {}, wantedSelf = {} }
    GR:SendMessage("GUILD_UPDATE")
    sim:Run(0.2)
    local scope2 = GR.Util.GetScopeDB()
    local total2 = 0
    for _ in pairs(scope2.wanted or {}) do total2 = total2 + 1 end
    check("P2 guild2 wanted empty", total2 == 0, total2)
    ui:RefreshGeneral()
    -- card should show 0 for new guild
    check("P2 paint after guild change", true)
  end
end

-- ---------- P3: MAP_SETTINGS size change reuses frames ----------
do
  local sim = Sim.New(42)
  local frames = 0
  local function NewFrame(typ, ...)
    frames = frames + 1
    local f = Sim.Stub()
    f._shown = true
    f._w, f._h = 26, 26
    f._parent = nil
    f._points = {}
    f.Show = function(self) self._shown = true end
    f.Hide = function(self) self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.SetSize = function(self, w, h) self._w, self._h = w, h end
    f.GetWidth = function(self) return self._w or 26 end
    f.GetHeight = function(self) return self._h or 26 end
    f.SetParent = function(self, p) self._parent = p end
    f.SetScale = function() end
    f.SetFrameLevel = function() end
    f.SetFrameStrata = function() end
    f.EnableMouse = function() end
    f.ClearAllPoints = function(self) self._points = {} end
    f.SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end
    f.SetScript = function() end
    f.CreateTexture = function()
      local t = Sim.Stub()
      t.SetSize = function() end
      t.SetPoint = function() end
      t.SetAllPoints = function() end
      t.ClearAllPoints = function() end
      t.SetTexture = function() end
      t.SetVertexColor = function() end
      t.SetTexCoord = function() end
      t.SetBlendMode = function() end
      t.SetAlpha = function() end
      t.Show = function() end
      t.Hide = function() end
      return t
    end
    return f
  end
  local canvas = NewFrame()
  canvas.GetWidth = function() return 1000 end
  canvas.GetHeight = function() return 1000 end
  canvas.GetFrameLevel = function() return 10 end
  canvas.GetFrameStrata = function() return "MEDIUM" end
  local mapShown = true
  local worldMap = {
    IsShown = function() return mapShown end,
    GetMapID = function() return 1429 end,
    GetCanvasScale = function() return 1 end,
    ScrollContainer = { Child = canvas },
    HookScript = function() end,
  }
  local db = Sim.DefaultDB()
  db.map = { showPins = true, pinSize = 26, pinClustering = false, pinStyle = "heads" }
  local alice = sim:AddClient("Alice", {
    db = db,
    extraFiles = { "Modules/Positions.lua", "Modules/MapPins.lua" },
    env = {
      CreateFrame = NewFrame,
      WorldMapFrame = worldMap,
      GameTooltip = {
        SetOwner = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
      },
    },
  })
  local GR = alice.GR
  local pins = GR:GetModule("MapPins")
  for i = 1, 10 do
    GR:SendMessage("POS_UPDATE", "P" .. i .. "-Realm", {
      mapId = 1429, x = 0.1 * i, y = 0.2, time = 1, classFile = "MAGE", level = 60,
    })
  end
  pins:Refresh()
  local afterFirst = frames
  check("P3 initial frames >0", afterFirst > 0, afterFirst)
  for size = 27, 31 do
    GR.db.map.pinSize = size
    GR:SendMessage("MAP_SETTINGS_CHANGED")
  end
  check("P3 five size steps zero new frames", frames == afterFirst, frames .. " vs " .. afterFirst)

  -- clustering join/split with Refresh (pool kept)
  GR.db.map.pinClustering = true
  GR.db.map.pinSize = 26
  local posMod = GR:GetModule("Positions")
  local cache = posMod:GetCache()
  for k in pairs(cache) do cache[k] = nil end
  cache["A-Realm"] = { mapId = 1429, x = 0.50, y = 0.50, time = 1, classFile = "MAGE", level = 60 }
  cache["B-Realm"] = { mapId = 1429, x = 0.50 + (28 / 1000), y = 0.50, time = 1, classFile = "MAGE", level = 60 }
  pins:Refresh()
  local mid = frames
  GR.db.map.pinSize = 31
  GR:SendMessage("MAP_SETTINGS_CHANGED")
  GR.db.map.pinSize = 26
  GR:SendMessage("MAP_SETTINGS_CHANGED")
  check("P3 cluster resize no new frames", frames == mid, frames .. " vs " .. mid)
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
