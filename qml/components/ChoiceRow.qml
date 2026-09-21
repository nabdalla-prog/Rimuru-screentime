import QtQuick
import qs.Commons

// A label above a row of choices, one of them selected. `options` is a list of
// { label, value }.
Column {
    id: root

    property string label: ""
    property var options: []
    property var value: null
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal chosen(var value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(6)

    Text {
        textFormat: Text.PlainText
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
    }
    Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
            model: root.options

            Rectangle {
                id: chip
                required property var modelData
                readonly property bool selected: modelData.value === root.value
                width: chipLabel.implicitWidth + Style.space(20)
                height: Style.space(26)
                radius: Style.space(6)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, selected ? 0.22 : (chipMouse.containsMouse ? 0.12 : 0.07))
                border.width: selected ? 1 : 0
                border.color: root.foreground

                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: chip.modelData.label
                    color: chip.selected ? root.foreground : Qt.darker(root.foreground, 1.25)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: chip.selected
                }
                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(chip.modelData.value)
                }
            }
        }
    }
}
