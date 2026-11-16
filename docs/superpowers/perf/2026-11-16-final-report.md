# Laporan akhir audit resource qs — 2026-11-16

Branch `audit/perf`, basis `7a81d50`, HEAD saat laporan ditulis `cd38536`.
Tidak ada commit yang di-push. Semua angka mentah ada di direktori ini
(`S1.csv`…`S5.csv`, `startup.csv`, `startup-base-7a81d50.csv`,
`trace-summary.txt`, `shots/`).

Kondisi pengukuran: qs 0.3.2 (`quickshell-git`), Qt 6.12, Hyprland, 1 monitor
`eDP-1` 1920×1080@144, iGPU i915, **musik diputar sepanjang pengukuran**
(`playerctl status` = Playing), tidak ada jendela user yang difokuskan.
Urutan skenario sama dengan baseline: S1 → S2 → S3 → S5 → S4.
Sampel 10 detik per repetisi, angka di tabel = median.

## Sebelum → sesudah

CPU dalam persen **satu core** (100 % = 1 core penuh).

| Skenario | CPU sebelum | CPU sesudah | Δ | ctx/10 s | RSS MB | PSS MB |
|---|---|---|---|---|---|---|
| S0 startup (siap QML) | 1720 ms | 1780 ms¹ | ±0 | — | — | — |
| S1 idle (bar) | 11,49 | **4,52** (3,62 tenang²) | −61 % (−69 %) | 2226 → 2435 | 1037 → 1063 | 875 → 903 |
| S2 overview | 16,42 | **9,48** (9,37) | −42 % | 5923 → 6246 | 1059 → 1087 | 894 → 927 |
| S3 sidebar L+R | 24,85 | **18,85** (16,87) | −24 % (−32 %) | 5403 → 6286 | 1319 → 1319 | 1114 → 1124 |
| S5 settings | 11,02 | **3,95** (3,90) | −64 % | 2342 → 2352 | 1282 → 1309 | 1095 → 1128 |
| S4 mediaControls | 26,05 | **14,35** (14,09) | −45 % | 5865 → 6102 | 1254 → 1278 | 1077 → 1106 |

¹ A/B dalam satu sesi: basis `7a81d50` 1781/1764/1747 ms (median 1764),
HEAD 1801/1752/1853 + 1834/1733/1759 ms (median 1780). Selisih +16 ms = derau;
tidak ada klaim perbaikan maupun regresi startup.
² "Tenang" = sampel yang tidak bertumpang dengan ledakan page fault
(`pf/10 s` > 10.000). Ledakan ini transien setelah panel dibangun, bukan biaya
menganggur. Sampel yang terbuang: S1 3 dari 8, S2 1 dari 6, S3 3 dari 6
(39,2 %/33,5 %/20,1 %), S5 1 dari 6, S4 1 dari 6 (21,2 %).
Kolom RSS/PSS memakai lintasan pertama (sesi segar, urutan sama dengan
baseline); lintasan kedua dalam sesi yang sama lebih tinggi karena retensi.

Rincian sampel per skenario (semua, termasuk yang bertumpang ledakan):

```text
S1 n=8  cpu 3,6 16,1 9,1 | 5,8 3,1 5,1 3,9 3,6      pf 1.485 12.252 38.402 | 35.320 138 5.618 617 481
S2 n=6  cpu 9,3 9,0 9,4 | 12,0 9,6 9,6             pf 2.157 959 727 | 36.343 540 2.181
S3 n=6  cpu 16,9 17,6 20,1 | 39,2 33,5 16,7        pf 3.170 4.542 38.921 | 299.288 241.228 2.910
S5 n=6  cpu 3,8 3,9 3,9 | 4,0 4,0 6,0              pf 988 526 121 | 509 717 41.395
S4 n=6  cpu 21,2 14,6 15,4 | 13,9 14,0 14,1        pf 103.870 209 647 | 407 354 527
```

Interpretasi yang jujur: penurunan di semua skenario berasal dari satu akar
yang sama (animasi dial volume yang berjalan walau dial tidak digambar),
karena kartu media ada di bar, sidebar kanan, settings, dan panel mediaControls.
Hanya fix #4 yang punya A/B dalam satu sesi (11,98 % → 2,20 % idle). Angka
sebelum/sesudah di tabel berasal dari dua sesi (baseline 2026-11-15 vs sesi ini);
drift antar sesi ada, karena itu setiap klaim perbaikan individual tetap
mengacu pada A/B-nya sendiri, bukan pada tabel ini.

Memori tidak membaik secara terukur. Fresh idle 1,06–1,09 GB (baseline 1,04 GB),
PSS 901–927 MB (baseline 875–894 MB). Setelah sidebar dibuka/ditutup, sesi ini
bertahan di ~1,25 GB (retensi ~+140 MB) — lebih rendah dari +270 MB sebelum
fix #3, tetapi tidak hilang, dan puncak S3 tetap ~1,32 GB karena isi sidebar
kanan dibangun eager sejak awal (disengaja, lihat daftar ditolak).
`VmSwap` 0, tidak ada memory pressure.

Context switch tidak turun (2.226 → 2.435 per 10 s di idle). Biaya yang hilang
adalah CPU rekonstruksi path QML di render thread, bukan jumlah bangun/tidur.

## Perubahan yang masuk

| Commit | Isi | Efek terukur |
|---|---|---|
| `b27b652` | fix #1: watcher VPN tidak lagi meninggalkan proses yatim saat halaman dibuka berulang | 3 proses yatim → 0. Tidak diklaim ada efek CPU/RSS |
| `7e51827` | ranking hotspot dari data terukur | — (dokumen) |
| `59b3a77` | atribusi ~300 MB RSS ke halaman phone | — (dokumen) |
| `93bd921` | fix #3: isi kartu notifikasi yang mengembang di belakang `Loader` | buka sidebar +173 MB (dulu +308), retensi +121 MB (dulu +270). A/B/A satu sesi |
| `a26e6ff` | fix #4: animasi gelombang `MaterialDial` hanya saat dial terlihat | idle 11,98 % → 2,20 % (n=8 vs n=10), recheck 2,07 %. RSS tidak berubah |
| `139f2d4` | bug fix terpisah: scroll touchpad di dial volume | bukan optimisasi; 10 test QML, gate manual PASS |
| `5a1cec5` | catat gate manual fix #4 | — (dokumen) |
| `cd38536` | perbaiki probe kesiapan `measure.sh --startup` | dulu melaporkan 55–66 ms; sekarang 1752–1853 ms |

## Perubahan nilai default dan perubahan sistem

- Nilai default config: **tidak ada yang diubah**. `gpu_busy_pct` tetap `-1`
  dengan WARN eksplisit karena `CAP_PERFMON` tidak tersedia.
- Perubahan sistem: **tidak ada**. `setcap` butuh sudo non-interaktif (gagal),
  `perf_event_paranoid=2` dan `yama/ptrace_scope=1` tidak diubah. Atribusi
  per-fungsi dikerjakan lewat trace QML (`qs --debug` + `qmlprofiler`), bukan
  `perf record`.
- Tidak ada perubahan di `~/.config/hypr/*`, tidak ada pekerjaan dGPU.
- Tidak ada fitur yang dihapus.

## Yang ditolak (dengan alasan terukur)

| Kandidat | Alasan |
|---|---|
| memperbaiki error ikon KDE Connect 0-byte | 53 baris log sekali saat halaman phone dibangun; delta resource 0 selama 65 detik |
| gate visibilitas jendela untuk `StyledSlider` / `MaterialLoadingIndicator` | hasil 2,08 % vs 2,20 % (derau), dan instance-nya memang ada di jendela terlihat |
| menunda pembangunan isi sidebar kanan saat startup | angkanya sama dengan gate dial, tetapi mengubah kehangatan buka pertama; tidak perlu setelah biaya dial hilang |
| menyembunyikan/menunda konten sidebar kanan saat tertutup | tidak ada kenaikan terukur setelah fix #4 dan mengubah UX |
| memasang `setcap` untuk `intel_gpu_top` | butuh sudo; metrik GPU tetap tidak tersedia dan tidak diklaim |

## Keputusan C: apakah sisa biaya tersebar struktural?

Ya, tersebar — tidak ada lagi hotspot CPU tunggal di atas derau. Angka
pendukung:

1. **Idle sisa 2,1–3,9 % satu core, dan komposisinya sudah terukur.** Trace
   QML sesudah fix #4, musik Paused (12,9 detik): **1.013 event/detik**, dari
   **72.082 event/detik** di trace sebelum fix dengan kondisi sama (−98,6 %).
   Yang tersisa saat Paused:

   | Event | Laju | Apa |
   |---|---|---|
   | `StyledSlider.qml:161` FrameAnimation | 167/dtk | gelombang slider di isi sidebar kanan yang sudah dibangun tapi tersembunyi |
   | `PhoneNotifications.qml:89` | 120/dtk | halaman phone, dibangun eager, tersembunyi |
   | `PhoneConnect.qml` + `PhoneNotifications.qml` (seri) | ~12/dtk per titik | idem |
   | `StyledProgressBar.qml:74/83` | 90/dtk masing-masing | progress bar yang dibangun |

   Dengan musik Playing, 37.577 event/detik: 3.061/dtk
   `MediaControls.qml:190` (feed `cava`), ~11.000/dtk `point.js`/`cubic.js`
   dari progress/visualizer bergelombang, dan ~1.600/dtk binding spinner
   `MaterialLoadingIndicator`/`MaterialShape`. Semua itu milik widget yang
   terlihat selama musik diputar — biaya yang disengaja, bukan kebocoran.

   Kandidat berikutnya yang sudah terukur tapi **belum** dikerjakan: ~500
   event/dtk di Paused berasal dari slider/progress/phone page yang tersembunyi
   di sidebar kanan (kelas bug yang sama dengan dial, tetapi jauh lebih murah).
2. **Tidak ada ledakan page fault berulang saat idle.** Monitor 150 detik:
   total 1.338 page fault, maksimum 463/detik, mayoritas <15/detik; RSS datar
   ~1,24 GB, `VmSwap` 0. Ledakan 30–300 ribu/10 detik hanya muncul sesaat
   setelah panel dibangun (S3/S4 di tabel).
3. **Yang tersisa berbentuk jumlah, bukan satu penyebab:** 114 singleton,
   254 blok `Timer` di 706 file QML (24 dengan interval 1000 ms, 15×600 ms,
   10×500 ms, 8×120 ms, 8×100 ms), plus 4 proses anak tetap (watcher VPN
   `ip route` tiap 1 detik, `nmcli monitor`, `busctl monitor` KDE Connect,
   `contacts_monitor.py`) yang masing-masing ~0 % CPU.
4. **Biaya keadaan terbuka tetap ada dan datang dari isi, bukan animasi:**
   overview +5 poin, sidebar +14 poin, mediaControls +11 poin di atas idle.
   Menurunkannya berarti mengubah kapan/apakah konten dibangun — keputusan UX,
   bukan lagi pemborosan.
5. **Startup 1,78 detik** dan **RSS idle 1,06–1,09 GB** tidak berubah; keduanya
   ditentukan oleh 114 singleton dan isi yang dibangun eager, bukan oleh satu
   komponen.

Kalau dilanjutkan, ada dua tingkat pekerjaan:

- **Kecil, sudah terukur:** ~500 event/dtk di Paused dari slider/progress/phone
  page tersembunyi di sidebar kanan (bagian 1 di atas). Jendela sidebarRight
  sendiri `visible: false` saat tertutup, jadi canvas-nya tidak melukis dan
  sisanya hanya callback JS — perkiraan dampak CPU kecil, harus diukur dulu
  sebelum diklaim.
- **Struktural, belum diukur sama sekali:** menggabungkan timer per-file menjadi
  satu ticker global, dan memindahkan watcher VPN 1 detik ke event
  `ip monitor`/`nmcli monitor`. Keduanya menyentuh banyak pemanggil dan butuh
  rencana sendiri.
