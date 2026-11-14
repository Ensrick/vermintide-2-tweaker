#!/usr/bin/env bash
# A7: gui_tweaker_dev vs gui_tweaker drift, identity-normalized (read-only).
R=<repos>/vermintide-2-tweaker
D=$R/gui_tweaker_dev/scripts/mods/gui_tweaker_dev; S=$R/gui_tweaker/scripts/mods/gui_tweaker
norm() { sed -e 's/\r$//' -e 's/gui_tweaker_dev/gui_tweaker/g' -e 's/gut_dev/gut/g' "$1"; }
echo "== only in dev"; comm -23 <(cd $D && find . -name '*.lua' | sed 's/gui_tweaker_dev/gui_tweaker/g' | sort) <(cd $S && find . -name '*.lua' | sort)
echo "== only in stable"; comm -13 <(cd $D && find . -name '*.lua' | sed 's/gui_tweaker_dev/gui_tweaker/g' | sort) <(cd $S && find . -name '*.lua' | sort)
echo "== common files differing (changed lines, file)"
for f in $(cd $S && find . -name '*.lua' | sort); do
  df=$(echo "$f" | sed 's/gui_tweaker/gui_tweaker_dev/g'); [ -f "$D/$df" ] || continue
  n=$(diff <(norm "$D/$df") <(sed 's/\r$//' "$S/$f") | grep -c '^[<>]'); [ "$n" -gt 0 ] && echo "$n $f"
done | sort -rn
