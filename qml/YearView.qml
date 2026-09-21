import QtQuick
import qs.Commons
import "../js/Model.js" as Model
import "components"

// The yearly overview: the year's total, a bar per month, and a "Wrapped"-style
// set of highlights. `summary` comes from Model.yearSummary (null when the year
// has nothing in it). Paging between years and going back are signals; the
// Dashboard owns the state.
Item {
    id: root

    property var summary: null
    property int year: new Date().getFullYear()
    property int currentMonth: -1
    property bool canOlder: false
    property bool canNewer: false
    property bool hints: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal backRequested
    signal olderRequested
    signal newerRequested

    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property real cardWidth: (width - Style.space(8)) / 2

    function plural(n, word) {
        return n + " " + word + (n === 1 ? "" : "s");
    }

    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---- Header: back link and the year pager ------------------------------
        Item {
            width: parent.width
            height: Style.space(26)

            Text {
                id: backLink
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "‹ Back"
                color: backMouse.containsMouse ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.underline: backMouse.containsMouse
                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.backRequested()
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                PagerArrow {
                    glyph: "‹"
                    active: root.canOlder
                    hintKey: "["
                    hints: root.hints
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.olderRequested()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(54)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: root.year
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                }
                PagerArrow {
                    glyph: "›"
                    active: root.canNewer
                    hintKey: "]"
                    hints: root.hints
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.newerRequested()
                }
            }
        }

        // ---- Nothing recorded that year -------------------------------------------
        Text {
            visible: root.summary === null
            width: parent.width
            topPadding: Style.space(40)
            bottomPadding: Style.space(40)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "No activity recorded in " + root.year
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
        }

        // ---- The year --------------------------------------------------------------
        Column {
            visible: root.summary !== null
            width: parent.width
            spacing: Style.space(10)

            Column {
                spacing: Style.space(2)

                Text {
                    textFormat: Text.PlainText
                    text: root.summary ? Model.fmt(root.summary.total) : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 34
                    font.bold: true
                }
                Text {
                    textFormat: Text.PlainText
                    text: root.summary ? "In " + root.year + " · " + root.plural(root.summary.activeDays, "active day") : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                }
            }

            Rule {
                foreground: root.foreground
            }
            SectionLabel {
                text: "MONTHS"
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
            MonthBars {
                months: root.summary ? root.summary.months : []
                currentMonth: root.currentMonth
                foreground: root.foreground
                fontFamily: root.fontFamily
            }

            Rule {
                foreground: root.foreground
            }
            SectionLabel {
                text: "HIGHLIGHTS"
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
            Grid {
                width: parent.width
                columns: 2
                spacing: Style.space(8)

                StatCard {
                    width: root.cardWidth
                    label: "Days tracked"
                    value: root.summary ? root.summary.activeDays + " of " + root.summary.spanDays : ""
                    detail: root.summary ? Math.round(root.summary.activeDays / root.summary.spanDays * 100) + "% of days" : ""
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Average day"
                    value: root.summary ? Model.fmt(root.summary.averageDay) : ""
                    detail: "on days you used it"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Longest streak"
                    value: root.summary ? root.plural(root.summary.longestStreak.days, "day") : ""
                    detail: root.summary ? Model.rangeLabel(root.summary.longestStreak.from, root.summary.longestStreak.to) : ""
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Longest break"
                    value: root.summary && root.summary.longestBreak ? root.plural(root.summary.longestBreak.days, "day") : "—"
                    detail: root.summary && root.summary.longestBreak ? Model.rangeLabel(root.summary.longestBreak.from, root.summary.longestBreak.to) : "no days off"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Peak day"
                    value: root.summary ? Model.fmt(root.summary.peakDay.ms) : ""
                    detail: root.summary ? Model.dateTitle(root.summary.peakDay.key) : ""
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Busiest week"
                    value: root.summary && root.summary.busiestWeek ? Model.fmt(root.summary.busiestWeek.ms) : "—"
                    detail: root.summary && root.summary.busiestWeek ? root.summary.busiestWeek.label : "needs two weeks of data"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Top months"
                    value: root.summary ? root.summary.topMonths.map(function (m) {
                        return m.label;
                    }).join(" \u2022 ") : ""
                    detail: root.summary ? root.summary.topMonths.map(function (m) {
                        return Model.fmt(m.ms);
                    }).join(" \u00b7 ") : ""
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
                StatCard {
                    width: root.cardWidth
                    label: "Recharge month"
                    value: root.summary && root.summary.rechargeMonth ? root.summary.rechargeMonth.label : "\u2014"
                    detail: root.summary && root.summary.rechargeMonth ? "lightest, " + Model.fmt(root.summary.rechargeMonth.ms) : "needs two months of data"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }
            }
            Rule {
                foreground: root.foreground
            }
            SectionLabel {
                text: "WEEKDAY RHYTHM"
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
            WeekdayRhythm {
                weekdays: root.summary ? root.summary.weekdays : []
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
        }
    }
}
