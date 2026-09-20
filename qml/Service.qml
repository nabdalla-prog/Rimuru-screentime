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
// is up, when no window has focus, or across a suspend (a gap longer than
// maxGapMs is treated as the machine being asleep, not as usage).
Item {
    id: root

    // Injected by omarchy-shell.
    property var shell: null

    readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-screentime"
    readonly property string historyPath: dataDir + "/history.json"

    readonly property int tickMs: 1000
    readonly property int maxGapMs: 5000
    readonly property int saveEveryMs: 60000
    readonly property string screensaverAppId: "org.omarchy.screensaver"

    // Always replaced, never mutated in place, so bindings re-evaluate.
    property var days: ({})
    property string todayKey: Model.dayKey(new Date())
    readonly property var today: days[todayKey] || Model.newDay()
    readonly property double todayTotal: today.total
    readonly property string label: Model.fmt(todayTotal)
    readonly property bool hasActivity: todayTotal > 0

    property bool ready: false
    property bool dirty: false
    property double lastTick: 0

    property bool sessionLocked: false
    readonly property var lockService: shell ? shell.serviceFor("omarchy.lock") : null

    readonly property string focusedApp: {
        var tl = ToplevelManager.activeToplevel;
        return tl && tl.appId ? String(tl.appId) : "";
    }
    readonly property bool tracking: ready && !sessionLocked && focusedApp !== "" && focusedApp !== screensaverAppId

    function tick() {
        var now = Date.now();
        var delta = now - lastTick;
        lastTick = now;

        var key = Model.dayKey(new Date(now));
        if (key !== todayKey) {
            todayKey = key;
            days = Model.pruneDays(days, Model.KEEP_DAYS, new Date(now));
            dirty = true;
        }

        if (!tracking || delta <= 0 || delta > maxGapMs)
            return;
        days = Model.addTime(days, todayKey, focusedApp, delta);
        dirty = true;
    }

    function save() {
        if (!ready || !dirty)
            return;
        dirty = false;
        historyFile.setText(Model.serialize(days));
    }

    // ---- Storage -----------------------------------------------------------

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
                root.days = Model.pruneDays(parsed.days, Model.KEEP_DAYS, new Date());
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
