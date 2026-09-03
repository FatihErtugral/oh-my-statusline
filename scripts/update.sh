#!/usr/bin/env bash
# oh-my-statusline updater — brings this clone up to date with origin.
#
#   scripts/update.sh            # fast-forward; force-syncs a managed clone
#   scripts/update.sh --force    # discard local changes in ANY clone
#   scripts/update.sh --quiet    # no output (used by the daily background check)
#
# Why this exists: `git pull --ff-only` gives up the moment the tree is dirty or
# the branch diverged, which left installs permanently stale — the old
# installer's `chmod +x` alone was enough to dirty the tree. Here:
#
#   managed clone  (~/.oh-my-statusline, or $OMS_DIR)  -> always ends on origin's
#                  tip; local changes are saved as a patch under .oms-backup/
#                  first, never silently thrown away
#   other clone    (a dev checkout, a plugin cache)    -> fast-forward only, and
#                  skipped entirely when dirty or diverged unless --force
#
# Portability: macOS (bash 3.2, BSD git) + Linux. No GNU-only flags, works on
# shallow (--depth 1) clones.
set -u

quiet=0
force=${OMS_FORCE:-0}
case $force in '' | *[!0-9]*) force=0 ;; esac
for a in "$@"; do
  case $a in
    --quiet) quiet=1 ;;
    --force) force=1 ;;
  esac
done

say() { [ "$quiet" -eq 1 ] || printf '\033[38;5;76m➜\033[0m  %s\n' "$1"; }
warn() { [ "$quiet" -eq 1 ] || printf '\033[38;5;178m!\033[0m  %s\n' "$1" >&2; }

self=${BASH_SOURCE[0]:-$0}
ROOT=$(cd "$(dirname "$self")/.." 2>/dev/null && pwd) || exit 0

# --- Is this an updatable clone at all? --------------------------------------
command -v git > /dev/null 2>&1 || { warn "git not found — skipping update."; exit 0; }
git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1 || exit 0
[ -n "$(git -C "$ROOT" config remote.origin.url 2>/dev/null)" ] || exit 0

# Plugin installs are Claude Code's to update (/plugin update) — hands off.
case $ROOT in
  */plugins/cache/* | */plugins/marketplaces/* | */.claude/plugins/*)
    say "plugin install — update it with /plugin update"
    exit 0
    ;;
esac

CLONE_DIR=${OMS_DIR:-$HOME/.oh-my-statusline}
canon() { (cd "$1" 2> /dev/null && pwd -P); }
managed=0
[ -n "$(canon "$ROOT")" ] && [ "$(canon "$ROOT")" = "$(canon "$CLONE_DIR")" ] && managed=1
[ "$managed" -eq 1 ] && force=1

# --- Which branch tracks origin? ---------------------------------------------
branch=$(git -C "$ROOT" symbolic-ref --short -q HEAD 2> /dev/null) || branch=''
if [ -z "$branch" ]; then # detached HEAD — fall back to origin's default branch
  branch=$(git -C "$ROOT" symbolic-ref --short -q refs/remotes/origin/HEAD 2> /dev/null)
  branch=${branch#origin/}
  [ -n "$branch" ] || branch=master
fi

# --- Fetch (keeps a shallow clone shallow) ------------------------------------
gitdir=$(git -C "$ROOT" rev-parse --git-dir 2> /dev/null)
case $gitdir in /*) ;; *) gitdir="$ROOT/$gitdir" ;; esac
if [ -f "$gitdir/shallow" ]; then
  git -C "$ROOT" fetch --quiet --depth 1 origin "$branch" 2> /dev/null \
    || { warn "fetch failed — network or credentials; install continues with the current copy."; exit 0; }
else
  git -C "$ROOT" fetch --quiet origin "$branch" 2> /dev/null \
    || { warn "fetch failed — network or credentials; install continues with the current copy."; exit 0; }
fi

target=$(git -C "$ROOT" rev-parse --verify -q FETCH_HEAD) || exit 0
head=$(git -C "$ROOT" rev-parse --verify -q HEAD) || exit 0

dirty=0
[ -n "$(git --no-optional-locks -C "$ROOT" status --porcelain 2> /dev/null)" ] && dirty=1

if [ "$head" = "$target" ] && [ "$dirty" -eq 0 ]; then
  say "Already up to date ($(git -C "$ROOT" rev-parse --short HEAD))."
  exit 0
fi

# --- Fast-forward when the tree allows it ------------------------------------
if [ "$dirty" -eq 0 ] && git -C "$ROOT" merge-base --is-ancestor "$head" "$target" 2> /dev/null; then
  if git -C "$ROOT" merge --ff-only --quiet "$target" 2> /dev/null; then
    say "Updated to $(git -C "$ROOT" log -1 --format='%h %s' 2> /dev/null)"
    exit 0
  fi
fi

# --- Otherwise: force-sync (managed clone) or step aside ----------------------
if [ "$force" -ne 1 ]; then
  if [ "$dirty" -eq 1 ]; then
    warn "local changes in $ROOT — update skipped (commit them, or re-run with --force)."
  else
    warn "$ROOT has diverged from origin — update skipped (re-run with --force to reset onto origin)."
  fi
  exit 0
fi

if [ "$dirty" -eq 1 ]; then
  mkdir -p "$ROOT/.oms-backup"
  patch="$ROOT/.oms-backup/local-$(date +%Y%m%d-%H%M%S).patch"
  if git -C "$ROOT" diff HEAD > "$patch" 2> /dev/null && [ -s "$patch" ]; then
    say "Local changes saved to $patch"
  else
    rm -f "$patch"
  fi
fi

if ! git -C "$ROOT" reset --hard --quiet "$target" 2> /dev/null; then
  # Untracked files colliding with new upstream files — clear them and retry
  # once. Ignored files (.update-stamp, .oms-backup/) survive `clean -fd`.
  git -C "$ROOT" clean -qfd -e .oms-backup 2> /dev/null
  git -C "$ROOT" reset --hard --quiet "$target" 2> /dev/null \
    || { warn "reset failed in $ROOT — remove the directory and re-run the installer."; exit 1; }
fi

say "Updated to $(git -C "$ROOT" log -1 --format='%h %s' 2> /dev/null)"
