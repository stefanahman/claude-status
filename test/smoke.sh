#!/usr/bin/env bash
# End-to-end check on a throwaway tmux server (-L): load the plugin the way
# TPM would, write each state through the hook script, ack, and assert what
# the status-bar renderer prints.
#
#   test/smoke.sh                       # scripts run under `bash` from PATH
#   BASH_BIN=/bin/bash test/smoke.sh    # macOS: prove they run on stock bash 3.2
#
# Not covered: the auto-ack branch in claude-tmux-state (needs an attached,
# focused client, i.e. a tty) and the Claude side (hooks/hooks.json), which
# `claude plugin validate .` checks structurally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"
SOCKET="claude-status-smoke-$$"
SCRATCH="$(mktemp -d)"

# Own socket AND -f /dev/null: -L alone still loads ~/.tmux.conf, and a
# real config may carry hooks or a status-right of its own.
t() { tmux -L "$SOCKET" -f /dev/null "$@"; }
cleanup() {
    t kill-server 2>/dev/null || true
    rm -rf "$SCRATCH"
}
trap cleanup EXIT

passed=0
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
ok() {
    passed=$((passed + 1))
    printf 'ok   %s\n' "$1"
}
assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3: expected [$2], got [$1]"
    ok "$3"
}
assert_contains() {
    [[ "$1" == *"$2"* ]] || fail "$3: expected to contain [$2], got [$1]"
    ok "$3"
}
assert_not_contains() {
    [[ "$1" != *"$2"* ]] || fail "$3: expected not to contain [$2], got [$1]"
    ok "$3"
}

# --- server ------------------------------------------------------------------
t new-session -d -s work -n main
t new-session -d -s pr-reviews -n scratch
t new-window -d -t pr-reviews -n pr-1
t new-window -d -t pr-reviews -n pr-2
t set-option -g status-right 'L #{claude_status} R'
t set-option -g @claude-status-aggregate 'pr-reviews:pr'

# The scripts find the server through $TMUX, like a real Claude session.
TMUX="$(t display-message -p '#{socket_path}'),0,0"
export TMUX

pane() { t display-message -t "$1" -p '#{pane_id}'; }
state() { TMUX_PANE="$(pane "$1")" "$BASH_BIN" "$ROOT/bin/claude-tmux-state" "$2"; }
ack() { "$BASH_BIN" "$ROOT/bin/claude-tmux-ack" "$(pane "$1")"; }
summary() { "$BASH_BIN" "$ROOT/bin/claude-tmux-summary"; }
opt() { t show-option -w -t "$(pane "$1")" -qv "${2:-@claude-state}"; }

# --- plugin load -------------------------------------------------------------
"$BASH_BIN" "$ROOT/claude-status.tmux"
assert_contains "$(t show-option -gv status-right)" "L #($ROOT/bin/claude-tmux-summary) R" "status-right interpolated"
assert_eq "$(t show-option -gv focus-events)" "on" "focus-events enabled"
assert_contains "$(t list-keys -T prefix a)" "claude-tmux-ack" "prefix + a bound"
hooks() { t show-hooks -g "$1" 2>/dev/null | grep -c claude-tmux-ack || true; }
# client-focus-in needs tmux ≥ 3.3; older servers get the pane hook only.
if t show-hooks -g client-focus-in >/dev/null 2>&1; then want="1/1"; else want="1/0"; fi
assert_eq "$(hooks pane-focus-in)/$(hooks client-focus-in)" "$want" "focus hooks installed"
"$BASH_BIN" "$ROOT/claude-status.tmux"
assert_eq "$(hooks pane-focus-in)/$(hooks client-focus-in)" "$want" "re-sourcing is idempotent"

# --- states ------------------------------------------------------------------
state work:main working
state pr-reviews:pr-1 blocked
state pr-reviews:pr-2 "done"
assert_eq "$(opt work:main)" working "state written to the window option"
assert_eq "$(opt pr-reviews:pr-2)" "done" "done stays unread without an attached client"

out=$(summary)
assert_contains "$out" '#[fg=#dbbc7f]work#[default]' "working chip"
assert_contains "$out" 'pr(#[fg=#ffaa00]1⚠#[default] #[fg=#00cc66]1*#[default])' "aggregate chip counts blocked + done"
assert_not_contains "$out" 'pr-reviews' "aggregated session gets no chip of its own"

# --- ack ---------------------------------------------------------------------
ack work:main
assert_eq "$(opt work:main)" working "ack is a no-op on a working window"
ack pr-reviews:pr-2
assert_eq "$(opt pr-reviews:pr-2)" idle "ack turns done into idle"
assert_contains "$(summary)" 'pr(#[fg=#ffaa00]1⚠#[default] #[fg=#00cc66]1#[default])' "idle counted without *"

state work:main "done"
assert_contains "$(summary)" '#[fg=#00cc66]work*#[default]' "done chip carries *"
state work:main idle
assert_eq "$(opt work:main)" idle "idle written directly (SessionStart)"
assert_contains "$(summary)" '#[fg=#00cc66]work#[default]' "idle chip has no *"
state work:main "done"

# --- tmux job context (what #() and the focus hooks actually run in) ---------
# Output goes through a file: older tmux doesn't relay run-shell output to a
# detached client.
t run-shell "$ROOT/bin/claude-tmux-summary > $SCRATCH/summary"
assert_contains "$(cat "$SCRATCH/summary")" '#[fg=#00cc66]work*#[default]' "summary renders as a tmux job"
t run-shell "$ROOT/bin/claude-tmux-ack $(pane work:main)"
assert_eq "$(opt work:main)" idle "ack works as a tmux job (focus-hook path)"

# --- clear -------------------------------------------------------------------
state work:main clear
state pr-reviews:pr-1 clear
state pr-reviews:pr-2 clear
assert_eq "$(summary)" "" "no stateful windows → empty output"

# --- options -----------------------------------------------------------------
t set-option -g @claude-status-color-working '#ff0000'
t set-option -g @claude-status-option '@agent'
state work:main working
assert_eq "$(opt work:main @agent)" working "custom option name honoured"
assert_contains "$(summary)" '#[fg=#ff0000]work#[default]' "custom colour honoured"

# --- guards ------------------------------------------------------------------
if state work:main green 2>/dev/null; then
    fail "unknown state accepted"
fi
ok "unknown state rejected"

(
    unset TMUX TMUX_PANE
    "$BASH_BIN" "$ROOT/bin/claude-tmux-state" working
) || fail "must be a no-op outside tmux"
ok "no-op outside tmux"

printf '\n%d checks passed\n' "$passed"
