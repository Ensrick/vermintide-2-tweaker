#!/bin/sh
# usage: D6_tok.sh "<issue>|<token>" ...   prints first 2 hits (path:line) on origin/master *.lua and per-top-dir file counts
R=<repos>/vermintide-2-tweaker
for a in "$@"; do
  n="${a%%|*}"; t="${a#*|}"
  hits=$(git -C "$R" grep -n -I -F -e "$t" origin/master -- '*.lua' 2>/dev/null | sed 's/^origin\/master://')
  first=$(printf '%s\n' "$hits" | grep -v '^qa/' | head -2 | cut -d: -f1,2 | sed -E 's#scripts/mods/[a-z_]+/##' | tr '\n' ' ')
  dirs=$(printf '%s\n' "$hits" | cut -d/ -f1 | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')
  echo "#$n $t :: $first:: $dirs"
done
