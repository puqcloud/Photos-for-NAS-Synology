import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Page {
    id: albumDetailPage
    header: Item {
        width: albumDetailPage.width
        height: 0
        visible: false
    }

    property var albumData: null
    property var photos: []
    property var subFolders: []
    property bool isRealAlbum: albumData && !albumData.isFolder && albumData.id > 0
    property bool isReadOnly: false
    property int columnCount: Math.max(3, Math.floor(width / units.gu(12)))
    property real cellDimension: width / columnCount
    property real itemSpacing: units.dp(2)
    property bool dataLoaded: false

    Component.onCompleted: {
        if (albumData && albumData.isFolder && albumData.childrenArr && albumData.childrenArr.length > 0) {
            albumDetailPage.subFolders = albumData.childrenArr;
        }
        loadAlbumPhotos();
    }

    Connections {
        target: mainView
        onItemDeleted: {
            var oldLen = albumDetailPage.photos.length;
            var newPhotos = albumDetailPage.photos.filter(function(p) { return p.id !== itemId; });
            if (newPhotos.length < oldLen) {
                albumDetailPage.photos = newPhotos;
                if (mainView.viewerPhotoList === albumDetailPage.photos) {
                    mainView.viewerPhotoList = albumDetailPage.photos;
                }
                if (albumDetailPage.albumData) {
                    if (albumDetailPage.showInfoPanel) {
                        albumDetailPage.loadAndShowInfo();
                    } else {
                        // Refresh info silently in case it's opened later
                        if (albumDetailPage.albumData.id > 0) {
                            SynoApi.getAlbumInfo(mainView.serverUrl, mainView.sid, mainView.synotoken, albumDetailPage.albumData.id, function(err, data) {
                                if (!err && data) albumDetailPage.fullAlbumInfo = data;
                            });
                        }
                    }
                }
            }
        }
        onAlbumUpdated: {
            if (albumDetailPage.albumData && albumDetailPage.albumData.id === albumId) {
                albumDetailPage.loadAlbumPhotos();
                if (albumDetailPage.showInfoPanel) {
                    albumDetailPage.loadAndShowInfo();
                }
            }
        }
    }

    SynoHeader {
        id: pageHeader
        anchors.top: parent.top
        title: {
            if (!albumDetailPage.albumData) return i18n.tr("Album");
            return albumDetailPage.albumData.displayName || albumDetailPage.albumData.name || i18n.tr("Album");
        }
        showBack: true
        showAdd: albumDetailPage.isRealAlbum && !albumDetailPage.isReadOnly
        showInfo: albumDetailPage.isRealAlbum
        showMore: albumDetailPage.isRealAlbum && !albumDetailPage.isReadOnly
        onBackClicked: pageStack.pop()
        onAddClicked: addPhotosSheet.open()
        onInfoClicked: loadAndShowInfo()
        onMoreClicked: albumMenuSheet.open()
    }

    property var fullAlbumInfo: null
    property bool showInfoPanel: false

    function loadAndShowInfo() {
        if (!albumData) return;
        fullAlbumInfo = albumData;
        showInfoPanel = true;

        if (albumData.id && albumData.id > 0) {
            SynoApi.getAlbumInfo(mainView.serverUrl, mainView.sid, mainView.synotoken, albumData.id, function(err, data) {
                if (!err && data) {
                    fullAlbumInfo = data;
                }
            });
        }
    }

    // Background interceptor to close info panel when clicking outside
    MouseArea {
        anchors.fill: parent
        visible: albumDetailPage.showInfoPanel
        z: 99
        onClicked: albumDetailPage.showInfoPanel = false
    }

    Rectangle {
        id: infoDrawer
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: albumDetailPage.showInfoPanel ? Math.min(infoFlickable.contentHeight + units.gu(2), parent.height * 0.75) : 0
        visible: albumDetailPage.showInfoPanel
        color: "#FAFAFA"
        z: 100
        clip: true

        Behavior on height {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        Flickable {
            id: infoFlickable
            anchors {
                fill: parent
                margins: units.gu(2)
            }
            contentHeight: infoCol.height
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: infoCol
                width: parent.width
                spacing: units.gu(2)

                // Header
                Row {
                    width: parent.width
                    spacing: units.gu(1)

                    Rectangle {
                        width: units.gu(4)
                        height: units.gu(4)
                        radius: units.gu(2)
                        color: closeInfoMouse.pressed ? "#E0E0E0" : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            anchors.centerIn: parent
                            name: "close"
                            width: units.gu(2.5)
                            height: units.gu(2.5)
                            color: "#333333"
                        }

                        MouseArea {
                            id: closeInfoMouse
                            anchors.fill: parent
                            onClicked: albumDetailPage.showInfoPanel = false
                        }
                    }

                    Label {
                        text: i18n.tr("Information")
                        font.pixelSize: units.gu(2.2)
                        font.weight: Font.DemiBold
                        color: "#1C1C1E"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle { width: parent.width; height: units.dp(1); color: "#E0E0E0" }

                // Details Content
                Column {
                    width: parent.width
                    spacing: units.gu(1.5)

                    // Name
                    Row {
                        width: parent.width
                        spacing: units.gu(1.5)
                        Icon { name: "stock_folder"; width: units.gu(2.5); height: units.gu(2.5); color: "#666666" }
                        Column {
                            width: parent.width - units.gu(4)
                            Label { text: i18n.tr("Name"); font.pixelSize: units.gu(1.4); color: "#666666" }
                            Label {
                                text: fullAlbumInfo ? (fullAlbumInfo.displayName || fullAlbumInfo.name || "") : ""
                                font.pixelSize: units.gu(1.7); font.weight: Font.DemiBold; color: "#1C1C1E"; wrapMode: Text.Wrap; width: parent.width
                            }
                        }
                    }

                    // Items
                    Row {
                        width: parent.width
                        spacing: units.gu(1.5)
                        Icon { name: "image-x-generic"; width: units.gu(2.5); height: units.gu(2.5); color: "#666666" }
                        Column {
                            width: parent.width - units.gu(4)
                            Label { text: i18n.tr("Items"); font.pixelSize: units.gu(1.4); color: "#666666" }
                            Label {
                                text: fullAlbumInfo ? (fullAlbumInfo.item_count || 0).toString() : "0"
                                font.pixelSize: units.gu(1.7); font.weight: Font.DemiBold; color: "#1C1C1E"
                            }
                        }
                    }

                    // Shared
                    Row {
                        width: parent.width
                        spacing: units.gu(1.5)
                        visible: fullAlbumInfo && (fullAlbumInfo.shared || (fullAlbumInfo.additional && fullAlbumInfo.additional.sharing_info))
                        Icon { name: "contact-new"; width: units.gu(2.5); height: units.gu(2.5); color: "#666666" }
                        Column {
                            width: parent.width - units.gu(4)
                            Label { text: i18n.tr("Shared"); font.pixelSize: units.gu(1.4); color: "#666666" }
                            Label {
                                text: i18n.tr("Yes")
                                font.pixelSize: units.gu(1.7); font.weight: Font.DemiBold; color: "#1C1C1E"
                            }
                        }
                    }

                    // Owner
                    Row {
                        width: parent.width
                        spacing: units.gu(1.5)
                        visible: fullAlbumInfo && fullAlbumInfo.additional && fullAlbumInfo.additional.sharing_info && fullAlbumInfo.additional.sharing_info.owner
                        Icon { name: "stock_person"; width: units.gu(2.5); height: units.gu(2.5); color: "#666666" }
                        Column {
                            width: parent.width - units.gu(4)
                            Label { text: i18n.tr("Owner"); font.pixelSize: units.gu(1.4); color: "#666666" }
                            Label {
                                text: fullAlbumInfo && fullAlbumInfo.additional && fullAlbumInfo.additional.sharing_info && fullAlbumInfo.additional.sharing_info.owner ? fullAlbumInfo.additional.sharing_info.owner.name : ""
                                font.pixelSize: units.gu(1.7); font.weight: Font.DemiBold; color: "#1C1C1E"
                            }
                        }
                    }

                    // Privacy
                    Row {
                        width: parent.width
                        spacing: units.gu(1.5)
                        visible: fullAlbumInfo && fullAlbumInfo.additional && fullAlbumInfo.additional.sharing_info && fullAlbumInfo.additional.sharing_info.privacy_type
                        Icon { name: "lock"; width: units.gu(2.5); height: units.gu(2.5); color: "#666666" }
                        Column {
                            width: parent.width - units.gu(4)
                            Label { text: i18n.tr("Privacy"); font.pixelSize: units.gu(1.4); color: "#666666" }
                            Label {
                                text: fullAlbumInfo && fullAlbumInfo.additional && fullAlbumInfo.additional.sharing_info ? fullAlbumInfo.additional.sharing_info.privacy_type : ""
                                font.pixelSize: units.gu(1.7); font.weight: Font.DemiBold; color: "#1C1C1E"
                            }
                        }
                    }

                    // Permissions
                    Row {
                        width: parent.width
                        spacing: units.gu(1.5)
                        visible: fullAlbumInfo && fullAlbumInfo.additional && fullAlbumInfo.additional.sharing_info && fullAlbumInfo.additional.sharing_info.permission
                        Icon { name: "stock_people"; width: units.gu(2.5); height: units.gu(2.5); color: "#666666" }
                        Column {
                            width: parent.width - units.gu(4)
                            Label { text: i18n.tr("Shared with"); font.pixelSize: units.gu(1.4); color: "#666666" }
                            Label {
                                text: {
                                    if (!fullAlbumInfo || !fullAlbumInfo.additional || !fullAlbumInfo.additional.sharing_info || !fullAlbumInfo.additional.sharing_info.permission) return "";
                                    var perms = fullAlbumInfo.additional.sharing_info.permission;
                                    if (perms.length === 0) return i18n.tr("No one");
                                    var names = [];
                                    for (var i = 0; i < perms.length; i++) {
                                        names.push(perms[i].name);
                                    }
                                    return names.join(", ");
                                }
                                font.pixelSize: units.gu(1.7); font.weight: Font.DemiBold; color: "#1C1C1E"; wrapMode: Text.Wrap; width: parent.width
                            }
                        }
                    }
                }
                
                Item { width: 1; height: units.gu(2) }
            }
        }
    }

    BottomSheet {
        id: albumMenuSheet
        contentHeight: units.gu(28)

        Column {
            anchors.fill: parent
            anchors.topMargin: units.gu(1)
            spacing: 0

            // Select
            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: selectMouse.pressed ? "#F0F0F2" : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)
                    Icon {
                        name: "ok"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Select")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: selectMouse
                    anchors.fill: parent
                    onClicked: {
                        albumMenuSheet.close();
                        if (albumTimeline) albumTimeline.isSelectionMode = true;
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            // Share
            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: shareMouse.pressed ? "#F0F0F2" : "transparent"

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
                        text: i18n.tr("Share Album")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: shareMouse
                    anchors.fill: parent
                    onClicked: {
                        albumMenuSheet.close();
                        if (albumDetailPage.photos.length === 0) {
                            mainView.showToast(i18n.tr("No photos to share"), false, false);
                            return;
                        }
                        var ids = [];
                        for (var i = 0; i < Math.min(albumDetailPage.photos.length, 500); i++) {
                            ids.push(albumDetailPage.photos[i].id);
                        }
                        shareDialog.openSheet(ids);
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            // Delete
            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: deleteMouse.pressed ? "#F0F0F2" : "transparent"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)
                    Icon {
                        name: "delete"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Delete Album")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    onClicked: {
                        albumMenuSheet.close();
                        mainView.showErrorDialog(
                            i18n.tr("Delete Album"),
                            i18n.tr("Are you sure you want to delete album \"%1\"? Photos will remain in your library.").arg(albumDetailPage.albumData.name),
                            i18n.tr("Delete"),
                            i18n.tr("Cancel"),
                            function() {
                                mainView.showLoading(i18n.tr("Deleting album..."));
                                SynoApi.deleteAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken, albumDetailPage.albumData.id, function(err) {
                                    mainView.hideLoading();
                                    if (err) {
                                        if (!mainView.handleApiError(err)) {
                                            mainView.showErrorDialog(i18n.tr("Delete Failed"), err.message);
                                        }
                                    } else {
                                        mainView.showToast(i18n.tr("Album deleted"), false, true);
                                        mainView.albumDeleted(albumDetailPage.albumData.id);
                                        pageStack.pop();
                                    }
                                });
                            }
                        );
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            // Cancel
            Rectangle {
                width: parent.width
                height: units.gu(5)
                color: cancelMouse.pressed ? "#F0F0F2" : "transparent"

                Label {
                    text: i18n.tr("Cancel")
                    font.pixelSize: units.gu(1.8)
                    color: Theme.textMuted
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    onClicked: albumMenuSheet.close()
                }
            }
        }
    }

    // Add Photos Bottom Sheet
    BottomSheet {
        id: addPhotosSheet
        contentHeight: units.gu(14)

        Column {
            anchors.fill: parent
            anchors.topMargin: units.gu(1)
            spacing: 0

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: addFromLibMouse.pressed ? "#F0F0F2" : "transparent"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)
                    Icon {
                        name: "image-x-generic"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Add from library")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: addFromLibMouse
                    anchors.fill: parent
                    onClicked: {
                        addPhotosSheet.close();
                        pageStack.push(Qt.resolvedUrl("AddPhotosPage.qml"), {
                            albumId: albumDetailPage.albumData.id,
                            albumName: albumDetailPage.albumData.name
                        });
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(5)
                color: addCancelMouse.pressed ? "#F0F0F2" : "transparent"
                Label {
                    text: i18n.tr("Cancel")
                    font.pixelSize: units.gu(1.8)
                    color: Theme.textMuted
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: addCancelMouse
                    anchors.fill: parent
                    onClicked: addPhotosSheet.close()
                }
            }
        }
    }

    ShareDialog {
        id: shareDialog
    }

    Item {
        id: contentArea
        anchors.top: pageHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // Sub-folders grid (for folder hierarchy navigation)
        GridView {
            id: subFolderGrid
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: units.gu(1.5)
            height: {
                if (!subFolderGrid.visible) return 0;
                var cols = Math.max(2, Math.floor(width / units.gu(14)));
                var rows = Math.ceil(albumDetailPage.subFolders.length / cols);
                var h = rows * subFolderGrid.cellHeight;
                if (albumDetailPage.photos.length > 0) {
                    return Math.min(units.gu(22), h);
                }
                return h;
            }
            visible: albumDetailPage.subFolders.length > 0
            cellWidth: width / Math.max(2, Math.floor(width / units.gu(14)))
            cellHeight: units.gu(17)
            model: albumDetailPage.subFolders
            clip: true
            z: 5

            delegate: Item {
                width: subFolderGrid.cellWidth
                height: subFolderGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: units.gu(0.6)
                    radius: units.gu(1)
                    color: "#F5F6F8"
                    border.color: "#E5E7EB"
                    border.width: units.dp(1)

                    Column {
                        anchors.centerIn: parent
                        spacing: units.gu(0.8)
                        width: parent.width - units.gu(2)

                        Icon {
                            name: modelData.hasChildren ? "folder" : "image-x-generic"
                            width: units.gu(4.5)
                            height: units.gu(4.5)
                            color: Theme.textMuted
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Label {
                            text: modelData.displayName || modelData.name || ""
                            font.pixelSize: units.gu(1.4)
                            font.weight: Font.DemiBold
                            color: Theme.textDark
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }

                        Label {
                            text: {
                                var cnt = modelData.total_count || 0;
                                if (cnt <= 0) return i18n.tr("Empty");
                                return i18n.tr("%1 items").arg(cnt);
                            }
                            font.pixelSize: units.gu(1.2)
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

        // Photos
        PhotoTimelineView {
            id: albumTimeline
            anchors.top: subFolderGrid.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: albumDetailPage.subFolders.length > 0 && albumDetailPage.photos.length > 0 ? units.gu(1) : 0
            height: albumDetailPage.photos.length > 0 ? undefined : 0
            visible: albumDetailPage.photos.length > 0
            photos: albumDetailPage.photos
            showFilterPill: false
            isReadOnly: albumDetailPage.isReadOnly
            passphrase: albumDetailPage.albumData ? (albumDetailPage.albumData.passphrase || "") : ""
            albumId: albumDetailPage.albumData ? albumDetailPage.albumData.id : -1
            onRefreshRequested: loadAlbumPhotos()
        }

        // Empty state placeholder
        Column {
            anchors.centerIn: parent
            spacing: units.gu(2)
            width: Math.min(parent.width - units.gu(6), units.gu(40))
            visible: albumDetailPage.dataLoaded && albumDetailPage.photos.length === 0 && albumDetailPage.subFolders.length === 0

            Icon {
                name: "image-x-generic"
                width: units.gu(8)
                height: units.gu(8)
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.textMuted
            }

            Label {
                text: i18n.tr("No photos")
                font.pixelSize: units.gu(2.2)
                font.weight: Font.Bold
                color: Theme.textDark
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Label {
                text: i18n.tr("This album is empty.")
                font.pixelSize: units.gu(1.6)
                color: Theme.textMuted
                anchors.horizontalCenter: parent.horizontalCenter
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    function loadAlbumPhotos() {
        albumDetailPage.dataLoaded = false;
        if (!albumData) return;

        if (albumData.isFolder) {
            var fid = albumData.folderId;
            if (!fid) {
                albumDetailPage.photos = [];
                return;
            }
            mainView.showLoading(i18n.tr("Loading folder photos..."));
            SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 500, fid, function(err, data) {
                mainView.hideLoading();
                if (err) {
                    if (!mainView.handleApiError(err)) {
                        mainView.showErrorDialog(i18n.tr("Folder Error"), err.message);
                    }
                } else if (data && data.list && data.list.length > 0) {
                    albumDetailPage.photos = data.list;
                } else {
                    albumDetailPage.photos = [];
                }
                albumDetailPage.dataLoaded = true;
            });
        } else if (albumData.id > 0) {
            var pass = albumData.passphrase || "";
            SynoApi.getAlbumPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, albumData.id, 0, 200, function(err, data) {
                mainView.hideLoading();
                if (err) {
                    if (err.code === 609 || err.code === 119) { // 609 = no permission (probably an empty shared album without passphrase), 119 = wrong password
                        mainView.showErrorDialog(i18n.tr("Access Denied"), i18n.tr("You don't have permission to view this album."));
                    } else if (!mainView.handleApiError(err)) {
                        mainView.showErrorDialog(i18n.tr("Album Error"), err.message);
                    }
                } else if (data && data.list) {
                    albumDetailPage.photos = data.list;
                } else {
                    albumDetailPage.photos = [];
                }
                albumDetailPage.dataLoaded = true;
            }, pass);
        } else if (albumData.id === -2) {
            // Favorites
            mainView.showLoading(i18n.tr("Loading favorites..."));
            SynoApi.getFavorites(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 200, function(err, data) {
                mainView.hideLoading();
                if (err) {
                    if (!mainView.handleApiError(err)) {
                        mainView.showErrorDialog(i18n.tr("Error"), err.message);
                    }
                } else if (data && data.list) {
                    albumDetailPage.photos = data.list;
                } else {
                    albumDetailPage.photos = [];
                }
                albumDetailPage.dataLoaded = true;
            });
        } else {
            // Virtual / Special Category Albums (Recently=-1, Videos=-3, Places=-4, Tags=-5)
            var limit = 500;
            SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, limit, function(err, data) {
                mainView.hideLoading();
                if (err) {
                    if (!mainView.handleApiError(err)) {
                        mainView.showErrorDialog(i18n.tr("Connection Error"), err.message);
                    }
                } else if (data && data.list) {
                    var list = data.list;
                    if (albumData.id === -1) {
                        list.sort(function(a, b) { return (b.indexed_time || b.time || 0) - (a.indexed_time || a.time || 0); });
                    } else if (albumData.id === -3) {
                        list = list.filter(function(p) { return p.type === "video"; });
                    } else if (albumData.id === -4) {
                        list = list.filter(function(p) {
                            return p.additional && p.additional.address && p.additional.address.country;
                        });
                    } else if (albumData.id === -5) {
                        list = list.filter(function(p) {
                            return p.additional && p.additional.tag && p.additional.tag.length > 0;
                        });
                    }
                    albumDetailPage.photos = list;
                } else {
                    albumDetailPage.photos = [];
                }
                albumDetailPage.dataLoaded = true;
            });
        }
    }
}
