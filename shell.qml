import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    // ── Bar position (BarSettings.qml): settings.barPosition = top | bottom | left | right,
    //    settings.barMirror reverses the pill order (right-to-left / bottom-to-top) ─────────
    readonly property string barPosition: ["top", "bottom", "left", "right"].includes(settings.barPosition) ? settings.barPosition : "top"
    readonly property bool vertical: barPosition === "left" || barPosition === "right"
    readonly property bool mirror: settings.barMirror
    readonly property int flip: vertical && mirror ? 180 : 0  // vertical mirror: column turned over, pills turned back upright
    readonly property int barHeight: vertical ? 40 : 34     // bar thickness (its width when vertical)
    readonly property int pillSize: vertical ? 32 : 26      // a pill's size across the bar
    property var barWindows: []          // all bar windows; clicks on them never close a panel
    readonly property int barMarginTop: 6                   // gap between the bar and its screen edge
    readonly property int barMarginSide: 10                 // gap at the two ends of the bar
    function barAnchored(e) { return e === barPosition || (vertical ? e === "top" || e === "bottom" : e === "left" || e === "right") }
    function barMargin(e) { return e === barPosition ? barMarginTop : barAnchored(e) ? barMarginSide : 0 }

    // Panels open beside the bar. align = where along the bar the panel belongs: "start" (left /
    // top), "center" or "end" (right / bottom), flipped when mirrored.
    // edge(): should the panel anchor to screen edge e? gap(): its margin from that edge.
    function edge(e, align) {
        if (e === barPosition) return true
        if (mirror) align = align === "start" ? "end" : align === "end" ? "start" : align
        return (align === "start" && e === (vertical ? "top" : "left"))
            || (align === "end" && e === (vertical ? "bottom" : "right"))
    }
    function gap(e, align) {
        return e === barPosition ? barHeight + barMarginTop + 10 : edge(e, align) ? barMarginSide + 6 : 0
    }
    readonly property int cornerRadius: 17          // full pill, Material You style
    readonly property string fontFamily: "FiraCode Nerd Font Mono"
    readonly property int fontSize: 13

    // ── Terminal for btop, logs, updates…: settings.terminal, else $TERMINAL, else the first one installed ─
    readonly property string terminal: settings.terminal || Quickshell.env("TERMINAL") || detectedTerminal
    property string detectedTerminal: "foot"
    Process {
        running: true
        command: ["sh", "-c", "for t in foot kitty alacritty ghostty wezterm konsole gnome-terminal xterm; do command -v $t >/dev/null && { echo $t; exit; }; done"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) root.detectedTerminal = text.trim() }
    }
    // Command array that runs argv in the terminal; appId lets window rules match it.
    function term(appId, title, argv) {
        switch (root.terminal.split("/").pop()) {
        case "foot":           return ["foot", "--app-id", appId, "--title", title, "-e"].concat(argv)
        case "kitty":          return ["kitty", "--class", appId, "--title", title].concat(argv)
        case "alacritty":      return ["alacritty", "--class", appId, "--title", title, "-e"].concat(argv)
        case "wezterm":        return ["wezterm", "start", "--class", appId, "--"].concat(argv)
        case "gnome-terminal": return ["gnome-terminal", "--title", title, "--"].concat(argv)
        default:               return [root.terminal, "-e"].concat(argv)
        }
    }

    // ── Colours: ~/.cache/quickshell-colors.json, written by matugen (see matugen/) ─
    readonly property color clrBg:        palette.bg
    readonly property color clrBgAlt:     palette.bgAlt
    readonly property color clrFg:        palette.fg
    readonly property color clrFgMuted:   palette.fgMuted
    readonly property color clrAccent:    palette.accent
    readonly property color clrOnAccent:  palette.accentText
    readonly property color clrAccentC:   palette.accentContainer
    readonly property color clrOnAccentC: palette.accentContainerText
    readonly property color clrTertC:     palette.tertiaryContainer
    readonly property color clrOnTertC:   palette.tertiaryContainerText
    readonly property color clrUrgent:    palette.urgent
    readonly property color clrBorder:    palette.border

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell-colors.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: palette
            property color bg:                  "#1c2024"
            property color bgAlt:               "#31353a"
            property color fg:                  "#e0e2e8"
            property color fgMuted:             "#c2c7ce"
            property color accent:              "#98ccf9"
            property color accentText:            "#003350"
            property color accentContainer:     "#054b71"
            property color accentContainerText:   "#cde5ff"
            property color tertiaryContainer:   "#4e4163"
            property color tertiaryContainerText: "#eedcff"
            property color urgent:              "#ffb4ab"
            property color border:              "#42474e"
        }
    }

    // ── Settings: ~/.config/quickshell/settings.json (right-click the clock to toggle) ─
    FileView {
        id: settingsFile
        path: Quickshell.shellDir + "/settings.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: settings
            property bool showReykjavik: false      // old setting, migrated into clockAlt.enabled
            property string terminal: ""            // "" = $TERMINAL or auto-detect (foot, kitty, alacritty, …)
            property string wallpaperDir: ""        // "" = ~/Pictures/Wallpapers
            property string barPosition: "top"      // top | bottom | left | right
            property bool barMirror: false          // reverse the pill order along the bar
            // Clocks (click the time in the bar to change these)
            property var clockLocal: ({ precision: "hm", hour24: true, showDate: false, dateFormat: "ddd d MMM" })
            property var clockAlt: ({ enabled: false, label: "UTC", zone: "UTC",
                                      precision: "hm", hour24: true, showDate: false, dateFormat: "ddd d MMM" })
            property var trayPinned: []             // tray item ids shown as icons in the bar
            property bool nightLight: false         // hyprsunset schedule on/off
            property var countdown: ({})            // timer / pomodoro state (Countdown.qml)
            property var pomodoro: ({ work: 25, short: 5, long: 15, every: 4, autoNext: true })
            // Do Not Disturb: active profile name ("" = off) and the profiles.
            // Each profile allows notification *types* and specific *apps*;
            // everything else is silenced (still kept in the history).
            property string dndProfile: ""
            property var dndProfiles: [
                { name: "Work",     icon: "󰃖", types: ["critical", "email", "system"],
                  apps: ["Slack", "Teams", "Thunderbird"] },
                { name: "Gaming",   icon: "󰊴", types: ["critical"],
                  apps: ["Discord"] },
                { name: "Chill",    icon: "󰋋", types: ["critical", "messages", "media"],
                  apps: [] },
                { name: "Chatting", icon: "󰭹", types: ["critical", "messages"],
                  apps: ["Discord", "Signal", "Telegram", "WhatsApp", "Vesktop"] },
                { name: "Sleep",    icon: "󰒲", types: ["critical"],
                  apps: [] }
            ]
        }
    }

    // ── Notifications: the bar is the notification daemon (Notifs.qml) ────────
    Notifs {
        id: notifs
        theme: root
        settings: settings
        otherPanelOpen: root.panels.some(p => p.panelScreen !== null) || cheatsheet.open
        onHistoryScreenChanged: if (historyScreen !== null) root.closeOthers(notifs)
    }

    // ── Sound: volume widget + mixer panel (Audio.qml) ───────────────────────
    Audio {
        id: audio
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(audio)
    }

    // ── Night light: hyprsunset on/off (NightLight.qml) ──────────────────────
    NightLight {
        id: night
        settings: settings
    }

    // ── Keybind cheat sheet: SUPER + / or SUPER + F1 (CheatSheet.qml) ────────
    CheatSheet {
        id: cheatsheet
        theme: root
    }

    // ── Media: now-playing pill + player panel (Media.qml) ───────────────────
    Media {
        id: media
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(media)
    }

    // ── Package updates (Updates.qml) ────────────────────────────────────────
    Updates {
        id: updates
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(updates)
    }

    // ── System stats: CPU / GPU / RAM + graphs panel (SysStats.qml) ─────────
    SysStats {
        id: stats
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(stats)
    }

    // ── Mic / camera / screen-share in use (Privacy.qml) ─────────────────────
    Privacy { id: privacy }

    // ── Caps / Num Lock state (LockKeys.qml) ─────────────────────────────────
    LockKeys { id: locks }

    // ── Bluetooth: devices panel, icon only when an adapter exists (BluetoothPanel.qml)
    BluetoothPanel {
        id: bt
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(bt)
    }

    // ── Network: connection status + details / Wi-Fi panel (Network.qml) ────
    Network {
        id: network
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(network)
    }

    // ── System tray: pinned icons + overflow panel (Tray.qml) ────────────────
    Tray {
        id: tray
        theme: root
        settings: settings
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(tray)
    }

    // ── Clocks: local + second time zone, settings panel (Clocks.qml) ────────
    Clocks {
        id: clocks
        theme: root
        settings: settings
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(clocks)
    }

    // ── Wallpaper picker (Wallpapers.qml) ────────────────────────────────────
    Wallpapers {
        id: wallpapers
        theme: root
        wallpaperDir: settings.wallpaperDir
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(wallpapers)
    }

    // ── Btrfs snapshots (Snapshots.qml) ──────────────────────────────────────
    Snapshots {
        id: snapshots
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(snapshots)
    }

    // ── Failed systemd units (Services.qml) ──────────────────────────────────
    Services {
        id: services
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(services)
    }

    // ── Timer / Pomodoro (Countdown.qml) ─────────────────────────────────────
    Countdown {
        id: countdown
        theme: root
        settings: settings
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(countdown)
    }

    // ── Keyboard layout (Keyboard.qml) ───────────────────────────────────────
    Keyboard {
        id: keyboard
        theme: root
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(keyboard)
    }

    // ── Bar settings: position + mirrored order (BarSettings.qml, gear icon on the bar) ─
    BarSettings {
        id: barSettings
        theme: root
        settings: settings
        onPanelScreenChanged: if (panelScreen !== null) root.closeOthers(barSettings)
    }

    // Every module with a panel. Opening one closes the others (and the notification history).
    readonly property var panels: [audio, clocks, media, tray, network, bt, stats, updates,
                                   wallpapers, snapshots, services, countdown, keyboard, barSettings]
    function closeOthers(keep) {
        if (keep !== notifs) notifs.historyScreen = null
        for (const p of panels) {
            if (p === keep || p.panelScreen === null) continue
            if (p === tray) tray.close(); else p.panelScreen = null
        }
    }

    // ── Hyprland submap (monitor -> workspace picker) ─────────────────────────
    property string submap: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.submap = event.data
            if (["activewindowv2", "closewindow", "openwindow", "movewindowv2", "windowtitlev2", "workspacev2"].includes(event.name))
                windowRefresh.restart()
        }
    }
    // Workspace info (each workspace's last-focused window) for the window titles, debounced
    Timer {
        id: windowRefresh
        interval: 120
        onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels() }
    }
    function appIcon(cls) {
        if (!cls) return ""
        const e = DesktopEntries.byId(cls) ?? DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e?.icon ?? cls.toLowerCase(), true)
    }

    // Hyprland's Lua config (hyprland.lua) takes Lua dispatchers; hyprland.conf takes the classic ones.
    property bool luaConfig: false
    Process {
        running: true
        command: ["sh", "-c", "test -f \"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua\" && echo lua"]
        stdout: StdioCollector { onStreamFinished: root.luaConfig = text.trim() === "lua" }
    }
    function focusWorkspace(name) {
        if (root.luaConfig) Hyprland.dispatch('hl.dsp.focus({ workspace = "' + name + '" })')
        else Hyprland.dispatch("workspace " + name)
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            Component.onCompleted: root.barWindows = root.barWindows.concat([barWindow])
            Component.onDestruction: root.barWindows = root.barWindows.filter(w => w !== barWindow)
            required property var modelData
            screen: modelData

            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
            readonly property bool monitorFocused: Hyprland.focusedMonitor?.name === hyprMonitor?.name

            // Window shown in this bar: the focused window on the focused monitor,
            // otherwise the last-focused window of this monitor's visible workspace
            readonly property var shownWindow: {
                if (monitorFocused && Hyprland.activeToplevel && Hyprland.activeToplevel.workspace === hyprMonitor?.activeWorkspace)
                    return Hyprland.activeToplevel
                const ws = hyprMonitor?.activeWorkspace
                if (!ws) return null
                const last = ((ws.lastIpcObject?.lastwindow ?? "") + "").replace(/^0x/, "")
                const tops = ws.toplevels.values
                return tops.find(t => (t.address + "").replace(/^0x/, "") === last) ?? (tops.length === 1 ? tops[0] : null)
            }

            // split-monitor-workspaces gives every monitor its own range of
            // workspace IDs (e.g. 41-50 on the LG). Show only this monitor's
            // workspaces, numbered 1..N locally like the SUPER+N binds.
            readonly property var monitorWorkspaces: Hyprland.workspaces.values
                .filter(w => w.id > 0 && w.monitor && w.monitor.name === hyprMonitor?.name)
                .sort((a, b) => a.id - b.id)

            function cycle(step) {
                const list = monitorWorkspaces
                if (list.length === 0) return
                let i = list.findIndex(w => w.id === hyprMonitor?.activeWorkspace?.id)
                i = (i + step + list.length) % list.length
                root.focusWorkspace(list[i].name)
            }

            anchors {
                top: root.barAnchored("top"); bottom: root.barAnchored("bottom")
                left: root.barAnchored("left"); right: root.barAnchored("right")
            }
            margins {
                top: root.barMargin("top"); bottom: root.barMargin("bottom")
                left: root.barMargin("left"); right: root.barMargin("right")
            }

            implicitHeight: root.vertical ? 0 : root.barHeight
            implicitWidth: root.vertical ? root.barHeight : 0
            color: "transparent"

            Rectangle {
                Layout.alignment: Qt.AlignCenter
                anchors.fill: parent
                color: root.clrBg
                radius: root.cornerRadius
                border.color: root.clrBorder
                border.width: 1
                Behavior on color { ColorAnimation { duration: 250 } }

                GridLayout {
                    Layout.alignment: Qt.AlignCenter
                    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                    layoutDirection: root.mirror && !root.vertical ? Qt.RightToLeft : Qt.LeftToRight
                    rotation: root.flip
                    anchors.fill: parent
                    anchors.leftMargin: root.vertical ? 4 : root.mirror ? 12 : 6
                    anchors.rightMargin: root.vertical ? 4 : root.mirror ? 6 : 12
                    anchors.topMargin: root.vertical ? 6 : 0
                    anchors.bottomMargin: root.vertical ? 6 : 0
                    rowSpacing: 8
                    columnSpacing: 8

                    // ── Left: this monitor's workspaces ──────────────────────
                    Rectangle {
                        rotation: root.flip
                        Layout.alignment: Qt.AlignCenter
                        implicitWidth: root.vertical ? root.pillSize : wsRow.implicitWidth + 8
                        implicitHeight: root.vertical ? wsRow.implicitHeight + 12 : 26
                        radius: Math.min(width, height) / 2
                        color: root.clrBgAlt

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: (wheel) => barWindow.cycle(wheel.angleDelta.y > 0 ? -1 : 1)
                        }

                        GridLayout {
                            Layout.alignment: Qt.AlignCenter
                            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            id: wsRow
                            anchors.centerIn: parent
                            rowSpacing: 2
                            columnSpacing: 2

                            Repeater {
                                model: barWindow.monitorWorkspaces

                                Rectangle {
                                    Layout.alignment: Qt.AlignCenter
                                    id: wsPill
                                    required property var modelData
                                    required property int index
                                    readonly property bool isActive: barWindow.hyprMonitor?.activeWorkspace?.id === modelData.id
                                    readonly property bool isFocused: isActive && barWindow.monitorFocused
                                    readonly property bool isOccupied: (modelData.toplevels?.values?.length ?? 0) > 0
                                    readonly property bool isUrgent: modelData.urgent ?? false

                                    implicitWidth: !root.vertical && isActive ? 34 : 20
                                    implicitHeight: root.vertical && isActive ? 34 : 20
                                    radius: 10

                                    color: isUrgent   ? root.clrUrgent
                                         : isFocused  ? root.clrAccent
                                         : isActive   ? root.clrAccentC
                                         : wsMouse.containsMouse ? Qt.alpha(root.clrFg, 0.08)
                                         : "transparent"

                                    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        Layout.alignment: Qt.AlignCenter
                                        anchors.centerIn: parent
                                        text: wsPill.index === 9 ? "0" : (wsPill.index + 1)
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontSize - 1
                                        font.bold: wsPill.isActive || wsPill.isOccupied
                                        color: wsPill.isUrgent   ? root.clrBg
                                             : wsPill.isFocused  ? root.clrOnAccent
                                             : wsPill.isActive   ? root.clrOnAccentC
                                             : wsPill.isOccupied ? root.clrFg
                                             : Qt.alpha(root.clrFgMuted, 0.55)
                                    }

                                    MouseArea {
                                        id: wsMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.focusWorkspace(wsPill.modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    // Now playing: click = player panel, middle = play/pause, scroll = next/previous
                    Rectangle {
                        rotation: root.flip
                        Layout.alignment: Qt.AlignCenter
                        id: mediaPill
                        readonly property bool open: media.panelScreen === barWindow.modelData
                        visible: media.hasPlayer
                        implicitWidth: root.vertical ? root.pillSize : mediaRow.implicitWidth + 16
                        implicitHeight: root.vertical ? mediaRow.implicitHeight + 12 : 26
                        radius: Math.min(width, height) / 2
                        clip: true
                        color: open ? root.clrAccentC : mediaMouse.containsMouse ? root.clrBgAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        GridLayout {
                            Layout.alignment: Qt.AlignCenter
                            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            id: mediaRow
                            anchors.centerIn: parent
                            rowSpacing: 8
                            columnSpacing: 8
                            ClippingRectangle {
                                Layout.alignment: Qt.AlignCenter
                                implicitWidth: 18; implicitHeight: 18; radius: 9
                                color: root.clrAccentC
                                Image {
                                    anchors.fill: parent
                                    source: media.player?.trackArtUrl ?? ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize: Qt.size(36, 36)
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                Layout.maximumWidth: 280
                                visible: !root.vertical
                                text: (media.player?.trackTitle ?? "") + (media.artist(media.player) ? "  ·  " + media.artist(media.player) : "")
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                                color: mediaPill.open ? root.clrOnAccentC : root.clrFg
                            }
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                text: media.player?.isPlaying ? "󰏤" : "󰐊"
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize + 1
                                color: mediaPill.open ? root.clrOnAccentC : root.clrAccent
                            }
                        }
                        // thin progress line along the bottom
                        Rectangle {
                            Layout.alignment: Qt.AlignCenter
                            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 10; bottomMargin: 2 }
                            height: 2; radius: 1
                            width: (parent.width - 20) * media.progress
                            color: root.clrAccent
                            visible: (media.player?.length ?? 0) > 0
                        }

                        MouseArea {
                            id: mediaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.MiddleButton) media.player?.togglePlaying()
                                else media.togglePanel(barWindow.modelData)
                            }
                            onWheel: (wheel) => { if (wheel.angleDelta.y > 0) media.player?.previous(); else media.player?.next() }
                        }
                    }

                    // Active window: app icon + title
                    GridLayout {
                        rotation: root.flip
                        Layout.alignment: Qt.AlignCenter
                        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                        visible: !root.vertical && barWindow.shownWindow !== null && (barWindow.shownWindow.title ?? "") !== ""
                        Layout.maximumWidth: 420
                        Layout.leftMargin: 4
                        rowSpacing: 8
                        columnSpacing: 8
                        IconImage {
                            Layout.alignment: Qt.AlignCenter
                            readonly property string cls: barWindow.shownWindow?.lastIpcObject?.class ?? barWindow.shownWindow?.wayland?.appId ?? ""
                            visible: source !== ""
                            source: root.appIcon(cls)
                            implicitSize: 16
                        }
                        Text {
                            Layout.alignment: Qt.AlignCenter
                            Layout.fillWidth: true
                            Layout.maximumWidth: 390
                            text: barWindow.shownWindow?.title ?? ""
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize - 1
                            color: barWindow.monitorFocused ? root.clrFg : root.clrFgMuted
                        }
                    }

                    Item { Layout.fillWidth: true; Layout.fillHeight: true }

                    // ── Center: clocks ───────────────────────────────────────
                    // Left-click: clock settings · Right-click: show/hide the second clock
                    Rectangle {
                        rotation: root.flip
                        Layout.alignment: Qt.AlignCenter
                        readonly property bool open: clocks.panelScreen === barWindow.modelData
                        implicitWidth: root.vertical ? root.pillSize : clockRow.implicitWidth + 20
                        implicitHeight: root.vertical ? clockRow.implicitHeight + 12 : 26
                        radius: Math.min(width, height) / 2
                        color: open ? root.clrAccentC : clockMouse.containsMouse ? root.clrBgAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        GridLayout {
                            Layout.alignment: Qt.AlignCenter
                            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            id: clockRow
                            anchors.centerIn: parent
                            rowSpacing: 10
                            columnSpacing: 10

                            Text {
                                Layout.alignment: Qt.AlignCenter
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize
                                font.bold: true
                                color: parent.parent.open ? root.clrOnAccentC : root.clrFg
                                horizontalAlignment: Text.AlignHCenter
                                text: root.vertical ? clocks.localText.replace(/[: ]+/g, "\n") : clocks.localText
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignCenter
                                visible: clocks.alt.enabled
                                implicitWidth: root.vertical ? root.pillSize - 6 : altText.implicitWidth + 14
                                implicitHeight: root.vertical ? altText.implicitHeight + 10 : 20
                                radius: 10
                                color: root.clrAccentC
                                border.width: parent.parent.open ? 1 : 0
                                border.color: root.clrOnAccentC

                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    id: altText
                                    anchors.centerIn: parent
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 2
                                    color: root.clrOnAccentC
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.vertical ? clocks.altText.replace(/[: ]+/g, "\n")
                                        : (clocks.alt.label ? clocks.alt.label + " " : "") + clocks.altText
                                }
                            }
                        }

                        MouseArea {
                            id: clockMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton)
                                    clocks.update("alt", { enabled: !clocks.alt.enabled })
                                else
                                    clocks.togglePanel(barWindow.modelData)
                            }
                        }
                    }

                    // Timer / Pomodoro: faint icon when idle, countdown while running.
                    // Click = panel · middle = pause/resume · right = stop
                    Rectangle {
                        rotation: root.flip
                        Layout.alignment: Qt.AlignCenter
                        readonly property bool open: countdown.panelScreen === barWindow.modelData
                        readonly property bool brk: countdown.mode === "pomodoro" && countdown.phase !== "work"
                        implicitWidth: root.vertical ? root.pillSize : cdRow.implicitWidth + 16
                        implicitHeight: root.vertical ? cdRow.implicitHeight + 12 : 26
                        radius: Math.min(width, height) / 2
                        clip: true
                        color: open ? root.clrAccentC
                             : countdown.active ? (brk ? root.clrTertC : root.clrBgAlt)
                             : cdMouse.containsMouse ? root.clrBgAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        GridLayout {
                            Layout.alignment: Qt.AlignCenter
                            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            id: cdRow
                            anchors.centerIn: parent
                            rowSpacing: 5
                            columnSpacing: 5
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                text: countdown.mode === "pomodoro" && countdown.active ? countdown.phaseInfo[countdown.phase].icon : "󱎫"
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize + 1
                                color: parent.parent.open ? root.clrOnAccentC
                                     : parent.parent.brk && countdown.active ? root.clrOnTertC
                                     : countdown.active ? root.clrAccent : root.clrFgMuted
                            }
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                visible: countdown.active
                                horizontalAlignment: Text.AlignHCenter
                                text: root.vertical ? countdown.fmt(countdown.left).replace(/:/g, "\n") : countdown.fmt(countdown.left)
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                                font.bold: true
                                color: parent.parent.open ? root.clrOnAccentC
                                     : parent.parent.brk ? root.clrOnTertC
                                     : countdown.status === "paused" ? root.clrFgMuted : root.clrFg
                            }
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignCenter
                            visible: countdown.active
                            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 8; bottomMargin: 2 }
                            height: 2; radius: 1
                            width: (parent.width - 16) * countdown.progress
                            color: root.clrAccent
                        }
                        MouseArea {
                            id: cdMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.MiddleButton) countdown.toggle()
                                else if (mouse.button === Qt.RightButton) countdown.stop()
                                else countdown.togglePanel(barWindow.modelData)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; Layout.fillHeight: true }

                    // ── Right: system tray, then notification bell ───────────
                    GridLayout {
                        Layout.alignment: Qt.AlignCenter
                        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                        rowSpacing: 8
                        columnSpacing: 8
                        // Privacy: shown while an app uses the mic, camera or screen
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            visible: privacy.active
                            implicitWidth: root.vertical ? root.pillSize : privRow.implicitWidth + 16
                            implicitHeight: root.vertical ? privRow.implicitHeight + 12 : 24
                            radius: Math.min(width, height) / 2
                            color: Qt.alpha(root.clrUrgent, 0.22)
                            border.width: 1
                            border.color: root.clrUrgent
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: privRow
                                anchors.centerIn: parent
                                rowSpacing: 6
                                columnSpacing: 6
                                Text { Layout.alignment: Qt.AlignCenter; visible: privacy.mic.length > 0; text: "󰍬"; font.family: root.fontFamily; font.pixelSize: root.fontSize; color: root.clrUrgent }
                                Text { Layout.alignment: Qt.AlignCenter; visible: privacy.camera.length > 0; text: "󰄀"; font.family: root.fontFamily; font.pixelSize: root.fontSize; color: root.clrUrgent }
                                Text { Layout.alignment: Qt.AlignCenter; visible: privacy.screen.length > 0; text: "󰹑"; font.family: root.fontFamily; font.pixelSize: root.fontSize; color: root.clrUrgent }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    Layout.maximumWidth: 160
                                    visible: !root.vertical
                                    text: privacy.apps.join(", ")
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2
                                    color: root.clrFg
                                }
                            }
                        }

                        // Wallpaper picker, snapshots, bar settings
                        Repeater {
                            model: [
                                { icon: "󰸉", mod: wallpapers },
                                { icon: "󰁯", mod: snapshots },
                                { icon: "󰒓", mod: barSettings }
                            ]
                            Rectangle {
                                rotation: root.flip
                                Layout.alignment: Qt.AlignCenter
                                required property var modelData
                                readonly property bool open: modelData.mod.panelScreen === barWindow.modelData
                                implicitWidth: root.pillSize
                                implicitHeight: 26
                                radius: Math.min(width, height) / 2
                                color: open ? root.clrAccentC : iconMouse.containsMouse ? root.clrBgAlt : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.open ? root.clrOnAccentC : root.clrFg
                                }
                                MouseArea {
                                    id: iconMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.mod.togglePanel(barWindow.modelData)
                                }
                            }
                        }

                        // Clipboard history (clipse, also SUPER + SHIFT + V)
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            implicitWidth: root.pillSize
                            implicitHeight: 26
                            radius: Math.min(width, height) / 2
                            color: clipMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                anchors.centerIn: parent
                                text: "󰅌"
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize + 1
                                color: root.clrFg
                            }
                            MouseArea {
                                id: clipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(root.term("clipse", "Clipboard", ["clipse"]))
                            }
                        }

                        // Updates: shown when packages are waiting
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: updates.panelScreen === barWindow.modelData
                            visible: updates.count > 0 || open
                            implicitWidth: root.vertical ? root.pillSize : updRow.implicitWidth + 16
                            implicitHeight: root.vertical ? updRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC : updMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: updRow
                                anchors.centerIn: parent
                                rowSpacing: 4
                                columnSpacing: 4
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: updates.updating ? "󰚰" : "󰏗"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrAccent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: updates.count
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2; font.bold: true
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrFg
                                }
                            }
                            MouseArea {
                                id: updMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: updates.togglePanel(barWindow.modelData)
                            }
                        }

                        // Failed systemd units: only shown when something failed
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: services.panelScreen === barWindow.modelData
                            visible: services.count > 0 || open
                            implicitWidth: root.vertical ? root.pillSize : svcRow.implicitWidth + 16
                            implicitHeight: root.vertical ? svcRow.implicitHeight + 12 : 24
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC : Qt.alpha(root.clrUrgent, svcMouse.containsMouse ? 0.3 : 0.18)
                            border.width: open ? 0 : 1
                            border.color: root.clrUrgent
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: svcRow
                                anchors.centerIn: parent
                                rowSpacing: 4
                                columnSpacing: 4
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: "󰒏"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrUrgent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: services.count
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2; font.bold: true
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrFg
                                }
                            }
                            MouseArea {
                                id: svcMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: services.togglePanel(barWindow.modelData)
                            }
                        }

                        // System stats: CPU / GPU / RAM (amber >= 70%, red >= 90%)
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: stats.panelScreen === barWindow.modelData
                            implicitWidth: root.vertical ? root.pillSize : statRow.implicitWidth + 16
                            implicitHeight: root.vertical ? statRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC : statMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: statRow
                                anchors.centerIn: parent
                                rowSpacing: 10
                                columnSpacing: 10
                                Repeater {
                                    model: [["󰻠", stats.cpu]].concat(stats.gpu ? [["󰢮", stats.gpuUtil]] : []).concat([["󰍛", stats.mem]])
                                    Text {
                                        Layout.alignment: Qt.AlignCenter
                                        required property var modelData
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData[0] + (root.vertical ? "\n" : " ") + Math.round(modelData[1]) + "%"
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fontSize - 2
                                        color: parent.parent.open ? root.clrOnAccentC
                                             : modelData[1] >= 90 ? root.clrUrgent
                                             : modelData[1] >= 70 ? root.clrAccent : root.clrFgMuted
                                    }
                                }
                            }
                            MouseArea {
                                id: statMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: stats.togglePanel(barWindow.modelData)
                            }
                        }

                        // Pinned tray apps: left = open, right = menu (in the tray panel), middle = secondary
                        Repeater {
                            model: tray.pinned

                            IconImage {
                                rotation: root.flip
                                Layout.alignment: Qt.AlignCenter
                                required property var modelData
                                source: modelData.icon
                                implicitSize: 16

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) tray.openMenu(barWindow.modelData, modelData)
                                        else if (mouse.button === Qt.MiddleButton) modelData.secondaryActivate()
                                        else tray.primary(barWindow.modelData, modelData)
                                    }
                                }
                            }
                        }

                        // Tray overflow button: opens the tray panel (unpinned apps live there)
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: tray.panelScreen === barWindow.modelData
                            visible: tray.items.length > 0
                            implicitWidth: root.vertical ? root.pillSize : ovRow.implicitWidth + 16
                            implicitHeight: root.vertical ? ovRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC : ovMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: ovRow
                                anchors.centerIn: parent
                                rowSpacing: 4
                                columnSpacing: 4
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: parent.parent.open ? "󰅃" : "󰅀"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrFg
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: tray.unpinned.length > 0
                                    text: tray.unpinned.length
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 2
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrFgMuted
                                }
                            }
                            MouseArea {
                                id: ovMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: tray.togglePanel(barWindow.modelData)
                            }
                        }

                        // Network: icon by connection type; warning badge when there's no internet
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: network.panelScreen === barWindow.modelData
                            implicitWidth: root.vertical ? root.pillSize : netRow.implicitWidth + 16
                            implicitHeight: root.vertical ? netRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC : netMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: netRow
                                anchors.centerIn: parent
                                rowSpacing: 3
                                columnSpacing: 3
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: network.icon
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : network.linkUp ? root.clrFg : root.clrUrgent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: network.linkUp && network.checks !== null && !network.online
                                    text: "󰀦"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 1
                                    color: root.clrUrgent
                                }
                            }
                            MouseArea {
                                id: netMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: network.togglePanel(barWindow.modelData)
                            }
                        }

                        // Bluetooth: hidden without an adapter; shows connected-device count
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: bt.panelScreen === barWindow.modelData
                            visible: bt.available
                            implicitWidth: root.vertical ? root.pillSize : btRow.implicitWidth + 16
                            implicitHeight: root.vertical ? btRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC : btMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: btRow
                                anchors.centerIn: parent
                                rowSpacing: 3
                                columnSpacing: 3
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: bt.icon
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : bt.powered ? root.clrFg : root.clrFgMuted
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: bt.connected.length > 1
                                    text: bt.connected.length
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 2
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrFgMuted
                                }
                            }
                            MouseArea {
                                id: btMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bt.togglePanel(barWindow.modelData)
                            }
                        }

                        // Lock keys: only shown when unusual (Caps Lock on / Num Lock off)
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            visible: locks.caps || !locks.num
                            implicitWidth: root.vertical ? root.pillSize : lockRow.implicitWidth + 14
                            implicitHeight: root.vertical ? lockRow.implicitHeight + 12 : 22
                            radius: Math.min(width, height) / 2
                            color: root.clrTertC
                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: lockRow
                                anchors.centerIn: parent
                                rowSpacing: 8
                                columnSpacing: 8
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: locks.caps
                                    text: root.vertical ? "󰪛" : "󰪛 CAPS"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2; font.bold: true
                                    color: root.clrOnTertC
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: !locks.num
                                    text: root.vertical ? "󰎠" : "󰎠 NUM off"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2; font.bold: true
                                    color: root.clrOnTertC
                                }
                            }
                        }

                        // Keyboard layout: click = next layout · right-click = list · scroll = switch
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            readonly property bool open: keyboard.panelScreen === barWindow.modelData
                            visible: keyboard.codes.length > 1
                            implicitWidth: root.vertical ? root.pillSize : kbText.implicitWidth + 16
                            implicitHeight: root.vertical ? kbText.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: open ? root.clrAccentC
                                 : keyboard.index > 0 ? root.clrTertC
                                 : kbMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                id: kbText
                                anchors.centerIn: parent
                                text: keyboard.short
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                                font.bold: true
                                color: parent.open ? root.clrOnAccentC : keyboard.index > 0 ? root.clrOnTertC : root.clrFg
                            }
                            MouseArea {
                                id: kbMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) keyboard.togglePanel(barWindow.modelData)
                                    else keyboard.next()
                                }
                                onWheel: (wheel) => keyboard.next()
                            }
                        }

                        // Volume: left-click = sound panel, middle = mute,
                        // right-click = pavucontrol, scroll = ±5%
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            implicitWidth: root.vertical ? root.pillSize : volRow.implicitWidth + 16
                            implicitHeight: root.vertical ? volRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: audio.panelScreen === barWindow.modelData ? root.clrAccentC
                                 : volMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: volRow
                                anchors.centerIn: parent
                                rowSpacing: 5
                                columnSpacing: 5
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: audio.volIcon(audio.volume, audio.muted)
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 2
                                    color: audio.panelScreen === barWindow.modelData ? root.clrOnAccentC
                                         : audio.muted ? root.clrFgMuted : root.clrFg
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: Math.round(audio.volume * 100) + "%"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 1
                                    color: audio.panelScreen === barWindow.modelData ? root.clrOnAccentC : root.clrFgMuted
                                }
                            }

                            MouseArea {
                                id: volMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.MiddleButton) audio.toggleMute(audio.sink)
                                    else if (mouse.button === Qt.RightButton) audio.launch("pavucontrol")
                                    else audio.togglePanel(barWindow.modelData)
                                }
                                onWheel: (wheel) => audio.step(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
                            }
                        }

                        // Night light: click = on/off, scroll = warmer/cooler
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            implicitWidth: root.vertical ? root.pillSize : nightRow.implicitWidth + 16
                            implicitHeight: root.vertical ? nightRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: night.enabled ? root.clrTertC
                                 : nightMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: nightRow
                                anchors.centerIn: parent
                                rowSpacing: 5
                                columnSpacing: 5
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: night.enabled ? "󰖔" : "󰖙"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: night.enabled ? root.clrOnTertC : root.clrFgMuted
                                }
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: !root.vertical && night.enabled && night.running && night.temperature < 6500
                                    text: night.temperature + "K"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 1
                                    color: root.clrOnTertC
                                }
                            }

                            MouseArea {
                                id: nightMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: night.toggle()
                                onWheel: (wheel) => night.nudge(wheel.angleDelta.y > 0 ? 250 : -250)
                            }
                        }

                        // Bell: left-click = history panel, right-click = Do Not Disturb
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            implicitWidth: root.vertical ? root.pillSize : bellRow.implicitWidth + 16
                            implicitHeight: root.vertical ? bellRow.implicitHeight + 12 : 26
                            radius: Math.min(width, height) / 2
                            color: notifs.historyScreen === barWindow.modelData ? root.clrAccentC
                                 : bellMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            GridLayout {
                                Layout.alignment: Qt.AlignCenter
                                flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                id: bellRow
                                anchors.centerIn: parent
                                rowSpacing: 5
                                columnSpacing: 5
                                Text {
                                    Layout.alignment: Qt.AlignCenter
                                    text: notifs.dnd ? notifs.active.icon : (notifs.count > 0 ? "󰂞" : "󰂚")
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 2
                                    color: notifs.historyScreen === barWindow.modelData ? root.clrOnAccentC
                                         : notifs.dnd ? root.clrAccent : root.clrFg
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignCenter
                                    visible: notifs.count > 0
                                    implicitWidth: Math.max(18, countText.implicitWidth + 10)
                                    implicitHeight: 18
                                    radius: 9
                                    color: root.clrAccent
                                    Text {
                                        Layout.alignment: Qt.AlignCenter
                                        id: countText
                                        anchors.centerIn: parent
                                        text: notifs.count > 99 ? "99+" : notifs.count
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: root.clrOnAccent
                                    }
                                }
                            }

                            MouseArea {
                                id: bellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) notifs.cycleProfile()
                                    else notifs.toggleHistory(barWindow.modelData)
                                }
                            }
                        }

                        // Power: opens the Material You power menu (same as SUPER + Esc)
                        Rectangle {
                            rotation: root.flip
                            Layout.alignment: Qt.AlignCenter
                            implicitWidth: root.pillSize
                            implicitHeight: 26
                            radius: Math.min(width, height) / 2
                            color: pwrMouse.containsMouse ? Qt.alpha(root.clrUrgent, 0.18) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                anchors.centerIn: parent
                                text: "󰐥"
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize + 2
                                color: pwrMouse.containsMouse ? root.clrUrgent : root.clrFg
                            }
                            MouseArea {
                                id: pwrMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["sh", "-c", "[ -x ~/.config/wlogout/launch.sh ] && exec ~/.config/wlogout/launch.sh || exec wlogout"])
                            }
                        }
                    }
                }
            }
        }
    }
}
