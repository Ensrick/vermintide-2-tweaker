@{
    Schema = 1
    # Prospective activation only, by a separately reviewed migration PR.
    # An enabled mod with missing allocation state MUST fail closed.
    # CWV initialization review: #724 comment 5590689291; see CLAIMS.md.
    # General's two scoped adoptions: #724 comment 6592186585. Existing
    # official .178 bytes/timestamp were preserved; Dev's .277 floor is empty.
    # Official CT/CIM adoption: #724 comment 6677449320; both ledgers were
    # initialized before this activation. CIM Dev remains unactivated.
    # MP and the WT beta/Dev pair: #724 comment 6814671590. Exact stale
    # claims were adopted from reviewed 883c6025 without timestamp renewal;
    # these three ledgers were initialized before this source activation.
    EnabledMods = @('character_weapon_variants', 'general_tweaker', 'general_tweaker_dev', 'chaos_wastes_tweaker', 'crafting_in_modded', 'modded_progression', 'weapon_tweaker', 'weapon_tweaker_dev')
}
