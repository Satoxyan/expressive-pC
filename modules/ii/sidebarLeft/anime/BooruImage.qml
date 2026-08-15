import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.common.widgets
import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Button {
    id: root
    property var imageData
    property var rowHeight
    property bool manualDownload: false
    property string previewDownloadPath
    property string downloadPath
    property string nsfwPath
    property string refererUrl: ""
    property string defaultUserAgent: Config.options?.networking?.userAgent
        ?? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property string fileName: decodeURIComponent((imageData.file_url).substring((imageData.file_url).lastIndexOf('/') + 1))
    property string filePath: `${root.previewDownloadPath}/${root.fileName}`
    property int maxTagStringLineLength: 50
    property real imageRadius: Appearance.rounding.small

    property bool showActions: false
    property bool sampleDownloaded: false
    property bool playOverlayVisible: false
    property bool checkingForPlay: false
    readonly property var imageExtensions: ["jpg", "jpeg", "png", "webp", "bmp", "tiff", "tif", "svg", "avif"]
    readonly property bool isAnimated: (root.imageData.tags || "").split(" ").includes("animated")

    onImageDataChanged: {
        root.sampleDownloaded = false
        root.playOverlayVisible = false
        animatedDownloader.running = false
        if (root.isAnimated) {
            cacheChecker.running = true
        }
    }

    onClicked: {
        if (root.sampleDownloaded) {
            root.checkingForPlay = true
            cacheChecker.running = true
        } else if (root.isAnimated && !animatedDownloader.running) {
            animatedDownloader.running = true
        } else {
            var src = String(imageObject.source)
            if (src.startsWith("/"))
                src = "file://" + src
            if (src.length > 0)
                Qt.openUrlExternally(src)
        }
    }

    // Standard downloader — used for all providers WITHOUT hotlink protection
    ImageDownloaderProcess {
        id: imageDownloader
        running: root.refererUrl === ""
        filePath: root.isAnimated ? root.filePath + ".preview" : root.filePath
        sourceUrl: root.isAnimated ? root.imageData.preview_url : (root.imageData.sample_url || root.imageData.preview_url || root.imageData.file_url)
        onDone: (path, width, height) => {
            if (root.isAnimated) {
                imageObject.source = path
            } else if (root.imageExtensions.includes(root.imageData.file_ext)) {
                imageObject.source = path
            } else {
                root.sampleDownloaded = true
                root.playOverlayVisible = true
            }
            if (!modelData.width || !modelData.height) {
                modelData.width = width
                modelData.height = height
                modelData.aspect_ratio = width / height
            }
        }
    }

    // Referer-aware downloader via curl — used for providers with hotlink protection (e.g. Gelbooru)
    // Stage 1: download preview_url fast for immediate display
    Process {
        id: refererPreviewDownloader
        running: root.refererUrl !== ""
        command: ["bash", "-c",
            `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.previewDownloadPath)}' && ` +
            `[ -f '${StringUtils.shellSingleQuoteEscape(root.filePath)}.preview' ] && echo DONE || ` +
            `(curl -s -L --max-time 120 --retry 2 ` +
            `-H 'Referer: ${root.refererUrl}' ` +
            `-H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(root.defaultUserAgent)}' ` +
            `'${StringUtils.shellSingleQuoteEscape(root.imageData.preview_url)}' ` +
            `-o '${StringUtils.shellSingleQuoteEscape(root.filePath)}.preview' && ` +
            `file -b --mime-type '${StringUtils.shellSingleQuoteEscape(root.filePath)}.preview' | grep -q '^image/' && ` +
            `echo DONE)`
        ]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim() === "DONE") {
                    imageObject.source = root.filePath + ".preview"
                    if (!root.isAnimated) {
                        refererSampleUpgrader.running = true
                    }
                }
            }
        }
    }
    // Stage 2: upgrade to sample_url quality in background (only if different from file_url)
    Process {
        id: refererSampleUpgrader
        running: false
        command: ["bash", "-c",
            `[ -f '${StringUtils.shellSingleQuoteEscape(root.filePath)}' ] && echo DONE || ` +
            `(curl -s -L --max-time 120 --retry 2 ` +
            `-H 'Referer: ${root.refererUrl}' ` +
            `-H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(root.defaultUserAgent)}' ` +
            `'${StringUtils.shellSingleQuoteEscape(root.imageData.sample_url)}' ` +
            `-o '${StringUtils.shellSingleQuoteEscape(root.filePath)}.tmp' && ` +
            `file -b --mime-type '${StringUtils.shellSingleQuoteEscape(root.filePath)}.tmp' | grep -qE '^(image|video)/' && ` +
            `mv '${StringUtils.shellSingleQuoteEscape(root.filePath)}.tmp' ` +
            `'${StringUtils.shellSingleQuoteEscape(root.filePath)}' && echo DONE)`
        ]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim() === "DONE") {
                    if (root.imageExtensions.includes(root.imageData.file_ext)) {
                        imageObject.source = root.filePath
                    } else {
                        root.sampleDownloaded = true
                        root.playOverlayVisible = true
                    }
                }
            }
        }
    }

    // On-demand downloader for animated content (GIF/MP4) — triggered by user click
    Process {
        id: animatedDownloader
        running: false
        command: ["bash", "-c",
            `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.previewDownloadPath)}' && ` +
            `[ -f '${StringUtils.shellSingleQuoteEscape(root.filePath)}' ] && echo DONE || ` +
            `(curl -s -L -C - --retry 2 ` +
            `${root.refererUrl ? `-H 'Referer: ${root.refererUrl}' ` : ``}` +
            `-H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(root.defaultUserAgent)}' ` +
            `'${StringUtils.shellSingleQuoteEscape(root.imageData.file_url || root.imageData.sample_url)}' ` +
            `-o '${StringUtils.shellSingleQuoteEscape(root.filePath)}.tmp' && ` +
            `file -b --mime-type '${StringUtils.shellSingleQuoteEscape(root.filePath)}.tmp' | grep -qE '^(image|video)/' && ` +
            `mv '${StringUtils.shellSingleQuoteEscape(root.filePath)}.tmp' ` +
            `'${StringUtils.shellSingleQuoteEscape(root.filePath)}' && echo DONE)`
        ]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim() === "DONE") {
                    root.sampleDownloaded = true
                    root.playOverlayVisible = true
                }
            }
        }
    }

    Process {
        id: cacheChecker
        running: false
        command: ["bash", "-c",
            `[ -f '${StringUtils.shellSingleQuoteEscape(root.filePath)}' ] && echo CACHED || echo MISSING`
        ]
        stdout: SplitParser {
            onRead: (line) => {
                var trimmed = line.trim()
                if (trimmed === "CACHED") {
                    if (root.checkingForPlay) {
                        root.checkingForPlay = false
                        Qt.openUrlExternally("file://" + root.filePath)
                    } else {
                        root.sampleDownloaded = true
                        root.playOverlayVisible = true
                    }
                } else if (trimmed === "MISSING" && root.checkingForPlay) {
                    root.checkingForPlay = false
                    root.sampleDownloaded = false
                    root.playOverlayVisible = false
                    animatedDownloader.running = true
                }
            }
        }
    }

    StyledToolTip {
        text: `${StringUtils.wordWrap(root.imageData.tags, root.maxTagStringLineLength)}`
    }

    padding: 0
    implicitWidth: root.rowHeight * modelData.aspect_ratio
    implicitHeight: root.rowHeight

    background: Rectangle {
        implicitWidth: root.rowHeight * modelData.aspect_ratio
        implicitHeight: root.rowHeight
        radius: imageRadius
        color: Appearance.colors.colLayer2
    }

    contentItem: Item {
        anchors.fill: parent

        StyledImage {
            id: imageObject
            anchors.fill: parent
            width: root.rowHeight * modelData.aspect_ratio
            height: root.rowHeight
            fillMode: Image.PreserveAspectFit
            source: modelData.preview_url || modelData.sample_url || modelData.file_url

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: root.rowHeight * modelData.aspect_ratio
                    height: root.rowHeight
                    radius: imageRadius
                }
            }
        }

        RippleButton {
            id: menuButton
            anchors.top: parent.top
            anchors.right: parent.right
            property real buttonSize: 30
            anchors.margins: Math.max(root.imageRadius - buttonSize / 2, 8)
            implicitHeight: buttonSize
            implicitWidth: buttonSize

            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
            colBackgroundHover: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.8), 0.2)
            colRipple: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.6), 0.1)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3onSurface
                text: "more_vert"
            }

            onClicked: {
                root.showActions = !root.showActions
            }
        }

        Rectangle {
            id: animatedPill
            visible: root.isAnimated
            anchors.top: menuButton.bottom
            anchors.horizontalCenter: menuButton.horizontalCenter
            anchors.topMargin: 4
            width: menuButton.buttonSize
            height: menuButton.buttonSize
            radius: Appearance.rounding.full
            color: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.m3colors.m3onSurface
                text: "slow_motion_video"
            }
        }

        Rectangle {
            visible: animatedDownloader.running
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: width / 2
            color: ColorUtils.transparentize("#000000", 0.4)

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 24
                color: "#ffffff"
                text: "sync"
            }

            NumberAnimation on rotation {
                running: animatedDownloader.running
                from: 360
                to: 0
                duration: 1000
                loops: Animation.Infinite
            }
        }

        Rectangle {
            visible: root.playOverlayVisible && root.isAnimated
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: width / 2
            color: ColorUtils.transparentize("#000000", 0.4)

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 24
                color: "#ffffff"
                text: "play_arrow"
            }
        }

        Loader {
            id: contextMenuLoader
            active: root.showActions
            anchors.top: menuButton.bottom
            anchors.right: parent.right
            anchors.margins: 8

            sourceComponent: Item {
                width: contextMenu.width
                height: contextMenu.height

                StyledRectangularShadow {
                    target: contextMenu
                }
                Rectangle {
                    id: contextMenu
                    anchors.centerIn: parent
                    opacity: root.showActions ? 1 : 0
                    visible: opacity > 0
                    radius: Appearance.rounding.small
                    color: Appearance.m3colors.m3surfaceContainer
                    implicitHeight: contextMenuColumnLayout.implicitHeight + radius * 2
                    implicitWidth: contextMenuColumnLayout.implicitWidth

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    ColumnLayout {
                        id: contextMenuColumnLayout
                        anchors.centerIn: parent
                        spacing: 0

                        MenuButton {
                            id: openFileLinkButton
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Open file link")
                            onClicked: {
                                root.showActions = false
                                Hyprland.dispatch("hl.config({cursor = {no_warps = true}})")
                                Qt.openUrlExternally(root.imageData.file_url)
                                Hyprland.dispatch("hl.config({cursor = {no_warps = false}})")
                            }
                        }
                        MenuButton {
                            id: sourceButton
                            visible: root.imageData.source && root.imageData.source.length > 0
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Go to source (%1)").arg(StringUtils.getDomain(root.imageData.source))
                            enabled: root.imageData.source && root.imageData.source.length > 0
                            onClicked: {
                                root.showActions = false
                                Hyprland.dispatch("hl.config({cursor = {no_warps = true}})")
                                Qt.openUrlExternally(root.imageData.source)
                                Hyprland.dispatch("hl.config({cursor = {no_warps = false}})")
                            }
                        }
                        MenuButton {
                            id: downloadButton
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Download")
                            onClicked: {
                                root.showActions = false;
                                const targetPath = root.imageData.is_nsfw ? root.nsfwPath : root.downloadPath;
                                const userAgent = Config.options?.networking?.userAgent ?? ""
                                const userAgentHeader = userAgent ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(userAgent)}'` : ""
                                const refererHeader = root.refererUrl ? ` -H 'Referer: ${root.refererUrl}'` : ""
                                Quickshell.execDetached(["bash", "-c", 
                                    `mkdir -p '${targetPath}' && curl '${StringUtils.shellSingleQuoteEscape(root.imageData.file_url)}'${userAgentHeader}${refererHeader} -o '${targetPath}/${root.fileName}' && notify-send '${Translation.tr("Download complete")}' '${root.downloadPath}/${root.fileName}' -a 'Shell'`
                                ])
                            }
                        }
                    }
                }
            }
        }
    }
}
