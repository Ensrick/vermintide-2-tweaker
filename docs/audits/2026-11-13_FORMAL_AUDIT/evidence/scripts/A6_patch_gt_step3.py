# A6 round 2: wording fix for WP-GT-02 step 3 in plan/wp/GT.md (kept for provenance).
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
old = ("3. `GTD/_gt_host_lag_comp.lua`, directly after the policy is loaded (line 2): if `mod:get(\"gt_host_lag_comp_default_off_v1\") ~= true` then "
       "`mod:set(\"gt_host_lag_comp\", (Policy.migrate_default_off(mod:get(\"gt_host_lag_comp\"), false)))` and `mod:set(\"gt_host_lag_comp_default_off_v1\", true)`. "
       "No third argument on either `mod:set`.")
new = ("3. `GTD/_gt_host_lag_comp.lua`, directly after the policy is loaded (line 2), add:\n"
       "   ```lua\n"
       "   do\n"
       "       local flag = \"gt_host_lag_comp_default_off_v1\"\n"
       "       local value, done = Policy.migrate_default_off(mod:get(\"gt_host_lag_comp\"), mod:get(flag))\n"
       "       if mod:get(flag) ~= true then\n"
       "           mod:set(\"gt_host_lag_comp\", value)\n"
       "           mod:set(flag, done)\n"
       "       end\n"
       "   end\n"
       "   ```\n"
       "   No third argument on either `mod:set` (no `on_setting_changed` call is wanted here).")
assert old in s
s = s.replace(old, new)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("ok")
