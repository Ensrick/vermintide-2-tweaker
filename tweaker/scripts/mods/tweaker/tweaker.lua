local mod = get_mod("t")

-- ============================================================
-- Any Weapon / Any Career
-- ============================================================
-- Based on Shazbot's AnyWeapon mod. Expands can_wield on every
-- ItemMasterList entry so all careers can equip any weapon.
-- Applied on game-state change (ItemMasterList loads lazily).
-- Crash-prevention hooks make off-career weapon use stable.

local _all_careers = {
    "bw_scholar", "bw_adept", "bw_unchained",
    "we_shade", "we_maidenguard", "we_waywatcher",
    "dr_ironbreaker", "dr_slayer", "dr_ranger",
    "wh_zealot", "wh_bountyhunter", "wh_captain",
    "es_huntsman", "es_knight", "es_mercenary", "es_questingknight",
    "dr_engineer", "we_thornsister", "wh_priest",
}

local _any_weapon_applied = false

local function apply_any_weapon()
    if _any_weapon_applied or not mod:get("any_weapon_any_career") then return end
    if not ItemMasterList then return end
    for _, weapon_data in pairs(ItemMasterList) do
        if weapon_data.can_wield then
            weapon_data.can_wield = _all_careers
        end
    end
    _any_weapon_applied = true
    mod:info("AnyWeapon: expanded can_wield for all items.")
end

-- ============================================================
-- Per-weapon career unlocks
-- ============================================================
-- Each setting unlock_CAREER_WEAPON adds that career to the weapon's
-- can_wield list so the career can equip the weapon normally.
-- Called alongside apply_any_weapon on every game-state change.

-- Per-career weapon unlock map.
-- Each career lists only the weapons it doesn't normally have access to
-- but whose animations are known-safe to cross-equip.
-- Key: career name. Value: list of weapon item keys.
local _WEAPON_UNLOCK_MAP = {
    -- Kruber: melee from Bardin/Saltzpyre + elf longbow (3P anim remapped to es_longbow)
    es_mercenary      = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "we_longbow" },
    es_huntsman       = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "we_longbow" },
    es_knight         = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "we_longbow" },
    es_questingknight = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "we_longbow" },
    -- Bardin: can borrow Kruber's mace/mace+shield and Saltzpyre's axe/Skullsplitter
    dr_ranger         = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    dr_ironbreaker    = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    dr_slayer         = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    dr_engineer       = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    -- Kerillian: longbow for non-Waystalker careers (Waystalker already has it natively)
    we_maidenguard    = { "we_longbow" },
    we_shade          = { "we_longbow" },
    we_thornsister    = { "we_longbow" },
    -- Saltzpyre: Kruber's mace/sword + Bardin's hammer/axe + Sienna's sword for all; shields only for Warrior Priest; elf longbow on Kruber's 3P anim
    wh_captain        = { "es_1h_mace", "es_1h_sword", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow" },
    wh_bountyhunter   = { "es_1h_mace", "es_1h_sword", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow" },
    wh_zealot         = { "es_1h_mace", "es_1h_sword", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow" },
    wh_priest         = { "es_1h_mace", "es_1h_sword", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "es_mace_shield", "dr_shield_hammer" },
}

-- Saved originals keyed by weapon_key; populated on first call, never cleared.
local _original_can_wield = {}

local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Collect every weapon key this mod might touch.
    local all_weapon_keys = {}
    for _, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, weapon_key in ipairs(weapons) do
            all_weapon_keys[weapon_key] = true
        end
    end

    for weapon_key in pairs(all_weapon_keys) do
        local item = ItemMasterList[weapon_key]
        if item and item.can_wield then
            -- Save original array once; never overwrite it.
            if not _original_can_wield[weapon_key] then
                local orig = {}
                for i, v in ipairs(item.can_wield) do orig[i] = v end
                _original_can_wield[weapon_key] = orig
            end
            -- Restore in-place so shared table references stay valid.
            local t    = item.can_wield
            local orig = _original_can_wield[weapon_key]
            while #t > 0 do table.remove(t) end
            for _, v in ipairs(orig) do t[#t + 1] = v end
        end
    end

    -- Re-apply only currently-enabled unlocks.
    for career, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, weapon_key in ipairs(weapons) do
            if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                local item = ItemMasterList[weapon_key]
                if item and item.can_wield then
                    local already = false
                    for _, c in ipairs(item.can_wield) do
                        if c == career then already = true; break end
                    end
                    if not already then
                        item.can_wield[#item.can_wield + 1] = career
                    end
                end
            end
        end
    end
end

-- 3rd-person animation remapping for cross-career weapon unlocks.
-- When career A uses career B's weapon, the weapon template's wield_anim fires on
-- the wrong skeleton and produces no animation (silent fail). We inject
-- wield_anim_career_3p entries into the live weapon template tables so the game's
-- own get_wield_anim() returns a compatible animation for the foreign career.
--
-- Format: Weapons[template_key].wield_anim_career_3p[career] = "animation_event"
-- The Weapons global holds the live template tables; patching it once affects both
-- SimpleInventoryExtension (local player 3P) and SimpleHuskInventoryExtension (other players).

local function patch_3p_weapon_anims()
    if not Weapons then return end

    -- Elf longbow (longbow_template_1, wield_anim "to_longbow") →
    -- Kruber careers redirect to his empire longbow animation ("to_es_longbow").
    -- Runs each game-state change so toggling the setting takes effect on next equip.
    local longbow = Weapons["longbow_template_1"]
    if longbow then
        longbow.wield_anim_career_3p = longbow.wield_anim_career_3p or {}
        for _, career in ipairs({
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
        }) do
            if mod:get("unlock_" .. career .. "_we_longbow") then
                longbow.wield_anim_career_3p[career] = "to_es_longbow"
            else
                longbow.wield_anim_career_3p[career] = nil
            end
        end
    end
end

mod.on_game_state_changed = function(status, state_name)
    apply_any_weapon()
    apply_weapon_unlocks()
    patch_3p_weapon_anims()
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "any_weapon_any_career" then
        apply_any_weapon()
    end
    -- All weapon unlock and 3P anim settings start with "unlock_"
    if setting_id:find("^unlock_") then
        apply_weapon_unlocks()
        patch_3p_weapon_anims()
    end
end

-- Crash prevention: nil explosion template.
mod:hook("DamageUtils", "create_explosion", function(func, world, attacker_unit, position, rotation, explosion_template, ...)
    if not explosion_template then return end
    return func(world, attacker_unit, position, rotation, explosion_template, ...)
end)

mod:hook("AreaDamageSystem", "create_explosion", function(func, self, attacker_unit, position, rotation, explosion_template_name, ...)
    if not ExplosionTemplates or not ExplosionTemplates[explosion_template_name] then return false end
    return func(self, attacker_unit, position, rotation, explosion_template_name, ...)
end)

-- Crash prevention: animation events on mismatched weapon units.
mod:hook("Unit", "animation_event", function(func, ...)
    pcall(func, ...)
end)

-- Crash prevention: attachment node mismatches when equipping off-career weapons.
mod:hook("SimpleInventoryExtension", "_wield_slot", function(func, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    local ret
    pcall(function() ret = func(self, equipment, slot_data, unit_1p, unit_3p, buff_extension) end)
    return ret
end)

mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    local ret
    pcall(function() ret = func(self, world, equipment, slot_name, unit_1p, unit_3p) end)
    return ret
end)

-- ============================================================
-- Commands
-- ============================================================

mod:command("find_class", "Find global class names matching a pattern", function(pattern)
    pattern = pattern:lower()
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find(pattern) then
            found[#found + 1] = k .. " (" .. type(v) .. ")"
        end
    end
    table.sort(found)
    for _, s in ipairs(found) do
        mod:echo(s)
    end
end)

mod:command("inspect", "List methods of a global class", function(name)
    local cls = _G[name]
    if not cls then mod:echo("Not found: " .. name) return end
    local found = {}
    for k, v in pairs(cls) do
        if type(v) == "function" then
            found[#found + 1] = k
        end
    end
    table.sort(found)
    for _, s in ipairs(found) do
        mod:echo(s)
    end
end)

mod:command("unstuck", "Teleport to nearest living teammate", function()
    local pm = Managers.player
    if not pm then mod:echo("Not in a level.") return end
    local player = pm:local_player()
    if not player then mod:echo("No local player.") return end
    local unit = player.player_unit
    if not unit then mod:echo("No player unit (dead?).") return end

    local target_pos = nil
    for _, p in pairs(pm:players()) do
        if p ~= player and p.player_unit and HEALTH_ALIVE[p.player_unit] then
            target_pos = Unit.local_position(p.player_unit, 0)
            break
        end
    end

    if target_pos then
        local mover = Unit.mover(unit)
        if mover then
            Mover.set_position(mover, target_pos + Vector3(0.5, 0, 0))
        end
        mod:echo("Unstuck!")
    else
        mod:echo("No living teammate found.")
    end
end)

local _godmode = false

mod:command("god", "Toggle godmode (invincibility)", function()
    _godmode = not _godmode
    mod:echo("Godmode " .. (_godmode and "ON" or "OFF"))
end)

mod:command("win", "Complete the current map", function()
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end)

-- ============================================================
-- Godmode
-- ============================================================

mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, ...)
    if _godmode then
        local pm = Managers.player
        local player = pm and pm:local_player()
        local local_unit = player and player.player_unit
        if local_unit and attacked_unit == local_unit then
            return 0
        end
    end
    return func(attacked_unit, ...)
end)

-- ============================================================
-- Coin Multiplier
-- ============================================================

local _granting_starting_coins = false

mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" and not _granting_starting_coins then
        local multiplier = mod:get("coin_multiplier")
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
        mod:info("Coin pickup: %d -> %d (x%.2f)", raw_amount, args[1], multiplier)
    end

    return func(self, unpack(args))
end)

-- ============================================================
-- Starting Coins
-- ============================================================
-- setup_run fires exactly once when a brand-new Chaos Wastes run begins
-- (not on each map transition or post-game). Perfect hook for run-start grants.

mod:hook_safe("DeusRunController", "setup_run", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 then
        if self.on_soft_currency_picked_up then
            mod:info("Starting coins: granting %d", starting)
            _granting_starting_coins = true
            self:on_soft_currency_picked_up(starting)
            _granting_starting_coins = false
        end
    end
end)

-- ============================================================
-- Boon Options Count + Boon Filtering
-- ============================================================
-- generate_random_power_ups is called for both shrines (default 4 options)
-- and chests (default 3 options). We distinguish by the count arg value.
-- We also filter disabled boons from the result and support a dump command
-- to discover boon IDs by inspecting the live pool.

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT  = 3

mod._dump_boons = false  -- set true by "t dump_boons" command

mod:command("dump_boons", "Log all boon IDs from the next shrine/chest roll", function()
    mod._dump_boons = true
    mod:echo("Boon dump enabled - open a shrine or chest to capture IDs.")
end)

mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)
    local args = { ... }

    -- Modify count (existing logic)
    local count_idx = nil
    for i, v in ipairs(args) do
        if type(v) == "number" and v >= 1 and v <= 10 then
            count_idx = i
            break
        end
    end

    if count_idx then
        local original = args[count_idx]
        local custom_count

        if original == SHRINE_DEFAULT then
            custom_count = mod:get("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = mod:get("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            mod:info("Boon options: args[%d]=%d -> %d", count_idx, original, custom_count)
            args[count_idx] = custom_count
        end
    else
        mod:info("Boon options: could not find count arg: %s %s %s %s",
            tostring(args[1]), tostring(args[2]), tostring(args[3]), tostring(args[4]))
    end

    -- Dump input pool for ID discovery
    if mod._dump_boons then
        mod:info("=== BOON POOL DUMP: %d args ===", #args)
        for i, v in ipairs(args) do
            if type(v) == "table" then
                local n = 0
                for _ in pairs(v) do n = n + 1 end
                mod:info("  args[%d] = table (%d entries)", i, n)
                for j, entry in ipairs(v) do
                    if type(entry) == "table" then
                        mod:info("    [%d] name=%s rarity=%s", j,
                            tostring(entry.name), tostring(entry.rarity))
                    else
                        mod:info("    [%d] = %s (%s)", j, tostring(entry), type(entry))
                    end
                end
            else
                mod:info("  args[%d] = %s (%s)", i, tostring(v), type(v))
            end
        end
    end

    -- Remove disabled boons from the draw pool before calling func.
    -- This ensures disabled boons are never drawn in the first place, so the
    -- returned count is always accurate — not reduced by post-draw filtering.
    -- Covers all availability types:
    --   shrine         → shrine shops
    --   cursed_chest   → Chests of Trials
    --   weapon_chest   → in-mission boon altars (power_up type) AND end-of-level grants
    --   terror_event   → terror event rewards
    -- Note: actual weapon generation goes through DeusWeaponGeneration.generate_weapon,
    -- which never calls generate_random_power_ups, so no special-casing is needed.
    local removed_main   = {}  -- {index, boon} removed from DeusPowerUpsArray
    local removed_rarity = {}  -- per-rarity removals from DeusPowerUpsArrayByRarity

    if DeusPowerUpsArray then
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local key  = boon and boon.name and ("disable_boon_" .. boon.name)
            if key and mod:get(key) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
                mod:info("Pool remove: %s", boon.name)
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local key  = boon and boon.name and ("disable_boon_" .. boon.name)
                    if key and mod:get(key) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    -- Call original — returns (seed, new_power_ups)
    local new_seed, new_power_ups = func(unpack(args))

    -- Restore removed boons (iterate in reverse to preserve original indices)
    for i = #removed_main, 1, -1 do
        local e = removed_main[i]
        table.insert(DeusPowerUpsArray, e.index, e.boon)
    end
    for rarity, removed in pairs(removed_rarity) do
        local arr = DeusPowerUpsArrayByRarity[rarity]
        for i = #removed, 1, -1 do
            local e = removed[i]
            table.insert(arr, e.index, e.boon)
        end
    end

    -- Dump result for ID discovery
    if mod._dump_boons and type(new_power_ups) == "table" then
        mod:info("=== BOON RESULT DUMP ===")
        for i, boon in ipairs(new_power_ups) do
            if type(boon) == "table" then
                mod:info("  [%d] name=%s rarity=%s", i,
                    tostring(boon.name), tostring(boon.rarity))
            end
        end
        mod._dump_boons = false
        mod:echo("Boon dump complete - check the log for IDs.")
    end

    return new_seed, new_power_ups
end)

-- ============================================================
-- Arc Layout: NaN Fix + Overflow Scaling
-- ============================================================
-- The shrine/chest boon arc uses: rad = math.rad(step / (count-1) * 180)
-- Problem 1 — count=1: (count-1)=0 → NaN offset → UIRenderer crash.
-- Problem 2 — count=5: cards extend beyond visible screen area.
--
-- Shrine (DeusShopView v2): offered boons are in self._shop_item_widgets.
-- Chest of Trials (DeusCursedChestView): offered boons are in self._power_up_widgets.
--
-- Fix NaN: when exactly 1 card, set X offset to 0 (centered).
-- Fix overflow: when count > default, scale Y offsets so total span stays within
--   the default count's natural span. Default for shrine = 4, for chest = 3.
--   Scale factor = (N_default - 1) / (N_actual - 1).

local function fix_arc_layout(widgets, n_default)
    if not widgets or #widgets == 0 then return end
    local n = #widgets
    -- NaN fix: single card → X = 0
    if n == 1 then
        local w = widgets[1]
        if w and w.offset and w.offset[1] ~= w.offset[1] then
            w.offset[1] = 0
        end
        return
    end
    -- Overflow fix: scale Y if more cards than the view was designed for
    if n > n_default then
        local scale = (n_default - 1) / (n - 1)
        for _, w in ipairs(widgets) do
            if w and w.offset then
                w.offset[2] = w.offset[2] * scale
            end
        end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self)
    -- Shrine offered boons are stored in _shop_item_widgets in v2.
    fix_arc_layout(self._shop_item_widgets, SHRINE_DEFAULT)
end)

mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_layout(self._power_up_widgets, CHEST_DEFAULT)
end)

-- ============================================================
-- Friendly Fire Toggle
-- ============================================================
-- On Champion+, ranged FF is on by default. Hook the two gate functions
-- that everything else calls through to suppress it when toggled off.

mod:hook("DamageUtils", "allow_friendly_fire_ranged", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

mod:hook("DamageUtils", "allow_friendly_fire_melee", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

-- ============================================================
-- Curse Disabling
-- ============================================================

local function is_curse_disabled(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then return false end
    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return mod:get(key) == true
end

-- Gate 1: MutatorHandler._activate_mutator — suppresses the curse effect itself.
mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        mod:echo("Suppressed curse: " .. name)
        return
    end
    return func(self, name, ...)
end)

-- Gate 2: DeusMechanism.get_current_node_curse — suppresses the popup (DeusCurseUI)
-- and prevents flow_callback_set_deus_curse_active from ever activating the curse.
mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then return nil end
    return curse
end)

-- Gate 3: DeusMapDecisionView._enable_hover — hides the chaos god icon/text in
-- the map tooltip for nodes whose curse is disabled.
-- Gate 4: DeusMechanism._transition_next_node — clears current_node.curse before
-- get_next_level_data runs so curse packages are never loaded (prevents sky/env effects).
mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    local drc = self._deus_run_controller
    local graph_data = drc and drc:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        mod:info("Clearing curse from node before level load: %s", saved_curse)
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    return unpack(results)
end)

-- Gate 5: DeusMechanism.start_next_round — clears current_node.curse before the
-- mutators list is built so the curse mutator is never activated in-game.
-- Also clears current_node.theme to suppress god-themed sky/shader mutators
-- that load from DeusThemeSettings[theme].mutators. Theme is reset to "wastes"
-- (the neutral no-god theme) so the visual effects don't load either.
mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local drc = self._deus_run_controller
    local current_node = drc and drc:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    if saved_curse and is_curse_disabled(saved_curse) then
        mod:info("Clearing curse+theme from node before mutator build: %s", saved_curse)
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    local results = { func(self, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results)
end)

mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]
    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end
    return func(self, node_key, ...)
end)

-- ============================================================
-- Boon Localization — auto-name from game data
-- ============================================================
-- DeusPowerUpTemplates[name].display_name is the real in-game localization key.
-- Managers.localization:append_backend_localizations() writes directly into the
-- table that Localize() checks first, so subsequent mod:localize(setting_id)
-- calls (which VMF falls back to Localize() for unknown keys) return correct names.
-- Also patches mod._localization directly in case VMF uses its own lookup table.

local _boon_loc_patched = false

local function patch_boon_localization()
    if _boon_loc_patched then return end
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then return end
    _boon_loc_patched = true

    local injections = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name then
            local template = DeusPowerUpTemplates[name]
            local display_key = template and template.display_name
            local display_name
            if display_key then
                local raw = Localize(display_key)
                -- Localize returns "<key>" when not found; discard that
                if raw ~= "<" .. display_key .. ">" then
                    display_name = raw
                end
            end
            display_name = display_name or name
            injections["disable_boon_" .. name] = display_name
            injections["start_boon_"   .. name] = display_name
        end
    end

    -- Inject into game's localization backend (VMF falls back to Localize())
    if Managers.localization then
        Managers.localization:append_backend_localizations(injections)
    end

    -- Also patch VMF's own localization table directly, in case it doesn't
    -- fall back to Localize() for settings it already has entries for.
    if type(mod._localization) == "table" then
        for key, display_name in pairs(injections) do
            if not mod._localization[key] then
                mod._localization[key] = {}
            end
            mod._localization[key].en = display_name
        end
    end
end

mod:hook_safe("DeusRunController", "init", function()
    patch_boon_localization()
end)

-- ============================================================
-- Starting Boons
-- ============================================================
-- Runs after _add_initial_power_ups so career talents are already set.
-- Looks up rarity from DeusPowerUpsArray (the live boon pool) — disabled boons
-- are only removed from the pool during generate_random_power_ups calls and
-- always restored immediately, so the pool is complete here. This means
-- a boon can be in both the disable list and the start list: it won't appear
-- at shrines/chests, but the player still receives it at run start.

mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    local own_peer_id = run_state and run_state:get_own_peer_id()

    -- On the server: grant boons for any peer (host's own init + client inits via rpc_deus_set_initial_setup).
    -- On a client: only grant for own peer (local path; host will authoritative-set anyway).
    if not run_state:is_server() and peer_id ~= own_peer_id then return end
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    -- Build rarity lookup from the live pool so we never need a hardcoded map.
    local rarity_of = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and not rarity_of[name] then
            rarity_of[name] = entry.rarity
        end
    end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
            mod:info("Starting boon: %s (%s)", name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)
    mod:echo(string.format("Granted %d starting boon(s).", #extra))
end)

-- ============================================================
-- Weapon Chest Distribution
-- ============================================================
-- Each level's in-mission weapon chests are lazily typed when first opened.
-- The type list (upgrade/swap_melee/swap_ranged/power_up) is built from
-- LevelSettings[level_key].deus_weapon_chest_distribution on first use, then
-- cached in self._deus_weapon_chest_distribution for the rest of that level.
-- We intercept the rebuild step to substitute our own counts.

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local chest_distribution = self._deus_weapon_chest_distribution

    if (not chest_distribution or #chest_distribution == 0) and DEUS_CHEST_TYPES then
        local upgrade  = mod:get("chest_upgrade_count")
        local swap_m   = mod:get("chest_swap_melee_count")
        local swap_r   = mod:get("chest_swap_ranged_count")
        local power_up = mod:get("chest_power_up_count")

        -- Only override if any count differs from the original defaults
        local sig_default = { upgrade = 1, swap_melee = 1, swap_ranged = 1, power_up = 2 }
        local is_custom = upgrade  ~= sig_default.upgrade
                       or swap_m   ~= sig_default.swap_melee
                       or swap_r   ~= sig_default.swap_ranged
                       or power_up ~= sig_default.power_up

        if is_custom then
            local dist = {}
            for i = 1, upgrade  do dist[#dist + 1] = DEUS_CHEST_TYPES.upgrade    end
            for i = 1, swap_m   do dist[#dist + 1] = DEUS_CHEST_TYPES.swap_melee end
            for i = 1, swap_r   do dist[#dist + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for i = 1, power_up do dist[#dist + 1] = DEUS_CHEST_TYPES.power_up   end

            if #dist > 0 then
                local run_state = self._run_state
                local node_key  = run_state and run_state:get_current_node_key()
                local path_graph = self:_get_graph_data()
                local node = path_graph and node_key and path_graph[node_key]
                local seed  = node and HashUtils and HashUtils.fnv32_hash(node.level_seed) or 0
                table.shuffle(dist, seed)

                self._deus_weapon_chest_distribution = dist
                local chest_type = dist[#dist]
                dist[#dist] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

-- ============================================================
-- Banned Weapon Traits + Any Trait on Any Weapon
-- ============================================================
-- Before generation/upgrade, temporarily replace each weapon's
-- baked_trait_combinations with a (possibly expanded, possibly filtered) pool,
-- then restore immediately after.
--
-- any_trait_any_weapon: gives every weapon the union of all weapons' combos.
-- ban_trait_*: strips combos containing that trait from the effective pool.

local _all_trait_combos_cache = nil

local function get_all_trait_combos()
    if _all_trait_combos_cache then return _all_trait_combos_cache end
    if not DeusWeapons then return nil end
    local all_combos = {}
    local seen = {}
    for _, data in pairs(DeusWeapons) do
        local combos = data.baked_trait_combinations
        if combos then
            for _, combo in ipairs(combos) do
                local key = table.concat(combo, "\0")
                if not seen[key] then
                    seen[key] = true
                    all_combos[#all_combos + 1] = combo
                end
            end
        end
    end
    _all_trait_combos_cache = all_combos
    return all_combos
end

local function apply_weapon_trait_filter()
    if not DeusWeapons then return {} end
    local any_trait = mod:get("any_trait_any_weapon")
    local expanded_pool = any_trait and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local base = expanded_pool or original
        if not base then break end

        -- Apply ban filter to the effective pool
        local filtered = {}
        for _, combo in ipairs(base) do
            local ok = true
            for _, trait in ipairs(combo) do
                if mod:get("ban_trait_" .. trait) then
                    ok = false
                    break
                end
            end
            if ok then
                filtered[#filtered + 1] = combo
            end
        end

        -- Determine new value to install:
        --   filtered if we removed some AND alternatives remain
        --   base     if any_trait expanded it but nothing was banned
        --   nil      if nothing changed
        local new_val
        if #filtered < #base and #filtered > 0 then
            new_val = filtered                   -- filtered down
        elseif #filtered == 0 then
            new_val = base                       -- all banned: safety, keep original pool
        elseif base ~= original then
            new_val = base                       -- expanded by any_trait, no bans
        end

        if new_val and new_val ~= original then
            saved[item_key] = original
            data.baked_trait_combinations = new_val
        end
    end
    return saved
end

local function restore_weapon_trait_filter(saved)
    if not DeusWeapons then return end
    for item_key, original in pairs(saved) do
        DeusWeapons[item_key].baked_trait_combinations = original
    end
end

mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

-- ============================================================
-- Run Structure: Force Belakor + Finale God Override
-- ============================================================
-- _setup_run is called on the host immediately after the run parameters are
-- resolved (dominant_god from vote/backend, with_belakor from backend cycle).
-- We intercept on the host (is_server=true) to override those values before
-- they are synced to clients via rpc_deus_setup_run.
--
-- Dominant god values: 1=Nurgle, 2=Tzeentch, 3=Khorne, 4=Slaanesh, 0=default.

local _FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

mod:hook("DeusMechanism", "_setup_run", function(func, self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
    if is_server then
        if mod:get("force_belakor") then
            with_belakor = true
        end

        local god_idx = mod:get("finale_dominant_god")
        if god_idx and god_idx > 0 then
            local god = _FINALE_GODS[god_idx]
            if god then
                dominant_god = god
                mod:info("Finale god override: %s", god)
            end
        end
    end

    return func(self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
end)

-- ============================================================
-- Pickup Spawn Counts (Weapon Altars, Chests of Trials, Arena Ammo)
-- + Campaign Potions in Chaos Wastes
-- ============================================================
-- Altar/chest counts: patch DEUS_LEVEL_PICKUP_SETTINGS presets.
-- Arena ammo: patch the current level's pickup_settings via LevelHelper
--   (handles both shared default_arena_pickup_settings and arena_belakor's
--   inline table); arena = primary with no deus_weapon_chest field.
-- Campaign potions: temporarily inject damage/speed/cooldown potions into
--   Pickups.deus_potions so they can appear alongside Chaos Wastes potions.
--   All three have spawn_weighting=0.2 (same as deus potions), safe to add.

mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    if not LevelHelper then return func(self, ...) end

    local altar_total  = mod:get("chest_upgrade_count")
                       + mod:get("chest_swap_melee_count")
                       + mod:get("chest_swap_ranged_count")
                       + mod:get("chest_power_up_count")
    local cursed_count = mod:get("cursed_chest_count")
    local arena_ammo   = mod:get("arena_ammo_count")
    local potions_on   = mod:get("enable_campaign_potions")

    local altar_custom  = altar_total  ~= 5  -- default: 1+1+1+2
    local cursed_custom = cursed_count ~= 1  -- default: 1
    local ammo_custom   = arena_ammo   ~= 2  -- default: 2

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    -- Patch via LevelHelper:current_level_settings() — works for both preset
    -- references (e.g. default_signature_pickup_settings) and inline tables
    -- (e.g. arena_belakor). This is the same table populate_pickups will read.
    -- Arenas are identified by absence of deus_weapon_chest (no altars on arenas).
    local saved = {}
    local cur = LevelHelper:current_level_settings()
    local cur_ps = cur and cur.pickup_settings
    if cur_ps then
        for _, diff_data in pairs(cur_ps) do
            if type(diff_data) == "table" and diff_data.primary then
                local p = diff_data.primary
                local is_arena = p.deus_weapon_chest == nil
                local entry = { tbl = p }

                if not is_arena then
                    if altar_custom and p.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = p.deus_weapon_chest
                        p.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and p.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = p.deus_cursed_chest
                        p.deus_cursed_chest = cursed_count
                    end
                else
                    if ammo_custom and p.ammo ~= nil then
                        entry.ammo = p.ammo
                        p.ammo = arena_ammo
                    end
                end

                if entry.deus_weapon_chest ~= nil
                or entry.deus_cursed_chest ~= nil
                or entry.ammo            ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    -- Inject campaign potions into Pickups.deus_potions.
    local added_potions = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                Pickups.deus_potions[name] = Pickups.potions[name]
                added_potions[#added_potions + 1] = name
            end
        end
    end

    local results = { func(self, ...) }

    -- Restore everything.
    for _, entry in ipairs(saved) do
        local p = entry.tbl
        if entry.deus_weapon_chest ~= nil then p.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then p.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo              ~= nil then p.ammo              = entry.ammo              end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    return unpack(results)
end)
