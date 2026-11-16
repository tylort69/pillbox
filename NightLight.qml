import QtQuick
import Quickshell
import Quickshell.Io

// Night light (hyprsunset). The bar owns the process:
//   on  = hyprsunset running its schedule (~/.config/hypr/hyprsunset.conf)
//   off = hyprsunset stopped, normal colours
// Scroll adjusts the temperature until the next scheduled change.
Scope {
    id: night
    required property var settings              // JsonAdapter with `nightLight`

    readonly property bool enabled: settings.nightLight
    property bool running: false
    property int temperature: 6500               // 6500 K = neutral

    function toggle() { settings.nightLight = !settings.nightLight }
    function nudge(delta) {
        if (!running) return
        const t = Math.max(2500, Math.min(6500, temperature + delta))
        run(["hyprctl", "hyprsunset", "temperature", String(t)])
        temperature = t
    }

    Process { id: cmd }
    function run(argv) { cmd.command = argv; cmd.startDetached() }

    function apply() {
        if (enabled && !running) run(["sh", "-c", "pidof hyprsunset >/dev/null || exec hyprsunset"])
        if (!enabled) run(["pkill", "-x", "hyprsunset"])
        poll.kick()
    }
    onEnabledChanged: apply()
    Component.onCompleted: apply()

    // Keep `running` and `temperature` in sync (also after schedule changes)
    Process {
        id: probe
        command: ["sh", "-c", "pidof hyprsunset >/dev/null && hyprctl hyprsunset temperature || echo off"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                night.running = out !== "off" && out !== ""
                const t = parseInt(out)
                night.temperature = isNaN(t) ? 6500 : t
            }
        }
    }
    Timer {
        id: poll
        interval: 1500                           // quick first check after a change...
        running: true
        repeat: true
        onTriggered: { probe.running = true; interval = 30000 }   // ...then every 30 s
        function kick() { interval = 1500; stop(); start() }
    }

    // `qs ipc call night toggle | warmer | cooler`
    IpcHandler {
        target: "night"
        function toggle(): void { night.toggle() }
        function warmer(): void { night.nudge(-250) }
        function cooler(): void { night.nudge(250) }
    }
}
