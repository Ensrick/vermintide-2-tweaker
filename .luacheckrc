-- .luacheckrc — luacheck config for the VT2 Tweaker monorepo.
-- See qa/CHECKS.md for which bug classes this catches.
-- See qa/README.md for install + usage.
--
-- Run from repo root: luacheck . --no-config-default
-- Or via the master entry: .\qa\run_all.ps1

-- Allow wide comments / BBCode blocks in localization
max_line_length = 220

-- Don't scan vendored / external / build-output dirs
exclude_files = {
    "Vermintide-2-Source-Code/",
    "_archive/",
    "_big_rebalance_extract/",
    "misc-vermintide-mods/",
    "tools/vmb-launcher/bin/",
    "tools/vmb-launcher/obj/",
    "tools/vmb-launcher/.vs/",
    "tools/publish-release/",
    ".release-stage/",
    "*/bundleV2/",
    "*/.build/",
    "*/upload/",
    "*.lua.processed",
    "tweaker/",  -- legacy SDK mod, frozen
}

-- VT2 / Stingray engine globals (read-only — mods consume, don't define)
read_globals = {
    -- VMF mod handle accessors
    "get_mod",
    "new_mod",

    -- Stingray engine + plugins
    "Application", "World", "Unit", "Mesh", "Material", "Light", "Actor",
    "ScriptUnit", "ScriptApplication", "ScriptWorld", "Script", "ScriptBackendItem",
    "Vector3", "Vector3Box", "Vector2", "Quaternion", "QuaternionBox",
    "Matrix4x4", "Matrix4x4Box", "Color",
    "Network", "GameSession",
    "WorldUtils", "PhysicsWorld",
    "Localize",
    "Profiler",
    "Mouse", "Keyboard",
    "Math",
    "Wwise",
    "AssetLoader",
    "Gui",
    "Camera",
    "Viewport",
    "ShadingEnvironment",
    "Boot",
    "Development",
    "Crashify",
    "cjson",       -- compiled lua plugin (always present)
    "bit",         -- LuaJIT bit library
    "Steam",
    "Imgui",

    -- VT2 Managers + utilities (read-only)
    "Managers",
    "ALIVE", "HEALTH_ALIVE",
    "POSITION_LOOKUP", "BLACKBOARDS",
    "LevelHelper", "LevelResource", "LevelSettings", "DEUS_LEVEL_SETTINGS", "DEUS_MAP_POPULATE_SETTINGS",
    "UISettings", "UIRenderer", "UIAtlasHelper", "UIPasses", "UIFontByResolution",
    "UIWidget", "UIWidgetUtils", "UIBackgroundFrameTextures",
    "Items", "ItemGridUI",
    "WeaponSkins", "Weapons", "WeaponTraits", "WeaponTweakTemplates",
    "Trinkets",
    "CareerSettings", "SPProfiles", "TalentTrees", "Talents", "TalentIDLookup",
    "ActivatedAbilitySettings", "PassiveAbilitySettings",
    "BackendUtils", "BackendInterfaceItemPlayfab", "BackendInterfaceLiveEventsPlayfab",
    "BackendInterfaceVersusPlayfab", "BackendManagerPlayFab", "BackendInterfaceCraftingPlayfab",
    "BuffSettings", "buff_templates",  -- lowercase alias appears in some BR code
    "DeusPowerUpBuffTemplates", "DeusPowerUpsArray",
    "DeusPowerUpsArrayByRarity", "DeusPowerUpsLookup", "DeusPowerUps",
    "DeusPowerUpRarityPool", "DeusPowerUpUtils",
    "DeusSoftCurrencySettings",
    "DeusWeapons",
    "DEUS_CHEST_TYPES",
    "DLCSettings", "DLCUtils",
    "InventorySettings", "IngameUI",
    "PickupSettings", "Pickups", "AllPickups",
    "PackSpawningSettings",
    "AttachmentUtils",
    "DamageUtils",
    "AiUtils",
    "GearUtils", "GearUtilsCommon",
    "HashUtils",
    "AttachmentNodeLinking",
    "BreedActions",
    "Breeds", "BreedPackSizes",
    "ConflictDirector", "ConflictUtils",
    "RollProbability",
    "LoadedDice",
    "MorrisBuffTweakData", "MorrisBuffSettings",
    "UIUtils",
    "CosmeticUtils",
    "LoadoutUtils",
    "PowerLevelFromLevelSettings", "PowerLevelTemplates",
    "InteractionHelper",
    "AchievementTemplates", "AchievementCategories", "AchievementManager",
    "FrameSettings",
    "ActionTemplates", "ActionUtils",
    "ActionFlamethrower", "ActionBeam", "ActionTrueFlightBow",
    "CharacterStateHelper", "PlayerUnitFirstPerson", "PlayerUnitStatusSettings",
    "CameraSettings",
    "AttackTemplates", "TrueFlightTemplates", "SpreadTemplates",
    "LightWeightProjectiles",
    "DefaultArmorPowerModifier",
    "MeleeBuffTypes",
    "ProcFunctions",
    "StatBuffApplicationMethods", "NewStatBuffApplicationMethods",
    "CurrentHordeSettings", "SpecialsPacing",
    "HordeSpawner", "TerrorEventUtils", "TerrorEventMixer", "TerrorEventBlueprints",
    "BTSpawnAllies", "BTConditions", "BTSelector", "BTSequence", "BTAction",
    "Boons",
    "MutatorHandler",
    "FlowCallbacks",
    "DialogueSystem",
    "FlowEvent",
    "AssistedRespawnSettings",
    "EnemySettings",
    "GameModeSettings", "GameMode", "GameModeManager",
    "ProfileSynchronizer",
    "RPC",
    "NetworkConstants",
    "DamageDataIndex", "DamageDataIndexLookup",
    "WeaveSettings", "WeaveUtils",
    "BountyBoardSettings",
    "PlayerData", "PlayerManager",
    "InventoryHelpers",
    "PortraitFrames",
    "LobbyAux", "LobbyInternal",
    "LocomotionUtils", "PlayerUnitMovementSettings",
    "PerceptionUtils",
    "MaterialSettingsTemplates",
    "BTLootRatFleeAction",
    "CutsceneSystem",
    "ImpactDurationOutput",
    "EAC",
    "GenericStatusExtension",
    "Projectiles",
    "ItemHelper",
    "HordeSettings", "HordeCompositionsPacing",
    "AnimTextureExtension",
    "VMFMod",
    "CareerConstants",
    "GwNavQueries", "GwNavMath",
    "DeusCostSettings",
    "Log",
    "AiBreedSnippets",
    "RagdollSettings",
    "ImpactTypeOutput",
    "UISceneGraph", "UIScenegraph",
    "VolumetricsFlowCallbacks",
    -- Behavior Tree action classes (broad pattern — match any BT*Action)
    "BTChaosExaltedSorcererSkulkAction",
    "BTNinjaApproachAction",
    "BTSuicideRunAction",
    "BTSkulkAroundAction",
    "BTConditions", "BTSelector", "BTSequence", "BTAction",
    "BehaviorTreeCompiler",
    -- More VT2 settings/templates
    "PerlinNoise",
    "PingEffects",
    "Animations",
    "Spawners",
    "ChestSettings",
    "EquipmentTokenSettings",
    "MorrisCustomMutators",
    "MorrisLevelLookup",
    "AmmoTemplates", "AmmoSettings",
    "BuffFunctionTemplates",
    "ObjectiveTemplates",
    "WeaveSettings",
    "DeusCardSettings",
    "DeusFamilySettings",
    "DeusBackendCommon",
    "TalentUtils",
    "ScriptApplication",
    "RagdollSettings",
    "OverchargeData",
    "PlayerInventoryUI",
    "RoamerSettings",
    "FilledShield",
    "DialogueLookup",
    "DialogueQueries",
    "PassTemplates",
    "RawPassTemplates",
    "AllUnlockableHeroes",
    "EquipmentSettings",
    "OptionsSettings",
    "BasicWindowSettings",
    "WindowSettings",
    "AchievementListPanelDefinitions",
    "global_dialogues",
    "InteractionDefinitions",
    "BackendInterfacePropertyRolls",
    "GamePlay",

    -- VMF utility globals (provided by the framework)
    "rawget", "rawset",
    "pdArray",

    -- script_data (Stingray's mutable config table)
    "script_data",

    -- Inheritance helper
    "class",

    -- File loaders
    "dofile",
    "local_require",
    "package",

    -- Lua 5.1 + LuaJIT additions that VT2's runtime exposes but luacheck std=lua51 misses
    "newproxy",
}

-- Globals that mods are PERMITTED to write to (carefully — see memory)
globals = {
    "mod",                  -- assigned at top of every mod file via local mod = get_mod(...)
    "ItemMasterList",       -- mods inject items
    "WeaponSkins",          -- mods inject skins
    "DeusPowerUpTemplates", -- ct injects boons
    "BuffTemplates",        -- bt registers BR buffs
    "DamageProfileTemplates",  -- BR overrides shield_slam etc.
    "ExplosionTemplates",   -- mods register custom explosions
    "DLCSettings",
    "MutatorTemplates",
    "NetworkLookup",        -- limited; only via launcher's pre-register pattern
    "AttachmentNodeLinking",
    "_G",                   -- monkey-patches like _G.get_mod (la_prefix_patch)
    "Localize",             -- mods can extend
}

-- Stingray engine's extended stdlib — Lua 5.1 baseline misses these but VT2
-- provides them at runtime. Listed here so W143 (undefined-field-of-global)
-- doesn't fire on them.
stds.vt2_runtime = {
    read_globals = {
        table = { fields = { "clone", "merge", "merge_recursive", "size",
                              "find", "find_table", "contains",
                              "dump", "shallow_copy", "values", "keys",
                              "is_empty", "mirror_array", "set_readonly" } },
        math = { fields = { "round", "lerp", "ease_in_quad", "ease_out_quad",
                            "ease_pulse", "clamp", "sign", "round_with_precision",
                            "easeInCubic", "easeOutCubic", "easeInOutCubic",
                            "easeOutBack", "easeInExpo" } },
        string = { fields = { "split", "trim", "starts_with", "ends_with" } },
    },
}
std = "lua51+vt2_runtime"

-- Don't be loud about every warning — focus on the load-bearing ones.
-- See qa/CHECKS.md for which classes we DO want flagged.
ignore = {
    "611", -- whitespace
    "612", -- trailing whitespace
    "614", -- trailing whitespace in comment
    "631", -- line too long (handled by max_line_length)
    "112", -- mutating undefined global -- VT2 mods legitimately extend vanilla tables
    "122", -- setting read-only field of global -- same, VT2 mods extend Weapons/Pickups/etc.
    "212",       -- unused argument -- VMF hook signatures often take args we don't use
    "211/_.*",   -- unused locals starting with _ (intentional discard)
    "212/_.*",   -- unused args starting with _
    "213",       -- unused loop variables
    "311",       -- value assigned but unused (common in mod hooks)
    "542",       -- empty if branch (intentional in some guards)
}

-- Per-file overrides

files["**/_localization.lua"] = {
    -- localization files have lots of "unused" string fields that are
    -- referenced by name (setting_id) from data files
    ignore = { "111", "112", "113", "121", "122", "131", "142", "143" },
}

files["**/*_localization.lua"] = {
    ignore = { "111", "112", "113", "121", "122", "131", "142", "143" },
}

files["**/_data.lua"] = {
    ignore = { "111", "112", "113" },
}

files["**/*_data.lua"] = {
    ignore = { "111", "112", "113" },
}

-- Auto-generated unlock maps — don't care about formatting
files["**/_cosmetic_unlocks.lua"] = {
    ignore = { "*" },
}

-- Material-Hijack embedded — frozen ported code from external mod
files["**/_material_hijack_embedded.lua"] = {
    ignore = { "*" },
}

-- MoreItemsLibrary embedded — frozen ported code
files["**/_moreitemslibrary_embedded.lua"] = {
    ignore = { "*" },
}
