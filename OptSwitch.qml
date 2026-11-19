import QtQuick
import QtQuick.Layouts

// Settings row: label, description and a Material 3 switch. toggled() on click.
Rectangle {
    id: osw
    required property var theme
    property string label
    property string sub
    property bool on
    signal toggled()

    implicitHeight: row.implicitHeight + 12
    radius: 14
    color: hover.hovered ? Qt.alpha(theme.clrFg, 0.06) : "transparent"

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: osw.label; font.family: osw.theme.fontFamily; font.pixelSize: 12; color: osw.theme.clrFg }
            Text {
                Layout.fillWidth: true
                text: osw.sub
                visible: text !== ""
                wrapMode: Text.Wrap
                font.family: osw.theme.fontFamily; font.pixelSize: 10; color: osw.theme.clrFgMuted
            }
        }
        Rectangle {
            implicitWidth: 44; implicitHeight: 26; radius: 13
            color: osw.on ? osw.theme.clrAccent : "transparent"
            border.width: osw.on ? 0 : 2
            border.color: osw.theme.clrFgMuted
            Behavior on color { ColorAnimation { duration: 150 } }
            Rectangle {
                width: osw.on ? 18 : 12
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: osw.on ? parent.width - width - 4 : 7
                color: osw.on ? osw.theme.clrOnAccent : osw.theme.clrFgMuted
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: osw.toggled() }
}
