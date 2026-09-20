import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../js/Model.js" as Model

// Tracks which app has focus and adds the elapsed time to today's bucket.
// Headless: the bar widget reads `today`, `days` and `label` from here.
//
// Time is attributed once per second to whichever window is focused at that
// tick. Nothing is counted while the session is locked, while the screensaver
// or a desktop portal has focus, when no window has focus, for ignored apps,
// or across a suspend (a gap longer than maxGapMs is treated as the machine
// being asleep, not as usage). A tick that spans midnight is split between
// the two days.
//
// Terminal windows and Steam games are looked up by python/resolve_app.py so
// the time is filed under the command running in the terminal ("nvim") or the
// game's title, not "ghostty" or "steam_app_730".
Item {
    id: root

    // Injected by omarchy-shell.
    property var shell: null

    readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-screentime"
    readonly property string historyPath: dataDir + "/history.json"
    readonly property string resolverPath: {
        var u = Qt.resolvedUrl("../python/resolve_app.py").toString();
        return u.startsWith("file://") ? u.slice(7) : u;
    }

    readonly property int tickMs: 1000
    readonly property int maxGapMs: 5000
    readonly property int saveEveryMs: 60000
    readonly property int resolveEveryMs: 3000

    // ---- Settings, pushed in by the bar widget from its shell.json entry ------
    property var ignoredApps: []
    property var appNames: ({})
    property int dailyGoalHours: 0
    property string settingsKey: ""

    function applySettings(s) {
        var src = s && typeof s === "object" ? s : {};
        var ignored = Model.parseList(src.ignoredApps);
        var names = Model.parseNames(src.appNames);
        var goal = Model.parseGoal(src.dailyGoalHours);
        // The widget re-sends settings on every change to its entry; skip no-ops.
        var key = JSON.stringify([ignored, names, goal]);
        if (key === settingsKey)
            return;
        settingsKey = key;
        ignoredApps = ignored;
        appNames = names;
        dailyGoalHours = goal;
    }

    // ---- Data ------------------------------------------------------------------

    // Always replaced, never mutated in place, so bindings re-evaluate.
    property var days: ({})
    property string todayKey: Model.dayKey(new Date())
    readonly property var today: days[todayKey] || Model.newDay()
    // Today without ignored apps: this is what every display shows.
    readonly property var visibleToday: Model.visibleDay(today, ignoredApps, appNames)
    readonly property double todayTotal: visibleToday.total
    readonly property string label: Model.fmt(todayTotal)
    readonly property bool hasActivity: todayTotal > 0

    property bool ready: false
    property bool dirty: false
    property double lastTick: 0

    property bool sessionLocked: false
    readonly property var lockService: shell ? shell.serviceFor("omarchy.lock") : null

    // ---- What has focus ----------------------------------------------------------

    readonly property var activeWindow: ToplevelManager.activeToplevel
    // The compositor's class for the focused window, e.g. "brave-browser".
    readonly property string rawApp: activeWindow && activeWindow.appId ? String(activeWindow.appId) : ""
    readonly property string focusedTitle: activeWindow && activeWindow.title ? String(activeWindow.title) : ""
    // What the resolver found for the focused terminal or game ("" = nothing).
    property string resolvedName: ""
    // True from focusing a terminal/game until the resolver answers, so the
    // first moments aren't filed under the wrong name.
    property bool resolvePending: false
    property string resolveFor: ""
    property bool resolveQueued: false

    readonly property bool isTerminal: Model.isTerminalClass(rawApp)
    readonly property bool needsResolve: isTerminal || Model.isSteamClass(rawApp)

    // The key today's time is filed under.
    readonly property string focusedApp: Model.canonicalApp(rawApp, resolvedName)
    readonly property bool tracking: ready && !sessionLocked && rawApp !== "" && !resolvePending && !Model.isSystemWindow(rawApp) && !Model.isIgnored(ignoredApps, appNames, focusedApp, rawApp)

    onRawAppChanged: {
        resolvedName = "";
        if (needsResolve) {
            resolvePending = true;
            resolveWatchdog.restart();
            requestResolve();
        } else {
            resolvePending = false;
            resolveWatchdog.stop();
        }
    }
    // A terminal's title follows the command running in it, and differs
    // between windows, so a change is a good moment to look again.
    onFocusedTitleChanged: {
        if (ready && needsResolve)
            titleDebounce.restart();
    }

    function requestResolve() {
        if (!needsResolve)
            return;
        if (resolver.running) {
            resolveQueued = true;
            return;
        }
        resolveFor = rawApp;
        resolver.running = true;
    }

    function finishResolve(output) {
        // An answer for a window that has since lost focus is stale.
        if (resolveFor !== rawApp)
            return;
        resolvedName = String(output).trim();
        resolvePending = false;
        resolveWatchdog.stop();
    }

    Process {
        id: resolver
        command: ["python3", root.resolverPath]
        stdout: StdioCollector {
            onStreamFinished: root.finishResolve(text)
        }
        onExited: function (exitCode, exitStatus) {
            // No python, or the script died: fall back to the window class.
            if (exitCode !== 0 && root.resolveFor === root.rawApp)
                root.resolvePending = false;
            if (root.resolveQueued) {
                root.resolveQueued = false;
                root.requestResolve();
            }
        }
    }

    // Never leave accrual paused if the resolver hangs.
    Timer {
        id: resolveWatchdog
        interval: 2500
        onTriggered: root.resolvePending = false
    }
    Timer {
        id: titleDebounce
        interval: 300
        onTriggered: root.requestResolve()
    }
    // What runs in a terminal changes without the window changing.
    Timer {
        interval: root.resolveEveryMs
        repeat: true
        running: root.ready && root.isTerminal
        onTriggered: root.requestResolve()
    }

    // ---- Accrual ---------------------------------------------------------------

    function tick() {
        var now = Date.now();
        var from = lastTick;
        var delta = now - from;
        lastTick = now;

        var key = Model.dayKey(new Date(now));
        if (key !== todayKey) {
            todayKey = key;
            days = Model.pruneDays(days, Model.KEEP_DAYS, new Date(now));
            dirty = true;
        }

        if (!tracking || delta <= 0 || delta > maxGapMs)
            return;
        var app = focusedApp;
        var next = days;
        var parts = Model.splitByDay(from, now);
        for (var i = 0; i < parts.length; i++)
            next = Model.addTime(next, parts[i].key, app, parts[i].ms);
        days = next;
        dirty = true;
    }

    function save() {
        if (!ready || !dirty)
            return;
        dirty = false;
        historyFile.setText(Model.serialize(days));
    }

    // One line per app today, for `omarchy-shell rimuru.screentime apps`.
    function summary() {
        var rows = Model.topApps(visibleToday, 1000, appNames);
        var out = [];
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            out.push(r.name + "  " + Model.fmt(r.ms));
        }
        return out.length > 0 ? out.join("\n") : "No activity yet";
    }

    // ---- Storage ---------------------------------------------------------------

    // FileView won't create the directory, so make sure it exists first. The
    // path is passed as an argument (no shell), so it can't be misparsed.
    Process {
        id: ensureDir
        command: ["mkdir", "-p", root.dataDir]
        onExited: historyFile.path = root.historyPath
    }

    // Keep an unreadable history instead of overwriting it with an empty one.
    Process {
        id: keepCorrupt
        onExited: root.start()
    }

    FileView {
        id: historyFile
        printErrors: false
        atomicWrites: true
        onLoaded: {
            var parsed = Model.parseHistory(text());
            if (parsed.ok) {
                root.days = Model.normalizeKeys(Model.pruneDays(parsed.days, Model.KEEP_DAYS, new Date()));
                root.dirty = true;
                root.start();
            } else {
                console.warn("screentime: " + root.historyPath + " is unreadable, keeping a copy and starting fresh");
                keepCorrupt.command = ["cp", "-f", root.historyPath, root.historyPath + ".corrupt-" + Date.now()];
                keepCorrupt.running = true;
            }
        }
        // First run: no file yet.
        onLoadFailed: root.start()
        onSaveFailed: {
            console.warn("screentime: could not save history, will retry");
            root.dirty = true;
        }
    }

    function start() {
        if (ready)
            return;
        lastTick = Date.now();
        todayKey = Model.dayKey(new Date());
        ready = true;
        // Something may already have focus; the change handler only sees changes.
        if (needsResolve) {
            resolvePending = true;
            resolveWatchdog.restart();
            requestResolve();
        }
    }

    Timer {
        interval: root.tickMs
        repeat: true
        running: root.ready
        onTriggered: root.tick()
    }

    Timer {
        interval: root.saveEveryMs
        repeat: true
        running: root.ready
        onTriggered: root.save()
    }

    Component.onCompleted: ensureDir.running = true
    Component.onDestruction: root.save()

    // ---- Lock state --------------------------------------------------------
    // Preferred: the shell's lock service reports changes as they happen.
    // Some plugin sandboxes can't reach it, so fall back to asking every 10s.

    onLockServiceChanged: syncLock()
    Connections {
        target: root.lockService
        ignoreUnknownSignals: true
        function onLockedChanged() {
            root.syncLock();
        }
    }
    function syncLock() {
        if (root.lockService)
            root.sessionLocked = root.lockService.locked === true;
    }

    Process {
        id: lockProbe
        command: ["omarchy-shell", "lock", "isLocked"]
        stdout: StdioCollector {
            onStreamFinished: root.sessionLocked = text.trim() === "true"
        }
    }
    Timer {
        interval: 10000
        repeat: true
        running: root.ready && !root.lockService
        onTriggered: if (!lockProbe.running) lockProbe.running = true
    }
}
