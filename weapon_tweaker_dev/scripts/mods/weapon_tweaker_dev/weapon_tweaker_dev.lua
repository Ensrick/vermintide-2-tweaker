--[[
weapon_tweaker — cross-career weapon unlocks, animation remapping, and visual tweaks.

Major sections (search by name to jump):
  * _weapon_scale_overrides / _weapon_grip_offsets — per-career scale & grip-position tweaks
  * Lifecycle: on_game_state_changed (re-applies unlocks per state), on_setting_changed,
                on_disabled (strip-only revert).

  Phase 1 OOP split (v0.12.209-dev) — see DEVELOPMENT.md "Module map":
  * weapon_unlock_map / apply_weapon_unlocks / patch_career_actions_on_weapons → _wt_availability.lua
  * /wt_regression_test harness (rt_register) → _wt_regression.lua
  * CW trait-pool filtering (apply_trait_filters) → _wt_trait_pools.lua
  * /sm_probe /dump /dump_actions /dump_weapons /wt_dump_wielded → _wt_diagnostics.lua

  Phase 2 OOP split (v0.12.210-dev) — the 3P anim-remap core → _wt_anim_remap.lua:
  * _anim_redirect / _career_anim_redirect / _suffix_career_map — the three redirect layers
  * _3p_remap_* / _3p_key_remaps + resolvers — per-weapon remap dispatch tables
  * _wt_anim_remap_data.lua — declarative per-template 3P remap catalog
  * _unit_state / _state_for — weak-keyed per-unit remap state + the two wield hooks
  * Unit.animation_event funnel hook + /info /animlog /force3p /force1p commands
  * _resolve_preview_wield_event — keep-previewer 3P wield-pose correction
  (_WIELD_ANIM_CAREER_3P_PATCHES_BULK + wield/template patchers + grip offsets +
   P0 create_equipment guards stay here — port-pipeline-coupled, Phase 3 candidates.)

Key conventions (also in CLAUDE.md):
  * NEVER hook BackendUtils.can_wield_item — modify ItemMasterList[*].can_wield directly.
  * rawget(ItemMasterList, k) when k might not exist (DLC ownership, save-data drift).
  * Lua 5.1 — locals are not hoisted; verify forward references before using a name.
]]

local mod = get_mod("wt_dev")

--[==[
Direction note — read before adding new cross-character unlocks
================================================================

What this mod is for
--------------------
weapon_tweaker exists to give players FULL FREEDOM to use any character's
weapons on any character, while keeping the bystander view plausible. The
1P (first-person) animation system in VT2 is universal: the first_person_base
unit and its state machine work on every character, with every weapon, with
no porting work required. We never override 1P fields (anim_event,
wield_anim, state_machine) — see feedback_1p_animations_universal.md.
Only the 3P (third-person) body is character-specific, so the work here is
3P-side only: we remap anim events from the source weapon onto a
functionally-similar weapon vocabulary that the receiver's 3P skeleton
actually knows. Example: Saltzpyre wielding a Longbow renders in 3P using
Crossbow events (a weapon his skeleton knows that's functionally close
enough that bystanders see something coherent). The local player still sees
the real Longbow in 1P; the lie is only in the 3P silhouette.

Direction reversal 2026-05-23
-----------------------------
wt is shedding IDENTICAL-FUNCTIONAL cross-character ports — cases where the
receiver already has a native weapon in the same functional family (e.g.
giving Saltzpyre access to Bardin's one-handed axe when Saltzpyre already
has a falchion-family one-hander that hits the same archetype). Those ports
don't add gameplay; they're purely a cosmetic preference. They are moving
to cosmetics_tweaker as a cross-character cosmetic swap with per-receiver
scaling and grip offset adjustments. See [[project_wt_direction_2026_05_23]]
and [[project_cosmetics_tweaker_xchar_swap]] for the migration plan.

What stays in wt
----------------
Genuine FUNCTIONAL cross-character ports — weapons that fill a slot or role
the receiver doesn't otherwise have access to. Examples that stay:
  - Brace of Pistols on Kruber (Kruber has no other twin-pistol option)
  - Longbow on Saltzpyre (different rhythm than Crossbow/Repeater Pistol)
  - Billhook <-> Polearm cross-access
  - Any weapon family the receiver doesn't have a native equivalent for
If the receiver already has a same-family weapon in their native lineup,
the new home for that "I just want to look like I'm using X" wish is
cosmetics_tweaker's cross-character cosmetic swap, not wt.

Cross-refs: [[project_wt_direction_2026_05_23]],
            [[project_cosmetics_tweaker_xchar_swap]],
            [[feedback_1p_animations_universal]]
]==]

local _mp_pre_backend = collectgarbage("count")  -- [mem-probe]
local weapon_backend = mod:dofile("scripts/mods/weapon_tweaker_dev/weapon_tweaker_backend")
mod:info("[mem-probe] wt weapon_backend: +%.1f MB lua (NOT in the boot_lua total below — baseline is set after this)", (collectgarbage("count") - _mp_pre_backend) / 1024)  -- [mem-probe]

-- Big Rebalance was retired under #321. Its unreachable implementation,
-- definitions, lifecycle stub, and dead-only formula checks were deleted under
-- #433. Saved br_* values remain untouched and the prefix stays reserved.

local MOD_VERSION = "0.12.279-dev"
_MEM_PROBE_T0_WT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

-- v0.12.73: source-pattern marker constant for the /wt_regression_test
-- `wt_itemmasterlist_uses_rawget` check (audit `.test_coverage_audit_2026-05-24.md`
-- PARTIAL row 1 — promoted to PASS by adding a belt-and-suspenders runtime
-- check beside the existing strict-table-lookup lint coverage).
local CT_WT_ITEMMASTERLIST_RAWGET_MARKER_v0_12_73 = "wt-itemmasterlist-rawget-hardened"

-- v0.12.77 (Issue #26): pcall-isolated `mod:safe_hook` / `mod:safe_hook_safe`
-- helpers. Required here near the top (after MOD_VERSION, before any
-- `mod:hook(...)` call site) so the methods are attached to the mod table
-- before any consumer below reaches for them. Self-contained per mod for v1;
-- cross-mod sharing is Wave-2. See `_safe_hook.lua` header for the full
-- rationale + VMF chain-isolation reference.
--
-- v0.12.84-dev: same require also installs Layer 3 `mod:traced_hook` /
-- `mod:traced_hook_safe` — safe_hook + structured `[wt:trace] event=...`
-- entry/exit log lines gated on `enable_debug_logging`. Adopt on hooks
-- where fire-confirmation is load-bearing (NOT on per-frame hooks — see
-- _safe_hook.lua header "RATE-LIMIT CAVEAT").
mod:dofile("scripts/mods/weapon_tweaker_dev/_safe_hook")
-- WT_DEV_OVERLAY_BEGIN:dev-tool-imports
-- ============================================================
-- Dev-only tooling modules (v0.12.96-dev)
-- ============================================================
-- Two nested VMF menus for live in-game tuning of cross-character ports.
-- Loaded HERE (after _safe_hook, before template patchers) so the module
-- locals are available; their `install()` calls fire at the bottom of this
-- file after the template patchers have populated `Weapons.<template>` with
-- their initial values (which is what the anim picker dropdowns mirror).
--
-- These modules will be stripped (or moved to a sibling `_dev` directory)
-- when wt forks a stable release-side mod; until then they ship inline.
-- See feedback_no_premature_dev_gates.md.
local _wt_dev_anim_picker = mod:dofile("scripts/mods/weapon_tweaker_dev/wt_dev_anim_picker")
local _wt_dev_hold_pose   = mod:dofile("scripts/mods/weapon_tweaker_dev/wt_dev_hold_pose")
-- WT_DEV_OVERLAY_END:dev-tool-imports

local _wt_axe_balance_policy = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_axe_balance")
local _wt_axe_balance = _wt_axe_balance_policy.new()
local _wt_grip_offset_policy = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_grip_offset_policy")
-- Bret Sword & Shield damage buff (self-applies at load when wt_brett_sword_shield_buff is ON;
-- mutates the weapon template, so a restart is needed to apply/revert).
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_brett_sword_shield_buff")

-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([wt] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Weapon Tweaker v%s loaded", MOD_VERSION)

-- ============================================================
-- Debug helper — routed through VMF logging channels
-- ============================================================
-- Diagnostics now route through VMF; visibility controlled by VMF
-- output_mode_debug / output_mode_warning (PROJECT_STANDARDS.md § 3.6).
-- v0.12.83-dev: two-helper policy per PROJECT_STANDARDS.md § 3.6.
-- `_dbg` = confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` = unexpected / wrong / mismatch — LOG-ONLY via engine printf.
local function _dbg(fmt, ...)
    mod:debug("[wt:dbg] " .. fmt, ...)
end

-- v0.12.202-dev (Issue #240 / BUG_CLASSES.md §17B): _dbg_alert is now log-only via
-- engine printf. It previously routed through mod:warning, which posts to CHAT by
-- default (VMF `warning` = mode 3, send_to_chat = mode >= 2), so routine diagnostics --
-- most visibly the [wt:attach_probe] missing-node trace for a staff in a Kruber ranged
-- slot -- spammed the user's chat on every inventory refresh. printf always lands in
-- console-*.log (even with mod-logging off) and never touches chat; pcall-guarded so a
-- bad format arg can't fault the caller. Mirrors et v0.7.25-dev; folds into the #169
-- VMF-native-logging sweep. Chat stays reserved for genuine failures, which would call
-- mod:warning directly (wt currently has none).
mod._wt_alerts_log_only_marker = "wt-alert-helpers-log-only-printf-240"
local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[wt:dbg] " .. fmt, ...) then
        pcall(printf, "[wt:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry). Additive
-- to the existing "Weapon Tweaker: Baseline Active" line further down.
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[wt:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[wt] v%s loaded", MOD_VERSION))
end

-- One-time migration of the v0.12.73-and-earlier dead checkboxes
-- (`debug`, `enable_weapon_debug_logging`, `wt_debug_mode`) into
-- the universal `enable_debug_logging` toggle (v0.12.81-dev rename
-- per PROJECT_STANDARDS.md § 3.6). Gated by a sentinel so it runs
-- exactly once per user — re-running would clobber an explicit OFF
-- set after the first migration. The widgets are gone in _data.lua
-- so the old keys won't be re-written by the VMF settings panel.
local function _migrate_legacy_debug_setting()
    if mod:get("wt_debug_migration_v1") then return end
    -- Clear the old debug keys to a definite `false`. The widgets are gone in
    -- _data.lua so VMF won't surface these in the panel; the residual
    -- entries are harmless but we still want a clean baseline so a
    -- future re-introduction of `debug` etc. doesn't pick up a stale
    -- truthy value from years ago. `mod:set(key, false)` is the
    -- safest cross-version write (some VMF builds treat `nil` as
    -- "no change"). `enable_debug_logging` itself also removed v0.12.176-dev
    -- (diagnostics now route through VMF channels — see CHANGELOG).
    mod:set("debug", false)
    mod:set("enable_weapon_debug_logging", false)
    mod:set("enable_debug_logging", false)
    mod:set("wt_debug_migration_v1", true)
end
_migrate_legacy_debug_setting()

-- ============================================================================
-- Shared module namespace + Phase 1 OOP module manifest (v0.12.209-dev)
-- ============================================================================
-- mod._wt carries cross-module state for the extracted _wt_* modules (the
-- event_tweaker mod._evt / cosmetics mod._cos pattern, PROJECT_STANDARDS §2.2a).
-- Each module is dofile'd EXACTLY ONCE from a manifest (mod:dofile is NOT a
-- singleton — reference_vmf_dofile_not_singleton — so modules never dofile each
-- other); the handles a module consumes are put on mod._wt BEFORE its dofile,
-- and the entry re-localizes each exported function so existing call sites stay
-- byte-identical. The established flat `mod._wt_*` fields (mod._wt_link_filter,
-- mod._wt_tf_*, ...) are a SEPARATE key namespace and are untouched.
mod._wt = mod._wt or {}
mod._wt.MOD_VERSION = MOD_VERSION

-- /wt_regression_test harness (_RT_CHECKS + rt_register + the command). Loads
-- FIRST so every inline `_rt_register(...)` check registration below the
-- manifest binds against the module's table (the et _et_regression precedent).
-- The check bodies stay inline near the file-local state tables (`_unit_state`,
-- `weapon_unlock_map`, etc.) they probe.
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_regression")
local _rt_register = mod._wt.rt_register

-- weapon_unlock_map + _cwv_managed are shared by runtime availability owners.
local _wt_unlock_data   = mod:dofile("scripts/mods/weapon_tweaker_dev/wt_unlock_data")
local weapon_unlock_map = _wt_unlock_data.weapon_unlock_map
-- WT_DEV_OVERLAY_BEGIN:port-status-owner
mod._wt.port_status = mod:dofile("scripts/mods/weapon_tweaker_dev/wt_port_status")
-- WT_DEV_OVERLAY_END:port-status-owner

-- CLARIFY: career_weapon_variants ("CWV") publishes its own custom items for
-- these (career, weapon) pairs. When CWV is installed, weapon_tweaker SKIPS
-- adding those careers to `can_wield` for the listed weapons (and the matching
-- widgets are stripped in _data.lua) so the two mods don't compete for the
-- same can_wield slot.
-- v0.12.99-dev: also from wt_unlock_data.lua (shared source of truth — see
-- the unlock_data dofile above).
-- v0.12.209-dev: bridged onto mod._wt for the _wt_availability module (which
-- owns the can_wield strip/add); the entry no longer reads _cwv_managed itself.
mod._wt.weapon_unlock_map = weapon_unlock_map
mod._wt.cwv_conditional_managed = _wt_unlock_data.cwv_conditional_managed

-- Availability control surface (can_wield strip/add + career-ability action
-- injection) and CW trait-pool filtering, extracted v0.12.209-dev. Both are
-- consumed by the lifecycle callbacks far below (on_game_state_changed /
-- on_setting_changed / on_disabled); dofile'd HERE, after wt_unlock_data
-- publishes the maps onto mod._wt and before those callbacks are defined, so
-- their file-local aliases are in scope at call time. Call sites unchanged.
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_availability")
local apply_weapon_unlocks            = mod._wt.apply_weapon_unlocks
local patch_career_actions_on_weapons = mod._wt.patch_career_actions_on_weapons
local clear_weapon_unlocks            = mod._wt.clear_weapon_unlocks
local clear_career_action_injections  = mod._wt.clear_career_action_injections

mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_trait_pools")
local apply_trait_filters = mod._wt.apply_trait_filters
local revert_trait_pools  = mod._wt.revert_trait_pools

-- issue 611: _data.lua builds the career/slot/source-scoped master widgets and
-- records their exact forward/reverse maps. Install the proven VMF checkbox
-- styling + repaint hooks, then derive every master from its own career's saved
-- children. Cascade and targeted child recompute dispatch below.
local _wt_master_toggles = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_master_toggles")
_wt_master_toggles.install_refresh_hook(mod)
_wt_master_toggles.seed(mod)

-- Read-only diagnostic dump/probe chat commands + the wield-time weapon-data
-- dump hook (leaf consumers of game globals only; no entry-state dependency).
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_diagnostics")

-- #341: Bolt Staff's two rapid primary actions exclusively use the `spark`
-- overcharge key. This small module owns the snapshot/apply/revert transaction;
-- no hook and no shared weapon-template mutation are required.
local _wt_bolt_staff_overcharge = mod:dofile(
    "scripts/mods/weapon_tweaker_dev/_wt_bolt_staff_overcharge")
local _wt_bolt_staff_overcharge_runtime =
    _wt_bolt_staff_overcharge.new_runtime(mod)
_wt_bolt_staff_overcharge_runtime.apply()

-- Weapon-availability control surface (can_wield strip/add, kruber-removed-pair
-- cleanup, career-ability action injection + on_disabled reverts) moved to
-- _wt_availability.lua in the v0.12.209-dev OOP split. The entry's file-local
-- aliases (apply_weapon_unlocks, patch_career_actions_on_weapons,
-- clear_weapon_unlocks, clear_career_action_injections) are established in the
-- manifest above. `feature_enabled` stays here — the anim funnel reads it on a
-- hot path (`enable_weapon_animation_redirects`).
local function feature_enabled(setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then return default_value ~= false end
    return value == true
end

-- CLARIFY: caches the last-known career name across calls. Falls back to the
-- cached value if Managers.player isn't ready (e.g. very early hook fires
-- during loading screens) so callers always get a usable career string when
-- one was ever resolved this session.
local _cached_career = nil
local function _local_career_name()
    local pm = Managers.player
    if not pm then return _cached_career end
    local pl = pm:local_player()
    if not pl then return _cached_career end
    local career = pl:career_name()
    if career then _cached_career = career; return career end
    -- CLARIFY: career_name() can return nil before character finishes spawning;
    -- profile_index/career_index are populated earlier so this is the fallback.
    local profile_idx = pl:profile_index()
    local career_idx = pl:career_index()
    if SPProfiles and profile_idx and career_idx then
        local prof = SPProfiles[profile_idx]
        local c = prof and prof.careers and prof.careers[career_idx]
        local n = c and c.name
        if n then _cached_career = n; return n end
    end
    return _cached_career
end

-- ============================================================================
-- 3P animation-remap core (v0.12.210-dev Phase 2 OOP split) -> _wt_anim_remap.lua
-- ============================================================================
-- The three redirect layers (_anim_redirect / _career_anim_redirect /
-- _suffix_career_map), the per-weapon + per-template + per-key remap tables and
-- their resolvers, the weak-keyed per-unit remap state, the Unit.animation_event
-- funnel hook, the two wield hooks that populate that state, the read-only
-- /info support command, and the keep-previewer pose
-- resolver moved to _wt_anim_remap.lua in the v0.12.210-dev Phase 2 decomposition.
-- VERBATIM function-bag move, zero behavior change. The module keeps its own hot
-- tables as file-local upvalues (the anim path is per-event-hot), so the funnel
-- never reads through mod._wt. The entry publishes the hot-path handles the
-- module consumes BEFORE the dofile, and re-localizes the module's exports the
-- entry's stayed code still references (keep previewer, mesh-swap spawn path,
-- longbow template patchers, rt-check bodies). `feature_enabled` and
-- `_local_career_name` stay in the entry (generic player-state helpers; the
-- funnel reads them on a hot path, so the module captures them as upvalues).
mod._wt.feature_enabled   = feature_enabled
mod._wt.local_career_name = _local_career_name
mod._wt.dbg               = _dbg
-- WT_DEV_OVERLAY_BEGIN:anim-picker-export
mod._wt.dev_anim_picker   = _wt_dev_anim_picker
-- WT_DEV_OVERLAY_END:anim-picker-export
mod._wt.build_3p_template_remaps = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_anim_remap_data")
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_anim_remap")
-- #536: reload ownership differs from attack remapping, so keep its local-3P
-- replay and receiver-native volley contract in a separate, reload-only module.
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_reload_3p")
local _safe_has_anim               = mod._wt.safe_has_anim
local _resolve_preview_wield_event = mod._wt.resolve_preview_wield_event
local _unit_career_name            = mod._wt.unit_career_name
local _unit_state                  = mod._wt.unit_state
local _suffix_career_map           = mod._wt.suffix_career_map
local _3p_template_remaps          = mod._wt.three_p_template_remaps
mod._wt.flamestorm_fx_policy = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_flamestorm_fx_policy")
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_flamestorm_fx")
-- WT_DEV_OVERLAY_BEGIN:longbow-live-probe-owner
local _WT316_ZOOM_PROBE            = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_longbow_zoom_probe")
local _wt316_zoom_probe            = _WT316_ZOOM_PROBE.new()
local _wt316_zoom_records          = setmetatable({}, { __mode = "k" })
-- WT_DEV_OVERLAY_END:longbow-live-probe-owner
-- ============================================================
-- Weapon Scale Overrides
-- ============================================================
-- Scale factors for cross-character weapons that look too small/large.
-- Keys: weapon_key. Values: table of career_prefix -> scale factor.
-- A weapon only gets scaled when equipped on a career matching one of
-- the listed prefixes. Native-character entries are omitted (scale 1.0).
--
-- IMPORTANT: scale (and grip offset, see below) applies via TWO separate code
-- paths and BOTH must work for full visual consistency:
--   1. In-game keep / mission body: applied via the GearUtils.create_equipment
--      hook on the slot_data result (left/right_unit_1p/3p fields).
--   2. Inventory character preview (post-WoM new menu): applied via the
--      MenuWorldPreviewer hooks. The previewer spawns its OWN units that are
--      NOT the same instances as the in-game ones — modifying the in-game
--      units doesn't affect the preview. The previewer:
--        - exposes the weapon KEY only at equip_item(item_key, slot, backend_id)
--        - exposes the SPAWNED UNIT only at _spawn_item_unit(unit, slot_type, item_template, ...)
--          where item_template is the weapon TEMPLATE table (e.g. we_one_hand_axe_template),
--          not the inventory item — its .name is the template name, NOT the weapon key.
--      We therefore capture the weapon key in equip_item (per-previewer, weak-keyed
--      so dismissed previewers don't leak) and look it up in _spawn_item_unit by
--      slot_type ("melee"/"ranged"/"hat" — strip "slot_" prefix from the equip_item
--      slot.name to match).
-- When adding new scale or grip-offset entries, no extra code is needed — both
-- paths share the same _scale_weapon_units / _offset_weapon_units helpers and
-- look up the same _weapon_scale_overrides / _weapon_grip_offsets tables.

-- Scale overrides: value is a number (uniform) or {x,y,z} table (per-axis).
local _weapon_scale_overrides = {
    we_1h_sword    = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
    bw_sword       = { es_ = 1.15, wh_ = 1.15, dr_ = 1.10 },
    bw_1h_crowbill = { es_ = 1.10, wh_ = 1.10, dr_ = 1.05 },
    we_2h_sword    = { es_ = 1.15 },
    dr_2h_axe      = { es_ = {1, 1.15, 1}, wh_ = {1, 1.15, 1}, we_ = {1, 1.15, 1}, bw_ = {1, 1.15, 1} },
    dr_1h_axe      = { we_ = {0.85, 0.85, 1} },
    dr_1h_hammer   = { we_ = {0.85, 0.85, 1} },
}

local function _resolve_scale_factor(weapon_key, career_name)
    if not weapon_key or not career_name then return nil end
    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides then return nil end
    for prefix, factor in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            return factor
        end
    end
    return nil
end

local _scale_field_probe_logged = {}
local function _scale_weapon_units(slot_data, weapon_key, career_name)
    if not weapon_key or not career_name then return end

    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides then return end

    -- One-time probe: dump the slot_data fields the first time we scale this
    -- weapon. Helps identify any unit fields the menu preview uses that we're
    -- missing in the unit_fields list.
    if not _scale_field_probe_logged[weapon_key] then
        _scale_field_probe_logged[weapon_key] = true
        for k, v in pairs(slot_data) do
            local t = type(v)
            if t == "userdata" then
                _dbg("[scale_probe] %s slot_data.%s (UNIT)", weapon_key, tostring(k))
            elseif t == "table" then
                _dbg("[scale_probe] %s slot_data.%s (table)", weapon_key, tostring(k))
            end
        end
    end

    local scale_factor = _resolve_scale_factor(weapon_key, career_name)
    if not scale_factor then return end

    local scale
    if type(scale_factor) == "table" then
        scale = Vector3(scale_factor[1], scale_factor[2], scale_factor[3])
    else
        scale = Vector3(scale_factor, scale_factor, scale_factor)
    end
    -- CLARIFY: scale all four hand units identically. Unlike grip offset (which
    -- has a `hand` field for shield-only/weapon-only scaling), scale always
    -- applies to both hands — there's no entry in `_weapon_scale_overrides`
    -- that scales only one hand, but if there were, the schema doesn't support
    -- it (no `_fields` like cosmetics_tweaker has).
    local unit_fields = { "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }
    for _, field in ipairs(unit_fields) do
        local unit = slot_data[field]
        if unit then
            pcall(Unit.set_local_scale, unit, 0, scale)
        end
    end
    if type(scale_factor) == "table" then
        _dbg("Scaled %s on %s by {%.2f, %.2f, %.2f}", weapon_key, career_name, scale_factor[1], scale_factor[2], scale_factor[3])
    else
        _dbg("Scaled %s on %s by %.2fx", weapon_key, career_name, scale_factor)
    end
end

-- 3P grip deltas are {x,y,z[, hand]}; spawn, preview, and durable paths share them.
-- +z seats the grip lower; an omitted hand targets both spawned 3P units.
local _weapon_grip_offsets = {
    we_1h_sword    = { dr_ = {0, 0, 0.05} },
    bw_sword       = { dr_ = {0, 0, 0.05} },
    es_1h_sword    = { dr_ = {0, 0, 0.05} },
    wh_dual_hammer = { dr_ = {0, 0, 0.15} },
    wh_1h_hammer   = { es_ = {0, 0, 0.15} },
    wh_hammer_shield = { es_ = {0, 0, 0.15, hand = "right"} },
    es_2h_sword    = { we_ = {0, 0, -0.085} },
    wh_2h_sword    = { we_ = {0, 0, -0.085} },
    -- Necromancer Ghost Scythe ported to Kruber (es_) renders as Greathammer in 3P
    -- (staff_scythe remap above) and needs the grip dropped +0.6 Z so Kruber's
    -- hands sit on the haft. Moved to the DURABLE per-frame re-apply path (see
    -- _DURABLE_GRIP_OFFSETS / OFFSETS.md) because a one-shot create_equipment
    -- write was STOMPED every animation tick in-game (preview-OK / in-game-wrong);
    -- the scythe now re-applies its offset every frame from mod.update, exactly
    -- like the dev hold-pose tool does. Career-scoped to es_ ONLY (Sienna's bw_*
    -- careers find no matching prefix -> offset stays nil -> early return, so
    -- Sienna's native scythe grip is NOT moved). 3P-ONLY by construction (both
    -- _offset_weapon_units and the durable re-apply write only *_unit_3p, never
    -- 1P). See _DURABLE_GRIP_OFFSETS just below for the why.
    bw_ghost_scythe = { es_ = {0, 0, 0.6} },
    -- Elven 2H Axe/Glaive -> Greathammer on Kruber; durable, es_-only, Z grip.
    -- Same durable per-frame re-apply as the scythe (see _DURABLE_GRIP_OFFSETS):
    -- a one-shot set_local_position is stomped every anim tick in-game (survives
    -- preview, reverts in gameplay). es_ ONLY (Kruber); other careers / native
    -- wielders of two_handed_axes_template_2 find no prefix -> offset nil -> early
    -- return, so they're untouched. 3P-ONLY by construction. (+0.285 Z.)
    we_2h_axe = { es_ = {0, 0, 0.285} },
    -- Sienna Flamestorm Staff (bw_skullstaff_flamethrower) ported to Kruber (es_)
    -- renders as Greathammer in 3P (staff anims redirect, picker SET A) and needs
    -- the grip dropped +0.6 Z so Kruber's hands seat on the staff haft — same value
    -- and durable per-frame re-apply as the scythe (a one-shot write is stomped
    -- every anim tick in-game). es_ ONLY (Kruber); Sienna's bw_* careers find no
    -- prefix -> offset nil -> early return, so the native Sienna grip is untouched.
    -- 3P-ONLY by construction. (User-tuned +0.6 Z, 2026-06-27.)
    bw_skullstaff_flamethrower = { es_ = {0, 0, 0.6} },
    -- The remaining Sienna staves ported to Kruber (es_) ALSO render as Greathammer
    -- in 3P (picker SET A) and need the SAME +0.6 Z grip drop so Kruber's hands seat
    -- on the staff haft (identical to the Flamestorm Staff above; user-directed
    -- 2026-06-29 "all sienna staves on kruber that haven't been given that"). es_ ONLY
    -- (Kruber); Sienna's bw_* careers find no prefix -> offset nil -> native grip
    -- untouched. DURABLE (large offset is stomped each anim tick in-game — all listed
    -- in _DURABLE_GRIP_OFFSETS). 3P + inventory-preview ONLY by construction (both
    -- paths read this table and write only *_unit_3p; 1P is never touched).
    bw_skullstaff_beam     = { es_ = {0, 0, 0.6} },
    bw_skullstaff_fireball = { es_ = {0, 0, 0.6} },
    bw_skullstaff_geiser   = { es_ = {0, 0, 0.6} },
    bw_skullstaff_spear    = { es_ = {0, 0, 0.6} },
    bw_necromancy_staff    = { es_ = {0, 0, 0.6} },
    bw_deus_01             = { es_ = {0, 0, 0.6} },
    -- Bretonnian Longsword (es_bastard_sword) on Saltzpyre (wh_) needs the grip
    -- dropped +0.08 Z so it seats in Saltzpyre's hands. wh_-ONLY (Saltzpyre); Kruber
    -- (es_) and other wielders of bastard_sword_template find no prefix -> offset nil
    -- -> untouched. DURABLE: node 0 is reset every anim tick, so a one-shot is stomped
    -- in-game (the value was user-tuned via the per-frame hold-pose tuner). 3P-only.
    -- (User-tuned +0.08 Z, 2026-06-28.)
    es_bastard_sword = { wh_ = {0, 0, 0.08} },
    -- Empire Handgun (es_handgun) on standard Saltzpyre bodies. The original
    -- correction was removed in v0.12.136 because it had been written into the
    -- shared attachment-linking table and therefore also moved native wielders.
    -- Keep the replacement receiver-scoped: all wh_* careers resolve this baked
    -- Y/Z delta, while every es_* Kruber career falls through untouched. It is
    -- durable because animation ticks were the user-observed source of the lost
    -- offset. Position-only application composes with #569 rotation and scale.
    es_handgun = { wh_ = {0, -0.17, -0.05} },
    wh_crossbow = { es_ = {0, 0.100, 0.025, hand = "left"} }, -- #701 Kruber, 3P left hand only
    -- Single source of truth for preview, spawn, and durable 3P grip nudges.
    --   * SMALL static nudges (the 0.05-0.15 entries above): a one-shot additive
    --     write at create_equipment / preview spawn via _offset_weapon_units. Fine
    --     for small deltas the engine's per-frame attachment re-apply doesn't
    --     visibly disturb.
    --   * STOMP-PRONE large offsets (the scythe): ALSO listed in
    --     _DURABLE_GRIP_OFFSETS below, which re-applies the SAME value every frame
    --     in-game so the engine's per-tick canonical-pose reset can't erase it.
    -- NEVER bake a tuned hold-pose value as a raw attachment-linking write on a SHARED template
    -- (staff_scythe is shared with Sienna) — that breaks the native wielder. The
    -- durable re-apply is career-gated to es_ instead. (es_handgun-on-Saltzpyre
    -- offset was mis-baked into a linking table in v0.12.135 and reverted in .136.)
}

-- Baked local-Euler corrections for cross-character 3P weapon roots. These
-- are deltas over each spawned unit's captured canonical rotation, never
-- absolute poses. The three Kruber shield families below use Saltzpyre's
-- Axe+Falchion body vocabulary on WHC/BH/Zealot, so they share the user's
-- tuned seating correction. Spear & Shield (`es_deus_01`) is intentionally
-- absent. CWV's Empire Axe+Shield currently inherits `.name = dr_shield_axe`
-- from its donor; retain both public variant keys for a future identity fix
-- and the donor alias for the live clone-name boundary.
local _SALTZ_KRUBER_SHIELD_ROTATION = { 25, -17.5, -15 }
local _weapon_rotation_overrides = {
    es_mace_shield           = { wh_ = _SALTZ_KRUBER_SHIELD_ROTATION },
    es_sword_shield          = { wh_ = _SALTZ_KRUBER_SHIELD_ROTATION },
    es_sword_shield_breton   = { wh_ = _SALTZ_KRUBER_SHIELD_ROTATION },
    dr_shield_axe            = { wh_ = _SALTZ_KRUBER_SHIELD_ROTATION },
    cwv_es_axe_shield        = { wh_ = _SALTZ_KRUBER_SHIELD_ROTATION },
    cwv_es_axe_shield_veteran = { wh_ = _SALTZ_KRUBER_SHIELD_ROTATION },
}

local function _resolve_rotation_override(weapon_key, career_name)
    if not weapon_key or not career_name then return nil end
    local overrides = _weapon_rotation_overrides[weapon_key]
    if not overrides then return nil end
    for prefix, rotation in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            return rotation
        end
    end
    return nil
end

-- ===========================================================================
-- DURABLE (per-frame re-applied) 3P grip offsets.    [OFFSETS.md]
-- ===========================================================================
-- WHY THIS EXISTS (the preview-OK / in-game-wrong failure):
--   A one-shot Unit.set_local_position written at create_equipment time SURVIVES
--   in the inventory MODEL PREVIEW (MenuWorldPreviewer poses the weapon once and
--   does NOT re-drive node 0 every frame) but is STOMPED in-game: the running
--   animation system re-applies each weapon unit's canonical attachment-node pose
--   on the very next tick, resetting node 0 and erasing our offset. This is
--   source-confirmed by wt_dev_hold_pose.lua:16-21 ("a one-shot set_local_pose is
--   overwritten on the very next animation tick ... re-writing the local pose
--   every frame keeps the value visible"). So a large grip drop (the +0.6 scythe)
--   looked right in preview and reverted to raw position in-game.
--
-- HOW THE DURABLE PATH WORKS:
--   For weapon_keys listed here, _reapply_durable_grip_offsets() runs every frame
--   (driven from weapon_tweaker_backend.lua's mod.update) on tracked wielded 3P
--   weapon units: local player, bots, and remote husks. Spawn/wield registration
--   boxes the canonical position before the one-shot offset; each tick writes
--   canonical + baked delta. The absolute reconstruction is stable and cannot
--   compound. No RPC is involved: every WT renderer reads the shipped tables.
--
-- INVARIANTS (do not break):
--   * 3P-ONLY: writes only right_unit_3p / left_unit_3p. NEVER 1P (universal
--     first person, the user's hard rule — feedback_cross_char_transforms_3p_only).
--   * CAREER-ONLY: gated on the same prefix match as _offset_weapon_units, so
--     only the receiving career (es_ = Kruber) is moved; the native wielder
--     (Sienna's bw_*) finds no prefix and is untouched.
--   * RENDERER-LOCAL fan-out: owner, bot, and remote-husk units are weak-tracked
--     at spawn/wield. Transient tuner values are never tracked or transported.
--   * SINGLE SOURCE OF TRUTH: the offset VALUE lives in _weapon_grip_offsets, not
--     here. This table is just the membership set of keys that need re-applying.
--
-- To add a weapon to the durable path: add its key = true here AND its offset to
-- _weapon_grip_offsets above. To remove: delete from here (the one-shot path in
-- _offset_weapon_units still applies the value at spawn for preview).
local _DURABLE_GRIP_OFFSETS = {
    bw_ghost_scythe = true,
    we_2h_axe       = true,  -- Elven 2H Axe/Glaive on Kruber (+0.285 Z, es_-only)
    bw_skullstaff_flamethrower = true,  -- Sienna Flamestorm Staff on Kruber (+0.6 Z, es_-only)
    bw_skullstaff_beam         = true,  -- Sienna Beam Staff on Kruber (+0.6 Z, es_-only)
    bw_skullstaff_fireball     = true,  -- Sienna Fireball Staff on Kruber (+0.6 Z, es_-only)
    bw_skullstaff_geiser       = true,  -- Sienna Conflagration Staff on Kruber (+0.6 Z, es_-only)
    bw_skullstaff_spear        = true,  -- Sienna Bolt Staff on Kruber (+0.6 Z, es_-only)
    bw_necromancy_staff        = true,  -- Sienna Soulstealer Staff on Kruber (+0.6 Z, es_-only)
    bw_deus_01                 = true,  -- Sienna Coruscation Staff on Kruber (+0.6 Z, es_-only)
    es_bastard_sword           = true,  -- Bretonnian Longsword on Saltzpyre (+0.08 Z, wh_-only)
    es_handgun                 = true,  -- Empire Handgun on Saltzpyre (-0.17 Y, -0.05 Z, wh_-only)
    wh_crossbow                = true,  -- Saltzpyre Crossbow on Kruber (+0.100 Y, +0.025 Z, left-only, #701)
}

-- Resolve the career-prefix-matched offset entry for (weapon_key, career_name)
-- from _weapon_grip_offsets. Returns the {x, y, z[, hand]} array or nil. Shared
-- by the one-shot and durable paths so owner bodies, bots, remote husks, and the
-- preview all consume the same baked value.
local function _resolve_grip_offset(weapon_key, career_name)
    if not weapon_key or not career_name then return nil end
    local overrides = _weapon_grip_offsets[weapon_key]
    if not overrides then return nil end
    for prefix, off in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            return off
        end
    end
    return nil
end

local function _offset_weapon_units(slot_data, weapon_key, career_name)
    if not weapon_key or not career_name then return end

    local offset = _resolve_grip_offset(weapon_key, career_name)
    if not offset then return end

    local pos = Vector3(offset[1], offset[2], offset[3])
    local hand = offset.hand
    -- v0.12.136-dev: 3P-ONLY. Grip offsets must NEVER move the 1P units
    -- (right_unit_1p / left_unit_1p). First person is universal across all six
    -- characters and renders correctly by default — offsetting it visibly breaks
    -- the first-person view (the user's hard rule: never touch 1P unless asked).
    -- The *_1p fields that used to be in these lists were a latent bug: EVERY
    -- grip offset was silently shifting the 1P weapon too. Cross-character grip
    -- correction is a 3P-skeleton concern only.
    local unit_fields
    if hand == "right" then
        unit_fields = { "right_unit_3p" }
    elseif hand == "left" then
        unit_fields = { "left_unit_3p" }
    else
        unit_fields = { "left_unit_3p", "right_unit_3p" }
    end
    for _, field in ipairs(unit_fields) do
        local unit = slot_data[field]
        if unit then
            -- POTENTIAL BUG (LOW): if create_equipment fires multiple times for
            -- the same unit instance (e.g. weapon swap that re-wields the same
            -- key), the offset compounds (current = previous_offset_position).
            -- Vanilla units start at zero local_position so the first apply
            -- is correct; subsequent applies double up. Not currently a known
            -- issue because spawning re-creates the unit instance.
            local ok_current, current = pcall(Unit.local_position, unit, 0)
            if ok_current and current then
                pcall(Unit.set_local_position, unit, 0, current + pos)
            end
        end
    end
    _dbg("Offset %s on %s by {%.3f, %.3f, %.3f} (hand=%s)", weapon_key, career_name, offset[1], offset[2], offset[3], tostring(hand or "both"))
end

-- #587 committed transform fan-out. "Committed" means source-baked in the two
-- tables above; the live Hold-Pose sliders remain local-player-only and never
-- enter this path. Each WT client can resolve the base item key and husk career
-- already supplied by vanilla, so no mod RPC (and no per-frame payload) exists.
local _wt587_tracked_durable_3p_units = setmetatable({}, { __mode = "k" })
local _wt587_diag_budget = 24

mod._wt587_transform_contract = {
    source = "baked_tables",
    transport = "none",
    rpc_channels = 0,
    live_tuner_scope = "local_player_3p_only",
    first_person = "unchanged",
    components = { scale = "scale_only", offset = "position_only", rotation = "wt569_rotation_only" },
}

mod._wt587_baked_transform_plan = function(weapon_key, career_name)
    return {
        scale = _resolve_scale_factor(weapon_key, career_name),
        offset = _resolve_grip_offset(weapon_key, career_name),
        rotation = _resolve_rotation_override(weapon_key, career_name),
        durable = _DURABLE_GRIP_OFFSETS[weapon_key] == true,
    }
end

local function _wt587_is_wielded(row)
    local owner = row.owner
    if not owner then return false end
    local ok_alive, alive = pcall(Unit.alive, owner)
    if not ok_alive or not alive then return false end
    local inv = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner, "inventory_system")
    if not inv or type(inv.get_wielded_slot_name) ~= "function" then return false end
    local ok_slot, wielded_slot = pcall(inv.get_wielded_slot_name, inv)
    return ok_slot and wielded_slot == row.slot_name
end

local function _wt587_track_durable_3p_units(slot_data, weapon_key, career_name, owner_3p, slot_name, role)
    if not _DURABLE_GRIP_OFFSETS[weapon_key] then return 0 end
    local offset = _resolve_grip_offset(weapon_key, career_name)
    if not offset then return 0 end
    local wanted_hand = offset.hand
    local tracked = 0
    for _, field in ipairs({ "right_unit_3p", "left_unit_3p" }) do
        local hand = field == "right_unit_3p" and "right" or "left"
        local unit = slot_data and slot_data[field]
        if unit and (not wanted_hand or wanted_hand == hand)
                and not _wt587_tracked_durable_3p_units[unit] then
            local ok_alive, alive = pcall(Unit.alive, unit)
            local ok_pos, base_position = pcall(Unit.local_position, unit, 0)
            if ok_alive and alive and ok_pos and base_position then
                _wt587_tracked_durable_3p_units[unit] = {
                    base = Vector3Box(base_position),
                    owner = owner_3p,
                    slot_name = slot_name,
                    weapon_key = weapon_key,
                    career_name = career_name,
                    hand = hand,
                    role = role,
                    offset = { offset[1], offset[2], offset[3] },
                }
                tracked = tracked + 1
                if _wt587_diag_budget > 0 then
                    _wt587_diag_budget = _wt587_diag_budget - 1
                    pcall(printf,
                        "[wt:587] tracked role=%s career=%s weapon=%s hand=%s slot=%s transport=none first_person=untouched",
                        tostring(role or "owner"), tostring(career_name), tostring(weapon_key),
                        tostring(hand), tostring(slot_name))
                end
            end
        end
    end
    return tracked
end
mod._wt587_track_durable_3p_units = _wt587_track_durable_3p_units

-- Animation ticks stomp weapon node 0, so every renderer reapplies its own
-- shipped baked delta to tracked local, bot, and remote-husk 3P units. The base
-- pose was boxed before the one-shot spawn write; absolute base+delta avoids
-- accumulation. Rotation (#569) and scale use separate setters and compose.
function mod._reapply_durable_grip_offsets()
    for unit, row in pairs(_wt587_tracked_durable_3p_units) do
        local ok_alive, alive = pcall(Unit.alive, unit)
        if not ok_alive or not alive then
            _wt587_tracked_durable_3p_units[unit] = nil
        elseif _wt587_is_wielded(row) then
            local base = row.base:unbox()
            local target = base + Vector3(row.offset[1], row.offset[2], row.offset[3])
            pcall(Unit.set_local_position, unit, 0, target)
            _wt_grip_offset_policy.log_issue701_retained_once(row, unit, target)
        end
    end
end

-- ===========================================================================
-- #569: non-WP Saltzpyre + Warrior Priest greathammer remap orientation
-- ===========================================================================
-- Vanilla's two_handed_melee_weapon linking attaches weapon node 0 directly to
-- body `j_rightweaponattach` with no rotation layer
-- (attachment_node_linking.lua:2836-2864); GearUtils.spawn_inventory_unit then
-- performs that link for the 3P unit before create_equipment returns
-- (gear_utils.lua:150-185). The correction therefore belongs on the linked 3P
-- weapon root, not in a shared template and not on the 1P unit.
--
-- Axis: WT's empirically tuned grip coordinate system uses local Z along the
-- weapon haft (`_weapon_grip_offsets`: +Z moves the grip lower). Rotating 180
-- degrees about LOCAL Z reverses the transverse weapon facing while preserving
-- the head-to-grip/haft direction. X or Y would reverse that longitudinal axis.
-- Use axis-angle explicitly so the boundary is unambiguous.
local _WT569_STANDARD_SALTZ_CAREERS = {
    wh_captain = true,
    wh_bountyhunter = true,
    wh_zealot = true,
}
local _WT569_NATIVE_WP_HAMMER_KEY = "wh_2h_hammer"
local _WT569_REMAP_EVENT = "to_2h_hammer_priest"
local _WT569_LOCAL_AXIS = { 0, 0, 1 }
local _WT569_DEGREES = 180
local _wt569_tracked_3p_units = setmetatable({}, { __mode = "k" })

mod._wt569_should_rotate_3p = function(weapon_key, career_name, item_template)
    if not _WT569_STANDARD_SALTZ_CAREERS[career_name] then return false end
    if _resolve_rotation_override(weapon_key, career_name) then return true end
    if weapon_key == _WT569_NATIVE_WP_HAMMER_KEY then return false end
    local by_career = item_template and item_template.wield_anim_career_3p
    return type(by_career) == "table"
        and by_career[career_name] == _WT569_REMAP_EVENT
end

mod._wt569_orientation_contract = {
    axis = _WT569_LOCAL_AXIS,
    degrees = _WT569_DEGREES,
    remap_event = _WT569_REMAP_EVENT,
    native_exempt_key = _WT569_NATIVE_WP_HAMMER_KEY,
    baked_shield_euler = _SALTZ_KRUBER_SHIELD_ROTATION,
    baked_shield_scope = "standard_saltzpyre_3p",
    spear_shield_exempt_key = "es_deus_01",
}

local function _wt569_rotation_delta(row)
    local euler = row and row.euler
    if euler then
        return Quaternion.from_euler_angles_xyz(euler[1], euler[2], euler[3])
    end
    return Quaternion.axis_angle(Vector3(0, 0, 1), math.pi)
end

local function _wt569_track_3p_units(slot_data, weapon_key, career_name, item_template, owner_3p, slot_name, preview_wielded)
    if not mod._wt569_should_rotate_3p(weapon_key, career_name, item_template) then return end
    local baked_euler = _resolve_rotation_override(weapon_key, career_name)
    for _, field in ipairs({ "right_unit_3p", "left_unit_3p" }) do
        local unit = slot_data and slot_data[field]
        if unit and not _wt569_tracked_3p_units[unit] then
            local ok_alive, alive = pcall(Unit.alive, unit)
            local ok_rot, base_rotation = pcall(Unit.local_rotation, unit, 0)
            if ok_alive and alive and ok_rot and base_rotation then
                _wt569_tracked_3p_units[unit] = {
                    base = QuaternionBox(base_rotation),
                    owner = owner_3p,
                    slot_name = slot_name,
                    preview_wielded = preview_wielded == true,
                    weapon_key = weapon_key,
                    career_name = career_name,
                    hand = field == "right_unit_3p" and "right" or "left",
                    euler = baked_euler and { baked_euler[1], baked_euler[2], baked_euler[3] } or nil,
                }
                if baked_euler then
                    pcall(printf,
                        "[wt:112] tracked shield rotation career=%s weapon=%s hand=%s euler={%.1f,%.1f,%.1f} first_person=untouched",
                        tostring(career_name), tostring(weapon_key),
                        field == "right_unit_3p" and "right" or "left",
                        baked_euler[1], baked_euler[2], baked_euler[3])
                else
                    pcall(printf,
                        "[wt:569] tracked career=%s weapon=%s hand=%s remap=%s axis=local_z degrees=180 first_person=untouched",
                        tostring(career_name), tostring(weapon_key),
                        field == "right_unit_3p" and "right" or "left", _WT569_REMAP_EVENT)
                end
            end
        end
    end
end

local function _wt569_is_wielded(row)
    if row.preview_wielded then return true end
    local owner = row.owner
    if not owner then return false end
    local ok_alive, alive = pcall(Unit.alive, owner)
    if not ok_alive or not alive then return false end
    local inv = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner, "inventory_system")
    if not inv or type(inv.get_wielded_slot_name) ~= "function" then return false end
    local ok_slot, wielded_slot = pcall(inv.get_wielded_slot_name, inv)
    return ok_slot and wielded_slot == row.slot_name
end

-- Per-frame absolute-from-captured-canonical application. Animation ticks reset
-- weapon node 0, so one-shot rotation is insufficient (same paid-for boundary
-- as durable grip offsets). We never multiply the current rotation: the boxed
-- canonical is composed with exactly one local-Z half-turn every frame, which
-- prevents double rotation even if create_equipment is revisited for a unit.
-- Tracking all spawned 3P units covers local player, bots, remote husks, and the
-- inventory preview; dead units fall out of the weak-key table.
function mod._wt569_reapply_3p_orientation()
    for unit, row in pairs(_wt569_tracked_3p_units) do
        local ok_alive, alive = pcall(Unit.alive, unit)
        if not ok_alive or not alive then
            _wt569_tracked_3p_units[unit] = nil
        else
            local base = row.base:unbox()
            local desired = base
            local corrected = _wt569_is_wielded(row)
            if corrected then
                desired = Quaternion.multiply(base, _wt569_rotation_delta(row))
            end
            pcall(Unit.set_local_rotation, unit, 0, desired)
            if row.last_corrected ~= corrected then
                row.last_corrected = corrected
                pcall(printf, "[wt:569] applied=%s career=%s weapon=%s hand=%s slot=%s mode=%s",
                    tostring(corrected), tostring(row.career_name), tostring(row.weapon_key),
                    tostring(row.hand), tostring(row.slot_name or "preview"),
                    row.euler and "baked_euler" or "wp_half_turn")
            end
        end
    end
end

-- Hold-Pose needs the same authoritative corrected baseline without depending
-- on per-frame hook order. A nil return means the unit is outside #569 scope.
function mod._wt569_desired_rotation_for_unit(unit)
    local row = _wt569_tracked_3p_units[unit]
    if not row then return nil end
    local base = row.base:unbox()
    if not _wt569_is_wielded(row) then return base end
    return Quaternion.multiply(base, _wt569_rotation_delta(row))
end

-- CW crash on ghost scythe 3P spawn (crashify://77917479-d053-4d34-b6b9-629878a7e6ec).
-- Unit hash 877616b4d5c71f36 = wpn_bw_ghost_scythe_01_3p (Necromancer base mesh). For
-- bw_unchained, vanilla `right_hand_unit_override.bw_unchained = "..._fire"` should
-- redirect to the _fire variant — and the package preloader DID load _fire_3p — but
-- the equip flow asked for the base. Crash dump shows career_name="bw_unchained" at
-- every modded hook frame yet nil at the unwrapped GearUtils.create_equipment entry,
-- so the per-career override at backend_utils.lua:159-162 was skipped. Engine fatal
-- in world.spawn_unit bypasses pcall (feedback_vt2_unit_node_not_pcall_safe.md), so
-- the pcall below catches Lua errors only — the real fix is the career_name fallback.
-- Rendering-path coverage: this is path 1 (in-game). Path 2 (HeroPreviewer) hook
-- lives below. Path 3 (LootItemUnitPreviewer) is intentionally NOT covered per
-- feedback_grip_offset_sign.md; CWV covers all three.
-- v0.12.77 (Issue #26): converted to `mod:safe_hook`. This is the in-game
-- (path 1 of 3) rendering hook for the keep + every mission spawn — a
-- raise inside here would kill cosmetics_tweaker / cwv / LA hooks on the
-- same Class.method silently, manifesting as "weapon model didn't apply"
-- with no log line to chase.
-- v0.12.84-dev: promoted to `mod:traced_hook` (Layer 3). Equip events are
-- per-mission-spawn / per-keep-load rate (NOT per-frame), so trace lines
-- are safe. The entry/exit pair confirms the in-game rendering path fired
-- and lets the user count returns when chasing cross-mod regressions.
mod:traced_hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    -- Fallback: if career_name was lost somewhere in the hook chain (observed in
    -- CW bot spawns), recover it from the spawning unit's inventory extension.
    -- _career_name is set in SimpleInventoryExtension.init before extensions_ready,
    -- so it's always available here (feedback_vt2_mission_spawn_career_lookup.md).
    if career_name == nil and unit_3p and ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(unit_3p, "inventory_system") then
        local inv = ScriptUnit.extension(unit_3p, "inventory_system")
        career_name = inv and inv._career_name or nil
        if career_name then
            mod:warning("[create_equipment] recovered nil career_name -> %s (weapon=%s slot=%s is_bot=%s)",
                tostring(career_name), tostring(item_data and item_data.name), tostring(slot_name), tostring(is_bot))
        end
    end

    -- v0.12.24: pre-resolve item_units when item_data has a per-career override.
    -- The hook chain reliably drops career_name between our wrapper (frame [12]
    -- in crash dumps shows "bw_unchained") and the unwrapped gear_utils.create_equipment
    -- (frame [10] shows nil), so its internal `BackendUtils.get_item_units(...,
    -- career_name)` runs with career_name=nil and the `right_hand_unit_override`
    -- block at backend_utils.lua:159 is skipped. Result: Sienna's non-Necromancer
    -- careers get the BASE bw_ghost_scythe 3p unit (not preloaded for them) →
    -- engine fatal in world.spawn_unit. We resolve item_units here with the
    -- correct career_name and inject via override_item_units, which gear_utils
    -- uses verbatim (`item_units = override_item_units or get_item_units(...)`).
    -- Gated on the item_data actually having a per-career override so we don't
    -- waste a function call on every spawn.
    if override_item_units == nil and item_data and career_name and BackendUtils
            and BackendUtils.get_item_units
            and ((item_data.right_hand_unit_override and item_data.right_hand_unit_override[career_name])
              or (item_data.left_hand_unit_override and item_data.left_hand_unit_override[career_name])) then
        local ok_resolve, resolved = pcall(BackendUtils.get_item_units, item_data, item_data.backend_id, nil, career_name)
        if ok_resolve and type(resolved) == "table" then
            override_item_units = resolved
            _dbg("[create_equipment] pre-resolved item_units for %s on %s (rhu=%s)",
                tostring(item_data.name), tostring(career_name), tostring(resolved.right_hand_unit))
        end
    end

    local ok, result = pcall(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if not ok then
        local weapon_key = item_data and item_data.name or "unknown"
        local has_override = item_data and item_data.right_hand_unit_override and "yes" or "no"
        local rhu = item_data and item_data.right_hand_unit or "nil"
        mod:error("create_equipment CRASHED: weapon=%s slot=%s career=%s is_bot=%s rhu=%s has_override=%s err=%s",
            tostring(weapon_key), tostring(slot_name), tostring(career_name),
            tostring(is_bot), tostring(rhu), has_override, tostring(result))
        -- Return an EMPTY stub, NEVER nil: vanilla SimpleInventoryExtension.add_equipment
        -- indexes the return UNGUARDED (`slot_equipment_data.master_item = ...` and
        -- `.skin`, simple_inventory_extension.lua:876/880), so a nil return converts our
        -- CAUGHT error into a HARD crash on the caller ("attempt to index local
        -- 'slot_equipment_data' (a nil value)"). Repro: a non-resident level-event 3p unit
        -- -- e.g. a whale_oil_barrel /spawn-ed off the whaling map -- makes cosmetics_tweaker
        -- skip the spawn (avoiding a C-assert), vanilla GearUtils then indexes the nil unit
        -- (entity_manager2.lua:114) and raises, we catch it, and the old `return nil` crashed
        -- add_equipment (console 2026-07-06-00.12.37, guid ff863169). With a stub the item
        -- equips-but-unrendered (all unit fields nil -> vanilla wield guards on Unit.alive)
        -- instead of taking down the game; the [wt][ERROR] above stays for diagnosis.
        return {}
    end
    if result and item_data then
        local weapon_key = item_data.name
        _scale_weapon_units(result, weapon_key, career_name)
        -- Capture the canonical 3P root before the one-shot offset below. The
        -- durable renderer then owns base+delta for local players and bots.
        _wt587_track_durable_3p_units(result, weapon_key, career_name,
            unit_3p, slot_name, is_bot and "bot" or "owner")
        _offset_weapon_units(result, weapon_key, career_name)
        _wt569_track_3p_units(result, weapon_key, career_name, result.item_template,
            unit_3p, slot_name, false)
    end
    return result or {}   -- never nil to the vanilla caller (see stub rationale above)
end)

-- Vanilla remote-husk wield is a separate renderer. Unlike the owner path, it
-- calls BackendUtils.get_item_units + GearUtils.spawn_inventory_unit directly
-- and never enters GearUtils.create_equipment
-- (simple_husk_inventory_extension.lua:641-782). Apply the same source-baked
-- transforms after vanilla has populated equipment.*_wielded_unit_3p. The base
-- item identity and self._career_name are already replicated by vanilla, so
-- this fan-out is deterministic on every WT client and sends no network data.
mod:hook_safe("SimpleHuskInventoryExtension", "_wield_slot",
    function(self, world, equipment, slot_name, unit_1p, unit_3p)
        local slot = equipment and equipment.slots and equipment.slots[slot_name]
        local item_data = slot and slot.item_data
        local weapon_key = item_data and (item_data.name or item_data.key)
        local career_name = self and self._career_name
        if not weapon_key or not career_name then return end

        local spawned_3p = {
            right_unit_3p = equipment.right_hand_wielded_unit_3p,
            left_unit_3p = equipment.left_hand_wielded_unit_3p,
        }
        _scale_weapon_units(spawned_3p, weapon_key, career_name)
        _wt587_track_durable_3p_units(spawned_3p, weapon_key, career_name,
            (self and self._unit) or unit_3p, slot_name, "remote_husk")
        _offset_weapon_units(spawned_3p, weapon_key, career_name)

        local item_template = nil
        if BackendUtils and BackendUtils.get_item_template then
            local ok_template, resolved = pcall(BackendUtils.get_item_template, item_data)
            item_template = ok_template and resolved or nil
        end
        _wt569_track_3p_units(spawned_3p, weapon_key, career_name, item_template,
            (self and self._unit) or unit_3p, slot_name, false)
    end)

-- ============================================================
-- Brace of Pistols on Kruber → 3P unit swap to repeating handgun
-- ============================================================
-- Migrated from character_weapon_variants v0.1.187 (CWV's
-- `cwv_es_brace_repeater` variant + `_cwv_3p_unit_override_swap` hook).
-- WT exposes `wh_brace_of_pistols` to all 4 Kruber careers via the
-- unlock map at the top of this file. When Kruber actually equips it,
-- this hook swaps the 3P body unit from the brace pistol mesh to the
-- Empire repeating handgun mesh. The 1P side stays as the brace
-- (cross-arm fire animation is what makes it visually distinct).
--
-- Anim plumbing:
--   * `_BRACE_REPEATER_BASE_WIELD_3P` patches the base brace template's
--     `wield_anim_career_3p` for Kruber → `to_repeating_handgun` (Kruber's
--     vanilla repeater wield SM, authored on his empire-soldier 3P body).
--     Saltzpyre native wielders fall through (their careers aren't keyed
--     here), so vanilla brace 3P wield is unaffected for them.
--   * `_BRACE_REPEATER_ANIM_REMAP_3P`: the brace's `special_action`
--     (the fire-all-8-pistols finisher) doesn't exist on the repeater
--     SM. Substitute with `attack_shoot_fast` (closest repeater clip).
--     All other brace events (`attack_shoot`, `attack_shoot_fast`,
--     `lock_target`) ARE authored on the repeater SM and don't need a
--     remap.
--
-- Husks: same hook fires because remote-player spawn flows through the
-- same `GearUtils.spawn_inventory_unit`. Only `owner_unit_1p` is nil for
-- husks; the 3P spawn path is identical → other players see the
-- repeater on Kruber's body too.

local _BRACE_REPEATER_3P_UNIT = "units/weapons/player/wpn_emp_handgun_repeater_t1/wpn_emp_handgun_repeater_t1_3p"

-- Force-load the repeater rifle 3P unit at mod init. Vanilla packages for the
-- brace's right_hand_unit don't include the repeater unit (different weapon),
-- so when the swap below tries to spawn it via Managers.state.unit_spawner,
-- the resource manager has no entry → "Unit not found" assertion (crash GUID
-- d9e1d3d3 — the very crash this block is here to prevent).
--
-- Same fix CWV uses for the Tuskgor Javelin pup unit
-- (`character_weapon_variants.lua:2638` — Managers.package:load(unit_path,
-- ref, nil, async=true, prioritize=true)). Per VT2's pickup_package_loader
-- convention, the engine generates a per-unit synthetic package at the unit
-- path so calling :load with a unit path works as a "load this single unit's
-- assets" request. Load is async but fires at mod init, long before any
-- equip path runs — by the time the brace hook spawns, the unit is ready.
-- Documented in `feedback_cwv_cross_character_unit_packages.md` (pattern
-- known from Tuskgor v0.1.118 and now applied to Brace-Repeater).
local function _force_load_brace_repeater_3p_unit()
    if not (Managers and Managers.package) then return end
    local ok, err = pcall(function()
        Managers.package:load(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p", nil, true, true)
    end)
    if ok then
        mod:info("[wt brace-3p-swap] force-loaded repeater 3P unit: %s", _BRACE_REPEATER_3P_UNIT)
    else
        mod:warning("[wt brace-3p-swap] failed to force-load repeater 3P unit: %s", tostring(err))
    end
end

_force_load_brace_repeater_3p_unit()

-- ============================================================
-- Saltzpyre Longbow → Crossbow 3P swap (parallel to brace→repeater)
-- ============================================================
-- Mirrors the brace→repeater pattern but with three differences:
--   1. LEFT-hand swap (bow/crossbow are left-hand weapons; brace was right-hand).
--   2. TWO units swapped per spawn: weapon (bow→crossbow) AND ammo (arrow→bolt).
--      The bow's ammo_data.ammo_hand == "left" so spawn_inventory_unit for
--      hand="left" returns (weapon_unit_3p, ammo_unit_3p, weapon_unit_1p,
--      ammo_unit_1p) — all four. Brace had no ammo unit; this one does.
--   3. Career detection still uses the v0.12.17 _unit_career_name (inventory-
--      ext-first; correctly populated at mission-spawn timing).
--
-- 1P stays vanilla longbow (1P is universal across characters — Saltzpyre
-- visually wields a bow in first-person view, fires arrows, same SM as
-- Huntsman). 3P body and ammo prop swap to crossbow + bolt so other
-- players (and the inventory preview) see Saltzpyre wielding a crossbow.
local _SP_CROSSBOW_3P_UNIT = "units/weapons/player/wpn_empire_crossbow_t1/wpn_empire_crossbow_tier1_3p"
local _SP_CROSSBOW_BOLT_3P_UNIT = "units/weapons/player/wpn_crossbow_quiver/wpn_crossbow_bolt_3p"

-- #580: all bow-like item keys whose Saltzpyre presentation is substituted
-- with his native crossbow. Keep this one predicate shared by the in-mission
-- spawn dispatcher and keep preview helper so those two ownership surfaces
-- cannot drift. This controls 3P units only; the swap helper returns both 1P
-- values from vanilla unchanged.
local _SP_CROSSBOW_PRESENTATION_ITEMS = {
    es_longbow = true,
    we_longbow = true,
    we_deus_01 = true,
}
local function _is_sp_crossbow_presentation_item(item_name)
    return _SP_CROSSBOW_PRESENTATION_ITEMS[item_name] == true
end

local function _force_load_sp_crossbow_3p_units()
    if not (Managers and Managers.package) then return end
    for ref_name, path in pairs({
        wt_sp_crossbow_3p     = _SP_CROSSBOW_3P_UNIT,
        wt_sp_crossbow_bolt_3p = _SP_CROSSBOW_BOLT_3P_UNIT,
    }) do
        local ok, err = pcall(function()
            Managers.package:load(path, ref_name, nil, true, true)
        end)
        if ok then
            mod:info("[wt sp-longbow-crossbow] force-loaded %s: %s", ref_name, path)
        else
            mod:warning("[wt sp-longbow-crossbow] failed to force-load %s: %s", ref_name, tostring(err))
        end
    end
end

_force_load_sp_crossbow_3p_units()

-- ============================================================
-- Cross-character FIRE / EXPLOSION particle fix (v0.12.159-dev)
-- ============================================================
-- CRASH (nicho, 2026-06-25, host): a non-native career (Foot Knight `es_knight`)
-- equipping a Bardin/Sienna fire weapon via wt's unlock map and firing it CTDs
-- the host —
--   <<Lua Error>> WorldApi create_particles failed,
--   Particle effect '#ID[35874310a062bfd8]' not loaded
--   (Assertion c_api_world.cpp:384; DamageUtils.create_explosion ->
--    World.create_particles, off the charged drakefire shot's timed AOE).
--
-- ROOT CAUSE: the drakefire/fireball AOE explosion particle
-- `fx/wpnfx_drake_pistols_projectile_impact` (murmur64A = 35874310a062bfd8) is
-- referenced by STRING in ExplosionTemplates, so it is NOT a build-time
-- dependency of the weapon's own unit bundle (the unit loads on equip, the
-- particle does not). It is instead bundled into the CAREER packages of the
-- careers that natively wield these weapons. A cross-character wielder loads the
-- weapon unit but never that career package, so the resource manager can't get
-- the particle at detonation -> C-level assert (bypasses pcall, same family as
-- the brace/crossbow unit force-loads above and the LA force-load crash class,
-- reference_vt2_la_package_force_load_crash).
--
-- FIX: force-load ONE vanilla, non-DLC Sienna career package at mod init. Verified
-- via vt2_bundle_unpacker that `resource_packages/careers/bw_unchained`
-- (= bundle 2f35c9d9dcee1fab) contains EVERY common cross-character fire
-- particle at once:
--   35874310a062bfd8  fx/wpnfx_drake_pistols_projectile_impact  Drake Pistols AOE + Fireball staff basic
--   db4255f05669df28  fx/wpnfx_fireball_charged_impact_remap    Fireball staff charged
--   9ce03ee5712aa07d  fx/wpnfx_fireball_charged_impact          charged-fire variants
--   fe6eaa73e7448531  fx/wpnfx_flamethrower_01                  Drakegun + Flamethrower staff
-- so one ~10 MB load makes them all resident for every wt user. Vanilla package
-- = Steam-verified complete bundle, so force-loading a non-resident vanilla
-- package is safe (no missing-member C-fatal). This is resource-pool memory,
-- NOT the Lua heap (reference_vt2_lua_heap_1gib_crash is heap-side). Async load
-- fires at mod init, long before any equip/fire path (mirrors the unit loads
-- above). (Follow-up: the Sienna flaming-flail particle 0df4b41f lives in the
-- `anvil` DLC package — DLC-gated, lower-traffic port — left for a later batch.)
local _FIRE_FX_CAREER_PACKAGE = "resource_packages/careers/bw_unchained"

local function _force_load_fire_explosion_packages()
    if not (Managers and Managers.package) then return end
    local ok, err = pcall(function()
        Managers.package:load(_FIRE_FX_CAREER_PACKAGE, "wt_fire_fx_particles", nil, true, true)
    end)
    if ok then
        mod:info("[wt fire-fx] force-loaded fire/explosion particle package: %s", _FIRE_FX_CAREER_PACKAGE)
    else
        mod:warning("[wt fire-fx] failed to force-load %s: %s", _FIRE_FX_CAREER_PACKAGE, tostring(err))
    end
end

_force_load_fire_explosion_packages()

-- The Necromancy / Soulstealer Staff (bw_necromancy_staff, template staff_death) is
-- a NECROMANCER-exclusive weapon; its particles — e.g. the soul_rip
-- `fx/wpnfx_necromancer_skullstaff_anticipation` (murmur64A 418bb6de77c32555) — live
-- in the `bw_necromancer` career package, NOT in bw_unchained. So the bw_unchained
-- load above does NOT cover it: a cross-character wielder firing soul_rip hit the same
-- create_particles C-fatal as the drakefire crash (GH #128) on this particle (nicho,
-- 2026-06-28, console-...-03.02.04 log; verified the particle is in bw_necromancer
-- bundle 82250c065e5b8ade).
--
-- bw_necromancer is a DLC career (`shovel`). Force-loading a non-resident DLC package
-- whose bundle a non-owner doesn't even have installed would itself async-crash
-- (reference_vt2_la_package_force_load_crash), so this is GATED on DLC ownership. Only
-- owners can wield the Necromancy Staff anyway, so non-owners need nothing here.
--
-- TIMING (v0.12.178-dev, 2026-06-29 nicho crash): the old code assumed
-- `Managers.unlock:is_dlc_unlocked` was resolved at mod-init "because the package
-- load above proves Managers.package is ready". That was WRONG — the unlock-manager
-- ownership truth can still be UNRESOLVED at mod-init even for an owner, so the gate
-- returned early (no log) and bw_necromancer never loaded → soul_rip create_particles
-- C-fatal in-mission (`fx/wpnfx_necromancer_skullstaff_anticipation` not loaded). Fix:
--   1. Ownership proxy — the engine force-loads `dlcs/shovel` ONLY for owners and it's
--      resident BEFORE wt mod-init (nicho's log: dlcs/shovel force_loaded at boot,
--      wt init ~9s later), so package residence is a timing-safe owner signal that
--      backstops the not-yet-resolved is_dlc_unlocked.
--   2. Idempotent + re-attempted from on_game_state_changed (keep/mission entry, by
--      which point ownership is always resolved) so a slow-resolving owner still gets
--      the package loaded before they can wield the staff.
local _FIRE_FX_NECRO_PACKAGE = "resource_packages/careers/bw_necromancer"
local _FIRE_FX_NECRO_DLC = "shovel"
local _FIRE_FX_NECRO_DLC_BOOT_PACKAGE = "resource_packages/dlcs/shovel"
local _necro_fx_loaded = false

-- Owner iff the unlock-manager says so OR the boot DLC package is resident (the
-- latter resolves earlier and backstops an unresolved is_dlc_unlocked at mod-init).
local function _necro_dlc_owned()
    local um = Managers and Managers.unlock
    if um and um.dlc_exists and um.is_dlc_unlocked
       and um:dlc_exists(_FIRE_FX_NECRO_DLC) and um:is_dlc_unlocked(_FIRE_FX_NECRO_DLC) then
        return true
    end
    if Managers and Managers.package and Managers.package.has_loaded
       and Managers.package:has_loaded(_FIRE_FX_NECRO_DLC_BOOT_PACKAGE) then
        return true
    end
    return false
end

-- Idempotent; safe to call repeatedly (mod-init + every on_game_state_changed). A
-- true non-owner never passes _necro_dlc_owned() so it never loads (correct — they
-- can't wield it); an owner whose ownership wasn't resolved at mod-init loads on the
-- first state transition where it is.
function mod._force_load_necromancer_fx_package()
    if _necro_fx_loaded then return end
    if not (Managers and Managers.package) then return end
    if not _necro_dlc_owned() then return end
    local ok, err = pcall(function()
        Managers.package:load(_FIRE_FX_NECRO_PACKAGE, "wt_fire_fx_necromancer", nil, true, true)
    end)
    if ok then
        _necro_fx_loaded = true
        mod:info("[wt fire-fx] force-loaded Necromancer fx package (shovel DLC owned): %s", _FIRE_FX_NECRO_PACKAGE)
    else
        mod:warning("[wt fire-fx] failed to force-load %s: %s", _FIRE_FX_NECRO_PACKAGE, tostring(err))
    end
end

mod._force_load_necromancer_fx_package()

-- ============================================================
-- Brace → Repeater illusion resolver
-- ============================================================
-- When a brace illusion has a matching cosmetic tier on the repeater
-- (e.g. brace `wh_brace_of_pistols_skin_03_runed_01` "Stylish Infused"
-- ↔ repeater `es_repeating_handgun_skin_XX_runed_01" "Stylish Infused"),
-- the 3P repeater should render the MATCHED illusion's mesh, not the
-- base repeater. Match key is the suffix after `_skin_<digits>`:
--   `_runed_01`  → Stylish Infused (red glow)
--   `_runed_02`  → Bogenhafen (purple glow)
--   `_runed_03`  → Geheimnisnacht (gold glow)
--   `_magic_01`  → Weavebound
--   `_magic_02`  → Versus
--   `_runed_06`  → Chaos Wastes (Lileath)
--   "" (no suffix) → base mesh
-- Numbers differ between weapons (brace has 5 base skins, repeater has
-- 3), but the trailing suffix is consistent across the game's cosmetic
-- pipeline.
--
-- Returns: { unit_name = "<repeater_unit_3p_path>", skin_key = "<matched_repeater_skin_or_nil>" }
-- Cached so repeated lookups (every equip / picker swap) don't re-iterate
-- `WeaponSkins.skins`. Cache is invalidated only by mod reload.

local _BRACE_TO_REPEATER_CACHE = {}

local function _extract_skin_suffix(brace_skin_key)
    -- "wh_brace_of_pistols_skin_03_runed_01" → "_runed_01"
    -- "wh_brace_of_pistols_skin_05"          → "" (no cosmetic-tier suffix)
    -- nil / not-a-brace                       → nil
    if type(brace_skin_key) ~= "string" then return nil end
    if not brace_skin_key:find("^wh_brace_of_pistols_skin_") then return nil end
    -- Everything after `_skin_<digits>`. The digits portion might be
    -- multi-digit; capture trailing suffix.
    local suffix = brace_skin_key:match("^wh_brace_of_pistols_skin_%d+(.*)$")
    return suffix or ""  -- "" means "base mesh, no cosmetic tier"
end

local function _resolve_brace_to_repeater_skin(brace_skin_key)
    -- Returns: matched_repeater_3p_unit_path, matched_repeater_skin_key
    -- Both are nil if no match (caller falls back to base repeater 3P).
    if not brace_skin_key then return nil, nil end
    local cached = _BRACE_TO_REPEATER_CACHE[brace_skin_key]
    if cached ~= nil then  -- including the negative cache (cached = false)
        if cached == false then return nil, nil end
        return cached.unit_name, cached.skin_key
    end

    local suffix = _extract_skin_suffix(brace_skin_key)
    if not suffix then
        _BRACE_TO_REPEATER_CACHE[brace_skin_key] = false
        return nil, nil
    end

    if not WeaponSkins or not WeaponSkins.skins then return nil, nil end

    -- For empty suffix (base brace skin = skin_01/_02/_05/etc without runed/magic),
    -- match repeater's base skin_01 explicitly. Otherwise scan repeater skins for
    -- one whose key matches `es_repeating_handgun_skin_<digits><suffix>`.
    local matched_skin_key, matched_skin
    if suffix == "" then
        matched_skin_key = "es_repeating_handgun_skin_01"
        matched_skin = WeaponSkins.skins[matched_skin_key]
    else
        for skin_key, skin in pairs(WeaponSkins.skins) do
            if type(skin_key) == "string"
                    and skin_key:find("^es_repeating_handgun_skin_%d+" .. suffix:gsub("%-", "%%-") .. "$") then
                matched_skin_key = skin_key
                matched_skin = skin
                break
            end
        end
    end

    if not matched_skin or not matched_skin.right_hand_unit then
        _BRACE_TO_REPEATER_CACHE[brace_skin_key] = false
        return nil, nil
    end

    local unit_name = matched_skin.right_hand_unit .. "_3p"
    _BRACE_TO_REPEATER_CACHE[brace_skin_key] = { unit_name = unit_name, skin_key = matched_skin_key }
    return unit_name, matched_skin_key
end

-- Diagnostic command. `wt brace_to_repeater_skin <brace_skin_key>` prints
-- the resolved match. Use to verify each brace illusion maps to the
-- correct repeater illusion before relying on the resolver in the swap
-- hooks. Examples:
--   wt brace_to_repeater_skin wh_brace_of_pistols_skin_01
--   wt brace_to_repeater_skin wh_brace_of_pistols_skin_03_runed_01
--   wt brace_to_repeater_skin wh_brace_of_pistols_skin_03_runed_02
mod:command("brace_to_repeater_skin", "Resolve a brace illusion to its matching repeater illusion", function(brace_skin_key)
    if not brace_skin_key or brace_skin_key == "" then
        mod:echo("Usage: /brace_to_repeater_skin <wh_brace_of_pistols_skin_*>")
        return
    end
    local suffix = _extract_skin_suffix(brace_skin_key)
    local unit, skin = _resolve_brace_to_repeater_skin(brace_skin_key)
    mod:echo("Brace: %s", brace_skin_key)
    mod:echo("  Suffix: %q", tostring(suffix))
    mod:echo("  Matched repeater skin: %s", tostring(skin or "(none — falls back to base repeater 3P)"))
    mod:echo("  Matched 3P unit: %s", tostring(unit or _BRACE_REPEATER_3P_UNIT .. "  [base, fallback]"))
end)

-- Dump command: walk every brace skin in WeaponSkins.skins and print
-- the resolved match. One-stop sanity check.
mod:command("brace_to_repeater_dump", "Dump every brace→repeater skin mapping", function()
    if not WeaponSkins or not WeaponSkins.skins then
        mod:echo("WeaponSkins.skins not loaded")
        return
    end
    local brace_keys = {}
    for skin_key in pairs(WeaponSkins.skins) do
        if type(skin_key) == "string" and skin_key:find("^wh_brace_of_pistols_skin_") then
            brace_keys[#brace_keys + 1] = skin_key
        end
    end
    table.sort(brace_keys)
    mod:info("=== Brace → Repeater skin mapping (%d brace skins) ===", #brace_keys)
    for _, brace_key in ipairs(brace_keys) do
        local unit, repeater_skin = _resolve_brace_to_repeater_skin(brace_key)
        mod:info("  %-50s → %s", brace_key, tostring(repeater_skin or "(no match, fallback)"))
    end
    mod:echo("Dumped %d brace skin mappings to log", #brace_keys)
end)

local _BRACE_REPEATER_BASE_WIELD_3P = {
    es_mercenary      = "to_repeating_handgun",
    es_huntsman       = "to_repeating_handgun",
    es_knight         = "to_repeating_handgun",
    es_questingknight = "to_repeating_handgun",
}

local _BRACE_REPEATER_ANIM_REMAP_3P = {
    special_action = "attack_shoot_fast",
}

local function _patch_brace_template_for_kruber()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then
        _dbg_alert("[wt:tpl_patch] event=skip template=brace_of_pistols_template_1 reason=missing")
        return
    end
    local tpl = Weapons.brace_of_pistols_template_1
    local n_career_overrides = 0
    local n_action_remaps = 0

    -- Wield event per-career override.
    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_BRACE_REPEATER_BASE_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Per-action anim_event_3p remap for events the repeater SM doesn't
    -- author. Sets a sibling anim_event_3p alongside anim_event so the
    -- 3P body fires the substitute while 1P keeps the original.
    if tpl.actions then
        for _, action_group in pairs(tpl.actions) do
            if type(action_group) == "table" then
                for _, sub_action in pairs(action_group) do
                    if type(sub_action) == "table"
                            and sub_action.anim_event
                            and _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event] then
                        sub_action.anim_event_3p = _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event]
                        n_action_remaps = n_action_remaps + 1
                    end
                end
            end
        end
    end
    -- v0.12.88-dev: per-patcher trace. Boot-time only; always-on. Captures
    -- how many career_overrides + per-action remaps were applied so a
    -- regression (table-emptied / iter-order-broken) is visible at load.
    _dbg("[wt:tpl_patch] event=applied template=brace_of_pistols_template_1 career_overrides=%d action_remaps=%d",
        n_career_overrides, n_action_remaps)
end

_patch_brace_template_for_kruber()

-- ============================================================
-- Saltzpyre Longbow → Crossbow: base template anim patches
-- ============================================================
-- Parallel to _patch_brace_template_for_kruber. The es_longbow's template
-- (longbow_empire_template) gets a wh_*-keyed wield_anim_career_3p so
-- Saltzpyre's 3P body plays the crossbow wield transition instead of
-- "to_es_longbow". Per-action anim_event_3p remaps cover firing events
-- that have different names on the crossbow SM than on the longbow's 1P.
--
-- The longbow's primary fire action uses anim_event = "attack_shoot_fast"
-- (1P bow draws-then-fires). Saltzpyre's 3P crossbow SM does NOT author
-- "attack_shoot_fast" (the crossbow has no rapid-fire variant) but DOES
-- author "attack_shoot" — so we remap. shoot_charged actions already use
-- "attack_shoot" so they fall through unchanged.
-- wh_priest is EXCLUDED per the user rule (feedback_vt2_no_bows_on_warrior_priest):
-- his 3P body authors neither `to_longbow` nor `to_crossbow`. Pre-v0.12.47-dev
-- the table included him with a `to_crossbow` entry that silently no-op'd on
-- his skeleton (he held his prior-weapon idle stance while wielding the
-- longbow). Removed in v0.12.47-dev to align with the new rule.
local _SP_LONGBOW_CROSSBOW_WIELD_3P = {
    wh_captain      = "to_crossbow",
    wh_bountyhunter = "to_crossbow",
    wh_zealot       = "to_crossbow",
}

local _SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast       = "attack_shoot",
    attack_shoot_fast_last  = "attack_shoot_last",
    draw_bow                = "to_zoom",       -- charged-shot aim hold; crossbow uses to_zoom
}

local function _patch_longbow_empire_template_for_saltzpyre()
    if not Weapons or not Weapons.longbow_empire_template then
        _dbg_alert("[wt:tpl_patch] event=skip template=longbow_empire_template reason=missing")
        return
    end
    local tpl = Weapons.longbow_empire_template
    local n_career_overrides = 0

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_SP_LONGBOW_CROSSBOW_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Per-action anim remap: register a RUNTIME career-scoped remap
    -- (_3p_template_remaps.longbow_empire_template.wh_) instead of MUTATING the
    -- SHARED template globally. The old global mutation set draw_bow → to_zoom on
    -- the template for EVERY career, which broke Kruber's NATIVE longbow charge
    -- (draw_bow fired to_zoom on es_ too) — #210. The runtime path is wh_-gated, so
    -- es_ (Kruber native) keeps its own draw_bow / attack_shoot_fast. Keyed by the
    -- actions' fired 3P event (= their anim_event; these actions carry no native
    -- anim_event_3p, so anim_event IS what fires).
    -- #316 live evidence disproved the old cross-career assumption: Mercenary reached
    -- ActionAim zoom, but `draw_bow -> to_zoom` suppressed the visible bow draw. All
    -- Kruber careers render on the Empire Soldier skeleton and consume its native
    -- `draw_bow` vocabulary. Keep explicit false entries for Merc/FK/GK so local 3P
    -- and remote husks both pass the real event through. Huntsman remains the native
    -- control. Saltzpyre's model substitution still needs the crossbow remap below.
    _3p_template_remaps.longbow_empire_template = _3p_template_remaps.longbow_empire_template or {}
    _3p_template_remaps.longbow_empire_template.es_mercenary      = false
    _3p_template_remaps.longbow_empire_template.es_knight         = false
    _3p_template_remaps.longbow_empire_template.es_questingknight = false
    _3p_template_remaps.longbow_empire_template.wh_               = _SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:tpl_patch] event=applied template=longbow_empire_template career_overrides=%d (wield) + native draw passthrough for es_ Merc/FK/GK + runtime crossbow remap for wh_; native es_huntsman untouched",
        n_career_overrides)
end

_patch_longbow_empire_template_for_saltzpyre()
-- WT_DEV_OVERLAY_BEGIN:longbow-live-probe-hooks
-- #316 diagnostic: camera zoom is owner-only and source-driven by ActionAim,
-- while visible body playback is a separate 3P presentation concern. Observe
-- three non-Huntsman Kruber aim attempts after the native draw fix. The result
-- reports camera state and keeps visible playback explicitly unverified; each
-- attempt emits at most two raw-console rows (start + result/early finish).
mod:hook_safe("ActionAim", "client_owner_start_action", function(self, new_action, t)
    local item_master_list = rawget(_G, "ItemMasterList")
    local item_data = item_master_list and rawget(item_master_list, self and self.item_name)
    local template_name = item_data and item_data.template
    local career_name = self and self.owner_unit and _unit_career_name(self.owner_unit)
    local scoped = _3p_template_remaps.longbow_empire_template or {}
    local remap = career_name and scoped[career_name]
    local record = _wt316_zoom_probe:arm(template_name, career_name,
        self and self.item_name, t, self and self.aim_zoom_time or t, {
            action_kind = new_action and new_action.kind,
            anim_event = new_action and new_action.anim_event,
            default_zoom = new_action and new_action.default_zoom,
            zoom_condition = new_action and type(new_action.zoom_condition_function) or "nil",
            remap = remap == false and "native_draw_bow"
                or (type(remap) == "table" and remap.draw_bow or nil),
        })
    if not record then return end
    _wt316_zoom_records[self] = record
    pcall(printf, "[wt:316] aim-start attempt=%d/%d career=%s item=%s template=%s kind=%s anim=%s aim_delay=%.3f default_zoom=%s condition=%s remap=%s",
        record.attempt, _wt316_zoom_probe.max_attempts, tostring(career_name),
        tostring(self.item_name), tostring(template_name), tostring(record.fields.action_kind),
        tostring(record.fields.anim_event), record.due_at - record.started_at,
        tostring(record.fields.default_zoom or "zoom_in(default)"),
        tostring(record.fields.zoom_condition), tostring(record.fields.remap))
end)

mod:hook_safe("ActionAim", "client_owner_post_update", function(self, dt, t)
    local record = _wt316_zoom_records[self]
    if not record then return end
    local status = self.owner_unit and ScriptUnit.has_extension(self.owner_unit, "status_system")
    local zooming = status and status:is_zooming() or false
    local result = _wt316_zoom_probe:observe(record, t, zooming, status and status.zoom_mode)
    if not result then return end
    _wt316_zoom_records[self] = nil
    pcall(printf, "[wt:316] aim-result attempt=%d/%d career=%s outcome=%s elapsed=%.3f zooming=%s zoom_mode=%s visible_draw=%s",
        record.attempt, _wt316_zoom_probe.max_attempts, tostring(record.career),
        tostring(result.outcome), result.elapsed, tostring(result.zooming),
        tostring(result.zoom_mode), tostring(result.visible_draw))
end)

mod:hook_safe("ActionAim", "finish", function(self, reason)
    local record = _wt316_zoom_records[self]
    if not record then return end
    local result = _wt316_zoom_probe:finish(record, nil, reason)
    _wt316_zoom_records[self] = nil
    if not result then return end
    pcall(printf, "[wt:316] aim-result attempt=%d/%d career=%s outcome=%s elapsed=%.3f reason=%s",
        record.attempt, _wt316_zoom_probe.max_attempts, tostring(record.career),
        tostring(result.outcome), result.elapsed, tostring(result.reason))
end)
-- WT_DEV_OVERLAY_END:longbow-live-probe-hooks

-- ============================================================
-- Saltzpyre Elf Longbow → Crossbow: base template anim patches
-- ============================================================
-- Parallel to _patch_longbow_empire_template_for_saltzpyre above. The elf
-- longbow's `Weapons.longbow_template_1` shares the empire longbow's
-- `anim_event` vocabulary (action_one.default = "attack_shoot_fast",
-- action_one.shoot_charged = "attack_shoot", action_two.default = "draw_bow"),
-- so the remap table is identical — the crossbow SM has no `attack_shoot_fast`
-- variant, and `draw_bow` aim-hold maps to `to_zoom`. wh_priest is EXCLUDED
-- per the user rule (feedback_vt2_no_bows_on_warrior_priest): his 3P body
-- authors neither `to_longbow` nor `to_crossbow`.
local _WE_LONGBOW_CROSSBOW_WIELD_3P = {
    wh_captain      = "to_crossbow",
    wh_bountyhunter = "to_crossbow",
    wh_zealot       = "to_crossbow",
}

local _WE_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast       = "attack_shoot",
    attack_shoot_fast_last  = "attack_shoot_last",
    draw_bow                = "to_zoom",
}

local function _patch_longbow_template_1_for_saltzpyre()
    if not Weapons or not Weapons.longbow_template_1 then
        _dbg_alert("[wt:tpl_patch] event=skip template=longbow_template_1 reason=missing")
        return
    end
    local tpl = Weapons.longbow_template_1
    local n_career_overrides = 0

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_WE_LONGBOW_CROSSBOW_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Same #210 fix as the empire longbow above: runtime wh_-gated remap instead of
    -- a global template mutation, so Kerillian's NATIVE elf longbow (we_) keeps its
    -- own draw_bow / attack_shoot_fast charge+fire anims. wh_-only remaps to crossbow.
    _3p_template_remaps.longbow_template_1 = _3p_template_remaps.longbow_template_1 or {}
    _3p_template_remaps.longbow_template_1.we_ = false  -- native Kerillian: never remap
    _3p_template_remaps.longbow_template_1.wh_ = _WE_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:tpl_patch] event=applied template=longbow_template_1 career_overrides=%d (wield) + runtime wh_ remap (#210: native we_ untouched)",
        n_career_overrides)
end

_patch_longbow_template_1_for_saltzpyre()

-- ============================================================
-- #580 Saltzpyre Moonfire Bow -> Crossbow: 3P event vocabulary
-- ============================================================
-- Vanilla `we_deus_01_template_1` uses the same source events as Kerillian's
-- longbow: rapid fire `attack_shoot_fast`, charged fire `attack_shoot`, and
-- aim `draw_bow`. Saltzpyre's native crossbow 3P state machine instead authors
-- `attack_shoot` and `to_zoom`. Register the substitutions in wt's runtime,
-- career-scoped funnel; never mutate the shared action tables, `wield_anim`,
-- first-person units, energy behavior, projectile data, or state machine.
-- `wt_wield_patches.lua` owns the matching wh_* `to_crossbow` wield entries.
local _WE_MOONFIRE_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast      = "attack_shoot",
    attack_shoot_fast_last = "attack_shoot_last",
    draw_bow               = "to_zoom",
}

local function _patch_moonfire_template_1_for_saltzpyre()
    if not Weapons or not Weapons.we_deus_01_template_1 then
        _dbg_alert("[wt:580] event=skip template=we_deus_01_template_1 reason=missing")
        return
    end

    _3p_template_remaps.we_deus_01_template_1 =
        _3p_template_remaps.we_deus_01_template_1 or {}
    _3p_template_remaps.we_deus_01_template_1.we_ = false
    _3p_template_remaps.we_deus_01_template_1.wh_ =
        _WE_MOONFIRE_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:580] event=applied template=we_deus_01_template_1 target=crossbow_template_1 scope=wh_ native_we_untouched=true remaps=3")
end

_patch_moonfire_template_1_for_saltzpyre()

-- ============================================================
-- Kruber Repeating Pistol → Repeating Handgun: base template anim patches
-- ============================================================
-- Parallel to _patch_brace_template_for_kruber. `wh_repeating_pistols`
-- (Saltzpyre's revolving repeater pistol) on Kruber, rendered as the empire
-- repeating handgun 3P mesh. Source template `Weapons.repeating_pistol_template_1`
-- fires `attack_shoot` (action_one.default + action_one.bullet_spray) and
-- `lock_target` (action_two.default). All three events EXIST in the target's
-- 3P SM (`repeating_handgun_template_1` authors `attack_shoot`,
-- `attack_shoot_last`, `attack_shoot_fast`, `attack_shoot_fast_last`,
-- `lock_target`, `lock_target_loop`, `reload`), so the per-action remap table
-- is EMPTY — only the `wield_anim_career_3p` override is needed. This is the
-- "vocabulary overlaps cleanly" case noted in CROSS_CHARACTER_PORT_RECIPE.md
-- Section 2 step (e) ("Skip (e) when every source action's anim_event already
-- exists in the target SM vocabulary unchanged.").
local _WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P = {
    es_mercenary      = "to_repeating_handgun",
    es_huntsman       = "to_repeating_handgun",
    es_knight         = "to_repeating_handgun",
    es_questingknight = "to_repeating_handgun",
}

local function _patch_repeating_pistol_template_1_for_kruber()
    if not Weapons or not Weapons.repeating_pistol_template_1 then
        _dbg_alert("[wt:tpl_patch] event=skip template=repeating_pistol_template_1 reason=missing")
        return
    end
    local tpl = Weapons.repeating_pistol_template_1
    local n_career_overrides = 0

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Intentionally no anim_event_3p remap loop: source vocabulary is a strict
    -- subset of target vocabulary, so falling through unchanged is correct.
    _dbg("[wt:tpl_patch] event=applied template=repeating_pistol_template_1 career_overrides=%d action_remaps=0_intentional",
        n_career_overrides)
end

_patch_repeating_pistol_template_1_for_kruber()

-- ============================================================
-- Cross-character wield-stance template patches (inventory previewer)
-- ============================================================
-- Each weapon's template has a universal `wield_anim` field that the engine
-- fires on both 1P and 3P units. 1P animations are universal across the six
-- characters and never need overriding. The 3P side does: when a cross-
-- character wielder has no native authoring of the source weapon's `to_*`
-- event, the previewer fires an event the body doesn't author and the body
-- holds the previous weapon's idle stance (no T-pose — see
-- feedback_vt2_no_tpose_default_stance).
--
-- In-mission, the `_career_anim_redirect` table (line ~225) intercepts the
-- wield event via `Unit.animation_event` and remaps it to the target body's
-- own polearm/billhook/spear `to_*` event. But the keep inventory previewer
-- (MenuWorldPreviewer) reads `wield_anim_career_3p` directly off the
-- template at character-model setup time — it does NOT go through the
-- `Unit.animation_event` redirect path our hook covers. Result: a polearm-
-- class weapon equipped cross-character renders correctly in-mission but
-- holds the wrong stance in the keep inventory.
--
-- Fix: bake the same career→event mapping the `_career_anim_redirect`
-- entry encodes into each template's `wield_anim_career_3p` field. Both
-- paths now resolve the correct stance natively. We keep the
-- `_career_anim_redirect` entries too — they cover wield events re-fired
-- from other code paths (push-attacks, etc.).
--
-- Only careers in the unlock map are listed for each template — entries
-- for careers that cannot equip a weapon would be dead. wh_priest never
-- appears here: his row in the unlock map has no polearm/spear/billhook
-- and no bows/crossbows per `feedback_vt2_no_bows_on_warrior_priest`.
--
-- The four `_patch_*` functions above (brace, longbow×2, repeating_pistol)
-- are NOT consolidated into this table because they also do per-action
-- `anim_event_3p` remap loops — a different concern that needs the action
-- table walk. This table only handles the wield-event patch, which is the
-- whole story for polearm-class templates because the in-mission
-- `_3p_remap_triggers` (line ~421) already covers their per-action remaps.
-- v0.12.139-dev: the wield-patch DATA moved to a shared module so the dev anim
-- picker (which runs from _data.lua / _localization.lua, BEFORE this script's
-- top-level patcher calls — see reference_vmf_mod_file_load_order) can resolve
-- each Kruber port's TARGET template from its chosen wield set at catalog-build
-- time. The picker pre-applies the same tables to Weapons.* (idempotent with the
-- apply below). All values are `to_*` events written to wield_anim_career_3p — a
-- 3P field; 1P (anim_event/wield_anim) is never touched. The verbatim tables
-- (with their per-block provenance comments) now live in wt_wield_patches.lua.
local _WIELD_PATCHES_MODULE = mod:dofile("scripts/mods/weapon_tweaker_dev/wt_wield_patches")
local _WIELD_ANIM_CAREER_3P_PATCHES      = _WIELD_PATCHES_MODULE.patches
local _WIELD_ANIM_CAREER_3P_PATCHES_BULK = _WIELD_PATCHES_MODULE.bulk

local function _apply_wield_anim_career_3p_patches(patches)
    if not Weapons then return end
    for template_name, career_overrides in pairs(patches) do
        local tpl = Weapons[template_name]
        if tpl then
            tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
            local applied = 0
            for career, event in pairs(career_overrides) do
                tpl.wield_anim_career_3p[career] = event
                applied = applied + 1
            end
            -- v0.12.102-dev: mirror the per-template `[wt:tpl_patch] event=applied`
            -- instrumentation already present on the brace / longbow / repeating-pistol
            -- patchers (lines ~2088 / 2155 / 2213 / 2257). Closes the diagnostic blind
            -- spot where polearm patches applied silently and we couldn't confirm from
            -- log whether wield_anim_career_3p[<career>] actually installed.
            _dbg("[wt:tpl_patch] event=applied template=%s career_overrides=%d", template_name, applied)
        else
            mod:warning("[wt wield-3p-patch] Weapons.%s missing; skipping wield_anim_career_3p patch", template_name)
        end
    end
end

_apply_wield_anim_career_3p_patches(_WIELD_ANIM_CAREER_3P_PATCHES)
_apply_wield_anim_career_3p_patches(_WIELD_ANIM_CAREER_3P_PATCHES_BULK)

-- ============================================================
-- v0.12.139-dev: not-loaded / no-ammo WIELD fallbacks for cross-character
-- repeating crossbows (3P-ONLY crash fix — Kerillian Repeater Crossbow on Kruber)
-- ============================================================
-- Crash class (network game only, bypasses pcall — engine RPC packer fatal):
--   `repeating_crossbow_elf_template` (we_crossbow_repeater) sets
--     wield_anim_not_loaded = "to_repeating_crossbow_elf"          (repeating_crossbows_elf.lua:259)
--     wield_anim_no_ammo    = "to_repeating_crossbow_elf_noammo"   (repeating_crossbows_elf.lua:258)
--   Neither `_elf` event is registered in NetworkLookup.anims
--   (anims_lookup_table.lua has to_repeating_crossbow / _noammo and
--    to_repeating_handgun / _noammo, but NO `_elf` entries). When the crossbow
--   is wielded EMPTY/unloaded, simple_inventory_extension.lua:2050-2063 routes
--   the not-loaded event into ammo_extension:start_reload(...), which reaches
--   generic_ammo_user_extension.lua:311-330:
--       event_id = NetworkLookup.anims[reload_event]  -- => nil
--       network_transmit:send_rpc_clients("rpc_anim_event", event_id, go_id)
--   Packing nil into the rpc_anim_event lookup-index field is a C-level fatal.
--   wt's _WIELD_ANIM_CAREER_3P_PATCHES_BULK only patches `wield_anim_career_3p`
--   (the LOADED stance, consumed via the safe non-networked Unit.animation_event
--   at simple_inventory_extension.lua:2013), NOT the not-loaded/no-ammo wields,
--   so the raw `_elf` names survive on the empty-wield reload-send path.
--
-- Fix (3P-ONLY): per-career not-loaded/no-ammo wield overrides pointing at the
-- RECEIVER-native, NetworkLookup-registered repeating wields that each receiver's
-- own 3P body authors. The fallback differs by receiver group:
--   * Kruber (empire_soldier body) -> to_repeating_handgun / _noammo
--       to_repeating_handgun         (anims_lookup_table.lua:670 — handgun has no
--                                     distinct not-loaded wield; its loaded wield is
--                                     the correct fallback)
--       to_repeating_handgun_noammo  (anims_lookup_table.lua:671 — handgun's own
--                                     wield_anim_no_ammo, repeating_handguns.lua:312)
--   * Saltzpyre (witch_hunter body)  -> to_repeating_crossbow / _noammo  (#536)
--       to_repeating_crossbow        (anims_lookup_table.lua:645 — Saltzpyre's own
--                                     Volley Crossbow wield_anim_not_loaded,
--                                     repeating_crossbows.lua:247)
--       to_repeating_crossbow_noammo (anims_lookup_table.lua:646 — same template's
--                                     wield_anim_no_ammo, repeating_crossbows.lua:246)
-- These are 3P wield-FALLBACK fields only — never anim_event/wield_anim (1P). They
-- are the SAME receiver-native events the in-mission _career_anim_redirect funnel
-- produces for the LOADED wield, so the empty-wield send now matches the loaded one.
--
-- #536: the wh (Saltzpyre) careers ALSO wield we_crossbow_repeater as a cross-
-- character port (wt_unlock_data.lua:142-144 list it for wh_captain / wh_bountyhunter
-- / wh_zealot; the loaded 3P wield is baked in wt_wield_patches.lua:199), but were
-- omitted from this NOT-LOADED/NO-AMMO table when it was added (v0.12.139, Kruber-
-- only). So an empty-clip wield on a wh career kept the elf template's raw base
-- wield_anim_not_loaded = "to_repeating_crossbow_elf" (UNregistered) and hit the same
-- packer fatal. wh_priest is DLC (bless) but is NOT in scope: it never receives this
-- weapon (wt_unlock_data.lua:145 omits it; the /wt_regression_test `wh_priest_no_bows`
-- check asserts wh_priest gets no bows/crossbows), so no DLC gate is required here —
-- these are pure data writes that stay inert for any career that can't wield the item.
-- NOTE: the DISTINCT native Saltzpyre Volley Crossbow (wh_crossbow_repeater,
-- repeating_crossbow_template_1) already uses to_repeating_crossbow / _noammo natively
-- and never crashed — this patch is for the ELF template (we_crossbow_repeater) ported
-- ONTO wh careers, a different weapon. Do NOT instead register the `_elf` names into
-- _anim_redirect (lines ~484-485): those redirect ONTO the same unregistered `_elf`
-- events and carry this identical latent crash for any non-elf wielder; they're only
-- safe today because they ride the direct (non-networked) Unit.animation_event path
-- behind _safe_has_anim.
local _KRUBER_REPEATER_CAREERS = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
}
local _WH_REPEATER_CAREERS = {
    "wh_captain", "wh_bountyhunter", "wh_zealot",
}
-- Each template maps to a LIST of receiver groups so distinct receivers can point at
-- their own registered fallback under a single template key (Lua tables can't hold two
-- entries for the same template name). This extends the v0.12.139 single-group form.
local _NOT_LOADED_NO_AMMO_CAREER_PATCHES = {
    -- we_crossbow_repeater (Kerillian Repeater Crossbow) ported cross-character.
    repeating_crossbow_elf_template = {
        { not_loaded = "to_repeating_handgun",  no_ammo = "to_repeating_handgun_noammo",  careers = _KRUBER_REPEATER_CAREERS },
        { not_loaded = "to_repeating_crossbow", no_ammo = "to_repeating_crossbow_noammo", careers = _WH_REPEATER_CAREERS },
    },
}

local function _apply_not_loaded_no_ammo_career_patches(patches)
    if not Weapons then return end
    for template_name, groups in pairs(patches) do
        local tpl = Weapons[template_name]
        if tpl then
            tpl.wield_anim_not_loaded_career = tpl.wield_anim_not_loaded_career or {}
            tpl.wield_anim_no_ammo_career   = tpl.wield_anim_no_ammo_career   or {}
            local n = 0
            for _, spec in ipairs(groups) do
                for _, career in ipairs(spec.careers) do
                    if spec.not_loaded then tpl.wield_anim_not_loaded_career[career] = spec.not_loaded end
                    if spec.no_ammo    then tpl.wield_anim_no_ammo_career[career]    = spec.no_ammo end
                    n = n + 1
                end
            end
            _dbg("[wt:tpl_patch] event=applied template=%s not_loaded/no_ammo careers=%d", template_name, n)
        else
            mod:warning("[wt not-loaded/no-ammo patch] Weapons.%s missing; skipping", template_name)
        end
    end
end

_apply_not_loaded_no_ammo_career_patches(_NOT_LOADED_NO_AMMO_CAREER_PATCHES)

-- ============================================================
-- Deepwood Staff (staff_life) first-person finger-node crash guard (v0.12.200-dev)
-- ============================================================
-- Crash class (#236 follow-up — Script Error "ep_r_index", Kruber Mercenary):
--   staff_life (Kerillian's Sister-of-the-Thorn Deepwood Staff) is unique among
--   staves: on wield/targeting its `synced_states.<state>.enter` spawns a
--   first-person vine finger-trail by resolving the RIGHT-HAND finger nodes
--   ep_r_index/middle/ring/pinky/thumb on the wielder's 1P MESH unit
--   (staff_life.lua init_state_data -> Unit.node(mesh_unit, "ep_r_index")).
--   Those `ep_r_*` nodes exist ONLY on the elf first-person rig. On any non-elf
--   1P rig (Kruber, Saltzpyre — both already offered this staff) Unit.node has
--   no such node and hard-crashes (bypasses the wield hook's xpcall as a
--   C-level fatal). Exposed the instant the staff became equippable on Kruber.
--
-- Guard: wrap each synced_state's `enter` so that when the LOCAL player's 1P
-- mesh lacks `ep_r_index`, we initialise state_data exactly as vanilla would
-- (empty particle_ids so update/leave stay safe, timer set) MINUS the finger
-- particles that can't attach, then skip. The native elf wielder's rig HAS the
-- nodes, so has_node is true and it falls through to the ORIGINAL enter,
-- byte-for-byte unchanged. 1P VFX only — no anim, no model, no 3P. Idempotent
-- via a per-state flag (staff_life & staff_life_vs share one synced_states
-- table through shallow table.clone, so one wrap covers both).
local function _guard_thorn_finger_enter(orig_enter)
    return function (self, owner_unit, weapon_unit, state_data, is_local_player, world)
        if is_local_player and owner_unit and Unit.alive(owner_unit) then
            local fp = ScriptUnit.has_extension(owner_unit, "first_person_system")
            local mesh_unit = fp and fp:get_first_person_mesh_unit()
            if mesh_unit and Unit.has_node and not Unit.has_node(mesh_unit, "ep_r_index") then
                state_data.particle_ids = {}
                state_data.nodes = state_data.nodes or {}
                state_data.timer = 0.7
                return
            end
        end
        return orig_enter(self, owner_unit, weapon_unit, state_data, is_local_player, world)
    end
end

local function _patch_staff_life_thorn_finger_crash_guard()
    if not (Weapons and Unit and Unit.has_node and Unit.alive and ScriptUnit) then
        _dbg_alert("[wt:tpl_patch] event=skip template=staff_life reason=missing_api")
        return
    end
    local n = 0
    for _, name in ipairs({ "staff_life", "staff_life_vs" }) do
        local tpl = Weapons[name]
        local ss  = tpl and tpl.synced_states
        if ss then
            for _, state in ipairs({ "wielding", "targeting" }) do
                local st = ss[state]
                if type(st) == "table" and type(st.enter) == "function" and not st._wt_thorn_guarded then
                    st.enter = _guard_thorn_finger_enter(st.enter)
                    st._wt_thorn_guarded = true
                    n = n + 1
                end
            end
        end
    end
    _dbg("[wt:tpl_patch] event=applied template=staff_life thorn_finger_crash_guard states=%d", n)
end

_patch_staff_life_thorn_finger_crash_guard()

-- ============================================================
-- Cross-character anim-variable crash guard (v0.12.128-dev)
-- ============================================================
-- A ported weapon can fire a charge/pose animation event that carries an
-- animation VARIABLE (anim_event_with_variable_float) whose variable name the
-- RECEIVER's state machine does not author. Vanilla
-- AnimationSystem.anim_event_with_variable_float does
-- `idx = Unit.animation_find_variable(unit, variable_name)` then
-- `Unit.animation_set_variable(unit, idx, value)` with NO nil-guard — when the
-- variable is missing, idx is nil and animation_set_variable hard-crashes
-- ("bad argument #2 ... number expected, got nil", animation_system.lua:163).
-- Reproduced on the Bretonnian Longsword (es_bastard_sword) charged on a
-- non-native career (wh_captain), event attack_swing_charge_right_diagonal_pose.
-- Guard: when the variable isn't found on the unit, SKIP the variable'd event
-- entirely. v0.12.131-dev: we previously fired the BARE event here, but that
-- caught dodges/actions in an animation LOOP — the missing blend variable is
-- exactly what transitions the clip out, so firing the event without it just
-- re-loops the clip. Skipping is safe: the action's gameplay logic proceeds
-- independently; only the cosmetic anim is dropped on the cross-character port
-- whose body lacks that variable. Native weapons always find their variable, so
-- they take the original path unchanged.
--
-- v0.12.132-dev CRITICAL MULTIPLAYER FIX (GUID: A/B-confirmed 2026-06-19): vanilla's
-- 6th param `skip_sync` (animation_system.lua:139) suppresses the rpc_anim_event_variable_float
-- re-broadcast. The RPC RECEIVER replays the networked event with skip_sync=TRUE
-- (animation_system.lua:312) precisely so it does NOT bounce back onto the wire. The
-- previous hook signature OMITTED skip_sync, so when it called func(...) with only 5
-- args, skip_sync collapsed to nil -> vanilla's `if not skip_sync and ...:game()`
-- (animation_system.lua:140) re-sent the RPC -> every husk that RECEIVED a variable'd
-- anim event RE-BROADCAST it -> infinite host<->client RPC feedback loop -> EVERY human
-- player's 3P animation stuck on endless repeat in a 2+ human lobby, on EVERY weapon
-- (native included), only in a network game. Fix: thread skip_sync through the signature
-- and pass it to func unchanged so husk replays stay local (skip_sync=true) as vanilla
-- intends. The find-variable crash guard above is unchanged.
mod:hook("AnimationSystem", "anim_event_with_variable_float", function(func, self, unit, event_name, variable_name, variable_value, skip_sync)
    if unit and Unit.alive(unit) then
        local idx = Unit.animation_find_variable(unit, variable_name)
        if type(idx) ~= "number" then
            return
        end
    end
    return func(self, unit, event_name, variable_name, variable_value, skip_sync)
end)

-- ============================================================
-- Body-specific attachment source-node safety (v0.12.114-dev — per-spawn)
-- ============================================================
-- Crash class: a weapon template's `unit_attachment_node_linking.third_person`
-- table references a body-skeleton-specific source node (e.g.
-- `j_leftweaponcomponent16`, an elf-body-only node) that doesn't exist on
-- non-native receiver bodies. `Unit.node(body_unit, source_node)` bypasses
-- pcall and engine-fatals when the requested node is missing.
--
-- Burn history:
--   * 2026-06-05 v0.12.112-dev: `j_leftweaponcomponent16` crash on
--     `we_shortbow` previewed on Foot Knight (crash GUID e7a69981).
--   * 2026-06-05 v0.12.113-dev: `j_leftweaponcomponent17` minutes later
--     (crash GUID 2061fa18). Generalized to prefix-match.
--   * Both fixes mutated the LIVE template at boot — which also affected
--     elves wielding their own bow. Result: elves' bows went INVISIBLE
--     because the proper grip linking entries were rewritten to `j_hips`
--     and the bow couldn't be held visibly. User reported 2026-06-05.
--
-- v0.12.114-dev fix: per-spawn check via Unit.has_node. Only substitute a
-- source node WHEN THE BODY UNIT ACTUALLY MISSING THE NODE. Elves keep
-- their proper grip; non-elves get `j_hips` fallback. Cost: ~one
-- `Unit.has_node` call per attachment entry per spawn (cheap, sub-ms).
--
-- Implementation: hook `MenuWorldPreviewer._spawn_item_unit` (preview) and
-- `GearUtils.create_equipment` (in-mission) to validate + substitute the
-- attachment_node_linking before the engine's link_units fires.
--
-- TODO (post-play, task #31): replace this safety-net with a proper 3P
-- unit swap so non-elves wielding the elf bows render as Kruber's Empire
-- Longbow (model + animations). Mirrors the brace-on-Kruber pattern.

local function _wt_validate_attachment_sources(body_unit, attachment_node_linking)
    if not attachment_node_linking
        or type(attachment_node_linking.third_person) ~= "table"
        or not body_unit or not Unit.has_node then
        return
    end
    local substituted = 0
    for _, phase in ipairs({ "display", "wielded", "unwielded" }) do
        local arr = attachment_node_linking.third_person[phase]
        if type(arr) == "table" then
            for _, e in ipairs(arr) do
                if type(e) == "table" and type(e.source) == "string" then
                    if not Unit.has_node(body_unit, e.source) then
                        e.source = "j_hips"  -- universal-body fallback
                        substituted = substituted + 1
                    end
                end
            end
        end
    end
    if substituted > 0 then
        _dbg("[wt:body_attach_safe] substituted %d missing-node source(s) at spawn", substituted)
    end
end

-- ============================================================
-- Universal attachment-node guard (engine-fatal crash fix)
-- ============================================================
-- GearUtils.link_units(world, attachment_node_linking, link_table, source, target)
-- runs Unit.node(source, link.source) / Unit.node(target, link.target) per entry
-- (gear_utils.lua:293-308). Unit.node is ENGINE-FATAL on a missing node (it bypasses
-- pcall). Cross-character weapons + sub-attachments can reference nodes the spawned
-- source/target units don't have on a non-native body -> hard crash. Repro: GUID
-- 459bd95e — equipping Skullsplitter + a tome on Kruber Mercenary (hero-view preview):
-- the tome's j_page_nr* nodes link to j_rightweaponcomponent11-14 that Kruber's body
-- lacks. The per-spawn previewer validation (_wt_validate_attachment_sources) only
-- covers the weapon's own .third_person linking; a sub-attachment carries its OWN flat
-- linking table that never passes through that hook. This is the UNIVERSAL choke point:
-- GearUtils.link calls GearUtils.link_units via the table (gear_utils.lua:290), so a
-- table hook here intercepts EVERY spawn path (preview AND in-mission). Missing
-- `a_unwielded_*` BODY sources get a receiver-local `j_hips` fallback so a holstered
-- cross-character weapon remains visible; all other missing links are dropped. Valid
-- links are untouched, so native wielders keep their authored mount (cf. the
-- v0.12.112/.113 global-mutation bug that broke elf bows -- this never mutates live data).
-- WT_LINK_UNITS_NODE_GUARD_MARKER

-- Pure, engine-free sanitizer (unit-testable). A missing `a_unwielded_*` source is
-- copied with `j_hips` only when that receiver body actually has `j_hips`; other
-- missing source/target links are dropped. Returns (linking, dropped, substituted):
-- the ORIGINAL table when unchanged (zero-copy fast path), else a contiguous copy.
-- On `mod` so the end-of-file regression tests can reach it without tripping the
-- 200-locals cap.
mod._wt_link_filter = function(linking, src_has, tgt_has)
    local safe, dropped, substituted = nil, 0, 0
    local n = #linking
    for i = 1, n do
        local e = linking[i]
        local source = e.source
        local source_ok = type(source) ~= "string" or src_has(source)
        local target_ok = type(e.target) ~= "string" or tgt_has(e.target)
        local hip_fallback = not source_ok
            and type(source) == "string"
            and source:sub(1, 12) == "a_unwielded_"
            and src_has("j_hips")
        if target_ok and (source_ok or hip_fallback) then
            if hip_fallback then
                if not safe then
                    safe = {}
                    for j = 1, i - 1 do safe[j] = linking[j] end
                end
                local copy = {}
                for key, value in pairs(e) do copy[key] = value end
                copy.source = "j_hips"
                safe[#safe + 1] = copy
                substituted = substituted + 1
            elseif safe then
                safe[#safe + 1] = e
            end
        else
            if not safe then
                safe = {}
                for j = 1, i - 1 do safe[j] = linking[j] end
            end
            dropped = dropped + 1
        end
    end
    return (safe or linking), dropped, substituted
end

if GearUtils and GearUtils.link_units and Unit and Unit.has_node then
    mod:hook(GearUtils, "link_units", function(func, world, attachment_node_linking, link_table, source, target)
        if type(attachment_node_linking) == "table" and source and target then
            local filtered, dropped, substituted = mod._wt_link_filter(
                attachment_node_linking,
                function(name) return Unit.has_node(source, name) end,
                function(name) return Unit.has_node(target, name) end)
            if dropped > 0 or substituted > 0 then
                _dbg("[wt:link_guard] sanitized attachment links: dropped=%d hip_fallback=%d", dropped, substituted)
                return func(world, filtered, link_table, source, target)
            end
        end
        return func(world, attachment_node_linking, link_table, source, target)
    end)
end

-- ============================================================
-- Toggleable weapon override bakes (issue 2 module decomposition)
-- ============================================================
-- The Authentic Brace of Pistols rework, the issue 348 Kruber 1h sword
-- push-attack revert, and the Warrior Priest punch buff moved to
-- _wt_weapon_overrides.lua. VERBATIM function-bag move, zero behavior change.
-- All three mutate a vanilla Weapons.* template in place at load behind their
-- own VMF checkbox, and the two damage reworks register their cloned profile
-- UNCONDITIONALLY so peer NetworkLookup indices stay aligned. The module must
-- stay immediately before the _wt431_damage_profile_parity dofile below, which
-- needs all three registration sites to have run. Adding a new toggleable
-- template rework means editing _wt_weapon_overrides.lua, never this file.
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_weapon_overrides")
-- ============================================================
-- Issue 431: peer-parity gate + wire floor for the custom damage profiles
-- ============================================================
-- Loaded AFTER all three registration sites (authentic brace above, priest
-- punch above, _wt_brett_sword_shield_buff at the top of this file) so the
-- fallback map is fully populated, and AFTER weapon_tweaker_backend.lua's
-- mod.update definition (line ~81 dofile) -- the beacon's install() WRAPS
-- mod.update and must not capture nil (crt issue-425 ordering rule). The
-- module installs the beacon, registers the gated feature that re-runs the
-- three apply functions on every parity flip, and hooks
-- WeaponSystem.send_rpc_attack_hit with the unconditional sender-side floor.
mod:dofile("scripts/mods/weapon_tweaker_dev/_wt431_damage_profile_parity")
-- NOTE: the beacon starts "disabled" (fail-safe), so at this instant all three
-- toggles sit on their vanilla profiles; the first beacon tick (sub-second, in
-- solo) flips to enabled and its callbacks re-run the three apply functions.

-- ============================================================
-- Moonfire Bow pre-nerf AOE restoration
-- ============================================================
-- One toggle in weapon_overrides:
--   moonfire_aoe_revert  — pre-nerf AOE detonation + puffs (damage host-side)
-- The cosmetic-only puff (moonfire_cosmetic_puff) moved to cosmetics_tweaker
-- (Weapon & Item Appearance, cos_moonfire_cosmetic_puff) on 2026-06-29.
--
-- Implementation hooks the four impact paths on PlayerProjectileUnitExtension
-- (hit_enemy / hit_level_unit / hit_static_unit / hit_breakable_object) and
-- spawns the FX locally on every peer that runs the projectile. The full
-- revert routes through DamageUtils.create_explosion which gates damage on
-- is_server — VFX still plays on every peer, damage only applies host-side.
--
-- The shooter's item_name match (`we_deus_01*`) covers every skin/illusion
-- since item keys preserve the base prefix.

local _MOONFIRE_PUFF_FX = "fx/wpnfx_we_deus_01_impact"

-- Template must be registered in ExplosionTemplates AND carry a .name field.
-- DamageUtils.create_explosion forwards `explosion_template.name` to
-- AreaDamageSystem.add_aoe_damage_target, which later calls
-- ExplosionUtils.get_template(name) -> ExplosionTemplates[name]. The vanilla
-- auto-name loop at the end of explosion_templates.lua runs at engine boot
-- (before mods load), so we set .name explicitly here.
local _MOONFIRE_AOE_NAME = "wt_moonfire_aoe_revert"
local _MOONFIRE_AOE_TEMPLATE = {
    name = _MOONFIRE_AOE_NAME,
    explosion = {
        damage_profile = "poison_aoe",
        effect_name = _MOONFIRE_PUFF_FX,
        sound_event_name = "arrow_hit_poison_cloud",
        no_prop_damage = true,
        no_friendly_fire = true,
        radius = 1.5,
        max_damage_radius = 0.75,
        use_attacker_power_level = true,
        attacker_power_level_offset = -0.5,
    },
}
if rawget(_G, "ExplosionTemplates") then
    ExplosionTemplates[_MOONFIRE_AOE_NAME] = _MOONFIRE_AOE_TEMPLATE
end

-- issue #535: register the AoE template into NetworkLookup.explosion_templates
-- UNCONDITIONALLY at load (PROJECT_STANDARDS 9.3, index determinism across wt
-- peers), mirroring the damage_profiles append idiom above (~:1891). The lookup
-- is frozen at engine boot with a strict __index that errors on any missing key
-- [src: scripts/network_lookup/network_lookup.lua build :1211 (create_lookup
-- {"n/a"}, ExplosionTemplates); strict __index :2360-2367]. Forward + reverse
-- append, rawget-guarded so it registers once.
--
-- WIRE-PATH ANALYSIS (why this registration is belt-and-suspenders, NOT
-- load-bearing): the moonfire hook calls DamageUtils.create_explosion DIRECTLY
-- (below), never AreaDamageSystem.create_explosion. DamageUtils.create_explosion
-- never encodes via NetworkLookup.explosion_templates; its only AoE-network
-- touch is area_damage_system:add_aoe_damage_target [src: damage_utils.lua:1470],
-- which stores the name as a STRING in a host-only local ring buffer and
-- resolves it through ExplosionUtils.get_template -> ExplosionTemplates[name]
-- [src: area_damage_system.lua:280,331,347], never NetworkLookup. The ONLY
-- NetworkLookup.explosion_templates[name] encode in the explosion path is
-- AreaDamageSystem.create_explosion [src: area_damage_system.lua:162], which the
-- moonfire path never reaches. So this name never rides the wire: it cannot
-- strict-__index-fatal on encode (the wt shooter's machine) nor on decode (a
-- non-wt peer). Full trace in weapon_tweaker/ENGINE_SURFACE.md. Registration is
-- still done for index determinism + to kill the footgun should a future change
-- ever route moonfire through AreaDamageSystem.create_explosion.
do
    local NL = rawget(_G, "NetworkLookup")
    local lookup = NL and NL.explosion_templates
    if lookup and not rawget(lookup, _MOONFIRE_AOE_NAME) then
        local idx = #lookup + 1
        rawset(lookup, idx, _MOONFIRE_AOE_NAME)
        rawset(lookup, _MOONFIRE_AOE_NAME, idx)
        pcall(printf, "[wt:535] registered %s into NetworkLookup.explosion_templates at index %d (wire-inert; see ENGINE_SURFACE.md)", _MOONFIRE_AOE_NAME, idx)
    end
    -- Record the wire-safe vanilla fallback for the moonfire AoE. machinegun_poison_arrow
    -- is the closest vanilla explosion template: same gameplay shape - damage_profile
    -- "poison_aoe", sound "arrow_hit_poison_cloud", no_prop_damage, use_attacker_power_level
    -- [src: scripts/settings/explosion_templates.lua:6-15]. There is NO active
    -- sender-side floor hook, because moonfire has no NetworkLookup send path
    -- (analysis above) - this is the documented substitute a floor WOULD coerce
    -- to if a send path is ever added, and the /wt_regression_test check below
    -- asserts it resolves to a real vanilla index. Same map shape as the #431
    -- damage-profile fallback (mod._wt431_custom_profile_fallback).
    mod._wt535_explosion_template_fallback = mod._wt535_explosion_template_fallback or {}
    mod._wt535_explosion_template_fallback[_MOONFIRE_AOE_NAME] = "machinegun_poison_arrow"
end

-- issue #535 regression: the moonfire AoE template must be registered in BOTH
-- ExplosionTemplates (local resolution) and NetworkLookup.explosion_templates
-- (wire index determinism), and its recorded wire-safe fallback must resolve to
-- a real vanilla index.
_rt_register("wt_535_moonfire_explosion_registered", function()
    local tmpl = rawget(_G, "ExplosionTemplates")
    if not tmpl then return "skip: ExplosionTemplates not loaded (run in-mission)" end
    local entry = rawget(tmpl, _MOONFIRE_AOE_NAME)
    if type(entry) ~= "table" then return "wt_moonfire_aoe_revert missing from ExplosionTemplates" end
    if entry.name ~= _MOONFIRE_AOE_NAME then return "wt_moonfire_aoe_revert entry missing its .name field" end
    local NL = rawget(_G, "NetworkLookup")
    local lookup = NL and NL.explosion_templates
    if not lookup then return "skip: NetworkLookup.explosion_templates not loaded" end
    local idx = rawget(lookup, _MOONFIRE_AOE_NAME)
    if type(idx) ~= "number" then
        return "wt_moonfire_aoe_revert not in NetworkLookup.explosion_templates (an encode would strict-__index fatal)"
    end
    if rawget(lookup, idx) ~= _MOONFIRE_AOE_NAME then
        return "NetworkLookup.explosion_templates reverse map broken (idx->name mismatch)"
    end
    local map = mod._wt535_explosion_template_fallback
    local fb = map and map[_MOONFIRE_AOE_NAME]
    if type(fb) ~= "string" or fb == _MOONFIRE_AOE_NAME then
        return "moonfire wire-safe fallback not recorded (must be a vanilla name, not the custom one)"
    end
    if not rawget(lookup, fb) then
        return string.format("wire-safe fallback %s not in NetworkLookup.explosion_templates", tostring(fb))
    end
end)

local _moonfire_jitter_offsets = {
    Vector3Box(0.35, 0, 0.1),
    Vector3Box(-0.3, 0.2, 0.15),
    Vector3Box(0.05, -0.3, 0.2),
}

local function _is_moonfire_arrow(item_name)
    if not item_name then return false end
    return string.sub(item_name, 1, 10) == "we_deus_01"
end

local function _wt_moonfire_on_hit(self, hit_position)
    if not _is_moonfire_arrow(self.item_name) then return end
    -- moonfire_cosmetic_puff moved to cosmetics_tweaker (Weapon & Item Appearance,
    -- setting cos_moonfire_cosmetic_puff) on 2026-06-29 — wt keeps only the gameplay
    -- AOE revert. Cosmetics' puff hook skips when this revert is on (it already puffs).
    if not mod:get("moonfire_aoe_revert") then return end
    local world = self._world
    if not world or not hit_position then return end

    local rotation = Unit.alive(self._projectile_unit)
        and Unit.local_rotation(self._projectile_unit, 0)
        or Quaternion.identity()
    local owner_unit = self._owner_unit
    if not Unit.alive(owner_unit) then return end
    local is_husk = self._owner_player and not self._owner_player.local_player or false
    DamageUtils.create_explosion(
        world,
        owner_unit,
        hit_position,
        rotation,
        _MOONFIRE_AOE_TEMPLATE,
        self.scale or 1,
        self.item_name,
        self._is_server,
        is_husk,
        self._projectile_unit,
        self.power_level or 0,
        self._is_critical_strike or false,
        owner_unit
    )
    for i = 1, #_moonfire_jitter_offsets do
        local p = hit_position + _moonfire_jitter_offsets[i]:unbox()
        World.create_particles(world, _MOONFIRE_PUFF_FX, p, Quaternion.identity())
    end
end

-- Hook BOTH PlayerProjectileUnitExtension (shooter's own machine) and
-- PlayerProjectileHuskExtension (every other peer that sees the arrow). Both
-- carry the same fields _wt_moonfire_on_hit reads (item_name, _world,
-- _projectile_unit, _owner_unit, _owner_player, scale, power_level,
-- _is_critical_strike, _is_server). Without the husk hooks the puff only
-- spawns on the shooter's screen.
local _moonfire_hooked_classes = { "PlayerProjectileUnitExtension", "PlayerProjectileHuskExtension" }
local _moonfire_hooked_methods = { "hit_enemy", "hit_level_unit", "hit_non_level_unit" }
for _, class_name in ipairs(_moonfire_hooked_classes) do
    local cls = rawget(_G, class_name)
    if cls then
        for _, method_name in ipairs(_moonfire_hooked_methods) do
            if cls[method_name] then
                mod:hook_safe(cls, method_name, function(self, impact_data, hit_unit, hit_position)
                    _wt_moonfire_on_hit(self, hit_position)
                end)
            end
        end
    end
end

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
    -- hand, no book). The helper handles BOTH hands (right=book → swapped to hammer;
    -- left=original hammer → hidden), career-gated to es_ inside.
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
-- v0.12.187-dev: REPLACED the spawned-unit mesh swap (v0.12.186-dev) with the simpler
-- offset-free approach the user asked for. The spawned-unit swap mounted a freshly-
-- spawned hammer at the right node and produced bad transforms / crazy offsets in-game.
-- Instead we KEEP the vanilla Skullsplitter hammer in its native engine position and
-- just HIDE THE BOOK, letting the to_1h_hammer wield redirect (wt_wield_patches.lua)
-- animate the hammer as Kruber's native 1H mace. NOTHING is spawned, linked, or
-- relinked — so there are no swap-induced offsets.
--
-- Vanilla `one_handed_hammer_book_priest_template`: left_hand_unit = the Skullsplitter
-- HAMMER (keep it), right_hand_unit = the BOOK (hide it). spawn_inventory_unit fires
-- once per hand:
--   * hand == "right" (the book): hide that 3P unit. `show_third_person_inventory`
--     re-shows the right-hand wielded unit on every wield
--     (simple_inventory_extension.lua:1017-1024), so `_rehide_hidden_3p_units` (below)
--     re-hides it durably; this spawn-time hide additionally covers the husk path
--     (husks don't call show_third_person_inventory from _wield_slot).
--   * hand == "left" (the hammer): return the vanilla units UNCHANGED — the hammer
--     keeps its correct native attachment.
-- 3P-ONLY: v_w1p/v_a1p (1P) are never touched — 1P is universal across all six chars.
_wt_hammer_book_3p_swap_apply = function(v_w3p, v_a3p, v_w1p, v_a1p, world, hand, item_template, item_data, owner_unit_1p, owner_unit_3p, material_settings_name)
    do
        local is_husk = owner_unit_1p == nil
        local career_for_log = _unit_career_name(owner_unit_3p)
        _dbg("[wt hammer-book-3p-swap] enter hand=%s husk=%s owner_unit_3p=%s career=%s v_w3p=%s",
            tostring(hand), tostring(is_husk), tostring(owner_unit_3p ~= nil),
            tostring(career_for_log), tostring(v_w3p ~= nil))
    end

    local career_name = _unit_career_name(owner_unit_3p)
    if not career_name or career_name:sub(1, 3) ~= "es_" then
        _dbg("[wt hammer-book-3p-swap] SKIP (career not Kruber: %s)", tostring(career_name))
        return v_w3p, v_a3p, v_w1p, v_a1p
    end

    -- RIGHT hand = the book → hide it (3P only). LEFT hand (the hammer) and any other
    -- hand → return vanilla unchanged (hammer stays in its native position).
    if hand == "right" and v_w3p and Unit.alive(v_w3p) then
        if Unit.has_visibility_group(v_w3p, "normal") then
            Unit.set_visibility(v_w3p, "normal", false)
        else
            Unit.set_unit_visibility(v_w3p, false)
        end
        _dbg("[wt hammer-book-3p-swap] hid book 3P unit at spawn (husk=%s career=%s)",
            tostring(owner_unit_1p == nil), career_name)
    end

    -- Never spawn/relink/delete — always return the vanilla units (book just hidden).
    return v_w3p, v_a3p, v_w1p, v_a1p
end

-- Durable re-hide of 3P units that a wt swap/hide leaves hidden but that vanilla
-- `show_third_person_inventory` re-shows on every wield/unwield
-- (simple_inventory_extension.lua:1017-1075 / simple_husk_inventory_extension.lua:471
-- set visibility back to `show`). Post-hook that function and re-hide the relevant
-- 3P unit, gated to Kruber (es_) careers:
--   * wh_brace_of_pistols: hide the LEFT pistol. The brace renders two pistols; the
--     right-hand mesh is swapped to the Empire repeater and the left pistol clips it.
--   * wh_hammer_book (#181): hide the RIGHT-hand unit (the BOOK). The Skullsplitter
--     hammer (left_hand_wielded_unit_3p) is KEPT visible in its correct native
--     position — it just animates via the to_1h_hammer wield redirect.
--
-- v0.12.39 — registered on BOTH SimpleInventoryExtension AND SimpleHuskInventoryExtension.
-- The husk class has the same method but no inheritance from the self-owned class
-- (see feedback_vt2_husk_extension_class_pair). ONE hook_safe per (Class, method) per
-- mod — both weapons share this single callback (VMF_RECIPES § 1, no-duplicate-hooks).
local function _rehide_hidden_3p_units(self, show)
    if not show then return end
    local equipment = self._equipment
    if not equipment then return end

    local wielded_slot = equipment.wielded_slot
    if not wielded_slot then return end
    local slot_data = equipment.slots and equipment.slots[wielded_slot]
    local item_data = slot_data and slot_data.item_data
    if not item_data then return end

    -- Which 3P unit to re-hide depends on the wielded weapon.
    local unit_to_hide
    if item_data.name == "wh_brace_of_pistols" then
        unit_to_hide = equipment.left_hand_wielded_unit_3p   -- brace's clipping left pistol
    elseif item_data.name == "wh_hammer_book" then
        unit_to_hide = equipment.right_hand_wielded_unit_3p  -- #181: the book (hammer stays)
    else
        return
    end
    if not unit_to_hide or not Unit.alive(unit_to_hide) then return end

    local owner_unit = self._unit
    local career_name = owner_unit and _unit_career_name(owner_unit)
    if not career_name or career_name:sub(1, 3) ~= "es_" then return end

    -- Force the unit invisible. Mirror the visibility-group branching that vanilla
    -- `show_third_person_inventory` uses so we hit whichever path it was rendered through.
    if Unit.has_visibility_group(unit_to_hide, "normal") then
        Unit.set_visibility(unit_to_hide, "normal", false)
    else
        Unit.set_unit_visibility(unit_to_hide, false)
    end
end

mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", _rehide_hidden_3p_units)
mod:hook_safe("SimpleHuskInventoryExtension", "show_third_person_inventory", _rehide_hidden_3p_units)

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

-- Inventory preview book-hide for Kruber's wh_hammer_book (#181).
-- v0.12.187-dev: matches the offset-free in-mission approach — the keep/hero preview
-- spawns 3P units from precomputed `spawn_data` (World.spawn_unit; it does NOT route
-- through GearUtils.spawn_inventory_unit), so to hide the book here we DROP its
-- spawn_data entry (the book is the right_hand entry). The Skullsplitter hammer
-- (left_hand entry) is left UNTOUCHED so it renders in its correct native position.
-- No mesh swap, no node-linking substitution → no preview offsets.
_wt_hammer_book_preview_swap_apply = function(self, item_name, slot)
    if item_name ~= "wh_hammer_book" then return end
    local career = self._current_career_name
    if not career or career:sub(1, 3) ~= "es_" then return end

    local slot_type = (type(slot) == "table" and slot.type) or nil
    if not slot_type then return end
    local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
    if not info or not info.spawn_data then return end

    local new_spawn_data = {}
    local hid_book = false
    for _, entry in ipairs(info.spawn_data) do
        if entry.right_hand then
            -- drop the book (right_hand) entry so it never spawns in the preview
            hid_book = true
        else
            -- keep the hammer (left_hand) + any other entry, untouched (native position)
            new_spawn_data[#new_spawn_data + 1] = entry
        end
    end
    info.spawn_data = new_spawn_data

    if hid_book then
        _dbg("[wt hammer-book-3p-swap preview] dropped book (right_hand) entry, kept native hammer on career=%s", career)
    end
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

    local fake_slot = { [_wt_grip_offset_policy.preview_slot_field(item_template)] = unit }
    _scale_weapon_units(fake_slot, weapon_key, career_name)
    _offset_weapon_units(fake_slot, weapon_key, career_name)
    _wt569_track_3p_units(fake_slot, weapon_key, career_name, item_template,
        nil, slot_type, not skip_wield_anim and self._wielded_slot_type == slot_type)

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

-- CW weapon-trait pool filtering (_trait_pool_sources + apply_trait_filters /
-- revert_trait_pools, currently a retired no-op stub) moved to _wt_trait_pools.lua
-- in the v0.12.209-dev OOP split. The lifecycle callbacks below call it via the
-- entry's file-local aliases (apply_trait_filters / revert_trait_pools) from the
-- manifest; the legacy mod._apply_trait_filters / mod._revert_trait_pools flat
-- exports are re-published by that module.

-- CLARIFY: VMF lifecycle callback. Fires on every game state transition
-- (StateLoading -> StateIngame, etc.) — re-applies the can_wield mutations
-- in case some other mod or game code reset ItemMasterList between states.
-- Idempotent (apply_weapon_unlocks strips before adding).
--
-- v0.12.74-dev: also drives a loadout dump on StateIngame entry when
-- enable_debug_logging is ON (v0.12.81-dev rename from wt_debug_mode
-- per PROJECT_STANDARDS.md § 3.6). VMF passes (status, state_name) where status is
-- "enter" / "exit" and state_name is the class name (e.g. "StateIngame")
-- — verified against general_tweaker / buff_tweaker / career_tweaker
-- which all use the same signature. The dump uses inventory_system
-- extension fields (`._career_name`, `:equipment().slots`) — same path
-- as the existing `/dump` chat command. Cheap: a handful of pairs() walks
-- through equipment.slots, only runs on state entry, only runs when debug
-- is on.
local function _dbg_dump_local_player_loadout()
    local pm = Managers and Managers.player
    if not pm then return end
    local ok_pl, player = pcall(pm.local_player, pm)
    if not ok_pl or not player or not player.player_unit then return end
    local unit = player.player_unit
    local ok_inv, inv = pcall(ScriptUnit.has_extension, unit, "inventory_system")
    if not ok_inv or not inv then return end
    local career_name = inv._career_name or "(unknown career)"
    local ok_eq, equipment = pcall(inv.equipment, inv)
    if not ok_eq or not equipment or not equipment.slots then return end
    _dbg("[loadout] StateIngame enter career=%s", tostring(career_name))
    for slot_name, slot_data in pairs(equipment.slots) do
        local item = slot_data and slot_data.item_data
        if item then
            local key = item.key or item.name or "?"
            local tmpl = item.template or (item.data and item.data.template) or "?"
            local itype = item.item_type or (item.data and item.data.item_type) or "?"
            _dbg("[loadout]   %s: key=%s item_type=%s template=%s",
                tostring(slot_name), tostring(key), tostring(itype), tostring(tmpl))
        end
    end
end

mod.on_game_state_changed = function(status, state_name)
    -- [heap-probe] v0.12.121-dev: per-state-transition lua_heap sampler for the
    -- 1 GiB lua_heap OOM diagnosis (see memory reference_vt2_lua_heap_1gib_crash).
    -- Fires on EVERY transition. Routed through mod:debug channel (VMF
    -- output_mode_debug controls visibility). Instrument only — no fix shipped.
    local _heap_pre = collectgarbage("count")
    local since_last = mod._heap_probe_last_kb and (_heap_pre - mod._heap_probe_last_kb) or 0
    mod:debug("[heap-probe] %s/%s pre-apply: %.1f MB (%.0f KB), since last transition: %+.0f KB",
        tostring(state_name), tostring(status), _heap_pre / 1024, _heap_pre, since_last)
    mod._heap_probe_last_kb = _heap_pre

    mod:info("Weapon Tweaker: Baseline Active")
    apply_weapon_unlocks()
    -- #368: CWV registers clone definitions from its own state-enter callback.
    -- Reconcile once more on the following frame so WT is the deterministic
    -- final can_wield writer regardless of VMF callback ordering.
    mod._wt368_deferred_availability = true
    patch_career_actions_on_weapons()
    apply_trait_filters()
    if mod._wt_apply_axe_balance then mod._wt_apply_axe_balance(nil, false) end
    _wt_bolt_staff_overcharge_runtime.apply()
    -- Re-attempt the Necromancer FX force-load (idempotent). DLC ownership can be
    -- unresolved at mod-init even for owners; by any state transition it's resolved,
    -- so this guarantees bw_necromancer's soul_rip particles are resident before the
    -- staff can be wielded in a mission (2026-06-29 nicho create_particles crash).
    mod._force_load_necromancer_fx_package()
    -- Loadout dump on StateIngame entry (routed through mod:debug channel).
    if status == "enter" and state_name == "StateIngame" then
        _dbg_dump_local_player_loadout()
    end

    local heap_post = collectgarbage("count")
    mod:debug("[heap-probe] %s/%s post-apply: %.1f MB, this transition's apply cost: %+.0f KB",
        tostring(state_name), tostring(status), heap_post / 1024, heap_post - _heap_pre)

    -- v0.12.126-dev LEAK TEST: on mission EXIT only, force a full GC and
    -- re-measure. The live sampler above deliberately never collects (so
    -- retained growth stays visible), but the one thing it can't answer is
    -- whether the heap that DIDN'T free on exit is a true retained-reference
    -- leak or just collectable garbage the engine hadn't reaped yet. This
    -- forces the question: `reclaimed` = garbage; whatever remains above the
    -- keep baseline (~150 MB) is the real, non-collectable footprint that
    -- ACCUMULATES toward the 1 GiB cap. Resync _heap_probe_last_kb to the
    -- post-GC value so the next transition's delta stays honest.
    if status == "exit" and state_name == "StateIngame" then
        local before_gc = collectgarbage("count")
        collectgarbage("collect")
        local after_gc = collectgarbage("count")
        mod._heap_probe_last_kb = after_gc
        mod:debug("[heap-probe] StateIngame/exit FORCED-GC LEAK TEST: %.1f MB -> %.1f MB (reclaimed %.0f KB garbage; %.1f MB SURVIVES GC = true non-garbage footprint — if this climbs each mission it's a real leak)",
            before_gc / 1024, after_gc / 1024, before_gc - after_gc, after_gc / 1024)
    end
end

-- clear_weapon_unlocks / clear_career_action_injections (the on_disabled revert
-- of the can_wield additions + injected ability actions) moved to
-- _wt_availability.lua in the v0.12.209-dev OOP split; on_disabled below calls
-- them via the entry's file-local aliases from the manifest.
mod.on_disabled = function()
    -- WT_DEV_OVERLAY_BEGIN:hold-pose-disable-lifecycle
    if _wt_dev_hold_pose and _wt_dev_hold_pose.on_disabled then
        _wt_dev_hold_pose.on_disabled()
    end
    -- WT_DEV_OVERLAY_END:hold-pose-disable-lifecycle
    if weapon_backend.overcharge_presentation then pcall(weapon_backend.overcharge_presentation.restore) end
    _wt_bolt_staff_overcharge_runtime.revert()
    if mod._wt_apply_axe_balance then mod._wt_apply_axe_balance(nil, true) end
    clear_weapon_unlocks()
    clear_career_action_injections()
    revert_trait_pools()
    mod:info("Weapon Tweaker disabled — cross-career unlocks, ability action injections, and trait-pool filters reverted")
end

mod.on_setting_changed = function(setting_id)
    if setting_id and setting_id:find("^wtmaster_") then
        -- issue 611: a master toggle was clicked. Cascade its new value to every
        -- child availability toggle (notify = false), then re-apply the unlocks
        -- once. Children set with notify = false do not re-enter this handler.
        _wt_master_toggles.on_master_changed(mod, setting_id)
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
        weapon_backend.refresh_on_setting_change(mod)
    elseif setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
        weapon_backend.refresh_on_setting_change(mod)
        -- issue 611 auto-off: recompute the owning master so deselecting one
        -- weapon flips its "Enable All ..." toggle OFF while the rest stay as-is.
        if setting_id:find("^unlock_") then
            _wt_master_toggles.on_child_changed(mod, setting_id)
        end
    elseif setting_id and (setting_id:find("^trait_") or setting_id:find("^cw_trait_")) then
        apply_trait_filters()
    -- WT_DEV_OVERLAY_BEGIN:dev-tool-setting-lifecycle
    elseif setting_id and setting_id:find("^wt_dev_anim_") then
        -- Dev: 3P anim picker — mutate live Weapons.<tpl> tables.
        _wt_dev_anim_picker.on_setting_changed(setting_id)
    elseif setting_id and setting_id:find("^wt_dev_hp_") then
        -- Hold-Pose owns immediate non-destructive bypass/restore for its
        -- isolated first-/third-person transform channels (#616).
        _wt_dev_hold_pose.on_setting_changed(setting_id)
    -- WT_DEV_OVERLAY_END:dev-tool-setting-lifecycle
    elseif setting_id == "wt_priest_punch_buff" then
        if mod.wt_apply_priest_punch_buff then mod.wt_apply_priest_punch_buff() end
    elseif setting_id == "wt_brett_sword_shield_buff" then
        if mod.wt_apply_brett_buff then mod.wt_apply_brett_buff() end
    elseif setting_id == _wt_bolt_staff_overcharge.SETTING_ID then
        _wt_bolt_staff_overcharge_runtime.apply()
    elseif setting_id == _wt_axe_balance_policy.GREATAXE_LIGHT_CRIT_SETTING
            or setting_id == _wt_axe_balance_policy.DUAL_AXES_LIGHT_CRIT_SETTING
            or setting_id == _wt_axe_balance_policy.DUAL_AXES_CLEAVE_SETTING
            or setting_id == _wt_axe_balance_policy.ONE_HAND_AXE_CLEAVE_SETTING
            or setting_id == _wt_axe_balance_policy.COG_HAMMER_HEAVY_SPEED_SETTING
            or setting_id == _wt_axe_balance_policy.MACE_SWORD_SPEED_SETTING
            or setting_id == _wt_axe_balance_policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING then
        mod._wt_apply_axe_balance(setting_id, false)
    end
end

do
    local function register_profile(name)
        local lookup = NetworkLookup and NetworkLookup.damage_profiles
        if type(name) ~= "string" or not lookup or rawget(lookup, name) then return end
        local index = #lookup + 1
        rawset(lookup, index, name)
        rawset(lookup, name, index)
    end
    mod._wt_apply_axe_balance = function(setting_id, force_off)
        if type(Weapons) ~= "table" then return end
        local function enabled(id, default_on)
            if force_off then return false end
            local value = mod:get(id)
            if value == nil then return default_on == true end
            return value == true
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.GREATAXE_LIGHT_CRIT_SETTING then
            _wt_axe_balance:apply_greataxe_crit(
                enabled(_wt_axe_balance_policy.GREATAXE_LIGHT_CRIT_SETTING, true), Weapons)
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.DUAL_AXES_LIGHT_CRIT_SETTING then
            _wt_axe_balance:apply_dual_crit(
                enabled(_wt_axe_balance_policy.DUAL_AXES_LIGHT_CRIT_SETTING, true), Weapons)
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.DUAL_AXES_CLEAVE_SETTING then
            if type(DamageProfileTemplates) == "table" and type(PowerLevelTemplates) == "table" then
                _wt_axe_balance:apply_dual_cleave(
                    enabled(_wt_axe_balance_policy.DUAL_AXES_CLEAVE_SETTING, true), Weapons,
                    DamageProfileTemplates, PowerLevelTemplates,
                    function(value) return table.clone(value, true) end, register_profile)
            end
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.ONE_HAND_AXE_CLEAVE_SETTING then
            if type(DamageProfileTemplates) == "table" and type(PowerLevelTemplates) == "table" then
                mod._wt431_custom_profile_fallback = mod._wt431_custom_profile_fallback or {}
                local parity_allowed = type(mod._wt431_profiles_allowed) == "function"
                    and mod._wt431_profiles_allowed() == true
                _wt_axe_balance:apply_one_hand_axe_cleave(
                    enabled(_wt_axe_balance_policy.ONE_HAND_AXE_CLEAVE_SETTING, false), Weapons,
                    DamageProfileTemplates, PowerLevelTemplates,
                    function(value) return table.clone(value, true) end, register_profile,
                    mod._wt431_custom_profile_fallback, parity_allowed)
            end
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.COG_HAMMER_HEAVY_SPEED_SETTING then
            _wt_axe_balance:apply_cog_heavy_speed(
                enabled(_wt_axe_balance_policy.COG_HAMMER_HEAVY_SPEED_SETTING, false), Weapons)
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.MACE_SWORD_SPEED_SETTING then
            _wt_axe_balance:apply_mace_sword_speed(
                enabled(_wt_axe_balance_policy.MACE_SWORD_SPEED_SETTING, false), Weapons)
        end
        if not setting_id or setting_id == _wt_axe_balance_policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING then
            if type(DamageProfileTemplates) == "table" then
                mod._wt431_custom_profile_fallback = mod._wt431_custom_profile_fallback or {}
                local parity_allowed = type(mod._wt431_profiles_allowed) == "function"
                    and mod._wt431_profiles_allowed() == true
                local count = _wt_axe_balance:apply_executioner_light_headshot(
                    enabled(_wt_axe_balance_policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING, false),
                    Weapons, DamageProfileTemplates,
                    function(value) return table.clone(value, true) end, register_profile,
                    mod._wt431_custom_profile_fallback, parity_allowed)
                pcall(printf, "[wt:664] applied: executioner_light_actions=%d enabled=%s parity=%s multiplier=%.2f",
                    count, tostring(enabled(_wt_axe_balance_policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING, false)),
                    tostring(parity_allowed), _wt_axe_balance_policy.EXECUTIONER_HEADSHOT_MULT)
            end
        end
    end
    mod._wt_apply_axe_balance(nil, false)
end

-- #664 hook pre-flight: repository grep on 2026-07-17 found no other WT hook
-- on DamageUtils.calculate_damage. Vanilla computes and returns the complete
-- post-armor, post-buff, post-stagger damage at damage_utils.lua:449-569; the
-- private light profile marker therefore gives an exact 1.30x headshot result
-- without changing body shots, heavies, cleave, stagger, crit, or armor data.
if rawget(_G, "DamageUtils") then
    mod:hook(DamageUtils, "calculate_damage", function(func, damage_output, target_unit,
            attacker_unit, hit_zone_name, original_power_level, boost_curve,
            boost_damage_multiplier, is_critical_strike, damage_profile, ...)
        local damage, second = func(damage_output, target_unit, attacker_unit,
            hit_zone_name, original_power_level, boost_curve, boost_damage_multiplier,
            is_critical_strike, damage_profile, ...)
        if type(damage) == "number" and target_unit then
            local breed = AiUtils.unit_breed(target_unit)
            local multiplier_type = DamageUtils.get_breed_damage_multiplier_type(breed, hit_zone_name)
            damage = _wt_axe_balance_policy.scale_executioner_headshot_damage(
                damage, multiplier_type, damage_profile)
        end
        if second ~= nil then return damage, second end
        return damage
    end)
end

_rt_register("issue621_one_hand_axe_cleave_boundary", function()
    local function action(profile)
        return { kind = "sweep", damage_profile = profile }
    end
    local single = {
        weapon_type = "AXE_1H", buff_type = "MELEE_1H",
        state_machine = "units/beings/player/first_person_base/state_machines/melee/1h_axe",
        actions = { action_one = { light_attack_left = action("rt_axe") } },
    }
    local dual = table.clone(single, true)
    dual.left_hand_unit = "offhand"
    dual.state_machine = "units/beings/player/first_person_base/state_machines/melee/dual_axes"
    local profiles = { rt_axe = { cleave_distribution = { attack = 2, impact = 4 } } }
    local state = _wt_axe_balance_policy.new()
    state:apply_one_hand_axe_cleave(true, { single = single, dual = dual }, profiles, {},
        function(value) return table.clone(value, true) end, nil, {}, true)
    local generated = profiles.wt_1h_axe_cleave_90_rt_axe
    if not generated or math.abs(generated.cleave_distribution.attack - 1.8) > 0.000001
            or math.abs(generated.cleave_distribution.impact - 3.6) > 0.000001 then
        return "#621 cleave clone is not exact 0.90x attack/impact"
    end
    if single.actions.action_one.light_attack_left.damage_profile ~= "wt_1h_axe_cleave_90_rt_axe"
            or dual.actions.action_one.light_attack_left.damage_profile ~= "rt_axe" then
        return "#621 single/dual capability boundary drifted"
    end
    state:apply_one_hand_axe_cleave(false, { single = single }, profiles, {},
        function(value) return table.clone(value, true) end, nil, {}, true)
    if single.actions.action_one.light_attack_left.damage_profile ~= "rt_axe" then
        return "#621 disable did not restore exact source profile"
    end
end)

_rt_register("issue622_cog_hammer_heavy_speed_boundary", function()
    local actions = {
        heavy_attack_left = { anim_time_scale = 0.99 },
        heavy_attack_right = { anim_time_scale = 0.99 },
        heavy_attack_left_charged = {}, heavy_attack_right_charged = {},
        light_attack_left = { anim_time_scale = 0.90 }, push = {},
    }
    local state = _wt_axe_balance_policy.new()
    state:apply_cog_heavy_speed(true, {
        two_handed_cog_hammers_template_1 = { actions = { action_one = actions } },
    })
    if math.abs(actions.heavy_attack_left.anim_time_scale - 0.90) > 0.000001
            or math.abs(actions.heavy_attack_left_charged.anim_time_scale - (1 / 1.10)) > 0.000001
            or actions.light_attack_left.anim_time_scale ~= 0.90
            or actions.push.anim_time_scale ~= nil then
        return "#622 heavy-only speed boundary drifted"
    end
    state:apply_cog_heavy_speed(false, {})
    if actions.heavy_attack_left.anim_time_scale ~= 0.99
            or actions.heavy_attack_left_charged.anim_time_scale ~= nil then
        return "#622 disable did not restore authored scales"
    end
end)

_rt_register("issue623_native_mace_sword_speed_boundary", function()
    local native = {
        light_attack_left_diagonal = { anim_time_scale = 0.945 },
        light_attack_right = { anim_time_scale = 1.035 },
        heavy_attack = { anim_time_scale = 1.035 },
        heavy_attack_2 = { anim_time_scale = 1.035 },
        light_attack_left = { anim_time_scale = 0.90 },
    }
    local reverse = table.clone(native, true)
    local state = _wt_axe_balance_policy.new()
    state:apply_mace_sword_speed(true, {
        dual_wield_hammer_sword_template = { actions = { action_one = native } },
        sword_and_mace_template = { actions = { action_one = reverse } },
    })
    if math.abs(native.light_attack_left_diagonal.anim_time_scale - (0.945 / 1.10)) > 0.000001
            or math.abs(native.heavy_attack_2.anim_time_scale - (1.035 / 1.10)) > 0.000001
            or native.light_attack_left.anim_time_scale ~= 0.90
            or reverse.light_attack_left_diagonal.anim_time_scale ~= 0.945 then
        return "#623 native-only action boundary drifted"
    end
    state:apply_mace_sword_speed(false, {})
    if native.light_attack_left_diagonal.anim_time_scale ~= 0.945
            or native.heavy_attack.anim_time_scale ~= 1.035 then
        return "#623 disable did not restore authored scales"
    end
end)

_rt_register("issue664_executioner_light_headshot_boundary", function()
    local source_profile = {
        charge_value = "light_attack", marker = "source",
        default_target = { power_distribution = { attack = 0.075, impact = 0.05 } },
        targets = { { power_distribution = { attack = 0.2, impact = 0.25 } } },
    }
    local profiles = { medium_slashing_linesman_executioner = source_profile }
    local light_a = { kind = "sweep", damage_profile = "medium_slashing_linesman_executioner" }
    local light_b = { kind = "sweep", damage_profile = "medium_slashing_linesman_executioner" }
    local heavy = { kind = "sweep", damage_profile = "heavy_slashing_smiter_executioner" }
    local body = { actions = { action_one = {
        light_attack_left = light_a, light_attack_bopp = light_b,
        heavy_attack_left = heavy, push = { kind = "push_stagger" },
    } } }
    local fallback, registered = {}, {}
    local state = _wt_axe_balance_policy.new()
    local count = state:apply_executioner_light_headshot(true, {
        two_handed_swords_executioner_template_1 = body,
    }, profiles, function(value) return table.clone(value, true) end,
        function(key) registered[key] = true end, fallback, true)
    local custom = profiles.wt_executioner_light_headshot_130
    if count ~= 2 or light_a.damage_profile ~= "wt_executioner_light_headshot_130"
            or light_b.damage_profile ~= "wt_executioner_light_headshot_130" then
        return "#664 did not repoint every and only light sweep"
    end
    if heavy.damage_profile ~= "heavy_slashing_smiter_executioner"
            or custom.marker ~= "source"
            or custom._wt_executioner_light_headshot_multiplier ~= 1.30
            or source_profile._wt_executioner_light_headshot_multiplier ~= nil then
        return "#664 custom profile isolation or 1.30 multiplier drifted"
    end
    if _wt_axe_balance_policy.scale_executioner_headshot_damage(100, "headshot", custom) ~= 130
            or _wt_axe_balance_policy.scale_executioner_headshot_damage(100, "torso", custom) ~= 100
            or _wt_axe_balance_policy.scale_executioner_headshot_damage(100, "headshot", source_profile) ~= 100 then
        return "#664 exact headshot/body/heavy damage boundary drifted"
    end
    if fallback.wt_executioner_light_headshot_130 ~= "medium_slashing_linesman_executioner"
            or not registered.wt_executioner_light_headshot_130 then
        return "#664 deterministic registration/fallback missing"
    end
    state:apply_executioner_light_headshot(false, {
        two_handed_swords_executioner_template_1 = body,
    }, profiles, function(value) return table.clone(value, true) end, nil, fallback, true)
    if light_a.damage_profile ~= "medium_slashing_linesman_executioner"
            or light_b.damage_profile ~= "medium_slashing_linesman_executioner" then
        return "#664 disable did not restore exact source profiles"
    end
end)

-- Install basic backend hooks (UI filtering and can_wield override)
weapon_backend.install(mod, weapon_unlock_map, apply_weapon_unlocks, patch_career_actions_on_weapons)
if weapon_backend.overcharge_presentation then
    for _, check in ipairs(weapon_backend.overcharge_presentation.rt_checks or {}) do
        _rt_register(check.name, check.fn)
    end
end
-- v0.12.68-dev: removed `mod.weapon_unlock_map = weapon_unlock_map` public
-- export. Repo grep + sibling-mod audit (AUDIT_section_e.md, weapon_tweaker
-- CODE_REVIEW.md, character_weapon_variants check) confirmed zero external
-- consumers. The local `weapon_unlock_map` table at line 59 remains — the
-- mod uses it internally. Only the public export is gone.

-- Run trait-pool filtering once at module load. on_game_state_changed will
-- re-run later if pools weren't ready yet (e.g. WeaponTraits not loaded).
apply_trait_filters()

-- ============================================================
-- Vanilla bug fix: LevelEndView._verify_weapon_data shape mismatch
-- ============================================================
-- crashify://811e5718-2e04-4995-8a22-0880c44cf44d. End-of-mission parade
-- crash: `team_previewer.lua:120: attempt to index local 'item_template'
-- (a nil value)`. Triggered when a player's loadout has a weapon that
-- fails `BackendInterfaceCommon.can_wield(career, item_data)` — most
-- commonly a `character_weapon_variants` cross-character variant, since
-- CWV variants inherit `entry.name` from their base weapon (per
-- feedback_cwv_clone_name_clobber.md) so the level-end verifier reads
-- the BASE entry's `can_wield` which doesn't include the new career.
--
-- Vanilla bug: `LevelEndView._verify_weapon_data` (level_end_view_v2.lua)
-- bails out with `verified_weapon = { item_name = career_settings.preview_items[1] }`.
-- But `career_settings.preview_items[1]` is itself a table of shape
-- `{ item_name = "<weapon_key>" }`, not a string. So `verified_weapon.item_name`
-- ends up holding a table, then `team_previewer.cb_hero_unit_spawned_skin_preview`
-- does `local item_name = item.item_name; ItemMasterList[item_name]` —
-- crashes because tables aren't valid ItemMasterList keys. Fatshark must
-- have changed the shape of `career_settings.preview_items` to a table-of-
-- tables without updating this code path.
--
-- Fix: post-hook the function, walk the returned `verified_weapon.item_name`
-- and unwrap one level if it's a table whose `.item_name` is a string. No
-- behavior change for the non-bailout path (verified_weapon.item_name is
-- assigned the string `weapon.item_name` at line 336 of the vanilla source,
-- which passes through unchanged).
if LevelEndView and LevelEndView._verify_weapon_data then
    -- v0.12.77 (Issue #26): converted to `mod:safe_hook`. The end-of-mission
    -- victory screen runs on a quick `LevelEndView:_setup_player_widgets`
    -- pass that hits this hook once per player. A raise here would blank
    -- the screen for every later consumer mod hooking the same path.
    mod:safe_hook("LevelEndView", "_verify_weapon_data", function(func, self, player_data, weapon_slot, weapon, weapon_pose_anim)
        _dbg("[verify_weapon_data] hook entry: player=%s career_index=%s weapon_slot=%s weapon.item_name=%s",
            tostring(player_data and player_data.name),
            tostring(player_data and player_data.career_index),
            tostring(weapon_slot),
            tostring(weapon and weapon.item_name))
        local verified_slot, verified_weapon, verified_pose = func(self, player_data, weapon_slot, weapon, weapon_pose_anim)
        if verified_weapon and type(verified_weapon.item_name) == "table" then
            local inner = verified_weapon.item_name.item_name
            if type(inner) == "string" then
                _dbg("[verify_weapon_data] unwrapping preview_items table shape: %s -> %s",
                    tostring(verified_weapon.item_name), inner)
                verified_weapon.item_name = inner
            else
                mod:warning("[verify_weapon_data] verified_weapon.item_name is a table with no string .item_name; clearing to avoid team_previewer crash (table=%s)",
                    tostring(verified_weapon.item_name))
                verified_weapon.item_name = nil
            end
        end
        return verified_slot, verified_weapon, verified_pose
    end)
end

-- ============================================================
-- Belt-and-suspenders: defend at the actual crash site
-- ============================================================
-- The `_verify_weapon_data` post-hook above is the correct surgical fix —
-- but in v0.12.52-dev a crash recurred (we_maidenguard parade) where the
-- vanilla "is not wieldable" bailout printed yet the post-hook unwrap log
-- was absent. Whether the hook didn't fire or the mutation was lost is
-- unresolved (the entry-point mod:info above will distinguish those on
-- the next repro). Regardless: also walk `hero_data.preview_items` at the
-- start of `TeamPreviewer.cb_hero_unit_spawned_skin_preview` and unwrap
-- any `.item_name` that's a `{ item_name = "..." }` table. This is the
-- frame just above where `ItemMasterList[item_name]` is indexed (line
-- 119-120 of team_previewer.lua) so it catches the broken shape no
-- matter which upstream path produced it.
--
-- TeamPreviewer is loaded by `require("scripts/ui/views/world_hero_previewer")`
-- which `team_previewer.lua` requires at file top. If TeamPreviewer is
-- not yet defined when this file runs (race), the string-form mod:hook
-- defers binding lazily.
mod:hook("TeamPreviewer", "cb_hero_unit_spawned_skin_preview", function(func, self, hero_previewer, hero_data)
    local preview_items = hero_data and hero_data.preview_items
    if preview_items then
        for i = 1, #preview_items do
            local item = preview_items[i]
            if item then
                -- Shape A: vanilla bug from LevelEndView bailout path —
                -- item.item_name is a `{ item_name = "..." }` table.
                if type(item.item_name) == "table" then
                    local inner = item.item_name.item_name
                    if type(inner) == "string" then
                        _dbg("[team_previewer cb] unwrapping preview_items[%d].item_name table shape -> %s (player=%s)",
                            i, inner, tostring(hero_data.hero_name))
                        item.item_name = inner
                    else
                        mod:warning("[team_previewer cb] preview_items[%d].item_name is a table with no string .item_name; clearing to avoid ItemMasterList crash (player=%s)",
                            i, tostring(hero_data.hero_name))
                        item.item_name = nil
                    end
                end
                -- Shape B: item.item_name is a string but not a valid
                -- ItemMasterList key (career-name leak, deleted CWV variant,
                -- stale skin, etc.). `ItemMasterList[k]` would return nil
                -- under the strict-lookup metatable; team_previewer.lua:121
                -- then crashes on `item_template.slot_type`. Use rawget to
                -- probe without firing the metatable's crashify, and clear
                -- to nil so the `if item_name then` guard skips this slot.
                if type(item.item_name) == "string" and not rawget(ItemMasterList, item.item_name) then
                    mod:warning("[team_previewer cb] preview_items[%d].item_name=%q is not in ItemMasterList; clearing to avoid team_previewer.lua:121 crash (player=%s)",
                        i, item.item_name, tostring(hero_data.hero_name))
                    item.item_name = nil
                end
            end
        end
    end
    return func(self, hero_previewer, hero_data)
end)

_rt_register("issue341_bolt_staff_primary_overcharge_contract", function()
    if _wt_bolt_staff_overcharge.MULTIPLIER ~= 0.6 then
        return "#341: primary overcharge multiplier must remain 0.6"
    end
    local status = rawget(_G, "PlayerUnitStatusSettings")
    local values = status and status.overcharge_values
    local baseline = _wt_bolt_staff_overcharge_runtime.baseline()
    if type(values) ~= "table" or type(baseline) ~= "number" then
        return "skip: PlayerUnitStatusSettings overcharge table not loaded"
    end
    local expected = _wt_bolt_staff_overcharge.desired_value(
        baseline, mod:get(_wt_bolt_staff_overcharge.SETTING_ID) == true)
    if values.spark ~= expected then
        return string.format("#341: spark overcharge expected %.3f, got %s",
            expected, tostring(values.spark))
    end
    local weapons = rawget(_G, "Weapons")
    local tpl = weapons and rawget(weapons, "staff_spark_spear_template_1")
    local action_one = tpl and tpl.actions and tpl.actions.action_one
    if not (action_one and action_one.default and action_one.rapid_left) then
        return "skip: Bolt Staff action table not loaded"
    end
    if action_one.default.overcharge_type ~= "spark"
            or action_one.rapid_left.overcharge_type ~= "spark" then
        return "#341: Bolt Staff primary actions no longer share the spark key"
    end
end)

-- Runtime regression registrations are isolated from the entry point while
-- preserving their original order and late-bound reads of live mod state.
local _wt_runtime_checks = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_runtime_checks")
local _wt_runtime_check_deps = {
    unit_state = _unit_state,
    weapon_unlock_map = weapon_unlock_map,
    three_p_template_remaps = _3p_template_remaps,
    post_spawn_preview_event = _wt603_post_spawn_preview_event,
    wield_anim_career_patches = _WIELD_ANIM_CAREER_3P_PATCHES,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    master_toggles = _wt_master_toggles,
    wield_patches_module = _WIELD_PATCHES_MODULE,
    is_sp_crossbow_presentation_item = _is_sp_crossbow_presentation_item,
    grip_offset_policy = _wt_grip_offset_policy,
    weapon_backend = weapon_backend,
}
-- WT_DEV_OVERLAY_BEGIN:runtime-check-dependencies
_wt_runtime_check_deps.dev_anim_picker = _wt_dev_anim_picker
_wt_runtime_check_deps.dev_hold_pose = _wt_dev_hold_pose
_wt_runtime_check_deps.zoom_probe_module = _WT316_ZOOM_PROBE
_wt_runtime_check_deps.zoom_probe = _wt316_zoom_probe
-- WT_DEV_OVERLAY_END:runtime-check-dependencies
_wt_runtime_checks.install(mod, _rt_register, _wt_runtime_check_deps)
-- WT_DEV_OVERLAY_BEGIN:picker-runtime-regressions
_rt_register("dev_picker_no_inspect_dropdown", function()
    -- User 2026-06-29: the inspect animation must NOT be a tunable picker dropdown —
    -- the weapon just uses whatever inspect anim it already has. Guard inspect events
    -- from creeping back into _WEAPON_ATTACKS / _SALTZ_WEAPON_ATTACKS.
    if not (_wt_dev_anim_picker and _wt_dev_anim_picker.inspect_attacks) then
        return "skip: picker has no inspect_attacks()"
    end
    local bad = _wt_dev_anim_picker.inspect_attacks()
    if type(bad) == "table" and #bad > 0 then
        return "inspect events present in picker (should be removed): " .. table.concat(bad, ", ")
    end
end)

_rt_register("issue411_dev_picker_source_events_resolve_live", function()
    if not (_wt_dev_anim_picker and _wt_dev_anim_picker.source_event_coverage) then
        return "picker has no source_event_coverage()"
    end
    local failures, weapons, events = _wt_dev_anim_picker.source_event_coverage()
    if #failures > 0 then return "dead picker source entries: " .. table.concat(failures, ", ") end
    if weapons == 0 or events == 0 then
        return string.format("picker source coverage inspected nothing (weapons=%d events=%d)",
            weapons, events)
    end
end)

_rt_register("saltz_billhook_set_uses_3p_events", function()
    -- #196: the Billhook SET (F) vocab must list the billhook's anim_event_3p VALUES
    -- (e.g. attack_swing_stab_charge), NOT its 1P anim_event names (attack_swing_charge_stab),
    -- because the picker writes anim_event_3p. The 1P names set a 3P event the Saltzpyre
    -- body doesn't author -> charge/heavy picks fall through to idle.
    if not (_wt_dev_anim_picker and _wt_dev_anim_picker.set_vocab_for) then
        return "skip: picker has no set_vocab_for()"
    end
    local vocab = _wt_dev_anim_picker.set_vocab_for("saltzpyre", "F")
    if type(vocab) ~= "table" then return "skip: Billhook SET F vocab not found" end
    local has = {}
    for _, e in ipairs(vocab) do has[e] = true end
    local bad = {}
    if not has["attack_swing_stab_charge"] then bad[#bad + 1] = "missing 3P charge event attack_swing_stab_charge" end
    for _, one_p in ipairs({ "attack_swing_charge_stab", "attack_swing_charge_down",
                             "attack_swing_heavy_down", "attack_swing_heavy_left", "attack_swing_stab_02" }) do
        if has[one_p] then bad[#bad + 1] = "1P-only event leaked into vocab: " .. one_p end
    end
    if #bad > 0 then return "Billhook SET F vocab wrong: " .. table.concat(bad, "; ") end
end)
-- WT_DEV_OVERLAY_END:picker-runtime-regressions
-- WT_DEV_OVERLAY_BEGIN:dev-tool-installs
-- ============================================================
-- Dev tooling installs (v0.12.96-dev)
-- ============================================================
-- Both modules expose M.install(). Called HERE, at the bottom of wt.lua, so
-- the template patchers above have already populated `Weapons.<template>`
-- with their initial values — the anim picker reads from those live tables
-- at install time to seed its dropdown defaults.
_wt_dev_anim_picker.install()
-- WT_DEV_OVERLAY_END:dev-tool-installs

mod:info("[mem-probe] wt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_WT) / 1024)
-- WT_DEV_OVERLAY_BEGIN:hold-pose-install
_wt_dev_hold_pose.install()
-- WT_DEV_OVERLAY_END:hold-pose-install
