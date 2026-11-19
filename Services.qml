import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Failed systemd units (system + user). The bar pill only appears when something failed.
// Restart / Clear on system units ask for your password through the polkit agent.
Scope {
    id: svc
    required property var theme

    property var failed: []                     // [{ unit, desc, user }]
    readonly property int count: failed.length
    property var panelScreen: null
    property var _sys: []

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen; if (panelScreen) check() }
    function check() { if (!sysProc.running && !userProc.running) sysProc.running = true }
    function parse(text, user) {
        try { return JSON.parse(text).map(u => ({ unit: u.unit, desc: u.description, user: user, sub: u.sub })) } catch (e) { return [] }
    }
    function sc(u) { return u.user ? ["systemctl", "--user"] : ["systemctl"] }
    function act(u, verb) {
        actProc.command = sc(u).concat([verb, u.unit])
        actProc.running = true
    }
    function logs(u) {
        Quickshell.execDetached(theme.term("unit-logs", u.unit + " logs",
            ["journalctl", "-b", "-e", "--no-hostname", u.user ? "--user-unit" : "-u", u.unit]))
        panelScreen = null
    }

    Process {
        id: sysProc
        command: ["systemctl", "--failed", "--output=json", "--no-pager"]
        stdout: StdioCollector { onStreamFinished: { svc._sys = svc.parse(text, false); userProc.running = true } }
    }
    Process {
        id: userProc
        command: ["systemctl", "--user", "--failed", "--output=json", "--no-pager"]
        stdout: StdioCollector { onStreamFinished: svc.failed = svc._sys.concat(svc.parse(text, true)) }
    }
    Process {
        id: actProc
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) Quickshell.execDetached(["notify-send", "-a", "systemd", "Action failed", text.trim()])
        }
        onExited: recheck.restart()
    }
    Timer { id: recheck; interval: 1500; onTriggered: svc.check() }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: svc.check() }

    IpcHandler {
        target: "services"
        function toggle(): void { svc.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        function check(): void { svc.check() }
    }

    HyprlandFocusGrab {
        active: svcPanel.visible
        windows: [svcPanel].concat(theme.barWindows)
        onCleared: svc.panelScreen = null
    }

    PanelWindow {
        id: svcPanel
        screen: svc.panelScreen ?? Quickshell.screens[0]
        visible: svc.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 500
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-services"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: svc.panelScreen = null

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: 16 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: svc.count ? svc.count + " failed service" + (svc.count === 1 ? "" : "s") : "All services OK"
                        font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true
                        color: svc.count ? theme.clrUrgent : theme.clrFg
                    }
                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: 18
                        color: rfHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                        Text { anchors.centerIn: parent; text: "󰑓"; font.family: theme.fontFamily; font.pixelSize: 18; color: theme.clrFg }
                        HoverHandler { id: rfHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: svc.check() }
                    }
                }

                Repeater {
                    model: svc.failed
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: col.implicitHeight + 20
                        radius: 18
                        color: theme.clrBgAlt
                        ColumnLayout {
                            id: col
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text { text: "󰅚"; font.family: theme.fontFamily; font.pixelSize: 16; color: theme.clrUrgent }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { Layout.fillWidth: true; text: modelData.unit; elide: Text.ElideMiddle; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrFg }
                                    Text { Layout.fillWidth: true; text: modelData.desc; elide: Text.ElideRight; font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted }
                                }
                                Rectangle {
                                    implicitWidth: scT.implicitWidth + 12; implicitHeight: 18; radius: 9
                                    color: modelData.user ? theme.clrAccentC : theme.clrTertC
                                    Text { id: scT; anchors.centerIn: parent; text: modelData.user ? "user" : "system"; font.family: theme.fontFamily; font.pixelSize: 9; color: modelData.user ? theme.clrOnAccentC : theme.clrOnTertC }
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: 6
                                Repeater {
                                    model: [
                                        { label: "󰈙  Logs",    act: () => svc.logs(modelData) },
                                        { label: "󰑓  Restart", act: () => svc.act(modelData, "restart") },
                                        { label: "󰅖  Clear",   act: () => svc.act(modelData, "reset-failed") }
                                    ]
                                    Rectangle {
                                        required property var modelData
                                        implicitWidth: bT.implicitWidth + 18; implicitHeight: 28; radius: 14
                                        color: bHover.hovered ? theme.clrAccentC : "transparent"
                                        border.width: 1; border.color: theme.clrBorder
                                        Text { id: bT; anchors.centerIn: parent; text: modelData.label; font.family: theme.fontFamily; font.pixelSize: 10; color: bHover.hovered ? theme.clrOnAccentC : theme.clrFg }
                                        HoverHandler { id: bHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: modelData.act() }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: svc.count ? "Clear hides a failure without fixing it. System units ask for your password." : "Checked every minute. This icon hides itself when nothing has failed."
                    font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                }
            }
        }
    }
}
