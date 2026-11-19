import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Keyboard layout: current layout on the bar (EN / RU), list panel to pick one.
// Layouts come from Hyprland's input.kb_layout ("us,ru"); SUPER + SPACE switches (xkb).
Scope {
    id: kb
    required property var theme

    property var codes: []                      // ["us", "ru"]
    property int index: 0
    property string name: ""                    // "English (US)"
    property var panelScreen: null

    readonly property string short: ({ us: "EN", gb: "EN", ru: "RU", ua: "UA", de: "DE", fr: "FR" })[codes[index]]
                                    ?? (codes[index] ?? "").toUpperCase()
    readonly property var names: ({ us: "English (US)", gb: "English (UK)", ru: "Русский", ua: "Українська", de: "Deutsch", fr: "Français" })

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    function select(i) { Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(i)]) }
    function next() { if (codes.length > 1) select((index + 1) % codes.length) }

    Process {
        id: query
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards
                    const k = kbs.find(x => x.main) ?? kbs.find(x => x.layout.includes(",")) ?? kbs[0]
                    kb.codes = k.layout.split(",").map(s => s.trim())
                    kb.index = k.active_layout_index ?? 0
                    kb.name = k.active_keymap
                } catch (e) {}
            }
        }
    }
    Component.onCompleted: query.running = true
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout" || event.name === "configreloaded") query.running = true
        }
    }

    IpcHandler {
        target: "keyboard"
        function next(): void { kb.next() }
    }

    HyprlandFocusGrab {
        active: kbPanel.visible
        windows: [kbPanel].concat(theme.barWindows)
        onCleared: kb.panelScreen = null
    }

    PanelWindow {
        id: kbPanel
        screen: kb.panelScreen ?? Quickshell.screens[0]
        visible: kb.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 280
        implicitHeight: body.implicitHeight + 32
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-keyboard"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: kb.panelScreen = null

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 6

                Text { text: "Keyboard layout"; font.family: theme.fontFamily; font.pixelSize: 16; font.bold: true; color: theme.clrFg }

                Repeater {
                    model: kb.codes
                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: index === kb.index
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 22
                        color: current ? theme.clrAccentC : rowHover.hovered ? theme.clrBgAlt : "transparent"
                        RowLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            spacing: 12
                            Rectangle {
                                implicitWidth: 34; implicitHeight: 24; radius: 8
                                color: current ? theme.clrAccent : theme.clrBgAlt
                                Text {
                                    anchors.centerIn: parent
                                    text: ({ us: "EN", gb: "EN", ru: "RU" })[modelData] ?? modelData.toUpperCase()
                                    font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true
                                    color: current ? theme.clrOnAccent : theme.clrFg
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: kb.names[modelData] ?? modelData
                                font.family: theme.fontFamily; font.pixelSize: 13
                                color: current ? theme.clrOnAccentC : theme.clrFg
                            }
                            Text { visible: current; text: "󰄬"; font.family: theme.fontFamily; font.pixelSize: 16; color: theme.clrOnAccentC }
                        }
                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { kb.select(index); kb.panelScreen = null } }
                    }
                }

                Text {
                    Layout.topMargin: 4
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "SUPER + SPACE switches layout anywhere, including the lock screen."
                    font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                }
            }
        }
    }
}
