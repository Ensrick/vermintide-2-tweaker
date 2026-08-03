-- Issue #748: Anim Picker TARGET-side vocabulary gate.
--
-- The picker's per-SET dropdown OPTIONS (`_SET_VOCAB` / `_SALTZ_SET_VOCAB` /
-- `_KERI_SET_VOCAB`, wt_dev_anim_picker.lua) are hardcoded target events the
-- apply path writes verbatim as `anim_event_3p`. The 3P body plays that event
-- (weapon_utils.lua:211 get_item_template -> WeaponUnitExtension.start_action
-- reads current_action_settings.anim_event_3p per swing), so an event the
-- receiver-native TARGET template never fires on the 3P body idles silently
-- (#196 fallthrough class: listing a 1P anim_event name whose sub-action
-- carries a divergent anim_event_3p, e.g. billhook attack_swing_charge_stab).
-- #411 gates the SOURCE side (every picker source event resolves to an
-- authored write site); this is its TARGET-side mirror: every SET vocab event
-- must exist in the receiver template's EFFECTIVE 3P vocabulary.
--
-- This gate is deliberately qa-layer ONLY: the shipped picker file is loaded
-- and parsed READ-ONLY here (no shipped-mod change, no version bump, no
-- parity/atomicity impact). The static vocab tables are extracted from the
-- picker source text, then cross-checked against the loaded module's own
-- M.set_vocab_for() surface so the extraction cannot drift from what the
-- shipped module actually advertises.
--
-- Fixture: qa/lua/tests/fixtures/wt_picker_target_3p_vocab.lua, generated from
-- the decompiled VT2 weapon templates: per TARGET template, the effective 3P
-- event per top-level sub-action = anim_event_3p when authored, else
-- anim_event (nested custom_*_anim_data excluded, same doctrine as the #411
-- fixture). Regenerate by executing each listed template file under Lua 5.1
-- with stubbed engine globals and collecting
-- actions.<action>.<sub_action>.(anim_event_3p or anim_event).
return function(H, repo_root)
    local picker_path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_dev_anim_picker.lua"
    local fixture = dofile(repo_root
        .. "/qa/lua/tests/fixtures/wt_picker_target_3p_vocab.lua")

    -- (receiver, SET letter) -> receiver-native TARGET weapon template whose
    -- effective 3P vocabulary the SET's dropdown options must live inside.
    -- Resolved from the picker's own _SET_LABEL/_SET_VOCAB per-set comments and
    -- verified against the decompiled template files named there.
    local TARGET_TEMPLATE = {
        kruber = {
            A = "two_handed_hammers_template_1",       -- Greathammer (2h_hammers.lua)
            B = "dual_wield_hammer_sword_template",    -- Mace & Sword (dual_wield_hammer_sword.lua)
            C = "one_handed_swords_template_1",        -- Empire 1H Sword (1h_swords.lua)
            D = "one_handed_hammer_shield_template_1", -- Mace & Shield (1h_hammers_shield.lua)
            E = "one_hand_axe_template_1",             -- WH 1H Axe (1h_axes.lua)
            F = "one_handed_hammer_template_1",        -- 1H Mace/Skullsplitter (1h_hammers.lua)
        },
        saltzpyre = {
            A = "two_handed_hammer_priest_template",   -- WP Greathammer (2h_hammers_priest.lua)
            B = "dual_wield_hammers_priest_template",  -- WP Dual Hammers (dual_wield_hammers_priest.lua)
            C = "dual_wield_axe_falchion_template",    -- Axe & Falchion (dual_wield_axe_falchion.lua)
            D = "fencing_sword_template_1",            -- Rapier (fencing_swords.lua)
            E = "one_hand_falchion_template_1",        -- 1H Falchion (1h_falchions.lua)
            F = "two_handed_billhooks_template",       -- Billhook (2h_billhooks.lua; #196 anim_event_3p column)
            G = "two_handed_swords_template_1",        -- 2H Sword (2h_swords.lua)
        },
        kerillian = {
            A = "two_handed_axes_template_2",          -- Elf 2H Axe/Glaive (2h_axes_wood_elf.lua)
            B = "two_handed_swords_wood_elf_template", -- Elf 2H Sword (2h_swords_wood_elf.lua)
            C = "we_one_hand_sword_template_1",        -- Elf 1H Sword (1h_swords_wood_elf.lua)
            D = "we_one_hand_axe_template",            -- Elf 1H Axe (1h_axes_wood_elf.lua:1070 up->up_left)
            E = "one_handed_spears_shield_template",   -- Elf Spear & Shield (1h_spears_shield.lua)
            F = "dual_wield_swords_template_1",        -- Dual Swords (dual_wield_swords.lua)
            G = "dual_wield_sword_dagger_template_1",  -- Sword & Dagger (dual_wield_sword_dagger.lua)
            H = "javelin_template",                    -- Elf Javelin (javelin.lua)
        },
    }

    local file = assert(io.open(picker_path, "rb"))
    local source = file:read("*a")
    file:close()

    -- Extract `local <name> = { ... }` from the picker source as a real table
    -- without executing the module (same extractor as the #411 test). The brace
    -- scan honours line comments and double-quoted strings (the picker's static
    -- tables use only double-quoted literals, no long brackets, no escapes).
    local function extract_table(name)
        local anchor = "local " .. name .. " = {"
        local start_at = source:find(anchor, 1, true)
        H.truthy(start_at, name .. " not found in picker source")
        local open_at = start_at + #anchor - 1
        local pos, depth, n = open_at, 0, #source
        while pos <= n do
            local c = source:sub(pos, pos)
            if c == '"' then
                local close = source:find('"', pos + 1, true)
                H.truthy(close, "unterminated string literal inside " .. name)
                pos = close
            elseif c == "-" and source:sub(pos + 1, pos + 1) == "-" then
                pos = (source:find("\n", pos, true) or n + 1) - 1
            elseif c == "{" then
                depth = depth + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then
                    local literal = source:sub(open_at, pos)
                    local chunk = assert(loadstring("return " .. literal,
                        "@picker:" .. name))
                    return chunk()
                end
            end
            pos = pos + 1
        end
        error("unbalanced braces extracting " .. name)
    end

    -- receiver -> { vocab = SET -> {events}, weapon_set = weapon_key -> SET }.
    -- Mirrors the picker's _RECV dispatch table (kruber / saltzpyre / kerillian).
    local catalog = {
        kruber = {
            vocab = extract_table("_SET_VOCAB"),
            weapon_set = extract_table("_WEAPON_SET"),
        },
        saltzpyre = {
            vocab = extract_table("_SALTZ_SET_VOCAB"),
            weapon_set = extract_table("_SALTZ_WEAPON_SET"),
        },
        kerillian = {
            vocab = extract_table("_KERI_SET_VOCAB"),
            weapon_set = extract_table("_KERI_WEAPON_SET"),
        },
    }

    -- Load the shipped module READ-ONLY under a get_mod stub so the textual
    -- extraction can be cross-checked against its public surface.
    local prior_get_mod = _G.get_mod
    _G.get_mod = function()
        return {
            dofile = function(_, path)
                return dofile(repo_root .. "/weapon_tweaker_dev/" .. path .. ".lua")
            end,
            debug = function() end,
            warning = function() end,
            info = function() end,
            get = function() return nil end,
        }
    end
    local ok, picker = pcall(dofile, picker_path)
    _G.get_mod = prior_get_mod
    if not ok then error(picker) end

    H.test("WT #748 extracted vocab catalogue matches the shipped module surface", function()
        for receiver, tables in pairs(catalog) do
            for set, events in pairs(tables.vocab) do
                local advertised = picker.set_vocab_for(receiver, set)
                H.truthy(advertised, receiver .. "/SET " .. set
                    .. " missing from the loaded module's set-vocab surface")
                H.deep_equal(advertised, events, receiver .. "/SET " .. set
                    .. " extraction drifted from M.set_vocab_for")
            end
        end
        H.equal(picker.set_vocab_for("kruber", "no_such_set"), nil)
    end)

    H.test("WT #748 every picker target event exists in the receiver's effective 3P vocabulary", function()
        local receivers = 0
        local events_checked = 0
        for receiver, tables in pairs(catalog) do
            receivers = receivers + 1
            local template_by_set = TARGET_TEMPLATE[receiver]
            H.truthy(template_by_set, receiver .. " missing from TARGET_TEMPLATE")
            for set in pairs(template_by_set) do
                H.truthy(tables.vocab[set], receiver .. "/SET " .. set
                    .. " mapped in TARGET_TEMPLATE but has no picker vocab; prune the map")
            end
            for weapon_key, set in pairs(tables.weapon_set) do
                H.truthy(tables.vocab[set], receiver .. "/" .. weapon_key
                    .. " assigned SET " .. tostring(set)
                    .. " which has no vocab (empty dropdowns)")
            end
            for set, events in pairs(tables.vocab) do
                local label = receiver .. "/SET " .. set
                local template = template_by_set[set]
                H.truthy(template, label
                    .. " has no TARGET_TEMPLATE entry; map the new SET's receiver template")
                local universe = fixture[template]
                H.truthy(universe, label .. " template " .. tostring(template)
                    .. " missing from fixture; regenerate wt_picker_target_3p_vocab.lua")
                H.truthy(#events > 0, label .. " advertises zero target events")
                local seen = {}
                for _, event in ipairs(events) do
                    H.truthy(not seen[event],
                        label .. " duplicate target event " .. tostring(event))
                    seen[event] = true
                    H.truthy(universe and universe[event],
                        label .. " target event '" .. tostring(event)
                        .. "' is NOT in the effective 3P vocabulary of "
                        .. tostring(template)
                        .. " (the #196 idle-fallthrough class)")
                    events_checked = events_checked + 1
                end
            end
        end
        H.equal(receivers, 3)
        H.truthy(events_checked >= 150,
            "catalogue suspiciously small: " .. events_checked .. " events")
    end)

    H.test("WT #748 divergent 1P anim_event names stay out of the target vocab", function()
        -- Billhook (#196 origin): 2h_billhooks.lua authors divergent
        -- anim_event_3p on its charge/heavy attacks (:12/:76/:139/:203), so the
        -- 1P anim_event names must be absent from BOTH the fixture universe and
        -- the saltzpyre SET F vocab.
        local billhook = fixture.two_handed_billhooks_template
        H.truthy(billhook, "two_handed_billhooks_template missing from fixture")
        H.truthy(billhook.attack_swing_stab_charge,
            "billhook fixture lost the 3P charge-stab event; misgenerated")
        H.equal(billhook.attack_swing_charge_stab, nil,
            "billhook fixture lists the divergent 1P charge-stab name (#196)")
        local saltz_f = catalog.saltzpyre.vocab.F or {}
        for _, event in ipairs(saltz_f) do
            H.truthy(event ~= "attack_swing_charge_stab"
                and event ~= "attack_swing_charge_down"
                and event ~= "attack_swing_heavy_down",
                "saltzpyre/SET F advertises billhook 1P name '" .. event
                .. "' again (#196)")
        end
        -- Elf 1H Axe: 1h_axes_wood_elf.lua:1070 authors
        -- anim_event_3p=attack_swing_up_left over anim_event=attack_swing_up.
        local elf_axe = fixture.we_one_hand_axe_template
        H.truthy(elf_axe, "we_one_hand_axe_template missing from fixture")
        H.truthy(elf_axe.attack_swing_up_left,
            "elf axe fixture lost the 3P up-left event; misgenerated")
        H.equal(elf_axe.attack_swing_up, nil,
            "elf axe fixture lists the divergent 1P up name (#196)")
    end)
end
