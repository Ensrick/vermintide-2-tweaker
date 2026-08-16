-- _ct_adventure_illusions.lua -- #917 preserve Adventure weapon illusions in CW.
--
-- Per-LOCAL-player snapshot of the melee/ranged Adventure illusions taken at
-- pilgrimage start (M.snapshot_now, called PRE-vanilla from the single merged
-- DeusMechanism._setup_run hook in _ct_run_runtime_owner.lua, BEFORE the
-- starter weapons are generated at deus_mechanism.lua:1098/:1134), plus a
-- compatibility-gated reapply that runs at the existing DeusWeaponGeneration
-- seams owned by _ct_weapon_trait_generation (_filtered_weapon_gen calls
-- apply_to_result as the LAST mutation on the detached generated result).
--
-- Compatibility gate: a saved skin is applied ONLY when its ItemMasterList
-- entry's `matching_item_key` (item_master_list.lua:80-83; usage :7814) equals
-- the generated weapon's base item key (`item.key = deus_item_data.base_item`,
-- deus_weapon_generation.lua:192). DeusWeapons base items ARE the Adventure
-- keys (deus_weapons.lua:17+ / DeusStartingWeaponTypeMapping :1510), so the
-- gate passes exactly for same-family weapons and never for any other family.
--
-- State rules (issue #917): the snapshot lives only on the owning peer's
-- machine and is only consulted for items that peer generates locally - the
-- deus item backend is per-peer, so starter/chest/altar generation for a
-- player always runs on that player's own machine. Nothing here is
-- host-global and nothing is sent over the wire; other peers see the skin
-- through vanilla weapon serialization (serialize_weapon writes item.skin,
-- deus_weapon_generation.lua:340-344). Upgrades carry the item's own current
-- compatible skin (never the snapshot), so host-side projections of OTHER
-- players' weapons (_ct_replacement_runtime) can never leak the host's skin.
-- Bot chest mirroring is excluded via the owner's bot_weapon_mirror_active
-- bracket; the vanilla _setup_run bot-loadout loop stays eligible, matching
-- vanilla's own hero-item sharing with bots (deus_mechanism.lua:1138).
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: one ordered mod:dofile installer call from
-- _ct_run_runtime_owner.lua (directly above its only apply seam,
-- _ct_weapon_trait_generation; the entry itself is frozen at its 1498-line
-- completion ceiling) and the runtime check
-- issue917_adventure_illusion_preservation in _ct_regression.lua; guarded by
-- qa/lua/tests/test_ct_adventure_illusions.lua.
return function(ctx)
    assert(type(ctx) == "table", "CT adventure illusions requires context")
    local mod = assert(ctx.mod, "CT adventure illusions requires mod")

    local M = {}
    local TOGGLE = "preserve_adventure_illusions"

    local state = mod._ct_adventure_illusions_state
    if not state then
        state = { snapshot = nil, suppressed = false, installed = false }
        mod._ct_adventure_illusions_state = state
    end

    -- Per-peer toggle by design (see PER_PEER_SETTING_NAMES): each player's
    -- illusions are their own local cosmetic choice; a host value would gate a
    -- purely-local presentation with no consistency benefit.
    local function _toggle_on()
        if type(mod.get) ~= "function" then return false end
        local ok, v = pcall(mod.get, mod, TOGGLE)
        return ok and v == true
    end

    -- The one compatibility gate. `item_master` is injectable for offline
    -- tests; runtime resolves the live global at call time.
    function M.compatible(skin_name, item_key, item_master)
        if type(skin_name) ~= "string" or type(item_key) ~= "string" then
            return false
        end
        item_master = item_master or rawget(_G, "ItemMasterList")
        if type(item_master) ~= "table" then return false end
        local skin_item = item_master[skin_name]
        return type(skin_item) == "table"
            and skin_item.matching_item_key == item_key
    end

    -- Build `adventure base key -> skin` from a career->slots->backend_id
    -- loadout table (the exact shape backend_items:get_loadout() returns and
    -- _setup_run walks, deus_mechanism.lua:1106-1124). Careers are overlaid in
    -- sorted order with the CURRENT career last, so when two careers carry the
    -- same weapon family with different illusions the played career wins.
    function M.build_snapshot(loadout, get_item, item_master, current_career)
        local snapshot = {}
        if type(loadout) ~= "table" or type(get_item) ~= "function" then
            return snapshot
        end
        local careers = {}
        for career_name in pairs(loadout) do
            careers[#careers + 1] = career_name
        end
        table.sort(careers, function(a, b) return tostring(a) < tostring(b) end)
        for pass = 1, 2 do
            for _, career_name in ipairs(careers) do
                local is_current = career_name == current_career
                if (pass == 1) ~= is_current then
                    local slots = loadout[career_name]
                    if type(slots) == "table" then
                        for slot, backend_id in pairs(slots) do
                            if slot == "slot_melee" or slot == "slot_ranged" then
                                local ok, item = pcall(get_item, backend_id)
                                local skin = ok and type(item) == "table" and item.skin
                                local key = ok and type(item) == "table" and item.key
                                if type(skin) == "string" and type(key) == "string"
                                    and M.compatible(skin, key, item_master) then
                                    snapshot[key] = skin
                                end
                            end
                        end
                    end
                end
            end
        end
        return snapshot
    end

    -- Pilgrimage-start capture from the live Adventure items backend (the same
    -- interface _setup_run reads 12 lines later). Toggle OFF clears any prior
    -- run's snapshot so a later mid-run toggle-on cannot resurrect stale data.
    function M.snapshot_now()
        if not _toggle_on() then
            state.snapshot = nil
            return nil
        end
        local backend = Managers and Managers.backend
        local items = backend and type(backend.get_interface) == "function"
            and backend:get_interface("items")
        if not (items and type(items.get_loadout) == "function"
            and type(items.get_item_from_id) == "function") then
            return nil
        end
        local ok, loadout = pcall(items.get_loadout, items)
        if not ok or type(loadout) ~= "table" then return nil end
        local current_career
        pcall(function()
            local player = Managers.player and Managers.player:local_player(1)
            if player and type(player.career_name) == "function" then
                current_career = player:career_name()
            end
        end)
        state.snapshot = M.build_snapshot(loadout, function(backend_id)
            return items:get_item_from_id(backend_id)
        end, rawget(_G, "ItemMasterList"), current_career)
        local count, parts = 0, {}
        for key, skin in pairs(state.snapshot) do
            count = count + 1
            parts[#parts + 1] = key .. "=" .. skin
        end
        table.sort(parts)
        pcall(printf, "[ct:issue917] adventure illusion snapshot: %d families (%s)",
            count, table.concat(parts, " "))
        return state.snapshot
    end

    -- Explicit exclusion bracket (also used by tests). Bot chest mirroring is
    -- additionally excluded by reading the owner's own state flag, so no other
    -- module needs editing.
    function M.suppress(on)
        state.suppressed = on == true
    end

    local function _suppressed()
        if state.suppressed then return true end
        local bot_state = mod._ct_bot_weapon_chest_owner_state
        return type(bot_state) == "table"
            and bot_state.bot_weapon_mirror_active == true
    end

    -- Called by _ct_weapon_trait_generation._filtered_weapon_gen as the LAST
    -- mutation on the detached generated item. `prior_item` is only passed on
    -- the upgrade_item path (the item being tempered).
    --   * upgrade_item: carry the item's OWN current compatible skin - vanilla
    --     rerolls skins per target rarity (deus_weapon_generation.lua:318-319).
    --     Never the snapshot: on this path the item may belong to a bot or,
    --     via replacement projection, to another player.
    --   * generate_* paths: apply the local snapshot skin for the generated
    --     family, if any. Wrong-family entries can never apply: the snapshot
    --     is keyed by matching_item_key AND re-gated per apply.
    function M.apply_to_result(label, result, prior_item)
        if type(result) ~= "table" or type(result.key) ~= "string" then
            return result
        end
        if not _toggle_on() or _suppressed() then return result end
        if label == "upgrade_item" then
            local prior_skin = type(prior_item) == "table" and prior_item.skin
            if type(prior_skin) == "string" and result.skin ~= prior_skin
                and M.compatible(prior_skin, result.key) then
                result.skin = prior_skin
                pcall(printf, "[ct:issue917] carried illusion through upgrade: key=%s skin=%s rarity=%s",
                    result.key, prior_skin, tostring(result.rarity))
            end
            return result
        end
        local snapshot = state.snapshot
        local saved = type(snapshot) == "table" and snapshot[result.key]
        if type(saved) == "string" and result.skin ~= saved
            and M.compatible(saved, result.key) then
            result.skin = saved
            pcall(printf, "[ct:issue917] applied adventure illusion: label=%s key=%s skin=%s",
                tostring(label), result.key, saved)
        end
        return result
    end

    -- Behavioral runtime check for /ct_regression_test (registered as
    -- issue917_adventure_illusion_preservation in _ct_regression.lua). Drives
    -- the real gate + apply functions on detached probe tables only.
    function M.regression_check()
        if not state.installed then
            return "adventure illusion module not installed"
        end
        local fake_master = {
            good_skin = { matching_item_key = "es_1h_mace" },
            wrong_family_skin = { matching_item_key = "es_2h_sword" },
        }
        if not M.compatible("good_skin", "es_1h_mace", fake_master) then
            return "compatibility gate rejects a matching skin"
        end
        if M.compatible("wrong_family_skin", "es_1h_mace", fake_master) then
            return "compatibility gate accepts a wrong-family skin"
        end
        if M.compatible("absent_skin", "es_1h_mace", fake_master)
            or M.compatible(nil, "es_1h_mace", fake_master) then
            return "compatibility gate accepts a missing skin"
        end
        local probe = { key = "es_1h_mace", skin = "vanilla_roll", rarity = "exotic" }
        local was_suppressed = state.suppressed
        M.suppress(true)
        M.apply_to_result("generate_item_from_item_key", probe, nil)
        M.suppress(was_suppressed)
        if probe.skin ~= "vanilla_roll" then
            return "suppressed apply mutated a generated result"
        end
    end

    -- NO hook lives here: DeusMechanism._setup_run already carries the #53
    -- belakor diagnostic hook in _ct_run_runtime_owner.lua, and VMF/mod-lint
    -- allow ONE hook per (Class, method) - the #917 pre-capture is merged into
    -- that single full hook (it calls M.snapshot_now BEFORE vanilla, which
    -- generates the starter weapons at deus_mechanism.lua:1098/:1134).
    state.installed = true

    return M
end
