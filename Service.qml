import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Workspace Names — service plugin.
//
// The bar keeps showing plain workspace numbers. This service watches the
// focused Hyprland workspace and, on every switch, slides a small pill in
// under the workspace widget showing "<id>  <name>" (or "Workspace <id>" when
// unnamed), holds it briefly, then slides it out the other way. Names come
// from ~/.config/omarchy/workspace-names.json ({"3": "Code", ...}) which is
// watched, so `workspace-name` edits show up instantly.
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

  // Tunables. Override via "_config": {"hold": 900, "slide": 160, "travel": 48,
  // "offsetX": 52, "offsetY": 6} in the names file.
  readonly property var cfg: (names && typeof names._config === "object" && names._config) ? names._config : ({})
  readonly property int holdMs: Number(cfg.hold) > 0 ? Number(cfg.hold) : 900
  readonly property int slideMs: Number(cfg.slide) > 0 ? Number(cfg.slide) : 160
  readonly property int travel: Number(cfg.travel) > 0 ? Number(cfg.travel) : 48
  readonly property int offsetX: cfg.offsetX !== undefined ? Number(cfg.offsetX) : 52
  readonly property int offsetY: cfg.offsetY !== undefined ? Number(cfg.offsetY) : 6

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
    var n = nameFor(id)
    return n !== "" ? n : "Workspace " + id
  }

  function show(id) {
    if (id === undefined || id === null || id < 1) {
      var fw = Hyprland.focusedWorkspace
      id = fw ? fw.id : -1
    }
    if (id < 1) return
    currentId = id
    named = nameFor(id) !== ""
    label = labelFor(id)
    opened = true
    hideTimer.restart()
    presented()
  }

  function hide() {
    if (!opened) return
    opened = false
    hideTimer.stop()
    dismissed()
  }

  onNamesChanged: {
    if (currentId > 0) {
      named = nameFor(currentId) !== ""
      label = labelFor(currentId)
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
      if (id === root.lastId && root.opened) return
      root.lastId = id
      root.show(id)
    }
  }

  Component.onCompleted: {
    var fw = Hyprland.focusedWorkspace
    if (fw) root.lastId = fw.id
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

  IpcHandler {
    target: root.pluginId
    function show(): string { root.show(-1); return "ok" }
    function showId(id: int): string { root.show(id); return "ok" }
    function hide(): string { root.hide(); return "ok" }
    function name(id: int): string { return root.nameFor(id) }
    function reload(): string { namesFile.reload(); return "ok" }
    function ping(): string { return "ok" }
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
        pill.shift = root.direction * root.travel
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
      }

      ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: pill; property: "shift"; to: -root.direction * root.travel; duration: root.slideMs; easing.type: Easing.InCubic }
        NumberAnimation { target: pill; property: "opacity"; to: 0; duration: root.slideMs; easing.type: Easing.InQuad }
        onFinished: if (!root.opened) win.shown = false
      }

      Rectangle {
        id: pill
        property real shift: 0

        // Tucked just under the bar, roughly beneath the workspace numbers.
        x: Style.gapsOut + root.offsetX + shift
        y: Style.bar.sizeHorizontal + Style.gapsOut + root.offsetY
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
