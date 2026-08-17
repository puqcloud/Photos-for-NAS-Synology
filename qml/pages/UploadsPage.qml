import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme

Page {
    id: uploadsPage

    header: Item {
        width: uploadsPage.width
        height: 0
        visible: false
    }

    property int retryCount: 0

    property bool hasFailedOrQueued: {
        var v = uploadsPage.retryCount;
        var items = backupManager.uploadItems;
        for (var i = 0; i < items.length; i++) {
            if (items[i].status === "failed" || items[i].status === "queued") return true;
        }
        return false;
    }

    property bool hasQueued: {
        var v = uploadsPage.retryCount;
        var items = backupManager.uploadItems;
        for (var i = 0; i < items.length; i++) {
            if (items[i].status === "queued" || items[i].status === "uploading") return true;
        }
        return false;
    }

    property bool hasFinished: {
        var v = uploadsPage.retryCount;
        var items = backupManager.uploadItems;
        for (var i = 0; i < items.length; i++) {
            if (items[i].status === "done" || items[i].status === "duplicate") return true;
        }
        return false;
    }

    Connections {
        target: backupManager
        onBackupFinished: retryCount++
        onBackupStarted: retryCount++
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Uploads")
            showBack: true
            onBackClicked: pageStack.pop()
        }

        Item {
            width: parent.width
            height: parent.height - units.gu(6)

            // Top area (status / stop / retry)
            Column {
                id: topCol
                anchors.top: parent.top
                anchors.topMargin: units.gu(1.5)
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: units.gu(1.5)

                // Status card while running
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(13)
                    radius: units.gu(1)
                    color: Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)
                    visible: backupManager.running

                    Column {
                        anchors.fill: parent
                        anchors.margins: units.gu(1.5)
                        spacing: units.gu(1.2)

                        Item {
                            width: parent.width
                            height: Math.max(statusLabel.implicitHeight, percentLabel.implicitHeight)

                            Label {
                                id: statusLabel
                                text: {
                                    if (backupManager.phase === "scanning") return i18n.tr("Scanning device...");
                                    return i18n.tr("Uploading %1 of %2").arg(backupManager.uploadedCount + backupManager.duplicateCount + backupManager.failedCount + 1).arg(backupManager.totalFiles);
                                }
                                font.pixelSize: units.gu(1.5)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                                anchors.left: parent.left
                                anchors.right: percentLabel.left
                                anchors.rightMargin: units.gu(1)
                                elide: Text.ElideRight
                            }

                            Label {
                                id: percentLabel
                                anchors.right: parent.right
                                text: i18n.tr("%1%").arg(Math.round(backupManager.phase === "uploading"
                                    ? backupManager.overallPercent + backupManager.currentPercent / Math.max(backupManager.totalFiles, 1)
                                    : 0))
                                font.pixelSize: units.gu(1.5)
                                font.weight: Font.DemiBold
                                color: Theme.primary
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

                        Row {
                            width: parent.width
                            spacing: units.gu(3)
                            visible: backupManager.phase === "uploading"

                            Label {
                                text: backupManager.speedText
                                font.pixelSize: units.gu(1.3)
                                color: Theme.textDark
                            }
                            Label {
                                text: i18n.tr("ETA") + " " + backupManager.etaText
                                font.pixelSize: units.gu(1.3)
                                color: Theme.textDark
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: units.gu(2)
                            visible: backupManager.phase === "uploading"

                            Label {
                                text: i18n.tr("OK") + ": " + backupManager.uploadedCount
                                font.pixelSize: units.gu(1.3)
                                color: "#4CAF50"
                            }
                            Label {
                                text: i18n.tr("Failed") + ": " + backupManager.failedCount
                                font.pixelSize: units.gu(1.3)
                                color: "#d9534f"
                            }
                        }
                    }
                }

                // Stop button while running
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(4.5)
                    radius: units.gu(2.25)
                    color: "#d9534f"
                    visible: backupManager.running

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Stop")
                        color: "#ffffff"
                        font.pixelSize: units.gu(1.7)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: backupManager.stopBackup()
                    }
                }

                // Resume / Retry button
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(4.5)
                    radius: units.gu(2.25)
                    color: uploadsPage.hasFailedOrQueued ? Theme.primary : Theme.textSubtle
                    visible: !backupManager.running && backupManager.uploadItems.length > 0

                    Label {
                        anchors.centerIn: parent
                        text: uploadsPage.hasQueued ? i18n.tr("Resume uploads") : i18n.tr("Retry failed")
                        color: "#ffffff"
                        font.pixelSize: units.gu(1.7)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: backupManager.retryFailed()
                    }
                }

                // Back up now (when queue is empty)
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(4.5)
                    radius: units.gu(2.25)
                    color: backupManager.enabled ? Theme.primary : Theme.textSubtle
                    visible: !backupManager.running && backupManager.uploadItems.length === 0

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Back up now")
                        color: "#ffffff"
                        font.pixelSize: units.gu(1.7)
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

                // Clear finished button
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(4.5)
                    radius: units.gu(2.25)
                    color: uploadsPage.hasFinished ? "#333333" : Theme.textSubtle
                    visible: !backupManager.running && backupManager.uploadItems.length > 0

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Clear finished")
                        color: "#ffffff"
                        font.pixelSize: units.gu(1.7)
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            backupManager.clearFinishedUploads();
                            mainView.showToast(i18n.tr("Upload list cleaned"), false, true);
                        }
                    }
                }

                // Free up space
                Rectangle {
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: units.gu(5)
                    radius: units.gu(1)
                    color: freeSpaceMouse.pressed ? "#F5F5F7" : Theme.cardBackground
                    border.color: Theme.divider
                    border.width: units.dp(1)
                    visible: !backupManager.running

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(1.5)
                        }
                        spacing: units.gu(1.5)

                        Icon {
                            name: "delete"
                            width: units.gu(2.2)
                            height: units.gu(2.2)
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - units.gu(8)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: i18n.tr("Free Up Space")
                                font.pixelSize: units.gu(1.6)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                            }
                            Label {
                                text: backupManager.clearableCount > 0
                                    ? i18n.tr("%1 backed up files on device • %2").arg(backupManager.clearableCount).arg(backupManager.clearableSizeText)
                                    : i18n.tr("Delete local copies of backed up files")
                                font.pixelSize: units.gu(1.3)
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
            }

            // Queue list
            ListView {
                id: uploadQueueList
                anchors.top: topCol.bottom
                anchors.topMargin: units.gu(1)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                model: backupManager.uploadItems
                visible: backupManager.uploadItems.length > 0

                delegate: Rectangle {
                    width: uploadQueueList.width
                    height: units.gu(5.5)
                    color: "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: units.gu(1.5)
                        }
                        spacing: units.gu(1.5)

                        Icon {
                            width: units.gu(2.2)
                            height: units.gu(2.2)
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.status === "failed" ? "sync-error"
                                : (modelData.status === "uploading" ? "transfer-progress-upload" : "sync")
                            color: modelData.status === "failed" ? "#d9534f"
                                : (modelData.status === "done" ? "#4CAF50"
                                : (modelData.status === "duplicate" ? Theme.textMuted : Theme.primary))
                        }

                        Column {
                            width: parent.width - units.gu(20)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: modelData.name
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textDark
                                elide: Text.ElideMiddle
                                width: parent.width
                            }
                            Label {
                                text: modelData.status === "failed" ? (modelData.error || i18n.tr("Error")) : ""
                                font.pixelSize: units.gu(1.2)
                                color: "#d9534f"
                                elide: Text.ElideRight
                                width: parent.width
                                visible: text.length > 0
                            }
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(6.5)
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: {
                                if (modelData.status === "uploading") return modelData.percent + "%";
                                if (modelData.status === "done") return i18n.tr("Done");
                                if (modelData.status === "duplicate") return i18n.tr("On server");
                                if (modelData.status === "failed") return i18n.tr("Error");
                                return i18n.tr("Queued");
                            }
                            font.pixelSize: units.gu(1.3)
                            color: modelData.status === "failed" ? "#d9534f"
                                : (modelData.status === "done" ? "#4CAF50" : Theme.textMuted)
                        }

                        // Per-item retry
                        Rectangle {
                            width: units.gu(4)
                            height: units.gu(3)
                            radius: units.gu(1.5)
                            color: retryItemMouse.pressed ? Theme.primaryDark : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.status === "failed"

                            Label {
                                anchors.centerIn: parent
                                text: "↻"
                                color: "#ffffff"
                                font.pixelSize: units.gu(1.6)
                            }

                            MouseArea {
                                id: retryItemMouse
                                anchors.fill: parent
                                onClicked: backupManager.retryOne(modelData.path)
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width - units.gu(3)
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: units.dp(1)
                        color: Theme.divider
                    }
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                visible: backupManager.uploadItems.length === 0
                spacing: units.gu(1.5)

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "transfer-progress-upload"
                    width: units.gu(6)
                    height: units.gu(6)
                    color: Theme.textMuted
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: i18n.tr("No uploads yet")
                    font.pixelSize: units.gu(1.8)
                    color: Theme.textMuted
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: i18n.tr("Start backup in Settings → Backup to see the queue here")
                    font.pixelSize: units.gu(1.3)
                    color: Theme.textSubtle
                }
            }
        }
    }
}
