import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

BottomSheet {
    id: sheet
    contentHeight: units.gu(60)

    property var itemIds: []
    property var albumsModel: []
    signal albumCreated(string albumName)

    function openSheet() {
        sheet.open();
        loadAlbums();
    }

    function loadAlbums() {
        SynoApi.getAlbums(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 100, function(err, data) {
            if (!err && data && data.list) {
                albumsModel = data.list;
            }
        });
    }

    content: Column {
        anchors.fill: parent
        spacing: 0

        // Header
        Item {
            width: parent.width
            height: units.gu(6)

            Icon {
                name: "close"
                width: units.gu(3)
                height: units.gu(3)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textMuted
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onClicked: sheet.close()
                }
            }

            Label {
                text: i18n.tr("Add to Album")
                font.pixelSize: units.gu(2)
                font.weight: Font.DemiBold
                color: "#E57373" // matches the red in screenshots
                anchors.centerIn: parent
            }
        }

        Rectangle {
            width: parent.width
            height: units.dp(1)
            color: Theme.divider
        }

        // List
        ListView {
            width: parent.width
            height: parent.height - units.gu(6) - units.dp(1)
            clip: true

            model: [ { id: "create_new", name: i18n.tr("Create album") } ].concat(albumsModel)

            delegate: ListItem {
                height: units.gu(7)
                
                Row {
                    anchors.fill: parent
                    anchors.margins: units.gu(1)
                    spacing: units.gu(2)

                    Item {
                        width: units.gu(5)
                        height: units.gu(5)
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            visible: modelData.id === "create_new"
                            name: "add"
                            width: units.gu(3)
                            height: units.gu(3)
                            anchors.centerIn: parent
                            color: Theme.textDark
                        }

                        // Thumbnail for real albums
                        Image {
                            visible: modelData.id !== "create_new"
                            anchors.fill: parent
                            source: {
                                if (modelData.id === "create_new") return "";
                                var cacheKey = (modelData.additional && modelData.additional.thumbnail) ? modelData.additional.thumbnail.cache_key : "";
                                // Use the first item's ID as the cover if possible, or album id?
                                // Synology API for album cover is different. Let's just use empty or placeholder.
                                return ""; 
                            }
                        }
                        
                        Rectangle {
                            visible: modelData.id !== "create_new" && parent.source === ""
                            anchors.fill: parent
                            color: "#E0E0E0"
                            radius: units.gu(1)
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            text: modelData.name
                            font.pixelSize: units.gu(1.8)
                            color: Theme.textDark
                        }
                        Label {
                            visible: modelData.id !== "create_new"
                            text: modelData.item_count ? i18n.tr("%1 items").arg(modelData.item_count) : ""
                            font.pixelSize: units.gu(1.4)
                            color: Theme.textMuted
                        }
                    }
                }

                onClicked: {
                    if (modelData.id === "create_new") {
                        // Open create album dialog
                        mainView.showInputDialog(
                            i18n.tr("Album Name"),
                            "",
                            i18n.tr("OK"),
                            i18n.tr("CANCEL"),
                            function(text) {
                                if (!text) return;
                                mainView.showLoading(i18n.tr("Creating..."));
                                SynoApi.createAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken, text, sheet.itemIds, function(err, data) {
                                    mainView.hideLoading();
                                    if (err) {
                                        mainView.showToast(i18n.tr("Failed to create album"), true, false);
                                    } else {
                                        mainView.showToast(i18n.tr("Album created"), false, true);
                                        sheet.close();
                                        sheet.albumCreated(text);
                                    }
                                });
                            }
                        );
                    } else {
                        // Add to existing album
                        mainView.showLoading(i18n.tr("Adding to album..."));
                        SynoApi.addItemsToAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken, modelData.id, sheet.itemIds, function(err, data) {
                            mainView.hideLoading();
                            if (err) {
                                mainView.showToast(i18n.tr("Failed to add items"), true, false);
                            } else {
                                mainView.showToast(i18n.tr("Added to album"), false, true);
                                mainView.albumUpdated(modelData.id);
                                sheet.close();
                                sheet.albumCreated(modelData.name);
                            }
                        });
                    }
                }
            }
        }
    }
}
