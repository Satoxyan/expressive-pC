# Baseline 2026-11-15 (branch `audit/perf`, sebelum perbaikan apa pun)

Kondisi: qs 0.3.2 (`quickshell-git`), Qt 6.12, Hyprland, 1 monitor `eDP-1`
1920×1080@144 scale 1, iGPU i915, **musik sedang diputar sepanjang pengukuran**
(`playerctl status` = Playing), tidak ada jendela user yang difokuskan.
3 repetisi per skenario, median. Angka mentah: `S1.csv`…`S5.csv`, `startup.txt`,
`env.json`, `effective-config.json`, `shots/`.

| Skenario | CPU % 1 core | ctx switch/10s | page fault/10s | IPC | RSS MB | PSS MB | thread |
|---|---|---|---|---|---|---|---|
| S0 startup (siap QML) | — (1720 ms) | — | — | — | — | — | — |
| S1 idle (bar) | 11,49 | 2226 | 4766 | 1,19 | 1037 | 875 | 85 |
| S2 overview | 16,42 | 5923 | 4280 | 1,02 | 1059 | 894 | 98 |
| S3 sidebar L+R | 24,85 | 5403 | 18686 | 1,12 | 1319 | 1114 | 98 |
| S5 settings | 11,02 | 2342 | 1932 | 1,27 | 1282 | 1095 | 97 |
| S4 mediaControls | 26,05 | 5865 | 2053 | 1,39 | 1254 | 1077 | 93 |

## Yang langsung terlihat

1. **Idle 11,5 % satu core** dan 2226 context switch / 10 s (222/detik) —
   ada pekerjaan berkala yang tidak sepadan dengan bar yang diam. Ini biaya
   yang paling sering dibayar user (kondisi default).
2. **Panel = +250–290 MB RSS** (S3 1319 MB, S5 1282 MB, S4 1254 MB) versus
   1037 MB sesudah kembali ke idle. Perlu dipastikan apakah ini cache yang
   disengaja atau retensi setelah panel ditutup.
3. **S3 punya page fault 18.686 / 10 s** (4× idle) dan lonjakan CPU 25 %.
4. Thread naik 85 → 98 saat panel dibuka, dan tidak turun setelah ditutup
   pada pengukuran berikutnya.

## Batasan pengukuran ini

- **GPU tidak terukur** (`gpu = -1`): `intel_gpu_top` butuh `CAP_PERFMON`,
  `sudo -n` tidak tersedia. Baseline GPU harus diambil ulang setelah
  `sudo setcap cap_perfmon+ep /usr/bin/intel_gpu_top`.
- Monitor kedua sedang `disabled`, jadi jalur per-monitor belum terwakili.
- Kondisi "musik diputar" harus dipertahankan identik pada setiap pengukuran
  pembanding, kalau tidak angka S1/S4 tidak sebanding.
