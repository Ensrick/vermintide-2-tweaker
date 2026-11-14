#!/usr/bin/env bash
# A7 read-only surface measurement for gui_tweaker_dev. Usage: A7_surface.sh <mod_dir_name>
REPO=<repos>/vermintide-2-tweaker
M=${1:-gui_tweaker_dev}
D="$REPO/$M/scripts/mods/$M"
cd "$D" || exit 1
echo "== files / LOC"; find . -name '*.lua' | wc -l; cat $(find . -name '*.lua') | wc -l
for pat in 'mod:hook(' 'mod:hook_safe(' 'mod:hook_origin(' 'mod:hook_disable(' 'mod:hook_enable(' 'mod:command(' 'mod:network_register(' 'mod:network_send(' 'mod:set(' 'mod:get(' 'pcall(' 'xpcall(' 'get_mod(' 'rawset(' '_rt_register(' 'mod:dofile(' 'mod:io_dofile(' 'dofile(' 'printf(' 'mod:echo(' 'mod:info(' 'mod:persistent_table(' 'Managers.save' 'vmf:set(' 'Application.set_user_setting' 'Application.save_user_settings'; do
  n=$(grep -rF --include='*.lua' -- "$pat" . | grep -v '^\s*--' | wc -l)
  printf '%-36s %s\n' "$pat" "$n"
done
echo "== per-file hook counts (hook+hook_safe+hook_origin)"
grep -rcE --include='*.lua' 'mod:hook(_safe|_origin)?\(' . | grep -v ':0$' | sort -t: -k2 -nr
