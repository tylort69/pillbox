import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// One Material You notification card, used for pop-ups and in the history panel.
Rectangle {
    id: card
    required property var notif
    required property var theme          // the ShellRoot (colours + fonts)
    property var arrived: new Date()
    property bool popup: false
    property bool paused: false          // pop-up held while a panel is open; restarts its full time after
    signal closeRequested()              // pop-up: hide it (keeps it in history)

    readonly property bool critical: notif.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: notif.actions.find(a => a.identifier === "default")
    readonly property var buttons: notif.actions.filter(a => a.identifier !== "default")
    readonly property string iconSource: {
        const i = notif.image || notif.appIcon
        if (!i) return ""
        if (i.startsWith("/") || i.includes("://")) return i.startsWith("/") ? "file://" + i : i
        return Quickshell.iconPath(i, true)
    }

    implicitWidth: 400
    implicitHeight: content.implicitHeight + 28
    radius: 22
    color: hover.hovered ? Qt.lighter(theme.clrBgAlt, 1.08) : theme.clrBgAlt
    border.width: critical ? 2 : 1
    border.color: critical ? theme.clrUrgent : theme.clrBorder
    Behavior on color { ColorAnimation { duration: 150 } }

    HoverHandler { id: hover }

    // Click the card: run its default action (e.g. open the chat), then close it
    TapHandler {
        onTapped: {
            if (card.defaultAction) card.defaultAction.invoke()
            if (card.defaultAction || card.popup) card.notif.dismiss()
        }
    }

    RowLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // App icon / image in a tonal circle
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 40; implicitHeight: 40; radius: 20
            color: card.critical ? card.theme.clrUrgent : card.theme.clrAccentC

            IconImage {
                anchors.centerIn: parent
                implicitSize: 26
                source: card.iconSource
                visible: card.iconSource !== ""
            }
            Text {
                anchors.centerIn: parent
                visible: card.iconSource === ""
                text: card.critical ? "󰀦" : "󰂚"
                font.family: card.theme.fontFamily
                font.pixelSize: 20
                color: card.critical ? card.theme.clrBg : card.theme.clrOnAccentC
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: card.notif.appName || "Notification"
                    elide: Text.ElideRight
                    font.family: card.theme.fontFamily
                    font.pixelSize: 11
                    color: card.theme.clrFgMuted
                }
                Text {
                    text: Qt.formatDateTime(card.arrived, "HH:mm")
                    font.family: card.theme.fontFamily
                    font.pixelSize: 11
                    color: card.theme.clrFgMuted
                }
                // Close / dismiss
                Rectangle {
                    implicitWidth: 22; implicitHeight: 22; radius: 11
                    color: closeHover.hovered ? Qt.alpha(card.theme.clrFg, 0.12) : "transparent"
                    opacity: hover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        font.family: card.theme.fontFamily
                        font.pixelSize: 13
                        color: card.theme.clrFg
                    }
                    HoverHandler { id: closeHover }
                    TapHandler { onTapped: card.notif.dismiss() }
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.notif.summary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: card.theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                color: card.theme.clrFg
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notif.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 8
                elide: Text.ElideRight
                font.family: card.theme.fontFamily
                font.pixelSize: 12
                color: card.theme.clrFgMuted
                onLinkActivated: (link) => Qt.openUrlExternally(link)
            }

            // Action buttons: tonal pills
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: card.buttons.length > 0
                spacing: 6
                Repeater {
                    model: card.buttons
                    Rectangle {
                        required property var modelData
                        implicitWidth: actText.implicitWidth + 24
                        implicitHeight: 30
                        radius: 15
                        color: actHover.hovered ? card.theme.clrAccent : card.theme.clrAccentC
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            text: modelData.text
                            font.family: card.theme.fontFamily
                            font.pixelSize: 12
                            color: actHover.hovered ? card.theme.clrOnAccent : card.theme.clrOnAccentC
                        }
                        HoverHandler { id: actHover }
                        TapHandler { onTapped: { modelData.invoke(); card.notif.dismiss() } }
                    }
                }
            }
        }
    }

    // Pop-up lifetime: the app's timeout, or 6 s. Critical ones stay until closed.
    // Hovering pauses the countdown.
    Timer {
        running: card.popup && !card.paused && !card.critical && !hover.hovered
        interval: {
            const t = card.notif.expireTimeout
            if (!t || t <= 0) return 6000
            return t > 1000 ? t : t * 1000      // seconds or milliseconds
        }
        onTriggered: card.closeRequested()
    }
}
