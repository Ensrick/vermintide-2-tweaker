std = "lua51"
max_line_length = 200

globals = {
    "get_mod",
    "mod",
    "Localize",
    "ItemMasterList",
    "Weapons",
    "CareerSettings",
    "ActionTemplates",
    "SPProfiles",
    "TalentTrees",
    "Managers",
    "Unit",
    "Vector3",
    "ScriptUnit",
    "Development",
    "CharacterStateHelper",
    "PlayerUnitFirstPerson",
    "CameraSettings",
    "ItemGridUI",
    "GearUtils",
    "HashUtils",
    "LevelHelper",
    "Pickups",
    "DeusWeapons",
    "DeusPowerUpTemplates",
    "MutatorTemplates",
    "DEUS_CHEST_TYPES",
    "DLCUtils",
    "InventorySettings",
    "IngameUI",
}

read_globals = {
    "rawget",
    "unpack",
    "pcall",
    "pairs",
    "ipairs",
    "type",
    "tostring",
    "math",
    "string",
    "table",
}

exclude_files = {
    "tweaker/**",
    ".build/**",
    "upload/**",
}
