#!/usr/bin/env bash
# tmux-claude-status — TPM entry point.
#
# Wires three things into the running tmux server:
#   1. prefix + a (configurable)  → acknowledge the current window (done → idle)
#   2. focus hooks                → auto-acknowledge when you look at a finished window
#   3. #{claude_status}           → replaced in status-left/right by the summary renderer
#
# Options (set before `run '~/.tmux/plugins/tpm/tpm'`):
#   @claude-status-ack-key        key bound after prefix                (default: a)
#   @claude-status-aggregate      "<session>:<label>" — windows of <session>
#                                 collapse into one "<label>(…)" chip   (default: none)
#   @claude-status-color-working  colour for the working state          (default: #dbbc7f)
#   @claude-status-color-blocked  colour for the blocked state          (default: #ffaa00)
#   @claude-status-color-done     colour for done and idle              (default: #00cc66)
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACK="$CURRENT_DIR/bin/claude-tmux-ack"
SUMMARY="$CURRENT_DIR/bin/claude-tmux-summary"

get_option() {
    local value
    value=$(tmux show-option -gqv "$1")
    printf '%s' "${value:-$2}"
}

# 1. Manual ack.
tmux bind-key "$(get_option '@claude-status-ack-key' 'a')" run-shell "$ACK"

# 2. Auto-ack on focus. Both hooks are needed: pane-focus-in fires when the
# active pane changes inside a client (prefix+arrows, mouse, prefix+o);
# client-focus-in fires when the terminal window itself regains focus
# (alt-tab, a window manager focusing it). The pane id is passed explicitly
# because $TMUX_PANE isn't reliably set in hook context. Both need
# focus-events. -a appends so the user's own hooks survive; the check keeps
# re-sourcing idempotent (query by name — tmux 3.4's bare `show-hooks -g`
# doesn't list pane-focus-in). client-focus-in exists from tmux 3.3; on
# older servers only pane focus and the key ack.
tmux set-option -g focus-events on
hook_installed() {
    tmux show-hooks -g "$1" 2>/dev/null | grep -qF "$ACK"
}
hook_installed pane-focus-in || tmux set-hook -ga pane-focus-in "run-shell \"$ACK #{pane_id}\""
hook_installed client-focus-in || tmux set-hook -ga client-focus-in "run-shell \"$ACK #{client_active_pane}\"" 2>/dev/null || true

# 3. Status interpolation (the tmux-battery pattern): the literal placeholder
# #{claude_status} becomes a #() call to the renderer.
placeholder='#{claude_status}'
for option in status-left status-right; do
    current=$(tmux show-option -gqv "$option")
    [[ "$current" == *"$placeholder"* ]] || continue
    tmux set-option -gq "$option" "${current//"$placeholder"/#($SUMMARY)}"
done
