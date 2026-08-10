-- In-game 3P weapon-mesh swap owner (#1159).
--
-- Extracted verbatim from the entry: the single GearUtils.spawn_inventory_unit
-- registration (the cross-character 3P mesh-swap dispatch, with the Kruber
-- brace-of-pistols -> repeating-handgun body inline) plus the three per-weapon
-- swap helpers it dispatches to - Saltzpyre longbow -> empire crossbow (weapon
-- AND ammo unit), Kruber repeating pistols -> repeating handgun, and the #181
-- Kruber Skullsplitter & Tome -> one-handed Skullsplitter hand policy.
--
-- The entry keeps a bare dofile at the former execution position, so hook
-- registration order is unchanged, and that order is load-bearing: this
-- dispatch must register after _wt_weapon_balance_patches and
-- _wt_moonfire_aoe (both append to NetworkLookup at load) and before the
-- preview owner. VMF silently drops a second hook on the same (Class, method),
-- so this file owns the ONLY GearUtils.spawn_inventory_unit registration in
-- the mod; the three helpers are called as plain functions and are never
-- re-hooked (docs/VMF_RECIPES.md section 1).
--
-- 3P-ONLY: no helper here touches a *_unit_1p, because first person is
-- universal across all six characters (memory
-- feedback_1p_animations_universal). Everything below the accessor block is
-- byte-identical to the lines it replaced. Offline evidence:
-- qa/lua/tests/test_wt_ingame_3p_swap_owner.lua.

local mod = get_mod("wt_dev")

-- Late-binding accessors: the entry's file-scope locals do not cross the chunk
-- boundary. mod._wt carries the identical values the moved lines closed over,
-- published by the entry immediately above this module's load position.
local _dbg                              = mod._wt.dbg
local _dbg_alert                        = mod._wt.dbg_alert
local _unit_career_name                 = mod._wt.unit_career_name
local _is_sp_crossbow_presentation_item = mod._wt.is_sp_crossbow_presentation_item
local _BRACE_REPEATER_3P_UNIT           = mod._wt.brace_repeater_3p_unit
local _SP_CROSSBOW_3P_UNIT              = mod._wt.sp_crossbow_3p_unit
local _SP_CROSSBOW_BOLT_3P_UNIT         = mod._wt.sp_crossbow_bolt_3p_unit
local _wt_skullsplitter_hand_policy     = mod._wt.skullsplitter_hand_policy

-- Forward declarations for swap helpers defined below — the brace hook closes
-- over them before their `local function` declaration line, so without these
-- the identifiers resolve to nil globals at hook runtime
-- (feedback_lua_forward_reference).
local _wt_longbow_3p_swap_apply
local _wt_repeating_pistol_3p_swap_apply
local _wt_hammer_book_3p_swap_apply

-- Hook GearUtils.spawn_inventory_unit. Always call vanilla first, capture
-- all 4 returns (v_w3p, v_a3p, v_w1p, v_a1p), then attempt the swap inside
-- a pcall so any failure returns vanilla's units unchanged. Equipping
-- never fails because of this swap.
-- v0.12.77 (Issue #26): converted to `mod:safe_hook`. The per-weapon swap
-- helpers below (_wt_brace_3p_swap_apply / _wt_longbow_3p_swap_apply /
-- _wt_repeating_pistol_3p_swap_apply) already pcall their own bodies, but
-- the outer dispatch + return-value plumbing was bare. safe_hook gives
-- chain-isolation belt-and-suspenders on top.
-- v0.12.84-dev: promoted to `mod:traced_hook` (Layer 3). This is the
-- cross-character 3P swap dispatch — the canonical 5-return / 2-nil-hole
-- function (`weapon_3p, ammo_3p, weapon_1p, ammo_1p` with melee nils) that
-- motivated the safe_hook v0.12.77/.78/.79 fix cycle. Trace lines let the
-- user see n_args + n_returned per fire when debugging swap regressions.
-- Event-rate (per spawn_inventory_unit call, not per-frame) so flood-safe.
mod:traced_hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
    local v_w3p, v_a3p, v_w1p, v_a1p =
        func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

    -- Dispatch to the appropriate per-weapon swap helper. v0.12.25 consolidated
    -- the longbow→crossbow hook into this same registration to silence the
    -- "Attempting to rehook" warning (VMF chained the duplicate registrations
    -- correctly but logged a warning each load). Brace logic stays inline below.
    if not item_data then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    if _is_sp_crossbow_presentation_item(item_data.name) then
        return _wt_longbow_3p_swap_apply(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p, material_settings_name)
    end
    if item_data.name == "wh_repeating_pistols" then
        return _wt_repeating_pistol_3p_swap_apply(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p, material_settings_name)
    end
    -- #181: Skullsplitter & Tome on Kruber → 1H Skullsplitter (hammer in the right
    -- hand, no book). The helper handles BOTH hands (right=book → hidden;
    -- left=hammer → relinked to Kruber's right-hand 1H node), es_-gated inside.
    if item_data.name == "wh_hammer_book" then
        return _wt_hammer_book_3p_swap_apply(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p, material_settings_name)
    end
    -- Gate: only apply swap when wielding a brace, on the right hand
    -- (where the brace's "main pistol" mounts), and the wielder is a
    -- Kruber career. _local_career_name() is defined earlier in this file;
    -- it returns the locally-wielded unit's career_name. For husks, fall
    -- back to checking `owner_unit_3p` via _unit_career_name (also
    -- defined earlier).
    if item_data.name ~= "wh_brace_of_pistols" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    -- Left-hand brace pistol on Kruber: hide it at spawn time. The
    -- right-hand repeater swap below is the main visual change, but the
    -- brace template renders a SECOND pistol on the left hand that clips
    -- through the repeater body. The existing `show_third_person_inventory`
    -- hook re-hides this on every wield/unwield FOR LOCAL PLAYERS — but
    -- husks never call `show_third_person_inventory` from `_wield_slot`
    -- (simple_husk_inventory_extension.lua:_wield_slot omits the
    -- `self:show_third_person_inventory(self._show_third_person)` call
    -- that simple_inventory_extension.lua:692 makes at the end of its
    -- wield). So for husks, the left pistol stayed visible after the
    -- right-hand swap completed. v0.12.39 fix: hide directly at spawn so
    -- the local viewer never sees the second pistol regardless of class.
    if hand == "left" then
        local career_left = _unit_career_name(owner_unit_3p)
        if career_left and career_left:sub(1, 3) == "es_" and v_w3p and Unit.alive(v_w3p) then
            if Unit.has_visibility_group(v_w3p, "normal") then
                Unit.set_visibility(v_w3p, "normal", false)
            else
                Unit.set_unit_visibility(v_w3p, false)
            end
            _dbg("[wt brace-3p-swap] hid left brace pistol at spawn for husk=%s career=%s",
                tostring(owner_unit_1p == nil), career_left)
        end
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    if hand ~= "right" then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    -- Career detection: prefer owner_unit_3p (always present, both local
    -- and husk paths). _unit_career_name reads career_system extension first
    -- (most authoritative on husks), with inventory_system + Managers.player
    -- fallbacks.
    local career_name = _unit_career_name(owner_unit_3p)

    -- v0.12.37 — diagnostic logging for every brace spawn. Filtered to brace
    -- items only, so this is at most ~2 lines per equip flow (not spammy).
    -- Captures the husk case explicitly so we can see WHY a swap is being
    -- skipped on the host's machine for a remote-player Kruber.
    do
        local is_husk = owner_unit_1p == nil
        local owner_ok = false
        local owner_name = "(no owner)"
        if Managers and Managers.player then
            local pm_ok, pl = pcall(Managers.player.owner, Managers.player, owner_unit_3p)
            if pm_ok and pl then
                owner_ok = true
                local n_ok, n = pcall(pl.name, pl)
                if n_ok and n then owner_name = tostring(n) end
            end
        end
        _dbg("[wt brace-3p-swap] enter hand=%s husk=%s owner_unit_3p=%s career=%s owner_known=%s owner=%s",
            tostring(hand), tostring(is_husk), tostring(owner_unit_3p ~= nil), tostring(career_name),
            tostring(owner_ok), owner_name)
    end

    if not career_name or career_name:sub(1, 3) ~= "es_" then
        _dbg("[wt brace-3p-swap] SKIP (career not Kruber: %s)", tostring(career_name))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if not v_w3p then
        _dbg("[wt brace-3p-swap] SKIP (vanilla v_w3p was nil)")
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    -- Package readiness check: the async force-load at mod init usually
    -- completes well before any equip flow, but guard the spawn anyway. A
    -- not-yet-loaded package would cause `spawn_local_unit_with_extensions`
    -- to throw the C++ "Unit not found" assertion (crash GUID d9e1d3d3).
    -- If unloaded here, just return vanilla's brace 3P unit — Kruber sees
    -- the brace mesh briefly until the next equip fires the swap.
    if Managers and Managers.package and Managers.package.has_loaded
            and not Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p") then
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    local pcall_ok, swap_result = pcall(function()
        local node_linking_settings = item_template[hand .. "_hand_attachment_node_linking"]
        if not node_linking_settings or not node_linking_settings.third_person then
            mod:warning("[wt brace-3p-swap] missing node_linking_settings.third_person; aborting")
            return nil
        end

        local unit_template_3p_name = item_data.third_person_extension_template
            or item_template.third_person_extension_template
            or "weapon_unit_3p"
        if owner_unit_1p then unit_template_3p_name = "weapon_unit_3p" end

        local extension_init_data_3p = {
            weapon_system = {
                item_template = item_template,
                item_name = item_data.name,
                owner_unit = owner_unit_3p,
                world = world,
            },
        }

        -- Spawn the repeater 3P unit FIRST. If spawn fails we still have
        -- vanilla's brace 3P unit to fall back to.
        local new_unit = Managers.state.unit_spawner:spawn_local_unit_with_extensions(
            _BRACE_REPEATER_3P_UNIT, unit_template_3p_name, extension_init_data_3p)
        if not new_unit then
            mod:warning("[wt brace-3p-swap] spawn returned nil for '%s'", _BRACE_REPEATER_3P_UNIT)
            return nil
        end

        -- Now safe to destroy vanilla's brace 3P unit.
        Managers.state.unit_spawner:mark_for_deletion(v_w3p)

        local attachment_node_linking_3p = node_linking_settings.third_person.wielded
        GearUtils.link(world, attachment_node_linking_3p, {}, owner_unit_3p, new_unit)

        local mat = material_settings_name or item_template.material_settings_name
        if mat then GearUtils.apply_material_settings(new_unit, mat) end

        -- v0.12.38 — mirror vanilla `_wield_slot` visibility behavior. For
        -- the LOCAL player, the 3P weapon is hidden when there's a 1P view
        -- (because the player sees their hands in 1P, not their 3P body).
        -- For HUSKS (no 1P), the 3P weapon stays visible — that's how other
        -- players see the held weapon. The unconditional `set_unit_visibility
        -- (new_unit, false)` was a bug carried over from CWV's original swap
        -- that was tested only on the local-player path. It made the swapped
        -- repeater unit invisible on the host's view of any remote-player
        -- Kruber husk, while the vanilla brace had been mark_for_deletion'd,
        -- so the host saw the brace (lingering on the to-delete frame) and
        -- then nothing afterwards. Vanilla check is on `right_hand_weapon_unit_1p`
        -- existence — equivalent to `owner_unit_1p` non-nil here.
        if owner_unit_1p then
            Unit.set_unit_visibility(new_unit, false)
        end

        _dbg("[wt brace-3p-swap] swapped 3P brace -> repeater on career=%s (husk=%s vis=%s)",
            career_name, tostring(owner_unit_1p == nil), tostring(owner_unit_1p == nil))

        return new_unit
    end)

    if not pcall_ok then
        mod:warning("[wt brace-3p-swap] pcall ERROR: %s — keeping vanilla unit", tostring(swap_result))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if swap_result then
        return swap_result, v_a3p, v_w1p, v_a1p
    end
    return v_w3p, v_a3p, v_w1p, v_a1p
end)

-- ============================================================
-- Saltzpyre Longbow → Crossbow in-game 3P spawn (helper, not a hook)
-- ============================================================
-- Was a second `mod:hook("GearUtils", "spawn_inventory_unit", ...)` in
-- v0.12.24 and earlier, which VMF chained but warned about as a duplicate
-- registration. v0.12.25 consolidated into the brace hook above: the brace
-- hook calls this helper when item_data.name == "es_longbow". Caller is
-- responsible for the post-func vanilla return values; signature mirrors
-- the original hook minus the chain-wrapper bits (no func arg, no
-- item_units/slot_name/unit_template/extra_extension_data/ammo_percent
-- because none of the body references them).
--
-- Parallel to the brace→repeater hook above. Differences:
--   * `hand == "left"` (bows/crossbows are left-hand weapons; brace was right)
--   * Swaps TWO 3P units per spawn: v_w3p (bow→crossbow) AND v_a3p (arrow→bolt).
--     The bow's `ammo_data.ammo_hand == "left"`, so vanilla
--     spawn_inventory_unit("left", longbow, ...) returns a non-nil v_a3p.
--     Brace had no ammo unit; this case does.
--   * 1P returns (v_w1p = bow, v_a1p = arrow) are left untouched — 1P stays
--     the longbow visually because 1P is universal across characters
--     (`feedback_1p_animations_universal.md`).
--
-- The new bolt ammo unit attaches via the CROSSBOW template's bolt-attachment
-- node linking, NOT the bow's arrow-attachment. The bow's arrow attaches at
-- the bow's nock point on the player body; the crossbow's bolt attaches at
-- the crossbow's nock groove. Using bow's arrow linking would render the
-- bolt at the wrong position relative to the (now-crossbow) weapon mesh.
_wt_longbow_3p_swap_apply = function(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p, material_settings_name)
    -- v0.12.43 — entry/skip diagnostic logging. Mirrors the brace-3p-swap
    -- pattern from v0.12.37 so we can see why the swap silently bails on
    -- husks. Previously the helper only logged on success, leaving every
    -- bail path (hand check, career check, v_w3p nil, package not loaded,
    -- pcall error) invisible in the host's console log.
    do
        local is_husk = owner_unit_1p == nil
        local owner_ok = false
        local owner_name = "(no owner)"
        if Managers and Managers.player then
            local pm_ok, pl = pcall(Managers.player.owner, Managers.player, owner_unit_3p)
            if pm_ok and pl then
                owner_ok = true
                local n_ok, n = pcall(pl.name, pl)
                if n_ok and n then owner_name = tostring(n) end
            end
        end
        local career_for_log = _unit_career_name(owner_unit_3p)
        _dbg("[wt sp-longbow-crossbow] enter hand=%s husk=%s owner_unit_3p=%s career=%s owner_known=%s owner=%s v_w3p=%s v_a3p=%s",
            tostring(hand), tostring(is_husk), tostring(owner_unit_3p ~= nil), tostring(career_for_log),
            tostring(owner_ok), owner_name, tostring(v_w3p ~= nil), tostring(v_a3p ~= nil))
    end

    if hand ~= "left" then
        _dbg("[wt sp-longbow-crossbow] SKIP (hand=%s, not left)", tostring(hand))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    local career_name = _unit_career_name(owner_unit_3p)
    if not career_name or career_name:sub(1, 3) ~= "wh_" then
        _dbg("[wt sp-longbow-crossbow] SKIP (career not Saltzpyre: %s)", tostring(career_name))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if not v_w3p then
        _dbg("[wt sp-longbow-crossbow] SKIP (vanilla v_w3p was nil)")
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    -- Package readiness checks — same async-load defensiveness as the brace hook.
    if Managers and Managers.package and Managers.package.has_loaded then
        if not Managers.package:has_loaded(_SP_CROSSBOW_3P_UNIT, "wt_sp_crossbow_3p") then
            _dbg("[wt sp-longbow-crossbow] SKIP (crossbow 3P package not loaded)")
            return v_w3p, v_a3p, v_w1p, v_a1p
        end
        if v_a3p and not Managers.package:has_loaded(_SP_CROSSBOW_BOLT_3P_UNIT, "wt_sp_crossbow_bolt_3p") then
            _dbg("[wt sp-longbow-crossbow] SKIP (bolt 3P package not loaded)")
            return v_w3p, v_a3p, v_w1p, v_a1p
        end
    end

    local pcall_ok, swap_result = pcall(function()
        local node_linking_settings = item_template[hand .. "_hand_attachment_node_linking"]
        if not node_linking_settings or not node_linking_settings.third_person then
            mod:warning("[wt sp-longbow-crossbow] missing node_linking_settings.third_person; aborting")
            return nil
        end

        local unit_template_3p_name = item_data.third_person_extension_template
            or item_template.third_person_extension_template
            or "weapon_unit_3p"
        if owner_unit_1p then unit_template_3p_name = "weapon_unit_3p" end

        local extension_init_data_3p = {
            weapon_system = {
                item_template = item_template,
                item_name = item_data.name,
                owner_unit = owner_unit_3p,
                world = world,
            },
        }

        -- Spawn new crossbow 3P unit first; fall back to vanilla bow if it fails.
        local new_weapon = Managers.state.unit_spawner:spawn_local_unit_with_extensions(
            _SP_CROSSBOW_3P_UNIT, unit_template_3p_name, extension_init_data_3p)
        if not new_weapon then
            mod:warning("[wt sp-longbow-crossbow] weapon spawn returned nil for '%s'", _SP_CROSSBOW_3P_UNIT)
            return nil
        end

        -- Spawn new bolt 3P unit, attached via the crossbow template's bolt
        -- ammo-attachment linking (NOT the longbow's arrow linking — the
        -- bolt belongs at the crossbow's nock position on the player body).
        -- If the bow template had no v_a3p there's nothing to swap; only
        -- swap when both source and target ammo paths are available.
        local new_ammo
        if v_a3p then
            local crossbow_tpl = Weapons and Weapons.crossbow_template_1
            local xbow_ammo_linking = crossbow_tpl and crossbow_tpl.ammo_data
                                       and crossbow_tpl.ammo_data.ammo_unit_attachment_node_linking
                                       and crossbow_tpl.ammo_data.ammo_unit_attachment_node_linking.third_person
                                       and crossbow_tpl.ammo_data.ammo_unit_attachment_node_linking.third_person.wielded
            if xbow_ammo_linking and GearUtils._attach_ammo_unit then
                new_ammo = GearUtils._attach_ammo_unit(world, _SP_CROSSBOW_BOLT_3P_UNIT, xbow_ammo_linking, owner_unit_3p)
            else
                mod:warning("[wt sp-longbow-crossbow] missing crossbow_template_1 ammo linking; skipping bolt swap")
            end
        end

        -- Destroy vanilla units only after replacements are safely spawned.
        Managers.state.unit_spawner:mark_for_deletion(v_w3p)
        if new_ammo and v_a3p then
            Managers.state.unit_spawner:mark_for_deletion(v_a3p)
        end

        -- Sibling of the v0.12.29 preview fix: the longbow's wielded
        -- attachment table references `bow_root` (a node on the bow weapon
        -- mesh). `new_weapon` is a crossbow unit which has no `bow_root` node;
        -- linking against the bow's table → engine fatal that bypasses pcall
        -- (`feedback_vt2_unit_node_not_pcall_safe`). crashify://92f9907f.
        -- Use the empire crossbow template's `.wielded` table instead — it
        -- references nodes that exist on the crossbow mesh by construction.
        local xbow_tpl = Weapons and Weapons.crossbow_template_1
        local attachment_node_linking_3p
        if xbow_tpl and xbow_tpl.left_hand_attachment_node_linking
                    and xbow_tpl.left_hand_attachment_node_linking.third_person
                    and xbow_tpl.left_hand_attachment_node_linking.third_person.wielded then
            attachment_node_linking_3p = xbow_tpl.left_hand_attachment_node_linking.third_person.wielded
        else
            mod:warning("[wt sp-longbow-crossbow] crossbow_template_1 wielded linking missing; aborting in-game swap on career=%s", career_name)
            return nil
        end
        GearUtils.link(world, attachment_node_linking_3p, {}, owner_unit_3p, new_weapon)

        local mat = material_settings_name or item_template.material_settings_name
        if mat then GearUtils.apply_material_settings(new_weapon, mat) end

        -- v0.12.38 — same fix as the brace swap. Vanilla `_wield_slot` hides
        -- the 3P units only when 1P units exist (local player). For husks
        -- (no 1P) the 3P units stay visible so other players can see them.
        if owner_unit_1p then
            Unit.set_unit_visibility(new_weapon, false)
            if new_ammo then Unit.set_unit_visibility(new_ammo, false) end
        end

        _dbg("[wt sp-longbow-crossbow] swapped 3P bow->crossbow, arrow->bolt(%s) on career=%s (husk=%s)",
            tostring(new_ammo ~= nil), career_name, tostring(owner_unit_1p == nil))

        return { weapon = new_weapon, ammo = new_ammo }
    end)

    if not pcall_ok then
        mod:warning("[wt sp-longbow-crossbow] pcall ERROR: %s — keeping vanilla units", tostring(swap_result))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if swap_result then
        return swap_result.weapon, (swap_result.ammo or v_a3p), v_w1p, v_a1p
    end
    -- v0.12.83-dev: promoted to `_dbg_alert` — this branch only fires after the
    -- preceding `mod:warning("[wt sp-longbow-crossbow] pcall ERROR ...")` has
    -- already logged, so the follow-up SKIP is part of the alert chain.
    _dbg_alert("[wt sp-longbow-crossbow] SKIP (pcall returned nil — internal abort, see prior warning)")
    return v_w3p, v_a3p, v_w1p, v_a1p
end

-- ============================================================
-- Kruber Repeating Pistol → Repeating Handgun in-game 3P spawn (helper)
-- ============================================================
-- Parallel to the brace→repeater helper but with one critical difference:
-- the source template's `right_hand_attachment_node_linking.third_person.wielded`
-- references weapon-mesh-side nodes that exist ONLY on the repeater pistol
-- mesh (`lock_hammer`, `rotator`, `trigger_t1` — see attachment_node_linking.lua
-- `repeater_pistol` block, lines 5083-5107). The brace's attachment table is
-- simpler — only `j_rightweaponattach → 0` — so linking the repeater handgun
-- unit via the brace's source table works. We don't get that luxury here:
-- linking the handgun unit via `lock_hammer` etc. would `Unit.node` fatal on
-- nodes that don't exist on the handgun mesh, and that fatal bypasses pcall
-- (feedback_vt2_unit_node_not_pcall_safe). crashify://f210b3b7 sibling.
--
-- Fix: substitute the TARGET template's `right_hand_attachment_node_linking.
-- third_person.wielded` (from `Weapons.repeating_handgun_template_1`) when
-- linking the new unit. The handgun's table references `j_rightweaponattach`
-- + `j_rightweaponcomponent9 → j_rotator` — body-side sources that Kruber's
-- 3P body authors natively and weapon-side targets that exist on the handgun
-- mesh. Same fix pattern as the longbow→crossbow swap at line 2519-2570.
--
-- Right-hand-only weapon — no ammo unit, no left-hand secondary like the
-- brace's two-pistol layout. Just one 3P unit swap per `hand == "right"` call.
-- Target unit is the same `_BRACE_REPEATER_3P_UNIT` the brace swap uses
-- (`wpn_emp_handgun_repeater_t1_3p` — Kruber's repeating handgun mesh; the
-- constant name reflects historical "brace's target" framing, not the source
-- weapon). Force-load is shared.
_wt_repeating_pistol_3p_swap_apply = function(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p, material_settings_name)
    -- Diagnostic entry log (mirrors brace + longbow patterns from v0.12.37+).
    do
        local is_husk = owner_unit_1p == nil
        local owner_ok = false
        local owner_name = "(no owner)"
        if Managers and Managers.player then
            local pm_ok, pl = pcall(Managers.player.owner, Managers.player, owner_unit_3p)
            if pm_ok and pl then
                owner_ok = true
                local n_ok, n = pcall(pl.name, pl)
                if n_ok and n then owner_name = tostring(n) end
            end
        end
        local career_for_log = _unit_career_name(owner_unit_3p)
        _dbg("[wt rp-pistol-handgun] enter hand=%s husk=%s owner_unit_3p=%s career=%s owner_known=%s owner=%s v_w3p=%s",
            tostring(hand), tostring(is_husk), tostring(owner_unit_3p ~= nil), tostring(career_for_log),
            tostring(owner_ok), owner_name, tostring(v_w3p ~= nil))
    end

    if hand ~= "right" then
        _dbg("[wt rp-pistol-handgun] SKIP (hand=%s, not right)", tostring(hand))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end
    local career_name = _unit_career_name(owner_unit_3p)
    if not career_name or career_name:sub(1, 3) ~= "es_" then
        _dbg("[wt rp-pistol-handgun] SKIP (career not Kruber: %s)", tostring(career_name))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if not v_w3p then
        _dbg("[wt rp-pistol-handgun] SKIP (vanilla v_w3p was nil)")
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if Managers and Managers.package and Managers.package.has_loaded
            and not Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p") then
        _dbg("[wt rp-pistol-handgun] SKIP (repeating handgun 3P package not loaded)")
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    local pcall_ok, swap_result = pcall(function()
        -- Source the repeating handgun template's attachment-node table (NOT
        -- the repeater pistol's). The pistol's `wielded` set has weapon-mesh-
        -- specific node targets (`lock_hammer`, `rotator`, `trigger_t1`) that
        -- the handgun mesh doesn't author → `Unit.node` engine fatal that
        -- bypasses pcall (feedback_vt2_unit_node_not_pcall_safe).
        local target_tpl = Weapons and Weapons.repeating_handgun_template_1
        local target_wielded_3p
        if target_tpl and target_tpl.right_hand_attachment_node_linking
                      and target_tpl.right_hand_attachment_node_linking.third_person
                      and target_tpl.right_hand_attachment_node_linking.third_person.wielded then
            target_wielded_3p = target_tpl.right_hand_attachment_node_linking.third_person.wielded
        else
            mod:warning("[wt rp-pistol-handgun] repeating_handgun_template_1 wielded linking missing; aborting on career=%s", career_name)
            return nil
        end

        local unit_template_3p_name = item_data.third_person_extension_template
            or item_template.third_person_extension_template
            or "weapon_unit_3p"
        if owner_unit_1p then unit_template_3p_name = "weapon_unit_3p" end

        local extension_init_data_3p = {
            weapon_system = {
                item_template = item_template,
                item_name = item_data.name,
                owner_unit = owner_unit_3p,
                world = world,
            },
        }

        -- Spawn new handgun 3P unit first; fall back to vanilla pistol if it fails.
        local new_unit = Managers.state.unit_spawner:spawn_local_unit_with_extensions(
            _BRACE_REPEATER_3P_UNIT, unit_template_3p_name, extension_init_data_3p)
        if not new_unit then
            mod:warning("[wt rp-pistol-handgun] spawn returned nil for '%s'", _BRACE_REPEATER_3P_UNIT)
            return nil
        end

        Managers.state.unit_spawner:mark_for_deletion(v_w3p)

        GearUtils.link(world, target_wielded_3p, {}, owner_unit_3p, new_unit)

        local mat = material_settings_name or item_template.material_settings_name
        if mat then GearUtils.apply_material_settings(new_unit, mat) end

        -- Mirror vanilla `_wield_slot` visibility: hide 3P unit only when the
        -- local viewer has a 1P unit (=local player); husks keep 3P visible.
        -- Same v0.12.38 fix as the brace + longbow swaps.
        if owner_unit_1p then
            Unit.set_unit_visibility(new_unit, false)
        end

        _dbg("[wt rp-pistol-handgun] swapped 3P pistol -> handgun on career=%s (husk=%s)",
            career_name, tostring(owner_unit_1p == nil))

        return new_unit
    end)

    if not pcall_ok then
        mod:warning("[wt rp-pistol-handgun] pcall ERROR: %s — keeping vanilla unit", tostring(swap_result))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    if swap_result then
        return swap_result, v_a3p, v_w1p, v_a1p
    end
    return v_w3p, v_a3p, v_w1p, v_a1p
end

-- ============================================================
-- Kruber Skullsplitter & Tome (wh_hammer_book) → 1H Skullsplitter in-game 3P (#181)
-- ============================================================
-- v0.12.187-dev removed the fresh-unit mesh swap because the separately spawned hammer
-- picked up a bad transform. That revision kept the authored left-hand hammer and only
-- hid the book, which directly caused the live wrong-hand defect: the source item really
-- authors its hammer as `left_hand_unit`. Reuse that already-spawned, illusion-correct
-- unit and relink only its 3P root onto Kruber's receiver-native right-hand node. This
-- avoids the old fresh-spawn offset path while producing the requested main-hand model.
--
-- Vanilla `one_handed_hammer_book_priest_template`: left_hand_unit = the Skullsplitter
-- HAMMER, right_hand_unit = the BOOK. spawn_inventory_unit fires
-- once per hand:
--   * hand == "right" (the book): hide that 3P unit. `show_third_person_inventory`
--     re-shows the right-hand wielded unit on every wield
--     (simple_inventory_extension.lua:1017-1024), so `_rehide_hidden_3p_units` (below)
--     re-hides it durably; this spawn-time hide additionally covers the husk path
--     (husks don't call show_third_person_inventory from _wield_slot).
--   * hand == "left" (the hammer): validate and relink the existing 3P unit to
--     `Weapons.one_handed_hammer_template_1`'s right-hand wielded linking
--     (`j_rightweaponattach` in vanilla attachment_node_linking.lua:2742-2753).
-- 3P-ONLY: v_w1p/v_a1p (1P) are never touched — 1P is universal across all six chars.
_wt_hammer_book_3p_swap_apply = function(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p)
    _wt_skullsplitter_hand_policy.apply_runtime({
        world = world, world_api = World, gear_utils = GearUtils, unit_api = Unit,
        hand = hand, item_template = item_template, item_name = item_data and item_data.name,
        owner_unit_3p = owner_unit_3p, weapon_unit_3p = v_w3p,
        career_name = _unit_career_name(owner_unit_3p),
        perspective = owner_unit_1p == nil and "husk" or "owner_or_bot",
        weapons = rawget(_G, "Weapons"), emit = printf,
    })
    return v_w3p, v_a3p, v_w1p, v_a1p
end
