# tools/harness/sweep-formats.psd1 - how tools/harness/Parse-Sweep.ps1 reads in-mod regression output (WP-H-03).
#
# Echo rows: the sweep case (qa/runtime/_rig/sweep_regression.lua) runs every /<mod>_regression_test through
# T.cmd; the driver prints each VMF echo as an evidence line OUT mod=<VMF mod name> via=echo text="<text>".
# Every runner in the tree today echoes the same row shape, "  <VERDICT>: <check>[ -- <detail>]", and a summary
# "=== <p> passed, <f> failed[, <x> xfail (known defects)][, <s> skipped] ===" (for example
# weapon_tweaker/scripts/mods/weapon_tweaker/_wt_regression.lua, chaos_wastes_tweaker_dev.lua:350-366,
# general_tweaker_dev.lua:393-415, character_weapon_variants.lua:228-249). cosmetics_tweaker and enemy_tweaker
# print the skip total on its own line. The first row whose Mod matches the VMF mod name applies; '*' is the
# default. Add a row for a mod only when its runner prints something else.
#
# Log rows: after WP-T-01 every runner prints one engine line per check, "[<prefix>:rt] <check> <VERDICT> <detail>",
# and "[<prefix>:rt] done pass=.. fail=.. skip=.. xfail=.. total=.."; those are read straight from the console log.
#
# Verdicts in sweep.json are PASS, FAIL or SKIP; the runner's own word is kept as raw. XPASS (a known defect no
# longer reproduces) and BAD-SHAPE count as FAIL, as the runners count them; XFAIL (a known defect still failing)
# counts as SKIP with its detail, so a known defect does not fail the run.
# Pure data file: no executable statements.
@{
    Formats = @(
        @{
            Mod         = '*'
            Row         = '^\s*(?<verdict>PASS|FAIL|SKIP|XFAIL|XPASS|BAD-SHAPE): (?<check>\S+)(?<rest>.*)$'
            Summary     = '^=== (?<pass>\d+) passed, (?<fail>\d+) failed(?:, (?<xfail>\d+) xfail \(known defects\))?(?:, (?<skip>\d+) skipped)? ===$'
            SkipSummary = '^=== (?<skip>\d+) skipped \(context absent\) ===$'
        }
    )
    Log = @{
        Row  = '\[(?<prefix>[A-Za-z_]+):rt\] (?<check>\S+) (?<verdict>PASS|FAIL|SKIP|XFAIL|XPASS|BADSHAPE)(?: (?<detail>[^\r\n]*))?'
        Done = '\[(?<prefix>[A-Za-z_]+):rt\] done pass=(?<pass>\d+) fail=(?<fail>\d+) skip=(?<skip>\d+) xfail=(?<xfail>\d+) total=(?<total>\d+)'
    }
    # VMF mod ids of a plan's expect_mods that have no regression suite by design; every other loaded mod must show
    # up in some suite, or Parse-Sweep.ps1 reports it as "(missing) <id>".
    NoSuite = @('VMF')
}
