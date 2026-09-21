import QtQuick
import qs.Commons

// Small bold caption that introduces a block ("MONTHS", "HIGHLIGHTS").
Text {
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    textFormat: Text.PlainText
    color: Qt.darker(foreground, 1.5)
    font.family: fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
}
