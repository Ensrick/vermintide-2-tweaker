-- Fixture for check_loc_tags.ps1 -SelfTest.
-- A DEV build with all-VALID sanctioned tags (incl. the two weapon_tweaker-only
-- extensions from LOCALIZATION_STANDARD.md § 13.8), plus decoys that must NOT be
-- flagged. Scanned as dev -> 0 findings. Scanned as STABLE -> 12 leaks (one per
-- sanctioned-tag-bearing entry below).
return {
    a_setting     = { en = "[untested] Alpha" },
    b_setting     = { en = "[Issue 491] Bravo" },
    c_setting     = { en = "[working] Charlie" },
    d_setting     = { en = "[verify-fix] [Issue 491] Delta" },
    e_setting     = { en = "[needs animations] Echo" },
    f_setting     = { en = "[diag] Foxtrot" },
    g_setting     = { en = "[Issue 501, 427 & 418] Golf" },
    i_setting     = en("[untested] India"),
    j_setting     = { en = "[needs offsets] Juliett" },                 -- wt-only (§ 13.8)
    k_setting     = { en = "[needs animations → Greathammer] Kilo" },   -- wt-only variant (§ 13.8)
    l_setting     = { en = "[Issue 321] Lima" },                        -- inert-block hand tag (§ 13.8)

    -- Decoys — must NOT be flagged:
    h_setting     = { en = "[CW] Hotel" },              -- uppercase category prefix, not a tag
    plain_setting = { en = "Just a plain label" },      -- no leading bracket
    angle_setting = { en = "<gut_key> marker" },        -- gut angle marker, not a square bracket
    mutex_label   = { en = "[working]     (A) Aegis" }, -- tag + mutex-cluster label (single tag = fine)
}
