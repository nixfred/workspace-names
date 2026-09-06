import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Suggestions.js" as Suggestions

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
  readonly property string renameTool: decodeURIComponent(String(Qt.resolvedUrl("bin/workspace-name")).replace(/^file:\/\//, ""))
  property var names: ({})
  property var suggestions: ({})
  property var liveApps: ({}) // workspace id -> sorted, de-duplicated app classes
  property bool mapOpen: false
  property int mapCursor: 0

  // PopoutCoordinator calls owner.close() when another panel takes focus.
  function close() { root.mapOpen = false }
  function closeForPopoutSwitch() { root.close() }

  function nameFor(id) {
    if (!names) return ""
    var n = names[String(id)]
    return (n === undefined || n === null) ? "" : String(n).trim()
  }

  function labelFor(id) { return Suggestions.label(root.names, root.suggestions, id) }

  function appsFor(id) {
    var apps = root.liveApps[String(id)]
    return apps && apps.length ? apps : []
  }

  function appSummary(id) {
    var apps = root.appsFor(id)
    if (!apps.length) return root.liveWindows(id) > 0 ? root.liveWindows(id) + " windows" : "Empty"
    var shown = apps.slice(0, 3).join(" · ")
    return apps.length > 3 ? shown + "  +" + (apps.length - 3) : shown
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
    function map(): string { root.openMap(); return "ok" }
    function ping(): string { return "ok" }
    function labels(): string { return JSON.stringify({ manual: root.names, suggested: root.suggestions }) }
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
  Process {
    id: clientsProbe
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var arr = JSON.parse(this.text || "[]")
          var byWorkspace = {}
          for (var i = 0; i < arr.length; i++) {
            var client = arr[i] || {}
            var id = client.workspace ? Number(client.workspace.id) : 0
            if (id < 1 || id > 10) continue
            var label = String(client.class || client.initialClass || "App").trim()
            if (!label) label = "App"
            var key = String(id)
            if (!byWorkspace[key]) byWorkspace[key] = []
            if (byWorkspace[key].indexOf(label) === -1) byWorkspace[key].push(label)
          }
          for (var key in byWorkspace) byWorkspace[key].sort()
          root.liveApps = byWorkspace
          root.suggestions = Suggestions.fromClients(arr)
        } catch (e) {
          console.warn("workspace-names: bad hyprctl clients output: " + e)
        }
      }
    }
  }
  Timer { id: probeDebounce; interval: 120; onTriggered: wsProbe.running = true }
  Timer { id: clientsDebounce; interval: 140; onTriggered: clientsProbe.running = true }
  function probe() { probeDebounce.restart(); clientsDebounce.restart() }
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
      case "windowtitle": case "windowtitlev2": case "activewindow":
        if (!clientsDebounce.running) clientsDebounce.start()
        break
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

  function openMap() {
    var list = root.workspaceIds()
    var focused = root.focusedId
    root.mapCursor = Math.max(0, list.indexOf(focused))
    root.mapOpen = true
  }
  function closeMap() { root.mapOpen = false }
  function moveMapCursor(delta) {
    var count = root.workspaceIds().length
    if (!count) return
    root.mapCursor = (root.mapCursor + delta + count) % count
  }
  function activateMapCursor() {
    var list = root.workspaceIds()
    if (root.mapCursor < 0 || root.mapCursor >= list.length) return
    root.closeMap()
    root.focusWorkspace(list[root.mapCursor])
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // ---- persistent title slot ----------------------------------------------
  // The focused workspace's name always lives right after the numbers (bold
  // when named, dim "Name…" when not). Click it to rename inline. Hidden on a
  // vertical bar, where there is no room beside the column.
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property string focusedName: focusedId > 0 ? root.labelFor(focusedId) : ""
  readonly property bool showTitle: false
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
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.openMap()
        else if (root.focusedId > 0) root.openEditor(root.focusedId)
      }
    }

    KeyboardPanel {
      id: workspaceMap
      anchorItem: titleSlot
      bar: root.bar
      owner: root
      open: root.mapOpen && root.bar !== null
      focusTarget: mapKeys
      padding: Style.space(10)
      contentWidth: Style.space(390)
      contentHeight: workspaceMap.fittedContentHeight(mapColumn.implicitHeight)
      onOpenChanged: if (!open && root.mapOpen) root.mapOpen = false

      Item {
        id: mapKeys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.closeMap()
        Keys.onUpPressed: root.moveMapCursor(-1)
        Keys.onDownPressed: root.moveMapCursor(1)
        Keys.onReturnPressed: root.activateMapCursor()
        Keys.onEnterPressed: root.activateMapCursor()

        ColumnLayout {
          id: mapColumn
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(4)

          Text {
            text: "Workspace Map"
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            color: Color.popups.text
          }
          Text {
            text: "↑↓ select · Enter switch · Right-click rename · Esc close"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Util.alpha(Color.popups.text, 0.58)
          }

          Repeater {
            model: root.workspaceIds()
            Rectangle {
              required property int modelData
              required property int index
              Layout.fillWidth: true
              implicitHeight: Style.space(42)
              radius: Math.max(4, Style.cornerRadius)
              color: index === root.mapCursor ? Util.alpha(Color.accent, 0.18) : "transparent"
              border.width: modelData === root.focusedId ? 1 : 0
              border.color: Color.accent

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)
                Text {
                  text: String(modelData === 10 ? 0 : modelData)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  color: Color.accent
                  Layout.preferredWidth: Style.space(18)
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  Text {
                    Layout.fillWidth: true
                    text: root.labelFor(modelData) || "Workspace " + modelData
                    elide: Text.ElideRight
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: root.nameFor(modelData) !== ""
                    color: Color.popups.text
                  }
                  Text {
                    Layout.fillWidth: true
                    text: root.appSummary(modelData)
                    elide: Text.ElideRight
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Util.alpha(Color.popups.text, 0.56)
                  }
                }
                Text {
                  text: root.liveWindows(modelData) > 0 ? String(root.liveWindows(modelData)) : ""
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Util.alpha(Color.popups.text, 0.65)
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: root.mapCursor = index
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    var id = modelData
                    root.closeMap()
                    Qt.callLater(function() { root.openEditor(id) })
                  } else { root.mapCursor = index; root.activateMapCursor() }
                }
              }
            }
          }
        }
      }
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
        readonly property string displayName: root.labelFor(modelData)
        readonly property string suggestedName: root.suggestions[String(modelData)] || ""
        readonly property bool named: wsName !== ""

        property bool chipOpen: false
        property bool editing: false
        property string saveError: ""
        Component.onCompleted: root.registerButton(modelData, button)
        Component.onDestruction: if (root) root.unregisterButton(modelData, button)

        // KeyboardPanel.close() / PopupCard.close() and the bar's popout
        // coordinator call `owner.close()` when one exists — and assign
        // `open = false` directly when it doesn't, which would silently break
        // the `open: button.editing` bindings below for good. So we own it.
        function close() { chipGrace.stop(); button.chipOpen = false; button.editing = false }
        function closeForPopoutSwitch() { button.close() }
        function debugState() {
          return {
            id: modelData, chipOpen: chipOpen, editing: editing, hovered: tooltipHovered,
            draft: editField.text, saved: wsName, suggested: suggestedName, saveError: saveError,
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
              text: button.displayName || "Name…"
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
          button.saveError = ""
          editField.text = button.wsName || button.suggestedName
          button.editing = true
          editField.selectAll()
        }
        function commitEdit() {
          if (!button.editing || saveProcess.running) return
          var v = String(editField.text).trim()
          button.saveError = ""
          saveProcess.command = v === ""
            ? [root.renameTool, "-i", String(modelData), "--clear"]
            : [root.renameTool, "-i", String(modelData), "--", v]
          saveProcess.running = true
        }
        function cancelEdit() { button.editing = false }

        Process {
          id: saveProcess
          stderr: StdioCollector { }
          onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
              namesFile.reload()
              button.editing = false
            } else button.saveError = "Couldn't save. Try again."
          }
        }

        KeyboardPanel {
          id: editor
          anchorItem: button
          bar: root.bar
          owner: button
          open: button.editing && root.bar !== null
          focusTarget: editField
          padding: Style.space(8)
          contentWidth: Style.space(350)
          contentHeight: editor.fittedContentHeight(editColumn.implicitHeight)
          // Belt and braces: if anything else ever forces the panel shut,
          // fall back to a consistent closed state instead of a stuck one.
          onOpenChanged: if (!open && button.editing) button.editing = false

          ColumnLayout {
            id: editColumn
            anchors.fill: parent
            spacing: Style.space(8)

            Text {
              text: "Name workspace " + button.modelData
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
            Text {
              Layout.fillWidth: true
              text: button.saveError || "Empty name uses an automatic label from window titles."
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: button.saveError ? Color.accent : Util.alpha(Color.popups.text, 0.65)
            }
            RowLayout {
              Layout.fillWidth: true
              Button {
                text: "Suggest"
                enabled: button.suggestedName !== "" && !saveProcess.running
                onClicked: { editField.text = button.suggestedName; editField.forceActiveFocus(); editField.selectAll() }
              }
              Item { Layout.fillWidth: true }
              Button { text: "Cancel"; onClicked: button.cancelEdit() }
              Button {
                text: saveProcess.running ? "Saving…" : "Save"
                enabled: !saveProcess.running
                bordered: true
                onClicked: button.commitEdit()
              }
            }
          }
        }
      }
    }
  }
}
