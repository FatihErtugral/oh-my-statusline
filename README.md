# oh-my-statusline

oh-my-zsh (robbyrussell) flavored status line for Claude Code.

```
➜  focurise git:(master) ✗ │ Fable 5 │ xhigh │ ctx ▰▰▱▱▱▱ 33% │ 5h ▰▰▰▱▱▱ 45% (2h 3m) │ 7d ▰▰▱▱▱▱ 25% (5d 14h)
```

| Segment | What it shows |
| --- | --- |
| `➜ dir git:(branch) ✗` | cwd + git branch, classic robbyrussell colors (`✗` = dirty) |
| `Fable 5` | active model |
| `xhigh` | reasoning effort level |
| `ctx` | context window fill |
| `5h` | Claude plan 5-hour session limit — bar = used %, right = time until reset |
| `7d` | Claude plan weekly limit — same, weekly window |

Plan usage is read from the native `rate_limits` field Claude Code passes to
status lines (same data as `/usage`) — no external tools, no network calls,
~30 ms per render. Bar colors go green → gold → soft orange (never red).

## Requirements

- macOS or Linux (Windows not supported)
- `bash` 3.2+ (macOS stock bash works) and `jq`
- A font with `➜ ▰ ▱ │ ✗` glyphs (any Nerd Font / modern terminal font)

## Install

One-liner (oh-my-zsh style — clones to `~/.oh-my-statusline`):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/FatihErtugral/oh-my-statusline/master/install.sh)"
```

Or from a clone:

```sh
git clone https://github.com/FatihErtugral/oh-my-statusline.git
cd oh-my-statusline && ./install.sh
```

`install.sh` backs up `~/.claude/settings.json`, merges the `statusLine` entry
in (all other keys preserved), smoke-tests the script, and shows a sample render.

### As a Claude Code plugin

```
/plugin marketplace add FatihErtugral/oh-my-statusline   # or a local path
/plugin install oh-my-statusline@oh-my-statusline
/oh-my-statusline:install
```

### Manual setup

```json
"statusLine": {
  "type": "command",
  "command": "bash /absolute/path/to/oh-my-statusline/scripts/statusline.sh"
}
```

## Notes

- `rate_limits` is only present for Claude subscription plans and appears
  after the first API response — the usage bars simply stay hidden until then.
- Every numeric is validated before rendering; malformed payloads degrade to
  fewer segments, never garbage output.
