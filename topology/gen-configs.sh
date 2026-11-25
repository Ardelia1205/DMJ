#!/usr/bin/env bash
# gen-configs.sh : membuat configs/leaf1.cfg, leaf2.cfg, spine1.cfg
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p configs

# kebijakan routing (dipakai leaf dan spine)
emit_policy() {
cat <<EOF
set / routing-policy prefix-set loopbacks prefix 10.0.0.0/24 mask-length-range 32..32
set / routing-policy policy export-lo statement 10 match prefix-set loopbacks
set / routing-policy policy export-lo statement 10 action policy-result accept
set / routing-policy policy accept-all default-action policy-result accept
EOF
}

# baris tambahan yang sudah terbukti (SNMP, sFlow, MTU, multihop), dari berkas opsional
# $1 = leaf atau spine
emit_extra() {
  [ -f extra-all.cfg ] && cat extra-all.cfg
  [ -f "extra-$1.cfg" ] && cat "extra-$1.cfg"
  return 0
}

# interface leaf. $1 = prefix link ke spine, $2 = loopback leaf
emit_leaf_interfaces() {
local LINK=$1 LO=$2
cat <<EOF
set / interface ethernet-1/1 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 address ${LINK}.1/30
set / interface ethernet-1/10 admin-state enable
set / interface ethernet-1/10 subinterface 0 type bridged
set / interface system0 admin-state enable
set / interface system0 subinterface 0 ipv4 admin-state enable
set / interface system0 subinterface 0 ipv4 address ${LO}/32
set / network-instance default interface ethernet-1/1.0
set / network-instance default interface system0.0
EOF
}

# BGP leaf. $1 = AS, $2 = loopback, $3 = prefix link
emit_leaf_bgp() {
local ASN=$1 LO=$2 LINK=$3
cat <<EOF
set / network-instance default protocols bgp admin-state enable
set / network-instance default protocols bgp autonomous-system ${ASN}
set / network-instance default protocols bgp router-id ${LO}
set / network-instance default protocols bgp afi-safi ipv4-unicast admin-state enable
set / network-instance default protocols bgp group underlay peer-as 65000
set / network-instance default protocols bgp group underlay export-policy export-lo
set / network-instance default protocols bgp group underlay import-policy accept-all
set / network-instance default protocols bgp neighbor ${LINK}.2 peer-group underlay
set / network-instance default protocols bgp group overlay peer-as 65000
set / network-instance default protocols bgp group overlay afi-safi evpn admin-state enable
set / network-instance default protocols bgp group overlay afi-safi ipv4-unicast admin-state disable
set / network-instance default protocols bgp group overlay transport local-address ${LO}
set / network-instance default protocols bgp neighbor 10.0.0.100 peer-group overlay
EOF
}

# VXLAN dan MAC-VRF (sama untuk kedua leaf)
emit_leaf_vxlan_macvrf() {
cat <<EOF
set / tunnel-interface vxlan1 vxlan-interface 1 type bridged ingress vni 1000
set / network-instance mac-vrf-1 type mac-vrf
set / network-instance mac-vrf-1 admin-state enable
set / network-instance mac-vrf-1 interface ethernet-1/10.0
set / network-instance mac-vrf-1 vxlan-interface vxlan1.1
set / network-instance mac-vrf-1 protocols bgp-evpn bgp-instance 1 admin-state enable
set / network-instance mac-vrf-1 protocols bgp-evpn bgp-instance 1 vxlan-interface vxlan1.1
set / network-instance mac-vrf-1 protocols bgp-evpn bgp-instance 1 evi 111
set / network-instance mac-vrf-1 protocols bgp-vpn bgp-instance 1 route-target export-rt target:100:111
set / network-instance mac-vrf-1 protocols bgp-vpn bgp-instance 1 route-target import-rt target:100:111
EOF
}

# perakit leaf. $1 = nama, $2 = AS, $3 = loopback, $4 = prefix link
gen_leaf() {
local NAME=$1 ASN=$2 LO=$3 LINK=$4
{
  emit_leaf_interfaces "$LINK" "$LO"
  emit_policy
  emit_leaf_bgp "$ASN" "$LO" "$LINK"
  emit_leaf_vxlan_macvrf
  emit_extra leaf
} > configs/${NAME}.cfg
}

# spine: tanpa MAC-VRF dan tanpa port client
gen_spine() {
{
cat <<EOF
set / interface ethernet-1/1 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/1 subinterface 0 ipv4 address 192.168.11.2/30
set / interface ethernet-1/2 admin-state enable
set / interface ethernet-1/2 subinterface 0 ipv4 admin-state enable
set / interface ethernet-1/2 subinterface 0 ipv4 address 192.168.12.2/30
set / interface system0 admin-state enable
set / interface system0 subinterface 0 ipv4 admin-state enable
set / interface system0 subinterface 0 ipv4 address 10.0.0.100/32
set / network-instance default interface ethernet-1/1.0
set / network-instance default interface ethernet-1/2.0
set / network-instance default interface system0.0
EOF
emit_policy
cat <<EOF
set / network-instance default protocols bgp admin-state enable
set / network-instance default protocols bgp autonomous-system 65000
set / network-instance default protocols bgp router-id 10.0.0.100
set / network-instance default protocols bgp afi-safi ipv4-unicast admin-state enable
set / network-instance default protocols bgp group underlay export-policy export-lo
set / network-instance default protocols bgp group underlay import-policy accept-all
set / network-instance default protocols bgp neighbor 192.168.11.1 peer-group underlay
set / network-instance default protocols bgp neighbor 192.168.11.1 peer-as 65001
set / network-instance default protocols bgp neighbor 192.168.12.1 peer-group underlay
set / network-instance default protocols bgp neighbor 192.168.12.1 peer-as 65002
set / network-instance default protocols bgp group overlay afi-safi evpn admin-state enable
set / network-instance default protocols bgp group overlay afi-safi ipv4-unicast admin-state disable
set / network-instance default protocols bgp group overlay transport local-address 10.0.0.100
set / network-instance default protocols bgp neighbor 10.0.0.1 peer-group overlay
set / network-instance default protocols bgp neighbor 10.0.0.1 peer-as 65001
set / network-instance default protocols bgp neighbor 10.0.0.2 peer-group overlay
set / network-instance default protocols bgp neighbor 10.0.0.2 peer-as 65002
EOF
emit_extra spine
} > configs/spine1.cfg
}

gen_leaf leaf1 65001 10.0.0.1 192.168.11
gen_leaf leaf2 65002 10.0.0.2 192.168.12
gen_spine
echo "Selesai:"; wc -l configs/*.cfg
