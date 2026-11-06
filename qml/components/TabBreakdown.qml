import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

Column {
    id: root

    property string browserName: ""
    property var rows: []
    property var colors: []
    property int highlightedIndex: -1
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    readonly property color dim: Qt.darker(foreground, 1.5)

    signal rowHoverRequested(int index)
    signal areaEntered
    signal areaLeft

    visible: rows.length > 0
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(3)

    SectionLabel {
        text: root.browserName.toUpperCase() + " SITES"
    }
    Flickable {
        width: parent.width
        height: Math.min(tabColumn.implicitHeight, Style.space(175))
        contentWidth: width
        contentHeight: tabColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: tabColumn
            width: parent.width
            Repeater {
                model: root.rows
                Item {
                    required property var modelData
                    required property int index
                    width: tabColumn.width
                    height: Style.space(25)
                    Rectangle {
                        anchors.fill: parent
                        radius: Style.space(4)
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)
                        visible: root.highlightedIndex === index
                    }
                    Rectangle {
                        id: dot
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(15)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(6)
                        height: width
                        radius: width / 2
                        color: root.colors[index] !== undefined ? root.colors[index] : root.foreground
                    }
                    Text {
                        anchors.left: dot.right
                        anchors.leftMargin: Style.space(6)
                        anchors.right: tabTime.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: modelData.title
                        elide: Text.ElideRight
                        color: root.highlightedIndex === index ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    Text {
                        id: tabTime
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: Model.fmt(modelData.ms)
                        color: root.highlightedIndex === index ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    HoverHandler {
                        onHoveredChanged: root.rowHoverRequested(hovered ? index : -1)
                    }
                }
            }
        }
    }
    Text {
        textFormat: Text.PlainText
        text: "Set a site limit in Settings with tab:youtube.com."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
    }
    HoverHandler {
        onHoveredChanged: {
            if (hovered) root.areaEntered();
            else root.areaLeft();
        }
    }
}
