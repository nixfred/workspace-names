import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Suggestions.js" as Suggestions

// Workspace Names — service plugin.
//
// A centered, non-interactive title flashes on workspace changes. Manual
// names take precedence over local window-title suggestions. The visible hold
// starts after the short entrance fade; the popup never takes keyboard focus.
//
// IPC (omarchy-shell nixfred.workspace-names <method>):
//   show          peek the pill for the focused workspace
//   showId <n>    peek the pill for workspace n
//   hide          dismiss now
//   name <n>      print the stored name for workspace n
//   reload        re-read the names file
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: "nixfred.workspace-names"
  readonly property string namesPath: Quickshell.env("HOME") + "/.config/omarchy/workspace-names.json"

  // id -> name, straight from the JSON file. Keys starting with "_" are config.
  property var names: ({})
  property var suggestions: ({})

  // hold: fully visible milliseconds; slide: fade milliseconds; topOffset: pixels.
  readonly property var cfg: (names && typeof names._config === "object" && names._config) ? names._config : ({})
  readonly property int holdMs: Number(cfg.hold) > 0 ? Number(cfg.hold) : 750
  readonly property int slideMs: Number(cfg.slide) > 0 ? Number(cfg.slide) : 80
  readonly property int topOffset: cfg.topOffset !== undefined ? Number(cfg.topOffset) : 96
  // Disable explicitly with _config.pill = false.
  readonly property bool pillEnabled: cfg.pill !== false

  property bool opened: false
  property int currentId: -1
  property int lastId: -1
  // +1: moved to a higher workspace (pill enters from the right, exits left).
  // -1: moved to a lower one (enters from the left, exits right).
  property int direction: 1
  property string label: ""
  property bool named: false

  signal presented()
  signal dismissed()

  function nameFor(id) {
    if (!names) return ""
    var n = names[String(id)]
    return (n === undefined || n === null) ? "" : String(n).trim()
  }

  function labelFor(id) {
    var n = Suggestions.label(root.names, root.suggestions, id)
    return n !== "" ? n : "Workspace " + id
  }

  function show(id) {
    if (!root.pillEnabled) return
    if (id === undefined || id === null || id < 1) {
      var fw = Hyprland.focusedWorkspace
      id = fw ? fw.id : -1
    }
    if (id < 1) return
    currentId = id
    named = Suggestions.label(root.names, root.suggestions, id) !== ""
    label = labelFor(id)
    opened = true
    hideTimer.stop()
    if (!clientsProbe.running) clientsProbe.running = true
    presented()
  }

  function hide() {
    if (!opened) return
    opened = false
    hideTimer.stop()
    dismissed()
  }

  function updateLabel() {
    if (currentId > 0) {
      named = Suggestions.label(root.names, root.suggestions, currentId) !== ""
      label = labelFor(currentId)
    }
  }
  onNamesChanged: updateLabel()
  onSuggestionsChanged: updateLabel()

  Process {
    id: clientsProbe
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.suggestions = Suggestions.fromClients(JSON.parse(this.text || "[]")) }
        catch (e) { console.warn("workspace-names: cannot read popup suggestions: " + e) }
      }
    }
  }
  Timer {
    id: probeDebounce
    interval: 120
    onTriggered: if (!clientsProbe.running) clientsProbe.running = true
  }

  // Hyprland's change_id (plonk renumbering) emits "changeworkspaceid>>old,new"
  // which Quickshell's workspace model does not apply — the old id lingers as
  // a ghost and the renumbered one reads as empty. Re-sync the model.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event && event.name ? String(event.name) : ""
      if (n === "changeworkspaceid" || n === "renameworkspace" || n === "moveworkspace") {
        root.resync()
      }
      if (/workspace|window/.test(n) && !probeDebounce.running) probeDebounce.start()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      var fw = Hyprland.focusedWorkspace
      if (!fw) return
      var id = fw.id
      if (id < 1) return  // special / scratchpad workspaces: leave alone
      if (root.lastId > 0 && id !== root.lastId) root.direction = id > root.lastId ? 1 : -1
      if (id === root.lastId) return
      root.lastId = id
      root.show(id)
    }
  }

  Component.onCompleted: {
    var fw = Hyprland.focusedWorkspace
    if (fw) root.lastId = fw.id
    clientsProbe.running = true
  }

  Timer {
    id: hideTimer
    interval: root.holdMs
    onTriggered: root.hide()
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

  function resync() {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
  }

  IpcHandler {
    target: root.pluginId
    function resync(): string { root.resync(); return "ok" }
    function ids(): string {
      var out = []
      var v = Hyprland.workspaces.values
      for (var i = 0; i < v.length; i++) out.push(v[i].id)
      return JSON.stringify(out)
    }
    function show(): string { root.show(-1); return "ok" }
    function showId(id: int): string { root.show(id); return "ok" }
    function hide(): string { root.hide(); return "ok" }
    function name(id: int): string { return root.nameFor(id) }
    function reload(): string { namesFile.reload(); return "ok" }
    function ping(): string { return "ok" }
    function state(): string { return JSON.stringify({ opened: root.opened, id: root.currentId, label: root.label, holdMs: root.holdMs, topOffset: root.topOffset, fadeMs: root.slideMs }) }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      // Only the output the focused workspace lives on gets the pill.
      readonly property bool onThisScreen: {
        var fw = Hyprland.focusedWorkspace
        if (!fw || !fw.monitor || !fw.monitor.name) return true
        return fw.monitor.name === modelData.name
      }

      property bool shown: false
      visible: shown && onThisScreen

      WlrLayershell.namespace: "omarchy-workspace-names"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      // Fixed-size full-screen surface (same trick as the OSD/notifications):
      // the pill animates inside it, the Wayland surface never resizes.
      anchors { top: true; bottom: true; left: true; right: true }
      // Purely visual — never eat a click.
      mask: Region {}

      Connections {
        target: root
        function onPresented() { win.present() }
        function onDismissed() { win.dismiss() }
      }

      function present() {
        exitAnim.stop()
        enterAnim.stop()
        win.shown = true
        pill.shift = 0
        pill.opacity = 0
        enterAnim.start()
      }

      function dismiss() {
        enterAnim.stop()
        exitAnim.start()
      }

      ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: pill; property: "shift"; to: 0; duration: root.slideMs; easing.type: Easing.OutCubic }
        NumberAnimation { target: pill; property: "opacity"; to: 1; duration: root.slideMs; easing.type: Easing.OutQuad }
        onFinished: if (root.opened && win.onThisScreen) hideTimer.restart()
      }

      ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: pill; property: "shift"; to: 0; duration: root.slideMs; easing.type: Easing.InCubic }
        NumberAnimation { target: pill; property: "opacity"; to: 0; duration: root.slideMs; easing.type: Easing.InQuad }
        onFinished: if (!root.opened) win.shown = false
      }

      Rectangle {
        id: pill
        property real shift: 0

        // Centered on the focused output, below the physical top edge.
        x: Math.round((win.width - width) / 2)
        y: root.topOffset
        width: row.implicitWidth + pad * 2
        height: Math.round(Style.font.title * 2.2)
        radius: Math.max(Style.cornerRadius, 4)
        color: Util.alpha(Color.popups.background, 0.96)
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border
        opacity: 0

        readonly property int pad: Style.space(12)

        Row {
          id: row
          anchors.centerIn: parent
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.currentId)
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            color: Color.accent
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: Style.font.title
            color: Util.alpha(Color.popups.text, 0.35)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: root.named
            font.italic: !root.named
            color: root.named ? Color.popups.text : Util.alpha(Color.popups.text, 0.6)
          }
        }
      }
    }
  }
}
