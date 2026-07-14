local M = {}

-- CLARIFY: separate feature_enabled implementation from the one in
-- weapon_tweaker.lua because this module receives `mod` as a parameter
-- (it's a sub-module, not the mod's own scope). Both implementations use the
-- same "nil setting => fall back to default_value" pattern; default_value=true
-- means "feature enabled by default".
-- POTENTIAL BUG (LOW): `default_value ~= false` returns true if default_value
-- is nil OR true. So `feature_enabled(mod, "x")` (no default supplied) returns
-- true. Callers below all pass `true` explicitly so this is harmless, but the
-- behavior diverges from the same-named function in weapon_tweaker.lua which
-- treats omitted default as "enabled by default" (same effective result).
local function feature_enabled(mod, setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then
        return default_value ~= false
    end

    return value == true
end

-- CLARIFY: invoked once at the bottom of weapon_tweaker.lua (~L3043). Sets
-- up backend hooks. Note: `apply_weapon_unlocks` is passed in but never
-- called from this module — only retained because it might be needed for
-- legacy code paths or future use. Could be dropped from the signature.
function M.install(mod, weapon_unlock_map, apply_weapon_unlocks)
    mod.loadout_cache = mod.loadout_cache or {}
    local cwv_ownership = mod._wt and mod._wt.cwv_ownership
    local cwv_managed = mod._wt and mod._wt.cwv_conditional_managed or {}
    local function cwv_active()
        return cwv_ownership
            and cwv_ownership.cwv_is_active(get_mod("character_weapon_variants"))
            or false
    end
    M._last_cwv_active = cwv_active()

    -- Passive overcharge-vent / energy-regen restore for cross-character
    -- overcharge weapons (Sienna staves) + the Moonfire Bow on careers that
    -- lack the native rate. Exposes M.tick(dt); driven from mod.update below
    -- (the single per-frame surface VMF schedules). Loaded once here. See the
    -- module header for the full networking / consumption-side rationale.
    local passive_charge = mod:dofile("scripts/mods/weapon_tweaker/_wt_passive_charge")
    M.passive_charge = passive_charge
    local overcharge_presentation = mod:dofile("scripts/mods/weapon_tweaker/_wt_overcharge_presentation")
    M.overcharge_presentation = overcharge_presentation

    local function is_mod_unlocked_weapon(career_name, weapon_key)
        if not career_name or not weapon_key then
            return false
        end

        local career_weapons = weapon_unlock_map[career_name]
        if not career_weapons then
            return false
        end

        if cwv_ownership and cwv_ownership.should_yield_native(
                career_name, weapon_key, cwv_active(), cwv_managed) then
            return false
        end

        for _, unlocked_key in ipairs(career_weapons) do
            if unlocked_key == weapon_key and mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                return true
            end
        end

        return false
    end
    -- Regression-visible pure ownership predicate. The read-side hooks below
    -- use this same closure, so a removed pair is rejected before any stale
    -- cached backend id can override vanilla's loadout.
    M.is_mod_unlocked_weapon = is_mod_unlocked_weapon

    M._filter_dirty = false

    function M.refresh_on_setting_change(mod)
        if Managers.backend and Managers.backend._interfaces
                and Managers.backend._interfaces["items"] then
            local items_interface = Managers.backend:get_interface("items")
            for career_name, slots in pairs(mod.loadout_cache) do
                for slot_name, backend_id in pairs(slots) do
                    local item = items_interface:get_item_from_id(backend_id)
                    local weapon_key = item and (item.key or (item.data and item.data.key))
                    if not weapon_key or not is_mod_unlocked_weapon(career_name, weapon_key) then
                        slots[slot_name] = nil
                    end
                end
                if not next(slots) then
                    mod.loadout_cache[career_name] = nil
                end
            end
        end

        M._filter_dirty = true
    end

    local function get_cached_backend_item(items_interface, career_name, slot_name)
        local slots = mod.loadout_cache[career_name]
        local backend_id = slots and slots[slot_name]
        if not backend_id then
            return nil, nil
        end

        local item = items_interface:get_item_from_id(backend_id)
        if not item then
            slots[slot_name] = nil
            return nil, nil
        end

        return backend_id, item
    end

    -- CLARIFY: deferred initialization. Two one-shot guards:
    --   1. _applied_unlocks: apply_weapon_unlocks needs ItemMasterList loaded.
    --      Runs once when ItemMasterList is first available.
    --   2. done_hooking_backend: backend hooks need the items_interface INSTANCE
    --      (not class). Hooking an instance method is required because the
    --      class-form hook on `BackendInterfaceItemPlayfab.set_loadout_item`
    --      can collide with weave-mode interface usage and other mods. Runs
    --      once when Managers.backend has interfaces created (in the lobby).
    -- VMF schedules `mod.update` every frame so the conditions are polled.
    -- VMF passes the frame `dt` as the first arg (repo-wide convention:
    -- `mod.update = function(dt) ... end`); the deferred-init guards below
    -- ignore it, but the passive-charge tick needs it.
    mod.update = function(dt)
        -- Per-frame passive-charge restore (cross-character staves / Moonfire
        -- Bow). Self-gated on its VMF toggle (default OFF) and the local owned
        -- player only; pcall-isolated internally so it can never break init.
        passive_charge.tick(dt)
        pcall(overcharge_presentation.tick)

        -- Per-frame DURABLE 3P grip-offset re-apply (the Necromancer Ghost
        -- Scythe on Kruber, etc.). A one-shot create_equipment offset is stomped
        -- by the engine's per-tick canonical-pose reset in-game (preview-OK /
        -- in-game-wrong), so members of _DURABLE_GRIP_OFFSETS re-apply every
        -- frame on the local player's wielded 3P unit. 3P-ONLY, career-gated,
        -- additive-from-canonical (never compounds). See the _DURABLE_GRIP_OFFSETS
        -- header in weapon_tweaker.lua / OFFSETS.md. Defined on the mod table
        -- because that's where the offset data lives (separate dofile scope).
        -- Guarded: nil before weapon_tweaker.lua finishes loading (load order).
        if mod._reapply_durable_grip_offsets then
            pcall(mod._reapply_durable_grip_offsets)
        end

        -- #569: durable, absolute 3P-only local-Z half-turn for non-native
        -- weapons on standard Saltzpyre careers whose live wield redirect is
        -- the Warrior Priest greathammer family. Tracks local/bot/husk/preview
        -- units and restores canonical rotation while unwielded.
        if mod._wt569_reapply_3p_orientation then
            pcall(mod._wt569_reapply_3p_orientation)
        end

        -- #593: CWV may be enabled/disabled or hot-reloaded without a game
        -- state transition. Reconcile exactly once per ownership transition:
        -- can_wield is strip/rebuilt and stale WT loadout-cache rows are pruned.
        local owns_axe_shield = cwv_active()
        if owns_axe_shield ~= M._last_cwv_active then
            M._last_cwv_active = owns_axe_shield
            apply_weapon_unlocks()
            M.refresh_on_setting_change(mod)
            mod:info("[wt:593] CWV ownership transition active=%s; native Kruber Axe+Shield reconciled",
                tostring(owns_axe_shield))
        end

        if not mod._applied_unlocks and ItemMasterList then
            mod._applied_unlocks = true
            apply_weapon_unlocks()
        end

        if not mod.done_hooking_backend and Managers.backend and Managers.backend._interfaces
                and Managers.backend._interfaces["items"] then
            mod.done_hooking_backend = true
            local items_interface = Managers.backend:get_interface("items")

            -- #582: eagerly prune cache entries whose ownership disappeared in
            -- this version (notably native dr_dual_wield_axes on ES/WH). The
            -- get_loadout/get_loadout_item_id hooks also revalidate on every
            -- read, but doing this once here makes hot-reload/session-retained
            -- state converge before the first inventory query.
            M.refresh_on_setting_change(mod)

            -- CLARIFY: when the user equips a CROSS-CAREER (mod-unlocked)
            -- weapon, we INTERCEPT the call and store the backend_id in our
            -- own per-career cache instead of letting the original method
            -- write it to PlayFab. The original would either reject the cross-
            -- career equip or silently revert it on next sync. The cache is
            -- read back in get_loadout_item_id / get_loadout to make the
            -- equipped item appear correct in UI and gameplay.
            -- v0.12.65: pass-through `...` for vanilla's 5th arg
            -- `optional_loadout_index` (and any future args). Versus mode
            -- and other code paths use the loadout_index; dropping it
            -- silently mis-targeted loadouts before this fix. Also return
            -- `true` from the mod-unlocked short-circuit so callers that
            -- treat the return value as success/fail (e.g.
            -- BackendInterfaceVersusPlayfab.set_loadout_item L111) don't
            -- see nil.
            mod:hook(items_interface, "set_loadout_item", function(func, self, backend_id, career_name, slot_name, ...)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    if mod.loadout_cache[career_name] then
                        mod.loadout_cache[career_name][slot_name] = nil
                    end
                    return func(self, backend_id, career_name, slot_name, ...)
                end

                local item_data = self:get_item_from_id(backend_id)
                local weapon_key = item_data and (item_data.key or (item_data.data and item_data.data.key))
                if is_mod_unlocked_weapon(career_name, weapon_key) then
                    mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
                    mod.loadout_cache[career_name][slot_name] = backend_id
                    return true
                end

                if mod.loadout_cache[career_name] then
                    mod.loadout_cache[career_name][slot_name] = nil
                end

                return func(self, backend_id, career_name, slot_name, ...)
            end)

            mod:hook(items_interface, "get_loadout", function(func, self)
                local loadout = func(self)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    return loadout
                end

                for career_name, slots in pairs(mod.loadout_cache) do
                    if loadout[career_name] then
                        for slot_name in pairs(slots) do
                            local cached_id, item = get_cached_backend_item(self, career_name, slot_name)
                            local weapon_key = item and (item.key or (item.data and item.data.key))
                            if cached_id and is_mod_unlocked_weapon(career_name, weapon_key) then
                                loadout[career_name][slot_name] = cached_id
                            else
                                slots[slot_name] = nil
                            end
                        end
                    end
                end

                return loadout
            end)

            -- CLARIFY: read-side mirror of set_loadout_item. When the equipped
            -- weapon for a (career, slot) is in our cache AND still passes
            -- is_mod_unlocked_weapon (settings haven't been disabled), return
            -- our cached backend_id; otherwise fall through to vanilla.
            mod:hook(items_interface, "get_loadout_item_id", function(func, self, career_name, slot_name, is_bot)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    return func(self, career_name, slot_name, is_bot)
                end

                -- audit 2026-06-07: vanilla get_loadout_item_id(self, career, slot, is_bot)
                -- (backend_interface_item_playfab.lua:512) takes a 4th `is_bot` arg that this
                -- hook previously DROPPED on both fall-through calls, so bot loadout lookups
                -- silently resolved via the player-default path. Only answer the LOCAL
                -- player's loadout from our modded cache; bot queries fall through to vanilla
                -- (bots have their own loadout) with is_bot preserved.
                if not is_bot then
                    local cached_id, item = get_cached_backend_item(self, career_name, slot_name)
                    local weapon_key = item and (item.key or (item.data and item.data.key))
                    if cached_id and is_mod_unlocked_weapon(career_name, weapon_key) then
                        return cached_id
                    end
                end

                return func(self, career_name, slot_name, is_bot)
            end)
        end

    end

    -- POTENTIAL BUG (LOW): table-form hook on `ItemGridUI`. If `ItemGridUI`
    -- isn't loaded yet at the moment M.install() runs (called from
    -- weapon_tweaker.lua bottom — after all top-level requires), this would
    -- raise "argument 'obj' should have the 'string/table' type, not 'nil'".
    -- ItemGridUI is loaded by inventory UI dependencies which load early, so
    -- this has not failed in practice. But the safer pattern is the
    -- string-form `mod:hook("ItemGridUI", ...)` per CLAUDE.md.
    mod:hook(ItemGridUI, "_on_category_index_change", function(func, self, index, keep_page_index)
        if feature_enabled(mod, "enable_weapon_ui_hooks", true) then
            if M._filter_dirty and self._category_settings then
                for _, s in ipairs(self._category_settings) do
                    if s._base_item_filter then
                        s.item_filter = s._base_item_filter
                        s._base_item_filter = nil
                    end
                end
                M._filter_dirty = false
            end

            local settings = self._category_settings and self._category_settings[index]
            if settings then
                local career_name = self._career_name
                local weapon_map = weapon_unlock_map[career_name]

                if settings._base_item_filter then
                    settings.item_filter = settings._base_item_filter
                end

                -- CLARIFY: only patch the filter when it's the EXACT vanilla
                -- "melee/ranged adventure mode" filter string. If a different
                -- mod or game mode (Versus, weave, etc.) has changed the
                -- filter, leave it alone — appending `or item_key == "..."`
                -- to a non-matching filter would change semantics.
                local base_filter = settings.item_filter
                if (base_filter == "( slot_type == melee ) and item_rarity ~= magic" or base_filter == "( slot_type == ranged ) and item_rarity ~= magic") and weapon_map then
                    local extra_filter = ""
                    for _, weapon_key in ipairs(weapon_map) do
                        if mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                            extra_filter = extra_filter .. " or item_key == \"" .. weapon_key .. "\""
                        end
                    end

                    if extra_filter ~= "" then
                        settings._base_item_filter = base_filter
                        settings.item_filter = "(" .. base_filter .. ")" .. extra_filter
                    end
                end
            end
        end

        return func(self, index, keep_page_index)
    end)
end

return M
