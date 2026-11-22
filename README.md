# WoW Addons

Addons for WoW Forever (interface 16001). Copy a folder into `Interface/AddOns/`, then `/reload`.

- **PersistentNotepad**: notepad saved between sessions, with a minimap button. `/np`
- **HawkTracker**: countdown bars and an expiry sound for Summon Hawk. `/hawks`
- **BreathFrame**: screen border while your breath runs out underwater. `/breathframe test`
- **TargetMacro**: right-click the target or focus frame and pick *Create Target Macro*, or use `/tmacro [focus|<name>]`, to get a targeting macro on your cursor. The minimap button opens settings for what the macro does (skip dead, hostile only, keep current target, raid marker and which one, focus, pet attack, auto attack, Auto Shot) with a live preview, and can update all macros it made. `/tmacro config`, `/tmacro update`
- **PetAbilityMap**: world map icon listing the pet abilities you can learn by taming in the zone you're viewing, plus a minimap button that opens a list of every ability and its ranks, marked learned or not. Click the map icon to show creature locations as ability icons on the map. Data from wow-petopia.com; locations from [QuestieDB](https://github.com/Questie/QuestieDB) (GPLv3). `/petab`, `/petab show`, `/petab known`
- **QuestZones**: floating window showing the % split of your unfinished quest objectives by continent, zones ranked by how much of your quest log you can progress there (yellow and green quests weighted 1.5x), and the top 6 zones to pick up new quests at or slightly below your level (quest chains count once). Toggle to include dungeon and raid quests. Recomputes on turn-in, accept, abandon and objective progress, or with the Recompute button. Locations from [QuestieDB](https://github.com/Questie/QuestieDB) (GPLv3). `/qz`

## Installing on Linux

`AddonInstaller/install-addons.sh` installs or updates addons from zip files and backs up or restores addon data and settings to a private repo. See `AddonInstaller/README.md`.
