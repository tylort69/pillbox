import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// System stats: CPU / GPU (NVIDIA) / RAM on the bar, graphs + details in a panel.
// scripts/stats.py every 2 s; nvidia-smi runs once in loop mode (one process).
Scope {
    id: stats
    required property var theme

    property var sys: null                      // from stats.py
    property var gpu: null                      // { util, vramUsed, vramTotal, temp, fan, power, clock }
    property var cpuHist: []
    property var gpuHist: []
    property var memHist: []
    readonly property int histLen: 60           // 2 minutes at 2 s
    property var panelScreen: null

    readonly property real cpu: sys?.cpu ?? 0
    readonly property real mem: sys ? 100 * sys.memUsed / sys.memTotal : 0
    readonly property real gpuUtil: gpu?.util ?? 0

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    function push(arr, v) { const a = arr.concat([v]); return a.length > histLen ? a.slice(a.length - histLen) : a }
    function gb(bytes) { return (bytes / 1073741824).toFixed(1) }
    function level(p) { return p >= 90 ? theme.clrUrgent : p >= 70 ? theme.clrTertC : theme.clrFg }
    function uptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        return (d ? d + "d " : "") + (h ? h + "h " : "") + m + "m"
    }

    Process {
        id: sysProc
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/stats.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    stats.sys = JSON.parse(text)
                    stats.cpuHist = stats.push(stats.cpuHist, stats.sys.cpu)
                    stats.memHist = stats.push(stats.memHist, stats.mem)
                } catch (e) {}
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sysProc.running = true }

    Process {
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,fan.speed,power.draw,clocks.gr,name",
                  "--format=csv,noheader,nounits", "-lms", "2000"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                const f = line.split(",").map(x => x.trim())
                if (f.length < 8) return
                const n = (x) => isNaN(parseFloat(x)) ? null : parseFloat(x)
                stats.gpu = { util: n(f[0]) ?? 0, vramUsed: n(f[1]), vramTotal: n(f[2]), temp: n(f[3]),
                              fan: n(f[4]), power: n(f[5]), clock: n(f[6]), name: f[7] }
                stats.gpuHist = stats.push(stats.gpuHist, stats.gpu.util)
            }
        }
    }

    IpcHandler {
        target: "stats"
        function toggle(): void { stats.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
    }

    // ── Sparkline graph ──────────────────────────────────────────────────────
    component Graph: Canvas {
        id: g
        property var values: []
        property color stroke: theme.clrAccent
        implicitHeight: 56
        onValuesChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height, n = stats.histLen
            if (values.length < 2) return
            const x = (i) => w - (values.length - 1 - i) * (w / (n - 1))
            const y = (v) => h - 2 - (Math.max(0, Math.min(100, v)) / 100) * (h - 4)
            ctx.beginPath()
            ctx.moveTo(x(0), h)
            for (let i = 0; i < values.length; i++) ctx.lineTo(x(i), y(values[i]))
            ctx.lineTo(x(values.length - 1), h)
            ctx.closePath()
            ctx.fillStyle = Qt.alpha(g.stroke, 0.18)
            ctx.fill()
            ctx.beginPath()
            for (let i = 0; i < values.length; i++) i ? ctx.lineTo(x(i), y(values[i])) : ctx.moveTo(x(i), y(values[i]))
            ctx.strokeStyle = g.stroke
            ctx.lineWidth = 2
            ctx.stroke()
        }
    }

    component StatCard: Rectangle {
        id: sc
        property string title
        property string icon
        property string big
        property string detail
        property var values: []
        property color tint: theme.clrAccent
        Layout.fillWidth: true
        implicitHeight: scCol.implicitHeight + 24
        radius: 20
        color: theme.clrBgAlt
        ColumnLayout {
            id: scCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text { text: sc.icon + "  " + sc.title; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent; Layout.fillWidth: true }
                Text { text: sc.big; font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg }
            }
            Graph { Layout.fillWidth: true; values: sc.values; stroke: sc.tint }
            Text { Layout.fillWidth: true; text: sc.detail; wrapMode: Text.Wrap; font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        active: statsPanel.visible
        windows: [statsPanel].concat(theme.barWindows)
        onCleared: stats.panelScreen = null
    }

    PanelWindow {
        id: statsPanel
        screen: stats.panelScreen ?? Quickshell.screens[0]
        visible: stats.panelScreen !== null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + theme.barMarginTop + 10; right: theme.barMarginSide + 6 }
        implicitWidth: 460
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.85)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-stats"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: stats.panelScreen = null

            Flickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "System"; font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg; Layout.fillWidth: true }
                        Text {
                            text: "up " + stats.uptime(stats.sys?.uptime ?? 0) + "  ·  load " + (stats.sys?.load ?? []).join(" ")
                            font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                        }
                    }

                    StatCard {
                        title: "CPU"; icon: "󰻠"
                        big: Math.round(stats.cpu) + "%"
                        values: stats.cpuHist
                        detail: (stats.sys?.cpuTemp != null ? stats.sys.cpuTemp + " °C" : "") + "  ·  " + (stats.sys?.cores.length ?? 0) + " threads"
                    }
                    // Per-core bars
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 14
                        color: theme.clrBgAlt
                        RowLayout {
                            anchors { fill: parent; margins: 8 }
                            spacing: 3
                            Repeater {
                                model: stats.sys?.cores ?? []
                                Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 3
                                    color: Qt.alpha(theme.clrFg, 0.08)
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        height: parent.height * Math.min(1, modelData / 100)
                                        radius: 3
                                        color: modelData >= 90 ? theme.clrUrgent : theme.clrAccent
                                        Behavior on height { NumberAnimation { duration: 300 } }
                                    }
                                }
                            }
                        }
                    }

                    StatCard {
                        title: stats.gpu?.name ?? "GPU"; icon: "󰢮"
                        big: Math.round(stats.gpuUtil) + "%"
                        values: stats.gpuHist
                        tint: theme.clrOnTertC
                        detail: stats.gpu ? [
                            stats.gpu.temp != null ? Math.round(stats.gpu.temp) + " °C" : "",
                            "VRAM " + (stats.gpu.vramUsed / 1024).toFixed(1) + " / " + (stats.gpu.vramTotal / 1024).toFixed(1) + " GB",
                            stats.gpu.power != null ? Math.round(stats.gpu.power) + " W" : "",
                            stats.gpu.clock != null ? stats.gpu.clock + " MHz" : "",
                            stats.gpu.fan != null ? "fan " + stats.gpu.fan + "%" : ""
                        ].filter(x => x).join("  ·  ") : "No NVIDIA GPU (nvidia-smi) found"
                    }

                    StatCard {
                        title: "Memory"; icon: "󰍛"
                        big: Math.round(stats.mem) + "%"
                        values: stats.memHist
                        tint: theme.clrFgMuted
                        detail: stats.sys ? stats.gb(stats.sys.memUsed) + " / " + stats.gb(stats.sys.memTotal) + " GB"
                                + (stats.sys.swapTotal ? "  ·  swap (zram) " + stats.gb(stats.sys.swapUsed) + " / " + stats.gb(stats.sys.swapTotal) + " GB" : "") : ""
                    }

                    // Disks
                    Repeater {
                        model: stats.sys?.disks ?? []
                        Rectangle {
                            required property var modelData
                            readonly property real pct: modelData.used / modelData.total
                            Layout.fillWidth: true
                            implicitHeight: 54
                            radius: 18
                            color: theme.clrBgAlt
                            ColumnLayout {
                                anchors { fill: parent; margins: 12 }
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "󰋊  Disk  " + modelData.mount; font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true; color: theme.clrAccent; Layout.fillWidth: true }
                                    Text { text: stats.gb(modelData.used) + " / " + stats.gb(modelData.total) + " GB"; font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 8; radius: 4
                                    color: Qt.alpha(theme.clrFg, 0.08)
                                    Rectangle { width: parent.width * pct; height: parent.height; radius: 4; color: pct > 0.9 ? theme.clrUrgent : theme.clrAccent }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 16
                        Repeater {
                            model: [
                                { label: "󰍉  Open btop",  argv: theme.term("btop", "btop", ["btop"]) },
                                { label: "󰢮  Open nvtop", argv: theme.term("nvtop", "nvtop", ["nvtop"]) }
                            ]
                            Text {
                                required property var modelData
                                text: modelData.label
                                font.family: theme.fontFamily; font.pixelSize: 11
                                color: toolHover.hovered ? theme.clrAccent : theme.clrFgMuted
                                HoverHandler { id: toolHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        Quickshell.execDetached(modelData.argv)
                                        stats.panelScreen = null
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
