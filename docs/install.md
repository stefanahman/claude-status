# Install

Two halves: the hooks are a Claude Code plugin, and tmux adds a plugin of
its own for the chips. One contract between them.

## 1. Claude Code (plugin)

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
it works*; tested with that release). Outside tmux they exit
immediately.

## 2. tmux (TPM)

```tmux
set -g @plugin 'stefanahman/claude-status'
set -g status-right '#{claude_status} %a %H:%M'   # put the placeholder wherever you like
set -g status-right-length 100                    # the default 40 truncates after a few chips

run '~/.tmux/plugins/tpm/tpm'
```

Press `prefix + I` to fetch it. Load it *after* any theme that rewrites
`status-right`, otherwise the theme overwrites the placeholder.

Without TPM: clone the repo and `run-shell /path/to/claude-status/claude-status.tmux`.

## 3. cmux — nothing to do

cmux keeps its own agent state from the same Claude Code hooks and shows
it in its sidebar, so this plugin writes nothing there. It used to set a
second pill, back when cmux folded Claude's idle reminder into "Needs
input" and a waiting agent read as one that wanted you; upstream fixed
that, and two answers to one question is worse than one.

Was `tmux-claude-status`; GitHub redirects the old name, and the Claude
Code plugin was always `claude-status@claude-status`.
