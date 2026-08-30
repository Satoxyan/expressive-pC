import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onSourceSizeChanged: {
        if (!root.generateThumbnail) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }
    onThumbnailPathChanged: {
        if (!root.generateThumbnail || !root.thumbnailPath) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }
    onSourcePathChanged: {
        if (!root.generateThumbnail || !root.sourcePath) return;
        Qt.callLater(() => { if (root.thumbnailPath) { thumbnailGeneration.running = false; thumbnailGeneration.running = true } })
    }
    Component.onCompleted: {
        if (root.generateThumbnail && root.thumbnailPath) Qt.callLater(() => thumbnailGeneration.running = true)
    }
    // ponytail: video thumbnail via ffmpeg, image via magick
    readonly property bool isVideo: Images.isValidVideoByName(root.sourcePath)
    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const thumb = FileUtils.trimFileProtocol(root.thumbnailPath);
            const thumbDir = thumb.substring(0, thumb.lastIndexOf("/"));
            if (root.isVideo) {
                return ["bash", "-c",
                    `mkdir -p '${thumbDir}' && [ -f '${thumb}' ] && exit 0; ffmpeg -y -ss 0 -i '${root.sourcePath}' -frames:v 1 -vf scale=${maxSize}:-1 -q:v 2 -update 1 '${thumb}' 2>/dev/null && exit 1 || exit 0`
                ]
            }
            return ["bash", "-c",
                `mkdir -p '${thumbDir}' && [ -f '${thumb}' ] && exit 0 || { magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} '${thumb}' && exit 1; }`
            ]
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.source = "";
                root.source = root.thumbnailPath; // Force reload
            }
        }
    }
}
