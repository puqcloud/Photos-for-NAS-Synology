.pragma library
.import QtQuick.LocalStorage 2.0 as Sql

var db = null;

function initDb() {
    return getDatabase();
}

function getDatabase() {
    if (db) return db;
    try {
        db = Sql.LocalStorage.openDatabaseSync("PhotosSynologyDB", "", "Storage for Photos for NAS Synology", 200000);
        db.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS settings (key TEXT UNIQUE, value TEXT)');
            tx.executeSql('CREATE TABLE IF NOT EXISTS synced_files (local_path TEXT PRIMARY KEY, file_name TEXT, file_size INTEGER, file_mtime TEXT, remote_id INTEGER, synced_at TEXT)');
            tx.executeSql('CREATE TABLE IF NOT EXISTS media_cache (cache_key TEXT PRIMARY KEY, url TEXT, size_bytes INTEGER, cached_at TEXT)');
        });
    } catch(e) {
        console.error("Failed to initialize database:", e);
    }
    return db;
}

// --- SETTINGS HELPERS ---

function setSetting(key, value) {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            var valStr = typeof value === 'object' ? JSON.stringify(value) : String(value);
            tx.executeSql('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, valStr]);
        });
        return true;
    } catch(e) {
        console.error("Error writing setting " + key + ":", e);
        return false;
    }
}

function getSetting(key, defaultValue) {
    var database = getDatabase();
    if (!database) return defaultValue;
    var result = defaultValue;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT value FROM settings WHERE key = ?', [key]);
            if (res.rows.length > 0) {
                var raw = res.rows.item(0).value;
                result = raw;
            }
        });
    } catch(e) {
        console.error("Error reading setting " + key + ":", e);
    }
    return result;
}

function removeSetting(key) {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            tx.executeSql('DELETE FROM settings WHERE key = ?', [key]);
        });
        return true;
    } catch(e) {
        console.error("Error deleting setting " + key + ":", e);
        return false;
    }
}

function clearAllCredentials() {
    removeSetting("sid");
    removeSetting("synotoken");
    removeSetting("autoLogin");
}

// Wipes ALL application data: settings, credentials, sync records
// and cache records. Leaves the DB schema intact.
function fullReset() {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            tx.executeSql('DELETE FROM settings');
            tx.executeSql('DELETE FROM synced_files');
            tx.executeSql('DELETE FROM media_cache');
        });
        return true;
    } catch(e) {
        console.error("Error resetting storage:", e);
        return false;
    }
}

// --- BACKUP SETTINGS HELPERS ---

function isBackupEnabled() {
    return getSetting("backup_enabled", "false") === "true";
}

function setBackupEnabled(enabled) {
    setSetting("backup_enabled", enabled ? "true" : "false");
}

// Returns array of selected folder names, or ["*"] for all folders
function getBackupFolders() {
    var raw = getSetting("backup_folders", "");
    if (!raw) return [];
    try {
        var parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) return parsed;
    } catch(e) {
        // fall through
    }
    if (raw === "*") return ["*"];
    return [];
}

function setBackupFolders(folders) {
    setSetting("backup_folders", JSON.stringify(folders || []));
}

function isFolderSelected(folderName) {
    var folders = getBackupFolders();
    if (folders.length === 0) return false;
    if (folders.indexOf("*") !== -1) return true;
    return folders.indexOf(folderName) !== -1;
}

// --- UPLOAD QUEUE PERSISTENCE ---

function saveUploadQueue(items) {
    try {
        var list = items || [];
        if (list.length > 500) list = list.slice(0, 500);
        setSetting("upload_queue", JSON.stringify(list));
    } catch(e) {
        console.error("Error saving upload queue:", e);
    }
}

function getUploadQueue() {
    var raw = getSetting("upload_queue", "");
    if (!raw) return [];
    try {
        var parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) return parsed;
    } catch(e) {
        // fall through
    }
    return [];
}

// --- SYNCED FILES TRACKING ---

function isFileSynced(localPath, fileName, fileSize) {
    var database = getDatabase();
    if (!database) return false;
    var found = false;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT local_path FROM synced_files WHERE local_path = ? OR (file_name = ? AND file_size = ?)', [localPath, fileName, fileSize]);
            if (res.rows.length > 0) {
                found = true;
            }
        });
    } catch(e) {
        console.error("Error checking sync status:", e);
    }
    return found;
}

function markFileAsSynced(localPath, fileName, fileSize, remoteId) {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            var now = new Date().toISOString();
            tx.executeSql('INSERT OR REPLACE INTO synced_files (local_path, file_name, file_size, remote_id, synced_at) VALUES (?, ?, ?, ?, ?)',
                [localPath, fileName, fileSize || 0, remoteId || 0, now]);
        });
        return true;
    } catch(e) {
        console.error("Error marking file synced:", e);
        return false;
    }
}

function getSyncedFilesList() {
    var database = getDatabase();
    var list = [];
    if (!database) return list;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT * FROM synced_files ORDER BY synced_at DESC');
            for (var i = 0; i < res.rows.length; i++) {
                list.push(res.rows.item(i));
            }
        });
    } catch(e) {
        console.error("Error fetching synced files list:", e);
    }
    return list;
}

// Returns map { local_path: remote_id } for quick lookups
function getSyncedPathMap() {
    var database = getDatabase();
    var map = {};
    if (!database) return map;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT local_path, remote_id FROM synced_files');
            for (var i = 0; i < res.rows.length; i++) {
                var row = res.rows.item(i);
                map[row.local_path] = row.remote_id;
            }
        });
    } catch(e) {
        console.error("Error fetching synced path map:", e);
    }
    return map;
}

function isPathSynced(localPath) {
    var database = getDatabase();
    if (!database) return false;
    var found = false;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT local_path FROM synced_files WHERE local_path = ?', [localPath]);
            if (res.rows.length > 0) found = true;
        });
    } catch(e) {
        console.error("Error checking sync status:", e);
    }
    return found;
}

// Returns the local path recorded for a remote asset id (or "")
function getLocalPathByRemoteId(remoteId) {
    var database = getDatabase();
    var result = "";
    if (!database || !remoteId) return result;
    try {
        database.transaction(function(tx) {
            var rNum = parseInt(remoteId, 10) || 0;
            var rStr = String(remoteId);
            var res = tx.executeSql('SELECT local_path FROM synced_files WHERE remote_id = ? OR remote_id = ? LIMIT 1', [rNum, rStr]);
            if (res.rows.length > 0) {
                result = res.rows.item(0).local_path || "";
            }
        });
    } catch(e) {
        console.error("Error looking up local path by remote id:", e);
    }
    return result;
}

function getSyncedStats() {
    var database = getDatabase();
    var stats = { count: 0, totalBytes: 0 };
    if (!database) return stats;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT COUNT(*) as cnt, SUM(file_size) as total_size FROM synced_files');
            if (res.rows.length > 0) {
                stats.count = res.rows.item(0).cnt || 0;
                stats.totalBytes = res.rows.item(0).total_size || 0;
            }
        });
    } catch(e) {
        console.error("Error getting synced stats:", e);
    }
    return stats;
}

function removeSyncedRecord(localPath) {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            tx.executeSql('DELETE FROM synced_files WHERE local_path = ?', [localPath]);
        });
        return true;
    } catch(e) {
        console.error("Error removing sync record:", e);
        return false;
    }
}

function clearAllSyncedRecords() {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            tx.executeSql('DELETE FROM synced_files');
        });
        return true;
    } catch(e) {
        console.error("Error clearing sync records:", e);
        return false;
    }
}

// --- CACHE MANAGEMENT ---

function registerCacheEntry(cacheKey, url, sizeBytes) {
    var database = getDatabase();
    if (!database) return;
    try {
        database.transaction(function(tx) {
            var now = new Date().toISOString();
            tx.executeSql('INSERT OR REPLACE INTO media_cache (cache_key, url, size_bytes, cached_at) VALUES (?, ?, ?, ?)',
                [cacheKey, url, sizeBytes || 102400, now]);
        });
    } catch(e) {
        console.error("Error registering cache:", e);
    }
}

function getCacheStats() {
    var database = getDatabase();
    var stats = { count: 0, totalBytes: 0 };
    if (!database) return stats;
    try {
        database.transaction(function(tx) {
            var res = tx.executeSql('SELECT COUNT(*) as cnt, SUM(size_bytes) as total_size FROM media_cache');
            if (res.rows.length > 0) {
                stats.count = res.rows.item(0).cnt || 0;
                stats.totalBytes = res.rows.item(0).total_size || 0;
            }
        });
    } catch(e) {
        console.error("Error getting cache stats:", e);
    }
    return stats;
}

function clearCacheDatabase() {
    var database = getDatabase();
    if (!database) return false;
    try {
        database.transaction(function(tx) {
            tx.executeSql('DELETE FROM media_cache');
        });
        return true;
    } catch(e) {
        console.error("Error clearing cache database:", e);
        return false;
    }
}
