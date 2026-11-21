#!/usr/bin/env bash
# install-addons.sh — install/update WoW addons from zips, and back up / restore
# addon data and settings to a private git repo (Linux / Bazzite).
#
#   ./install-addons.sh               back up addon data, then install every .zip next to this script
#   ./install-addons.sh --no-backup   install without backing up first
#   ./install-addons.sh backup        back up addon data and settings, commit, push
#   ./install-addons.sh list          show recent backups
#   ./install-addons.sh restore [id]  put the latest backup (or a listed id) back into WTF
#
# Installing: each zip is unzipped, every addon folder inside replaces the one in
# your AddOns folder, and the zip is moved to ./installed.
#
# Backups: Config.wtf, and for the account and each character: SavedVariables
# (addon data), macros, key bindings, enabled-addon lists, window layout, chat
# setup and synced settings. Backups only run once a backup repo is set up
# (run "./install-addons.sh backup" once to set it up).
#
# Optional settings (otherwise found/asked once and remembered in .txt files here):
ADDONS_PATH=""     # e.g. "$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
BACKUP_REMOTE=""   # e.g. git@github.com:YOU/wowaddons-backup.git  (make the repo PRIVATE)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH_FILE="$HERE/addons-path.txt"
REPO="$HERE/backup-repo"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
die()   { red "$*"; exit 1; }

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

resolve_addons_path() {
  if [[ -z "$ADDONS_PATH" && -f "$PATH_FILE" ]]; then ADDONS_PATH="$(<"$PATH_FILE")"; fi
  if [[ -z "$ADDONS_PATH" || ! -d "$ADDONS_PATH" ]]; then
    ADDONS_PATH="$(find_addons_path)"
    if [[ -z "$ADDONS_PATH" || ! -d "$ADDONS_PATH" ]]; then die "AddOns folder not found: '$ADDONS_PATH'"; fi
    printf '%s\n' "$ADDONS_PATH" > "$PATH_FILE"
  fi
  WTF="$(cd "$ADDONS_PATH/../.." && pwd)/WTF"
}

do_install() {
  echo "Installing to: $ADDONS_PATH"
  echo

  shopt -s nullglob nocaseglob
  zips=("$HERE"/*.zip)
  shopt -u nocaseglob
  if (( ${#zips[@]} == 0 )); then echo "No .zip files found next to this script."; return 0; fi

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
  return 0
}

# --- backup repo --------------------------------------------------------------
ensure_repo() {
  if [[ ! -d "$REPO/.git" ]]; then
    if [[ -z "$BACKUP_REMOTE" ]]; then
      read -rp "Private GitHub repo URL for backups (e.g. git@github.com:YOU/wowaddons-backup.git): " BACKUP_REMOTE
      [[ -n "$BACKUP_REMOTE" ]] || die "No repo URL given."
      printf '%s\n' "$BACKUP_REMOTE" > "$HERE/backup-remote.txt"
    fi
    git clone -q "$BACKUP_REMOTE" "$REPO" 2>/dev/null || {
      # empty new repo: start one locally pointing at the remote
      mkdir -p "$REPO" && git -C "$REPO" init -q -b main && git -C "$REPO" remote add origin "$BACKUP_REMOTE"
    }
  fi
  git -C "$REPO" config user.name >/dev/null || git -C "$REPO" config user.name "wow-backup"
  git -C "$REPO" config user.email >/dev/null || git -C "$REPO" config user.email "wow-backup@localhost"
}

game_running() { pgrep -fi 'wow.*\.exe' >/dev/null 2>&1; }

# Files worth keeping, relative to WTF.
collect() {
  ( cd "$WTF"
    [[ -f Config.wtf ]] && echo Config.wtf
    find Account -type f \( \
        -path '*/SavedVariables/*.lua' -o -name 'macros-cache.txt' -o -name 'bindings-cache.wtf' \
        -o -name 'config-cache.wtf' -o -name 'AddOns.txt' -o -name 'layout-local.txt' -o -name 'chat-cache.txt' \
      \) 2>/dev/null )
}

do_backup() {
  [[ -d "$WTF" ]] || die "WTF folder not found at $WTF"
  command -v git >/dev/null || die "git is required for backups."
  ensure_repo
  git -C "$REPO" pull -q --ff-only 2>/dev/null || true
  game_running && echo "Note: WoW is running. It saves addon data on logout or /reload, so the newest changes may be missing."

  rm -rf "$REPO/WTF"; mkdir -p "$REPO/WTF"
  local n=0 f
  while IFS= read -r f; do
    mkdir -p "$REPO/WTF/$(dirname "$f")"
    cp -p -- "$WTF/$f" "$REPO/WTF/$f"
    n=$((n + 1))
  done < <(collect)
  [[ -f "$REPO/README.md" ]] || printf '# WoW addon data backup\n\nMade by wow-backup.sh. Keep this repo private.\n' > "$REPO/README.md"

  git -C "$REPO" add -A
  if git -C "$REPO" diff --cached --quiet; then green "No changes since the last backup ($n files)."; return; fi
  git -C "$REPO" commit -q -m "Backup $(date '+%Y-%m-%d %H:%M') from $(hostname)"
  if git -C "$REPO" push -q -u origin HEAD 2>/dev/null; then
    green "Backed up $n files and pushed."
  else
    red "Backed up $n files locally, but the push failed. Check the repo URL and your GitHub login, then run backup again."
  fi
}

do_list() {
  ensure_repo
  git -C "$REPO" fetch -q 2>/dev/null || true
  git -C "$REPO" log --format='%h  %s' -n 20 "$(git -C "$REPO" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo HEAD)" 2>/dev/null \
    || echo "No backups yet."
}

do_restore() {
  local ref="${1:-}"
  ensure_repo
  git -C "$REPO" pull -q --ff-only 2>/dev/null || true
  [[ -n "$ref" ]] || ref=HEAD
  git -C "$REPO" rev-parse -q --verify "$ref^{commit}" >/dev/null || die "Unknown backup: $ref (see ./wow-backup.sh list)"
  game_running && die "Close WoW first; it would overwrite the restored files when you log out."

  local safety="$HERE/wtf-before-restore-$(date '+%Y%m%d-%H%M%S').tar.gz"
  if [[ -d "$WTF" ]]; then
    tar -czf "$safety" -C "$(dirname "$WTF")" WTF
    echo "Saved the current WTF folder to $safety"
  fi
  local tmp; tmp="$(mktemp -d)"
  git -C "$REPO" archive "$ref" WTF | tar -x -C "$tmp"
  mkdir -p "$WTF"
  cp -rp -- "$tmp/WTF/." "$WTF/"
  rm -rf "$tmp"
  green "Restored backup $(git -C "$REPO" log -1 --format='%h (%s)' "$ref")."
}

# --- main ---------------------------------------------------------------------
if [[ -z "$BACKUP_REMOTE" && -f "$HERE/backup-remote.txt" ]]; then BACKUP_REMOTE="$(<"$HERE/backup-remote.txt")"; fi
resolve_addons_path

case "${1:-}" in
  backup)  do_backup ;;
  list)    do_list ;;
  restore) do_restore "${2:-}" ;;
  ""|--no-backup)
    if [[ "${1:-}" != "--no-backup" ]]; then
      if [[ -n "$BACKUP_REMOTE" ]]; then
        echo "Backing up addon data first..."
        do_backup || red "Backup failed; installing anyway."
        echo
      else
        echo "(Tip: run './install-addons.sh backup' once to set up automatic backups of your addon data.)"
        echo
      fi
    fi
    do_install ;;
  *) echo "Usage: $0 [--no-backup] | backup | list | restore [id]"; exit 1 ;;
esac
