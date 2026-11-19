import QtQuick
import QtQuick.Layouts

// Row of mutually exclusive choices (Material 3 segmented button).
// options: [{ v: value, t: "Label" }]; value: the selected v; picked(v) when one is clicked.
Rectangle {
    id: seg
    required property var theme
    property var options: []
    property var value
    signal picked(var v)

    implicitHeight: 34
    radius: 17
    color: "transparent"
    border.width: 1
    border.color: theme.clrBorder

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Repeater {
            model: seg.options
            Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: seg.value === modelData.v
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 17
                color: on ? seg.theme.clrAccentC : optHover.hovered ? Qt.alpha(seg.theme.clrFg, 0.08) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: (opt.on ? "󰄬 " : "") + opt.modelData.t
                    font.family: seg.theme.fontFamily
                    font.pixelSize: 11
                    color: opt.on ? seg.theme.clrOnAccentC : seg.theme.clrFg
                }
                HoverHandler { id: optHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: seg.picked(opt.modelData.v) }
            }
        }
    }
}
