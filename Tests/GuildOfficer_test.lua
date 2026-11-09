-- U.IsGuildOfficer feature-detect gates (no real Forever client).
-- From repo root: luajit Tests/GuildOfficer_test.lua
local fails = 0
local function check(name, cond, extra)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (extra and (" (" .. tostring(extra) .. ")") or ""))
  end
end

local CLEAR = {
  "IsInGuild", "C_GuildInfo", "IsGuildLeader", "CanEditOfficerNote",
}
local function LoadUtil(env)
  -- Explicit nil clears: `{ key = nil }` is omitted by pairs in Lua 5.1.
  for i = 1, #CLEAR do _G[CLEAR[i]] = nil end
  for k, v in pairs(env) do _G[k] = v end
  _G.AngryMurlocs = {}
  dofile("Core/Util.lua")
  return _G.AngryMurlocs.Util
end

do
  local U = LoadUtil({
    IsInGuild = function() return false end,
    C_GuildInfo = nil,
    IsGuildLeader = nil,
    CanEditOfficerNote = nil,
  })
  check("no guild => false", U.IsGuildOfficer() == false)
end

do
  local U = LoadUtil({
    IsInGuild = function() return true end,
    C_GuildInfo = {
      IsGuildOfficer = function() return true end,
    },
    IsGuildLeader = function() return false end,
    CanEditOfficerNote = function() return false end,
  })
  check("C_GuildInfo.IsGuildOfficer true", U.IsGuildOfficer() == true)
end

do
  local U = LoadUtil({
    IsInGuild = function() return true end,
    C_GuildInfo = {
      IsGuildOfficer = function() return false end,
    },
    IsGuildLeader = function() return true end,
  })
  check("leader still true if IsGuildOfficer API false", U.IsGuildOfficer() == true)
end

do
  local U = LoadUtil({
    IsInGuild = function() return true end,
    C_GuildInfo = nil,
    IsGuildLeader = function() return true end,
    CanEditOfficerNote = function() return false end,
  })
  check("fallback IsGuildLeader", U.IsGuildOfficer() == true)
end

do
  local U = LoadUtil({
    IsInGuild = function() return true end,
    C_GuildInfo = {
      CanEditOfficerNote = function() return true end,
    },
    IsGuildLeader = function() return false end,
  })
  check("fallback C_GuildInfo.CanEditOfficerNote", U.IsGuildOfficer() == true)
end

do
  local U = LoadUtil({
    IsInGuild = function() return true end,
    C_GuildInfo = nil,
    IsGuildLeader = function() return false end,
    CanEditOfficerNote = function() return true end,
  })
  check("fallback global CanEditOfficerNote", U.IsGuildOfficer() == true)
end

do
  local U = LoadUtil({
    IsInGuild = function() return true end,
    C_GuildInfo = nil,
    IsGuildLeader = function() return false end,
    CanEditOfficerNote = function() return false end,
  })
  check("member without rights => false", U.IsGuildOfficer() == false)
end

print(string.format("\n%d failures", fails))
if fails > 0 then
  error(fails .. " test failures")
end
