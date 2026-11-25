#!/usr/bin/env bash
# traffic-runner.sh <label> [durasi_detik] [jumlah_ulangan] [jeda_detik]
# Contoh: ./traffic-runner.sh pilot 60 3 15
set -uo pipefail

LABEL=${1:?label wajib, mis. pilot atau skenario1}
DUR=${2:-300}
REPS=${3:-1}
GAP=${4:-30}

BITRATE=25M
PKT=8000
SRC=clab-telemetry-client1
DST=clab-telemetry-client2
DST_IP=192.168.100.2
OUT="$HOME/repro/data/traffic/${LABEL}"
mkdir -p "$OUT"

start_server() {
  docker exec "$DST" pkill iperf3 2>/dev/null || true
  sleep 1
  docker exec -d "$DST" iperf3 -s
  sleep 2
}

preflight() {
  for c in "$SRC" "$DST"; do
    [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ] \
      || { echo "[ERR] container $c tidak berjalan"; exit 1; }
  done
  docker exec "$SRC" ping -c 2 -W 2 "$DST_IP" >/dev/null \
    || { echo "[ERR] ping $DST_IP gagal (cek Tahap 3)"; exit 1; }
}

preflight
{
  echo "label=$LABEL durasi=$DUR ulangan=$REPS bitrate=$BITRATE payload=$PKT"
  echo "mulai=$(date -Is)"
} | tee "$OUT/meta.txt"

for i in $(seq 1 "$REPS"); do
  F="$OUT/run${i}.json"
  ok=0
  for try in 1 2 3; do
    start_server
    echo "[$(date -Is)] run $i/$REPS percobaan $try" | tee -a "$OUT/log.txt"
    docker exec "$SRC" iperf3 -c "$DST_IP" -u -b "$BITRATE" -l "$PKT" \
        -t "$DUR" -i 1 --json > "$F" 2>>"$OUT/log.txt"
    if jq -e '.end.sum.bits_per_second' "$F" >/dev/null 2>&1; then ok=1; break; fi
    echo "[WARN] run $i gagal, ulangi" | tee -a "$OUT/log.txt"
    sleep 5
  done
  [ "$ok" = 1 ] || { echo "[ERR] run $i gagal 3 kali"; exit 2; }
  [ "$i" -lt "$REPS" ] && sleep "$GAP"
done

docker exec "$DST" pkill iperf3 2>/dev/null || true
echo "selesai=$(date -Is)" | tee -a "$OUT/meta.txt"

echo "run,mbps_sender,loss_persen,jitter_ms" > "$OUT/ringkasan.csv"
for f in "$OUT"/run*.json; do
  jq -r '[input_filename, (.end.sum.bits_per_second/1e6), .end.sum.lost_percent, .end.sum.jitter_ms] | @csv' "$f" \
    >> "$OUT/ringkasan.csv"
done
cat "$OUT/ringkasan.csv"
