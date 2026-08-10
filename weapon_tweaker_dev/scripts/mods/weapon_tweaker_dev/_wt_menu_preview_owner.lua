-- Menu/inventory preview surface owner (#1159).
--
-- Extracted verbatim from the entry: the mod's ONE
-- MenuWorldPreviewer.equip_item hook_safe (brace -> repeater body inline, plus
-- the longbow, repeating-pistol and Skullsplitter & Tome preview helpers it
-- dispatches to), the weak-keyed preview item-key capture that bridges
-- equip_item to _spawn_item_unit, the #603 Ranger dual-wield stance selector,
-- the _wt_paired_preview_transform install (#735), and the full
-- MenuWorldPreviewer._spawn_item_unit wrapper - pre-spawn attachment-source
-- validation, post-spawn scale/offset/rotation, the v0.12.146-dev preview
-- wield-pose correction, and the debug-gated missing-node probe.
--
-- The entry keeps a bare dofile at the former execution position, so hook
-- registration order is unchanged: this loads after the in-game 3P swap owner
-- and before the lifecycle callbacks. Two invariants travel with the code.
-- Hook the DERIVED MenuWorldPreviewer, never HeroPreviewer: VT2's class()
-- copies parent methods at definition time, so a base-class hook never fires
-- on the previewer instance (foundation/scripts/util/class.lua:51-57). And
-- hook_safe does not chain on a duplicate registration from the same mod,
-- which is why all four preview swap helpers share the single equip_item body.
--
-- 3P-ONLY: nothing here touches a 1P unit. Everything below the accessor block
-- is byte-identical to the lines it replaced, except the trailing mod._wt
-- publication that hands the #603 selector back to the entry's runtime-check
-- dependency table. Offline evidence:
-- qa/lua/tests/test_wt_menu_preview_owner.lua.

local mod = get_mod("wt_dev")

-- Late-binding accessors: the entry's file-scope locals do not cross the chunk
-- boundary. mod._wt carries the identical values the moved lines closed over,
-- published by the entry immediately above this module's load position.
local _dbg                              = mod._wt.dbg
local _local_career_name                = mod._wt.local_career_name
local _safe_has_anim                    = mod._wt.safe_has_anim
local _resolve_preview_wield_event      = mod._wt.resolve_preview_wield_event
local _is_sp_crossbow_presentation_item = mod._wt.is_sp_crossbow_presentation_item
local _BRACE_REPEATER_3P_UNIT           = mod._wt.brace_repeater_3p_unit
local _SP_CROSSBOW_3P_UNIT              = mod._wt.sp_crossbow_3p_unit
local _wt_skullsplitter_hand_policy     = mod._wt.skullsplitter_hand_policy
local _wt_validate_attachment_sources   = mod._wt.validate_attachment_sources
local _scale_weapon_units               = mod._wt.scale_weapon_units
local _resolve_grip_offset              = mod._wt.resolve_grip_offset
local _offset_weapon_units              = mod._wt.offset_weapon_units
local _resolve_rotation_override        = mod._wt.resolve_rotation_override
local _wt569_track_3p_units             = mod._wt.track_3p_rotation_units
local _wt_grip_offset_policy            = mod._wt.grip_offset_policy

-- Forward declarations for the helper functions defined below, called from
-- the consolidated `MenuWorldPreviewer.equip_item` hook_safe below. Without
-- these, the closure resolves the identifiers as nil globals
-- (feedback_lua_forward_reference).
local _wt_longbow_preview_swap_apply
local _wt_repeating_pistol_preview_swap_apply
local _wt_hammer_book_preview_swap_apply
local _wt_capture_preview_item_key


-- Character preview path: swap brace 3P → repeater 3P on Kruber.
-- The in-game spawn flow goes through GearUtils.spawn_inventory_unit (hooked
-- above); the keep inventory previewer does NOT — it calls
-- World.spawn_unit(world, unit_name) directly from precomputed `spawn_data`
-- built in equip_item. So the brace pistol mesh still rendered on the
-- inventory character preview while the in-game 3P showed the repeater
-- correctly.
--
-- Fix: post-hook equip_item, then mutate the stored spawn_data:
--   * right-hand entry: rewrite `unit_name` → _BRACE_REPEATER_3P_UNIT
--   * left-hand entry: drop it (vanilla brace's left pistol clips the
--     repeater body; mirrors the show_third_person_inventory hide above)
-- The repeater 3P unit is already force-loaded at mod init (see
-- _force_load_brace_repeater_3p_unit) so World.spawn_unit resolves it.
--
-- CRITICAL: hook MenuWorldPreviewer, NOT HeroPreviewer. The keep inventory
-- (HeroWindowCharacterPreview, character-select, store, loot) all
-- instantiate MenuWorldPreviewer. VT2's foundation class() helper COPIES
-- parent methods into the child at class-definition time (no __index
-- chain — see foundation/scripts/util/class.lua:51-57), so after
-- `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs
-- at game load, MenuWorldPreviewer.equip_item is a static copy of
-- HeroPreviewer.equip_item. VMF mod:hook("HeroPreviewer", "equip_item")
-- replaces HeroPreviewer.equip_item but NOT MenuWorldPreviewer.equip_item;
-- the previewer instance dispatches through the copy and the hook never
-- fires. See feedback_vt2_class_hook_derived.
--
-- v0.12.25 consolidation: this is the ONLY mod:hook_safe registration for
-- equip_item from this mod. It dispatches to the longbow swap and item-key
-- capture helpers defined below. Previously each lived in its own hook_safe
-- registration; only the LAST one actually fired because hook_safe does not
-- chain on duplicate registrations from the same mod (feedback_vmf_hook_safe_no_chain).
mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_name, slot, backend_id, skin, skip_wield_anim)
    -- Helper 1: capture item key for the `_spawn_item_unit` hook (below) to
    -- look up. Always fires (item-name-agnostic).
    _wt_capture_preview_item_key(self, item_name, slot)

    -- Helper 2: longbow → crossbow preview swap (Saltzpyre careers).
    _wt_longbow_preview_swap_apply(self, item_name, slot)

    -- Helper 3: repeating pistol → repeating handgun preview swap (Kruber careers).
    _wt_repeating_pistol_preview_swap_apply(self, item_name, slot)

    -- Helper 4: Skullsplitter & Tome → 1H Skullsplitter preview swap (Kruber, #181).
    _wt_hammer_book_preview_swap_apply(self, item_name, slot)

    -- Inline body: brace → repeater preview swap (Kruber careers).
    if item_name ~= "wh_brace_of_pistols" then return end
    local career = self._current_career_name
    if not career or career:sub(1, 3) ~= "es_" then return end

    local slot_type = (type(slot) == "table" and slot.type) or nil
    if not slot_type then return end
    local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return end

    local new_spawn_data = {}
    local swapped = false
    for _, entry in ipairs(info.spawn_data) do
        if entry.right_hand then
            entry.unit_name = _BRACE_REPEATER_3P_UNIT
            entry.despawn_both_hands_units = nil
            new_spawn_data[#new_spawn_data + 1] = entry
            swapped = true
        elseif entry.left_hand then
            -- drop; brace's left pistol would clip the repeater body
        else
            new_spawn_data[#new_spawn_data + 1] = entry
        end
    end
    info.spawn_data = new_spawn_data

    if swapped then
        _dbg("[wt brace-3p-swap preview] swapped preview 3P brace -> repeater on career=%s", career)
    end
end)

-- Inventory preview swap for Saltzpyre's es_longbow → crossbow visual.
-- Same MenuWorldPreviewer.equip_item pattern as the brace hook above
-- (NOT HeroPreviewer — see comment block above the brace hook). Mutates
-- the left_hand spawn_data entry's `unit_name` to point at the crossbow
-- 3P unit. No ammo swap in preview path because vanilla preview doesn't
-- spawn the bow's arrow (`world_hero_previewer.lua:680-712` only handles
-- left_hand/right_hand entries; ammo_unit isn't fed through the preview
-- spawn pipeline — see line 689 conditional that's about is_ammo_weapon
-- THROWN items like javelins, not about arrows on bows).
--
-- v0.12.25: was its own `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)`
-- registration; consolidated into the brace hook above because hook_safe
-- chain does NOT chain on duplicate registrations from the same mod — only
-- the last one fires (feedback_vmf_hook_safe_no_chain). The brace hook calls
-- this helper unconditionally on every equip_item; helper short-circuits when
-- item_name isn't the longbow.
_wt_longbow_preview_swap_apply = function(self, item_name, slot)
    if not _is_sp_crossbow_presentation_item(item_name) then return end
    local career = self._current_career_name
    if not career or career:sub(1, 3) ~= "wh_" then return end

    local slot_type = (type(slot) == "table" and slot.type) or nil
    if not slot_type then return end
    local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return end

    -- Source the empire crossbow's attachment-node table (NOT the longbow's).
    -- The longbow's `unit_attachment_node_linking.third_person.unwielded`
    -- references `a_unwielded_bow`, a skeleton node that exists on the
    -- elf and empire BODIES but NOT on Saltzpyre's 3P body. When the
    -- previewer mounts the holstered (unwielded) weapon, `Unit.node` raises
    -- an engine-level fatal that bypasses pcall (see
    -- feedback_vt2_unit_node_not_pcall_safe). crashify://f210b3b7. We must
    -- substitute the crossbow's attachment table here in addition to the
    -- mesh swap below — crossbow_template_1 is the WH crossbow Saltzpyre
    -- uses natively, so its `left_hand_attachment_node_linking.third_person`
    -- references nodes that DO exist on his body.
    local xbow_linking_3p
    local xbow_tpl = Weapons and Weapons.crossbow_template_1
    if xbow_tpl and xbow_tpl.left_hand_attachment_node_linking
                and xbow_tpl.left_hand_attachment_node_linking.third_person then
        xbow_linking_3p = xbow_tpl.left_hand_attachment_node_linking.third_person
    else
        mod:warning("[wt sp-longbow-crossbow preview] crossbow_template_1.left_hand_attachment_node_linking.third_person missing; skipping unit_name swap to avoid a_unwielded_bow crash on career=%s", career)
        return
    end

    local swapped = false
    for _, entry in ipairs(info.spawn_data) do
        if entry.left_hand then
            entry.unit_name = _SP_CROSSBOW_3P_UNIT
            entry.unit_attachment_node_linking = xbow_linking_3p
            swapped = true
        end
    end

    if swapped then
        _dbg("[wt sp-longbow-crossbow preview] swapped preview 3P bow -> crossbow on career=%s (unit_name + unit_attachment_node_linking)", career)
    end
end

-- Inventory preview swap for Kruber's wh_repeating_pistols → repeating handgun
-- visual. Same `MenuWorldPreviewer.equip_item` pattern as the longbow helper.
-- Mutates the right_hand spawn_data entry's `unit_name` AND
-- `unit_attachment_node_linking` because the source `repeater_pistol`
-- attachment-node table references weapon-mesh-side nodes (`lock_hammer`,
-- `rotator`, `trigger_t1`) that don't exist on the repeating handgun mesh —
-- linking via them would `Unit.node` engine fatal that bypasses pcall
-- (feedback_vt2_unit_node_not_pcall_safe). Substituting the target template's
-- whole `third_person` table fixes both wielded and unwielded paths.
--
-- Right-hand-only — no left-hand drop like the brace's two-pistol layout.
_wt_repeating_pistol_preview_swap_apply = function(self, item_name, slot)
    if item_name ~= "wh_repeating_pistols" then return end
    local career = self._current_career_name
    if not career or career:sub(1, 3) ~= "es_" then return end

    local slot_type = (type(slot) == "table" and slot.type) or nil
    if not slot_type then return end
    local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return end

    local handgun_linking_3p
    local handgun_tpl = Weapons and Weapons.repeating_handgun_template_1
    if handgun_tpl and handgun_tpl.right_hand_attachment_node_linking
                  and handgun_tpl.right_hand_attachment_node_linking.third_person then
        handgun_linking_3p = handgun_tpl.right_hand_attachment_node_linking.third_person
    else
        mod:warning("[wt rp-pistol-handgun preview] repeating_handgun_template_1.right_hand_attachment_node_linking.third_person missing; skipping unit_name swap to avoid weapon-mesh node fatal on career=%s", career)
        return
    end

    local swapped = false
    for _, entry in ipairs(info.spawn_data) do
        if entry.right_hand then
            entry.unit_name = _BRACE_REPEATER_3P_UNIT
            entry.unit_attachment_node_linking = handgun_linking_3p
            swapped = true
        end
    end

    if swapped then
        _dbg("[wt rp-pistol-handgun preview] swapped preview 3P pistol -> handgun on career=%s (unit_name + unit_attachment_node_linking)", career)
    end
end

-- Inventory-preview mirror for Kruber's wh_hammer_book (#181). The previewer bypasses
-- GearUtils.spawn_inventory_unit and consumes precomputed spawn_data directly, so the
-- same transaction must drop the right/book entry and reclassify the existing
-- left/hammer entry as a right-hand unit using receiver-native linking.
_wt_hammer_book_preview_swap_apply = function(self, item_name, slot)
    _wt_skullsplitter_hand_policy.apply_preview(
        self, item_name, slot, rawget(_G, "Weapons"), printf)
end

-- Apply scale/offset to the inventory character preview.
-- The keep inventory uses MenuWorldPreviewer (see notes above the
-- brace-3P swap hook — class() copies parent methods, so hooks on
-- HeroPreviewer.equip_item never fire on MenuWorldPreviewer instances).
local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

-- _spawn_item_unit only sees the weapon template (e.g. we_one_hand_axe_template),
-- not the inventory item, so its item_data.name is NOT the weapon key. We
-- capture the mapping (per previewer, weak-keyed so it doesn't pin the
-- previewer in memory) at equip time and look it up at spawn.
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

-- v0.12.25: same hook_safe-no-chain consolidation as the longbow preview
-- helper above. Called unconditionally from the brace `equip_item` hook.
_wt_capture_preview_item_key = function(self, item_key, slot)
    if item_key and type(item_key) == "string" then
        local slot_name = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
        if slot_name then
            local slot_type = slot_name:gsub("^slot_", "")
            local map = _mwp_pending_keys[self]
            if not map then map = {}; _mwp_pending_keys[self] = map end
            map[slot_type] = item_key
        end
    end
end

-- #603: `to_dual_axes` selects the Slayer-style stance on the Ranger preview
-- body even though the body reports that event as authored. Ranger Veteran's
-- known-good non-Slayer dual-wield stance is `to_dual_hammers`, so select it
-- only for this exact inventory-preview tuple. Dual Hammers are the control,
-- Slayer stays native, and no in-mission animation surface calls this helper.
local function _wt603_post_spawn_preview_event(weapon_key, career_name, fired_event)
    if weapon_key == "dr_dual_wield_axes"
            and career_name == "dr_ranger"
            and fired_event == "to_dual_axes" then
        return "to_dual_hammers"
    end
    return nil
end

local _wt_paired_preview_transform = mod:dofile(
    "scripts/mods/weapon_tweaker_dev/_wt_paired_preview_transform")
_wt_paired_preview_transform.install(mod, {
    local_career_name = _local_career_name, resolve_rotation = _resolve_rotation_override,
    resolve_offset = _resolve_grip_offset, offset_weapon_units = _offset_weapon_units,
    track_rotation = _wt569_track_3p_units, is_unit = _is_unit,
    policy = _wt_grip_offset_policy,
})

-- v0.12.114-dev: converted from hook_safe to mod:hook (full wrapper) so we
-- can PRE-VALIDATE attachment_node_linking before the original _spawn_item_unit
-- calls link_units. Previously hook_safe ran AFTER spawn (post-crash, useless
-- for prevention). The PRE check substitutes any source nodes that the
-- target body doesn't actually have (e.g. j_leftweaponcomponent16 on a non-
-- elf body) with j_hips. Elves keep their native nodes because Unit.has_node
-- returns true. Replaces the broken boot-time global mutation that
-- v0.12.112/.113-dev shipped (which broke elf bow visibility).
mod:hook("MenuWorldPreviewer", "_spawn_item_unit", function(func, self, unit, slot_type, item_template, attachment_node_linking, scene_graph_links, material_settings_name, skip_wield_anim)
    -- PRE: validate attachment sources against the actual body unit to
    -- prevent engine-fatal Unit.node() on missing-node lookups.
    if self and _is_unit(self.character_unit) then
        _wt_validate_attachment_sources(self.character_unit, attachment_node_linking)
    end

    -- Call through. Multi-return capture per VMF_RECIPES.md § 2.
    local r1, r2, r3 = func(self, unit, slot_type, item_template,
        attachment_node_linking, scene_graph_links, material_settings_name,
        skip_wield_anim)

    -- POST: scale / offset + diagnostic probe (original hook_safe logic).
    if not unit or not _is_unit(unit) then return r1, r2, r3 end
    local map = _mwp_pending_keys[self]
    local weapon_key = map and map[slot_type]
    if not weapon_key then return r1, r2, r3 end
    local career_name = _local_career_name() or self._character_name
                        or (self._profile and self._profile.name)
    if not career_name then return r1, r2, r3 end

    local default_field = _wt_grip_offset_policy.preview_slot_field(item_template)
    local fake_slot = { [default_field] = unit }
    _scale_weapon_units(fake_slot, weapon_key, career_name)
    local offset_field = _wt_grip_offset_policy.preview_slot_field(
        item_template, _resolve_grip_offset(weapon_key, career_name))
    if offset_field then
        _offset_weapon_units({ [offset_field] = unit }, weapon_key, career_name)
    end
    local rotation_field = _wt_grip_offset_policy.preview_slot_field(
        item_template, _resolve_rotation_override(weapon_key, career_name))
    if rotation_field then
        _wt569_track_3p_units({ [rotation_field] = unit }, weapon_key, career_name,
            item_template, nil, slot_type,
            not skip_wield_anim and self._wielded_slot_type == slot_type,
            "inventory_preview")
    end

    -- v0.12.146-dev: INVENTORY-PREVIEW WIELD POSE (3P-ONLY). Correct the wield
    -- stance for cross-character ports whose wield_anim_career_3p entry omits the
    -- previewed career's prefix (so the engine fell back to the source template's
    -- base wield_anim and fired an event the receiver body doesn't author -> the
    -- "missing pose" symptom; e.g. Elf Greatsword `to_2h_sword_we` on Kruber).
    -- The previewer fires the wield event ONLY for the currently-wielded slot
    -- (world_hero_previewer.lua:1056 `self._wielded_slot_type == item_slot_type`),
    -- so gate on that to avoid re-posing the off-hand slot. Re-uses the SAME
    -- `_career_anim_redirect` data the in-mission hook uses (no parallel table)
    -- via `_resolve_preview_wield_event`. Strictly 3P: only `self.character_unit`.
    if not skip_wield_anim
            and self._wielded_slot_type == slot_type
            and type(item_template) == "table" then
        local preview_body = self.character_unit
        local preview_career = self._current_career_name or career_name
        if preview_body and _is_unit(preview_body) and preview_career then
            -- The event the engine actually fired (mirror world_hero_previewer
            -- get_wield_anim: wield_anim_career_3p[career] -> base wield_anim).
            local wac3p = item_template.wield_anim_career_3p
            local fired = (wac3p and wac3p[preview_career]) or item_template.wield_anim
            -- #603 evidence: Ranger Dual Axes resolves to `to_dual_axes`, and
            -- the preview body authors both dual-wield events. User verification
            -- established that `to_dual_axes` is the Slayer-style preview pose;
            -- the exact Ranger/Axes tuple is corrected to the known-good
            -- non-Slayer `to_dual_hammers` stance below. Preview-only.
            if preview_career == "dr_ranger"
                    and (weapon_key == "dr_dual_wield_hammers"
                        or weapon_key == "dr_dual_wield_axes") then
                mod._wt603_preview_diag_seen = mod._wt603_preview_diag_seen or {}
                local diag_key = tostring(weapon_key) .. "\0" .. tostring(fired)
                if not mod._wt603_preview_diag_seen[diag_key] then
                    mod._wt603_preview_diag_seen[diag_key] = true
                    mod:info("[wt:603] Ranger preview weapon=%s fired=%s has_fired=%s has_dual_axes=%s has_dual_hammers=%s",
                        tostring(weapon_key), tostring(fired),
                        tostring(fired and _safe_has_anim(preview_body, fired) or false),
                        tostring(_safe_has_anim(preview_body, "to_dual_axes")),
                        tostring(_safe_has_anim(preview_body, "to_dual_hammers")))
                end
            end
            local post_spawn_event = _wt603_post_spawn_preview_event(
                weapon_key, preview_career, fired)
            if post_spawn_event and _safe_has_anim(preview_body, post_spawn_event) then
                pcall(Unit.animation_event, preview_body, post_spawn_event)
            end
            if fired then
                local resolved = _resolve_preview_wield_event(preview_body, fired, preview_career)
                -- Only correct when the redirect resolves to a DIFFERENT,
                -- body-authored event AND the engine's fired event is NOT
                -- itself authored (i.e. it was the missing-pose fallback). If
                -- the body authors `fired`, the engine already posed correctly.
                if resolved and resolved ~= fired
                        and not _safe_has_anim(preview_body, fired)
                        and _safe_has_anim(preview_body, resolved) then
                    _dbg("[wt:preview_wield] career=%s template_wield=%s -> %s (missing-pose fix)",
                        tostring(preview_career), tostring(fired), tostring(resolved))
                    pcall(Unit.animation_event, preview_body, resolved)
                end
            end
        end
    end

    -- DIAGNOSTIC v0.12.94-dev: cross-character attachment node-presence probe.
    -- v0.12.93-dev shipped this reading the GLOBAL weapon template, which was
    -- WRONG -- the global template intentionally stays untouched (Saltzpyre's
    -- vanilla flow needs `a_unwielded_crossbow` and other body-specific
    -- nodes). The engine actually reads from the SPAWN_DATA entry's
    -- `unit_attachment_node_linking` field, which is what per-spawn helpers
    -- substitute. Read from the same table the engine reads so we get TRUE
    -- positives only.
    --
    -- Walk every spawn_data entry on every slot the previewer is currently
    -- displaying, look at the actually-attached `unit_attachment_node_linking`
    -- (the post-substitution table when a helper fired), check each source
    -- node against the live character body. A missing node here USED to be an
    -- imminent engine fatal, but the universal GearUtils.link_units guard
    -- (WT_LINK_UNITS_NODE_GUARD_MARKER, below) now drops any missing-node link
    -- before vanilla's Unit.node can fatal, on every spawn path -- so this probe
    -- is now a benign, debug-gated trace (it flags a boot-substitution gap, not a
    -- crash). Kept as a diagnostic; downgraded from _dbg_alert to _dbg in v0.12.202.
    local body = self.character_unit
    if not body or not _is_unit(body) then return r1, r2, r3 end
    local info_by_slot = self._item_info_by_slot
    if type(info_by_slot) ~= "table" then return r1, r2, r3 end
    for slot_name, info in pairs(info_by_slot) do
        local entries = info and info.spawn_data
        if type(entries) == "table" then
            for entry_idx, entry in ipairs(entries) do
                local link = entry.unit_attachment_node_linking
                if type(link) == "table" then
                    for _, state in ipairs({ "display", "wielded", "unwielded" }) do
                        local arr = link[state]
                        if type(arr) == "table" then
                            for _, e in ipairs(arr) do
                                local src = e and e.source
                                if type(src) == "string"
                                        and not Unit.has_node(body, src) then
                                    -- v0.12.202-dev: NOT fatal. The universal
                                    -- GearUtils.link_units guard (WT_LINK_UNITS_NODE_GUARD
                                    -- _MARKER) drops this link before vanilla's
                                    -- Unit.node (gear_utils.lua:297-298) can engine-fatal,
                                    -- on every spawn path. So this is a benign debug trace
                                    -- (a boot-substitution gap, e.g. a_unwielded_staff on a
                                    -- Kruber ranged slot), routed through _dbg (debug-gated,
                                    -- log-only) -- NOT _dbg_alert. Was a chat-spamming false
                                    -- alarm before (#240).
                                    _dbg(
                                        "[wt:attach_probe] missing node on body "
                                        .. "(career=%s slot=%s entry=%d state=%s source=%s) "
                                        .. "-- neutralized by link_units guard, not fatal",
                                        tostring(career_name), tostring(slot_name),
                                        entry_idx, state, src)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return r1, r2, r3
end)

-- Published back for the entry's runtime-check dependency table:
-- /wt_regression_test asserts the #603 Ranger stance selector, which now lives
-- in this module rather than in the entry's file scope.
mod._wt.post_spawn_preview_event = _wt603_post_spawn_preview_event
