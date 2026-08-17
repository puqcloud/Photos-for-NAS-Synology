import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Rectangle {
    id: root
    width: parent.width
    height: units.gu(7)
    color: Theme.background
    z: 100

    property int currentTab: 0 // 0: Photos, 1: Albums, 2: Sharing, 3: More
    signal tabSelected(int index)

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: units.dp(1)
        color: Theme.divider
    }

    Row {
        anchors.fill: parent

        // Tab 0: Photos
        Item {
            width: parent.width / 4
            height: parent.height

            Column {
                anchors.centerIn: parent
                spacing: units.dp(2)

                Icon {
                    name: "image-x-generic"
                    width: units.gu(3)
                    height: units.gu(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.currentTab === 0 ? Theme.primary : Theme.textMuted
                }

                Label {
                    text: i18n.tr("Photos")
                    fontSize: "x-small"
                    font.weight: root.currentTab === 0 ? Font.DemiBold : Font.Normal
                    color: root.currentTab === 0 ? Theme.primary : Theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.currentTab = 0;
                    root.tabSelected(0);
                }
            }
        }

        // Tab 1: Albums
        Item {
            width: parent.width / 4
            height: parent.height

            Column {
                anchors.centerIn: parent
                spacing: units.dp(2)

                Icon {
                    name: "folder"
                    width: units.gu(3)
                    height: units.gu(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.currentTab === 1 ? Theme.primary : Theme.textMuted
                }

                Label {
                    text: i18n.tr("Albums")
                    fontSize: "x-small"
                    font.weight: root.currentTab === 1 ? Font.DemiBold : Font.Normal
                    color: root.currentTab === 1 ? Theme.primary : Theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.currentTab = 1;
                    root.tabSelected(1);
                }
            }
        }

        // Tab 2: Sharing
        Item {
            width: parent.width / 4
            height: parent.height

            Column {
                anchors.centerIn: parent
                spacing: units.dp(2)

                Icon {
                    name: "system-users"
                    width: units.gu(3)
                    height: units.gu(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.currentTab === 2 ? Theme.primary : Theme.textMuted
                }

                Label {
                    text: i18n.tr("Sharing")
                    fontSize: "x-small"
                    font.weight: root.currentTab === 2 ? Font.DemiBold : Font.Normal
                    color: root.currentTab === 2 ? Theme.primary : Theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.currentTab = 2;
                    root.tabSelected(2);
                }
            }
        }

        // Tab 3: More
        Item {
            width: parent.width / 4
            height: parent.height

            Column {
                anchors.centerIn: parent
                spacing: units.dp(2)

                Icon {
                    name: "navigation-menu"
                    width: units.gu(3)
                    height: units.gu(3)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.currentTab === 3 ? Theme.primary : Theme.textMuted
                }

                Label {
                    text: i18n.tr("More")
                    fontSize: "x-small"
                    font.weight: root.currentTab === 3 ? Font.DemiBold : Font.Normal
                    color: root.currentTab === 3 ? Theme.primary : Theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.currentTab = 3;
                    root.tabSelected(3);
                }
            }
        }
    }
}
