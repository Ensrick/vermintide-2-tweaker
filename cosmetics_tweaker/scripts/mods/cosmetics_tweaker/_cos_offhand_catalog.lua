-- _cos_offhand_catalog.lua — independent offhand catalog and package owner.
--
-- Owns the offhand package reference lifecycle, authored mesh/readiness and
-- inventory-icon resolution, static shield/dual-wield catalogs, lazy CWV pool
-- discovery, and the deferred all-pool preload implementation. It deliberately
-- does not own picker UI, render hooks, persistence/session state, LA merge
-- hooks, RPCs, commands, or mod lifecycle/update callbacks.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed through one ordered,
-- idempotent mod:dofile(...).install call before offhand session state.

local Catalog = {}

function Catalog.install(mod, deps)
    if mod._cos_offhand_catalog_owner then
        return mod._cos_offhand_catalog_owner
    end

    deps = deps or {}
    local OFFHAND_PRELOAD_LIFECYCLE = assert(deps.offhand_preload_lifecycle, "offhand_preload_lifecycle is required")
    local OFFHAND_NAMES = assert(deps.offhand_names, "offhand_names is required")
    local GK_SET = assert(deps.gk_set, "gk_set is required")
    local LA_BRIDGE = assert(deps.la_bridge, "la_bridge is required")
    local CWV_FAMILY_CONTRACT = assert(deps.cwv_family_contract, "cwv_family_contract is required")
    local _custom_illusions = assert(deps.custom_illusions, "custom_illusions is required")
    local _skin_requires_unowned_dlc = assert(deps.skin_requires_unowned_dlc, "skin_requires_unowned_dlc is required")
    local _dbg = assert(deps.dbg, "dbg is required")
    local _dbg_alert = assert(deps.dbg_alert, "dbg_alert is required")
    local get_mod = assert(deps.get_mod, "get_mod is required")
    local get_managers = deps.get_managers or function() return Managers end
    local Application = deps.application or Application
    local NetworkLookup = deps.network_lookup or NetworkLookup
    local WeaponSkins = deps.weapon_skins or WeaponSkins
    local ItemMasterList = deps.item_master_list or ItemMasterList
    local printf = deps.printf or printf

    -- Independent offhand (shield) illusion system
    -- ============================================================
    -- Adds a second row of illusion buttons below the main row on the
    -- weapon customization screen. The main row swaps the right-hand
    -- weapon model; this row independently swaps the left-hand (shield)
    -- model. Only shown for weapons that have a left_hand_unit.

    -- Preload the unit packages backing an offhand override, so when the
    -- in-game body re-spawns under a different illusion the engine can still
    -- find our chosen shield mesh. The 1p and 3p meshes are SEPARATE packages
    -- in vanilla VT2 — LA's own bootstrap loads both halves explicitly, and
    -- WeaponUtils.get_weapon_packages confirms it (`unit_name` AND
    -- `unit_name .. "_3p"` are queued separately). The in-game body spawns
    -- BOTH halves; the customization previewer only spawns 3p. Load both.
    --
    -- ASYNCHRONOUS load: the former sync path predated `_override_package_ready`
    -- (below). Both local and husk overrides now require Application.can_get for
    -- the 1P and 3P units before exposing an override, so a queued package safely
    -- degrades to the base mesh instead of reaching world.spawn_unit early. This
    -- removes the startup ResourcePackage.flush storm while preserving the crash
    -- gate. PackageManager invokes our callback only after force_load completes.
    local _offhand_preload_lifecycle = OFFHAND_PRELOAD_LIFECYCLE.new()
    local _preloaded_offhand_packages = _offhand_preload_lifecycle.states
    local _OFFHAND_PACKAGE_REFERENCE = "cosmetics_tweaker_offhand"
    local _offhand_late_callback_reports = 0
    local function _preload_one(package_path)
        local Managers = get_managers()
        if not package_path or package_path == "" then return end
        if _preloaded_offhand_packages[package_path] then return end
        if not Managers or not Managers.package then return end
        if Managers.package:has_loaded(package_path) then
            _offhand_preload_lifecycle:mark_resident(package_path)
            return
        end
        -- Skip if the unit is already engine-resident via a resource_package
        -- loaded by another mod / the boot chain. LA loads
        -- `resource_packages/levels/dlcs/morris/wastes_common` and four
        -- similar globals — they CONTAIN the deus shields used by LA's
        -- Imperial Hero variants, but the deus shield meshes have no
        -- standalone `units/.../wpn_es_deus_shield_03.package`. Calling
        -- Managers.package:load on a non-existent package_name still writes
        -- to self._packages, so has_loaded subsequently lies — and the
        -- override fires for a unit that isn't actually in the resource
        -- manager → "Unit not found" assert in World.spawn_unit. The
        -- can_get("unit", ...) check is the engine's authoritative
        -- "spawnable?" answer regardless of which package provides the unit.
        if Application and Application.can_get and Application.can_get("unit", package_path) then
            _offhand_preload_lifecycle:mark_resident(package_path)
            _dbg("[offhand] %s already engine-resident (no standalone load needed)", package_path)
            return
        end
        -- v0.9.3.2-hotfix: paths in `NetworkLookup.inventory_packages` ARE
        -- loadable via `Managers.package:load` even though there's no standalone
        -- .package file for them. Memory `feedback_vt2_force_load_only_listed_paths`
        -- documents the inverse — paths NOT in the list fatal asynchronously
        -- bypassing pcall. So: only skip when the path is in NEITHER the
        -- standalone-package set NOR the inventory_packages list.
        -- This fixes wpn_empire_shield_01_t1 / _02 / _03 / _04 / _05 which are
        -- inventory_package_list entries (lines 1214-1227 of vanilla
        -- inventory_package_list.lua) but have no standalone .package, causing
        -- our v0.8 / v0.9.x preload to silently skip them and PC-B to crash when
        -- PC-A (Kruber) wielded the Empire sword+shield. Burned 2026-05-21.
        local in_inventory_list = false
        if NetworkLookup and type(NetworkLookup.inventory_packages) == "table" then
            for _, listed in ipairs(NetworkLookup.inventory_packages) do
                if listed == package_path then
                    in_inventory_list = true
                    break
                end
            end
        end
        if Application and Application.can_get and not Application.can_get("package", package_path)
            and not in_inventory_list then
            -- v0.9.43-dev: this benign line fired hundreds of times per session and
            -- drowned the trace. Dedupe to once per unique path per session so the
            -- [cos:trace] channel stays readable. Behavior unchanged (still returns).
            mod._skip_preload_logged = mod._skip_preload_logged or {}
            if not mod._skip_preload_logged[package_path] then
                mod._skip_preload_logged[package_path] = true
                _dbg("[offhand] no standalone package at %s and not in inventory_packages list — skipping preload (deduped: once/session)", package_path)
            end
            return
        end
        -- Queue without prioritization. PackageManager serializes async packages
        -- and completes one ready handle per update; no ResourcePackage.flush is
        -- performed at the call site (package_manager.lua:20-87,260-274).
        local generation = _offhand_preload_lifecycle:begin(package_path)
        if not generation then return end
        local ok, err = pcall(function()
            -- resource-safety: cos1159-offhand-package-preload
            Managers.package:load(package_path, _OFFHAND_PACKAGE_REFERENCE, function()
                if _offhand_preload_lifecycle:complete(package_path, generation) then
                    _dbg("[offhand] async package ready %s", package_path)
                elseif _offhand_late_callback_reports < 4 then
                    _offhand_late_callback_reports = _offhand_late_callback_reports + 1
                    pcall(printf, "[cos:565] ignored late offhand preload callback path=%s report=%d/4",
                        tostring(package_path), _offhand_late_callback_reports)
                end
            end, true, false)
        end)
        if ok then
            _dbg("[offhand] queued package %s (async)", package_path)
        else
            _offhand_preload_lifecycle:cancel(package_path, generation)
            _dbg_alert("[offhand] preload FAILED for %s: %s", package_path, tostring(err))
        end
    end

    -- Balance the one mod-owned reference taken for every queued package. This is
    -- wired into the existing on_unload above; pending async loads are unloadable by
    -- PackageManager too (it resolves either the async handle or loaded handle).
    mod._release_offhand_packages = function(reason)
        local Managers = get_managers()
        local pm = Managers and Managers.package
        -- Invalidate the generation BEFORE touching PackageManager. If another
        -- owner keeps a shared async handle alive, vanilla retains our callback in
        -- that handle even after our reference is removed (package_manager.lua
        -- :41-48, :196-237). The callback must observe the dead generation.
        local owned_paths = _offhand_preload_lifecycle:release()
        if not pm then
            pcall(printf, "[cos:565] offhand lifecycle invalidated without package manager acquired=%d reason=%s",
                #owned_paths, tostring(reason))
            return 0
        end
        local released = 0
        local failed = 0
        local detail_reports = 0
        for _, package_path in ipairs(owned_paths) do
            local count = pm.reference_count and pm:reference_count(package_path, _OFFHAND_PACKAGE_REFERENCE) or 0
            if not count or count < 1 then
                failed = failed + 1
                if detail_reports < 4 then
                    detail_reports = detail_reports + 1
                    pcall(printf, "[cos:565] offhand reference missing at release path=%s report=%d/4",
                        tostring(package_path), detail_reports)
                end
            else
                -- `begin` dedupes acquisition, so the expected count is exactly
                -- one. If an earlier regression somehow duplicated this private
                -- reference, drain every copy: no other subsystem owns this name.
                if count ~= 1 and detail_reports < 4 then
                    detail_reports = detail_reports + 1
                    pcall(printf, "[cos:565] offhand reference count mismatch path=%s count=%d report=%d/4",
                        tostring(package_path), count, detail_reports)
                end
                local path_ok = true
                local last_err
                for _ = 1, count do
                    local ok, err = pcall(function() pm:unload(package_path, _OFFHAND_PACKAGE_REFERENCE) end)
                    if not ok then
                        path_ok = false
                        last_err = err
                        break
                    end
                end
                if path_ok then
                    released = released + 1
                else
                    failed = failed + 1
                    if detail_reports < 4 then
                        detail_reports = detail_reports + 1
                        pcall(printf, "[cos:565] offhand reference release failed path=%s error=%s report=%d/4",
                            tostring(package_path), tostring(last_err), detail_reports)
                    end
                end
            end
        end
        pcall(printf, "[cos:565] offhand lifecycle release acquired=%d released=%d failed=%d late_callbacks=%d reason=%s",
            #owned_paths, released, failed,
            _offhand_preload_lifecycle.stats.late_callbacks_ignored, tostring(reason))
        return released
    end
    mod._cos_offhand_preload_contract = {
        mode = "async",
        reference_name = _OFFHAND_PACKAGE_REFERENCE,
        readiness_gate = "Application.can_get:1p+3p",
        callback_guard = "generation_token",
        max_lifecycle_reports = 4,
    }
    mod._cos_offhand_preload_lifecycle = _offhand_preload_lifecycle

    -- v0.9.3: skin-variant suffixes that share a base unit path but live in
    -- SEPARATE .package files. When a client wields a skinned variant of a
    -- weapon (e.g. wpn_emp_gk_shield_02_runed_01_3p — the Stylish loot-chest
    -- skin underlying LA's Ostermark01 texture paint), the host needs that
    -- package preloaded too, or vanilla World.spawn_unit asserts at
    -- c_api_world.cpp:67 (engine-level, pcall can't catch).
    -- Burned PC-B 2026-05-21 17:22 when PC-A switched to Ostermark01.
    local _SKIN_VARIANT_SUFFIXES = {
        "_runed_01", "_runed_02", "_runed_03", "_runed_04", "_runed_05", "_runed_06",
        "_magic_01", "_magic_02",
    }

    local function _preload_offhand_package(unit_path)
        _preload_one(unit_path)
        if unit_path and unit_path ~= "" then
            _preload_one(unit_path .. "_3p")
            -- v0.9.3: also load skinned variants so a peer wielding a Stylish/
            -- themed/Weavebound/Shyish-Infused variant of this base weapon
            -- doesn't crash our wield delegate.
            for _, suffix in ipairs(_SKIN_VARIANT_SUFFIXES) do
                _preload_one(unit_path .. suffix)
                _preload_one(unit_path .. suffix .. "_3p")
            end
        end
    end

    local function _preload_offhand_for_option(opt)
        if not opt then return end
        if opt.unit then _preload_offhand_package(opt.unit) end
        if opt.intended_unit then _preload_offhand_package(opt.intended_unit) end
    end

    -- v0.9.0.4-hotfix: forward-decl. Real impl placed AFTER `_offhand_options`
    -- is declared (line ~1574) so the function can close over the local. Called
    -- from mod.update after `_la_bridge_init_done = true` to bulk-preload every
    -- mesh in the offhand pools + custom illusions on EVERY peer. Eliminates the
    -- ProfileSynchronizer async-load vs synchronous-wield-RPC race that crashes
    -- the client when host equips a cross-character shield mesh. Mechanism
    -- documented in `feedback_cwv_cross_character_unit_packages.md`.
    local _force_load_all_offhand_packages

    -- Defensive gate before applying a left_hand_unit override. Uses
    -- Application.can_get("unit", ...) — the engine's authoritative answer
    -- about whether World.spawn_unit will succeed, regardless of which
    -- package (standalone or resource_package) provides the unit. Replaces
    -- the old has_loaded check which lied for resource_package-resident
    -- units that we'd phantom-loaded.
    local function _override_package_ready(unit_path)
        if not unit_path or unit_path == "" then return false end
        if not Application or not Application.can_get then return false end
        if not Application.can_get("unit", unit_path) then return false end
        if not Application.can_get("unit", unit_path .. "_3p") then return false end
        return true
    end

    -- Variant-aware authored-shield mesh resolution shared by the
    -- LOCAL offhand-override path (BackendUtils.get_item_units, non-husk body) and
    -- the husk path so the two can NEVER disagree on the canonical shield model.
    -- Before this, the husk path resolved the 3P as
    -- `new_units[2]` (LA's authored 3P mesh) while the local path's
    -- `_override_package_ready` derived it by `..\"_3p\"` suffix. They happen to
    -- match for today's shields (`new_units[2] == new_units[1].."_3p"`), but the
    -- suffix is NOT guaranteed for future LA variants, and routing both paths
    -- through one resolver removes the divergence by construction.
    -- #200/#629: texture-authored variants may declare `new_units` too.  Those
    -- units are their UV/material owners and MUST be spawned before paint; treating
    -- texture variants as paint-only wrapped the final LA choices over whichever
    -- shield happened to be equipped.  Cosmetics-authored components (currently
    -- the Purpure/Azure GK shield) use this exact resolver as well.
    local function _resolve_authored_offhand_variant(armoury_key)
        if not armoury_key then return nil, nil end
        local authored = GK_SET and GK_SET.resolve_variant(armoury_key)
        if authored then return authored, "cosmetics" end
        local la = get_mod("Loremasters-Armoury")
        local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
        return variant, variant and "loremaster" or nil
    end

    local function _resolve_authored_offhand_mesh(armoury_key)
        if not armoury_key then return nil, nil, false end
        local variant, source = _resolve_authored_offhand_variant(armoury_key)
        if not variant then return nil, nil, false end
        local nu = variant.new_units
        local la_1p = nu and nu[1]
        if not la_1p then return nil, nil, false end
        local la_3p = (nu and nu[2])
            or (source == "cosmetics" and la_1p)
            or (la_1p .. "_3p")
        local cg = Application and Application.can_get
        local ready = (cg and cg("unit", la_1p) and cg("unit", la_3p)) and true or false
        return la_1p, la_3p, ready
    end

    -- v0.8.51-dev: pools are STRICTLY same-character. A weapon belonging to a
    -- given Hero can only swap to shields that originate from that Hero's
    -- weapon family. All Kruber (`es_*`) weapons share the same Kruber-shield
    -- pool, Kerillian (`we_*`) shares the Kerillian-shield pool, etc. LA
    -- shields are merged in per-weapon-type via `_merge_la_offhand_options`
    -- and LA's own `icons` table is already character-correct (Kruber LA
    -- shields target `es_*` weapons, Kerillian LA shields target `we_*`, etc.),
    -- so the merge preserves the same-character invariant.
    -- v0.9.9.4-dev: schema is `_offhand_options[item_type][hand_field] = pool`.
    -- Single-mount shield weapons store their pool under "left_hand_unit" (the
    -- shield slot); multi-mount weapons (rapier+pistol, dual-wields) populate
    -- both "right_hand_unit" and "left_hand_unit" so each mount gets its own
    -- picker row. Helpers (_get_offhand_options, force-load, merge, etc.) walk
    -- the per-hand structure. See `_MULTI_MOUNT_ITEM_TYPES` below.
    local _SHIELD_POOLS_BY_ITEM_TYPE = {
        -- Kruber (Empire) — every Kruber-asset shield is shareable across
        -- every Kruber shield weapon (sword+shield, mace+shield, Bret
        -- sword+shield, deus 1h).
        es_1h_sword_shield = {
            { name = "Empire Shield",          unit = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1" },
            { name = "Empire Round Shield",    unit = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02" },
            { name = "Empire Shield (Ornate)", unit = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03" },
            { name = "Empire Shield (Plated)", unit = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04" },
            { name = "Empire Shield (Gold)",   unit = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05" },
            { name = "GK Shield (Blue)",       unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03" },
            { name = "GK Shield (Red)",        unit = "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02" },
            { name = "GK Shield (Red, Runed)", unit = "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01" },
            { name = "GK Shield (Green)",      unit = "units/weapons/player/wpn_emp_gk_shield_04/wpn_emp_gk_shield_04" },
            { name = "GK Shield (White)",      unit = "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05" },
            { name = "GK Shield (Blessed)",    unit = "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01" },
            { name = "Deus Shield (Ornate)",   unit = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02" },
            { name = "Deus Shield (Plumed)",   unit = "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03" },
        },
        -- Kerillian (Wood Elf) — only Kerillian-asset shields.
        we_1h_spears_shield = {
            { name = "Elven Shield",           unit = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01" },
            { name = "Elven Shield (Exotic)",  unit = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02" },
        },
        -- Bardin (Dwarf) — only Bardin-asset shields.
        dr_1h_axe_shield = {
            { name = "Dwarf Shield 1",         unit = "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01" },
            { name = "Dwarf Shield 2",         unit = "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02" },
            { name = "Dwarf Shield 2 (Runed)", unit = "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01" },
            { name = "Dwarf Shield 3",         unit = "units/weapons/player/wpn_dw_shield_03_t1/wpn_dw_shield_03" },
            { name = "Dwarf Shield 4",         unit = "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04" },
            { name = "Dwarf Shield 4 (Magic)", unit = "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01" },
            { name = "Dwarf Shield 5",         unit = "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05" },
            { name = "Dwarf Shield 5 (Runed)", unit = "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01" },
        },
        -- Saltzpyre (Warrior Priest) — only Saltzpyre-asset shields.
        wh_flail_shield = {
            { name = "WP Shield",              unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1" },
            { name = "WP Shield (Runed)",      unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed" },
            { name = "WP Shield (Magic)",      unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic" },
        },
    }

    local function _decorate_shield_option(option)
        if type(option) ~= "table" then return option end
        local identity = option.component_identity or option.la_armoury_key
            or option.intended_unit or option.unit or option.vanilla_skin
        return OFFHAND_NAMES.decorate(option, identity, "left_hand_unit", option.name,
            nil, function(key) return mod:localize(key) end, "shield",
            option.localization_key, rawget(_G, "Localize"))
    end

    for _, pool in pairs(_SHIELD_POOLS_BY_ITEM_TYPE) do
        for _, option in ipairs(pool) do _decorate_shield_option(option) end
    end

    -- Inventory-icon ownership follows the independently customized shield for
    -- these exact item types. Keep this presentation policy separate from the
    -- DLC/unlock filters used while building the selectable pools.
    local _SHIELD_ICON_OWNER_ITEM_TYPES = {
        we_1h_spears_shield = true,
        dr_1h_axe_shield = true,
        dr_1h_hammer_shield = true,
        wh_flail_shield = true,
        wh_hammer_shield = true,
    }
    for _, item_type in ipairs(LA_BRIDGE.kruber_shield_item_types or {}) do
        _SHIELD_ICON_OWNER_ITEM_TYPES[item_type] = true
    end
    for item_type, family in pairs(CWV_FAMILY_CONTRACT.families) do
        if family.icon_owner == "left_hand_unit" then
            _SHIELD_ICON_OWNER_ITEM_TYPES[item_type] = true
        end
    end

    local function _inventory_icon_for_offhand_unit(unit_path, preferred_template)
        if type(unit_path) ~= "string" or unit_path == "" then return nil end
        local candidates = {}
        local seen = {}
        local function consider(key, data)
            if type(data) ~= "table" or data.left_hand_unit ~= unit_path
                    or type(data.inventory_icon) ~= "string"
                    or data.inventory_icon == "" then return end
            local stable_key = tostring(key or data.name or data.inventory_icon)
            local dedupe = stable_key .. "\0" .. data.inventory_icon
            if seen[dedupe] then return end
            seen[dedupe] = true
            candidates[#candidates + 1] = {
                key = stable_key,
                icon = data.inventory_icon,
                template = data.template,
            }
        end
        if WeaponSkins and type(WeaponSkins.skins) == "table" then
            for key, skin in pairs(WeaponSkins.skins) do
                local data = type(skin) == "table" and (skin.data or skin) or nil
                consider(type(key) == "string" and key or (skin and skin.name), data)
            end
        end
        if type(ItemMasterList) == "table" then
            for key, data in pairs(ItemMasterList) do
                if type(data) == "table" and data.item_type == "weapon_skin" then
                    consider(key, data)
                end
            end
        end
        table.sort(candidates, function(a, b)
            local a_preferred = preferred_template and a.template == preferred_template or false
            local b_preferred = preferred_template and b.template == preferred_template or false
            if a_preferred ~= b_preferred then return a_preferred end
            if a.key ~= b.key then return a.key < b.key end
            return a.icon < b.icon
        end)
        return candidates[1] and candidates[1].icon or nil
    end

    local function _shallow_copy(t)
        local out = {}
        for i = 1, #t do out[i] = t[i] end
        return out
    end

    -- Promote each shield pool into the per-hand structure under left_hand_unit.
    -- LA shield options merged in `_merge_la_offhand_options` also land under
    -- left_hand_unit (LA only ships `swap_hand = "left_hand_unit"` variants).
    local _offhand_options = {}
    for item_type, pool in pairs(_SHIELD_POOLS_BY_ITEM_TYPE) do
        _offhand_options[item_type] = { left_hand_unit = pool }
    end
    -- De-aliased copies. Vanilla offhand options are the same across these
    -- weapon types, but LA shield options must be pooled per-weapon-type
    -- (driven by each LA variant's `icons` table). Sharing one table reference
    -- across weapon types would cross-pollinate Bret-authored LA textures onto
    -- mace UVs and vice-versa.
    _offhand_options.es_1h_mace_shield          = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) }
    _offhand_options.es_1h_sword_shield_breton  = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) }
    _offhand_options.es_deus_01                 = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) }
    -- CWV Kruber shield weapons are Empire-family receivers. Seed their vanilla
    -- row before the LA merge; otherwise the merge creates an LA-only pool.
    for _, item_type in ipairs(LA_BRIDGE.kruber_shield_item_types or {}) do
        if item_type ~= "es_1h_sword_shield_breton" and not _offhand_options[item_type] then
            _offhand_options[item_type] = {
                left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield),
            }
        end
    end
    _offhand_options.dr_1h_hammer_shield        = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.dr_1h_axe_shield) }
    _offhand_options.wh_hammer_shield           = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.wh_flail_shield) }
    for item_type in pairs(CWV_FAMILY_CONTRACT.families) do
        local pool_source = CWV_FAMILY_CONTRACT.shield_pool_source(item_type)
        local pool = pool_source and _SHIELD_POOLS_BY_ITEM_TYPE[pool_source]
        if pool then
            _offhand_options[item_type] = { left_hand_unit = _shallow_copy(pool) }
        end
    end

    -- #629: the recolored Shield of Honour Renewed is an independently selectable
    -- Kruber offhand component, not a whole-weapon illusion.  Insert a distinct
    -- record into every compatible vanilla/CWV pool so the same component appears
    -- for Bretonnian Sword+Shield, Empire Sword+Shield, Mace+Shield, and compatible
    -- generated families without sharing mutable row state between them.
    if GK_SET and GK_SET.offhand_option then
        for _, item_type in ipairs(LA_BRIDGE.kruber_shield_item_types or {}) do
            local hands = _offhand_options[item_type]
            if hands and hands.left_hand_unit then
                hands.left_hand_unit[#hands.left_hand_unit + 1] =
                    _decorate_shield_option(GK_SET.offhand_option())
            end
        end
    end

    -- v0.9.9.4-dev: item_types with hand-qualified cosmetic pools. #583 makes
    -- dual weapons follow the native ownership model: vanilla row 1 owns the
    -- main/right hand and Cosmetics adds only the left/offhand row. The right pool
    -- remains registered for compatibility auditing and old in-memory selections.
    local _MULTI_MOUNT_ITEM_TYPES = {
        wh_fencing_sword           = true,  -- rapier (R) + pistol (L)
        wh_brace_of_pisols         = true,  -- pistol pair (matched)
        dr_drakefire_pistols       = true,  -- drakefire pair (matched)
        ww_dual_swords             = true,  -- elf sword pair (matched)
        ww_dual_daggers            = true,  -- elf dagger pair (matched)
        we_dual_wield_daggers      = true,  -- alias for ww_dual_daggers
        ww_sword_and_dagger        = true,  -- sword (R) + dagger (L)
        dr_dual_axes               = true,  -- dwarf axe pair (matched)
        dr_dual_wield_hammers      = true,  -- dwarf hammer pair (matched)
        es_dual_wield_hammer_sword = true,  -- mace (R) + sword (L)
        cwv_es_sword_and_mace      = true,  -- sword (R) + mace (L), CWV #483
        wh_dual_wield_axe_falchion = true,  -- axe (R) + falchion (L)
        wh_dual_hammer             = true,  -- Warrior Priest matched hammer pair
    }

    -- ============================================================
    -- Dual-wield offhand pools (v0.8.51-dev, refactored v0.8.56-dev)
    -- ============================================================
    -- For dual-wield weapons the offhand picker overrides `left_hand_unit`.
    -- The available pool of left-hand candidates depends on the dual-wield's
    -- shape:
    --
    --   MATCHED-PAIR (dr_dual_axes, we_dual_wield_daggers, ww_dual_swords,
    --   dr_dual_wield_hammers, wh_dual_hammer): both hands hold the same
    --   weapon variant. Pool = every variant of that weapon family. Swapping
    --   the left while keeping the right gives the player axe_01 on right
    --   and axe_02 on left.
    --
    --   MIXED-PAIR (es_dual_wield_hammer_sword: hammer right + sword left;
    --   ww_sword_and_dagger: sword right + dagger left; wh_dual_wield_axe_falchion:
    --   axe right + sword/falchion left): each hand holds a different weapon
    --   kind. Pool = every variant of the LEFT-hand weapon kind, so the user
    --   swaps the secondary weapon.
    --
    -- Pool sourcing:
    --   - Item types whose own `<item_type>_skins` table EXISTS in vanilla
    --     `WeaponSkins.skin_combinations`: walk that table, read `left_hand_unit`
    --     from each referenced skin. For matched pairs this equals right_hand_unit.
    --   - Item types whose own skin table is MISSING in vanilla (only one base
    --     skin exists, no crafted variants): borrow a single-hand skin table
    --     that matches the left-hand weapon kind. Single-hand skins only store
    --     `right_hand_unit`, so use that field. The borrowed table effectively
    --     becomes "every variant of this weapon kind".
    -- v0.9.9.4-dev: per-hand spec. Each item_type maps to up to two
    -- `{hand_field = {skin_table=...|matching_item_key=..., unit_field=...}}`
    -- entries, one per mount
    -- the picker should expose. `unit_field` is the SKIN-TABLE column to read
    -- (NOT the destination hand) — vanilla matched-pair skins ship both hand
    -- units in the SAME unit_field (left_hand_unit for native dual-wield
    -- tables) and skins borrowed from single-hand templates only carry
    -- right_hand_unit. The destination hand for the override is `hand_field`
    -- (the table key).
    local _DUAL_WIELD_POOLS = {
        -- Matched/mixed dual-wields WITH their own skin tables in vanilla.
        -- For matched pairs (axe pair, dagger pair, sword pair) the same skin
        -- table sources both hands; the user can mix right/left independently.
        dr_dual_axes = {
            right_hand_unit = { skin_table = "dr_dual_wield_axes_skins", unit_field = "left_hand_unit" },
            left_hand_unit  = { skin_table = "dr_dual_wield_axes_skins", unit_field = "left_hand_unit" },
        },
        ww_dual_daggers = {
            right_hand_unit = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
            left_hand_unit  = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
        },
        we_dual_wield_daggers = {
            right_hand_unit = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
            left_hand_unit  = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
        },
        ww_dual_swords = {
            right_hand_unit = { skin_table = "we_dual_wield_swords_skins", unit_field = "left_hand_unit" },
            left_hand_unit  = { skin_table = "we_dual_wield_swords_skins", unit_field = "left_hand_unit" },
        },
        -- ww_sword_and_dagger (Kerillian sword+dagger): native skin table
        -- carries both hands. Right = sword, left = dagger (per
        -- weapon_skins.lua entries: right_hand_unit = wpn_we_sword_*,
        -- left_hand_unit = wpn_we_dagger_*).
        ww_sword_and_dagger = {
            right_hand_unit = { skin_table = "we_dual_wield_sword_dagger_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "we_dual_wield_sword_dagger_skins", unit_field = "left_hand_unit"  },
        },

        -- Dual-wields whose own `<item_type>_skins` table is MISSING in vanilla.
        -- Borrow single-hand skin tables matching each hand's weapon kind:
        --   * dr_dual_wield_hammers: matched pair, both hands hold 1h dwarf hammer
        --     -> dr_1h_hammer_skins for both
        --   * es_dual_wield_hammer_sword: right = mace (no dedicated skin table
        --     in vanilla; reuse es_1h_sword_skins as approximate variants), left = sword
        --     -> es_1h_sword_skins for both. The hand_swap is intentional —
        --     vanilla treats the kruber 1h sword pool as the "weapon variants"
        --     for both sides because no native mace skin table exists.
        --   * wh_dual_wield_axe_falchion: right = axe (no 1h-axe skins for
        --     Saltzpyre; reuse falchion variants), left = falchion
        --     -> wh_1h_falchion_skins for both.
        --   * wh_brace_of_pisols / dr_drakefire_pistols: matched pistol pairs.
        --     No dedicated skin tables in vanilla, but the symmetric units
        --     ship on the base template; we expose the same pool for both
        --     hands so the user can mix barrels.
        -- Warrior Priest Dual Skullsplitters ship a dedicated Bless skin table
        -- with common/rare/unique/magic variants. The old exclusion predated that
        -- source audit and is the native #583 reproduction.
        wh_dual_hammer = {
            right_hand_unit = { skin_table = "wh_dual_hammer_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "wh_dual_hammer_skins", unit_field = "left_hand_unit" },
        },
        dr_dual_wield_hammers = {
            right_hand_unit = { skin_table = "dr_1h_hammer_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "dr_1h_hammer_skins", unit_field = "right_hand_unit" },
        },
        es_dual_wield_hammer_sword = {
            right_hand_unit = { skin_table = "es_1h_sword_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "es_1h_sword_skins", unit_field = "right_hand_unit" },
        },
        -- CWV's inverse Empire pair has no independent hand tables of its own.
        -- Source each row from the exact vanilla family instead of zipping the
        -- generated paired skins: sword cosmetics on the right, mace cosmetics
        -- on the left. `matching_item_key` is deliberately data-driven so future
        -- asymmetric modded pairs can reuse this registration shape.
        cwv_es_sword_and_mace = {
            right_hand_unit = { matching_item_key = "es_1h_sword", unit_field = "right_hand_unit" },
            left_hand_unit  = { matching_item_key = "es_1h_mace", unit_field = "right_hand_unit" },
        },
        wh_dual_wield_axe_falchion = {
            right_hand_unit = { skin_table = "wh_1h_falchion_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "wh_1h_falchion_skins", unit_field = "right_hand_unit" },
        },
        -- Asymmetric exotic — rapier + pistol (Saltzpyre's fencing sword).
        -- Native skin table carries both hand units per skin entry; right is
        -- the rapier mesh, left is the matching pistol.
        wh_fencing_sword = {
            right_hand_unit = { skin_table = "wh_fencing_sword_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "wh_fencing_sword_skins", unit_field = "left_hand_unit"  },
        },
        -- Symmetric pistol pairs (no dedicated skin tables in vanilla — fall
        -- back to the brace template's own per-skin entries via the same skin
        -- table reused for both hands). If vanilla ships no skin table for
        -- these item_types the pool ends up empty and the picker just doesn't
        -- render for them (graceful).
        wh_brace_of_pisols = {
            right_hand_unit = { skin_table = "wh_brace_of_pistols_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "wh_brace_of_pistols_skins", unit_field = "left_hand_unit"  },
        },
        dr_drakefire_pistols = {
            right_hand_unit = { skin_table = "dr_drakefire_pistols_skins", unit_field = "right_hand_unit" },
            left_hand_unit  = { skin_table = "dr_drakefire_pistols_skins", unit_field = "left_hand_unit"  },
        },
    }

    local function _source_illusion_name(skin_key, data)
        local L = rawget(_G, "Localize")
        local display_key = data and data.display_name
        local candidates = {}
        if display_key then candidates[#candidates + 1] = display_key end
        if skin_key then candidates[#candidates + 1] = skin_key .. "_name" end
        if L then
            for _, key in ipairs(candidates) do
                if type(key) == "string" and key ~= "" then
                    local ok, localized = pcall(L, key)
                    if ok and type(localized) == "string" and localized ~= ""
                            and localized ~= key and localized ~= "<" .. key .. ">" then
                        return localized, display_key
                    end
                end
            end
        end
        return OFFHAND_NAMES.readable_source_name(skin_key), display_key
    end

    local function _decorate_dual_component(option, skin_key, hand_field, data)
        local source_name, display_key = _source_illusion_name(skin_key, data)
        option.source_description_key = data and data.description
        if hand_field == "left_hand_unit" then
            return OFFHAND_NAMES.decorate(option, skin_key, hand_field, source_name, display_key,
                function(key) return mod:localize(key) end, nil, nil, rawget(_G, "Localize"))
        end
        option.name = source_name
        option.source_skin_key = skin_key
        option.source_display_key = display_key
        return option
    end

    -- Build offhand options from a skin_combination table. Reads either
    -- `left_hand_unit` (native dual-wield tables) or `right_hand_unit`
    -- (borrowed single-hand tables) per the `unit_field` arg. Returns the
    -- canonical `{ name, unit, rarity }` shape consumed by the picker.
    local function _build_offhand_options_from_skin_table(skin_table_name, unit_field, hand_field)
        if not WeaponSkins or not WeaponSkins.skin_combinations then return nil end
        local sct = WeaponSkins.skin_combinations[skin_table_name]
        if not sct then return nil end
        unit_field = unit_field or "left_hand_unit"

        local skin_by_name = {}
        if WeaponSkins.skins then
            for _, s in ipairs(WeaponSkins.skins) do
                if s.name and s.data then skin_by_name[s.name] = s.data end
            end
            -- CWV registers generated skins by string key; those entries are not
            -- guaranteed to be present in the array portion used by vanilla.
            for skin_key, s in pairs(WeaponSkins.skins) do
                if type(skin_key) == "string" and type(s) == "table" then
                    skin_by_name[skin_key] = s.data or s
                end
            end
        end

        local seen = {}
        local out = {}
        local rarity_order = { "plentiful", "common", "rare", "exotic", "unique", "bogenhafen", "promotion" }
        local seen_rarity = {}
        local rarity_keys = {}
        for _, r in ipairs(rarity_order) do
            if sct[r] then rarity_keys[#rarity_keys + 1] = r; seen_rarity[r] = true end
        end
        for r, _ in pairs(sct) do
            if not seen_rarity[r] then rarity_keys[#rarity_keys + 1] = r end
        end

        for _, rarity in ipairs(rarity_keys) do
            local bucket = sct[rarity]
            if type(bucket) == "table" then
                for _, skin_key in ipairs(bucket) do
                    local s = skin_by_name[skin_key]
                    local unit_path = s and s[unit_field]
                    if unit_path and not seen[unit_path] then
                        seen[unit_path] = true
                        local option = {
                            unit   = unit_path,
                            rarity = s.rarity or rarity,
                            skin_key = skin_key,
                            inventory_icon = s.inventory_icon,
                        }
                        out[#out + 1] = _decorate_dual_component(
                            option, skin_key, hand_field, s)
                    end
                end
            end
        end
        return out
    end

    do
        -- Build a hand pool directly from ItemMasterList's canonical weapon-skin
        -- ownership relation. This covers modded asymmetric pairs whose generated
        -- pair table intentionally couples the hands and therefore cannot supply
        -- independent picker rows. Stable rarity/key sorting keeps UI order fixed.
        local function _build_offhand_options_from_matching_item(matching_item_key, unit_field, hand_field, admitted_owners)
            if type(ItemMasterList) ~= "table" then return nil end
            unit_field = unit_field or "right_hand_unit"

            local rarity_rank = {
                plentiful = 1, common = 2, rare = 3, exotic = 4,
                unique = 5, bogenhafen = 6, promotion = 7, magic = 8,
            }
            local candidates = {}
            for skin_key, entry in pairs(ItemMasterList) do
                if type(entry) == "table"
                        and entry.item_type == "weapon_skin"
                        and entry.matching_item_key == matching_item_key
                        and entry[unit_field]
                        and CWV_FAMILY_CONTRACT.skin_source_allowed(entry, admitted_owners)
                        and not _skin_requires_unowned_dlc(skin_key) then
                    candidates[#candidates + 1] = {
                        skin_key = skin_key,
                        data = entry,
                    }
                end
            end
            table.sort(candidates, function(a, b)
                local ar = rarity_rank[a.data.rarity] or 99
                local br = rarity_rank[b.data.rarity] or 99
                if ar ~= br then return ar < br end
                return a.skin_key < b.skin_key
            end)

            local seen = {}
            local out = {}
            for _, candidate in ipairs(candidates) do
                local entry = candidate.data
                local unit_path = entry[unit_field]
                if not seen[unit_path] then
                    seen[unit_path] = true
                    local option = {
                        unit = unit_path,
                        rarity = entry.rarity,
                        skin_key = candidate.skin_key,
                        inventory_icon = entry.inventory_icon,
                    }
                    out[#out + 1] = _decorate_dual_component(
                        option, candidate.skin_key, hand_field, entry)
                end
            end
            return out
        end

        -- #583: CWV skin-combination tables are created by the sibling mod and may
        -- not exist yet when Cosmetics loads. Keep the exact source declaration
        -- here, then build lazily from the picker/update paths once CWV is ready.
        local cwv_dual_sources = {
            cwv_es_dual_swords = {
                right_hand_unit = { skin_table = "cwv_es_dual_swords_skins", unit_field = "right_hand_unit" },
                left_hand_unit  = { skin_table = "cwv_es_dual_swords_skins", unit_field = "left_hand_unit" },
            },
            cwv_es_sword_and_mace = {
                right_hand_unit = { matching_item_key = "es_1h_sword", unit_field = "right_hand_unit" },
                left_hand_unit  = { matching_item_key = "es_1h_mace", unit_field = "right_hand_unit" },
            },
            cwv_es_dual_axes = {
                right_hand_unit = { skin_table = "cwv_es_dual_axes_skins", unit_field = "right_hand_unit" },
                left_hand_unit  = { skin_table = "cwv_es_dual_axes_skins", unit_field = "left_hand_unit" },
            },
            cwv_wh_dual_axes = {
                right_hand_unit = { skin_table = "cwv_wh_dual_axes_skins", unit_field = "right_hand_unit" },
                left_hand_unit  = { skin_table = "cwv_wh_dual_axes_skins", unit_field = "left_hand_unit" },
            },
            cwv_es_dual_maces = {
                right_hand_unit = { skin_table = "cwv_es_dual_maces_skins", unit_field = "right_hand_unit" },
                left_hand_unit  = { skin_table = "cwv_es_dual_maces_skins", unit_field = "left_hand_unit" },
            },
            cwv_wh_dual_maces = {
                right_hand_unit = { skin_table = "cwv_wh_dual_maces_skins", unit_field = "right_hand_unit" },
                left_hand_unit  = { skin_table = "cwv_wh_dual_maces_skins", unit_field = "left_hand_unit" },
            },
            cwv_es_dual_warpriest_hammers = {
                right_hand_unit = { skin_table = "cwv_es_dual_warpriest_hammers_skins", unit_field = "right_hand_unit" },
                left_hand_unit  = { skin_table = "cwv_es_dual_warpriest_hammers_skins", unit_field = "left_hand_unit" },
            },
        }
        for item_type, per_hand in pairs(CWV_FAMILY_CONTRACT.dual_sources()) do
            cwv_dual_sources[item_type] = per_hand
        end
        mod._cwv_dual_offhand_contract = cwv_dual_sources
        mod._independent_dual_item_types = mod._independent_dual_item_types or {}
        for item_type in pairs(_DUAL_WIELD_POOLS) do
            mod._independent_dual_item_types[item_type] = true
        end
        for item_type in pairs(cwv_dual_sources) do
            mod._independent_dual_item_types[item_type] = true
            _MULTI_MOUNT_ITEM_TYPES[item_type] = true
        end

        local function _build_dual_pool(item_type, per_hand)
            _offhand_options[item_type] = _offhand_options[item_type] or {}
            for hand_field, spec in pairs(per_hand) do
                if not _offhand_options[item_type][hand_field] then
                    local source_name = spec.skin_table or spec.matching_item_key
                    local source_kind = spec.skin_table and "skin_table" or "matching_item"
                    local pool
                    if spec.matching_item_key then
                        pool = _build_offhand_options_from_matching_item(spec.matching_item_key, spec.unit_field, hand_field, spec.admitted_owner_item_types)
                    else
                        pool = _build_offhand_options_from_skin_table(
                            spec.skin_table, spec.unit_field, hand_field)
                    end
                    if pool and #pool > 0 then
                        _offhand_options[item_type][hand_field] = pool
                        mod:info("[cosmetics:offhand] pool item=%s hand=%s options=%d source=%s:%s field=%s",
                            item_type, hand_field, #pool, source_kind, source_name, spec.unit_field)
                    else
                        mod:info("[cosmetics:offhand] pool item=%s hand=%s options=0 source=%s:%s field=%s",
                            item_type, hand_field, source_kind, tostring(source_name), tostring(spec.unit_field))
                    end
                end
            end
            local left = _offhand_options[item_type].left_hand_unit
            if type(left) == "table" and #left > 0
                    and not (left[1] and left[1].follow_main) then
                table.insert(left, 1, {
                    name = "Follow Main Illusion",
                    unit = "",
                    rarity = "default",
                    follow_main = true,
                })
            end
            local right = _offhand_options[item_type].right_hand_unit
            return type(right) == "table" and #right > 0
                and type(left) == "table" and #left > 1
        end

        for item_type, per_hand in pairs(_DUAL_WIELD_POOLS) do
            _build_dual_pool(item_type, per_hand)
        end

        mod._ensure_independent_dual_pool = function(item_type)
            if not mod._independent_dual_item_types[item_type] then
                return _offhand_options[item_type]
            end
            local sources = cwv_dual_sources[item_type] or _DUAL_WIELD_POOLS[item_type]
            if sources then _build_dual_pool(item_type, sources) end
            return _offhand_options[item_type]
        end

        mod._discover_cwv_dual_offhand_pools = function()
            local built = 0
            for item_type in pairs(cwv_dual_sources) do
                local pools = mod._ensure_independent_dual_pool(item_type)
                if pools and pools.right_hand_unit and pools.left_hand_unit
                        and #pools.right_hand_unit > 0 and #pools.left_hand_unit > 1 then
                    built = built + 1
                end
            end
            return built
        end

        -- #641: generated inventory for incrementally authoring independent
        -- offhand-weapon and shield names. It is derived from the same selectable
        -- pools the picker renders, so non-selectable source skins cannot leak in.
        mod._cos.offhand_name_policy = OFFHAND_NAMES
        mod._cos.offhand_name_inventory = function()
            mod._discover_cwv_dual_offhand_pools()
            local records = {}
            for item_type, pools in pairs(_offhand_options) do
                for hand_field, pool in pairs(pools) do
                    for _, option in ipairs(pool or {}) do
                        if option.component_kind and option.component_identity then
                            records[#records + 1] = {
                                item_type = item_type,
                                hand_field = hand_field,
                                component_kind = option.component_kind,
                                component_identity = option.component_identity,
                                source_skin_key = option.source_skin_key,
                                source_name = option.name,
                                localization_key = option.component_localization_key,
                                status = option.component_name_source,
                            }
                        end
                    end
                end
            end
            return OFFHAND_NAMES.inventory_rows(records)
        end
    end

    -- Deferred implementation of the forward-declared bulk package loader.
    -- It remains action-time only and is called by the entry-owned update loop
    -- after the LA bridge has initialized.
    --
    -- Why this exists: when HOST picks a cross-character shield (e.g.
    -- `wpn_emp_gk_shield_03` "GK Shield Blue" via the offhand picker, or equips
    -- the CT custom illusion `ct_es_mace_gk_shield_01` which also uses
    -- shield_03 as left_hand_unit), the CLIENT receives vanilla skin
    -- propagation. Client's `SimpleHuskInventoryExtension._wield_slot` calls
    -- `BackendUtils.get_item_units(item_data, nil, slot.skin, career_name)`,
    -- gets shield_03's path back, then `GearUtils.spawn_inventory_unit` →
    -- `unit_spawner:spawn_local_unit_with_extensions` → engine `spawn_unit`.
    -- shield_03's package WAS NOT preloaded on the client — ProfileSynchronizer
    -- starts an async load when peer profiles sync but it races the synchronous
    -- wield RPC and loses. Result: engine spawn_unit crash, PC-B fell out of the
    -- session 2026-05-19. Identical mechanism to weapon_tweaker's brace-repeater
    -- crash (feedback_cwv_cross_character_unit_packages.md).
    --
    -- Fix: enumerate every unit_path the user might equip via CT (offhand pools
    -- + custom illusions) and queue an async load at boot on EVERY peer.
    -- _preload_offhand_package is idempotent via the _preloaded_offhand_packages
    -- set, so re-calls are cheap.
    local _force_loaded_all_offhand_done = false
    _force_load_all_offhand_packages = function()
        local Managers = get_managers()
        if _force_loaded_all_offhand_done then return end
        if not Managers or not Managers.package then return end
        -- CWV registers its generated skin tables after Cosmetics may have loaded.
        -- If CWV is present, wait until all seven dual families are discoverable so
        -- remote peers preload the same compatible units before any hand payload.
        if get_mod("character_weapon_variants")
                and mod._discover_cwv_dual_offhand_pools
                and mod._discover_cwv_dual_offhand_pools() < 7 then
            return
        end
        local count = 0
        -- A. Vanilla-mesh + cross-character pools (_offhand_options).
        -- v0.9.9.4: per-hand structure — outer = item_type, middle = hand_field,
        -- inner = pool array.
        for _wkey, hand_pools in pairs(_offhand_options) do
            if type(hand_pools) == "table" then
                for _hand, pool in pairs(hand_pools) do
                    if type(pool) == "table" then
                        for _, opt in ipairs(pool) do
                            if type(opt) == "table" then
                                if opt.unit then _preload_offhand_package(opt.unit); count = count + 1 end
                                if opt.intended_unit then _preload_offhand_package(opt.intended_unit); count = count + 1 end
                            end
                        end
                    end
                end
            end
        end
        -- B. LA bridge offhand options (texture-paint + kind="unit" custom-mesh).
        -- v0.9.9.4: same per-hand structure (LA only ships left_hand_unit
        -- variants currently, but walk all hands for forward-compat).
        if LA_BRIDGE and type(LA_BRIDGE.la_offhand_options_by_weapon_type) == "table" then
            for _wkey, hand_pools in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
                if type(hand_pools) == "table" then
                    for _hand, pool in pairs(hand_pools) do
                        if type(pool) == "table" then
                            for _, opt in ipairs(pool) do
                                if type(opt) == "table" then
                                    if opt.unit then _preload_offhand_package(opt.unit); count = count + 1 end
                                    if opt.intended_unit then _preload_offhand_package(opt.intended_unit); count = count + 1 end
                                end
                            end
                        end
                    end
                end
            end
        end
        -- C. Custom illusions injected by CT. These register at boot into
        -- WeaponSkins.skins and are equippable by any peer; their left/right
        -- hand units must be loadable on every machine.
        if _custom_illusions then
            for _, illusion in ipairs(_custom_illusions) do
                if illusion.right_hand_unit then _preload_offhand_package(illusion.right_hand_unit); count = count + 1 end
                if illusion.left_hand_unit  then _preload_offhand_package(illusion.left_hand_unit);  count = count + 1 end
            end
        end
        _force_loaded_all_offhand_done = true
        mod:info("[offhand] queued all offhand pool packages asynchronously (%d preload calls, dedup'd via _preloaded_offhand_packages)", count)
        pcall(printf, "[cos:565] offhand bulk preload queued mode=async calls=%d", count)
        -- [heap-probe] snapshot Lua bookkeeping after the package requests are queued.
        -- Package resource memory is C++-side (collectgarbage does not see it), and
        -- async completion is intentionally spread across later PackageManager frames.
        mod:debug("[heap-probe] post offhand async-queue: lua_heap %.1f MB (%.0f KB) live; %d preload calls (references released on unload)",
            collectgarbage("count") / 1024, collectgarbage("count"), count)
    end

    local owner = {
        preload_lifecycle = _offhand_preload_lifecycle,
        preload_offhand_package = _preload_offhand_package,
        preload_offhand_for_option = _preload_offhand_for_option,
        force_load_all_offhand_packages = _force_load_all_offhand_packages,
        override_package_ready = _override_package_ready,
        resolve_authored_offhand_variant = _resolve_authored_offhand_variant,
        resolve_authored_offhand_mesh = _resolve_authored_offhand_mesh,
        shield_pools_by_item_type = _SHIELD_POOLS_BY_ITEM_TYPE,
        decorate_shield_option = _decorate_shield_option,
        shield_icon_owner_item_types = _SHIELD_ICON_OWNER_ITEM_TYPES,
        inventory_icon_for_offhand_unit = _inventory_icon_for_offhand_unit,
        source_illusion_name = _source_illusion_name,
        offhand_options = _offhand_options,
        multi_mount_item_types = _MULTI_MOUNT_ITEM_TYPES,
        dual_wield_pools = _DUAL_WIELD_POOLS,
    }
    mod._cos_offhand_catalog_owner = owner
    return owner
end

return Catalog
