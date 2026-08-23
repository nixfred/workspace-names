import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspace Names — bar widget (WorkspacesWidget.qml).
//
// A drop-in for the stock `omarchy.workspaces` widget: the numbers render
// exactly the same way (same WidgetButton, same glyph, same sizing), plus:
//   hover a number   → a small chip slides out under it with the workspace's
//                      current name (or "Name…" when unnamed); it stays while
//                      the pointer is on the number or the chip
//   click the chip   → inline editor (Enter saves, Esc cancels, empty clears)
//   right-click      → open the editor directly
//   left-click       → focus the workspace, as before
// Names are written through bin/workspace-name so the JSON file stays the
// single source of truth; the service picks the change up and flashes the
// slide-in title.
BarWidget {
  id: root
  moduleName: "nixfred.workspace-names"

  readonly property string home: Quickshell.env("HOME")
  readonly property string namesPath: home + "/.config/omarchy/workspace-names.json"
  readonly property string renameTool: home + "/bin/workspace-name"
  property var names: ({})

  function nameFor(id) {
    if (!names) return ""
    var n = names[String(id)]
    return (n === undefined || n === null) ? "" : String(n).trim()
  }

  FileView {
    id: namesFile
    path: root.namesPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.names = ({})
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.names = (parsed && typeof parsed === "object") ? parsed : ({})
    } catch (e) {
      console.warn("workspace-names: ignoring bad JSON at " + root.namesPath + ": " + e)
    }
  }

  function saveName(id, name) {
    if (!root.bar) return
    var trimmed = String(name || "").trim()
    var cmd = Util.shellQuote(root.renameTool) + " -i " + id
    cmd += trimmed === "" ? " --clear" : " " + Util.shellQuote(trimmed)
    root.bar.run(cmd)
  }

  // ---- IPC: omarchy-shell nixfred.workspace-names.bar <method> -------------
  // edit(n) / editCurrent() open the inline editor under workspace n (the
  // focused one for editCurrent) — this is what SUPER+SHIFT+R drives.
  property var buttons: ({})
  function registerButton(id, item) { var b = {}; for (var k in buttons) b[k] = buttons[k]; b[String(id)] = item; buttons = b }
  function unregisterButton(id, item) {
    if (buttons[String(id)] !== item) return
    var b = {}; for (var k in buttons) if (k !== String(id)) b[k] = buttons[k]; buttons = b
  }
  function openEditor(id) {
    var b = buttons[String(id)]
    if (!b) return false
    b.beginEdit()
    return true
  }
  function editCurrentWorkspace() {
    var fw = Hyprland.focusedWorkspace
    return fw ? openEditor(fw.id) : false
  }

  IpcHandler {
    target: root.moduleName + ".bar"
    function edit(id: int): string { return root.openEditor(id) ? "ok" : "no such workspace button" }
    function editCurrent(): string { return root.editCurrentWorkspace() ? "ok" : "no focused workspace" }
    function ping(): string { return "ok" }
    function state(id: int): string {
      var b = root.buttons[String(id)]
      if (!b) return "no button"
      return JSON.stringify(b.debugState())
    }
  }

  // ---- stock workspace row (kept byte-for-byte in behaviour) --------------

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // ---- live truth from hyprctl ------------------------------------------
  // Quickshell's Hyprland.workspaces model does not apply Hyprland's
  // "changeworkspaceid" event (plonk renumbering), so old ids linger as
  // ghosts and renumbered ones read as empty. We therefore take the id list
  // and occupancy from `hyprctl workspaces -j` (re-probed on every workspace
  // event, debounced) and only use the model for focus and click targets.
  property var live: null  // { "3": windows, ... } or null until first probe

  Process {
    id: wsProbe
    command: ["hyprctl", "workspaces", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var arr = JSON.parse(this.text || "[]")
          var m = {}
          for (var i = 0; i < arr.length; i++) m[String(arr[i].id)] = Number(arr[i].windows) || 0
          root.live = m
        } catch (e) {
          console.warn("workspace-names: bad hyprctl workspaces output: " + e)
        }
        root.refreshIds()
      }
    }
  }
  Timer { id: probeDebounce; interval: 120; onTriggered: wsProbe.running = true }
  function probe() { probeDebounce.restart() }
  Component.onCompleted: probe()
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event && event.name ? String(event.name) : ""
      switch (n) {
      case "changeworkspaceid": case "createworkspace": case "destroyworkspace":
      case "moveworkspace": case "renameworkspace": case "openwindow": case "closewindow":
      case "movewindow": case "monitorremoved": case "monitoradded":
        root.probe(); break
      }
    }
  }

  function liveWindows(id) {
    if (!root.live) return -1
    var w = root.live[String(id)]
    return w === undefined ? 0 : w
  }

  function computeWorkspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var fw = Hyprland.focusedWorkspace
    if (root.live) {
      for (var k in root.live) {
        var id = Number(k)
        if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
      }
    } else {
      var values = Hyprland.workspaces.values
      for (var i = 0; i < values.length; i++) {
        var vid = values[i].id
        if (vid > 0 && vid <= 10 && ids.indexOf(vid) === -1) ids.push(vid)
      }
    }
    if (fw && fw.id > 0 && fw.id <= 10 && ids.indexOf(fw.id) === -1) ids.push(fw.id)
    // Titled slots are anchors (plonk never moves them): keep them visible
    // even while empty so you can always jump back to "Browser" on 4.
    if (root.names) {
      for (var key in root.names) {
        var tid = Number(key)
        if (key.charAt(0) !== "_" && tid > 0 && tid <= 10 && ids.indexOf(tid) === -1) ids.push(tid)
      }
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }
  onNamesChanged: refreshIds()

  // The stock widget binds the Repeater straight to computeWorkspaceIds(),
  // which hands back a fresh array on every re-evaluation and makes the
  // Repeater tear down and rebuild every button. Stateless buttons don't
  // care; ours carry an open chip / editor, so only publish a new array when
  // the ids really changed.
  property var ids: computeWorkspaceIds()
  function workspaceIds() { return ids }
  function refreshIds() {
    var next = computeWorkspaceIds()
    if (JSON.stringify(next) !== JSON.stringify(ids)) ids = next
  }
  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.refreshIds() }
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // ---- persistent title slot ----------------------------------------------
  // The focused workspace's name always lives right after the numbers (bold
  // when named, dim "Name…" when not). Click it to rename inline. Hidden on a
  // vertical bar, where there is no room beside the column.
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string focusedName: focusedId > 0 ? root.nameFor(focusedId) : ""
  readonly property bool showTitle: !root.vertical
  readonly property real titleMinWidth: Style.space(48)
  readonly property real titleMaxWidth: Style.space(180)
  readonly property real titleGap: Style.space(6)

  implicitWidth: grid.implicitWidth + (showTitle ? titleGap + titleSlot.width : 0) + trailingGap
  implicitHeight: grid.implicitHeight

  Item {
    id: titleSlot
    visible: root.showTitle
    anchors.left: grid.right
    anchors.leftMargin: root.titleGap
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: root.showTitle ? Math.max(root.titleMinWidth, Math.min(titleLabel.implicitWidth, root.titleMaxWidth)) : 0

    Text {
      id: titleLabel
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      width: Math.min(implicitWidth, root.titleMaxWidth)
      elide: Text.ElideRight
      text: root.focusedName !== "" ? root.focusedName : "Name…"
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: root.focusedName !== ""
      font.italic: root.focusedName === ""
      color: {
        var fg = root.bar ? root.bar.barForeground : Color.foreground
        if (titleMouse.containsMouse) return Style.hoverStateColor(fg, Color.accent)
        return root.focusedName !== "" ? fg : Util.alpha(fg, 0.55)
      }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    MouseArea {
      id: titleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.IBeamCursor
      onClicked: if (root.focusedId > 0) root.openEditor(root.focusedId)
    }
  }

  GridLayout {
    id: grid
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: button
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property int liveWin: root.liveWindows(modelData)
        readonly property bool occupied: liveWin >= 0 ? liveWin > 0 : (workspace !== null && workspace.toplevels.values.length > 0)
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property string wsName: root.nameFor(modelData)
        readonly property bool named: wsName !== ""

        property bool chipOpen: false
        property bool editing: false
        Component.onCompleted: root.registerButton(modelData, button)
        Component.onDestruction: root.unregisterButton(modelData, button)

        // KeyboardPanel.close() / PopupCard.close() and the bar's popout
        // coordinator call `owner.close()` when one exists — and assign
        // `open = false` directly when it doesn't, which would silently break
        // the `open: button.editing` bindings below for good. So we own it.
        function close() { chipGrace.stop(); button.chipOpen = false; button.editing = false }
        function closeForPopoutSwitch() { button.close() }
        function debugState() {
          return {
            id: modelData, chipOpen: chipOpen, editing: editing, hovered: tooltipHovered,
            chip: { open: chip.open, visible: chip.visible, containsMouse: chip.containsMouse },
            editor: { open: editor.open, visible: editor.visible, primed: editor.focusPrimed, switching: editor.popoutSwitching },
            activePopout: root.bar && root.bar.activePopout ? (root.bar.activePopout.modelData !== undefined ? "button" + root.bar.activePopout.modelData : "other") : "none"
          }
        }

        bar: root.bar
        text: focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function(mouseButton) {
          if (mouseButton === Qt.RightButton) button.beginEdit()
          else root.focusWorkspace(modelData)
        }

        // ---- hover chip -------------------------------------------------
        function syncChip() {
          var want = button.tooltipHovered || chip.containsMouse
          if (want) { chipGrace.stop(); button.chipOpen = true }
          else chipGrace.restart()
        }
        onTooltipHoveredChanged: syncChip()
        Connections {
          target: chip
          function onContainsMouseChanged() { button.syncChip() }
        }
        Timer {
          id: chipGrace
          interval: 240
          onTriggered: if (!(button.tooltipHovered || chip.containsMouse)) button.chipOpen = false
        }

        PopupCard {
          id: chip
          anchorItem: button
          bar: root.bar
          owner: button
          triggerMode: "hover"
          open: button.chipOpen && !button.editing && root.bar !== null
          padding: Style.space(6)
          margin: Style.space(3)
          contentWidth: Math.round(chipLabel.implicitWidth + chip.padding * 2 + Style.space(12))
          contentHeight: chip.fittedContentHeight(chipLabel.implicitHeight + Style.space(2))

          Item {
            anchors.fill: parent
            Text {
              id: chipLabel
              anchors.centerIn: parent
              text: button.named ? button.wsName : "Name…"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: button.named
              font.italic: !button.named
              color: button.named ? Color.popups.text : Util.alpha(Color.popups.text, 0.6)
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.IBeamCursor
              onClicked: button.beginEdit()
            }
          }
        }

        // ---- inline editor ----------------------------------------------
        function beginEdit() {
          button.chipOpen = false
          editField.text = button.wsName
          button.editing = true
          editField.selectAll()
        }
        function commitEdit() {
          if (!button.editing) return
          var v = editField.text
          button.editing = false
          if (String(v).trim() !== button.wsName) root.saveName(modelData, v)
        }
        function cancelEdit() { button.editing = false }

        KeyboardPanel {
          id: editor
          anchorItem: button
          bar: root.bar
          owner: button
          open: button.editing && root.bar !== null
          focusTarget: editField
          padding: Style.space(8)
          contentWidth: Style.space(230)
          contentHeight: editor.fittedContentHeight(editRow.implicitHeight)
          // Belt and braces: if anything else ever forces the panel shut,
          // fall back to a consistent closed state instead of a stuck one.
          onOpenChanged: if (!open && button.editing) button.editing = false

          RowLayout {
            id: editRow
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              text: String(button.modelData === 10 ? 0 : button.modelData)
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: Color.accent
              Layout.alignment: Qt.AlignVCenter
            }
            TextField {
              id: editField
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              placeholderText: "Workspace name"
              verticalPadding: Style.space(4)
              onAccepted: button.commitEdit()
              Keys.onEscapePressed: button.cancelEdit()
            }
          }
        }
      }
    }
  }
}
