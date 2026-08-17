import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme

Page {
    id: mainTabsPage
    header: Item {
        width: mainTabsPage.width
        height: 0
        visible: false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Item {
        id: tabContent
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: bottomNav.top
        }

        Loader {
            id: tab0Loader
            anchors.fill: parent
            source: "PhotosPage.qml"
            visible: bottomNav.currentTab === 0
        }

        Loader {
            id: tab1Loader
            anchors.fill: parent
            source: "AlbumsPage.qml"
            visible: bottomNav.currentTab === 1
        }

        Loader {
            id: tab2Loader
            anchors.fill: parent
            source: "SharingPage.qml"
            visible: bottomNav.currentTab === 2
        }

        Loader {
            id: tab3Loader
            anchors.fill: parent
            source: "MorePage.qml"
            visible: bottomNav.currentTab === 3
        }
    }

    SynoBottomNav {
        id: bottomNav
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        currentTab: 0
        onTabSelected: {
            if (index === 0 && tab0Loader.item && typeof tab0Loader.item.loadPhotos === "function") {
                if (tab0Loader.item.timelineView && tab0Loader.item.timelineView.filterIndex === 3) {
                    if (typeof tab0Loader.item.loadFolders === "function") tab0Loader.item.loadFolders();
                } else {
                    tab0Loader.item.loadPhotos();
                }
            } else if (index === 1 && tab1Loader.item && typeof tab1Loader.item.loadAlbums === "function") {
                tab1Loader.item.loadAlbums();
                if (typeof tab1Loader.item.loadSpecialCovers === "function") tab1Loader.item.loadSpecialCovers();
            } else if (index === 2 && tab2Loader.item && typeof tab2Loader.item.loadData === "function") {
                tab2Loader.item.loadData();
            }
        }
    }
}
