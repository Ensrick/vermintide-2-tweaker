p='findings/A2.md'; s=open(p,encoding='utf-8').read()
def rep(a,b,count=1):
    global s
    assert s.count(a)>=1, 'missing: '+a[:70]
    s=s.replace(a,b) if count==0 else s.replace(a,b,count)
rep("| tracked files / Lua files / Lua lines | 357 / 130 / 47,280 | 80 (approx) / 30 / 10,119 |","| tracked files / Lua files / Lua lines | 357 / 130 / 47,280 | 92 / 30 / 10,119 |")
rep("| `mod:hook` / `mod:hook_safe` (literal) | 81 / 19 (+1 via `hook_mod:hook` in `_cwv_husk_path.lua:1376`) = 101 hooks on 101 distinct targets | 43 / 4 = 47 |",
    "| `mod:hook` / `mod:hook_safe` | 81 / 19 (+1 via `hook_mod:hook` in `_cwv_husk_path.lua:1376`) = 101 hooks on 101 distinct targets | 46 real call sites (a 47th textual match is a string inside a check, `weapons_of_chaos.lua:1240`); 5 of them sit in a per-class installer run for 2 classes, so 55 registrations at runtime |")
rep("| settings widgets (user-facing) | 6 (+ dev anim-picker tree) | see section 3 |","| settings widgets (user-facing) | 6 (+ dev anim-picker tree) | 8 (1 checkbox, 7 dropdowns) |")
rep("| CHANGELOG version headings | 485 (0.1.570-dev) | see section 2 |","| CHANGELOG version headings | 485 (0.1.570-dev) | 59 (0.1.62-dev) |")
rep("and nine `NetworkLookup` tables: `item_names`","and eight `NetworkLookup` tables: `item_names`")
rep("`Weapons` (about 20 new templates, plus","`Weapons` (new templates, plus")
rep("**Hook surface.** 47 hooks on 47 targets. 16 are previewer hooks in `_woc_mod_unit_preview.lua`, 13 are Chaos Wastes / backend hooks in the registration owner.",
    "**Hook surface.** 46 hook call sites in source, 55 registrations at runtime (seven previewer hooks are installed once for `HeroPreviewer` and once for `MenuWorldPreviewer`, `_woc_mod_unit_preview.lua:390-442`). 16 call sites are previewer hooks, 13 are Chaos Wastes / backend hooks in the registration owner.")
rep("CONFIRMED with a caveat: 15 of 24 vanilla paths are in `Vermintide-2-Source-Code/scripts/network_lookup/inventory_package_list.lua`; the other 9 exist only in DLC equipment settings",
    "CONFIRMED for the 24 literal vanilla paths in the catalog, with a caveat: 16 are in `Vermintide-2-Source-Code/scripts/network_lookup/inventory_package_list.lua`; the other 8 exist only in DLC equipment settings")
rep("| 14 | All 47 WOC hook targets and the 24 cwv hook targets sampled exist with the hooked names |","| 14 | The 24 WOC hook targets and 24 cwv hook targets sampled exist with the hooked names |")
rep("26 rows name a template that cwv builds in code.","26 rows override the template, most with one that cwv builds in code.")
a="""**Impact.** Whether the second application is harmless depends on `_cwv_spawn_item_post` being idempotent, which I did not establish [unverified]. Preview transform and scale bugs are a standing cluster (#237, #692, #747). Confirmation: with debug logging on, one inventory preview spawn prints both `[cwv preview hook] HeroPreviewer._spawn_item fired` and `MenuWorldPreviewer._spawn_item fired`."""
b="""The same pairing exists for `_update_units_visibility` (`_cwv_old_musket_preview_pose.lua:355-356`; the child calls the parent at `menu_world_previewer.lua:320`) and in WOC for `_spawn_item` (`_woc_mod_unit_preview.lua:384-385`) and for `post_update`, `clear_units` and `on_exit` through `install_animation_hooks` run for both classes (`:390-442`; the child calls the parent at `menu_world_previewer.lua:300,738,221`).

**Impact.** Whether the second application is harmless depends on each handler being idempotent, which I did not establish [unverified]. Preview transform and scale bugs are a standing cluster (#237, #692, #712, #747). Confirmation: with debug logging on, one inventory preview spawn prints both `[cwv preview hook] HeroPreviewer._spawn_item fired` and `MenuWorldPreviewer._spawn_item fired`."""
rep(a,b)
rep("### A2-F15 | S2 | correctness | Preview spawn work runs twice for the inventory previewer","### A2-F15 | S2 | correctness | Preview hooks on a class and its parent run twice for the inventory previewer (cwv and WOC)")
rep("**Recommendation.** Hook only the parent, or mark the spawn data as processed and return early on re-entry.","**Recommendation.** Hook only the parent class for methods the child delegates, or set a re-entry flag on `self` for the duration of the outer call.")
open(p,'w',encoding='utf-8',newline='\n').write(s); print('patched')
