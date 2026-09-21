import QtQuick
import qs.Commons

// A small pill: a name, optionally with a remove cross.
Rectangle {
    id: chip

    property string text: ""
    property bool removable: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal clicked

    width: chipText.implicitWidth + Style.space(18) + (removable ? Style.space(14) : 0)
    height: Style.space(24)
    radius: height / 2
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, chipMouse.containsMouse ? 0.2 : 0.11)

    Text {
        id: chipText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(9)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.text
        color: chip.foreground
        font.family: chip.fontFamily
        font.pixelSize: Style.font.caption
    }
    Text {
        visible: chip.removable
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "×"
        color: Qt.darker(chip.foreground, 1.5)
        font.family: chip.fontFamily
        font.pixelSize: Style.font.body
    }
    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
