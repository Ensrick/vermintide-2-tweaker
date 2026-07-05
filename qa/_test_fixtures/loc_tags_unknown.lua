-- Fixture for check_loc_tags.ps1 -SelfTest.
-- A DEV build with UNKNOWN-vocab typos and MUTEX combos, plus uppercase
-- decoys that must be ignored. Scanned as dev -> unknown=4, mutex=2, leak=0.
return {
    -- Unknown vocabulary (tag-like lowercase/Issue-leading, not sanctioned):
    u1 = { en = "[confirmed working] Uniform" }, -- should be [working]
    u2 = { en = "[fixed] Victor" },              -- invented tag
    u3 = { en = "[issue 5] Whiskey" },           -- lowercase 'i' — casing matters
    u4 = { en = "[untest] Xray" },               -- typo of [untested]

    -- Uppercase category prefixes — legitimate display names, NOT flagged:
    ok1 = { en = "[CW] Yankee" },
    ok2 = { en = "[Big Rebalance] Zulu" },
    ok3 = { en = "[WARNING] Caution text" },

    -- Mutually-exclusive tag combos (crash/working/untested):
    mx1 = { en = "[untested] [working] Mutex one" },
    mx2 = { en = "[crash] [untested] Mutex two" },
}
