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
  (Grip offsets + P0 create_equipment guards stay here — port-pipeline-coupled,
   Phase 3 candidates. The wield/template patchers moved to
   _wt_cross_char_template_patches.lua under #1159.)

Key conventions (also in CLAUDE.md):
  * NEVER hook BackendUtils.can_wield_item — modify ItemMasterList[*].can_wield directly.
  * rawget(ItemMasterList, k) when k might not exist (DLC ownership, save-data drift).
  * Lua 5.1 — locals are not hoisted; verify forward references before using a name.
]]

local mod = get_mod("wt")
local _WA_LIBRARY = mod:dofile(
    "scripts/mods/weapon_tweaker/_lib_weapon_appearance")
local _WEAPON_APPEARANCE = _WA_LIBRARY.new()
mod._wt_weapon_appearance = _WEAPON_APPEARANCE

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
local weapon_backend = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_backend")
mod:info("[mem-probe] wt weapon_backend: +%.1f MB lua (NOT in the boot_lua total below — baseline is set after this)", (collectgarbage("count") - _mp_pre_backend) / 1024)  -- [mem-probe]

-- Big Rebalance was retired under #321. Its unreachable implementation,
-- definitions, lifecycle stub, and dead-only formula checks were deleted under
-- #433. Saved br_* values remain untouched and the prefix stays reserved.

local MOD_VERSION = "0.12.330-beta"
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
mod:dofile("scripts/mods/weapon_tweaker/_safe_hook")

local _wt_axe_balance_policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_axe_balance")
-- Fire Sword heavy-attack policy (#943): two default-off projections from one
-- per-template-identity baseline (sweep opener + nova slowdown).
local _wt_fire_sword_policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_fire_sword")
local _wt_grip_offset_policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_grip_offset_policy")
local _wt_skullsplitter_hand_policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_skullsplitter_hand")

-- #1436: install history before every ordinary balance owner. Private
-- profiles are registered here so #431 fingerprints a stable catalog later.
local _wt_history_owner = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_history_owner").install({
        mod = mod,
        module_root = "scripts/mods/weapon_tweaker/",
    })
local _wt_history_runtime = _wt_history_owner.runtime
-- Bret Sword & Shield damage buff (self-applies at load when wt_brett_sword_shield_buff is ON;
-- mutates the weapon template, so a restart is needed to apply/revert).
mod:dofile("scripts/mods/weapon_tweaker/_wt_brett_sword_shield_buff")

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
    local ok, data = pcall(require, "scripts/mods/weapon_tweaker/weapon_tweaker_data")
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
    -- "no change"). #169: the retired `enable_debug_logging` key receives no
    -- migration write at all; VMF-native logging owns diagnostics
    -- (PROJECT_STANDARDS § 3.6), so touching the key here would itself be a
    -- live executable use of it.
    mod:set("debug", false)
    mod:set("enable_weapon_debug_logging", false)
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
mod:dofile("scripts/mods/weapon_tweaker/_wt_regression")
local _rt_register = mod._wt.rt_register

-- weapon_unlock_map + _cwv_managed are shared by runtime availability owners.
local _wt_unlock_data   = mod:dofile("scripts/mods/weapon_tweaker/wt_unlock_data")
local weapon_unlock_map = _wt_unlock_data.weapon_unlock_map

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
mod:dofile("scripts/mods/weapon_tweaker/_wt_availability")
local apply_weapon_unlocks            = mod._wt.apply_weapon_unlocks
local patch_career_actions_on_weapons = mod._wt.patch_career_actions_on_weapons
local clear_weapon_unlocks            = mod._wt.clear_weapon_unlocks
local clear_career_action_injections  = mod._wt.clear_career_action_injections

mod:dofile("scripts/mods/weapon_tweaker/_wt_trait_pools")
local apply_trait_filters = mod._wt.apply_trait_filters
local revert_trait_pools  = mod._wt.revert_trait_pools

-- issue 611: _data.lua builds the career/slot/source-scoped master widgets and
-- records their exact forward/reverse maps. Install the proven VMF checkbox
-- styling + repaint hooks, then derive every master from its own career's saved
-- children. Cascade and targeted child recompute dispatch below.
local _wt_master_toggles = mod:dofile("scripts/mods/weapon_tweaker/_wt_master_toggles")
_wt_master_toggles.install_refresh_hook(mod)
_wt_master_toggles.seed(mod)

-- Issue #445: one master for the exact active Weapon Tweaks family. The pure
-- policy is also consumed by localization and engine-free QA, preventing the
-- menu, runtime cascade, and authorship labels from drifting apart.
local _wt_rework_master = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_rework_master_policy")
local _wt_rework_master_runtime_module = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_rework_master_runtime")
mod._wt.rework_master_policy = _wt_rework_master

-- Read-only diagnostic dump/probe commands (leaf consumers of game globals;
-- no entry-state dependency and no gameplay mutation).
mod:dofile("scripts/mods/weapon_tweaker/_wt_diagnostics")
-- #661 correctness owner: exact provider identity + effective-template action
-- reconciliation runs before vanilla's local wield transition. Diagnostics is
-- only a leaf callback and cannot disable the invariant.
mod:dofile("scripts/mods/weapon_tweaker/_wt_weapon_action_lifecycle")

-- #341: Bolt Staff's two rapid primary actions exclusively use the `spark`
-- overcharge key. This small module owns the snapshot/apply/revert transaction;
-- no hook and no shared weapon-template mutation are required.
local _wt_bolt_staff_overcharge = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_bolt_staff_overcharge")
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
mod._wt.dbg_alert         = _dbg_alert
mod._wt.build_3p_template_remaps = mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_remap_data")
mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_remap")
-- #536: reload ownership differs from attack remapping, so keep its local-3P
-- replay and receiver-native volley contract in a separate, reload-only module.
mod:dofile("scripts/mods/weapon_tweaker/_wt_reload_3p")
local _safe_has_anim               = mod._wt.safe_has_anim
local _resolve_preview_wield_event = mod._wt.resolve_preview_wield_event
local _unit_career_name            = mod._wt.unit_career_name
local _unit_state                  = mod._wt.unit_state
local _suffix_career_map           = mod._wt.suffix_career_map
local _3p_template_remaps          = mod._wt.three_p_template_remaps
mod._wt.flamestorm_fx_policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_flamestorm_fx_policy")
mod:dofile("scripts/mods/weapon_tweaker/_wt_flamestorm_fx")
-- Cross-character transform owner (#1159). This retains the former registration
-- position and returns the preview-facing functions consumed later in the entry.
local _wt_transform_runtime = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_transform_runtime").install(mod, {
        appearance = _WEAPON_APPEARANCE,
        grip_policy = _wt_grip_offset_policy,
        dbg = _dbg,
    })
local _scale_weapon_units = _wt_transform_runtime.scale_weapon_units
local _resolve_grip_offset = _wt_transform_runtime.resolve_grip_offset
local _offset_weapon_units = _wt_transform_runtime.offset_weapon_units
local _resolve_rotation_override = _wt_transform_runtime.resolve_rotation_override
local _wt569_track_3p_units = _wt_transform_runtime.track_3p_rotation_units
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

-- #201: Deepwood Staff's secondary action spawns the native plague-vortex
-- through WeaponSystem. The weapon units are ordinary Woods DLC inventory
-- assets, but the vortex runtime unit is resident only with the complete
-- Sister of the Thorn career package. Cross-career users do not load that
-- package naturally, so explicitly request it for DLC owners and keep the
-- availability/action boundary closed until it is resident.
local _deepwood_runtime = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_deepwood_runtime").install(mod, {
    package_manager = function() return Managers and Managers.package end,
    unlock_manager = function() return Managers and Managers.unlock end,
    on_residency_changed = function() mod._wt368_deferred_availability = true end,
})
mod._wt.deepwood_runtime = _deepwood_runtime
mod._wt.deepwood_runtime_ready = _deepwood_runtime.ready

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

-- Cross-character base-template 3P patch owner (#1159).
--
-- The five per-weapon source-template patchers (brace, Empire longbow, elf
-- longbow, Moonfire Bow, repeating pistol), the shared wield_anim_career_3p
-- applier, and the not-loaded / no-ammo wield fallback applier moved verbatim
-- to _wt_cross_char_template_patches.lua. Bare dofile at the former execution
-- position: each patcher mutates Weapons.* at file scope, so the load position
-- is what orders those writes against the rebalance rewrites further down.
mod:dofile("scripts/mods/weapon_tweaker/_wt_cross_char_template_patches")
-- Cross-character engine-fatal safety owner (#1159). It remains immediately
-- after template mutation and before custom damage-profile registration.
local _wt_cross_character_safety = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_cross_character_safety").install(mod, {
        dbg = _dbg,
        dbg_alert = _dbg_alert,
    })
local _wt_validate_attachment_sources =
    _wt_cross_character_safety.validate_attachment_sources
-- Toggle-gated weapon rebalance owner (#1159).
--
-- Authentic Brace of Pistols, the issue #348 Kruber Empire 1h sword push-combo
-- revert, and the Warrior Priest punch buff moved verbatim to
-- _wt_weapon_balance_patches.lua. Bare dofile at the former execution position:
-- the two cloned damage profiles append to NetworkLookup.damage_profiles, so
-- this load position is what fixes the index every wt peer has to agree on.
mod:dofile("scripts/mods/weapon_tweaker/_wt_weapon_balance_patches")

-- Moonfire Bow pre-nerf AOE restoration - owner module (#1159).
-- The toggle read, the ExplosionTemplates + NetworkLookup.explosion_templates
-- registration, the recorded wire-safe fallback, the /wt_regression_test check,
-- and the projectile-impact hook loop moved verbatim to _wt_moonfire_aoe.lua.
-- Bare dofile at the former execution position: this must still run after
-- _wt_regression (rt_register) and before the 3P swap dispatch below.
mod:dofile("scripts/mods/weapon_tweaker/_wt_moonfire_aoe")

-- In-game 3P weapon-mesh swap owner (#1159).
--
-- The consolidated GearUtils.spawn_inventory_unit dispatch, its inline
-- brace -> repeating-handgun body, and the three per-weapon swap helpers
-- (Saltzpyre longbow -> crossbow, Kruber repeating pistols -> repeating
-- handgun, #181 Skullsplitter & Tome -> 1H Skullsplitter) moved verbatim to
-- _wt_ingame_3p_swap_owner.lua. Bare dofile at the former execution position:
-- the dispatch has to register after the balance and Moonfire owners above
-- (both append to NetworkLookup at load) and before the preview owner below,
-- and it is the one spawn_inventory_unit registration VMF will accept.
mod._wt.is_sp_crossbow_presentation_item = _is_sp_crossbow_presentation_item
mod._wt.brace_repeater_3p_unit           = _BRACE_REPEATER_3P_UNIT
mod._wt.sp_crossbow_3p_unit              = _SP_CROSSBOW_3P_UNIT
mod._wt.sp_crossbow_bolt_3p_unit         = _SP_CROSSBOW_BOLT_3P_UNIT
mod._wt.skullsplitter_hand_policy        = _wt_skullsplitter_hand_policy
mod:dofile("scripts/mods/weapon_tweaker/_wt_ingame_3p_swap_owner")

-- Menu/inventory preview surface owner (#1159).
--
-- The consolidated MenuWorldPreviewer.equip_item hook_safe with its four
-- preview swap helpers, the weak-keyed preview item-key capture, the #603
-- Ranger stance selector, the _wt_paired_preview_transform install, and the
-- full MenuWorldPreviewer._spawn_item_unit wrapper moved verbatim to
-- _wt_menu_preview_owner.lua. Bare dofile at the former execution position:
-- both previewer registrations have to land here, after the in-game 3P swap
-- owner above and before the lifecycle callbacks below.
mod._wt.validate_attachment_sources = _wt_validate_attachment_sources
mod._wt.scale_weapon_units          = _scale_weapon_units
mod._wt.resolve_grip_offset         = _resolve_grip_offset
mod._wt.offset_weapon_units         = _offset_weapon_units
mod._wt.resolve_rotation_override   = _resolve_rotation_override
mod._wt.track_3p_rotation_units     = _wt569_track_3p_units
mod._wt.grip_offset_policy          = _wt_grip_offset_policy
mod:dofile("scripts/mods/weapon_tweaker/_wt_menu_preview_owner")

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
    mod._force_load_deepwood_runtime_package(true)
    apply_weapon_unlocks()
    -- #368: CWV registers clone definitions from its own state-enter callback.
    -- Reconcile once more on the following frame so WT is the deterministic
    -- final can_wield writer regardless of VMF callback ordering.
    mod._wt368_deferred_availability = true
    patch_career_actions_on_weapons()
    apply_trait_filters()
    if mod._wt_reconcile_history_owner_stack then
        mod._wt_reconcile_history_owner_stack("game_state")
    elseif mod._wt_apply_axe_balance then
        mod._wt_apply_axe_balance(nil, false)
    end
    if mod._wt_apply_fire_sword then mod._wt_apply_fire_sword(nil, false) end
    if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
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
    if weapon_backend.overcharge_presentation then pcall(weapon_backend.overcharge_presentation.restore) end
    _wt_bolt_staff_overcharge_runtime.revert()
    _wt_history_owner:restore()
    if mod._wt_apply_fire_sword then mod._wt_apply_fire_sword(nil, true) end
    if mod._wt374_revert_energy_data then mod._wt374_revert_energy_data() end
    clear_weapon_unlocks()
    clear_career_action_injections()
    revert_trait_pools()
    mod:info("Weapon Tweaker disabled — cross-career unlocks, ability action injections, and trait-pool filters reverted")
end

local _wt_rework_runtime = _wt_rework_master_runtime_module.new(
    mod, _wt_rework_master, function()
        if mod.wt_apply_priest_punch_buff then mod.wt_apply_priest_punch_buff() end
        if mod.wt_apply_brett_buff then mod.wt_apply_brett_buff() end
        _wt_bolt_staff_overcharge_runtime.apply()
        if mod._wt_apply_axe_balance then mod._wt_apply_axe_balance(nil, false) end
        if mod._wt_apply_fire_sword then mod._wt_apply_fire_sword(nil, false) end
    end)
mod._wt.rework_master_runtime = _wt_rework_runtime

mod:dofile("scripts/mods/weapon_tweaker/_wt_settings_runtime").install({
    mod = mod, rework_runtime = _wt_rework_runtime,
    master_toggles = _wt_master_toggles, backend = weapon_backend,
    apply_weapon_unlocks = apply_weapon_unlocks,
    patch_career_actions = patch_career_actions_on_weapons,
    apply_trait_filters = apply_trait_filters,
    bolt_policy = _wt_bolt_staff_overcharge,
    bolt_runtime = _wt_bolt_staff_overcharge_runtime,
    balance_policy = _wt_axe_balance_policy,
    fire_sword_policy = _wt_fire_sword_policy,
    history_runtime = _wt_history_runtime,
})

-- The #601/#621/#622/#623/#664 balance adapter (mod._wt_apply_axe_balance) is
-- owned by _wt_axe_balance.lua. Installed HERE rather than at its manifest
-- dofile above because install applies once, and that first apply must have
-- registered every generated custom damage profile into NetworkLookup before
-- the #431 parity beacon below reads the catalog.
_wt_axe_balance_policy.install(mod)

-- ============================================================
-- Issue 943: Fire Sword heavy-attack projections
-- ============================================================
-- The bounded apply seam (mod._wt_apply_fire_sword) is owned by
-- _wt_fire_sword.lua; installing here keeps the load-time apply at the exact
-- manifest position the adapter used to occupy.
_wt_fire_sword_policy.install(mod)

-- ============================================================
-- Issue 431: exact peer-catalog gate + unconditional wire floor
-- ============================================================
-- Load only after every custom-profile family above has registered its full,
-- toggle-independent fallback catalog. Presence alone cannot prove that the
-- process-local NetworkLookup.damage_profiles integers match (BUG_CLASSES 64).
-- This still precedes weapon_backend.install, whose mod.update assignment
-- chains the parity/runtime-gate drivers installed by this module.
mod:dofile("scripts/mods/weapon_tweaker/_wt431_damage_profile_parity")

-- Normalize a stale master flag from an older/custom settings file without
-- mutating any leaf. Programmatic write is non-notifying and bounded to one.
_wt_rework_runtime:sync()

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
local _wt_runtime_checks = mod:dofile("scripts/mods/weapon_tweaker/_wt_runtime_checks")
local _wt_runtime_check_deps = {
    unit_state = _unit_state,
    weapon_unlock_map = weapon_unlock_map,
    three_p_template_remaps = _3p_template_remaps,
    post_spawn_preview_event = mod._wt.post_spawn_preview_event,
    wield_anim_career_patches = mod._wt.wield_anim_career_patches,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    master_toggles = _wt_master_toggles,
    wield_patches_module = mod._wt.wield_patches_module,
    is_sp_crossbow_presentation_item = _is_sp_crossbow_presentation_item,
    grip_offset_policy = _wt_grip_offset_policy,
    skullsplitter_hand_policy = _wt_skullsplitter_hand_policy,
    weapon_backend = weapon_backend,
    deepwood_runtime = _deepwood_runtime,
    fire_sword_policy = _wt_fire_sword_policy,
}
_wt_runtime_checks.install(mod, _rt_register, _wt_runtime_check_deps)
_rt_register("issue1436_historical_weapon_patch_versions", function()
    if not _wt_history_runtime then
        return "#1436: historical weapon runtime was not installed"
    end
    return _wt_history_runtime:verify()
end)
-- WT_PUBLIC_OVERLAY_BEGIN:public-beta-surface-regression
_rt_register("issue635_public_beta_dev_surface_absent", function()
    local wt = mod._wt or {}
    if wt.dev_anim_picker ~= nil then return "dev animation picker exported in public beta" end
    if wt.dev_hold_pose ~= nil then return "dev Hold-Pose tuner exported in public beta" end
    if wt.port_status ~= nil then return "dev port-status owner exported in public beta" end
end)
-- WT_PUBLIC_OVERLAY_END:public-beta-surface-regression

mod:info("[mem-probe] wt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_WT) / 1024)
