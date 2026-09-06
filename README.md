# Workspace Names

An Omarchy plugin that keeps workspace numbers in the bar and flashes the
current workspace name in a centered popup. Names can be automatic or yours.

The numbers share a rounded rail with an animated accent capsule around the
active number, adapted from the Kinetic Workspace Strip. This styling is part
of Workspace Names itself; it does not require a second workspace widget.

## Everyday workflow

1. Switch to the workspace and press **Super+Shift+R**, or right-click its number.
2. Type a short project name and press **Enter** or **Save**.
3. Use **Suggest** to start from its current apps and window titles.
4. Clear the field and save to return to automatic naming. **Esc** or **Cancel**
   leaves the saved name alone.

Manual names take precedence. Automatic suggestions use local window metadata
and never write over a name you typed.

**A workspace names itself.** Give a workspace its first window and, once the
title settles (about a second), its suggestion is written to the names file as
a real name — bold in the popup, carried by Plonk, yours to change. Renaming or
clearing it is always the last word: clear a name and the next suggestion is
accepted in its place. Set `"autoName": false` in `_config` to keep suggestions
display-only.

## Popup

The bar contains numbers only. Switching workspaces shows the name centered
near the top of the focused screen, with a **750 ms** fully visible hold and
brief **80 ms** fades. It passes clicks through and never takes keyboard focus.

Names and popup settings live in `~/.config/omarchy/workspace-names.json`:

```json
{
  "_config": { "pill": true, "hold": 750, "slide": 80, "topOffset": 139, "autoName": true },
  "2": "Website redesign",
  "4": "Music"
}
```

`topOffset` is measured in logical pixels from the screen's top edge. For a
1920×1200 screen reporting 220 mm height at scale 1, **139 pixels is about one
inch**. Adjust it for your display; the default is 96. Set `pill` to false to
hide the popup. The file is watched for changes.

## Plonk and custom names

- Occupied workspaces carry their saved names when Plonk renumbers them.
- A name follows its windows. Move the last window off a named workspace
  (**Super+Shift+*number***) and Plonk 1.2.0+ moves the name to wherever that
  window landed, unless that workspace already has a name of its own. Closing
  the window moves nothing.
- Plonk reserves empty named slots by default. Its `empty_names=archive`
  option releases vanished slots while preserving their names in the names
  file's `_plonk_archived_names` array.
- The rename helper shares Plonk's directory lock, so simultaneous saves and
  compaction do not overwrite each other's JSON updates. A busy or failed save
  leaves the editor open with an error.
- Plonk snapshots the names file before remapping it, retaining its last 20
  backups under `~/.local/state/plonk/names-backups/`.

Hyprland's actual workspace names remain numeric. The widget refreshes from
`hyprctl` on renumber events, avoiding stale Quickshell workspace IDs — for the
focused workspace too, so the rail's highlight still lands on the right number
after a workspace is created and renumbered underneath it.

## Install

```bash
omarchy plugin add https://github.com/nixfred/workspace-names.git --enable
```

Replace the existing workspace widget entry in `bar.layout.left` in
`~/.config/omarchy/shell.json` with `{"id": "nixfred.workspace-names"}`.
Copy `bin/workspace-name` to a directory on your `PATH`. For the shortcut, add
to `~/.config/hypr/bindings.lua` after checking it is available:

```lua
o.bind("SUPER + SHIFT + R", "Rename workspace", "workspace-name")
```

Run `hyprctl reload` and `hyprctl configerrors`. A shell restart may be needed
for new plugin modules: `omarchy restart shell`.

Requires Omarchy Quattro, Hyprland, `hyprctl`, `jq`, and `flock`.
The widget uses its bundled helper when saving; the PATH copy serves shortcuts
and terminal use. For development, the installed plugin directory can be a
symlink to this checkout.

## Workspace Map and commands

The map lists workspace labels, occupancy, and app identities. Use arrow keys
and Enter or click to switch; right-click a row to rename; Esc closes.

```bash
omarchy-shell nixfred.workspace-names.bar map
workspace-name "Website redesign"
workspace-name -i 4 Music
workspace-name --clear
workspace-name --list
workspace-name --peek
```

`workspace-name` with no arguments opens the inline editor, falling back to an
Omarchy prompt only if the editor is unavailable.

## Checks

```bash
node tests/suggestions.test.js
bash tests/rename-helper.test.sh
omarchy plugin validate .
```

Tests cover local suggestions, manual precedence, renumbering, the inline
editor fallback, quoting, and concurrent name writes using temporary state.

## License

MIT — Fred Nix & Larry.
# Workspace visibility

The bar shows workspaces that currently exist, including an empty workspace
you are using. It does not force buttons 1–5 or show a vanished workspace just
because a saved title remains. Plonk can release vanished named slots with
`empty_names=archive` in `~/.config/plonk/config`; archived titles remain in
`_plonk_archived_names` in the workspace names file.
