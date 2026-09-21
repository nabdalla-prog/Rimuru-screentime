import QtQuick
import qs.Commons
import "../../js/Model.js" as Model

// One Monday-to-Sunday page of the trend: a header with the date range, the
// week's total (click it to flip between time and share of the week's 168
// hours) and paging arrows, then seven bars. Clicking a bar inspects that day;
// the wheel pages through weeks. `page` comes from Model.weekPage.
Item {
    id: root

    property var page: ({ label: "", total: 0, share: 0, days: [] })
    property string selectedKey: ""
    property bool showShare: false
    property bool hints: false
    // This week is the busiest ever recorded.
    property bool record: false
    property bool canOlder: false
    property bool canNewer: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal daySelected(string key)
    signal olderRequested
    signal newerRequested
    signal shareToggled

    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property real barAreaHeight: Style.space(60)
    readonly property string totalText: (record ? "\u2605 " : "") + (showShare ? Math.round((page.share || 0) * 100) + "% of week" : Model.fmt(page.total || 0))

    width: parent ? parent.width : implicitWidth
    implicitHeight: header.height + Style.space(8) + bars.height

    Item {
        id: header
        width: parent.width
        height: Style.space(24)

        PagerArrow {
            id: olderArrow
            anchors.left: parent.left
            glyph: "‹"
            active: root.canOlder
            hintKey: "["
            hints: root.hints
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.olderRequested()
        }
        Text {
            anchors.left: olderArrow.right
            anchors.right: totalLabel.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.page.label
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
        Text {
            id: totalLabel
            anchors.right: newerArrow.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.totalText
            color: totalMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.15)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            KeyBadge {
                anchors.right: parent.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                key: "s"
                show: root.hints
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
            MouseArea {
                id: totalMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.shareToggled()
            }
        }
        PagerArrow {
            id: newerArrow
            anchors.right: parent.right
            glyph: "›"
            active: root.canNewer
            hintKey: "]"
            hints: root.hints
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.newerRequested()
        }
    }

    Row {
        id: bars
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        width: parent.width

        Repeater {
            model: root.page.days

            Item {
                id: dayCol
                required property var modelData
                required property int index
                readonly property bool selected: modelData.key === root.selectedKey
                width: bars.width / 7
                height: root.barAreaHeight + Style.space(38)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Style.space(2)
                    radius: Style.space(6)
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, dayCol.selected ? 0.12 : (dayMouse.containsMouse && !dayCol.modelData.future ? 0.06 : 0))
                }
                Item {
                    id: barArea
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(6)
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(18)
                    height: root.barAreaHeight

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.space(4)
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, dayCol.modelData.future ? 0.04 : 0.1)
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: dayCol.modelData.ms > 0 ? Math.max(Style.space(4), parent.height * dayCol.modelData.rel) : 0
                        radius: Style.space(4)
                        color: root.foreground
                        opacity: dayCol.selected || dayCol.modelData.today ? 1 : 0.45
                    }
                }
                Text {
                    anchors.top: barArea.bottom
                    anchors.topMargin: Style.space(4)
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: dayCol.modelData.future ? "" : (dayCol.modelData.ms > 0 ? Model.fmt(dayCol.modelData.ms) : "–")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(4)
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: dayCol.modelData.letter
                    color: dayCol.selected || dayCol.modelData.today ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: dayCol.selected || dayCol.modelData.today
                }
                KeyBadge {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    key: String(index + 1)
                    show: root.hints && !dayCol.modelData.future
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !dayCol.modelData.future
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.daySelected(dayCol.modelData.key)
                }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (event) {
            if (event.angleDelta.y > 0 && root.canOlder)
                root.olderRequested();
            else if (event.angleDelta.y < 0 && root.canNewer)
                root.newerRequested();
        }
    }
}
