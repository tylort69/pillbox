import QtQuick
import Quickshell
import Quickshell.Io

// Mic / camera / screen-share in use (scripts/privacy.py, every 3 s).
Scope {
    id: privacy
    property var mic: []
    property var camera: []
    property var screen: []
    readonly property bool active: mic.length + camera.length + screen.length > 0
    readonly property var apps: Array.from(new Set(mic.concat(camera, screen)))

    Process {
        id: probe
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/privacy.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); privacy.mic = r.mic; privacy.camera = r.camera; privacy.screen = r.screen } catch (e) {}
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: probe.running = true }
}
