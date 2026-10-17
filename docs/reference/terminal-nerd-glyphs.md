---
id: terminal-nerd-glyphs
type: reference
verification: unverified
sources:
  - "https://wezterm.org/config/fonts.html"
  - "https://github.com/ghostty-org/ghostty/discussions/9257"
  - "https://src.opensuse.org/rpm/kitty/src/branch/devel/kitty.changes (kitty 0.36.0, 2024-08-17)"
updated: 2026-10-17
---
# Nerd Font glyphs by terminal

This page lists which terminals draw Nerd Font glyphs and under what
condition. Read it before you put a Nerd Font glyph on the status line: it is
why the line uses none.

Unverified: only the VS Code row was observed first-hand, on VS Code 1.131 on
Linux on 2026-10-17. With MesloLGS Nerd Font installed but not selected, the
glyphs rendered as boxes; with it selected, they rendered. The other rows come
from the terminals' own documentation and changelogs.

Nerd Font glyphs sit in Unicode's Private Use Area. Having a Nerd Font
installed does not, by itself, make them render. The terminal must either use
that font, or fall back to it for a glyph its own font lacks, and fallback
differs from terminal to terminal.

| Terminal | Draws the glyphs when | Identified by |
| --- | --- | --- |
| VS Code, Cursor, VSCodium | `terminal.integrated.fontFamily` (else `editor.fontFamily`) names a Nerd Font; no fallback to other installed fonts | `TERM_PROGRAM=vscode` |
| WezTerm | always: Nerd Font Symbols is bundled in its default fallback | `TERM_PROGRAM=WezTerm` |
| Ghostty | always: Symbols Nerd Font is built in | `TERM_PROGRAM=ghostty` |
| kitty 0.36+ | always: a NERD symbols font is built in, used when no system font has the glyph | `KITTY_WINDOW_ID` |
| a GTK / pango renderer | a Nerd Font is installed: pango falls back through fontconfig, Private Use Area included | — |

Over SSH, the glyphs depend on the fonts of the machine running the terminal,
not on the remote host's fonts.

A status line drawn while a Nerd Font was in use keeps its glyphs after the
font changes. Until the line is drawn again, those glyphs show as boxes.

Standard Unicode "Block Elements" (`▁ ▂ ▃ … █`, `▘ ▝ ▛ ▜`) and Geometric
Shapes (`○ ◔ ◑ ◕ ●`) are outside the Private Use Area. Ordinary font fallback
covers them, and many terminals draw block elements themselves. Claude Code
draws its own mascot with block elements.
