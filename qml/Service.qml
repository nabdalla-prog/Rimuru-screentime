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
// after a few minutes without keyboard or mouse input (see "Idle" below),
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

    // What this service offers the widget and popup. BarWidget.qml holds the
    // level it expects; when they differ (an update replaced the widget but the
    // running service, which the shell keeps loaded, is still the old one) the
    // UI tells the user to restart the shell. Bump it in both files whenever
    // what the UI reads from or calls on the service changes.
    readonly property int apiLevel: 7

    // ---- Update notice -----------------------------------------------------
    // The shell keeps this plugin loaded, so after an update (new files on disk)
    // it keeps running the old code until the shell restarts. This service
    // watches its own manifest and reports when the version on disk differs from
    // the one running, so the bar and popup can ask for a restart.
    readonly property string manifestPath: {
        var u = Qt.resolvedUrl("../manifest.json").toString();
        return u.startsWith("file://") ? u.slice(7) : u;
    }
    property string diskVersion: ""
    readonly property bool updatePending: diskVersion !== "" && diskVersion !== Model.VERSION

    FileView {
        id: manifestFile
        path: root.manifestPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.diskVersion = String(JSON.parse(text()).version || "");
            } catch (e) {
                root.diskVersion = "";
            }
        }
    }

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
    property int idleMinutes: Model.IDLE_DEFAULT
    property var appLimits: ({})
    property int breakMinutes: 0
    property bool trackProjects: true
    property string settingsKey: ""

    function applySettings(s) {
        var src = s && typeof s === "object" ? s : {};
        var ignored = Model.parseList(src.ignoredApps);
        var names = Model.parseNames(src.appNames);
        var goal = Model.parseGoal(src.dailyGoalHours);
        var idle = Model.parseIdle(src.idleMinutes);
        var limits = Model.parseLimits(src.appLimits);
        var breakMin = Model.parseBreak(src.breakMinutes);
        var projects = Model.parseBool(src.trackProjects, true);
        // The widget re-sends settings on every change to its entry; skip no-ops.
        var key = JSON.stringify([ignored, names, goal, idle, limits, breakMin, projects]);
        if (key === settingsKey)
            return;
        settingsKey = key;
        ignoredApps = ignored;
        appNames = names;
        dailyGoalHours = goal;
        idleMinutes = idle;
        appLimits = limits;
        trackProjects = projects;
        if (breakMin !== breakMinutes) {
            breakMinutes = breakMin;
            // A new interval starts counting from the current streak, without
            // reminding at once for time already past it.
            if (breakMin > 0)
                breaks = {
                    "streakMs": breaks.streakMs,
                    "pausedAt": breaks.pausedAt,
                    "reminded": Math.floor(breaks.streakMs / (breakMin * 60000))
                };
        }
    }

    // ---- Data ------------------------------------------------------------------

    // Always replaced, never mutated in place, so bindings re-evaluate.
    property var days: ({})
    // Totals of days older than KEEP_DAYS, kept forever: { "YYYY-MM-DD": ms }.
    property var archive: ({})
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
    // The project folder the terminal's command works in ("" = none).
    property string resolvedProject: ""
    // True from focusing a terminal/game until the resolver answers, so the
    // first moments aren't filed under the wrong name.
    property bool resolvePending: false
    property string resolveFor: ""
    property bool resolveQueued: false

    readonly property bool isTerminal: Model.isTerminalClass(rawApp)
    readonly property bool needsResolve: isTerminal || Model.isSteamClass(rawApp)

    // The key today's time is filed under.
    readonly property string focusedApp: Model.canonicalApp(rawApp, resolvedName)
    readonly property bool tracking: ready && !sessionLocked && !userIdle && rawApp !== "" && !resolvePending && !Model.isSystemWindow(rawApp) && !Model.isIgnored(ignoredApps, appNames, focusedApp, rawApp)

    onRawAppChanged: {
        resolvedName = "";
        resolvedProject = "";
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
        var lines = String(output).trim().split("\n");
        resolvedName = (lines[0] || "").trim();
        resolvedProject = isTerminal ? (lines[1] || "").trim() : "";
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
            rollHistory(new Date(now));
            dirty = true;
        }

        if (!tracking || delta <= 0 || delta > maxGapMs) {
            // Asleep since the last tick, or simply not counting: a break
            // starts (the earliest moment is kept).
            if (ready)
                breaks = Model.breakPause(breaks, delta > maxGapMs ? from : now);
            return;
        }
        var app = focusedApp;
        var project = trackProjects && isTerminal ? resolvedProject : "";
        var next = days;
        var log = recent;
        var at = from;
        var parts = Model.splitByDay(from, now);
        for (var i = 0; i < parts.length; i++) {
            next = Model.addTime(next, parts[i].key, app, parts[i].ms, project);
            log = Model.logRecent(log, parts[i].key, app, at, at + parts[i].ms, idleMs, project);
            at += parts[i].ms;
        }
        days = next;
        recent = log;
        dirty = true;

        var b = Model.breakAdvance(breaks, now, delta, breakMinutes);
        breaks = b.state;
        if (b.remind)
            Quickshell.execDetached(["notify-send", "--app-name=Screen Time", "--icon=preferences-desktop-screensaver", "Time for a short break", "You've been at the screen for " + Model.fmt(b.state.streakMs) + ". Look at something far away for 20 seconds, or stand up and stretch."]);
    }

    // ---- Break reminder ----------------------------------------------------------
    // Screen time since the last break (two minutes away: idle, locked, asleep
    // or nothing focused). Off unless `breakMinutes` is set.
    property var breaks: Model.newBreakState()
    readonly property double breakStreakMs: breaks.streakMs

    // ---- App limits ------------------------------------------------------------
    // Each app with a daily limit gets one desktop notification the day it
    // reaches it; the bar turns the urgent colour while any app is over.

    readonly property var limitStatus: Model.limitStatus(visibleToday, appLimits, appNames)
    readonly property var overLimits: limitStatus.filter(function (s) {
        return s.over;
    })
    // "YYYY-MM-DD|name" of the limits already announced.
    property var notified: ({})
    // The first check after starting only takes note, so restarting the shell
    // doesn't repeat today's notifications.
    property bool limitsPrimed: false

    onLimitStatusChanged: checkLimits()
    onTodayKeyChanged: notified = ({})

    function checkLimits() {
        if (!ready)
            return;
        var next = null;
        for (var i = 0; i < limitStatus.length; i++) {
            var s = limitStatus[i];
            var id = todayKey + "|" + s.name;
            if (!s.over || notified[id])
                continue;
            next = next || Object.assign({}, notified);
            next[id] = true;
            if (limitsPrimed)
                Quickshell.execDetached(["notify-send", "--app-name=Screen Time", "--icon=appointment-soon", s.label + ": daily limit reached", "You've used " + Model.fmt(s.usedMs) + " of your " + Model.fmt(s.limitMs) + " today."]);
        }
        if (next)
            notified = next;
        limitsPrimed = true;
    }

    // One line per limit, for `omarchy-shell rimuru.screentime limits`.
    function limitsSummary() {
        if (limitStatus.length === 0)
            return "No limits set";
        return limitStatus.map(function (s) {
            return s.label + "  " + Model.fmt(s.usedMs) + " / " + Model.fmt(s.limitMs) + (s.over ? "  OVER" : "");
        }).join("\n");
    }

    // ---- Idle ------------------------------------------------------------------
    // The compositor reports when there has been no keyboard or mouse input for
    // `idleMinutes`. Apps that keep the screen awake (a playing video, a call)
    // hold that off, so watching still counts. By the time it fires, the wait
    // itself has been counted although nobody was there, so it is taken back.

    readonly property double idleMs: idleMinutes * 60000
    readonly property bool userIdle: idleMonitor.enabled && idleMonitor.isIdle
    // What was counted during the last idleMs (see Model.logRecent).
    property var recent: []

    IdleMonitor {
        id: idleMonitor
        enabled: root.ready && root.idleMinutes > 0
        timeout: root.idleMinutes * 60
        respectInhibitors: true
    }

    onUserIdleChanged: {
        // Gone since the idle wait began, which is already longer than a break.
        if (userIdle)
            breaks = Model.breakPause({
                "streakMs": Math.max(0, breaks.streakMs - idleMs),
                "pausedAt": 0,
                "reminded": breaks.reminded
            }, Date.now() - idleMs);
        if (userIdle && recent.length > 0) {
            days = Model.takeBack(days, recent, Date.now() - idleMs);
            dirty = true;
        }
        recent = [];
    }

    // Clears today only; earlier days and the archive are untouched. The window
    // keeps being timed from now, so cleared time can't come back.
    function resetToday() {
        var next = Object.assign({}, days);
        delete next[todayKey];
        days = next;
        recent = [];
        dirty = true;
        save();
    }

    // Erases everything, archive included. There is no undo.
    function resetAll() {
        days = ({});
        archive = ({});
        recent = [];
        dirty = true;
        save();
    }

    // Days that have aged out of the detailed window move to the archive.
    function rollHistory(now) {
        var rolled = Model.rollArchive(days, archive, Model.KEEP_DAYS, now);
        days = rolled.days;
        archive = rolled.archive;
    }

    function save() {
        if (!ready || !dirty)
            return;
        dirty = false;
        historyFile.setText(Model.serialize(days, archive));
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
                var rolled = Model.rollArchive(Model.normalizeKeys(parsed.days), parsed.archive, Model.KEEP_DAYS, new Date());
                root.days = rolled.days;
                root.archive = rolled.archive;
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
