import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme

Rectangle {
    id: root
    clip: true

    property string thumbnailUrl: ""
    property var photoData: null
    property bool selectionMode: false
    property bool isSelected: false
    property bool showBackupBadge: false

    property string queueStatus: {
        if (!root.photoData || !root.photoData.isLocal) return "";
        var map = typeof backupManager !== "undefined" ? backupManager.queueMap : null;
        if (!map) return "";
        return map[root.photoData.localPath] || "";
    }
    property color placeholderColor: {
        if (!photoData || !photoData.id) return "#EAECEF";
        var s = String(photoData.id);
        var h = 0;
        for (var i = 0; i < s.length; i++) {
            h = (h * 31 + s.charCodeAt(i)) & 0xFFFFFFFF;
        }
        var r = (h & 0xFF);
        var g = ((h >> 8) & 0xFF);
        var b = ((h >> 16) & 0xFF);
        return Qt.rgba(0.45 + r / 510, 0.45 + g / 510, 0.45 + b / 510, 1.0);
    }

    color: image.status === Image.Ready ? "transparent" : placeholderColor
    signal clicked(var item)
    signal pressAndHold(var item)

    Image {
        id: image
        anchors.fill: parent
        source: root.thumbnailUrl
        sourceSize.width: 256
        sourceSize.height: 256
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: status === Image.Ready ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    ActivityIndicator {
        anchors.centerIn: parent
        running: image.status === Image.Loading
        visible: running
        width: units.gu(2.5)
        height: units.gu(2.5)
    }

    Icon {
        anchors.centerIn: parent
        name: "image-missing"
        visible: image.status === Image.Error
            && !(root.photoData && root.photoData.type === "video")
        width: units.gu(2.5)
        height: units.gu(2.5)
        color: Theme.textMuted
    }

    // Videos without a preview (not yet generated locally or on the
    // server): show a video icon instead of an empty square
    Icon {
        anchors.centerIn: parent
        name: "camcorder"
        visible: !!root.photoData && root.photoData.type === "video"
            && image.status !== Image.Ready
        width: units.gu(4)
        height: units.gu(4)
        color: Qt.rgba(0, 0, 0, 0.35)
        z: 1
    }

    // Video duration badge (if video)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: units.dp(4)
        height: units.gu(2.2)
        width: videoRow.width + units.gu(1)
        radius: units.gu(0.4)
        color: "#99000000"
        visible: !!(root.photoData && root.photoData.type === "video")

        Row {
            id: videoRow
            anchors.centerIn: parent
            spacing: units.dp(3)

            Label {
                text: "▶"
                font.pixelSize: units.gu(1.1)
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                text: {
                    if (!root.photoData || !root.photoData.additional || !root.photoData.additional.video_meta) return "";
                    var ms = root.photoData.additional.video_meta.duration || 0;
                    var sec = Math.floor(ms / 1000);
                    var m = Math.floor(sec / 60);
                    var s = Math.floor(sec % 60);
                    return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
                }
                font.pixelSize: units.gu(1.2)
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
                visible: text.length > 0
            }
        }
    }

    // Backup state badge
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: units.dp(4)
        width: units.gu(2.6)
        height: units.gu(2.6)
        radius: units.gu(0.6)
        color: "#B3000000"
        visible: root.showBackupBadge && !!root.photoData
        opacity: root.photoData && !root.photoData.isLocal ? 0.6 : 1.0

        Icon {
            id: backupStateIcon
            anchors.centerIn: parent
            name: {
                if (!root.photoData || !root.photoData.isLocal) return "weather-clouds-symbolic";
                var qs = root.queueStatus;
                if (qs === "uploading" || qs === "queued") return "sync";
                if (root.photoData.isBackedUp) return "tick";
                return "weather-clouds-symbolic";
            }
            width: units.gu(1.8)
            height: units.gu(1.8)
            color: {
                if (!root.photoData || !root.photoData.isLocal) return "#ffffff";
                var qs = root.queueStatus;
                if (qs === "uploading" || qs === "queued") return "#7CFC00";
                if (root.photoData.isBackedUp) return "#7CFC00";
                return "#FF5252";
            }

            RotationAnimator on rotation {
                running: root.queueStatus === "uploading"
                from: 0
                to: 360
                duration: 1600
                loops: Animation.Infinite
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#66000000"
        visible: root.isSelected
        z: 2
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: units.dp(6)
        width: units.gu(2.4)
        height: units.gu(2.4)
        radius: width / 2
        color: root.isSelected ? Theme.primary : "transparent"
        border.color: "#ffffff"
        border.width: units.dp(2)
        visible: root.selectionMode
        z: 3

        Icon {
            anchors.centerIn: parent
            name: "tick"
            width: units.gu(1.6)
            height: units.gu(1.6)
            color: "#ffffff"
            visible: root.isSelected
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: {
            if (root.selectionMode) {
                // Let the parent handle selection
                root.clicked(root.photoData);
            } else {
                root.clicked(root.photoData);
            }
        }
        onPressAndHold: {
            if (!root.selectionMode) {
                root.pressAndHold(root.photoData);
            }
        }
    }
}
