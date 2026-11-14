#!/usr/bin/env bash
# A1: read-only drift measurement between weapon_tweaker and weapon_tweaker_dev.
# Normalises the namespace (weapon_tweaker_dev -> weapon_tweaker, wt_dev -> wt) and reports
# per-file added/removed line counts, plus lines inside WT_DEV_OVERLAY blocks.
R=<repos>/vermintide-2-tweaker
A=$R/weapon_tweaker/scripts/mods/weapon_tweaker
B=$R/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev
printf '%-48s %7s %7s %7s %7s %8s\n' file pubLOC devLOC +dev -dev overlayL
for f in "$A"/*.lua; do
  n=$(basename "$f")
  d="$B/$(echo "$n" | sed 's/^weapon_tweaker\(_data\|_localization\)\?\.lua$/weapon_tweaker_dev\1.lua/')"
  [ -f "$d" ] || d="$B/$n"
  [ -f "$d" ] || { printf '%-48s MISSING-IN-DEV\n' "$n"; continue; }
  norm() { sed -e 's/weapon_tweaker_dev/weapon_tweaker/g' -e 's/wt_dev/wt/g' -e 's/\r$//' "$1"; }
  plus=$(diff <(sed 's/\r$//' "$f") <(norm "$d") | grep -c '^>')
  minus=$(diff <(sed 's/\r$//' "$f") <(norm "$d") | grep -c '^<')
  ov=$(awk '/WT_DEV_OVERLAY_BEGIN/{o=1} o{c++} /WT_DEV_OVERLAY_END/{o=0} END{print c+0}' "$d")
  if [ "$plus" != 0 ] || [ "$minus" != 0 ]; then
    printf '%-48s %7s %7s %7s %7s %8s\n' "$n" "$(wc -l <"$f")" "$(wc -l <"$d")" "$plus" "$minus" "$ov"
  fi
done
