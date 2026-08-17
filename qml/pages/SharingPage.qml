import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Item {
    id: sharingTab
    anchors.fill: parent

    property int subTab: 0
    property var sharedWithMe: []
    property var sharedWithOthers: []
    property bool loading: false

    property real itemSpacing: units.gu(1)
    property int columnCount: sharingTab.width > units.gu(60) ? 4 : (sharingTab.width > units.gu(40) ? 3 : 2)

    function loadData() {
        if (!mainView.sid) return;
        loading = true;
        mainView.showLoading(i18n.tr("Loading sharing..."));
        
        var reqCount = 2;
        var checkDone = function() {
            reqCount--;
            if (reqCount <= 0) {
                loading = false;
                mainView.hideLoading();
            }
        };

        SynoApi.getSharedWithMeAlbums(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 100, function(err, data) {
            if (!err && data && data.list) {
                sharedWithMe = data.list;
            }
            checkDone();
        });
        
        SynoApi.getSharedWithOthersAlbums(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 100, function(err, data) {
            if (!err && data && data.list) {
                sharedWithOthers = data.list;
            }
            checkDone();
        });
    }

    Component.onCompleted: {
        loadData();
    }

    Connections {
        target: mainView
        onSidChanged: if (mainView.sid) loadData()
        onItemDeleted: loadData()
        onAlbumDeleted: loadData()
        onAlbumUpdated: loadData()
    }

    Column {
        anchors.fill: parent

        SynoHeader {
            title: i18n.tr("Sharing")
            showSearch: true
            showRefresh: true
            showMore: true
            onRefreshClicked: loadData()
            onSearchClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
        }

        // Sub-tabs: WITH ME | WITH OTHERS
        Rectangle {
            width: parent.width
            height: units.gu(5.5)
            color: Theme.background

            Row {
                anchors.fill: parent

                Repeater {
                    model: [i18n.tr("WITH ME"), i18n.tr("WITH OTHERS")]

                    Item {
                        width: parent.width / 2
                        height: parent.height

                        Label {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: units.gu(1.6)
                            font.weight: sharingTab.subTab === index ? Font.Bold : Font.DemiBold
                            color: sharingTab.subTab === index ? Theme.textDark : Theme.textMuted
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.8
                            height: units.dp(2.5)
                            color: Theme.primary
                            visible: sharingTab.subTab === index
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: sharingTab.subTab = index
                        }
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

        // Content Area
        Item {
            width: parent.width
            height: parent.height - units.gu(11.5)
            
            Flickable {
                anchors.fill: parent
                contentWidth: parent.width
                contentHeight: albumFlow.height + units.gu(4)
                clip: true
                visible: (sharingTab.subTab === 0 && sharedWithMe && sharedWithMe.length > 0) || (sharingTab.subTab === 1 && sharedWithOthers && sharedWithOthers.length > 0)
                
                Flow {
                    id: albumFlow
                    width: parent.width - units.gu(4)
                    anchors.top: parent.top
                    anchors.topMargin: units.gu(2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: sharingTab.itemSpacing

                    Repeater {
                        model: sharingTab.subTab === 0 ? sharedWithMe : sharedWithOthers

                        AlbumCard {
                            width: (albumFlow.width - sharingTab.itemSpacing * (sharingTab.columnCount - 1)) / sharingTab.columnCount
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
                                if (modelData.additional && modelData.additional.thumbnail && modelData.additional.thumbnail.cache_key && modelData.additional.thumbnail.unit_id) {
                                    return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                                                          modelData.additional.thumbnail.unit_id, modelData.additional.thumbnail.cache_key, "m", "unit", modelData.passphrase || "");
                                }
                                return "";
                            }
                            onClicked: {
                                pageStack.push(Qt.resolvedUrl("AlbumDetailPage.qml"), { 
                                    albumData: modelData, 
                                    isReadOnly: sharingTab.subTab === 0 
                                });
                            }
                        }
                    }
                }
            }

            // Empty state placeholder
            Column {
                anchors.centerIn: parent
                spacing: units.gu(2)
                width: Math.min(parent.width - units.gu(6), units.gu(40))
                visible: (sharingTab.subTab === 0 && (!sharedWithMe || sharedWithMe.length === 0)) || (sharingTab.subTab === 1 && (!sharedWithOthers || sharedWithOthers.length === 0))

                Icon {
                    name: "system-users"
                    width: units.gu(8)
                    height: units.gu(8)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.primary
                }

                Label {
                    text: i18n.tr("No shared albums")
                    font.pixelSize: units.gu(2.2)
                    font.weight: Font.Bold
                    color: Theme.textDark
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Label {
                    text: i18n.tr("Photos and albums shared with you will appear here.")
                    font.pixelSize: units.gu(1.6)
                    color: Theme.textMuted
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
            }
            
            LoadingOverlay {
                visible: sharingTab.loading
                message: i18n.tr("Loading...")
            }
        }
    }
}
