-- Refreshes the Forever API snapshot used by Tests/ForeverApi_test.lua.
--
-- Source: https://github.com/Ketho/BlizzardInterfaceResources (branch "forever"),
-- dumped from the live WoW Forever client. The resource files are read as
-- text with patterns; nothing from the download is executed.
--
-- From the repo root (needs git and luajit or lua5.1):
--   luajit Tests/forever_api/update.lua                 clone/pull the branch, write Tests/forever_api
--   luajit Tests/forever_api/update.lua --src <dir>     use an existing checkout of the branch
--   luajit Tests/forever_api/update.lua --out <dir>     write the lists somewhere else (CI check)

local REPO = "https://github.com/Ketho/BlizzardInterfaceResources.git"
local BRANCH = "forever"
local CACHE = "Tests/forever_api/.cache"

local src, out = nil, "Tests/forever_api"
local i = 1
while arg and arg[i] do
  if arg[i] == "--src" then src = arg[i + 1]; i = i + 2
  elseif arg[i] == "--out" then out = arg[i + 1]; i = i + 2
  else error("unknown argument: " .. tostring(arg[i])) end
end

local function Run(cmd)
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end

local function Exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

if not src then
  src = CACHE
  if Exists(CACHE .. "/README.md") then
    Run('git -C "' .. CACHE .. '" fetch --quiet --depth 1 origin ' .. BRANCH)
    Run('git -C "' .. CACHE .. '" reset --quiet --hard FETCH_HEAD')
  else
    Run('git clone --quiet --depth 1 --single-branch --branch ' .. BRANCH .. ' ' .. REPO .. ' "' .. CACHE .. '"')
  end
end

local function Read(path)
  local f = assert(io.open(path, "rb"), "missing " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local function Write(path, lines)
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

local function SortedKeys(set)
  local list = {}
  for k in pairs(set) do list[#list + 1] = k end
  table.sort(list)
  return list
end

local R = src .. "/Resources/"

-- Global functions: Blizzard API plus functions defined by FrameXML
local functions = {}
for _, file in ipairs({ "GlobalAPI.lua", "FrameXML.lua" }) do
  for name in Read(R .. file):gmatch('"([^"]+)"') do functions[name] = true end
end

local events = {}
for name in Read(R .. "Events.lua"):gmatch('"([%u%d_]+)"') do events[name] = true end

local templates = {}
for name in Read(R .. "Templates.lua"):gmatch('%["([^"]+)"%]%s*=%s*{') do templates[name] = true end

-- Enum.<Name>.<Member>, read line by line from the Enum = { ... } block
local enums = {}
do
  local inEnum, current = false, nil
  for line in Read(R .. "LuaEnum.lua"):gmatch("[^\r\n]+") do
    if line:match("^Enum = {") then
      inEnum = true
    elseif inEnum then
      local name = line:match("^\t([%w_]+) = {")
      local member = line:match("^\t\t([%w_]+) = ")
      if name then
        current = name
      elseif member and current then
        enums["Enum." .. current .. "." .. member] = true
      elseif line:match("^}") then
        inEnum = false
      end
    end
  end
end

local build = Read(src .. "/README.md"):match('GetBuildInfo%(%) => ([^\n`]+)') or "unknown"
local commit = "unknown"
do
  local p = io.popen('git -C "' .. src .. '" rev-parse HEAD 2>/dev/null')
  if p then
    commit = (p:read("*l") or "unknown")
    p:close()
  end
end

local counts = {}
for label, set in pairs({ functions = functions, events = events, templates = templates, enums = enums }) do
  local list = SortedKeys(set)
  assert(#list > 100, "suspiciously few " .. label .. " (" .. #list .. "), is the source right?")
  Write(out .. "/" .. label .. ".txt", list)
  counts[label] = #list
end

Write(out .. "/SOURCE.txt", {
  "source: " .. REPO .. " (branch " .. BRANCH .. ")",
  "commit: " .. commit,
  "build: " .. build,
  string.format("functions: %d  events: %d  templates: %d  enums: %d",
    counts.functions, counts.events, counts.templates, counts.enums),
})

print(string.format("Forever API snapshot written to %s (build %s)", out, build))
print(string.format("functions %d, events %d, templates %d, enums %d",
  counts.functions, counts.events, counts.templates, counts.enums))
