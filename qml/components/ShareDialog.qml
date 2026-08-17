import QtQuick 2.9
import Ubuntu.Components 1.3
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi

Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 999

    property var itemIds: []
    property string passphrase: ""
    property string shareUrl: ""
    property bool isShareEnabled: false
    property bool hasPassword: false
    property string password: ""
    property bool showPassword: false
    property bool hasExpiration: false
    property int expiration: 0
    property string privacyRole: "view"
    property var invitees: []
    property int currentView: 0
    property int editingInviteeIndex: -1
    property string editingInviteeRole: "view"

    function openSheet(ids) {
        itemIds = ids || [];
        passphrase = "";
        shareUrl = i18n.tr("Loading link...");
        isShareEnabled = false; hasPassword = false; password = ""; showPassword = false;
        hasExpiration = false; expiration = 0; privacyRole = "view";
        invitees = [];
        currentView = 0;
        root.visible = true;
        animY.start();
        
        SynoApi.createShareLink(mainView.serverUrl, mainView.sid, mainView.synotoken, itemIds, function(err, data) {
            if (err) {
                mainView.showToast(i18n.tr("Failed to load share link: %1").arg(err.message), true, false);
            } else {
                var actualPassphrase = "";
                if (data && data.passphrase) actualPassphrase = data.passphrase;
                else if (data && data.share_url) actualPassphrase = data.share_url.split("/").pop();
                else if (data && data.list && data.list.length > 0) actualPassphrase = data.list[0].passphrase;
                
                if (actualPassphrase) {
                    passphrase = actualPassphrase;
                    shareUrl = mainView.serverUrl.replace(/\/+$/, "") + "/mo/sharing/" + passphrase;
                }
            }
        });
    }

    function closeSheet() {
        animYClose.start();
    }
    
    NumberAnimation { id: animY; target: contentContainer; property: "y"; from: root.height; to: 0; duration: 250; easing.type: Easing.OutCubic }
    NumberAnimation { id: animYClose; target: contentContainer; property: "y"; to: root.height; duration: 250; easing.type: Easing.OutCubic; onStopped: root.visible = false }

    function saveShare() {
        if (!isShareEnabled && invitees.length === 0) {
            mainView.showToast(i18n.tr("Share saved successfully"), false, true);
            closeSheet();
            return;
        }
        
        if (!passphrase) {
            mainView.showToast(i18n.tr("Still loading share link, please wait"), false, false);
            return;
        }
        
        mainView.showLoading(i18n.tr("Saving share..."));
        
        var perm = [];
        if (isShareEnabled && privacyRole !== "private") {
            perm.push({ action: "update", role: privacyRole, member: { type: "public" } });
        }
        for (var i = 0; i < invitees.length; i++) {
            var member = { type: invitees[i].type };
            if (typeof invitees[i].id === 'number') {
                member.id = invitees[i].id;
            } else {
                member.name = invitees[i].id;
            }
            perm.push({ action: "update", role: invitees[i].role, member: member });
        }
        var exp = hasExpiration ? expiration : 0;
        var pw = isShareEnabled ? password : "";
        
        SynoApi.updateSharePassphrase(mainView.serverUrl, mainView.sid, mainView.synotoken,
            passphrase, pw, exp, JSON.stringify(perm), function(err) {
            mainView.hideLoading();
            if (err) {
                mainView.showToast(i18n.tr("Failed to apply settings: %1").arg(err.message), true, false);
            } else {
                mainView.showToast(i18n.tr("Share saved successfully"), false, true);
                closeSheet();
            }
        });
    }

    function fmtDate(ts) {
        if (!ts) return "";
        var d = new Date(ts * 1000);
        var m = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
        return d.getDate() + " " + m[d.getMonth()] + " " + d.getFullYear();
    }

    Item {
        id: contentContainer
        width: parent.width; height: parent.height
        y: parent.height

        Rectangle { anchors.fill: parent; color: Theme.background }

        // ----- VIEW 0: MAIN SHARE -----
        Item {
            id: mainViewRect
            anchors.fill: parent
            visible: root.currentView === 0

            // Header
            Item { width: parent.width; height: units.gu(6)
                Icon { name: "close"; width: units.gu(2.5); height: units.gu(2.5); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(1.5)
                    MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: closeSheet() }
                }
                Label { text: i18n.tr("Share"); font.pixelSize: units.gu(2.2); font.weight: Font.DemiBold; color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(6) }
                Label { text: i18n.tr("DONE"); font.pixelSize: units.gu(1.8); font.weight: Font.DemiBold; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(1.5)
                    MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: saveShare() }
                }
            }
            
            Flickable {
                width: parent.width; height: parent.height - units.gu(6); y: units.gu(6); contentHeight: mainCol.height + units.gu(4); clip: true
                Column {
                    id: mainCol; width: parent.width; spacing: 0
                    
                    // Top image preview
                    Item { width: parent.width; height: units.gu(18)
                        Rectangle {
                            width: units.gu(12); height: units.gu(12); radius: units.gu(1); color: "#E0E0E0"
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -units.gu(1)
                            clip: true
                            Icon {
                                name: "stock_image"; anchors.centerIn: parent; width: units.gu(4); height: units.gu(4); color: "#B0B0B0"
                                visible: previewImage.status !== Image.Ready
                            }
                            Image {
                                id: previewImage
                                anchors.fill: parent
                                source: (itemIds && itemIds.length > 0) ? SynoApi.getProviderThumbnailUrl(mainView.serverUrl, mainView.sid, mainView.synotoken, itemIds[0], "share", "sm") : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }
                        }
                        Label {
                            text: (itemIds && itemIds.length > 1) ? i18n.tr("%1 items").arg(itemIds.length) : i18n.tr("1 item")
                            font.pixelSize: units.gu(1.4)
                            color: Theme.textMuted
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: itemIds && itemIds.length > 0
                        }
                    }
                    
                    // Enable share link
                    Rectangle { width: parent.width; height: units.gu(6); color: "transparent"
                        Label { text: i18n.tr("Enable share link"); font.pixelSize: units.gu(1.8); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                        Rectangle { width: units.gu(5.5); height: units.gu(3); radius: units.gu(1.5); color: isShareEnabled ? Theme.primary : "#E0E0E0"; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2)
                            Rectangle { width: units.gu(2.6); height: units.gu(2.6); radius: units.gu(1.3); color: "#fff"; anchors.verticalCenter: parent.verticalCenter
                                x: isShareEnabled ? parent.width - width - units.dp(2) : units.dp(2)
                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: isShareEnabled = !isShareEnabled }
                        }
                    }
                    Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }

                    Column {
                        width: parent.width; visible: isShareEnabled
                        
                        // Share Link section
                        Item { width: parent.width; height: units.gu(4)
                            Label { text: i18n.tr("Share Link"); font.pixelSize: units.gu(1.5); color: Theme.primary; font.weight: Font.DemiBold; anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(0.5); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                        }
                        Item { width: parent.width; height: units.gu(4)
                            Label { text: shareUrl; font.pixelSize: units.gu(1.7); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2); elide: Text.ElideMiddle; width: parent.width - units.gu(4) }
                        }
                        Item { width: parent.width; height: units.gu(5)
                            Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2); spacing: units.gu(1)
                                Rectangle { width: units.gu(8); height: units.gu(3.5); radius: units.gu(1.75); border.color: Theme.divider; border.width: units.dp(1); color: "transparent"
                                    Label { text: i18n.tr("Copy"); anchors.centerIn: parent; font.pixelSize: units.gu(1.6); color: Theme.textDark }
                                    MouseArea { anchors.fill: parent; onClicked: mainView.showToast(i18n.tr("Copied"), false, true) }
                                }
                                Rectangle { width: units.gu(8); height: units.gu(3.5); radius: units.gu(1.75); border.color: Theme.divider; border.width: units.dp(1); color: "transparent"
                                    Label { text: i18n.tr("Share"); anchors.centerIn: parent; font.pixelSize: units.gu(1.6); color: Theme.textDark }
                                }
                            }
                        }
                        Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }
                        
                        // Privacy Settings
                        Item { width: parent.width; height: units.gu(5)
                            Label { text: i18n.tr("Privacy Settings"); font.pixelSize: units.gu(1.5); color: Theme.primary; font.weight: Font.DemiBold; anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(0.5); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                        }
                        Rectangle { width: parent.width; height: units.gu(7); color: "transparent"
                            Column { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2)
                                Label { text: privacyRole === "private" ? i18n.tr("Private") : i18n.tr("Public"); font.pixelSize: units.gu(1.8); color: Theme.textDark }
                                Label { text: privacyRole === "private" ? i18n.tr("Only invitees can access") : (privacyRole === "download" ? i18n.tr("Anyone with the link can download") : i18n.tr("Anyone with the link can view")); font.pixelSize: units.gu(1.4); color: Theme.textMuted }
                            }
                            Icon { name: "go-next"; width: units.gu(2); height: units.gu(2); color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2) }
                            MouseArea { anchors.fill: parent; onClicked: privacyPopup.visible = true }
                        }
                        Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }
                        
                        // Require password
                        Rectangle { width: parent.width; height: units.gu(6); color: "transparent"
                            Label { text: i18n.tr("Require password"); font.pixelSize: units.gu(1.8); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                            Rectangle { width: units.gu(5.5); height: units.gu(3); radius: units.gu(1.5); color: hasPassword ? Theme.primary : "#E0E0E0"; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2)
                                Rectangle { width: units.gu(2.6); height: units.gu(2.6); radius: units.gu(1.3); color: "#fff"; anchors.verticalCenter: parent.verticalCenter
                                    x: hasPassword ? parent.width - width - units.dp(2) : units.dp(2)
                                    Behavior on x { NumberAnimation { duration: 150 } }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { hasPassword = !hasPassword; if(hasPassword) passwordPopup.visible = true; else password = ""; } }
                        }
                        Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }
                        
                        // Set expiration date
                        Rectangle { width: parent.width; height: units.gu(6); color: "transparent"
                            Label { text: i18n.tr("Set expiration date"); font.pixelSize: units.gu(1.8); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                            Label { text: hasExpiration ? fmtDate(expiration) : ""; font.pixelSize: units.gu(1.4); color: Theme.primary; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(8) }
                            Rectangle { width: units.gu(5.5); height: units.gu(3); radius: units.gu(1.5); color: hasExpiration ? Theme.primary : "#E0E0E0"; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2)
                                Rectangle { width: units.gu(2.6); height: units.gu(2.6); radius: units.gu(1.3); color: "#fff"; anchors.verticalCenter: parent.verticalCenter
                                    x: hasExpiration ? parent.width - width - units.dp(2) : units.dp(2)
                                    Behavior on x { NumberAnimation { duration: 150 } }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { hasExpiration = !hasExpiration; if(hasExpiration) expirationPopup.visible = true; } }
                        }
                        Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }
                    } // end of isShareEnabled Column
                    
                    // Invitee List is ALWAYS visible
                    Item { width: parent.width; height: units.gu(5)
                        Label { text: i18n.tr("Invitee List"); font.pixelSize: units.gu(1.5); color: Theme.primary; font.weight: Font.DemiBold; anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(0.5); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                    }
                    Rectangle { width: parent.width; height: units.gu(7); color: "transparent"
                        Column { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2)
                            Label { text: i18n.tr("User/Group"); font.pixelSize: units.gu(1.8); color: Theme.textDark }
                            Label { text: invitees.length === 0 ? i18n.tr("Not shared with any users yet") : i18n.tr("%1 user(s) added").arg(invitees.length); font.pixelSize: units.gu(1.4); color: Theme.textMuted }
                        }
                        Icon { name: "go-next"; width: units.gu(2); height: units.gu(2); color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2) }
                        MouseArea { anchors.fill: parent; onClicked: currentView = 1 }
                    }
                    Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider }
                }
            }
            
            // Privacy Popup
            Rectangle {
                id: privacyPopup; anchors.fill: parent; color: "transparent"; visible: false; z: 10
                Rectangle { anchors.fill: parent; color: "#000"; opacity: 0.5; MouseArea { anchors.fill: parent; onClicked: privacyPopup.visible = false } }
                Rectangle { width: parent.width; height: units.gu(24); anchors.bottom: parent.bottom; color: Theme.background; radius: units.gu(2)
                    Column { width: parent.width; anchors.bottom: parent.bottom
                        Repeater {
                            model: [
                                { role: "private", title: i18n.tr("Private"), desc: i18n.tr("Only invitees can access") },
                                { role: "view", title: i18n.tr("Public"), desc: i18n.tr("Anyone with the link can view") },
                                { role: "download", title: i18n.tr("Public"), desc: i18n.tr("Anyone with the link can download") }
                            ]
                            Rectangle { width: parent.width; height: units.gu(7); color: "transparent"
                                Column { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2)
                                    Label { text: modelData.title; font.pixelSize: units.gu(1.8); color: Theme.textDark }
                                    Label { text: modelData.desc; font.pixelSize: units.gu(1.4); color: Theme.textMuted }
                                }
                                Icon { name: "ok"; width: units.gu(2); height: units.gu(2); color: Theme.primary; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2); visible: privacyRole === modelData.role }
                                Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider; anchors.bottom: parent.bottom }
                                MouseArea { anchors.fill: parent; onClicked: { privacyRole = modelData.role; privacyPopup.visible = false; } }
                            }
                        }
                    }
                }
            }
            
            // Password Popup
            Rectangle {
                id: passwordPopup; anchors.fill: parent; color: "transparent"; visible: false; z: 10
                Rectangle { anchors.fill: parent; color: "#000"; opacity: 0.5; MouseArea { anchors.fill: parent; onClicked: { passwordPopup.visible = false; if(!password) hasPassword = false; } } }
                Rectangle { width: parent.width - units.gu(6); height: units.gu(18); color: Theme.background; radius: units.gu(1.5); anchors.centerIn: parent
                    Label { text: i18n.tr("Enter password"); font.pixelSize: units.gu(2); font.weight: Font.DemiBold; color: Theme.textDark; anchors.top: parent.top; anchors.topMargin: units.gu(2); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                    TextField { id: pwInput; width: parent.width - units.gu(4); height: units.gu(4); anchors.top: parent.top; anchors.topMargin: units.gu(6); anchors.horizontalCenter: parent.horizontalCenter; echoMode: showPwCheck.checked ? TextInput.Normal : TextInput.Password; text: password }
                    Row { anchors.top: pwInput.bottom; anchors.topMargin: units.gu(1); anchors.left: parent.left; anchors.leftMargin: units.gu(2); spacing: units.gu(1)
                        CheckBox { id: showPwCheck; checked: false; width: units.gu(2); height: units.gu(2) }
                        Label { text: i18n.tr("Show password"); font.pixelSize: units.gu(1.5); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(2); anchors.right: parent.right; anchors.rightMargin: units.gu(2); spacing: units.gu(2)
                        Label { text: i18n.tr("CANCEL"); font.pixelSize: units.gu(1.6); color: Theme.primary; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: { passwordPopup.visible = false; if(!password) hasPassword = false; } }
                        }
                        Label { text: i18n.tr("OK"); font.pixelSize: units.gu(1.6); color: Theme.primary; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: { password = pwInput.text; passwordPopup.visible = false; if(!password) hasPassword = false; } }
                        }
                    }
                }
            }
            
            // Expiration Popup
            Rectangle {
                id: expirationPopup; anchors.fill: parent; color: "transparent"; visible: false; z: 10
                Rectangle { anchors.fill: parent; color: "#000"; opacity: 0.5; MouseArea { anchors.fill: parent; onClicked: { expirationPopup.visible = false; if(!expiration) hasExpiration = false; } } }
                Rectangle { width: parent.width - units.gu(6); height: units.gu(15); color: Theme.background; radius: units.gu(1.5); anchors.centerIn: parent
                    Label { text: i18n.tr("Expiration Days"); font.pixelSize: units.gu(2); font.weight: Font.DemiBold; color: Theme.textDark; anchors.top: parent.top; anchors.topMargin: units.gu(2); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                    TextField { id: expInput; width: parent.width - units.gu(4); height: units.gu(4); anchors.top: parent.top; anchors.topMargin: units.gu(6); anchors.horizontalCenter: parent.horizontalCenter; text: "30"; inputMethodHints: Qt.ImhDigitsOnly }
                    Row { anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(2); anchors.right: parent.right; anchors.rightMargin: units.gu(2); spacing: units.gu(2)
                        Label { text: i18n.tr("CANCEL"); font.pixelSize: units.gu(1.6); color: Theme.primary; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: { expirationPopup.visible = false; if(!expiration) hasExpiration = false; } }
                        }
                        Label { text: i18n.tr("OK"); font.pixelSize: units.gu(1.6); color: Theme.primary; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: { 
                                var d = new Date(); d.setHours(0,0,0,0); d.setDate(d.getDate() + parseInt(expInput.text || "30")); 
                                expiration = Math.floor(d.getTime() / 1000); 
                                expirationPopup.visible = false; 
                            } }
                        }
                    }
                }
            }
        }

        // ----- VIEW 1: INVITEE LIST WITH SELECT2 DROPDOWN -----
        Item {
            id: inviteeListRect
            anchors.fill: parent
            visible: root.currentView === 1
            
            property var preFetchedList: []
            property bool isFetching: false

            onVisibleChanged: {
                if (visible) {
                    preFetchUsers();
                    doSearch(searchInput.text);
                } else {
                    searchDropdown.visible = false;
                }
            }

            function preFetchUsers() {
                if (isFetching || preFetchedList.length > 0) return;
                isFetching = true;
                
                SynoApi.searchUsers(mainView.serverUrl, mainView.sid, mainView.synotoken, "", function(err, users) {
                    if (err) {
                        mainView.showToast("Failed to fetch users: " + err.message, false, false);
                    }
                    if (!err && users) {
                        var arr = preFetchedList.slice();
                        for (var i=0; i<users.length; i++) arr.push({ uid: users[i].id, name: users[i].name, type: "user" });
                        preFetchedList = arr;
                        doSearch(searchInput.text);
                    }
                });
                SynoApi.searchGroups(mainView.serverUrl, mainView.sid, mainView.synotoken, "", function(err, groups) {
                    if (!err && groups) {
                        var arr = preFetchedList.slice();
                        for (var i=0; i<groups.length; i++) arr.push({ uid: groups[i].id, name: groups[i].name, type: "group" });
                        preFetchedList = arr;
                        doSearch(searchInput.text);
                    }
                });
            }
            
            function doSearch(kw) {
                searchModel.clear();
                var lowerKw = kw.toLowerCase();
                for (var i=0; i<preFetchedList.length; i++) {
                    var item = preFetchedList[i];
                    if (lowerKw === "" || item.name.toLowerCase().indexOf(lowerKw) !== -1) {
                        searchModel.append({ uid: item.uid, name: item.name, type: item.type });
                    }
                }
            }
            
            // Header
            Item { width: parent.width; height: units.gu(6)
                Icon { name: "back"; width: units.gu(2.5); height: units.gu(2.5); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(1.5)
                    MouseArea { anchors.fill: parent; anchors.margins: -units.gu(1); onClicked: currentView = 0 }
                }
                Label { text: i18n.tr("Invitee List"); font.pixelSize: units.gu(2.2); font.weight: Font.DemiBold; color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(6) }
            }
            
            // Select2-like Search Box
            Item {
                id: searchBoxContainer
                width: parent.width; height: units.gu(6); y: units.gu(6); z: 10
                
                TextField {
                    id: searchInput
                    width: parent.width - units.gu(4); height: units.gu(4)
                    anchors.centerIn: parent
                    placeholderText: i18n.tr("Add user or group...")
                    onTextChanged: {
                        inviteeListRect.doSearch(text);
                        searchDropdown.visible = true;
                    }
                    onActiveFocusChanged: {
                        if (activeFocus) searchDropdown.visible = true;
                    }
                }
                
                // The Dropdown
                Rectangle {
                    id: searchDropdown
                    width: searchInput.width; height: Math.min(units.gu(24), searchModel.count * units.gu(6))
                    anchors.top: searchInput.bottom; anchors.topMargin: units.dp(2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.background
                    border.color: Theme.divider; border.width: units.dp(1); radius: units.dp(4)
                    visible: false
                    clip: true
                    
                    ListModel { id: searchModel }
                    
                    // Empty state in dropdown
                    Label {
                        text: inviteeListRect.isFetching ? i18n.tr("Loading...") : i18n.tr("No matches found")
                        font.pixelSize: units.gu(1.6)
                        color: Theme.textMuted
                        anchors.centerIn: parent
                        visible: searchModel.count === 0
                    }

                    ListView {
                        anchors.fill: parent
                        model: searchModel
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            width: parent.width; height: units.gu(6); color: mouseArea.pressed ? "#F0F0F0" : "transparent"
                            Label { text: name; font.pixelSize: units.gu(1.6); color: Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -units.dp(8); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                            Label { text: type === "group" ? i18n.tr("Group") : i18n.tr("User"); font.pixelSize: units.gu(1.2); color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: units.dp(10); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider; anchors.bottom: parent.bottom }
                            
                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                onClicked: {
                                    var exists = false;
                                    for (var j=0; j<invitees.length; j++) {
                                        if (invitees[j].id === model.uid && invitees[j].type === model.type) exists = true;
                                    }
                                    if (!exists) {
                                        var arr = invitees.slice();
                                        arr.push({ id: model.uid, name: model.name, type: model.type, role: "view" });
                                        invitees = arr;
                                    }
                                    searchInput.text = "";
                                    searchDropdown.visible = false;
                                    searchInput.focus = false;
                                }
                            }
                        }
                    }
                }
            }

            // Empty state illustration
            Item {
                anchors.fill: parent; anchors.topMargin: units.gu(12); visible: invitees.length === 0
                Icon { name: "stock_people"; width: units.gu(10); height: units.gu(10); color: "#E0E0E0"; anchors.centerIn: parent; anchors.verticalCenterOffset: -units.gu(6) }
                Label { text: i18n.tr("No users added yet"); font.pixelSize: units.gu(1.6); color: Theme.textMuted; anchors.centerIn: parent; anchors.verticalCenterOffset: units.gu(4) }
            }
            
            // List of added invitees
            Flickable {
                width: parent.width; height: parent.height - units.gu(12); y: units.gu(12); visible: invitees.length > 0; contentHeight: inviteeCol.height
                MouseArea { anchors.fill: parent; onClicked: searchDropdown.visible = false } // hide dropdown if tap outside
                Column {
                    id: inviteeCol; width: parent.width; spacing: 0
                    Item { width: parent.width; height: units.gu(4)
                        Label { text: i18n.tr("Invitees"); font.pixelSize: units.gu(1.5); color: Theme.primary; font.weight: Font.DemiBold; anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(0.5); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                    }
                    Repeater {
                        model: invitees
                        Rectangle { width: parent.width; height: units.gu(7); color: "transparent"
                            Rectangle { width: units.gu(4.5); height: units.gu(4.5); radius: units.gu(2.25); color: modelData.type === "group" ? "#4CD964" : "#007AFF"; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2)
                                Label { anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); font.pixelSize: units.gu(2); font.weight: Font.Bold; color: "#fff" }
                            }
                            Column { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(8)
                                Label { text: modelData.name; font.pixelSize: units.gu(1.8); color: Theme.textDark }
                                Label { text: modelData.role === "download" ? i18n.tr("Downloader") : (modelData.role === "provider" ? i18n.tr("Provider") : i18n.tr("Viewer")); font.pixelSize: units.gu(1.4); color: Theme.textMuted }
                            }
                            Icon { name: "go-next"; width: units.gu(2); height: units.gu(2); color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2) }
                            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider; anchors.bottom: parent.bottom }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    searchDropdown.visible = false;
                                    editingInviteeIndex = index;
                                    editingInviteeRole = modelData.role;
                                    permissionPopup.visible = true;
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Permission Popup
        Rectangle {
            id: permissionPopup; anchors.fill: parent; color: "transparent"; visible: false; z: 10
            Rectangle { anchors.fill: parent; color: "#000"; opacity: 0.5; MouseArea { anchors.fill: parent; onClicked: permissionPopup.visible = false } }
            Rectangle { width: parent.width; height: units.gu(28); anchors.bottom: parent.bottom; color: Theme.background; radius: units.gu(2)
                Column { width: parent.width; anchors.bottom: parent.bottom
                    Item { width: parent.width; height: units.gu(4)
                        Label { text: i18n.tr("Access Permissions"); font.pixelSize: units.gu(1.5); color: Theme.primary; font.weight: Font.DemiBold; anchors.bottom: parent.bottom; anchors.bottomMargin: units.gu(0.5); anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                    }
                    Repeater {
                        model: [
                            { role: "view", title: i18n.tr("Viewer") },
                            { role: "download", title: i18n.tr("Downloader") },
                            { role: "provider", title: i18n.tr("Provider") },
                            { role: "remove", title: i18n.tr("Remove Access"), color: "#FF3B30" }
                        ]
                        Rectangle { width: parent.width; height: units.gu(6); color: "transparent"
                            Label { text: modelData.title; font.pixelSize: units.gu(1.8); color: modelData.color || Theme.textDark; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: units.gu(2) }
                            Icon { name: "ok"; width: units.gu(2); height: units.gu(2); color: Theme.primary; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: units.gu(2); visible: editingInviteeRole === modelData.role }
                            Rectangle { width: parent.width; height: units.dp(1); color: Theme.divider; anchors.bottom: parent.bottom }
                            MouseArea { anchors.fill: parent; onClicked: {
                                if (modelData.role === "remove") {
                                    var arr2 = invitees.slice();
                                    arr2.splice(editingInviteeIndex, 1);
                                    invitees = arr2;
                                } else {
                                    var arr = invitees.slice();
                                    arr[editingInviteeIndex].role = modelData.role;
                                    invitees = arr;
                                }
                                permissionPopup.visible = false;
                            } }
                        }
                    }
                }
            }
        }
    }
}
