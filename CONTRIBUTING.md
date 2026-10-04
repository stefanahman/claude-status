# Contributing

```sh
test/smoke.sh                       # throwaway tmux server + a fake cmux, 43 checks
BASH_BIN=/bin/bash test/smoke.sh    # macOS: prove it on bash 3.2
shellcheck claude-status.tmux bin/* test/smoke.sh
claude plugin validate .
claude --plugin-dir . -p 'Reply with ok'   # inside tmux: watch the window option flip
```

Developing against a checkout: `ln -sfn "$PWD" ~/.tmux/plugins/claude-status`
(`~/.config/tmux/plugins/` when your tmux.conf lives under `~/.config/tmux` —
TPM installs next to the config; it treats an existing directory as installed)
and `claude --plugin-dir /path/to/claude-status`.
