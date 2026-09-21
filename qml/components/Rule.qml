import QtQuick
import qs.Commons

// A one-pixel divider tinted from the foreground, like the shell's own.
Rectangle {
    property color foreground: Color.foreground

    width: parent ? parent.width : 100
    height: 1
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
}
