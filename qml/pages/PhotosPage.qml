import QtQuick 2.9
import Ubuntu.Components 1.3
import Ubuntu.Components.Popups 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi
import "../js/Storage.js" as Storage

Item {
    id: photosTab
    anchors.fill: parent

    property var photos: []
    property var folderList: []
    property var folderTree: null
    property bool isSortAsc: false
    property alias timelineView: timelineView
    property bool backupEnabled: backupManager.enabled
    property bool bannerDismissed: false
    property bool showBackupBanner: !bannerDismissed && (!backupManager.enabled
        || (backupManager.enabled && backupManager.selRemaining > 0 && !backupManager.running))

    Component.onCompleted: {
        loadPhotos();
    }

    Connections {
        target: backupManager
        onLocalListRefreshed: {
            updateDisplayList();
        }
    }

    Connections {
        target: mainView
        onItemDeleted: {
            var oldLen = photosTab.photos.length;
            photosTab.photos = photosTab.photos.filter(function(p) { return p.id !== itemId; });
            updateDisplayList();
            if (mainView.viewerPhotoList === timelineView.photos) {
                mainView.viewerPhotoList = timelineView.photos;
            }
        }
        onMemoryCacheCleared: {
            photosTab.photos = [];
            loadPhotos();
        }
    }

    // Merges server items with the local device files: local files that are
    // already backed up are shown once (server item with a green badge);
    // not-yet-backed-up local files are shown as separate cells.
    function updateDisplayList() {
        try {
            var serverItems = photosTab.photos.slice();
            // Drop stale local flags from previous merges (e.g. after "free
            // up space" deleted the files): they are re-applied below only
            // for files that actually exist on the device right now
            for (var fi = 0; fi < serverItems.length; fi++) {
                if (serverItems[fi].isLocal) {
                    serverItems[fi].isLocal = false;
                    serverItems[fi].isBackedUp = false;
                    serverItems[fi].localPath = "";
                    serverItems[fi].remoteThumbId = "";
                }
            }
            var localItems = backupManager.localFiles.slice();

            var serverById = {};
            var serverByName = {};
            for (var i = 0; i < serverItems.length; i++) {
                serverById[serverItems[i].id] = serverItems[i];
                var fn = (serverItems[i].filename || "").toLowerCase();
                if (fn && !serverByName[fn]) serverByName[fn] = serverItems[i];
            }

            var syncedMap = Storage.getSyncedPathMap(); // localPath -> remote asset id
            var usedServerIds = {};
            var toShow = [];

            for (var j = 0; j < localItems.length; j++) {
                var local = localItems[j];
                var remoteId = syncedMap[local.localPath];
                var matched = null;
                if (remoteId && serverById[remoteId]) {
                    matched = serverById[remoteId];
                } else if (!matched) {
                    var n = (local.filename || "").toLowerCase();
                    if (n && serverByName[n]) matched = serverByName[n];
                }

                if (matched) {
                    // Exists on server and locally: show once, with green badge
                    matched.isLocal = true;
                    matched.localPath = local.localPath;
                    matched.isBackedUp = true;
                    matched.remoteThumbId = remoteId || matched.id;
                    // Use the device file's timestamp: the server stores
                    // EXIF wall-clock as a plain UTC epoch (no timezone),
                    // which displays shifted on the device
                    matched.time = local.time;
                    usedServerIds[matched.id] = true;
                    toShow.push(matched);
                } else if (remoteId) {
                    // Backed up, but server item not in the loaded pages yet:
                    // still show the server thumbnail for local videos via remote id
                    local.isBackedUp = true;
                    local.remoteThumbId = remoteId;
                    toShow.push(local);
                } else {
                    toShow.push(local);
                }
            }

            for (var k = 0; k < serverItems.length; k++) {
                if (!usedServerIds[serverItems[k].id]) toShow.push(serverItems[k]);
            }

            toShow.sort(function(a, b) { return (b.time || 0) - (a.time || 0); });
            timelineView.photos = toShow;
        } catch(e) {
            console.log("updateDisplayList error:", e);
            timelineView.photos = photosTab.photos;
        }
    }

    function loadPhotos() {
        if (!mainView.sid) return;
        mainView.showLoading(i18n.tr("Loading photos..."));
        SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 500, function(err, data) {
            mainView.hideLoading();
            if (err) {
                if (!mainView.handleApiError(err)) {
                    mainView.showErrorDialog(i18n.tr("Connection Error"), err.message);
                }
            } else if (data && data.list) {
                photosTab.photos = photosTab.isSortAsc ? data.list.slice().reverse() : data.list;
                updateDisplayList();
            }
        });
        backupManager.refreshLocalFiles();
    }

    function loadFolders() {
        if (!mainView.sid) return;
        mainView.showLoading(i18n.tr("Loading folders..."));
        SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 2000, function(err, data) {
            if (err) {
                mainView.hideLoading();
                if (!mainView.handleApiError(err)) {
                    mainView.showErrorDialog(i18n.tr("Connection Error"), err.message);
                }
                return;
            }
            if (!data || !data.list || data.list.length === 0) {
                mainView.hideLoading();
                photosTab.folderList = [];
                return;
            }

            var photos = data.list;
            var folderMap = {};
            for (var i = 0; i < photos.length; i++) {
                var fid = photos[i].folder_id;
                if (!fid) continue;
                if (!folderMap[fid]) {
                    folderMap[fid] = { id: fid, count: 0 };
                }
                folderMap[fid].count++;
            }

            var folderIds = Object.keys(folderMap);
            if (folderIds.length === 0) {
                mainView.hideLoading();
                photosTab.folderList = [];
                return;
            }

            var fetched = 0;
            var foldersWithNames = [];
            for (var j = 0; j < folderIds.length; j++) {
                (function(fId, fCount) {
                    SynoApi.getFolderById(mainView.serverUrl, mainView.sid, mainView.synotoken, fId, function(fErr, folderObj) {
                        fetched++;
                        if (!fErr && folderObj) {
                            foldersWithNames.push({
                                id: fId,
                                name: folderObj.name || "Folder #" + fId,
                                count: fCount
                            });
                        } else {
                            foldersWithNames.push({
                                id: fId,
                                name: "/Folder #" + fId,
                                count: fCount
                            });
                        }
                        if (fetched >= folderIds.length) {
                            var tree = buildFolderTree(foldersWithNames);
                            photosTab.folderTree = tree;
                            var rootItems = [];
                            for (var key in tree.children) {
                                rootItems.push(tree.children[key]);
                            }
                            rootItems.sort(function(a, b) { return a.name.localeCompare(b.name); });
                            photosTab.folderList = rootItems;
                            mainView.hideLoading();
                        }
                    });
                })(parseInt(folderIds[j]), folderMap[folderIds[j]].count);
            }
        });
    }

    function buildFolderTree(folders) {
        var root = { name: "/", children: {}, total_count: 0, item_count: 0 };

        for (var i = 0; i < folders.length; i++) {
            var f = folders[i];
            var clean = f.name.replace(/^\/+/, "");
            var parts = clean.split("/");
            var node = root;
            for (var p = 0; p < parts.length; p++) {
                var seg = parts[p];
                var fullSoFar = "/" + parts.slice(0, p + 1).join("/");
                if (!node.children[seg]) {
                    node.children[seg] = {
                        name: seg,
                        fullName: fullSoFar,
                        folderId: null,
                        item_count: 0,
                        total_count: 0,
                        isFolder: true,
                        children: {}
                    };
                }
                node = node.children[seg];
            }
            node.folderId = f.id;
            node.item_count = f.count;
        }

        function computeTotal(node) {
            var total = node.item_count || 0;
            for (var key in node.children) {
                total += computeTotal(node.children[key]);
            }
            node.total_count = total;
            node.hasChildren = Object.keys(node.children).length > 0;
            return total;
        }
        computeTotal(root);

        function flattenChildren(node) {
            var arr = [];
            var keys = Object.keys(node.children);
            keys.sort();
            for (var k = 0; k < keys.length; k++) {
                var child = node.children[keys[k]];
                child.displayName = child.name;
                child.childrenArr = flattenChildren(child);
                arr.push(child);
            }
            return arr;
        }
        root.childrenArr = flattenChildren(root);
        return root;
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Photos")
            showSearch: true
            showRefresh: true
            showUploads: true
            uploadsBadge: {
                var n = 0;
                var items = backupManager.uploadItems;
                for (var i = 0; i < items.length; i++) {
                    var s = items[i].status;
                    if (s === "failed" || s === "queued" || s === "uploading") n++;
                }
                return n > 0 ? String(n) : "";
            }
            onRefreshClicked: {
                if (timelineView.filterIndex === 3) {
                    loadFolders();
                } else {
                    loadPhotos();
                }
            }
            onSearchClicked: {
                pageStack.push(Qt.resolvedUrl("SearchPage.qml"));
            }
            onUploadsClicked: {
                pageStack.push(Qt.resolvedUrl("UploadsPage.qml"));
            }
        }

        Item {
            width: parent.width
            height: parent.height - units.gu(7)

            // Folders Grid View
            GridView {
                id: folderGridView
                anchors.fill: parent
                anchors.topMargin: (photosTab.showBackupBanner && !timelineView.isSelectionMode) ? units.gu(15) : units.gu(1.5)
                anchors.leftMargin: units.gu(1.5)
                anchors.rightMargin: units.gu(1.5)
                visible: timelineView.filterIndex === 3 && photosTab.folderList.length > 0
                cellWidth: width / 2
                cellHeight: units.gu(20)
                model: photosTab.folderList
                clip: true

                delegate: Item {
                    width: folderGridView.cellWidth
                    height: folderGridView.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: units.gu(0.8)
                        radius: units.gu(1.2)
                        color: "#F5F6F8"
                        border.color: "#E5E7EB"
                        border.width: units.dp(1)

                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(1)

                            Rectangle {
                                width: units.gu(8)
                                height: units.gu(8)
                                radius: units.gu(1.5)
                                color: "#E5E7EB"
                                anchors.horizontalCenter: parent.horizontalCenter

                                Icon {
                                    name: "folder"
                                    width: units.gu(4)
                                    height: units.gu(4)
                                    color: Theme.textMuted
                                    anchors.centerIn: parent
                                }
                            }

                            Label {
                                text: modelData.displayName || modelData.name || i18n.tr("Unknown Folder")
                                font.pixelSize: units.gu(1.6)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - units.gu(2)
                                elide: Text.ElideMiddle
                                horizontalAlignment: Text.AlignHCenter
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }

                            Label {
                                text: {
                                    var cnt = modelData.total_count || modelData.item_count;
                                    if (!cnt || cnt <= 0) return i18n.tr("Empty folder");
                                    return i18n.tr("%1 items").arg(cnt);
                                }
                                font.pixelSize: units.gu(1.4)
                                color: Theme.textMuted
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                pageStack.push(Qt.resolvedUrl("AlbumDetailPage.qml"), { albumData: modelData });
                            }
                        }
                    }
                }
            }

            // Empty state for Folders
            Column {
                anchors.centerIn: parent
                visible: timelineView.filterIndex === 3 && photosTab.folderList.length === 0 && !mainView.loading
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
                    text: i18n.tr("No folders found on Synology NAS")
                    font.pixelSize: units.gu(1.8)
                    color: Theme.textMuted
                }
            }

            // Timeline View (reused component)
            PhotoTimelineView {
                id: timelineView
                anchors.fill: parent
                visible: true
                photos: photosTab.photos
                showFilterPill: true
                enableFolders: true
                showBackupBadges: true
                topContentPadding: (photosTab.showBackupBanner && !timelineView.isSelectionMode) ? units.gu(14) : 0
                onRefreshRequested: loadPhotos()
                onLoadFoldersRequested: loadFolders()
            }

            // Backup Banner (suspended OR pending files)
            Rectangle {
                id: backupBanner
                anchors.top: parent.top
                anchors.topMargin: units.gu(1)
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - units.gu(4)
                height: units.gu(13)
                radius: units.gu(1)
                color: "#F4F5F7"
                visible: photosTab.showBackupBanner && !timelineView.isSelectionMode
                z: 10

                Row {
                    id: bannerContentRow
                    anchors.fill: parent
                    anchors.margins: units.gu(2)
                    spacing: units.gu(2)

                    Column {
                        width: parent.width - closeBtn.width - units.gu(2)
                        spacing: units.gu(1.5)

                        Label {
                            text: backupManager.enabled
                                ? i18n.tr("%1 files waiting for backup").arg(backupManager.selRemaining)
                                : i18n.tr("Photo Backup Suspended")
                            font.pixelSize: units.gu(1.6)
                            font.weight: Font.DemiBold
                            color: Theme.textDark
                        }

                        Label {
                            text: backupManager.enabled
                                ? i18n.tr("Back up now to upload them to the server.")
                                : i18n.tr("Turn on to continue backing up photos.")
                            font.pixelSize: units.gu(1.4)
                            color: Theme.textMuted
                        }

                        Rectangle {
                            width: units.gu(12)
                            height: units.gu(3.5)
                            radius: units.gu(1.75)
                            color: "#333333"

                            Label {
                                anchors.centerIn: parent
                                text: backupManager.enabled ? i18n.tr("Back up now") : i18n.tr("Set Up Now")
                                color: "#ffffff"
                                font.pixelSize: units.gu(1.4)
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (backupManager.enabled) {
                                        backupManager.startBackup();
                                    } else {
                                        pageStack.push(Qt.resolvedUrl("BackupSettingsPage.qml"));
                                    }
                                }
                            }
                        }
                    }

                    Icon {
                        id: closeBtn
                        name: "close"
                        width: units.gu(2)
                        height: units.gu(2)
                        color: Theme.textMuted
                        anchors.top: parent.top

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -units.gu(1)
                            onClicked: {
                                photosTab.bannerDismissed = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
