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

# --- cmux --------------------------------------------------------------------
# A fake cmux that logs its argv (with CMUX_QUIET) and talks on both
# streams: the hook must discard what it says.
FAKE_BIN="$SCRATCH/fake-bin"
mkdir -p "$FAKE_BIN"
CMUX_LOG="$SCRATCH/cmux.log"
cat >"$FAKE_BIN/cmux" <<EOF
#!/bin/sh
printf 'quiet=%s %s\n' "\${CMUX_QUIET-}" "\$*" >>'$CMUX_LOG'
echo "OK"
echo "cmux: chatter" >&2
EOF
chmod +x "$FAKE_BIN/cmux"
last_call() { tail -n 1 "$CMUX_LOG" 2>/dev/null || true; }
calls() { wc -l <"$CMUX_LOG" 2>/dev/null | tr -d ' ' || echo 0; }
# pill runs the hook outside tmux with the fake named as cmux's own CLI.
pill() {
    (
        unset TMUX TMUX_PANE
        CMUX_WORKSPACE_ID=WS-1 CMUX_CLAUDE_HOOK_CMUX_BIN="$FAKE_BIN/cmux" "$BASH_BIN" "$ROOT/bin/claude-state" "$1"
    )
}

out=$(pill working 2>&1)
assert_eq "$out" "" "pill: the hook prints nothing"
assert_eq "$(last_call)" 'quiet=1 set-status claude working --workspace WS-1 --icon bolt.fill --color #dbbc7f --priority 90' "pill: working"
pill blocked
assert_eq "$(last_call)" 'quiet=1 set-status claude blocked --workspace WS-1 --icon hand.raised.fill --color #ffaa00 --priority 90' "pill: blocked"
pill "done"
assert_eq "$(last_call)" 'quiet=1 set-status claude done --workspace WS-1 --icon checkmark.circle.fill --color #00cc66 --priority 90' "pill: done stays done (no auto-ack under cmux)"
pill idle
assert_eq "$(last_call)" 'quiet=1 set-status claude idle --workspace WS-1 --icon circle --color #00cc66 --priority 90' "pill: idle"
pill clear
assert_eq "$(last_call)" 'quiet=1 clear-status claude --workspace WS-1' "pill: clear removes it"

# cmux on PATH, no CMUX_CLAUDE_HOOK_CMUX_BIN: found by name.
n=$(calls)
(
    unset TMUX TMUX_PANE
    PATH="$FAKE_BIN:$PATH" CMUX_WORKSPACE_ID=WS-2 "$BASH_BIN" "$ROOT/bin/claude-state" working
)
assert_eq "$(last_call)" 'quiet=1 set-status claude working --workspace WS-2 --icon bolt.fill --color #dbbc7f --priority 90' "pill: cmux found on PATH"
assert_eq "$(calls)" "$((n + 1))" "pill: one call per state"

# CMUX_CLAUDE_HOOK_CMUX_BIN wins over PATH.
ALT_BIN="$SCRATCH/alt-bin"
mkdir -p "$ALT_BIN"
ALT_LOG="$SCRATCH/alt.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>%s\n' "'$ALT_LOG'" >"$ALT_BIN/cmux-alt"
chmod +x "$ALT_BIN/cmux-alt"
n=$(calls)
(
    unset TMUX TMUX_PANE
    PATH="$FAKE_BIN:$PATH" CMUX_WORKSPACE_ID=WS-3 CMUX_CLAUDE_HOOK_CMUX_BIN="$ALT_BIN/cmux-alt" "$BASH_BIN" "$ROOT/bin/claude-state" idle
)
assert_eq "$(tail -n 1 "$ALT_LOG")" 'set-status claude idle --workspace WS-3 --icon circle --color #00cc66 --priority 90' "pill: CMUX_CLAUDE_HOOK_CMUX_BIN names the CLI"
assert_eq "$(calls)" "$n" "pill: the PATH one is left alone then"

# No workspace, no call; no CLI, no failure.
n=$(calls)
(
    unset TMUX TMUX_PANE CMUX_WORKSPACE_ID
    PATH="$FAKE_BIN:$PATH" "$BASH_BIN" "$ROOT/bin/claude-state" working
) || fail "must be a no-op without CMUX_WORKSPACE_ID"
assert_eq "$(calls)" "$n" "pill: no call without CMUX_WORKSPACE_ID"
out=$(
    unset TMUX TMUX_PANE
    PATH="$SCRATCH/nowhere:/usr/bin:/bin" CMUX_WORKSPACE_ID=WS-4 CMUX_CLAUDE_HOOK_CMUX_BIN="$SCRATCH/nowhere/cmux" "$BASH_BIN" "$ROOT/bin/claude-state" working 2>&1
) || fail "must be a no-op when the CLI is missing"
assert_eq "$out" "" "pill: silent when the CLI is missing"

# A failing cmux is swallowed: exit 0, nothing printed.
BAD_BIN="$SCRATCH/bad-bin"
mkdir -p "$BAD_BIN"
printf '#!/bin/sh\necho "cmux: no such workspace" >&2\nexit 1\n' >"$BAD_BIN/cmux"
chmod +x "$BAD_BIN/cmux"
out=$(
    unset TMUX TMUX_PANE
    CMUX_WORKSPACE_ID=WS-5 CMUX_CLAUDE_HOOK_CMUX_BIN="$BAD_BIN/cmux" "$BASH_BIN" "$ROOT/bin/claude-state" working 2>&1
) || fail "a failing cmux must not fail the hook"
assert_eq "$out" "" "pill: a failing cmux is silent"

# Both at once: a tmux server inside a cmux terminal gets the window
# option and the pill.
n=$(calls)
mark="$SCRATCH/both.$RANDOM"
t send-keys -t "$(pane work:main)" "CMUX_WORKSPACE_ID=WS-6 CMUX_CLAUDE_HOOK_CMUX_BIN='$FAKE_BIN/cmux' $BASH_BIN '$ROOT/bin/claude-state' blocked; touch '$mark'" Enter
for _ in $(seq 1 200); do
    [[ -e "$mark" ]] && break
    sleep 0.05
done
[[ -e "$mark" ]] || fail "the both-at-once hook never ran"
assert_eq "$(opt work:main)" blocked "both: the tmux window option is written"
assert_eq "$(last_call)" 'quiet=1 set-status claude blocked --workspace WS-6 --icon hand.raised.fill --color #ffaa00 --priority 90' "both: the pill is written too"
assert_eq "$(calls)" "$((n + 1))" "both: one cmux call"
state work:main working

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
