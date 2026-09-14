#!/usr/bin/env bash
# End-to-end check on a throwaway tmux server (-L): load the plugin the way
# TPM would, write each state through the hook script, ack, and assert what
# the status-bar renderer prints.
#
#   test/smoke.sh                       # scripts run under `bash` from PATH
#   BASH_BIN=/bin/bash test/smoke.sh    # macOS: prove they run on stock bash 3.2
#
# The cmux half runs against a fake `cmux` that logs its arguments.
#
# Not covered: the auto-ack branch in claude-state (needs an attached,
# focused client, i.e. a tty) and the Claude side (hooks/hooks.json), which
# `claude plugin validate .` checks structurally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"
SOCKET="claude-status-smoke-$$"
SCRATCH="$(mktemp -d)"

# Run from a cmux terminal, the hook script would pin a pill on the real
# workspace; the cmux half of this test uses a fake it names explicitly.
unset CMUX_WORKSPACE_ID CMUX_CLAUDE_HOOK_CMUX_BIN

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
# /bin/sh in every pane: the state hook runs inside the panes (it writes
# only from a process under the pane's own), and a login shell would
# read its rc files first. The first session carries it as its command;
# the option covers what comes after (a session-less server exits).
t new-session -d -s work -n main /bin/sh
t set-option -g default-shell /bin/sh
t new-session -d -s pr-reviews -n scratch
t new-window -d -t pr-reviews -n pr-1
t new-window -d -t pr-reviews -n pr-2
t set-option -g status-right 'L #{claude_status} R'
t set-option -g @claude-status-aggregate 'pr-reviews:pr'

# The scripts find the server through $TMUX, like a real Claude session.
TMUX="$(t display-message -p '#{socket_path}'),0,0"
export TMUX

pane() { t display-message -t "$1" -p '#{pane_id}'; }
# state runs the hook inside the pane, as Claude would, and waits for it.
state() {
    local mark="$SCRATCH/state.$RANDOM$RANDOM"
    t send-keys -t "$(pane "$1")" "$BASH_BIN '$ROOT/bin/claude-state' $2; touch '$mark'" Enter
    for _ in $(seq 1 200); do
        [[ -e "$mark" ]] && return 0
        sleep 0.05
    done
    fail "state $2 never ran in $1"
}
ack() { "$BASH_BIN" "$ROOT/bin/claude-tmux-ack" "$(pane "$1")"; }
summary() { "$BASH_BIN" "$ROOT/bin/claude-tmux-summary"; }
opt() { t show-option -w -t "$(pane "$1")" -qv @claude-state; }

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
assert_not_contains "$(t show-options -w -t "$(pane work:main)")" "@claude-state" "clear unsets the option"

# --- options -----------------------------------------------------------------
t set-option -g @claude-status-color-working '#ff0000'
state work:main working
assert_contains "$(summary)" '#[fg=#ff0000]work#[default]' "custom colour honoured"

# --- cmux: nothing is written ------------------------------------------------
# cmux keeps its own agent state from the same Claude Code hooks and mux
# reads that, so this plugin writes no pill: a second answer to an
# answered question, and one that went stale the moment the terminal it
# was written from went away. A fake on PATH proves the silence — being
# inside a cmux terminal must not produce a call.
FAKE_BIN="$SCRATCH/fake-bin"
mkdir -p "$FAKE_BIN"
CMUX_LOG="$SCRATCH/cmux.log"
cat >"$FAKE_BIN/cmux" <<EOF
#!/bin/sh
printf '%s\n' "$*" >>'$CMUX_LOG'
EOF
chmod +x "$FAKE_BIN/cmux"

for s in working blocked "done" idle clear; do
    out=$(
        unset TMUX TMUX_PANE
        PATH="$FAKE_BIN:$PATH" CMUX_WORKSPACE_ID=WS-1 CMUX_CLAUDE_HOOK_CMUX_BIN="$FAKE_BIN/cmux" \
            "$BASH_BIN" "$ROOT/bin/claude-state" "$s" 2>&1
    ) || fail "the hook must not fail inside a cmux terminal"
    assert_eq "$out" "" "cmux: $s prints nothing"
done
assert_eq "$([[ -e "$CMUX_LOG" ]] && wc -l <"$CMUX_LOG" | tr -d ' ' || echo 0)" "0" "cmux: no call is made"

# A tmux server inside a cmux terminal still gets its window option.
mark="$SCRATCH/both.$RANDOM"
t send-keys -t "$(pane work:main)" "CMUX_WORKSPACE_ID=WS-6 PATH='$FAKE_BIN:$PATH' $BASH_BIN '$ROOT/bin/claude-state' blocked; touch '$mark'" Enter
for _ in $(seq 1 200); do
    [[ -e "$mark" ]] && break
    sleep 0.05
done
[[ -e "$mark" ]] || fail "the hook inside cmux never ran"
assert_eq "$(opt work:main)" blocked "inside cmux: the tmux window option is still written"
assert_eq "$([[ -e "$CMUX_LOG" ]] && wc -l <"$CMUX_LOG" | tr -d ' ' || echo 0)" "0" "inside cmux: still no cmux call"
state work:main working

# --- aggregate: several pairs ------------------------------------------------
# owl keeps three such sessions; the option takes a pair for each.
t new-session -d -s features -n ft-1
t new-window -d -t features -n ft-2
t new-session -d -s projects -n pj-1
state features:ft-1 working
state features:ft-2 blocked
state projects:pj-1 idle
# pr-reviews' windows were cleared above: a pair whose session has no
# stateful window is named here on purpose.
t set-option -g @claude-status-aggregate 'features:ft projects:pj pr-reviews:pr'
out=$(summary)
assert_contains "$out" 'ft(#[fg=#ffaa00]1⚠#[default] #[fg=#ff0000]1~#[default])' "several pairs: the first chip counts its own session"
assert_contains "$out" 'pj(#[fg=#00cc66]1#[default])' "several pairs: the second chip counts its own"
assert_not_contains "$out" 'pr(' "a pair whose session has no stateful window renders nothing"
assert_not_contains "$out" '#[fg=#ff0000]features#[default]' "an aggregated session gets no chip of its own"
before=${out%%pj(*}
assert_contains "$before" 'ft(' "chips render in the order the pairs are written"

t set-option -g @claude-status-aggregate 'features:ft'
out=$(summary)
assert_contains "$out" 'ft(#[fg=#ffaa00]1⚠#[default] #[fg=#ff0000]1~#[default])' "one pair still aggregates, unchanged"
assert_contains "$out" '#[fg=#00cc66]projects#[default]' "a session outside the pairs keeps its own chip"

t set-option -g @claude-status-aggregate ''
out=$(summary)
assert_not_contains "$out" 'ft(' "no option, no aggregate chip"
assert_contains "$out" '#[fg=#ff0000]features#[default]' "the session gets its own chip back"

state features:ft-1 clear
state features:ft-2 clear
state projects:pj-1 clear

# --- guards ------------------------------------------------------------------
# The usage check comes before the pane guards, so it answers from here.
if TMUX_PANE="$(pane work:main)" "$BASH_BIN" "$ROOT/bin/claude-state" green 2>/dev/null; then
    fail "unknown state accepted"
fi
ok "unknown state rejected"

(
    unset TMUX TMUX_PANE
    "$BASH_BIN" "$ROOT/bin/claude-state" working
) || fail "must be a no-op outside tmux"
ok "no-op outside tmux"

# Inherited variables: this process is not under the pane they name.
TMUX_PANE="$(pane work:main)" "$BASH_BIN" "$ROOT/bin/claude-state" blocked || fail "must be a no-op outside the pane"
assert_eq "$(opt work:main)" working "a pane this process is not in is left alone"
TMUX_PANE="$(pane work:main)" "$BASH_BIN" "$ROOT/bin/claude-state" clear || fail "clear must be a no-op outside the pane"
assert_eq "$(opt work:main)" working "clear from outside the pane is ignored too"
TMUX_PANE=%9999 "$BASH_BIN" "$ROOT/bin/claude-state" working || fail "a pane that is gone must be a no-op"
ok "no-op when the pane is gone"

printf '\n%d checks passed\n' "$passed"
