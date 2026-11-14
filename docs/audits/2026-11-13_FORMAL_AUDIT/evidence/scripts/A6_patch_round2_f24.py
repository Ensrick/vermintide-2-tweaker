# A6 round 2: append finding F24 to findings/A6.md (kept for provenance).
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
anchor = "## 5. Dev vs stable drift"
add = (
"### A6-F24 | S1 | correctness | Round 2 addition: `/ai` and AFK takeover set the option without notifying, so the swap never starts\n"
"- Evidence: the `/ai` command body is `mod:set(\"ai_takeover_enabled\", not mod:get(\"ai_takeover_enabled\"))` with no third argument (`GTD/_gt_ai_takeover.lua:664-670`); "
"its comment says the set \"fires on_setting_changed\". VMF only raises the setting-changed event when the third argument `notify_mod` is truthy "
"(`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:46-61`; the decompiled Workshop copy agrees, "
"`misc-vermintide-mods/Vermintide Mod Framework/scripts/mods/vmf/modules/core/settings.lua:27-40`). The swap is only started from the "
"`on_setting_changed` branch (`MAIN:640-656`). The AFK driver has the same shape and says so in a comment: \"we WANT on_setting_changed to fire\" "
"(`GTD/_gt_ai_takeover.lua:814-818`, end paths `:782`, `:835`). Other commands in the mod know about this and apply explicitly after `mod:set` "
"(`MAIN:790-795`, `GTD/_gt_noclip.lua:317-324`, `GTD/_gt_bots_keep.lua:427-431`). `/bots_in_keep` has the same gap for its OFF path "
"(`GTD/_gt_bots_keep.lua:370-372`; the clear only runs from `MAIN:657-670`). The public tree has identical lines (`GTS/_gt_ai_takeover.lua:669,818,835`, `GTS/_gt_bots_keep.lua:339`).\n"
"- Impact: static evidence suggests AI takeover works only from the options checkbox, not from `/ai` and not from the AFK timer. This is issue #247 (`verify-fix`, 1-major).\n"
"- Recommendation: pass `true` as the third argument at those four `mod:set` calls, or call `mod._gt_ai_handle_toggle_change` directly. Work package `plan/wp/GT.md` WP-GT-04.\n"
"- Confirm (R): host in a mission runs `/ai`; pass = `mod._gt_ai_saved_state` gains one entry within 10 s.\n"
"- Counts after this addition: S0 = 0, S1 = 8, S2 = 11, S3 = 5.\n\n"
)
assert anchor in s and "A6-F24" not in s
s = s.replace(anchor, add + anchor, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("ok")
