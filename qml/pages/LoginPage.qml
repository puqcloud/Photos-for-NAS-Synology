import QtQuick 2.9
import Ubuntu.Components 1.3
import "../components"
import "../js/Theme.js" as Theme
import "../js/SynologyApi.js" as SynoApi
import "../js/Storage.js" as Storage

Item {
    id: loginPage
    anchors.fill: parent

    property bool showPassword: false
    property bool otpRequired: false
    property bool isFormValid: serverInput.text.trim().length > 0 && userInput.text.trim().length > 0 && passInput.text.length > 0

    // Full screen coral background
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.primary
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, contentCol.height + units.gu(16))
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: contentCol
            width: Math.min(loginPage.width - units.gu(6), units.gu(46))
            anchors.horizontalCenter: parent.horizontalCenter
            y: units.gu(8)
            spacing: units.gu(3)

            // App Logo
            Item {
                width: units.gu(9)
                height: units.gu(9)
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    id: appLogo
                    source: "../../photos-for-nas-synology.png"
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            // Brand Title
            Label {
                text: "Photos for NAS Synology"
                font.pixelSize: units.gu(3.2)
                font.weight: Font.Bold
                color: "#ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

            // Input Fields Card
            Rectangle {
                width: parent.width
                height: formColumn.height
                color: "#ffffff"
                radius: units.gu(1.2)
                clip: true

                Column {
                    id: formColumn
                    width: parent.width

                    // 1. Address / QuickConnect ID
                    Item {
                        width: parent.width
                        height: units.gu(6.5)

                        TextInput {
                            id: serverInput
                            anchors {
                                left: parent.left
                                right: serverDropdownBtn.visible ? serverDropdownBtn.left : parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: units.gu(2.5)
                                rightMargin: units.gu(1)
                            }
                            font.pixelSize: units.gu(1.9)
                            color: Theme.textDark
                            clip: true
                            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                text: i18n.tr("Server Address (IP or Domain)")
                                color: "#9E9E9E"
                                font.pixelSize: units.gu(1.9)
                                verticalAlignment: Text.AlignVCenter
                                visible: !serverInput.text && !serverInput.inputMethodComposing
                            }
                        }

                        // Optional Server history dropdown button
                        Item {
                            id: serverDropdownBtn
                            width: units.gu(5)
                            height: parent.height
                            anchors.right: parent.right
                            visible: false

                            Icon {
                                anchors.centerIn: parent
                                name: "down"
                                width: units.gu(2)
                                height: units.gu(2)
                                color: "#9E9E9E"
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: units.gu(2)
                            anchors.rightMargin: units.gu(2)
                            height: units.dp(1)
                            color: "#EEEEEE"
                        }
                    }

                    // 2. Account
                    Item {
                        width: parent.width
                        height: units.gu(6.5)

                        TextInput {
                            id: userInput
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: units.gu(2.5)
                                rightMargin: units.gu(2)
                            }
                            font.pixelSize: units.gu(1.9)
                            color: Theme.textDark
                            clip: true
                            inputMethodHints: Qt.ImhNoAutoUppercase
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                text: i18n.tr("Account")
                                color: "#9E9E9E"
                                font.pixelSize: units.gu(1.9)
                                verticalAlignment: Text.AlignVCenter
                                visible: !userInput.text && !userInput.inputMethodComposing
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: units.gu(2)
                            anchors.rightMargin: units.gu(2)
                            height: units.dp(1)
                            color: "#EEEEEE"
                        }
                    }

                    // 3. Password
                    Item {
                        width: parent.width
                        height: units.gu(6.5)

                        TextInput {
                            id: passInput
                            anchors {
                                left: parent.left
                                right: toggleEyeBtn.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: units.gu(2.5)
                                rightMargin: units.gu(1)
                            }
                            font.pixelSize: units.gu(1.9)
                            color: Theme.textDark
                            clip: true
                            echoMode: loginPage.showPassword ? TextInput.Normal : TextInput.Password
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                text: i18n.tr("Password")
                                color: "#9E9E9E"
                                font.pixelSize: units.gu(1.9)
                                verticalAlignment: Text.AlignVCenter
                                visible: !passInput.text && !passInput.inputMethodComposing
                            }
                        }

                        // Eye toggle button for password
                        Item {
                            id: toggleEyeBtn
                            width: units.gu(5.5)
                            height: parent.height
                            anchors.right: parent.right

                            Canvas {
                                id: eyeCanvas
                                anchors.centerIn: parent
                                width: units.gu(2.6)
                                height: units.gu(2.6)

                                Connections {
                                    target: loginPage
                                    onShowPasswordChanged: eyeCanvas.requestPaint()
                                }
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.strokeStyle = loginPage.showPassword ? Theme.primary : (passInput.text.length > 0 ? "#757575" : "#BDBDBD");
                                    ctx.lineWidth = 1.8;
                                    
                                    // Eye outline
                                    ctx.beginPath();
                                    ctx.moveTo(units.dp(2), height / 2);
                                    ctx.quadraticCurveTo(width / 2, units.dp(3), width - units.dp(2), height / 2);
                                    ctx.quadraticCurveTo(width / 2, height - units.dp(3), units.dp(2), height / 2);
                                    ctx.stroke();

                                    // Pupil
                                    ctx.beginPath();
                                    ctx.arc(width / 2, height / 2, units.dp(3), 0, 2 * Math.PI);
                                    ctx.fillStyle = ctx.strokeStyle;
                                    ctx.fill();

                                    // Slash if hidden
                                    if (!loginPage.showPassword) {
                                        ctx.beginPath();
                                        ctx.moveTo(units.dp(4), height - units.dp(4));
                                        ctx.lineTo(width - units.dp(4), units.dp(4));
                                        ctx.stroke();
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    loginPage.showPassword = !loginPage.showPassword;
                                    eyeCanvas.requestPaint();
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: units.gu(2)
                            anchors.rightMargin: units.gu(2)
                            height: units.dp(1)
                            color: "#EEEEEE"
                        }
                    }

                    // 4. HTTPS Row
                    Item {
                        width: parent.width
                        height: units.gu(6.0)

                        Label {
                            text: "HTTPS"
                            anchors.left: parent.left
                            anchors.leftMargin: units.gu(2.5)
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: units.gu(2.0)
                            font.weight: Font.DemiBold
                            color: Theme.textDark
                        }

                        // Custom Styled Switch/Checkmark
                        Rectangle {
                            id: httpsToggle
                            width: units.gu(3)
                            height: units.gu(3)
                            radius: units.gu(0.6)
                            anchors.right: parent.right
                            anchors.rightMargin: units.gu(2.5)
                            anchors.verticalCenter: parent.verticalCenter
                            color: httpsCheckbox.checked ? "#4CD964" : "#E0E0E0"

                            Icon {
                                anchors.centerIn: parent
                                name: "ok"
                                width: units.gu(2)
                                height: units.gu(2)
                                color: "#ffffff"
                                visible: httpsCheckbox.checked
                            }

                            CheckBox {
                                id: httpsCheckbox
                                visible: false
                                checked: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: httpsCheckbox.checked = !httpsCheckbox.checked
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: httpsCheckbox.checked = !httpsCheckbox.checked
                        }
                    }

                    // 5. OTP Section (if 2FA requested)
                    Item {
                        id: otpRow
                        width: parent.width
                        height: loginPage.otpRequired ? units.gu(6.5) : 0
                        visible: loginPage.otpRequired
                        clip: true

                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: units.gu(2)
                            anchors.rightMargin: units.gu(2)
                            height: units.dp(1)
                            color: "#EEEEEE"
                        }

                        TextInput {
                            id: otpInput
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: units.gu(2.5)
                                rightMargin: units.gu(2)
                            }
                            font.pixelSize: units.gu(1.9)
                            color: Theme.textDark
                            clip: true
                            inputMethodHints: Qt.ImhDigitsOnly
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                text: i18n.tr("6-digit 2-step verification code")
                                color: "#9E9E9E"
                                font.pixelSize: units.gu(1.8)
                                verticalAlignment: Text.AlignVCenter
                                visible: !otpInput.text && !otpInput.inputMethodComposing
                            }
                        }
                    }
                }
            }

            // Sign In Button
            Rectangle {
                id: signInBtn
                width: parent.width
                height: units.gu(6.2)
                radius: units.gu(3.1)
                color: isFormValid ? (signInMouse.pressed ? "#D94E3E" : "#FA6353") : "#FF998D"
                border.color: "#ffffff"
                border.width: units.dp(1.5)
                opacity: signInMouse.pressed ? 0.9 : 1.0

                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Sign In")
                    color: "#ffffff"
                    font.pixelSize: units.gu(2.3)
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: signInMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: doLogin()
                }
            }
        }
    }

    // Bottom Left Info Button (About)
    Rectangle {
        id: infoBtnBox
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: units.gu(2.5)
        width: units.gu(5.5)
        height: units.gu(5.5)
        radius: units.gu(2.75)
        color: infoMouse.pressed ? "#33000000" : "transparent"
        z: 50

        Icon {
            anchors.centerIn: parent
            name: "info"
            width: units.gu(3.4)
            height: units.gu(3.4)
            color: "#ffffff"
        }

        MouseArea {
            id: infoMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                pageStack.push(Qt.resolvedUrl("AboutPage.qml"));
            }
        }
    }

    Scrollbar {
        flickableItem: flickable
        align: Qt.AlignTrailing
    }

    Component.onCompleted: {
        var savedUrl = Storage.getSetting("serverUrl", "");
        var savedUser = Storage.getSetting("username", "");
        var savedHttps = Storage.getSetting("https", "true") === "true";

        if (savedUrl) serverInput.text = savedUrl.replace(/^https?:\/\//, "");
        if (savedUser) userInput.text = savedUser;
        httpsCheckbox.checked = savedHttps;
    }

    function doLogin() {
        var rawServer = serverInput.text.trim();
        var user = userInput.text.trim();
        var pass = passInput.text;
        var otp = otpInput.text.trim();
        var isHttps = httpsCheckbox.checked;

        if (!rawServer || !user || !pass) {
            mainView.showErrorDialog(i18n.tr("Sign In"), i18n.tr("Please enter server address, account, and password."));
            return;
        }

        // Format Server URL
        var server = rawServer;
        if (!server.startsWith("http://") && !server.startsWith("https://")) {
            server = (isHttps ? "https://" : "http://") + server;
        }

        mainView.showLoading(i18n.tr("Connecting..."));

        SynoApi.login(server, user, pass, otp, function(err, data) {
            mainView.hideLoading();
            if (err) {
                if (err.code === 403 || err.code === 404 || err.code === 406) {
                    loginPage.otpRequired = true;
                    mainView.showErrorDialog(i18n.tr("2-Step Verification"), err.message);
                } else if (err.code === 400 || err.code === 401) {
                    mainView.showErrorDialog(i18n.tr("Sign In"), i18n.tr("Account or password invalid. Please try again."));
                } else {
                    mainView.showErrorDialog(i18n.tr("Sign In"), err.message || i18n.tr("Connection failed. Please check server address and network."));
                }
                return;
            }

            if (data && data.sid) {
                var sid = data.sid;
                var synotoken = data.synotoken || "";

                // Save to local storage
                Storage.setSetting("serverUrl", server);
                Storage.setSetting("username", user);
                Storage.setSetting("https", isHttps ? "true" : "false");
                Storage.setSetting("sid", sid);
                Storage.setSetting("synotoken", synotoken);

                // Update state
                mainView.serverUrl = server;
                mainView.sid = sid;
                mainView.synotoken = synotoken;
                mainView.username = user;
                mainView.isLoggedIn = true;
                mainView.refreshFavorites();

                pageStack.clear();
                pageStack.push(Qt.resolvedUrl("MainTabsPage.qml"));
            }
        });
    }
}
