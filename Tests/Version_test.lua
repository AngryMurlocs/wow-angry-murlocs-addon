-- The addon version lives in four places and they must always agree:
--   AngryMurlocs.toc "## Version:", GR.VERSION in AngryMurlocs.lua,
--   "**Version:**" in README.md, and the top "## X.Y.Z" in CHANGELOG.md.
-- An optional "## Unreleased" section may sit above the top version.
-- With the argument "release" (release MRs) there must be no "## Unreleased"
-- section any more, so the new version is the top section.
-- Run from repo root: luajit Tests/Version_test.lua [release]

local releaseMode = arg and arg[1] == "release"

local function ReadFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local fails = 0
local function check(name, cond)
  if cond then
    print("OK  " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name)
  end
end

local SEMVER = "^%d+%.%d+%.%d+$"

local toc = ReadFile("AngryMurlocs.toc"):match("## Version:%s*([^\r\n]+)")
local lua = ReadFile("AngryMurlocs.lua"):match('GR%.VERSION%s*=%s*"([^"]+)"')
local readme = ReadFile("README.md"):match("%*%*Version:%*%*%s*([^\r\n]+)")

-- Windows editors may save a byte order mark; CurseForge then shows the first
-- heading wrong.
for _, path in ipairs({ "CHANGELOG.md", "README.md", "AngryMurlocs.toc" }) do
  check(path .. " has no byte order mark", ReadFile(path):sub(1, 3) ~= "\239\187\191")
end

local headings = {}
for line in ReadFile("CHANGELOG.md"):gmatch("[^\r\n]+") do
  local h = line:match("^## (.+)$")
  if h then headings[#headings + 1] = h:gsub("%s+$", "") end
end

local hasUnreleased = headings[1] == "Unreleased"
local changelog = hasUnreleased and headings[2] or headings[1]

check("toc version is X.Y.Z (" .. tostring(toc) .. ")", toc and toc:match(SEMVER) ~= nil)
check("GR.VERSION matches toc (" .. tostring(lua) .. ")", lua == toc)
check("README version matches toc (" .. tostring(readme) .. ")", readme == toc)
check("CHANGELOG top version matches toc (" .. tostring(changelog) .. ")", changelog == toc)

local unreleasedCount = 0
for _, h in ipairs(headings) do
  if h == "Unreleased" then unreleasedCount = unreleasedCount + 1 end
end
check("at most one Unreleased section, and only at the top",
  unreleasedCount == 0 or (unreleasedCount == 1 and hasUnreleased))

if releaseMode then
  check("release: no Unreleased section left", not hasUnreleased)
end

print(fails .. " failures")
os.exit(fails == 0 and 0 or 1)
