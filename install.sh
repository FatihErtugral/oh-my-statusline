#!/usr/bin/env bash
# oh-my-statusline installer & updater — macOS & Linux.
#
#   Local:  ./install.sh                 (from a cloned repo — uses that copy)
#   Remote: sh -c "$(curl -fsSL https://raw.githubusercontent.com/FatihErtugral/oh-my-statusline/master/install.sh)"
#           (clones to ~/.oh-my-statusline, oh-my-zsh style)
#
# Re-running it is the update path: the clone is brought to origin's tip first
# (see scripts/update.sh), then the statusLine entry is written into
# ~/.claude/settings.json (the file is backed up first; every other key is
# preserved). Nothing else is touched.
#
#   --force   reset even a dev checkout onto origin (managed clones always sync)
set -euo pipefail

REPO_URL=${OMS_REPO:-https://github.com/FatihErtugral/oh-my-statusline.git}
CLONE_DIR=${OMS_DIR:-$HOME/.oh-my-statusline}
SETTINGS_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
SETTINGS="$SETTINGS_DIR/settings.json"

FORCE=0
NO_UPDATE=${OMS_NO_UPDATE:-0}
for a in "$@"; do
  case $a in
    --force) FORCE=1 ;;
    --no-update) NO_UPDATE=1 ;;
    -h | --help)
      sed -n '2,17p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

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
    say "Existing install found: $CLONE_DIR"
  else
    say "Cloning to $CLONE_DIR"
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR" || die "git clone failed."
  fi
  ROOT=$CLONE_DIR
fi

# --- Update the clone (this is what makes re-running the installer an update) --
# update.sh is conflict-proof: a managed clone (~/.oh-my-statusline) always ends
# on origin's tip with local changes stashed as a patch; a dev checkout is only
# fast-forwarded, and left alone when dirty unless --force.
if [ "$NO_UPDATE" != 1 ] && git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  if [ -f "$ROOT/scripts/update.sh" ]; then
    if [ "$FORCE" = 1 ]; then
      bash "$ROOT/scripts/update.sh" --force || true
    else
      bash "$ROOT/scripts/update.sh" || true
    fi
  else
    # Pre-0.2 clone: no updater on disk yet — bootstrap one fetch/reset by hand,
    # which also brings scripts/update.sh in for every run after this one.
    say "Bootstrapping updater into the existing clone"
    b=$(git -C "$ROOT" symbolic-ref --short -q HEAD 2> /dev/null || echo master)
    if git -C "$ROOT" fetch --quiet origin "$b" 2> /dev/null \
      && git -C "$ROOT" reset --hard --quiet FETCH_HEAD 2> /dev/null; then
      say "Clone reset onto origin/$b"
    else
      say "Could not refresh $ROOT automatically — installing from it as-is."
      say "If it stays stale: rm -rf \"$ROOT\" and re-run this installer."
    fi
  fi
fi

SCRIPT="$ROOT/scripts/statusline.sh"
[ -f "$SCRIPT" ] || die "statusline.sh not found at $SCRIPT"
# Only chmod when needed — an unnecessary mode change dirties the clone and
# used to be the very thing that broke the next update.
[ -x "$SCRIPT" ] || chmod +x "$SCRIPT"
[ ! -f "$ROOT/scripts/update.sh" ] || [ -x "$ROOT/scripts/update.sh" ] || chmod +x "$ROOT/scripts/update.sh"

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
