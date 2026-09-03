# Journal

## 2026-09-03 - initialized
- documentation tree created

## 2026-09-03 - signed-in account + updates that cannot get stuck
- the status line trails the signed-in account, read from the Claude Code config because the payload never carries it
- re-running the installer is now the update path on every supported OS
- root cause of installs that never updated: `chmod +x` dirtied a tree tracked 100644, so `pull --ff-only` refused forever
- bars keep their glyph meter, with the percentage carrying the accent
- the info row gained a shrink ladder, so narrow terminals stop overflowing
