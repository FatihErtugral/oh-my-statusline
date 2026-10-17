#!/usr/bin/env bash
# omz-statusline — oh-my-zsh (robbyrussell) flavored Claude Code status line.
#
#   ➜  dir git:(branch) ✗ │ Model │ effort │ ctx ▃ 33% │ 5h ▄ 45% 2ʰ 3ᵐ │ 7d ▂ 25% 5ᵈ 14ʰ │ ✻ 2/3  ↳ 4 │ you@example.com
#
# Segments: robbyrussell dir+git · model · reasoning effort · then METERS for
# context-window fill and Claude plan rate limits (5-hour session + weekly —
# same data as /usage, read from the statusline stdin JSON `rate_limits` field;
# nothing external is called) · and last, trailing the whole line, the Claude
# sessions open on this machine (with the workflow agents they run) and the
# signed-in Claude account. A meter is a one-cell vertical gauge (OMS_METER:
# pie, or the classic ▰▱ bar). The percentage is its loud part, in the level
# color, with the label dim and the countdown quieter still — its unit letters
# are modifier letters the font draws small.
#
# Responsive layout (flex-wrap): terminal width comes from $COLUMNS (Claude
# Code sets it before running the script; /dev/tty is the fallback). When
# everything fits on one line, it renders as one line. When it doesn't, the
# account shortens to its local part and then drops, the session counts drop,
# the meters wrap onto a second row; if that row still overflows they narrow
# (bar style), then drop their glyphs entirely — the reset countdowns are always
# kept and only vanish as the very last resort on extremely narrow terminals.
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

input=''
IFS= read -r -d '' input # all of stdin, without forking cat

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
  (.rate_limits.seven_day.resets_at // "-"),
  (.session_id // "-")')
model=${F[0]:-?} effort=${F[1]:--} cwd=${F[2]:--} used=${F[3]:--}
p5=${F[4]:--} r5=${F[5]:--} p7=${F[6]:--} r7=${F[7]:--} sid_self=${F[8]:--}

now=${EPOCHSECONDS:-$(date +%s)}

# --- Daily auto-update (oh-my-zsh style) --------------------------------------
# If this install is a git clone with a remote, update in the background at
# most once every 24h. Stamp file holds the last-check epoch (content-based —
# portable across GNU/BSD stat). Never blocks the render; failures are silent.
# scripts/update.sh decides what is safe: a managed clone is force-synced onto
# origin (local changes saved as a patch), a dev checkout is fast-forwarded
# only, and a plugin install is left to /plugin update.
# Every render passes through here, so the stamp is read first and git is
# asked about a remote only once a check is due.
self=${BASH_SOURCE[0]:-$0}
case $self in
  /*/scripts/*) ROOT=${self%/scripts/*} ;;
  *) ROOT=$(cd "$(dirname "$self")/.." 2>/dev/null && pwd) || ROOT='' ;;
esac
if [ -n "$ROOT" ] && [ -d "$ROOT/.git" ]; then
  stamp="$ROOT/.update-stamp"
  last=0
  [ -f "$stamp" ] && read -r last < "$stamp"
  case "$last" in '' | *[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -ge 86400 ] && [ -n "$(git -C "$ROOT" config remote.origin.url 2>/dev/null)" ]; then
    echo "$now" > "$stamp"
    if [ -f "$ROOT/scripts/update.sh" ]; then
      (bash "$ROOT/scripts/update.sh" --quiet > /dev/null 2>&1 &)
    else
      (git -C "$ROOT" pull --ff-only > /dev/null 2>&1 &)
    fi
  fi
fi

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

# --- Live session records -----------------------------------------------------
# The files and the liveness of their processes — built-ins only, so the render
# cache below can use them before anything expensive runs. Parsed further down.
cfgdir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
sdir=$cfgdir/sessions
np=0 SIDS=''
if [ "${OMS_SESSIONS:-on}" != off ]; then
  for rf in "$sdir"/[0-9]*.json; do
    [ -f "$rf" ] || continue
    pid=${rf##*/}
    pid=${pid%.json}
    case $pid in 0* | *[!0-9]*) continue ;; esac # canonical names only
    [ "$pid" -gt 1 ] && kill -0 "$pid" || continue
    rec=''
    IFS= read -r -d '' rec < "$rf"
    SP[np]=$pid
    SF[np]=$rf
    SR[np]=${rec//$'\n'/ } # one line for jq -R; JSON strings never hold a raw newline
    np=$((np + 1))
  done
fi

# --- Render cache ---------------------------------------------------------------
# With refreshInterval set, most runs are timer ticks on which nothing shown has
# changed. The last render is kept per session with the inputs it was drawn
# from, and printed again while they hold: the payload fields shown, the width,
# the minute (the countdowns), the settings, the set of live session processes,
# and the cache strictly newer than every session record, workflow journal, git
# HEAD, reflog and index, and this script — "strictly", because bash 3.2 compares
# whole seconds and a change in the cache's own second must not slip through.
# All of that is shell built-ins; any change falls through to the full render.
# Working-tree edits touch none of the git files, so on idle ticks the dirty
# mark can lag by up to a minute.
cachedir=${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-statusline
cache=''
case $sid_self in
  '' | - | *[!A-Za-z0-9-]*) ;;
  *) cache=$cachedir/render-$sid_self ;;
esac
ckey="1|${F[*]:0:8}|$cols|$((now / 60))|${OMS_ACCOUNT:-}|${OMS_SESSIONS:-}|${OMS_METER:-}|$cfgdir|${SP[*]}"
if [ -n "$cache" ] && [ "$cache" -nt "$self" ]; then
  fresh=1
  for ((i = 0; i < np; i++)); do
    [ "$cache" -nt "${SF[i]}" ] || fresh=0
  done
  ckey_old='' csids='' cout=''
  { IFS= read -r ckey_old; IFS= read -r csids; IFS= read -r -d '' cout; } < "$cache"
  [ "$ckey_old" = "$ckey" ] || fresh=0
  if [ "$fresh" = 1 ]; then
    for sid in $csids; do
      for j in "$cfgdir"/projects/*/"$sid"/subagents/workflows/*/journal.jsonl; do
        [ -e "$j" ] && ! [ "$cache" -nt "$j" ] && fresh=0
      done
    done
    # -e first: bash 3.2's -nt is false, not true, when the other file is missing.
    for g in "$cwd/.git/HEAD" "$cwd/.git/logs/HEAD" "$cwd/.git/index"; do
      [ -e "$g" ] && ! [ "$cache" -nt "$g" ] && fresh=0
    done
    if [ "$fresh" = 1 ]; then
      printf '%s' "$cout"
      exit 0
    fi
  fi
fi

# --- Signed-in Claude account -------------------------------------------------
# Which account this session is authenticated as. The statusline payload does
# not carry it, so it is read from the Claude Code config file
# ($CLAUDE_CONFIG_DIR/.claude.json, else ~/.claude.json) — a local read, no
# network. OMS_ACCOUNT: email (default; full address, shortened to the local
# part when the line is tight) | user (local part only) | off.
acct='' acct_short=''
acct_mode=${OMS_ACCOUNT:-email}
if [ "$acct_mode" != off ]; then
  cfg="$HOME/.claude.json"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -f "$CLAUDE_CONFIG_DIR/.claude.json" ] && cfg="$CLAUDE_CONFIG_DIR/.claude.json"
  [ -f "$cfg" ] && acct=$(jq -r '.oauthAccount.emailAddress // .oauthAccount.displayName // empty' "$cfg" 2>/dev/null)
  # Plain-ASCII identifiers only; anything else is dropped, never rendered.
  case $acct in '' | *[!A-Za-z0-9@._+-]*) acct='' ;; esac
  acct_short=${acct%%@*}
  [ "$acct_mode" = user ] && acct=$acct_short
fi

# --- Open Claude sessions -----------------------------------------------------
# How many Claude Code sessions are open on this machine, what they are doing,
# and how many workflow agents they are running. Claude Code keeps one record
# per running process in
# $CLAUDE_CONFIG_DIR/sessions/<pid>.json (else ~/.claude/sessions) with a live
# `status`: busy | shell | waiting | idle. The format is undocumented, so a
# record only counts while it checks out: its process is still alive, and its
# start time still matches procStart (otherwise the pid was recycled and the
# record is a crash leftover). Spare (pre-warmed, not yet a session) and daemon
# records are not sessions. OMS_SESSIONS=off hides the segment.
#
# procStart is taken the way Claude Code takes it: on Linux /proc/<pid>/stat
# field 22 (a file read, no fork); elsewhere (macOS) `ps -o lstart=` under
# LC_ALL=C TZ=UTC — one ps call covering every live pid. When neither yields a
# token, the recycled-pid check is skipped and liveness alone decides.

# /proc/<pid>/stat field 22 — start time in clock ticks since boot.
proc_start() { # $1=pid -> sets PSTART ('' when unreadable)
  local st
  local -a f
  PSTART=''
  [ -r "/proc/$1/stat" ] || return
  IFS= read -r st < "/proc/$1/stat"
  f=(${st##*\) }) # past "pid (comm) " — comm may itself contain spaces
  PSTART=${f[19]}
}

s_total=0 s_busy=0 s_wait=0 s_agents=0
if [ "$np" -gt 0 ]; then
  if [ ! -d /proc/self ]; then
    plist=${SP[*]}
    while read -r p st; do
      case $p in '' | *[!0-9]*) continue ;; esac
      LSTART[p]=$st
    done < <(LC_ALL=C TZ=UTC ps -o pid=,lstart= -p "${plist// /,}")
  fi
  recs=''
  for ((i = 0; i < np; i++)); do
    pid=${SP[i]}
    if [ -d /proc/self ]; then
      proc_start "$pid"
    else
      PSTART=${LSTART[pid]}
    fi
    recs+="$PSTART"$'\t'"$pid"$'\t'"${SR[i]}"$'\n'
  done
  # One "status sessionId pid" line per record that checks out.
  nj=0
  while IFS=$'\t' read -r st sid pid; do
    s_total=$((s_total + 1))
    case $st in
      busy | shell) s_busy=$((s_busy + 1)) ;;
      waiting) s_wait=$((s_wait + 1)) ;;
    esac
    # Workflow runs still in flight in this session. Each run keeps a
    # journal — one "started" line per agent, then "result" or "failed" for
    # the same key — and gets a workflows/<run>.json once it is over. A
    # journal older than the session's .key file (written when the process
    # started) belongs to an earlier process and cannot be running.
    case $sid in '' | *[!0-9a-f-]*) continue ;; esac
    SIDS="$SIDS $sid"
    key=''
    for k in "$sdir/$pid".*.key; do [ -f "$k" ] && key=$k; done
    for j in "$cfgdir"/projects/*/"$sid"/subagents/workflows/*/journal.jsonl; do
      [ -f "$j" ] || continue
      run=${j%/journal.jsonl}
      [ -f "${run%/subagents/workflows/*}/workflows/${run##*/}.json" ] && continue
      [ -n "$key" ] && [ "$key" -nt "$j" ] && continue
      JR[nj]=$j
      nj=$((nj + 1))
    done
  done < <(printf '%s' "$recs" | jq -Rr '
    split("\t") as [$start, $pid, $rec] | $rec | fromjson? | objects
    | select(.spare != true and .kind != "daemon")
    | select($start == "" or (.procStart | type) != "string" or .procStart == $start)
    | [(.status | strings) // "-", (.sessionId | strings) // "-", $pid] | join("\t")')
  if [ "$nj" -gt 0 ]; then
    s_agents=$(awk -F'"' '
      $2 == "type" && $6 == "key" {
        k = FILENAME SUBSEP $8
        if ($4 == "started") n[k]++
        else if (($4 == "result" || $4 == "failed") && n[k] > 0) n[k]--
      }
      END { for (k in n) t += n[k]; print t + 0 }' "${JR[@]}")
    case $s_agents in '' | *[!0-9]*) s_agents=0 ;; esac
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
  if   [ "$1" -ge 80 ]; then echo "$ORANGE"
  elif [ "$1" -ge 50 ]; then echo "$GOLD"
  else echo "$GREEN"
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

# Palette. The fill scale is deliberately muted — sage, soft gold, terracotta —
# because these colors sit on screen all day next to the text. Never red.
GREEN=71  # calm green: low fill + the robbyrussell arrow
GOLD=179  # soft gold: half full
ORANGE=173 # muted terracotta: nearly full — as loud as this gets
# "2h 57m" -> "2ʰ 57ᵐ". Modifier letters are what a terminal has instead of a
# smaller font: the font draws them small, so the countdown stops competing
# with the percentage. The ASCII form stays the one the layout MEASURES —
# these glyphs are one cell but up to three bytes, and ${#var} counts bytes
# under a C locale.
small_units() { # $1=ascii countdown -> sets SMALL
  local s=$1 c i
  SMALL=''
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      h) SMALL+='ʰ' ;;
      m) SMALL+='ᵐ' ;;
      d) SMALL+='ᵈ' ;;
      *) SMALL+=$c ;;
    esac
  done
}

DIM=238   # empty bar cells
TRACK=236 # the unfilled part of a block meter's cell
LBL=244   # labels and countdowns
BARW=5    # bar width in cells (compact tier drops to 4)

# Meter style, OMS_METER: block (default) — one cell filled from the bottom in
# eighths over a dark track, so the empty part stays visible and the gauge is
# full cell height in any font; pie — one cell, ○◔◑◕● (small in many fonts);
# bar — the classic ▰▱ bar. Every glyph on this line is standard Unicode, which
# a font that lacks it borrows from another font. Nerd Font icons were tried
# and dropped: they sit in the Private Use Area, where no terminal borrows, so
# without that exact font they render as boxes — and a line drawn while the
# font was there keeps showing boxes after it is gone.
meter=${OMS_METER:-block}
BLOCK=(' ' ▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
PIE=(○ ◔ ◑ ◕ ●)

SEP=$'\033[38;5;238m │ \033[0m'
SEPW=3    # plain-character width of SEP

# --- Info row: dir+git · model · effort ---------------------------------------
# Each piece is kept on its own with its plain width, so the row can be rebuilt
# at a narrower tier when the terminal is small: it sheds the effort level,
# then the git branch, then the model, and only then truncates the directory
# name. The directory itself never disappears — it is what tells you where you
# are, and a status line that cannot say that has nothing left to say.
seg_dir='' seg_dir_w=0     # ➜  dir
seg_git='' seg_git_w=0     # git:(branch) ✗ — glued to the dir, no separator
seg_model='' seg_model_w=0
seg_effort='' seg_effort_w=0
dname=''

# 1) Dir + git in oh-my-zsh robbyrussell format: ➜  dir git:(branch) ✗
# arrow=green, dir=cyan, git:()=blue, branch=soft red (167, not harsh), ✗=gold.
if [ "$cwd" != "-" ] && [ -n "$cwd" ]; then
  if [ "$cwd" = "$HOME" ]; then
    dname='~'
  else
    dname=${cwd##*/}
  fi
  seg_dir=$(printf '\033[1;38;5;%sm➜\033[0m  \033[38;5;44m%s\033[0m' "$GREEN" "$dname")
  seg_dir_w=$((3 + ${#dname}))
  if git --no-optional-locks -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      seg_git=$(printf ' \033[38;5;33mgit:(\033[38;5;167m%s\033[38;5;33m)\033[0m' "$branch")
      seg_git_w=$((7 + ${#branch}))
      if [ -n "$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null)" ]; then
        seg_git+=$(printf ' \033[38;5;%sm✗\033[0m' "$GOLD")
        seg_git_w=$((seg_git_w + 2))
      fi
    fi
  fi
fi

# 2) Model (soft blue-gray). A trailing parenthetical — "Opus 5.5 (1M
# context)" — is detail the line has no room for; the name alone stays.
m=${model%% (*)}
[ -n "$m" ] && model=$m
seg_model=$(printf '\033[38;5;109m%s\033[0m' "$model")
seg_model_w=${#model}

# 3) Effort (muted plain text, lowercase — no emoji glyphs).
if [ "$effort" != "-" ] && [ -n "$effort" ]; then
  case "$effort" in
    low) ecol=$GREEN ;;
    medium) ecol=109 ;;
    high) ecol=$GOLD ;;
    xhigh) ecol=$ORANGE ;;
    max) ecol=133 ;;
    *) ecol=244 ;;
  esac
  seg_effort=$(printf '\033[38;5;%sm%s\033[0m' "$ecol" "$effort")
  seg_effort_w=${#effort}
fi

# 4) Account (soft mauve). It trails the whole status line — the end of the
# single row, or the end of the wrapped bars row — so it is built as a trailing
# element with its own separator, in two widths: full address and local part.
acct_seg='' acct_seg_w=0 acct_seg_short='' acct_seg_short_w=0
if [ -n "$acct" ]; then
  acct_seg=$(printf '\033[38;5;139m%s\033[0m' "$acct")
  acct_seg_w=${#acct}
  acct_seg_short=$(printf '\033[38;5;139m%s\033[0m' "$acct_short")
  acct_seg_short_w=${#acct_short}
fi

# 5) Open sessions: "✻ 2/3  ◐ 1  ↳ 5" — Claude's own asterisk (its banner and
# spinner glyph), the sessions at work (busy, shell included) over all open
# ones, then ◐ the sessions waiting on you — a permission prompt or a question,
# shown only when there are any and the only bold count, since it is the one
# that asks for you — and ↳ the workflow agents running across them. One space
# ties a glyph to its number, two set the groups apart. The asterisk stays
# neutral: terracotta means "nearly full" on this line. It sits in front of the
# account, in the same trailing group. Widths are counted by hand: each glyph
# is one cell but several bytes.
sess_seg='' sess_seg_w=0
if [ "$s_total" -gt 0 ]; then
  bcol=$GREEN
  [ "$s_busy" -gt 0 ] || bcol=$LBL
  sess_seg=$(printf '\033[38;5;250m✻ \033[38;5;%sm%s\033[38;5;%sm/%s\033[0m' "$bcol" "$s_busy" "$LBL" "$s_total")
  sess_seg_w=$((2 + ${#s_busy} + 1 + ${#s_total}))
  for st in "$s_wait ◐ 1;38;5;$GOLD" "$s_agents ↳ 0;38;5;109"; do
    set -- $st
    [ "$1" -gt 0 ] || continue
    sess_seg+=$(printf '  \033[%sm%s %s\033[0m' "$3" "$2" "$1")
    sess_seg_w=$((sess_seg_w + 4 + ${#1}))
  done
fi

# Widest-first tiers the layout walks until the row fits: the account gives
# way first (full address, local part, gone), then the session counts.
acct_tiers='email user none'
[ "$acct_mode" = user ] && acct_tiers='user none'
[ -n "$acct" ] || acct_tiers='none'
tail_tiers=$acct_tiers
if [ -n "$sess_seg" ]; then
  tail_tiers=''
  for t in $acct_tiers; do tail_tiers+="s+$t "; done
  tail_tiers+='none'
fi

set_tail() { # $1=[s+]email|user|none -> TAIL (separators included), TAILW
  TAIL='' TAILW=0
  case $1 in
    s+*) TAIL="$SEP$sess_seg" TAILW=$((SEPW + sess_seg_w)) ;;
  esac
  case ${1#s+} in
    email) TAIL+="$SEP$acct_seg" TAILW=$((TAILW + SEPW + acct_seg_w)) ;;
    user) TAIL+="$SEP$acct_seg_short" TAILW=$((TAILW + SEPW + acct_seg_short_w)) ;;
  esac
}

compose_info() { # $1..$3 = keep git / model / effort (1 or 0)
  info=$seg_dir info_w=$seg_dir_w
  if [ "$1" = 1 ] && [ -n "$seg_git" ]; then
    info+=$seg_git
    info_w=$((info_w + seg_git_w))
  fi
  if [ "$2" = 1 ]; then
    [ -n "$info" ] && { info+="$SEP"; info_w=$((info_w + SEPW)); }
    info+=$seg_model
    info_w=$((info_w + seg_model_w))
  fi
  if [ "$3" = 1 ] && [ -n "$seg_effort" ]; then
    [ -n "$info" ] && { info+="$SEP"; info_w=$((info_w + SEPW)); }
    info+=$seg_effort
    info_w=$((info_w + seg_effort_w))
  fi
}

fit_info() { # shrink the info row a tier at a time until it fits $cols
  local n
  compose_info 1 1 1
  [ "$info_w" -le "$cols" ] && return
  compose_info 1 1 0
  [ "$info_w" -le "$cols" ] && return
  compose_info 0 1 0
  [ "$info_w" -le "$cols" ] && return
  compose_info 0 0 0
  [ "$info_w" -le "$cols" ] && return
  # Last resort: cut the directory name. Only for a plain-ASCII name — slicing
  # a multibyte name by bytes (what ${x:0:n} does in a C locale) would emit a
  # broken sequence, and a corrupted glyph is worse than an overflowing row.
  case $dname in
    '' | *[!A-Za-z0-9._@+-]*) return ;;
  esac
  n=$((cols - 4))
  [ "$n" -lt 1 ] && return
  [ "$n" -ge ${#dname} ] && return
  seg_dir=$(printf '\033[1;38;5;%sm➜\033[0m  \033[38;5;44m%s…\033[0m' "$GREEN" "${dname:0:n}")
  seg_dir_w=$((3 + n + 1))
  compose_info 0 0 0
}

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

build_bars() { # $1=bar cells (0 = no meter)  $2=full|bare -> BARS, BARS_W
  local barw=$1 mode=$2 i pct col wt tcol lab num rest restw bar bstyle barcells fill j
  BARS='' BARS_W=0
  for ((i = 0; i < nbars; i++)); do
    pct=${BP[i]}
    col=$(level_color "$pct")
    # Emphasis follows urgency. Below half a limit the number is plain weight
    # and the countdown nearly fades — nothing to act on; past half it turns
    # bold, and past 80% the reset time brightens, because "when does this
    # free up" is then the question.
    wt='0;' tcol=240
    [ "$pct" -ge 50 ] && wt='1;' tcol=$LBL
    [ "$pct" -ge 80 ] && tcol=250
    lab=${BL[i]}
    num="${pct}%"
    rest='' restw=0
    if [ "$mode" = full ] && [ -n "${BT[i]}" ]; then
      small_units "${BT[i]}"
      rest=" $SMALL"
      restw=$((1 + ${#BT[i]}))
    fi
    if [ -n "$BARS" ]; then
      BARS+="$SEP"
      BARS_W=$((BARS_W + SEPW))
    fi
    if [ "$barw" -gt 0 ]; then
      # The meter carries the level color across the whole glyph — its shape
      # already separates full from empty, so the color is free to mean level.
      bstyle="38;5;$col" barcells=1
      case $meter in
        bar)
          fill=$(((pct * barw + 50) / 100))
          [ "$fill" -gt "$barw" ] && fill=$barw
          bar=''
          for ((j = 0; j < barw; j++)); do
            if [ "$j" -lt "$fill" ]; then bar+='▰'; else bar+='▱'; fi
          done
          barcells=$barw
          ;;
        pie) bar=${PIE[$(((pct * 4 + 50) / 100))]} ;;
        *) # One cell whatever the tier, on its track: the eighth nearest the level.
          bar=${BLOCK[$(((pct * 8 + 50) / 100))]}
          bstyle+=";48;5;$TRACK"
          ;;
      esac
      BARS+=$(printf '\033[38;5;%sm%s \033[%sm%s\033[0m \033[%s38;5;%sm%s\033[0m\033[38;5;%sm%s\033[0m' \
        "$LBL" "$lab" "$bstyle" "$bar" "$wt" "$col" "$num" "$tcol" "$rest")
      BARS_W=$((BARS_W + ${#lab} + 1 + barcells + 1 + ${#num} + restw))
    else
      BARS+=$(printf '\033[38;5;%sm%s \033[%s38;5;%sm%s\033[0m\033[38;5;%sm%s\033[0m' \
        "$LBL" "$lab" "$wt" "$col" "$num" "$tcol" "$rest")
      BARS_W=$((BARS_W + ${#lab} + 1 + ${#num} + restw))
    fi
  done
}

# --- Layout (flex-wrap) --------------------------------------------------------
# One line when it fits. The trailing group is the first thing to give way —
# the account (full address, then local part, then gone), then the session
# counts — before the bars wrap onto a second row and compact in steps.
# Countdowns survive every step but the last (bare) one.
build_bars "$BARW" full
compose_info 1 1 1

if [ "$nbars" -eq 0 ]; then
  fit_info
  for t in $tail_tiers; do
    set_tail "$t"
    [ $((info_w + TAILW)) -le "$cols" ] && break
  done
  printf -v out '%s%s\033[0m' "$info" "$TAIL"
else
  one_line=0
  for t in $tail_tiers; do
    set_tail "$t"
    if [ $((info_w + SEPW + BARS_W + TAILW)) -le "$cols" ]; then
      one_line=1
      break
    fi
  done

  if [ "$one_line" -eq 1 ]; then
    printf -v out '%s%s%s%s\033[0m' "$info" "$SEP" "$BARS" "$TAIL"
  else
    # Two rows: info above, bars (still trailed by the sessions and account
    # while they fit) below — narrowing the bars only after both are gone. The
    # info row gets its own shrink ladder; on one line it is never trimmed,
    # because wrapping is always the better trade there.
    fit_info
    fit=0
    for t in $tail_tiers; do
      set_tail "$t"
      if [ $((BARS_W + TAILW)) -le "$cols" ]; then
        fit=1
        break
      fi
    done
    if [ "$fit" -eq 0 ]; then
      set_tail none
      [ "$BARS_W" -gt "$cols" ] && build_bars 4 full
      [ "$BARS_W" -gt "$cols" ] && build_bars 0 full
      [ "$BARS_W" -gt "$cols" ] && build_bars 0 bare
    fi
    printf -v out '%s\033[0m\n%s%s\033[0m' "$info" "$BARS" "$TAIL"
  fi
fi
printf '%s' "$out"

# Keep this render for the next tick (see Render cache). Written aside and moved
# into place, so a run cut short never leaves half a cache behind. Old caches
# are swept at most once a day.
if [ -n "$cache" ]; then
  [ -d "$cachedir" ] || mkdir -p "$cachedir"
  printf '%s\n%s\n%s' "$ckey" "$SIDS" "$out" > "$cache.$$" && mv -f "$cache.$$" "$cache"
  swept=0
  [ -f "$cachedir/.swept" ] && read -r swept < "$cachedir/.swept"
  case $swept in '' | *[!0-9]*) swept=0 ;; esac
  if [ $((now - swept)) -ge 86400 ]; then
    echo "$now" > "$cachedir/.swept"
    find "$cachedir" -name 'render-*' -mtime +1 -exec rm -f {} + > /dev/null 2>&1
  fi
fi
