# WoW Addon Entwicklung — Referenz

Allgemeine deutschsprachige Hilfestellung für WoW-Addon-Entwicklung (Classic/TBC-Fokus).  
Basiert auf [Malura — WoW Addon Dokumentation](https://malura.de/projekte/wow-addon-dokumentation); Abschnitte 8–12 fehlen dort im Live-Body und sind hier aus Standard-WoW-API ergänzt.

**Agents:** Entscheidungsregeln und Projektbefunde stehen im Skill
`.cursor/skills/wow-addon-dev/` (`SKILL.md` + `references/`). Diese Datei bleibt die
menschliche Tutorial-Referenz.

## Inhaltsverzeichnis

1. [Erste Schritte](#1-erste-schritte)
2. [Addon-Struktur & TOC-Datei](#2-addon-struktur--toc-datei)
3. [Lua Grundlagen](#3-lua-grundlagen)
4. [Event-System](#4-event-system)
5. [Widget API — UI Elemente](#5-widget-api--ui-elemente)
6. [Häufige API-Funktionen](#6-häufige-api-funktionen)
7. [Slash-Befehle](#7-slash-befehle)
8. [SavedVariables](#8-savedvariables--persistente-daten)
9. [XML UI Layout](#9-xml-ui-layout)
10. [Secure Templates & Combat Lockdown](#10-secure-templates--combat-lockdown)
11. [Classic / TBC / Forever](#11-classic--tbc--forever)
12. [Ressourcen](#12-ressourcen)

---

## 1. Erste Schritte

### Was du brauchst

- Texteditor (VS Code, Cursor, Notepad++, …)
- Installierter WoW-Client (Classic / TBC / Forever / …)
- Keine Vorkenntnisse nötig — Lua ist klein und lesbar

### Addon-Speicherort

```
World of Warcraft\_classic_\Interface\AddOns\DeinAddonName\
```

Andere Clients analog: `_classic_era_`, `_classic_tbc_`, `_forever_`, …

### Dein erstes Addon

1. Ordner `Interface\AddOns\HalloWelt\`
2. `HalloWelt.toc`:

```toc
## Interface: 11508
## Title: Hallo Welt
## Notes: Mein erstes Addon!
## Author: DeinName
## Version: 1.0.0

HalloWelt.lua
```

3. `HalloWelt.lua`:

```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
  print("Hallo, Welt!")
end)
```

4. Im Spiel: `/reload`

### Entwicklungswerkzeuge

| Befehl | Wirkung |
|--------|---------|
| `/reload` | UI + Addons neu laden |
| `/dump ausdruck` | Lua-Ausdruck auswerten |
| `/etrace` | Event-Trace |
| `/fstack` | Frame-Stack unter dem Cursor |

Zusätzlich: BugSack / BugGrabber für Lua-Fehler.

---

## 2. Addon-Struktur & TOC-Datei

### Typische Ordnerstruktur

```
MeinAddon/
├── MeinAddon.toc
├── MeinAddon.lua
├── Config.lua
├── embeds.xml          # optional: Libs
├── libs/
└── Localization/       # oder Locales/
```

### TOC-Format

```toc
## Interface: 11508
## Title: Mein Addon
## Notes: Beschreibung
## Author: Name
## Version: 1.0.0
## SavedVariables: MeinAddonDB
## SavedVariablesPerCharacter: MeinAddonCharDB
## OptionalDeps: Ace3

embeds.xml
Core.lua
Config.lua
```

Dateien werden **von oben nach unten** geladen. Nur `.lua` / `.xml` in die TOC schreiben.

### Wichtige TOC-Direktiven

| Direktive | Bedeutung |
|-----------|-----------|
| `Interface` | Client-Build (sonst „Out of date“) |
| `Title` / `Notes` | Anzeigename / Tooltip |
| `SavedVariables` | Account-weite Persistenz |
| `SavedVariablesPerCharacter` | Pro Charakter |
| `Dependencies` | Pflicht-Addons |
| `OptionalDeps` | Optionale Abhängigkeiten (Lade-Reihenfolge) |
| `LoadOnDemand` | `1` = bei Bedarf laden |

### Interface-Versionen (Richtwerte)

| Client | Interface |
|--------|-----------|
| Classic Era / Anniversary | `11508` |
| TBC Classic | `20504` |
| Wrath Classic | `30403` |
| Cataclysm Classic | `40400` |
| Forever | `16001` (prüfen!) |

Aktuell prüfen: `/dump select(4, GetBuildInfo())`

---

## 3. Lua Grundlagen

### Variablen & Typen

```lua
local wert = "Hallo"   -- lokal bevorzugen
Globale = "selten"     -- Globals vermeiden

local n = 100
local ok = true
local nichts = nil
local liste = {1, 2, 3}           -- Array (1-indiziert!)
local dict = {name = "Held"}      -- Dictionary
```

### Operatoren

- Vergleich: `==`, `~=` (nicht `!=`), `<`, `>`
- Logisch: `and`, `or`, `not`
- String: `"a" .. "b"`
- Idiom: `local s = (leben > 50) and "Gut" or "Schlecht"`

### Kontrollstrukturen & Schleifen

```lua
if leben > 50 then
  print("ok")
elseif leben > 25 then
  print("vorsicht")
else
  print("kritisch")
end

for i = 1, 10 do end
for i, v in ipairs(liste) do end   -- Array
for k, v in pairs(dict) do end     -- Dictionary
```

### Funktionen & Tabellen-als-Objekt

```lua
local function add(a, b)
  return a + b
end

local Addon = {}
function Addon:Init()
  self.aktiv = true
end
Addon:Init()
```

---

## 4. Event-System

### Grundmuster

```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_LOGIN" then
    print("login")
  elseif event == "PLAYER_LOGOUT" then
    print("logout")
  end
end)
```

Parameter: `self` (Frame), `event` (String), `...` (Event-Args).

```lua
frame:UnregisterEvent("UNIT_HEALTH")
frame:UnregisterAllEvents()
frame:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
```

### Wichtige Events

**Login / Laden**

| Event | Wann |
|-------|------|
| `ADDON_LOADED` | Addon geladen — hier SavedVariables nutzen |
| `PLAYER_LOGIN` | Spieler fertig eingeloggt |
| `PLAYER_ENTERING_WORLD` | Ladebildschirm vorbei (auch Zonenwechsel) |
| `PLAYER_LOGOUT` | Logout |

**Kampf**

| Event | Wann |
|-------|------|
| `PLAYER_REGEN_DISABLED` | Kampf beginnt |
| `PLAYER_REGEN_ENABLED` | Kampf endet |
| `COMBAT_LOG_EVENT_UNFILTERED` | Kampflog (Client-abhängig eingeschränkt) |
| `PLAYER_DEAD` | Tod |

**Einheiten / Gruppe**

| Event | Args / Hinweis |
|-------|----------------|
| `UNIT_HEALTH` | `unitId` |
| `UNIT_POWER_UPDATE` | `unitId`, powerType |
| `UNIT_AURA` | Buffs/Debuffs |
| `UNIT_TARGET` / `PLAYER_TARGET_CHANGED` | Ziel |
| `GROUP_ROSTER_UPDATE` | Gruppe geändert |

### Dispatch-Table-Pattern

```lua
local frame = CreateFrame("Frame")
local events = {}

function events:PLAYER_LOGIN()
  print("login")
end

function events:UNIT_HEALTH(unit)
  if unit == "player" then
    print(UnitHealth("player"))
  end
end

frame:SetScript("OnEvent", function(self, event, ...)
  local fn = events[event]
  if fn then fn(self, ...) end
end)

for event in pairs(events) do
  frame:RegisterEvent(event)
end
```

---

## 5. Widget API — UI Elemente

### Frame erstellen

```lua
-- CreateFrame(type, name, parent, template)
local frame = CreateFrame("Frame", "MeinFrame", UIParent)
frame:SetSize(200, 100)
frame:SetPoint("CENTER")
```

### Häufige Typen

`Frame`, `Button`, `CheckButton`, `EditBox`, `ScrollFrame`, `Slider`, `StatusBar`

### Position & Sichtbarkeit

```lua
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 10, -5)
frame:ClearAllPoints()

frame:Show()
frame:Hide()
frame:SetShown(true)
frame:IsShown()   -- eigener State
frame:IsVisible() -- inkl. Parent-Kette
```

Anker: `TOPLEFT`, `TOP`, `TOPRIGHT`, `LEFT`, `CENTER`, `RIGHT`, `BOTTOMLEFT`, `BOTTOM`, `BOTTOMRIGHT`

### Texture & FontString

```lua
local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(frame)
bg:SetColorTexture(0, 0, 0, 0.8)

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(32, 32)
icon:SetPoint("LEFT", 5, 0)
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER")
text:SetText("Hallo")
text:SetTextColor(1, 1, 0)
```

### Button & StatusBar

```lua
local btn = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
btn:SetSize(100, 25)
btn:SetPoint("CENTER")
btn:SetText("Klick")
btn:SetScript("OnClick", function(self, button)
  print(button)
end)

local bar = CreateFrame("StatusBar", nil, UIParent)
bar:SetSize(200, 20)
bar:SetPoint("CENTER")
bar:SetMinMaxValues(0, 100)
bar:SetValue(75)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0, 1, 0)
```

### Script-Handler

`OnLoad`, `OnShow`, `OnHide`, `OnUpdate`, `OnEvent`, `OnEnter`, `OnLeave`, `OnMouseDown`, `OnMouseUp`, `OnClick`, `OnDragStart`, `OnDragStop`

---

## 6. Häufige API-Funktionen

### Unit IDs

`player`, `target`, `focus`, `pet`, `party1`–`party4`, `raid1`–`raid40`, `mouseover`, `targettarget`

### Unit / Health / Power

```lua
local name = UnitName("target")
local level = UnitLevel("target")
local class, classFile = UnitClass("target")  -- "Krieger", "WARRIOR"
local guid = UnitGUID("target")
local exists = UnitExists("target")
local isPlayer = UnitIsPlayer("target")

local hp, maxHp = UnitHealth("player"), UnitHealthMax("player")
local power, maxPower = UnitPower("player"), UnitPowerMax("player")
local isDead = UnitIsDead("target")
```

### Auras / Spells / Items

```lua
for i = 1, 40 do
  local name = UnitAura("player", i, "HELPFUL")
  if not name then break end
end

local spellName = GetSpellInfo(spellId)
local start, duration = GetSpellCooldown(spellId)

local itemName = GetItemInfo(itemId)
local count = GetItemCount(itemId)
```

API-Signaturen können je Client/Version abweichen — bei Fehlern warcraft.wiki.gg prüfen.

### Chat / Zeit / Gruppe

```lua
SendChatMessage("Hallo", "SAY")
SendChatMessage("msg", "GUILD")
DEFAULT_CHAT_FRAME:AddMessage("Hinweis", 1, 0.8, 0)

local t = GetTime()
local h, m = GetGameTime()

local n = GetNumGroupMembers()
local inRaid = IsInRaid()
local inGroup = IsInGroup()
```

---

## 7. Slash-Befehle

### Registrierung

```lua
SLASH_MEINADDON1 = "/meinaddon"
SLASH_MEINADDON2 = "/ma"

SlashCmdList["MEINADDON"] = function(msg, editBox)
  print("Befehl:", msg)
end
```

Schlüssel in `SlashCmdList` muss zum `SLASH_<KEY>n`-Präfix passen (hier `MEINADDON`).

### Argumente parsen

```lua
SlashCmdList["MEINADDON"] = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower() or "help"

  if cmd == "help" or cmd == "" then
    print("/ma config | /ma toggle")
  elseif cmd == "config" then
    -- Options öffnen
  elseif cmd == "toggle" then
    -- Feature umschalten
  else
    print("Unbekannt:", cmd)
  end
end
```

---

## 8. SavedVariables — Persistente Daten

> Ergänzung (Abschnitt auf Malura-Live-Seite fehlt).

### TOC

```toc
## SavedVariables: MeinAddonDB
## SavedVariablesPerCharacter: MeinAddonCharDB
```

- Account: `WTF\<Account>\SavedVariables\MeinAddon.lua`
- Charakter: `WTF\<Account>\<Realm>\<Char>\SavedVariables\MeinAddon.lua`

### Init-Pattern

SavedVariables sind erst nach `ADDON_LOADED` für **dein** Addon zuverlässig gesetzt.

```lua
local addonName = ...
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
  if name ~= addonName then return end

  MeinAddonDB = MeinAddonDB or {}
  local db = MeinAddonDB
  if db.version == nil then
    db.version = 1
    db.enabled = true
  end
  -- Defaults nachziehen, Migrationen hier
end)
```

### Defaults & Migration

```lua
local defaults = { enabled = true, scale = 1 }

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

CopyDefaults(defaults, MeinAddonDB)
```

Nur `nil` überschreiben — bewusstes `false` (Feature aus) bleibt erhalten.
Nicht `db.flag or true` für Booleans nutzen.

`PLAYER_LOGOUT` ist optional für Aufräumen; der Client schreibt SV automatisch.

---

## 9. XML UI Layout

> Ergänzung (Abschnitt auf Malura-Live-Seite fehlt).

Viele moderne Addons bauen UI rein in Lua (`CreateFrame`). XML lohnt sich für Templates, Secure-Buttons und große Layouts.

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">

  <Script file="MeinAddon.lua"/>
  <Include file="Templates.xml"/>

  <Frame name="MeinAddonFrame" parent="UIParent" enableMouse="true" movable="true" hidden="true">
    <Size x="300" y="200"/>
    <Anchors>
      <Anchor point="CENTER"/>
    </Anchors>
    <Scripts>
      <OnLoad>
        self:RegisterForDrag("LeftButton")
      </OnLoad>
      <OnDragStart>
        self:StartMoving()
      </OnDragStart>
      <OnDragStop>
        self:StopMovingOrSizing()
      </OnDragStop>
    </Scripts>
  </Frame>
</Ui>
```

XML-Datei in der TOC listen (oder via `<Include>` / `<Script>` laden).

---

## 10. Secure Templates & Combat Lockdown

> Ergänzung (Abschnitt auf Malura-Live-Seite fehlt).

### Combat Lockdown

Im Kampf (`InCombatLockdown() == true`) sind viele Frame-/Action-Änderungen verboten (geschützte Frames, Attribute, Parent, …).

```lua
if InCombatLockdown() then
  -- später nachholen
  return
end
-- sichere Änderungen
```

Nach Kampfende: `PLAYER_REGEN_ENABLED` nutzen, um deferred Arbeit nachzuholen.

### Secure Action Buttons

Geschützte Aktionen (Cast, Target, …) nur über Secure-Templates, typisch `SecureActionButtonTemplate`:

```lua
local btn = CreateFrame("Button", "MeinSecureBtn", UIParent, "SecureActionButtonTemplate")
btn:SetSize(36, 36)
btn:SetPoint("CENTER")
btn:RegisterForClicks("AnyUp", "AnyDown") -- Classic/TBC oft beide nötig
btn:SetAttribute("type", "spell")
btn:SetAttribute("spell", "Feuerball")
btn:SetAttribute("unit", "target")
```

Attribute nur **außerhalb** des Kampfes setzen/ändern. Normale Lua-`CastSpellByName`-Aufrufe aus Addon-Code sind eingeschränkt bzw. taint-anfällig — Secure-Weg bevorzugen.

---

## 11. Classic / TBC / Forever

> Ergänzung (Abschnitt auf Malura-Live-Seite fehlt; Forever-Hinweis zusätzlich).

### Classic-Familie

- Interface-Nummer in der TOC muss zum Client passen.
- Multi-Client: ggf. `Addon_Vanilla.toc` / `Addon_TBC.toc` / … oder bedingte TOC-Direktiven (siehe warcraft.wiki.gg — TOC format).
- Secure-Clicks: auf manchen Classic-Clients `AnyUp` **und** `AnyDown` registrieren.
- API-Namen und Aura-Signaturen unterscheiden sich zwischen Retail und Classic — nicht blind Retail-Snippets kopieren.

### Forever (kurz)

- Pfad oft: `World of Warcraft\_forever_\Interface\AddOns\`
- Interface aktuell z. B. `16001` — immer mit `/dump select(4, GetBuildInfo())` prüfen.
- Manche Events/`RegisterEvent`-Aufrufe können mit `ADDON_ACTION_FORBIDDEN` scheitern → Fehler mit `pcall` abfangen und **echten Fallback** nutzen (kein CLEU erzwingen, wenn der Client es blockt). `pcall` entsperrt keine verbotene Aktion.

---

## 12. Ressourcen

| Ressource | URL |
|-----------|-----|
| Malura-Referenz (Quelle) | https://malura.de/projekte/wow-addon-dokumentation |
| Warcraft Wiki (API / TOC) | https://warcraft.wiki.gg |
| TOC-Format | https://warcraft.wiki.gg/wiki/TOC_format |
| SavedVariables | https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions |
| SecureTemplates | https://warcraft.wiki.gg/wiki/SecureActionButtonTemplate |
| Malura WoW-Addons (GitHub) | https://github.com/maluramichael?tab=repositories&q=wow-addon |

Empfohlene Debug-Addons: **BugSack**, **BugGrabber**.

---

## Hinweis zur Quelle

Die Live-Seite bei Malura listet Abschnitte 8–12 im Inhaltsverzeichnis, liefert aber (Stand Recherche) keinen Body dafür — der Content bricht nach Slash-Befehlen ab. Abschnitte 8–12 hier sind bewusst ergänzt und als solche markiert.
