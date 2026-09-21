import QtQuick
import qs.Commons
import "../js/Model.js" as Model
import "components"

// The settings menu, shown inside the popup. Every control reports a change
// through `settingChanged(key, value)`; the owner decides where it is stored,
// so this file knows nothing about the shell. The two destructive actions ask
// several times before reporting.
Item {
    id: root

    // ---- Current values ----------------------------------------------------
    property bool iconOnly: false
    property bool showInsights: true
    property bool showYearLink: true
    property bool playful: true
    property int weekCap: 52
    property int dailyGoalHours: 0
    property var ignoredApps: []
    property var appNames: ({})
    // Names of today's apps, offered as one-tap suggestions to ignore.
    property var todayApps: []
    property string storageText: ""
    property string version: Model.VERSION
    property color danger: Color.urgent
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    // True while a text field has focus, so typing isn't taken as shortcuts.
    readonly property bool editing: ignoreBox.editing || nameApp.editing || nameValue.editing

    signal settingChanged(string key, var value)
    signal resetTodayRequested
    signal wipeAllRequested
    signal backRequested

    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property var nameEntries: Object.keys(appNames).map(function (k) {
        return {
            "key": k,
            "name": appNames[k]
        };
    })

    function addIgnored(raw) {
        var name = String(raw).trim().toLowerCase();
        if (name === "" || ignoredApps.indexOf(name) !== -1)
            return;
        settingChanged("ignoredApps", ignoredApps.concat([name]));
    }
    function removeIgnored(name) {
        settingChanged("ignoredApps", ignoredApps.filter(function (a) {
            return a !== name;
        }));
    }
    function addName() {
        var key = nameApp.text.trim().toLowerCase();
        var name = nameValue.text.trim().slice(0, 40);
        if (key === "" || name === "")
            return;
        var next = Object.assign({}, appNames);
        next[key] = name;
        settingChanged("appNames", next);
        nameApp.clear();
        nameValue.clear();
    }
    function removeName(key) {
        var next = Object.assign({}, appNames);
        delete next[key];
        settingChanged("appNames", next);
    }
    function releaseFocus() {
        ignoreBox.release();
        nameApp.release();
        nameValue.release();
    }

    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        // ---- Header ------------------------------------------------------------
        Item {
            width: parent.width
            height: Style.space(26)

            Text {
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
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Settings"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
            }
        }

        // ---- Display -------------------------------------------------------------
        Card {
            title: "DISPLAY"
            foreground: root.foreground
            fontFamily: root.fontFamily

            ToggleRow {
                label: "Icon only in the bar"
                checked: root.iconOnly
                foreground: root.foreground
                fontFamily: root.fontFamily
                onToggled: function (v) {
                    root.settingChanged("iconOnly", v);
                }
            }
            ToggleRow {
                label: "Show insights"
                detail: "Top app, comparison with the day before, busiest day"
                checked: root.showInsights
                foreground: root.foreground
                fontFamily: root.fontFamily
                onToggled: function (v) {
                    root.settingChanged("showInsights", v);
                }
            }
            ToggleRow {
                label: "Show yearly overview"
                checked: root.showYearLink
                foreground: root.foreground
                fontFamily: root.fontFamily
                onToggled: function (v) {
                    root.settingChanged("showYearLink", v);
                }
            }
            ToggleRow {
                label: "Playful extras"
                detail: "The hourglass turns over on the hour"
                checked: root.playful
                foreground: root.foreground
                fontFamily: root.fontFamily
                onToggled: function (v) {
                    root.settingChanged("playful", v);
                }
            }
        }

        // ---- Trend and history -----------------------------------------------------
        Card {
            title: "TREND & HISTORY"
            foreground: root.foreground
            fontFamily: root.fontFamily

            ChoiceRow {
                label: "Weekly graph reach"
                options: [
                    {
                        "label": "12 weeks",
                        "value": 12
                    },
                    {
                        "label": "24 weeks",
                        "value": 24
                    },
                    {
                        "label": "36 weeks",
                        "value": 36
                    },
                    {
                        "label": "52 weeks",
                        "value": 52
                    }
                ]
                value: root.weekCap
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChosen: function (v) {
                    root.settingChanged("weeks", v);
                }
            }
            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.storageText
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
        }

        // ---- Daily goal ----------------------------------------------------------------
        Card {
            title: "DAILY GOAL"
            foreground: root.foreground
            fontFamily: root.fontFamily

            ChoiceRow {
                label: "A check mark appears in the bar when you reach it"
                options: [
                    {
                        "label": "Off",
                        "value": 0
                    },
                    {
                        "label": "2h",
                        "value": 2
                    },
                    {
                        "label": "4h",
                        "value": 4
                    },
                    {
                        "label": "6h",
                        "value": 6
                    },
                    {
                        "label": "8h",
                        "value": 8
                    },
                    {
                        "label": "10h",
                        "value": 10
                    }
                ]
                value: root.dailyGoalHours
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChosen: function (v) {
                    root.settingChanged("dailyGoalHours", v);
                }
            }
        }

        // ---- Tracking ---------------------------------------------------------------------
        Card {
            title: "TRACKING"
            foreground: root.foreground
            fontFamily: root.fontFamily

            Text {
                textFormat: Text.PlainText
                text: "Ignored apps"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
            }
            Flow {
                width: parent.width
                spacing: Style.space(6)

                Text {
                    visible: root.ignoredApps.length === 0
                    textFormat: Text.PlainText
                    text: "None. Ignored apps are never counted and their past time is hidden."
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
                Repeater {
                    model: root.ignoredApps

                    Chip {

                        foreground: root.foreground

                        fontFamily: root.fontFamily
                        required property string modelData
                        text: modelData
                        removable: true
                        onClicked: root.removeIgnored(modelData)
                    }
                }
            }
            Text {
                visible: root.todayApps.length > 0
                textFormat: Text.PlainText
                text: "Seen today, tap to ignore:"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
            Flow {
                visible: root.todayApps.length > 0
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                    model: root.todayApps

                    Chip {

                        foreground: root.foreground

                        fontFamily: root.fontFamily
                        required property string modelData
                        text: modelData
                        onClicked: root.addIgnored(modelData)
                    }
                }
            }
            TextBox {
                id: ignoreBox
                width: parent.width
                placeholder: "App name, then Enter"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onSubmitted: function (t) {
                    root.addIgnored(t);
                    ignoreBox.clear();
                }
            }

            Rule {
                foreground: root.foreground
            }

            Text {
                textFormat: Text.PlainText
                text: "Custom names"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
            }
            Flow {
                width: parent.width
                spacing: Style.space(6)

                Text {
                    visible: root.nameEntries.length === 0
                    textFormat: Text.PlainText
                    text: "None. Apps given the same name are merged into one row."
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
                Repeater {
                    model: root.nameEntries

                    Chip {

                        foreground: root.foreground

                        fontFamily: root.fontFamily
                        required property var modelData
                        text: modelData.key + " → " + modelData.name
                        removable: true
                        onClicked: root.removeName(modelData.key)
                    }
                }
            }
            Row {
                width: parent.width
                spacing: Style.space(6)

                TextBox {
                    id: nameApp
                    width: (parent.width - addName.width - parent.spacing * 2) * 0.45
                    placeholder: "App"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onSubmitted: nameValue.focusInput()
                }
                TextBox {
                    id: nameValue
                    width: (parent.width - addName.width - parent.spacing * 2) * 0.55
                    placeholder: "Shown as"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onSubmitted: root.addName()
                }
                Chip {
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    id: addName
                    anchors.verticalCenter: nameApp.verticalCenter
                    text: "Add"
                    onClicked: root.addName()
                }
            }
        }

        // ---- About ------------------------------------------------------------------------------
        Card {
            title: "ABOUT"
            foreground: root.foreground
            fontFamily: root.fontFamily

            Text {
                textFormat: Text.PlainText
                text: "Rimuru Screen Time  ·  v" + root.version
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
            }
            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Everything stays on this computer. Nothing is sent anywhere."
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
            Text {
                textFormat: Text.PlainText
                text: "github.com/nabdalla-prog/Rimuru-screentime"
                color: linkMouse.containsMouse ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.underline: linkMouse.containsMouse
                MouseArea {
                    id: linkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally("https://github.com/nabdalla-prog/Rimuru-screentime")
                }
            }
        }

        // ---- Danger zone -------------------------------------------------------------------------------
        Card {
            title: "DANGER ZONE"
            tint: root.danger
            foreground: root.foreground
            fontFamily: root.fontFamily

            DangerButton {
                steps: ["RESET", "SURE?", "REALLY?"]
                title: "Reset today"
                detail: "Clears today only. Earlier days are untouched."
                danger: root.danger
                foreground: root.foreground
                fontFamily: root.fontFamily
                onConfirmed: root.resetTodayRequested()
            }
            DangerButton {
                steps: ["WIPE ALL", "SURE?", "CAN'T UNDO!", "WIPE!"]
                title: "Wipe all history"
                detail: "Erases every day, including the archive. There is no undo."
                danger: root.danger
                foreground: root.foreground
                fontFamily: root.fontFamily
                onConfirmed: root.wipeAllRequested()
            }
        }
    }
}
