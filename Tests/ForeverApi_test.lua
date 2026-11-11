-- Every WoW API the addon uses must exist in the WoW Forever client.
--
-- Checks all addon files listed in AngryMurlocs.toc against the snapshot in
-- Tests/forever_api (from Ketho/BlizzardInterfaceResources, branch "forever"):
--   global function calls        Foo(...)
--   C_ namespace functions       C_Foo.Bar
--   events                       RegisterEvent / SafeRegisterEvent / *_EVENTS lists
--   frame templates              CreateFrame(type, name, parent, "Template")
--   enum values                  Enum.Foo.Bar
-- Names that are missing on purpose (guarded fallbacks for other clients) are
-- listed in Tests/forever_api/allowed_missing.txt with a reason.
--
-- It does not prove that an API behaves the same on Forever. Test in game too.
--
-- From repo root: luajit Tests/ForeverApi_test.lua [snapshotDir]
local DATA = (arg and arg[1]) or "Tests/forever_api"

local fails = 0
local function Fail(msg)
  fails = fails + 1
  print("FAIL " .. msg)
end

local function Read(path)
  local f = assert(io.open(path, "rb"), "missing " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local function LoadSet(name)
  local set = {}
  for line in Read(DATA .. "/" .. name):gmatch("[^\r\n]+") do set[line] = true end
  return set
end

local functions = LoadSet("functions.txt")
local events = LoadSet("events.txt")
local templates = LoadSet("templates.txt")
local enums = LoadSet("enums.txt")

-- allowed_missing.txt: "Name  # reason" per line
local allowed = {}
for line in Read("Tests/forever_api/allowed_missing.txt"):gmatch("[^\r\n]+") do
  local name = line:match("^%s*([^#%s]+)")
  if name then allowed[name] = true end
end

-- C_ namespaces present in the snapshot (for bare namespace access)
local namespaces = {}
for name in pairs(functions) do
  local ns = name:match("^(C_[%w_]+)%.")
  if ns then namespaces[ns] = true end
end

-- Lua built-ins and frequent WoW-free globals that the call scan may see.
local LUA = {}
for name in ([[assert error getmetatable ipairs next pairs pcall print rawequal rawget rawlen
  rawset require select setmetatable tonumber tostring type unpack xpcall loadstring loadfile
  setfenv getfenv collectgarbage dofile load wipe tinsert tremove strsplit strjoin format date time]]):gmatch("%S+") do
  LUA[name] = true
end

local files = {}
for line in Read("AngryMurlocs.toc"):gmatch("[^\r\n]+") do
  line = line:gsub("^\239\187\191", "")
  if not line:match("^%s*#") and line:match("%.lua%s*$") then
    files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
  end
end

local function LineAt(s, pos)
  local n = 1
  for _ in s:sub(1, pos):gmatch("\n") do n = n + 1 end
  return n
end

-- Blank out comments and string contents (keeps positions for line numbers).
local function StripCode(s)
  s = s:gsub("%-%-%[(=*)%[.-%]%1%]", function(c) return (c:gsub("[^\n]", " ")) end)
  s = s:gsub('"[^"\n]*"', function(c) return '"' .. string.rep(" ", #c - 2) .. '"' end)
  s = s:gsub("'[^'\n]*'", function(c) return "'" .. string.rep(" ", #c - 2) .. "'" end)
  s = s:gsub("%-%-[^\n]*", function(c) return string.rep(" ", #c) end)
  return s
end

local seen = {}
local function Report(kind, name, file, line)
  if allowed[name] then return end
  local key = kind .. " " .. name
  if seen[key] then return end
  seen[key] = true
  Fail(string.format("%s %s not in Forever (%s:%d)", kind, name, file, line))
end

local checked = 0
for _, file in ipairs(files) do
  local raw = Read(file)
  local code = StripCode(raw)

  -- Names the addon defines itself (functions, locals, upvalues)
  local defined = {}
  for name in code:gmatch("function%s+([%a_][%w_]*)") do defined[name] = true end
  for list in code:gmatch("local%s+([%a_][%w_%s,]*)=") do
    for name in list:gmatch("[%a_][%w_]*") do defined[name] = true end
  end
  for list in code:gmatch("local%s+([%a_][%w_%s,]*)\n") do
    for name in list:gmatch("[%a_][%w_]*") do defined[name] = true end
  end
  for params in code:gmatch("function%s*[%w_%.:]*%s*%(([^%)]*)%)") do
    for name in params:gmatch("[%a_][%w_]*") do defined[name] = true end
  end

  -- Global function calls: Name( not preceded by . : or a word character
  for pos, name in code:gmatch("()([%a_][%w_]*)%s*%(") do
    local before = pos > 1 and code:sub(pos - 1, pos - 1) or ""
    if not before:match("[%.:%w_]") and not defined[name] and not LUA[name]
        and name ~= "function" and name:match("^[%u]") and not name:match("^C_") then
      checked = checked + 1
      if not functions[name] then Report("function", name, file, LineAt(code, pos)) end
    end
  end

  -- _G.Name lookups
  for pos, name in code:gmatch("()_G%.([%a_][%w_]*)") do
    if name:match("^C_") then
      if not namespaces[name] then Report("namespace", name, file, LineAt(code, pos)) end
    elseif not functions[name] and not defined[name] then
      Report("function", name, file, LineAt(code, pos))
    end
  end

  -- C_Namespace.Function
  for pos, ns, fn in code:gmatch("()(C_[%w_]+)%.([%a_][%w_]*)") do
    checked = checked + 1
    if not functions[ns .. "." .. fn] then Report("function", ns .. "." .. fn, file, LineAt(code, pos)) end
  end

  -- Enum.Name.Member
  for pos, name, member in code:gmatch("()Enum%.([%w_]+)%.([%w_]+)") do
    checked = checked + 1
    local full = "Enum." .. name .. "." .. member
    if not enums[full] then Report("enum", full, file, LineAt(code, pos)) end
  end

  -- Events: string literals in RegisterEvent calls and *_EVENTS lists
  for pos, ev in raw:gmatch('()RegisterEvent%s*%(%s*"([%u%d_]+)"') do
    checked = checked + 1
    if not events[ev] then Report("event", ev, file, LineAt(raw, pos)) end
  end
  for pos, ev in raw:gmatch('()RegisterEvent%s*%([^,%)\n]+,%s*"([%u%d_]+)"') do
    checked = checked + 1
    if not events[ev] then Report("event", ev, file, LineAt(raw, pos)) end
  end
  for pos, block in raw:gmatch("()[%w_]*_EVENTS%s*=%s*(%b{})") do
    for ev in block:gmatch('"([%u%d_]+)"') do
      checked = checked + 1
      if not events[ev] then Report("event", ev, file, LineAt(raw, pos)) end
    end
  end

  -- Frame templates: 4th argument of CreateFrame
  for pos, list in raw:gmatch('()CreateFrame%s*%(%s*"[^"]*"%s*,[^,\n]*,[^,\n]*,%s*"([^"]+)"') do
    for tmpl in list:gmatch("[^,%s]+") do
      checked = checked + 1
      if not templates[tmpl] then Report("template", tmpl, file, LineAt(raw, pos)) end
    end
  end
end

print(string.format("checked %d API uses in %d files against %s", checked, #files, DATA))
local source = Read(DATA .. "/SOURCE.txt"):match("build: ([^\n]+)")
if source then print("snapshot build " .. source) end
if checked < 100 then Fail("scan found too few API uses (" .. checked .. "), is the scanner broken?") end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
