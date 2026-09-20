import QtQuick
import qs.Commons

// One line of the app list: colour dot, name, time and share. Hovering it
// reports the row so the donut can spotlight the matching slice, and it
// lights up when the donut reports the same slice.
Item {
    id: root

    property color dotColor: Color.foreground
    property string name: ""
    property string timeText: ""
    property string percentText: ""
    property bool highlighted: false
    property bool dimmed: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal hoverChanged(bool inside)

    width: parent ? parent.width : implicitWidth
    height: Style.space(26)
    opacity: dimmed ? 0.45 : 1

    Rectangle {
        anchors.fill: parent
        radius: Style.space(4)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)
        visible: root.highlighted
    }
    Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(9)
        height: width
        radius: width / 2
        color: root.dotColor
    }
    Text {
        anchors.left: dot.right
        anchors.leftMargin: Style.space(8)
        anchors.right: values.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.name
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
    }
    Text {
        id: values
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.timeText + "  " + root.percentText
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hoverChanged(true)
        onExited: root.hoverChanged(false)
    }
}
