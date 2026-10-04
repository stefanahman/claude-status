# States

| state | colour | meaning | written by |
|---|---|---|---|
| `working` | yellow | processing a turn | hooks |
| `blocked` | orange | waiting for you: permission, question, plan approval | hooks |
| `done` | green, `*` suffix | finished, you haven't looked yet | hooks |
| `idle` | green | waiting for your next prompt: just started, or finished and seen | hooks (session start), ack (`prefix + a`, or focusing the window; tmux only) |
| *(unset)* | — | no Claude here / session ended | hooks |

If you're looking at the pane when Claude finishes — pane and window
active, and the terminal has focus — it goes straight to `idle`: no stale
`*`.

## The contract (for other tools)

One word per Claude, one of the states above, where the session runs.

tmux: the window option `@claude-state`. Read it however you like:

```sh
tmux list-windows -a -F '#{session_name}:#{window_name} #{@claude-state}'
```

That option is the whole contract. Nothing is written under cmux: it
derives the same four states from its own copy of the hooks, and
[mux](https://github.com/stefanahman/mux) reads them from there —
`running`, `needsInput`, and `idle` paired with the workspace's unread
notification to tell `done` from `idle`.

[owl](https://github.com/stefanahman/owl) reads the state through mux, to
badge pull requests and issues with the state of their agent, and to
refuse typing into one that is blocked.
