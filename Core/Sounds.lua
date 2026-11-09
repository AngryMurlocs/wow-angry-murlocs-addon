-- Per-kind notification sounds (lvl / death / sight). Default: off.
local GR = AngryMurlocs or {}
AngryMurlocs = GR

GR.Sounds = GR.Sounds or {}
local S = GR.Sounds

-- Placeholder catalog — finalize paths after Forever client probe-listen.
-- Invalid / unknown ids stay silent.
local CATALOG = {
  { id = "levelup", file = "Sound\\Interface\\LevelUp.ogg" },
  { id = "raidwarn", file = "Sound\\Interface\\RaidWarning.ogg" },
  { id = "tell", file = "Sound\\Interface\\iTellMessage.ogg" },
  { id = "auction", file = "Sound\\Interface\\AuctionWindowOpen.ogg" },
  { id = "mapping", file = "Sound\\Interface\\MapPing.ogg" },
}

local DEFAULTS = {
  lvl = { enabled = false, id = "levelup" },
  death = { enabled = false, id = "raidwarn" },
  sight = { enabled = false, id = "tell" },
}

local function CatalogById(id)
  for i = 1, #CATALOG do
    if CATALOG[i].id == id then return CATALOG[i] end
  end
end

function S.List()
  return CATALOG
end

function S.Ensure()
  GR.db = GR.db or {}
  GR.db.sounds = GR.db.sounds or {}
  local root = GR.db.sounds
  for kind, def in pairs(DEFAULTS) do
    local cur = root[kind]
    if type(cur) ~= "table" then
      root[kind] = { enabled = def.enabled, id = def.id }
    else
      if cur.enabled == nil then cur.enabled = def.enabled end
      if cur.id == nil or cur.id == "" then cur.id = def.id end
    end
  end
  return root
end

function S.Get(kind)
  local root = S.Ensure()
  return root[kind] or DEFAULTS[kind]
end

local function PlayFile(path)
  if not path or path == "" then return false end
  if PlaySoundFile then
    local ok = pcall(PlaySoundFile, path, "Master")
    if ok then return true end
    ok = pcall(PlaySoundFile, path)
    return ok and true or false
  end
  return false
end

-- Play catalog id (no enabled check). Invalid id = silent.
function S.PlayId(id)
  local entry = CatalogById(id)
  if not entry then return false end
  return PlayFile(entry.file)
end

-- Real alerts: only if enabled == true.
function S.Play(kind)
  local cfg = S.Get(kind)
  if not cfg or cfg.enabled ~= true then return false end
  return S.PlayId(cfg.id)
end

-- Probehören: ignores enabled switch.
function S.Preview(kind)
  local cfg = S.Get(kind)
  if not cfg then return false end
  return S.PlayId(cfg.id)
end

function S.SetEnabled(kind, on)
  local cfg = S.Get(kind)
  cfg.enabled = on and true or false
end

function S.SetId(kind, id)
  if not CatalogById(id) then return false end
  local cfg = S.Get(kind)
  cfg.id = id
  return true
end
