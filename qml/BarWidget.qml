import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../js/Model.js" as Model

// Bar button showing today's total, and the host for the popup panel.
// Left click opens the panel; right click switches between "icon + time" and
// "icon only" (remembered in shell.json).
BarWidget {
    id: root
    moduleName: "rimuru.screentime"

    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    // Must match Service.qml's apiLevel. If it doesn't, the shell is still
    // running an older service than these files (see Service.qml).
    readonly property int requiredApiLevel: 4
    readonly property bool serviceStale: service !== null && service.apiLevel !== requiredApiLevel

    // Every read tolerates a service that predates the property.
    readonly property string timeLabel: service && service.label !== undefined ? service.label : ""
    readonly property bool hasActivity: service && service.hasActivity === true

    // Daily goal: a check mark joins the label once today reaches it.
    readonly property var goal: Model.goalProgress(service && service.todayTotal ? service.todayTotal : 0, service ? service.dailyGoalHours : 0)
    readonly property string label: goal.reached ? timeLabel + " ✓" : timeLabel
    readonly property string goalTooltip: {
        if (!goal.enabled)
            return "";
        if (goal.reached)
            return " · goal reached (" + Model.fmt(goal.goalMs) + ")";
        return " · " + Model.fmt(goal.remainingMs) + " left of " + Model.fmt(goal.goalMs);
    }

    // Nerd Font hourglass (U+F051F).
    readonly property string glyph: "󰔟"

    readonly property bool iconOnly: {
        var v = root.setting("iconOnly", false);
        return v === true || v === "true";
    }

    // Vertical bars are narrow: stack the glyph over each token of the label.
    readonly property var verticalLines: {
        if (!root.vertical)
            return [];
        var lines = [root.glyph];
        if (!root.iconOnly && root.label)
            lines = lines.concat(String(root.label).split(" ").filter(function (p) {
                return p !== "";
            }));
        return lines;
    }

    // Writes one key of this widget's entry in shell.json (which hot-reloads),
    // keeping every other key the entry already has.
    function setSetting(key, value) {
        var entry = {
            id: root.moduleName
        };
        for (var k in root.settings)
            if (k !== "id")
                entry[k] = root.settings[k];
        entry[key] = value;
        // Apply locally first so the bar reacts at once; the shell.json write
        // comes back through the bar as the same value.
        root.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
    }

    function toggleIconOnly() {
        root.setSetting("iconOnly", !root.iconOnly);
    }

    // The service lives apart from the widget, so hand it the settings.
    function pushSettings() {
        if (root.service && typeof root.service.applySettings === "function")
            root.service.applySettings(root.settings);
    }
    onServiceChanged: pushSettings()

    // ---- Panel contract used by the shell's summon/hide/toggle routing ------
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function open() {
        if (panelLoader.item)
            panelLoader.item.open();
    }
    function close() {
        if (panelLoader.item)
            panelLoader.item.close();
    }
    function togglePanel() {
        if (panelLoader.item)
            panelLoader.item.toggle();
    }
    function closeForPopoutSwitch() {
        if (panelLoader.item)
            panelLoader.item.closeForPopoutSwitch();
    }

    // Underline under the button while the panel is open.
    readonly property real openPanelIndicatorWidth: root.vertical ? Style.bar.iconSlot : Math.max(1, Math.round(button.labelWidth || iconGlyph.tightWidth))
    readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

    function injectPanel() {
        var target = panelLoader.item;
        if (!target)
            return;
        if ("bar" in target)
            target.bar = root.bar;
        if ("settings" in target)
            target.settings = root.settings;
        if ("anchorItem" in target)
            target.anchorItem = button;
        if ("hostWidget" in target)
            target.hostWidget = root;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: {
        injectPanel();
        pushSettings();
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    // `omarchy-shell rimuru.screentime <command>`. Handy for keybindings, and
    // the way to change settings until the settings menu exists.
    IpcHandler {
        target: "rimuru.screentime"
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function toggle(): void {
            root.togglePanel();
        }
        // `background off`, `background slime`, or `background /path/to/picture.png`.
        function background(what: string): void {
            var value = what.trim();
            var lower = value.toLowerCase();
            if (lower === "off" || lower === "slime") {
                root.setSetting("backgroundMode", lower);
            } else if (value !== "") {
                root.setSetting("backgroundImage", value);
                root.setSetting("backgroundMode", "image");
            }
        }
        function settings(): void {
            if (panelLoader.item)
                panelLoader.item.showSettings();
        }
        function year(): void {
            if (panelLoader.item)
                panelLoader.item.showYear();
        }
        function apps(): string {
            if (!root.service || typeof root.service.summary !== "function")
                return "service unavailable";
            return root.service.summary();
        }
        function goal(hours: int): void {
            root.setSetting("dailyGoalHours", Model.parseGoal(hours));
        }
        function ignore(app: string): void {
            var list = Model.parseList(root.setting("ignoredApps", []));
            var name = app.trim().toLowerCase();
            if (name !== "" && list.indexOf(name) === -1)
                root.setSetting("ignoredApps", list.concat([name]));
        }
        function unignore(app: string): void {
            var name = app.trim().toLowerCase();
            root.setSetting("ignoredApps", Model.parseList(root.setting("ignoredApps", [])).filter(function (a) {
                return a !== name;
            }));
        }
        function rename(app: string, name: string): void {
            var names = Model.parseNames(root.setting("appNames", {}));
            var key = app.trim().toLowerCase();
            if (key === "")
                return;
            if (name.trim() === "")
                delete names[key];
            else
                names[key] = name.trim().slice(0, 40);
            root.setSetting("appNames", names);
        }
        function status(): string {
            var s = root.service;
            var line = "opened=" + root.opened + " label=" + root.label + " service=" + (s ? "ok" : "missing");
            if (s)
                line += " api=" + s.apiLevel + "/" + root.requiredApiLevel + (root.serviceStale ? " STALE" : "") + " raw=" + s.rawApp + " app=" + s.focusedApp + " tracking=" + s.tracking + " locked=" + s.sessionLocked + " lockSource=" + (s.lockService ? "event" : "poll");
            console.log("screentime: " + line);
            return line;
        }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.vertical ? "" : root.iconOnly ? root.glyph : root.glyph + " " + root.label
        labelVisible: !root.vertical && !root.iconOnly
        hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
        fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
        horizontalMargin: 8.5
        tooltipText: (root.hasActivity ? "Screen time today · " + root.timeLabel : "Screen time · no activity yet") + root.goalTooltip + (root.serviceStale ? " · updated: restart the shell to finish" : "")
        onPressed: function (b) {
            if (b === Qt.RightButton)
                root.toggleIconOnly();
            else
                root.togglePanel();
        }

        // Centers the glyph's ink over the (hidden) label in icon-only mode.
        OpticalGlyph {
            id: iconGlyph
            visible: !root.vertical && root.iconOnly
            anchors.fill: parent
            text: root.glyph
            fontFamily: button.fontFamily
            fontSize: button.fontSize
            color: button.foreground
        }

        Column {
            visible: root.vertical
            anchors.fill: parent

            Repeater {
                model: root.verticalLines

                OpticalGlyph {
                    required property string modelData
                    width: button.width
                    height: Style.bar.iconSlot
                    text: modelData
                    fontFamily: button.fontFamily
                    fontSize: modelData === root.glyph ? Style.font.icon : (modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize)
                    color: button.foreground
                }
            }
        }
    }
}
