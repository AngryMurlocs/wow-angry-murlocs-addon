-- PROFRCQ category request path + privacy vs disable purge.
-- From repo root: luajit Tests/RecipeCategorySync_test.lua
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

local RESULT = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 }

-- Codec rejects oversized / bad ids
do
  AngryMurlocs = AngryMurlocs or {}
  -- Load ProfRecipes codecs via a sim client.
  local sim = Sim.New(20)
  local alice = sim:AddClient("Alice", { extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" } })
  local R = alice.GR:GetModule("ProfRecipes")
  local body = R.EncodeCategoryRequest({ 5, 1, 5, 2 })
  local ids = R.DecodeCategoryRequest(body)
  check("encode/decode sort uniq", ids and ids[1] == 1 and ids[2] == 2 and ids[3] == 5 and #ids == 3)
  local tooMany = {}
  for i = 1, 25 do tooMany[i] = i end
  local enc = R.EncodeCategoryRequest(tooMany)
  local dec = R.DecodeCategoryRequest(enc)
  check("encoder trims to 24", dec and #dec == 24)
  local _, why = R.DecodeCategoryRequest("1|" .. table.concat(tooMany, "+"))
  -- Decode of 25 ids should reject when not trimmed by encoder
  local raw25 = "1|" .. table.concat(tooMany, "+")
  local d25, w25 = R.DecodeCategoryRequest(raw25)
  check("decode rejects 25", d25 == nil and w25 == "too_many")
end

-- Category-only request does not send PROFRM
do
  local sim = Sim.New(21)
  local alice, bob
  alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel)
          sim:Deliver(alice, prefix, msg, channel)
          return RESULT.Success
        end,
      },
    },
  })
  bob = sim:AddClient("Bob", {
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel)
          sim:Deliver(bob, prefix, msg, channel)
          return RESULT.Success
        end,
      },
    },
  })
  alice.GR:GetModule("ProfRecipes"):OnEnable()
  bob.GR:GetModule("ProfRecipes"):OnEnable()
  -- Alice knows category for 4242 without confirmed reagents.
  alice.GR:GetModule("ProfRecipes").StoreMeta(4242, {
    categoryId = 55,
    categoryName = "Potions",
    name = "Test Potion",
  })
  bob.GR.Comm:Send("PROFRCQ|" .. bob.GR:GetModule("ProfRecipes").EncodeCategoryRequest({ 4242 }), "ctrl", "sync")
  sim:Run(8)
  local sawC, sawM = false, false
  for _, m in ipairs(sim.bus) do
    if m.msg:find("^PROFRC|") then sawC = true end
    if m.msg:find("^PROFRM|") then sawM = true end
  end
  check("category reply sent", sawC)
  check("no material reply for PROFRCQ", not sawM)
  local key, name, resolved = bob.GR:GetModule("ProfRecipes").ResolveRecipeCategory(4242, "alch")
  check("bob resolved category", resolved == true and key == "55" and name == "Potions", tostring(key) .. "/" .. tostring(name))
end

-- Disable purges queued category reply
do
  local sim = Sim.New(22)
  local alice
  alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() return RESULT.AddonMessageThrottle end,
      },
    },
  })
  local R = alice.GR:GetModule("ProfRecipes")
  R:OnEnable()
  R.StoreMeta(7, { categoryId = 1, categoryName = "X" })
  R:OnCategoryRequest("Bob-Realm", { 7 })
  check("reply queued", alice.GR.Comm:QueueSize() >= 1)
  R:OnDisable()
  check("disable clears reply queue", alice.GR.Comm:QueueSize() == 0, alice.GR.Comm:QueueSize())
end

-- Locked: shareProfessions off purges reply, keeps request sendable.
do
  local sim = Sim.New(23)
  local alice
  alice = sim:AddClient("Alice", {
    extraFiles = { "Modules/Professions.lua", "Modules/ProfRecipes.lua" },
    env = {
      Enum = { SendAddonMessageResult = RESULT },
      C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function() return RESULT.AddonMessageThrottle end,
      },
    },
  })
  local R = alice.GR:GetModule("ProfRecipes")
  R:OnEnable()
  R.StoreMeta(9, { categoryId = 2, categoryName = "Y" })
  alice.GR.Comm:Send("PROFRCQ|1|9", "ctrl", "sync", { operationId = "req-priv" })
  R:OnCategoryRequest("Bob-Realm", { 9 })
  check("req+reply queued", alice.GR.Comm:QueueSize() >= 2, alice.GR.Comm:QueueSize())
  alice.GR.db.privacy.shareProfessions = false
  alice.GR:SendMessage("SHARE_PROF_CHANGED")
  local left = alice.GR.Comm:QueueSize()
  check("privacy keeps request in queue", left >= 1, left)
  local sent = {}
  alice.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel)
    sent[#sent + 1] = msg
    return RESULT.Success
  end
  sim:Run(5)
  local sawReq, sawRep = false, false
  for i = 1, #sent do
    if sent[i]:find("^PROFRCQ|") then sawReq = true end
    if sent[i]:find("^PROFRC|") then sawRep = true end
  end
  check("privacy still sends request", sawReq)
  check("privacy blocks reply", not sawRep)
end

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
