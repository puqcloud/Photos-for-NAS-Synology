import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Rectangle {
    id: root
    height: width + units.gu(5.5)
    color: "transparent"
    clip: true

    property string title: ""
    property int itemCount: 0
    property string dateText: ""
    property string coverUrl: ""
    property var albumData: null
    signal clicked(var album)

    property var fourCovers: []

    Component.onCompleted: {
        if (root.albumData && root.albumData.id > 0) {
            var pass = root.albumData.passphrase || "";
            SynoApi.getAlbumPhotos(mainView.serverUrl, mainView.sid, mainView.synotoken, root.albumData.id, 0, 4, function(err, data) {
                if (!err && data && data.list && data.list.length > 0) {
                    var urls = [];
                    var len = Math.min(4, data.list.length);
                    for (var i = 0; i < len; i++) {
                        var p = data.list[i];
                        if (p.additional && p.additional.thumbnail) {
                            urls.push(SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, p.additional.thumbnail.unit_id || p.id, p.additional.thumbnail.cache_key, "sm", "unit", pass));
                        }
                    }
                    root.fourCovers = urls;
                }
            }, pass);
        }
    }

    Rectangle {
        id: coverContainer
        width: parent.width
        height: parent.width
        radius: units.gu(0.8)
        clip: true
        color: "#EAECEF"

        // Single Cover (fallback)
        Image {
            id: coverImage
            anchors.fill: parent
            source: root.fourCovers.length === 0 ? root.coverUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: root.fourCovers.length === 0 && root.coverUrl.length > 0
        }

        // 2x2 Grid Cover
        Grid {
            anchors.fill: parent
            columns: 2
            rows: 2
            spacing: units.dp(1)
            visible: root.fourCovers.length > 0

            Repeater {
                model: root.fourCovers
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
            name: "image-x-generic"
            width: units.gu(4.5)
            height: units.gu(4.5)
            color: Theme.textMuted
            visible: root.fourCovers.length === 0 && (!coverImage.visible || coverImage.status !== Image.Ready)
        }
    }

    Column {
        anchors {
            top: coverContainer.bottom
            topMargin: units.gu(0.6)
            left: parent.left
            right: parent.right
        }
        spacing: units.dp(2)

        Label {
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: units.gu(1.6)
            font.weight: Font.DemiBold
            color: Theme.textDark
            text: root.title || i18n.tr("Unnamed Album")
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }

        Label {
            width: parent.width
            font.pixelSize: units.gu(1.4)
            color: Theme.textMuted
            text: {
                var parts = [];
                if (root.dateText) parts.push(root.dateText);
                parts.push(i18n.tr("%1 items").arg(root.itemCount));
                return parts.join("  ");
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.albumData) {
                root.clicked(root.albumData);
            }
        }
    }
}
