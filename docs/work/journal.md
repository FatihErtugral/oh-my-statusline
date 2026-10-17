# Journal

## 2026-10-17 - open sessions, block meters, urgency emphasis
- the line counts open Claude Code sessions and the workflow agents they run, from records Anthropic does not document; ultracode is absent from the payload — [[reference/claude-local-state]]
- meters became a one-cell block gauge on a dark track; Nerd Font glyphs and icon labels were tried and dropped — [[reference/terminal-nerd-glyphs]]
- emphasis follows urgency: bold only past half a limit, the countdown brightens near the limit
- a `refreshInterval` timer keeps other sessions current; a per-session render cache makes idle ticks ~7 ms instead of ~35

## 2026-09-03 - initialized
- documentation tree created

## 2026-09-03 - signed-in account + updates that cannot get stuck
- the status line trails the signed-in account, read from the Claude Code config because the payload never carries it
- re-running the installer is now the update path on every supported OS
- root cause of installs that never updated: `chmod +x` dirtied a tree tracked 100644, so `pull --ff-only` refused forever
- bars keep their glyph meter, with the percentage carrying the accent
- the info row gained a shrink ladder, so narrow terminals stop overflowing
