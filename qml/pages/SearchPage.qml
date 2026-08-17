import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Page {
    id: searchPage

    header: Item {
        width: searchPage.width
        height: 0
        visible: false
    }

    property var searchResults: []
    property bool isSearching: false
    property string currentQuery: ""
    property int columnCount: Math.max(3, Math.floor(width / units.gu(12)))
    property real cellSpacing: units.dp(2)
    property real cellSize: (width - (columnCount - 1) * cellSpacing) / columnCount

    // Top Search Bar
    Rectangle {
        id: searchBar
        anchors.top: parent.top
        width: parent.width
        height: units.gu(7)
        color: Theme.cardBackground
        z: 10

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: units.dp(1)
            color: Theme.divider
        }

        Row {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: units.gu(1.5)
            }
            spacing: units.gu(1.5)

            Rectangle {
                width: units.gu(4)
                height: units.gu(4)
                radius: units.gu(2)
                color: backMouse.pressed ? "#E5E5EA" : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    name: "back"
                    width: units.gu(2.4)
                    height: units.gu(2.4)
                    color: Theme.textDark
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    onClicked: pageStack.pop()
                }
            }

            Rectangle {
                width: parent.width - units.gu(6)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: "#F0F2F5"
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    anchors {
                        fill: parent
                        leftMargin: units.gu(1.5)
                        rightMargin: units.gu(1.5)
                    }
                    spacing: units.gu(1)

                    Icon {
                        name: "find"
                        width: units.gu(2.2)
                        height: units.gu(2.2)
                        color: Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: searchInput
                        width: parent.width - units.gu(7)
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: units.gu(1.8)
                        color: Theme.textDark
                        clip: true
                        focus: true
                        onAccepted: performSearch(text.trim())
                        onTextChanged: searchDebounce.restart()

                        Text {
                            text: i18n.tr("Search photos, videos...")
                            visible: !searchInput.text && !searchInput.inputMethodComposing
                            color: Theme.textMuted
                            font.pixelSize: units.gu(1.8)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Icon {
                        name: "clear"
                        width: units.gu(2)
                        height: units.gu(2)
                        color: Theme.textMuted
                        visible: searchInput.text.length > 0
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                searchInput.text = "";
                                searchPage.searchResults = [];
                                searchPage.currentQuery = "";
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: searchDebounce
        interval: 400
        onTriggered: {
            var q = searchInput.text.trim();
            if (q.length >= 2) performSearch(q);
        }
    }

    // Quick Filter Chips
    Item {
        id: chipsArea
        anchors.top: searchBar.bottom
        width: parent.width
        height: chipsArea.visible ? units.gu(5) : 0
        visible: searchPage.searchResults.length === 0 && !searchPage.isSearching && !searchPage.currentQuery

        Flickable {
            anchors.fill: parent
            contentWidth: chipRow.width + units.gu(3)
            clip: true

            Row {
                id: chipRow
                anchors.left: parent.left
                anchors.leftMargin: units.gu(1.5)
                anchors.verticalCenter: parent.verticalCenter
                spacing: units.gu(1)

                Repeater {
                    model: [
                        { text: i18n.tr("2025"), query: "2025" },
                        { text: i18n.tr("2024"), query: "2024" },
                        { text: i18n.tr("Videos"), query: "video" },
                        { text: i18n.tr("Screenshots"), query: "screenshot" },
                        { text: i18n.tr("Camera"), query: "jpg" },
                        { text: i18n.tr("Recent"), query: "" }
                    ]

                    Rectangle {
                        height: units.gu(3.6)
                        width: chipLabel.width + units.gu(2.5)
                        radius: units.gu(1.8)
                        color: chipMouse.pressed ? "#D0D4DC" : "#E4E7EC"

                        Label {
                            id: chipLabel
                            text: modelData.text
                            font.pixelSize: units.gu(1.5)
                            font.weight: Font.DemiBold
                            color: Theme.textDark
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            onClicked: {
                                if (modelData.query === "") {
                                    searchInput.text = "";
                                    searchPage.searchResults = [];
                                    searchPage.currentQuery = "";
                                    performRecent();
                                } else {
                                    searchInput.text = modelData.query;
                                    performSearch(modelData.query);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Results + Empty states
    Item {
        id: resultsArea
        anchors.top: chipsArea.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        PhotoTimelineView {
            anchors.fill: parent
            photos: searchPage.searchResults
            showFilterPill: false
            visible: searchPage.searchResults.length > 0
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: searchPage.isSearching
            visible: running
        }

        Column {
            anchors.centerIn: parent
            visible: searchPage.searchResults.length === 0 && !searchPage.isSearching && !searchPage.currentQuery
            spacing: units.gu(1)
            width: parent.width - units.gu(6)

            Icon {
                name: "find"
                width: units.gu(6)
                height: units.gu(6)
                color: "#D0D4DC"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Label {
                text: i18n.tr("Search your Synology library")
                font.pixelSize: units.gu(1.8)
                font.weight: Font.DemiBold
                color: Theme.textMuted
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.Wrap
            }
        }

        Column {
            anchors.centerIn: parent
            visible: searchPage.searchResults.length === 0 && !searchPage.isSearching && searchPage.currentQuery.length > 0
            spacing: units.gu(1)
            width: parent.width - units.gu(6)

            Icon {
                name: "image-missing"
                width: units.gu(6)
                height: units.gu(6)
                color: "#D0D4DC"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Label {
                text: i18n.tr("No items found for \"%1\"").arg(searchPage.currentQuery)
                font.pixelSize: units.gu(1.8)
                color: Theme.textMuted
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 3
            }
        }
    }

    function performSearch(query) {
        if (!query || query.length === 0) return;
        searchPage.currentQuery = query;
        searchPage.isSearching = true;
        searchPage.searchResults = [];

        SynoApi.searchItems(mainView.serverUrl, mainView.sid, mainView.synotoken, query, 0, 100, function(err, data) {
            searchPage.isSearching = false;
            if (err) {
                if (!mainView.handleApiError(err)) {
                    mainView.showErrorDialog(i18n.tr("Search Error"), err.message);
                }
            } else if (data && data.list) {
                searchPage.searchResults = data.list;
            }
        });
    }

    function performRecent() {
        searchPage.isSearching = true;
        searchPage.searchResults = [];
        SynoApi.getPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, 0, 100, function(err, data) {
            searchPage.isSearching = false;
            if (!err && data && data.list) {
                searchPage.searchResults = data.list.sort(function(a, b) {
                    return (b.indexed_time || b.time || 0) - (a.indexed_time || a.time || 0);
                });
            }
        });
    }
}
