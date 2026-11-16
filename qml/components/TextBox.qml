import QtQuick
import qs.Commons

// A one-line text field. Enter reports the text through `submitted`; Esc
// gives up focus (so the popup's own keys work again). `editing` is true while
// the field has focus, which the popup uses to stop treating typing as
// shortcuts.
//
// The TextInput inside stays read-only and this file does the typing itself.
// An editable TextInput reads the whole clipboard every time the clipboard
// changes (to keep `canPaste` current), whether or not it has focus or is even
// on screen. In a shell that never exits, any program that owns the clipboard
// could stall or exhaust it that way. Read-only skips that read, so here the
// clipboard is read only when the user presses the paste shortcut. The price
// is no undo and no input-method composition in these fields.
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
        readOnly: true
        cursorVisible: activeFocus

        // Replaces the selection (if any) with `s`. insert() honours
        // maximumLength.
        function type(s) {
            if (selectionStart !== selectionEnd)
                remove(selectionStart, selectionEnd);
            insert(cursorPosition, s);
        }
        // Deletes the selection, or else `count` characters before (negative)
        // or after (positive) the cursor, keeping surrogate pairs whole.
        function erase(count) {
            if (selectionStart !== selectionEnd) {
                remove(selectionStart, selectionEnd);
                return;
            }
            let from = cursorPosition, to = cursorPosition + count;
            const code = i => text.charCodeAt(i);
            if (count < 0 && to > 0 && code(to) >= 0xDC00 && code(to) <= 0xDFFF)
                to--;
            else if (count > 0 && to < length && code(to - 1) >= 0xD800 && code(to - 1) <= 0xDBFF)
                to++;
            remove(Math.max(0, Math.min(from, to)), Math.min(length, Math.max(from, to)));
        }
        // How far the previous word starts before the cursor (Ctrl+Backspace).
        function wordBefore() {
            const m = /\S*\s*$/.exec(text.slice(0, cursorPosition));
            return Math.max(1, m ? m[0].length : 1);
        }
        // The only clipboard read: paste() needs an editable field, so it is
        // editable for exactly this call. Switching moves the cursor to the
        // end, hence the saving and restoring around it.
        function pasteNow() {
            const a = selectionStart, b = selectionEnd, at = cursorPosition;
            readOnly = false;
            if (a !== b)
                select(a, b);
            else
                cursorPosition = at;
            paste();
            const after = cursorPosition;
            readOnly = true;
            cursorPosition = after;
            cursorVisible = Qt.binding(() => activeFocus);
        }

        Keys.onPressed: function (event) {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (event.key === Qt.Key_Escape) {
                input.focus = false;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submitted(text);
            } else if (event.matches(StandardKey.Paste)) {
                pasteNow();
            } else if (event.matches(StandardKey.Cut)) {
                copy();
                erase(0);
            } else if (event.key === Qt.Key_Backspace) {
                erase(ctrl ? -wordBefore() : -1);
            } else if (event.key === Qt.Key_Delete) {
                erase(1);
            } else {
                // Printable text only. Shortcuts and control characters fall
                // through to the TextInput (copy, select all, moving the
                // cursor). Ctrl with Alt is how some layouts send AltGr.
                const alt = (event.modifiers & Qt.AltModifier) !== 0;
                const c = event.text.length ? event.text.charCodeAt(0) : 0;
                if ((ctrl && !alt) || c < 0x20 || c === 0x7F)
                    return;
                type(event.text);
            }
            event.accepted = true;
        }
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
