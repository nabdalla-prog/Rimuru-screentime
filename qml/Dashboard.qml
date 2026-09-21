import QtQuick
import qs.Commons
import "../js/Model.js" as Model
import "components"

// Everything inside the popup: the day's total, a donut of its apps with a
// legend, a week-by-week trend, and a few insights, or the yearly overview
// behind the "Year" link. It knows nothing about the shell (Panel.qml wraps
// it), so it can be shown with any data.
//
// Clicking a bar in the trend inspects that day; clicking it again, or the
// "Today" link, comes back. Which day, week and year are on screen is state
// kept here and cleared by reset().
Item {
    id: root

    // ---- Inputs ------------------------------------------------------------
    property var days: ({})
    // Totals of days older than the detailed window, for the yearly view.
    property var archive: ({})
    property string todayKey: Model.dayKey(new Date())
    property var ignoredApps: []
    property var appNames: ({})
    property int dailyGoalHours: 0
    // Off while the popup is closed, so nothing is recomputed each second.
    property bool active: true
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    // Preferences the settings menu changes (the owner stores them).
    property bool iconOnly: false
    property bool showInsights: true
    property bool showYearLink: true
    property bool playful: true
    property string backgroundMode: "slime"
    property string backgroundImage: ""
    property int backgroundStrength: 1
    property string backgroundFit: "fill"
    property string backgroundStatus: "ok"
    property int weekCap: 52
    property color danger: Color.urgent
    // The shell is still running an older service than these files.
    property bool stale: false

    // A preference was changed in the settings menu.
    signal settingChanged(string key, var value)
    signal resetTodayRequested
    signal wipeAllRequested

    // ---- State -------------------------------------------------------------
    property string selectedKey: ""   // "" means today
    property int back: 0              // weeks before the current one
    property bool showMore: false
    property bool showShare: false
    property int hoverIndex: -1
    // Key hints ("f"): small key caps naming each control's shortcut.
    property bool hints: false
    property string view: "day"       // "day", "year" or "settings"
    property int yearShown: 0         // 0 means the current year

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
    // Never further back than the graph reach allows, even if it was shortened
    // while paged out.
    readonly property int shownBack: Math.min(back, lastBack)
    readonly property var page: active ? Model.weekPage(days, today, shownBack, ignoredApps, appNames) : ({ label: "", total: 0, share: 0, days: [] })
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

    // ---- Yearly view -------------------------------------------------------
    readonly property var totals: active ? Model.dayTotals(days, archive, ignoredApps, appNames) : ({})
    readonly property string recordKey: {
        var r = Model.recordWeek(totals, todayKey);
        return r ? r.key : "";
    }
    // Nothing has ever been recorded: show a short hint instead of a blank day.
    readonly property bool fresh: Object.keys(days || {}).length === 0 && Object.keys(archive || {}).length === 0
    // Today's apps (minus ignored ones), offered as tap-to-ignore suggestions.
    readonly property var todayApps: view === "settings" ? Model.topApps(Model.visibleDay(days[todayKey] || Model.newDay(), ignoredApps, appNames), 12, appNames).filter(function (r) {
        return !r.other;
    }).map(function (r) {
        return r.name;
    }) : []
    readonly property string storageText: view === "settings" ? Model.storageSummary(days, archive) : ""
    // True while a settings text field has focus; the popup then stops treating
    // typing as shortcuts.
    readonly property bool editing: view === "settings" && settingsView.editing
    // The hourglass turns over once per hour (see the timer at the bottom).
    property int flips: 0
    readonly property var yearList: Model.yearsRange(totals, todayKey)
    readonly property int currentYear: today.getFullYear()
    readonly property int year: yearShown > 0 ? yearShown : currentYear
    readonly property var summary: view === "year" ? Model.yearSummary(totals, year, todayKey) : null

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
        hints = false;
        selectedKey = "";
        back = 0;
        showMore = false;
        hoverIndex = -1;
        settingsView.releaseFocus();
        view = "day";
        yearShown = 0;
    }

    function openYear() {
        if (!showYearLink)
            return;
        yearShown = 0;
        view = "year";
    }

    function closeYear() {
        view = "day";
    }

    function openSettings() {
        view = "settings";
    }

    // Backs out of the yearly overview or the settings menu. Returns false when
    // already on the day view, so the caller can close the popup instead.
    function leaveView() {
        if (view === "day")
            return false;
        settingsView.releaseFocus();
        view = "day";
        return true;
    }

    // Older/newer year, kept between the first recorded year and this one.
    function stepYear(delta) {
        var oldest = yearList.length > 0 ? yearList[0] : currentYear;
        yearShown = Math.max(oldest, Math.min(currentYear, year + delta));
    }

    function selectDay(key) {
        // Clicking the day already on screen goes back to today.
        selectedKey = (key === activeKey || key === todayKey) ? "" : key;
    }

    function pageBy(delta) {
        back = Math.max(0, Math.min(lastBack, back + delta));
    }

    // Keys 1-7: inspect Monday to Sunday of the week on screen.
    function selectDayNumber(n) {
        var d = page.days[n - 1];
        if (view === "day" && d && !d.future)
            selectDay(d.key);
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
    implicitHeight: view === "year" ? yearView.implicitHeight : (view === "settings" ? settingsView.implicitHeight : column.implicitHeight)

    SettingsView {
        id: settingsView
        width: parent.width
        visible: root.view === "settings"
        iconOnly: root.iconOnly
        showInsights: root.showInsights
        showYearLink: root.showYearLink
        playful: root.playful
        backgroundMode: root.backgroundMode
        backgroundImage: root.backgroundImage
        backgroundStrength: root.backgroundStrength
        backgroundFit: root.backgroundFit
        backgroundStatus: root.backgroundStatus
        weekCap: root.weekCap
        dailyGoalHours: root.dailyGoalHours
        ignoredApps: root.ignoredApps
        appNames: root.appNames
        todayApps: root.todayApps
        storageText: root.storageText
        danger: root.danger
        foreground: root.foreground
        fontFamily: root.fontFamily
        onSettingChanged: function (key, value) {
            root.settingChanged(key, value);
        }
        onResetTodayRequested: root.resetTodayRequested()
        onWipeAllRequested: root.wipeAllRequested()
        onBackRequested: root.leaveView()
    }

    YearView {
        id: yearView
        width: parent.width
        visible: root.view === "year"
        summary: root.summary
        year: root.year
        currentMonth: root.year === root.currentYear ? root.today.getMonth() : -1
        canOlder: root.yearList.length > 0 && root.year > root.yearList[0]
        canNewer: root.year < root.currentYear
        hints: root.hints
        foreground: root.foreground
        fontFamily: root.fontFamily
        onBackRequested: root.closeYear()
        onOlderRequested: root.stepYear(-1)
        onNewerRequested: root.stepYear(1)
    }

    Column {
        id: column
        visible: root.view === "day"
        width: parent.width
        spacing: Style.space(10)

        // ---- Update notice: the running service is older than these files --------
        Rectangle {
            visible: root.stale
            width: parent.width
            height: staleText.implicitHeight + Style.space(16)
            radius: Style.space(8)
            color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.16)
            border.width: 1
            border.color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.55)

            Text {
                id: staleText
                anchors.fill: parent
                anchors.margins: Style.space(8)
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: "Screen Time was updated. To finish, restart the shell: omarchy restart shell"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
        }

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
                    rotation: root.flips * 180
                    Behavior on rotation {
                        NumberAnimation {
                            duration: 700
                            easing.type: Easing.OutBack
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.showYearLink
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openYear()
                    }
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
            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Row {
                    anchors.right: parent.right
                    spacing: Style.space(12)

                    Text {
                        visible: root.showYearLink
                        textFormat: Text.PlainText
                        text: "Year \u203A"
                        color: yearMouse.containsMouse ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.underline: yearMouse.containsMouse
                        KeyBadge {
                            anchors.right: parent.left
                            anchors.rightMargin: Style.space(4)
                            anchors.verticalCenter: parent.verticalCenter
                            key: "y"
                            show: root.hints
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }
                        MouseArea {
                            id: yearMouse
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openYear()
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: "\uF013"
                        color: gearMouse.containsMouse ? root.foreground : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        KeyBadge {
                            anchors.right: parent.left
                            anchors.rightMargin: Style.space(4)
                            anchors.verticalCenter: parent.verticalCenter
                            key: "c"
                            show: root.hints
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }
                        MouseArea {
                            id: gearMouse
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSettings()
                        }
                    }
                }
                Text {
                    visible: !root.viewingToday
                    anchors.right: parent.right
                    textFormat: Text.PlainText
                    text: "Back to today"
                    color: todayMouse.containsMouse ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: todayMouse.containsMouse
                    KeyBadge {
                        anchors.right: parent.left
                        anchors.rightMargin: Style.space(4)
                        anchors.verticalCenter: parent.verticalCenter
                        key: "t"
                        show: root.hints
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }
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
        }

        Text {
            visible: root.fresh
            width: parent.width
            textFormat: Text.PlainText
            text: "Nothing tracked yet. Time is counted while a window has focus."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

        Rule {
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
            KeyBadge {
                anchors.right: parent.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                key: "m"
                show: root.hints
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
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

        Rule {
            foreground: root.foreground
        }

        // ---- Week trend --------------------------------------------------------
        WeekTrend {
            page: root.page
            selectedKey: root.activeKey
            showShare: root.showShare
            record: root.recordKey !== "" && root.page.key === root.recordKey
            canOlder: root.shownBack < root.lastBack
            canNewer: root.shownBack > 0
            hints: root.hints
            foreground: root.foreground
            fontFamily: root.fontFamily
            onDaySelected: function (key) {
                root.selectDay(key);
            }
            onOlderRequested: root.pageBy(1)
            onNewerRequested: root.pageBy(-1)
            onShareToggled: root.showShare = !root.showShare
        }

        Rule {
            visible: root.showInsights
            foreground: root.foreground
        }

        // ---- Insights ----------------------------------------------------------
        Column {
            visible: root.showInsights
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

    // Turns the hourglass over when the hour changes.
    property int lastHour: new Date().getHours()
    Timer {
        interval: 30000
        repeat: true
        running: root.playful
        onTriggered: {
            var hour = new Date().getHours();
            if (hour !== root.lastHour) {
                root.lastHour = hour;
                root.flips++;
            }
        }
    }
}
