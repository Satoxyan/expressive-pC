import qs.modules.common
import QtQuick;

/**
 * A booru response.
 */
QtObject {
    property string provider
    property var tags
    property var page
    // Halaman terakhir pencarian ini; -1 berarti endpoint tidak memberitahu totalnya
    // dan halaman terakhir belum terlewati.
    property int totalPages: -1
    property var images
    property string message
}
