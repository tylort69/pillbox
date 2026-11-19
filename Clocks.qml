import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Two independent clocks for the bar (local + a second time zone) and their
// settings panel (click the time). Settings live in settings.json:
//   clockLocal: { precision, hour24, showDate, dateFormat }
//   clockAlt:   { enabled, label, zone, precision, hour24, showDate, dateFormat }
Scope {
    id: clocks
    required property var theme
    required property var settings            // JsonAdapter of settings.json

    readonly property var local: settings.clockLocal
    readonly property var alt: settings.clockAlt
    property var panelScreen: null            // screen whose bar opened the panel

    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen }
    function update(which, change) {
        const cur = which === "local" ? settings.clockLocal : settings.clockAlt
        const next = Object.assign({}, cur, change)
        if (which === "local") settings.clockLocal = next; else settings.clockAlt = next
    }

    // ── Time source ───────────────────────────────────────────────────────────
    SystemClock {
        id: sys
        precision: (clocks.local.precision === "hms" || (clocks.alt.enabled && clocks.alt.precision === "hms"))
                   ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Offset of the second clock's zone, from the system tz database (handles DST)
    property int altOffsetMin: 0
    property bool altZoneValid: true
    Process {
        id: zoneProbe
        command: ["sh", "-c", 'test -f "/usr/share/zoneinfo/$1" && TZ="$1" date +%z || echo invalid', "_", clocks.alt.zone]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                clocks.altZoneValid = t !== "invalid"
                if (!clocks.altZoneValid) return
                const sign = t[0] === "-" ? -1 : 1
                clocks.altOffsetMin = sign * (parseInt(t.substr(1, 2)) * 60 + parseInt(t.substr(3, 2)))
            }
        }
    }
    function probeZone() { zoneProbe.running = false; zoneProbe.running = true }
    Connections { target: clocks; function onAltChanged() { clocks.probeZone() } }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: clocks.probeZone() }

    // ── Formatting ───────────────────────────────────────────────────────────
    function timeFormat(c) {
        if (c.precision === "h") return c.hour24 ? "HH'h'" : "h AP"
        if (c.precision === "hms") return c.hour24 ? "HH:mm:ss" : "h:mm:ss AP"
        return c.hour24 ? "HH:mm" : "h:mm AP"
    }
    function render(c, d) {
        const t = Qt.formatDateTime(d, timeFormat(c))
        return c.showDate ? Qt.formatDateTime(d, c.dateFormat) + "  " + t : t
    }
    readonly property date altDate: new Date(sys.date.getTime() + (altOffsetMin + sys.date.getTimezoneOffset()) * 60000)
    readonly property string localText: render(local, sys.date)
    readonly property string altText: render(alt, altDate)

    // Choices shown in the panel
    readonly property var precisions: [["h", "Hours"], ["hm", "Hours:Min"], ["hms", "H:M:S"]]
    readonly property var dateFormats: ["ddd d MMM", "dddd, d MMMM", "d MMM yyyy", "yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "MMM d, yyyy"]
    readonly property var zones: [
        ["Reykjavík", "Atlantic/Reykjavik"], ["UTC", "UTC"], ["London", "Europe/London"],
        ["Berlin", "Europe/Berlin"], ["New York", "America/New_York"], ["Los Angeles", "America/Los_Angeles"],
        ["Tokyo", "Asia/Tokyo"], ["Sydney", "Australia/Sydney"],
    ]

    // ── Reusable controls ─────────────────────────────────────────────────────
    component Segmented: Row {
        id: seg
        property var options: []             // [[value, label], ...]
        property string value
        signal picked(string v)
        spacing: 0
        Repeater {
            model: seg.options
            Rectangle {
                required property var modelData
                required property int index
                readonly property bool on: seg.value === modelData[0]
                width: segText.implicitWidth + 28; height: 34
                radius: 0
                color: on ? theme.clrAccentC : (segHover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent")
                border.width: 1; border.color: theme.clrBorder
                // M3 segmented button: rounded outer ends
                topLeftRadius: index === 0 ? 17 : 0
                bottomLeftRadius: index === 0 ? 17 : 0
                topRightRadius: index === seg.options.length - 1 ? 17 : 0
                bottomRightRadius: index === seg.options.length - 1 ? 17 : 0
                Text {
                    id: segText
                    anchors.centerIn: parent
                    text: (parent.on ? "󰄬 " : "") + modelData[1]
                    font.family: theme.fontFamily; font.pixelSize: 12
                    color: parent.on ? theme.clrOnAccentC : theme.clrFg
                }
                HoverHandler { id: segHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: seg.picked(modelData[0]) }
            }
        }
    }

    component Switch: Rectangle {
        id: sw
        property bool checked
        signal toggled()
        implicitWidth: 52; implicitHeight: 32; radius: 16
        color: checked ? theme.clrAccent : theme.clrBgAlt
        border.width: checked ? 0 : 2
        border.color: theme.clrFgMuted
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: sw.checked ? 24 : 16; height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - 4 : 8
            color: sw.checked ? theme.clrOnAccent : theme.clrFgMuted
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: sw.toggled() }
    }

    component Chip: Rectangle {
        id: chip
        property string label
        property bool selected
        signal clicked()
        implicitWidth: chipText.implicitWidth + 22; implicitHeight: 30; radius: 8
        color: selected ? theme.clrAccentC : (chipHover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent")
        border.width: selected ? 0 : 1; border.color: theme.clrBorder
        Text {
            id: chipText
            anchors.centerIn: parent
            text: (chip.selected ? "󰄬 " : "") + chip.label
            font.family: theme.fontFamily; font.pixelSize: 11
            color: chip.selected ? theme.clrOnAccentC : theme.clrFg
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    component Label: Text {
        font.family: theme.fontFamily; font.pixelSize: 12; font.bold: true
        color: theme.clrAccent
        Layout.topMargin: 6
    }

    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder
        property bool invalid: false
        signal accepted(string text)
        implicitHeight: 34; radius: 17
        color: theme.clrBg
        border.width: input.activeFocus || invalid ? 2 : 1
        border.color: invalid ? theme.clrUrgent : input.activeFocus ? theme.clrAccent : theme.clrBorder
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.fontFamily; font.pixelSize: 12
            color: theme.clrFg
            selectionColor: theme.clrAccentC
            onAccepted: field.accepted(text)
            onActiveFocusChanged: if (!activeFocus) field.accepted(text)
            Text {
                visible: !input.text
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholder
                font: input.font
                color: theme.clrFgMuted
            }
        }
    }

    // Month calendar (Material You date grid). Scroll or use the arrows to change month.
    property int monthOffset: 0
    onPanelScreenChanged: if (panelScreen) monthOffset = 0     // always open on the current month
    component CalendarCard: Rectangle {
        id: cal
        readonly property date today: sys.date
        readonly property date shown: new Date(today.getFullYear(), today.getMonth() + clocks.monthOffset, 1)
        readonly property int firstDow: Qt.locale().firstDayOfWeek % 7          // 0 = Sunday
        readonly property int lead: (shown.getDay() - firstDow + 7) % 7         // blanks before day 1
        readonly property int daysIn: new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()
        implicitWidth: 340
        implicitHeight: calCol.implicitHeight + 32
        radius: 24
        color: theme.clrBgAlt

        WheelHandler { onWheel: (e) => clocks.monthOffset += e.angleDelta.y > 0 ? -1 : 1 }

        ColumnLayout {
            id: calCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: Qt.formatDate(cal.shown, "MMMM yyyy")
                    font.family: theme.fontFamily; font.pixelSize: 15; font.bold: true
                    color: theme.clrFg
                }
                Rectangle {          // back to today
                    visible: clocks.monthOffset !== 0
                    implicitWidth: todayText.implicitWidth + 18; implicitHeight: 28; radius: 14
                    color: todayHover.hovered ? theme.clrAccentC : "transparent"
                    border.width: 1; border.color: theme.clrBorder
                    Text { id: todayText; anchors.centerIn: parent; text: "Today"; font.family: theme.fontFamily; font.pixelSize: 11; color: todayHover.hovered ? theme.clrOnAccentC : theme.clrFg }
                    HoverHandler { id: todayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: clocks.monthOffset = 0 }
                }
                Repeater {
                    model: [["󰅁", -1], ["󰅂", 1]]
                    Rectangle {
                        required property var modelData
                        implicitWidth: 30; implicitHeight: 30; radius: 15
                        color: navHover.hovered ? Qt.alpha(theme.clrFg, 0.08) : "transparent"
                        Text { anchors.centerIn: parent; text: modelData[0]; font.family: theme.fontFamily; font.pixelSize: 16; color: theme.clrFg }
                        HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: clocks.monthOffset += modelData[1] }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 2
                columnSpacing: 2
                // Weekday initials, starting on the locale's first day of the week
                Repeater {
                    model: 7
                    Text {
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((cal.firstDow + index) % 7, Locale.ShortFormat).slice(0, 2)
                        font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true
                        color: theme.clrFgMuted
                    }
                }
                // 6 weeks of days; neighbouring months' days are faded
                Repeater {
                    model: 42
                    Rectangle {
                        required property int index
                        readonly property date day: new Date(cal.shown.getFullYear(), cal.shown.getMonth(), index - cal.lead + 1)
                        readonly property bool inMonth: day.getMonth() === cal.shown.getMonth()
                        readonly property bool isToday: day.toDateString() === cal.today.toDateString()
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 18
                        color: isToday ? theme.clrAccent : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: parent.day.getDate()
                            font.family: theme.fontFamily; font.pixelSize: 12; font.bold: parent.isToday
                            color: parent.isToday ? theme.clrOnAccent : parent.inMonth ? theme.clrFg : Qt.alpha(theme.clrFgMuted, 0.45)
                        }
                    }
                }
            }
        }
    }

    // One settings card for a clock
    component ClockCard: Rectangle {
        id: card
        required property string which       // "local" | "alt"
        readonly property var c: which === "local" ? clocks.local : clocks.alt
        readonly property bool isAlt: which === "alt"
        readonly property bool active: !isAlt || c.enabled
        implicitWidth: 400
        implicitHeight: col.implicitHeight + 32
        radius: 24
        color: theme.clrBgAlt

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: card.isAlt ? "󰥔  Second clock" : "󰥔  Local time"
                    font.family: theme.fontFamily; font.pixelSize: 15; font.bold: true
                    color: theme.clrFg
                }
                Switch {
                    visible: card.isAlt
                    checked: !!(card.c && card.c.enabled)
                    onToggled: clocks.update("alt", { enabled: !card.c.enabled })
                }
            }

            // Live preview
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52; radius: 16
                color: theme.clrBg
                opacity: card.active ? 1 : 0.45
                Text {
                    anchors.centerIn: parent
                    text: (card.isAlt ? card.c.label + "  " : "") + (card.isAlt ? clocks.altText : clocks.localText)
                    font.family: theme.fontFamily; font.pixelSize: 20; font.bold: true
                    color: theme.clrFg
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                enabled: card.active
                opacity: card.active ? 1 : 0.45

                // Second clock: zone + label
                Label { visible: card.isAlt; text: "Time zone" }
                Flow {
                    visible: card.isAlt
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: clocks.zones
                        Chip {
                            required property var modelData
                            label: modelData[0]
                            selected: card.c.zone === modelData[1]
                            onClicked: clocks.update("alt", { zone: modelData[1], label: modelData[0] })
                        }
                    }
                }
                RowLayout {
                    visible: card.isAlt
                    Layout.fillWidth: true
                    spacing: 8
                    Field {
                        Layout.fillWidth: true
                        text: card.c.zone ?? ""
                        placeholder: "Any zone, e.g. Asia/Kolkata"
                        invalid: !clocks.altZoneValid
                        onAccepted: (t) => { if (t.trim() && t.trim() !== card.c.zone) clocks.update("alt", { zone: t.trim() }) }
                    }
                    Field {
                        Layout.preferredWidth: 130
                        text: card.c.label ?? ""
                        placeholder: "Label"
                        onAccepted: (t) => { if (t !== card.c.label) clocks.update("alt", { label: t }) }
                    }
                }
                Text {
                    visible: card.isAlt && !clocks.altZoneValid
                    text: "Unknown time zone. Use a name like Europe/Paris."
                    font.family: theme.fontFamily; font.pixelSize: 11
                    color: theme.clrUrgent
                }

                Label { text: "Time" }
                Segmented {
                    options: clocks.precisions
                    value: card.c.precision
                    onPicked: (v) => clocks.update(card.which, { precision: v })
                }
                Segmented {
                    options: [["24", "24-hour"], ["12", "12-hour"]]
                    value: card.c.hour24 ? "24" : "12"
                    onPicked: (v) => clocks.update(card.which, { hour24: v === "24" })
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Label { Layout.fillWidth: true; Layout.topMargin: 0; text: "Show date" }
                    Switch {
                        checked: card.c.showDate
                        onToggled: clocks.update(card.which, { showDate: !card.c.showDate })
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    enabled: card.c.showDate
                    opacity: card.c.showDate ? 1 : 0.45
                    Repeater {
                        model: clocks.dateFormats
                        Chip {
                            required property var modelData
                            label: Qt.formatDateTime(card.isAlt ? clocks.altDate : sys.date, modelData)
                            selected: card.c.dateFormat === modelData
                            onClicked: clocks.update(card.which, { dateFormat: modelData })
                        }
                    }
                }
            }
        }
    }

    // ── Panel: drops down under the bar's centre ─────────────────────────────
    // Click anywhere outside this panel (and the bars) to close it
    HyprlandFocusGrab {
        active: clockPanel.visible
        windows: [clockPanel].concat(theme.barWindows)
        onCleared: clocks.panelScreen = null
    }

    PanelWindow {
        id: clockPanel
        screen: clocks.panelScreen ?? Quickshell.screens[0]
        visible: clocks.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "center"); bottom: theme.edge("bottom", "center"); left: theme.edge("left", "center"); right: theme.edge("right", "center") }
        margins { top: theme.gap("top", "center"); bottom: theme.gap("bottom", "center"); left: theme.gap("left", "center"); right: theme.gap("right", "center") }
        implicitWidth: cards.implicitWidth + 32
        implicitHeight: cards.implicitHeight + 32
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-clock"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: clocks.panelScreen = null

            RowLayout {
                id: cards
                anchors { fill: parent; margins: 16 }
                spacing: 12
                CalendarCard { Layout.alignment: Qt.AlignTop }
                ClockCard { which: "local"; Layout.alignment: Qt.AlignTop }
                ClockCard { which: "alt"; Layout.alignment: Qt.AlignTop }
            }
        }
    }

    // `qs ipc call clock toggle`
    IpcHandler {
        target: "clock"
        function toggle(): void { clocks.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
    }
}
