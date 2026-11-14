#!/usr/bin/env bash
# A6: engine contact surface counts per Lua file for a mod script dir. Usage: A6_surface.sh <dir>
cd "$1" || exit 1
printf "%-46s %5s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n" file loc hook safe orig cmd nreg nsend upd pcall mget mset
for f in *.lua; do
  loc=$(wc -l < "$f")
  h=$(grep -c 'mod:hook(' "$f"); hs=$(grep -c 'mod:hook_safe(' "$f"); ho=$(grep -c 'mod:hook_origin(' "$f")
  c=$(grep -c 'mod:command(' "$f"); nr=$(grep -c 'mod:network_register(' "$f"); ns=$(grep -c 'network_send(' "$f")
  u=$(grep -c '_gt_register_update(\|_register_update(' "$f"); p=$(grep -o 'pcall(' "$f" | wc -l)
  mg=$(grep -o 'mod:get(' "$f" | wc -l); ms=$(grep -o 'mod:set(' "$f" | wc -l)
  printf "%-46s %5d %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d\n" "$f" $loc $h $hs $ho $c $nr $ns $u $p $mg $ms
done
