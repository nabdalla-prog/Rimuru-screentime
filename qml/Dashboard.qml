import QtQuick
import qs.Commons
import "../js/Model.js" as Model
import "components"

// Everything inside the popup: the day's total, a donut of its apps with a
// legend, a week-by-week trend, and a few insights. It knows nothing about
// the shell (Panel.qml wraps it), so it can be shown with any data.
//
// Clicking a bar in the trend inspects that day; clicking it again, or the
// "Today" link, comes back. Which day and week are on screen is state kept
// here and cleared by reset().
Item {
    id: root

    // ---- Inputs ------------------------------------------------------------
    property var days: ({})
    property string todayKey: Model.dayKey(new Date())
    property var ignoredApps: []
    property var appNames: ({})
    property int dailyGoalHours: 0
    // Off while the popup is closed, so nothing is recomputed each second.
    property bool active: true
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    // ---- State -------------------------------------------------------------
    property string selectedKey: ""   // "" means today
    property int back: 0              // weeks before the current one
    property bool showMore: false
    property bool showShare: false
    property int hoverIndex: -1

    readonly property int weekCap: 52
    readonly property int maxLegendApps: 6
    readonly property string glyph: "󰔟"

    readonly property date today: Model.parseKey(todayKey) || new Date()
    readonly property string activeKey: selectedKey !== "" ? selectedKey : todayKey
    readonly property bool viewingToday: activeKey === todayKey
    readonly property color dim: Qt.darker(foreground, 1.5)

    readonly property int lastBack: active ? Model.maxBack(days, today, weekCap) : 0
    readonly property string oldestKey: Model.dayKey(Model.mondayOf(Model.addDays(today, -7 * lastBack)))

    readonly property var dayData: active ? Model.visibleDay(days[activeKey] || Model.newDay(), ignoredApps, appNames) : Model.newDay()
    readonly property var slices: active ? Model.donutSlices(dayData, appNames, maxLegendApps, 0.03) : []
    // The apps the legend doesn't list (they sit under "Other" in the donut).
    readonly property var moreRows: active && showMore ? Model.topApps(dayData, 100000, appNames).slice(headCount) : []
    readonly property var page: active ? Model.weekPage(days, today, back, ignoredApps, appNames) : ({ label: "", total: 0, share: 0, days: [] })
    readonly property var insights: active ? Model.dayInsights(days, activeKey, todayKey, page, ignoredApps, appNames) : []
    readonly property var goal: Model.goalProgress(dayData.total, dailyGoalHours)
    readonly property bool hasOther: slices.length > 0 && slices[slices.length - 1].other === true
    readonly property int headCount: hasOther ? slices.length - 1 : slices.length

    // Slice colours: the theme's own colour first, then hues spread around the
    // wheel from it. "Other" is a dimmed foreground.
    readonly property var sliceColors: {
        var out = [];
        var base = foreground.hslSaturation > 0.15 ? foreground.hslHue : 0.5;
        for (var i = 0; i < slices.length; i++) {
            if (slices[i].other)
                out.push(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.4));
            else if (i === 0)
                out.push(foreground);
            else
                out.push(Qt.hsla((base + i * 0.618) % 1, 0.55, 0.6, 1));
        }
        return out;
    }

    // The slices with their colour attached, for the donut.
    readonly property var coloredSlices: {
        var out = [];
        for (var i = 0; i < slices.length; i++)
            out.push(Object.assign({}, slices[i], {
                "color": sliceColors[i]
            }));
        return out;
    }

    // ---- Actions -----------------------------------------------------------
    function reset() {
        selectedKey = "";
        back = 0;
        showMore = false;
        hoverIndex = -1;
    }

    function selectDay(key) {
        // Clicking the day already on screen goes back to today.
        selectedKey = (key === activeKey || key === todayKey) ? "" : key;
    }

    function pageBy(delta) {
        back = Math.max(0, Math.min(lastBack, back + delta));
    }

    // Arrow keys: move the selected day and follow it to its week.
    function stepDay(delta) {
        var next = Model.shiftDay(activeKey, delta, todayKey, oldestKey);
        selectedKey = next === todayKey ? "" : next;
        var d = Model.parseKey(next);
        if (d)
            back = Math.min(lastBack, Model.weeksBack(today, d));
    }

    implicitWidth: Style.space(460)
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---- Header: the day's total -----------------------------------------
        Item {
            width: parent.width
            height: heroRow.height

            Row {
                id: heroRow
                spacing: Style.space(14)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyph
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 40
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                        textFormat: Text.PlainText
                        text: Model.fmt(root.dayData.total)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: 34
                        font.bold: true
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: Model.dayTitle(root.activeKey, root.todayKey) + (root.dayAppCount > 0 ? " · " + root.dayAppCount + (root.dayAppCount === 1 ? " app" : " apps") : "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                    }
                }
            }
            Text {
                visible: !root.viewingToday
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Back to today"
                color: todayMouse.containsMouse ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.underline: todayMouse.containsMouse
                MouseArea {
                    id: todayMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reset()
                }
            }
        }

        // ---- Daily goal (today only, and only when one is set) -----------------
        Column {
            visible: root.goal.enabled && root.viewingToday
            width: parent.width
            spacing: Style.space(4)

            Rectangle {
                width: parent.width
                height: Style.space(6)
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

                Rectangle {
                    width: Math.max(parent.height, parent.width * root.goal.ratio)
                    height: parent.height
                    radius: height / 2
                    color: root.foreground
                }
            }
            Text {
                textFormat: Text.PlainText
                text: root.goal.reached ? "Goal reached ✓ · " + Model.fmt(root.goal.goalMs) : Model.fmt(root.goal.remainingMs) + " left of " + Model.fmt(root.goal.goalMs)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
        }

        PanelRule {
            foreground: root.foreground
        }

        // ---- Donut and legend --------------------------------------------------
        Item {
            width: parent.width
            height: Math.max(donut.height, legend.implicitHeight)

            DonutChart {
                id: donut
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                slices: root.coloredSlices
                hovered: root.hoverIndex
                foreground: root.foreground
                fontFamily: root.fontFamily
                centerTitle: root.hoverIndex >= 0 && root.hoverIndex < root.slices.length ? root.slices[root.hoverIndex].name : Model.dayTitle(root.activeKey, root.todayKey)
                centerValue: root.hoverIndex >= 0 && root.hoverIndex < root.slices.length ? Model.fmt(root.slices[root.hoverIndex].ms) : Model.fmt(root.dayData.total)
                onHoverRequested: function (index) {
                    root.hoverIndex = index;
                }
            }

            Column {
                id: legend
                anchors.left: donut.right
                anchors.leftMargin: Style.space(16)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    visible: root.slices.length === 0
                    textFormat: Text.PlainText
                    text: "No activity"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                }

                Repeater {
                    model: root.slices

                    LegendRow {
                        required property var modelData
                        required property int index
                        dotColor: root.sliceColors[index] !== undefined ? root.sliceColors[index] : root.foreground
                        name: modelData.name
                        timeText: Model.fmt(modelData.ms)
                        percentText: Math.round(modelData.share * 100) + "%"
                        highlighted: root.hoverIndex === index
                        dimmed: root.hoverIndex >= 0 && root.hoverIndex !== index
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onHoverChanged: function (inside) {
                            if (inside)
                                root.hoverIndex = index;
                            else if (root.hoverIndex === index)
                                root.hoverIndex = -1;
                        }
                    }
                }
            }
        }

        // ---- Show more: every app, scrollable ------------------------------------
        Text {
            visible: root.hasOther
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: root.showMore ? "SHOW LESS" : "SHOW MORE"
            color: moreMouse.containsMouse ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            MouseArea {
                id: moreMouse
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showMore = !root.showMore
            }
        }

        Flickable {
            id: moreList
            visible: root.showMore && root.hasOther
            width: parent.width
            height: visible ? Math.min(moreColumn.implicitHeight, Style.space(190)) : 0
            contentWidth: width
            contentHeight: moreColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: moreColumn
                width: moreList.width

                Repeater {
                    model: root.moreRows

                    LegendRow {
                        required property var modelData
                        // Everything listed here is part of the donut's "Other" slice.
                        readonly property int sliceIndex: root.slices.length - 1
                        dotColor: root.sliceColors[sliceIndex] !== undefined ? root.sliceColors[sliceIndex] : root.foreground
                        name: modelData.name
                        timeText: Model.fmt(modelData.ms)
                        percentText: Math.round(modelData.share * 100) + "%"
                        highlighted: root.hoverIndex === sliceIndex
                        dimmed: root.hoverIndex >= 0 && root.hoverIndex !== sliceIndex
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        onHoverChanged: function (inside) {
                            if (inside)
                                root.hoverIndex = sliceIndex;
                            else if (root.hoverIndex === sliceIndex)
                                root.hoverIndex = -1;
                        }
                    }
                }
            }
        }

        PanelRule {
            foreground: root.foreground
        }

        // ---- Week trend --------------------------------------------------------
        WeekTrend {
            page: root.page
            selectedKey: root.activeKey
            showShare: root.showShare
            canOlder: root.back < root.lastBack
            canNewer: root.back > 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            onDaySelected: function (key) {
                root.selectDay(key);
            }
            onOlderRequested: root.pageBy(1)
            onNewerRequested: root.pageBy(-1)
            onShareToggled: root.showShare = !root.showShare
        }

        PanelRule {
            foreground: root.foreground
        }

        // ---- Insights ----------------------------------------------------------
        Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
                model: root.insights

                Item {
                    required property var modelData
                    width: parent.width
                    height: Style.space(22)

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: modelData.label
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: modelData.value
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                }
            }
        }
    }

    readonly property int dayAppCount: Object.keys(dayData.apps).length

    // A one-pixel divider tinted from the foreground, like the shell's own.
    component PanelRule: Rectangle {
        property color foreground: Color.foreground
        width: parent ? parent.width : 100
        height: 1
        color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    }
}
