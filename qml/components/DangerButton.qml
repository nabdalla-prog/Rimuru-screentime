import QtQuick
import qs.Commons

// A button for something that can't be undone. It takes several clicks, each
// asking again ("RESET" > "SURE?" > "REALLY?"); the last click does it. Waiting
// too long, or leaving the button, starts over.
Item {
    id: root

    property var steps: ["DELETE", "SURE?"]
    property string title: ""
    property string detail: ""
    property color danger: Color.urgent
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    property int stage: 0

    signal confirmed

    width: parent ? parent.width : implicitWidth
    height: Math.max(Style.space(38), texts.implicitHeight + Style.space(10))

    Timer {
        id: revert
        interval: 4000
        onTriggered: root.stage = 0
    }

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: button.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.title
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
        }
        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.detail
            wrapMode: Text.WordWrap
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }
    Rectangle {
        id: button
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(96), label.implicitWidth + Style.space(24))
        height: Style.space(28)
        radius: Style.space(6)
        // Neutral until you hover or begin confirming, then the danger colour.
        readonly property bool armed: root.stage > 0 || mouse.containsMouse
        color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, root.stage > 0 ? 0.28 : (mouse.containsMouse ? 0.16 : 0.06))
        border.width: 1
        border.color: armed ? root.danger : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

        Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.steps[root.stage]
            color: button.armed ? root.danger : Qt.darker(root.foreground, 1.25)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onExited: {
                root.stage = 0;
                revert.stop();
            }
            onClicked: {
                if (root.stage >= root.steps.length - 1) {
                    root.stage = 0;
                    revert.stop();
                    root.confirmed();
                } else {
                    root.stage++;
                    revert.restart();
                }
            }
        }
    }
}
