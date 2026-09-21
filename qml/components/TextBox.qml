import QtQuick
import qs.Commons

// A one-line text field. Enter reports the text through `submitted`; Esc
// gives up focus (so the popup's own keys work again). `editing` is true while
// the field has focus, which the popup uses to stop treating typing as
// shortcuts.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    readonly property bool editing: input.activeFocus

    signal submitted(string text)

    function clear() {
        input.text = "";
    }
    function release() {
        input.focus = false;
    }
    function focusInput() {
        input.forceActiveFocus();
    }

    implicitHeight: Style.space(28)
    radius: Style.space(6)
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    border.width: 1
    border.color: input.activeFocus ? foreground : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.2)

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        selectByMouse: true
        maximumLength: 60
        color: root.foreground
        selectionColor: root.foreground
        selectedTextColor: Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: root.submitted(text)
        Keys.onEscapePressed: input.focus = false
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text === "" && !input.activeFocus
        textFormat: Text.PlainText
        text: root.placeholder
        color: Qt.darker(root.foreground, 1.8)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        acceptedButtons: Qt.NoButton
    }
}
