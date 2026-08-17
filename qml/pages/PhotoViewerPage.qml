import QtQuick 2.9
import Ubuntu.Components 1.3
import QtMultimedia 5.6
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi
import "../js/Storage.js" as Storage

Item {
    id: photoViewerPage
    anchors.fill: parent
    visible: false
    z: 1000
    opacity: visible ? 1.0 : 0.0
    focus: visible

    Keys.onBackPressed: close()
    Keys.onEscapePressed: close()

    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    function resetDetails() {
        photoViewerPage.itemExif = "";
        photoViewerPage.itemDate = "";
        photoViewerPage.itemSize = "";
        photoViewerPage.itemRes = "";
        photoViewerPage.itemLocation = "";
    }

    // Server asset id for a photo, or "" when it exists only on the device.
    function serverImageId(item) {
        if (!item) return "";
        var id = String(item.id || "");
        if (id.length > 0 && id.indexOf("local:") !== 0) return id;
        return String(item.remoteThumbId || "");
    }

    function open() {
        photoViewerPage.showDetails = false;
        photoViewerPage.visible = true;
        photoViewerPage.closing = false;
        photoViewerPage.updateVideoAspect();
        photoViewerPage.forceActiveFocus();
        // Wait for the layout pass so the video surface gets a real size
        openDelayTimer.restart();
    }

    Timer {
        id: openDelayTimer
        interval: 250
        repeat: false
        onTriggered: photoViewerPage.loadStreamLink()
    }

    function stopPlayback() {
        console.log("PhotoViewer: stopping playback immediately");
        photoViewerPage.wantPlay = false;
        photoViewerPage.hasPlayedOnce = false;
        photoViewerPage.videoEnded = false;
        openDelayTimer.stop();
        streamWatchdog.stop();
        streamTeardownTimer.stop();
        if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
            videoPlayer.pause();
        }
        videoPlayer.stop();
        photoViewerPage.proxyUrl = "";
        photoViewerPage.streamLink = null;
        if (typeof backupEngine !== "undefined" && typeof backupEngine.mediaProxyShutdown === "function") {
            backupEngine.mediaProxyShutdown();
        }
    }

    function close() {
        console.log("PhotoViewer: closing viewer");
        photoViewerPage.visible = false;
        photoViewerPage.closing = true;
        dragOffsetAnim.stop();
        photoViewerPage.dragOffset = 0;
        photoViewerPage.pagerAnimating = false;
        photoViewerPage.pagerCommitPending = false;
        photoViewerPage.neighborPhoto = null;
        photoViewerPage.draggingPhoto = false;
        stopPlayback();
    }

    function loadStreamLink() {
        if (!isVideo || !currentPhoto) return;

        // Defer until the viewer is laid out: creating the video surface while
        // the page is still 0x0 breaks aspect ratio on Ubuntu Touch
        if (!photoViewerPage.visible) {
            openDelayTimer.restart();
            return;
        }

        var itemId = currentPhoto.id;

        // Local video: play from the app cache, because Media Hub blocks
        // direct access to ~/Pictures and ~/Videos for confined apps
        if (photoViewerPage.isPureLocal && currentPhoto.localPath) {
            var playUrl = "file://" + currentPhoto.localPath;
            if (typeof backupEngine !== "undefined"
                    && typeof backupEngine.cacheMediaForPlayback === "function"
                    && currentPhoto.localPath) {
                playUrl = backupEngine.cacheMediaForPlayback(currentPhoto.localPath);
            }
            streamLink = { itemId: itemId, local: true, originalUrl: playUrl };
            return;
        }

        if (!mainView.sid) return;
        if (streamLink && streamLink.itemId === itemId) return;

        // The Synology streaming URL is stateless (sid + SynoToken in the
        // query), so it can be built synchronously. Media Hub cannot fetch
        // https itself, so it goes through the local http proxy.
        var streamTarget = SynoApi.getStreamingUrl(mainView.serverUrl, mainView.sid,
                                                   mainView.synotoken, itemId, photoViewerPage.passphrase);
        if (typeof backupEngine !== "undefined" && typeof backupEngine.mediaProxyUrl === "function") {
            photoViewerPage.proxyUrl = backupEngine.mediaProxyUrl(streamTarget) || streamTarget;
        } else {
            photoViewerPage.proxyUrl = streamTarget;
        }
        photoViewerPage._proxyEpoch = photoViewerPage._proxyEpoch + 1;
        photoViewerPage.streamLink = { itemId: itemId, local: false, originalUrl: streamTarget };
    }

    property var photoList: (mainView.viewerPhotoList && mainView.viewerPhotoList.length > 0) ? mainView.viewerPhotoList : []
    property int currentIndex: mainView.viewerCurrentIndex
    property var currentPhoto: (photoList && photoList.length > currentIndex) ? photoList[currentIndex] : null
    // When a server-sourced image fails (network hiccup), fall back to the
    // local copy once; reset in onCurrentPhotoChanged below
    property bool useLocalFallback: false
    property string passphrase: ""
    property int albumId: -1
    property bool isReadOnly: false
    property bool showDetails: false
    property bool showUi: true
    property bool isVideo: currentPhoto && currentPhoto.type === "video"
    property bool isPureLocal: currentPhoto && currentPhoto.id && String(currentPhoto.id).indexOf("local:") === 0
    property var streamLink: null
    property string proxyUrl: ""
    property bool videoErrorShown: false
    property bool downloadFallbackTried: false
    property bool downloadingVideo: false
    property bool hasPlayedOnce: false
    property bool closing: false
    property bool wantPlay: false
    property bool videoEnded: false
    property real downloadPercent: 0
    property real videoAspect: 0 // display aspect (width/height); 0 = unknown

    // Pager (swipe between photos)
    property real dragOffset: 0
    property real panX: 0
    property real panY: 0
    property bool draggingPhoto: false
    property bool pagerAnimating: false
    property var neighborPhoto: null
    property bool pagerCommitPending: false
    property bool pagerCommitNext: false

    // Stream teardown: the media player is stopped and the source detached
    // first; only after a grace period (so the Aal backend fully releases
    // the HTTP stream) do we kill the proxy. Aborting the proxy while
    // GStreamer is still reading crashes the app.
    property var _pendingTeardownLink: null
    property int _proxyEpoch: 0
    property int _teardownEpoch: -1

    Timer {
        id: streamTeardownTimer
        interval: 800
        repeat: false
        onTriggered: {
            var link = photoViewerPage._pendingTeardownLink;
            photoViewerPage._pendingTeardownLink = null;
            if (!link || link.local) return;
            // A newer stream registered a proxy URL in the meantime: leave
            // the proxy alone, the old connection dies with its player
            if (photoViewerPage._proxyEpoch !== photoViewerPage._teardownEpoch) return;
            if (typeof backupEngine !== "undefined"
                    && typeof backupEngine.mediaProxyShutdown === "function") {
                backupEngine.mediaProxyShutdown();
            }
        }
    }

    function scheduleStreamTeardown(link) {
        if (!link || link.local) return;
        photoViewerPage._pendingTeardownLink = link;
        photoViewerPage._teardownEpoch = photoViewerPage._proxyEpoch;
        streamTeardownTimer.restart();
    }

    function updateVideoAspect() {
        var asp = 0;
        if (currentPhoto && currentPhoto.isLocal && currentPhoto.localPath
                && typeof backupEngine !== "undefined"
                && typeof backupEngine.mediaDimensions === "function") {
            var dims = backupEngine.mediaDimensions(currentPhoto.localPath);
            if (dims) {
                var parts = dims.split("x");
                if (parts.length === 2) {
                    var w = parseInt(parts[0], 10);
                    var h = parseInt(parts[1], 10);
                    if (w > 0 && h > 0) asp = w / h;
                }
            }
        }
        if (asp <= 0 && currentPhoto && currentPhoto.additional
                && currentPhoto.additional.resolution
                && currentPhoto.additional.resolution.width > 0
                && currentPhoto.additional.resolution.height > 0) {
            asp = currentPhoto.additional.resolution.width / currentPhoto.additional.resolution.height;
        }
        photoViewerPage.videoAspect = asp;
    }

    // Media Hub sometimes reports Playing without ever delivering media,
    // so watch for that and step through the fallback chain
    Timer {
        id: streamWatchdog
        interval: 7000
        repeat: false
        onTriggered: {
            var hasMedia = videoPlayer.duration > 0 && videoPlayer.position >= 0;
            if (photoViewerPage.closing || photoViewerPage.downloadingVideo) return;
            if (!photoViewerPage.streamLink || photoViewerPage.streamLink.local) return;
            // Once the stream has proven itself, temporary position hiccups
            // (e.g. after a seek) must not trigger the fallback
            if (photoViewerPage.hasPlayedOnce) return;
            if (videoPlayer.playbackState === MediaPlayer.PlayingState && hasMedia) return;
            handleStreamFailure();
        }
    }

    // Pager slide animation (moves dragOffset; imageContainer and the
    // neighbor photo follow it through property bindings)
    NumberAnimation {
        id: dragOffsetAnim
        target: photoViewerPage
        property: "dragOffset"
        duration: 220
        easing.type: Easing.OutCubic
        onStopped: {
            var commit = photoViewerPage.pagerCommitPending;
            photoViewerPage.pagerCommitPending = false;
            if (commit && !photoViewerPage.closing) {
                if (photoViewerPage.pagerCommitNext) {
                    photoViewerPage.nextPhoto();
                } else {
                    photoViewerPage.prevPhoto();
                }
            }
            photoViewerPage.pagerAnimating = false;
            photoViewerPage.dragOffset = 0;
            photoViewerPage.neighborPhoto = null;
            photoViewerPage.draggingPhoto = false;
        }
    }

    function handleStreamFailure() {
        var link = photoViewerPage.streamLink;
        if (photoViewerPage.closing || !link || link.local || photoViewerPage.downloadingVideo) return;
        if (!photoViewerPage.downloadFallbackTried) {
            startDownloadFallback();
        } else if (!photoViewerPage.videoErrorShown) {
            photoViewerPage.videoErrorShown = true;
            mainView.showErrorDialog(
                i18n.tr("Video Playback Error"),
                i18n.tr("This video cannot be played on this device. You can try opening it in the browser."),
                i18n.tr("Open in Browser"),
                i18n.tr("Cancel"),
                function() {
                    if (photoViewerPage.streamLink && !photoViewerPage.streamLink.local) {
                        Qt.openUrlExternally(photoViewerPage.streamLink.originalUrl);
                    }
                },
                null
            );
        }
    }

    function startDownloadFallback() {
        if (photoViewerPage.closing || photoViewerPage.downloadingVideo
                || photoViewerPage.downloadFallbackTried) return;
        if (typeof backupEngine === "undefined"
                || typeof backupEngine.downloadMediaForPlayback !== "function") return;
        var link = photoViewerPage.streamLink;
        if (!link || link.local) return;
        var dlUrl = link.originalUrl;
        if (!dlUrl) return;
        photoViewerPage.downloadFallbackTried = true;
        photoViewerPage.downloadingVideo = true;
        photoViewerPage.downloadPercent = 0;
        var dlId = photoViewerPage.currentPhoto ? photoViewerPage.currentPhoto.id : "video";
        backupEngine.downloadMediaForPlayback(dlUrl,
            "playback-dl-" + String(dlId).replace(/[^a-zA-Z0-9-]/g, "_") + ".mp4");
    }

    Connections {
        target: typeof backupEngine !== "undefined" ? backupEngine : null
        onMediaDownloadProgress: {
            if (photoViewerPage.downloadingVideo && total > 0) {
                photoViewerPage.downloadPercent = received * 100 / total;
            }
        }
        onMediaDownloaded: {
            photoViewerPage.downloadingVideo = false;
            streamWatchdog.stop();
            if (photoViewerPage.closing) return;
            if (!success) {
                photoViewerPage.videoErrorShown = true;
                mainView.showErrorDialog(
                    i18n.tr("Video Playback Error"),
                    i18n.tr("This video cannot be played on this device. You can try opening it in the browser."),
                    i18n.tr("Open in Browser"),
                    i18n.tr("Cancel"),
                    function() {
                        if (photoViewerPage.streamLink && !photoViewerPage.streamLink.local) {
                            Qt.openUrlExternally(photoViewerPage.streamLink.originalUrl);
                        }
                    },
                    null
                );
                return;
            }
            if (typeof backupEngine !== "undefined" && typeof backupEngine.mediaProxyShutdown === "function") {
                backupEngine.mediaProxyShutdown();
            }
            photoViewerPage.proxyUrl = "";
            photoViewerPage.hasPlayedOnce = false;
            photoViewerPage.wantPlay = true;
            photoViewerPage.streamLink = {
                itemId: photoViewerPage.currentPhoto ? photoViewerPage.currentPhoto.id : "",
                local: true,
                originalUrl: "file://" + filePath
            };
            photoViewerPage.videoErrorShown = false;
            videoPlayer.play();
        }
    }

    onStreamLinkChanged: {
        photoViewerPage.hasPlayedOnce = false;
        photoViewerPage.wantPlay = !!photoViewerPage.streamLink;
        photoViewerPage.videoEnded = false;
        if (photoViewerPage.streamLink && !photoViewerPage.streamLink.local) {
            streamWatchdog.restart();
        } else {
            streamWatchdog.stop();
        }
    }

    onCurrentPhotoChanged: {
        resetZoom();
        videoErrorShown = false;
        downloadFallbackTried = false;
        downloadingVideo = false;
        hasPlayedOnce = false;
        downloadPercent = 0;
        streamWatchdog.stop();
        photoViewerPage.useLocalFallback = false;
        photoViewerPage.dragOffset = 0;
        photoViewerPage.panX = 0;
        photoViewerPage.panY = 0;
        photoViewerPage.draggingPhoto = false;
        photoViewerPage.pagerAnimating = false;
        photoViewerPage.neighborPhoto = null;
        stopPlayback();
        photoViewerPage.videoAspect = 0;
        photoViewerPage.updateVideoAspect();

        // Refresh the info panel data if it is open on the new photo.
        if (photoViewerPage.showDetails && currentPhoto) {
            loadItemDetail(currentPhoto.id);
        }
        if (photoViewerPage.visible && isVideo) {
            photoViewerPage.wantPlay = true;
            openDelayTimer.restart();
        }
    }

    onVisibleChanged: {
        if (!visible) {
            stopPlayback();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // --- PHOTO VIEWER ---
    // Plain Item instead of a Flickable: zoom/pan are managed manually so
    // the image follows the fingers exactly, without bounce/overshoot
    // interference (a Flickable both fights the pinch math and drifts the
    // focal point when its content moves)
    Item {
        id: flickable
        anchors.fill: parent
        clip: true
        visible: !photoViewerPage.isVideo

        Item {
            id: imageContainer
            x: photoViewerPage.dragOffset + photoViewerPage.panX
            y: photoViewerPage.panY
            // The container IS the zoom: images fill it at scale 1, so the
            // zoom never skews toward a corner. Panning is done via panX/panY,
            // which the pinch handler keeps anchored to the fingers.
            width: flickable.width * pinchArea.scale
            height: flickable.height * pinchArea.scale

            // Instant Preview Thumbnail (loads from cache instantly in 0ms)
            Image {
                id: thumbPreview
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: true
                source: {
                    if (!currentPhoto || isVideo) return "";
                    // Prefer the cached server preview for photos that exist
                    // on the server; decode the local file only when there is
                    // no server copy (or the server request failed)
                    var rid = photoViewerPage.useLocalFallback ? "" : photoViewerPage.serverImageId(currentPhoto);
                    // Local photos always decode the device file first: the
                    // server may not have generated the thumbnail for a
                    // freshly uploaded item yet
                    if (currentPhoto.isLocal && !isVideo) rid = "";
                    if (rid) {
                        var cacheKey = (currentPhoto.additional && currentPhoto.additional.thumbnail) ? currentPhoto.additional.thumbnail.cache_key : "";
                        return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, rid, cacheKey, "m", "unit", photoViewerPage.passphrase);
                    }
                    if (currentPhoto.localPath) {
                        return "image://syno/local/" + encodeURIComponent(currentPhoto.localPath) + "/m";
                    }
                    return "";
                }
                visible: fullImage.status !== Image.Ready
                onStatusChanged: {
                    if (status === Image.Error && !photoViewerPage.useLocalFallback
                            && currentPhoto && currentPhoto.localPath
                            && photoViewerPage.serverImageId(currentPhoto)) {
                        photoViewerPage.useLocalFallback = true;
                    }
                }
            }

            // High-res Image
            Image {
                id: fullImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                source: {
                    if (!currentPhoto || isVideo) return "";
                    // Same server-preview preference as the thumbnail: this
                    // removes the slow local full-res decode for photos that
                    // are backed up to the server
                    var rid = photoViewerPage.useLocalFallback ? "" : photoViewerPage.serverImageId(currentPhoto);
                    // Local photos always decode the device file first: the
                    // server may not have generated the thumbnail for a
                    // freshly uploaded item yet
                    if (currentPhoto.isLocal && !isVideo) rid = "";
                    if (rid) {
                        var cacheKey = currentPhoto.additional && currentPhoto.additional.thumbnail ? currentPhoto.additional.thumbnail.cache_key : "";
                        return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, rid, cacheKey, "xl", "unit", photoViewerPage.passphrase);
                    }
                    if (currentPhoto.localPath) {
                        return "image://syno/local/" + encodeURIComponent(currentPhoto.localPath) + "/xl";
                    }
                    return "";
                }
                opacity: status === Image.Ready ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                onStatusChanged: {
                    if (status === Image.Error && !photoViewerPage.useLocalFallback
                            && currentPhoto && currentPhoto.localPath
                            && photoViewerPage.serverImageId(currentPhoto)) {
                        photoViewerPage.useLocalFallback = true;
                    }
                }

                Icon {
                    anchors.centerIn: parent
                    name: "image-missing"
                    color: Theme.textMuted
                    width: units.gu(6)
                    height: units.gu(6)
                    visible: fullImage.status === Image.Error
                }
            }

            // Preloader Spinner
            ActivityIndicator {
                anchors.centerIn: parent
                running: fullImage.status === Image.Loading
                visible: running
                z: 10
            }
        }

        // Neighbor photo sliding in while swiping (thumbnail only, fast)
        Item {
            id: neighborContainer
            width: flickable.width
            height: flickable.height
            x: photoViewerPage.dragOffset < 0
                ? photoViewerPage.dragOffset + flickable.width
                : photoViewerPage.dragOffset - flickable.width
            visible: photoViewerPage.neighborPhoto !== null
                && (photoViewerPage.draggingPhoto || photoViewerPage.pagerAnimating)
                && pinchArea.scale <= 1.0

            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                source: {
                    var n = photoViewerPage.neighborPhoto;
                    if (!n) return "";
                    var rid = photoViewerPage.serverImageId(n);
                    if (rid) {
                        var cacheKey = (n.additional && n.additional.thumbnail) ? n.additional.thumbnail.cache_key : "";
                        return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, rid, cacheKey, "m", "unit", photoViewerPage.passphrase);
                    }
                    if (n.localPath) return "image://syno/local/" + encodeURIComponent(n.localPath) + "/m";
                    return "";
                }
            }
        }

        PinchArea {
            id: pinchArea
            anchors.fill: parent
            property real scale: 1.0
            property real minScale: 1.0
            property real maxScale: 4.0

            // Snapshot of the state at pinch start. The offset computation is
            // anchored to it, so the content point that was under the fingers
            // at the start stays under the fingers throughout the gesture.
            property real startScale: 1.0
            property real startPanX: 0
            property real startPanY: 0
            property real startCenterX: 0
            property real startCenterY: 0

            function clampPanX(v) {
                return Math.min(0, Math.max(flickable.width * (1 - pinchArea.scale), v));
            }
            function clampPanY(v) {
                return Math.min(0, Math.max(flickable.height * (1 - pinchArea.scale), v));
            }

            // Zooms toward a given viewport point: keeps the content under
            // that point stationary
            function zoomAt(px, py, newScale) {
                var ratio = newScale / pinchArea.scale;
                var nx = (px - photoViewerPage.panX) * ratio;
                var ny = (py - photoViewerPage.panY) * ratio;
                pinchArea.scale = newScale;
                photoViewerPage.panX = clampPanX(px - nx);
                photoViewerPage.panY = clampPanY(py - ny);
            }

            onPinchStarted: {
                if (photoViewerPage.isVideo) return;
                startScale = scale;
                startPanX = photoViewerPage.panX;
                startPanY = photoViewerPage.panY;
                startCenterX = pinch.center.x;
                startCenterY = pinch.center.y;
            }

            onPinchUpdated: {
                if (photoViewerPage.isVideo) return;
                // pinch.scale is cumulative since the gesture started, so the
                // new scale is computed from the start snapshot. The exponent
                // dampens the gesture for a slow, comfortable zoom.
                var factor = Math.pow(Math.max(0.01, pinch.scale), 0.35);
                var s = startScale * factor;
                if (s < minScale) s = minScale;
                if (s > maxScale) s = maxScale;
                var ratio = s / startScale;
                // Keep the content point that was under the fingers at the
                // pinch start under the current finger center
                var px = (startCenterX - startPanX) * ratio;
                var py = (startCenterY - startPanY) * ratio;
                scale = s;
                photoViewerPage.panX = clampPanX(pinch.center.x - px);
                photoViewerPage.panY = clampPanY(pinch.center.y - py);
            }

            onPinchFinished: {
                if (photoViewerPage.isVideo) return;
                // Snap the pan into the valid range after the final scale
                photoViewerPage.panX = clampPanX(photoViewerPage.panX);
                photoViewerPage.panY = clampPanY(photoViewerPage.panY);
            }

            MouseArea {
                id: mainMouseArea
                anchors.fill: parent
                property real startX: 0
                property real startY: 0
                property real panStartX: 0
                property real panStartY: 0
                property bool isSwipe: false
                property bool verticalIntent: false
                property bool panMoved: false

                onPressed: {
                    startX = mouse.x;
                    startY = mouse.y;
                    panStartX = photoViewerPage.panX;
                    panStartY = photoViewerPage.panY;
                    panMoved = false;
                    isSwipe = false;
                    verticalIntent = false;
                    if (photoViewerPage.pagerAnimating) return;
                    photoViewerPage.dragOffset = 0;
                    photoViewerPage.draggingPhoto = false;
                    photoViewerPage.neighborPhoto = null;
                }

                onPositionChanged: {
                    if (photoViewerPage.pagerAnimating) return;

                    // While zoomed, drag pans the image directly
                    if (pinchArea.scale > 1.0) {
                        var nx = panStartX + (mouse.x - startX);
                        var ny = panStartY + (mouse.y - startY);
                        photoViewerPage.panX = pinchArea.clampPanX(nx);
                        photoViewerPage.panY = pinchArea.clampPanY(ny);
                        if (Math.abs(mouse.x - startX) > units.gu(0.5)
                                || Math.abs(mouse.y - startY) > units.gu(0.5)) {
                            panMoved = true;
                        }
                        return;
                    }

                    var dx = mouse.x - startX;
                    var dy = mouse.y - startY;

                    if (photoViewerPage.isVideo) {
                        // Videos keep the simple flick gesture (no drag preview)
                        if (Math.abs(dx) > units.gu(3)) {
                            isSwipe = true;
                        }
                        return;
                    }

                    if (!isSwipe) {
                        if (Math.abs(dy) > units.gu(2.5) && Math.abs(dy) > Math.abs(dx)) {
                            verticalIntent = true;
                            return;
                        }
                        if (Math.abs(dx) > units.gu(1.5)) {
                            isSwipe = true;
                            photoViewerPage.draggingPhoto = true;
                        }
                    }
                    if (!isSwipe || !photoViewerPage.draggingPhoto) return;

                    var idx = mainView.viewerCurrentIndex;
                    var offset = dx;

                    // Rubber band at the edges of the list
                    if (offset < 0 && idx >= photoViewerPage.photoList.length - 1) {
                        offset = offset / 3;
                    } else if (offset > 0 && idx <= 0) {
                        offset = offset / 3;
                    }

                    if (photoViewerPage.neighborPhoto === null) {
                        if (offset < 0) {
                            photoViewerPage.neighborPhoto = idx < photoViewerPage.photoList.length - 1
                                ? photoViewerPage.photoList[idx + 1] : null;
                        } else {
                            photoViewerPage.neighborPhoto = idx > 0
                                ? photoViewerPage.photoList[idx - 1] : null;
                        }
                    }

                    photoViewerPage.dragOffset = offset;
                }

                onReleased: {
                    if (photoViewerPage.pagerAnimating) return;

                    if (photoViewerPage.draggingPhoto && photoViewerPage.dragOffset !== 0) {
                        var w = flickable.width;
                        var idx = mainView.viewerCurrentIndex;
                        var off = photoViewerPage.dragOffset;
                        var threshold = Math.min(w * 0.25, units.gu(18));
                        var commitNext = off < -threshold && idx < photoViewerPage.photoList.length - 1;
                        var commitPrev = off > threshold && idx > 0;

                        photoViewerPage.draggingPhoto = false;

                        if (commitNext || commitPrev) {
                            // Slide the current photo out and the neighbor in
                            photoViewerPage.pagerAnimating = true;
                            pagerCommitPending = true;
                            pagerCommitNext = commitNext;
                            dragOffsetAnim.to = commitNext ? -w : w;
                        } else {
                            // Snap back
                            photoViewerPage.pagerAnimating = true;
                            pagerCommitPending = false;
                            dragOffsetAnim.to = 0;
                        }
                        dragOffsetAnim.from = off;
                        dragOffsetAnim.restart();
                        return;
                    }

                    photoViewerPage.draggingPhoto = false;
                    photoViewerPage.dragOffset = 0;
                    photoViewerPage.neighborPhoto = null;

                    if (pinchArea.scale <= 1.0 && isSwipe) {
                        var deltaX = mouse.x - startX;
                        if (deltaX < -units.gu(5)) {
                            nextPhoto();
                        } else if (deltaX > units.gu(5)) {
                            prevPhoto();
                        }
                    } else if (!isSwipe && !verticalIntent && !panMoved) {
                        if (photoViewerPage.showDetails) {
                            photoViewerPage.showDetails = false;
                        } else {
                            photoViewerPage.showUi = !photoViewerPage.showUi;
                        }
                    }
                }

                onDoubleClicked: {
                    if (photoViewerPage.isVideo) return;
                    if (pinchArea.scale > 1.0) {
                        resetZoom();
                    } else {
                        // Zoom toward the double-tap point
                        pinchArea.zoomAt(mouse.x, mouse.y, 2.5);
                    }
                }
            }
        }
    }

    // --- VIDEO PLAYER ---
    Item {
        anchors.fill: parent
        visible: photoViewerPage.isVideo

        // Preloader: black overlay with a spinner, shown until the first
        // real frame of the current video arrives (hides stale frames and
        // blurry thumbnails from the previous video)
        Rectangle {
            id: videoPreloader
            anchors.fill: parent
            color: "#000000"
            visible: !photoViewerPage.hasPlayedOnce
            z: 2

            // Server thumbnail as a poster while the video is loading
            // (only when the video exists on the server)
            Image {
                id: videoPoster
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                source: {
                    if (!currentPhoto || !isVideo) return "";
                    // Local video: prefer a preview image stored next to the file if one exists
                    if (currentPhoto.isLocal && currentPhoto.localPath
                            && typeof backupEngine !== "undefined"
                            && typeof backupEngine.localVideoPreview === "function") {
                        var prev = backupEngine.localVideoPreview(currentPhoto.localPath);
                        if (prev) {
                            return "image://syno/local/" + encodeURIComponent(prev) + "/m";
                        }
                    }
                    if (!mainView.sid) return "";
                    var id = photoViewerPage.serverImageId(currentPhoto);
                    if (!id) return "";
                    var cacheKey = (currentPhoto.additional && currentPhoto.additional.thumbnail)
                        ? currentPhoto.additional.thumbnail.cache_key : (id + "_0");
                    return SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                                   id, cacheKey, "m", "unit", photoViewerPage.passphrase);
                }
                visible: source !== "" && status !== Image.Error
                opacity: 0.9
            }

            Column {
                anchors.centerIn: parent
                spacing: units.gu(1.5)

                ActivityIndicator {
                    running: videoPreloader.visible
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Label {
                    text: photoViewerPage.downloadingVideo
                        ? i18n.tr("Downloading video") + " " + Math.round(photoViewerPage.downloadPercent) + "%"
                        : i18n.tr("Loading video...")
                    color: "#ffffff"
                    font.pixelSize: units.gu(1.5)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        MediaPlayer {
            id: videoPlayer
            source: {
                if (!photoViewerPage.streamLink) return "";
                if (photoViewerPage.streamLink.local) return photoViewerPage.streamLink.originalUrl;
                return photoViewerPage.proxyUrl || "";
            }
            autoPlay: false
            onStatusChanged: {
                console.log("PhotoViewer: video status changed:", status, "playbackState:", playbackState, "pos:", position, "/", duration);
                if (duration > 0 && position >= 0) {
                    photoViewerPage.hasPlayedOnce = true;
                }
                // Auto-start / auto-resume after seek or status change
                if (photoViewerPage.wantPlay
                        && !photoViewerPage.closing
                        && playbackState !== MediaPlayer.PlayingState
                        && videoPlayer.source !== ""
                        && status !== MediaPlayer.InvalidMedia
                        && status !== MediaPlayer.NoMedia
                        && status !== MediaPlayer.EndOfMedia) {
                    console.log("PhotoViewer: triggering videoPlayer.play()");
                    videoPlayer.play();
                }
                if (status === MediaPlayer.EndOfMedia) {
                    console.log("PhotoViewer: video reached EndOfMedia");
                    // Do not auto-replay: wait for the user to press play again
                    photoViewerPage.wantPlay = false;
                    photoViewerPage.videoEnded = true;
                    videoPlayer.pause();
                    videoPlayer.seek(0);
                }
            }
            onPlaybackStateChanged: {
                console.log("PhotoViewer: playbackState changed to:", playbackState, "status:", status, "pos:", position);
                if (position >= 0 && duration > 0) {
                    photoViewerPage.hasPlayedOnce = true;
                }
                if (playbackState === MediaPlayer.PlayingState) {
                    if (typeof videoOutput !== "undefined" && typeof videoOutput.updateDynamicAspect === "function") {
                        videoOutput.updateDynamicAspect();
                    }
                }
            }
            onPositionChanged: {
                // The position becomes valid without a media-status change,
                // so track the first real frame here too
                if (position >= 0 && duration > 0 && !photoViewerPage.hasPlayedOnce) {
                    photoViewerPage.hasPlayedOnce = true;
                }
            }
            onError: {
                console.log("PhotoViewer: videoPlayer error:", error, errorString, "status:", status, "source:", source);
                if (photoViewerPage.closing) return;
                if (!photoViewerPage.streamLink) return;
                if (photoViewerPage.streamLink.itemId !== (photoViewerPage.currentPhoto ? photoViewerPage.currentPhoto.id : null)) return;
                if (photoViewerPage.streamLink.local) {
                    if (!photoViewerPage.videoErrorShown) {
                        photoViewerPage.videoErrorShown = true;
                        mainView.showToast(i18n.tr("Video cannot be played on this device"), true, false);
                    }
                    return;
                }
                handleStreamFailure();
            }
        }

        VideoOutput {
            id: videoOutput
            // The UT video backend stretches the frame to the item rect when
            // it does not know the surface size, so letterbox manually using
            // the video's aspect ratio to avoid distortion
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            width: photoViewerPage.videoAspect > 0
                ? ((parent.width / parent.height) > photoViewerPage.videoAspect
                    ? parent.height * photoViewerPage.videoAspect
                    : parent.width)
                : parent.width
            height: photoViewerPage.videoAspect > 0
                ? ((parent.width / parent.height) > photoViewerPage.videoAspect
                    ? parent.height
                    : parent.width / photoViewerPage.videoAspect)
                : parent.height
            source: videoPlayer
            fillMode: VideoOutput.PreserveAspectFit
            orientation: (videoPlayer.metaData && videoPlayer.metaData.orientation) ? (videoPlayer.metaData.orientation % 360) : 0
            visible: photoViewerPage.hasPlayedOnce

            function updateDynamicAspect() {
                var w = sourceRect.width;
                var h = sourceRect.height;
                if (!w || !h) {
                    if (videoPlayer.metaData && videoPlayer.metaData.resolution) {
                        w = videoPlayer.metaData.resolution.width;
                        h = videoPlayer.metaData.resolution.height;
                    }
                }
                if (w > 0 && h > 0) {
                    var asp = w / h;
                    if (orientation === 90 || orientation === 270) {
                        asp = h / w;
                    }
                    if (Math.abs(photoViewerPage.videoAspect - asp) > 0.01) {
                        photoViewerPage.videoAspect = asp;
                    }
                }
            }

            onSourceRectChanged: updateDynamicAspect()
            onOrientationChanged: updateDynamicAspect()

            MouseArea {
                anchors.fill: parent
                property real startX: 0
                property real startY: 0
                property bool isSwipe: false

                onPressed: {
                    startX = mouse.x;
                    startY = mouse.y;
                    isSwipe = false;
                }
                onPositionChanged: {
                    if (Math.abs(mouse.x - startX) > units.gu(2) || Math.abs(mouse.y - startY) > units.gu(2)) {
                        isSwipe = true;
                    }
                }
                onReleased: {
                    if (isSwipe) {
                        var deltaX = mouse.x - startX;
                        if (deltaX < -units.gu(5)) nextPhoto();
                        else if (deltaX > units.gu(5)) prevPhoto();
                    } else {
                        if (photoViewerPage.showDetails) {
                            photoViewerPage.showDetails = false;
                        } else {
                            photoViewerPage.showUi = !photoViewerPage.showUi;
                        }
                    }
                }
            }
        }

        // Black overlay at the end of playback (avoids sink artifacts)
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            visible: photoViewerPage.videoEnded
            z: 2

            Label {
                anchors.centerIn: parent
                text: i18n.tr("Replay")
                color: "#ffffff"
                font.pixelSize: units.gu(1.8)
            }
        }

        // Big Play/Pause Button
        Rectangle {
            anchors.centerIn: parent
            width: units.gu(8)
            height: units.gu(8)
            radius: units.gu(4)
            color: "#66000000"
            visible: photoViewerPage.showUi && videoPlayer.status !== MediaPlayer.Loading

            Icon {
                anchors.centerIn: parent
                name: videoPlayer.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                width: units.gu(4)
                height: units.gu(4)
                color: "#ffffff"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
                        photoViewerPage.wantPlay = false;
                        videoPlayer.pause();
                    } else {
                        photoViewerPage.videoEnded = false;
                        photoViewerPage.wantPlay = true;
                        videoPlayer.play();
                        photoViewerPage.showUi = false;
                    }
                }
            }
        }

        // Video Slider (Seek bar)
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: units.gu(8) // above the bottom action bar
            width: parent.width
            height: units.gu(6)
            color: "#66000000"
            visible: photoViewerPage.showUi && photoViewerPage.hasPlayedOnce

            Label {
                id: seekCurrent
                anchors {
                    left: parent.left
                    leftMargin: units.gu(1.5)
                    verticalCenter: parent.verticalCenter
                }
                text: SynoApi.formatDuration(videoPlayer.position)
                color: "white"
                font.pixelSize: units.gu(1.4)
            }

            Label {
                id: seekDuration
                anchors {
                    right: parent.right
                    rightMargin: units.gu(1.5)
                    verticalCenter: parent.verticalCenter
                }
                text: SynoApi.formatDuration(videoPlayer.duration)
                color: "white"
                font.pixelSize: units.gu(1.4)
            }

            // Mute toggle
            Icon {
                id: muteIcon
                anchors {
                    right: seekDuration.left
                    rightMargin: units.gu(1)
                    verticalCenter: parent.verticalCenter
                }
                name: videoPlayer.muted ? "audio-volume-muted" : "audio-volume-high"
                width: units.gu(2.5)
                height: units.gu(2.5)
                color: "white"

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onClicked: {
                        videoPlayer.muted = !videoPlayer.muted;
                    }
                }
            }

            // Custom seek bar: the stock Ubuntu Slider does not follow
            // external value updates, so draw our own track/thumb
            Item {
                id: seekArea
                anchors {
                    left: seekCurrent.right
                    right: muteIcon.left
                    leftMargin: units.gu(1)
                    rightMargin: units.gu(1)
                    verticalCenter: parent.verticalCenter
                }
                height: units.gu(2.5)

                property bool dragging: false
                property real dragFrac: 0
                property real displayFrac: {
                    if (seekArea.dragging) return seekArea.dragFrac;
                    if (videoPlayer.duration > 0 && videoPlayer.position >= 0) {
                        return Math.min(1.0, Math.max(0.0, videoPlayer.position / videoPlayer.duration));
                    }
                    return 0;
                }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "#66FFFFFF"

                    Rectangle {
                        width: parent.width * seekArea.displayFrac
                        height: parent.height
                        radius: parent.radius
                        color: Theme.primary
                    }
                }

                Rectangle {
                    x: (parent.width - width) * seekArea.displayFrac
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(1.6)
                    height: units.gu(1.6)
                    radius: width / 2
                    color: "#ffffff"
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -units.gu(1)
                    onPressed: {
                        seekArea.dragging = true;
                        seekArea.dragFrac = Math.min(1, Math.max(0, mouse.x / parent.width));
                        photoViewerPage.wantPlay = false;
                        videoPlayer.pause();
                    }
                    onPositionChanged: {
                        if (seekArea.dragging) {
                            seekArea.dragFrac = Math.min(1, Math.max(0, mouse.x / parent.width));
                        }
                    }
                    onReleased: {
                        if (videoPlayer.duration > 0) {
                            var targetPos = Math.floor(seekArea.dragFrac * videoPlayer.duration);
                            console.log("PhotoViewer: seek to targetPos:", targetPos, "ms (total duration:", videoPlayer.duration, "ms)");
                            videoPlayer.seek(targetPos);
                        }
                        seekArea.dragging = false;
                        photoViewerPage.videoEnded = false;
                        photoViewerPage.wantPlay = true;
                        videoPlayer.play();
                    }
                    onCanceled: {
                        seekArea.dragging = false;
                    }
                }
            }
        }

        ActivityIndicator {
            anchors.centerIn: parent
            running: videoPlayer.status === MediaPlayer.Buffering || videoPlayer.status === MediaPlayer.Loading
            visible: running && photoViewerPage.hasPlayedOnce
        }
    }

    // Top Navigation Overlay
    Rectangle {
        id: topNavOverlay
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: units.gu(6.5)
        color: "#99000000"
        visible: photoViewerPage.showUi
        z: 100

        Row {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: units.gu(1.5)
            }

            Rectangle {
                width: units.gu(4.5)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: backBtnMouse.pressed ? "#4D000000" : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    name: "back"
                    width: units.gu(2.8)
                    height: units.gu(2.8)
                    color: "#ffffff"
                }

                MouseArea {
                    id: backBtnMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: photoViewerPage.close()
                }
            }

            Label {
                text: currentPhoto ? (currentPhoto.filename || "") : ""
                font.pixelSize: units.gu(1.8)
                color: "#ffffff"
                elide: Text.ElideMiddle
                width: parent.width - units.gu(12)
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: units.gu(4.5)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: infoBtnMouse.pressed ? "#4D000000" : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    name: "info"
                    width: units.gu(2.6)
                    height: units.gu(2.6)
                    color: "#ffffff"
                }

                MouseArea {
                    id: infoBtnMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: photoViewerPage.showDetails = !photoViewerPage.showDetails
                }
            }
        }
    }

    // Previous / Next arrow overlays
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        width: units.gu(5)
        height: units.gu(5)
        radius: units.gu(2.5)
        color: prevMouse.pressed ? "#99000000" : "#66000000"
        visible: photoViewerPage.showUi && photoViewerPage.currentIndex > 0
        z: 50

        Icon {
            anchors.centerIn: parent
            name: "back"
            width: units.gu(2.5)
            height: units.gu(2.5)
            color: "#ffffff"
        }

        MouseArea {
            id: prevMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: prevPhoto()
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        width: units.gu(5)
        height: units.gu(5)
        radius: units.gu(2.5)
        color: nextMouse.pressed ? "#99000000" : "#66000000"
        visible: photoViewerPage.showUi && photoViewerPage.currentIndex < photoViewerPage.photoList.length - 1
        z: 50

        Icon {
            anchors.centerIn: parent
            name: "next"
            width: units.gu(2.5)
            height: units.gu(2.5)
            color: "#ffffff"
        }

        MouseArea {
            id: nextMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: nextPhoto()
        }
    }

    // Bottom date/location label (like Synology Photos original)
    Label {
        id: bottomInfoLabel
        anchors {
            left: parent.left
            right: parent.right
            bottom: bottomActionBar.top
            leftMargin: units.gu(2)
            rightMargin: units.gu(2)
            bottomMargin: units.gu(0.5)
        }
        text: {
            if (!currentPhoto) return "";
            var parts = [];
            if (currentPhoto.time) {
                var p = SynoApi.dateParts(currentPhoto);
                var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                parts.push(p.date + " " + months[p.month] + " " + p.year);
            }
            var addr = currentPhoto.additional ? currentPhoto.additional.address : null;
            if (addr) {
                var loc = [];
                if (addr.country) loc.push(addr.country);
                if (addr.state) loc.push(addr.state);
                if (addr.county) loc.push(addr.county);
                if (loc.length > 0) parts.push(loc.join(", "));
            }
            return parts.join("  ·  ");
        }
        font.pixelSize: units.gu(1.5)
        color: "#ffffff"
        elide: Text.ElideRight
        visible: photoViewerPage.showUi && text.length > 0 && !photoViewerPage.showDetails
        z: 99
    }

    // Bottom Action Bar
    Rectangle {
        id: bottomActionBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: detailsDrawer.visible ? detailsDrawer.top : parent.bottom
        }
        height: units.gu(6)
        color: "#99000000"
        visible: photoViewerPage.showUi
        z: 99

        Row {
            anchors.centerIn: parent
            spacing: units.gu(5)

            // Share / Download
            Rectangle {
                width: units.gu(4.5)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: shareMouse.pressed ? "#33ffffff" : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                visible: !photoViewerPage.isReadOnly && !photoViewerPage.isPureLocal

                Icon {
                    anchors.centerIn: parent
                    name: "share"
                    width: units.gu(2.8)
                    height: units.gu(2.8)
                    color: "#ffffff"
                }

                MouseArea {
                    id: shareMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (currentPhoto) {
                            shareDialog.openSheet([currentPhoto.id]);
                        }
                    }
                }
            }

            // Favorite (Heart)
            Rectangle {
                width: units.gu(4.5)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: favMouse.pressed ? "#33ffffff" : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                visible: !photoViewerPage.isPureLocal

                Icon {
                    anchors.centerIn: parent
                    name: photoViewerPage.isFavorite ? "like" : "unlike"
                    width: units.gu(2.8)
                    height: units.gu(2.8)
                    color: photoViewerPage.isFavorite ? "#FF3B58" : "#ffffff"
                }

                MouseArea {
                    id: favMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!currentPhoto) return;
                        var currentlyFav = photoViewerPage.isFavorite;
                        var adding = !currentlyFav;

                        // Optimistically update array
                        var ids = mainView.favoriteIds.slice();
                        if (adding) {
                            if (ids.indexOf(currentPhoto.id) === -1) ids.push(currentPhoto.id);
                        } else {
                            var idx = ids.indexOf(currentPhoto.id);
                            if (idx !== -1) ids.splice(idx, 1);
                        }
                        mainView.favoriteIds = ids;

                        SynoApi.toggleFavorite(mainView.serverUrl, mainView.sid, mainView.synotoken, currentPhoto.id, adding, function(err, data) {
                            if (err) {
                                mainView.showToast(i18n.tr("Failed to update favorite"), true, false);
                                mainView.refreshFavorites();
                            } else {
                                if (adding) {
                                    mainView.showToast(i18n.tr("Added to Favorites"), false, true);
                                } else {
                                    mainView.showToast(i18n.tr("Removed from Favorites"), false, false);
                                }
                            }
                        });
                    }
                }
            }

            // Info toggle
            Rectangle {
                width: units.gu(4.5)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: infoBottomMouse.pressed ? "#33ffffff" : "transparent"
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    name: "info"
                    width: units.gu(2.8)
                    height: units.gu(2.8)
                    color: photoViewerPage.showDetails ? "#4FC3F7" : "#ffffff"
                }

                MouseArea {
                    id: infoBottomMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        photoViewerPage.showDetails = !photoViewerPage.showDetails;
                        if (photoViewerPage.showDetails && currentPhoto) {
                            loadItemDetail(currentPhoto.id);
                        }
                    }
                }
            }

            // Delete
            Rectangle {
                width: units.gu(4.5)
                height: units.gu(4.5)
                radius: units.gu(2.25)
                color: deleteMouse.pressed ? "#33ffffff" : "transparent"
                anchors.verticalCenter: parent.verticalCenter
                visible: !photoViewerPage.isReadOnly

                Icon {
                    anchors.centerIn: parent
                    name: photoViewerPage.albumId > 0 ? "list-remove" : "delete"
                    width: units.gu(2.8)
                    height: units.gu(2.8)
                    color: "#ffffff"
                }

                MouseArea {
                    id: deleteMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!currentPhoto) return;

                        // Local-only photo (not on the server): just remove
                        // the file from this device
                        if (photoViewerPage.isPureLocal) {
                            mainView.showErrorDialog(
                                i18n.tr("Delete Photo"),
                                i18n.tr("Are you sure you want to delete this item from this device?"),
                                i18n.tr("Delete"),
                                i18n.tr("Cancel"),
                                function() { performLocalDelete(); }
                            );
                            return;
                        }

                        var isRemove = photoViewerPage.albumId > 0;

                        // Find a local copy of this asset, if any
                        var localPath = currentPhoto.localPath || "";
                        if (!localPath) {
                            localPath = Storage.getLocalPathByRemoteId(currentPhoto.id);
                        }

                        if (!isRemove && localPath.length > 0) {
                            // Ask whether to delete the local copy as well
                            mainView.showActionDialog(
                                i18n.tr("Delete Photo"),
                                i18n.tr("A local copy exists on this device. Where do you want to delete it?"),
                                i18n.tr("Delete everywhere"),
                                i18n.tr("Server only"),
                                i18n.tr("Cancel"),
                                function() {
                                    performDelete(true, localPath);
                                },
                                function() {
                                    performDelete(false, "");
                                },
                                function() {
                                    // Canceled, do nothing
                                }
                            );
                            return;
                        }

                        mainView.showErrorDialog(
                            isRemove ? i18n.tr("Remove Photo") : i18n.tr("Delete Photo"),
                            isRemove ? i18n.tr("Are you sure you want to remove this item from the album?") : i18n.tr("Are you sure you want to delete this item?"),
                            isRemove ? i18n.tr("Remove") : i18n.tr("Delete"),
                            i18n.tr("Cancel"),
                            function() {
                                if (isRemove) {
                                    performRemove();
                                } else {
                                    performDelete(false, "");
                                }
                            }
                        );
                    }
                }
            }
        }
    }

    // Bottom Information Drawer (scrollable, like Synology Photos Info panel)
    Rectangle {
        id: detailsDrawer
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: photoViewerPage.showDetails ? Math.min(detailsFlickable.contentHeight + units.gu(2), parent.height * 0.65) : 0
        visible: photoViewerPage.showDetails && currentPhoto !== null
        color: "#FAFAFA"
        z: 100
        clip: true

        Behavior on height {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        Flickable {
            id: detailsFlickable
            anchors {
                fill: parent
                margins: units.gu(2)
            }
            contentHeight: detailsCol.height
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: detailsCol
                width: parent.width
                spacing: units.gu(2)

                // --- Header: "Information" with close X ---
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
                            onClicked: photoViewerPage.showDetails = false
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

                // --- Description ---
                Label {
                    text: {
                        var src = photoViewerPage.detailSrc();
                        var desc = src && src.additional ? src.additional.description : "";
                        return desc || i18n.tr("Description");
                    }
                    font.pixelSize: units.gu(1.7)
                    color: {
                        var src = photoViewerPage.detailSrc();
                        var desc = src && src.additional ? src.additional.description : "";
                        return desc ? "#333333" : "#AAAAAA";
                    }
                    width: parent.width
                    wrapMode: Text.Wrap
                }

                // Divider
                Rectangle { width: parent.width; height: units.dp(1); color: "#E0E0E0" }

                // --- Section: Details ---
                Label {
                    text: i18n.tr("Details")
                    font.pixelSize: units.gu(1.6)
                    font.weight: Font.DemiBold
                    color: "#E57373"
                }

                // Date & Time
                Row {
                    width: parent.width
                    spacing: units.gu(1.5)

                    Icon {
                        name: "calendar"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.time) return "";
                                var p = SynoApi.dateParts(currentPhoto);
                                var months = ["January","February","March","April","May","June","July","August","September","October","November","December"];
                                return p.date + " " + months[p.month] + " " + p.year;
                            }
                            font.pixelSize: units.gu(1.7)
                            font.weight: Font.DemiBold
                            color: "#1C1C1E"
                        }

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.time) return "";
                                var p = SynoApi.dateParts(currentPhoto);
                                var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                                var hh = p.hours;
                                var mm = p.minutes;
                                return days[p.day] + ", " + (hh < 10 ? "0"+hh : hh) + ":" + (mm < 10 ? "0"+mm : mm);
                            }
                            font.pixelSize: units.gu(1.4)
                            color: "#888888"
                        }
                    }
                }

                // Filename, Resolution, Size
                Row {
                    width: parent.width
                    spacing: units.gu(1.5)

                    Icon {
                        name: photoViewerPage.isVideo ? "camcorder" : "image-x-generic-symbolic"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: {
                                var src = photoViewerPage.detailSrc();
                                return src ? (src.filename || "") : "";
                            }
                            font.pixelSize: units.gu(1.7)
                            font.weight: Font.DemiBold
                            color: "#1C1C1E"
                            elide: Text.ElideMiddle
                            width: detailsCol.width - units.gu(6)
                        }

                        Label {
                            text: {
                                var src = photoViewerPage.detailSrc();
                                if (!src) return "";
                                var parts = [];
                                var add = src.additional || {};
                                if (add.resolution) {
                                    var w = add.resolution.width;
                                    var h = add.resolution.height;
                                    var mp = ((w * h) / 1000000).toFixed(1);
                                    parts.push(mp + " MP");
                                    parts.push(w + " x " + h);
                                }
                                if (src.filesize) {
                                    var mb = (src.filesize / (1024 * 1024)).toFixed(1);
                                    parts.push(mb + " MB");
                                }
                                return parts.join("  ");
                            }
                            font.pixelSize: units.gu(1.4)
                            color: "#888888"
                        }
                    }
                }

                // Video duration (if video)
                Row {
                    width: parent.width
                    spacing: units.gu(1.5)
                    visible: photoViewerPage.isVideo

                    Icon {
                        name: "media-playback-start"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        text: {
                            var src = photoViewerPage.detailSrc();
                            if (!src || !src.additional || !src.additional.video_meta) return "";
                            var ms = src.additional.video_meta.duration || 0;
                            var sec = Math.floor(ms / 1000);
                            var m = Math.floor(sec / 60);
                            var s = Math.floor(sec % 60);
                            return i18n.tr("Duration") + ": " + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
                        }
                        font.pixelSize: units.gu(1.7)
                        color: "#1C1C1E"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // GPS / Address
                Row {
                    width: parent.width
                    spacing: units.gu(1.5)
                    visible: {
                        var add = currentPhoto ? currentPhoto.additional : null;
                        return !!(add && add.address && add.address.country);
                    }

                    Icon {
                        name: "location"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.additional || !currentPhoto.additional.address) return "";
                                var a = currentPhoto.additional.address;
                                var parts = [];
                                if (a.country) parts.push(a.country);
                                if (a.state) parts.push(a.state);
                                if (a.county) parts.push(a.county);
                                return parts.join(", ");
                            }
                            font.pixelSize: units.gu(1.7)
                            font.weight: Font.DemiBold
                            color: "#1C1C1E"
                            wrapMode: Text.Wrap
                            width: detailsCol.width - units.gu(6)
                        }

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.additional || !currentPhoto.additional.address) return "";
                                var a = currentPhoto.additional.address;
                                var parts = [];
                                if (a.city) parts.push(a.city);
                                if (a.route) parts.push(a.route);
                                return parts.join(", ");
                            }
                            font.pixelSize: units.gu(1.4)
                            color: "#888888"
                            wrapMode: Text.Wrap
                            width: detailsCol.width - units.gu(6)
                            visible: text.length > 0
                        }

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.additional || !currentPhoto.additional.gps) return "";
                                var g = currentPhoto.additional.gps;
                                if (!g.latitude && !g.longitude) return "";
                                return (g.latitude ? g.latitude.toFixed(3) : "0") + ", " + (g.longitude ? g.longitude.toFixed(3) : "0");
                            }
                            font.pixelSize: units.gu(1.3)
                            color: "#AAAAAA"
                            visible: text.length > 0
                        }
                    }
                }

                // Camera / EXIF
                Row {
                    width: parent.width
                    spacing: units.gu(1.5)
                    visible: {
                        var add = currentPhoto ? currentPhoto.additional : null;
                        return !!(add && add.exif && add.exif.camera);
                    }

                    Icon {
                        name: "camera-app-symbolic"
                        width: units.gu(3)
                        height: units.gu(3)
                        color: "#666666"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: units.dp(2)

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.additional || !currentPhoto.additional.exif) return "";
                                return currentPhoto.additional.exif.camera || "";
                            }
                            font.pixelSize: units.gu(1.7)
                            font.weight: Font.DemiBold
                            color: "#1C1C1E"
                        }

                        Label {
                            text: {
                                if (!currentPhoto || !currentPhoto.additional || !currentPhoto.additional.exif) return "";
                                var e = currentPhoto.additional.exif;
                                var parts = [];
                                if (e.aperture) parts.push(e.aperture.toLowerCase());
                                if (e.exposure_time) parts.push(e.exposure_time);
                                if (e.focal_length) parts.push(e.focal_length);
                                if (e.iso) parts.push("ISO" + e.iso);
                                return parts.join("  ");
                            }
                            font.pixelSize: units.gu(1.4)
                            color: "#888888"
                        }
                    }
                }

                // Tags section
                Label {
                    text: i18n.tr("Tags")
                    font.pixelSize: units.gu(1.6)
                    font.weight: Font.DemiBold
                    color: "#E57373"
                    visible: true
                }

                Label {
                    text: {
                        if (!currentPhoto || !currentPhoto.additional || !currentPhoto.additional.tag || currentPhoto.additional.tag.length === 0)
                            return i18n.tr("No tags");
                        var names = [];
                        for (var i = 0; i < currentPhoto.additional.tag.length; i++) {
                            names.push(currentPhoto.additional.tag[i].name || currentPhoto.additional.tag[i]);
                        }
                        return names.join(", ");
                    }
                    font.pixelSize: units.gu(1.5)
                    color: "#888888"
                    width: parent.width
                    wrapMode: Text.Wrap
                }

                // Bottom spacer
                Item { width: 1; height: units.gu(2) }
            }
        }
    }

    // Properties for favorites and detail data
    property bool isFavorite: currentPhoto ? (mainView.favoriteIds.indexOf(currentPhoto.id) !== -1) : false
    property string itemExif: ""
    property string itemDate: ""
    property string itemSize: ""
    property string itemRes: ""
    property string itemLocation: ""
    property var detailData: null

    function detailSrc() {
        if (detailData && currentPhoto && detailData.id === currentPhoto.id) return detailData;
        return currentPhoto;
    }

    function loadItemDetail(itemId) {
        if (!itemId || String(itemId).indexOf("local:") === 0) return;
        SynoApi.getItemDetail(mainView.serverUrl, mainView.sid, mainView.synotoken, itemId, function(err, data) {
            if (err) {
                if (!mainView.handleApiError(err)) {
                    console.log("Failed to load item detail: " + err.message);
                }
            } else if (data) {
                photoViewerPage.detailData = data;
            }
        });
    }

    function performRemove() {
        if (!currentPhoto) return;
        mainView.showLoading(i18n.tr("Removing..."));
        SynoApi.removeItemsFromAlbum(mainView.serverUrl, mainView.sid, mainView.synotoken, photoViewerPage.albumId, [currentPhoto.id], function(err) {
            mainView.hideLoading();
            if (err) {
                if (!mainView.handleApiError(err)) {
                    mainView.showErrorDialog(i18n.tr("Remove Failed"), err.message);
                }
            } else {
                mainView.showToast(i18n.tr("Item removed from album"), false, true);
                mainView.itemDeleted(currentPhoto.id);
                photoViewerPage.close();
            }
        });
    }

    // Deletes a local-only photo (never uploaded): remove the file and the
    // sync record via the central itemDeleted handler, then close the viewer
    function performLocalDelete() {
        if (!currentPhoto) return;
        var itemId = currentPhoto.id;
        mainView.showLoading(i18n.tr("Deleting..."));
        mainView.itemDeleted(itemId, true);
        mainView.hideLoading();
        mainView.showToast(i18n.tr("Deleted from device"), false, true);
        photoViewerPage.close();
    }

    function performDelete(alsoLocal, localPath) {
        if (!currentPhoto) return;
        var itemId = currentPhoto.id;
        mainView.showLoading(i18n.tr("Deleting..."));
        SynoApi.deleteItems(mainView.serverUrl, mainView.sid, mainView.synotoken, [itemId], function(err, data) {
            mainView.hideLoading();
            if (err) {
                if (!mainView.handleApiError(err)) {
                    mainView.showErrorDialog(i18n.tr("Delete Failed"), err.message);
                }
                return;
            }
            mainView.showToast(alsoLocal ? i18n.tr("Item deleted from server and device") : i18n.tr("Item deleted"), false, true);
            mainView.itemDeleted(itemId, alsoLocal);
            photoViewerPage.close();
        });
    }

    function prevPhoto() {
        if (mainView.viewerCurrentIndex > 0) {
            photoViewerPage.itemDate = "";
            photoViewerPage.itemSize = "";
            photoViewerPage.itemRes = "";
            photoViewerPage.itemLocation = "";
            mainView.viewerCurrentIndex--;
            photoViewerPage.detailData = null;
            resetZoom();
        }
    }

    function nextPhoto() {
        if (mainView.viewerCurrentIndex < photoViewerPage.photoList.length - 1) {
            mainView.viewerCurrentIndex++;
            photoViewerPage.detailData = null;
            resetZoom();
        }
    }

    function resetZoom() {
        pinchArea.scale = 1.0;
        photoViewerPage.panX = 0;
        photoViewerPage.panY = 0;
    }

    ShareDialog {
        id: shareDialog
    }
}
