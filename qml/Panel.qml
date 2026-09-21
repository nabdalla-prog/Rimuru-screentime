import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model
import "components"

// Popup opened from the bar button. BarWidget.qml owns the button and injects
// `bar`, `anchorItem` and `hostWidget`; the content is Dashboard.qml, fed from
// the Service through the widget.
Panel {
    id: root
    moduleName: "rimuru.screentime"
    ipcTarget: "rimuru.screentime"
    manageIpc: false

    property var anchorItem: null

    // The bar tracks the widget mounted in its slot (BarWidget.qml), not this
    // nested panel, so that is what it must be handed as the popout identity.
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    readonly property var service: hostWidget ? hostWidget.service : null
    // The running service is older than these files: ask for a restart.
    readonly property bool serviceStale: hostWidget ? hostWidget.needsRestart === true : false

    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

    function open() {
        root.controller.show();
    }
    function close() {
        root.controller.hide();
    }
    // Open the popup straight on the settings menu.
    function showSettings() {
        dashboard.openSettings();
        root.open();
    }
    // Open the popup straight on the yearly overview.
    function showYear() {
        dashboard.openYear();
        root.open();
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

    // Up/Down scroll the popup when it is taller than the screen.
    function scrollBy(pixels) {
        var most = Math.max(0, scroll.contentHeight - scroll.height);
        scroll.contentY = Math.max(0, Math.min(most, scroll.contentY + pixels));
    }

    // Each opening starts on today, on the current week.
    onOpenedChanged: {
        if (!opened)
            dashboard.reset();
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(460))
        contentHeight: panel.fittedContentHeight(dashboard.implicitHeight)

        // Left/Right move the selected day, Up/Down scroll, [ and ] page
        // through weeks, T returns to today, M shows every app, S flips the
        // week total between time and share of the week, Y opens the yearly
        // view (where Left/Right and [ ] change the year), C opens settings,
        // 1-7 inspect a day of the week, F shows the keys as small caps.
        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // While a settings field is being typed in, keys belong to it.
            blocked: dashboard.editing
            // Esc backs out of the yearly view or settings first, then closes.
            onCloseRequested: {
                if (!dashboard.leaveView())
                    root.close();
            }
            onMoveRequested: function (dx, dy) {
                dashboard.hints = false;
                if (dx !== 0 && dashboard.view === "year")
                    dashboard.stepYear(dx);
                else if (dx !== 0)
                    dashboard.stepDay(dx);
                if (dy !== 0)
                    root.scrollBy(dy * Style.space(60));
            }
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (t) {
                // "f" shows the key caps; any other key hides them again.
                dashboard.hints = (t === "f" || t === "F") ? !dashboard.hints : false;
                if (t >= "1" && t <= "7")
                    dashboard.selectDayNumber(Number(t));
                else if (t === "c" || t === "C")
                    dashboard.openSettings();
                else if (t === "y" || t === "Y")
                    dashboard.view === "year" ? dashboard.closeYear() : dashboard.openYear();
                else if (t === "[")
                    dashboard.view === "year" ? dashboard.stepYear(-1) : dashboard.pageBy(1);
                else if (t === "]")
                    dashboard.view === "year" ? dashboard.stepYear(1) : dashboard.pageBy(-1);
                else if (t === "t" || t === "T")
                    dashboard.reset();
                else if (t === "m" || t === "M")
                    dashboard.showMore = !dashboard.showMore;
                else if (t === "s" || t === "S")
                    dashboard.showShare = !dashboard.showShare;
            }

            // A faint picture behind everything. It never takes input.
            BackgroundArt {
                id: art
                anchors.fill: parent
                mode: Model.parseBackgroundMode(root.setting("backgroundMode", "slime"))
                imagePath: Model.cleanImagePath(root.setting("backgroundImage", ""), Quickshell.env("HOME"))
                fit: Model.parseFit(root.setting("backgroundFit", "fill"))
                strength: Model.backgroundOpacity(root.setting("backgroundStrength", 1))
            }

            Flickable {
                id: scroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: dashboard.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Dashboard {
                    id: dashboard
                    width: scroll.width
                    active: root.opened
                    // An older service may lack newer properties, so each falls
                    // back to a default instead of passing undefined on.
                    days: root.service && root.service.days ? root.service.days : ({})
                    archive: root.service && root.service.archive ? root.service.archive : ({})
                    todayKey: root.service && root.service.todayKey ? root.service.todayKey : Model.dayKey(new Date())
                    ignoredApps: root.service && root.service.ignoredApps ? root.service.ignoredApps : []
                    appNames: root.service && root.service.appNames ? root.service.appNames : ({})
                    dailyGoalHours: root.service && root.service.dailyGoalHours ? root.service.dailyGoalHours : 0
                    stale: root.serviceStale
                    iconOnly: Model.parseBool(root.setting("iconOnly", false), false)
                    showInsights: Model.parseBool(root.setting("showInsights", true), true)
                    showYearLink: Model.parseBool(root.setting("showYearLink", true), true)
                    playful: Model.parseBool(root.setting("playful", true), true)
                    backgroundMode: art.mode
                    backgroundImage: String(root.setting("backgroundImage", ""))
                    backgroundStrength: Model.parseStrength(root.setting("backgroundStrength", 1))
                    backgroundFit: art.fit
                    backgroundStatus: art.status
                    weekCap: Model.parseWeeks(root.setting("weeks", 52))
                    danger: root.bar ? root.bar.urgent : Color.urgent
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily

                    // Preferences live in this widget's entry in shell.json.
                    onSettingChanged: function (key, value) {
                        if (root.hostWidget)
                            root.hostWidget.setSetting(key, value);
                    }
                    onResetTodayRequested: {
                        if (root.service && typeof root.service.resetToday === "function")
                            root.service.resetToday();
                    }
                    onWipeAllRequested: {
                        if (root.service && typeof root.service.resetAll === "function")
                            root.service.resetAll();
                    }
                    // Typing ended: give the keys back to the popup.
                    onEditingChanged: {
                        if (!editing)
                            keyCatcher.forceActiveFocus();
                    }
                }
            }
        }
    }
}
