import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

// Wallpaper picker: thumbnails of ~/Pictures/Wallpapers; clicking one sets it
// (hyprpaper + hyprlock) and re-themes everything through matugen.
Scope {
    id: wp
    required property var theme

    property string wallpaperDir: ""             // settings.wallpaperDir
    readonly property string dir: wallpaperDir || Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string scripts: Quickshell.shellDir + "/scripts/"
    property var items: []                      // [{ path, thumb }]
    property string current: ""
    property bool applying: false
    property var panelScreen: null

    function togglePanel(screen) {
        panelScreen = (panelScreen === screen) ? null : screen
        if (panelScreen !== null) refresh()
    }
    function refresh() { listProc.running = true; curProc.running = true }
    function apply(path) {
        if (applying || path === current) return
        applying = true
        current = path
        setProc.command = [scripts + "set-wallpaper.sh", path]
        setProc.running = true
    }
    function random() {
        const others = items.filter(i => i.path !== current)
        if (others.length) apply(others[Math.floor(Math.random() * others.length)].path)
    }

    Process {
        id: listProc
        command: [wp.scripts + "wallpapers.sh", wp.dir]
        stdout: StdioCollector {
            onStreamFinished: wp.items = text.trim().split("\n").filter(l => l).map(l => { try { return JSON.parse(l) } catch (e) { return null } }).filter(x => x)
        }
    }
    Process {
        id: curProc
        command: ["readlink", "-f", Quickshell.env("HOME") + "/.cache/current-wallpaper"]
        stdout: StdioCollector { onStreamFinished: wp.current = text.trim() }
    }
    Process {
        id: setProc
        onExited: (code) => {
            wp.applying = false
            if (code !== 0) Quickshell.execDetached(["notify-send", "-a", "Wallpaper", "Couldn't set wallpaper", "set-wallpaper.sh exited with " + code])
            curProc.running = true
        }
    }
    Component.onCompleted: curProc.running = true

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { wp.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        function random(): void { wp.refresh(); randomLater.restart() }
    }
    Timer { id: randomLater; interval: 800; onTriggered: wp.random() }

    HyprlandFocusGrab {
        active: wpPanel.visible
        windows: [wpPanel].concat(theme.barWindows)
        onCleared: wp.panelScreen = null
    }

    PanelWindow {
        id: wpPanel
        screen: wp.panelScreen ?? Quickshell.screens[0]
        visible: wp.panelScreen !== null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + theme.barMarginTop + 10; right: theme.barMarginSide + 6 }
        implicitWidth: 3 * 200 + 2 * 10 + 32
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-wallpaper"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: wp.panelScreen = null

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: 16 }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "Wallpaper"; font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg }
                        Text {
                            text: wp.applying ? "Applying and re-theming…" : wp.items.length + " in ~/Pictures/Wallpapers  ·  colours follow the wallpaper"
                            font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                        }
                    }
                    Repeater {
                        model: [
                            { icon: "󰒝", tip: "Random", act: () => wp.random() },
                            { icon: "󰉋", tip: "Open folder", act: () => { Quickshell.execDetached(["sh", "-c", 'if command -v yazi >/dev/null; then shift; exec "$@"; else exec xdg-open "$1"; fi', "_", wp.dir].concat(theme.term("yazi", "Wallpapers", ["yazi", wp.dir]))); wp.panelScreen = null } },
                            { icon: "󰑓", tip: "Rescan", act: () => wp.refresh() }
                        ]
                        Rectangle {
                            required property var modelData
                            implicitWidth: 36; implicitHeight: 36; radius: 18
                            color: btnHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                            Text { anchors.centerIn: parent; text: modelData.icon; font.family: theme.fontFamily; font.pixelSize: 18; color: theme.clrFg }
                            HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: !wp.applying; onTapped: modelData.act() }
                        }
                    }
                }

                Text {
                    visible: wp.items.length === 0
                    text: "No images found. Put .png / .jpg / .webp files in ~/Pictures/Wallpapers."
                    font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFgMuted
                }

                GridView {
                    id: grid
                    visible: wp.items.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: Math.min(contentHeight, 3 * cellHeight)
                    cellWidth: 210
                    cellHeight: 135
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: wp.items
                    delegate: Item {
                        required property var modelData
                        readonly property bool isCurrent: modelData.path === wp.current
                        width: grid.cellWidth; height: grid.cellHeight
                        ClippingRectangle {
                            anchors { fill: parent; rightMargin: 10; bottomMargin: 10 }
                            radius: 16
                            color: theme.clrBgAlt
                            border.width: isCurrent ? 3 : tileHover.hovered ? 2 : 0
                            border.color: isCurrent ? theme.clrAccent : theme.clrFgMuted
                            Image {
                                anchors.fill: parent
                                source: "file://" + modelData.thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                opacity: wp.applying && !isCurrent ? 0.5 : 1
                            }
                            Rectangle {
                                visible: isCurrent
                                anchors { right: parent.right; top: parent.top; margins: 8 }
                                implicitWidth: 26; implicitHeight: 26; radius: 13
                                color: theme.clrAccent
                                Text {
                                    anchors.centerIn: parent
                                    text: wp.applying ? "󰔟" : "󰄬"
                                    font.family: theme.fontFamily; font.pixelSize: 14; color: theme.clrOnAccent
                                }
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                implicitHeight: 24
                                color: Qt.alpha(theme.clrBg, 0.7)
                                visible: tileHover.hovered
                                Text {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.path.split("/").pop()
                                    elide: Text.ElideMiddle
                                    font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFg
                                }
                            }
                        }
                        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !wp.applying; onTapped: wp.apply(modelData.path) }
                    }
                }
            }
        }
    }
}
