import QtQuick
import QtQuick.Shapes

// A small slime mascot in light blue: a droplet body with a glossy highlight,
// two shiny eyes, rosy cheeks and a smile. It is an original drawing, made
// from a few shapes in a 200 x 200 space and scaled to fit the item; it is not
// artwork from the anime.
Item {
    id: root

    implicitWidth: 200
    implicitHeight: 200

    Item {
        id: stage
        width: 200
        height: 200
        scale: Math.min(root.width, root.height) / 200
        transformOrigin: Item.TopLeft

        // Soft shadow on the ground.
        Rectangle {
            x: 36
            y: 178
            width: 128
            height: 14
            radius: 7
            color: "#26000000"
        }

        Shape {
            width: 200
            height: 200
            preferredRendererType: Shape.CurveRenderer

            // Body.
            ShapePath {
                strokeWidth: 0
                fillGradient: LinearGradient {
                    x1: 100
                    y1: 12
                    x2: 100
                    y2: 186

                    GradientStop {
                        position: 0.0
                        color: "#a4e3ff"
                    }
                    GradientStop {
                        position: 0.55
                        color: "#52b4f6"
                    }
                    GradientStop {
                        position: 1.0
                        color: "#2f7fdf"
                    }
                }
                PathSvg {
                    path: "M 100 14 C 108 14 114 24 120 38 C 148 56 178 84 180 122 C 182 160 152 184 100 184 C 48 184 18 160 20 122 C 22 84 52 56 80 38 C 86 24 92 14 100 14 Z"
                }
            }

            // Glossy highlight on the upper left.
            ShapePath {
                fillColor: "transparent"
                strokeColor: "#b3ffffff"
                strokeWidth: 8
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M 46 104 C 50 84 64 70 84 62"
                }
            }

            // Smile.
            ShapePath {
                fillColor: "transparent"
                strokeColor: "#1b2a52"
                strokeWidth: 5
                capStyle: ShapePath.RoundCap
                PathSvg {
                    path: "M 84 146 Q 100 164 116 146"
                }
            }
        }

        // Eyes, with a sparkle each.
        Rectangle {
            x: 60
            y: 106
            width: 24
            height: 32
            radius: 12
            color: "#1b2a52"
        }
        Rectangle {
            x: 116
            y: 106
            width: 24
            height: 32
            radius: 12
            color: "#1b2a52"
        }
        Rectangle {
            x: 67
            y: 111
            width: 9
            height: 9
            radius: 4.5
            color: "white"
        }
        Rectangle {
            x: 123
            y: 111
            width: 9
            height: 9
            radius: 4.5
            color: "white"
        }

        // Cheeks.
        Rectangle {
            x: 42
            y: 138
            width: 22
            height: 12
            radius: 6
            color: "#70ff8fa3"
        }
        Rectangle {
            x: 136
            y: 138
            width: 22
            height: 12
            radius: 6
            color: "#70ff8fa3"
        }
    }
}
