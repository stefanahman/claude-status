# tmux-claude-status

See whether [Claude Code](https://docs.claude.com/en/docs/claude-code) is
**working**, **blocked** on you, or **done** — for every tmux window, in the
status bar you already have.

```
[work]  1:claude  2:vim  3:shell            work*  eden  pr(1⚠ 2~ 1)   Thu 17:46
                                            ─────  ────  ────────────
                                            done,  idle  one chip for a whole
                                            unread       session of agents
```

Claude Code hooks write the state into a tmux window option; a tiny renderer
turns the options of all windows into coloured chips. Looking at a finished
window (focusing the pane, or the terminal itself) acknowledges it. Nothing
polls, nothing scrapes the screen, and it works the same over SSH.

## Install

Two halves, one contract. Install both.

### 1. tmux (TPM)

```tmux
set -g @plugin 'stefanahman/tmux-claude-status'
set -g status-right '#{claude_status} %a %H:%M'   # put the placeholder wherever you like
set -g status-right-length 100                    # the default 40 truncates after a few chips

run '~/.tmux/plugins/tpm/tpm'
```

Press `prefix + I` to fetch it. Load it *after* any theme that rewrites
`status-right`, otherwise the theme overwrites the placeholder.

Without TPM: clone the repo and `run-shell /path/to/tmux-claude-status/claude-status.tmux`.

### 2. Claude Code (plugin)

```
/plugin marketplace add stefanahman/tmux-claude-status
/plugin install claude-status@claude-status
```

Or in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-status": { "source": { "source": "github", "repo": "stefanahman/tmux-claude-status" } }
  },
  "enabledPlugins": { "claude-status@claude-status": true }
}
```

The plugin ships only hooks (`hooks/hooks.json`) — no skills, no commands, no
permissions — for the events Claude Code 2.1.263 emits (the table under *How
it works*; tested with that release). Outside tmux they exit immediately.

## States

| state | colour | meaning | written by |
|---|---|---|---|
| `working` | yellow | processing a turn | hooks |
| `blocked` | orange | waiting for you: permission, question, plan approval | hooks |
| `done` | green, `*` suffix | finished, you haven't looked yet | hooks |
| `idle` | green | waiting for your next prompt: just started, or finished and seen | hooks (session start), ack (`prefix + a`, or focusing the window) |
| *(unset)* | — | no Claude here / session ended | hooks |

If you're looking at the pane when Claude finishes — pane and window active,
and the terminal has focus — it goes straight to `idle`: no stale `*`.

### The contract (for other tools)

Everything lives in one window option, `@claude-state`, holding one of the
words above. Read it however you like:

```sh
tmux list-windows -a -F '#{session_name}:#{window_name} #{@claude-state}'
```

[pr-owl](https://github.com/stefanahman/pr-owl) reads it to badge pull
requests with the state of their review agent.

## Options

Set before `run '~/.tmux/plugins/tpm/tpm'`.

| option | default | |
|---|---|---|
| `@claude-status-ack-key` | `a` | key after `prefix` that acknowledges the current window |
| `@claude-status-aggregate` | *(none)* | `<session>:<label>` — collapse that session's windows into one `<label>(N⚠ N~ N* N)` chip |
| `@claude-status-color-working` | `#dbbc7f` | |
| `@claude-status-color-blocked` | `#ffaa00` | |
| `@claude-status-color-done` | `#00cc66` | used for `done` and `idle` |

Colours are anything tmux accepts (`colour214`, `red`, `#rrggbb`). tmux maps
hex to the nearest 256-colour when the terminal lacks true colour.

Aggregate example — one window per PR review in a `pr-reviews` session:

```tmux
set -g @claude-status-aggregate 'pr-reviews:pr'
```

renders `pr(1⚠ 2~ 1* 3)`: 1 blocked, 2 working, 1 done-unread, 3 idle.

## How it works

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

Each hook runs `bin/claude-tmux-state <state>`, which writes the window
option of `$TMUX_PANE`. `claude-status.tmux` binds the ack key, appends
`pane-focus-in` / `client-focus-in` hooks that run `bin/claude-tmux-ack`, turns
on `focus-events`, and replaces `#{claude_status}` with
`#(bin/claude-tmux-summary)`.

Focus acking needs a terminal that reports focus (Ghostty, iTerm2, kitty,
WezTerm, Alacritty, foot… do; Terminal.app doesn't) and, for the
terminal-focus half, tmux ≥ 3.3 (`client-focus-in`). Tested on 3.2a, 3.4 and
3.6. Without either, `prefix + a` still works.

### Manual hooks (no plugin)

If you'd rather not use the plugin system, the same hooks go into
`~/.claude/settings.json` with absolute paths:

```json
{
  "hooks": {
    "SessionStart":      [{ "matcher": "startup|resume|clear|fork", "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state idle" }] }],
    "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state working" }] }],
    "PostToolUse":       [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state working" }] }],
    "PreToolUse":        [{ "matcher": "AskUserQuestion|ExitPlanMode", "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state blocked" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state blocked" }] }],
    "Elicitation":       [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state blocked" }] }],
    "Notification":      [{ "matcher": "permission_prompt|agent_needs_input|elicitation_dialog", "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state blocked" }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state done" }] }],
    "StopFailure":       [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state done" }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-claude-status/bin/claude-tmux-state clear" }] }]
  }
}
```

## Limitations

- One state per window. Two Claude sessions in split panes of the same window
  overwrite each other; put them in separate windows.
- "Already looking at it" reads the terminal's focus from tmux ≥ 3.3
  (`client_flags`). On older servers it means *attached, pane active, window
  active*, so a finish while you're alt-tabbed away is acked as seen.
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
UIs. This plugin is for people who stay in tmux. The state words match
herdr's, so a bridge (`herdr pane report-agent`, `cmux set-status`) is a
few lines in `bin/claude-tmux-state` — not built yet.

## Hacking

```sh
test/smoke.sh                       # throwaway tmux server, 23 checks
BASH_BIN=/bin/bash test/smoke.sh    # macOS: prove it on bash 3.2
shellcheck claude-status.tmux bin/* test/smoke.sh
claude plugin validate .
claude --plugin-dir . -p 'Reply with ok'   # inside tmux: watch the window option flip
```

Developing against a checkout: `ln -sfn "$PWD" ~/.tmux/plugins/tmux-claude-status`
(`~/.config/tmux/plugins/` when your tmux.conf lives under `~/.config/tmux` —
TPM installs next to the config; it treats an existing directory as installed)
and `claude --plugin-dir /path/to/tmux-claude-status`.

## License

MIT
