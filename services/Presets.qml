pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property alias folderModel: presetsFolderModel
    property alias onlineFolderModel: onlinePresetsFolderModel
    property alias importedFolderModel: importedPresetsFolderModel

    signal renamed(string oldName, string newName)

    FolderListModel {
        id: presetsFolderModel
        folder: Qt.resolvedUrl(Directories.userPresetsPath)
        showDirs: false
        nameFilters: ["*.json"]
    }

    FolderListModel {
        id: onlinePresetsFolderModel
        folder: Qt.resolvedUrl(`${Quickshell.env("HOME")}/.cache/quickshell/presets`)
        showDirs: false
        nameFilters: ["*.json"]
    }

    FolderListModel {
        id: importedPresetsFolderModel
        folder: Qt.resolvedUrl(`${Quickshell.env("HOME")}/.cache/quickshell/presets_imported`)
        showDirs: false
        nameFilters: ["*.json"]
    }

    function previewImage(data) {
        const background = data?.background
        const raw = background?.wallpaperPath ?? ""
        if (/\.(mp4|webm|mkv|avi|mov)$/i.test(raw)) return background?.thumbnailPath ?? ""
        if (background?.collage?.enable) {
            try {
                let node = JSON.parse(background.collage.tree)
                while (node.t !== "leaf") node = node.a
                if (node.img) return node.img
            } catch (e) {}
        }
        return raw
    }

    function refresh() {
        const current = presetsFolderModel.folder
        presetsFolderModel.folder = ""
        presetsFolderModel.folder = current
    }

    function refreshOnline() {
        const current = onlinePresetsFolderModel.folder
        onlinePresetsFolderModel.folder = ""
        onlinePresetsFolderModel.folder = current
    }

    function refreshImported() {
        const current = importedPresetsFolderModel.folder
        importedPresetsFolderModel.folder = ""
        importedPresetsFolderModel.folder = current
    }

    Process {
        id: saveProc
        onExited: root.refresh()
    }

    Process {
        id: deleteProc
        onExited: root.refresh()
    }

    Process {
        id: renameProc
        property string oldName: ""
        stdout: StdioCollector { id: renameOut }
        onExited: code => {
            root.refresh()
            root.renamed(renameProc.oldName, code === 0 ? renameOut.text.trim() : "")
        }
    }

    Process {
        id: deleteOnlineProc
        onExited: root.refreshOnline()
    }

    Process {
        id: deleteImportedProc
        onExited: root.refreshImported()
    }

    Process {
        id: overwriteProc
        onExited: root.refresh()
    }

    Process {
        id: exportZipProc
    }

    Process {
        id: installProc
        stdout: StdioCollector { id: installOut }
        onExited: code => {
            root.refresh()
            if (code !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Presets", Translation.tr("Install failed"), Translation.tr("Could not copy the preset files")])
                return
            }
            const lines = installOut.text.trim().split("\n")
            const saved = lines[0].split("/").pop().replace(".json", "")
            const missingLine = lines.find(l => l.startsWith("missing: "))
            if (missingLine) {
                const files = missingLine.slice(9)
                Quickshell.execDetached(["notify-send", "-a", "Presets", Translation.tr("Preset installed with missing images"), Translation.tr("Saved as \"%1\", but these files were not found: %2").arg(saved).arg(files)])
                return
            }
            Quickshell.execDetached(["notify-send", "-a", "Presets", Translation.tr("Preset installed"), Translation.tr("Saved as \"%1\" in My presets. Wallpapers are in Pictures/Wallpapers.").arg(saved)])
        }
    }

    Process {
        id: publishPickProc
        property string presetName: ""
        stdout: StdioCollector { id: publishPickOut }
        onExited: code => {
            const picked = publishPickOut.text.trim()
            if (code !== 0 || picked === "") return
            publishPrepProc.presetName = publishPickProc.presetName
            publishPrepProc.command = ["bash", Directories.presetsScriptPath, "--export-zip", publishPickProc.presetName, "--folder", "--preview", picked]
            publishPrepProc.running = true
        }
    }

    Process {
        id: publishPrepProc
        property string presetName: ""
        onExited: code => {
            if (code === 3) {
                Quickshell.execDetached(["notify-send", "-a", "Presets", Translation.tr("Can't upload this preset"), Translation.tr("It was installed from the gallery and belongs to its author")])
                return
            }
            if (code !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Presets", Translation.tr("Upload failed"), Translation.tr("Could not prepare the preset folder")])
                return
            }
            const folder = `${Quickshell.env("HOME")}/.cache/quickshell/presets_share/${publishPrepProc.presetName}`
            const repo = PresetsOnline.sources[0].repo
            Quickshell.execDetached(["notify-send", "-a", "Presets", Translation.tr("Upload your preset"), Translation.tr("Drag the \"%1\" folder into the GitHub page and press Propose changes").arg(publishPrepProc.presetName)])
            Quickshell.execDetached(["xdg-open", folder])
            Quickshell.execDetached(["xdg-open", `https://github.com/${repo}/upload/main/presets`])
        }
    }

    Process {
        id: importZipProc
        onExited: root.refreshImported()
    }

    function save(rawInput) {
        const raw = rawInput.trim()
        if (raw.length === 0) return

        const commaIndex = raw.indexOf(",")
        let name = raw
        let description = ""

        if (commaIndex !== -1) {
            name = raw.substring(0, commaIndex).trim()
            description = raw.substring(commaIndex + 1).trim()
        }

        name = name.replace(/\s/g, "_")
        if (name.length === 0) return

        saveProc.command = ["bash", Directories.presetsScriptPath, "--save", name, description]
        saveProc.running = true
    }

    function apply(name) {
        GlobalStates.settingsOpen = false
        Collage.armEntrance()
        Wallpapers.confirmedPath = ""
        Wallpapers.previewPath = ""
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name])
    }

    function applyOnline(name) {
        GlobalStates.settingsOpen = false
        Collage.armEntrance()
        Wallpapers.confirmedPath = ""
        Wallpapers.previewPath = ""
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name, "--online"])
    }

    function remove(name) {
        deleteProc.command = ["bash", Directories.presetsScriptPath, "--remove", name]
        deleteProc.running = true
    }

    function rename(name, newName) {
        renameProc.oldName = name
        renameProc.command = ["bash", Directories.presetsScriptPath, "--rename", name, newName.trim()]
        renameProc.running = true
    }

    function removeOnline(name) {
        deleteOnlineProc.command = ["bash", Directories.presetsScriptPath, "--remove", name, "--online"]
        deleteOnlineProc.running = true
    }

    function removeImported(name) {
        deleteImportedProc.command = ["bash", Directories.presetsScriptPath, "--remove", name, "--imported"]
        deleteImportedProc.running = true
    }

    function applyImported(name) {
        GlobalStates.settingsOpen = false
        Collage.armEntrance()
        Wallpapers.confirmedPath = ""
        Wallpapers.previewPath = ""
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name, "--imported"])
    }

    function overwrite(name) {
        // Overwrite with same name (presets.sh --save filters General+Services)
        overwriteProc.command = ["bash", Directories.presetsScriptPath, "--save", name]
        overwriteProc.running = true
    }

    function exportZip(name) {
        exportZipProc.command = ["bash", Directories.presetsScriptPath, "--export-zip", name]
        exportZipProc.running = true
    }

    function install(name, source) {
        const cmd = ["bash", Directories.presetsScriptPath, "--install", name, source === "imported" ? "--imported" : "--online"]
        if (source !== "imported") cmd.push("--origin", PresetsOnline.originOf(name), "--as", PresetsOnline.displayName(name))
        installProc.command = cmd
        installProc.running = true
    }

    function publish(name) {
        const title = Translation.tr("Choose the preview image (a screenshot of your desktop)")
        const start = `${Quickshell.env("HOME")}/Pictures`
        publishPickProc.presetName = name
        publishPickProc.command = ["bash", "-c",
            'if command -v kdialog >/dev/null 2>&1; then kdialog --title "$1" --getopenfilename "$2" "Images (*.png *.jpg *.jpeg *.webp)"; else zenity --file-selection --title="$1" --filename="$2/" --file-filter="Images | *.png *.jpg *.jpeg *.webp"; fi',
            "pick", title, start]
        publishPickProc.running = true
    }

    function importZip(path) {
        const clean = String(path).replace(/^file:\/\//, "")
        importZipProc.command = ["bash", Directories.presetsScriptPath, "--import-zip", clean]
        importZipProc.running = true
    }
}
