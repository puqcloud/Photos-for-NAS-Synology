import QtQuick 2.9
import Ubuntu.Components 1.3
import Ubuntu.Components.Popups 1.3
import "../js/Theme.js" as Theme

Item {
    id: inputDialogRoot
    anchors.fill: parent
    visible: false
    z: 1000

    property string titleText: ""
    property string placeholderText: ""
    property string okText: ""
    property string cancelText: ""
    property var okCallback: null

    function show(title, placeholder, ok, cancel, onOk) {
        titleText = title;
        placeholderText = placeholder;
        okText = ok || i18n.tr("OK");
        cancelText = cancel || i18n.tr("CANCEL");
        okCallback = onOk;
        inputField.text = "";
        visible = true;
    }

    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        MouseArea { anchors.fill: parent } // Block background clicks
    }

    Rectangle {
        width: units.gu(35)
        height: contentCol.height + units.gu(4)
        anchors.centerIn: parent
        radius: units.gu(2)
        color: Theme.background

        Column {
            id: contentCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: units.gu(2)
            spacing: units.gu(2)

            Label {
                text: titleText
                font.pixelSize: units.gu(2)
                font.weight: Font.DemiBold
                color: Theme.textDark
            }

            TextField {
                id: inputField
                width: parent.width
                placeholderText: inputDialogRoot.placeholderText
                font.pixelSize: units.gu(1.6)
            }

            Row {
                anchors.right: parent.right
                spacing: units.gu(2)

                Button {
                    text: cancelText
                    color: "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: parent.text
                        color: "#E57373"
                        font.weight: Font.DemiBold
                    }
                    onClicked: {
                        inputDialogRoot.visible = false;
                    }
                }

                Button {
                    text: okText
                    color: "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: parent.text
                        color: "#E57373"
                        font.weight: Font.DemiBold
                    }
                    onClicked: {
                        inputDialogRoot.visible = false;
                        if (okCallback) {
                            okCallback(inputField.text);
                        }
                    }
                }
            }
        }
    }
}
