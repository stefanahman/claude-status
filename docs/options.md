# Options

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
