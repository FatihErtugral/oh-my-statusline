#!/usr/bin/env bash
# oh-my-statusline installer — macOS & Linux.
#
#   Local:  ./install.sh                 (from a cloned repo — uses that copy)
#   Remote: sh -c "$(curl -fsSL https://raw.githubusercontent.com/FatihErtugral/oh-my-statusline/master/install.sh)"
#           (clones to ~/.oh-my-statusline, oh-my-zsh style)
#
# What it does: writes the statusLine entry into ~/.claude/settings.json
# (backs the file up first, preserves every other key). Nothing else is touched.
set -euo pipefail

REPO_URL=${OMS_REPO:-https://github.com/FatihErtugral/oh-my-statusline.git}
CLONE_DIR=${OMS_DIR:-$HOME/.oh-my-statusline}
SETTINGS_DIR="$HOME/.claude"
SETTINGS="$SETTINGS_DIR/settings.json"

say() { printf '\033[38;5;76m➜\033[0m  %s\n' "$1"; }
die() { printf '\033[38;5;178m✗\033[0m  %s\n' "$1" >&2; exit 1; }

# --- Preconditions -----------------------------------------------------------
case "$(uname -s)" in
  Darwin | Linux) ;;
  *) die "Unsupported OS: $(uname -s) — oh-my-statusline supports macOS & Linux only." ;;
esac

command -v jq > /dev/null 2>&1 || die "jq is required. Install it first: brew install jq (macOS) / sudo apt install jq / sudo pacman -S jq"

# --- Locate or fetch the script ----------------------------------------------
# Local mode: running from a cloned repo (BASH_SOURCE resolves to a real file
# next to scripts/statusline.sh). Remote mode (curl pipe): clone the repo.
src=${BASH_SOURCE[0]:-$0}
if [ -f "$src" ] && [ -f "$(cd "$(dirname "$src")" && pwd)/scripts/statusline.sh" ]; then
  ROOT=$(cd "$(dirname "$src")" && pwd)
  say "Installing from local copy: $ROOT"
else
  command -v git > /dev/null 2>&1 || die "git is required for remote install."
  if [ -d "$CLONE_DIR/.git" ]; then
    say "Updating existing clone: $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only || die "git pull failed — resolve manually in $CLONE_DIR"
  else
    say "Cloning to $CLONE_DIR"
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" || die "git clone failed."
  fi
  ROOT=$CLONE_DIR
fi

SCRIPT="$ROOT/scripts/statusline.sh"
[ -f "$SCRIPT" ] || die "statusline.sh not found at $SCRIPT"
chmod +x "$SCRIPT"

# --- Smoke-test the script before touching settings ---------------------------
out=$(echo '{"model":{"display_name":"test"}}' | bash "$SCRIPT") || die "statusline.sh failed its smoke test."
case "$out" in *test*) ;; *) die "statusline.sh produced unexpected output." ;; esac

# --- Write settings.json (merge, backup, preserve) -----------------------------
mkdir -p "$SETTINGS_DIR"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON — fix it manually first (nothing was changed)."

old=$(jq -r '.statusLine.command // empty' "$SETTINGS")
if [ -n "$old" ] && [ "$old" != "bash \"$SCRIPT\"" ]; then
  say "Replacing existing statusLine: $old"
fi

cp "$SETTINGS" "$SETTINGS.bak"
tmp=$(mktemp)
jq --arg cmd "bash \"$SCRIPT\"" \
  '.statusLine = {type: "command", command: $cmd}' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

say "statusLine written to $SETTINGS (backup: settings.json.bak)"
say "Done — takes effect on the next status line render. Sample:"
printf '   '
echo '{"model":{"display_name":"Fable 5"},"effort":{"level":"high"},"workspace":{"current_dir":"'"$ROOT"'"},"context_window":{"used_percentage":33}}' | bash "$SCRIPT"
printf '\n'
