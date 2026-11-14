#!/bin/sh
# D4 patch-day canary 2: static check for #1686-class bugs. Lists literal `icon = "<name>"` values in a mod
# that have no entry in the decompiled gui_icons_atlas.lua. Read-only.
# Usage: sh D4_icon_atlas_check.sh <mod_dir>      (default career_tweaker)
# Paths: VT2_REPO_ROOT and VT2_DECOMPILE_ROOT override the defaults. Exit code 1 when a name is missing.
# Blind spot: icons built at run time or reused from vanilla tables by reference are not seen.
REPO=${VT2_REPO_ROOT:-$HOME/source/repos/vermintide-2-tweaker}
ATLAS=${VT2_DECOMPILE_ROOT:-$HOME/source/repos/Vermintide-2-Source-Code}/scripts/ui/atlas_settings/gui_icons_atlas.lua
MOD=${1:-career_tweaker}
[ -f "$ATLAS" ] || { echo "ERROR: atlas file not found: $ATLAS"; exit 2; }
NAMES=$(grep -rhoE "icon *= *\"[a-z0-9_]+\"" "$REPO/$MOD/scripts" | sed 's/.*"\(.*\)"/\1/' | sort -u)
MISSING=0
for k in $NAMES; do
  c=$(grep -c "\b$k = {" "$ATLAS")
  if [ "$c" = "0" ]; then echo "MISSING-IN-ATLAS: $k"; MISSING=$((MISSING+1)); fi
done
echo "checked $(echo "$NAMES" | grep -c .) distinct icon literals in $MOD, $MISSING missing"
[ "$MISSING" = "0" ]
