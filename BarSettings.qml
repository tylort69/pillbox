import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Bar settings: which screen edge the bar sits on, and whether the pill order is mirrored.
// Saved in settings.json (barPosition, barMirror); open with the gear on the bar
// or `qs ipc call bar toggle`.
Scope {
    id: bs
    required property var theme
    required property var settings
    property var panelScreen: null

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }

    readonly property var positions: [
        { id: "top",    label: "Top" },
        { id: "bottom", label: "Bottom" },
        { id: "left",   label: "Left" },
        { id: "right",  label: "Right" }
    ]
    readonly property string orderText: theme.vertical
        ? (theme.mirror ? "Workspaces at the bottom, power button at the top" : "Workspaces at the top, power button at the bottom")
        : (theme.mirror ? "Workspaces on the right, power button on the left" : "Workspaces on the left, power button on the right")

    IpcHandler {
        target: "bar"
        function toggle(): void { bs.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        function position(where: string): void { if (bs.positions.some(p => p.id === where)) bs.settings.barPosition = where }
        function mirror(on: bool): void { bs.settings.barMirror = on }
    }

    HyprlandFocusGrab {
        active: bsPanel.visible
        windows: [bsPanel].concat(theme.barWindows)
        onCleared: bs.panelScreen = null
    }

    PanelWindow {
        id: bsPanel
        screen: bs.panelScreen ?? Quickshell.screens[0]
        visible: bs.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 400
        implicitHeight: body.implicitHeight + 32
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bar-settings"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: bs.panelScreen = null

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 10

                Text { text: "Bar"; font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg }

                Text { text: "Position"; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent }

                // One card per edge, each with a little screen showing where the bar goes
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: bs.positions
                        Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool current: theme.barPosition === modelData.id
                            readonly property bool vert: modelData.id === "left" || modelData.id === "right"
                            Layout.fillWidth: true
                            implicitHeight: 92
                            radius: 20
                            color: current ? theme.clrAccentC : cardHover.hovered ? theme.clrBgAlt : Qt.alpha(theme.clrBgAlt, 0.5)
                            border.width: current ? 0 : 1
                            border.color: theme.clrBorder
                            Behavior on color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                // mini screen
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 62; implicitHeight: 40; radius: 6
                                    color: "transparent"
                                    border.width: 2
                                    border.color: card.current ? theme.clrOnAccentC : theme.clrFgMuted
                                    // the bar
                                    Rectangle {
                                        x: card.modelData.id === "right" ? parent.width - width - 4 : 4
                                        y: card.modelData.id === "bottom" ? parent.height - height - 4 : 4
                                        width: card.vert ? 5 : parent.width - 8
                                        height: card.vert ? parent.height - 8 : 5
                                        radius: 2.5
                                        color: card.current ? theme.clrAccent : theme.clrFg
                                        // workspaces end of the bar, flips with the mirror setting
                                        Rectangle {
                                            width: card.vert ? parent.width : 10
                                            height: card.vert ? 10 : parent.height
                                            radius: 2.5
                                            x: !card.vert && theme.mirror ? parent.width - width : 0
                                            y: card.vert && theme.mirror ? parent.height - height : 0
                                            color: card.current ? theme.clrOnAccentC : theme.clrAccent
                                        }
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: card.modelData.label
                                    font.family: theme.fontFamily; font.pixelSize: 12; font.bold: card.current
                                    color: card.current ? theme.clrOnAccentC : theme.clrFg
                                }
                            }
                            HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: bs.settings.barPosition = card.modelData.id }
                        }
                    }
                }

                Text { Layout.topMargin: 4; text: "Order"; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent }

                // Mirror switch (M3 style)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: mirRow.implicitHeight + 20
                    radius: 20
                    color: mirHover.hovered ? theme.clrBgAlt : Qt.alpha(theme.clrBgAlt, 0.5)
                    RowLayout {
                        id: mirRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                        spacing: 12
                        Text { text: "󰯌"; font.family: theme.fontFamily; font.pixelSize: 20; color: theme.clrFg }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: theme.vertical ? "Mirror (bottom → top)" : "Mirror (right → left)"
                                font.family: theme.fontFamily; font.pixelSize: 13; color: theme.clrFg
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: bs.orderText
                                font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                            }
                        }
                        Rectangle {
                            implicitWidth: 52; implicitHeight: 32; radius: 16
                            color: theme.mirror ? theme.clrAccent : "transparent"
                            border.width: theme.mirror ? 0 : 2
                            border.color: theme.clrFgMuted
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Rectangle {
                                property int d: theme.mirror ? 24 : 16
                                width: d; height: d; radius: d / 2
                                anchors.verticalCenter: parent.verticalCenter
                                x: theme.mirror ? parent.width - width - 4 : 8
                                color: theme.mirror ? theme.clrOnAccent : theme.clrFgMuted
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on d { NumberAnimation { duration: 150 } }
                            }
                        }
                    }
                    HoverHandler { id: mirHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: bs.settings.barMirror = !bs.settings.barMirror }
                }

                Text {
                    Layout.topMargin: 2
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "On the left or right the bar is narrower: window and track titles are hidden and the clock stacks."
                    font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                }
            }
        }
    }
}
