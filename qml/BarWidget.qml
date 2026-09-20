import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button showing today's total, and the host for the popup panel.
// Left click opens the panel; right click switches between "icon + time" and
// "icon only" (remembered in shell.json).
BarWidget {
    id: root
    moduleName: "rimuru.screentime"

    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    readonly property string label: service ? service.label : ""
    readonly property bool hasActivity: service ? service.hasActivity : false

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

    function toggleIconOnly() {
        var entry = {
            id: root.moduleName
        };
        for (var key in root.settings)
            if (key !== "id")
                entry[key] = root.settings[key];
        entry.iconOnly = !root.iconOnly;
        // Apply locally first so the bar reacts on the click itself; the
        // shell.json write comes back through the bar as the same value.
        root.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
    }

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
    onSettingsChanged: injectPanel()

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

    // `omarchy-shell rimuru.screentime toggle` etc., handy for keybindings.
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
        function status(): void {
            var s = root.service;
            console.log("screentime: opened=" + root.opened + " label=" + root.label + " service=" + (s ? "ok" : "missing") + (s ? " app=" + s.focusedApp + " tracking=" + s.tracking + " locked=" + s.sessionLocked + " lockSource=" + (s.lockService ? "event" : "poll") : ""));
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
        tooltipText: root.hasActivity ? "Screen time today · " + root.label : "Screen time · no activity yet"
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
