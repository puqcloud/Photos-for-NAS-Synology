import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Rectangle {
    id: root
    width: Math.min(parent.width - units.gu(4), units.gu(46))
    height: contentRow.height + units.gu(2)
    radius: units.gu(1)
    color: isError ? "#FF3B30" : (isSuccess ? "#34C759" : "#323232")
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: isShowing ? units.gu(3) : -height - units.gu(5)
    opacity: isShowing ? 1.0 : 0.0
    visible: opacity > 0
    z: 2500

    property string message: ""
    property bool isError: false
    property bool isSuccess: false
    property bool isShowing: false

    Behavior on anchors.topMargin {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: 200 }
    }

    Row {
        id: contentRow
        width: parent.width - units.gu(3)
        anchors.centerIn: parent
        spacing: units.gu(1.5)

        Icon {
            name: root.isError ? "dialog-error" : (root.isSuccess ? "ok" : "dialog-information")
            width: units.gu(2.8)
            height: units.gu(2.8)
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
        }

        Label {
            text: root.message
            color: "#ffffff"
            font.pixelSize: units.gu(1.6)
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            width: parent.width - units.gu(4.5)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Timer {
        id: hideTimer
        interval: 3500
        repeat: false
        onTriggered: {
            root.isShowing = false;
        }
    }

    function show(msg, error, success) {
        root.message = msg || "";
        root.isError = !!error;
        root.isSuccess = !!success;
        root.isShowing = true;
        hideTimer.restart();
    }
}
