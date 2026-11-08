# AngryMurlocs Changelog

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
