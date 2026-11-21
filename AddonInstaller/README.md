# AddonInstaller

Installs or updates WoW addons from zip files on Linux (made for Bazzite; works with Lutris, Steam/Proton, Bottles, Heroic and Faugus installs).

1. Put this folder anywhere, e.g. `~/AddonInstaller`.
2. Drop addon `.zip` files into it.
3. Run `./install-addons.sh` (or right-click it in the file manager and run it).

Each addon in each zip replaces the matching folder in `Interface/AddOns`, and the zip moves to `installed/`. The first run finds your AddOns folder (or asks for it) and remembers it in `addons-path.txt`. Addon settings in the `WTF` folder are left alone.

After it runs, `/reload` in game picks up updates; newly added addons need a game restart.

## Backing up addon data and settings

`wow-backup.sh` saves your addon data and settings to a **private** GitHub repo, and can put them back.

One-time setup:
1. On GitHub, create a new **private**, empty repo (e.g. `wowaddons-backup`).
2. Make sure `git push` works from your machine (SSH key or `gh auth login`).
3. Run `./wow-backup.sh backup` and paste the repo URL when asked (remembered in `backup-remote.txt`).

Commands:
- `./wow-backup.sh backup` — copy the files below from `WTF`, commit and push. Run it after logging out of WoW for the freshest data.
- `./wow-backup.sh list` — show recent backups.
- `./wow-backup.sh restore [id]` — put the latest backup (or one from `list`) back. WoW must be closed; your current `WTF` folder is saved to `wtf-before-restore-<time>.tar.gz` first. Files are overwritten, not deleted.

What's backed up from `WTF`: `Config.wtf`, and for the account and every character: `SavedVariables/*.lua` (addon data), macros, key bindings, enabled-addon lists (`AddOns.txt`), window layout and chat setup. `.bak` files are skipped.

These files include character names, notes you typed into addons, and other addon data, so keep the repo private.
