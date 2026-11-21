import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications

// The bar is the notification daemon: pop-ups on the focused monitor, a history
// panel opened from the bell, and Do Not Disturb profiles that allow notifications
// per type and per app. Profiles live in ~/.config/pillbox/settings.json.
Scope {
    id: notifs
    required property var theme                // the ShellRoot
    required property var settings             // JsonAdapter of settings.json

    // ── Notification types: how a notification is classified ────────────────
    readonly property var types: [
        { id: "critical",  name: "Critical",  icon: "󰀦" },
        { id: "messages",  name: "Messages",  icon: "󰭹" },
        { id: "email",     name: "Email",     icon: "󰇮" },
        { id: "media",     name: "Media",     icon: "󰝚" },
        { id: "system",    name: "System",    icon: "󰒓" },
        { id: "downloads", name: "Downloads", icon: "󰇚" },
    ]
    readonly property var typeApps: ({
        messages:  ["discord", "vesktop", "signal", "telegram", "element", "whatsapp", "slack", "teams", "thunderbird-chat"],
        email:     ["thunderbird", "evolution", "geary", "mail", "outlook"],
        media:     ["spotify", "sone", "tidal", "mpv", "vlc", "playerctl", "youtube music"],
        system:    ["udiskie", "networkmanager", "nm-applet", "blueman", "hyprland", "pacman", "yay", "system", "notify-send"],
        downloads: [],
    })
    readonly property var typeCategories: ({
        messages: ["im"], email: ["email"], system: ["device", "network", "power"], downloads: ["transfer"], media: [],
    })
    readonly property var iconChoices: ["󰂛", "󰃖", "󰊴", "󰋋", "󰭹", "󰒲", "󰎈", "󰌵", "󰇮", "󰔟"]

    function appKey(n) { return ((n.appName || n.desktopEntry || "") + "").toLowerCase() }
    function typesOf(n) {
        const out = []
        if (n.urgency === NotificationUrgency.Critical) out.push("critical")
        const cat = ((n.hints && n.hints["category"]) || "") + ""
        const app = appKey(n)
        for (const t of ["messages", "email", "media", "system", "downloads"]) {
            if (typeCategories[t].some(c => cat === c || cat.startsWith(c + ".")) ||
                typeApps[t].some(a => app.includes(a)))
                out.push(t)
        }
        return out
    }

    // ── Profiles ──────────────────────────────────────────────────────────────
    readonly property var profiles: settings.dndProfiles
    readonly property string activeName: settings.dndProfile
    readonly property var active: profiles.find(p => p.name === activeName) ?? null
    readonly property bool dnd: active !== null

    function allowed(n) {
        const p = active
        if (!p) return true
        if (typesOf(n).some(t => p.types.includes(t))) return true
        const app = appKey(n)
        return p.apps.some(a => a && app.includes(a.toLowerCase()))
    }
    function setProfile(name) { settings.dndProfile = (name === activeName) ? "" : name }
    function cycleProfile() {
        const names = [""].concat(profiles.map(p => p.name))
        settings.dndProfile = names[(names.indexOf(activeName) + 1) % names.length]
    }
    function updateProfile(name, change) {
        settings.dndProfiles = profiles.map(p => p.name === name ? Object.assign({}, p, change(p)) : p)
    }
    function renameProfile(oldName, newName) {
        newName = newName.trim()
        if (!newName || profiles.some(p => p.name === newName)) return false
        updateProfile(oldName, p => ({ name: newName }))
        if (activeName === oldName) settings.dndProfile = newName
        if (editing === oldName) editing = newName
        return true
    }
    function addProfile() {
        let i = 1, name = "New profile"
        while (profiles.some(p => p.name === name)) name = "New profile " + (++i)
        settings.dndProfiles = profiles.concat([{ name: name, icon: "󰂛", types: ["critical"], apps: [] }])
        editing = name
    }
    function deleteProfile(name) {
        settings.dndProfiles = profiles.filter(p => p.name !== name)
        if (activeName === name) settings.dndProfile = ""
        editing = ""
    }
    function hasApp(list, app) { return list.some(a => a.toLowerCase() === app.toLowerCase()) }
    function toggleIn(list, item) { return list.includes(item) ? list.filter(x => x !== item) : list.concat([item]) }

    property string editing: ""                 // profile open in the editor ("" = none)

    // ── History & pop-ups ─────────────────────────────────────────────────────
    readonly property var history: server.trackedNotifications.values
    readonly property int count: history.length
    property var popups: []
    property var arrivals: ({})                 // id -> Date
    property var silenced: ({})                 // id -> true when DND held it back
    property var historyScreen: null            // screen whose bell opened the panel (null = closed)
    property bool otherPanelOpen: false         // set by shell.qml: any other bar panel / cheat sheet open
    // Pop-ups wait (hidden, countdown paused) while any panel is open
    readonly property bool held: historyScreen !== null || otherPanelOpen
    readonly property var seenApps: {
        const seen = new Map()                  // lowercase -> first spelling seen
        for (const n of history) if (n.appName && !seen.has(n.appName.toLowerCase())) seen.set(n.appName.toLowerCase(), n.appName)
        return Array.from(seen.values()).sort()
    }

    function hidePopup(n) { popups = popups.filter(p => p !== n) }
    function clearAll() { for (const n of history.slice()) n.dismiss() }
    function toggleHistory(screen) {
        historyScreen = (historyScreen === screen) ? null : screen
        if (historyScreen === null) editing = ""
    }

    // `qs ipc call notifs toggle|clear|cycle|profile <name>|off`  (SUPER+N = toggle)
    IpcHandler {
        target: "notifs"
        function toggle(): void { notifs.toggleHistory(notifs.focusedScreen) }
        function clear(): void { notifs.clearAll() }
        function cycle(): void { notifs.cycleProfile() }
        function profile(name: string): void { notifs.settings.dndProfile = name }
        function off(): void { notifs.settings.dndProfile = "" }
        function edit(name: string): void { notifs.historyScreen = notifs.focusedScreen; notifs.editing = name }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: (n) => {
            n.tracked = true
            const a = notifs.arrivals; a[n.id] = new Date(); notifs.arrivals = a
            n.closed.connect(() => notifs.hidePopup(n))
            if (notifs.allowed(n)) {
                notifs.popups = [n].concat(notifs.popups).slice(0, 5)
            } else {
                const s = notifs.silenced; s[n.id] = true; notifs.silenced = s
            }
        }
    }

    readonly property var focusedScreen:
        Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    // ── Pop-ups: top-right of the focused monitor, under the bar ─────────────
    PanelWindow {
        screen: notifs.focusedScreen
        visible: notifs.popups.length > 0 && !notifs.held
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 400
        implicitHeight: popupColumn.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notifications"

        Column {
            id: popupColumn
            width: parent.width
            spacing: 10
            Repeater {
                model: notifs.popups
                NotifCard {
                    required property var modelData
                    width: popupColumn.width
                    notif: modelData
                    theme: notifs.theme
                    popup: true
                    paused: notifs.held
                    arrived: notifs.arrivals[modelData.id] ?? new Date()
                    onCloseRequested: notifs.hidePopup(modelData)
                }
            }
        }
    }

    // ── Reusable bits for the panel ──────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string label
        property string icon: ""
        property bool selected: false
        property bool removable: false
        signal clicked()
        implicitWidth: chipRow.implicitWidth + 24
        implicitHeight: 32
        radius: 8                                         // M3 filter chip shape
        color: selected ? theme.clrAccentC : (chipHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent")
        border.width: selected ? 0 : 1
        border.color: theme.clrBorder
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: chip.selected || chip.icon !== ""
                text: chip.selected && !chip.removable && chip.icon === "" ? "󰄬" : chip.icon
                font.family: theme.fontFamily; font.pixelSize: 14
                color: chip.selected ? theme.clrOnAccentC : theme.clrFgMuted
            }
            Text {
                text: chip.label
                font.family: theme.fontFamily; font.pixelSize: 12
                color: chip.selected ? theme.clrOnAccentC : theme.clrFg
            }
            Text {
                visible: chip.removable
                text: "󰅖"
                font.family: theme.fontFamily; font.pixelSize: 12
                color: chip.selected ? theme.clrOnAccentC : theme.clrFgMuted
            }
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    component SectionLabel: Text {
        font.family: theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        color: theme.clrAccent
        Layout.topMargin: 4
    }

    // ── History panel: opened from the bell on that monitor's bar ────────────
    // Click anywhere outside this panel (and the bars) to close it
    HyprlandFocusGrab {
        active: panel.visible
        windows: [panel].concat(theme.barWindows)
        onCleared: notifs.toggleHistory(notifs.historyScreen)
    }

    PanelWindow {
        id: panel
        screen: notifs.historyScreen ?? notifs.focusedScreen
        visible: notifs.historyScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 440
        implicitHeight: Math.min(panelBody.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notifications"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: notifs.toggleHistory(notifs.historyScreen)

            Flickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: panelBody.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: panelBody
                    width: parent.width
                    spacing: 10

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true
                            color: theme.clrFg
                        }
                        Text {
                            text: notifs.dnd ? notifs.active.icon + "  " + notifs.active.name + " is on" : ""
                            font.family: theme.fontFamily; font.pixelSize: 12
                            color: theme.clrAccent
                        }
                    }

                    // Do Not Disturb profile picker
                    SectionLabel { text: "Do not disturb" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            label: "Off"; icon: "󰂚"
                            selected: !notifs.dnd
                            onClicked: notifs.settings.dndProfile = ""
                        }
                        Repeater {
                            model: notifs.profiles
                            Chip {
                                required property var modelData
                                label: modelData.name
                                icon: modelData.icon
                                selected: notifs.activeName === modelData.name
                                onClicked: notifs.setProfile(modelData.name)
                            }
                        }
                        Chip { label: "New"; icon: "󰐕"; onClicked: notifs.addProfile() }
                    }

                    // Edit link for the selected profile
                    Text {
                        visible: notifs.dnd && notifs.editing === ""
                        text: "󰏫  Customise " + (notifs.active?.name ?? "")
                        font.family: theme.fontFamily; font.pixelSize: 12
                        color: editHover.hovered ? theme.clrAccent : theme.clrFgMuted
                        HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: notifs.editing = notifs.activeName }
                    }

                    // ── Profile editor ─────────────────────────────────────
                    Rectangle {
                        id: editor
                        readonly property var prof: notifs.profiles.find(p => p.name === notifs.editing) ?? null
                        visible: prof !== null
                        Layout.fillWidth: true
                        implicitHeight: edCol.implicitHeight + 28
                        radius: 20
                        color: theme.clrBgAlt

                        ColumnLayout {
                            id: edCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                // Icon: click to cycle
                                Rectangle {
                                    implicitWidth: 36; implicitHeight: 36; radius: 18
                                    color: theme.clrAccentC
                                    Text {
                                        anchors.centerIn: parent
                                        text: editor.prof?.icon ?? ""
                                        font.family: theme.fontFamily; font.pixelSize: 18
                                        color: theme.clrOnAccentC
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            const c = notifs.iconChoices
                                            notifs.updateProfile(editor.prof.name, p => ({ icon: c[(c.indexOf(p.icon) + 1) % c.length] }))
                                        }
                                    }
                                }
                                // Name: edit and press Enter
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 36; radius: 18
                                    color: theme.clrBg
                                    border.width: nameInput.activeFocus ? 2 : 1
                                    border.color: nameInput.activeFocus ? theme.clrAccent : theme.clrBorder
                                    TextInput {
                                        id: nameInput
                                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: editor.prof?.name ?? ""
                                        font.family: theme.fontFamily; font.pixelSize: 13
                                        color: theme.clrFg
                                        selectionColor: theme.clrAccentC
                                        onAccepted: if (!notifs.renameProfile(editor.prof.name, text)) text = editor.prof.name
                                    }
                                }
                                Text {
                                    text: "Done"
                                    font.family: theme.fontFamily; font.pixelSize: 13; font.bold: true
                                    color: theme.clrAccent
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (nameInput.text !== editor.prof.name) notifs.renameProfile(editor.prof.name, nameInput.text)
                                            notifs.editing = ""
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Allow these types" }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: notifs.types
                                    Chip {
                                        required property var modelData
                                        label: modelData.name
                                        icon: modelData.icon
                                        selected: editor.prof?.types.includes(modelData.id) ?? false
                                        onClicked: notifs.updateProfile(editor.prof.name, p => ({ types: notifs.toggleIn(p.types, modelData.id) }))
                                    }
                                }
                            }

                            SectionLabel { text: "Always allow these apps" }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: editor.prof?.apps ?? []
                                    Chip {
                                        required property var modelData
                                        label: modelData
                                        selected: true
                                        removable: true
                                        onClicked: notifs.updateProfile(editor.prof.name, p => ({ apps: p.apps.filter(a => a !== modelData) }))
                                    }
                                }
                                // Add an app by name
                                Rectangle {
                                    implicitWidth: 150; implicitHeight: 32; radius: 8
                                    color: "transparent"
                                    border.width: appInput.activeFocus ? 2 : 1
                                    border.color: appInput.activeFocus ? theme.clrAccent : theme.clrBorder
                                    TextInput {
                                        id: appInput
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: theme.fontFamily; font.pixelSize: 12
                                        color: theme.clrFg
                                        Text {
                                            visible: !appInput.text && !appInput.activeFocus
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "󰐕 Add app…"
                                            font: appInput.font
                                            color: theme.clrFgMuted
                                        }
                                        onAccepted: {
                                            const a = text.trim()
                                            if (a && !notifs.hasApp(editor.prof.apps, a))
                                                notifs.updateProfile(editor.prof.name, p => ({ apps: p.apps.concat([a]) }))
                                            text = ""
                                        }
                                    }
                                }
                            }

                            // Suggestions: apps that have sent notifications
                            Text {
                                readonly property var sugg: notifs.seenApps.filter(a => !notifs.hasApp(editor.prof?.apps ?? [], a))
                                visible: sugg.length > 0
                                text: "Recent apps (tap to allow)"
                                font.family: theme.fontFamily; font.pixelSize: 11
                                color: theme.clrFgMuted
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: notifs.seenApps.filter(a => !notifs.hasApp(editor.prof?.apps ?? [], a))
                                    Chip {
                                        required property var modelData
                                        label: modelData
                                        icon: "󰐕"
                                        onClicked: notifs.updateProfile(editor.prof.name, p => ({ apps: p.apps.concat([modelData]) }))
                                    }
                                }
                            }

                            Text {
                                Layout.topMargin: 4
                                text: "󰆴  Delete profile"
                                font.family: theme.fontFamily; font.pixelSize: 12
                                color: delHover.hovered ? theme.clrUrgent : theme.clrFgMuted
                                HoverHandler { id: delHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: notifs.deleteProfile(editor.prof.name) }
                            }
                        }
                    }

                    // ── History ────────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        SectionLabel { Layout.fillWidth: true; text: "History" }
                        Text {
                            visible: notifs.count > 0
                            text: "Clear all (" + notifs.count + ")"
                            font.family: theme.fontFamily; font.pixelSize: 12
                            color: clearHover.hovered ? theme.clrAccent : theme.clrFgMuted
                            HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: notifs.clearAll() }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.bottomMargin: 12
                        visible: notifs.count === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: "󰂚\nYou're all caught up"
                        font.family: theme.fontFamily; font.pixelSize: 14
                        color: theme.clrFgMuted
                    }

                    Repeater {
                        model: notifs.history.slice().reverse()   // newest first
                        NotifCard {
                            required property var modelData
                            Layout.fillWidth: true
                            notif: modelData
                            theme: notifs.theme
                            arrived: notifs.arrivals[modelData.id] ?? new Date()
                            opacity: notifs.silenced[modelData.id] ? 0.6 : 1   // held back by DND
                        }
                    }
                }
            }
        }
    }
}
