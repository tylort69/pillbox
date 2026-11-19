import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// System tray: apps you pin show as icons in the bar, the rest live behind the
// overflow button. The panel shows every tray app as a tile; tray menus open
// inside the panel. Pins are saved in settings.json (trayPinned: [item ids]).
Scope {
    id: tray
    required property var theme
    required property var settings

    readonly property var items: SystemTray.items.values
    readonly property var pinnedIds: settings.trayPinned ?? []
    readonly property var pinned: items.filter(i => pinnedIds.includes(i.id))
    readonly property var unpinned: items.filter(i => !pinnedIds.includes(i.id))

    property var panelScreen: null
    property var menuItem: null                // tray item whose menu is open in the panel
    property var menuStack: []                 // submenu entries opened inside that menu

    function isPinned(item) { return pinnedIds.includes(item.id) }
    function togglePin(item) {
        settings.trayPinned = isPinned(item) ? pinnedIds.filter(i => i !== item.id) : pinnedIds.concat([item.id])
    }
    function togglePanel(screen) {
        if (panelScreen === screen && menuItem === null) { panelScreen = null; return }
        menuItem = null; menuStack = []; panelScreen = screen
    }
    function openMenu(screen, item) {
        if (!item.hasMenu) return
        menuItem = item; menuStack = []; panelScreen = screen
    }
    function close() { panelScreen = null; menuItem = null; menuStack = [] }
    // App name: a clean id ("sone" -> "Sone"), else its title/tooltip ("Claude_status_icon_1" -> "Claude")
    function name(item) {
        const id = (item.id || "") + ""
        if (/^[A-Za-z][A-Za-z0-9.-]*$/.test(id) && !/^org\.|^chrome_status|StatusNotifierItem/i.test(id))
            return id.charAt(0).toUpperCase() + id.slice(1)
        return item.tooltipTitle || item.title || id
    }
    // Extra line under the name, e.g. sone's current song
    function detail(item) {
        const t = item.title || item.tooltipTitle || ""
        return t && t !== name(item) ? t : ""
    }
    // Left click: activate, or show the menu for menu-only items
    function primary(screen, item) {
        if (item.onlyMenu) openMenu(screen, item)
        else { item.activate(); close() }
    }

    // `qs ipc call tray toggle` / `qs ipc call tray menu <n>` (n = tile index, for testing)
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    IpcHandler {
        target: "tray"
        function toggle(): void { tray.togglePanel(tray.focusedScreen) }
        function menu(n: int): void { if (tray.items[n]) tray.openMenu(tray.focusedScreen, tray.items[n]) }
    }

    // ── Panel ─────────────────────────────────────────────────────────────────
    HyprlandFocusGrab {
        active: trayPanel.visible
        windows: [trayPanel].concat(theme.barWindows)
        onCleared: tray.close()
    }

    PanelWindow {
        id: trayPanel
        screen: tray.panelScreen ?? Quickshell.screens[0]
        visible: tray.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "end"); bottom: theme.edge("bottom", "end"); left: theme.edge("left", "end"); right: theme.edge("right", "end") }
        margins { top: theme.gap("top", "end"); bottom: theme.gap("bottom", "end"); left: theme.gap("left", "end"); right: theme.gap("right", "end") }
        implicitWidth: 380
        implicitHeight: Math.min(body.implicitHeight + 32, (screen?.height ?? 1080) * 0.8)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-tray"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: tray.menuItem ? (tray.menuStack.length ? tray.menuStack = tray.menuStack.slice(0, -1) : tray.menuItem = null) : tray.close()

            Flickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 12

                    Text {
                        text: "System tray"
                        font.family: theme.fontFamily; font.pixelSize: 18; font.bold: true
                        color: theme.clrFg
                    }
                    Text {
                        visible: tray.items.length === 0
                        text: "No tray apps running"
                        font.family: theme.fontFamily; font.pixelSize: 12
                        color: theme.clrFgMuted
                    }

                    // Tiles: one per tray app
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 8
                        columnSpacing: 8
                        Repeater {
                            model: tray.items
                            Rectangle {
                                id: tile
                                required property var modelData
                                readonly property bool menuOpen: tray.menuItem === modelData
                                Layout.fillWidth: true
                                implicitHeight: 88
                                radius: 20
                                color: menuOpen ? theme.clrAccentC : tileHover.hovered ? Qt.lighter(theme.clrBgAlt, 1.1) : theme.clrBgAlt
                                Behavior on color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    spacing: 6
                                    IconImage {
                                        Layout.alignment: Qt.AlignHCenter
                                        source: tile.modelData.icon
                                        implicitSize: 28
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: tray.name(tile.modelData)
                                        elide: Text.ElideRight
                                        font.family: theme.fontFamily; font.pixelSize: 11
                                        color: tile.menuOpen ? theme.clrOnAccentC : theme.clrFg
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        horizontalAlignment: Text.AlignHCenter
                                        text: tray.detail(tile.modelData)
                                        elide: Text.ElideRight
                                        font.family: theme.fontFamily; font.pixelSize: 10
                                        color: tile.menuOpen ? theme.clrOnAccentC : theme.clrFgMuted
                                    }
                                }

                                // Pin toggle (top-right corner)
                                Rectangle {
                                    anchors { top: parent.top; right: parent.right; margins: 6 }
                                    width: 24; height: 24; radius: 12
                                    color: tray.isPinned(tile.modelData) ? theme.clrAccent : pinHover.hovered ? Qt.alpha(theme.clrFg, 0.1) : "transparent"
                                    visible: tray.isPinned(tile.modelData) || tileHover.hovered
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰐃"
                                        font.family: theme.fontFamily; font.pixelSize: 13
                                        color: tray.isPinned(tile.modelData) ? theme.clrOnAccent : theme.clrFgMuted
                                    }
                                    HoverHandler { id: pinHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: tray.togglePin(tile.modelData) }
                                }

                                HoverHandler { id: tileHover }
                                MouseArea {
                                    anchors.fill: parent
                                    z: -1
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) tray.openMenu(tray.panelScreen, tile.modelData)
                                        else if (mouse.button === Qt.MiddleButton) tile.modelData.secondaryActivate()
                                        else tray.primary(tray.panelScreen, tile.modelData)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: tray.items.length > 0 && tray.menuItem === null
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Click to open · right-click for its menu · 󰐃 pins it to the bar"
                        font.family: theme.fontFamily; font.pixelSize: 11
                        color: theme.clrFgMuted
                    }

                    // ── The selected app's menu, rendered here ───────────────
                    Rectangle {
                        visible: tray.menuItem !== null
                        Layout.fillWidth: true
                        implicitHeight: menuCol.implicitHeight + 16
                        radius: 20
                        color: theme.clrBgAlt

                        QsMenuOpener {
                            id: opener
                            menu: tray.menuStack.length ? tray.menuStack[tray.menuStack.length - 1]
                                                        : (tray.menuItem?.menu ?? null)
                        }

                        ColumnLayout {
                            id: menuCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 0

                            // Header: app name, or "‹ back" inside a submenu
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 36; radius: 12
                                color: tray.menuStack.length && backHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                                Text {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: tray.menuStack.length ? "󰁍  " + (tray.menuStack[tray.menuStack.length - 1].text || "Back")
                                                                : (tray.menuItem ? tray.name(tray.menuItem) : "")
                                    font.family: theme.fontFamily; font.pixelSize: 13; font.bold: true
                                    color: theme.clrAccent
                                }
                                HoverHandler { id: backHover; cursorShape: tray.menuStack.length ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { enabled: tray.menuStack.length > 0; onTapped: tray.menuStack = tray.menuStack.slice(0, -1) }
                            }

                            Repeater {
                                model: opener.children
                                Item {
                                    id: entry
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: modelData.isSeparator ? 9 : 38

                                    Rectangle {      // separator
                                        visible: entry.modelData.isSeparator
                                        anchors.centerIn: parent
                                        width: parent.width - 24; height: 1
                                        color: theme.clrBorder
                                    }
                                    Rectangle {      // menu row
                                        visible: !entry.modelData.isSeparator
                                        anchors.fill: parent
                                        radius: 12
                                        color: rowHover.hovered && entry.modelData.enabled ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                                        opacity: entry.modelData.enabled ? 1 : 0.4
                                        RowLayout {
                                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                            spacing: 10
                                            // check / radio state
                                            Text {
                                                visible: entry.modelData.buttonType !== QsMenuButtonType.None
                                                text: entry.modelData.buttonType === QsMenuButtonType.RadioButton
                                                      ? (entry.modelData.checkState === Qt.Checked ? "󰐾" : "󰄰")
                                                      : (entry.modelData.checkState === Qt.Checked ? "󰄲" : "󰄱")
                                                font.family: theme.fontFamily; font.pixelSize: 16
                                                color: entry.modelData.checkState === Qt.Checked ? theme.clrAccent : theme.clrFgMuted
                                            }
                                            IconImage {
                                                visible: entry.modelData.icon !== ""
                                                source: entry.modelData.icon
                                                implicitSize: 16
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: entry.modelData.text.replace(/_(?!_)/g, "")   // strip mnemonic underscores
                                                elide: Text.ElideRight
                                                font.family: theme.fontFamily; font.pixelSize: 12
                                                color: theme.clrFg
                                            }
                                            Text {
                                                visible: entry.modelData.hasChildren
                                                text: "󰅂"
                                                font.family: theme.fontFamily; font.pixelSize: 14
                                                color: theme.clrFgMuted
                                            }
                                        }
                                        HoverHandler { id: rowHover; cursorShape: entry.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler {
                                            enabled: entry.modelData.enabled
                                            onTapped: {
                                                if (entry.modelData.hasChildren) {
                                                    tray.menuStack = tray.menuStack.concat([entry.modelData])
                                                } else {
                                                    entry.modelData.triggered()
                                                    tray.close()
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
}
