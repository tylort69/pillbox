import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Countdown timer, alarm (at a clock time) + Pomodoro. Lives next to the clock; the panel opens under it.
// State is kept in settings.json (settings.countdown), so it survives bar restarts.
Scope {
    id: cd
    required property var theme
    required property var settings

    // ── state ────────────────────────────────────────────────────────────────
    // st: { mode: "timer"|"alarm"|"pomodoro", state: "idle"|"running"|"paused",
    //       endAt: ms, left: ms (when paused), total: ms, phase: "work"|"short"|"long", done: int,
    //       alarm only: label: string, warn: minutes before to remind (0 = off), warned: bool }
    readonly property var st: settings.countdown ?? ({})
    readonly property string mode: st.mode ?? "timer"
    readonly property string status: st.state ?? "idle"
    readonly property string phase: st.phase ?? "work"
    readonly property int done: st.done ?? 0
    readonly property var pomo: settings.pomodoro ?? ({ work: 25, short: 5, long: 15, every: 4, autoNext: true })
    property real now: Date.now()
    readonly property real left: status === "running" ? Math.max(0, (st.endAt ?? 0) - now) : status === "paused" ? (st.left ?? 0) : 0
    readonly property real progress: (st.total ?? 0) > 0 ? 1 - left / st.total : 0
    readonly property bool active: status !== "idle"
    property int customMin: 20
    // Alarm being set up in the panel: minutes after midnight, reminder and label
    property int alarmMin: (new Date().getHours() + 1) % 24 * 60
    property int alarmWarn: 10
    property string alarmLabel: ""
    readonly property bool hour24: settings.clockLocal?.hour24 ?? true
    property var panelScreen: null

    readonly property var phaseInfo: ({
        work:  { icon: "󰔟", name: "Focus" },
        short: { icon: "󰅶", name: "Short break" },
        long:  { icon: "󰒲", name: "Long break" }
    })

    function save(patch) { settings.countdown = Object.assign({}, st, patch) }
    function fmt(ms) {
        const s = Math.ceil(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
        const p = (n) => (n < 10 ? "0" : "") + n
        return h ? h + ":" + p(m) + ":" + p(x) : p(m) + ":" + p(x)
    }
    function togglePanel(screen) { panelScreen = (panelScreen === screen) ? null : screen; now = Date.now() }

    // ── alarm helpers ────────────────────────────────────────────────────────
    function clockText(d) { return Qt.formatTime(d, hour24 ? "HH:mm" : "h:mm AP") }
    function minText(min) { return clockText(new Date(2000, 0, 1, Math.floor(min / 60), min % 60)) }
    // Next time the clock shows min (minutes after midnight): today, or tomorrow if it has passed
    function nextAt(min) {
        const d = new Date(now); d.setHours(Math.floor(min / 60), min % 60, 0, 0)
        if (d.getTime() <= now) d.setDate(d.getDate() + 1)
        return d
    }
    function isTomorrow(d) { return d.getDate() !== new Date(now).getDate() }
    function until(ms) {
        const m = Math.ceil(ms / 60000), h = Math.floor(m / 60)
        return h ? h + " h" + (m % 60 ? " " + m % 60 + " min" : "") : m + " min"
    }
    // "11", "11:30", "1130", "7:45pm", "9a" -> minutes after midnight, or -1.
    // Without am/pm on a 12-hour clock, "11" means whichever of 11:00 / 23:00 comes next.
    function parseTime(text) {
        const r = String(text).trim().toLowerCase().replace(/\s+/g, "").replace(".", ":")
                   .match(/^(\d{1,2})(?::?(\d{2}))?(a|p|am|pm)?$/)
        if (!r) return -1
        let h = parseInt(r[1]); const m = r[2] ? parseInt(r[2]) : 0
        if (m > 59) return -1
        if (r[3]) {
            if (h < 1 || h > 12) return -1
            h = h % 12 + (r[3][0] === "p" ? 12 : 0)
        } else if (h > 23) return -1
        else if (!hour24 && h >= 1 && h <= 12) {
            const am = h % 12 * 60 + m, pm = am + 720
            return nextAt(am).getTime() <= nextAt(pm).getTime() ? am : pm
        }
        return h * 60 + m
    }
    // The next few round half hours, at least 10 minutes away
    function quickSlots() {
        const d = new Date(now + 10 * 60000)
        let min = Math.ceil((d.getHours() * 60 + d.getMinutes()) / 30) * 30
        const out = []
        for (let i = 0; i < 6; i++) out.push((min + i * 30) % 1440)
        return out
    }
    function setAlarm(min) { alarmMin = (min + 1440) % 1440; atInput.text = minText(alarmMin) }
    function startAlarm(min, warn, label) {
        const end = nextAt(min).getTime(), ms = end - Date.now()
        save({ mode: "alarm", state: "running", endAt: end, total: ms, left: 0,
               label: label ?? "", warn: warn ?? 0, warned: ms <= (warn ?? 0) * 60000 })
    }

    function startTimer(min) {
        const ms = Math.round(min * 60000)
        save({ mode: "timer", state: "running", endAt: Date.now() + ms, total: ms, left: 0 })
    }
    function startPhase(ph, doneCount) {
        const ms = pomo[ph] * 60000
        save({ mode: "pomodoro", state: "running", phase: ph, endAt: Date.now() + ms, total: ms, left: 0,
               done: doneCount ?? done })
    }
    function pause()  { if (status === "running" && mode !== "alarm") save({ state: "paused", left: left }) }
    function resume() { if (status === "paused") save({ state: "running", endAt: Date.now() + (st.left ?? 0) }) }
    function toggle() { status === "running" ? pause() : status === "paused" ? resume() : null }
    function stop()   { save({ state: "idle", left: 0, endAt: 0, total: 0 }) }
    function add(min) {
        if (status === "running") save({ endAt: st.endAt + min * 60000, total: st.total + min * 60000,
                                         warned: (st.warned ?? false) && left + min * 60000 <= (st.warn ?? 0) * 60000 })
        else if (status === "paused") save({ left: st.left + min * 60000, total: st.total + min * 60000 })
    }
    function skip() { if (mode === "pomodoro") finish(true) }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Timer", "-u", "critical", "-i", "alarm-symbolic", title, body])
        Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
    }
    function finish(skipped) {
        if (mode === "alarm") {
            const at = clockText(new Date(st.endAt ?? now)), label = st.label ?? ""
            stop()
            notify("It's " + at, label || "Alarm for " + at)
            return
        }
        if (mode === "timer") {
            stop()
            notify("Time's up", fmt(st.total ?? 0) + " timer finished")
            return
        }
        const wasWork = phase === "work"
        const d = wasWork ? done + 1 : done
        const nextPh = wasWork ? (d % (pomo.every ?? 4) === 0 ? "long" : "short") : "work"
        if (!skipped) notify(wasWork ? "Focus session done" : "Break over",
                             (wasWork ? "Take a " + pomo[nextPh] + " min " + phaseInfo[nextPh].name.toLowerCase() : "Back to focus for " + pomo.work + " min")
                             + "  ·  " + d + " session" + (d === 1 ? "" : "s") + " today")
        if (pomo.autoNext ?? true) startPhase(nextPh, d)
        else save({ state: "idle", phase: nextPh, done: d, total: 0 })
    }

    Timer {
        interval: 250
        running: cd.status === "running"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cd.now = Date.now()
            if (cd.left <= 0) cd.finish(false)
            else if (cd.mode === "alarm" && (cd.st.warn ?? 0) > 0 && !cd.st.warned && cd.left <= cd.st.warn * 60000) {
                const at = cd.clockText(new Date(cd.st.endAt))
                cd.save({ warned: true })
                Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm-symbolic",
                                         (cd.st.label || "Alarm") + " at " + at, "In " + cd.until(cd.left)])
                Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/bell.oga"])
            }
        }
    }

    // Keeps the "in 1 h 20 min" text and the quick times fresh while setting an alarm
    Timer {
        interval: 15000
        running: cd.panelScreen !== null && cd.mode === "alarm" && !cd.active
        repeat: true
        onTriggered: cd.now = Date.now()
    }

    IpcHandler {
        target: "timer"
        function toggle(): void { cd.togglePanel(Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]) }
        function start(minutes: real): void { cd.startTimer(minutes) }
        function alarm(time: string): void { const m = cd.parseTime(time); if (m >= 0) cd.startAlarm(m, 0, "") }
        function pomodoro(): void { cd.startPhase("work", 0) }
        function pause(): void { cd.toggle() }
        function stop(): void { cd.stop() }
    }

    // ── panel ────────────────────────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string label
        property bool filled: false
        signal clicked()
        implicitWidth: chipT.implicitWidth + 24
        implicitHeight: 34
        radius: 17
        color: filled ? (chipHover.hovered ? Qt.lighter(theme.clrAccent, 1.08) : theme.clrAccent)
                      : chipHover.hovered ? theme.clrAccentC : theme.clrBgAlt
        Text {
            id: chipT
            anchors.centerIn: parent
            text: chip.label
            font.family: theme.fontFamily; font.pixelSize: 12; font.bold: chip.filled
            color: chip.filled ? theme.clrOnAccent : chipHover.hovered ? theme.clrOnAccentC : theme.clrFg
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chip.clicked() }
    }

    HyprlandFocusGrab {
        active: cdPanel.visible
        windows: [cdPanel].concat(theme.barWindows)
        onCleared: cd.panelScreen = null
    }

    PanelWindow {
        id: cdPanel
        screen: cd.panelScreen ?? Quickshell.screens[0]
        visible: cd.panelScreen !== null
        // Opens beside the bar wherever it is (shell.qml: edge / gap)
        anchors { top: theme.edge("top", "center"); bottom: theme.edge("bottom", "center"); left: theme.edge("left", "center"); right: theme.edge("right", "center") }
        margins { top: theme.gap("top", "center"); bottom: theme.gap("bottom", "center"); left: theme.gap("left", "center"); right: theme.gap("right", "center") }
        implicitWidth: 480
        implicitHeight: body.implicitHeight + 32
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-timer"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: 28
            color: theme.clrBg
            border.color: theme.clrBorder
            border.width: 1
            focus: true
            Keys.onEscapePressed: cd.panelScreen = null

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12

                // Mode tabs
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: tabs.implicitWidth + 6; implicitHeight: 36; radius: 18
                    color: theme.clrBgAlt
                    RowLayout {
                        id: tabs
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [["timer", "󱎫  Timer"], ["alarm", "󰀠  Alarm"], ["pomodoro", "󰔟  Pomodoro"]]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: cd.mode === modelData[0]
                                implicitWidth: tabT.implicitWidth + 24; implicitHeight: 30; radius: 15
                                color: on ? theme.clrAccentC : "transparent"
                                Text { id: tabT; anchors.centerIn: parent; text: modelData[1]; font.family: theme.fontFamily; font.pixelSize: 12; color: on ? theme.clrOnAccentC : theme.clrFg }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { enabled: !cd.active; onTapped: cd.save({ mode: modelData[0] }) }
                            }
                        }
                    }
                }

                // Ring + time
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 200; implicitHeight: 200
                    Canvas {
                        id: ring
                        anchors.fill: parent
                        property real p: cd.progress
                        onPChanged: requestPaint()
                        Connections { target: cd.theme; function onClrAccentChanged() { ring.requestPaint() } }
                        onPaint: {
                            const c = getContext("2d"); c.reset()
                            const r = width / 2 - 8
                            c.lineWidth = 10; c.lineCap = "round"
                            c.strokeStyle = Qt.alpha(theme.clrFg, 0.08)
                            c.beginPath(); c.arc(width / 2, height / 2, r, 0, 2 * Math.PI); c.stroke()
                            if (p > 0) {
                                c.strokeStyle = cd.mode === "pomodoro" && cd.phase !== "work" ? theme.clrOnTertC : theme.clrAccent
                                c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * p); c.stroke()
                            }
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: cd.active ? cd.fmt(cd.left)
                                : cd.mode === "pomodoro" ? cd.fmt(cd.pomo[cd.phase] * 60000)
                                : cd.mode === "alarm" ? cd.minText(cd.alarmMin) : cd.fmt(cd.customMin * 60000)
                            font.family: theme.fontFamily; font.pixelSize: 40; font.bold: true
                            color: cd.status === "paused" ? theme.clrFgMuted : theme.clrFg
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: cd.mode === "pomodoro"
                                ? cd.phaseInfo[cd.phase].icon + "  " + cd.phaseInfo[cd.phase].name + "  ·  " + cd.done + " done"
                                : cd.mode === "alarm" ? (cd.active
                                    ? "󰀠  " + cd.clockText(new Date(cd.st.endAt ?? 0))
                                    : (cd.isTomorrow(cd.nextAt(cd.alarmMin)) ? "Tomorrow, in " : "In ") + cd.until(cd.nextAt(cd.alarmMin).getTime() - cd.now))
                                : cd.status === "paused" ? "Paused" : cd.active ? "Running" : "Set a time"
                            font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFgMuted
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 150
                            visible: cd.mode === "alarm" && cd.active && !!cd.st.label
                            text: cd.st.label ?? ""
                            elide: Text.ElideRight
                            font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFg
                        }
                    }
                }

                // Idle timer: presets + custom minutes
                Flow {
                    visible: cd.mode === "timer" && !cd.active
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [1, 5, 10, 15, 30, 45, 60]
                        Chip { required property int modelData; label: modelData + " min"; onClicked: cd.startTimer(modelData) }
                    }
                }
                RowLayout {
                    visible: cd.mode === "timer" && !cd.active
                    Layout.fillWidth: true
                    spacing: 6
                    Chip { label: "−"; onClicked: cd.customMin = Math.max(1, cd.customMin - (cd.customMin > 10 ? 5 : 1)) }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34; radius: 17
                        color: theme.clrBgAlt
                        border.width: minInput.activeFocus ? 2 : 0; border.color: theme.clrAccent
                        TextInput {
                            id: minInput
                            anchors.centerIn: parent
                            width: parent.width - 20
                            horizontalAlignment: TextInput.AlignHCenter
                            text: cd.customMin
                            validator: IntValidator { bottom: 1; top: 1440 }
                            font.family: theme.fontFamily; font.pixelSize: 13; color: theme.clrFg
                            selectByMouse: true
                            onTextEdited: if (acceptableInput) cd.customMin = parseInt(text)
                            onAccepted: cd.startTimer(cd.customMin)
                        }
                        Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: "min"; font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
                    }
                    Chip { label: "+"; onClicked: cd.customMin = Math.min(1440, cd.customMin + (cd.customMin >= 10 ? 5 : 1)) }
                    Chip { label: "󰐊  Start"; filled: true; onClicked: cd.startTimer(cd.customMin) }
                }

                // Idle alarm: quick times, a clock time to type, reminder and label
                ColumnLayout {
                    visible: cd.mode === "alarm" && !cd.active
                    Layout.fillWidth: true
                    spacing: 8
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: cd.quickSlots()
                            Chip { required property int modelData; label: cd.minText(modelData); filled: cd.alarmMin === modelData; onClicked: cd.setAlarm(modelData) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip { label: "−"; onClicked: cd.setAlarm(cd.alarmMin - 15) }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 34; radius: 17
                            color: theme.clrBgAlt
                            border.width: atInput.activeFocus || !atInput.ok ? 2 : 0
                            border.color: atInput.ok ? theme.clrAccent : theme.clrUrgent
                            TextInput {
                                id: atInput
                                readonly property bool ok: cd.parseTime(text) >= 0
                                anchors.centerIn: parent
                                width: parent.width - 20
                                horizontalAlignment: TextInput.AlignHCenter
                                Component.onCompleted: text = cd.minText(cd.alarmMin)
                                font.family: theme.fontFamily; font.pixelSize: 13; color: theme.clrFg
                                selectByMouse: true
                                onTextEdited: if (ok) cd.alarmMin = cd.parseTime(text)
                                onEditingFinished: if (ok) text = cd.minText(cd.alarmMin)
                                onAccepted: if (ok) cd.startAlarm(cd.alarmMin, cd.alarmWarn, cd.alarmLabel)
                            }
                            Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: "at"; font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
                        }
                        Chip { label: "+"; onClicked: cd.setAlarm(cd.alarmMin + 15) }
                        Chip { label: "󰀠  Set"; filled: true; onClicked: cd.startAlarm(cd.alarmMin, cd.alarmWarn, cd.alarmLabel) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Heads-up"; font.family: theme.fontFamily; font.pixelSize: 11; color: theme.clrFgMuted }
                        Repeater {
                            model: [0, 5, 10, 15, 30]
                            Chip { required property int modelData; label: modelData ? modelData + " min" : "Off"; filled: cd.alarmWarn === modelData; onClicked: cd.alarmWarn = modelData }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34; radius: 17
                        color: theme.clrBgAlt
                        border.width: labelInput.activeFocus ? 2 : 0; border.color: theme.clrAccent
                        TextInput {
                            id: labelInput
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                            text: cd.alarmLabel
                            font.family: theme.fontFamily; font.pixelSize: 12; color: theme.clrFg
                            selectByMouse: true
                            onTextEdited: cd.alarmLabel = text
                            onAccepted: if (atInput.ok) cd.startAlarm(cd.alarmMin, cd.alarmWarn, cd.alarmLabel)
                            Text { visible: !parent.text; text: "What for? (optional, e.g. Errands)"; font: parent.font; color: theme.clrFgMuted }
                        }
                    }
                }

                // Idle pomodoro
                ColumnLayout {
                    visible: cd.mode === "pomodoro" && !cd.active
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6
                        Repeater {
                            model: [["work", "Focus"], ["short", "Break"], ["long", "Long break"]]
                            RowLayout {
                                required property var modelData
                                spacing: 2
                                Chip { label: "−"; implicitWidth: 30; onClicked: cd.settings.pomodoro = Object.assign({}, cd.pomo, { [modelData[0]]: Math.max(1, cd.pomo[modelData[0]] - 5) }) }
                                Text {
                                    text: modelData[1] + "\n" + cd.pomo[modelData[0]] + " min"
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFg
                                }
                                Chip { label: "+"; implicitWidth: 30; onClicked: cd.settings.pomodoro = Object.assign({}, cd.pomo, { [modelData[0]]: Math.min(120, cd.pomo[modelData[0]] + 5) }) }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            label: (cd.pomo.autoNext ?? true) ? "󰄲  Auto-start next" : "󰄱  Auto-start next"
                            onClicked: cd.settings.pomodoro = Object.assign({}, cd.pomo, { autoNext: !(cd.pomo.autoNext ?? true) })
                        }
                        Chip { visible: cd.done > 0; label: "󰑓  Reset count"; onClicked: cd.save({ done: 0, phase: "work" }) }
                        Item { Layout.fillWidth: true }
                        Chip { label: "󰐊  Start " + cd.phaseInfo[cd.phase].name.toLowerCase(); filled: true; onClicked: cd.startPhase(cd.phase) }
                    }
                }

                // Running / paused controls
                RowLayout {
                    visible: cd.active
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    Chip { label: cd.mode === "alarm" ? "+15 min" : "+1 min"; onClicked: cd.add(cd.mode === "alarm" ? 15 : 1) }
                    Chip { label: "+5 min"; onClicked: cd.add(5) }
                    Chip { visible: cd.mode !== "alarm"; label: cd.status === "running" ? "󰏤  Pause" : "󰐊  Resume"; filled: true; onClicked: cd.toggle() }
                    Chip { visible: cd.mode === "pomodoro"; label: "󰒭  Skip"; onClicked: cd.skip() }
                    Chip { label: "󰓛  Stop"; onClicked: cd.stop() }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: cd.mode === "alarm" ? "On the bar: right-click stops" : "On the bar: middle-click pauses, right-click stops"
                    font.family: theme.fontFamily; font.pixelSize: 10; color: theme.clrFgMuted
                }
            }
        }
    }
}
