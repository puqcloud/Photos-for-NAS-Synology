import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/SynologyApi.js" as Api
import "../js/Storage.js" as Storage

Item {
    id: root

    property bool enabled: Storage.isBackupEnabled()

    onEnabledChanged: {
        if (Storage.isBackupEnabled() !== enabled) {
            Storage.setBackupEnabled(enabled);
        }
        statusChanged();
    }
    property string phase: "idle" // idle | scanning | uploading | done
    property bool running: phase === "scanning" || phase === "uploading"

    property int totalFiles: 0          // candidates for upload in current run
    property int uploadedCount: 0       // uploaded in current run
    property int duplicateCount: 0      // already on server (skipped)
    property int failedCount: 0         // failed in current run
    property int remainingCount: _queue.length
    property string currentFile: ""
    property real currentPercent: 0
    property real overallPercent: 0
    property string speedText: "--"
    property string etaText: "--:--"

    property var folderGroups: []
    property var localFiles: []
    property int selTotal: 0
    property int selBackedUp: 0
    property int selRemaining: 0
    property var uploadItems: []
    property var queueMap: ({})
    property bool reverifying: false
    property int reverifyTotal: 0
    property int reverifyDone: 0
    property int clearableCount: 0
    property real clearableBytes: 0
    property string clearableSizeText: formatBytes(clearableBytes)

    function updateQueueMap() {
        var map = {};
        for (var i = 0; i < uploadItems.length; i++) {
            map[uploadItems[i].path] = uploadItems[i].status;
        }
        queueMap = map;
    }

    signal backupStarted()
    signal backupFinished(bool success)
    signal localListRefreshed()
    signal statusChanged()

    property var _candidates: []
    property var _queue: []
    property var _metaByPath: ({})
    property var _speedSamples: []
    property real _lastSampleTime: 0
    property real _lastSampleBytes: 0
    property real _completedBytes: 0
    property real _totalBytesAll: 0
    property bool _stopped: false
    property bool _scanPending: false
    property real _lastFinishedAt: 0
    property real _lastReverifyAt: 0
    property string _uploadingPath: ""

    Component.onCompleted: {
        uploadItems = Storage.getUploadQueue();
        for (var i = 0; i < uploadItems.length; i++) {
            if (uploadItems[i].status === "uploading") uploadItems[i].status = "queued";
        }
        updateQueueMap();
    }

    function saveQueue() {
        var list = uploadItems;
        if (list.length > 300) {
            // Auto-clean: keep active items + the most recent 100 finished
            var kept = [];
            var recentDone = 0;
            for (var i = 0; i < list.length; i++) {
                var s = list[i].status;
                if (s === "failed" || s === "queued" || s === "uploading") kept.push(list[i]);
            }
            for (var j = 0; j < list.length && recentDone < 100; j++) {
                var st = list[j].status;
                if (st === "done" || st === "duplicate") {
                    kept.push(list[j]);
                    recentDone++;
                }
            }
            list = kept;
        }
        Storage.saveUploadQueue(list);
    }

    // Remove finished (done/duplicate) entries from the upload list
    function clearFinishedUploads() {
        var kept = [];
        for (var i = 0; i < uploadItems.length; i++) {
            var s = uploadItems[i].status;
            if (s === "failed" || s === "queued" || s === "uploading") kept.push(uploadItems[i]);
        }
        uploadItems = kept;
        updateQueueMap();
        saveQueue();
    }

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 MB";
        if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
        if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        if (bytes >= 1024) return Math.round(bytes / 1024) + " kB";
        return bytes + " B";
    }

    // Delete local copies of files that are already on the server
    function freeUpSpace() {
        if (running || reverifying) {
            mainView.showToast(i18n.tr("Busy, try again later"), true, false);
            return;
        }
        var paths = [];
        for (var i = 0; i < localFiles.length; i++) {
            if (localFiles[i].isBackedUp && localFiles[i].localPath) {
                paths.push(localFiles[i].localPath);
            }
        }
        if (paths.length === 0) {
            mainView.showToast(i18n.tr("Nothing to clear"), false, true);
            return;
        }
        var deleted = backupEngine.deleteLocalFiles(paths);
        for (var j = 0; j < deleted.length; j++) {
            Storage.removeSyncedRecord(deleted[j]);
        }
        mainView.showToast(i18n.tr("Deleted %1 local files").arg(deleted.length), false, true);
        refreshLocalFiles();
    }

    function isVideoName(name) {
        var ext = String(name).split(".").pop().toLowerCase();
        return ["mp4","mov","m4v","mkv","webm","avi","3gp","mpeg","mpg"].indexOf(ext) !== -1;
    }

    function refreshLocalFiles() {
        if (typeof backupEngine === "undefined") return;
        _scanPending = false;
        backupEngine.scanMedia();
        maybeAutoReverify();
    }

    function maybeAutoReverify() {
        if (reverifying || running) return;
        if (!Storage.isBackupEnabled()) return;
        if (!mainView.sid || !mainView.isLoggedIn) return;
        var now = Date.now();
        if (now - _lastReverifyAt < 10 * 60 * 1000) return; // throttle: 10 min
        reverifyBackup();
    }

    // Re-check with the server which backed-up files still exist there
    function reverifyBackup() {
        if (reverifying || running) {
            mainView.showToast(i18n.tr("Busy, try again later"), true, false);
            return;
        }
        if (!mainView.sid || !mainView.isLoggedIn) {
            mainView.showToast(i18n.tr("Please log in first"), true, false);
            return;
        }
        var syncedList = Storage.getSyncedFilesList();
        var ids = [];
        var pathById = {};
        for (var i = 0; i < syncedList.length; i++) {
            var row = syncedList[i];
            var rid = String(row.remote_id || "");
            if (!rid || rid === "0") continue;
            ids.push(rid);
            if (!pathById[rid]) pathById[rid] = row.local_path;
        }
        if (ids.length === 0) {
            mainView.showToast(i18n.tr("Nothing to verify yet"), false, true);
            return;
        }
        if (ids.length > 500) ids = ids.slice(0, 500); // newest uploads first

        _lastReverifyAt = Date.now();
        reverifying = true;
        reverifyTotal = ids.length;
        reverifyDone = 0;
        statusChanged();

        Api.checkItemsExist(mainView.serverUrl, mainView.sid, mainView.synotoken, ids, function(err, result) {
            reverifying = false;
            if (err) {
                mainView.handleApiError(err);
                statusChanged();
                return;
            }
            var missing = result.missing;
            var removed = 0;
            for (var id in missing) {
                if (!missing.hasOwnProperty(id)) continue;
                var p = pathById[id];
                if (p) {
                    Storage.removeSyncedRecord(p);
                    removed++;
                }
            }
            reverifyDone = reverifyTotal;
            statusChanged();
            mainView.showToast(
                removed > 0
                    ? i18n.tr("Verification: %1 files missing on server").arg(removed)
                    : i18n.tr("Verification: everything is on the server"),
                removed > 0, removed === 0);
            refreshLocalFiles();
        }, function(doneCount, totalCount) {
            reverifyDone = doneCount;
            statusChanged();
        });
    }

    function startBackup() {
        if (running) return;
        if (reverifying) {
            mainView.showToast(i18n.tr("Verification in progress, please wait"), true, false);
            return;
        }
        if (!Storage.isBackupEnabled()) {
            mainView.showToast(i18n.tr("Backup is disabled. Enable it in Settings."), true, false);
            return;
        }
        if (!mainView.sid || !mainView.isLoggedIn) {
            mainView.showToast(i18n.tr("Please log in first"), true, false);
            return;
        }
        var folders = Storage.getBackupFolders();
        if (folders.length === 0) {
            mainView.showToast(i18n.tr("No backup folders selected"), true, false);
            return;
        }

        _stopped = false;
        _queue = [];
        _candidates = [];
        _metaByPath = {};
        _speedSamples = [];
        _lastSampleTime = 0;
        _lastSampleBytes = 0;
        _completedBytes = 0;
        _totalBytesAll = 0;
        _uploadingPath = "";
        uploadItems = [];
        saveQueue();
        updateQueueMap();
        totalFiles = 0;
        uploadedCount = 0;
        duplicateCount = 0;
        failedCount = 0;
        currentFile = "";
        currentPercent = 0;
        overallPercent = 0;
        speedText = "--";
        etaText = "--:--";

        phase = "scanning";
        backupStarted();
        refreshLocalFiles();
    }

    function stopBackup() {
        _stopped = true;
        if (_uploadingPath !== "") {
            for (var i = 0; i < uploadItems.length; i++) {
                if (uploadItems[i].path === _uploadingPath) {
                    uploadItems[i].status = "queued";
                    uploadItems[i].error = "";
                    uploadItems[i].percent = 0;
                    break;
                }
            }
        }
        _queue = [];
        if (typeof backupEngine !== "undefined") backupEngine.cancelUpload();
        uploadItemsChanged();
        saveQueue();
        updateQueueMap();
        _lastFinishedAt = Date.now(); // prevent the in-flight scan from auto-restarting
        if (running) {
            phase = "idle";
            backupFinished(false);
        }
    }

    // Retry all failed/queued items
    function retryFailed() {
        if (running) return;
        if (!mainView.sid || !mainView.isLoggedIn) {
            mainView.showToast(i18n.tr("Please log in first"), true, false);
            return;
        }
        if (localFiles.length === 0) {
            refreshLocalFiles();
            mainView.showToast(i18n.tr("Scanning device, retry in a moment"), false, true);
            return;
        }
        var retryPaths = [];
        for (var i = 0; i < uploadItems.length; i++) {
            var it = uploadItems[i];
            if (it.status === "failed" || it.status === "queued") {
                it.status = "queued";
                it.percent = 0;
                it.error = "";

                var meta = _metaByPath[it.path];
                if (meta) {
                    retryPaths.push(meta);
                } else {
                    var mtime = 0;
                    var size = 0;
                    for (var k = 0; k < localFiles.length; k++) {
                        if (localFiles[k].localPath === it.path) {
                            mtime = localFiles[k].time;
                            size = localFiles[k].filesize;
                            break;
                        }
                    }
                    retryPaths.push({ name: it.name, path: it.path, mtime: mtime, size: size });
                }
            }
        }
        if (retryPaths.length === 0) {
            mainView.showToast(i18n.tr("Nothing to retry"), false, true);
            return;
        }
        uploadItemsChanged();
        saveQueue();
        updateQueueMap();
        _queue = retryPaths;
        _stopped = false;
        totalFiles = retryPaths.length;
        uploadedCount = 0;
        duplicateCount = 0;
        failedCount = 0;
        currentFile = "";
        currentPercent = 0;
        overallPercent = 0;
        _uploadingPath = "";
        _speedSamples = [];
        _lastSampleTime = 0;
        _lastSampleBytes = 0;
        _completedBytes = 0;
        _totalBytesAll = 0;
        for (var j = 0; j < _queue.length; j++) {
            var qmeta = _queue[j];
            _totalBytesAll += qmeta ? (qmeta.size || 0) : 0;
        }
        phase = "uploading";
        backupStarted();
        uploadNext();
    }

    // Retry a single file
    function retryOne(path) {
        var it = null;
        for (var i = 0; i < uploadItems.length; i++) {
            if (uploadItems[i].path === path) { it = uploadItems[i]; break; }
        }
        if (!it) return;
        if (it.status === "uploading") return;
        it.status = "queued";
        it.percent = 0;
        it.error = "";
        uploadItemsChanged();

        var meta = _metaByPath[path];
        if (!meta) {
            var mtime = 0;
            var size = 0;
            for (var k = 0; k < localFiles.length; k++) {
                if (localFiles[k].localPath === path) {
                    mtime = localFiles[k].time;
                    size = localFiles[k].filesize;
                    break;
                }
            }
            if (!mtime) {
                refreshLocalFiles();
                mainView.showToast(i18n.tr("Scanning device, retry in a moment"), false, true);
                return;
            }
            meta = { name: it.name, path: path, mtime: mtime, size: size };
        }
        _queue.unshift(meta);

        _stopped = false;
        saveQueue();
        updateQueueMap();
        if (!running) {
            phase = "uploading";
            backupStarted();
        }
        if (_uploadingPath === "") uploadNext();
    }

    function onScanFinished(folders) {
        folderGroups = folders;
        var syncedMap = Storage.getSyncedPathMap();

        // Build local file list for display (selected folders only)
        var local = [];
        for (var i = 0; i < folders.length; i++) {
            var folder = folders[i];
            if (!Storage.isFolderSelected(folder.name)) continue;
            var files = folder.files || [];
            for (var j = 0; j < files.length; j++) {
                var f = files[j];
                local.push({
                    id: "local:" + f.path,
                    localPath: f.path,
                    filename: f.name,
                    time: f.mtime,
                    type: isVideoName(f.name) ? "video" : "photo",
                    filesize: f.size,
                    isLocal: true,
                    isBackedUp: !!(syncedMap[f.path]),
                    additional: null
                });
            }
        }
        localFiles = local;
        selTotal = local.length;
        selBackedUp = 0;
        clearableCount = 0;
        clearableBytes = 0;
        for (var k = 0; k < local.length; k++) {
            if (local[k].isBackedUp) {
                selBackedUp++;
                clearableCount++;
                clearableBytes += local[k].filesize || 0;
            }
        }
        selRemaining = selTotal - selBackedUp;
        localListRefreshed();
        statusChanged();

        if (phase === "scanning") {
            processCandidates(folders, syncedMap);
            return;
        }

        // Auto-backup: enabled + pending files + not mid-run + not just finished
        if (phase !== "uploading"
            && Storage.isBackupEnabled()
            && (Date.now() - _lastFinishedAt) > 5000) {
            var pending = 0;
            for (var p = 0; p < folders.length; p++) {
                var folder2 = folders[p];
                if (!Storage.isFolderSelected(folder2.name)) continue;
                var files2 = folder2.files || [];
                for (var q2 = 0; q2 < files2.length; q2++) {
                    if (!syncedMap[files2[q2].path]) pending++;
                }
            }
            if (pending > 0) {
                phase = "idle";
                startBackup();
            }
        }
    }

    function processCandidates(folders, syncedMap) {
        _candidates = [];
        _metaByPath = {};
        for (var i = 0; i < folders.length; i++) {
            var folder = folders[i];
            if (!Storage.isFolderSelected(folder.name)) continue;
            var files = folder.files || [];
            for (var j = 0; j < files.length; j++) {
                var f = files[j];
                if (syncedMap[f.path]) continue; // already backed up
                _candidates.push(f);
                _metaByPath[f.path] = f;
            }
        }

        totalFiles = _candidates.length;
        console.log("BackupManager: scan found", totalFiles, "files to back up (selected folders)");

        if (_stopped) {
            phase = "idle";
            backupFinished(false);
            return;
        }

        if (_candidates.length === 0) {
            phase = "done";
            mainView.showToast(i18n.tr("Backup is up to date"), false, true);
            backupFinished(true);
            return;
        }

        // The server handles duplicates itself (duplicate=ignore), so the
        // candidates go straight into the upload queue
        _queue = _candidates.slice();
        _completedBytes = 0;
        _totalBytesAll = 0;
        for (var q = 0; q < _queue.length; q++) _totalBytesAll += _queue[q].size || 0;
        console.log("BackupManager:", _queue.length, "files to upload");

        var items = [];
        for (var q2 = 0; q2 < _queue.length && q2 < 2000; q2++) {
            items.push({ name: _queue[q2].name, path: _queue[q2].path, status: "queued", percent: 0, error: "" });
        }
        uploadItems = items;

        phase = "uploading";
        uploadNext();
    }

    function uploadNext() {
        if (_stopped) {
            phase = "idle";
            backupFinished(false);
            return;
        }
        if (_queue.length === 0) {
            finishBackup();
            return;
        }
        var f = _queue.shift();
        remainingCount = _queue.length;
        currentFile = f ? (f.name || "") : "";
        currentPercent = 0;
        overallPercent = totalFiles > 0 ? ((uploadedCount + duplicateCount + failedCount) * 100 / totalFiles) : 0;
        _uploadingPath = f ? (f.path || "") : "";

        if (!_uploadingPath) {
             Qt.callLater(uploadNext);
             return;
        }

        for (var i = 0; i < uploadItems.length; i++) {
            if (uploadItems[i].path === _uploadingPath) {
                uploadItems[i].status = "uploading";
                uploadItems[i].percent = 0;
                break;
            }
        }
        uploadItemsChanged();
        saveQueue();
        updateQueueMap();

        console.log("BackupManager: uploading", _uploadingPath);
        var targetFolder = Storage.getSetting("backup_target_folder", "MobileBackup");
        backupEngine.uploadAsset(mainView.serverUrl, mainView.sid, mainView.synotoken,
                                 targetFolder, _uploadingPath);
    }

    function onUploadProgress(filePath, sentBytes, totalBytes) {
        if (filePath !== _uploadingPath) return;
        if (totalBytes > 0) currentPercent = sentBytes * 100 / totalBytes;
        for (var i = 0; i < uploadItems.length; i++) {
            if (uploadItems[i].path === filePath) {
                uploadItems[i].percent = totalBytes > 0 ? Math.round(sentBytes * 100 / totalBytes) : 0;
                break;
            }
        }
        updateSpeed(_completedBytes + sentBytes);
    }

    function onUploadFinished(filePath, success, httpStatus, status, assetId, errorMessage) {
        console.log("BackupManager: upload result", filePath, "success:", success, "http:", httpStatus, "status:", status, "error:", errorMessage);

        for (var i = 0; i < uploadItems.length; i++) {
            if (uploadItems[i].path === filePath) {
                if (success && status === "duplicate") {
                    uploadItems[i].status = "duplicate";
                } else if (success) {
                    uploadItems[i].status = "done";
                } else {
                    if (_stopped) {
                        uploadItems[i].status = "queued";
                        uploadItems[i].error = "";
                        uploadItems[i].percent = 0;
                    } else {
                        uploadItems[i].status = "failed";
                        uploadItems[i].error = errorMessage || "";
                    }
                }
                if (success) uploadItems[i].percent = 100;
                break;
            }
        }
        uploadItemsChanged();

        if (httpStatus === 401) {
            _stopped = true;
            _queue = [];
            phase = "idle";
            mainView.handleApiError({ code: 401, message: i18n.tr("Session expired. Please log in again.") });
            return;
        }
        var meta = _metaByPath[filePath] || {};
        if (success) {
            if (status === "duplicate") duplicateCount++;
            else uploadedCount++;
            Storage.markFileAsSynced(filePath, meta.name || "", meta.size || 0, assetId || "");
            _completedBytes += meta.size || 0;
            // Update the badge in the photo grid right away
            for (var li = 0; li < localFiles.length; li++) {
                if (localFiles[li].localPath === filePath) {
                    localFiles[li].isBackedUp = true;
                    break;
                }
            }
            localListRefreshed();
        } else {
            if (!_stopped) {
                failedCount++;
                mainView.showToast(i18n.tr("Upload failed: %1").arg(meta.name || filePath), true, false);
            }
        }
        overallPercent = totalFiles > 0 ? ((uploadedCount + duplicateCount + failedCount) * 100 / totalFiles) : 0;
        _uploadingPath = "";
        saveQueue();
        updateQueueMap();
        if (_stopped) return;
        Qt.callLater(uploadNext);
    }

    function updateSpeed(bytesDone) {
        var now = Date.now();
        if (_lastSampleTime === 0) {
            _lastSampleTime = now;
            _lastSampleBytes = bytesDone;
            return;
        }
        var dt = (now - _lastSampleTime) / 1000.0;
        if (dt < 0.1) return;
        var db = bytesDone - _lastSampleBytes;
        var mbps = (db / dt) / (1024 * 1024);
        _lastSampleTime = now;
        _lastSampleBytes = bytesDone;
        if (isNaN(mbps) || !isFinite(mbps) || mbps < 0) return;
        _speedSamples.push(mbps);
        while (_speedSamples.length > 5) _speedSamples.shift();
        var sum = 0;
        for (var i = 0; i < _speedSamples.length; i++) sum += _speedSamples[i];
        var avg = sum / _speedSamples.length;
        if (avg >= 1) speedText = avg.toFixed(1) + " MB/s";
        else if (avg > 0.001) speedText = Math.max(1, Math.round(avg * 1000)) + " kB/s";
        else speedText = "--";

        var remaining = _totalBytesAll - bytesDone;
        if (avg > 0 && remaining > 0) {
            etaText = formatEta(Math.round(remaining / (avg * 1024 * 1024)));
        } else {
            etaText = "--:--";
        }
    }

    function formatEta(totalSec) {
        if (totalSec < 0 || !isFinite(totalSec)) return "--:--";
        var h = Math.floor(totalSec / 3600);
        var m = Math.floor((totalSec % 3600) / 60);
        var s = totalSec % 60;
        var mm = m < 10 ? "0" + m : m;
        var ss = s < 10 ? "0" + s : s;
        return h > 0 ? (h + ":" + mm + ":" + ss) : (mm + ":" + ss);
    }

    function finishBackup() {
        _lastFinishedAt = Date.now();
        phase = "done";
        var success = failedCount === 0;
        mainView.showToast(
            success
                ? i18n.tr("Backup complete: %1 uploaded, %2 duplicates").arg(uploadedCount).arg(duplicateCount)
                : i18n.tr("Backup finished with %1 errors").arg(failedCount),
            !success, success);
        backupFinished(success);
        refreshLocalFiles();
    }

    Connections {
        target: typeof backupEngine !== "undefined" ? backupEngine : null
        onMediaScanFinished: root.onScanFinished(folders)
        onUploadProgress: {
            root._uploadingPath = filePath;
            root.onUploadProgress(filePath, sentBytes, totalBytes);
        }
        onUploadFinished: root.onUploadFinished(filePath, success, httpStatus, status, assetId, errorMessage)
    }
}
