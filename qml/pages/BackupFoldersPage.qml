import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/Storage.js" as Storage

Page {
    id: backupFoldersPage

    header: Item {
        width: backupFoldersPage.width
        height: 0
        visible: false
    }

    property var selectedFolders: Storage.getBackupFolders()
    property bool selectAllChecked: selectedFolders.indexOf("*") !== -1
    property var folderGroups: []
    property bool scanning: false
    property bool scanFailed: false
    property bool engineMissing: false
    property bool noReadAccess: false

    Component.onCompleted: {
        refreshFolders();
    }

    // The scan result may be stale or the device may have gained/lost
    // files, so always trigger a fresh scan when the page opens; the
    // cached list (if any) is shown instantly while scanning.
    function refreshFolders() {
        if (typeof backupEngine === "undefined") {
            // Old build without the C++ engine: nothing to scan
            engineMissing = true;
            scanFailed = true;
            return;
        }
        engineMissing = false;
        if (backupManager.folderGroups.length > 0) {
            folderGroups = backupManager.folderGroups;
        }
        scanning = true;
        scanFailed = false;
        backupEngine.scanMedia();
        scanWatchdog.restart();
    }

    // If the scan never reports back (e.g. no read access to the media
    // folders), surface a failure state instead of an endless spinner.
    Timer {
        id: scanWatchdog
        interval: 10000
        repeat: false
        onTriggered: {
            backupFoldersPage.scanning = false;
            backupFoldersPage.scanFailed = true;
        }
    }

    function toggleFolder(name) {
        var list = selectedFolders.slice();
        var idx = list.indexOf(name);
        if (idx === -1) {
            list.push(name);
        } else {
            list.splice(idx, 1);
        }
        selectedFolders = list;
        saveSelection();
    }

    function toggleSelectAll() {
        if (selectAllChecked) {
            selectedFolders = [];
        } else {
            selectedFolders = ["*"];
        }
        selectAllChecked = selectedFolders.indexOf("*") !== -1;
        saveSelection();
    }

    function saveSelection() {
        Storage.setBackupFolders(selectedFolders);
        backupManager.refreshLocalFiles();
    }

    function emptyTitle() {
        if (engineMissing) return i18n.tr("Backup engine not available - update the app");
        if (noReadAccess) return i18n.tr("No read access to media folders");
        if (scanFailed) return i18n.tr("Scan failed - no read access to media folders");
        return i18n.tr("No folders found in Pictures");
    }

    function emptyIsError() {
        return engineMissing || noReadAccess || scanFailed;
    }

    Connections {
        target: typeof backupEngine !== "undefined" ? backupEngine : null
        onMediaScanStatus: {
            backupFoldersPage.noReadAccess =
                (picturesExists && !picturesReadable) || (videosExists && !videosReadable);
        }
        onMediaScanFinished: {
            scanWatchdog.stop();
            scanning = false;
            scanFailed = false;
            folderGroups = folders;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Backup Folders")
            showBack: true
            onBackClicked: pageStack.pop()
        }

        Item {
            width: parent.width
            height: parent.height - units.gu(6)

            // Select all row
            Rectangle {
                id: selectAllRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: units.gu(6)
                color: "transparent"

                Row {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: units.gu(2)
                    }
                    spacing: units.gu(2)

                    Switch {
                        id: selectAllSwitch
                        checked: backupFoldersPage.selectAllChecked
                        anchors.verticalCenter: parent.verticalCenter
                        onCheckedChanged: {
                            if (checked !== backupFoldersPage.selectAllChecked) {
                                backupFoldersPage.toggleSelectAll();
                            }
                        }
                    }

                    Label {
                        text: i18n.tr("All folders")
                        font.pixelSize: units.gu(1.9)
                        font.weight: Font.DemiBold
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: units.dp(1)
                    color: Theme.divider
                }
            }

            // Section label
            Label {
                id: sectionLabel
                anchors.top: selectAllRow.bottom
                anchors.topMargin: units.gu(1.5)
                anchors.left: parent.left
                anchors.leftMargin: units.gu(2)
                text: i18n.tr("Folders:") + " " + backupFoldersPage.folderGroups.length
                font.pixelSize: units.gu(1.5)
                color: Theme.textMuted
            }

            // Folder list
            ListView {
                id: folderListView
                anchors.top: sectionLabel.bottom
                anchors.topMargin: units.gu(0.5)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                model: backupFoldersPage.folderGroups
                enabled: !backupFoldersPage.selectAllChecked
                visible: backupFoldersPage.folderGroups.length > 0

                delegate: Rectangle {
                    width: parent.width
                    height: units.gu(6.5)
                    color: "transparent"

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
                            width: units.gu(2.8)
                            height: units.gu(2.8)
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - units.gu(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.dp(2)

                            Label {
                                text: modelData.name
                                font.pixelSize: units.gu(1.8)
                                color: Theme.textDark
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Label {
                                text: (modelData.root || "") + " • " + i18n.tr("%1 items").arg(modelData.fileCount)
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                            }
                        }

                        Switch {
                            checked: backupFoldersPage.selectedFolders.indexOf(modelData.name) !== -1
                            anchors.verticalCenter: parent.verticalCenter
                            onCheckedChanged: {
                                var isNow = backupFoldersPage.selectedFolders.indexOf(modelData.name) !== -1;
                                if (checked !== isNow) {
                                    backupFoldersPage.toggleFolder(modelData.name);
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width - units.gu(4)
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: units.dp(1)
                        color: Theme.divider
                    }
                }
            }

            // Scanning indicator
            Column {
                anchors.centerIn: parent
                visible: backupFoldersPage.folderGroups.length === 0 && backupFoldersPage.scanning
                spacing: units.gu(1.5)

                ActivityIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: true
                }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                visible: backupFoldersPage.folderGroups.length === 0 && !backupFoldersPage.scanning
                spacing: units.gu(1.5)

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "folder"
                    width: units.gu(6)
                    height: units.gu(6)
                    color: Theme.textMuted
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: backupFoldersPage.emptyTitle()
                    font.pixelSize: units.gu(1.8)
                    color: backupFoldersPage.emptyIsError() ? "#d9534f" : Theme.textMuted
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: typeof backupEngine !== "undefined" ? backupEngine.picturesPath() : ""
                    font.pixelSize: units.gu(1.3)
                    color: Theme.textSubtle
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(12)
                    height: units.gu(4)
                    radius: units.gu(2)
                    color: Theme.primary

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Rescan")
                        color: "#ffffff"
                        font.pixelSize: units.gu(1.6)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            backupFoldersPage.refreshFolders();
                        }
                    }
                }
            }
        }
    }
}
