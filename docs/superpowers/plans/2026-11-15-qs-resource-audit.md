# Audit Resource Quickshell (expressive-pC) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menurunkan CPU, RAM, dan GPU yang dipakai proses `qs` pada config ini, terukur per perubahan, tanpa satu pun fitur rusak atau hilang.

**Architecture:** Ukur dulu (harness + baseline per skenario), urutkan hotspot berdasarkan angka, lalu perbaiki satu per satu; tiap perbaikan wajib punya angka sebelum/sesudah dan lulus empat lapis gerbang (qmllint Qt6 → boot log → screenshot ter-mask → checklist manual). Pendekatan A dari spec.

**Tech Stack:** Quickshell 0.3.2 / Qt 6.12 (QML), bash, `perf`, `/proc`, `intel_gpu_top`, `grim`, ImageMagick, `hyprctl`.

**Spec:** `docs/superpowers/specs/2026-11-15-qs-resource-audit-design.md`

## Global Constraints

- Target kerja: `~/.config/quickshell/expressive-pC` (pohon live). Repo `~/git/expressive-pC` bukan target.
- Satu commit = satu perbaikan, selalu membawa angka sebelum/sesudah.
- **Tidak ada ambang minimal** penurunan resource. Semua angka dilaporkan apa adanya.
- Dilarang: menghapus/mematikan fitur, mengubah `~/.config/hypr/hyprland/*.lua`, menyentuh dGPU (qs render di iGPU), atau menurunkan interval sampai data basi tanpa mengukur dampaknya.
- Gate wajib per perbaikan: `/usr/lib/qt6/bin/qmllint` (sintaks) → `qs log` tanpa error baru → `grim` + `magick compare` mask ≤0,1 % piksel non-mask → checklist manual.
- Angka mentah ke `docs/superpowers/perf/<YYYY-MM-DD>-<label>/` sebagai CSV; jangan hanya di percakapan.
- Verifikasi yang benar-benar tervalidasi: semua perintah di bawah sudah dicoba di mesin ini kecuali yang ditandai `(belum dicoba)`.

## Review Focus

1. **Config efektif ≠ default di repo.** `~/.config/illogical-impulse/config.json` mem-pin nilainya sendiri, jadi perubahan default bisa tidak berefek apa pun pada angka. Setiap baseline menyimpan salinan config efektif; perbaikan yang menyentuh default wajib membuktikan nilainya benar-benar terpakai.
2. **Monitor kedua sedang `disabled`.** Jalur per-monitor tidak terukur sekarang; perubahan yang menambah/mengurangi item per monitor bisa lolos gate di 1 monitor lalu rusak di 2.
3. **Path preview overview (rearm + snapshot) baru di-merge dan rapuh.** Perubahan pada capture/`ScreencopyView` bisa membuat tile kosong tanpa error di log.
4. **Lock screen.** Optimasi yang menyentuh `LockScreen.qml`/`LockSurface.qml` bisa membuat layar tidak bisa dibuka. Wajib uji lock manual sebelum commit.
5. **Nilai/nama non-ASCII dan panjang** (judul media, lirik, hostname) — jalur teks yang sering dipakai untuk refresh berkala.

---

### Task 1: Siapkan pohon kerja audit

**Files:**
- Modify (git state): `~/.config/quickshell/expressive-pC` — branch `audit/perf`
- Create: `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/superpowers/perf/` di pohon live

**Interfaces:**
- Produces: pohon live di branch `audit/perf`, tanpa proses yatim, `intel_gpu_top` punya `CAP_PERFMON`.

- [ ] **Step 1: Pastikan pohon live bersih dan commit pekerjaan staged**

```bash
cd ~/.config/quickshell/expressive-pC
git status --short          # 6 file staged (preview/smooth screencopy)
git commit -m "feat(previews): sharper window previews in overview and dock"
git status --short          # harus kosong
```

- [ ] **Step 2: Buat branch audit dari HEAD**

```bash
git switch -c audit/perf
git branch --show-current   # audit/perf
```

- [ ] **Step 3: Matikan proses yatim watcher (3 `bash` loop `ip route` di `ppid 1`)**

```bash
ps -o pid,ppid,etime,cmd -C bash | grep 'ip -4 route'
pkill -f 'ip -4 route get 1.1.1.1'
sleep 1; ps -o pid,cmd -C bash | grep -c 'ip -4 route'   # 0 selain milik instance aktif
```

- [ ] **Step 4: Beri `intel_gpu_top` izin sampling**

```bash
sudo setcap cap_perfmon+ep /usr/bin/intel_gpu_top
getcap /usr/bin/intel_gpu_top          # ... cap_perfmon=ep
intel_gpu_top -J -s 500 -o /tmp/opencode/gpu.json & sleep 2; kill %1
grep -c '"Render/3D"' /tmp/opencode/gpu.json    # >0
```

- [ ] **Step 5: Salin dokumen spec & plan ini ke pohon live, lalu commit**

```bash
mkdir -p docs/superpowers/{specs,plans,perf}
cp /home/syoxide/git/expressive-pC/docs/superpowers/specs/2026-11-15-qs-resource-audit-design.md docs/superpowers/specs/
cp /home/syoxide/git/expressive-pC/docs/superpowers/plans/2026-11-15-qs-resource-audit.md docs/superpowers/plans/
git add docs/ && git commit -m "docs(perf): add resource audit spec and plan"
```

---

### Task 2: Harness pengukur (`measure.sh`)

**Files:**
- Create: `scripts/perf/measure.sh`

**Interfaces:**
- Produces: `measure.sh [--pid PID] [--seconds N] [--out FILE]` → menulis satu baris CSV dengan header:
  `ts,pid,task_clock_ms,ctx_switches,page_faults,ipc,rss_kb,pss_kb,private_dirty_kb,threads,gpu_busy_pct`
- Produces: `measure.sh --startup` → mencetak `startup_ms` (waktu dari `qs` dijalankan sampai `qs ipc` menjawab).
- Produces: exit≠0 jika ada kolom kosong (itu self-test-nya).

- [ ] **Step 1: Tulis skrip**

Sumber angka (semua sudah diverifikasi kecuali GPU):
- CPU & page fault & IPC: `perf stat -p $PID -e task-clock,page-faults,cycles,instructions sleep $SECONDS` (parse `2>&1`).
- IPC = instructions/cycles.
- `ctx_switches`: delta `voluntary_ctxt_switches` + `nonvoluntary_ctxt_switches` dari `/proc/$PID/status` selama jendela ukur (pengganti `powertop` — tidak butuh root).
- RAM: `grep -E '^(Rss|Pss|Private_Dirty):' /proc/$PID/smaps_rollup` (kB).
- Thread: `ls /proc/$PID/task | wc -l`.
- GPU: `intel_gpu_top -J -s 200 -o -` selama jendela ukur, ambil median `Render/3D` `busy` (integer %, pakai `python3` untuk parsing JSON stream).
- PID default: `pgrep -x qs | head -1`.

- [ ] **Step 2: Jalankan self-test terhadap instance yang hidup**

```bash
scripts/perf/measure.sh --seconds 10 --out /tmp/opencode/m.csv; echo "rc=$?"
column -s, -t < /tmp/opencode/m.csv
```
Expected: `rc=0`, 11 kolom terisi, `task_clock_ms` antara 100–5000, `pss_kb` < `rss_kb`.

- [ ] **Step 3: Commit**

```bash
git add scripts/perf/measure.sh
git commit -m "perf: add resource measurement harness"
```

---

### Task 3: Harness visual (`shot.sh` + mask)

**Files:**
- Create: `scripts/perf/shot.sh`
- Create: `scripts/perf/masks.conf`

**Interfaces:**
- Produces: `shot.sh --scenario S1|S2|S3|S5 --tag baseline|after --out DIR` → menulis `<DIR>/<scenario>-<tag>.png`.
- Produces: `shot.sh --compare --scenario S1 --baseline DIR --after DIR` → mencetak `diff_pct=<float>` dan exit 0 jika `diff_pct ≤ 0.1`.
- `masks.conf`: satu baris per kotak `x,y,w,h,komentar` (koordinat piksel monitor `eDP-1`), untuk jam, NetworkSpeed, grafik resource, progres media, isi preview overview.

- [ ] **Step 1: Tulis `masks.conf` dengan koordinat nyata**

Ambang dan kotak ditentukan dari satu tangkapan: `grim -o eDP-1 /tmp/opencode/m0.png`, lalu baca koordinat widget volatile. Isi awal (sesuaikan setelah melihat gambar):

```
0,0,1920,60,bar atas: jam/network/graph/island
```

- [ ] **Step 2: Tulis `shot.sh`**

`--compare` menggambar kotak hitam pada kedua PNG (dari `masks.conf`, `magick -draw "rectangle ..."`) ke `/tmp`, lalu `magick compare -metric AE base.png after.png null:` → persen dari total piksel non-mask.

- [ ] **Step 3: Uji dengan build yang sama (kontrol negatif)**

```bash
scripts/perf/shot.sh --scenario S1 --tag baseline --out /tmp/opencode/shots
sleep 3
scripts/perf/shot.sh --scenario S1 --tag after --out /tmp/opencode/shots
scripts/perf/shot.sh --compare --scenario S1 --baseline /tmp/opencode/shots --after /tmp/opencode/shots; echo "rc=$?"
```
Expected: `rc=0` dengan `diff_pct` kecil. Kalau gagal, kotak mask belum menutup widget volatile — perbaiki `masks.conf`, bukan ambangnya.

- [ ] **Step 4: Commit**

```bash
git add scripts/perf/shot.sh scripts/perf/masks.conf
git commit -m "perf: add masked visual regression harness"
```

---

### Task 4: Baseline S0–S5

**Files:**
- Create: `docs/superpowers/perf/<YYYY-MM-DD>-baseline/{S1.csv,S2.csv,S3.csv,S4.csv,S5.csv,startup.txt,effective-config.json,summary.md}`

**Interfaces:**
- Consumes: `measure.sh`, `shot.sh` (Task 2–3).
- Produces: direktori baseline yang dipakai semua task perbaikan sebagai pembanding.

- [ ] **Step 1: Catat config efektif** — `cp ~/.config/illogical-impulse/config.json` + `qs ipc call` yang relevan ke `effective-config.json` (alasan: Review Focus #1).

- [ ] **Step 2: Ukur S0 (startup)** — `scripts/perf/measure.sh --startup` 3× setelah `killall qs; sleep 1`; median ke `startup.txt`.

- [ ] **Step 3: Ukur S1 (idle)** — setelah start, diamkan 60 s, lalu `measure.sh` 3× × 10 s, `shot.sh` S1.

- [ ] **Step 4: Ukur S2 (overview)** — `qs ipc call search toggle`; verifikasi terbuka lewat `shot.sh` (gambar berbeda dari S1); lalu 3× ukur + screenshot.

- [ ] **Step 5: Ukur S3 (sidebar kiri+kanan), S5 (settings)** — sama polanya dengan IPC target masing-masing.

- [ ] **Step 6: Ukur S4 (media + lirik)** — putar satu track dengan judul non-ASCII (Review Focus #5), 3× ukur.

- [ ] **Step 7: Tulis `summary.md`** berisi median tiap metrik per skenario, dan commit.

```bash
git add docs/superpowers/perf && git commit -m "perf: baseline S0-S5 measurements"
```

---

### Task 5: Skill `qs-perf-audit`

**Files:**
- Create: `~/.config/opencode/skills/qs-perf-audit/SKILL.md`

**Interfaces:**
- Produces: skill yang dipakai subagent di Task 8 ke atas.

- [ ] **Step 1 (RED): jalankan baseline tanpa skill.** Dispatch subagent general dengan: "Optimalkan penggunaan CPU/RAM config Quickshell di `~/.config/quickshell/expressive-pC` tanpa merusak fitur." Catat verbatim: apakah ia mengukur dulu, apa yang ia ubah tanpa angka, rasionalisasi apa yang muncul.

- [ ] **Step 2: Tulis skill** yang menutup tepat kegagalan itu. Isi wajib: protokol ukur (Task 2–3), daftar area + path nyata, aturan "tidak ada perubahan tanpa angka", keempat lapis gate, dan larangan mengubah `hyprland/*.lua`/menghapus fitur. Frontmatter `description` mulai dengan "Use when...".

- [ ] **Step 3 (GREEN): ulangi Step 1 dengan skill aktif.** Subagent harus mengukur dulu dan menolak mengubah apa pun tanpa angka. Kalau tidak, perbaiki skill dan ulangi.

- [ ] **Step 4: Commit skill** (di luar repo config; tidak ada commit git untuk ini) dan catat lokasinya di laporan.

---

### Task 6: Perbaikan #1 — kebocoran watcher proses

**Files:**
- Modify: `services/Vpn.qml:152`

**Interfaces:**
- Consumes: baseline S1 (Task 4).

- [ ] **Step 1: Ukur sebelum** — hitung proses `ip -4 route` milik instance aktif dan angka S1 (`measure.sh`, 10 s).

- [ ] **Step 2: Perbaiki akar masalah** — `Process` di `Vpn.qml` tidak boleh meninggalkan anak saat qs mati/restart. Pilihan lazim di repo: hentikan loop lewat `onExited`/`onRunningChanged` dan pastikan `Process` di-reap; atau ganti polling `ip route` dengan pembacaan langsung (mis. `nl`/`ip -j` sekali per perubahan dari event NetworkManager). Pilih yang paling kecil dan tetap memberi hasil sama.

- [ ] **Step 3: Verifikasi kebocoran hilang** — restart qs 3× berturut-turut, tiap kali `ps -C bash | grep -c 'ip -4 route'` harus 0–1 (hanya milik instance yang hidup).

- [ ] **Step 4: Ukur sesudah** — S1 lagi, 3×; tulis ke `docs/superpowers/perf/<tanggal>-fix1-vpn/`.

- [ ] **Step 5: Gate** — qmllint, `qs log` tanpa error baru, `shot.sh --compare` S1, checklist manual.

- [ ] **Step 6: Commit** dengan tabel angka sebelum/sesudah di body commit.

---

### Task 7: Peringkat hotspot dari data

**Files:**
- Create: `docs/superpowers/perf/<tanggal>-ranking.md`

- [ ] **Step 1:** Dari baseline, buat tabel per area: bukti angka (CPU/page-fault/RSS/GPU), file, dugaan penyebab, perkiraan biaya perbaikan, risiko gate.
- [ ] **Step 2:** Minta user menyetujui urutan. Berhenti di sini sampai disetujui.

---

### Task 8 (template, diulang per hotspot): Perbaikan #N

**Files:** sesuai hotspot; biasanya 1 file + 1 komit.

**Interfaces:**
- Consumes: `measure.sh`, `shot.sh`, baseline, `masks.conf`.

- [ ] **Step 1:** Ukur skenario yang relevan (10 detik, 3×, median) — simpan sebagai "before".
- [ ] **Step 2:** Ubah **satu** hal, sekecil mungkin, akar masalahnya bukan gejalanya (grep semua pemanggil fungsi yang disentuh).
- [ ] **Step 3:** Gate 1–4 dari Global Constraints, plus gate bersyarat:
  - menyentuh `LockScreen.qml`/`LockSurface.qml` → **wajib** uji lock + unlock manual (Review Focus #4);
  - menyentuh capture/preview (`ScreencopyView`, `OverviewWindow`, `DragApps`) → **wajib** screenshot S2 dan tile yang berisi preview (Review Focus #3);
  - menambah/menghapus item per monitor → **wajib** dicatat deret nama monitor dari `hyprctl monitors -j` di CSV, dan batasannya ditulis jelas kalau monitor kedua tidak bisa dinyalakan (Review Focus #2);
  - mengubah nilai default → **wajib** buktikan nilai efektif berubah (`~/.config/illogical-impulse/config.json` bisa mem-pin nilainya; Review Focus #1).

  Gate 4 dijalankan user; kalau belum tersedia, perbaikan berhenti di branch, tidak di-commit ke `audit/perf`.
- [ ] **Step 4:** Ukur lagi, hitung delta, tulis CSV `docs/superpowers/perf/<tanggal>-fixN-<slug>/`.
- [ ] **Step 5:** Commit dengan angka; kalau gate gagal → `git revert`/`git checkout -- <file>`, catat alasannya di `docs/superpowers/perf/rejected.md`.

---

### Task 9: Laporan akhir + data keputusan C

**Files:**
- Create: `docs/superpowers/perf/<tanggal>-final-report.md`

- [ ] **Step 1:** Tabel sebelum/sesudah per skenario per metrik (median), daftar perubahan default (nilai lama → baru), perubahan sistem (`setcap`), dan daftar yang ditolak.
- [ ] **Step 2:** Bagian keputusan C: apakah biaya yang tersisa tersebar struktural (timer per-file, capture per-monitor terduplikasi, 114 singleton) atau ada hotspot tunggal. Sertakan angka yang mendukung, bukan opini.
- [ ] **Step 3:** Serahkan ke user untuk memutuskan lanjut C atau berhenti.
