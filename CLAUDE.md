# claude-status — agent notes

Two halves, one contract (README.md): Claude Code hooks (the
`claude-status@claude-status` plugin) write the agent's state — a tmux
window option under tmux, a sidebar pill under cmux — and the tmux half
renders it. owl reads the state through mux; the pill's shape (key
`claude`, values working/blocked/done/idle) is shared with mux's cmux
driver, so a change to it changes mux too.

The parts, so a change starts in the right file:

| file | what |
|---|---|
| `hooks/hooks.json` | which Claude Code event writes which state — the first file to open when the state is wrong |
| `bin/claude-state` | writes it: the tmux window option, the cmux pill, or both |
| `bin/claude-tmux-summary` | renders the status line, including the aggregate chips |
| `bin/claude-tmux-ack` | done → idle, from the key and the focus hooks |
| `claude-status.tmux` | the TPM entry: binds the key, installs the focus hooks, wires `#{claude_status}` |
| `README.md`, "The contract (for other tools)" | the window option and the pill as other tools read them — mux depends on this section, so change it and mux with it |

A change is done when it is committed in coherent pieces, pushed with
CI green, live on this machine, documented, and — at a milestone —
tagged and released. Do all of it and say which steps you did.

## Test

```sh
test/smoke.sh                       # a throwaway tmux server, a fake cmux
BASH_BIN=/bin/bash test/smoke.sh    # stock macOS bash 3.2
shellcheck claude-status.tmux bin/* test/smoke.sh
claude plugin validate . --strict   # CI's plugin job runs this too
```

Check exit codes, not output. The scripts must stay bash 3.2 and never
print on a hook's stdout (SessionStart output is fed to Claude). The
smoke test unsets CMUX_WORKSPACE_ID first; a shell inside cmux carries
the real one. CI has a fourth step the local commands do not: every
file in `bin/` and `claude-status.tmux` must be executable, so a new
script needs `chmod +x` before it is committed.

## Commit

Conventional commits, lower-case subject, a body that says why; no
Co-Authored-By trailers. The version bumps are their own commits, as
in the history: `chore: plugin 0.2.1`, `chore: the marketplace lists
0.2.1`.

## Push, and make it live here

```sh
git push origin main
gh run list --workflow ci --branch main --limit 1   # until completed success
```

CI (`.github/workflows/ci.yml`): `test` (shellcheck, the smoke suite on
a real tmux, the executable bits) and `plugin` (`claude plugin validate
--strict` for the shape and `claude plugin tag --dry-run .` for the
version, which must read the same in all three places; on a pinned
`@anthropic-ai/claude-code` that has to be bumped now and then).

The tmux half loads from `~/.config/tmux/plugins/claude-status`, a
symlink to this checkout on Stefan's machine (TPM treats an existing
directory as installed): run `claude-status.tmux` from that path to
re-wire the running server (TPM does it on `prefix + I` and at server
start; a plain `tmux source-file` leaves the old wiring in place).

The Claude half takes two commands and a restart, and each does a
different thing:

```sh
claude plugin marketplace update claude-status   # the catalogue: pulls the marketplace clone
claude plugin update claude-status@claude-status # the installed copy, which is what a session loads
```

Neither alone is enough, and a session keeps the hooks it started with,
so a restart is what makes a hook change take effect.

## Ship at a milestone

Bump the version in three places, in two commits as the history does
(`chore: plugin 0.2.1`, `chore: the marketplace lists 0.2.1`):
`.claude-plugin/plugin.json`, and in `.claude-plugin/marketplace.json`
both `metadata.version` and `plugins[0].version`. Then a tag and a
release with notes — there is no goreleaser here:

```sh
git tag -a v0.2.1 -m "claude-status 0.2.1: <the batch, one line>"
git push origin v0.2.1
gh release create v0.2.1 --title v0.2.1 --notes "<what changed, for the people on TPM and the marketplace>"
```
