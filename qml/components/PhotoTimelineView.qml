import QtQuick 2.9
import Ubuntu.Components 1.3
import Ubuntu.Components.Popups 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi
import "../js/Storage.js" as Storage

Item {
    id: root
    
    property var photos: []
    property bool isSelectionMode: false
    property var selectedIds: []
    property bool showFilterPill: true
    property bool enableFolders: false
    property bool showBackupBadges: false
    property var folderList: []
    property int filterIndex: filterPill.selectedIndex
    
    property var groupedSections: []
    
    property int columnCount: {
        if (filterPill.selectedIndex === 0) return Math.max(6, Math.floor(root.width / units.gu(5.5)));
        if (filterPill.selectedIndex === 1) return Math.max(4, Math.floor(root.width / units.gu(8.5)));
        if (filterPill.selectedIndex === 2) return Math.max(3, Math.floor(root.width / units.gu(12)));
        return 2;
    }
    property real itemSpacing: units.dp(2)

    property bool isReadOnly: false
    property string passphrase: ""
    property int albumId: -1

    signal refreshRequested()
    signal loadFoldersRequested()

    function toggleSelection(id) {
        var idx = selectedIds.indexOf(id);
        var newList = selectedIds.slice();
        if (idx === -1) {
            newList.push(id);
        } else {
            newList.splice(idx, 1);
        }
        selectedIds = newList;
        if (selectedIds.length === 0) {
            isSelectionMode = false;
        }
    }

    function clearSelection() {
        selectedIds = [];
        isSelectionMode = false;
    }

    function updateGroupedSections() {
        var mode = filterPill.selectedIndex;
        if (mode === 3) return;
        root.groupedSections = buildChronologicalGroups(root.photos, mode);
    }

    function buildChronologicalGroups(items, mode) {
        if (!items || items.length === 0) return [];

        var currentYear = new Date().getFullYear();
        var monthNames = [
            i18n.tr("January"), i18n.tr("February"), i18n.tr("March"),
            i18n.tr("April"), i18n.tr("May"), i18n.tr("June"),
            i18n.tr("July"), i18n.tr("August"), i18n.tr("September"),
            i18n.tr("October"), i18n.tr("November"), i18n.tr("December")
        ];

        var groupMap = {};
        var groupOrder = [];

        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var p = SynoApi.dateParts(item);

            var key = "";
            var title = "";
            var subtitle = "";

            if (mode === 0) {
                key = String(p.year);
                title = key;
            } else if (mode === 1) {
                key = p.year + "-" + p.month;
                title = monthNames[p.month];
                if (p.year !== currentYear) {
                    title += " " + p.year;
                }
            } else {
                key = p.year + "-" + p.month + "-" + p.date;
                title = p.date + " " + monthNames[p.month];
                if (p.year !== currentYear) {
                    title += " " + p.year;
                }
                var days = [i18n.tr("Sunday"), i18n.tr("Monday"), i18n.tr("Tuesday"), i18n.tr("Wednesday"), i18n.tr("Thursday"), i18n.tr("Friday"), i18n.tr("Saturday")];
                subtitle = days[p.day];
            }

            if (!groupMap[key]) {
                groupMap[key] = { title: title, subtitle: subtitle, items: [] };
                groupOrder.push(key);
            }
            groupMap[key].items.push(item);
        }

        var result = [];
        for (var j = 0; j < groupOrder.length; j++) {
            result.push(groupMap[groupOrder[j]]);
        }
        return result;
    }

    onPhotosChanged: updateGroupedSections()
    Component.onCompleted: updateGroupedSections()

    property real topContentPadding: 0

    Item {
        anchors.fill: parent

        // 1. Timeline List View
        ListView {
            id: timelineListView
            anchors.fill: parent
            visible: filterPill.selectedIndex !== 3 && root.groupedSections.length > 0
            model: root.groupedSections
            clip: true
            cacheBuffer: Math.max(height * 2, units.gu(400))
            boundsBehavior: Flickable.StopAtBounds

            header: Item {
                width: timelineListView.width
                height: root.topContentPadding + (root.isSelectionMode ? units.gu(2) : units.gu(1))
            }

            delegate: Item {
                width: timelineListView.width
                height: col.height

                Column {
                    id: col
                    width: parent.width
                    spacing: units.dp(4)

                    Item {
                        width: parent.width
                        height: units.gu(4.2)

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: units.gu(1.5)
                            anchors.right: parent.right
                            anchors.rightMargin: units.gu(1.5)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.gu(1)

                            Label {
                                text: modelData.title
                                font.pixelSize: units.gu(1.8)
                                font.weight: Font.DemiBold
                                color: Theme.textDark
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Label {
                                text: modelData.subtitle || ""
                                font.pixelSize: units.gu(1.5)
                                color: Theme.textMuted
                                visible: text.length > 0
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        height: {
                            var rows = Math.ceil(modelData.items.length / root.columnCount);
                            var cellW = (width - (root.columnCount - 1) * root.itemSpacing) / root.columnCount;
                            return rows * cellW + (rows > 0 ? (rows - 1) * root.itemSpacing : 0);
                        }
                        spacing: root.itemSpacing

                        Repeater {
                            model: modelData.items

                            Item {
                                width: (root.width - (root.columnCount - 1) * root.itemSpacing) / root.columnCount
                                height: width

                                PhotoGridItem {
                                    anchors.fill: parent
                                    photoData: modelData
                                    selectionMode: root.isSelectionMode
                                    isSelected: root.selectedIds.indexOf(modelData.id) !== -1
                                    showBackupBadge: root.showBackupBadges
                                    thumbnailUrl: {
                                        // For videos: if backed up or exists on server, fetch server thumbnail (or local preview)
                                        if (modelData.type === "video") {
                                            if (modelData.localPath && typeof backupEngine !== "undefined"
                                                    && typeof backupEngine.localVideoPreview === "function") {
                                                var prev = backupEngine.localVideoPreview(modelData.localPath);
                                                if (prev) {
                                                    return "image://syno/local/" + encodeURIComponent(prev) + "/sm";
                                                }
                                            }
                                            var targetId = modelData.remoteThumbId || (String(modelData.id || "").indexOf("local:") !== 0 ? modelData.id : null);
                                            if (targetId && mainView.sid) {
                                                var cKey = (modelData.additional && modelData.additional.thumbnail)
                                                    ? modelData.additional.thumbnail.cache_key : (targetId + "_0");
                                                var szCode = (filterPill.selectedIndex === 0) ? "sm" : "m";
                                                return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                                                          targetId, cKey, szCode, "unit", root.passphrase);
                                            }
                                            return "";
                                        }
                                        if (modelData.isLocal) {
                                            return "image://syno/local/" + encodeURIComponent(modelData.localPath || "") + "/sm";
                                        }
                                        var cacheKey = (modelData.additional && modelData.additional.thumbnail)
                                            ? modelData.additional.thumbnail.cache_key : (modelData.id + "_0");
                                        var sizeCode = (filterPill.selectedIndex === 0) ? "sm" : "m";
                                        return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, modelData.id, cacheKey, sizeCode, "unit", root.passphrase);
                                    }
                                    onClicked: {
                                        if (root.isSelectionMode) {
                                            root.toggleSelection(item.id);
                                        } else {
                                            // Pass the event up. But we need to open viewer.
                                            // The simplest way is to directly call mainView.openViewer
                                            // We need the index of this photo in root.photos
                                            var idx = -1;
                                            for(var i=0; i<root.photos.length; i++) {
                                                if (root.photos[i].id === item.id) {
                                                    idx = i;
                                                    break;
                                                }
                                            }
                                            if (idx !== -1) {
                                                mainView.openViewer(root.photos, idx, root.isReadOnly, root.passphrase, root.albumId);
                                            }
                                        }
                                    }
                                    onPressAndHold: {
                                        if (!root.isSelectionMode) {
                                            root.isSelectionMode = true;
                                            root.toggleSelection(item.id);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: units.gu(1)
                    }
                }
            }

            footer: Item {
                width: timelineListView.width
                height: units.gu(10)
            }
        }

        // Custom Scrollbar
        Item {
            id: customScrollbar
            anchors.right: parent.right
            anchors.top: timelineListView.top
            anchors.bottom: timelineListView.bottom
            width: units.gu(4)
            visible: filterPill.selectedIndex !== 3 && timelineListView.contentHeight > timelineListView.height
            opacity: 0.0

            Behavior on opacity { NumberAnimation { duration: 250 } }

            Timer {
                id: scrollbarHideTimer
                interval: 3000
                onTriggered: {
                    if (!scrollbarMouseArea.drag.active) customScrollbar.opacity = 0.0;
                }
            }

            Connections {
                target: timelineListView
                onContentYChanged: {
                    if (timelineListView.moving && !scrollbarMouseArea.drag.active) {
                        customScrollbar.opacity = 1.0;
                        scrollbarHideTimer.restart();
                    }
                }
            }

            Item {
                id: scrollTrack
                anchors.right: parent.right
                anchors.rightMargin: units.dp(4)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: units.dp(6)
            }

            Rectangle {
                id: scrollThumb
                anchors.horizontalCenter: scrollTrack.horizontalCenter
                width: units.dp(6)
                radius: width / 2
                color: "#99000000"
                height: Math.max(units.gu(4), (timelineListView.height / timelineListView.contentHeight) * scrollTrack.height)
                y: {
                    if (timelineListView.contentHeight <= timelineListView.height) return 0;
                    var ratio = timelineListView.contentY / (timelineListView.contentHeight - timelineListView.height);
                    return Math.max(0, Math.min(scrollTrack.height - height, ratio * (scrollTrack.height - height)));
                }

                Rectangle {
                    id: dateIndicator
                    anchors.right: parent.left
                    anchors.rightMargin: units.gu(1)
                    anchors.verticalCenter: parent.verticalCenter
                    width: dateLabel.width + units.gu(3)
                    height: units.gu(4)
                    radius: height / 2
                    color: Theme.primary
                    visible: scrollbarMouseArea.pressed || customScrollbar.opacity > 0.0
                    
                    Label {
                        id: dateLabel
                        anchors.centerIn: parent
                        color: "#ffffff"
                        font.pixelSize: units.gu(1.6)
                        font.weight: Font.DemiBold
                        text: {
                            var idx = timelineListView.indexAt(10, timelineListView.contentY + timelineListView.height / 2);
                            if (idx >= 0 && idx < root.groupedSections.length) {
                                return root.groupedSections[idx].title;
                            }
                            return "";
                        }
                    }
                }
            }

            MouseArea {
                id: scrollbarMouseArea
                anchors.fill: parent
                drag.target: scrollThumb
                drag.axis: Drag.YAxis
                drag.minimumY: 0
                drag.maximumY: scrollTrack.height - scrollThumb.height
                
                onPressed: {
                    customScrollbar.opacity = 1.0;
                    scrollbarHideTimer.stop();
                }
                
                onReleased: scrollbarHideTimer.restart()
                
                onPositionChanged: {
                    if (drag.active) {
                        var ratio = scrollThumb.y / (scrollTrack.height - scrollThumb.height);
                        timelineListView.contentY = ratio * (timelineListView.contentHeight - timelineListView.height);
                    }
                }
            }
        }

        // Empty state for Photos
        Column {
            anchors.centerIn: parent
            visible: filterPill.selectedIndex !== 3 && root.photos.length === 0 && !mainView.loading
            spacing: units.gu(1.5)

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "image-x-generic"
                width: units.gu(6)
                height: units.gu(6)
                color: Theme.textMuted
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: i18n.tr("No photos found")
                font.pixelSize: units.gu(1.8)
                color: Theme.textMuted
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(14)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: Theme.primary

                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Refresh")
                    color: "#ffffff"
                    font.pixelSize: units.gu(1.8)
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.refreshRequested()
                }
            }
        }

        TimelineFilterPill {
            id: filterPill
            anchors.bottom: parent.bottom
            anchors.bottomMargin: units.gu(2)
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showFilterPill && !root.isSelectionMode && root.photos.length > 0
            onFilterChanged: {
                if (index === 3) {
                    root.loadFoldersRequested();
                } else {
                    root.updateGroupedSections();
                }
            }
        }
    }

    // Top Selection Header
    Rectangle {
        id: selectionTopBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: units.gu(7)
        color: Theme.background
        visible: root.isSelectionMode
        z: 100

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: units.dp(1)
            color: Theme.divider
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: units.gu(2)
            anchors.rightMargin: units.gu(2)
            spacing: units.gu(2)

            Icon {
                name: "close"
                width: units.gu(3)
                height: units.gu(3)
                color: Theme.textDark
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onClicked: root.clearSelection()
                }
            }

            Label {
                text: i18n.tr("%1 Selected").arg(root.selectedIds.length)
                font.pixelSize: units.gu(2.2)
                font.weight: Font.DemiBold
                color: Theme.textDark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Bottom Selection Actions
    Rectangle {
        id: selectionBottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: units.gu(8)
        color: Theme.background
        visible: root.isSelectionMode
        z: 100
        
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: units.dp(1)
            color: Theme.divider
        }

        Row {
            anchors.fill: parent
            spacing: 0

            // 1. Add to Album
            Item {
                width: parent.width / 3
                height: parent.height
                visible: !root.isReadOnly

                Column {
                    id: addCol
                    anchors.centerIn: parent
                    spacing: units.dp(4)

                    Icon {
                        name: "image-x-generic"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: root.selectedIds.length > 0 ? Theme.textDark : Theme.textSubtle
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Label {
                        text: i18n.tr("Add to Album")
                        font.pixelSize: units.gu(1.2)
                        color: root.selectedIds.length > 0 ? Theme.textDark : Theme.textSubtle
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onClicked: {
                        if (root.selectedIds.length === 0) return;
                        addToAlbumSheet.openSheet();
                    }
                }
            }

            // 2. Delete
            Item {
                width: parent.width / 3
                height: parent.height
                visible: !root.isReadOnly

                Column {
                    id: deleteCol
                    anchors.centerIn: parent
                    spacing: units.dp(4)

                    Icon {
                        name: root.albumId > 0 ? "list-remove" : "delete"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: root.selectedIds.length > 0 ? Theme.primaryDark : Theme.textSubtle
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Label {
                        text: root.albumId > 0 ? i18n.tr("Remove") : i18n.tr("Delete")
                        font.pixelSize: units.gu(1.2)
                        color: root.selectedIds.length > 0 ? Theme.primaryDark : Theme.textSubtle
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onClicked: {
                        if (root.selectedIds.length === 0) return;
                        var isRemove = root.albumId > 0;

                        if (isRemove) {
                            // Case A: Remove items from Album
                            var sIds = [];
                            for (var ai = 0; ai < root.selectedIds.length; ai++) {
                                if (String(root.selectedIds[ai]).indexOf("local:") !== 0) {
                                    sIds.push(root.selectedIds[ai]);
                                }
                            }
                            mainView.showErrorDialog(
                                i18n.tr("Remove Items"),
                                i18n.tr("Are you sure you want to remove %1 items from this album?").arg(root.selectedIds.length),
                                i18n.tr("Remove"),
                                i18n.tr("Cancel"),
                                function() {
                                    mainView.showLoading(i18n.tr("Removing..."));
                                    SynoApi.removeItemsFromAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken, root.albumId, sIds, function(err) {
                                        mainView.hideLoading();
                                        if (err) {
                                            mainView.showToast(i18n.tr("Failed to remove items"), true, false);
                                        } else {
                                            mainView.showToast(i18n.tr("Items removed from album"), false, true);
                                            var idsToRemove = root.selectedIds.slice();
                                            root.clearSelection();
                                            for (var i = 0; i < idsToRemove.length; i++) {
                                                mainView.itemDeleted(idsToRemove[i], false);
                                            }
                                        }
                                    });
                                }
                            );
                            return;
                        }

                        // Case B: Delete items from Library
                        var photoMap = {};
                        for (var pi = 0; pi < root.photos.length; pi++) {
                            var pItem = root.photos[pi];
                            if (pItem) {
                                photoMap[pItem.id] = pItem;
                            }
                        }

                        var localOnlyIds = [];
                        var localOnlyPaths = [];
                        var serverIds = [];
                        var localPathsOfServerItems = [];

                        for (var si = 0; si < root.selectedIds.length; si++) {
                            var selId = root.selectedIds[si];
                            var itemObj = photoMap[selId];

                            if (String(selId).indexOf("local:") === 0) {
                                localOnlyIds.push(selId);
                                var lPath = (itemObj && itemObj.localPath) ? itemObj.localPath : String(selId).substring(6);
                                localOnlyPaths.push(lPath);
                            } else {
                                serverIds.push(selId);
                                var localCopy = (itemObj && itemObj.localPath) ? itemObj.localPath : Storage.getLocalPathByRemoteId(selId);
                                if (localCopy && localCopy.length > 0) {
                                    localPathsOfServerItems.push(localCopy);
                                }
                            }
                        }

                        var totalLocalCopies = localOnlyPaths.length + localPathsOfServerItems.length;

                        function executeDeleteEverywhere() {
                            mainView.showLoading(i18n.tr("Deleting..."));
                            var idsToDeleteLocal = localOnlyIds.slice();
                            var idsToDeleteServer = serverIds.slice();
                            var pathsToDelete = localOnlyPaths.concat(localPathsOfServerItems);
                            root.clearSelection();

                            // 1. Delete local files from filesystem immediately
                            if (pathsToDelete.length > 0 && typeof backupEngine !== "undefined") {
                                backupEngine.deleteLocalFiles(pathsToDelete);
                            }

                            // 2. Delete server items if any
                            if (idsToDeleteServer.length > 0) {
                                SynoApi.deleteItems(mainView.serverUrl, mainView.sid, mainView.synotoken, idsToDeleteServer, function(err) {
                                    mainView.hideLoading();
                                    if (err) {
                                        mainView.showToast(i18n.tr("Delete failed on server"), true, false);
                                    } else {
                                        mainView.showToast(i18n.tr("Items deleted from server and device"), false, true);
                                    }
                                    for (var j = 0; j < idsToDeleteServer.length; j++) {
                                        mainView.itemDeleted(idsToDeleteServer[j], true);
                                    }
                                    for (var lj = 0; lj < idsToDeleteLocal.length; lj++) {
                                        mainView.itemDeleted(idsToDeleteLocal[lj], true);
                                    }
                                });
                            } else {
                                mainView.hideLoading();
                                for (var lj2 = 0; lj2 < idsToDeleteLocal.length; lj2++) {
                                    mainView.itemDeleted(idsToDeleteLocal[lj2], true);
                                }
                                mainView.showToast(i18n.tr("Items deleted from device"), false, true);
                            }
                        }

                        function executeDeleteServerOnly() {
                            if (serverIds.length === 0) return;
                            mainView.showLoading(i18n.tr("Deleting..."));
                            var idsToDeleteServer = serverIds.slice();
                            root.clearSelection();

                            SynoApi.deleteItems(mainView.serverUrl, mainView.sid, mainView.synotoken, idsToDeleteServer, function(err) {
                                mainView.hideLoading();
                                if (err) {
                                    mainView.showToast(i18n.tr("Delete failed"), true, false);
                                } else {
                                    mainView.showToast(i18n.tr("Items deleted from server"), false, true);
                                    for (var j = 0; j < idsToDeleteServer.length; j++) {
                                        mainView.itemDeleted(idsToDeleteServer[j], false);
                                    }
                                }
                            });
                        }

                        if (serverIds.length === 0) {
                            // Sub-case 1: Only local files selected
                            mainView.showErrorDialog(
                                i18n.tr("Delete Items"),
                                i18n.tr("Are you sure you want to delete %1 items from this device?").arg(localOnlyPaths.length),
                                i18n.tr("Delete"),
                                i18n.tr("Cancel"),
                                function() {
                                    executeDeleteEverywhere();
                                }
                            );
                        } else if (totalLocalCopies > 0) {
                            // Sub-case 2: Server items selected AND local copies exist on device
                            mainView.showActionDialog(
                                i18n.tr("Delete Items"),
                                i18n.tr("Local copies exist on this device for selected items. Where do you want to delete them?"),
                                i18n.tr("Delete everywhere"),
                                i18n.tr("Server only"),
                                i18n.tr("Cancel"),
                                function() {
                                    executeDeleteEverywhere();
                                },
                                function() {
                                    executeDeleteServerOnly();
                                },
                                function() {
                                    // Canceled: do nothing
                                }
                            );
                        } else {
                            // Sub-case 3: Only server files without local copies
                            mainView.showErrorDialog(
                                i18n.tr("Delete Items"),
                                i18n.tr("Are you sure you want to delete %1 items from the server?").arg(serverIds.length),
                                i18n.tr("Delete"),
                                i18n.tr("Cancel"),
                                function() {
                                    executeDeleteServerOnly();
                                }
                            );
                        }
                    }
                }
            }

            // 3. More
            Item {
                id: moreButton
                width: parent.width / 3
                height: parent.height

                Column {
                    id: moreCol
                    anchors.centerIn: parent
                    spacing: units.dp(4)

                    Icon {
                        name: "navigation-menu"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: Theme.textDark
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Label {
                        text: i18n.tr("More")
                        font.pixelSize: units.gu(1.2)
                        color: Theme.textDark
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onClicked: {
                        if (root.selectedIds.length === 0) return;
                        moreSheet.open();
                    }
                }
            }
        }
    }

    // More Options Sheet
    BottomSheet {
        id: moreSheet
        contentHeight: units.gu(24)

        Column {
            width: parent.width
            spacing: 0

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)

                    Icon {
                        name: "share"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Share")
                        font.pixelSize: units.gu(1.8)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        moreSheet.close();
                        if (root.selectedIds.length === 0) return;
                        shareDialog.openSheet(root.selectedIds);
                        root.clearSelection();
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)

                    Icon {
                        name: "download"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Download")
                        font.pixelSize: units.gu(1.8)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        moreSheet.close();
                        if (root.selectedIds.length === 0) return;
                        var downloadUrl = SynoApi.getDownloadUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, root.selectedIds, root.passphrase);
                        Qt.openUrlExternally(downloadUrl);
                        root.clearSelection();
                    }
                }
            }
            
            Rectangle {
                width: parent.width
                height: units.dp(1)
                color: Theme.divider
            }

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)

                    Icon {
                        name: "favorite"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Add to Favorites")
                        font.pixelSize: units.gu(1.8)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        moreSheet.close();
                        mainView.showLoading(i18n.tr("Adding to Favorites..."));
                        SynoApi.toggleFavorite(mainView.serverUrl, mainView.sid, mainView.synotoken, root.selectedIds, true, function(err) {
                            mainView.hideLoading();
                            if (err) {
                                console.log("ToggleFavorite Error:", JSON.stringify(err));
                                mainView.showToast(i18n.tr("Failed to add to Favorites"), true, false);
                            } else {
                                mainView.showToast(i18n.tr("Added to Favorites"), false, true);
                                root.clearSelection();
                                root.refreshRequested();
                            }
                        });
                    }
                }
            }
        }
    }

    ShareDialog {
        id: shareDialog
    }

    AddToAlbumSheet {
        id: addToAlbumSheet
        itemIds: root.selectedIds
    }
}
