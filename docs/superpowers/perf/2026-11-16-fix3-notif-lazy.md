# Iterasi #3 — isi kartu notifikasi yang tersembunyi dibuat lazy

## Akar masalah (hasil bisect)

Halaman `phone` memuat daftar notifikasi dari HP yang terhubung (saat ini **110
notifikasi aktif**, 23 grup aplikasi). Setiap kartu — termasuk yang tidak
pernah dibuka — membangun **seluruh isi "expanded"**: body rich-text, chip
aksi, field reply, tombol-tombol ripple. Isi itu tidak pernah tampil selama
kartu collapsed, tapi tetap diinstansiasi.

Bisect (RSS setelah sidebar dibuka, satu sesi):

| Probe | Tambahan RSS |
|---|---|
| halaman `phone` dimatikan (`phone.enable=false`) | +35 MB |
| isi `Phone.qml` diganti `Item` kosong | +37 MB |
| `ColumnLayout` kosong | +39 MB |
| header + roster + actions saja | +45 MB |
| navCards saja | +40 MB |
| navCards + notificationList | +287…355 MB |
| notificationList tanpa `NotificationListView` | +53 MB |
| list dengan model kosong | +54 MB |
| delegate diganti kotak polos | +49…76 MB |
| **isi "expanded content" dibuang** | **+170 MB** |

Jadi biayanya ada di isi kartu, bukan di cache notifikasi: mengosongkan cache
(`cachedNotificationsJson`) tidak menolong karena HP langsung mengirim ulang
110 notifikasi yang sama.

## Perubahan

`modules/common/widgets/NotificationItem.qml` — blok "expanded content"
dipindah ke `Loader { active: root.expanded || root.replying }`. Kartu collapsed
tidak lagi membangun body rich-text, chip aksi, maupun field reply. Tidak ada
perubahan yang terlihat: isi itu memang hanya tampil saat kartu dibuka.

## Angka (A/B/A, satu sesi, `measure.sh`)

| Kondisi | idle | dibuka | selisih buka | ditutup | retensi |
|---|---|---|---|---|---|
| fix ON (A) | 1067 MB | 1227 MB | **+159 MB** | 1173 MB | +105 MB |
| fix OFF (B) | 1064 MB | 1372 MB | **+308 MB** | 1334 MB | +270 MB |
| fix ON (A2) | 1067 MB | 1254 MB | **+187 MB** | 1205 MB | +137 MB |

Median selisih buka: **+173 MB vs +308 MB** (turun ~44 %); memori yang
bertahan setelah panel ditutup: **+121 MB vs +270 MB**.

Catatan: angka "full" sebelumnya (+300 MB) dan "expanded dibuang" (+170 MB)
diukur dengan file yang sama sebelum perubahan, jadi arah dan besarnya konsisten.

## Gate

1. **Sintaks**: `/usr/lib/qt6/bin/qmllint modules/common/widgets/NotificationItem.qml` — tanpa error.
2. **Boot**: `qs log` tidak memuat error/warning baru. Yang tersisa dan
   **sudah ada sebelumnya**: `Error decoding: file:///tmp/kdeconnect_syoxide/…
   Unsupported image format` — file ikon 0 byte dari KDE Connect (kandidat fix
   berikutnya, belum disentuh).
3. **Visual**: `shot.sh --sane` S1 stddev 0.262, S3 0.128 — PASS. Halaman phone
   collapsed diambil langsung (`shots/S3-phone-collapsed.png`) dan kartu
   notifikasi tampil normal.
4. **Gerbang expand** (yang berisiko): `NotificationGroup.expanded` dipaksa
   `true` sementara untuk memuat semua Loader — **26 Loader termuat, tanpa error
   QML**, dan screenshot menunjukkan body, tombol X/copy, serta chip aksi
   tergambar. Sesudah itu default dikembalikan ke `false`.
5. **Manual (user)**: klik kanan satu notifikasi di halaman phone untuk
   memastikan expand/collapse dan tombol aksinya bekerja.

## Yang tidak diubah

- `phonePrewarm` masih menyalakan halaman phone di latar (opsi A/B pada
  `2026-11-16-fix2-phone-ram.md` tidak diambil).
- Cache notifikasi tidak dibatasi.
- File ikon 0 byte masih memicu percobaan decode yang gagal.
