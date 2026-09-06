# Workspace Names

An Omarchy plugin that keeps workspace numbers in the bar and flashes the
current workspace name in a centered popup. Names can be automatic or yours.

## Everyday workflow

1. Switch to the workspace and press **Super+Shift+R**, or right-click its number.
2. Type a short project name and press **Enter** or **Save**.
3. Use **Suggest** to start from its current apps and window titles.
4. Clear the field and save to return to automatic naming. **Esc** or **Cancel**
   leaves the saved name alone.

Manual names take precedence. Automatic suggestions use local window metadata,
update as the contents change, and never write over your names.

## Popup

The bar contains numbers only. Switching workspaces shows the name centered
near the top of the focused screen, with a **750 ms** fully visible hold and
brief **80 ms** fades. It passes clicks through and never takes keyboard focus.

Names and popup settings live in `~/.config/omarchy/workspace-names.json`:

```json
{
  "_config": { "pill": true, "hold": 750, "slide": 80, "topOffset": 139 },
  "2": "Website redesign",
  "4": "Music"
}
```

`topOffset` is measured in logical pixels from the screen's top edge. For a
1920×1200 screen reporting 220 mm height at scale 1, **139 pixels is about one
inch**. Adjust it for your display; the default is 96. Set `pill` to false to
hide the popup. The file is watched for changes.

## Plonk and custom names

- Occupied workspaces carry their manually saved names when Plonk renumbers
  them. Automatic labels follow their windows without a stored ID mapping.
- With the custom-name protection update in Plonk, an empty slot with a saved
  name is reserved. Incoming workspaces skip it, so its custom name survives.
  Clear the name when that reserved slot is no longer useful.
- The rename helper shares Plonk's directory lock, so simultaneous saves and
  compaction do not overwrite each other's JSON updates. A busy or failed save
  leaves the editor open with an error.
- Plonk snapshots the names file before remapping it, retaining its last 20
  backups under `~/.local/state/plonk/names-backups/`.

Hyprland's actual workspace names remain numeric. The widget refreshes from
`hyprctl` on renumber events, avoiding stale Quickshell workspace IDs.

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
