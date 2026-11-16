import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Btrfs snapshots (Snapper): list root / home snapshots, pre/post pairs merged
// (snap-pac makes one pair per pacman run), create one, see what changed.
// Restoring: boot the snapshot from the Limine "Snapshots" menu, then run
// limine-snapper-restore (button shown once it's installed).
Scope {
    id: snaps
    required property var theme

    property string config: "root"
    property var rows: []                       // newest first: { num, post, date, type, desc, cleanup, user }
    property string error: ""
    property bool loading: false
    property bool creating: false
    property bool canRestore: false
    property var panelScreen: null

    function togglePanel(screen) {
        panelScreen = (panelScreen === screen) ? null : screen
        if (panelScreen !== null) refresh()
    }
    function refresh() {
        loading = true
        listProc.command = ["snapper", "--jsonout", "-c", config, "list", "--disable-used-space"]
        listProc.running = true
        restoreCheck.running = true
    }
    function setConfig(c) { if (c !== config) { config = c; rows = []; refresh() } }
    function create() {
        if (creating) return
        creating = true
        createProc.command = ["snapper", "-c", config, "create", "--cleanup-algorithm", "number", "-d", "Manual (bar) " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm")]
        createProc.running = true
    }
    function showChanges(r) {
        const range = r.post ? r.num + ".." + r.post : r.num + "..0"
        Quickshell.execDetached(theme.term("snapper-diff", "Snapshot " + range + " changes", ["sh", "-c",
            "snapper -c " + config + " status " + range + " | less -R"]))
    }
    function age(d) {
        const s = (Date.now() - d.getTime()) / 1000
        return s < 3600 ? Math.max(1, Math.round(s / 60)) + " min ago"
             : s < 86400 ? Math.round(s / 3600) + " h ago"
             : Math.round(s / 86400) + " d ago"
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                snaps.loading = false
                if (!text.trim()) return
                try {
                    const all = JSON.parse(text)[snaps.config] ?? []
                    const posts = {}
                    for (const s of all) if (s.type === "post") posts[s["pre-number"]] = s.number
                    snaps.rows = all.filter(s => s.number !== 0 && s.type !== "post").map(s => ({
                        num: s.number, post: posts[s.number] ?? 0,
                        date: new Date(s.date.replace(" ", "T")),
                        type: s.type, desc: (s.description === "timeline" || (!s.description && s.cleanup === "timeline")) ? "Hourly snapshot" : (s.description || "Snapshot"),
                        cleanup: s.cleanup, user: s.user
                    })).reverse()
                    snaps.error = ""
                } catch (e) { snaps.error = "Couldn't read snapper output" }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) {
                snaps.loading = false
                snaps.error = text.includes("permission") || text.includes("No permissions")
                    ? "Snapper won't let your user list snapshots yet (ALLOW_USERS isn't set for this config)."
                    : text.trim()
            }
        }
    }
    Process {
        id: createProc
        stderr: StdioCollector { onStreamFinished: if (text.trim()) snaps.error = text.trim() }
        onExited: { snaps.creating = false; snaps.refresh() }
    }
    Process {
        id: restoreCheck
        command: ["sh", "-c", "command -v limine-snapper-restore"]
        onExited: (code) => snaps.canRestore = code === 0
    }

    IpcHandler {
        target: "snapshots"
        function toggle(): void { snaps.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
    }

    HyprlandFocusGrab {
        active: snapPanel.visible
        windows: [snapPanel].concat(theme.barWindows)
        onCleared: snaps.panelScreen = null
    }

    PanelWindow {
        id: snapPanel
        screen: snaps.panelScreen ?? Quickshell.screens[0]
        visible: snaps.panelScreen !== null
        anchors { top: true; right: true }
        margins { top: theme.barHeight + theme.barMarginTop + 10; right: theme.barMarginSide + 6 }
        implicitWidth: 500
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-snapshots"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: snaps.panelScreen = null

            ColumnLayout {
                id: body
                anchors { fill: parent; margins: 16 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "Snapshots"; font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true; color: theme.clrFg }
                        Text {
                            text: snaps.loading ? "Loading…"
                                : snaps.rows.length ? snaps.rows.length + " snapshots  ·  newest " + snaps.age(snaps.rows[0].date) : ""
                            font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted
                        }
                    }
                    // root / home segmented button
                    Rectangle {
                        implicitWidth: seg.implicitWidth + 6; implicitHeight: 34; radius: 17
                        color: theme.clrBgAlt
                        RowLayout {
                            id: seg
                            anchors.centerIn: parent
                            spacing: 2
                            Repeater {
                                model: [["root", "󰋊  System"], ["home", "󰋜  Home"]]
                                Rectangle {
                                    required property var modelData
                                    readonly property bool on: snaps.config === modelData[0]
                                    implicitWidth: segT.implicitWidth + 20; implicitHeight: 28; radius: 14
                                    color: on ? theme.clrAccentC : "transparent"
                                    Text { id: segT; anchors.centerIn: parent; text: modelData[1]; font.family: theme.fontFamily; font.pixelSize: 11; color: on ? theme.clrOnAccentC : theme.clrFg }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: snaps.setConfig(modelData[0]) }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: snaps.error !== ""
                    Layout.fillWidth: true
                    implicitHeight: errT.implicitHeight + 20
                    radius: 16
                    color: Qt.alpha(theme.clrUrgent, 0.15)
                    Text { id: errT; anchors { fill: parent; margins: 10 } text: "󰀦  " + snaps.error; wrapMode: Text.Wrap; font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFg }
                }

                Rectangle {
                    visible: snaps.rows.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: Math.min(list.contentHeight + 12, 440)
                    radius: 20
                    color: theme.clrBgAlt
                    ListView {
                        id: list
                        anchors { fill: parent; margins: 6 }
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: snaps.rows
                        delegate: Rectangle {
                            required property var modelData
                            width: list.width
                            implicitHeight: 48
                            radius: 14
                            color: rowHover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent"
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                                spacing: 10
                                Rectangle {
                                    implicitWidth: 30; implicitHeight: 30; radius: 15
                                    color: modelData.post ? theme.clrTertC : modelData.cleanup === "timeline" ? Qt.alpha(theme.clrFg, 0.08) : theme.clrAccentC
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.post ? "󰏗" : modelData.cleanup === "timeline" ? "󰥔" : "󰄀"
                                        font.family: theme.fontFamily; font.pixelSize: 14
                                        color: modelData.post ? theme.clrOnTertC : modelData.cleanup === "timeline" ? theme.clrFgMuted : theme.clrOnAccentC
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.desc
                                        elide: Text.ElideRight
                                        font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFg
                                    }
                                    Text {
                                        text: "#" + modelData.num + (modelData.post ? " → #" + modelData.post : "") + "  ·  "
                                              + Qt.formatDateTime(modelData.date, "ddd d MMM HH:mm") + "  ·  " + snaps.age(modelData.date)
                                        font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                                    }
                                }
                                Rectangle {
                                    implicitWidth: chT.implicitWidth + 18; implicitHeight: 28; radius: 14
                                    color: chHover.hovered ? theme.clrAccentC : "transparent"
                                    border.width: 1; border.color: theme.clrBorder
                                    Text { id: chT; anchors.centerIn: parent; text: "Changes"; font.family: theme.fontFamily; font.pixelSize: 10; color: chHover.hovered ? theme.clrOnAccentC : theme.clrFg }
                                    HoverHandler { id: chHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: snaps.showChanges(modelData) }
                                }
                            }
                            HoverHandler { id: rowHover }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    // Create (M3 filled)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44; radius: 22
                        color: crHover.hovered ? Qt.lighter(theme.clrAccent, 1.08) : theme.clrAccent
                        opacity: snaps.creating || snaps.error !== "" && snaps.rows.length === 0 ? 0.5 : 1
                        Text {
                            anchors.centerIn: parent
                            text: snaps.creating ? "Creating…" : "󰄀  Snapshot " + (snaps.config === "root" ? "system" : "home") + " now"
                            font.family: theme.fontFamily; font.pixelSize: 13; font.bold: true; color: theme.clrOnAccent
                        }
                        HoverHandler { id: crHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !snaps.creating; onTapped: snaps.create() }
                    }
                    // Restore (outlined), once limine-snapper-sync is installed
                    Rectangle {
                        visible: snaps.canRestore && snaps.config === "root"
                        implicitWidth: rsT.implicitWidth + 28; implicitHeight: 44; radius: 22
                        color: rsHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                        border.width: 1; border.color: theme.clrBorder
                        Text { id: rsT; anchors.centerIn: parent; text: "󰁯  Restore…"; font.family: theme.fontFamily; font.pixelSize: 13; color: theme.clrFg }
                        HoverHandler { id: rsHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { Quickshell.execDetached(theme.term("limine-restore", "Restore snapshot", ["limine-snapper-restore"])); snaps.panelScreen = null } }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: snaps.config === "root"
                        ? "To roll back: reboot, pick the snapshot under Snapshots in the Limine menu, then use Restore."
                        : "Home snapshots: copy files back out of /home/.snapshots/<number>/snapshot."
                    font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                }
            }
        }
    }
}
