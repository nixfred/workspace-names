#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/bin"
cat > "$test_dir/bin/hyprctl" <<'STUB'
#!/bin/bash
echo '{"id":3}'
STUB
cat > "$test_dir/bin/omarchy-shell" <<'STUB'
#!/bin/bash
if [[ $1 == -q ]]; then exit 0; fi
echo ok
STUB
cat > "$test_dir/bin/omarchy-menu-input" <<'STUB'
#!/bin/bash
touch "$TEST_FALLBACK"
exit 1
STUB
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH"
export WORKSPACE_NAMES_FILE="$test_dir/names.json"
export PLONK_STATE_DIR="$test_dir/plonk"
export TEST_FALLBACK="$test_dir/fallback"
bash "$root/bin/workspace-name"
[[ ! -e "$TEST_FALLBACK" ]] || { echo 'FAIL: inline editor fell through to a second prompt'; exit 1; }
bash "$root/bin/workspace-name" -i 3 -- 'Project "quoted" $(literal)'
jq -e '."3" == "Project \"quoted\" $(literal)"' "$WORKSPACE_NAMES_FILE" >/dev/null
bash "$root/bin/workspace-name" -i 3 --clear
jq -e 'has("3") | not' "$WORKSPACE_NAMES_FILE" >/dev/null

# Simulate a compact holding the same directory lock and updating another name.
(
  exec 9<"$PLONK_STATE_DIR"
  flock 9
  touch "$test_dir/locked"
  sleep .2
  printf '%s\n' '{"8":"Moved by Plonk"}' > "$WORKSPACE_NAMES_FILE"
) &
writer=$!
for ((n=0; n<100; n++)); do
  [[ ! -e "$test_dir/locked" ]] || break
  sleep .01
done
[[ -e "$test_dir/locked" ]]
bash "$root/bin/workspace-name" -i 3 -- 'My custom name'
wait "$writer"
jq -e '."3" == "My custom name" and ."8" == "Moved by Plonk"' "$WORKSPACE_NAMES_FILE" >/dev/null

# --if-unset claims an empty slot, never overwrites one that is taken, and
# never flashes the popup.
printf '%s\n' '{}' > "$WORKSPACE_NAMES_FILE"
bash "$root/bin/workspace-name" --if-unset -i 4 -- 'Auto Brave'
jq -e '."4" == "Auto Brave"' "$WORKSPACE_NAMES_FILE" >/dev/null
bash "$root/bin/workspace-name" --if-unset -i 4 -- 'Auto Something Else'
jq -e '."4" == "Auto Brave"' "$WORKSPACE_NAMES_FILE" >/dev/null
bash "$root/bin/workspace-name" -i 4 -- 'Mine'
bash "$root/bin/workspace-name" --if-unset -i 4 -- 'Auto Brave'
jq -e '."4" == "Mine"' "$WORKSPACE_NAMES_FILE" >/dev/null
# a blank suggestion writes nothing
bash "$root/bin/workspace-name" --if-unset -i 5 -- '   '
jq -e 'has("5") | not' "$WORKSPACE_NAMES_FILE" >/dev/null
# a whitespace-only stored name is not a name: the suggestion may claim it
printf '%s\n' '{"6":"  "}' > "$WORKSPACE_NAMES_FILE"
bash "$root/bin/workspace-name" --if-unset -i 6 -- 'Auto Files'
jq -e '."6" == "Auto Files"' "$WORKSPACE_NAMES_FILE" >/dev/null

echo 'Rename helper tests passed'
