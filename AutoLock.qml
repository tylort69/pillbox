import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Pause auto-lock: holds a Wayland idle inhibitor on the bar, so hypridle (or any idle
// daemon) doesn't lock or blank the screen. Timed (15 min … 8 h) or until turned back on.
// Not saved to settings on purpose: a bar restart or a new login always turns auto-lock back on.
Scope {
    id: al
    required property var theme

    property bool paused: false
    property real until: 0                       // ms timestamp; 0 = until turned back on
    property real now: Date.now()
    readonly property real left: paused && until > 0 ? Math.max(0, until - now) : 0
    property var panelScreen: null

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen; now = Date.now() }
    function pause(min) { now = Date.now(); until = min > 0 ? now + min * 60000 : 0; paused = true }
    function extend(min) { if (paused && until > 0) until += min * 60000 }
    function resume(quiet) {
        if (!paused) return
        paused = false; until = 0
        if (!quiet) Quickshell.execDetached(["notify-send", "-a", "System", "-i", "system-lock-screen",
                                             "Auto-lock is back on", "The screen locks again after 10 min idle"])
    }
    function toggle() { paused ? resume(true) : pause(0) }
    function fmtLeft(ms) {
        const m = Math.ceil(ms / 60000), h = Math.floor(m / 60)
        return h ? h + ":" + (m % 60 < 10 ? "0" : "") + m % 60 : m + "m"
    }

    IdleInhibitor {
        enabled: al.paused
        window: al.theme.barWindows[0] ?? null
    }

    Timer {
        interval: 1000
        running: al.paused && al.until > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: { al.now = Date.now(); if (al.left <= 0) al.resume(false) }
    }

    // `qs ipc call autolock toggle | pause <minutes, 0 = until resumed> | resume | panel`
    IpcHandler {
        target: "autolock"
        function toggle(): void { al.toggle() }
        function pause(minutes: int): void { al.pause(minutes) }
        function resume(): void { al.resume(true) }
        function panel(): void { al.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
    }

    // ── panel ────────────────────────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string label
        property bool filled: false
        signal clicked()
        implicitWidth: chipT.implicitWidth + 24
        implicitHeight: 34
        radius: 17
        color: filled ? (chipHover.hovered ? Qt.lighter(theme.clrAccent, 1.08) : theme.clrAccent)
                      : chipHover.hovered ? theme.clrAccentC : theme.clrBgAlt
        Text {
            id: chipT
            anchors.centerIn: parent
            text: chip.label
            font.family: theme.fontFamily; font.pixelSize: 12; font.bold: chip.filled
            color: chip.filled ? theme.clrOnAccent : chipHover.hovered ? theme.clrOnAccentC : theme.clrFg
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    HyprlandFocusGrab {
        active: alPanel.visible
        windows: [alPanel].concat(theme.barWindows)
        onCleared: al.panelScreen = null
    }

    PanelWindow {
        id: alPanel
        screen: al.panelScreen ?? Quickshell.screens[0]
        visible: al.panelScreen !== null
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 360
        implicitHeight: body.implicitHeight + 32
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-autolock"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: al.panelScreen = null

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 44; implicitHeight: 44; radius: 22
                        color: al.paused ? theme.clrTertC : theme.clrBgAlt
                        Text {
                            anchors.centerIn: parent
                            text: al.paused ? "󰌿" : "󰌾"
                            font.family: theme.fontFamily; font.pixelSize: 20
                            color: al.paused ? theme.clrOnTertC : theme.clrFg
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: al.paused ? "Auto-lock paused" : "Auto-lock is on"
                            font.family: theme.fontFamily; font.pixelSize: 14; font.bold: true; color: theme.clrFg
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: !al.paused ? "Locks after 10 min idle. Pause it for:"
                                : al.until > 0 ? "Back on at " + Qt.formatTime(new Date(al.until), "HH:mm") + "  ·  " + al.fmtLeft(al.left) + " left"
                                : "Until you turn it back on"
                            font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                        }
                    }
                }

                // Off: durations
                Flow {
                    visible: !al.paused
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [[15, "15 min"], [30, "30 min"], [60, "1 h"], [120, "2 h"], [240, "4 h"], [480, "8 h"], [0, "Until I turn it back on"]]
                        Chip { required property var modelData; label: modelData[1]; onClicked: { al.pause(modelData[0]); al.panelScreen = null } }
                    }
                }

                // Paused: extend / resume
                RowLayout {
                    visible: al.paused
                    Layout.fillWidth: true
                    spacing: 6
                    Chip { visible: al.until > 0; label: "+30 min"; onClicked: al.extend(30) }
                    Chip { visible: al.until > 0; label: "+1 h"; onClicked: al.extend(60) }
                    Item { Layout.fillWidth: true }
                    Chip { label: "󰌾  Turn back on"; filled: true; onClicked: { al.resume(true); al.panelScreen = null } }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: al.paused ? "On the bar: right-click turns it back on" : "On the bar: right-click pauses it until you turn it back on"
                    font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                }
            }
        }
    }
}
