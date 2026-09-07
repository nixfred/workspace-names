#!/usr/bin/env bash
# workspace-cycle picks the next/previous workspace over the union of the
# workspaces that exist and the slots that carry a name. The whole point is the
# named-but-empty slot: Hyprland's own e+1 walks existing workspaces only, so it
# jumped straight over a titled workspace the moment its last window left.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/bin"

# hyprctl stub: WS describes the workspaces, ACTIVE the focused one, and every
# dispatch is appended to $DISPATCHED so we can assert what was asked for.
cat > "$test_dir/bin/hyprctl" <<'STUB'
#!/bin/bash
case "$*" in
  *"-j workspaces"*|*"workspaces -j"*) cat "$WS" ;;
  *"-j activeworkspace"*|*"activeworkspace -j"*) printf '{"id":%s}\n' "$ACTIVE" ;;
  dispatch*) printf '%s\n' "$*" >> "$DISPATCHED" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$test_dir/bin/hyprctl"
export PATH="$test_dir/bin:$PATH"
export WS="$test_dir/ws.json"
export DISPATCHED="$test_dir/dispatched"
export WORKSPACE_NAMES_FILE="$test_dir/names.json"

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; exit 1; }

# Returns the workspace the script asked Hyprland to focus.
went() {
  : > "$DISPATCHED"
  ACTIVE=$1 bash "$root/bin/workspace-cycle" "$2"
  sed -n 's/.*workspace = "\([0-9]*\)".*/\1/p' "$DISPATCHED" | tail -1
}

# 11 and 13 hold windows; 12 is empty but titled. This is the reported bug.
printf '%s\n' '[{"id":11,"name":"11","monitor":"eDP-1","windows":1},
                {"id":13,"name":"13","monitor":"eDP-1","windows":1}]' > "$WS"
printf '%s\n' '{"11":"Left","12":"NamedGap","13":"Right"}' > "$WORKSPACE_NAMES_FILE"
[[ $(went 11 next) == 12 ]] || fail "a named empty workspace must not be skipped, got $(went 11 next)"
pass "a named but empty workspace is still reachable"
[[ $(went 13 prev) == 12 ]] || fail "prev must reach the named empty workspace too"
pass "prev reaches the named empty workspace"

# An UNnamed empty slot stays out of the cycle: 12 has no title here, so the
# step from 11 must land on 13 exactly as Hyprland's e+1 always did.
printf '%s\n' '{"11":"Left","13":"Right"}' > "$WORKSPACE_NAMES_FILE"
[[ $(went 11 next) == 13 ]] || fail "an unnamed empty slot must not join the cycle"
pass "an unnamed empty slot is never visited"

# Both ends wrap.
printf '%s\n' '[{"id":1,"name":"1","monitor":"eDP-1","windows":1},
                {"id":2,"name":"2","monitor":"eDP-1","windows":1},
                {"id":3,"name":"3","monitor":"eDP-1","windows":1}]' > "$WS"
printf '%s\n' '{}' > "$WORKSPACE_NAMES_FILE"
[[ $(went 3 next) == 1 ]] || fail "next must wrap past the last workspace"
[[ $(went 1 prev) == 3 ]] || fail "prev must wrap past the first workspace"
pass "the cycle wraps at both ends"

# Metadata keys are not workspace numbers. If _auto or _config were read as
# slots the script would try to focus a workspace called "_config".
printf '%s\n' '{"1":"One","_auto":["1"],"_config":{"hold":750},
                "_plonk_archived_names":[{"name":"Old","workspace":"9"}]}' > "$WORKSPACE_NAMES_FILE"
[[ $(went 1 next) == 2 ]] || fail "metadata keys must not become cycle targets"
pass "_auto, _config and the archive are not treated as slots"

# A blank title reserves nothing.
printf '%s\n' '{"1":"One","5":"   "}' > "$WORKSPACE_NAMES_FILE"
[[ $(went 3 next) == 1 ]] || fail "a blank title must not join the cycle"
pass "a blank title does not join the cycle"

# A single workspace and nothing named: there is nowhere to go, and the script
# must not dispatch at all rather than focusing the workspace we are already on.
printf '%s\n' '[{"id":1,"name":"1","monitor":"eDP-1","windows":1}]' > "$WS"
printf '%s\n' '{}' > "$WORKSPACE_NAMES_FILE"
: > "$DISPATCHED"
ACTIVE=1 bash "$root/bin/workspace-cycle" next
[[ ! -s "$DISPATCHED" ]] || fail "a lone workspace must produce no dispatch, got: $(cat "$DISPATCHED")"
pass "a lone workspace produces no dispatch"

# A missing names file is not an error: fall back to existing workspaces.
printf '%s\n' '[{"id":1,"name":"1","monitor":"eDP-1","windows":1},
                {"id":2,"name":"2","monitor":"eDP-1","windows":1}]' > "$WS"
rm -f "$WORKSPACE_NAMES_FILE"
[[ $(went 1 next) == 2 ]] || fail "a missing names file must not break the cycle"
pass "a missing names file falls back to existing workspaces"

# Same for a symlinked names file, which the helper refuses to read.
ln -s /etc/passwd "$WORKSPACE_NAMES_FILE"
[[ $(went 1 next) == 2 ]] || fail "a symlinked names file must be ignored, not followed"
pass "a symlinked names file is ignored"
rm -f "$WORKSPACE_NAMES_FILE"

# Named workspaces (Hyprland's own, non-numeric ids) are left out.
printf '%s\n' '[{"id":1,"name":"1","monitor":"eDP-1","windows":1},
                {"id":2,"name":"special:magic","monitor":"eDP-1","windows":1},
                {"id":3,"name":"3","monitor":"eDP-1","windows":1}]' > "$WS"
printf '%s\n' '{}' > "$WORKSPACE_NAMES_FILE"
[[ $(went 1 next) == 3 ]] || fail "a non-numeric workspace must stay out of the cycle"
pass "non-numeric (special) workspaces stay out of the cycle"

# A bad direction is a usage error, not a silent no-op.
if bash "$root/bin/workspace-cycle" sideways 2>/dev/null; then
  fail "an unknown direction must exit non-zero"
fi
pass "an unknown direction is rejected"

echo "all tests passed"
