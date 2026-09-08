@{
    Schema = 1
    # Prospective activation only, by a separately reviewed migration PR.
    # An enabled mod with missing allocation state MUST fail closed.
    # CWV initialization review: #724 comment 5590689291; see CLAIMS.md.
    EnabledMods = @('character_weapon_variants')
}
