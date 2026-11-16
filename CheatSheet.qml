import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Keybind cheat sheet (SUPER + / or SUPER + F1). Reads `hyprctl binds -j` every time
// it opens, so it always matches the live config. Binds are grouped by the part of
// their description before " · " (e.g. "Apps · Firefox"); binds without a
// description land in "Other". Rows that only differ by a number are merged (1–0).
Scope {
    id: sheet
    required property var theme
    property bool open: false
    property var groups: []                   // [{ name, rows: [{ keys, text }] }]
    property string filter: ""

    function toggle() { open = !open; if (open) { filter = ""; reader.running = true } }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { sheet.toggle() }
    }

    // ── Turning raw binds into rows ───────────────────────────────────────────
    readonly property var modNames: [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
    readonly property var keyNames: ({
        "catchall": "Any key", "slash": "/", "mouse:272": "Left drag", "mouse:273": "Right drag", "mouse_down": "Scroll ↓",
        "mouse_up": "Scroll ↑", "left": "←", "right": "→", "up": "↑", "down": "↓", "Escape": "Esc",
        "Print": "PrtSc", "XF86AudioRaiseVolume": "Vol +", "XF86AudioLowerVolume": "Vol −",
        "XF86AudioMute": "Mute", "XF86AudioMicMute": "Mic mute", "XF86AudioNext": "Next",
        "XF86AudioPrev": "Prev", "XF86AudioPlay": "Play", "XF86AudioPause": "Pause",
        "XF86MonBrightnessUp": "Bright +", "XF86MonBrightnessDown": "Bright −",
    })
    function keyLabel(k) { return keyNames[k] ?? (k.length === 1 ? k.toUpperCase() : k) }
    function mods(mask) { return modNames.filter(m => mask & m[0]).map(m => m[1]) }

    function build(binds) {
        const rows = []
        for (const b of binds) {
            let desc = b.description || ""
            let cat = "Other", text = desc
            const dot = desc.indexOf(" · ")
            if (dot > 0) { cat = desc.slice(0, dot); text = desc.slice(dot + 3) }
            if (!desc) text = "(no description) " + (b.dispatcher || "")
            if (b.submap) cat = cat === "Other" ? "Submap: " + b.submap : cat
            // Number-row binds made by keycode (SHIFT binds): code 10..18 = 1..9, 19 = 0
            let key = b.key
            if (b.catch_all) key = "catchall"
            // SHIFT + number binds are made with the shifted symbol (! @ # … ) — show the digit
            const shifted = { exclam: "1", at: "2", numbersign: "3", dollar: "4", percent: "5",
                              asciicircum: "6", ampersand: "7", asterisk: "8", parenleft: "9", parenright: "0" }
            if ((b.modmask & 1) && shifted[key]) key = shifted[key]
            if (!key && b.keycode >= 10 && b.keycode <= 19) key = b.keycode === 19 ? "0" : String(b.keycode - 9)
            else if (!key && b.keycode) key = "code " + b.keycode
            rows.push({ cat: cat, text: text, mods: mods(b.modmask), key: key })
        }
        // Merge rows that differ only by a single digit key (workspace binds etc.)
        const merged = [], seen = {}
        for (const r of rows) {
            const isDigit = /^[0-9]$/.test(r.key)
            const norm = isDigit ? r.text.replace(/\b[0-9]\b/, "N") : null
            const id = isDigit ? r.cat + "|" + r.mods.join("+") + "|" + norm : null
            if (id && seen[id]) { seen[id].digits.push(r.key); continue }
            const row = { cat: r.cat, text: isDigit ? norm : r.text, mods: r.mods, key: r.key, digits: isDigit ? [r.key] : null }
            if (id) seen[id] = row
            merged.push(row)
        }
        for (const r of merged) {
            if (r.digits && r.digits.length > 1) {
                const order = "1234567890"
                r.digits.sort((a, b) => order.indexOf(a) - order.indexOf(b))
                r.keyText = r.digits[0] + "–" + r.digits[r.digits.length - 1]
            } else {
                r.keyText = keyLabel(r.key)
                if (r.digits) r.text = r.text.replace("N", r.key)
            }
            r.keys = r.mods.concat([r.keyText])
        }
        // Group, keeping a sensible category order
        const order = ["Apps", "Windows", "Layout", "Focus", "Workspaces", "Monitors", "Pick workspace", "Session", "Shell", "Tools", "Media"]
        const byCat = {}
        for (const r of merged) (byCat[r.cat] = byCat[r.cat] || []).push(r)
        const names = Object.keys(byCat).sort((a, b) => {
            const ia = order.indexOf(a), ib = order.indexOf(b)
            return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b)
        })
        groups = names.map(n => ({ name: n, rows: byCat[n] }))
    }

    Process {
        id: reader
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: { try { sheet.build(JSON.parse(text)) } catch (e) { console.warn("cheatsheet:", e) } }
        }
    }

    function matches(row, group) {
        if (!filter) return true
        const f = filter.toLowerCase()
        return (group + " " + row.text + " " + row.keys.join(" ")).toLowerCase().includes(f)
    }

    readonly property var focusedScreen:
        Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    // ── Overlay ───────────────────────────────────────────────────────────────
    PanelWindow {
        screen: sheet.focusedScreen
        visible: sheet.open
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-cheatsheet"
        WlrLayershell.keyboardFocus: sheet.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Scrim: click outside the card to close
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(theme.clrBg, 0.6)
            TapHandler { onTapped: sheet.open = false }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 1500)
            height: Math.min(parent.height - 120, content.implicitHeight + 48)
            radius: 32
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            TapHandler {}                     // swallow clicks so the scrim doesn't close

            ColumnLayout {
                id: content
                anchors { fill: parent; margins: 24 }
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Text {
                        text: "󰌌  Keybinds"
                        font.family: theme.fontFamily; font.pixelSize: 24; font.bold: true
                        color: theme.clrFg
                    }
                    Item { Layout.fillWidth: true }
                    // Search
                    Rectangle {
                        implicitWidth: 360; implicitHeight: 44; radius: 22
                        color: theme.clrBgAlt
                        border.width: search.activeFocus ? 2 : 0
                        border.color: theme.clrAccent
                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                            spacing: 10
                            Text { text: "󰍉"; font.family: theme.fontFamily; font.pixelSize: 16; color: theme.clrFgMuted }
                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                focus: sheet.open
                                text: sheet.filter
                                onTextChanged: sheet.filter = text
                                font.family: theme.fontFamily; font.pixelSize: 14
                                color: theme.clrFg
                                Keys.onEscapePressed: sheet.open = false
                                Text {
                                    visible: !search.text
                                    text: "Search binds…"
                                    font: search.font
                                    color: theme.clrFgMuted
                                }
                            }
                        }
                    }
                    Text {
                        text: "Esc to close"
                        font.family: theme.fontFamily; font.pixelSize: 12
                        color: theme.clrFgMuted
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: flow.implicitHeight
                    contentHeight: flow.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Flow {
                        id: flow
                        width: parent.width
                        spacing: 14
                        readonly property int cols: Math.max(1, Math.floor((width + spacing) / (440 + spacing)))
                        readonly property real colW: (width - (cols - 1) * spacing) / cols

                        Repeater {
                            model: sheet.groups
                            Rectangle {
                                id: group
                                required property var modelData
                                readonly property var rows: modelData.rows.filter(r => sheet.matches(r, modelData.name))
                                visible: rows.length > 0
                                width: flow.colW
                                height: visible ? groupCol.implicitHeight + 28 : 0
                                radius: 24
                                color: theme.clrBgAlt

                                ColumnLayout {
                                    id: groupCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 6
                                    Text {
                                        text: group.modelData.name
                                        font.family: theme.fontFamily; font.pixelSize: 13; font.bold: true
                                        color: theme.clrAccent
                                        Layout.bottomMargin: 2
                                    }
                                    Repeater {
                                        model: group.rows
                                        RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4
                                            // Key caps
                                            Repeater {
                                                model: modelData.keys
                                                RowLayout {
                                                    required property var modelData
                                                    required property int index
                                                    spacing: 4
                                                    Text {
                                                        visible: index > 0
                                                        text: "+"
                                                        font.family: theme.fontFamily; font.pixelSize: 11
                                                        color: theme.clrFgMuted
                                                    }
                                                    Rectangle {
                                                        implicitWidth: Math.max(26, capText.implicitWidth + 14)
                                                        implicitHeight: 24
                                                        radius: 8
                                                        color: modelData === "SUPER" ? theme.clrAccentC : theme.clrBg
                                                        border.width: 1
                                                        border.color: theme.clrBorder
                                                        Text {
                                                            id: capText
                                                            anchors.centerIn: parent
                                                            text: modelData
                                                            font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true
                                                            color: modelData === "SUPER" ? theme.clrOnAccentC : theme.clrFg
                                                        }
                                                    }
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 8
                                                text: modelData.text
                                                elide: Text.ElideRight
                                                horizontalAlignment: Text.AlignRight
                                                font.family: theme.fontFamily; font.pixelSize: 12
                                                color: theme.clrFg
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
