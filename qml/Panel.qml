import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

// Popup opened from the bar button: today's total, a per-app breakdown, and
// the last seven days. BarWidget.qml owns the button and injects `bar`,
// `anchorItem` and `hostWidget`; data comes from the Service via the widget.
Panel {
    id: root
    moduleName: "nabdalla.screentime"
    ipcTarget: "nabdalla.screentime"
    manageIpc: false

    property var anchorItem: null

    // The bar tracks the widget mounted in its slot (BarWidget.qml), not this
    // nested panel, so that is what it must be handed as the popout identity.
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    readonly property var service: hostWidget ? hostWidget.service : null
    readonly property int maxRows: 7

    // Only compute while visible: the service updates `days` every second.
    readonly property var rows: opened && service ? Model.topApps(service.today, maxRows) : []
    readonly property var week: opened && service ? Model.recentDays(service.days, new Date(), 7) : []
    readonly property double total: service ? service.todayTotal : 0
    readonly property int appCount: service ? Object.keys(service.today.apps).length : 0

    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color dim: Qt.darker(contentForeground, 1.5)
    readonly property color track: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.14)

    function open() {
        root.controller.show();
    }
    function close() {
        root.controller.hide();
    }
    function toggle() {
        if (root.opened)
            root.close();
        else
            root.open();
    }
    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction);
        return false;
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(360))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }

            Flickable {
                id: scroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: content
                    width: scroll.width
                    spacing: Style.space(10)

                    // ---- Hero: today's total ---------------------------------
                    Row {
                        spacing: Style.space(14)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰔟"
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: 40
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(2)

                            Text {
                                textFormat: Text.PlainText
                                text: Model.fmt(root.total)
                                color: root.contentForeground
                                font.family: root.contentFontFamily
                                font.pixelSize: 34
                                font.bold: true
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: root.appCount === 0 ? "Today" : "Today · " + root.appCount + (root.appCount === 1 ? " app" : " apps")
                                color: root.dim
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.body
                            }
                        }
                    }

                    PanelSeparator {
                        foreground: root.contentForeground
                    }

                    // ---- Per-app breakdown -----------------------------------
                    PanelSectionHeader {
                        text: "APPS"
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                    }

                    Text {
                        visible: root.rows.length === 0
                        textFormat: Text.PlainText
                        text: "No activity yet"
                        color: root.dim
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                    }

                    Repeater {
                        model: root.rows

                        Item {
                            id: appRow
                            required property var modelData
                            width: content.width
                            height: Style.space(30)

                            Text {
                                anchors.left: parent.left
                                anchors.right: timeText.left
                                anchors.rightMargin: Style.space(8)
                                textFormat: Text.PlainText
                                text: appRow.modelData.name
                                color: root.contentForeground
                                elide: Text.ElideRight
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.body
                            }
                            Text {
                                id: timeText
                                anchors.right: parent.right
                                textFormat: Text.PlainText
                                text: Model.fmt(appRow.modelData.ms) + "  " + Math.round(appRow.modelData.share * 100) + "%"
                                color: root.dim
                                font.family: root.contentFontFamily
                                font.pixelSize: Style.font.body
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Style.space(4)
                                radius: height / 2
                                color: root.track

                                Rectangle {
                                    width: Math.max(parent.height, parent.width * appRow.modelData.rel)
                                    height: parent.height
                                    radius: height / 2
                                    color: root.contentForeground
                                    opacity: appRow.modelData.other ? 0.45 : 1
                                }
                            }
                        }
                    }

                    PanelSeparator {
                        foreground: root.contentForeground
                    }

                    // ---- Last 7 days -----------------------------------------
                    PanelSectionHeader {
                        text: "LAST 7 DAYS"
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                    }

                    Row {
                        id: weekRow
                        width: content.width
                        spacing: 0

                        Repeater {
                            model: root.week

                            Column {
                                id: dayCol
                                required property var modelData
                                width: weekRow.width / 7
                                spacing: Style.space(4)

                                Item {
                                    width: parent.width
                                    height: Style.space(56)

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: Style.space(16)
                                        height: Math.max(Style.space(3), parent.height * dayCol.modelData.rel)
                                        radius: Style.space(3)
                                        color: root.contentForeground
                                        opacity: dayCol.modelData.today ? 1 : 0.35
                                    }
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: dayCol.modelData.ms > 0 ? Model.fmt(dayCol.modelData.ms) : "–"
                                    color: root.dim
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: dayCol.modelData.label
                                    color: dayCol.modelData.today ? root.contentForeground : root.dim
                                    font.family: root.contentFontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: dayCol.modelData.today
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
