# claude-status

Whether Claude Code is working, blocked or done, in your tmux status bar.

[![ci](https://github.com/stefanahman/claude-status/actions/workflows/ci.yml/badge.svg)](https://github.com/stefanahman/claude-status/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/stefanahman/claude-status)](https://github.com/stefanahman/claude-status/releases)
[![license](https://img.shields.io/github/license/stefanahman/claude-status)](LICENSE)

```
[work]  1:claude  2:vim  3:shell            work*  eden  pr(1⚠ 2~ 1)   Thu 17:46
                                            ─────  ────  ────────────
                                            done,  idle  one chip for a whole
                                            unread       session of agents
```

Claude Code hooks write the state where the session runs, as a tmux
window option, and a small renderer turns it into coloured chips, one
per window. Looking at a finished window acknowledges it. Nothing polls
Claude, nothing scrapes the screen, and it works the same over SSH.

## Install

The hooks are a Claude Code plugin:

```
/plugin marketplace add stefanahman/claude-status
/plugin install claude-status@claude-status
```

The chips are a tmux plugin, through [TPM](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'stefanahman/claude-status'
set -g status-right '#{claude_status} %a %H:%M'
set -g status-right-length 100
```

Under cmux there is nothing to install: cmux shows the same states in
its sidebar.

## States

| state | colour | meaning | written by |
|---|---|---|---|
| `working` | yellow | processing a turn | hooks |
| `blocked` | orange | waiting for you: permission, question, plan approval | hooks |
| `done` | green, `*` suffix | finished, you haven't looked yet | hooks |
| `idle` | green | waiting for your next prompt: just started, or finished and seen | hooks (session start), ack (`prefix + a`, or focusing the window; tmux only) |
| *(unset)* | — | no Claude here / session ended | hooks |

## Docs

- [Install](docs/install.md): settings.json instead of `/plugin`, without
  TPM, and cmux
- [States](docs/states.md): what each state means, and the contract
  other tools read
- [Options](docs/options.md): the ack key, colours, one chip per session
- [How it works](docs/how-it-works.md): the hooks, focus, manual setup,
  limits, related plugins

See also: [owl](https://github.com/stefanahman/owl) ·
[spaces](https://github.com/stefanahman/spaces) ·
[mux](https://github.com/stefanahman/mux) ·
[mindoro](https://github.com/stefanahman/mindoro) ·
[mcp-defer](https://github.com/stefanahman/mcp-defer) ·
[eden](https://github.com/stefanahman/eden)

## License

MIT
