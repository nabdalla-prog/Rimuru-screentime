import QtQuick
import QtQuick.Shapes
import qs.Commons

// Ring chart of one day. `slices` come from Model.donutSlices, each with a
// `color` added. The colour lives inside the slice on purpose: a change then
// replaces the slices (and their shapes) instead of relying on an existing
// shape repainting. The pointer highlights a slice (and dims the rest); the
// owner keeps the highlighted index in `hovered` so a legend can share it.
Item {
    id: root

    property var slices: []
    property int hovered: -1
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    // Centre text: shown for the whole day, or for the hovered slice.
    property string centerTitle: ""
    property string centerValue: ""

    // The pointer moved over a slice, or off the ring (-1).
    signal hoverRequested(int index)

    readonly property real ring: Style.space(16)
    readonly property real radius: (Math.min(width, height) - ring - Style.space(6)) / 2
    readonly property real gapDegrees: slices.length > 1 ? 1.6 : 0

    implicitWidth: Style.space(150)
    implicitHeight: implicitWidth

    function sliceAt(x, y) {
        var dx = x - width / 2;
        var dy = y - height / 2;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < radius - ring / 2 - Style.space(2) || dist > radius + ring / 2 + Style.space(4))
            return -1;
        // Clockwise from twelve o'clock, as a fraction of a turn.
        var turn = (Math.atan2(dy, dx) * 180 / Math.PI + 90) / 360;
        if (turn < 0)
            turn += 1;
        for (var i = 0; i < slices.length; i++)
            if (turn >= slices[i].startFrac && turn < slices[i].startFrac + slices[i].sweepFrac)
                return i;
        return -1;
    }

    // The empty ring stays visible, so an idle day still shows a chart. A
    // bordered circle rather than an arc: a near-full arc leaves faint seams.
    Rectangle {
        anchors.centerIn: parent
        width: root.radius * 2 + root.ring
        height: width
        radius: width / 2
        color: "transparent"
        border.width: root.ring
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
    }

    Repeater {
        model: root.slices

        Shape {
            id: slice
            required property var modelData
            required property int index
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.hovered < 0 || root.hovered === index ? 1 : 0.35
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }

            ShapePath {
                strokeColor: slice.modelData.color !== undefined ? slice.modelData.color : root.foreground
                strokeWidth: root.hovered === slice.index ? root.ring + Style.space(5) : root.ring
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                Behavior on strokeWidth {
                    NumberAnimation {
                        duration: 120
                    }
                }
                PathAngleArc {
                    centerX: root.width / 2
                    centerY: root.height / 2
                    radiusX: root.radius
                    radiusY: root.radius
                    startAngle: -90 + slice.modelData.startFrac * 360 + root.gapDegrees / 2
                    sweepAngle: Math.max(0.6, Math.min(359.9, slice.modelData.sweepFrac * 360 - root.gapDegrees))
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: root.radius * 1.5
        spacing: Style.space(1)

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.centerTitle
            elide: Text.ElideRight
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.centerValue
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function (mouse) {
            root.hoverRequested(root.sliceAt(mouse.x, mouse.y));
        }
        onExited: root.hoverRequested(-1)
    }
}
