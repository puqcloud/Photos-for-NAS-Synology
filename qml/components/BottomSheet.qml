import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Item {
    id: bottomSheet
    anchors.fill: parent
    visible: false
    z: 999

    default property alias content: contentContainer.data
    property alias contentHeight: backgroundRect.height
    
    signal closed()

    // Dimmed background
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: bottomSheet.visible ? 0.5 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            onClicked: bottomSheet.close()
        }
    }

    // Sheet container
    Rectangle {
        id: backgroundRect
        width: parent.width
        height: units.gu(40) // Default, should be overridden
        color: Theme.background
        radius: units.gu(2)
        
        // Hide the bottom radius by extending it downwards
        Rectangle {
            width: parent.width
            height: units.gu(2)
            anchors.bottom: parent.bottom
            color: parent.color
        }

        y: bottomSheet.visible ? (parent.height - height) : parent.height
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        Item {
            id: contentContainer
            anchors.fill: parent
            anchors.margins: units.gu(2)
        }
    }

    function open() {
        bottomSheet.visible = true;
    }

    function close() {
        bottomSheet.visible = false;
        bottomSheet.closed();
    }
}
