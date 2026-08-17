import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Rectangle {
    id: root
    anchors.fill: parent
    color: "#66000000"
    visible: opacity > 0
    opacity: 0
    z: 1500

    property string message: i18n.tr("Connecting...")

    Behavior on opacity {
        NumberAnimation { duration: 150 }
    }

    MouseArea {
        anchors.fill: parent
        preventStealing: true
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(8), units.gu(32))
        height: units.gu(9)
        radius: units.gu(1)
        color: "#ffffff"

        Row {
            anchors.centerIn: parent
            spacing: units.gu(2)

            ActivityIndicator {
                anchors.verticalCenter: parent.verticalCenter
                running: root.visible
                width: units.gu(3.2)
                height: units.gu(3.2)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: root.message
                font.pixelSize: units.gu(1.8)
                color: Theme.textDark
            }
        }
    }

    function show(msg) {
        root.message = msg || i18n.tr("Connecting...");
        root.opacity = 1.0;
    }

    function hide() {
        root.opacity = 0;
    }
}
