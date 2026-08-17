import QtQuick 2.9
import Ubuntu.Components 1.3
import "components"
import "js/Storage.js" as Storage
import "js/SynologyApi.js" as SynoApi
import "js/Theme.js" as Theme

MainView {
    id: mainView
    objectName: "mainView"
    applicationName: "photos-for-nas-synology.puqsoftware"
    width: units.gu(45)
    height: units.gu(80)
    backgroundColor: isLoggedIn ? Theme.background : Theme.primary
    headerColor: isLoggedIn ? Theme.background : Theme.primary
    anchorToKeyboard: true

    // Session State
    property string serverUrl: ""
    property string sid: ""
    property string synotoken: ""
    property string username: ""
    property bool isLoggedIn: false
    property bool loading: false
    property string appVersion: "1.0.0"

    // Viewer Global Properties (ensures 0ms instant transition without array marshaling)
    property var viewerPhotoList: []
    property int viewerCurrentIndex: 0
    signal itemDeleted(var itemId, var alsoLocal)
    signal albumDeleted(int albumId)
    signal albumUpdated(int albumId)
    signal memoryCacheCleared()

    property bool _itemDeleteRefreshPending: false

    onItemDeleted: {
        var localPath = "";
        if (String(itemId).indexOf("local:") === 0) {
            localPath = String(itemId).substring(6);
            alsoLocal = true; // Local-only items are always deleted locally when removed
        } else {
            localPath = Storage.getLocalPathByRemoteId(itemId);
        }

        if (localPath) {
            Storage.removeSyncedRecord(localPath);
            if (alsoLocal && typeof backupEngine !== "undefined") {
                backupEngine.deleteLocalFiles([localPath]);
            }
            if (typeof backupManager !== "undefined") {
                if (alsoLocal) {
                    backupManager.localFiles = backupManager.localFiles.filter(function(f) { return f.localPath !== localPath; });
                }
                // Mass deletes emit many itemDeleted signals: rescan once
                if (!mainView._itemDeleteRefreshPending) {
                    mainView._itemDeleteRefreshPending = true;
                    Qt.callLater(function() {
                        mainView._itemDeleteRefreshPending = false;
                        backupManager.refreshLocalFiles();
                    });
                }
            }
        }
    }
    
    // Favorites Tracking
    property var favoriteIds: []
    function refreshFavorites() {
        if (!sid) return;
        SynoApi.getFavorites(serverUrl, sid, synotoken, 0, 10000, function(err, data) {
            if (!err && data && data.list) {
                var ids = [];
                for (var i = 0; i < data.list.length; i++) {
                    ids.push(data.list[i].id);
                }
                mainView.favoriteIds = ids;
            }
        });
    }

    function openViewer(list, index, isReadOnly, passphrase, albumId) {
        viewerPhotoList = list;
        viewerCurrentIndex = index;
        if (photoViewerOverlay) {
            photoViewerOverlay.isReadOnly = !!isReadOnly;
            photoViewerOverlay.passphrase = passphrase || "";
            photoViewerOverlay.albumId = albumId || -1;
        }
        photoViewerOverlay.open();
    }

    PageStack {
        id: pageStack
        anchors.fill: parent
    }

    // Pre-instantiated instant Photo Viewer Overlay
    Loader {
        id: photoViewerLoader
        anchors.fill: parent
        source: "pages/PhotoViewerPage.qml"
        asynchronous: false // load immediately on startup
        z: 1000
    }
    
    property var photoViewerOverlay: photoViewerLoader.item

    // Backup manager (device -> server photo backup)
    BackupManager {
        id: backupManager
    }

    onIsLoggedInChanged: {
        if (isLoggedIn) {
            backupManager.refreshLocalFiles();
        } else {
            backupManager.localFiles = [];
        }
    }

    // Global Synology Loading Modal Popup
    LoadingOverlay {
        id: loadingOverlay
    }

    // Global Alert / Error Dialog
    SynoDialog {
        id: synoDialog
    }

    // Global Notification Toast
    NotificationBanner {
        id: notificationBanner
    }

    Component.onCompleted: {
        loadVersion();
        Storage.initDb();
        checkSession();
    }

    function loadVersion() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../manifest.json"));
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var manifest = JSON.parse(xhr.responseText);
                    if (manifest && manifest.version) {
                        mainView.appVersion = manifest.version;
                    }
                } catch (e) {
                    console.warn("Failed to parse manifest.json: " + e);
                }
            }
        }
        xhr.send();
    }

    function checkSession() {
        var savedUrl = Storage.getSetting("serverUrl", "");
        var savedSid = Storage.getSetting("sid", "");
        var savedToken = Storage.getSetting("synotoken", "");
        var savedUser = Storage.getSetting("username", "");

        if (savedUrl && savedSid) {
            mainView.serverUrl = savedUrl;
            mainView.sid = savedSid;
            mainView.synotoken = savedToken;
            mainView.username = savedUser;
            mainView.isLoggedIn = true;
            mainView.refreshFavorites();
            pageStack.push(Qt.resolvedUrl("pages/MainTabsPage.qml"));
        } else {
            pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"));
        }
    }

    function showLoading(msg) {
        mainView.loading = true;
        loadingOverlay.show(msg);
    }

    function hideLoading() {
        mainView.loading = false;
        loadingOverlay.hide();
    }

    function handleApiError(err) {
        if (!err) return false;
        // Check for Auth errors (119 = Session timeout, 105/106/107, etc)
        var codes = [105, 106, 107, 119, 400, 401, 402, 403, 404, 405, 406, 407, 408];
        if (codes.indexOf(err.code) !== -1) {
            mainView.isLoggedIn = false;
            mainView.sid = "";
            mainView.synotoken = "";
            Storage.setSetting("sid", "");
            Storage.setSetting("synotoken", "");
            if (typeof synoImageCache !== "undefined") synoImageCache.clearCache();
            pageStack.clear();
            pageStack.push(Qt.resolvedUrl("pages/LoginPage.qml"));
            mainView.showToast(err.message || i18n.tr("Session expired. Please log in again."), true, false);
            return true; // handled
        }
        mainView.showToast(err.message || i18n.tr("Network error"), true, false);
        return false;
    }

    function showErrorDialog(title, message, btnText, cancelText, onOk, onCancel) {
        synoDialog.show(title, message, btnText, cancelText, onOk, onCancel);
    }

    function showActionDialog(title, message, primaryBtnText, secondaryBtnText, cancelBtnText, onPrimary, onSecondary, onCancel) {
        synoDialog.showWithExtra(title, message, primaryBtnText, secondaryBtnText, cancelBtnText, onPrimary, onSecondary, onCancel);
    }

    function showToast(msg, isError, isSuccess) {
        notificationBanner.show(msg, isError, isSuccess);
    }
    
    function showInputDialog(title, placeholder, okText, cancelText, onOk) {
        synoInputDialog.show(title, placeholder, okText, cancelText, onOk);
    }
    
    SynoInputDialog {
        id: synoInputDialog
    }
}
