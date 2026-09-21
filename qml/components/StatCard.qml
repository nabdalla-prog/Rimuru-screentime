import QtQuick
import qs.Commons

// One highlight of the year: a small label, a value and a line of detail.
Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string detail: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    implicitHeight: content.implicitHeight + Style.space(20)
    radius: Style.space(8)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.07)

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(10)
        spacing: Style.space(2)

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.label.toUpperCase()
            elide: Text.ElideRight
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }
        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.value
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
        }
        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.detail
            elide: Text.ElideRight
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }
}
