#!/usr/bin/env bash
# Harness ukur resource proses qs. Satu file, tanpa dependensi selain perf/awk/python3.
# ponytail: parsing toleran (perf -x, + /proc), bukan framework metrik.
#
# Pakai:
#   measure.sh [--pid N] [--seconds N] [--out FILE]   # satu baris CSV
#   measure.sh --startup [--out FILE]                 # startup_ms
#   measure.sh --selftest                             # wajib lulus sebelum dipakai
set -uo pipefail

CONFIG=${QS_CONFIG:-$(basename "$PWD")}
PID=""; SECS=10; OUT=""; MODE=measure; STARTUP_SECS=120

while [ $# -gt 0 ]; do
  case "$1" in
    --pid) PID=$2; shift 2 ;;
    --seconds) SECS=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --startup) MODE=startup; shift ;;
    --selftest) MODE=selftest; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

HEADER='ts,pid,task_clock_ms,ctx_switches,page_faults,ipc,rss_kb,pss_kb,private_dirty_kb,threads,gpu_busy_pct'

emit() { # $1 = row
  if [ -n "$OUT" ]; then
    [ -s "$OUT" ] || echo "$HEADER" >> "$OUT"
    echo "$1" >> "$OUT"
  fi
  echo "$1"
}

find_pid() { pgrep -x qs | head -1; }

gpu_busy() { # median Render/3D busy %, atau -1 kalau tak berizin/tak tersedia
  local tmp; tmp=$(mktemp)
  timeout 5 intel_gpu_top -J -s 200 -o "$tmp" >/dev/null 2>&1
  local v
  v=$(grep -A4 '"Render/3D"' "$tmp" 2>/dev/null | grep -o '"busy": [0-9.]*' | awk '{print $2}' |
      sort -n | awk '{a[NR]=$1} END {if (NR==0) print -1; else print a[int((NR+1)/2)]}')
  rm -f "$tmp"
  echo "${v:--1}"
}

measure() {
  local pid=$1 secs=$2
  [ -n "$pid" ] || { echo "measure: no qs pid" >&2; return 1; }
  [ -d "/proc/$pid" ] || { echo "measure: pid $pid gone" >&2; return 1; }

  local c0 threads perf_out csv_gpu
  c0=$(awk -F':[ \t]*' '/^voluntary_ctxt_switches|^nonvoluntary_ctxt_switches/{s+=$2} END{print s+0}' "/proc/$pid/status")
  threads=$(ls "/proc/$pid/task" | wc -l)
  csv_gpu=$(gpu_busy)

  perf_out=$(LC_ALL=C perf stat -x, -p "$pid" \
      -e task-clock,page-faults,cycles,instructions sleep "$secs" 2>&1)

  local c1 cpu_ms pf cycles instr
  c1=$(awk -F':[ \t]*' '/^voluntary_ctxt_switches|^nonvoluntary_ctxt_switches/{s+=$2} END{print s+0}' "/proc/$pid/status")
  cpu_ms=$(awk -F, '$3=="task-clock:u"{print $1}' <<<"$perf_out")
  pf=$(awk -F, '$3=="page-faults:u"{print $1}' <<<"$perf_out")
  cycles=$(awk -F, '$3=="cycles:u"{print $1}' <<<"$perf_out")
  instr=$(awk -F, '$3=="instructions:u"{print $1}' <<<"$perf_out")
  [ -n "$cpu_ms" ] || { echo "measure: perf produced no counters (perf_event_paranoid?)" >&2; return 1; }

  local rss pss dirty ipc
  rss=$(awk '/^Rss:/{print $2}' "/proc/$pid/smaps_rollup")
  pss=$(awk '/^Pss:/{print $2}' "/proc/$pid/smaps_rollup")
  dirty=$(awk '/^Private_Dirty:/{print $2}' "/proc/$pid/smaps_rollup")
  ipc=$(awk -v i="$instr" -v c="$cycles" 'BEGIN{printf "%.3f", (c>0? i/c : 0)}')

  emit "$(date +%FT%T),"$pid",$cpu_ms,$((c1-c0)),$pf,$ipc,$rss,$pss,$dirty,$threads,$csv_gpu"
}

startup() {
  pkill -x qs 2>/dev/null; sleep 1
  local t0 t1 pid
  t0=$(date +%s%N)
  nohup qs -c "$CONFIG" >/tmp/opencode/qs-startup.log 2>&1 &
  for _ in $(seq 1 $((STARTUP_SECS*10))); do
    pid=$(qs list --all 2>/dev/null | awk -v cfg="/$CONFIG/shell.qml" '
      /Process ID:/{p=$3} /Config path:/{if (index($0,cfg)) {print p; exit}}')
    [ -n "$pid" ] && break
    sleep 0.1
  done
  [ -n "${pid:-}" ] || { echo "startup: qs never registered" >&2; return 1; }
  t1=$(date +%s%N)
  emit "startup_ms=$(( (t1-t0)/1000000 )),pid=$pid,config=$CONFIG"
}

selftest() {
  local pid; pid=$(find_pid)
  local row
  row=$(measure "$pid" 3) || { echo "SELFTEST FAIL: measure returned error" >&2; return 1; }
  echo "$row"
  local n; n=$(awk -F, '{print NF}' <<<"$row")
  local ok=0
  [ "$n" -eq 11 ] || { echo "SELFTEST FAIL: $n kolom, harus 11" >&2; ok=1; }
  awk -F, '$3<=0 || $3>100000 {exit 1}' <<<"$row" || { echo "SELFTEST FAIL: task_clock_ms di luar akal" >&2; ok=1; }
  awk -F, '$8>$7 {exit 1}' <<<"$row" || { echo "SELFTEST FAIL: pss > rss" >&2; ok=1; }
  awk -F, '$11=="" {exit 1}' <<<"$row" || { echo "SELFTEST FAIL: kolom gpu kosong" >&2; ok=1; }
  awk -F, '$11==-1 {print "SELFTEST WARN: GPU tak terbaca (cap_perfmon belum dipasang) — kolom gpu = -1"}' <<<"$row"
  [ "$ok" -eq 0 ] && echo "SELFTEST PASS"
  return "$ok"
}

case "$MODE" in
  measure) measure "${PID:-$(find_pid)}" "$SECS" ;;
  startup) startup ;;
  selftest) selftest ;;
esac
