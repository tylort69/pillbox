import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Internet status for the bar: connection type (Ethernet / Wi-Fi), reachability
// (router, internet, DNS), connection details, and a Wi-Fi menu when a wireless
// adapter exists (via iwd). Data comes from scripts/net.py.
Scope {
    id: net
    required property var theme

    readonly property string script: Quickshell.shellDir + "/scripts/net.py"
    property var info: ({ links: [], dns: [], gateway: "", iface: "", wifiHardware: false, iwd: false })
    property var checks: null                    // { router, internet, dns } ms or null
    property bool checking: false
    property var wifiNets: []
    property bool scanning: false
    property string connectingTo: ""
    property string passwordFor: ""              // SSID whose password field is open
    property string wifiError: ""
    property var panelScreen: null

    readonly property var primary: info.links.find(l => l.default) ?? info.links.find(l => l.state === "up") ?? null
    readonly property bool linkUp: primary !== null && primary.state === "up" && primary.ipv4.length > 0
    readonly property bool online: linkUp && checks !== null && checks.internet !== null
    readonly property bool isWifi: primary?.type === "wifi"
    readonly property var wifiLink: info.links.find(l => l.type === "wifi") ?? null

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    function refresh() { infoProc.running = false; infoProc.running = true }
    function runChecks() { checking = true; checkProc.running = false; checkProc.running = true }
    function scan() { scanning = true; wifiError = ""; scanProc.running = false; scanProc.running = true }
    function connect(ssid, pass) {
        connectingTo = ssid; wifiError = ""
        connectProc.command = ["python3", "-I", script, "wifi-connect", ssid, pass || ""]
        connectProc.running = true
    }

    // Wi-Fi bars from signal strength (dBm)
    function wifiIcon(rssi) {
        if (rssi === null || rssi === undefined) return "󰤯"
        return rssi > -55 ? "󰤨" : rssi > -67 ? "󰤥" : rssi > -78 ? "󰤢" : "󰤟"
    }
    readonly property string icon: !linkUp ? (wifiLink ? "󰤮" : "󰈂")
                                  : isWifi ? wifiIcon(primary.wifi?.rssi) : "󰈀"
    readonly property string statusText: !linkUp ? "Not connected"
                                        : checks === null ? "Checking…"
                                        : checks.internet !== null ? "Connected to the internet"
                                        : checks.router !== null ? "Connected, no internet"
                                        : "Connected, router not responding"
    readonly property string typeText: !primary ? "No network adapter connected"
        : isWifi ? "Wi-Fi · " + (primary.wifi?.ssid || "—")
        : "Ethernet" + (primary.speed ? " · " + (primary.speed >= 1000 ? (primary.speed / 1000) + " Gb/s" : primary.speed + " Mb/s") : "")

    // ── Data ──────────────────────────────────────────────────────────────────
    Process {
        id: infoProc
        command: ["python3", "-I", net.script, "info"]
        stdout: StdioCollector { onStreamFinished: { try { net.info = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        id: checkProc
        command: ["python3", "-I", net.script, "checks"]
        stdout: StdioCollector { onStreamFinished: { try { net.checks = JSON.parse(text) } catch (e) {} net.checking = false } }
    }
    Process {
        id: scanProc
        command: ["python3", "-I", net.script, "wifi-scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); net.wifiNets = r.networks || []; if (r.error) net.wifiError = r.error } catch (e) {}
                net.scanning = false
            }
        }
    }
    Process {
        id: connectProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); if (!r.ok) net.wifiError = r.error || "Couldn't connect" } catch (e) {}
                net.connectingTo = ""; net.passwordFor = ""
                net.refresh(); net.scan(); net.runChecks()
            }
        }
    }
    Process { id: actionProc; onExited: { net.refresh(); net.scan() } }
    function wifiAction(args) { actionProc.command = ["python3", "-I", script].concat(args); actionProc.running = true }

    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: net.refresh() }
    Timer { interval: net.panelScreen ? 10000 : 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: net.runChecks() }
    // Re-check right away when the link changes (cable unplugged, Wi-Fi switched…)
    onLinkUpChanged: runChecks()
    onPanelScreenChanged: if (panelScreen) { runChecks(); if (info.iwd && wifiLink) scan() }

    // `qs ipc call network toggle`
    IpcHandler {
        target: "network"
        function toggle(): void { net.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
    }

    Process { id: copyProc }
    function copy(t) { copyProc.command = ["wl-copy", t]; copyProc.startDetached() }

    // ── Panel ─────────────────────────────────────────────────────────────────
    component Check: Rectangle {
        id: chk
        property string label
        property var ms                          // number or null
        property bool pending: false
        Layout.fillWidth: true
        implicitHeight: 64; radius: 18
        color: pending ? theme.clrBgAlt : ms !== null ? Qt.alpha(theme.clrAccent, 0.14) : Qt.alpha(theme.clrUrgent, 0.16)
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: chk.pending ? "󰔟" : chk.ms !== null ? "󰄬" : "󰅖"
                font.family: theme.fontFamily; font.pixelSize: 18
                color: chk.pending ? theme.clrFgMuted : chk.ms !== null ? theme.clrAccent : theme.clrUrgent
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: chk.label + (chk.ms !== null && !chk.pending ? "  " + chk.ms + " ms" : "")
                font.family: theme.fontFamily; font.pixelSize: 11
                color: theme.clrFg
            }
        }
    }

    component Row2: RowLayout {
        id: r2
        property string label
        property string value
        property bool copyable: false
        Layout.fillWidth: true
        visible: value !== ""
        Text { text: r2.label; font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFgMuted; Layout.preferredWidth: 90 }
        Text {
            Layout.fillWidth: true
            text: r2.value
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignRight
            font.family: theme.fontFamily; font.pixelSize: 12
            color: copyHover.hovered && r2.copyable ? theme.clrAccent : theme.clrFg
            HoverHandler { id: copyHover; cursorShape: r2.copyable ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: r2.copyable; onTapped: net.copy(r2.value.split(",")[0].trim().split(" ")[0].split("/")[0]) }
        }
    }

    HyprlandFocusGrab {
        active: netPanel.visible
        windows: [netPanel].concat(theme.barWindows)
        onCleared: net.panelScreen = null
    }

    PanelWindow {
        id: netPanel
        screen: net.panelScreen ?? Quickshell.screens[0]
        visible: net.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 420
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.85)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-network"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: net.panelScreen = null

            Flickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 12

                    // Status hero
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Rectangle {
                            implicitWidth: 56; implicitHeight: 56; radius: 18
                            color: net.online ? theme.clrAccentC : net.linkUp ? theme.clrTertC : Qt.alpha(theme.clrUrgent, 0.2)
                            Text {
                                anchors.centerIn: parent
                                text: net.icon
                                font.family: theme.fontFamily; font.pixelSize: 28
                                color: net.online ? theme.clrOnAccentC : net.linkUp ? theme.clrOnTertC : theme.clrUrgent
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: net.statusText; font.family: theme.fontFamily; font.pixelSize: 16; font.bold: true; color: theme.clrFg }
                            Text { text: net.typeText; font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFgMuted }
                        }
                        // Re-run checks
                        Rectangle {
                            implicitWidth: 36; implicitHeight: 36; radius: 18
                            color: rHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "󰑓"
                                font.family: theme.fontFamily; font.pixelSize: 18
                                color: theme.clrFg
                                RotationAnimation on rotation { running: net.checking; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            HoverHandler { id: rHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { net.refresh(); net.runChecks() } }
                        }
                    }

                    // Reachability checks
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Check { label: "Router"; ms: net.checks?.router ?? null; pending: net.checks === null }
                        Check { label: "Internet"; ms: net.checks?.internet ?? null; pending: net.checks === null }
                        Check { label: "DNS"; ms: net.checks?.dns ?? null; pending: net.checks === null }
                    }

                    // Connection details (click an address to copy it)
                    Rectangle {
                        Layout.fillWidth: true
                        visible: net.primary !== null
                        implicitHeight: details.implicitHeight + 24
                        radius: 20
                        color: theme.clrBgAlt
                        ColumnLayout {
                            id: details
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 7
                            Text { text: "Connection"; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent }
                            Row2 { label: "Interface"; value: net.primary ? net.primary.name + (net.primary.driver ? "  (" + net.primary.driver + ")" : "") : "" }
                            Row2 { label: "IPv4"; value: net.primary?.ipv4.join(", ") ?? ""; copyable: true }
                            Row2 { label: "Router"; value: net.info.gateway; copyable: true }
                            Row2 { label: "DNS in use"; value: net.info.dnsCurrent || (net.info.dns[0] ?? ""); copyable: true }
                            Row2 { label: "DNS backups"; value: net.info.dns.filter(d => d !== net.info.dnsCurrent).map(d => d.split(" ")[0]).join(", "); copyable: true }
                            Row2 { label: "IPv6"; value: net.primary?.ipv6.join(", ") ?? ""; copyable: true }
                            Row2 { label: "MAC"; value: net.primary?.mac ?? ""; copyable: true }
                            Row2 { label: "Signal"; value: net.isWifi && net.primary.wifi?.rssi ? net.primary.wifi.rssi + " dBm" : "" }
                            Text { text: "Click an address to copy it"; font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted; Layout.alignment: Qt.AlignRight }
                        }
                    }

                    // ── Wi-Fi ───────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: wifiCol.implicitHeight + 24
                        radius: 20
                        color: theme.clrBgAlt
                        ColumnLayout {
                            id: wifiCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text { Layout.fillWidth: true; text: "Wi-Fi"; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent }
                                Text {
                                    visible: net.info.iwd && net.wifiLink !== null
                                    text: net.scanning ? "Scanning…" : "󰑓 Scan"
                                    font.family: theme.fontFamily; font.pixelSize: 11
                                    color: scanHover.hovered ? theme.clrAccent : theme.clrFgMuted
                                    HoverHandler { id: scanHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { enabled: !net.scanning; onTapped: net.scan() }
                                }
                            }
                            // No adapter / no iwd
                            Text {
                                visible: !net.info.wifiHardware || !net.info.iwd || net.wifiLink === null
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: !net.info.wifiHardware ? "󰤮  No Wi-Fi adapter in this PC. Plug in a USB Wi-Fi adapter and this section turns into a network list."
                                    : !net.info.iwd ? "󰤮  A Wi-Fi adapter was found, but iwd isn't installed. Install it (sudo pacman -S iwd, then enable iwd.service) to manage Wi-Fi here."
                                    : "󰤮  Wi-Fi adapter not ready."
                                font.family: theme.fontFamily; font.pixelSize: 12
                                color: theme.clrFgMuted
                            }
                            Text {
                                visible: net.wifiError !== "" && net.wifiError !== "no-adapter"
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                                text: net.wifiError
                                font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrUrgent
                            }
                            // Network list
                            Repeater {
                                model: net.info.iwd && net.wifiLink ? net.wifiNets : []
                                ColumnLayout {
                                    id: netRow
                                    required property var modelData
                                    readonly property bool secured: modelData.security !== "open"
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 40; radius: 14
                                        color: netRow.modelData.connected ? Qt.alpha(theme.clrAccent, 0.14) : rowHover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent"
                                        RowLayout {
                                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                            spacing: 10
                                            Text {
                                                text: ["󰤟", "󰤟", "󰤢", "󰤥", "󰤨"][Math.min(4, netRow.modelData.bars)]
                                                font.family: theme.fontFamily; font.pixelSize: 16
                                                color: netRow.modelData.connected ? theme.clrAccent : theme.clrFg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: netRow.modelData.ssid
                                                elide: Text.ElideRight
                                                font.family: theme.fontFamily; font.pixelSize: 12; font.bold: netRow.modelData.connected
                                                color: theme.clrFg
                                            }
                                            Text { visible: netRow.secured; text: "󰌾"; font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFgMuted }
                                            Text {
                                                text: net.connectingTo === netRow.modelData.ssid ? "Connecting…"
                                                    : netRow.modelData.connected ? "Disconnect" : "Connect"
                                                font.family: theme.fontFamily; font.pixelSize: 11
                                                color: theme.clrAccent
                                            }
                                        }
                                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            enabled: net.connectingTo === ""
                                            onTapped: {
                                                const n = netRow.modelData
                                                if (n.connected) net.wifiAction(["wifi-disconnect"])
                                                else if (netRow.secured && !n.known) net.passwordFor = (net.passwordFor === n.ssid ? "" : n.ssid)
                                                else net.connect(n.ssid, "")
                                            }
                                        }
                                    }
                                    // Password field for new secured networks
                                    Rectangle {
                                        visible: net.passwordFor === netRow.modelData.ssid
                                        Layout.fillWidth: true
                                        implicitHeight: 38; radius: 19
                                        color: theme.clrBg
                                        border.width: 2; border.color: theme.clrAccent
                                        TextInput {
                                            id: pass
                                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            focus: parent.visible
                                            font.family: theme.fontFamily; font.pixelSize: 12
                                            color: theme.clrFg
                                            onAccepted: { net.connect(netRow.modelData.ssid, text); text = "" }
                                            Text {
                                                visible: !pass.text
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Password, then Enter"
                                                font: pass.font
                                                color: theme.clrFgMuted
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
