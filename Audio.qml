import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// Sound control for the bar: default output/input volume, device switching,
// per-app volume, and shortcuts to pavucontrol / wiremix.
Scope {
    id: audio
    required property var theme

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    property var panelScreen: null                 // screen whose bar opened the panel

    readonly property var nodes: Pipewire.nodes.values
    function mediaClass(n) { return (n.properties?.["media.class"] ?? "") + "" }
    // `type` is known before a node is tracked; media.class (to hide the Scarlett's
    // internal split nodes) arrives once the tracker below has bound the node.
    function internal(n) { return mediaClass(n).includes("Internal") }
    readonly property var sinks: nodes.filter(n => n.type === PwNodeType.AudioSink && !internal(n))
    readonly property var sources: nodes.filter(n => n.type === PwNodeType.AudioSource && !internal(n))
    readonly property var apps: nodes.filter(n => n.type === PwNodeType.AudioOutStream && !internal(n))

    // Streams from WebRTC/Chromium/etc. report a library name; use the program instead
    function genericApp(name) { return !name || /webrtc|chromium|pulseaudio|alsa|playback|audio stream/i.test(name) }
    function appBinary(n) {
        const b = ((n.properties ?? {})["application.process.binary"] || "") + ""
        return b ? b.charAt(0).toUpperCase() + b.slice(1) : ""
    }
    function nodeName(n) {
        if (!n) return "None"
        const p = n.properties ?? {}
        if (n.isStream) {
            const a = p["application.name"] || ""
            return genericApp(a) ? (appBinary(n) || a || p["media.name"] || n.name) : a
        }
        // Short name, unless another device of the same kind shares it
        const peers = n.isSink ? sinks : sources
        const nick = n.nickname || ""
        if (nick && peers.filter(o => o.nickname === nick).length === 1) return nick
        return n.description || nick || n.name
    }
    function appIcon(n) {
        const p = n.properties ?? {}
        const a = p["application.name"] || ""
        const i = p["application.icon-name"] ||
                  (genericApp(a) ? ((p["application.process.binary"] || "") + "").toLowerCase() : a.toLowerCase())
        return Quickshell.iconPath(i, true)
    }
    function volIcon(v, m) { return m || v <= 0 ? "󰝟" : v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾" }
    function setVolume(node, v) { if (node?.audio) { node.audio.muted = false; node.audio.volume = Math.max(0, Math.min(1, v)) } }
    function toggleMute(node) { if (node?.audio) node.audio.muted = !node.audio.muted }
    function step(delta) { setVolume(sink, volume + delta) }
    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }

    // Keep the audio properties of everything we show live
    PwObjectTracker { objects: [audio.sink, audio.source].concat(audio.sinks, audio.sources, audio.apps).filter(o => o) }

    // `qs ipc call audio toggle|up|down|mute`
    IpcHandler {
        target: "audio"
        function toggle(): void { audio.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null) }
        function up(): void { audio.step(0.05) }
        function down(): void { audio.step(-0.05) }
        function mute(): void { audio.toggleMute(audio.sink) }
    }

    Process { id: launcher }
    function launch(argv) { launcher.command = argv; launcher.startDetached(); panelScreen = null }

    // ── One volume row: [mute button] [slider] [percent] ────────────────────
    component VolumeRow: RowLayout {
        id: row
        required property var node
        property string icon: audio.volIcon(node?.audio?.volume ?? 0, node?.audio?.muted ?? false)
        property string iconSource: ""
        spacing: 10

        Rectangle {
            implicitWidth: 40; implicitHeight: 40; radius: 20
            color: (row.node?.audio?.muted ?? false) ? theme.clrBgAlt : theme.clrAccentC
            Behavior on color { ColorAnimation { duration: 150 } }
            IconImage {
                anchors.centerIn: parent
                visible: row.iconSource !== ""
                source: row.iconSource
                implicitSize: 22
                opacity: (row.node?.audio?.muted ?? false) ? 0.4 : 1
            }
            Text {
                anchors.centerIn: parent
                visible: row.iconSource === ""
                text: row.icon
                font.family: theme.fontFamily; font.pixelSize: 18
                color: (row.node?.audio?.muted ?? false) ? theme.clrFgMuted : theme.clrOnAccentC
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: audio.toggleMute(row.node) }
        }
        MSlider {
            Layout.fillWidth: true
            theme: audio.theme
            value: row.node?.audio?.volume ?? 0
            muted: row.node?.audio?.muted ?? false
            onMoved: (v) => audio.setVolume(row.node, v)
        }
        Text {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: Math.round((row.node?.audio?.volume ?? 0) * 100) + "%"
            font.family: theme.fontFamily; font.pixelSize: 12
            color: theme.clrFgMuted
        }
    }

    // ── Device picker: one radio row per device ──────────────────────────────
    component DeviceList: ColumnLayout {
        id: dl
        required property var devices
        required property var current
        signal picked(var node)
        spacing: 2
        Repeater {
            model: dl.devices
            Rectangle {
                required property var modelData
                readonly property bool isCurrent: modelData === dl.current
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 17
                color: isCurrent ? Qt.alpha(theme.clrAccent, 0.14) : (devHover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent")
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 10
                    Text {
                        text: isCurrent ? "󰐾" : "󰄰"        // M3 radio
                        font.family: theme.fontFamily; font.pixelSize: 16
                        color: isCurrent ? theme.clrAccent : theme.clrFgMuted
                    }
                    Text {
                        Layout.fillWidth: true
                        text: audio.nodeName(modelData)
                        elide: Text.ElideRight
                        font.family: theme.fontFamily; font.pixelSize: 12
                        color: theme.clrFg
                    }
                }
                HoverHandler { id: devHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dl.picked(modelData) }
            }
        }
    }

    component SectionLabel: Text {
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        color: theme.clrAccent
        Layout.topMargin: 6
    }

    // Click anywhere outside this panel (and the bars) to close it
    HyprlandFocusGrab {
        active: audioPanel.visible
        windows: [audioPanel].concat(theme.barWindows)
        onCleared: audio.panelScreen = null
    }

    PanelWindow {
        id: audioPanel
        screen: audio.panelScreen ?? Quickshell.screens[0]
        visible: audio.panelScreen !== null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + theme.barMarginTop + 10; right: theme.barMarginSide + 6 }
        implicitWidth: 420
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-audio"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: audio.panelScreen = null

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
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: "Sound"
                            font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true
                            color: theme.clrFg
                        }
                        Repeater {
                            model: [
                                { label: "wiremix", icon: "󰆍", argv: theme.term("wiremix", "Mixer", ["wiremix"]) },
                                { label: "pavucontrol", icon: "󰒓", argv: ["pavucontrol"] },
                            ]
                            Rectangle {
                                required property var modelData
                                implicitWidth: btnRow.implicitWidth + 20
                                implicitHeight: 30; radius: 15
                                color: btnHover.hovered ? theme.clrAccentC : "transparent"
                                border.width: 1; border.color: theme.clrBorder
                                RowLayout {
                                    id: btnRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: modelData.icon; font.family: theme.fontFamily; font.pixelSize: 13; color: btnHover.hovered ? theme.clrOnAccentC : theme.clrFg }
                                    Text { text: modelData.label; font.family: theme.fontFamily; font.pixelSize: 11; color: btnHover.hovered ? theme.clrOnAccentC : theme.clrFg }
                                }
                                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: audio.launch(modelData.argv) }
                            }
                        }
                    }

                    // Output
                    SectionLabel { text: "Output  ·  " + audio.nodeName(audio.sink) }
                    VolumeRow { Layout.fillWidth: true; node: audio.sink }
                    DeviceList {
                        Layout.fillWidth: true
                        devices: audio.sinks
                        current: audio.sink
                        onPicked: (n) => Pipewire.preferredDefaultAudioSink = n
                    }

                    // Input
                    SectionLabel { text: "Input  ·  " + audio.nodeName(audio.source) }
                    VolumeRow {
                        Layout.fillWidth: true
                        node: audio.source
                        icon: (audio.source?.audio?.muted ?? false) ? "󰍭" : "󰍬"
                    }
                    DeviceList {
                        Layout.fillWidth: true
                        devices: audio.sources
                        current: audio.source
                        onPicked: (n) => Pipewire.preferredDefaultAudioSource = n
                    }

                    // Apps
                    SectionLabel { text: "Apps"; visible: audio.apps.length > 0 }
                    Repeater {
                        model: audio.apps
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.leftMargin: 50
                                text: audio.nodeName(modelData)
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                font.family: theme.fontFamily; font.pixelSize: 11
                                color: theme.clrFgMuted
                            }
                            VolumeRow {
                                Layout.fillWidth: true
                                node: modelData
                                iconSource: audio.appIcon(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
