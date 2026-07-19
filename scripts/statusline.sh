#!/usr/bin/env bash
# omz-statusline — oh-my-zsh (robbyrussell) flavored Claude Code status line.
#
#   ➜  dir git:(branch) ✗ │ Model │ effort │ ctx ▰▰▱▱▱ 33% │ 5h ▰▰▰▱▱ 45% (2h 3m) │ 7d ▰▱▱▱▱ 25% (5d 14h)
#
# Segments: robbyrussell dir+git · model · reasoning effort · then PROGRESS
# BARS for context-window fill and Claude plan rate limits (5-hour session +
# weekly — same data as /usage, read from the statusline stdin JSON
# `rate_limits` field; nothing external is called).
#
# Responsive layout (flex-wrap): terminal width comes from $COLUMNS (Claude
# Code sets it before running the script; /dev/tty is the fallback). When
# everything fits on one line, it renders as one line. When it doesn't, the
# bars wrap onto a second row; if that row still overflows the bars narrow,
# then drop their glyphs entirely — the reset countdowns are always kept and
# only vanish as the very last resort on extremely narrow terminals.
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
#   - stderr silenced; every output line ends with SGR reset
#   - visible widths are tracked as plain-character counts while building
#     (never by re-measuring ANSI-colored strings)

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
BARW=5    # bar width in cells (compact tier drops to 4)

# Terminal width: Claude Code exports COLUMNS before running the script
# (v2.1.153+); /dev/tty is the fallback for older versions / manual runs.
cols=${COLUMNS:-}
case "$cols" in
  '' | *[!0-9]*)
    set -- $(stty size < /dev/tty)
    cols=${2:-}
    case "$cols" in '' | *[!0-9]*) cols=80 ;; esac
    ;;
esac

SEP=$'\033[38;5;238m │ \033[0m'
SEPW=3    # plain-character width of SEP

# --- Info row: dir+git · model · effort ---------------------------------------
info='' info_w=0
add_info() { # $1=colored segment  $2=its plain-character width
  if [ -n "$info" ]; then
    info+="$SEP"
    info_w=$((info_w + SEPW))
  fi
  info+="$1"
  info_w=$((info_w + $2))
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
  segw=$((3 + ${#dname}))
  if git --no-optional-locks -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      seg+=$(printf ' \033[38;5;33mgit:(\033[38;5;167m%s\033[38;5;33m)\033[0m' "$branch")
      segw=$((segw + 7 + ${#branch}))
      if [ -n "$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null)" ]; then
        seg+=$(printf ' \033[38;5;178m✗\033[0m')
        segw=$((segw + 2))
      fi
    fi
  fi
  add_info "$seg" "$segw"
fi

# 2) Model (soft blue-gray).
add_info "$(printf '\033[38;5;109m%s\033[0m' "$model")" "${#model}"

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
  add_info "$(printf '\033[38;5;%sm%s\033[0m' "$ecol" "$effort")" "${#effort}"
fi

# --- Bars: collected as data first, rendered at whatever width the layout
# --- tier allows (full -> compact -> text-only).
nbars=0
add_bar() { # $1=label $2=pct(validated) $3=countdown text ('' if unknown)
  BL[nbars]=$1
  BP[nbars]=$2
  BT[nbars]=$3
  nbars=$((nbars + 1))
}

if ci=$(as_pct "$used"); then
  add_bar ctx "$ci" ''
fi
if p5i=$(as_pct "$p5"); then
  t=''
  r5i=$(as_int "$r5") && t=$(time_left "$r5i")
  add_bar 5h "$p5i" "$t"
fi
if p7i=$(as_pct "$p7"); then
  t=''
  r7i=$(as_int "$r7") && t=$(time_left "$r7i")
  add_bar 7d "$p7i" "$t"
fi

build_bars() { # $1=bar cells (0 = text only)  $2=full|bare -> sets BARS, BARS_W
  local barw=$1 mode=$2 i pct col right fill f e j
  BARS='' BARS_W=0
  for ((i = 0; i < nbars; i++)); do
    pct=${BP[i]}
    col=$(level_color "$pct")
    right="${pct}%"
    if [ "$mode" = full ] && [ -n "${BT[i]}" ]; then
      right="${pct}% (${BT[i]})"
    fi
    if [ -n "$BARS" ]; then
      BARS+="$SEP"
      BARS_W=$((BARS_W + SEPW))
    fi
    if [ "$barw" -gt 0 ]; then
      fill=$(((pct * barw + 50) / 100))
      [ "$fill" -gt "$barw" ] && fill=$barw
      f='' e=''
      for ((j = 0; j < fill; j++)); do f+='▰'; done
      for ((j = fill; j < barw; j++)); do e+='▱'; done
      BARS+=$(printf '\033[38;5;%sm%s \033[38;5;%sm%s\033[38;5;%sm%s \033[38;5;%sm%s\033[0m' \
        "$LBL" "${BL[i]}" "$col" "$f" "$DIM" "$e" "$LBL" "$right")
      BARS_W=$((BARS_W + ${#BL[i]} + 1 + barw + 1 + ${#right}))
    else
      BARS+=$(printf '\033[38;5;%sm%s \033[38;5;%sm%s\033[0m' \
        "$LBL" "${BL[i]}" "$col" "$right")
      BARS_W=$((BARS_W + ${#BL[i]} + 1 + ${#right}))
    fi
  done
}

# --- Layout (flex-wrap) --------------------------------------------------------
# One line when it fits; otherwise the bars wrap onto a second row and
# compact in steps until that row fits. Countdowns survive every step but
# the last (bare) one.
build_bars "$BARW" full

if [ "$nbars" -eq 0 ]; then
  printf '%s\033[0m' "$info"
elif [ $((info_w + SEPW + BARS_W)) -le "$cols" ]; then
  printf '%s%s%s\033[0m' "$info" "$SEP" "$BARS"
else
  [ "$BARS_W" -gt "$cols" ] && build_bars 4 full
  [ "$BARS_W" -gt "$cols" ] && build_bars 0 full
  [ "$BARS_W" -gt "$cols" ] && build_bars 0 bare
  printf '%s\033[0m\n%s\033[0m' "$info" "$BARS"
fi
