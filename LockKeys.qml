import QtQuick
import Quickshell
import Quickshell.Io

// Caps Lock / Num Lock state from the keyboard LEDs (/sys/class/leds/*::capslock).
// Hyprland has no event for lock keys, so read the LEDs once a second (cheap).
Scope {
    id: locks
    property bool caps: false
    property bool num: true

    Process {
        id: reader
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -r | head -1; cat /sys/class/leds/*::numlock/brightness 2>/dev/null | sort -r | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split("\n")
                locks.caps = v[0] === "1"
                locks.num = v.length < 2 || v[1] !== "0"
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: reader.running = true }
}
