import QtQuick
import "../../js/Model.js" as Model

// A faint picture behind the popup. It only ever draws: it takes no clicks, sits
// under everything, and its strength is capped at a watermark so text stays
// easy to read. The picture is either the built-in slime or a file the user
// chose; if that file can't be loaded, nothing is drawn and `status` says why.
Item {
    id: root

    // "off", "slime" or "image".
    property string mode: "slime"
    // A plain filesystem path (already cleaned by Model.cleanImagePath).
    property string imagePath: ""
    // "fill" covers the popup; "fit" shows the whole picture in the corner.
    property string fit: "fill"
    // Opacity, from Model.backgroundOpacity.
    property real strength: 0.10

    // "ok", "empty" (no path yet), "loading" or "error".
    readonly property string status: {
        if (mode !== "image")
            return "ok";
        if (imagePath === "")
            return "empty";
        if (picture.status === Image.Ready)
            return "ok";
        return picture.status === Image.Error ? "error" : "loading";
    }

    clip: true
    visible: mode !== "off"
    enabled: false

    SlimeArt {
        visible: root.mode === "slime"
        // The drawing is small and solid, so it gets a little more than a photo
        // would, but never past a watermark.
        opacity: Math.min(0.24, root.strength * 1.3)
        width: Math.min(root.width * 0.62, root.height * 0.7)
        height: width
        // Tucked into the lower right corner, bleeding a little past the edges.
        x: root.width - width * 0.86
        y: root.height - height * 0.9
    }

    Image {
        id: picture
        visible: root.mode === "image"
        anchors.fill: parent
        source: root.mode === "image" ? Model.imageUrl(root.imagePath) : ""
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        // Decode no larger than the popup could ever show.
        sourceSize.width: 1600
        sourceSize.height: 1600
        opacity: root.strength
        fillMode: root.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        horizontalAlignment: Image.AlignRight
        verticalAlignment: root.fit === "fit" ? Image.AlignBottom : Image.AlignVCenter
    }
}
