#!/usr/bin/env bash
# Tangkapan + cek visual qs. Dua hal, sengaja dipisah:
#   --sane    : gagal kalau area yang digambar qs kosong/rata (render rusak)
#   --compare : menghasilkan diff_pct + gambar diff sebagai BUKTI untuk dilihat
#               manusia; tidak lulus/gagal sendiri.
# ponytail: oracle piksel penuh untuk desktop hidup = noise (jam, grafik, preview
# live, jendela user). Yang diotomasi hanya yang bisa dipastikan: render kosong.
set -uo pipefail

SCEN=""; TAG=""; OUT=""; BASE=""; AFTER=""; MODE="shot"; MON=${MON:-eDP-1}
MASKS=$(dirname "$0")/masks.conf

while [ $# -gt 0 ]; do
  case "$1" in
    --scenario) SCEN=$2; shift 2 ;;
    --tag) TAG=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --baseline) BASE=$2; shift 2 ;;
    --after) AFTER=$2; shift 2 ;;
    --sane) MODE=sane; shift ;;
    --compare) MODE=compare; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Area yang digambar qs sendiri per skenario: "x,y,w,h". S1 hanya bar;
# S2/S3/S5 overlay penuh.
region() {
  case "$1" in
    S1) echo "0,0,1920,42" ;;
    *)  echo "0,0,1920,1080" ;;
  esac
}

shot() {
  [ -n "$SCEN" ] && [ -n "$TAG" ] && [ -n "$OUT" ] || { echo "shot: butuh --scenario --tag --out" >&2; return 2; }
  mkdir -p "$OUT"
  grim -o "$MON" "$OUT/$SCEN-$TAG.png" || return 1
  echo "$OUT/$SCEN-$TAG.png"
}

sane() {
  local img=$1 r x y w h
  [ -f "$img" ] || { echo "sane: no such image $img" >&2; return 1; }
  r=$(region "$SCEN"); IFS=, read -r x y w h <<<"$r"
  local sd
  sd=$(magick "$img" -crop "${w}x${h}+${x}+${y}" +repage -colorspace Gray \
        -format "%[fx:standard_deviation]" info: 2>/dev/null)
  [ -n "$sd" ] || { echo "sane: magick failed" >&2; return 1; }
  echo "scenario=$SCEN region=${w}x${h}+${x}+${y} stddev=$sd"
  awk -v s="$sd" 'BEGIN{exit !(s>0.02)}' || { echo "SANE FAIL: area qs nyaris rata (render kosong?)" >&2; return 1; }
  echo "SANE PASS"
}

compare() {
  [ -n "$BASE" ] && [ -n "$AFTER" ] && [ -n "$SCEN" ] || { echo "compare: butuh --baseline --after --scenario" >&2; return 2; }
  local a="$BASE/$SCEN-baseline.png" b="$AFTER/$SCEN-after.png"
  [ -f "$a" ] && [ -f "$b" ] || { echo "compare: butuh $SCEN-baseline.png dan $SCEN-after.png" >&2; return 2; }
  local tmp; tmp=$(mktemp -d)
  local draw=""
  [ -f "$MASKS" ] && draw=$(awk -F, '$1!~/^#/ && NF>=4 {printf " -draw \"rectangle %s,%s %s,%s\"", $1,$2,$1+$3,$2+$4}' "$MASKS")
  eval magick "\"$a\"" $draw "\"$tmp/a.png\"" 2>/dev/null || cp "$a" "$tmp/a.png"
  eval magick "\"$b\"" $draw "\"$tmp/b.png\"" 2>/dev/null || cp "$b" "$tmp/b.png"
  local ae total pct
  ae=$(magick compare -metric AE "$tmp/a.png" "$tmp/b.png" null: 2>&1 | tr -d '\r')
  total=$(magick identify -format "%[fx:w*h]" "$tmp/b.png")
  pct=$(awk -v e="${ae%%.*}" -v t="$total" 'BEGIN{printf "%.4f", (t>0? e*100/t : 0)}')
  mkdir -p "$AFTER"; magick compare "$tmp/a.png" "$tmp/b.png" "$AFTER/diff-$SCEN.png" 2>/dev/null
  rm -rf "$tmp"
  echo "diff_pct=$pct diff_image=$AFTER/diff-$SCEN.png (bukti, bukan gerbang)"
}

case "$MODE" in
  shot) shot ;;
  sane) sane "${OUT:-/dev/null}/${SCEN}-${TAG:-baseline}.png" ;;
  compare) compare ;;
esac
