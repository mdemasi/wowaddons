# AddonInstaller

One script, `install-addons.sh`, that installs or updates WoW addons from zip files and backs up your addon data and settings to a private GitHub repo. Made for Bazzite; works with Lutris, Steam/Proton, Bottles, Heroic and Faugus installs.

## Commands

| Command | What it does |
|---|---|
| `./install-addons.sh` | Back up addon data (once backups are set up), then install every `.zip` in this folder |
| `./install-addons.sh --no-backup` | Install without backing up first |
| `./install-addons.sh backup` | Back up addon data and settings now (sets up backups on first run) |
| `./install-addons.sh list` | Show recent backups |
| `./install-addons.sh restore [id]` | Put the latest backup (or one from `list`) back |

## Installing addons

1. Put this folder anywhere, e.g. `~/AddonInstaller`, and drop addon `.zip` files into it.
2. Run `./install-addons.sh`.

Each addon in each zip replaces the matching folder in `Interface/AddOns`, and the zip moves to `installed/`. The first run finds your AddOns folder (or asks for it) and remembers it in `addons-path.txt`. Afterwards, `/reload` in game picks up updates; newly added addons need a game restart.

## Backups

One-time setup:
1. On GitHub, create a new **private**, empty repo (e.g. `wowaddons-backup`).
2. Make sure `git push` works from your machine (SSH key or `gh auth login`).
3. Run `./install-addons.sh backup` and paste the repo URL when asked (remembered in `backup-remote.txt`).

From then on every install backs up first. Back up after logging out of WoW for the freshest data, since the game only saves addon data on logout or `/reload`.

Restoring needs WoW closed. Your current `WTF` folder is saved to `wtf-before-restore-<time>.tar.gz` first, and files are overwritten, never deleted.

Backed up from `WTF`: `Config.wtf`, and for the account and every character: `SavedVariables/*.lua` (addon data), macros, key bindings, enabled-addon lists (`AddOns.txt`), window layout and chat setup. `.bak` files are skipped. These include character names and notes typed into addons, so keep the repo private.
