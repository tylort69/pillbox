import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Pending package updates: official repos (checkupdates, safe temp db) + AUR (paru or yay -Qua).
// Checked hourly; the panel lists them and "Update all" runs paru / yay / pacman in your terminal.
Scope {
    id: upd
    required property var theme

    property var repo: []                       // [{ name, from, to }]
    property var aur: []
    property bool checking: false
    property bool updating: false
    property var lastCheck: null
    readonly property int count: repo.length + aur.length
    property var panelScreen: null

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    function parse(text) {
        return text.trim().split("\n").filter(l => l.includes("->")).map(l => {
            const p = l.trim().split(/\s+/)
            return { name: p[0], from: p[1], to: p[3] }
        })
    }
    function check() { if (checking || updating) return; checking = true; repoProc.running = true }

    Process {
        id: repoProc
        command: ["sh", "-c", "checkupdates 2>/dev/null; true"]
        stdout: StdioCollector { onStreamFinished: { upd.repo = upd.parse(text); aurProc.running = true } }
    }
    Process {
        id: aurProc
        command: ["sh", "-c", "h=$(command -v paru || command -v yay) && $h -Qua 2>/dev/null; true"]
        stdout: StdioCollector { onStreamFinished: { upd.aur = upd.parse(text); upd.checking = false; upd.lastCheck = new Date() } }
    }
    // Update in a terminal; re-check when the terminal closes
    Process {
        id: updateProc
        command: theme.term("system-update", "System update", ["sh", "-c",
                  "h=$(command -v paru || command -v yay) || h='sudo pacman'; f=\"$HOME/.config/fish/scripts/fira-progress.py\"; [ -f \"$f\" ] && h=\"python3 -I $f $h\"; $h -Syu; echo; read -r -p 'Done. Press Enter to close.' _"])
        onExited: { upd.updating = false; upd.check() }
    }
    function updateAll() { if (updating) return; updating = true; panelScreen = null; updateProc.running = true }

    Timer { interval: 3600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: upd.check() }

    IpcHandler {
        target: "updates"
        function toggle(): void { upd.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        function check(): void { upd.check() }
    }

    // ── Panel ─────────────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        active: updPanel.visible
        windows: [updPanel].concat(theme.barWindows)
        onCleared: upd.panelScreen = null
    }

    PanelWindow {
        id: updPanel
        screen: upd.panelScreen ?? Quickshell.screens[0]
        visible: upd.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 460
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-updates"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: upd.panelScreen = null

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: 16 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: upd.count ? upd.count + " update" + (upd.count === 1 ? "" : "s") + " available" : "Up to date"
                            font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg
                        }
                        Text {
                            text: upd.checking ? "Checking…" : upd.lastCheck ? "Checked " + Qt.formatTime(upd.lastCheck, "HH:mm") + "  ·  " + upd.repo.length + " official, " + upd.aur.length + " AUR" : ""
                            font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                        }
                    }
                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: 18
                        color: chkHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰑓"
                            font.family: theme.fontFamily; font.pixelSize: 18; color: theme.clrFg
                            RotationAnimation on rotation { running: upd.checking; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                        HoverHandler { id: chkHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: upd.check() }
                    }
                }

                // Package list
                Rectangle {
                    visible: upd.count > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: Math.min(list.contentHeight + 16, 420)
                    radius: 20
                    color: theme.clrBgAlt
                    ListView {
                        id: list
                        anchors { fill: parent; margins: 8 }
                        clip: true
                        model: upd.repo.map(p => Object.assign({ src: "" }, p)).concat(upd.aur.map(p => Object.assign({ src: "AUR" }, p)))
                        delegate: RowLayout {
                            required property var modelData
                            width: list.width
                            height: 26
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                elide: Text.ElideRight
                                font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFg
                            }
                            Rectangle {
                                visible: modelData.src !== ""
                                implicitWidth: aurT.implicitWidth + 10; implicitHeight: 18; radius: 9
                                color: theme.clrTertC
                                Text { id: aurT; anchors.centerIn: parent; text: modelData.src; font.family: theme.fontFamily; font.pixelSize: 9; color: theme.clrOnTertC }
                            }
                            Text {
                                text: modelData.from + "  →  " + modelData.to
                                font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                                Layout.maximumWidth: 230
                                elide: Text.ElideLeft
                            }
                        }
                    }
                }

                // Update button (M3 filled)
                Rectangle {
                    visible: upd.count > 0
                    Layout.fillWidth: true
                    implicitHeight: 44; radius: 22
                    color: updHover.hovered ? Qt.lighter(theme.clrAccent, 1.08) : theme.clrAccent
                    opacity: upd.updating ? 0.5 : 1
                    Text {
                        anchors.centerIn: parent
                        text: upd.updating ? "Updating in terminal…" : "󰚰  Update all (opens a terminal)"
                        font.family: theme.fontFamily; font.pixelSize: 13; font.bold: true
                        color: theme.clrOnAccent
                    }
                    HoverHandler { id: updHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: !upd.updating; onTapped: upd.updateAll() }
                }
            }
        }
    }
}
