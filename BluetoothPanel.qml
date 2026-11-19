import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Bluetooth

// Bluetooth for the bar (BlueZ). The bar icon only appears when an adapter exists.
// Panel: power, scan, connected / paired / nearby devices, battery levels,
// connect / disconnect / pair / forget.
Scope {
    id: bt
    required property var theme

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool powered: adapter?.enabled ?? false
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var connected: devices.filter(d => d.connected)
    readonly property var paired: devices.filter(d => d.paired && !d.connected)
    readonly property var nearby: devices.filter(d => !d.paired && !d.connected && (d.name || d.deviceName))
    property var panelScreen: null

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    // Stop scanning when the panel closes (scanning drains battery on the other side too)
    onPanelScreenChanged: if (!panelScreen && adapter && adapter.discovering) adapter.discovering = false

    readonly property string icon: !available || !powered ? "󰂲" : connected.length ? "󰂱" : "󰂯"
    function devName(d) { return d.name || d.deviceName || d.address }
    function devIcon(d) {
        const i = (d.icon || "") + ""
        if (i.includes("headset") || i.includes("headphone")) return "󰋋"
        if (i.includes("audio") || i.includes("speaker")) return "󰓃"
        if (i.includes("keyboard")) return "󰌌"
        if (i.includes("mouse")) return "󰍽"
        if (i.includes("gaming") || i.includes("joystick")) return "󰊴"
        if (i.includes("phone")) return "󰏲"
        if (i.includes("computer")) return "󰟀"
        return "󰂯"
    }
    function pairAndConnect(d) {
        d.trusted = true                      // reconnect automatically in future
        if (!d.paired) d.pair(); else d.connect()
    }
    // After pairing finishes, connect
    Instantiator {
        model: bt.devices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPairedChanged() { if (modelData.paired && !modelData.connected) modelData.connect() }
        }
    }

    // `qs ipc call bluetooth toggle`
    IpcHandler {
        target: "bluetooth"
        function toggle(): void { bt.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
    }

    // ── Pieces ────────────────────────────────────────────────────────────────
    component Switch: Rectangle {
        id: sw
        property bool checked
        signal toggled()
        implicitWidth: 52; implicitHeight: 32; radius: 16
        color: checked ? theme.clrAccent : theme.clrBgAlt
        border.width: checked ? 0 : 2
        border.color: theme.clrFgMuted
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: sw.checked ? 24 : 16; height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - 4 : 8
            color: sw.checked ? theme.clrOnAccent : theme.clrFgMuted
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sw.toggled() }
    }

    component Section: Text {
        font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true
        color: theme.clrAccent
        Layout.topMargin: 4
    }

    component DeviceRow: Rectangle {
        id: row
        required property var dev
        readonly property bool busy: dev.pairing || dev.state === BluetoothDeviceState.Connecting
                                     || dev.state === BluetoothDeviceState.Disconnecting
        Layout.fillWidth: true
        implicitHeight: 52
        radius: 16
        color: dev.connected ? Qt.alpha(theme.clrAccent, 0.14) : rowHover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent"

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: 17
                color: row.dev.connected ? theme.clrAccentC : theme.clrBgAlt
                Text {
                    anchors.centerIn: parent
                    text: bt.devIcon(row.dev)
                    font.family: theme.fontFamily; font.pixelSize: 17
                    color: row.dev.connected ? theme.clrOnAccentC : theme.clrFg
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: bt.devName(row.dev)
                    elide: Text.ElideRight
                    font.family: theme.fontFamily; font.pixelSize: 12; font.bold: row.dev.connected
                    color: theme.clrFg
                }
                Text {
                    text: row.dev.pairing ? "Pairing…"
                        : row.dev.state === BluetoothDeviceState.Connecting ? "Connecting…"
                        : row.dev.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                        : row.dev.connected ? ("Connected" + (row.dev.batteryAvailable ? "  ·  󰁹 " + Math.round(row.dev.battery * 100) + "%" : ""))
                        : row.dev.paired ? "Paired" : "Not paired"
                    font.family: theme.fontFamily; font.pixelSize: 10
                    color: theme.clrFgMuted
                }
            }
            // Main action
            Rectangle {
                implicitWidth: actText.implicitWidth + 22; implicitHeight: 30; radius: 15
                color: actHover.hovered && !row.busy ? theme.clrAccent : theme.clrAccentC
                opacity: row.busy ? 0.5 : 1
                Text {
                    id: actText
                    anchors.centerIn: parent
                    text: row.dev.connected ? "Disconnect" : row.dev.paired ? "Connect" : "Pair"
                    font.family: theme.fontFamily; font.pixelSize: 11
                    color: actHover.hovered && !row.busy ? theme.clrOnAccent : theme.clrOnAccentC
                }
                HoverHandler { id: actHover; cursorShape: row.busy ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler {
                    enabled: !row.busy
                    onTapped: {
                        if (row.dev.connected) row.dev.disconnect()
                        else bt.pairAndConnect(row.dev)
                    }
                }
            }
            // Forget (paired devices)
            Text {
                visible: row.dev.paired && rowHover.hovered
                text: "󰆴"
                font.family: theme.fontFamily; font.pixelSize: 15
                color: forgetHover.hovered ? theme.clrUrgent : theme.clrFgMuted
                HoverHandler { id: forgetHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: row.dev.forget() }
            }
        }
        HoverHandler { id: rowHover }
    }

    // ── Panel ─────────────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        active: btPanel.visible
        windows: [btPanel].concat(theme.barWindows)
        onCleared: bt.panelScreen = null
    }

    PanelWindow {
        id: btPanel
        screen: bt.panelScreen ?? Quickshell.screens[0]
        visible: bt.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 420
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-bluetooth"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: bt.panelScreen = null

            Flickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text { text: "Bluetooth"; font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg; Layout.fillWidth: true }
                        Switch {
                            visible: bt.available
                            checked: bt.powered
                            onToggled: bt.adapter.enabled = !bt.adapter.enabled
                        }
                    }

                    Text {
                        visible: !bt.available
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "󰂲  No Bluetooth adapter found. Plug in a USB Bluetooth adapter and it shows up here."
                        font.family: theme.fontFamily; font.pixelSize: 12
                        color: theme.clrFgMuted
                    }
                    Text {
                        visible: bt.available && !bt.powered
                        text: bt.adapter?.state === BluetoothAdapterState.Blocked ? "󰂲  Bluetooth is blocked (rfkill)." : "󰂲  Bluetooth is off."
                        font.family: theme.fontFamily; font.pixelSize: 12
                        color: theme.clrFgMuted
                    }

                    ColumnLayout {
                        visible: bt.available && bt.powered
                        Layout.fillWidth: true
                        spacing: 4

                        Section { text: "Connected"; visible: bt.connected.length > 0 }
                        Repeater { model: bt.connected; DeviceRow { required property var modelData; dev: modelData } }

                        Section { text: "Paired"; visible: bt.paired.length > 0 }
                        Repeater { model: bt.paired; DeviceRow { required property var modelData; dev: modelData } }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Section { text: "Nearby"; Layout.fillWidth: true; Layout.topMargin: 0 }
                            Rectangle {
                                implicitWidth: scanText.implicitWidth + 22; implicitHeight: 30; radius: 15
                                color: bt.adapter?.discovering ? theme.clrAccentC : scanHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                                border.width: bt.adapter?.discovering ? 0 : 1; border.color: theme.clrBorder
                                Text {
                                    id: scanText
                                    anchors.centerIn: parent
                                    text: bt.adapter?.discovering ? "󰑓  Scanning… (stop)" : "󰑓  Scan"
                                    font.family: theme.fontFamily; font.pixelSize: 11
                                    color: bt.adapter?.discovering ? theme.clrOnAccentC : theme.clrFg
                                }
                                HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: bt.adapter.discovering = !bt.adapter.discovering }
                            }
                        }
                        Text {
                            visible: bt.nearby.length === 0
                            text: bt.adapter?.discovering ? "Looking for devices… put yours in pairing mode." : "Press Scan to find devices."
                            font.family: theme.fontFamily; font.pixelSize: 11
                            color: theme.clrFgMuted
                        }
                        Repeater { model: bt.nearby; DeviceRow { required property var modelData; dev: modelData } }
                    }
                }
            }
        }
    }
}
