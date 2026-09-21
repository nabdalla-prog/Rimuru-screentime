import QtQuick
import qs.Commons

// A small key cap shown next to a control while key hints are on ("f"), naming
// the key that triggers it.
Rectangle {
    id: root

    property string key: ""
    property bool show: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    visible: show && key !== ""
    z: 20
    width: Math.max(height, label.implicitWidth + Style.space(8))
    height: Style.space(16)
    radius: Style.space(4)
    color: foreground

    Text {
        id: label
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.key
        color: Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
    }
}
