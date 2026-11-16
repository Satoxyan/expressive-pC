#!/usr/bin/env bash
# Regresi kebocoran watcher: ambil perintah bash loop dari services/Vpn.qml apa
# adanya, jalankan di bawah parent sementara, bunuh parent itu, lalu pastikan
# loop ikut mati. Tanpa penjaga PPID, loop jadi yatim dan hidup selamanya
# (tiap restart qs menambah satu proses).
#
# Pakai: scripts/perf/tests/vpn-watcher-dies-with-parent.sh [path/Vpn.qml]
set -uo pipefail

QC=${1:-services/Vpn.qml}
[ -f "$QC" ] || { echo "FAIL: $QC tidak ada" >&2; exit 2; }

script=$(python3 - "$QC" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'id: tunnelWatch.*?\n\s*command: \["bash", "-c", "(.*?)"\]', src, re.S)
if not m:
    sys.exit("tunnelWatch bash command tidak ditemukan")
print(m.group(1).replace('\\"', '"'))
PY
) || exit 2

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$script" > "$tmp/loop.sh"
printf '#!/usr/bin/env bash\nbash "%s/loop.sh" &\necho $! > "%s/child.pid"\nwait\n' "$tmp" "$tmp" > "$tmp/parent.sh"

bash "$tmp/parent.sh" & parent=$!
for _ in $(seq 1 50); do [ -s "$tmp/child.pid" ] && break; sleep 0.1; done
child=$(cat "$tmp/child.pid" 2>/dev/null) || { echo "FAIL: watcher tidak pernah mulai" >&2; exit 1; }

kill -9 "$parent" 2>/dev/null
sleep 3

if kill -0 "$child" 2>/dev/null; then
  echo "FAIL: watcher $child masih hidup setelah parent mati (proses bocor)"
  kill -9 "$child" 2>/dev/null
  exit 1
fi
echo "PASS: watcher mati bersama parent"
