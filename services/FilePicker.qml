import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Opens a system file picker (kdialog) and returns the selected path via callback.
 */
Singleton {
    id: root

    function pickImage(callback: var) {
        picker.onFileSelected = callback;
        picker.exec([
            "kdialog", "--getopenfilename",
            Quickshell.env("HOME") + "/Pictures",
            "image/png image/jpeg image/jpg image/webp image/avif image/bmp image/gif image/tiff"
        ])
    }

    Process {
        id: picker
        property var onFileSelected: null

        stdout: StdioCollector {
            id: collector
        }

        onExited: (code) => {
            if (code !== 0 || !picker.onFileSelected) return;
            const path = collector.text.trim();
            if (path !== "") picker.onFileSelected(path);
            picker.onFileSelected = null;
        }
    }
}
