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

    readonly property int barHeight: 34
    property var barWindows: []          // all bar windows; clicks on them never close a panel
    readonly property int barMarginTop: 6
    readonly property int barMarginSide: 10
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

    // Every module with a panel. Opening one closes the others (and the notification history).
    readonly property var panels: [audio, clocks, media, tray, network, bt, stats, updates,
                                   wallpapers, snapshots, services, countdown, keyboard]
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

            anchors { top: true; left: true; right: true }
            margins {
                top: root.barMarginTop
                left: root.barMarginSide
                right: root.barMarginSide
            }

            implicitHeight: root.barHeight
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: root.clrBg
                radius: root.cornerRadius
                border.color: root.clrBorder
                border.width: 1
                Behavior on color { ColorAnimation { duration: 250 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 12
                    spacing: 8

                    // ── Left: this monitor's workspaces ──────────────────────
                    Rectangle {
                        implicitWidth: wsRow.implicitWidth + 8
                        implicitHeight: 26
                        radius: 13
                        color: root.clrBgAlt

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: (wheel) => barWindow.cycle(wheel.angleDelta.y > 0 ? -1 : 1)
                        }

                        RowLayout {
                            id: wsRow
                            anchors.centerIn: parent
                            spacing: 2

                            Repeater {
                                model: barWindow.monitorWorkspaces

                                Rectangle {
                                    id: wsPill
                                    required property var modelData
                                    required property int index
                                    readonly property bool isActive: barWindow.hyprMonitor?.activeWorkspace?.id === modelData.id
                                    readonly property bool isFocused: isActive && barWindow.monitorFocused
                                    readonly property bool isOccupied: (modelData.toplevels?.values?.length ?? 0) > 0
                                    readonly property bool isUrgent: modelData.urgent ?? false

                                    implicitWidth: isActive ? 34 : 20
                                    implicitHeight: 20
                                    radius: 10

                                    color: isUrgent   ? root.clrUrgent
                                         : isFocused  ? root.clrAccent
                                         : isActive   ? root.clrAccentC
                                         : wsMouse.containsMouse ? Qt.alpha(root.clrFg, 0.08)
                                         : "transparent"

                                    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
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
                        id: mediaPill
                        readonly property bool open: media.panelScreen === barWindow.modelData
                        visible: media.hasPlayer
                        implicitWidth: mediaRow.implicitWidth + 16
                        implicitHeight: 26
                        radius: 13
                        clip: true
                        color: open ? root.clrAccentC : mediaMouse.containsMouse ? root.clrBgAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: mediaRow
                            anchors.centerIn: parent
                            spacing: 8
                            ClippingRectangle {
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
                                Layout.maximumWidth: 280
                                text: (media.player?.trackTitle ?? "") + (media.artist(media.player) ? "  ·  " + media.artist(media.player) : "")
                                elide: Text.ElideRight
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                                color: mediaPill.open ? root.clrOnAccentC : root.clrFg
                            }
                            Text {
                                text: media.player?.isPlaying ? "󰏤" : "󰐊"
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize + 1
                                color: mediaPill.open ? root.clrOnAccentC : root.clrAccent
                            }
                        }
                        // thin progress line along the bottom
                        Rectangle {
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
                    RowLayout {
                        visible: barWindow.shownWindow !== null && (barWindow.shownWindow.title ?? "") !== ""
                        Layout.maximumWidth: 420
                        Layout.leftMargin: 4
                        spacing: 8
                        IconImage {
                            readonly property string cls: barWindow.shownWindow?.lastIpcObject?.class ?? barWindow.shownWindow?.wayland?.appId ?? ""
                            visible: source !== ""
                            source: root.appIcon(cls)
                            implicitSize: 16
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 390
                            text: barWindow.shownWindow?.title ?? ""
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize - 1
                            color: barWindow.monitorFocused ? root.clrFg : root.clrFgMuted
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // ── Center: clocks ───────────────────────────────────────
                    // Left-click: clock settings · Right-click: show/hide the second clock
                    Rectangle {
                        readonly property bool open: clocks.panelScreen === barWindow.modelData
                        implicitWidth: clockRow.implicitWidth + 20
                        implicitHeight: 26
                        radius: 13
                        color: open ? root.clrAccentC : clockMouse.containsMouse ? root.clrBgAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        RowLayout {
                            id: clockRow
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize
                                font.bold: true
                                color: parent.parent.open ? root.clrOnAccentC : root.clrFg
                                text: clocks.localText
                            }

                            Rectangle {
                                visible: clocks.alt.enabled
                                implicitWidth: altText.implicitWidth + 14
                                implicitHeight: 20
                                radius: 10
                                color: root.clrAccentC
                                border.width: parent.parent.open ? 1 : 0
                                border.color: root.clrOnAccentC

                                Text {
                                    id: altText
                                    anchors.centerIn: parent
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize - 2
                                    color: root.clrOnAccentC
                                    text: (clocks.alt.label ? clocks.alt.label + " " : "") + clocks.altText
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
                        readonly property bool open: countdown.panelScreen === barWindow.modelData
                        readonly property bool brk: countdown.mode === "pomodoro" && countdown.phase !== "work"
                        implicitWidth: cdRow.implicitWidth + 16
                        implicitHeight: 26
                        radius: 13
                        clip: true
                        color: open ? root.clrAccentC
                             : countdown.active ? (brk ? root.clrTertC : root.clrBgAlt)
                             : cdMouse.containsMouse ? root.clrBgAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            id: cdRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: countdown.mode === "pomodoro" && countdown.active ? countdown.phaseInfo[countdown.phase].icon : "󱎫"
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize + 1
                                color: parent.parent.open ? root.clrOnAccentC
                                     : parent.parent.brk && countdown.active ? root.clrOnTertC
                                     : countdown.active ? root.clrAccent : root.clrFgMuted
                            }
                            Text {
                                visible: countdown.active
                                text: countdown.fmt(countdown.left)
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                                font.bold: true
                                color: parent.parent.open ? root.clrOnAccentC
                                     : parent.parent.brk ? root.clrOnTertC
                                     : countdown.status === "paused" ? root.clrFgMuted : root.clrFg
                            }
                        }
                        Rectangle {
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

                    Item { Layout.fillWidth: true }

                    // ── Right: system tray, then notification bell ───────────
                    RowLayout {
                        spacing: 8
                        layoutDirection: Qt.RightToLeft

                        // Power: opens the Material You power menu (same as SUPER + Esc)
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 13
                            color: pwrMouse.containsMouse ? Qt.alpha(root.clrUrgent, 0.18) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
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

                        // Bell: left-click = history panel, right-click = Do Not Disturb
                        Rectangle {
                            implicitWidth: bellRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: notifs.historyScreen === barWindow.modelData ? root.clrAccentC
                                 : bellMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                id: bellRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: notifs.dnd ? notifs.active.icon : (notifs.count > 0 ? "󰂞" : "󰂚")
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 2
                                    color: notifs.historyScreen === barWindow.modelData ? root.clrOnAccentC
                                         : notifs.dnd ? root.clrAccent : root.clrFg
                                }
                                Rectangle {
                                    visible: notifs.count > 0
                                    implicitWidth: Math.max(18, countText.implicitWidth + 10)
                                    implicitHeight: 18
                                    radius: 9
                                    color: root.clrAccent
                                    Text {
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

                        // Night light: click = on/off, scroll = warmer/cooler
                        Rectangle {
                            implicitWidth: nightRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: night.enabled ? root.clrTertC
                                 : nightMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                id: nightRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: night.enabled ? "󰖔" : "󰖙"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: night.enabled ? root.clrOnTertC : root.clrFgMuted
                                }
                                Text {
                                    visible: night.enabled && night.running && night.temperature < 6500
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

                        // Volume: left-click = sound panel, middle = mute,
                        // right-click = pavucontrol, scroll = ±5%
                        Rectangle {
                            implicitWidth: volRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: audio.panelScreen === barWindow.modelData ? root.clrAccentC
                                 : volMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                id: volRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: audio.volIcon(audio.volume, audio.muted)
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 2
                                    color: audio.panelScreen === barWindow.modelData ? root.clrOnAccentC
                                         : audio.muted ? root.clrFgMuted : root.clrFg
                                }
                                Text {
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

                        // Keyboard layout: click = next layout · right-click = list · scroll = switch
                        Rectangle {
                            readonly property bool open: keyboard.panelScreen === barWindow.modelData
                            visible: keyboard.codes.length > 1
                            implicitWidth: kbText.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: open ? root.clrAccentC
                                 : keyboard.index > 0 ? root.clrTertC
                                 : kbMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
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

                        // Lock keys: only shown when unusual (Caps Lock on / Num Lock off)
                        Rectangle {
                            visible: locks.caps || !locks.num
                            implicitWidth: lockRow.implicitWidth + 14
                            implicitHeight: 22
                            radius: 11
                            color: root.clrTertC
                            RowLayout {
                                id: lockRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    visible: locks.caps
                                    text: "󰪛 CAPS"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2; font.bold: true
                                    color: root.clrOnTertC
                                }
                                Text {
                                    visible: !locks.num
                                    text: "󰎠 NUM off"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2; font.bold: true
                                    color: root.clrOnTertC
                                }
                            }
                        }

                        // Bluetooth: hidden without an adapter; shows connected-device count
                        Rectangle {
                            readonly property bool open: bt.panelScreen === barWindow.modelData
                            visible: bt.available
                            implicitWidth: btRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: open ? root.clrAccentC : btMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                id: btRow
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: bt.icon
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : bt.powered ? root.clrFg : root.clrFgMuted
                                }
                                Text {
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

                        // Network: icon by connection type; warning badge when there's no internet
                        Rectangle {
                            readonly property bool open: network.panelScreen === barWindow.modelData
                            implicitWidth: netRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: open ? root.clrAccentC : netMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                id: netRow
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: network.icon
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : network.linkUp ? root.clrFg : root.clrUrgent
                                }
                                Text {
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

                        // Tray overflow button: opens the tray panel (unpinned apps live there)
                        Rectangle {
                            readonly property bool open: tray.panelScreen === barWindow.modelData
                            visible: tray.items.length > 0
                            implicitWidth: ovRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: open ? root.clrAccentC : ovMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                id: ovRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: parent.parent.open ? "󰅃" : "󰅀"
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrFg
                                }
                                Text {
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

                        // Pinned tray apps: left = open, right = menu (in the tray panel), middle = secondary
                        Repeater {
                            model: tray.pinned

                            IconImage {
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

                        // System stats: CPU / GPU / RAM (amber >= 70%, red >= 90%)
                        Rectangle {
                            readonly property bool open: stats.panelScreen === barWindow.modelData
                            implicitWidth: statRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: open ? root.clrAccentC : statMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                id: statRow
                                anchors.centerIn: parent
                                spacing: 10
                                Repeater {
                                    model: [["󰻠", stats.cpu]].concat(stats.gpu ? [["󰢮", stats.gpuUtil]] : []).concat([["󰍛", stats.mem]])
                                    Text {
                                        required property var modelData
                                        text: modelData[0] + " " + Math.round(modelData[1]) + "%"
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

                        // Failed systemd units: only shown when something failed
                        Rectangle {
                            readonly property bool open: services.panelScreen === barWindow.modelData
                            visible: services.count > 0 || open
                            implicitWidth: svcRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: 12
                            color: open ? root.clrAccentC : Qt.alpha(root.clrUrgent, svcMouse.containsMouse ? 0.3 : 0.18)
                            border.width: open ? 0 : 1
                            border.color: root.clrUrgent
                            RowLayout {
                                id: svcRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: "󰒏"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrUrgent
                                }
                                Text {
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

                        // Updates: shown when packages are waiting
                        Rectangle {
                            readonly property bool open: updates.panelScreen === barWindow.modelData
                            visible: updates.count > 0 || open
                            implicitWidth: updRow.implicitWidth + 16
                            implicitHeight: 26
                            radius: 13
                            color: open ? root.clrAccentC : updMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                id: updRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: updates.updating ? "󰚰" : "󰏗"
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize + 1
                                    color: parent.parent.open ? root.clrOnAccentC : root.clrAccent
                                }
                                Text {
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

                        // Clipboard history (clipse, also SUPER + SHIFT + V)
                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: 13
                            color: clipMouse.containsMouse ? root.clrBgAlt : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
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

                        // Wallpaper picker and snapshots
                        Repeater {
                            model: [
                                { icon: "󰸉", mod: wallpapers },
                                { icon: "󰁯", mod: snapshots }
                            ]
                            Rectangle {
                                required property var modelData
                                readonly property bool open: modelData.mod.panelScreen === barWindow.modelData
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: 13
                                color: open ? root.clrAccentC : iconMouse.containsMouse ? root.clrBgAlt : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
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

                        // Privacy: shown while an app uses the mic, camera or screen
                        Rectangle {
                            visible: privacy.active
                            implicitWidth: privRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: 12
                            color: Qt.alpha(root.clrUrgent, 0.22)
                            border.width: 1
                            border.color: root.clrUrgent
                            RowLayout {
                                id: privRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text { visible: privacy.mic.length > 0; text: "󰍬"; font.family: root.fontFamily; font.pixelSize: root.fontSize; color: root.clrUrgent }
                                Text { visible: privacy.camera.length > 0; text: "󰄀"; font.family: root.fontFamily; font.pixelSize: root.fontSize; color: root.clrUrgent }
                                Text { visible: privacy.screen.length > 0; text: "󰹑"; font.family: root.fontFamily; font.pixelSize: root.fontSize; color: root.clrUrgent }
                                Text {
                                    Layout.maximumWidth: 160
                                    text: privacy.apps.join(", ")
                                    elide: Text.ElideRight
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 2
                                    color: root.clrFg
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
