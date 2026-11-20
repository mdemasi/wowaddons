# AddonInstaller

Installs or updates WoW addons from zip files on Linux (made for Bazzite; works with Lutris, Steam/Proton, Bottles, Heroic and Faugus installs).

1. Put this folder anywhere, e.g. `~/AddonInstaller`.
2. Drop addon `.zip` files into it.
3. Run `./install-addons.sh` (or right-click it in the file manager and run it).

Each addon in each zip replaces the matching folder in `Interface/AddOns`, and the zip moves to `installed/`. The first run finds your AddOns folder (or asks for it) and remembers it in `addons-path.txt`. Addon settings in the `WTF` folder are left alone.

After it runs, `/reload` in game picks up updates; newly added addons need a game restart.
