-- From repo root: luajit Tests/PinFade_test.lua
AngryMurlocs = AngryMurlocs or {}
-- Minimal stub so MapPins can load as a module without WoW.
AngryMurlocs.Util = { ClassColor = function() return 1, 1, 1 end, L = function(k) return k end, Now = function() return 0 end }
AngryMurlocs.NewModule = function(self, name)
  local m = { name = name }
  self._modules = self._modules or {}
  self._modules[name] = m
  return m
end
dofile("Modules/MapPins.lua")

local M = AngryMurlocs._modules.MapPins
local fails = 0
local function check(name, cond, extra)
  if cond then print("OK  " .. name) else fails = fails + 1 print("FAIL " .. name .. (extra and (" " .. tostring(extra)) or "")) end
end

check("full at 0", M.FadeFactor(0) == 1)
check("full at 45", M.FadeFactor(45) == 1)
check("between at 52.5", math.abs(M.FadeFactor(52.5) - (1 + M.FADE_MIN) / 2) < 0.001, M.FadeFactor(52.5))
check("min at 60", M.FadeFactor(60) == M.FADE_MIN)
check("min past 60", M.FadeFactor(90) == M.FADE_MIN)
check("negative age full", M.FadeFactor(-5) == 1)
check("constants", M.STALE_SEC == 60 and M.FADE_START_SEC == 45 and M.FADE_MIN == 0.25)

print(string.format("\n%d failures", fails))
if fails > 0 then error(fails .. " test failures") end
