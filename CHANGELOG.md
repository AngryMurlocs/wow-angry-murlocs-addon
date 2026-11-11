# AngryMurlocs Changelog

## 0.11.1

- New look for death and level-up messages, with murloc artwork and a new font
- Death messages are easier to read: who died, the cause and the place each get their own line
- Level-up messages show the name in large letters above the new level

## 0.11.0

- The death message no longer guesses who or what killed you. If it is unclear, it says so.
- More reliable death messages, also in places without a zone name
- The addon tells you in chat when guild members use a newer version, so you know when to update

## 0.10.1

- The main window closes when you enter combat
- Overview and Settings can't be opened during combat

## 0.10.0

- New settings layout with a menu on the left: Sharing, Map, Level-Up, Death, Sightings and Interface
- Level-up and death messages: sound, size, duration and position each on one page
- Choose a sound for messages, listen to it first, and turn sounds on or off per message type
- Move the messages anywhere on screen and lock them in place, or reset position and size
- New: browse and search the recipes your guild's crafters know
- Clearer main window tabs

## 0.9.0

- Same changes as 0.8.3, released as a bigger update

## 0.8.3

- Guild members on the map now show as murlocs in their class colors
- When several members stand on the same spot, their icons spread out instead of covering each other
- Members standing apart stay where they actually are
- Icons stay in place when the map refreshes or you zoom

## 0.8.2

- Behind-the-scenes cleanup for better stability
- Minimap button and settings open more reliably
- The addon stays quiet when you are not in a guild

## 0.8.1

- Deaths caused by another player can now count towards the Wanted list again
- Deaths by monsters or falling show a message but don't count
- Shorter death messages

## 0.8.0

- Wanted sightings show how fresh they are: fresh, recent or old
- Guild map icons slowly fade out before they disappear. Hovering an icon brings it to the front.
- Professions list: see who is online, sort the list, and browse it page by page
- Death and level-up messages wait their turn instead of piling up, and wait until combat is over

## 0.7.0

- Fairer Wanted counting: each victim's kills are counted once, no matter how the news arrives
- Duels, battlegrounds and arenas never count. Neither do monsters or unclear deaths.
- Shift-click now hides a Wanted entry just for you instead of deleting it for the whole guild. `/am wanted unhide all` brings hidden entries back.
- Wanted list: pages, search, sorting by level or last seen, and more details per entry
- Guild data is shared once when you log in and when you change guilds, not on every loading screen. Use the sync button or `/am sync` to update manually.
- You can see how the data exchange with your guild is going
- Your own deaths are only shared while "Share guild deaths" is turned on
- Profession data is now kept separately for each guild
- `/am diag` shows local information for troubleshooting. Nothing is shared.
- All guild members should update: older versions can't exchange Wanted data with this one

## 0.6.1

- The Wanted list now works the same for everyone in the guild, with fixed rules
- Wanted players get a level and a rank: Markiert, Gesucht, Kopfgeld, Erzfeind, Gildenschreck
- Duels, battlegrounds and arenas don't count
- Better looking map icons, and the size setting now works for all icon styles

## 0.6.0

- Removed the Main/Twink and Craft features
- Fixed empty profession lists of other guild members
- Fixed your own name showing up twice in the professions list
- Lists line up neatly
- The Wanted list is kept after reloads and updates
- Guild data updates automatically after loading screens
- Professions and Wanted windows no longer open on top of each other

## 0.5.8

- `/am config` opens the settings
- Settings button in the main window
- Minimap button: left-click opens Wanted, right-click opens the main window

## 0.5.7

- Fixed guild map icons not showing up

## 0.5.6

- Bigger guild map icons

## 0.5.5

- Cleaner guild map icons without the round border

## 0.5.4

- Guild map icons keep their size when you zoom the map

## 0.5.3

- Level-up and death messages stay on screen longer

## 0.5.2

- Guild map icons now match the size of party icons

## 0.5.1

- Guild members on the map show as small murlocs for their class
- Icons keep their size while zooming
- More choice for the icon size

## 0.5.0

- Wanted sightings: when you target a Wanted player, your guild gets told where you saw them
- Settings for sharing and showing sightings
- Main/Twink: link your characters, visible to the guild
- Guild craft requests
- Data is kept separately for each guild
- More reliable sharing of long messages
- Bigger lists for bigger guilds

## 0.4.0

- First release: guild map icons, professions, Wanted list, death and level-up messages
