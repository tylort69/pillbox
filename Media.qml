import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris

// Now-playing for the bar: tracks MPRIS players (TIDAL/sone, Firefox, mpv, …),
// exposes the active one to the bar pill, and shows a Material You player panel.
Scope {
    id: media
    required property var theme

    readonly property var players: Mpris.players.values
    property string pinnedId: ""               // player picked in the switcher ("" = automatic)
    // Active player: the one you picked, else one that's playing, else the first
    readonly property var player: players.find(p => p.uniqueId + "" === pinnedId && pinnedId !== "")
                                  ?? players.find(p => p.isPlaying) ?? players[0] ?? null
    readonly property bool hasPlayer: player !== null && (player.trackTitle || "") !== ""
    property var panelScreen: null

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0
        const m = Math.floor(sec / 60), s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function artist(p) { return p ? (p.trackArtist || (p.trackArtists ? p.trackArtists.join(", ") : "")) : "" }
    readonly property real progress: player && player.length > 0 ? Math.min(1, player.position / player.length) : 0

    // Fresh position when the panel opens or the active player changes (also while paused)
    onPanelScreenChanged: if (player) player.positionChanged()
    onPlayerChanged: if (player) player.positionChanged()

    // MPRIS doesn't push position updates; poll while playing
    Timer {
        running: media.player !== null && media.player.isPlaying
        interval: 1000
        repeat: true
        onTriggered: media.player.positionChanged()
    }

    // `qs ipc call media toggle|playpause|next|previous`
    IpcHandler {
        target: "media"
        function toggle(): void { media.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        function playpause(): void { media.player?.togglePlaying() }
        function next(): void { media.player?.next() }
        function previous(): void { media.player?.previous() }
    }

    // ── Controls ──────────────────────────────────────────────────────────────
    component IconButton: Rectangle {
        id: btn
        property string icon
        property bool active: false             // e.g. shuffle on
        property bool usable: true
        property int size: 40
        signal clicked()
        implicitWidth: size; implicitHeight: size; radius: size / 2
        color: active ? theme.clrAccentC : (btnHover.hovered && usable ? Qt.alpha(theme.clrFg, 0.08) : "transparent")
        opacity: usable ? 1 : 0.35
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.family: theme.fontFamily; font.pixelSize: btn.size * 0.5
            color: btn.active ? theme.clrOnAccentC : theme.clrFg
        }
        HoverHandler { id: btnHover; cursorShape: btn.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: btn.usable; onTapped: btn.clicked() }
    }

    component Art: ClippingRectangle {
        id: art
        property string source
        property int size: 140
        implicitWidth: size; implicitHeight: size
        radius: size * 0.16
        color: theme.clrAccentC
        Image {
            anchors.fill: parent
            source: art.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !art.source
            text: "󰝚"
            font.family: theme.fontFamily; font.pixelSize: art.size * 0.4
            color: theme.clrOnAccentC
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────────
    // Click anywhere outside this panel (and the bars) to close it
    HyprlandFocusGrab {
        active: mediaPanel.visible
        windows: [mediaPanel].concat(theme.barWindows)
        onCleared: media.panelScreen = null
    }

    PanelWindow {
        id: mediaPanel
        screen: media.panelScreen ?? Quickshell.screens[0]
        visible: media.panelScreen !== null && media.player !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "start"); bottom: theme.edge("bottom", "start"); left: theme.edge("left", "start"); right: theme.edge("right", "start") }
        margins { top: theme.gap("top", "start"); bottom: theme.gap("bottom", "start"); left: theme.gap("left", "start"); right: theme.gap("right", "start") }
        implicitWidth: 460
        implicitHeight: body.implicitHeight + 40
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-media"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: media.panelScreen = null
            Keys.onSpacePressed: media.player?.togglePlaying()

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 14

                // Art + track info
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Art { source: media.player?.trackArtUrl ?? ""; size: 132 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4
                        Text {
                            text: (media.player?.identity ?? "") + (media.player?.isPlaying ? "  ·  playing" : "  ·  paused")
                            font.family: theme.fontFamily; font.pixelSize: 11
                            color: theme.clrAccent
                        }
                        Text {
                            Layout.fillWidth: true
                            text: media.player?.trackTitle || "Nothing playing"
                            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                            font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true
                            color: theme.clrFg
                        }
                        Text {
                            Layout.fillWidth: true
                            text: media.artist(media.player)
                            elide: Text.ElideRight
                            font.family: theme.fontFamily; font.pixelSize: 13
                            color: theme.clrFg
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: media.player?.trackAlbum ?? ""
                            elide: Text.ElideRight
                            font.family: theme.fontFamily; font.pixelSize: 12
                            color: theme.clrFgMuted
                        }
                    }
                }

                // Progress (drag or scroll to seek)
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (media.player?.length ?? 0) > 0
                    spacing: 2
                    MSlider {
                        Layout.fillWidth: true
                        theme: media.theme
                        value: media.progress
                        onMoved: (v) => { if (media.player?.canSeek) media.player.position = v * media.player.length }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: media.fmt(media.player?.position ?? 0); font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
                        Item { Layout.fillWidth: true }
                        Text { text: media.fmt(media.player?.length ?? 0); font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
                    }
                }

                // Transport
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    IconButton {
                        icon: "󰒝"
                        usable: media.player?.shuffleSupported ?? false
                        active: media.player?.shuffle ?? false
                        onClicked: media.player.shuffle = !media.player.shuffle
                    }
                    IconButton { icon: "󰒮"; size: 48; usable: media.player?.canGoPrevious ?? false; onClicked: media.player.previous() }
                    // M3 expressive play button: square-ish while playing, round while paused
                    Rectangle {
                        implicitWidth: 72; implicitHeight: 64
                        radius: media.player?.isPlaying ? 18 : 32
                        color: playHover.hovered ? Qt.lighter(theme.clrAccent, 1.08) : theme.clrAccent
                        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        Text {
                            anchors.centerIn: parent
                            text: media.player?.isPlaying ? "󰏤" : "󰐊"
                            font.family: theme.fontFamily; font.pixelSize: 30
                            color: theme.clrOnAccent
                        }
                        HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: media.player?.togglePlaying() }
                    }
                    IconButton { icon: "󰒭"; size: 48; usable: media.player?.canGoNext ?? false; onClicked: media.player.next() }
                    IconButton {
                        readonly property int loop: media.player?.loopState ?? MprisLoopState.None
                        icon: loop === MprisLoopState.Track ? "󰑘" : "󰑖"
                        usable: media.player?.loopSupported ?? false
                        active: loop !== MprisLoopState.None
                        onClicked: media.player.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist
                                                         : loop === MprisLoopState.Playlist ? MprisLoopState.Track
                                                         : MprisLoopState.None
                    }
                }

                // Player volume (when the player supports it)
                RowLayout {
                    Layout.fillWidth: true
                    visible: media.player?.volumeSupported ?? false
                    spacing: 10
                    Text { text: "󰕾"; font.family: theme.fontFamily; font.pixelSize: 16; color: theme.clrFgMuted }
                    MSlider {
                        Layout.fillWidth: true
                        theme: media.theme
                        value: media.player?.volume ?? 0
                        onMoved: (v) => media.player.volume = v
                    }
                    Text {
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((media.player?.volume ?? 0) * 100) + "%"
                        font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                    }
                }

                // Player switcher (only with more than one player)
                Flow {
                    Layout.fillWidth: true
                    visible: media.players.length > 1
                    spacing: 6
                    Repeater {
                        model: media.players
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: modelData === media.player
                            implicitWidth: pRow.implicitWidth + 22; implicitHeight: 30; radius: 8
                            color: sel ? theme.clrAccentC : "transparent"
                            border.width: sel ? 0 : 1; border.color: theme.clrBorder
                            RowLayout {
                                id: pRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: modelData.isPlaying ? "󰐊" : "󰏤"; font.family: theme.fontFamily; font.pixelSize: 11; color: sel ? theme.clrOnAccentC : theme.clrFgMuted }
                                Text { text: modelData.identity; font.family: theme.fontFamily; font.pixelSize: 11; color: sel ? theme.clrOnAccentC : theme.clrFg }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: media.pinnedId = modelData.uniqueId + "" }
                        }
                    }
                }

                // Open the player app
                Text {
                    Layout.alignment: Qt.AlignRight
                    visible: media.player?.canRaise ?? false
                    text: "󰏌  Open " + (media.player?.identity ?? "")
                    font.family: theme.fontFamily; font.pixelSize: 11
                    color: raiseHover.hovered ? theme.clrAccent : theme.clrFgMuted
                    HoverHandler { id: raiseHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { media.player.raise(); media.panelScreen = null } }
                }
            }
        }
    }
}
