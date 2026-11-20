#!/usr/bin/env bash
# install-addons.sh — install or update WoW addons from zip files (Linux / Bazzite).
#
# Drop addon .zip files next to this script and run it. Each zip is unzipped,
# every addon folder inside replaces the one in your AddOns folder, and the zip
# is moved to ./installed. Addon settings (the WTF folder) are not touched.
#
# Optional: set your WoW Forever AddOns folder here, e.g.
# ADDONS_PATH="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
# Leave empty to auto-detect (the choice is remembered in addons-path.txt).
ADDONS_PATH=""

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_FILE="$HERE/addons-path.txt"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

# Unzip with whatever is available (unzip, bsdtar, or python3).
extract() {
  if command -v unzip >/dev/null; then unzip -q -o "$1" -d "$2"
  elif command -v bsdtar >/dev/null; then bsdtar -xf "$1" -C "$2"
  elif command -v python3 >/dev/null; then python3 -I -m zipfile -e "$1" "$2"
  else red "Need unzip, bsdtar or python3 to extract zips."; exit 1
  fi
}

# Look in the usual Wine/Proton prefixes (Lutris, Steam, Bottles, Heroic, Faugus).
find_addons_path() {
  local roots=(
    "$HOME/Games" "$HOME/.wine" "$HOME/.local/share/lutris"
    "$HOME/.local/share/Steam/steamapps/compatdata"
    "$HOME/.steam/steam/steamapps/compatdata"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata"
    "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"
    "$HOME/.var/app/net.lutris.Lutris/data/lutris"
    "$HOME/.local/share/bottles/bottles" "$HOME/Faugus"
  )
  local found=() r p
  for r in "${roots[@]}"; do
    [[ -d "$r" ]] || continue
    while IFS= read -r -d '' p; do found+=("$p"); done < <(
      find "$r" -maxdepth 9 -type d -path '*/World of Warcraft/_*_/Interface/AddOns' -print0 2>/dev/null)
  done
  if (( ${#found[@]} == 1 )); then printf '%s' "${found[0]}"; return; fi
  if (( ${#found[@]} > 1 )); then
    echo "Found more than one AddOns folder:" >&2
    local i; for i in "${!found[@]}"; do echo "  [$((i + 1))] ${found[$i]}" >&2; done
    read -rp "Which one is WoW Forever? Enter the number: " n
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#found[@]} )); then
      printf '%s' "${found[$((n - 1))]}"; return
    fi
  fi
  read -rp "Paste the full path to your WoW Forever Interface/AddOns folder: " p
  printf '%s' "$p"
}

if [[ -z "$ADDONS_PATH" && -f "$PATH_FILE" ]]; then ADDONS_PATH="$(<"$PATH_FILE")"; fi
if [[ -z "$ADDONS_PATH" || ! -d "$ADDONS_PATH" ]]; then
  ADDONS_PATH="$(find_addons_path)"
  if [[ -z "$ADDONS_PATH" || ! -d "$ADDONS_PATH" ]]; then red "AddOns folder not found: '$ADDONS_PATH'"; exit 1; fi
  printf '%s\n' "$ADDONS_PATH" > "$PATH_FILE"
fi
echo "Installing to: $ADDONS_PATH"
echo

shopt -s nullglob nocaseglob
zips=("$HERE"/*.zip)
shopt -u nocaseglob
if (( ${#zips[@]} == 0 )); then echo "No .zip files found next to this script."; exit 0; fi

mkdir -p "$HERE/installed"
failed=0

for zip in "${zips[@]}"; do
  tmp="$(mktemp -d)"
  if ! extract "$zip" "$tmp" 2>/dev/null; then
    red "  $(basename "$zip"): could not unzip"; failed=$((failed + 1)); rm -rf "$tmp"; continue
  fi

  # An addon folder holds a .toc named after it (Name.toc or Name_Variant.toc).
  dirs=()
  while IFS= read -r -d '' toc; do
    d="$(dirname "$toc")"; dn="$(basename "$d")"; tn="$(basename "$toc" .toc)"
    if [[ "$tn" == "$dn" || "$tn" == "$dn"_* ]]; then dirs+=("$d"); fi
  done < <(find "$tmp" -type f -iname '*.toc' -print0)

  # Keep only top-level addon folders (skip libraries bundled inside an addon).
  addons=()
  if (( ${#dirs[@]} )); then
    mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | sort -u)
    for d in "${dirs[@]}"; do
      nested=0
      for o in "${dirs[@]}"; do [[ "$d" != "$o" && "$d" == "$o"/* ]] && nested=1 && break; done
      (( nested )) || addons+=("$d")
    done
  fi

  if (( ${#addons[@]} == 0 )); then
    red "  $(basename "$zip"): no addon folder (with a matching .toc) inside"
    failed=$((failed + 1)); rm -rf "$tmp"; continue
  fi

  for src in "${addons[@]}"; do
    name="$(basename "$src")"
    [[ -n "$name" && "$name" != Blizzard_* ]] || continue
    dest="$ADDONS_PATH/$name"
    verb="Installed"
    if [[ -e "$dest" ]]; then rm -rf -- "$dest"; verb="Updated"; fi
    cp -r -- "$src" "$dest"
    green "  $verb $name"
  done
  mv -f -- "$zip" "$HERE/installed/"
  rm -rf "$tmp"
done

echo
echo "Done. Type /reload in game for updates; restart the game for newly added addons."
(( failed )) && echo "$failed zip(s) failed and were left in place."
exit 0
