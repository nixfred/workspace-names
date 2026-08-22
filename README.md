# Workspace Names (Omarchy plugin)

Keep the plain workspace **numbers** in the Omarchy bar, but give each
workspace a **title**. Every time you switch workspaces a small pill slides in
under the numbers — `3 │ Code` — holds for under a second, then slides out.
Direction follows the switch (moving up slides in from the right, moving down
from the left). It never steals focus or clicks.

- Names live in `~/.config/omarchy/workspace-names.json` (`{"3": "Code"}`),
  watched live. Optional tuning: `"_config": {"hold": 900, "slide": 160,
  "travel": 48, "offsetX": 52, "offsetY": 6}` (ms / px).
- **Rename in the bar:** hover a workspace number → a chip with its name
  (or *Name…*) drops down; click the chip (or right-click the number) → inline
  editor right there. Enter saves, Esc cancels, empty clears. Left-click still
  focuses the workspace. The widget (`WorkspacesWidget.qml`) replaces
  `omarchy.workspaces` in `shell.json` and renders the numbers identically.
- **SUPER+SHIFT+R** opens that same inline editor for the current workspace
  (falls back to Omarchy's text prompt if the widget isn't in the bar). Or from a shell: `workspace-name Code`, `workspace-name
  --clear`, `workspace-name --list`, `workspace-name --peek`,
  `workspace-name -i 4 Mail`.
- Hyprland's real workspace names are untouched (plonk, `hl.dsp.focus` by id,
  etc. all keep working).

## Always-on title (v0.3.0)

The focused workspace's name lives permanently right after the workspace numbers in the left bar section — bold when named, a dim *Name…* when not. Click it to rename inline. Hidden on a vertical bar.

The slide-in pill that used to appear on every workspace switch is now **off by default** (it doubled the title). Bring it back with `{"_config": {"pill": true}}` in `~/.config/omarchy/workspace-names.json`.

## Install

```bash
omarchy plugin add https://github.com/nixfred/workspace-names.git --enable
```

Then:

1. **Bar widget** — in `~/.config/omarchy/shell.json`, replace `"omarchy.workspaces"` in
   `bar.layout.left` with `{"id": "nixfred.workspace-names"}` (it draws the numbers
   identically, plus the hover chip / inline editor).
2. **Keybind (optional)** — copy `bin/workspace-name` somewhere on your `PATH` and add to
   `~/.config/hypr/bindings.lua`:
   ```lua
   o.bind("SUPER + SHIFT + R", "Rename workspace", "workspace-name")
   ```
3. `omarchy-restart-shell` — new plugin QML is not hot-reloaded. (Wait ~20 s after
   the plugin files land before restarting; restarting immediately can crash quickshell.)

Requires `hyprctl` and `jq` for the CLI helper. Works with
[plonk](https://github.com/nixfred/plonk) and [Rift](https://github.com/nixfred/rift) —
Hyprland's real workspace names are never touched.

IPC: `omarchy-shell nixfred.workspace-names show|showId <n>|hide|name <n>|reload` (service),
`omarchy-shell nixfred.workspace-names.bar edit <n>|editCurrent` (bar widget).

## License

MIT — Fred Nix & Larry.
