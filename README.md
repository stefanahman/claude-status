# claude-status

See whether [Claude Code](https://docs.claude.com/en/docs/claude-code) is
**working**, **blocked** on you, or **done** — for every tmux window, in the
status bar you already have; for every [cmux](https://github.com/manaflow-ai/cmux)
workspace, as a pill in its sidebar.

```
[work]  1:claude  2:vim  3:shell            work*  eden  pr(1⚠ 2~ 1)   Thu 17:46
                                            ─────  ────  ────────────
                                            done,  idle  one chip for a whole
                                            unread       session of agents
```

Claude Code hooks write the state where the session runs: into a tmux
window option, which a tiny renderer turns into coloured chips, one per
window; or onto the cmux workspace, as a status pill next to cmux's own.
Looking at a finished tmux window (focusing the pane, or the terminal
itself) acknowledges it. Nothing polls Claude, nothing scrapes the screen,
and it works the same over SSH.

Was `tmux-claude-status`; GitHub redirects the old name, and the Claude
Code plugin was always `claude-status@claude-status`.

## Install

The hooks are a Claude Code plugin — that half is all cmux needs. tmux
adds a plugin of its own for the chips. One contract between them.

### 1. Claude Code (plugin)

```
/plugin marketplace add stefanahman/claude-status
/plugin install claude-status@claude-status
```

Or in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-status": { "source": { "source": "github", "repo": "stefanahman/claude-status" } }
  },
  "enabledPlugins": { "claude-status@claude-status": true }
}
```

The plugin ships only hooks (`hooks/hooks.json`) — no skills, no commands, no
permissions — for the events Claude Code 2.1.263 emits (the table under *How
it works*; tested with that release). Outside tmux and cmux they exit
immediately.

### 2. tmux (TPM)

```tmux
set -g @plugin 'stefanahman/claude-status'
set -g status-right '#{claude_status} %a %H:%M'   # put the placeholder wherever you like
set -g status-right-length 100                    # the default 40 truncates after a few chips

run '~/.tmux/plugins/tpm/tpm'
```

Press `prefix + I` to fetch it. Load it *after* any theme that rewrites
`status-right`, otherwise the theme overwrites the placeholder.

Without TPM: clone the repo and `run-shell /path/to/claude-status/claude-status.tmux`.

### 3. cmux

Nothing to install: cmux puts its CLI and the workspace id in the
environment of every terminal it runs, and the hooks use them. The pill
sits in the sidebar with cmux's own (custom pills are on by default,
`sidebar.showCustomMetadata`).

## States

| state | colour | meaning | written by |
|---|---|---|---|
| `working` | yellow | processing a turn | hooks |
| `blocked` | orange | waiting for you: permission, question, plan approval | hooks |
| `done` | green, `*` suffix | finished, you haven't looked yet | hooks |
| `idle` | green | waiting for your next prompt: just started, or finished and seen | hooks (session start), ack (`prefix + a`, or focusing the window; tmux only) |
| *(unset)* | — | no Claude here / session ended | hooks |

If you're looking at the tmux pane when Claude finishes — pane and window
active, and the terminal has focus — it goes straight to `idle`: no stale
`*`. Under cmux `done` stays until the next prompt; a reader that wants
"seen" pairs it with cmux's unread notification for the workspace.

### The contract (for other tools)

One word per Claude, one of the states above, where the session runs.

tmux: the window option `@claude-state`. Read it however you like:

```sh
tmux list-windows -a -F '#{session_name}:#{window_name} #{@claude-state}'
```

cmux: the workspace's status pill under the key `claude`:

```sh
cmux list-status --workspace <id>      # claude=blocked icon=hand.raised.fill color=#ffaa00 priority=90
```

cmux's own pill, `claude_code`, is its hook lifecycle rendered, and that
lifecycle folds Claude's idle reminder — the notification sent a minute
after every turn — into "Needs input". This pill carries the hook events
as they are, so `blocked` means a permission, a question or a plan review.

[owl](https://github.com/stefanahman/owl) reads both, through
[mux](https://github.com/stefanahman/mux), to badge pull requests and
issues with the state of their agent, and to refuse typing into one that
is blocked.

## Options

Set before `run '~/.tmux/plugins/tpm/tpm'`.

| option | default | |
|---|---|---|
| `@claude-status-ack-key` | `a` | key after `prefix` that acknowledges the current window |
| `@claude-status-aggregate` | *(none)* | `<session>:<label>` — collapse that session's windows into one `<label>(N⚠ N~ N* N)` chip; several pairs, space-separated |
| `@claude-status-color-working` | `#dbbc7f` | |
| `@claude-status-color-blocked` | `#ffaa00` | |
| `@claude-status-color-done` | `#00cc66` | used for `done` and `idle` |

Colours are anything tmux accepts (`colour214`, `red`, `#rrggbb`). tmux maps
hex to the nearest 256-colour when the terminal lacks true colour.

Aggregate example — one window per PR review in a `reviews` session:

```tmux
set -g @claude-status-aggregate 'reviews:pr'
```

renders `pr(1⚠ 2~ 1* 3)`: 1 blocked, 2 working, 1 done-unread, 3 idle.

A tool that keeps several such sessions gets a pair for each, separated by
spaces — [owl](https://github.com/stefanahman/owl) has three:

```tmux
set -g @claude-status-aggregate 'reviews:pr features:ft projects:pj'
```

renders `pr(2⚠ 1) ft(1~) pj(3)`, in the order the pairs are written and after
the one-chip-per-session ones. A pair whose session has no window with a state
renders nothing at all.

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

Each hook runs `bin/claude-state <state>`. Under cmux (`CMUX_WORKSPACE_ID`
set) it sets the workspace's `claude` pill through the CLI cmux names in
`CMUX_CLAUDE_HOOK_CMUX_BIN`, and clears it on `SessionEnd`; a cmux that
fails is ignored. Under tmux (`TMUX` and `TMUX_PANE`) it writes the window
option of `$TMUX_PANE`; a tmux server started inside a cmux terminal gets
both. `claude-status.tmux` binds the ack key, appends `pane-focus-in` /
`client-focus-in` hooks that run `bin/claude-tmux-ack`, turns on
`focus-events`, and replaces `#{claude_status}` with
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

- One state per tmux window, one per cmux workspace. Two Claude sessions
  in split panes of the same window, or in two surfaces of the same
  workspace, overwrite each other; put them in separate windows or
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
UIs, and each detects the state itself. cmux is bridged here because its
own detection reads the idle reminder as needing input; the pill is the
precise state beside it. herdr's words match these, so a bridge
(`herdr pane report-agent`) is a few lines in `bin/claude-state` — not
built yet.

## Hacking

```sh
test/smoke.sh                       # throwaway tmux server + a fake cmux, 42 checks
BASH_BIN=/bin/bash test/smoke.sh    # macOS: prove it on bash 3.2
shellcheck claude-status.tmux bin/* test/smoke.sh
claude plugin validate .
claude --plugin-dir . -p 'Reply with ok'   # inside tmux: watch the window option flip
```

Developing against a checkout: `ln -sfn "$PWD" ~/.tmux/plugins/claude-status`
(`~/.config/tmux/plugins/` when your tmux.conf lives under `~/.config/tmux` —
TPM installs next to the config; it treats an existing directory as installed)
and `claude --plugin-dir /path/to/claude-status`. Under cmux, the pill of
the workspace you run that in is yours to watch: `cmux list-status`.

## License

MIT
