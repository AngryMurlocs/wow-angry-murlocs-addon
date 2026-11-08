# AngryMurlocs Changelog

## 0.8.1

- Death Recap fallback when CLEU is silent (Forever)
- Player-* GUID from Recap counts Wanted + toast
- Mob/env Recap toasts without Wanted credit
- Shorter death toast strings (en/de)

## 0.8.0

### Freshness / UI

- Wanted sightings: three tiers — fresh (&lt;60 s), warm (&lt;5 min), stale (5+ min). List colour/suffix and tooltip label update while the panel is open.
- Guild map pins: fade from full alpha after 45 s toward ~0.25 at 60 s (TTL unchanged). Tooltip shows fresh / aging / about to disappear.
- Overlapping pins: older below newer; hover raises the pin.
- Professions: online from recent addon traffic (10 min), sort online↔name, paging Top 40 of N (no silent cut-off).
- Death and level-up toasts share one queue: death before level-up, 1.5 s display cooldown, combat deferral, max 20 (level-ups dropped first). No parallel overlapping toasts.

### Limits

- “Online” in the profession list means the addon was heard from, not WoW login state.
- Pin fade stays inside the existing 60 s position TTL (heartbeat ~25 s).

## 0.7.0

### Wanted counting

- New counting model: every victim (origin) keeps its own kill counter per killer. Level = legacy level + sum of origin counters. Merging takes the maximum per origin, so the same kill arriving live, relayed and by sync is counted once.
- The 10 s pair cooldown is checked only on the victim's own client. The old minute-bucket event id (which dropped a second kill after 10–59 s) is gone.
- Duels, battlegrounds, arenas and **unknown instance context** never count. Mobs, environment and unclear killers never count.
- **Auto-increment is effectively off on WoW Forever for now.** The only reliable killer source (combat log) is blocked there. A target or attacking enemy player is no longer blamed: such deaths show as "cause unknown" and do not count. Use `/am diag on` + `/am diag death` to collect evidence for a reliable source.
- Shift-click no longer deletes for the guild. It hides the entry **locally**; it returns when its level rises. `/am wanted unhide all` restores everything.
- Wanted list: shows "Top 40 of N" with paging, search by name, sort by level or last seen, a source breakdown in the tooltip (own / victim report / relayed / legacy) and the data age.

### Sync

- New wire messages (`WK`, `SR`, `WSH`, `WS`, `WSE`). Legacy `WANTED|*` and `SYNCREQ` from 0.6.x are ignored (counted in diagnostics).
- One sync request per session (login/reload, random 4–10 s delay) and on guild change; no longer on every loading screen. Manual sync via button or `/am sync`.
- Only one guild member answers: others cancel when they see a response header. If two answer at the same time, the one with the alphabetically later name drops its queued rest. Paged responses (120 records/page, cursor by change time + key, up to 5 pages automatically, "partial" can be resumed).
- At login each member re-announces its own newest victim counters (max. 20, only with death sharing on), so members who were offline when it happened learn them. Duplicates are ignored by receivers.
- Login storms: responders keep a random subset of pending requests (max. 3), and a requester that got no answer while other 0.7+ members are online retries up to 2 times.
- Visible sync status: waiting, receiving x/y from name, complete, partial, incomplete, "no responding guild member". Sync buttons are locked while a sync runs.
- Outgoing messages go through a priority queue (kill > control > data > position), max. 2 per second, bounded per class.

### Privacy

- Own deaths are only sent (live and in sync answers) while "Share guild deaths" is on. The dead flag in position updates follows the same setting.
- Turning a share setting off drops queued messages of that kind.
- Profession cache is now stored per guild + realm (moved once into the guild that is active at the first login).
- Wanted scope recovery only merges keys of the **same** guild and realm (case/space variants, `__none__` from the same realm). Other guilds are never merged.

### Diagnostics

- `/am diag on|off|show|death`: local ring buffer (200 entries) with rejection reasons, queue sizes and peer counts. `death` shows which death-related events and APIs the client actually provides. Nothing is sent to the guild.

### Migration

- SavedVariables schema 2. Old Wanted entries keep their level as `legacy` (no per-kill history existed). Migration is repeatable and leaves privacy settings, pins and toast layout untouched.

### Mixed versions and known limits

- 0.6.x and 0.7.0 do not exchange Wanted data. Until everyone updates, lists can differ between members.
- Legacy levels merge by maximum. If two members had different old histories for the same killer, the merged level can be lower than their sum.
- Each killer keeps at most 100 origins. If more victims exist, the smallest counters are dropped and the level can fall (logged in diagnostics).
- Delta sync after a responder change is approximate; use a manual (full) sync if a list looks incomplete.
- Data already received by other clients cannot be recalled when you turn a share setting off.
- Sharing your position while dead (ghost) can still reveal a death indirectly, even with death sharing off.
- Victim reports are statements by addon clients, not server-confirmed kills.

## 0.6.1

- Smart Auto-Wanted with **guild-fixed** rules (no per-player sliders): promote on **first** kill, pair CD 10s, event dedup
- Wanted **Level** (+1 per validated guild kill) and ranks: Markiert / Gesucht / Kopfgeld / Erzfeind / Gildenschreck
- No time-expire; safety cap 1000 entries; UI + full-sync Top 40; live `WANTED|kill` to all online
- No manual/auto distinction; BG/arena/duel excluded
- Map pins: normalize class head/body art via TexCoords; pin size slider applies to rings
- Polish: Wanted scope recover once + orphan wipe; prune stale event ids; death killer uses UnitFullName

## 0.6.0

- Remove Main/Twink and Craft (Handwerk) modules, tabs, slash commands, and wire handlers
- Fix empty remote profession lists: keep PROF pipe delimiters; harden empty-cache overwrite; delayed rebroadcast
- Pixel-aligned list columns (professions + Wanted) for proportional fonts
- Fix self appearing twice in profession list (Forever name-fold / compact match)
- Wanted: full guild sync + scope recovery so the list survives reloads/updates; remove clear-all button
- Auto guild sync (professions + Wanted) after loading screens (`PLAYER_ENTERING_WORLD`, debounced)
- Exclusive Berufe / Wanted windows (no stacked overlay at CENTER)
- `/am config` (also `options` / `settings`); Settings nav; minimap LMB Wanted / RMB main (from 0.5.8)

## 0.5.8

- `/am config` (also `options` / `settings`) opens addon settings
- Settings nav button in main window
- Minimap: left-click Wanted, right-click main window

## 0.5.7

- Fix invisible guild pins: re-export Media/Pins TGAs in WoW-compatible format (match circle.tga)

## 0.5.6

- Guild pin default size 18 (larger murloc icons)

## 0.5.5

- Guild pins: drop round circle border; square murloc only; default size 14

## 0.5.4

- Fix guild pin zoom: use WorldMapFrame canvas scale + OnCanvasScaleChanged (Forever)

## 0.5.3

- Longer default toast times: level-up 8s, death 10s (migrates old 4.5/5.5)

## 0.5.2

- Default guild pin size matches Blizzard party pins (11); migrates old size 8

## 0.5.1

- Guild map pins use per-class mini-murloc icons (Media/Pins)
- Pin size stays fixed while zooming the world map (matches party-pin behavior)
- Options pin-size slider range 8–24

## 0.5.0

- Automatic Wanted sightings on targeting listed players (guild share, 60s send cooldown, separate alert cooldown, stale after 30 minutes)
- Settings for sharing sightings and showing sighting alerts
- Optional Main/Twink mapping, synced to guild; shown in profession list and map pin tooltips
- Guild craft request window (item link, qty, mats, note; claim / assign / done / reopen / cancel)
- Guild+realm scoped storage for Wanted, Mains, and Craft; legacy Wanted migrated once
- Safer addon comm: no silent truncation; fragment long messages; escape item-link pipes
- Navigation buttons; `/am craft`, `/am main`; Wanted remove via Shift-click only
- Larger scrollable lists for bigger guilds

## 0.4.0

- Prior release (map pins, professions, Wanted kills, death/level toasts)
