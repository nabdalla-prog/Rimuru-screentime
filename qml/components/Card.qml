import QtQuick
import qs.Commons

// A padded, softly tinted block that groups related settings under a title.
Rectangle {
    id: root

    property string title: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    // Overrides the tint (the danger zone uses a red one).
    property color tint: foreground
    default property alias content: inner.data

    width: parent ? parent.width : implicitWidth
    implicitHeight: inner.implicitHeight + Style.space(24)
    radius: Style.space(8)
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.07)

    Column {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        SectionLabel {
            visible: root.title !== ""
            text: root.title
            foreground: root.tint
            fontFamily: root.fontFamily
        }
    }
}
