import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Rectangle {
    id: root
    width: units.gu(36)
    height: units.gu(4.8)
    radius: units.gu(2.4)
    color: "#EBECEF"
    z: 90

    property int selectedIndex: 2 // 0: Year, 1: Month, 2: Day, 3: Folders
    signal filterChanged(int index)

    // Border
    border.color: "#DFE1E5"
    border.width: units.dp(1)

    Row {
        anchors.fill: parent
        anchors.margins: units.dp(3)

        Repeater {
            model: [i18n.tr("Year"), i18n.tr("Month"), i18n.tr("Day"), i18n.tr("Folders")]

            Item {
                width: (root.width - units.dp(6)) / 4
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    radius: units.gu(2)
                    color: root.selectedIndex === index ? "#FFFFFF" : "transparent"
                    border.color: root.selectedIndex === index ? "#E0E2E6" : "transparent"
                    border.width: root.selectedIndex === index ? units.dp(1) : 0

                    Label {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: units.gu(1.6)
                        font.weight: root.selectedIndex === index ? Font.DemiBold : Font.Normal
                        color: root.selectedIndex === index ? Theme.textDark : Theme.textMuted
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.selectedIndex = index;
                        root.filterChanged(index);
                    }
                }
            }
        }
    }
}
