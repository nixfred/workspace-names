#!/usr/bin/env bash
# workspace-clients adds each terminal's foreground program and directory to
# `hyprctl clients -j`. Everything it reads is faked: hyprctl, ps, and /proc.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/bin" "$tmp/proc"
cat > "$tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_CLIENTS"
EOF
cat > "$tmp/bin/ps" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_PS"
EOF
chmod +x "$tmp/bin/hyprctl" "$tmp/bin/ps"
export FAKE_CLIENTS="$tmp/clients.json" FAKE_PS="$tmp/ps.txt"
export WORKSPACE_CLIENTS_HYPRCTL="$tmp/bin/hyprctl" WORKSPACE_CLIENTS_PS="$tmp/bin/ps" WORKSPACE_CLIENTS_PROC="$tmp/proc"

cwd() { mkdir -p "$tmp/proc/$1"; ln -s "$2" "$tmp/proc/$1/cwd"; }
run() { bash "$root/bin/workspace-clients"; }
field() { run | jq -r --argjson pid "$1" ".[] | select(.pid == \$pid) | $2"; }

printf '%s\n' '[
  {"pid": 100, "class": "foot", "title": "✳ Task", "workspace": {"id": 1}},
  {"pid": 200, "class": "foot", "title": "pi@gus:~", "workspace": {"id": 2}},
  {"pid": 300, "class": "brave-browser", "title": "X", "workspace": {"id": 3}},
  {"pid": 400, "class": "kitty", "title": "x", "workspace": {"id": 4}},
  {"pid": 500, "class": "foot", "title": "y", "workspace": {"id": 5}},
  {"pid": 600, "class": "foot", "title": "z", "workspace": {"id": 6}}
]' > "$FAKE_CLIENTS"

# 100: foot -> bash -> claude (which has its own children: tools, MCP servers)
# 200: foot -> bash, idle
# 300: brave -> zygote renderers, no shell
# 400: kitty -> zsh -> bash (a nested shell) -> nvim
# 500: foot -> bash -> node /usr/lib/pi/cli.js (an interpreter running a tool)
# 600: foot -> bash with an old background job and a newer foreground one
cat > "$FAKE_PS" <<'EOF'
  100     1 foot
  101   100 /usr/bin/bash
  102   101 claude --dangerously-skip-permissions
  103   102 node /home/pi/.mcp/server.js
  104   102 /usr/bin/bash -c sleep 5
  200     1 foot
  201   200 -bash
  300     1 /opt/brave-bin/brave
  301   300 /opt/brave-bin/brave --type=zygote
  400     1 kitty
  401   400 /usr/bin/zsh
  402   401 bash
  403   402 nvim notes.md
  500     1 foot
  501   500 bash
  502   501 node --no-warnings /usr/lib/pi/cli.js --model x
  600     1 foot
  601   600 bash
  602   601 sleep 9999
  610   601 htop
EOF
cwd 101 /home/pi
cwd 102 /home/pi/Projects/Larry
cwd 201 /home/pi/Projects/blip
cwd 403 /home/pi/notes
cwd 501 /home/pi
cwd 610 /tmp

[[ $(run | jq 'length') == 6 ]] || fail "every client must come back"
[[ $(field 100 .activity.command) == claude ]] || fail "the foreground program, not its children: got $(field 100 .activity.command)"
[[ $(field 100 .activity.cwd) == /home/pi/Projects/Larry ]] || fail "the program's own directory"
[[ $(field 100 .activity.home) == "$HOME" ]] || fail "home is reported"
[[ -n $(field 100 .activity.host) ]] || fail "host is reported"
[[ $(field 200 .activity.command) == "" ]] || fail "an idle shell has no command"
[[ $(field 200 .activity.cwd) == /home/pi/Projects/blip ]] || fail "an idle shell reports its directory"
[[ $(field 300 .activity) == null ]] || fail "a window with no shell has no activity"
[[ $(field 400 .activity.command) == nvim ]] || fail "nested shells are walked through: got $(field 400 .activity.command)"
[[ $(field 400 .activity.cwd) == /home/pi/notes ]] || fail "nested program's directory"
[[ $(field 500 .activity.command) == cli ]] || fail "an interpreter reports its script: got $(field 500 .activity.command)"
[[ $(field 500 .activity.cwd) == /home/pi ]] || fail "falls back to the shell's directory"
[[ $(field 600 .activity.command) == htop ]] || fail "the newest child is the foreground one: got $(field 600 .activity.command)"
[[ $(field 100 .title) == "✳ Task" ]] || fail "client fields pass through untouched"

# Hyprland unreachable: an empty array, exit 0.
printf 'not json' > "$FAKE_CLIENTS"
out=$(run); status=$?
[[ $status == 0 && $out == "[]" ]] || fail "unreachable Hyprland must print [] and exit 0, got '$out' ($status)"

# ps failing: clients still come back, with no activity.
printf '[{"pid": 100, "class": "foot", "title": "t", "workspace": {"id": 1}}]' > "$FAKE_CLIENTS"
export WORKSPACE_CLIENTS_PS=/nonexistent/ps
[[ $(run | jq -r '.[0].activity') == null ]] || fail "a missing ps must not lose the clients"
[[ $(run | jq -r '.[0].class') == foot ]] || fail "a missing ps must not lose the clients"

echo "workspace-clients tests passed"
