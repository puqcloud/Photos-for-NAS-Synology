import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Page {
    id: aboutPage

    header: PageHeader {
        id: pageHeader
        title: i18n.tr("About & Disclaimer")
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.pageBackground
        z: -1
    }

    Flickable {
        id: pageFlick
        anchors {
            top: pageHeader.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        contentHeight: contentCol.height + units.gu(4)
        clip: true

        Column {
            id: contentCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: units.gu(3)
            }
            spacing: units.gu(3)

            // App Icon & Name
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: units.gu(1.5)

                Image {
                    source: "../../photos-for-nas-synology.png"
                    width: units.gu(12)
                    height: units.gu(12)
                    anchors.horizontalCenter: parent.horizontalCenter
                    fillMode: Image.PreserveAspectFit
                }

                Label {
                    text: "Photos for NAS Synology"
                    font.pixelSize: units.gu(2.4)
                    font.weight: Font.Bold
                    color: Theme.textDark
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Label {
                    text: i18n.tr("Version ") + mainView.appVersion
                    font.pixelSize: units.gu(1.5)
                    color: Theme.textMuted
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Rectangle {
                width: parent.width
                height: units.dp(1)
                color: Theme.divider
            }

            // Author
            Column {
                width: parent.width
                spacing: units.gu(1)

                Label {
                    text: i18n.tr("Author")
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                    color: Theme.textDark
                }

                Label {
                    text: "PUQ Software"
                    font.pixelSize: units.gu(1.6)
                    color: Theme.textDark
                }

                Label {
                    text: "Ruslan Polovyi"
                    font.pixelSize: units.gu(1.6)
                    color: Theme.textDark
                }

                Label {
                    id: emailLabel
                    text: "ruslan@polovyi.com"
                    font.pixelSize: units.gu(1.6)
                    color: Theme.primary
                    font.underline: true

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Clipboard.push("ruslan@polovyi.com");
                            emailLabel.text = i18n.tr("Email copied to clipboard");
                            copyResetTimer.restart();
                        }
                    }
                }

                Label {
                    text: i18n.tr("Website: ") + "<a href='https://polovyi.com/'>https://polovyi.com/</a>"
                    font.pixelSize: units.gu(1.6)
                    color: Theme.textDark
                    linkColor: Theme.primary
                    onLinkActivated: Qt.openUrlExternally(link)
                }

                Timer {
                    id: copyResetTimer
                    interval: 2000
                    repeat: false
                    onTriggered: emailLabel.text = "ruslan@polovyi.com"
                }
            }

            // Disclaimer Section
            Column {
                width: parent.width
                spacing: units.gu(1)

                Label {
                    text: i18n.tr("Disclaimer")
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                    color: Theme.textDark
                }

                Label {
                    text: i18n.tr("This application is an unofficial release and is NOT affiliated with, maintained, authorized, endorsed or sponsored by Synology Inc. 'Synology' and 'Synology Photos' are registered trademarks of Synology Inc.\n\nThe application is provided 'as is', without warranty of any kind. You use it at your own risk and the authors accept no liability.")
                    font.pixelSize: units.gu(1.5)
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Rectangle {
                width: parent.width
                height: units.dp(1)
                color: Theme.divider
            }

            // Privacy Statement
            Column {
                width: parent.width
                spacing: units.gu(1)

                Label {
                    text: i18n.tr("Privacy Statement")
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                    color: Theme.textDark
                }

                Label {
                    text: i18n.tr("All your photos, videos, passwords, and data stay strictly between your Ubuntu Touch device and your Synology NAS. No external servers are contacted.")
                    font.pixelSize: units.gu(1.5)
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            // Contact / Support
            Column {
                width: parent.width
                spacing: units.gu(1)

                Label {
                    text: i18n.tr("Contact & Support")
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                    color: Theme.textDark
                }

                Label {
                    text: i18n.tr("For community support, visit <a href='https://github.com/puqcloud/Photos-for-NAS-Synology'>https://github.com/puqcloud/Photos-for-NAS-Synology</a>")
                    font.pixelSize: units.gu(1.5)
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    width: parent.width
                    linkColor: Theme.primary
                    onLinkActivated: Qt.openUrlExternally(link)
                }
            }

            // Credits
            Column {
                width: parent.width
                spacing: units.gu(1)

                Label {
                    text: i18n.tr("Credits")
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                    color: Theme.textDark
                }

                Label {
                    text: i18n.tr("Built for Ubuntu Touch and UBports community.")
                    font.pixelSize: units.gu(1.5)
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
        }
    }

    Scrollbar {
        flickableItem: pageFlick
        align: Qt.AlignTrailing
    }
}
