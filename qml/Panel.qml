import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

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

    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

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
        // week total between time and share of the week.
        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onMoveRequested: function (dx, dy) {
                if (dx !== 0)
                    dashboard.stepDay(dx);
                if (dy !== 0)
                    root.scrollBy(dy * Style.space(60));
            }
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (t) {
                if (t === "[")
                    dashboard.pageBy(1);
                else if (t === "]")
                    dashboard.pageBy(-1);
                else if (t === "t" || t === "T")
                    dashboard.reset();
                else if (t === "m" || t === "M")
                    dashboard.showMore = !dashboard.showMore;
                else if (t === "s" || t === "S")
                    dashboard.showShare = !dashboard.showShare;
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
                    days: root.service ? root.service.days : ({})
                    todayKey: root.service ? root.service.todayKey : Model.dayKey(new Date())
                    ignoredApps: root.service ? root.service.ignoredApps : []
                    appNames: root.service ? root.service.appNames : ({})
                    dailyGoalHours: root.service ? root.service.dailyGoalHours : 0
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                }
            }
        }
    }
}
