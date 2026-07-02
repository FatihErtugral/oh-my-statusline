---
description: Activate the oh-my-statusline status line (writes statusLine into user settings)
allowed-tools: Read, Edit, Write, Bash
---

Activate this plugin's status line for the user.

The plugin root on this machine is: `${CLAUDE_PLUGIN_ROOT}`

Steps:

1. Verify `jq` is available (`command -v jq`). If missing, tell the user to install it (`brew install jq` on macOS, `apt/pacman install jq` on Linux) and stop.
2. Verify the script exists and is executable: `${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh` (chmod +x if needed).
3. Read `~/.claude/settings.json` (create `{}` if it does not exist). Preserving all other keys, set:

```json
"statusLine": {
  "type": "command",
  "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh\""
}
```

Write the RESOLVED absolute path (the literal value of `${CLAUDE_PLUGIN_ROOT}` shown above), not the variable — settings.json does not expand plugin variables.

4. If a previous `statusLine` existed, show the user the old value before replacing and confirm.
5. Confirm the change by piping a minimal payload through the script:
   `echo '{"model":{"display_name":"test"}}' | bash "${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"`
   Expected: a colored `test` string, exit 0.
6. Tell the user the status line takes effect on the next render (no restart needed).
