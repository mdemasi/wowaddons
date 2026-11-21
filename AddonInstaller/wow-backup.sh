#!/usr/bin/env bash
# wow-backup.sh — back up / restore WoW addon data and settings to a private git repo.
#
#   ./wow-backup.sh backup          copy addon data + settings from WTF, commit, push
#   ./wow-backup.sh list            show recent backups
#   ./wow-backup.sh restore [id]    copy the latest backup (or a listed id) back into WTF
#
# Backed up from WTF: Config.wtf, and for the account and each character:
# SavedVariables (addon data), macros, key bindings, enabled-addon lists,
# window layout, chat setup and synced settings.
#
# Optional settings (otherwise asked once and remembered in .txt files here):
BACKUP_REMOTE=""   # e.g. git@github.com:YOU/wowaddons-backup.git  (make the repo PRIVATE)
ADDONS_PATH=""     # same as install-addons.sh; read from addons-path.txt if empty

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HERE/backup-repo"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
die()   { red "$*"; exit 1; }

command -v git >/dev/null || die "git is required."

# --- locate WTF -------------------------------------------------------------
if [[ -z "$ADDONS_PATH" && -f "$HERE/addons-path.txt" ]]; then ADDONS_PATH="$(<"$HERE/addons-path.txt")"; fi
if [[ -z "$ADDONS_PATH" || ! -d "$ADDONS_PATH" ]]; then
  read -rp "Path to your WoW Forever Interface/AddOns folder: " ADDONS_PATH
  [[ -d "$ADDONS_PATH" ]] || die "Not a folder: $ADDONS_PATH"
  printf '%s\n' "$ADDONS_PATH" > "$HERE/addons-path.txt"
fi
WTF="$(cd "$ADDONS_PATH/../.." && pwd)/WTF"

# --- backup repo --------------------------------------------------------------
if [[ -z "$BACKUP_REMOTE" && -f "$HERE/backup-remote.txt" ]]; then BACKUP_REMOTE="$(<"$HERE/backup-remote.txt")"; fi
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

case "${1:-}" in
  backup)  do_backup ;;
  list)    do_list ;;
  restore) do_restore "${2:-}" ;;
  *) echo "Usage: $0 backup | list | restore [id]"; exit 1 ;;
esac
