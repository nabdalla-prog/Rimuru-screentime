import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Average time on each weekday (Monday to Sunday) across the year, as seven
// bars. The heaviest weekday is drawn at full strength.
Row {
    id: root

    property var weekdays: []
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    readonly property real barAreaHeight: Style.space(52)

    width: parent ? parent.width : implicitWidth

    Repeater {
        model: root.weekdays

        Item {
            id: col
            required property var modelData
            width: root.width / 7
            height: root.barAreaHeight + Style.space(34)

            Item {
                id: area
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(18)
                height: root.barAreaHeight

                Rectangle {
                    anchors.fill: parent
                    radius: Style.space(4)
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: col.modelData.ms > 0 ? Math.max(Style.space(4), parent.height * col.modelData.rel) : 0
                    radius: Style.space(4)
                    color: root.foreground
                    opacity: col.modelData.rel >= 1 ? 1 : 0.5
                }
            }
            Text {
                anchors.top: area.bottom
                anchors.topMargin: Style.space(4)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: col.modelData.ms > 0 ? Model.fmt(col.modelData.ms) : "–"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
            Text {
                anchors.bottom: parent.bottom
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: col.modelData.letter
                color: col.modelData.rel >= 1 ? root.foreground : Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: col.modelData.rel >= 1
            }
        }
    }
}
