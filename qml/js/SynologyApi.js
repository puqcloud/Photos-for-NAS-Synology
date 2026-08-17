.pragma library

// Synology Photos REST Web API Client for Ubuntu Touch

function cleanUrl(url) {
    if (!url) return "";
    var u = url.trim();
    if (!u.match(/^https?:\/\//i)) {
        u = "https://" + u;
    }
    return u.replace(/\/+$/, "");
}

function getErrorMessage(code) {
    switch (code) {
        case 100: return "Unknown error occurred.";
        case 101: return "Invalid parameter provided.";
        case 102: return "The requested API does not exist on this Synology NAS.";
        case 103: return "The requested API method does not exist.";
        case 104: return "This API version is not supported by your DSM.";
        case 105: return "User does not have permission to execute this API.";
        case 106: return "Session timeout. Please log in again.";
        case 107: return "Session interrupted by duplicate login.";
        case 119: return "Session expired (119). Please log in again.";
        case 400: return "No such account or incorrect password.";
        case 401: return "Account is disabled or locked.";
        case 402: return "Permission denied. Check Synology Photos app privileges.";
        case 403: return "2-Step verification (OTP) code is required.";
        case 404: return "Invalid 2-Step verification (OTP) code.";
        case 405: return "App-specific password required.";
        case 406: return "OTP enforcement is active for this account.";
        case 407: return "Max login attempts reached. Please try again later.";
        case 408: return "Password expired. Please change it in DSM.";
        case 409: return "Password is too weak.";
        case 500: return "Synology server internal error.";
        case 801: return "Team Space is not enabled or accessible.";
        default: return "Synology error code: " + code;
    }
}

function sendRequest(url, method, params, headers, callback) {
    var xhr = new XMLHttpRequest();
    var paramPairs = [];
    if (params) {
        for (var k in params) {
            if (params.hasOwnProperty(k) && params[k] !== undefined && params[k] !== null) {
                paramPairs.push(encodeURIComponent(k) + "=" + encodeURIComponent(params[k]));
            }
        }
    }
    var fullUrl = url;
    var postData = null;

    if (method.toUpperCase() === "GET") {
        if (paramPairs.length > 0) {
            fullUrl += (url.indexOf("?") === -1 ? "?" : "&") + paramPairs.join("&");
        }
    } else {
        postData = paramPairs.join("&");
    }

    xhr.open(method, fullUrl, true);
    xhr.timeout = 25000;

    if (method.toUpperCase() === "POST") {
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
    }

    if (headers) {
        for (var h in headers) {
            if (headers.hasOwnProperty(h) && headers[h]) {
                xhr.setRequestHeader(h, headers[h]);
            }
        }
    }

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var json = JSON.parse(xhr.responseText);
                    if (json.success) {
                        callback(null, json.data);
                    } else {
                        var errCode = (json.error && json.error.code) ? json.error.code : 100;
                        var errMsg = getErrorMessage(errCode);
                        callback({ code: errCode, message: errMsg, raw: json.error }, null);
                    }
                } catch(e) {
                    callback({ code: -1, message: "Failed to parse JSON response: " + e.message, raw: xhr.responseText }, null);
                }
            } else if (xhr.status === 0) {
                callback({ code: 0, message: "Network connection failed or host unreachable. Check URL and SSL settings." }, null);
            } else {
                callback({ code: xhr.status, message: "HTTP error: " + xhr.status + " " + xhr.statusText }, null);
            }
        }
    };

    xhr.ontimeout = function() {
        callback({ code: -2, message: "Connection timed out. Please check your network and NAS address." }, null);
    };

    xhr.onerror = function() {
        callback({ code: 0, message: "Network error occurred." }, null);
    };

    xhr.send(postData);
}

// 1. Query Synology API Info
function queryApiInfo(serverUrl, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/query.cgi";
    var params = {
        api: "SYNO.API.Info",
        version: 1,
        method: "query",
        query: "all"
    };
    sendRequest(url, "GET", params, null, callback);
}

// 2. Login to Synology DSM
function login(serverUrl, account, password, otpCode, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.API.Auth",
        version: 7,
        method: "login",
        account: account,
        passwd: password,
        format: "sid",
        enable_syno_token: "yes"
    };

    if (otpCode && otpCode.trim().length > 0) {
        params["otp_code"] = otpCode.trim();
    }

    sendRequest(url, "POST", params, null, function(err, data) {
        if (err && (err.code === 104 || err.code === 103)) {
            // Fallback to version 6
            params.version = 6;
            sendRequest(url, "POST", params, null, function(err2, data2) {
                if (err2 && (err2.code === 104 || err2.code === 103)) {
                    // Fallback to version 3
                    params.version = 3;
                    sendRequest(url, "POST", params, null, callback);
                } else {
                    callback(err2, data2);
                }
            });
        } else {
            callback(err, data);
        }
    });
}

// 3. Logout
function logout(serverUrl, sid, synotoken, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.API.Auth",
        version: 7,
        method: "logout",
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, function(err, data) {
        if (callback) callback(err, data);
    });
}

// 4. Fetch Photos list
function getPhotos(serverUrl, sid, synotoken, offset, limit, folderId, callback) {
    var cb = callback;
    var fId = folderId;
    if (typeof folderId === "function") {
        cb = folderId;
        fId = undefined;
    }
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Item",
        version: 1,
        method: "list",
        offset: offset || 0,
        limit: limit || 500,
        additional: '["thumbnail","resolution","orientation","exif","tag","description","gps","address","video_meta"]',
        _sid: sid
    };
    if (fId !== undefined && fId !== null) {
        params["folder_id"] = fId;
    }
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, cb);
}

// 4b. Fetch Favorites list
function getFavorites(serverUrl, sid, synotoken, offset, limit, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Item",
        version: 1,
        method: "list",
        offset: offset || 0,
        limit: limit || 500,
        is_favorite: true,
        additional: '["thumbnail","resolution","orientation","exif","tag","description","gps","address","video_meta"]',
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, callback);
}

// 4c. Toggle Favorite
function toggleFavorite(serverUrl, sid, synotoken, itemIds, isAdding, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    
    var realArray = [];
    if (typeof itemIds === 'number' || typeof itemIds === 'string') {
        realArray = [parseInt(itemIds)];
    } else if (itemIds && itemIds.length !== undefined) {
        for (var i = 0; i < itemIds.length; i++) {
            realArray.push(parseInt(itemIds[i]));
        }
    }
    
    if (realArray.length === 0) {
        if (callback) callback(null);
        return;
    }
    
    var idsString = JSON.stringify(realArray);
    
    var postData = {
        api: "SYNO.Foto.Browse.Item",
        version: 7,
        method: "set_favorite",
        id: idsString,
        favorite: isAdding,
        _sid: sid
    };
    
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;
    
    sendRequest(url, "POST", postData, headers, function(err, data) {
        if (err) {
            console.log("ToggleFavorite Error on IDs " + idsString + ":", JSON.stringify(err));
        }
        if (callback) callback(err, data);
    });
}

// 5. Fetch Albums list
function getAlbums(serverUrl, sid, synotoken, offset, limit, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Album",
        version: 1,
        method: "list",
        offset: offset || 0,
        limit: limit || 50,
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, callback);
}

// 6. Fetch Folders list
function getFolders(serverUrl, sid, synotoken, offset, limit, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Folder",
        version: 1,
        method: "list",
        offset: offset || 0,
        limit: limit || 50,
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, callback);
}

// 6b. Get a single folder by ID
var _folderNameCache = {};
function getFolderById(serverUrl, sid, synotoken, folderId, callback) {
    if (_folderNameCache[folderId]) {
        callback(null, _folderNameCache[folderId]);
        return;
    }
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Folder",
        version: 1,
        method: "get",
        id: folderId,
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;
    sendRequest(url, "GET", params, headers, function(err, data) {
        if (!err && data && data.folder) {
            _folderNameCache[folderId] = data.folder;
        }
        callback(err, data ? data.folder : null);
    });
}

function clearFolderCache() {
    _folderNameCache = {};
}

// 7. Get Photos within an Album
function getAlbumPhotos(serverUrl, sid, synotoken, albumId, offset, limit, callback, passphrase) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Item",
        version: 1,
        method: "list",
        offset: offset || 0,
        limit: limit || 50,
        additional: '["thumbnail","resolution","orientation","exif","tag","description","gps","address","video_meta"]',
        _sid: sid
    };
    
    if (passphrase) {
        params.passphrase = '"' + passphrase + '"';
    } else {
        params.album_id = albumId;
    }
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, callback);
}

// 8. Generate Thumbnail URL
function getThumbnailUrl(serverUrl, sid, synotoken, itemId, cacheKey, size, type, passphrase) {
    var base = cleanUrl(serverUrl);
    var sz = size || "m"; // 'sm', 'm', 'xl'
    var t = type || "unit"; // 'unit', 'album'
    var cKey = cacheKey;
    if (!cKey && t === "unit" && itemId) {
        cKey = String(itemId) + "_0";
    }
    var url = base + "/webapi/entry.cgi?api=SYNO.Foto.Thumbnail&version=2&method=get&id=" +
              encodeURIComponent(itemId) + "&size=" + encodeURIComponent(sz) + "&type=" + encodeURIComponent(t) + "&_sid=" + encodeURIComponent(sid);
    if (cKey) {
        url += "&cache_key=" + encodeURIComponent(cKey);
    }
    if (synotoken) {
        url += "&SynoToken=" + encodeURIComponent(synotoken);
    }
    if (passphrase) {
        url += "&passphrase=%22" + encodeURIComponent(passphrase) + "%22";
    }
    return url;
}

// 9. Generate Download / Original URL
function getDownloadUrl(serverUrl, sid, synotoken, itemId, passphrase) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi?api=SYNO.Foto.Download&version=1&method=download&unit_id=%5B" +
              encodeURIComponent(itemId) + "%5D&_sid=" + encodeURIComponent(sid);
    if (synotoken) {
        url += "&SynoToken=" + encodeURIComponent(synotoken);
    }
    if (passphrase) {
        url += "&passphrase=%22" + encodeURIComponent(passphrase) + "%22";
    }
    return url;
}

// 9b. Get Streaming URL for Videos
function getStreamingUrl(serverUrl, sid, synotoken, itemId, passphrase) {
    // SYNO.Foto.Download delivers the original MP4 video stream with
    // HTTP 206 Partial Content (Range requests) support, whereas
    // SYNO.Foto.Streaming requires server-side AME transcoding license.
    return getDownloadUrl(serverUrl, sid, synotoken, itemId, passphrase);
}

// 10. Search Items (Photos / Videos)
function searchItems(serverUrl, sid, synotoken, keyword, offset, limit, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Search.Search",
        version: 1,
        method: "list_item",
        keyword: JSON.stringify(keyword),
        offset: offset || 0,
        limit: limit || 100,
        additional: '["thumbnail","resolution","orientation"]',
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, callback);
}

// 11. Create Album
function createAlbum(serverUrl, sid, synotoken, name, itemIds, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var postData = {
        api: "SYNO.Foto.Browse.NormalAlbum",
        version: 1,
        method: "create",
        name: name,
        _sid: sid
    };
    if (itemIds && itemIds.length > 0) {
        postData["item"] = JSON.stringify(itemIds);
    }
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", postData, headers, callback);
}

function createShareLink(serverUrl, sid, synotoken, itemIds, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Browse.NormalAlbum";
    
    var d = new Date();
    var dateString = d.getFullYear() + "-" + 
                     ("0" + (d.getMonth() + 1)).slice(-2) + "-" + 
                     ("0" + d.getDate()).slice(-2);
                     
    var params = {
        api: "SYNO.Foto.Browse.NormalAlbum",
        version: 1,
        method: "create",
        name: "\"" + dateString + "\"",
        shared: "true",
        _sid: sid
    };
    if (itemIds && itemIds.length > 0) {
        params.item = JSON.stringify(itemIds);
    }
    
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;
    
    sendRequest(url, "POST", params, headers, function(err, data) {
        if (err) {
            callback(err, null);
            return;
        }
        if (data && data.album) {
            callback(null, data.album);
        } else {
            callback(null, data);
        }
    });
}

function updateSharePassphrase(serverUrl, sid, synotoken, passphrase, password, expiration, permission, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Sharing.Passphrase";
    var postData = {
        api: "SYNO.Foto.Sharing.Passphrase",
        method: "update",
        version: 1,
        passphrase: "\"" + passphrase + "\"",
        expiration: expiration || 0,
        permission: permission,
        _sid: sid
    };
    if (password && password.length > 0) {
        postData.password = "\"" + password + "\"";
    } else {
        postData.password = "\"\"";
    }
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;
    sendRequest(url, "POST", postData, headers, callback);
}

// 11b. Search Users for sharing
function searchUsers(serverUrl, sid, synotoken, keyword, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Sharing.Misc";
    var params = {
        api: "SYNO.Foto.Sharing.Misc",
        version: 1,
        method: "list_user_group",
        team_space_sharable_list: "false",
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", params, headers, function(err, data) {
        if (err) { callback(err, null); return; }
        var list = data.list || [];
        var res = [];
        for (var i=0; i<list.length; i++) {
            if (list[i].type === "user" && list[i].name.toLowerCase().indexOf(keyword.toLowerCase()) !== -1) {
                res.push({ id: list[i].id, name: list[i].name, type: "user" });
            }
        }
        callback(null, res);
    });
}

// 11c. Search Groups for sharing
function searchGroups(serverUrl, sid, synotoken, keyword, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Sharing.Misc";
    var params = {
        api: "SYNO.Foto.Sharing.Misc",
        version: 1,
        method: "list_user_group",
        team_space_sharable_list: "false",
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", params, headers, function(err, data) {
        if (err) { callback(err, null); return; }
        var list = data.list || [];
        var res = [];
        for (var i=0; i<list.length; i++) {
            if (list[i].type === "group" && list[i].name.toLowerCase().indexOf(keyword.toLowerCase()) !== -1) {
                res.push({ id: list[i].id, name: list[i].name, type: "group" });
            }
        }
        callback(null, res);
    });
}
// 12. Add Items to Album
function addItemsToAlbum(serverUrl, sid, synotoken, albumId, itemIds, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var postData = {
        api: "SYNO.Foto.Browse.NormalAlbum",
        version: 1,
        method: "add_item",
        id: albumId,
        item: JSON.stringify(itemIds),
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", postData, headers, callback);
}

// 12b. Remove Items from Album
function removeItemsFromAlbum(serverUrl, sid, synotoken, albumId, itemIds, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var postData = {
        api: "SYNO.Foto.Browse.NormalAlbum",
        version: 1,
        method: "delete_item",
        id: albumId,
        item: JSON.stringify(itemIds),
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", postData, headers, callback);
}

// 13. Delete Album
function deleteAlbum(serverUrl, sid, synotoken, albumId, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var postData = {
        api: "SYNO.Foto.Browse.Album",
        version: 1,
        method: "delete",
        id: JSON.stringify([albumId]),
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", postData, headers, callback);
}

// 14. Get single item with full details
function getItemDetail(serverUrl, sid, synotoken, itemId, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var params = {
        api: "SYNO.Foto.Browse.Item",
        version: 1,
        method: "get",
        id: JSON.stringify([itemId]),
        additional: '["thumbnail","resolution","orientation","exif","tag","description","gps","address","video_meta","video_convert"]',
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "GET", params, headers, function(err, data) {
        if (err) {
            callback(err, null);
        } else {
            var list = data && data.list ? data.list : [];
            callback(null, list.length > 0 ? list[0] : null);
        }
    });
}

// 15. Delete items
function deleteItems(serverUrl, sid, synotoken, itemIds, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi";
    var postData = {
        api: "SYNO.Foto.Browse.Item",
        version: 1,
        method: "delete",
        id: JSON.stringify(itemIds),
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", postData, headers, callback);
}

// 16. Get Shared With Me Albums
function getSharedWithMeAlbums(serverUrl, sid, synotoken, offset, limit, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Sharing.Misc";
    var params = {
        api: "SYNO.Foto.Sharing.Misc",
        version: 2,
        method: "list_shared_with_me_album",
        additional: JSON.stringify(["sharing_info", "thumbnail", "access_permission"]),
        offset: offset || 0,
        limit: limit || 50,
        sort_by: "\"share_modify_time\"",
        sort_direction: "\"desc\"",
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", params, headers, function(err, data) {
        if (err) {
            callback(err, null);
        } else {
            callback(null, data);
        }
    });
}

// 17. Get Shared With Others Albums
function getSharedWithOthersAlbums(serverUrl, sid, synotoken, offset, limit, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Browse.Album";
    var params = {
        api: "SYNO.Foto.Browse.Album",
        version: 4,
        method: "list",
        offset: offset || 0,
        limit: limit || 50,
        additional: JSON.stringify(["thumbnail", "sharing_info"]),
        category: "\"shared\"",
        sort_by: "\"share_modify_time\"",
        sort_direction: "\"desc\"",
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", params, headers, function(err, data) {
        if (err) {
            callback(err, null);
        } else {
            callback(null, data);
        }
    });
}

// 18. Get Album Info
function getAlbumInfo(serverUrl, sid, synotoken, albumId, callback) {
    var base = cleanUrl(serverUrl);
    var url = base + "/webapi/entry.cgi/SYNO.Foto.Browse.Album";
    var params = {
        api: "SYNO.Foto.Browse.Album",
        version: 4,
        method: "get",
        id: JSON.stringify([albumId]),
        additional: JSON.stringify(["sharing_info", "flex_section", "provider_count", "thumbnail"]),
        _sid: sid
    };
    var headers = {};
    if (synotoken) headers["X-SYNO-TOKEN"] = synotoken;

    sendRequest(url, "POST", params, headers, function(err, data) {
        if (err) {
            callback(err, null);
        } else if (data && data.list && data.list.length > 0) {
            callback(null, data.list[0]);
        } else {
            callback(new Error("Album not found"), null);
        }
    });
}

// --- BACKUP / SYNC HELPERS ---

// Formats a duration in milliseconds as "mm:ss" (or "h:mm:ss" when >= 1h).
// When compact is true, "0:05" becomes "0:05" (short "m:ss" form).
function formatDuration(ms, compact) {
    if (!ms || isNaN(ms) || ms < 0) ms = 0;
    var totalSeconds = Math.floor(ms / 1000);
    var h = Math.floor(totalSeconds / 3600);
    var m = Math.floor((totalSeconds % 3600) / 60);
    var s = totalSeconds % 60;
    var ss = s < 10 ? "0" + s : String(s);
    if (h > 0) {
        var mm = m < 10 ? "0" + m : String(m);
        return h + ":" + mm + ":" + ss;
    }
    if (compact) return m + ":" + ss;
    var mm2 = m < 10 ? "0" + m : String(m);
    return mm2 + ":" + ss;
}

// Checks which of the given item ids still exist on the server.
// Implemented via the documented SYNO.Foto.Browse.Item list API (paged,
// first 5000 items) instead of per-item lookups.
// callback(err, { present: {id:true}, missing: {id:true} })
function checkItemsExist(serverUrl, sid, synotoken, itemIds, callback, progressCb) {
    var ids = itemIds || [];
    if (ids.length === 0) {
        callback(null, { present: {}, missing: {} });
        return;
    }
    var wanted = {};
    for (var i = 0; i < ids.length; i++) wanted[String(ids[i])] = true;

    var found = {};
    var offset = 0;
    var limit = 500;
    var maxItems = 5000;

    function fetchPage() {
        getPhotos(serverUrl, sid, synotoken, offset, limit, function(err, data) {
            if (err) {
                callback(err, null);
                return;
            }
            var list = (data && data.list) ? data.list : [];
            for (var i = 0; i < list.length; i++) {
                var id = String(list[i].id);
                if (wanted[id]) found[id] = true;
            }
            if (typeof progressCb === "function") {
                progressCb(Math.min(offset + list.length, ids.length), ids.length);
            }
            offset += list.length;
            if (list.length === limit && offset < maxItems) {
                fetchPage();
            } else {
                var missing = {};
                for (var k in wanted) {
                    if (!found[k]) missing[k] = true;
                }
                callback(null, { present: found, missing: missing });
            }
        });
    }
    fetchPage();
}

// Returns an image-provider URL that routes the server thumbnail through the
// local cache provider (image://syno/remote/<encoded-url>/<size>), so viewed
// images are counted and cleared by the "Clear Cache" setting. The URL is
// double-encoded: the QML engine decodes the provider id once, leaving a
// single percent-encoded URL for the provider to decode.
function getProviderThumbnailUrl(serverUrl, sid, synotoken, itemId, cacheKey, size, type, passphrase) {
    var url = getThumbnailUrl(serverUrl, sid, synotoken, itemId, cacheKey, size, type, passphrase);
    return "image://syno/remote/" + encodeURIComponent(url) + "/" + (size || "m");
}

// DSM stores EXIF wall-clock times as plain UTC epochs (the API carries no
// timezone), so server items must be displayed with UTC fields to recover
// the original wall-clock time. Device files carry real epochs and use
// local fields.
function dateParts(item) {
    var local = item && (item.isLocal === true || (item.localPath && item.localPath.length > 0));
    var d = new Date((item && item.time ? item.time : 0) * 1000);
    if (isNaN(d.getTime())) d = new Date(0);
    return {
        year: local ? d.getFullYear() : d.getUTCFullYear(),
        month: local ? d.getMonth() : d.getUTCMonth(),
        date: local ? d.getDate() : d.getUTCDate(),
        day: local ? d.getDay() : d.getUTCDay(),
        hours: local ? d.getHours() : d.getUTCHours(),
        minutes: local ? d.getMinutes() : d.getUTCMinutes()
    };
}
