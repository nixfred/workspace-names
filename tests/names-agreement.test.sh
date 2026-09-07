#!/usr/bin/env bash
# The QML and the shell must agree about what the names document says.
#
# Four things read ~/.config/omarchy/workspace-names.json: this plugin's QML,
# bin/workspace-name, bin/workspace-cycle, and Plonk. The shell readers share
# one jq predicate — a slot is a key like "5", a name is a non-blank STRING —
# and the QML side used to run String() over whatever it found, so {"2": 42}
# showed a workspace named "42" in the bar that Plonk would never carry and
# workspace-cycle would never stop on.
#
# Names.js is now the single JS statement of that rule. This test does not
# re-implement the shell rule to compare against: it walks the REAL
# bin/workspace-cycle over each document and diffs the cycle it produces
# against Names.slots(). If either side's idea of a name drifts, this fails.
# (The technique is borrowed from bjarneo/omarchy-workspace-layout, which runs
# its generated Lua through a real interpreter and diffs it against its model.)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir "$test_dir/bin"

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

# Only workspace 99 exists, so the cycle is exactly {99} + whatever the shell
# reader considers a named slot. Walking it from 99 enumerates that set.
printf '%s\n' '[{"id":99,"name":"99","monitor":"eDP-1","windows":1}]' > "$WS"

shell_slots() { # -> the named slots bin/workspace-cycle will stop on, ascending
  local at=99 seen="" guard=0 target
  while :; do
    : > "$DISPATCHED"
    ACTIVE=$at bash "$root/bin/workspace-cycle" next
    target=$(sed -n 's/.*workspace = "\([0-9]*\)".*/\1/p' "$DISPATCHED" | tail -1)
    [[ -n $target ]] || break            # a lone workspace dispatches nothing
    [[ $target != 99 ]] || break         # wrapped home; the walk is complete
    seen="$seen $target"
    at=$target
    guard=$((guard + 1))
    ((guard < 50)) || { echo "FAIL: cycle did not terminate"; exit 1; }
  done
  # An empty walk is a real answer (no named slots), not a failure.
  [[ -n ${seen// /} ]] || { printf ''; return 0; }
  tr ' ' '\n' <<<"$seen" | sed '/^$/d' | sort -n | tr '\n' ' ' | sed 's/ $//'
}

model_slots() { # -> Names.slots() for the same document, ascending
  node -e '
    const fs=require("fs"), vm=require("vm"), api={};
    vm.createContext(api);
    vm.runInContext(fs.readFileSync(process.argv[1],"utf8"), api);
    const doc=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
    console.log(api.slots(doc).join(" "));
  ' "$root/Names.js" "$WORKSPACE_NAMES_FILE"
}

check() { # document, description
  printf '%s\n' "$1" > "$WORKSPACE_NAMES_FILE"
  local from_shell from_model
  from_shell=$(shell_slots)
  from_model=$(model_slots)
  if [[ $from_shell != "$from_model" ]]; then
    echo "FAIL: $2"
    echo "  document:      $1"
    echo "  workspace-cycle: [$from_shell]"
    echo "  Names.js:        [$from_model]"
    exit 1
  fi
  printf 'PASS: %s  [%s]\n' "$2" "$from_model"
}

check '{"1":"Brave","2":"Imprint","5":"x.com"}' 'plain named slots'
check '{"2":42}'                                'a number is not a name'
check '{"2":true}'                              'a boolean is not a name'
check '{"2":["Arr"]}'                           'an array is not a name'
check '{"2":{"o":1}}'                           'an object is not a name'
check '{"2":null}'                              'null is not a name'
check '{"3":"   "}'                             'whitespace is not a name'
check '{"1":"Real","2":42,"3":"  ","4":true,"5":["A"],"6":{"o":1},"7":"Also"}' 'a mixed malformed document'
check '{"_auto":["1"],"_config":{"hold":750}}'  'metadata alone names nothing'
check '{"1":"One","_auto":["1"],"_config":{"hold":750},"_plonk_archived_names":[{"name":"Old","workspace":"9"}]}' 'metadata beside a real name'
check '{"0":"Zero","1":"One"}'                  'workspace 0 does not exist'
check '{"06":"Padded","6":"Six"}'               'a padded key is not workspace 6'
check '{}'                                      'an empty document'
check '{"1":"Brave","2":"Imprint","3":"Sonos","4":"Weather","5":"x.com","6":"Pi","_auto":["5","6"]}' 'the live document from this machine'


# --- the two QML readers must not drift apart again ------------------------
#
# Service.qml and WorkspacesWidget.qml each own a FileView on the same
# document. nameFor was deduplicated into Names.js, but the load paths beside
# it were not, and the widget kept the older one: strict nameFor said "" for
# {"2":42} while labelFor, handed the un-normalized document, still read "42" —
# one file contradicting itself. Cheap static checks that both went through
# Names.normalize and neither blanks its names on a failed read.
for qml in Service.qml WorkspacesWidget.qml; do
  grep -q 'Names.normalize(parsed)' "$root/$qml" \
    || { echo "FAIL: $qml does not normalize the document it loads"; exit 1; }
  if grep -q 'onLoadFailed: root.names = ({})' "$root/$qml"; then
    echo "FAIL: $qml still blanks every name when a read fails"; exit 1
  fi
  grep -q 'import "Names.js" as Names' "$root/$qml" \
    || { echo "FAIL: $qml does not import the shared rule"; exit 1; }
  if grep -q 'instanceof Array' "$root/$qml"; then
    echo "FAIL: $qml uses instanceof Array, which is wrong across realms"; exit 1
  fi
  printf 'PASS: %s loads the document through the shared rule\n' "$qml"
done

echo "all tests passed"
