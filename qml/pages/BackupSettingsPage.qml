import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/Storage.js" as Storage

Page {
    id: backupSettingsPage

    header: Item {
        width: backupSettingsPage.width
        height: 0
        visible: false
    }

    property var syncStats: Storage.getSyncedStats()
    property int foldersVersion: 0

    Connections {
        target: backupManager
        onStatusChanged: foldersVersion++
        onLocalListRefreshed: syncStats = Storage.getSyncedStats()
    }

    Component.onCompleted: {
        if (mainView.isLoggedIn) backupManager.refreshLocalFiles();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Backup")
            showBack: true
            onBackClicked: pageStack.pop()
        }

        Flickable {
            width: parent.width
            height: parent.height - units.gu(6)
            contentHeight: contentCol.height + units.gu(4)
            clip: true

            Column {
                id: contentCol
                width: parent.width
                spacing: units.gu(2)

                Item { width: 1; height: units.gu(1) }

                // Disabled warning (always visible when disabled)
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(9.5)
                    radius: units.gu(1)
                    color: "#FFF3CD"
                    border.color: "#FFE08A"
                    border.width: units.dp(1)
                    visible: !backupManager.enabled

                    Column {
                        id: warningCol
                        anchors.fill: parent
                        anchors.margins: units.gu(1.5)
                        spacing: units.gu(0.8)

                        Label {
                            text: i18n.tr("Backup is disabled")
                            font.pixelSize: units.gu(1.8)
                            font.weight: Font.DemiBold
                            color: "#8A6D3B"
                        }
                        Label {
                            text: i18n.tr("Turn on backup to continue backing up your photos from this device.")
                            font.pixelSize: units.gu(1.5)
                            color: "#8A6D3B"
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                    }
                }

                // Enable toggle
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(8)
                    radius: units.gu(1)
                    color: Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2)
                        }

                        Column {
                            width: parent.width - enableSwitch.width - units.gu(2)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: i18n.tr("Enable Backup")
                                font.pixelSize: units.gu(1.9)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                            }
                            Label {
                                text: i18n.tr("Automatically upload new photos from this device")
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                            }
                        }

                        Switch {
                            id: enableSwitch
                            checked: backupManager.enabled
                            anchors.verticalCenter: parent.verticalCenter
                            onCheckedChanged: {
                                if (checked !== backupManager.enabled) {
                                    backupManager.enabled = checked;
                                }
                            }
                        }
                    }
                }

                // Wi-Fi only toggle
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(8)
                    radius: units.gu(1)
                    color: Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2)
                        }

                        Column {
                            width: parent.width - wifiSwitch.width - units.gu(2)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: i18n.tr("Upload on Wi-Fi Only")
                                font.pixelSize: units.gu(1.9)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                            }
                            Label {
                                text: i18n.tr("Prevent mobile cellular data usage")
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                            }
                        }

                        Switch {
                            id: wifiSwitch
                            checked: Storage.getSetting("backup_wifi_only", "true") === "true"
                            anchors.verticalCenter: parent.verticalCenter
                            onCheckedChanged: {
                                Storage.setSetting("backup_wifi_only", checked ? "true" : "false");
                            }
                        }
                    }
                }

                // Folder selection card
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(7)
                    radius: units.gu(1)
                    color: folderMouse.pressed ? "#F5F5F7" : Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)
                    opacity: backupManager.enabled ? 1.0 : 0.5

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2)
                        }
                        spacing: units.gu(2)

                        Icon {
                            name: "folder"
                            width: units.gu(3)
                            height: units.gu(3)
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - units.gu(7)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: i18n.tr("Backup Folders")
                                font.pixelSize: units.gu(1.9)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                            }
                            Label {
                                text: {
                                    var v = backupSettingsPage.foldersVersion;
                                    var folders = Storage.getBackupFolders();
                                    if (folders.length === 0) return i18n.tr("No folders selected");
                                    if (folders.indexOf("*") !== -1) return i18n.tr("All folders in Pictures");
                                    return folders.join(", ");
                                }
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Icon {
                            name: "next"
                            width: units.gu(2)
                            height: units.gu(2)
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: folderMouse
                        anchors.fill: parent
                        onClicked: pageStack.push(Qt.resolvedUrl("BackupFoldersPage.qml"));
                    }
                }

                // Status cards (Total / Backed up / Remaining)
                Row {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: units.gu(1.5)

                    Rectangle {
                        width: (parent.width - units.gu(3)) / 3
                        height: units.gu(9)
                        radius: units.gu(1)
                        color: Theme.cardBackground
                        border.color: Theme.divider
                        border.width: units.dp(1)

                        Column {
                            anchors.centerIn: parent
                            spacing: units.dp(3)

                            Label {
                                text: backupManager.selTotal
                                font.pixelSize: units.gu(2.6)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Label {
                                text: i18n.tr("Total")
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - units.gu(3)) / 3
                        height: units.gu(9)
                        radius: units.gu(1)
                        color: Theme.cardBackground
                        border.color: Theme.divider
                        border.width: units.dp(1)

                        Column {
                            anchors.centerIn: parent
                            spacing: units.dp(3)

                            Label {
                                text: backupManager.selBackedUp
                                font.pixelSize: units.gu(2.6)
                                font.weight: Font.DemiBold
                                color: "#4CAF50"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Label {
                                text: i18n.tr("Backed up")
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - units.gu(3)) / 3
                        height: units.gu(9)
                        radius: units.gu(1)
                        color: Theme.cardBackground
                        border.color: Theme.divider
                        border.width: units.dp(1)

                        Column {
                            anchors.centerIn: parent
                            spacing: units.dp(3)

                            Label {
                                text: backupManager.selRemaining
                                font.pixelSize: units.gu(2.6)
                                font.weight: Font.DemiBold
                                color: Theme.primary
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Label {
                                text: i18n.tr("Remaining")
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                // Progress card (visible while running)
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(40)
                    radius: units.gu(1)
                    color: Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)
                    visible: backupManager.running
                    clip: true

                    Column {
                        id: progressCol
                        anchors.fill: parent
                        anchors.margins: units.gu(2)
                        spacing: units.gu(1.5)

                        Row {
                            width: parent.width
                            spacing: units.gu(1)

                            Label {
                                id: percentLabel
                                text: Math.round(backupManager.running && backupManager.phase === "uploading"
                                    ? backupManager.overallPercent + backupManager.currentPercent / Math.max(backupManager.totalFiles, 1)
                                    : 0) + "%"
                                font.pixelSize: units.gu(1.6)
                                font.weight: Font.DemiBold
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Label {
                                text: {
                                    if (backupManager.phase === "scanning") return i18n.tr("Scanning device...");
                                    return i18n.tr("Uploading %1 of %2").arg(backupManager.uploadedCount + backupManager.duplicateCount + backupManager.failedCount + 1).arg(backupManager.totalFiles);
                                }
                                font.pixelSize: units.gu(1.6)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                                width: parent.width - percentLabel.width - units.gu(2)
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: units.dp(6)
                            radius: units.dp(3)
                            color: "#E5E5EA"

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                width: {
                                    var v = backupManager.phase === "uploading"
                                        ? (backupManager.overallPercent + backupManager.currentPercent / Math.max(backupManager.totalFiles, 1)) / 100
                                        : 0;
                                    if (v < 0) v = 0;
                                    if (v > 1) v = 1;
                                    return parent.width * v;
                                }
                                color: Theme.primary
                            }
                        }

                        Label {
                            text: {
                                if (backupManager.phase === "uploading" && backupManager.currentFile) {
                                    return backupManager.currentFile;
                                }
                                return "";
                            }
                            font.pixelSize: units.gu(1.4)
                            color: Theme.textMuted
                            elide: Text.ElideMiddle
                            width: parent.width
                            visible: text.length > 0
                        }

                        Row {
                            width: parent.width
                            spacing: units.gu(2)

                            Label {
                                text: i18n.tr("Uploaded") + ": " + backupManager.uploadedCount
                                font.pixelSize: units.gu(1.4)
                                color: "#4CAF50"
                            }
                            Label {
                                text: i18n.tr("Duplicates") + ": " + backupManager.duplicateCount
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                            }
                            Label {
                                text: i18n.tr("Failed") + ": " + backupManager.failedCount
                                font.pixelSize: units.gu(1.4)
                                color: "#d9534f"
                            }
                        }

                        // Per-file upload list
                        ListView {
                            width: parent.width
                            height: units.gu(8)
                            clip: true
                            visible: backupManager.uploadItems.length > 0
                            model: backupManager.uploadItems
                            spacing: 0

                            delegate: Rectangle {
                                width: parent.width
                                height: units.gu(3.2)
                                color: "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: units.gu(1)
                                    anchors.rightMargin: units.gu(1)
                                    spacing: units.gu(1.5)

                                    Icon {
                                        width: units.gu(1.8)
                                        height: units.gu(1.8)
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.status === "failed" ? "sync-error"
                                            : (modelData.status === "uploading" ? "transfer-progress-upload"
                                            : "sync")
                                        color: modelData.status === "failed" ? "#d9534f"
                                            : (modelData.status === "done" ? "#4CAF50"
                                            : (modelData.status === "duplicate" ? Theme.textMuted : Theme.primary))
                                    }

                                    Label {
                                        text: modelData.name
                                        font.pixelSize: units.gu(1.3)
                                        color: Theme.textDark
                                        elide: Text.ElideMiddle
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - units.gu(14)
                                    }

                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: units.gu(6)
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                        text: {
                                            if (modelData.status === "uploading") return modelData.percent + "%";
                                            if (modelData.status === "done") return i18n.tr("Done");
                                            if (modelData.status === "duplicate") return i18n.tr("On server");
                                            return i18n.tr("Error");
                                        }
                                        font.pixelSize: units.gu(1.3)
                                        color: modelData.status === "failed" ? "#d9534f"
                                            : (modelData.status === "done" ? "#4CAF50" : Theme.textMuted)
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: units.gu(3)
                            visible: backupManager.phase === "uploading"

                            Label {
                                text: backupManager.speedText
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textDark
                            }
                            Label {
                                text: i18n.tr("ETA") + " " + backupManager.etaText
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textDark
                            }
                        }

                        Rectangle {
                            width: units.gu(12)
                            height: units.gu(4)
                            radius: units.gu(2)
                            color: "#d9534f"
                            anchors.horizontalCenter: parent.horizontalCenter

                            Label {
                                anchors.centerIn: parent
                                text: i18n.tr("Stop")
                                color: "#ffffff"
                                font.pixelSize: units.gu(1.6)
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: backupManager.stopBackup()
                            }
                        }
                    }
                }

                // Re-check server button
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(7.5)
                    radius: units.gu(1)
                    color: verifyMouse.pressed ? "#F5F5F7" : Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)
                    opacity: backupManager.running ? 0.5 : 1.0

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2)
                        }
                        spacing: units.gu(2)

                        Icon {
                            name: "view-refresh"
                            width: units.gu(2.6)
                            height: units.gu(2.6)
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - units.gu(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: i18n.tr("Re-check backups")
                                font.pixelSize: units.gu(1.9)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                            }
                            Label {
                                text: backupManager.reverifying
                                    ? i18n.tr("Verifying... %1 of %2").arg(backupManager.reverifyDone).arg(backupManager.reverifyTotal)
                                    : i18n.tr("Check which backed up files are still on the server")
                                font.pixelSize: units.gu(1.4)
                                color: backupManager.reverifying ? Theme.primary : Theme.textMuted
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Icon {
                            name: "next"
                            width: units.gu(2)
                            height: units.gu(2)
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: verifyMouse
                        anchors.fill: parent
                        onClicked: backupManager.reverifyBackup()
                    }
                }

                // Free up space
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(7.5)
                    radius: units.gu(1)
                    color: freeSpaceMouse.pressed ? "#F5F5F7" : Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)

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
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - units.gu(8)
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

                        Icon {
                            name: "next"
                            width: units.gu(2)
                            height: units.gu(2)
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
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

                // Back up now button
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(5.5)
                    radius: units.gu(2.75)
                    color: (backupManager.enabled && !backupManager.running) ? Theme.primary : Theme.textSubtle
                    visible: !backupManager.running

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Back up now")
                        color: "#ffffff"
                        font.pixelSize: units.gu(2)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!backupManager.enabled) {
                                mainView.showToast(i18n.tr("Backup is disabled. Turn it on first."), true, false);
                            } else {
                                backupManager.startBackup();
                            }
                        }
                    }
                }

                // Sync history
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(7)
                    radius: units.gu(1)
                    color: Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(2)
                        }
                        spacing: units.gu(2)

                        Column {
                            width: parent.width - units.gu(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: i18n.tr("Sync Database")
                                font.pixelSize: units.gu(1.9)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                            }
                            Label {
                                text: i18n.tr("%1 items recorded in sync history").arg(syncStats.count)
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                            }
                        }

                        Rectangle {
                            width: units.gu(10)
                            height: units.gu(4)
                            radius: units.gu(2)
                            color: "#d9534f"
                            anchors.verticalCenter: parent.verticalCenter

                            Label {
                                anchors.centerIn: parent
                                text: i18n.tr("Reset")
                                color: "#ffffff"
                                font.pixelSize: units.gu(1.5)
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Storage.clearAllSyncedRecords();
                                    syncStats = Storage.getSyncedStats();
                                    backupManager.refreshLocalFiles();
                                    mainView.showToast(i18n.tr("Sync history reset"), false, true);
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: units.gu(2) }
            }
        }
    }
}
