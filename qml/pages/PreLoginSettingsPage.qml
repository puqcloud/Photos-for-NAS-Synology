import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/Storage.js" as Storage

Page {
    id: preLoginSettingsPage
    header: Item {
        width: preLoginSettingsPage.width
        height: 0
        visible: false
    }

    property int cacheBytes: 0

    Component.onCompleted: refreshCacheSize()

    Connections {
        target: mainView
        onMemoryCacheCleared: refreshCacheSize()
    }

    function refreshCacheSize() {
        if (typeof synoImageCache !== "undefined") {
            preLoginSettingsPage.cacheBytes = synoImageCache.cacheSizeBytes();
        }
    }

    function formatSize(bytes) {
        if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Settings")
            showBack: true
            onBackClicked: pageStack.pop()
        }

        Flickable {
            id: pageFlick
            width: parent.width
            height: parent.height - units.gu(6)
            contentHeight: contentCol.height + units.gu(4)
            clip: true

            Column {
                id: contentCol
                width: parent.width
                spacing: 0

                // SECTION: Backup
                Item { width: parent.width; height: units.gu(3); }
                Label {
                    text: i18n.tr("Backup")
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                    color: Theme.primary
                    anchors.left: parent.left
                    anchors.leftMargin: units.gu(2)
                }
                Item { width: parent.width; height: units.gu(1.5); }

                // Photo Backup
                Item {
                    width: parent.width
                    height: units.gu(6.5)

                    Icon {
                        name: "save"
                        width: units.gu(2.6)
                        height: units.gu(2.6)
                        color: Theme.primary
                        anchors.left: parent.left
                        anchors.leftMargin: units.gu(2)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: units.gu(5.5)
                        anchors.right: parent.right
                        anchors.rightMargin: units.gu(4)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: i18n.tr("Photo Backup")
                            font.pixelSize: units.gu(2)
                            color: Theme.textDark
                        }
                        Label {
                            text: {
                                if (!backupManager.enabled) return i18n.tr("Disabled");
                                var folders = Storage.getBackupFolders();
                                if (folders.length === 0) return i18n.tr("Enabled • no folders selected");
                                return i18n.tr("Enabled");
                            }
                            font.pixelSize: units.gu(1.4)
                            color: backupManager.enabled ? Theme.primary : Theme.textMuted
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Icon {
                        name: "next"
                        width: units.gu(2)
                        height: units.gu(2)
                        color: Theme.textMuted
                        anchors.right: parent.right
                        anchors.rightMargin: units.gu(2)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!mainView.isLoggedIn) {
                                mainView.showToast(i18n.tr("Please log in first"), true, false);
                                return;
                            }
                            pageStack.push(Qt.resolvedUrl("BackupSettingsPage.qml"));
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: units.dp(1)
                    color: Theme.divider
                }

                // Clear Cache
                Item {
                    width: parent.width
                    height: units.gu(8)

                    Rectangle {
                        anchors.fill: parent
                        color: clearCacheMouse.pressed ? "#F5F5F7" : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: units.gu(2)
                            }
                            spacing: units.gu(2)

                            Icon {
                                name: "delete"
                                width: units.gu(2.6)
                                height: units.gu(2.6)
                                color: Theme.textDark
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - units.gu(6)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: units.dp(2)

                                Label {
                                    text: i18n.tr("Clear Cache")
                                    font.pixelSize: units.gu(1.9)
                                    font.weight: Font.DemiBold
                                    color: Theme.textDark
                                }

                                Label {
                                    text: preLoginSettingsPage.cacheBytes > 0
                                        ? i18n.tr("Cache: %1 • safe to delete").arg(preLoginSettingsPage.formatSize(preLoginSettingsPage.cacheBytes))
                                        : i18n.tr("Clear cached images")
                                    font.pixelSize: units.gu(1.4)
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }

                        MouseArea {
                            id: clearCacheMouse
                            anchors.fill: parent
                            onClicked: {
                                if (preLoginSettingsPage.cacheBytes <= 0) {
                                    mainView.showToast(i18n.tr("No cached images on the device"), false, true);
                                    return;
                                }
                                mainView.showErrorDialog(
                                    i18n.tr("Clear Cache"),
                                    i18n.tr("Delete %1 of cached images?").arg(preLoginSettingsPage.formatSize(preLoginSettingsPage.cacheBytes)),
                                    i18n.tr("Delete"),
                                    i18n.tr("Cancel"),
                                    function() {
                                        if (typeof synoImageCache !== "undefined") synoImageCache.clearCache();
                                        mainView.memoryCacheCleared();
                                        preLoginSettingsPage.refreshCacheSize();
                                        mainView.showToast(i18n.tr("Cache cleared"), false, true);
                                    },
                                    null
                                );
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

                // Free Up Space
                Item {
                    width: parent.width
                    height: units.gu(8)

                    Rectangle {
                        anchors.fill: parent
                        color: freeSpaceMouse.pressed ? "#F5F5F7" : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: units.gu(2)
                            }
                            spacing: units.gu(2)

                            Icon {
                                name: "delete"
                                width: units.gu(2.6)
                                height: units.gu(2.6)
                                color: Theme.textDark
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - units.gu(6)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: units.dp(2)

                                Label {
                                    text: i18n.tr("Free Up Space")
                                    font.pixelSize: units.gu(1.9)
                                    font.weight: Font.DemiBold
                                    color: Theme.textDark
                                }

                                Label {
                                    text: backupManager.clearableCount > 0
                                        ? i18n.tr("%1 backed up files on device • %2").arg(backupManager.clearableCount).arg(backupManager.clearableSizeText)
                                        : i18n.tr("Delete local copies of backed up files")
                                    font.pixelSize: units.gu(1.4)
                                    color: backupManager.clearableCount > 0 ? Theme.primary : Theme.textMuted
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }

                        MouseArea {
                            id: freeSpaceMouse
                            anchors.fill: parent
                            onClicked: {
                                if (backupManager.clearableCount === 0) {
                                    mainView.showToast(i18n.tr("No backed up files on the device"), false, true);
                                    return;
                                }
                                mainView.showErrorDialog(
                                    i18n.tr("Free Up Space"),
                                    i18n.tr("Delete %1 local files (%2) that are already on the server?").arg(backupManager.clearableCount).arg(backupManager.clearableSizeText),
                                    i18n.tr("Delete"),
                                    i18n.tr("Cancel"),
                                    function() {
                                        backupManager.freeUpSpace();
                                    },
                                    null
                                );
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

                // Reset App
                Item {
                    width: parent.width
                    height: units.gu(8)

                    Rectangle {
                        anchors.fill: parent
                        color: resetAppMouse.pressed ? "#F5F5F7" : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: units.gu(2)
                            }
                            spacing: units.gu(2)

                            Icon {
                                name: "edit-clear"
                                width: units.gu(2.6)
                                height: units.gu(2.6)
                                color: "#FF3B30"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - units.gu(6)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: units.dp(2)

                                Label {
                                    text: i18n.tr("Reset App")
                                    font.pixelSize: units.gu(1.9)
                                    font.weight: Font.DemiBold
                                    color: "#FF3B30"
                                }

                                Label {
                                    text: i18n.tr("Erase all data and restore the app to its fresh-install state")
                                    font.pixelSize: units.gu(1.4)
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }

                        MouseArea {
                            id: resetAppMouse
                            anchors.fill: parent
                            onClicked: {
                                mainView.showErrorDialog(i18n.tr("Reset App"),
                                    i18n.tr("This will erase all app data: your login, settings, and backup configuration. The app will be restored to its fresh-install state. This cannot be undone."),
                                    i18n.tr("Reset"), i18n.tr("Cancel"),
                                    function() {
                                        if (typeof synoImageCache !== "undefined") synoImageCache.clearCache();
                                        if (typeof backupManager !== "undefined") {
                                            backupManager.stopBackup();
                                            backupManager.uploadItems = [];
                                        }
                                        Storage.fullReset();
                                        mainView.sid = "";
                                        mainView.synotoken = "";
                                        mainView.username = "";
                                        mainView.serverUrl = "";
                                        mainView.isLoggedIn = false;
                                        pageStack.clear();
                                        pageStack.push(Qt.resolvedUrl("LoginPage.qml"));
                                    },
                                    function() {});
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
            }
        }
    }
}
