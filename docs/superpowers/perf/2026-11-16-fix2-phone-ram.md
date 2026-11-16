# Iterasi #2 — halaman `phone` di sidebar: 300 MB, terukur

## Pengukuran (A/B bergantian, satu sesi, musik Playing)

| Kondisi | idle | sidebar dibuka | setelah ditutup |
|---|---|---|---|
| `sidebar.phone.enable = true` (default) | 1037 MB | 1388 MB (**+351**) | 1344 MB (**+307 bertahan**) |
| `sidebar.phone.enable = false` | 1034 MB | 1069 MB (+35) | 1035 MB (**+1**) |

Selisihnya atribusi bersih: **~300 MB dari halaman `phone` saja**, dan tidak
dilepas setelah sidebar ditutup. Sisi lain (home, header, panel lain) hanya
+35 MB dan kembali penuh setelah ditutup.

Config live sempat diubah (`phone.enable=false`) untuk eksperimen ini dan
**sudah dikembalikan**; `phone.enable = true` terverifikasi sesudah restore,
dan angka kontrol mereproduksi hasil awal (1388 / 1344 MB).

## Kenapa ini terjadi

- `SidebarLeftContent.qml:103` — timer `phonePrewarm` (1,2 s) menyetel
  `phoneSlot.prewarm = true` secara otomatis begitu konten sidebar pertama kali
  dibuat, jadi halaman `phone` dibangun **tanpa pernah diminta**.
- `SidebarLeftContent.qml:286` — Loader aktif selama `slot.visited ||
  slot.prewarm`, dan `visited` tidak pernah direset. Sekali tersentuh, halaman
  tinggal di memori sampai qs mati.
- `Config.options.sidebar.keepRightSidebarLoaded` default `true` menambah pola
  yang sama di sisi kanan.

## Tiga jalan keluar, semuanya mengubah perilaku

| Opsi | Hemat | Efek samping |
|---|---|---|
| A. Buang `phonePrewarm` | 300 MB untuk yang tidak pernah membuka halaman phone | Buka pertama halaman phone kembali "menetes" (kartu muncul satu-satu) — persis yang diperbaiki oleh komentar di kode |
| B. Lepas halaman `visited` saat sidebar ditutup | 300 MB untuk semua orang | Buka ulang halaman butuh load async lagi (~1,2 s) dan state sub-halaman hilang |
| C. Cari alokasi di dalam halaman phone | 300 MB tanpa mengubah UX kalau sumbernya bisa dikecilkan | Belum diketahui; butuh bisect di 5.583 baris `sidebarLeft/phone/` |

Aku belum menerapkan apa pun: ketiganya mengubah pengalaman yang user lihat,
jadi keputusannya milikmu — bukan keputusan yang pantas kuambil diam-diam.

## Catatan

`perf record` masih terblokir (`perf_event_paranoid=2`), jadi tidak ada
atribusi per-fungsi; angka di atas murni dari A/B proses.
