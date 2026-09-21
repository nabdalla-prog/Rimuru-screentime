import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// Twelve month rows for one year: name, a bar scaled to the busiest month, and
// the time. Months outside the measured span (before tracking began, or still
// to come) show a dash and no bar. The current month is drawn at full strength.
Column {
    id: root

    property var months: []
    property int currentMonth: -1
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(3)

    Repeater {
        model: root.months

        Item {
            id: row
            required property var modelData
            width: root.width
            height: Style.space(22)
            opacity: modelData.outside ? 0.45 : 1

            Text {
                id: name
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(36)
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.modelData.month === root.currentMonth ? root.foreground : Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: row.modelData.month === root.currentMonth
            }
            Rectangle {
                anchors.left: name.right
                anchors.right: value.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(8)
                radius: height / 2
                visible: !row.modelData.outside
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                Rectangle {
                    width: row.modelData.ms > 0 ? Math.max(parent.height, parent.width * row.modelData.rel) : 0
                    height: parent.height
                    radius: height / 2
                    color: root.foreground
                    opacity: row.modelData.month === root.currentMonth ? 1 : 0.6
                }
            }
            Text {
                id: value
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(72)
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: row.modelData.ms > 0 ? Model.fmt(row.modelData.ms) : "–"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
            }
        }
    }
}
