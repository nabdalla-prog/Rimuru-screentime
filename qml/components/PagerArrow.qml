import QtQuick
import qs.Commons

// Small clickable chevron for paging. Dims and ignores clicks when disabled.
Item {
    id: root

    property string glyph: "‹"
    property bool active: true
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    // Key hints: the key that triggers this arrow.
    property string hintKey: ""
    property bool hints: false

    signal clicked

    implicitWidth: Style.space(22)
    implicitHeight: Style.space(24)
    opacity: !active ? 0.25 : (mouse.containsMouse ? 1 : 0.7)

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title + 4
    }
    KeyBadge {
        anchors.centerIn: parent
        key: root.hintKey
        show: root.hints && root.active
        foreground: root.foreground
        fontFamily: root.fontFamily
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.active
        cursorShape: root.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
