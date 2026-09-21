import QtQuick
import qs.Commons

// A label (with an optional line of detail) and an on/off switch. Clicking
// anywhere on the row flips it.
Item {
    id: root

    property string label: ""
    property string detail: ""
    property bool checked: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal toggled(bool value)

    width: parent ? parent.width : implicitWidth
    height: Math.max(Style.space(30), texts.implicitHeight + Style.space(8))

    Column {
        id: texts
        anchors.left: parent.left
        anchors.right: track.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.label
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
        }
        Text {
            visible: root.detail !== ""
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
        id: track
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: Style.space(18)
        radius: height / 2
        color: root.checked ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Rectangle {
            width: parent.height - Style.space(6)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - Style.space(3) : Style.space(3)
            color: root.checked ? Color.background : root.foreground
            Behavior on x {
                NumberAnimation {
                    duration: 120
                }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
