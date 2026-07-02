#!/usr/bin/env bash
# omz-statusline — oh-my-zsh (robbyrussell) flavored Claude Code status line.
#
#   ➜  dir git:(branch) ✗ │ Model │ effort │ ctx ▰▰▱▱▱▱ 33% │ 5h ▰▰▰▱▱▱ 45% (2h 3m) │ 7d ▰▰▱▱▱▱ 25% (5d 14h)
#
# Segments: robbyrussell dir+git · model · reasoning effort · then PROGRESS
# BARS for context-window fill and Claude plan rate limits (5-hour session +
# weekly — same data as /usage, read from the statusline stdin JSON
# `rate_limits` field; nothing external is called).
#
# Portability: macOS (bash 3.2) + Linux. No mapfile, no EPOCHSECONDS
# dependency, no GNU-only flags. Requires jq (degrades to a dim hint if
# missing).
#
# Robustness rules (terminal artifacts happened before — keep these):
#   - newline-delimited jq extraction (values like "Fable 5" contain spaces;
#     NEVER use exotic join separators — a control char in output corrupts
#     the terminal and causes black-blotch redraw artifacts)
#   - every numeric is validated digits-only before printing; garbage is
#     dropped, never rendered
#   - no emoji-width glyphs — only narrow-width chars
#   - stderr silenced; output is one line, always ends with SGR reset

exec 2>/dev/null

input=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  printf '\033[38;5;244momz-statusline: jq is required (brew install jq / apt install jq)\033[0m'
  exit 0
fi

# Newline-delimited extraction — portable replacement for mapfile (macOS
# ships bash 3.2). Values like "Fable 5" contain spaces; never word-split.
i=0
while IFS= read -r line; do
  F[i]=$line
  i=$((i + 1))
done < <(echo "$input" | jq -r '
  (.model.display_name // "?"),
  (.effort.level // "-"),
  (.workspace.current_dir // .cwd // "-"),
  (.context_window.used_percentage // "-"),
  (.rate_limits.five_hour.used_percentage // "-"),
  (.rate_limits.five_hour.resets_at // "-"),
  (.rate_limits.seven_day.used_percentage // "-"),
  (.rate_limits.seven_day.resets_at // "-")')
model=${F[0]:-?} effort=${F[1]:--} cwd=${F[2]:--} used=${F[3]:--}
p5=${F[4]:--} r5=${F[5]:--} p7=${F[6]:--} r7=${F[7]:--}

now=${EPOCHSECONDS:-$(date +%s)}

# --- Daily auto-update (oh-my-zsh style) --------------------------------------
# If this install is a git clone with a remote, fast-forward pull in the
# background at most once every 24h. Stamp file holds the last-check epoch
# (content-based — portable across GNU/BSD stat). Never blocks the render;
# failures are silent (ff-only never rewrites local work).
self=${BASH_SOURCE[0]:-$0}
ROOT=$(cd "$(dirname "$self")/.." 2>/dev/null && pwd) || ROOT=''
if [ -n "$ROOT" ] && [ -d "$ROOT/.git" ] && [ -n "$(git -C "$ROOT" config remote.origin.url 2>/dev/null)" ]; then
  stamp="$ROOT/.update-stamp"
  last=$(cat "$stamp" 2>/dev/null)
  case "$last" in '' | *[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -ge 86400 ]; then
    echo "$now" > "$stamp"
    (git -C "$ROOT" pull --ff-only > /dev/null 2>&1 &)
  fi
fi

# Digits-only check; strips a decimal part ("23.5" -> "23"), clamps to 100.
as_pct() { # $1=value -> echoes 0-100 int, or nothing if not numeric
  local v=${1%%.*}
  case "$v" in '' | *[!0-9]*) return 1 ;; esac
  [ "$v" -gt 100 ] && v=100
  echo "$v"
}

# Digits-only epoch check (no clamp).
as_int() { # $1=value -> echoes int, or nothing if not numeric
  local v=${1%%.*}
  case "$v" in '' | *[!0-9]*) return 1 ;; esac
  echo "$v"
}

# Muted color by fill level (green -> gold -> orange, NEVER red).
level_color() { # $1=pct
  if   [ "$1" -ge 80 ]; then echo 172   # soft orange
  elif [ "$1" -ge 50 ]; then echo 178   # gold
  else echo 76                          # green
  fi
}

# "2h 15m" / "3d 12h" style countdown until an epoch.
time_left() { # $1=resets_at epoch (validated)
  local s=$(($1 - now))
  [ "$s" -le 0 ] && { echo "now"; return; }
  local d=$((s / 86400)) h=$((s % 86400 / 3600)) m=$((s % 3600 / 60))
  if   [ "$d" -gt 0 ]; then echo "${d}d ${h}h"
  elif [ "$h" -gt 0 ]; then echo "${h}h ${m}m"
  else echo "${m}m"
  fi
}

DIM=238   # empty bar cells
LBL=244   # labels / percentages
BARW=6    # bar width in cells

# Emit one bar segment: label, pct(0-100 validated), fill-color, right-label.
bar_segment() {
  local label=$1 pct=$2 col=$3 right=$4
  [ "$pct" -gt 100 ] && pct=100
  local fill=$(((pct * BARW + 50) / 100))
  [ "$fill" -gt "$BARW" ] && fill=$BARW
  local f='' e='' i
  for ((i = 0; i < fill; i++)); do f+='▰'; done
  for ((i = fill; i < BARW; i++)); do e+='▱'; done
  printf '\033[38;5;%sm%s \033[38;5;%sm%s\033[38;5;%sm%s \033[38;5;%sm%s\033[0m' \
    "$LBL" "$label" "$col" "$f" "$DIM" "$e" "$LBL" "${right:-${pct}%}"
}

SEP=$'\033[38;5;238m │ \033[0m'
out=''

# Append a segment, prefixing SEP unless it's the first one.
add_seg() {
  [ -n "$out" ] && out+="$SEP"
  out+="$1"
}

# 1) Dir + git in oh-my-zsh robbyrussell format: ➜  dir git:(branch) ✗
# arrow=green, dir=cyan, git:()=blue, branch=soft red (167, not harsh), ✗=gold.
if [ "$cwd" != "-" ] && [ -n "$cwd" ]; then
  if [ "$cwd" = "$HOME" ]; then
    dname='~'
  else
    dname=${cwd##*/}
  fi
  seg=$(printf '\033[1;38;5;76m➜\033[0m  \033[38;5;44m%s\033[0m' "$dname")
  if git --no-optional-locks -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      seg+=$(printf ' \033[38;5;33mgit:(\033[38;5;167m%s\033[38;5;33m)\033[0m' "$branch")
      if [ -n "$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null)" ]; then
        seg+=$(printf ' \033[38;5;178m✗\033[0m')
      fi
    fi
  fi
  add_seg "$seg"
fi

# 2) Model (soft blue-gray).
add_seg "$(printf '\033[38;5;109m%s\033[0m' "$model")"

# 3) Effort (muted plain text, lowercase — no emoji glyphs).
if [ "$effort" != "-" ] && [ -n "$effort" ]; then
  case "$effort" in
    low) ecol=71 ;;
    medium) ecol=109 ;;
    high) ecol=178 ;;
    xhigh) ecol=172 ;;
    max) ecol=133 ;;
    *) ecol=244 ;;
  esac
  add_seg "$(printf '\033[38;5;%sm%s\033[0m' "$ecol" "$effort")"
fi

# 4) Context window bar.
if ci=$(as_pct "$used"); then
  add_seg "$(bar_segment 'ctx' "$ci" "$(level_color "$ci")")"
fi

# 5) Claude plan limits (same data as /usage): 5-hour session + weekly.
if p5i=$(as_pct "$p5"); then
  right5="${p5i}%"
  r5i=$(as_int "$r5") && right5="${p5i}% ($(time_left "$r5i"))"
  add_seg "$(bar_segment '5h' "$p5i" "$(level_color "$p5i")" "$right5")"
fi
if p7i=$(as_pct "$p7"); then
  right7="${p7i}%"
  r7i=$(as_int "$r7") && right7="${p7i}% ($(time_left "$r7i"))"
  add_seg "$(bar_segment '7d' "$p7i" "$(level_color "$p7i")" "$right7")"
fi

printf '%s\033[0m' "$out"
