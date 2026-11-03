@{
    Schema = 1
    # Prospective activation only, by a separately reviewed migration PR.
    # An enabled mod with missing allocation state MUST fail closed.
    # CWV initialization review: #724 comment 5590689291; see CLAIMS.md.
    # General's two scoped adoptions: #724 comment 6592186585. Existing
    # official .178 bytes/timestamp were preserved; Dev's .277 floor is empty.
    EnabledMods = @('character_weapon_variants', 'general_tweaker', 'general_tweaker_dev')
}
