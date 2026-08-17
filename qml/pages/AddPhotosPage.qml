import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Page {
    id: addPhotosPage
    header: Item { width: 0; height: 0; visible: false }

    property int albumId: 0
    property string albumName: ""
    property var allPhotos: []
    property var selectedIds: []
    property bool isSelectionMode: true

    Component.onCompleted: {
        loadAllPhotos();
    }

    // Header
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: units.gu(6)
        color: Theme.cardBackground
        z: 10

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: units.dp(1)
            color: Theme.divider
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: units.gu(1)
            anchors.rightMargin: units.gu(1)

            Rectangle {
                id: cancelBtnRect
                width: units.gu(4); height: units.gu(4)
                radius: units.gu(2)
                color: cancelBtn.pressed ? "#E5E5EA" : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                Icon {
                    anchors.centerIn: parent
                    name: "close"; width: units.gu(2.5); height: units.gu(2.5)
                    color: Theme.textDark
                }
                MouseArea {
                    id: cancelBtn
                    anchors.fill: parent
                    onClicked: pageStack.pop()
                }
            }

            Rectangle {
                id: doneBtnRect
                width: doneLabel.width + units.gu(3); height: units.gu(4)
                radius: units.gu(2)
                color: addPhotosPage.selectedIds.length > 0 ? Theme.primary : "#CCCCCC"
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                Label {
                    id: doneLabel
                    text: i18n.tr("Done (%1)").arg(addPhotosPage.selectedIds.length)
                    font.pixelSize: units.gu(1.6); font.weight: Font.DemiBold
                    color: "#ffffff"; anchors.centerIn: parent
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (addPhotosPage.selectedIds.length === 0) return;
                        mainView.showLoading(i18n.tr("Adding photos..."));
                        SynoApi.addItemsToAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken,
                            addPhotosPage.albumId, addPhotosPage.selectedIds, function(err) {
                            mainView.hideLoading();
                            if (err) {
                                mainView.showToast(i18n.tr("Failed to add photos"), true, false);
                            } else {
                                mainView.showToast(i18n.tr("%1 photos added").arg(addPhotosPage.selectedIds.length), false, true);
                                mainView.albumUpdated(addPhotosPage.albumId);
                                pageStack.pop();
                            }
                        });
                    }
                }
            }

            Label {
                text: i18n.tr("Add to %1").arg(addPhotosPage.albumName || i18n.tr("Album"))
                font.pixelSize: units.gu(2); font.weight: Font.DemiBold
                color: Theme.textDark
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: cancelBtnRect.right
                anchors.right: doneBtnRect.left
                anchors.leftMargin: units.gu(1)
                anchors.rightMargin: units.gu(1)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // Photo grid in selection mode
    Item {
        anchors.top: parent.top
        anchors.topMargin: units.gu(6)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        GridView {
            id: photoGrid
            anchors.fill: parent
            anchors.margins: units.gu(1)
            cellWidth: width / Math.max(3, Math.floor(width / units.gu(11)))
            cellHeight: cellWidth
            model: addPhotosPage.allPhotos
            clip: true

            delegate: Item {
                width: photoGrid.cellWidth - units.dp(2)
                height: photoGrid.cellHeight - units.dp(2)

                PhotoGridItem {
                    anchors.fill: parent
                    photoData: modelData
                    selectionMode: true
                    isSelected: addPhotosPage.selectedIds.indexOf(modelData.id) !== -1
                    thumbnailUrl: {
                        var cacheKey = (modelData.additional && modelData.additional.thumbnail)
                            ? modelData.additional.thumbnail.cache_key : "";
                        return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                                      modelData.id, cacheKey, "sm");
                    }
                    onClicked: {
                        var idx = addPhotosPage.selectedIds.indexOf(modelData.id);
                        var arr = addPhotosPage.selectedIds.slice();
                        if (idx === -1) arr.push(modelData.id);
                        else arr.splice(idx, 1);
                        addPhotosPage.selectedIds = arr;
                    }
                }
            }
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: addPhotosPage.allPhotos.length === 0
            visible: running
        }
    }

    function loadAllPhotos() {
        SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 500, function(err, data) {
            if (!err && data && data.list) {
                addPhotosPage.allPhotos = data.list;
            }
        });
    }
}
