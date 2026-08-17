import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Rectangle {
    id: root
    width: parent.width
    height: units.gu(6)
    color: Theme.background
    z: 100

    property string title: ""
    property bool showBack: false
    property bool showSearch: false
    property bool showAdd: false
    property bool showRefresh: false
    property bool showInfo: false
    property bool showMore: false
    property bool showUploads: false
    property string uploadsBadge: ""

    signal backClicked()
    signal searchClicked()
    signal addClicked()
    signal refreshClicked()
    signal infoClicked()
    signal moreClicked()
    signal uploadsClicked()

    Row {
        id: leftRow
        anchors.left: parent.left
        anchors.leftMargin: units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        spacing: units.gu(1)

        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: backMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showBack
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                anchors.centerIn: parent
                name: "back"
                width: units.gu(2.6)
                height: units.gu(2.6)
                color: Theme.textDark
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.backClicked()
            }
        }

        Label {
            text: root.title
            font.pixelSize: units.gu(2.6)
            font.weight: Font.Bold
            color: Theme.textDark
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        spacing: units.gu(0.5)

        // Search Button
        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: searchMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showSearch

            Icon {
                anchors.centerIn: parent
                name: "find"
                width: units.gu(2.4)
                height: units.gu(2.4)
                color: Theme.textDark
            }

            MouseArea {
                id: searchMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.searchClicked()
            }
        }

        // Add Button
        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: addMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showAdd

            Icon {
                anchors.centerIn: parent
                name: "add"
                width: units.gu(2.4)
                height: units.gu(2.4)
                color: Theme.textDark
            }

            MouseArea {
                id: addMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addClicked()
            }
        }

        // Refresh Button
        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: refreshMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showRefresh

            Icon {
                anchors.centerIn: parent
                name: "view-refresh"
                width: units.gu(2.4)
                height: units.gu(2.4)
                color: Theme.textDark
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshClicked()
            }
        }

        // Info Button
        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: infoMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showInfo

            Icon {
                anchors.centerIn: parent
                name: "info"
                width: units.gu(2.4)
                height: units.gu(2.4)
                color: Theme.textDark
            }

            MouseArea {
                id: infoMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.infoClicked()
            }
        }

        // Uploads Button (backup queue)
        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: uploadsMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showUploads
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                anchors.centerIn: parent
                name: "transfer-progress-upload"
                width: units.gu(2.4)
                height: units.gu(2.4)
                color: Theme.textDark
            }

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: units.dp(2)
                anchors.right: parent.right
                anchors.rightMargin: units.dp(2)
                width: uploadsBadgeLabel.width + units.gu(1)
                height: units.gu(2)
                radius: units.gu(1)
                color: Theme.primary
                visible: root.uploadsBadge.length > 0

                Label {
                    id: uploadsBadgeLabel
                    anchors.centerIn: parent
                    text: root.uploadsBadge
                    font.pixelSize: units.gu(1.1)
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }
            }

            MouseArea {
                id: uploadsMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.uploadsClicked()
            }
        }

        // More Menu Button
        Rectangle {
            width: units.gu(4.5)
            height: units.gu(4.5)
            radius: units.gu(2.25)
            color: moreMouse.pressed ? "#E5E5EA" : "transparent"
            visible: root.showMore

            Icon {
                anchors.centerIn: parent
                name: "navigation-menu"
                width: units.gu(2.4)
                height: units.gu(2.4)
                color: Theme.textDark
            }

            MouseArea {
                id: moreMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moreClicked()
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: units.dp(1)
        color: Theme.divider
    }
}
