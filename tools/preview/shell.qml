import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import "plugin/qml"
import "plugin/qml/components"
import "plugin/js/Model.js" as Model

// Preview window for working on the popup without the real shell or your real
// history. It shows Dashboard with made-up data. Run it with tools/preview.sh.
//
// Choose what to show with environment variables:
//   SCEN     today | year | settings | past | more | hover | hints | empty | goal | ...
//   THEMES   comma-separated Omarchy theme folders to switch to, live
//   BGMODE   off | slime | image     BGPATH  picture path     BGSTRENGTH  1-3
//   SHIFT    pixels to scroll the content up, to see a tall view's lower part
ShellRoot {
    id: shell
    readonly property string scenario: Quickshell.env("SCEN") || "today"
    // Live theme switching, the way `omarchy theme set` does it inside the shell:
    // hand the new palette to the Color singleton and refresh Style.
    readonly property var themeList: (Quickshell.env("THEMES") || "").split(",").filter(function (x) { return x !== ""; })
    property int themeIndex: 0
    // Each file is applied only once it has actually loaded (reading text()
    // straight after changing the path returns the previous file's text).
    FileView {
        id: colorsFile
        printErrors: false
        onLoaded: {
            Color.loadColors(text());
            Style.scheduleRefresh();
            console.log("THEME colors@" + Date.now() + " " + path + " -> Color.foreground=" + Color.foreground + " background=" + Color.background);
        }
    }
    FileView {
        id: shellFile
        printErrors: false
        onLoaded: {
            Color.loadShell(text());
            Style.scheduleRefresh();
        }
        onLoadFailed: {
            Color.loadShell("");
            Style.scheduleRefresh();
        }
    }
    function applyTheme(dir) {
        shellFile.path = dir + "/shell.toml";
        colorsFile.path = dir + "/colors.toml";
    }
    Timer {
        interval: Number(Quickshell.env("THEME_STEP") || 4000)
        repeat: true
        running: shell.themeList.length > 0
        triggeredOnStart: true
        onTriggered: {
            if (shell.themeIndex < shell.themeList.length)
                shell.applyTheme(shell.themeList[shell.themeIndex++]);
        }
    }
    readonly property string todayKey: "2026-09-20"

    // Deterministic pseudo-random so screenshots are repeatable.
    function makeHistory(span) {
        var seed = 7;
        function rnd() {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            return seed / 0x7fffffff;
        }
        var days = {};
        var names = ["nvim", "claude", "brave", "terminal", "spotify", "Counter-Strike 2", "web:github.com", "imv", "nautilus", "about"];
        var weights = [0.30, 0.25, 0.20, 0.08, 0.06, 0.05, 0.03, 0.015, 0.01, 0.005];
        var today = Model.parseKey(todayKey);
        for (var i = 0; i < span; i++) {
            var d = Model.addDays(today, -i);
            var dow = (d.getDay() + 6) % 7;
            if (rnd() < 0.08 && i > 0)
                continue;
            var hours = (dow < 5 ? 3 + rnd() * 4 : 1 + rnd() * 3) * (i === 0 ? 0.6 : 1);
            var apps = {};
            var total = 0;
            for (var k = 0; k < names.length; k++) {
                var ms = Math.round(hours * 3600000 * weights[k] * (0.6 + rnd() * 0.8));
                if (ms > 0) {
                    apps[names[k]] = ms;
                    total += ms;
                }
            }
            days[Model.dayKey(d)] = { total: total, apps: apps };
        }
        // The real rollover, so the archive path is exercised too.
        return Model.rollArchive(days, {}, 365, today);
    }

    readonly property var hist: scenario === "empty" || scenario === "yearnone" ? ({ days: {}, archive: {} }) : (scenario === "yearnew" ? makeHistory(20) : makeHistory(1100))

    PanelWindow {
        anchors {
            top: true
            left: true
        }
        margins {
            top: 50
            left: 20
        }
        implicitWidth: 500
        implicitHeight: 1000
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "screentime-harness"
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Color.background
            border.width: 2
            border.color: Qt.darker(Color.foreground, 1.6)
        }

        BackgroundArt {
            id: art
            x: 20
            y: 20
            width: 460
            height: dash.implicitHeight
            mode: Model.parseBackgroundMode(Quickshell.env("BGMODE") || "off")
            imagePath: Model.cleanImagePath(Quickshell.env("BGPATH") || "", Quickshell.env("HOME"))
            strength: Model.backgroundOpacity(Quickshell.env("BGSTRENGTH") || 1)
            fit: Model.parseFit(Quickshell.env("BGFIT") || "fill")
            Component.onCompleted: console.log("BG status=" + status + " mode=" + mode + " path=" + imagePath)
            onStatusChanged: console.log("BG status=" + status)
        }

        Dashboard {
            id: dash
            x: 20
            y: 20 - Number(Quickshell.env("SHIFT") || 0)
            width: 460
            days: shell.hist.days
            archive: Quickshell.env("STALE") === "1" ? undefined : shell.hist.archive
            stale: Quickshell.env("STALE") === "1"
            todayKey: shell.todayKey
            dailyGoalHours: shell.scenario === "goal" || shell.scenario === "settings" ? 6 : 0
            foreground: Color.foreground
            ignoredApps: shell.scenario === "ignore" ? ["nvim"] : (shell.scenario === "settings" ? ["rofi", "wofi"] : [])
            backgroundMode: art.mode
            backgroundImage: Quickshell.env("BGPATH") || ""
            backgroundStrength: Number(Quickshell.env("BGSTRENGTH") || 1)
            backgroundFit: art.fit
            backgroundStatus: art.status
            showInsights: shell.scenario !== "noinsights"
            showYearLink: shell.scenario !== "noyear"
            iconOnly: shell.scenario === "settings"
            appNames: shell.scenario === "rename" || shell.scenario === "settings" ? ({ "brave": "Browser", "claude": "AI" }) : ({})

            Component.onCompleted: {
                var s = shell.scenario;
                if (s === "hover")
                    hoverIndex = 1;
                else if (s === "more")
                    showMore = true;
                else if (s === "morehover") {
                    showMore = true;
                    hoverIndex = 2;
                } else if (s === "past")
                    selectDay("2026-09-16");
                else if (s === "pageback") {
                    pageBy(3);
                    selectDay("2026-08-27");
                } else if (s === "share")
                    showShare = true;
                else if (s === "hints") {
                    selectDay("2026-09-16");
                    hints = true;
                } else if (s === "settings")
                    openSettings();
                else if (s === "record")
                    back = Model.weeksBack(today, Model.parseKey(recordKey));
                else if (s === "flip")
                    flips = 1;
                else if (s === "fire")
                    burst = true;
                else if (s === "year" || s === "yearnew" || s === "yearnone")
                    openYear();
                else if (s === "yearold") {
                    openYear();
                    stepYear(-1);
                } else if (s === "yearoldest") {
                    openYear();
                    stepYear(-10);
                } else if (s === "oldest") {
                    pageBy(1000);
                    stepDay(-1);
                }
            }
        }
    }
}
