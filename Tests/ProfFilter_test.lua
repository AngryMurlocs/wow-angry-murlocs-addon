-- Profession MatchesProfessionFilter cases (no network).
-- From repo root: luajit Tests/ProfFilter_test.lua

local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

-- Minimal env so UI.lua can load its filter helper without full WoW.
package.path = package.path
dofile("Localization/enUS.lua")
dofile("Core/Util.lua")
dofile("Core/Theme.lua")

-- Stub Ace-like module shell used by UI.lua
local GR = AngryMurlocs
GR.VERSION = "test"
function GR:NewModule(name)
  local m = {}
  GR._modules = GR._modules or {}
  GR._modules[name] = m
  return m
end
function GR:GetModule(name)
  return GR._modules and GR._modules[name]
end
function GR:RegisterMessage() end
function GR:UnregisterMessage() end
function GR:BindMessage() end
function GR:UnbindMessages() end
function GR:ReleaseEventFrame() end
function GR:SendMessage() end

-- Minimal CreateFrame so UI module file can load.
_G.CreateFrame = function()
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == "string" and k:match("^%u") then
        local f = function() return t end
        rawset(t, k, f)
        return f
      end
    end,
  })
end
_G.UIParent = _G.CreateFrame()
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.GameTooltip_Hide = function() end

dofile("Modules/UI.lua")

local Match = GR:GetModule("UI").MatchesProfessionFilter

local entry = {
  list = {
    { key = "ench", skill = 225, name = "Enchanting" },
    { key = "tail", skill = 300, name = "Tailoring" },
  },
}

check("empty filter passes", Match("Bob", entry, {}))
check("name text match", Match("Bob-Realm", entry, { text = "bob" }))
check("prof key alone requires that key", Match("Bob", entry, { profKey = "ench" }))
check("other key alone fails", not Match("Bob", entry, { profKey = "alch" }))
check("selected prof + min skill ok", Match("Bob", entry, { profKey = "ench", minSkill = 200 }))
check("selected prof + min skill fail", not Match("Bob", entry, { profKey = "ench", minSkill = 250 }))
check("other high skill ignored when key set", not Match("Bob", entry, { profKey = "ench", minSkill = 250 }))
check("no key: any skill meets min", Match("Bob", entry, { minSkill = 300 }))
check("no key: min too high fails", not Match("Bob", entry, { minSkill = 301 }))
check("empty min means no skill gate", Match("Bob", entry, { profKey = "ench", minSkill = nil }))
check("combined text key skill", Match("Bob", entry, { text = "ench 200" }))
check("combined text key skill fail", not Match("Bob", entry, { text = "ench 250" }))

local online = {}
check("active only filters offline", not Match("Bob", entry, {
  activeOnly = true,
  isOnline = function(n) return online[n] end,
}))
online.Bob = true
check("active only allows online", Match("Bob", entry, {
  activeOnly = true,
  me = "Me",
  isOnline = function(n) return online[n] end,
}))

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
