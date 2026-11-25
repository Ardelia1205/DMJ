#!/usr/bin/env bash
# cek-tahap3.sh : pemeriksaan cepat Tahap 3 tanpa masuk ke router
CLI() { docker exec "clab-telemetry-$1" sr_cli "$2" 2>&1; }
for n in spine1 leaf1 leaf2; do
  echo "=== $n : BGP neighbor ==="
  CLI $n "show network-instance default protocols bgp neighbor" | grep -Ei "peer|established|idle|active|connect" | head -20
done
echo "=== leaf1 : ringkasan rute EVPN ==="
CLI leaf1 "show network-instance default protocols bgp routes evpn route-type summary"
echo "=== ping client1 ke client2 ==="
docker exec clab-telemetry-client1 ping -c 3 -W 2 192.168.100.2 | tail -3
echo "=== ping MTU 9000 (-s 8972) ==="
docker exec clab-telemetry-client1 ping -M do -s 8972 -c 3 -W 2 192.168.100.2 | tail -3
