# Design: Audit & Optimalisasi Resource Quickshell (expressive-pC)

Tanggal: 2026-11-15
Status: menunggu persetujuan

## 1. Intent

Config Quickshell ini (`expressive-pC`, 729 file QML, ~132.000 baris) memakai
resource yang tidak sepadan dengan apa yang sedang ditampilkan. Yang diukur
sekarang, pada kondisi idle, satu instance qs:

| Metrik | Nilai terukur | Sumber |
|---|---|---|
| Residen (RSS / PSS) | 1.092 MB / 925 MB | `/proc/<pid>/smaps_rollup` |
| Private dirty | 879 MB | idem |
| Thread | 85 | `ps -o nlwp` |
| CPU idle (10 s) | 276 ms task-clock = **2,76 %** satu core | `perf stat -p` |
| CPU rata-rata sejak start | 6,5 % (termasuk startup) | `ps %cpu` |
| IPC | **0,54** — 46 % waktu menunggu memory/sync | `perf stat` |
| Page fault | **≈ 1.160 / detik** saat idle | `perf stat` |

Tujuannya: menurunkan angka-angka ini tanpa mencabut fitur.

## 2. Goals

1. Menurunkan CPU idle, GPU busy, dan RAM qs, terukur, per perbaikan.
2. Setiap penurunan angka dibuktikan **tidak** merusak fitur (gerbang §7).
3. Meninggalkan artefak: harness ukur yang bisa dijalankan ulang, checklist
   smoke, dan satu laporan berisi angka sebelum/sesudah.
4. Menghasilkan data yang cukup untuk memutuskan apakah pendekatan C
   (rombak arsitektur) layak.

## 3. Non-goals

- Tidak menambah fitur, tidak mengubah default config milik user.
- Tidak mengubah `hyprland.conf` atau config kompositor di luar repo ini.
- Tidak mengoptimasi proses selain `qs` (mis. `hyprland`, `pipewire`).
- Tidak mengejar angka dengan mematikan fitur secara diam-diam.

## 4. Anti-goals (dianggap gagal walau angka turun)

- Ada fitur yang berhenti berfungsi, rusak visual, atau animasi jadi patah.
- Angka turun karena fitur dimatikan lewat config default.
- Perbaikan hanya berlaku di mesin ini (hardcode path, `scale`, jumlah monitor).
- Regresi performa di skenario lain (menang idle, kalah saat overview dibuka).

## 5. Batasan (fakta mesin & repo)

- Quickshell 0.3.2 (`quickshell-git`), Qt 6.12, Hyprland. Saat ini **satu
  monitor aktif** (`eDP-1`, 1920×1080@144, scale 1); monitor kedua terdeteksi
  tapi `disabled`. Multi-monitor hanya masuk checklist manual, bukan baseline.
- Hybrid GPU: **qs render di Intel iGPU** (`/dev/dri/renderD128` → `i915`),
  RTX 3050 tidak dipakai qs. Jadi GPU yang diukur `intel_gpu_top`; `nvtop`
  hanya untuk memastikan dGPU tidak ikut terbangun.
- **Shell yang berjalan TIDAK dijalankan dari repo ini.** `qs -c
  expressive-pC` membaca `~/.config/quickshell/expressive-pC` (checkout git
  terpisah, HEAD `7a81d50`, remote `Satoxyan/expressive-pC`, inode berbeda,
  tanpa symlink/deploy script). **Keputusan: audit dikerjakan langsung di pohon
  live itu**, pada branch audit khusus, supaya angka yang diukur adalah angka
  dari kode yang benar-benar berjalan. Repo ini hanya jadi rujukan historis.
  Sebelum baseline: 6 file staged di pohon live (pekerjaan preview yang sudah
  di-commit di repo ini, `b73dc68`) di-commit dulu supaya basisnya bersih.
- `perf_event_paranoid=2` → profiling userspace proses sendiri tanpa root.
  `powertop` (wakeup) butuh root; default: `sudo` khusus sampling.
- `heaptrack` & `valgrind` **meluncurkan instance qs baru** — tidak bisa
  menempel ke proses yang sedang jalan. Audit akan me-restart shell beberapa
  kali; bar hilang ~2 detik per restart.
- **Tidak ada test suite fungsional.** `tests/` = 3 suite (2 python, 1 QML
  lyrics). Mayoritas modul tidak punya test. Karena itu "tidak ada efek
  samping" harus dibuktikan dengan harness visual + checklist manual (§7).
- `qmllint` di `/usr/bin` adalah **Qt 5.15** dan selalu exit 255 tanpa output.
  Yang benar: `/usr/lib/qt6/bin/qmllint` (6.12). Ini bukan kerusakan repo.
- Repo ini punya 114 singleton, 270 `Timer`, 592 `Behavior on`, 16
  `ShaderEffect`, 16 `MultiEffect`. Beban utama ada di scene graph dan
  polling service, bukan di algoritma.

## 6. Pendekatan

| | Cara | Status |
|---|---|---|
| **A** | Bukti dulu: bangun harness + smoke gate → baseline per skenario → ranking hotspot → perbaiki satu per satu dengan angka sebelum/sesudah | **Dipilih** |
| B | Per-resource berurutan (CPU → GPU → RAM) | Ditolak: 3x lintas file yang sama, 3x risiko regresi, tanpa keunggulan |
| C | Rombak arsitektur (scheduler timer terpusat, service capture bersama, polling terpadu) | Ditunda: dinilai setelah A menghasilkan data. Pemicu di §11 |

Di dalam A, urutan kerja mengikuti biaya terukur, bukan urutan folder.

## 7. Metrik & protokol ukur

### Skenario (masing-masing diukur terpisah, urutan tetap)

| ID | Kondisi | Pemicu |
|---|---|---|
| S0 | start bersih | `qs -c expressive-pC` sampai frame pertama |
| S1 | idle, hanya bar | diamkan 60 s setelah start |
| S2 | overview terbuka | `qs ipc call search toggle` (verifikasi nama perintah saat implementasi) |
| S3 | sidebar kiri + kanan | `qs ipc call sidebarLeft toggle`; `sidebarRight toggle` |
| S4 | media main + lirik | `mpv`/player + bar media |
| S5 | settings terbuka | `qs ipc call settings toggle` |

### Angka yang diambil per skenario

CPU (`perf stat -p <pid>` 10 s: task-clock, page-faults, cycles, instructions,
IPC), RAM (`smaps_rollup`: RSS, PSS, Private_Dirty) + tren selama 5 menit,
thread, wakeup/detik (`powertop --csv` 30 s), GPU (`intel_gpu_top` busy %),
frame time (`QSG_RENDER_TIMING=1`, ambil median + p95 saat S2/S4), dan waktu
start (S0).

### Aturan pengukuran

- **Sebelum baseline:** matikan proses yatim dari instance qs lama (saat ini 3
  `bash` loop `ip route` 1 Hz di `ppid 1`). Tanpa ini, angka idle tercemar dan
  makin tercemar tiap restart.
- 3 repetisi, ambil median; deviasi antar-repetisi >15 % → ukur ulang.
- Kondisi sama: brightness, jumlah jendela terbuka, wallpaper, monitor aktif.
- Sebelum ukur: diamkan 10 s supaya cache/animasi startup reda.
- Semua angka mentah disimpan di `docs/superpowers/perf/<tanggal>-<commit>/`
  sebagai CSV, bukan ditempel di percakapan.

## 8. Gerbang verifikasi (4 lapis, dari murah ke mahal)

1. **Statis (sintaks saja)** — `/usr/lib/qt6/bin/qmllint` pada file yang
   disentuh; tidak boleh menambah error. Batas jujur: qmllint tidak bisa
   me-resolve `import qs.*` (Quickshell memetakan `qs` ke root config saat
   runtime; qmllint tidak punya padanannya), jadi gate ini hanya menangkap
   kesalahan sintaks — bukan tipe/properti. Bukan gerbang keselamatan.
2. **Boot** — qs start tanpa error baru di `qs log` (diff log sebelum/sesudah).
3. **Visual** — `grim` menangkap layar pada skenario S1–S5 sebelum & sesudah.
   Karena bar **tidak pernah statis** (jam, NetworkSpeed 1 s, grafik resource
   3 s, DynamicIsland, progres media, preview overview yang live), perbandingan
   memakai **mask per-widget**: jam, speed, grafik, progres, dan isi preview
   di-mask; sisanya dibandingkan dengan `magick compare -metric AE`, ambang
   ≤0,1 % piksel pada area non-mask. Perubahan pada area ter-mask diperiksa
   manual di gate 4.
4. **Manual** — checklist ±20 titik yang dijalankan user setelah batch selesai
   (overview, lock, dashboard, media, OSD, clipboard, wallpaper, blur,
   multi-monitor, region selector, session screen).

Satu commit = satu perbaikan = satu set angka + keempat lapis di atas.
Perbaikan yang tidak lolos lapis 3 atau 4 di-revert, bukan "diperbaiki nanti".

## 9. Area yang disisir (urutan awal, dapat berubah oleh data)

| Area | Bukti awal |
|---|---|
| Kebocoran proses | `services/Vpn.qml` menjalankan `bash` loop `ip route` **1 Hz selamanya**, dan loop itu **tidak mati saat qs restart**: saat audit disusun ada 3 proses yatim (`ppid 1`, umur 35 mnt & 28 mnt) dari instance sebelumnya, plus satu milik instance aktif. Tiap restart menambah satu. `services/SystemInfo.qml` juga fork per refresh |
| Timer/interval | 68 `running: true` di 48 file, 270 `Timer` total. `ResourceUsage.qml` tick pertama 1 ms lalu 3000 ms (aman — dugaan awal salah) |
| Singleton berat | 114 singleton, semua instansiasi saat start (kandidat RSS + startup) |
| Binding churn | 592 `Behavior on`, expression yang bergantung waktu/tick |
| GPU/efek | 16 `ShaderEffect`, 16 `MultiEffect`; blur & capture (overview) |
| RAM/retensi | `Image` tanpa `sourceSize`, cache tak dibatasi (`cache: false` vs unbounded), hasil `grabToImage` ditahan selamanya |
| Service IO | `nmcli monitor`, `busctl monitor`, reload file berulang |

## 10. Deliverable

1. `skills/qs-perf-audit/SKILL.md` — skill: protokol ukur, checklist per area,
   aturan "tidak ada perubahan tanpa angka", tangga verifikasi §8.
2. `scripts/perf/measure.sh` + `scripts/perf/shot.sh` — harness (angka mentah
   ke CSV, screenshot per skenario).
3. `docs/superpowers/perf/` — baseline + hasil per commit.
4. Satu laporan akhir: tabel sebelum/sesudah, daftar perubahan, sisa risiko,
   dan rekomendasi apakah C layak.

## 11. Kapan berhenti / kapan naik ke C

- **Tidak ada ambang minimal** yang harus dicapai (keputusan user): perubahan
  yang menurunkan resource sedikit tetap sah selama gerbang §8 lolos dan tidak
  mengorbankan fitur. Angka dilaporkan apa adanya, juga yang turunnya kecil.
- **Berhenti** saat daftar hotspot dari data sudah habis: tidak ada lagi
  perbaikan yang bisa dibuktikan aman lewat gerbang §8, dan checklist manual
  bersih.
- **Naik ke C** jika data A menunjukkan biaya terbesar berasal dari struktur
  yang tidak bisa diperbaiki per-file: mis. total biaya timer tersebar rata
  di puluhan file tanpa hotspot tunggal, atau capture/efek per-monitor
  terduplikasi oleh desain. Keputusan C disertai angka dari A, bukan opini.

## 12. Keputusan yang sudah diambil

1. **Target = pohon live** `~/.config/quickshell/expressive-pC`, branch audit
   sendiri. Tidak ada langkah sinkronisasi manual.
2. **Scope = kode + nilai default config**, dengan syarat: setiap perubahan
   default dicatat di tabel laporan (nilai lama → baru, alasan, angka
   pendukung) dan tidak mengubah apa yang dilihat user pada kondisi diam.
   Interval yang membuat data basi hanya boleh berubah bila diukur dampaknya.
3. **GPU & wakeup diotomasi** via `setcap cap_perfmon+ep
   /usr/bin/intel_gpu_top` dan satu entri sudoers NOPASSWD terbatas untuk
   `powertop --csv`. Keduanya perubahan sistem: disiapkan sekali, didokumentasi
   di laporan, bisa dicabut (`setcap -r`, hapus baris sudoers).

## 13. Yang diserahkan ke builder

- Nama perintah IPC final per skenario — target sudah diverifikasi ada semua
  (`search`, `sidebarLeft`, `sidebarRight`, `settings`); fungsi `toggle`
  per target dipastikan saat harness ditulis.
- Apakah `heaptrack` cukup akurat di build Qt release, atau butuh `valgrind
  --tool=massif` sebagai pembanding (jatuh tempo saat area RSS digarap).

Catatan: **tidak ada ambang signifikansi** (keputusan user). Angka dilaporkan
apa adanya; yang wajib hanyalah angka sebelum/sesudah ada dan gerbang §8 lolos.

## 14. Keputusan yang kuambil sendiri (boleh dibantah user)

- Kerja dilakukan di **branch audit** di pohon live; `main` tetap jadi titik
  pulang kalau eksperimen gagal.
- Harness tidak menyentuh `sudo` untuk `perf` (tidak perlu); hanya `powertop`
  yang lewat sudoers.
- Angka mentah disimpan di repo (di pohon live: `docs/superpowers/perf/`),
  bukan di `/tmp`, supaya bisa dibandingkan lintas bulan.
- Skill ditulis sebagai skill personal (`~/.config/opencode/skills/`), bukan
  file di repo, karena berlaku untuk config Quickshell apa pun.
