import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi
import "../js/Storage.js" as Storage

Item {
    id: moreTab
    anchors.fill: parent

    Flickable {
        id: pageFlick
        anchors.fill: parent
        contentHeight: contentCol.height + units.gu(4)
        clip: true

        Column {
            id: contentCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: 0

            // 1. User Profile Header
            Item {
                width: parent.width
                height: units.gu(11)

                Row {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: units.gu(2.5)
                    }
                    spacing: units.gu(2)

                    Column {
                        width: parent.width - units.gu(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.gu(0.4)

                        Label {
                            text: mainView.username || "User"
                            font.pixelSize: units.gu(2.6)
                            font.weight: Font.Bold
                            color: Theme.textDark
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Label {
                            text: mainView.serverUrl || ""
                            font.pixelSize: units.gu(1.6)
                            color: Theme.textMuted
                            elide: Text.ElideMiddle
                            width: parent.width
                        }
                    }

                    Rectangle {
                        width: units.gu(6.5)
                        height: units.gu(6.5)
                        radius: units.gu(3.25)
                        color: "#EAECEF"
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            anchors.centerIn: parent
                            name: "contact"
                            width: units.gu(4)
                            height: units.gu(4)
                            color: "#B0B5BD"
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: units.dp(1)
                    color: Theme.divider
                }
            }

            // 2. Settings
            Item {
                width: parent.width
                height: units.gu(7.5)

                Rectangle {
                    anchors.fill: parent
                    color: settingsMouse.pressed ? "#F5F5F7" : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2.5)
                        }
                        spacing: units.gu(2)

                        Icon {
                            name: "settings"
                            width: units.gu(2.8)
                            height: units.gu(2.8)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: i18n.tr("Settings")
                            font.pixelSize: units.gu(2)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - units.gu(8)
                        }

                        Icon {
                            name: "next"
                            width: units.gu(2.2)
                            height: units.gu(2.2)
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        onClicked: pageStack.push(Qt.resolvedUrl("PreLoginSettingsPage.qml"));
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: units.dp(1)
                    color: Theme.divider
                }
            }

            // 3. About & Disclaimer
            Item {
                width: parent.width
                height: units.gu(7.5)

                Rectangle {
                    anchors.fill: parent
                    color: aboutMouse.pressed ? "#F5F5F7" : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2.5)
                        }
                        spacing: units.gu(2)

                        Icon {
                            name: "dialog-information"
                            width: units.gu(2.8)
                            height: units.gu(2.8)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: i18n.tr("About & Disclaimer")
                            font.pixelSize: units.gu(2)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - units.gu(8)
                        }

                        Icon {
                            name: "next"
                            width: units.gu(2.2)
                            height: units.gu(2.2)
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: aboutMouse
                        anchors.fill: parent
                        onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"));
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: units.dp(1)
                    color: Theme.divider
                }
            }

            // 4. Log Out
            Item {
                width: parent.width
                height: units.gu(7.5)

                Rectangle {
                    anchors.fill: parent
                    color: logoutMouse.pressed ? "#F5F5F7" : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2.5)
                        }
                        spacing: units.gu(2)

                        Icon {
                            name: "system-log-out"
                            width: units.gu(2.8)
                            height: units.gu(2.8)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: i18n.tr("Log Out")
                            font.pixelSize: units.gu(2)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: logoutMouse
                        anchors.fill: parent
                        onClicked: doLogout()
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: units.dp(1)
                    color: Theme.divider
                }
            }
        }
    }

    Scrollbar {
        flickableItem: pageFlick
        align: Qt.AlignTrailing
    }

    function doLogout() {
        mainView.showLoading(i18n.tr("Logging out..."));
        SynoApi.logout(mainView.serverUrl, mainView.sid, mainView.synotoken, function() {
            mainView.hideLoading();
            Storage.clearAllCredentials();
            SynoApi.clearFolderCache();
            backupManager.stopBackup();
            mainView.sid = "";
            mainView.synotoken = "";
            mainView.isLoggedIn = false;
            pageStack.clear();
            pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
        });
    }
}
