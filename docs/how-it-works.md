# How it works

`hooks/hooks.json` maps Claude Code hook events to states:

| event | state |
|---|---|
| `SessionStart` (`startup`, `resume`, `clear`, `fork`) | `idle` |
| `UserPromptSubmit`, `PostToolUse` | `working` |
| `PreToolUse` for `AskUserQuestion` / `ExitPlanMode` | `blocked` |
| `PermissionRequest`, `Elicitation` | `blocked` |
| `Notification` (`permission_prompt`, `agent_needs_input`, `elicitation_dialog`) | `blocked` (belt and braces for the row above) |
| `Stop`, `StopFailure` | `done` |
| `SessionEnd` | *(unset)* |

Each hook runs `bin/claude-state <state>`, which writes the window option
of `$TMUX_PANE` when `TMUX` and `TMUX_PANE` are set, and does nothing
otherwise — including inside a cmux terminal, which keeps its own state.
A tmux server started inside one still gets its option.
`claude-status.tmux` binds the ack key, appends `pane-focus-in` /
`client-focus-in` hooks that run `bin/claude-tmux-ack`, turns on
`focus-events`, and replaces `#{claude_status}` with
`#(bin/claude-tmux-summary)`.

Focus acking needs a terminal that reports focus (Ghostty, iTerm2, kitty,
WezTerm, Alacritty, foot… do; Terminal.app doesn't) and, for the
terminal-focus half, tmux ≥ 3.3 (`client-focus-in`). Tested on 3.2a, 3.4 and
3.6. Without either, `prefix + a` still works.

## Manual hooks (no plugin)

If you'd rather not use the plugin system, the same hooks go into
`~/.claude/settings.json` with absolute paths:

```json
{
  "hooks": {
    "SessionStart":      [{ "matcher": "startup|resume|clear|fork", "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state idle" }] }],
    "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state working" }] }],
    "PostToolUse":       [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state working" }] }],
    "PreToolUse":        [{ "matcher": "AskUserQuestion|ExitPlanMode", "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state blocked" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state blocked" }] }],
    "Elicitation":       [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state blocked" }] }],
    "Notification":      [{ "matcher": "permission_prompt|agent_needs_input|elicitation_dialog", "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state blocked" }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state done" }] }],
    "StopFailure":       [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state done" }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/claude-status/bin/claude-state clear" }] }]
  }
}
```

## Limitations

- One state per tmux window. Two Claude sessions in split panes of the
  same window overwrite each other; put them in separate windows or
  workspaces.
- "Already looking at it" reads the terminal's focus from tmux ≥ 3.3
  (`client_flags`). On older servers it means *attached, pane active, window
  active*, so a finish while you're alt-tabbed away is acked as seen.
- tmux marks a client `focused` on the terminal's focus-in report and clears
  it on focus-out; a terminal window that never reports focus-out — one on
  another desktop space; with Ghostty and yabai three of six clients were
  `focused` at once — stays focused, so a finish there is auto-acked as seen.
- Requires bash (any version — stock macOS 3.2 is fine) on tmux's `PATH`.

## Related

Other tmux status plugins for Claude Code: [craftzdog/tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager),
[samleeney/tmux-agent-status](https://github.com/samleeney/tmux-agent-status),
[accessd/tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator),
[alexose/claude-tmux-status](https://github.com/alexose/claude-tmux-status),
[smilovanovic/tmux-claude](https://github.com/smilovanovic/tmux-claude),
[haxybaxy/claude-tmux-status](https://github.com/haxybaxy/claude-tmux-status).
This one differs in the explicit `done` → `idle` acknowledgement (including on
terminal focus), the `blocked` state covering questions and plan approval,
session aggregation, and shipping the hook half as an installable plugin.

[cmux](https://github.com/manaflow-ai/cmux) and [herdr](https://github.com/herdrdev/herdr)
solve the same problem by replacing the terminal / multiplexer, with richer
UIs, and each detects the state itself — cmux from these same hooks, which
is why nothing is written there. herdr's words match these, so a bridge
(`herdr pane report-agent`) is a few lines in `bin/claude-state` — not
built yet.
