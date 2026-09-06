pragma Singleton
pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import Qt.labs.folderlistmodel
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root

    readonly property string userFacePath: FileUtils.trimFileProtocol(Directories.home) + "/.face"
    readonly property string configuredPath: FileUtils.trimFileProtocol(Config.options.profile.avatarPath)
    readonly property string configuredPicture: FileUtils.trimFileProtocol(Config.options.profile.avatarPicture)

    readonly property bool hasConfiguredPath: configuredPath !== ""

    readonly property string folder: hasConfiguredPath ? configuredPath : userFacePath

    FolderListModel {
        id: avatarFolderModel
        folder: "file://" + root.folder
        showDirs: false
        showHidden: true
        nameFilters: ["*.png", "*.svg", "*.jpg", "*.jpeg", "*.webp"]
        onCountChanged: {
            if (count > 0) {
                root.firstImage = FileUtils.trimFileProtocol(avatarFolderModel.get(0, "filePath").toString())
            } else {
                root.firstImage = ""
            }
        }
    }

    property string firstImage: ""

    // Single source of truth for the avatar image to display.
    // Priority: explicitly picked picture -> first image in the folder.
    readonly property string effectiveAvatarSource: {
        if (configuredPicture !== "") return "file://" + configuredPicture
        if (firstImage !== "") return "file://" + firstImage
        return ""
    }
}