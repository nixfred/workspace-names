import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Suggestions.js" as Suggestions
import "Names.js" as Names
import "WorkspaceIds.js" as WorkspaceIds

// Workspace Names — bar widget (WorkspacesWidget.qml).
//
// Rounded rail and sliding focus capsule adapted from pi.workspaces.
// Keep the numbered buttons and Workspace Names interactions together:
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
    return Names.nameFor(names, id)
  }

  function labelFor(id) { return Suggestions.label(root.names, root.suggestions, id) }
  // Same lookup the service uses, so the Suggest button and the popup agree.
  function appNameFor(cls) {
    var entry = DesktopEntries.heuristicLookup(String(cls))
    return entry && entry.name ? String(entry.name) : ""
  }

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

    // Same rule as the service: a read that fails is not a document with no
    // names in it. Plonk rewrites this file on every compact, so a read landing
    // in that window used to blank every name in the bar until the next change.
    onLoadFailed: {
      if (root.namesLoaded) {
        console.warn("workspace-names: cannot read " + root.namesPath + "; keeping the names already loaded")
        return
      }
      root.names = ({})
      root.namesLoaded = true
    }
  }

  property bool namesLoaded: false

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        console.warn("workspace-names: " + root.namesPath + " is not a JSON object; keeping the names already loaded")
        return
      }
      // Normalize here too, not just in nameFor: labelFor hands this document
      // to Suggestions.label, which stringifies whatever it is given. Without
      // this the bar contradicted itself — the number drew un-named while the
      // label read "42".
      root.names = Names.normalize(parsed)
      root.namesLoaded = true
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
    return root.focusedId > 0 ? openEditor(root.focusedId) : false
  }

  IpcHandler {
    target: root.moduleName + ".bar"
    function edit(id: int): string { return root.openEditor(id) ? "ok" : "no such workspace button" }
    function editCurrent(): string { return root.editCurrentWorkspace() ? "ok" : "no focused workspace" }
    function map(): string { root.openMap(); return "ok" }
    function ping(): string { return "ok" }
    function labels(): string { return JSON.stringify({ manual: root.names, suggested: root.suggestions }) }
    function visibleIds(): string { return JSON.stringify(root.workspaceIds()) }
    function state(id: int): string {
      var b = root.buttons[String(id)]
      if (!b) return "no button"
      return JSON.stringify(b.debugState())
    }
  }

  // ---- workspace state --------------------------------------------------

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
          root.suggestions = Suggestions.fromClients(arr, root.appNameFor)
        } catch (e) {
          console.warn("workspace-names: bad hyprctl clients output: " + e)
        }
      }
    }
  }
  // Which workspace is focused, straight from the compositor. Quickshell's
  // model answers that question from the same state that ghosts renumbered
  // ids, so it is only a hint (see focusedId below).
  //
  // The probe is a startup and safety-net read: every switch after that is
  // announced by the compositor itself ("workspace"/"workspacev2", or
  // "focusedmonv2" when focus crosses monitors), and those events carry the
  // id Hyprland actually means. A probe that was already in flight when one of
  // those arrived is older than the event and must not overwrite it.
  property int focusEventSerial: 0
  Process {
    id: focusProbe
    property int startedAt: -1
    command: ["hyprctl", "activeworkspace", "-j"]
    onRunningChanged: if (running) startedAt = root.focusEventSerial
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var id = Number(JSON.parse(this.text || "{}").id)
          if (isFinite(id) && id > 0 && focusProbe.startedAt === root.focusEventSerial) root.compositorFocusedId = id
        } catch (e) {
          console.warn("workspace-names: bad hyprctl activeworkspace output: " + e)
        }
        root.refreshIds()
      }
    }
  }
  Timer { id: probeDebounce; interval: 120; onTriggered: { wsProbe.running = true; focusProbe.running = true } }
  Timer { id: clientsDebounce; interval: 140; onTriggered: clientsProbe.running = true }
  function probe() { probeDebounce.restart(); clientsDebounce.restart() }
  Component.onCompleted: probe()

  function eventParts(event, count) {
    try { if (event && event.parse) return event.parse(count) } catch (error) {}
    return String(event && event.data ? event.data : "").split(",")
  }
  function enterWorkspace(id) {
    var next = Number(id)
    if (!isFinite(next) || next < 1) return  // special / scratchpad: leave alone
    root.focusEventSerial++
    root.compositorFocusedId = next
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event && event.name ? String(event.name) : ""
      switch (n) {
      case "workspace": case "workspacev2":
        root.enterWorkspace(root.eventParts(event, 2)[0]); break
      case "focusedmonv2":
        root.enterWorkspace(root.eventParts(event, 2)[1]); break
      case "changeworkspaceid": case "renameworkspace": case "moveworkspace":
        // Quickshell does not apply these to its workspace model: without a
        // refresh the focused workspace stays a ghost id that is on no button,
        // and the focus capsule has nothing to sit on.
        if (n === "changeworkspaceid") {
          // Plonk renumbering the workspace you are standing on announces no
          // "workspace" event of its own, so carry the focus over by hand.
          var parts = root.eventParts(event, 2)
          if (Number(parts[0]) === root.compositorFocusedId) root.enterWorkspace(parts[1])
        }
        Hyprland.refreshWorkspaces()
        root.probe(); break
      case "createworkspace": case "destroyworkspace": case "openwindow":
      case "closewindow": case "movewindow": case "monitorremoved": case "monitoradded":
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
    return WorkspaceIds.visible(root.live, Hyprland.workspaces.values, root.focusedId)
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
  // The compositor is the only authority on which workspace is focused: the
  // id comes from its own switch events (see enterWorkspace), with a hyprctl
  // probe filling in at startup. Quickshell's model is consulted only until
  // the compositor has spoken. It used to be the primary source, and after a
  // renumber (plonk's change_id) it can carry a workspace under its OLD id —
  // the model does not apply that event — so with Brave on 3 renumbered to 2,
  // arriving on 2 highlighted 3, and SUPER+RIGHT looked as if it skipped a
  // workspace. Nothing re-read the truth until the next create or destroy.
  property int compositorFocusedId: -1
  readonly property int modelFocusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property int focusedId: root.compositorFocusedId > 0 ? root.compositorFocusedId : root.modelFocusedId
  onFocusedIdChanged: refreshIds()
  readonly property int focusedIndex: root.ids.indexOf(root.focusedId)
  readonly property color railForeground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color capsuleText: root.bar ? root.bar.themeContrastForeground : Color.background
  readonly property real slotExtent: Style.spaceReal(24)
  readonly property real capsuleThickness: Style.spaceReal(22)
  readonly property real targetStart: Math.max(0, root.focusedIndex) * root.slotExtent
  property real animatedStart: targetStart
  property real animatedEnd: targetStart + slotExtent

  Behavior on animatedStart {
    NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
  }
  Behavior on animatedEnd {
    NumberAnimation { duration: 380; easing.type: Easing.OutQuint }
  }
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

  // The rail and capsule sit behind the existing clickable/editor buttons.
  // Geometry follows the same slot width in horizontal and vertical bars.
  Item {
    anchors.fill: grid
    Rectangle {
      x: root.vertical ? (parent.width - width) / 2 : Style.spaceReal(2)
      y: root.vertical ? Style.spaceReal(2) : (parent.height - height) / 2
      width: root.vertical ? root.capsuleThickness : Math.max(0, parent.width - Style.spaceReal(4))
      height: root.vertical ? Math.max(0, parent.height - Style.spaceReal(4)) : root.capsuleThickness
      radius: Math.min(width, height) / 2
      color: Util.alpha(root.railForeground, 0.055)
      border.width: Style.space(1)
      border.color: Util.alpha(root.railForeground, 0.1)
    }
    Rectangle {
      visible: root.focusedIndex >= 0
      x: root.vertical ? (parent.width - width) / 2 : root.animatedStart
      y: root.vertical ? root.animatedStart : (parent.height - height) / 2
      width: root.vertical ? root.capsuleThickness : Math.max(1, root.animatedEnd - root.animatedStart)
      height: root.vertical ? Math.max(1, root.animatedEnd - root.animatedStart) : root.capsuleThickness
      radius: Math.min(width, height) / 2
      color: Color.accent
      border.width: Style.space(1)
      border.color: Util.alpha(root.railForeground, 0.52)
      Behavior on color { ColorAnimation { duration: 180 } }
    }
  }

  GridLayout {
    id: grid
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: button
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property int liveWin: root.liveWindows(modelData)
        readonly property bool occupied: liveWin >= 0 ? liveWin > 0 : (workspace !== null && workspace.toplevels.values.length > 0)
        // root.focusedId, not the model directly: the number under the capsule
        // and the capsule itself must never disagree.
        readonly property bool focused: root.focusedId === modelData
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
        text: modelData === 10 ? "0" : String(modelData)
        labelVisible: false
        opacity: 1
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : root.slotExtent
        fixedHeight: root.vertical ? root.slotExtent : root.barSize
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(21)
          height: width
          radius: width / 2
          color: button.tooltipHovered && !button.focused
            ? Util.alpha(root.railForeground, 0.11) : "transparent"
          Behavior on color { ColorAnimation { duration: 130 } }
        }
        Text {
          anchors.centerIn: parent
          text: button.text
          textFormat: Text.PlainText
          color: button.focused ? root.capsuleText : root.railForeground
          opacity: button.focused ? 1 : (button.occupied ? 0.9 : 0.45)
          font.family: button.fontFamily
          font.pixelSize: button.focused ? Style.font.subtitle : Style.font.body
          font.bold: button.focused
          Behavior on color { ColorAnimation { duration: 160 } }
          Behavior on opacity { NumberAnimation { duration: 160 } }
          Behavior on font.pixelSize { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
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
