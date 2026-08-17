import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Item {
    id: albumsTab
    anchors.fill: parent

    property var albums: []
    property var recentCovers: []
    property var favoriteCovers: []
    property var placesCovers: []
    property var tagsCovers: []
    property var videoCovers: []
    property var specialCards: []

    property int columnCount: 2
    property real itemSpacing: units.gu(1)

    Connections {
        target: mainView
        onItemDeleted: {
            loadAlbums();
            loadSpecialCovers();
        }
        onAlbumDeleted: {
            var updated = albumsTab.albums.slice();
            for (var i = 0; i < updated.length; i++) {
                if (updated[i].id === albumId) {
                    updated.splice(i, 1);
                    albumsTab.albums = updated;
                    break;
                }
            }
        }
        onAlbumUpdated: {
            // Reload albums to update thumbnails and counts
            loadAlbums();
            loadSpecialCovers();
        }
    }

    Component.onCompleted: {
        loadAlbums();
        loadSpecialCovers();
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Albums")
            showSearch: true
            showRefresh: true
            showAdd: true
            showMore: true
            onRefreshClicked: {
                loadAlbums();
                loadSpecialCovers();
            }
            onSearchClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
            onAddClicked: createAlbumSheet.open()
            onMoreClicked: albumsMoreSheet.open()
        }

        Flickable {
            width: parent.width
            height: parent.height - units.gu(6)
            contentHeight: contentCol.height + units.gu(12)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contentCol
                width: parent.width
                spacing: units.gu(3)

                // Special Cards Row
                Item {
                    width: parent.width
                    height: units.gu(20)

                    ListView {
                        anchors.fill: parent
                        anchors.leftMargin: units.gu(2)
                        orientation: ListView.Horizontal
                        spacing: units.gu(1.5)
                        model: albumsTab.specialCards
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: units.gu(15)
                            height: units.gu(19)
                            color: "transparent"

                            Column {
                                anchors.fill: parent
                                spacing: units.gu(1)

                                Rectangle {
                                    width: units.gu(15)
                                    height: units.gu(15)
                                    radius: units.gu(1.2)
                                    color: "#EAECEF"
                                    clip: true

                                    Grid {
                                        anchors.fill: parent
                                        anchors.margins: units.dp(1)
                                        columns: 2
                                        rows: 2
                                        spacing: units.dp(1)
                                        visible: modelData.covers && modelData.covers.length >= 4

                                        Repeater {
                                            model: modelData.covers
                                            Image {
                                                width: (parent.width - units.dp(1)) / 2
                                                height: (parent.height - units.dp(1)) / 2
                                                source: modelData
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                            }
                                        }
                                    }

                                    Icon {
                                        anchors.centerIn: parent
                                        name: {
                                            if (modelData.id === "favorites") return "like";
                                            if (modelData.id === "places") return "location";
                                            if (modelData.id === "tags") return "tag";
                                            if (modelData.id === "videos") return "media-playback-start";
                                            return "history";
                                        }
                                        width: units.gu(4.5)
                                        height: units.gu(4.5)
                                        color: "#C0C0C0"
                                        visible: !modelData.covers || modelData.covers.length < 4
                                    }
                                }

                                Label {
                                    text: modelData.name
                                    font.pixelSize: units.gu(1.4)
                                    font.weight: Font.DemiBold
                                    color: Theme.textDark
                                    width: parent.width
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                    maximumLineCount: 1
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var vid = -1;
                                    if (modelData.id === "favorites") vid = -2;
                                    if (modelData.id === "places") vid = -4;
                                    if (modelData.id === "tags") vid = -5;
                                    if (modelData.id === "videos") vid = -3;
                                    pageStack.push(Qt.resolvedUrl("AlbumDetailPage.qml"), {
                                        albumData: { name: modelData.name, id: vid }
                                    });
                                }
                            }
                        }
                    }
                }

                // All Albums Header
                Item {
                    width: parent.width
                    height: units.gu(4)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: units.gu(2)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(4)

                        Label {
                            text: i18n.tr("All albums")
                            font.pixelSize: units.gu(2.2)
                            font.weight: Font.DemiBold
                            color: Theme.textDark
                        }

                        Icon {
                            name: "down"
                            width: units.gu(2)
                            height: units.gu(2)
                            color: Theme.textDark
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Icon {
                        name: "folder"
                        width: units.gu(2.5)
                        height: units.gu(2.5)
                        color: Theme.textDark
                        anchors.right: parent.right
                        anchors.rightMargin: units.gu(2)
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -units.gu(1)
                            onClicked: {
                                albumsTab.albums.sort(function(a, b) {
                                    return (a.name || "").localeCompare(b.name || "");
                                });
                                albumsTab.albums = albumsTab.albums.slice();
                                mainView.showToast(i18n.tr("Sorted by name"), false, true);
                            }
                        }
                    }
                }

                // Albums Grid
                Flow {
                    id: albumFlow
                    width: parent.width - units.gu(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: albumsTab.itemSpacing

                    Repeater {
                        model: albumsTab.albums

                        AlbumCard {
                            width: (albumFlow.width - albumsTab.itemSpacing * (albumsTab.columnCount - 1)) / albumsTab.columnCount
                            title: modelData.name || ""
                            itemCount: modelData.item_count || 0
                            dateText: {
                                if (modelData.create_time) {
                                    var d = new Date(modelData.create_time * 1000);
                                    var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                                    return months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear();
                                }
                                return "";
                            }
                            albumData: modelData
                            coverUrl: {
                                if (modelData.cover && modelData.cover.additional && modelData.cover.additional.thumbnail) {
                                    return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                                                          modelData.cover.id, modelData.cover.additional.thumbnail.cache_key, "m");
                                }
                                return "";
                            }
                            onClicked: {
                                pageStack.push(Qt.resolvedUrl("AlbumDetailPage.qml"), { albumData: modelData });
                            }
                        }
                    }
                }

                Item { width: 1; height: units.gu(6) }
            }
        }
    }

    // Create Album Bottom Sheet
    BottomSheet {
        id: createAlbumSheet
        contentHeight: units.gu(20)

        Column {
            anchors.fill: parent
            anchors.topMargin: units.gu(1)
            spacing: 0

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: createSelMouse.pressed ? "#F0F0F2" : "transparent"
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
                        text: i18n.tr("Select photos")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: createSelMouse
                    anchors.fill: parent
                    onClicked: {
                        createAlbumSheet.close();
                        mainView.showInputDialog(
                            i18n.tr("New Album"),
                            i18n.tr("Enter album name to create from Photos tab selection"),
                            i18n.tr("Create"),
                            i18n.tr("Cancel"),
                            function(text) {
                                if (!text) return;
                                mainView.showLoading(i18n.tr("Creating album..."));
                                SynoApi.createAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken, text, [], function(err) {
                                    mainView.hideLoading();
                                    if (err) {
                                        mainView.showToast(i18n.tr("Failed to create album"), true, false);
                                    } else {
                                        mainView.showToast(i18n.tr("Album created"), false, true);
                                        loadAlbums();
                                    }
                                });
                            }
                        );
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: createUpMouse.pressed ? "#F0F0F2" : "transparent"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)
                    Icon {
                        name: "transfer-progress-upload"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Upload photos")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: createUpMouse
                    anchors.fill: parent
                    onClicked: {
                        createAlbumSheet.close();
                        mainView.showErrorDialog(
                            i18n.tr("Upload Photos"),
                            i18n.tr("Photo upload will be available in a future update via the Backup feature."),
                            i18n.tr("OK")
                        );
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(5)
                color: canMouse.pressed ? "#F0F0F2" : "transparent"
                Label {
                    text: i18n.tr("Cancel")
                    font.pixelSize: units.gu(1.8)
                    color: Theme.textMuted
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: canMouse
                    anchors.fill: parent
                    onClicked: createAlbumSheet.close()
                }
            }
        }
    }

    // 3-dot Menu Bottom Sheet
    BottomSheet {
        id: albumsMoreSheet
        contentHeight: units.gu(24)

        Column {
            anchors.fill: parent
            anchors.topMargin: units.gu(1)
            spacing: 0

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: moreSelMouse.pressed ? "#F0F0F2" : "transparent"
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
                    id: moreSelMouse
                    anchors.fill: parent
                    onClicked: {
                        albumsMoreSheet.close();
                        mainView.showToast(i18n.tr("Long-press an album to select photos inside"), false, false);
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: moreSortMouse.pressed ? "#F0F0F2" : "transparent"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)
                    Icon {
                        name: "filter"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Sort by")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: moreSortMouse
                    anchors.fill: parent
                    onClicked: {
                        albumsMoreSheet.close();
                        albumsTab.albums.sort(function(a, b) {
                            return (a.name || "").localeCompare(b.name || "");
                        });
                        albumsTab.albums = albumsTab.albums.slice();
                        mainView.showToast(i18n.tr("Sorted by name"), false, true);
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(6)
                color: moreFilMouse.pressed ? "#F0F0F2" : "transparent"
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: units.gu(2)
                    spacing: units.gu(2)
                    Icon {
                        name: "filter"
                        width: units.gu(3); height: units.gu(3)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: i18n.tr("Filter")
                        font.pixelSize: units.gu(1.9)
                        color: Theme.textDark
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: moreFilMouse
                    anchors.fill: parent
                    onClicked: {
                        albumsMoreSheet.close();
                        mainView.showToast(i18n.tr("Filter by type coming soon"), false, false);
                    }
                }
            }

            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

            Rectangle {
                width: parent.width
                height: units.gu(5)
                color: moreCanMouse.pressed ? "#F0F0F2" : "transparent"
                Label {
                    text: i18n.tr("Cancel")
                    font.pixelSize: units.gu(1.8)
                    color: Theme.textMuted
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: moreCanMouse
                    anchors.fill: parent
                    onClicked: albumsMoreSheet.close()
                }
            }
        }
    }

    function loadAlbums() {
        if (!mainView.sid) return;
        mainView.showLoading(i18n.tr("Loading albums..."));
        SynoApi.getAlbums(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 100, function(err, data) {
            mainView.hideLoading();
            if (!err && data && data.list) {
                albumsTab.albums = data.list;
            }
        });
    }

    function loadSpecialCovers() {
        if (!mainView.sid) return;

        SynoApi.getFavorites(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 4, function(err, data) {
            if (!err && data && data.list) {
                albumsTab.favoriteCovers = extractThumbnails(data.list);
                rebuildSpecialCards();
            }
        });

        SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 500, function(err, data) {
            if (err || !data || !data.list) return;
            var list = data.list;
            albumsTab.recentCovers = extractThumbnails(list.slice(0, 4));

            var videos = [];
            var places = [];
            var tags = [];
            for (var i = 0; i < list.length; i++) {
                var p = list[i];
                if (p.type === "video" && videos.length < 4) videos.push(p);
                var add = p.additional;
                if (add) {
                    if (add.address && add.address.country && places.length < 4) places.push(p);
                    if (add.tag && add.tag.length > 0 && tags.length < 4) tags.push(p);
                }
                if (videos.length >= 4 && places.length >= 4 && tags.length >= 4) break;
            }
            albumsTab.videoCovers = extractThumbnails(videos);
            albumsTab.placesCovers = extractThumbnails(places);
            albumsTab.tagsCovers = extractThumbnails(tags);
            rebuildSpecialCards();
        });
    }

    function rebuildSpecialCards() {
        albumsTab.specialCards = [
            { id: "recent", name: i18n.tr("Recently"), covers: albumsTab.recentCovers },
            { id: "favorites", name: i18n.tr("Favorites"), covers: albumsTab.favoriteCovers },
            { id: "places", name: i18n.tr("Places"), covers: albumsTab.placesCovers },
            { id: "tags", name: i18n.tr("Tags"), covers: albumsTab.tagsCovers },
            { id: "videos", name: i18n.tr("Videos"), covers: albumsTab.videoCovers }
        ];
    }

    function extractThumbnails(list) {
        var urls = [];
        for (var i = 0; i < list.length && i < 4; i++) {
            var p = list[i];
            if (p.additional && p.additional.thumbnail) {
                urls.push(SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                                          p.id, p.additional.thumbnail.cache_key, "sm"));
            }
        }
        return urls;
    }
}
