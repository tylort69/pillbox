import QtQuick

// Material 3 (2024) style slider: thick rounded track, a gap, and a slim handle.
Item {
    id: s
    required property var theme
    property real value: 0                  // 0..1
    property bool muted: false
    signal moved(real v)

    implicitHeight: 28
    implicitWidth: 200
    readonly property real handleX: 2 + value * (width - 4 - 4)
    readonly property color activeColor: muted ? theme.clrFgMuted : theme.clrAccent

    // Active (filled) part
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: Math.max(0, s.handleX - 6)
        height: 16
        radius: 8
        color: s.activeColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    // Inactive part
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: s.handleX + 10
        width: Math.max(0, s.width - x)
        height: 16
        radius: 8
        color: s.theme.clrAccentC
        opacity: s.muted ? 0.5 : 1
    }
    // Handle
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: s.handleX
        width: 4
        height: drag.pressed ? 32 : 28
        radius: 2
        color: s.activeColor
        Behavior on height { NumberAnimation { duration: 100 } }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function set(mx) { s.moved(Math.max(0, Math.min(1, mx / s.width))) }
        onPressed: (m) => set(m.x)
        onPositionChanged: (m) => { if (pressed) set(m.x) }
        onWheel: (w) => s.moved(Math.max(0, Math.min(1, s.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
