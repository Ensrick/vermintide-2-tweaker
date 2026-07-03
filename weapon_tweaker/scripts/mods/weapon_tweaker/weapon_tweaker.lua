--[[
weapon_tweaker — cross-career weapon unlocks, animation remapping, and visual tweaks.

Major sections (search by name to jump):
  * weapon_unlock_map / apply_weapon_unlocks       — which careers can wield which weapons
  * patch_career_actions_on_weapons                — keep career abilities working on cross-career weapons
  * _anim_redirect / _career_anim_redirect / _unit_state
                                                   — three-layer animation system + per-unit remap state
                                                     (see DEVELOPMENT.md, feedback_animation_remap_rules)
  * _suffix_career_map / _try_suffix_redirect      — suffix-based event swaps (e.g. *_2h_billhook)
  * _weapon_scale_overrides / _weapon_grip_offsets — per-career scale & grip-position tweaks
  * 3P state-machine probe / dump_actions / animlog — debug commands
  * Lifecycle: on_game_state_changed (re-applies unlocks per state), on_setting_changed,
                on_disabled (strip-only revert).

Key conventions (also in CLAUDE.md):
  * NEVER hook BackendUtils.can_wield_item — modify ItemMasterList[*].can_wield directly.
  * rawget(ItemMasterList, k) when k might not exist (DLC ownership, save-data drift).
  * Lua 5.1 — locals are not hoisted; verify forward references before using a name.
]]

local mod = get_mod("wt")

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

-- ============================================================
-- BIG REBALANCE — ON ICE (v0.12.122-dev, 2026-06-18)
-- ============================================================
-- The entire Big Rebalance integration is mothballed. bt (buff_tweaker) was
-- retired 2026-06-08, so BR's _master() gate has been permanently false — BR
-- did NOTHING — yet weapon_tweaker_big_rebalance.lua + _big_rebalance_defs.lua
-- still loaded their full payload (DamageProfile / Explosion / Buff defs + the
-- ~2600-line hook installers) into the hard 1 GiB lua_heap at boot, contributing
-- to the lua_heap OOM crashes. We stop loading them entirely. To UN-ICE: restore
-- bt, then un-comment the dofile line below and delete the `if true then return`
-- guard banners at the top of the two BR module files. (Reversal is purely
-- un-commenting; both BR files are still shipped in the bundle, just dormant.)
-- local big_rebalance = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance")  -- BR ON ICE
local big_rebalance = { apply_all = function() end }
-- The two true-flight formula helpers were file-scope in the BR module (NOT
-- behind the master gate) purely so wt's /wt_regression_test markers can assert
-- them with BR off. Preserve them on the stub so those tests stay green —
-- gameplay is unchanged: their only callers live in the master-gated trueflight
-- hook, which is never installed once bt is retired.
function mod._wt_tf_projectile_speed(speed, i)
    if i > 1 then return speed * (1 - i * 0.05) end
    return speed
end
function mod._wt_tf_is_extra_shot(i, num_projectiles, num_extra_shots)
    local extra_shots_idx = num_projectiles - (num_extra_shots or 0) + 1
    return extra_shots_idx <= i
end

local MOD_VERSION = "0.12.202-dev"
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
local _wt_dev_anim_picker = mod:dofile("scripts/mods/weapon_tweaker/wt_dev_anim_picker")
local _wt_dev_hold_pose   = mod:dofile("scripts/mods/weapon_tweaker/wt_dev_hold_pose")
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
    -- "no change"). `enable_debug_logging` itself also removed v0.12.176-dev
    -- (diagnostics now route through VMF channels — see CHANGELOG).
    mod:set("debug", false)
    mod:set("enable_weapon_debug_logging", false)
    mod:set("enable_debug_logging", false)
    mod:set("wt_debug_migration_v1", true)
end
_migrate_legacy_debug_setting()

-- /regression_test scaffold. Registrations live at end of file so they can
-- reference the file-local state tables (`_unit_state`, `weapon_unlock_map`,
-- etc.).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("wt_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail, skip = 0, 0, 0
    mod:echo("=== wt regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
            -- v0.12.117 (Issue #74): tests return "skip: <reason>" when their
            -- preconditions (game tables, sibling mods) aren't loaded; that's
            -- neither PASS nor FAIL and must not pollute the failure count.
            mod:echo("  SKIP: %s -- %s", c.name, err); skip = skip + 1
            mod:info("[regression] SKIP %s: %s", c.name, err)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
end)
mod:info("[regression-test-command] registered as /wt_regression_test")

-- v0.12.99-dev: weapon_unlock_map + _cwv_managed extracted to wt_unlock_data.lua
-- so wt_dev_anim_picker.lua can dofile the same source without depending on
-- VMF's main-script-vs-data load order. (v0.12.98-dev had the picker reading
-- `mod._weapon_unlock_map`, which was nil at _data.lua time because VMF runs
-- _data.lua before main wt.lua finishes — load order is a VMF invariant.)
local _wt_unlock_data   = mod:dofile("scripts/mods/weapon_tweaker/wt_unlock_data")
local weapon_unlock_map = _wt_unlock_data.weapon_unlock_map

-- CLARIFY: career_weapon_variants ("CWV") publishes its own custom items for
-- these (career, weapon) pairs. When CWV is installed, weapon_tweaker SKIPS
-- adding those careers to `can_wield` for the listed weapons (and the matching
-- widgets are stripped in _data.lua) so the two mods don't compete for the
-- same can_wield slot.
-- v0.12.99-dev: also from wt_unlock_data.lua (shared source of truth — see
-- the unlock_data dofile above).
local _cwv_managed = _wt_unlock_data.cwv_managed

-- v0.12.57-dev: pairs removed from `weapon_unlock_map`. Users who had the
-- corresponding `unlock_es_*_<weapon>` toggle = true before the removal will
-- have the career still in the weapon's `item.can_wield` list. The regular
-- strip-rebuild walk inside `apply_weapon_unlocks` only iterates pairs that
-- ARE in the map, so a removed pair would leak the can_wield entry forever.
-- This list keeps a one-shot cleanup invariant: every init pass strips the
-- removed Kruber careers from these weapons' can_wield, idempotently.
local _kruber_removed_pairs = {
    es_mercenary      = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
    es_huntsman       = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
    es_knight         = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
    es_questingknight = { "wh_1h_axe", "wh_hammer_shield", "dr_shield_hammer" },
}

local function _strip_removed_kruber_unlocks()
    if not ItemMasterList then return end
    for career, weapons in pairs(_kruber_removed_pairs) do
        for _, weapon_key in ipairs(weapons) do
            -- Issue #8 (2026-05-23): defensive `rawget` — `weapon_key` here is
            -- from an internal literal table so a strict-metatable Crashify is
            -- unreachable today, but the convention is to never index
            -- ItemMasterList with a non-literal key. Cheap, future-proof.
            local item = rawget(ItemMasterList, weapon_key)
            if item and item.can_wield then
                for i = #item.can_wield, 1, -1 do
                    if item.can_wield[i] == career then
                        table.remove(item.can_wield, i)
                    end
                end
            end
        end
    end
end

local function feature_enabled(setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then return default_value ~= false end
    return value == true
end

-- CLARIFY: The strip-then-add pattern is required because this runs on
-- on_setting_changed too — toggling a checkbox off must REMOVE the career
-- from can_wield, not just leave it. Direct-modifying ItemMasterList is the
-- ONLY way (BackendUtils.can_wield_item is unhookable from split mods —
-- see DEVELOPMENT.md "Don't hook BackendUtils.can_wield_item").
local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Drop stale can_wield entries for pairs removed from `weapon_unlock_map`
    -- since the last release. Idempotent — runs every init + on_setting_changed.
    _strip_removed_kruber_unlocks()

    local has_cwv = get_mod("character_weapon_variants") ~= nil

    -- Strip all mod-managed careers from can_wield
    for career, weapons in pairs(weapon_unlock_map) do
        local cwv_skip = has_cwv and _cwv_managed[career]
        for _, weapon_key in ipairs(weapons) do
            if not (cwv_skip and cwv_skip[weapon_key]) then
                local item = rawget(ItemMasterList, weapon_key)
                if item and item.can_wield then
                    for i = #item.can_wield, 1, -1 do
                        if item.can_wield[i] == career then
                            table.remove(item.can_wield, i)
                        end
                    end
                end
            end
        end
    end

    -- Add back only enabled ones
    for career, weapons in pairs(weapon_unlock_map) do
        local cwv_skip = has_cwv and _cwv_managed[career]
        for _, weapon_key in ipairs(weapons) do
            if not (cwv_skip and cwv_skip[weapon_key]) then
                if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                    local item = rawget(ItemMasterList, weapon_key)
                    if item then
                        if not item.can_wield then item.can_wield = {} end
                        local already = false
                        for _, value in ipairs(item.can_wield) do
                            if value == career then already = true; break end
                        end
                        if not already then
                            item.can_wield[#item.can_wield + 1] = career
                        end
                    end
                end
            end
        end
    end
end

-- CLARIFY: tracks which (template, action_name) entries were injected by
-- patch_career_actions_on_weapons so subsequent calls (on setting change) can
-- back them out before re-applying. Without this, toggling settings would
-- accumulate stale ability-action entries on weapon templates.
local _career_action_injections = {}

-- CLARIFY: when a cross-career weapon is unlocked, that weapon's template
-- needs the unlocking career's ABILITY action (e.g. Foot Knight's shoulder
-- charge) so the ability still works while wielding the unlocked weapon.
-- Without this patch, activating the career ability on a cross-career weapon
-- silently does nothing because the action isn't on that template.
local function patch_career_actions_on_weapons()
    if not Weapons or not CareerSettings or not ActionTemplates or not ItemMasterList then return end

    for tmpl_key, actions in pairs(_career_action_injections) do
        local tmpl = Weapons[tmpl_key]
        if tmpl and tmpl.actions then
            for action_name in pairs(actions) do
                tmpl.actions[action_name] = nil
            end
        end
    end
    _career_action_injections = {}

    for career, weapons in pairs(weapon_unlock_map) do
        local cs = CareerSettings[career]
        if cs then
            local ability_list = cs.activated_ability
            local ability = ability_list and ability_list[1]
            local action_name = ability and ability.action_name
            local action_template = action_name and ActionTemplates[action_name]
            if action_template then
                for _, weapon_key in ipairs(weapons) do
                    if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                        local item = rawget(ItemMasterList, weapon_key)
                        local tmpl_key = item and item.template
                        local tmpl = tmpl_key and Weapons[tmpl_key]
                        if tmpl and tmpl.actions and not tmpl.actions[action_name] then
                            tmpl.actions[action_name] = action_template
                            _career_action_injections[tmpl_key] = _career_action_injections[tmpl_key] or {}
                            _career_action_injections[tmpl_key][action_name] = true
                        end
                    end
                end
            end
        end
    end
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

local _anim_redirect = {
    to_repeating_crossbow            = "to_repeating_crossbow_elf",
    to_repeating_crossbow_noammo     = "to_repeating_crossbow_elf_noammo",
    to_es_longbow                    = "to_longbow",
    to_es_longbow_noammo             = "to_longbow_noammo",
    attack_swing_down_left_axe       = "attack_swing_down_left",
    push_stab                        = "attack_swing_stab",
    attack_swing_stab_lh             = "attack_swing_stab",
}

-- Career-aware redirects for events that are phantom entries on all skeletons.
-- Key = event to intercept, value = { alt, character_prefix }
-- When the career does NOT match the prefix, redirect to alt.
-- CLARIFY: `invert = true` flips the rule — redirect when the career DOES match
-- the prefix (used when the native skeleton lacks the wield event despite being
-- "this character's weapon", e.g. Saltzpyre's `to_1h_falchion` is missing on
-- the WHC skeleton itself, so we need to redirect ON wh_priest career).
-- `overrides` is a per-career-name (not prefix) override that takes precedence
-- over both the prefix rule and `alt`.
local _career_anim_redirect = {
    to_longbow                       = { alt = "to_es_longbow",                 prefix = "we_" },
    to_longbow_noammo                = { alt = "to_es_longbow_noammo",          prefix = "we_" },
    to_repeating_crossbow_elf        = { alt = "to_repeating_crossbow",         prefix = "we_" },
    to_repeating_crossbow_elf_noammo = { alt = "to_repeating_crossbow_noammo",  prefix = "we_" },
    -- Note: `wh_priest` here is a full career name acting as a prefix; safe
    -- because no other `wh_*` career shares its first 9 chars.
    to_1h_falchion                   = { alt = "to_1h_hammer",                  prefix = "wh_priest", invert = true },
    to_1h_sword                      = { alt = "to_1h_hammer",                  prefix = "wh_priest", invert = true },
    to_1h_axe                        = { alt = "to_1h_sword",                   prefix = "bw_", invert = true,
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_crowbill                   = { alt = "to_1h_sword",                   prefix = "bw_",
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_hammer                     = { alt = "to_1h_sword",                   prefix = "we_", invert = true },
    to_1h_hammer_shield_priest       = { alt = "to_1h_hammer_shield",           prefix = "wh_priest" },
    to_1h_spear_shield               = { alt = "to_es_deus_01",                 prefix = "we_",
                                         overrides = { wh_priest = "to_1h_hammer_shield" } },
    to_es_deus_01                    = { alt = "to_1h_spear_shield",           prefix = "es_",
                                         overrides = { wh_priest = "to_1h_hammer_shield" } },
    to_spear                         = { alt = "to_polearm",                   prefix = "we_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    to_polearm                       = { alt = "to_spear",                     prefix = "es_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    -- QUESTION: `prefix = "wh_"` here means "redirect when career does NOT
    -- start with wh_". But ALL non-wh careers have explicit `overrides` entries
    -- below, so the `alt = "to_polearm"` fallback only triggers for careers
    -- not listed (none currently). The `alt` is effectively dead — every
    -- non-wh career maps via overrides. Intentional defensive default, or
    -- just leftover?
    to_2h_billhook                   = { alt = "to_polearm",                   prefix = "wh_",
                                         overrides = { es_mercenary = "to_polearm", es_huntsman = "to_polearm", es_knight = "to_polearm", es_questingknight = "to_polearm",
                                                       we_waywatcher = "to_spear", we_maidenguard = "to_spear", we_shade = "to_spear", we_thornsister = "to_spear",
                                                       wh_priest = "to_1h_hammer" } },
    to_2h_sword                      = { alt = "to_2h_sword_we",                prefix = "we_", invert = true },
    to_2h_sword_we                   = { alt = "to_bastard_sword",              prefix = "we_",
                                         overrides = { wh_priest = "to_1h_hammer",
                                                       wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" } },
    to_dual_hammers_priest           = { alt = "to_dual_hammers",               prefix = "wh_" },
    to_dual_axes                     = { alt = "to_dual_hammers",               prefix = "dr_slayer" },
    -- v0.12.119: Sienna's Flaming Flail (bw_1h_flail_flaming) wield on non-bw
    -- receivers — DECISIONS:36 flagged the missing wield redirect as the cause
    -- of the broken wield stance (the H2 attack redirect in the flail block
    -- already existed; the wield event did not). `to_1h_flail` is the universal
    -- Empire-flail wield that already works on every character via es_1h_flail.
    to_1h_flail_flaming              = { alt = "to_1h_flail",                   prefix = "bw_",
                                         overrides = { wh_priest = "to_1h_hammer" } },
}

-- Suffix-based animation redirect: when an event ending in a weapon suffix
-- doesn't exist on the skeleton, swap the suffix based on career.
-- Checked longest-first to avoid e.g. "_spear" matching "_2h_heavy_spear".
-- CLARIFY: order matters because `event_name:sub(-#suffix) == suffix` is a
-- substring match — without longest-first, `to_es_deus_01` would match
-- `_es_deus_01` correctly but `to_1h_spear_shield` would match `_spear` first
-- (both 6 chars from end onwards differ but the shorter match wins by order).
local _suffix_order = { "_2h_sword_we", "_bastard_sword", "_1h_spear_shield", "_es_deus_01", "_2h_billhook", "_polearm", "_spear" }
local _suffix_career_map = {
    ["_2h_sword_we"] = {
        es_mercenary = "_bastard_sword", es_huntsman = "_bastard_sword", es_knight = "_bastard_sword", es_questingknight = "_bastard_sword",
        wh_captain = "_1h_sword", wh_bountyhunter = "_1h_sword", wh_zealot = "_1h_sword",
        wh_priest = "_1h_hammer",
    },
    ["_1h_spear_shield"] = {
        es_mercenary = "_es_deus_01", es_huntsman = "_es_deus_01", es_knight = "_es_deus_01", es_questingknight = "_es_deus_01",
        dr_ranger = "_1h_hammer_shield", dr_ironbreaker = "_1h_hammer_shield", dr_slayer = "_1h_hammer_shield", dr_engineer = "_1h_hammer_shield",
        wh_captain = "_1h_sword_shield", wh_bountyhunter = "_1h_sword_shield", wh_zealot = "_1h_sword_shield",
        wh_priest = "_1h_hammer_shield",
    },
    ["_es_deus_01"] = {
        we_waywatcher = "_1h_spear_shield", we_maidenguard = "_1h_spear_shield", we_shade = "_1h_spear_shield", we_thornsister = "_1h_spear_shield",
        wh_captain = "_1h_sword_shield", wh_bountyhunter = "_1h_sword_shield", wh_zealot = "_1h_sword_shield",
        wh_priest = "_1h_hammer_shield",
    },
    ["_spear"] = {
        wh_captain = "_2h_billhook", wh_bountyhunter = "_2h_billhook", wh_zealot = "_2h_billhook",
        wh_priest = "_1h_hammer",
    },
    ["_polearm"] = {
        we_waywatcher = "_spear", we_maidenguard = "_spear", we_shade = "_spear", we_thornsister = "_spear",
        wh_captain = "_2h_billhook", wh_bountyhunter = "_2h_billhook", wh_zealot = "_2h_billhook",
        wh_priest = "_1h_hammer",
    },
    ["_2h_billhook"] = {
        es_mercenary = "_polearm", es_huntsman = "_polearm", es_knight = "_polearm", es_questingknight = "_polearm",
        we_waywatcher = "_spear", we_maidenguard = "_spear", we_shade = "_spear", we_thornsister = "_spear",
        wh_priest = "_1h_hammer",
    },
}

-- pcall-guarded `Unit.has_animation_event`. Returns true only if the unit has
-- the named anim event. Used by every redirect/remap helper below — defined
-- BEFORE _try_suffix_redirect to avoid the forward-reference trap that bit
-- this codebase 5+ times (see feedback_lua_forward_reference.md).
local function _safe_has_anim(unit, event)
    local ok, result = pcall(Unit.has_animation_event, unit, event)
    return ok and result
end

local function _try_suffix_redirect(unit, event_name, career)
    for _, suffix in ipairs(_suffix_order) do
        local slen = #suffix
        if event_name:sub(-slen) == suffix then
            local map = _suffix_career_map[suffix]
            local target_suffix = map and map[career]
            if target_suffix then
                local base = event_name:sub(1, -(slen + 1))
                local target = base .. target_suffix
                if _safe_has_anim(unit, target) then
                    return target
                end
            end
            return nil
        end
    end
    return nil
end

-- ============================================================================
-- INVENTORY-PREVIEW WIELD POSE (3P-ONLY) — receiver-native stance correction
-- ============================================================================
-- v0.12.146-dev. The keep inventory previewer (MenuWorldPreviewer, derived
-- from HeroPreviewer) fires the wield anim on the 3P body directly at spawn:
--   wield = wield_anim_career_3p[career] or wield_anim_career[career]
--                                        or item_template.wield_anim
-- (world_hero_previewer.lua:1059-1066). It does NOT route that event through
-- our `Unit.animation_event` hook's `_career_anim_redirect` path, because the
-- preview `character_unit` has NO career_system / inventory_system extension —
-- so `_unit_career_name(unit)` returns nil in the hook and the redirect is a
-- no-op there (gated on a resolved career at line ~1544).
--
-- For cross-character ports whose `wt_wield_patches.lua` entry omits the
-- receiver's career prefix (e.g. `two_handed_swords_wood_elf_template` lists
-- only `wh_*`, so on a Kruber `es_*` career `wield_anim_career_3p[es_*]` is
-- nil), the previewer falls back to the elf template's base
-- `wield_anim = "to_2h_sword_we"` and fires it on Kruber's empire_soldier body,
-- which does not author that elf event -> no wield transition -> the body holds
-- its previous/idle stance (the "missing pose" symptom; no T-pose, see
-- feedback_vt2_no_tpose_default_stance). In-mission the same event is redirected
-- by `_career_anim_redirect.to_2h_sword_we` (alt = "to_bastard_sword" for the
-- non-we_ branch), which is why the mission render is correct.
--
-- This resolver re-uses the SAME `_career_anim_redirect` data the in-mission
-- hook uses (no parallel pose table) to compute the receiver-native wield event
-- for one (event, career) pair, WITHOUT firing. The spawn hook below then plays
-- it on the 3P preview body only if (a) it differs from what the engine already
-- fired and (b) the body actually authors it. Strictly 3P: the preview world has
-- no 1P unit, and we touch only `self.character_unit`.
--
-- Resolution mirrors the `_career_anim_redirect` branch in the animation_event
-- hook (overrides -> prefix/invert -> alt), then a suffix-redirect fallback:
local function _resolve_preview_wield_event(body, event_name, career)
    if not event_name or not career then return nil end
    local redir = _career_anim_redirect[event_name]
    if redir then
        if redir.overrides and redir.overrides[career]
                and _safe_has_anim(body, redir.overrides[career]) then
            return redir.overrides[career]
        end
        local matches_prefix = career:sub(1, #redir.prefix) == redir.prefix
        local should_redirect = redir.invert and matches_prefix
                                or (not redir.invert and not matches_prefix)
        if should_redirect and _safe_has_anim(body, redir.alt) then
            return redir.alt
        end
        return nil
    end
    -- Suffix-based fallback (e.g. *_2h_billhook -> *_polearm) for events not
    -- listed in _career_anim_redirect. _try_suffix_redirect already verifies the
    -- target is authored on the body before returning it.
    return _try_suffix_redirect(body, event_name, career)
end

-- ============================================================================
-- ANIMATION REMAPPING — READ FIRST
-- ============================================================================
-- 1P (first-person) animations are UNIVERSAL across all six characters and
-- all weapons. The first_person_base unit is shared, so any weapon's 1P state
-- machine and clips play correctly on any character's first-person view by
-- default. We never override anim_event (1P), wield_anim (1P), or
-- state_machine per character — only 3P fields need cross-character work.
--
-- Every remap table and every redirect in this file targets the 3P body
-- (player_unit + husks). The 1P first_person_unit gets an early return in the
-- animation_event hook so it stays untouched. See feedback_animation_remap_rules
-- and feedback_1p_animations_universal memory notes for the full rule.
--
-- When a remap table key looks like a 1P event name (e.g.
-- "attack_swing_charge_stab" — authored for the elf spear's 1P state machine),
-- it's there because the SAME event-name string also fires on the 3P body
-- where the empire-soldier skeleton has no clip for it. The remap value is the
-- 3P-body substitute. The 1P side fires the unmodified event and plays
-- correctly on first_person_base — we don't touch it.
-- ============================================================================

-- 3P body event remapping: player_unit IS the 3P body (receives anim_event_3p).
-- The non-player unit is the 1P hands (receives anim_event) — universal,
-- never remapped here.
-- When a cross-career weapon is equipped, remap attack events on player_unit
-- to the target weapon's anim_event_3p values so proper 3P animations play.

-- Elf spear actions → billhook 3P events (for Saltzpyre wielding elf spear)
local _3p_remap_spear_to_billhook = {
    attack_swing_charge_right    = "attack_swing_charge_left_diagonal",
    attack_swing_charge_left     = "attack_swing_stab_charge",
    attack_swing_down_right      = "attack_swing_stab",
    attack_swing_down_left_axe   = "attack_swing_left_diagonal",
    attack_swing_down_left       = "attack_swing_stab",
    attack_swing_right           = "attack_swing_left_diagonal",
    attack_swing_heavy_right     = "attack_swing_heavy_left_diagonal",
    attack_swing_heavy           = "attack_swing_heavy_stab",
    push_stab                    = "attack_swing_left_diagonal",
    attack_swing_stab_lh         = "attack_swing_stab",
    attack_swing_charge          = "attack_swing_stab_charge",
    attack_swing_charge_stab     = "attack_swing_charge_left_diagonal",
}

-- Polearm/heavy spear → billhook 3P fixes (for Saltzpyre)
-- Only remap events that are MISSING or broken on billhook skeleton.
-- Leave working events alone — elf spear table remaps interfere if shared.
local _3p_remap_polearm_to_billhook = {
    attack_swing_stab_lh         = "attack_swing_stab",
}

-- Elf spear 1P actions → Kruber polearm-compatible 3P events.
-- Only remap events that genuinely crash or don't exist on the
-- polearm skeleton. Let others play natively.
local _3p_remap_spear_to_polearm = {
    attack_swing_down_left_axe   = "attack_swing_down_left",
    attack_swing_left            = "attack_swing_down_left",
}

-- Billhook 1P events → polearm-compatible 3P events.
-- Cross-career equip sends the 1P anim_event (not anim_event_3p) to
-- both units. These billhook-specific events are phantom on the polearm
-- skeleton. Remap lights → lights, heavies → heavies, charges → charges.
local _3p_remap_billhook_to_polearm = {
    -- Heavy 1 (thrust): charge + release
    attack_swing_charge_stab         = "attack_swing_charge_right",
    attack_swing_stab_charge         = "attack_swing_charge_right",
    attack_swing_heavy_stab          = "attack_swing_heavy_right",
    -- Heavy 2 (overhead): charge + release
    attack_swing_charge_down         = "attack_swing_charge",
    attack_swing_charge_left_diagonal = "attack_swing_charge",
    attack_swing_heavy_down          = "attack_swing_heavy",
    attack_swing_heavy_left_diagonal = "attack_swing_heavy",
    -- Lights
    attack_swing_left_diagonal       = "attack_swing_down_left",
    attack_swing_stab                = "attack_swing_right",
    attack_swing_stab_02             = "attack_swing_right",
    attack_swing_heavy_left          = "attack_swing_heavy",
    attack_swing_down                = "attack_swing_down_right",
    push_stab                        = "attack_swing_right",
    attack_swing_left                = "attack_swing_down_left",
}

local _3p_remap_spear_shield_to_deus = {
    attack_swing_stab_lh             = "attack_swing_stab",
}

local _3p_remap_deus_to_spear_shield = {
    attack_swing_up                  = "attack_swing_stab_lh",
}

-- Career-aware remap triggers: event → { career_prefix = remap_table, ... }
-- "_default" key used when no career-specific entry matches.
local _3p_remap_triggers = {
    to_spear = {
        _default = _3p_remap_spear_to_polearm,
        wh_      = _3p_remap_spear_to_billhook,
        -- Kerillian's elf skeleton authors the spear moveset natively; the
        -- _default remap was built for Kruber's polearm skeleton and breaks
        -- her down_left / left attacks if applied. Mirrors the wh_ = false
        -- pattern on to_2h_billhook below.
        we_      = false,
    },
    to_polearm = {
        _default = _3p_remap_billhook_to_polearm,
        es_      = _3p_remap_spear_to_polearm,
        wh_      = _3p_remap_spear_to_billhook,
    },
    to_2h_billhook = {
        _default = _3p_remap_billhook_to_polearm,
        wh_      = false,
    },
    to_1h_spear_shield = {
        _default = _3p_remap_spear_shield_to_deus,
    },
    to_es_deus_01 = {
        _default = _3p_remap_spear_shield_to_deus,
        we_      = _3p_remap_deus_to_spear_shield,
    },
}

-- CLARIFY: returns either a remap table (truthy) or `false` (a deliberate
-- "no remap" entry like `to_2h_billhook.wh_ = false`). Caller stores the
-- result on the per-unit state (see `_unit_state` below) — `false` correctly
-- clears any prior remap; only `nil` (no entry at all) preserves prior state.
local function _resolve_3p_remap(event_name, career)
    local trigger = _3p_remap_triggers[event_name]
    if not trigger then return nil end
    if not career then return trigger._default end
    for prefix, tbl in pairs(trigger) do
        if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
            return tbl
        end
    end
    return trigger._default
end

-- Per-unit 3P animation state, keyed by the 3P body unit (player_unit for
-- the local player, husk units for remote players). Weak-keyed so dead units
-- release automatically.
--
-- v0.12.35 — replaces the prior single-global pattern, which only tracked the
-- LOCAL player's weapon. With one global, the animation_event hook applied
-- the local viewer's remap to every 3P body it saw, so remote players' cross-
-- career weapons rendered with wrong/missing 3P anims unless the host happened
-- to be holding the same weapon on the same career.
--
-- Each entry tracks:
--   template      = item_data.template at last wield
--   key           = item_data.key at last wield
--   remap         = currently active _3p_*_remap table (or `false` for a
--                   deliberate "no remap" from _3p_remap_triggers.X.we_ = false)
--   last_remap_id = snapshot of (template or key) at the moment the remap was
--                   selected — used to skip clear-and-reset for non-weapon `to_`
--                   events (to_crouch / to_zoom / to_onground)
local _unit_state = setmetatable({}, { __mode = "k" })

local function _state_for(unit)
    if not unit then return nil end
    local s = _unit_state[unit]
    if not s then
        s = { template = nil, key = nil, remap = nil, last_remap_id = nil }
        _unit_state[unit] = s
    end
    return s
end

-- Template-based 3P attack remaps: when a cross-career weapon shares a wield
-- event with a different native weapon, attack events may lack valid transitions
-- in the target skeleton's 3P state machine. Remap to compatible events.
-- Key: weapon template name. Value: { career_prefix = remap_table, ... }
-- A nil value for a prefix means no remap needed (native character).
local _3p_template_remaps = {
    two_handed_swords_template_1 = {
        we_ = {
            attack_swing_charge_diagonal       = "attack_swing_charge",
            attack_swing_charge_diagonal_right = "attack_swing_charge",
            attack_swing_charge_diagonal_left  = "attack_swing_charge",
            attack_swing_heavy_left_diagonal   = "attack_swing_left",
            attack_swing_heavy_right_diagonal  = "attack_swing_heavy_right",
            attack_swing_left_diagonal         = "attack_swing_left",
            attack_swing_right_diagonal        = "attack_swing_right",
            attack_swing_down_right            = "attack_swing_heavy",
        },
    },
    two_handed_axes_template_1 = {
        dr_ = false,
        _default = {
            attack_swing_up                   = "attack_swing_left",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        },
    },
    two_handed_swords_wood_elf_template = {
        we_ = false,
        wh_ = {
            attack_swing_charge      = "attack_swing_charge_left_diagonal",
            attack_swing_right       = "attack_swing_right_diagonal",
            attack_swing_left        = "attack_swing_left_diagonal",
            attack_swing_heavy       = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
        },
        _default = {
            attack_swing_charge      = "attack_swing_charge_left_diagonal",
            attack_swing_left        = "attack_swing_up_left",
            attack_swing_heavy       = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
        },
    },
    one_hand_falchion_template_1 = {
        wh_ = false,
        dr_ = {
            -- Bardin: differentiate the two heavy variants
            --   left_diagonal (variant A)        → elf H1 (vertical) — charge fires natively
            --   right_diagonal_pose (variant B)  → elf H2 (right swing)
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_pose",
            attack_swing_heavy_left_diagonal        = "attack_swing_heavy_down",
            attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right",
            attack_swing_up                         = "attack_swing_down",
        },
        _default = {
            attack_swing_charge_left_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_pose",
            attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_pose",
            attack_swing_heavy_left_diagonal        = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right",
            attack_swing_up                         = "attack_swing_down",
        },
    },
    one_handed_crowbill = {
        bw_ = false,
        dr_ = {
            -- Bardin: H1 and H3 release fires events that produce no visible
            -- animation on his crowbill SM. Use the elf-sword overhead targets.
            attack_swing_stab                = "attack_swing_down",
            attack_swing_up_left             = "attack_swing_left_diagonal",
            attack_swing_charge_left         = "attack_swing_charge_left_diagonal", -- H1 charge windup
            attack_swing_heavy_left_up       = "attack_swing_heavy_down",           -- H1 release overhead
            attack_swing_charge_left_pose    = "attack_swing_charge_left_diagonal", -- H3 charge windup
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",           -- H3 release overhead
        },
        _default = {
            -- attack_swing_left fires natively as a right-swing on cross
            -- skeletons (verified via wt force3p on Kruber). Don't remap it —
            -- earlier versions mapped it to attack_swing_down, which collapsed
            -- L2 into L1's vertical and made the first two lights look identical.
            attack_swing_stab          = "attack_swing_down",  -- thrust → vertical (no working thrust event on cross skeleton)
            attack_swing_heavy_left_up = "attack_swing_heavy",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy",
            attack_swing_up_left       = "attack_swing_left_diagonal",
        },
    },
    -- one_handed_flails_flaming_template: no template-level remaps. H1
    -- (attack_swing_charge_down → attack_swing_heavy_down) fires natively as
    -- the correct overhead. H2's broken release (attack_swing_heavy_left) is
    -- handled by the direct-redirect block in the animation_event hook —
    -- table-remap of that event corrupts the SM (same pattern as billhook
    -- attack_swing_stab_02).
    --
    -- Saltzpyre's billhook (wh_2h_billhook) on Kruber. v0.12.102-dev fix for
    -- the wield-event-collision bug class identified during the Kruber-on-
    -- billhook regression triage:
    --   `_WIELD_ANIM_CAREER_3P_PATCHES.two_handed_billhooks_template` rewrites
    --   the wield event to `to_polearm` for es_*. The v0.12.64-dev
    --   `_resolve_3p_remap(event_name, career)` fallback at line ~1287 then
    --   keys on the POST-patch wield event, but `_3p_remap_triggers["to_polearm"]`
    --   defines `es_ = _3p_remap_spear_to_polearm` (authored for the elf-spear
    --   cross-character port). That entry hijacks the billhook lookup and
    --   installs the wrong remap table — billhook source events (e.g.
    --   `attack_swing_charge_stab`, `attack_swing_left_diagonal`, etc., all
    --   listed in `_3p_remap_billhook_to_polearm` at line ~644) get no
    --   substitute and fire raw on Kruber's polearm SM. Adding an explicit
    --   `_3p_template_remaps[two_handed_billhooks_template]` entry routes the
    --   lookup through `_resolve_template_remap` FIRST (line ~1247), which is
    --   keyed unambiguously by template name and short-circuits the ambiguous
    --   wield-event fallback. The wh_ branch is intentionally `false` —
    --   billhook is Saltzpyre-native and needs no remap.
    two_handed_billhooks_template = {
        wh_ = false,
        es_ = _3p_remap_billhook_to_polearm,
    },
    -- ============================================================
    -- v0.12.149-dev: BAKED Kruber 3P picks for 4 natively-owned weapons.
    -- ============================================================
    -- These four ports were tuned via the dev anim picker and CONFIRMED working
    -- on Kruber. The picks are baked here (career-scoped) instead of the picker's
    -- raw shared-template write — see KRUBER_3P_ANIM_DECISIONS.md "BAKED" section.
    --
    -- WHY CAREER-SCOPED, NOT A SHARED `anim_event_3p` WRITE: each template carries
    -- NO authored `anim_event_3p` natively (verified: 2h_picks.lua / dual_wield_axes
    -- .lua / 1h_swords_flaming_spell.lua / 1h_dagger_wizard.lua all have anim_event
    -- only). So weapon_unit_extension.lua:512 (`anim_event_3p or event`) fires the
    -- source `anim_event` string on EVERY wielder's own 3P body at :652. Writing the
    -- shared template's `anim_event_3p` would make Bardin (pickaxe, dual axes) and
    -- Sienna (fire sword, dagger) — the NATIVE owners — fire the Kruber-tuned string
    -- on THEIR skeletons too, breaking the native view. The `es_` remap below
    -- redirects ONLY for Kruber's careers; the owner prefix (`dr_`/`bw_`) is `false`
    -- → _resolve_template_remap returns nil → native owner plays UNTOUCHED. Same
    -- native-owned precedent as two_handed_billhooks_template above (wh_ = false).
    --
    -- 3P-ONLY by construction: consumed at the Unit.animation_event hook (:1513),
    -- whose `unit` is the 3P body (1P hands unit excluded upstream). Remap keys are
    -- the fired event = the template's source `anim_event` (no authored anim_event_3p),
    -- which equals the picker's source-event dump verbatim. Identity entries
    -- (attack_push->attack_push, parry_pose->parry_pose, etc.) are harmless re-fires;
    -- a target absent on Kruber's redirected SM safely falls through (native fires).
    --
    -- Bardin pickaxe (dr_2h_pick) -> Empire Greathammer (wield to_2h_hammer on es_).
    two_handed_picks_template_1 = {
        dr_ = false, -- native (Bardin): untouched
        es_ = {
            attack_push                         = "attack_push",
            attack_swing_charge_left_down       = "attack_swing_charge_left",
            attack_swing_charge_left_down_pose  = "attack_swing_charge",
            attack_swing_charge_right_down      = "attack_swing_charge_right",
            attack_swing_down_left              = "attack_swing_down_left",
            attack_swing_down_left_axe          = "attack_swing_down_left",
            attack_swing_down_right             = "attack_swing_down_right",
            attack_swing_down_right_axe         = "attack_swing_down_right",
            attack_swing_left                   = "attack_swing_left",
            attack_swing_left_diagonal          = "attack_swing_left_diagonal",
            attack_swing_right_diagonal         = "attack_swing_heavy_right",
            parry_pose                          = "parry_pose",
        },
    },
    -- Sienna fire sword (bw_flame_sword) -> Empire 1H Sword (wield to_1h_sword on es_).
    flaming_sword_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                  = "attack_push",
            attack_swing_charge          = "attack_swing_charge_left",
            attack_swing_charge_right    = "attack_swing_charge_right_pose",
            attack_swing_heavy           = "attack_swing_heavy",
            attack_swing_left            = "attack_swing_left_diagonal",
            attack_swing_left_diagonal   = "attack_swing_left_diagonal",
            attack_swing_right_diagonal  = "attack_swing_right_diagonal",
            attack_swing_right_spell     = "attack_swing_right",
            attack_swing_stab            = "attack_swing_down",
            parry_pose                   = "parry_pose",
        },
        -- v0.12.188-dev: Sienna Flaming Sword on SALTZPYRE body -> 1H Falchion
        -- (wh_-scoped redirect). attack_swing_right_spell has no Falchion twin —
        -- mapped to the nearest event per the user's pick.
        wh_ = {
            attack_push                 = "attack_push",
            attack_swing_charge         = "attack_swing_charge_left_diagonal_pose",
            attack_swing_charge_right   = "attack_swing_charge_right_diagonal_pose",
            attack_swing_heavy          = "attack_swing_heavy_left_diagonal",
            attack_swing_left           = "attack_swing_left_diagonal",
            attack_swing_left_diagonal  = "attack_swing_left_diagonal",
            attack_swing_right_diagonal = "attack_swing_right_diagonal",
            attack_swing_right_spell    = "attack_swing_up",
            attack_swing_stab           = "attack_swing_down",
            parry_pose                  = "parry_pose",
        },
    },
    -- Sienna dagger (bw_dagger) -> Empire 1H Sword (wield to_1h_sword on es_).
    one_handed_daggers_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                  = "attack_push",
            attack_swing_charge          = "attack_swing_charge_left",
            attack_swing_charge_left     = "attack_swing_charge_right_pose",
            attack_swing_heavy           = "attack_swing_heavy",
            attack_swing_heavy_right     = "attack_swing_heavy_right",
            attack_swing_left            = "attack_swing_left_diagonal",
            attack_swing_left_diagonal   = "attack_swing_left_diagonal",
            attack_swing_right_diagonal  = "attack_swing_right_diagonal",
            attack_swing_stab            = "attack_swing_down",
            parry_pose                   = "parry_pose",
        },
        -- v0.12.188-dev: Sienna Dagger on SALTZPYRE body -> 1H Falchion
        -- (wh_-scoped redirect).
        wh_ = {
            attack_push                 = "attack_push",
            attack_swing_charge         = "attack_swing_charge_left_diagonal_pose",
            attack_swing_charge_left    = "attack_swing_charge_right_diagonal_pose",
            attack_swing_heavy          = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right    = "attack_swing_heavy_right_diagonal",
            attack_swing_left           = "attack_swing_left_diagonal",
            attack_swing_left_diagonal  = "attack_swing_left_diagonal",
            attack_swing_right_diagonal = "attack_swing_right_diagonal",
            attack_swing_stab           = "attack_swing_heavy_left_diagonal",
            parry_pose                  = "parry_pose",
        },
    },
    -- Bardin's dual axes on non-Slayer careers. The wield event redirect
    -- (to_dual_axes → to_dual_hammers) loads the dual-hammers SM, but the
    -- dual_wield_axes template fires several attack events the dual-hammers
    -- SM doesn't define. Map them to dual-hammers anim_events that play.
    -- Per-career entries (dr_ironbreaker / dr_ranger / dr_engineer); dr_slayer
    -- has no entry so _resolve_template_remap returns nil → native plays.
    dual_wield_axes_template_1 = (function()
        -- Spread dual-axe lights across the 5 distinct dual_hammers light
        -- anim_events (left, down, left_diagonal, up, stab) so each chain
        -- position plays a unique animation. dual_axes L1's native release
        -- (attack_swing_left_diagonal) already plays as dual_hammers L3 swing,
        -- so leave it alone; remap the other 4 light releases onto the
        -- remaining 4 dual_hammers light anim_events.
        local t = {
            attack_swing_charge_diagonal = "attack_swing_charge_left",   -- L3 / H3 charge windup
            attack_swing_heavy_right     = "attack_swing_heavy_right_diagonal", -- H1 release
            attack_swing_heavy           = "attack_swing_heavy_down",    -- H2 release
            -- Lights (each maps to a different dual_hammers light):
            attack_swing_right_diagonal  = "attack_swing_left",          -- L2 release → dual_hammers L1
            attack_swing_left            = "attack_swing_down",          -- L3 release → dual_hammers L2
            attack_swing_right           = "attack_swing_up",            -- L4 release → dual_hammers L4
            attack_swing_down            = "attack_swing_stab",          -- L5 release → dual_hammers L5
            -- L1 native (attack_swing_left_diagonal) plays dual_hammers L3 swing
        }
        -- v0.12.149-dev: BAKED Kruber picks. Bardin's dual axes on Kruber render
        -- as Empire Mace & Sword (wield to_dual_hammer_sword_es). Confirmed via the
        -- dev anim picker; baked here career-scoped. dr_slayer keeps no entry →
        -- native; dr_ironbreaker/ranger/engineer keep `t` above. es_ is Kruber.
        local es_t = {
            attack_push                       = "attack_push",
            attack_swing_charge_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_left          = "attack_swing_charge_left",
            attack_swing_charge_right         = "attack_swing_charge_right",
            attack_swing_down                 = "attack_swing_down",
            attack_swing_heavy                = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right          = "attack_swing_heavy_right_diagonal",
            attack_swing_left                 = "attack_swing_left_diagonal",
            attack_swing_left_diagonal        = "attack_swing_left",
            attack_swing_right                = "attack_swing_right_diagonal",
            attack_swing_right_diagonal       = "attack_swing_right",
            parry_pose                        = "parry_pose",
        }
        -- v0.12.188-dev: BAKED Saltzpyre picks. Bardin's dual axes on the non-WP
        -- Saltzpyre body render as Dual Axe & Falchion (wield to_dual_axe_falchion);
        -- wh_-scoped redirect, separate from the Kruber es_ bake above.
        local wh_t = {
            attack_push                      = "attack_push",
            attack_swing_charge_diagonal     = "attack_swing_charge_down",
            attack_swing_charge_left         = "attack_swing_charge_left",
            attack_swing_charge_right        = "attack_swing_charge_down",
            attack_swing_down                = "attack_swing_heavy_down",
            attack_swing_heavy               = "attack_swing_heavy_left",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
            attack_swing_heavy_right         = "attack_swing_heavy_down",
            attack_swing_left                = "attack_swing_down",
            attack_swing_left_diagonal       = "attack_swing_heavy_left",
            attack_swing_right               = "attack_swing_right",
            attack_swing_right_diagonal      = "attack_swing_right",
            parry_pose                       = "parry_pose",
        }
        return { dr_ironbreaker = t, dr_ranger = t, dr_engineer = t, es_ = es_t, wh_ = wh_t }
    end)(),
    -- Sienna's Mace (bw_1h_mace) -> Empire Greathammer on Kruber (wield to_2h_hammer
    -- on es_). v0.12.150-dev: BAKED Kruber picks (confirmed via the dev anim picker).
    -- bw_ = false → Sienna native plays UNTOUCHED; es_ is the Kruber-only redirect.
    one_handed_hammer_wizard_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                         = "attack_push",
            attack_swing_charge_left_diagonal   = "attack_swing_charge",
            attack_swing_charge_left_pose        = "attack_swing_charge_left",
            attack_swing_charge_right_pose       = "attack_swing_charge_right",
            attack_swing_down                    = "attack_swing_down_left",
            attack_swing_heavy_down              = "attack_swing_down_left",
            attack_swing_heavy_left_up           = "attack_swing_heavy",
            attack_swing_heavy_right_up          = "attack_swing_heavy_right",
            attack_swing_left                    = "attack_swing_left",
            attack_swing_left_diagonal           = "attack_swing_left_diagonal",
            attack_swing_left_diagonal_last      = "attack_swing_left_diagonal",
            attack_swing_right_diagonal          = "attack_swing_down_right",
            parry_pose                           = "parry_pose",
        },
    },
    -- Necromancer Ghost Scythe (bw_ghost_scythe) -> Empire Greathammer on Kruber
    -- (wield to_2h_hammer on es_). v0.12.150-dev: BAKED Kruber picks. bw_ = false →
    -- Sienna native plays UNTOUCHED; es_ is the Kruber-only redirect. The two scythe
    -- specials (special_action / special_action_02) have no SET A twin — mapped to
    -- the nearest Greathammer events per the user's picks. ALSO carries a +6 Z 3P
    -- grip offset (es_ only) via _weapon_grip_offsets below, applied through the
    -- DURABLE per-frame path (_DURABLE_GRIP_OFFSETS) — bumped from +0.569 in
    -- v0.12.151-dev because the one-shot offset was stomped in-game (see OFFSETS.md).
    staff_scythe = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                          = "attack_push",
            attack_swing_charge_left             = "attack_swing_charge_left",
            attack_swing_charge_left_diagonal    = "attack_swing_charge_left",
            attack_swing_charge_right            = "attack_swing_charge_right",
            attack_swing_heavy                   = "attack_swing_heavy",
            attack_swing_heavy_left_diagonal     = "attack_swing_heavy",
            attack_swing_heavy_right             = "attack_swing_heavy_right",
            attack_swing_left                    = "attack_swing_left",
            attack_swing_left_diagonal           = "attack_swing_down_left",
            attack_swing_left_diagonal_last      = "attack_swing_down_left",
            attack_swing_right                   = "attack_swing_heavy_right",
            attack_swing_up_right                = "attack_swing_down_right",
            parry_pose                           = "parry_pose",
            special_action                       = "attack_swing_charge",
            special_action_02                    = "attack_swing_down_left",
        },
    },
    -- Warrior Priest / Saltzpyre Greathammer (wh_2h_hammer, template
    -- two_handed_hammer_priest_template) -> Empire Greathammer on Kruber (wield
    -- to_2h_hammer on es_). v0.12.188-dev: RE-BAKED Kruber picks (#180 — the
    -- v0.12.151 bake animated badly on Kruber, so the weapon was moved back to
    -- _NEEDS_ANIMS in v0.12.157 and re-tuned via the dev anim picker; these picks
    -- are pulled verbatim from the user's persisted picks). wh_ = false →
    -- Saltzpyre/Warrior-Priest natives play UNTOUCHED; es_ is the Kruber-only
    -- redirect. attack_slam / attack_slam_charge have no Greathammer twin — mapped
    -- to the nearest events per the user's picks.
    two_handed_hammer_priest_template = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                       = "attack_push",
            attack_slam                       = "attack_swing_left",
            attack_slam_charge                = "attack_swing_left",
            attack_swing_charge               = "attack_swing_charge",
            attack_swing_charge_right         = "attack_swing_charge",
            attack_swing_charge_right_down    = "attack_swing_charge_left",
            attack_swing_down_right           = "attack_swing_down_left",
            attack_swing_heavy_right          = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal = "attack_swing_down_left",
            attack_swing_left                 = "attack_swing_left_diagonal",
            attack_swing_up                   = "attack_swing_heavy",
            attack_swing_up_left              = "attack_swing_down_left",
            parry_pose                        = "parry_pose",
            parry_pose_02                     = "parry_pose",
        },
    },
    -- Bardin Outcast Engineer Coghammer (dr_2h_cog_hammer, template
    -- two_handed_cog_hammers_template_1) -> Empire Greathammer on Kruber (wield
    -- to_2h_hammer on es_). v0.12.188-dev: RE-BAKED Kruber picks (#182 — the
    -- v0.12.151 3-pick identity bake animated badly on Kruber, so the weapon was
    -- moved back to _NEEDS_ANIMS in v0.12.157 and re-tuned via the dev anim picker;
    -- these 16 picks are pulled verbatim from the user's persisted picks). dr_ =
    -- false → Bardin native plays UNTOUCHED; es_ is the Kruber-only redirect.
    two_handed_cog_hammers_template_1 = {
        dr_ = false, -- native (Bardin Outcast Engineer): untouched
        es_ = {
            attack_push                    = "attack_push",
            attack_swing_charge            = "attack_swing_charge",
            attack_swing_charge_pose       = "attack_swing_charge_left",
            attack_swing_charge_right      = "attack_swing_charge_right",
            attack_swing_charge_right_down = "attack_swing_charge_right",
            attack_swing_down_left         = "attack_swing_down_left",
            attack_swing_down_right        = "attack_swing_down_left",
            attack_swing_heavy             = "attack_swing_down_left",
            attack_swing_heavy_right       = "attack_swing_down_left",
            attack_swing_left              = "attack_swing_left",
            attack_swing_left_diagonal     = "attack_swing_left_diagonal",
            attack_swing_right_diagonal    = "attack_swing_down_right",
            attack_swing_up                = "attack_swing_left",
            attack_swing_up_pose           = "attack_swing_left",
            attack_swing_up_right          = "attack_swing_down_right",
            parry_pose                     = "parry_pose",
        },
    },
    -- ============================================================
    -- v0.12.156-dev: BAKED Kruber 3P picks for 7 more cross-character ports.
    -- ============================================================
    -- Pulled verbatim from the user's persisted dev anim picker (user_settings.config,
    -- 2026-06-25) — the last [Needs Animations] Kruber ports. Same career-scoped
    -- pattern as the v0.12.149-.151 bakes above: native owner prefix = false (owner
    -- plays UNTOUCHED), es_ is the Kruber-only redirect. 3P-only (consumed at the
    -- Unit.animation_event hook). Identity entries are harmless re-fires; __unset__
    -- picks were omitted (fall through to native).

    -- Kerillian 1H Axe (we_1h_axe) -> Kruber native to_1h_axe (mostly identity).
    we_one_hand_axe_template = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                              = "attack_push",
            attack_swing_charge_left_diagonal        = "attack_swing_charge_left_diagonal",
            attack_swing_charge_left_diagonal_pose   = "attack_swing_charge_left_diagonal_pose",
            attack_swing_charge_right_diagonal_pose  = "attack_swing_charge_right_diagonal_pose",
            attack_swing_down                        = "attack_swing_down_right",
            attack_swing_down_right                  = "attack_swing_down_right",
            attack_swing_heavy_down                  = "attack_swing_heavy_down",
            attack_swing_heavy_down_right            = "attack_swing_heavy_down_right",
            attack_swing_left                        = "attack_swing_left_diagonal",
            attack_swing_right                       = "attack_swing_right_diagonal",
            attack_swing_up                          = "attack_swing_right_diagonal",
            parry_pose                               = "parry_pose",
        },
    },
    -- Kerillian Glaive (we_2h_axe) -> Empire Greathammer (wield to_2h_hammer on es_).
    two_handed_axes_template_2 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                = "attack_push",
            attack_swing_charge_down   = "attack_swing_charge_right",
            attack_swing_charge_left   = "attack_swing_charge_right",
            attack_swing_heavy_down    = "attack_swing_down_left",
            attack_swing_heavy_left    = "attack_swing_heavy_right",
            attack_swing_left          = "attack_swing_heavy",
            attack_swing_left_diagonal = "attack_swing_heavy",
            attack_swing_right         = "attack_swing_heavy_right",
            parry_pose                 = "parry_pose",
        },
        -- v0.12.188-dev: Kerillian Glaive on SALTZPYRE body -> WP Greathammer
        -- (two_handed_axes_template_2 source events; wh_-scoped redirect).
        wh_ = {
            attack_push                = "attack_push",
            attack_swing_charge_down   = "attack_swing_charge",
            attack_swing_charge_left   = "attack_swing_charge_right",
            attack_swing_heavy_down    = "attack_swing_left",
            attack_swing_heavy_left    = "attack_swing_heavy_right",
            attack_swing_left          = "attack_swing_left",
            attack_swing_left_diagonal = "attack_swing_down_right",
            attack_swing_right         = "attack_swing_up",
            parry_pose                 = "parry_pose",
        },
    },
    -- Kerillian Dual Daggers (we_dual_wield_daggers) -> Empire Mace & Sword.
    dual_wield_daggers_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                = "attack_push",
            attack_swing_charge        = "attack_swing_charge_left",
            attack_swing_charge_left   = "attack_swing_charge_right",
            attack_swing_charge_right  = "attack_swing_charge_right",
            attack_swing_down_left     = "attack_swing_left",
            attack_swing_down_right    = "attack_swing_right",
            attack_swing_heavy         = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_down    = "attack_swing_heavy_right_diagonal",
            attack_swing_left          = "attack_swing_left_diagonal",
            attack_swing_right         = "attack_swing_right_diagonal",
            parry_pose                 = "parry_pose",
            push_stab                  = "attack_swing_down",
        },
        -- v0.12.188-dev: Kerillian Dual Daggers on SALTZPYRE body -> Dual Axe &
        -- Falchion (wh_-scoped redirect).
        wh_ = {
            attack_push               = "attack_push",
            attack_swing_charge       = "attack_swing_charge_down",
            attack_swing_charge_left  = "attack_swing_charge_left",
            attack_swing_charge_right = "attack_swing_charge_down",
            attack_swing_down_left    = "attack_swing_heavy_down",
            attack_swing_down_right   = "attack_swing_heavy_left",
            attack_swing_heavy        = "attack_swing_heavy_down",
            attack_swing_heavy_down   = "attack_swing_heavy_down",
            attack_swing_left         = "attack_swing_heavy_down",
            attack_swing_right        = "attack_swing_heavy_left",
            parry_pose                = "parry_pose",
            push_stab                 = "attack_swing_heavy_down",
        },
    },
    -- Kerillian Sword & Dagger (we_dual_wield_sword_dagger) -> Empire Mace & Sword.
    dual_wield_sword_dagger_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                       = "attack_push",
            attack_swing_charge               = "attack_swing_charge_right",
            attack_swing_charge_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_left          = "attack_swing_charge_right",
            attack_swing_heavy                = "attack_swing_heavy_right_diagonal",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
            attack_swing_left                 = "attack_swing_left_diagonal",
            attack_swing_right                = "attack_swing_right_diagonal",
            attack_swing_right_diagonal       = "attack_swing_right",
            attack_swing_stab                 = "attack_swing_down",
            parry_pose                        = "parry_pose",
            push_stab                         = "attack_swing_down",
        },
        -- v0.12.188-dev: Kerillian Sword & Dagger on SALTZPYRE body -> Dual Axe &
        -- Falchion (wh_-scoped redirect).
        wh_ = {
            attack_push                      = "attack_push",
            attack_swing_charge              = "attack_swing_charge_down",
            attack_swing_charge_diagonal     = "attack_swing_charge_left",
            attack_swing_charge_left         = "attack_swing_charge_down",
            attack_swing_heavy               = "attack_swing_heavy_down",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_left",
            attack_swing_left                = "attack_swing_heavy_down",
            attack_swing_right               = "attack_swing_heavy_down",
            attack_swing_right_diagonal      = "attack_swing_heavy_left",
            attack_swing_stab                = "attack_swing_heavy_left",
            parry_pose                       = "parry_pose",
            push_stab                        = "attack_swing_heavy_down",
        },
    },
    -- Kerillian Dual Swords (we_dual_wield_swords) -> Empire Mace & Sword.
    dual_wield_swords_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                       = "attack_push",
            attack_swing_charge_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_left          = "attack_swing_charge_right",
            attack_swing_charge_right         = "attack_swing_charge_left",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right          = "attack_swing_heavy_right_diagonal",
            attack_swing_left                 = "attack_swing_left",
            attack_swing_left_diagonal        = "attack_swing_left_diagonal",
            attack_swing_right                = "attack_swing_right_diagonal",
            attack_swing_right_diagonal       = "attack_swing_right",
            parry_pose                        = "parry_pose",
            push_stab                         = "attack_swing_down",
        },
        -- v0.12.188-dev: Kerillian Dual Swords on SALTZPYRE body -> Dual Axe &
        -- Falchion (wh_-scoped redirect).
        wh_ = {
            attack_push                      = "attack_push",
            attack_swing_charge_diagonal     = "attack_swing_charge_down",
            attack_swing_charge_left         = "attack_swing_charge_left",
            attack_swing_charge_right        = "attack_swing_charge_down",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
            attack_swing_heavy_right         = "attack_swing_heavy_left",
            attack_swing_left                = "attack_swing_heavy_down",
            attack_swing_left_diagonal       = "attack_swing_heavy_down",
            attack_swing_right               = "attack_swing_heavy_left",
            attack_swing_right_diagonal      = "attack_swing_heavy_left",
            parry_pose                       = "parry_pose",
            push_stab                        = "attack_swing_heavy_down",
        },
    },
    -- Warrior Priest Dual Skullsplitters (wh_dual_hammer) -> Empire Mace & Sword.
    dual_wield_hammers_priest_template = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                        = "attack_push",
            attack_swing_charge_down           = "attack_swing_charge_left",
            attack_swing_charge_left           = "attack_swing_charge_left",
            attack_swing_charge_right          = "attack_swing_charge_right",
            attack_swing_down                  = "attack_swing_down",
            attack_swing_heavy_down            = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_left_diagonal   = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right_diagonal  = "attack_swing_heavy_right_diagonal",
            attack_swing_left                  = "attack_swing_left",
            attack_swing_left_diagonal         = "attack_swing_left_diagonal",
            attack_swing_stab                  = "attack_swing_down",
            attack_swing_up                    = "attack_swing_right",
            parry_pose                         = "parry_pose",
        },
    },
    -- Warrior Priest Flail & Shield (wh_flail_shield) -> Empire Mace & Shield.
    one_handed_flail_shield_template = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                     = "attack_push",
            attack_slam                     = "attack_swing_heavy",
            attack_swing_charge             = "attack_swing_charge_left_pose",
            attack_swing_charge_down_pose   = "attack_swing_charge_left_pose",
            attack_swing_charge_pose        = "attack_swing_charge_left_pose",
            attack_swing_down               = "attack_swing_down",
            attack_swing_down_right         = "attack_swing_down",
            attack_swing_heavy_down         = "attack_swing_down",
            attack_swing_heavy_left         = "attack_swing_heavy_left",
            attack_swing_left               = "attack_swing_heavy_left",
            attack_swing_left_diagonal      = "attack_swing_left",
            attack_swing_right_diagonal     = "attack_swing_right_diagonal",
            parry_pose                      = "parry_pose",
        },
    },
    -- ============================================================
    -- v0.12.188-dev: BAKED Kruber + Saltzpyre 3P picks for the latest
    -- [Needs Animations] cross-character ports.
    -- ============================================================
    -- Pulled verbatim from the user's persisted dev anim picker
    -- (user_settings(2).config) — the Kruber Sienna-staves/Rapier batch and the
    -- Saltzpyre melee + Sienna-staves batches. Same career-scoped pattern as the
    -- v0.12.149-.156 bakes: native owner prefix = false (owner plays UNTOUCHED);
    -- es_ is the Kruber-only redirect, wh_ the (non-WP) Saltzpyre redirect. The
    -- staff/Deus templates carry BOTH es_ and wh_ because the same Sienna source
    -- weapons are surfaced on both receiver bodies. 3P-only (consumed at the
    -- Unit.animation_event hook). Identity entries are harmless re-fires; the
    -- staves' `inspect_start` picks were deliberately NOT baked (the picker never
    -- remaps inspect — 2026-06-29 user decision — and never applied them).

    -- Saltzpyre's Rapier (wh_fencing_sword) -> Empire 1H Sword on Kruber (wield
    -- to_1h_sword on es_). wh_ = false → Saltzpyre/WP native plays UNTOUCHED.
    fencing_sword_template_1 = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                 = "attack_push",
            attack_swing_left           = "attack_swing_left_diagonal",
            attack_swing_right          = "attack_swing_right",
            attack_swing_right_diagonal = "attack_swing_right_diagonal",
            attack_swing_stab           = "attack_swing_heavy_right",
            attack_swing_stab_charge    = "attack_swing_charge_right_pose",
            parry_pose                  = "parry_pose",
        },
    },

    -- Sienna's "Deus" staff (bw_deus_01) -> Empire Greathammer on Kruber (es_) /
    -- WP Greathammer on Saltzpyre (wh_). bw_ = false → Sienna native untouched.
    bw_deus_01_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_geiser_placed  = "attack_swing_down_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_down_right",
            cooldown_start        = "parry_pose",
        },
        wh_ = {
            attack_geiser_placed  = "attack_swing_heavy_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_up",
            cooldown_start        = "parry_pose",
        },
    },

    -- Sienna's Necromancy / Soulstealer staff (bw_necromancy_staff, staff_death)
    -- -> Greathammer (es_ Kruber / wh_ Saltzpyre). bw_ = false → Sienna untouched.
    staff_death = {
        bw_ = false, -- native (Sienna / Necromancer): untouched
        es_ = {
            chain_attack    = "attack_swing_left",
            chain_attack_02 = "attack_swing_down_right",
            cooldown_start  = "parry_pose",
            soul_rip_attack = "attack_swing_heavy",
            soul_rip_pop    = "attack_swing_left",
            soul_rip_start  = "attack_swing_heavy_right",
        },
        wh_ = {
            chain_attack    = "attack_swing_heavy_right_diagonal",
            chain_attack_02 = "attack_swing_down_right",
            cooldown_start  = "attack_swing_heavy_right_diagonal",
            soul_rip_attack = "attack_swing_charge_right",
            soul_rip_pop    = "attack_swing_heavy_right",
            soul_rip_start  = "attack_swing_charge",
        },
    },

    -- Sienna's Beam staff (bw_skullstaff_beam) -> Greathammer (es_ / wh_).
    staff_blast_beam_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_shoot_beam_spark   = "attack_push",
            attack_shoot_beam_start   = "parry_pose",
            attack_shoot_sparks       = "attack_swing_heavy",
            cooldown_start            = "parry_pose",
            flamethrower_charge_start = "parry_pose",
        },
        wh_ = {
            attack_shoot_beam_spark   = "attack_swing_down_right",
            attack_shoot_beam_start   = "parry_pose",
            attack_shoot_sparks       = "attack_swing_heavy_right_diagonal",
            cooldown_start            = "parry_pose",
            flamethrower_charge_start = "attack_swing_charge_right",
        },
    },

    -- Sienna's Fireball staff (bw_skullstaff_fireball) -> Greathammer (es_ / wh_).
    staff_fireball_fireball_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_charge_fireball        = "attack_swing_charge_right",
            attack_shoot_fireball         = "attack_swing_down_right",
            attack_shoot_fireball_charged = "attack_swing_down_right",
            cooldown_start                = "parry_pose",
        },
        wh_ = {
            attack_charge_fireball        = "attack_swing_charge_right",
            attack_shoot_fireball         = "attack_swing_up",
            attack_shoot_fireball_charged = "attack_swing_heavy_right",
            cooldown_start                = "parry_pose",
        },
    },

    -- Sienna's Flamethrower staff (bw_skullstaff_flamethrower) -> Greathammer.
    staff_flamethrower_template = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_shoot_flamethrower         = "attack_swing_down_left",
            attack_shoot_flamethrower_charged = "attack_swing_down_left",
            cooldown_start                    = "parry_pose",
            flamethrower_charge_start         = "attack_swing_charge_left",
        },
        wh_ = {
            attack_shoot_flamethrower         = "attack_swing_up",
            attack_shoot_flamethrower_charged = "attack_swing_heavy_right",
            cooldown_start                    = "parry_pose",
            flamethrower_charge_start         = "attack_swing_charge_right",
        },
    },

    -- Sienna's Geiser staff (bw_skullstaff_geiser) -> Greathammer (es_ / wh_).
    staff_fireball_geiser_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_geiser_placed  = "attack_swing_down_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_down_right",
            cooldown_start        = "parry_pose",
        },
        wh_ = {
            attack_geiser_placed  = "attack_swing_heavy_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_up",
            cooldown_start        = "parry_pose",
        },
    },

    -- Sienna's Spear/Spark staff (bw_skullstaff_spear) -> Greathammer (es_ / wh_).
    staff_spark_spear_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_charge_spear        = "attack_swing_charge_right",
            attack_shoot_rapid_left    = "attack_swing_heavy",
            attack_shoot_rapid_right   = "attack_swing_heavy_right",
            attack_shoot_spear_charged = "attack_swing_down_right",
        },
        wh_ = {
            attack_charge_spear        = "attack_swing_charge_right",
            attack_shoot_rapid_left    = "attack_swing_down_right",
            attack_shoot_rapid_right   = "attack_swing_heavy_right_diagonal",
            attack_shoot_spear_charged = "attack_swing_heavy_right",
            cooldown_start             = "parry_pose",
        },
    },

    -- Kruber's Empire Mace & Sword (es_dual_wield_hammer_sword) on the SALTZPYRE
    -- body -> Dual Axe & Falchion (wh_). es_ = false → Kruber native untouched.
    dual_wield_hammer_sword_template = {
        es_ = false, -- native (Kruber): untouched
        wh_ = {
            attack_push                       = "attack_push",
            attack_swing_charge_left          = "attack_swing_charge_left",
            attack_swing_charge_right         = "attack_swing_charge_down",
            attack_swing_down                 = "attack_swing_right",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left",
            attack_swing_heavy_right_diagonal = "attack_swing_heavy_down",
            attack_swing_left                 = "attack_swing_right_diagonal",
            attack_swing_left_diagonal        = "attack_swing_down_left",
            attack_swing_right                = "attack_swing_right",
            attack_swing_right_diagonal       = "attack_swing_left_diagonal",
            parry_pose                        = "parry_pose",
        },
    },

    -- Kruber's Halberd (es_halberd) on the SALTZPYRE body -> Billhook (wh_).
    -- es_ = false → Kruber native untouched.
    two_handed_halberds_template_1 = {
        es_ = false, -- native (Kruber): untouched
        wh_ = {
            attack_push               = "attack_push",
            attack_swing_charge_left  = "attack_swing_charge_stab",
            attack_swing_charge_right = "attack_swing_charge_stab",
            attack_swing_down_left    = "attack_swing_left_diagonal",
            attack_swing_down_right   = "attack_swing_down",
            attack_swing_heavy        = "attack_swing_heavy_stab",
            attack_swing_heavy_right  = "attack_swing_heavy_down",
            attack_swing_right        = "attack_swing_stab",
            parry_pose                = "parry_pose",
        },
    },

    -- Kerillian's Spear (we_spear) on the SALTZPYRE body -> Billhook (wh_).
    -- we_ = false → Kerillian native untouched.
    two_handed_spears_elf_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        wh_ = {
            attack_push                = "attack_push",
            attack_swing_charge_left   = "attack_swing_charge_stab",
            attack_swing_charge_right  = "attack_swing_charge_down",
            attack_swing_down_left     = "attack_swing_left_diagonal",
            attack_swing_down_left_axe = "attack_swing_stab",
            attack_swing_down_right    = "attack_swing_stab",
            attack_swing_heavy         = "attack_swing_heavy_down",
            attack_swing_heavy_right   = "attack_swing_heavy_stab",
            attack_swing_right         = "attack_swing_stab",
            parry_pose                 = "parry_pose",
            push_stab                  = "attack_swing_left_diagonal",
        },
    },
}

do
    local R = _3p_template_remaps
    -- ============================================================
    -- v0.12.201-dev: BAKED tester 3P picks (Downloads/user_settings(4).config,
    -- 2026-07-03) — Kerillian batch-1 (33 ports) + Saltzpyre Executioner Sword
    -- + Kruber Skullsplitter & Tome. Same career-scoped pattern as the
    -- v0.12.149-.188 bakes: native owner prefix = false (owner plays UNTOUCHED),
    -- we_ = Kerillian redirect, wh_ = (non-WP) Saltzpyre, es_ = Kruber. Emitted as
    -- post-definition assignments (mirrors the longbow-port block below) so each
    -- new we_/wh_/es_ MERGES into the existing es_/wh_ literal entry without
    -- disturbing it. 3P-only (Unit.animation_event hook); identity entries are
    -- harmless re-fires; __unset__ picks were omitted (fall through to native).
    -- dual_wield_axes_template_1 gets NO dr_=false (its Bardin remap is per-career
    -- dr_ironbreaker/ranger/engineer; a dr_ prefix=false would shadow them).
    -- ============================================================
    -- kerillian (we_): es_2h_hammer -> two_handed_hammers_template_1
    R.two_handed_hammers_template_1 = R.two_handed_hammers_template_1 or {}
    R.two_handed_hammers_template_1.es_ = R.two_handed_hammers_template_1.es_ or false
    R.two_handed_hammers_template_1.we_ = {
        attack_push                = "attack_push",
        attack_swing_charge        = "attack_swing_charge_left",
        attack_swing_charge_left   = "attack_swing_charge_left",
        attack_swing_charge_right  = "attack_swing_charge_left",
        attack_swing_down_left     = "attack_swing_heavy_down",
        attack_swing_down_right    = "attack_swing_right",
        attack_swing_heavy         = "attack_swing_heavy_left",
        attack_swing_heavy_right   = "attack_swing_heavy_left",
        attack_swing_left          = "attack_swing_left",
        attack_swing_left_diagonal = "attack_swing_left_diagonal",
        parry_pose                 = "parry_pose",
    }
    -- kerillian (we_): wh_2h_hammer -> two_handed_hammer_priest_template
    R.two_handed_hammer_priest_template = R.two_handed_hammer_priest_template or {}
    R.two_handed_hammer_priest_template.wh_ = R.two_handed_hammer_priest_template.wh_ or false
    R.two_handed_hammer_priest_template.we_ = {
        attack_push                       = "attack_push",
        attack_slam                       = "attack_swing_left_diagonal",
        attack_slam_charge                = "attack_swing_heavy_left",
        attack_swing_charge               = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_down",
        attack_swing_charge_right_down    = "attack_swing_charge_down",
        attack_swing_down_right           = "attack_swing_right",
        attack_swing_heavy_right          = "attack_swing_heavy_left",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_down",
        attack_swing_left                 = "attack_swing_right",
        attack_swing_up                   = "attack_swing_left",
        attack_swing_up_left              = "attack_swing_left",
        parry_pose                        = "parry_pose",
        parry_pose_02                     = "parry_pose",
    }
    -- kerillian (we_): dr_2h_cog_hammer -> two_handed_cog_hammers_template_1
    R.two_handed_cog_hammers_template_1 = R.two_handed_cog_hammers_template_1 or {}
    R.two_handed_cog_hammers_template_1.dr_ = R.two_handed_cog_hammers_template_1.dr_ or false
    R.two_handed_cog_hammers_template_1.we_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_heavy_left",
        attack_swing_charge_pose       = "attack_swing_heavy_left",
        attack_swing_charge_right      = "attack_swing_charge_down",
        attack_swing_charge_right_down = "attack_swing_heavy_left",
        attack_swing_down_left         = "attack_swing_right",
        attack_swing_down_right        = "attack_swing_right",
        attack_swing_heavy             = "attack_swing_heavy_down",
        attack_swing_heavy_right       = "attack_swing_heavy_down",
        attack_swing_left              = "attack_swing_right",
        attack_swing_left_diagonal     = "attack_swing_left",
        attack_swing_right_diagonal    = "attack_swing_right",
        attack_swing_up                = "attack_swing_left",
        attack_swing_up_pose           = "attack_swing_left",
        attack_swing_up_right          = "attack_swing_right",
        parry_pose                     = "parry_pose",
    }
    -- kerillian (we_): dr_2h_pick -> two_handed_picks_template_1
    R.two_handed_picks_template_1 = R.two_handed_picks_template_1 or {}
    R.two_handed_picks_template_1.dr_ = R.two_handed_picks_template_1.dr_ or false
    R.two_handed_picks_template_1.we_ = {
        attack_push                        = "attack_push",
        attack_swing_charge_left_down      = "attack_swing_charge_left",
        attack_swing_charge_left_down_pose = "attack_swing_charge_left",
        attack_swing_charge_right_down     = "attack_swing_charge_down",
        attack_swing_down_left             = "attack_swing_right",
        attack_swing_down_left_axe         = "attack_swing_right",
        attack_swing_down_right            = "attack_swing_right",
        attack_swing_down_right_axe        = "attack_swing_right",
        attack_swing_left                  = "attack_swing_right",
        attack_swing_left_diagonal         = "attack_swing_left",
        attack_swing_right_diagonal        = "attack_swing_right",
        parry_pose                         = "parry_pose",
    }
    -- kerillian (we_): bw_ghost_scythe -> staff_scythe
    R.staff_scythe = R.staff_scythe or {}
    R.staff_scythe.bw_ = R.staff_scythe.bw_ or false
    R.staff_scythe.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_down",
        attack_swing_heavy                = "attack_swing_heavy_down",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left",
        attack_swing_heavy_right          = "attack_swing_heavy_down",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_left_diagonal_last   = "attack_swing_heavy_left",
        attack_swing_right                = "attack_swing_right",
        attack_swing_up_right             = "attack_swing_right",
        parry_pose                        = "parry_pose",
        special_action                    = "attack_swing_heavy_left",
        special_action_02                 = "attack_swing_heavy_down",
    }
    -- kerillian (we_): bw_skullstaff_beam -> staff_blast_beam_template_1
    R.staff_blast_beam_template_1 = R.staff_blast_beam_template_1 or {}
    R.staff_blast_beam_template_1.bw_ = R.staff_blast_beam_template_1.bw_ or false
    R.staff_blast_beam_template_1.we_ = {
        attack_shoot_beam_spark   = "attack_swing_heavy_down",
        attack_shoot_beam_start   = "attack_swing_left",
        attack_shoot_sparks       = "attack_swing_heavy_left",
        cooldown_start            = "parry_pose",
        flamethrower_charge_start = "attack_swing_right",
    }
    -- kerillian (we_): bw_skullstaff_fireball -> staff_fireball_fireball_template_1
    R.staff_fireball_fireball_template_1 = R.staff_fireball_fireball_template_1 or {}
    R.staff_fireball_fireball_template_1.bw_ = R.staff_fireball_fireball_template_1.bw_ or false
    R.staff_fireball_fireball_template_1.we_ = {
        attack_charge_fireball        = "attack_swing_charge_left",
        attack_shoot_fireball         = "attack_swing_right",
        attack_shoot_fireball_charged = "attack_swing_left",
        cooldown_start                = "parry_pose",
    }
    -- kerillian (we_): bw_skullstaff_flamethrower -> staff_flamethrower_template
    R.staff_flamethrower_template = R.staff_flamethrower_template or {}
    R.staff_flamethrower_template.bw_ = R.staff_flamethrower_template.bw_ or false
    R.staff_flamethrower_template.we_ = {
        attack_shoot_flamethrower         = "attack_swing_right",
        attack_shoot_flamethrower_charged = "attack_swing_left",
        cooldown_start                    = "parry_pose",
        flamethrower_charge_start         = "attack_swing_charge_left",
    }
    -- kerillian (we_): bw_skullstaff_geiser -> staff_fireball_geiser_template_1
    R.staff_fireball_geiser_template_1 = R.staff_fireball_geiser_template_1 or {}
    R.staff_fireball_geiser_template_1.bw_ = R.staff_fireball_geiser_template_1.bw_ or false
    R.staff_fireball_geiser_template_1.we_ = {
        attack_geiser_placed  = "attack_swing_left",
        attack_geiser_start   = "attack_swing_charge_left",
        attack_shoot_fireball = "attack_swing_right",
        cooldown_start        = "parry_pose",
    }
    -- kerillian (we_): bw_skullstaff_spear -> staff_spark_spear_template_1
    R.staff_spark_spear_template_1 = R.staff_spark_spear_template_1 or {}
    R.staff_spark_spear_template_1.bw_ = R.staff_spark_spear_template_1.bw_ or false
    R.staff_spark_spear_template_1.we_ = {
        attack_charge_spear        = "attack_swing_charge_left",
        attack_shoot_rapid_left    = "attack_swing_left",
        attack_shoot_rapid_right   = "attack_swing_right",
        attack_shoot_spear_charged = "attack_swing_left",
        cooldown_start             = "parry_pose",
    }
    -- kerillian (we_): bw_necromancy_staff -> staff_death
    R.staff_death = R.staff_death or {}
    R.staff_death.bw_ = R.staff_death.bw_ or false
    R.staff_death.we_ = {
        chain_attack    = "attack_swing_left",
        chain_attack_02 = "attack_swing_right",
        cooldown_start  = "parry_pose",
        soul_rip_attack = "attack_swing_charge_left",
        soul_rip_pop    = "attack_swing_left",
        soul_rip_start  = "attack_swing_right",
    }
    -- kerillian (we_): bw_deus_01 -> bw_deus_01_template_1
    R.bw_deus_01_template_1 = R.bw_deus_01_template_1 or {}
    R.bw_deus_01_template_1.bw_ = R.bw_deus_01_template_1.bw_ or false
    R.bw_deus_01_template_1.we_ = {
        attack_geiser_placed  = "attack_swing_left",
        attack_geiser_start   = "attack_swing_charge_left",
        attack_shoot_fireball = "attack_swing_right",
        cooldown_start        = "parry_pose",
    }
    -- kerillian (we_): es_2h_sword_executioner -> two_handed_swords_executioner_template_1
    R.two_handed_swords_executioner_template_1 = R.two_handed_swords_executioner_template_1 or {}
    R.two_handed_swords_executioner_template_1.es_ = R.two_handed_swords_executioner_template_1.es_ or false
    R.two_handed_swords_executioner_template_1.we_ = {
        attack_push                     = "attack_push",
        attack_swing_charge_left_down   = "attack_swing_charge",
        attack_swing_charge_right_down  = "attack_swing_charge",
        attack_swing_down_left          = "attack_swing_right",
        attack_swing_down_right         = "attack_swing_right",
        attack_swing_left               = "attack_swing_left",
        attack_swing_left_diagonal      = "attack_swing_left",
        attack_swing_left_diagonal_last = "attack_swing_heavy",
        attack_swing_right              = "attack_swing_heavy_right",
        parry_pose                      = "parry_pose",
    }
    -- kerillian (we_): es_bastard_sword -> bastard_sword_template
    R.bastard_sword_template = R.bastard_sword_template or {}
    R.bastard_sword_template.es_ = R.bastard_sword_template.es_ or false
    R.bastard_sword_template.we_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_down_pose           = "attack_swing_charge",
        attack_swing_charge_left_diagonal       = "attack_swing_charge",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge",
        attack_swing_down                       = "attack_swing_left",
        attack_swing_down_right                 = "attack_swing_heavy_right",
        attack_swing_heavy_down                 = "attack_swing_heavy",
        attack_swing_heavy_left_diagonal        = "attack_swing_left",
        attack_swing_heavy_right_diagonal       = "attack_swing_right",
        attack_swing_right                      = "attack_swing_right",
        attack_swing_up_left                    = "attack_swing_left",
        parry_pose                              = "parry_pose",
        swap_charge_stance                      = "attack_swing_charge",
    }
    -- kerillian (we_): wh_fencing_sword -> fencing_sword_template_1
    R.fencing_sword_template_1 = R.fencing_sword_template_1 or {}
    R.fencing_sword_template_1.wh_ = R.fencing_sword_template_1.wh_ or false
    R.fencing_sword_template_1.we_ = {
        attack_push                 = "attack_swing_heavy_down_right",
        attack_shoot                = "attack_push",
        attack_swing_left           = "attack_swing_left",
        attack_swing_right          = "attack_swing_right_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_stab           = "attack_swing_stab",
        attack_swing_stab_charge    = "attack_swing_charge_down",
        front_idle_exit             = "attack_swing_left",
        parry_pose                  = "parry_pose",
    }
    -- kerillian (we_): bw_1h_flail_flaming -> one_handed_flails_flaming_template
    R.one_handed_flails_flaming_template = R.one_handed_flails_flaming_template or {}
    R.one_handed_flails_flaming_template.bw_ = R.one_handed_flails_flaming_template.bw_ or false
    R.one_handed_flails_flaming_template.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_down    = "attack_swing_charge_down",
        attack_swing_down_right     = "attack_swing_heavy_down_right",
        attack_swing_heavy_down     = "attack_swing_heavy_down",
        attack_swing_heavy_left     = "attack_swing_heavy_left_up",
        attack_swing_left           = "attack_swing_left_diagonal",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right          = "attack_swing_heavy_down_right",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        parry_pose                  = "parry_pose",
    }
    -- kerillian (we_): bw_dagger -> one_handed_daggers_template_1
    R.one_handed_daggers_template_1 = R.one_handed_daggers_template_1 or {}
    R.one_handed_daggers_template_1.bw_ = R.one_handed_daggers_template_1.bw_ or false
    R.one_handed_daggers_template_1.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_left    = "attack_swing_charge_down",
        attack_swing_heavy          = "attack_swing_heavy_left_up",
        attack_swing_heavy_right    = "attack_swing_heavy_down_right",
        attack_swing_left           = "attack_swing_left",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_stab           = "attack_swing_stab",
        parry_pose                  = "parry_pose",
    }
    -- kerillian (we_): bw_flame_sword -> flaming_sword_template_1
    R.flaming_sword_template_1 = R.flaming_sword_template_1 or {}
    R.flaming_sword_template_1.bw_ = R.flaming_sword_template_1.bw_ or false
    R.flaming_sword_template_1.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_down",
        attack_swing_charge_right   = "attack_swing_charge_down",
        attack_swing_heavy          = "attack_swing_heavy_down_right",
        attack_swing_left           = "attack_swing_left",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_right_spell    = "attack_swing_heavy_left_up",
        attack_swing_stab           = "attack_swing_stab",
        parry_pose                  = "parry_pose",
    }
    -- kerillian (we_): wh_1h_hammer -> one_handed_hammer_priest_template
    R.one_handed_hammer_priest_template = R.one_handed_hammer_priest_template or {}
    R.one_handed_hammer_priest_template.wh_ = R.one_handed_hammer_priest_template.wh_ or false
    R.one_handed_hammer_priest_template.we_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_left_diagonal       = "attack_swing_charge_left_diagonal",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down_right                 = "attack_swing_right",
        attack_swing_heavy_down                 = "attack_swing_heavy_down",
        attack_swing_heavy_down_right           = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal              = "attack_swing_left",
        attack_swing_left_diagonal_last         = "attack_swing_left",
        attack_swing_right                      = "attack_swing_right",
        attack_swing_right_diagonal             = "attack_swing_right",
        parry_pose                              = "parry_pose",
    }
    -- kerillian (we_): dr_1h_hammer -> one_handed_hammer_template_2
    R.one_handed_hammer_template_2 = R.one_handed_hammer_template_2 or {}
    R.one_handed_hammer_template_2.dr_ = R.one_handed_hammer_template_2.dr_ or false
    R.one_handed_hammer_template_2.we_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_left_diagonal       = "attack_swing_charge_left_diagonal",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down_right                 = "attack_swing_right",
        attack_swing_heavy_down                 = "attack_swing_heavy_down",
        attack_swing_heavy_down_right           = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal              = "attack_swing_left",
        attack_swing_left_diagonal_last         = "attack_swing_left",
        attack_swing_right                      = "attack_swing_right",
        attack_swing_right_diagonal             = "attack_swing_right",
        parry_pose                              = "parry_pose",
    }
    -- kerillian (we_): es_mace_shield -> one_handed_hammer_shield_template_1
    R.one_handed_hammer_shield_template_1 = R.one_handed_hammer_shield_template_1 or {}
    R.one_handed_hammer_shield_template_1.es_ = R.one_handed_hammer_shield_template_1.es_ or false
    R.one_handed_hammer_shield_template_1.we_ = {
        attack_push                   = "attack_push",
        attack_swing_charge           = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_left_pose = "attack_swing_charge_left",
        attack_swing_charge_pose      = "attack_swing_charge_stab",
        attack_swing_down             = "push_stab",
        attack_swing_heavy            = "attack_swing_heavy_stab",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down_right",
        attack_swing_up_left          = "attack_swing_heavy_left",
        parry_pose                    = "parry_pose",
    }
    -- kerillian (we_): es_sword_shield -> one_handed_sword_shield_template_1
    R.one_handed_sword_shield_template_1 = R.one_handed_sword_shield_template_1 or {}
    R.one_handed_sword_shield_template_1.es_ = R.one_handed_sword_shield_template_1.es_ or false
    R.one_handed_sword_shield_template_1.we_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_charge_left",
        attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_stab       = "attack_swing_charge_stab",
        attack_swing_heavy             = "attack_swing_heavy_left",
        attack_swing_heavy_right       = "attack_swing_heavy_down_right",
        attack_swing_heavy_stab        = "attack_swing_heavy_stab",
        attack_swing_left              = "attack_swing_heavy_left",
        attack_swing_left_diagonal     = "attack_swing_heavy_left",
        attack_swing_right_diagonal    = "attack_swing_heavy_down_right",
        attack_swing_stab              = "push_stab",
        parry_pose                     = "parry_pose",
    }
    -- kerillian (we_): es_sword_shield_breton -> one_handed_sword_shield_template_2
    R.one_handed_sword_shield_template_2 = R.one_handed_sword_shield_template_2 or {}
    R.one_handed_sword_shield_template_2.es_ = R.one_handed_sword_shield_template_2.es_ or false
    R.one_handed_sword_shield_template_2.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge               = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left",
        attack_swing_charge_stab          = "attack_swing_charge_stab",
        attack_swing_down_right           = "attack_swing_heavy_left",
        attack_swing_heavy                = "attack_swing_heavy_left",
        attack_swing_heavy_breton         = "attack_swing_stab_lh",
        attack_swing_heavy_down           = "attack_swing_heavy_down_right",
        attack_swing_heavy_stab           = "attack_swing_heavy_stab",
        attack_swing_stab                 = "attack_swing_stab",
        attack_swing_up_left              = "attack_swing_heavy_down_right",
        parry_pose                        = "parry_pose",
    }
    -- kerillian (we_): wh_flail_shield -> one_handed_flail_shield_template
    R.one_handed_flail_shield_template = R.one_handed_flail_shield_template or {}
    R.one_handed_flail_shield_template.wh_ = R.one_handed_flail_shield_template.wh_ or false
    R.one_handed_flail_shield_template.we_ = {
        attack_push                   = "attack_push",
        attack_slam                   = "push_stab",
        attack_swing_charge           = "attack_swing_charge_stab",
        attack_swing_charge_down_pose = "attack_swing_charge_stab",
        attack_swing_charge_pose      = "attack_swing_charge_stab",
        attack_swing_down             = "attack_swing_heavy_left",
        attack_swing_down_right       = "attack_swing_heavy_down_right",
        attack_swing_heavy_down       = "attack_swing_heavy_left",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_left_diagonal    = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down_right",
        parry_pose                    = "parry_pose",
    }
    -- kerillian (we_): wh_hammer_book -> one_handed_hammer_book_priest_template
    R.one_handed_hammer_book_priest_template = R.one_handed_hammer_book_priest_template or {}
    R.one_handed_hammer_book_priest_template.wh_ = R.one_handed_hammer_book_priest_template.wh_ or false
    R.one_handed_hammer_book_priest_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left",
        attack_swing_charge_stab          = "attack_swing_charge_stab",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_stab",
        attack_swing_heavy_stab           = "attack_swing_stab",
        attack_swing_left_diagonal        = "attack_swing_heavy_left",
        attack_swing_left_diagonal_last   = "attack_swing_heavy_left",
        attack_swing_right_diagonal       = "attack_swing_heavy_down_right",
        attack_swing_right_diagonal_axe   = "attack_swing_heavy_down_right",
        attack_swing_stab                 = "push_stab",
        attack_swing_up_left              = "attack_swing_heavy_left",
        parry_pose                        = "parry_pose",
        spell_pose                        = "attack_push",
    }
    -- kerillian (we_): wh_hammer_shield -> one_handed_hammer_shield_priest_template
    R.one_handed_hammer_shield_priest_template = R.one_handed_hammer_shield_priest_template or {}
    R.one_handed_hammer_shield_priest_template.wh_ = R.one_handed_hammer_shield_priest_template.wh_ or false
    R.one_handed_hammer_shield_priest_template.we_ = {
        attack_push                   = "attack_push",
        attack_swing_charge           = "attack_swing_charge_stab",
        attack_swing_charge_left_pose = "attack_swing_charge_left",
        attack_swing_charge_pose      = "attack_swing_charge_stab",
        attack_swing_down             = "attack_swing_heavy_left",
        attack_swing_heavy            = "attack_swing_heavy_stab",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down_right",
        attack_swing_up_left          = "attack_swing_heavy_left",
        parry_pose                    = "parry_pose",
    }
    -- kerillian (we_): dr_shield_axe -> one_hand_axe_shield_template_1
    R.one_hand_axe_shield_template_1 = R.one_hand_axe_shield_template_1 or {}
    R.one_hand_axe_shield_template_1.dr_ = R.one_hand_axe_shield_template_1.dr_ or false
    R.one_hand_axe_shield_template_1.we_ = {
        attack_push                            = "attack_push",
        attack_swing_charge                    = "attack_swing_charge_left",
        attack_swing_charge_left_diagonal_pose = "attack_swing_charge_stab",
        attack_swing_charge_left_pose          = "attack_swing_charge_left",
        attack_swing_charge_right_pose         = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down                      = "attack_swing_heavy_left",
        attack_swing_heavy                     = "attack_swing_heavy_stab",
        attack_swing_heavy_down                = "attack_swing_heavy_left",
        attack_swing_heavy_right               = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal             = "attack_swing_heavy_left",
        attack_swing_right_diagonal            = "attack_swing_heavy_down_right",
        attack_swing_up_left                   = "attack_swing_heavy_left",
        parry_pose                             = "parry_pose",
    }
    -- kerillian (we_): wh_dual_hammer -> dual_wield_hammers_priest_template
    R.dual_wield_hammers_priest_template = R.dual_wield_hammers_priest_template or {}
    R.dual_wield_hammers_priest_template.wh_ = R.dual_wield_hammers_priest_template.wh_ or false
    R.dual_wield_hammers_priest_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_down          = "attack_swing_charge_left",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_right",
        attack_swing_down                 = "attack_swing_right",
        attack_swing_heavy_down           = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_stab                 = "push_stab",
        attack_swing_up                   = "attack_swing_right_diagonal",
        parry_pose                        = "parry_pose",
    }
    -- kerillian (we_): dr_dual_wield_axes -> dual_wield_axes_template_1
    R.dual_wield_axes_template_1 = R.dual_wield_axes_template_1 or {}
    R.dual_wield_axes_template_1.we_ = {
        attack_push                      = "attack_push",
        attack_swing_charge_diagonal     = "attack_swing_charge_right",
        attack_swing_charge_left         = "attack_swing_charge_left",
        attack_swing_charge_right        = "attack_swing_charge_right",
        attack_swing_down                = "attack_swing_left",
        attack_swing_heavy               = "attack_swing_heavy_right",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right         = "attack_swing_heavy_right",
        attack_swing_left                = "attack_swing_left",
        attack_swing_left_diagonal       = "attack_swing_left_diagonal",
        attack_swing_right               = "attack_swing_right",
        attack_swing_right_diagonal      = "attack_swing_right_diagonal",
        parry_pose                       = "parry_pose",
    }
    -- kerillian (we_): dr_dual_wield_hammers -> dual_wield_hammers_template
    R.dual_wield_hammers_template = R.dual_wield_hammers_template or {}
    R.dual_wield_hammers_template.dr_ = R.dual_wield_hammers_template.dr_ or false
    R.dual_wield_hammers_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_down          = "attack_swing_charge_left",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_right",
        attack_swing_down                 = "attack_swing_right",
        attack_swing_heavy_down           = "attack_swing_heavy_right",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left",
        attack_swing_stab                 = "push_stab",
        attack_swing_up                   = "attack_swing_right",
        parry_pose                        = "parry_pose",
    }
    -- kerillian (we_): es_dual_wield_hammer_sword -> dual_wield_hammer_sword_template
    R.dual_wield_hammer_sword_template = R.dual_wield_hammer_sword_template or {}
    R.dual_wield_hammer_sword_template.es_ = R.dual_wield_hammer_sword_template.es_ or false
    R.dual_wield_hammer_sword_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left          = "attack_swing_charge",
        attack_swing_charge_right         = "attack_swing_charge",
        attack_swing_down                 = "push_stab",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy",
        attack_swing_left                 = "attack_swing_heavy_left_diagonal",
        attack_swing_left_diagonal        = "attack_swing_left",
        attack_swing_right                = "attack_swing_right",
        attack_swing_right_diagonal       = "attack_swing_right_diagonal",
        parry_pose                        = "parry_pose",
    }
    -- kerillian (we_): wh_dual_wield_axe_falchion -> dual_wield_axe_falchion_template
    R.dual_wield_axe_falchion_template = R.dual_wield_axe_falchion_template or {}
    R.dual_wield_axe_falchion_template.wh_ = R.dual_wield_axe_falchion_template.wh_ or false
    R.dual_wield_axe_falchion_template.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge_down    = "attack_swing_charge",
        attack_swing_charge_left    = "attack_swing_charge_diagonal",
        attack_swing_down           = "attack_swing_right",
        attack_swing_down_left      = "attack_swing_stab",
        attack_swing_heavy_down     = "attack_swing_heavy",
        attack_swing_heavy_left     = "attack_swing_heavy_left_diagonal",
        attack_swing_left_diagonal  = "attack_swing_right_diagonal",
        attack_swing_right          = "attack_swing_right",
        attack_swing_right_diagonal = "attack_swing_left",
        parry_pose                  = "parry_pose",
    }
    -- kerillian (we_): dr_1h_throwing_axes -> one_handed_throwing_axes_template
    R.one_handed_throwing_axes_template = R.one_handed_throwing_axes_template or {}
    R.one_handed_throwing_axes_template.dr_ = R.one_handed_throwing_axes_template.dr_ or false
    R.one_handed_throwing_axes_template.we_ = {
        attack_throw = "attack_swing_up",
        reload       = "attack_throw",
        reload_last  = "attack_throw",
        throw_charge = "throw_charge",
    }
    -- saltzpyre (wh_): es_2h_sword_executioner -> two_handed_swords_executioner_template_1
    R.two_handed_swords_executioner_template_1 = R.two_handed_swords_executioner_template_1 or {}
    R.two_handed_swords_executioner_template_1.es_ = R.two_handed_swords_executioner_template_1.es_ or false
    R.two_handed_swords_executioner_template_1.wh_ = {
        attack_push                     = "attack_push",
        attack_swing_charge_left_down   = "attack_swing_charge_diagonal_left",
        attack_swing_charge_right_down  = "attack_swing_charge_diagonal_right",
        attack_swing_down_left          = "attack_swing_heavy_left_diagonal",
        attack_swing_down_right         = "attack_swing_heavy_right_diagonal",
        attack_swing_left               = "attack_swing_left_diagonal",
        attack_swing_left_diagonal      = "attack_swing_right_diagonal",
        attack_swing_left_diagonal_last = "attack_swing_left_diagonal",
        attack_swing_right              = "attack_swing_right_diagonal",
        parry_pose                      = "parry_pose",
    }
    -- kruber (es_): wh_hammer_book -> one_handed_hammer_book_priest_template
    R.one_handed_hammer_book_priest_template = R.one_handed_hammer_book_priest_template or {}
    R.one_handed_hammer_book_priest_template.wh_ = R.one_handed_hammer_book_priest_template.wh_ or false
    R.one_handed_hammer_book_priest_template.es_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_stab          = "attack_swing_charge_right_diagonal_pose",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_down",
        attack_swing_heavy_stab           = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_left_diagonal_last   = "attack_swing_left_diagonal_last",
        attack_swing_right_diagonal       = "attack_swing_right_diagonal",
        attack_swing_right_diagonal_axe   = "attack_swing_right_diagonal",
        attack_swing_stab                 = "attack_swing_right",
        attack_swing_up_left              = "attack_swing_left_diagonal",
        parry_pose                        = "parry_pose",
        spell_pose                        = "attack_swing_right",
    }
end

local function _resolve_template_remap(template_name, career)
    local entry = _3p_template_remaps[template_name]
    if not entry then return nil end
    if career then
        for prefix, tbl in pairs(entry) do
            if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
                return tbl
            end
        end
    end
    return entry._default
end

local _3p_key_remaps = {
    we_1h_sword = {
        we_ = false,
        _default = {
            attack_swing_stab          = "attack_swing_down",                 -- L4 stab → vertical
            attack_swing_charge_down   = "attack_swing_charge_left_diagonal", -- H1 charge windup (also L1 charge gains a windup)
            attack_swing_charge_left   = "attack_swing_charge_right_pose",    -- H2 charge windup
            attack_swing_heavy_left_up = "attack_swing_heavy_right",          -- H2 release → heavy right swing
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_left_diagonal", -- H3 charge → vertical (matches H1; also affects L2 charge — windup pose only, brief)
            attack_swing_heavy_down_right = "attack_swing_heavy_down",        -- H3 release → vertical (was horizontal)
        },
    },
    bw_sword = {
        dr_ = {
            -- 3-position heavy chain. Differentiate variants:
            --   H1 from idle (charge_left/heavy)            → elf H2 (right swing)
            --   H2 (charge_right_pose/heavy_right)          → elf H1 (vertical heavy)
            --   H3+ (charge_left_pose/heavy) — release is the same event as H1
            --   so it inherits the right-swing; charge gets right-pose windup to match.
            attack_swing_charge_left       = "attack_swing_charge_right_pose",
            attack_swing_heavy             = "attack_swing_heavy_right",
            attack_swing_charge_right_pose = "attack_swing_charge_left_diagonal",
            attack_swing_heavy_right       = "attack_swing_heavy_down",
            attack_swing_charge_left_pose  = "attack_swing_charge_right_pose", -- H3+ chain windup matches right swing
        },
    },
    es_1h_sword = {
        -- one_handed_swords_template_1 (shared with bw_sword) — same heavy chain.
        dr_ = {
            attack_swing_charge_left       = "attack_swing_charge_right_pose",
            attack_swing_heavy             = "attack_swing_heavy_right",
            attack_swing_charge_right_pose = "attack_swing_charge_left_diagonal",
            attack_swing_heavy_right       = "attack_swing_heavy_down",
            attack_swing_charge_left_pose  = "attack_swing_charge_right_pose", -- H3+ chain windup matches right swing
        },
    },
}

local function _resolve_key_remap(weapon_key, career)
    local entry = _3p_key_remaps[weapon_key]
    if not entry then return nil end
    if career then
        for prefix, tbl in pairs(entry) do
            if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
                return tbl
            end
        end
    end
    return entry._default
end

local _log_anims = false
local _last_3p_unit = nil
-- CLARIFY: captured in the wield hook from `self._first_person_unit`. Used
-- ONLY to distinguish the local 1P hands unit (which should NOT receive
-- redirects) from husks (which should). Cannot use `is_local` for this —
-- the 1P unit has `is_local=false` same as husks (see feedback_animation_remap_rules).
local _local_fp_unit = nil
-- CLARIFY: stashed reference to the original `Unit.animation_event` so we can
-- bypass our own hook for force-fire events that corrupt the SM when going
-- through the remap-table path (e.g. attack_swing_stab_02 on billhook).
local _original_animation_event = nil
local _animlog_last_was_attack = false

mod:command("info", "Show current weapon tweaker state", function()
    mod:echo("Weapon Tweaker v" .. MOD_VERSION)
    local career = _local_career_name()
    mod:echo("Career: " .. (career or "unknown"))
    local remap_name = "none"
    local pm = Managers.player
    local player = pm and pm:local_player()
    local state = player and player.player_unit and _unit_state[player.player_unit]
    local remap = state and state.remap
    if remap then
        if remap == _3p_remap_spear_to_billhook then remap_name = "spear→billhook"
        elseif remap == _3p_remap_polearm_to_billhook then remap_name = "polearm→billhook"
        elseif remap == _3p_remap_spear_to_polearm then remap_name = "spear→polearm"
        elseif remap == _3p_remap_billhook_to_polearm then remap_name = "billhook→polearm"
        else remap_name = "custom" end
    end
    mod:echo("3P Remap: " .. remap_name)
    mod:echo("Anim log: " .. (_log_anims and "ON" or "OFF"))
    if career then
        local weapons = weapon_unlock_map[career]
        if weapons then
            local enabled = 0
            for _, wk in ipairs(weapons) do
                if mod:get("unlock_" .. career .. "_" .. wk) then enabled = enabled + 1 end
            end
            mod:echo("Weapons: " .. enabled .. "/" .. #weapons .. " enabled")
        end
    end
end)

mod:command("animlog", "Toggle animation event logging", function()
    _log_anims = not _log_anims
    mod:echo("Animation logging: " .. (_log_anims and "ON" or "OFF"))
end)

mod:command("force3p", "Force a 3P animation event on local player (usage: /force3p attack_swing_stab)", function(event)
    -- CLARIFY: targets `player.player_unit` which is actually the 3P body
    -- (see CLAUDE.md "Animation Remapping"). Bypasses our own hook by calling
    -- `_original_animation_event` directly so the test isn't muddied by remap
    -- redirects — used to verify which raw events animate visibly on the
    -- currently-loaded weapon SM (per feedback_animation_remap_rules:
    -- has_animation_event TRUE does not guarantee visible playback).
    if not event then mod:echo("Usage: /force3p <event_name>") return end
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit then mod:echo("No local player unit") return end
    local unit = player.player_unit
    local ok_h, has = pcall(Unit.has_animation_event, unit, event)
    has = ok_h and has
    mod:echo("force3p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, unit, event)
        else
            pcall(Unit.animation_event, unit, event)
        end
        mod:echo("  -> fired on player_unit")
    else
        mod:echo("  -> event not found on player_unit")
    end
end)

mod:command("force1p", "Force a 1P animation event on local player's first-person unit (usage: /force1p attack_swing_stab)", function(event)
    -- Mirror of force3p but targets the 1P hands unit captured in the wield
    -- hook. Used to probe whether the currently-wielded weapon's 1P SM has a
    -- visible animation for an event that's not referenced by the template
    -- (e.g. searching for a hidden stab on bastard_sword).
    if not event then mod:echo("Usage: /force1p <event_name>") return end
    if not _local_fp_unit then mod:echo("No 1P unit captured (wield a weapon first)") return end
    local unit = _local_fp_unit
    local ok_h, has = pcall(Unit.has_animation_event, unit, event)
    has = ok_h and has
    mod:echo("force1p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, unit, event)
        else
            pcall(Unit.animation_event, unit, event)
        end
        mod:echo("  -> fired on first_person_unit")
    else
        mod:echo("  -> event not found on first_person_unit")
    end
end)

-- Keys are profile/character names. Warrior Priest (wh_priest career) shares
-- the witch_hunter profile but uses a distinct 3P skeleton, so it's listed
-- separately under its own key for `wt sm_probe`. Note: "way_watcher" is the
-- path for `we_` careers — VT2's source uses this naming.
local _3p_state_machine_paths = {
    empire_soldier            = "units/beings/player/third_person_base/empire_soldier/chr_third_person_base",
    witch_hunter              = "units/beings/player/third_person_base/witch_hunter/chr_third_person_base",
    witch_hunter_warrior_priest = "units/beings/player/third_person_base/witch_hunter_warrior_priest/chr_third_person_base",
    bright_wizard             = "units/beings/player/third_person_base/bright_wizard/chr_third_person_base",
    dwarf_ranger              = "units/beings/player/third_person_base/dwarf_ranger/chr_third_person_base",
    wood_elf                  = "units/beings/player/third_person_base/way_watcher/chr_third_person_base",
}

mod:command("sm_probe", "Probe what 3P state machine resources exist for all characters", function()
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player or not player.player_unit then
        mod:echo("No player unit")
        return
    end
    local unit_3p = player.player_unit
    local pkg = Managers.package

    local function log(msg)
        mod:echo(msg)
        mod:info("[PROBE] %s", msg)
    end

    for name, path in pairs(_3p_state_machine_paths) do
        local loaded = "?"
        if pkg then
            local ok_c, val = pcall(function() return pkg:has_loaded(path, "global") end)
            if ok_c then loaded = tostring(val)
            else loaded = "err" end
        end
        log(string.format("  %-16s loaded=%s", name, loaded))
    end

    local ok_sm, has_sm = pcall(Unit.has_animation_state_machine, unit_3p)
    log("3P has_animation_state_machine: " .. (ok_sm and tostring(has_sm) or "err"))

    local test_events = {
        "to_2h_sword", "to_2h_sword_we", "to_bastard_sword", "to_spear", "to_polearm",
        "to_1h_sword", "to_1h_hammer", "to_2h_billhook", "to_longbow", "to_es_longbow",
        "to_1h_sword_shield", "to_1h_hammer_shield", "to_dual_wield", "to_2h_hammer",
        "to_2h_axe", "to_1h_axe", "to_1h_falchion", "to_1h_flail", "to_crossbow",
        "to_repeating_crossbow", "to_handgun", "to_blunderbuss",
        "attack_swing_right", "attack_swing_left", "attack_swing_down",
        "attack_swing_up_left", "attack_swing_down_left", "attack_swing_down_right",
        "attack_swing_heavy", "attack_swing_heavy_right", "attack_swing_heavy_left",
        "attack_swing_heavy_down", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal",
        "attack_swing_charge", "attack_swing_charge_left", "attack_swing_charge_right",
        "attack_swing_charge_left_diagonal", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_down_pose", "attack_swing_charge_left_diagonal_pose",
        "attack_swing_charge_stab", "attack_swing_charge_down",
        "attack_swing_stab", "attack_swing_stab_02", "attack_swing_stab_lh",
        "attack_swing_left_diagonal", "attack_swing_down_left_axe",
        "attack_push", "push_stab", "parry_pose",
    }
    log("Events on 3P unit:")
    for _, ev in ipairs(test_events) do
        local ok_e, has = pcall(Unit.has_animation_event, unit_3p, ev)
        if ok_e and has then
            log(string.format("  %-40s TRUE", ev))
        else
            log(string.format("  %-40s false", ev))
        end
    end
end)


local function _is_local_player_unit(unit)
    local pm = Managers.player
    if not pm then return false end
    local ok, player = pcall(pm.local_player, pm)
    if not ok or not player then return false end
    return player.player_unit == unit
end

-- Returns the career name of the player who owns this unit (local or husk).
-- nil for non-player units. Use for per-unit redirect decisions so husks of
-- other players get routed by THEIR career, not the local viewer's.
local function _unit_career_name(unit)
    if not unit then return nil end
    -- Primary: career_system extension. CareerExtension is attached to both
    -- local player_units AND husks (unit_extension_templates.lua: line 12 for
    -- self-owned, line 75 for husks). Its init sets self._career_name directly
    -- from career_data.name (career_extension.lua:23) — the most authoritative
    -- source. v0.12.37 — was previously falling through to inventory_system
    -- first, but on remote-player husks (SimpleHuskInventoryExtension) the
    -- inventory extension's `_career_name` is only set if a Player object was
    -- passed in extension_init_data with a non-nil career_name() at init time.
    -- That's a real race on lobby-formed remote players. career_system has no
    -- such race — it pulls from career_data directly.
    local ok_career, career_ext = pcall(ScriptUnit.has_extension, unit, "career_system")
    if ok_career and career_ext and career_ext._career_name then return career_ext._career_name end
    -- Fallback: inventory_system extension. SimpleInventoryExtension.init sets
    -- self._career_name BEFORE extensions_ready fires, and our
    -- GearUtils.spawn_inventory_unit hook is called from within add_equipment
    -- (invoked from extensions_ready). Reliable for the local player even at
    -- fresh-mission-spawn timing when Managers.player:owner(unit) returns nil.
    -- See feedback_vt2_mission_spawn_career_lookup.
    local ok_ext, ext = pcall(ScriptUnit.has_extension, unit, "inventory_system")
    if ok_ext and ext and ext._career_name then return ext._career_name end
    -- Fallback: Managers.player path (post-spawn / husk lookups).
    local pm = Managers.player
    if not pm then return nil end
    local ok, player = pcall(pm.owner, pm, unit)
    if not ok or not player then return nil end
    local ok2, name = pcall(player.career_name, player)
    if ok2 and name then return name end
    local ok3, prof_idx = pcall(player.profile_index, player)
    local ok4, career_idx = pcall(player.career_index, player)
    if ok3 and ok4 and SPProfiles and prof_idx and career_idx then
        local prof = SPProfiles[prof_idx]
        local c = prof and prof.careers and prof.careers[career_idx]
        if c and c.name then return c.name end
    end
    return nil
end

-- v0.12.88-dev: sampling counters for hot-path _dbg traces. animation_event
-- fires on every animation event for every unit (per-frame-class hot path),
-- so emitting a _dbg line per call would flood the log. _ANIM_EVENT_SAMPLE_N
-- = 60 means roughly "log 1 in 60 calls" (~1/sec on a player wielding a
-- weapon). REMAP / FORCE / REDIR branches sample less aggressively because
-- they only fire on actual remap hits (cross-character ports), which are
-- rarer than the top-level call count. Per PROJECT_STANDARDS § 3.6
-- "Performance note: mod:get is cheap"; sampling is purely a log-volume
-- concern.
local _ANIM_EVENT_SAMPLE_N = 60
local _ANIM_EVENT_SAMPLE_REMAP_N = 30
local _anim_event_call_count = 0
local _anim_event_remap_count = 0

-- CLARIFY: stringified hook on the C-API class `Unit`. VMF resolves this
-- against `_G.Unit.animation_event`. This is the central entry point — every
-- animation event for every unit goes through here once the mod is loaded,
-- so cheap early-exits matter for performance.
mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
    -- CLARIFY: capture the underlying function the FIRST time we're called so
    -- force-fire paths (force3p command, billhook stab_02 force-target) can
    -- bypass our own hook recursively without infinite loop.
    if not _original_animation_event then _original_animation_event = func end

    if not event_name then return func(unit, event_name, ...) end

    -- v0.12.88-dev: sampled entry trace (1-in-60). This is the hottest hook
    -- in wt; full per-call _dbg would flood. Sample is enough to confirm the
    -- hook is firing at all + spot-check the event names flowing through.
    _anim_event_call_count = _anim_event_call_count + 1
    if _anim_event_call_count % _ANIM_EVENT_SAMPLE_N == 0 then
        _dbg("[wt:anim] event=enter event_name=%s sample=%d (1-in-%d)",
            tostring(event_name), _anim_event_call_count, _ANIM_EVENT_SAMPLE_N)
    end

    if not feature_enabled("enable_weapon_animation_redirects", true) then
        return func(unit, event_name, ...)
    end

    -- 1P first_person_unit must never get redirects — 1P animations work by
    -- default. See feedback_animation_remap_rules. 1P unit has is_local=false
    -- (same as husks), so we MUST identify it by its captured ref. v0.9.69
    -- crashed when is_local was used to protect 1P because it ALSO skipped
    -- redirects on the 3P body. Moved AHEAD of state lookups so we don't
    -- waste work on 1P events.
    if _local_fp_unit and unit == _local_fp_unit then
        return func(unit, event_name, ...)
    end

    local is_local = _is_local_player_unit(unit)
    if not is_local then _last_3p_unit = unit end

    -- v0.12.35 — resolve career FROM THE UNIT, not the local player. Husks of
    -- remote players need their OWN career to drive redirects; using the
    -- local viewer's career hijacked every other player's animations whenever
    -- their career/weapon didn't happen to match ours. Falls back to the local
    -- career only if the unit lookup fails (e.g. very early in spawn).
    local career = _unit_career_name(unit) or (is_local and _local_career_name()) or nil
    local state = _state_for(unit)

    -- ============================================================
    -- [wt:play] dev-picker play-path trace (v0.12.145-dev) — LOGGING ONLY.
    -- ============================================================
    -- Diagnose-before-mitigate: prove WHERE a picked anim_event_3p is lost
    -- between the menu write and the engine. Scoped tightly so it stays
    -- readable: only fires for the LOCAL 3P body, only while wielding one of the
    -- picker's flagged-weapon templates, only for combat events (attack_/push_/
    -- parry_), and only when the dev picker toggle is ON.
    --
    -- HOW IT WORKS: when the gate is active we (a) log the event the ENGINE READ
    -- (event_name as start_action passed it — this is the live
    -- current_action_settings.anim_event_3p the picker mutated, OR the template
    -- default if the pick didn't take), and (b) wrap `func` so EVERY downstream
    -- call in this hook logs the FINAL event actually handed to the engine. If
    -- the funnel renames the picked event, the FINAL line differs from the READ
    -- line and names the rename — that's the override hypothesis, confirmed or
    -- refuted per event. (The one FORCE path that calls `_original_animation_event`
    -- directly is gated on state.remap == spear_to_billhook, which never applies
    -- to any picker weapon, so wrapping only `func` is complete coverage here.)
    if is_local and event_name and state and state.template
        and (event_name:sub(1, 7) == "attack_" or event_name:sub(1, 5) == "push_" or event_name:sub(1, 6) == "parry_")
        and mod:get("enable_dev_anim_picker")
        and _wt_dev_anim_picker and _wt_dev_anim_picker.is_picker_template
        and _wt_dev_anim_picker.is_picker_template(state.template) then
        -- On the 3P body the engine fires the picked anim_event_3p VALUE directly
        -- (weapon_unit_extension.lua:512). So `event_name` here SHOULD be one of
        -- the picker's set 3P values if the pick took. is_picked_3p tells us
        -- whether the read event is a picked value (pick reached the engine) or a
        -- template default (pick lost UPSTREAM — apply n==0, wrong template, or
        -- never written). The live_3p_map dump shows what the picks currently are.
        local is_picked_3p = _wt_dev_anim_picker.is_picked_3p_value(state.template, event_name)
        local map = _wt_dev_anim_picker.live_3p_map(state.template)
        local map_parts = {}
        for src, val in pairs(map) do map_parts[#map_parts + 1] = tostring(src) .. "->" .. tostring(val) end
        table.sort(map_parts)
        mod:info("[wt:play] READ event=%s tmpl=%s key=%s career=%s is_picked_3p_value=%s has_anim=%s picks_set={%s}",
            tostring(event_name), tostring(state.template), tostring(state.key),
            tostring(career), tostring(is_picked_3p), tostring(_safe_has_anim(unit, event_name)),
            table.concat(map_parts, ","))
        local _wt_play_orig_func = func
        func = function(u, ev, ...)
            -- Logs the FINAL event the engine receives AFTER wt's funnel. If it
            -- differs from the read event, wt renamed it — the override
            -- hypothesis, confirmed/refuted per swing.
            mod:info("[wt:play] FINAL event=%s (read was %s)%s has_anim=%s",
                tostring(ev), tostring(event_name),
                (tostring(ev) ~= tostring(event_name)) and " <<RENAMED BY FUNNEL>>" or " (unchanged)",
                tostring(_safe_has_anim(u, ev)))
            return _wt_play_orig_func(u, ev, ...)
        end
    end

    if _log_anims then
        local _al_tag = is_local and "3P-body" or "3P-husk"
        local is_combat = event_name:sub(1, 7) == "attack_" or event_name:sub(1, 5) == "push_" or event_name:sub(1, 3) == "to_" or event_name:sub(1, 6) == "parry_"
        local exists = _safe_has_anim(unit, event_name)
        local suffix = exists and "" or " [MISSING]"
        if is_combat then
            if not _animlog_last_was_attack then
                local s_tmpl = state and state.template
                local s_key = state and state.key
                local hdr = "--- [template: " .. tostring(s_tmpl) .. "] [key: " .. tostring(s_key) .. "] [career: " .. tostring(career) .. "] ---"
                mod:info(hdr)
                mod:echo("--- " .. tostring(s_key or s_tmpl) .. " ---")
            end
            _animlog_last_was_attack = true
            local msg = _al_tag .. " " .. event_name .. suffix
            mod:info(msg)
            mod:echo(msg)
        else
            _animlog_last_was_attack = false
            mod:info("[animlog] " .. _al_tag .. " " .. event_name .. suffix)
        end
    end

    -- Reset this UNIT's 3P weapon remap on actual weapon change. The
    -- whitelist-by-template-change pattern from DEVELOPMENT.md "Non-Weapon
    -- `to_` Events": non-weapon `to_` events (to_crouch / to_zoom / to_onground)
    -- don't change state.template/key, so `remap_id == state.last_remap_id`
    -- and we skip the clear. Only true weapon switches (which update those
    -- via the wield hook) reach the clear-and-reset block.
    --
    -- v0.12.35 — was previously gated on `is_local`. The same logic applies
    -- per-unit: husks switching weapons should re-resolve their own remap.
    local remap_id = state and (state.template or state.key)
    if state and event_name:sub(1, 3) == "to_" and remap_id and remap_id ~= state.last_remap_id then
        state.last_remap_id = remap_id
        state.remap = nil
        if state.template then
            local tmpl_remap = _resolve_template_remap(state.template, career)
            if tmpl_remap then state.remap = tmpl_remap end
        end
        if not state.remap and state.key then
            local key_remap = _resolve_key_remap(state.key, career)
            if key_remap then state.remap = key_remap end
        end
        -- tmpl_remap / key_remap may be `false` (deliberate skip from
        -- `_3p_template_remaps[name][prefix] = false`). `if tmpl_remap then`
        -- treats false as "not found" and falls through to key_remap. Final
        -- state.remap ends up nil if both were false — desired (native plays).
        --
        -- v0.12.64-dev — Fallback to `_resolve_3p_remap(event_name, career)`
        -- when neither template nor key remap hits.
        --
        -- Bug: when `_WIELD_ANIM_CAREER_3P_PATCHES` (line 1931, added v0.12.55/56)
        -- pre-rewrites a template's `wield_anim_career_3p[<career>]` at boot,
        -- the ENGINE fires the rewritten event (e.g. `to_polearm` for Kruber-on-
        -- billhook), not the original (`to_2h_billhook`). The
        -- `_career_anim_redirect.to_polearm` override branch never installs
        -- `state.remap` because that table's overrides[es_*] is nil — the
        -- redirect was designed for the `to_2h_billhook → to_polearm` redirect
        -- path, not the already-rewritten-by-patcher path.
        --
        -- Result before this fallback: Kruber-on-billhook reaches polearm
        -- stance correctly via the patcher, but billhook-specific attack
        -- events (`attack_swing_stab`, `attack_swing_left_diagonal`,
        -- `attack_swing_charge_stab`, etc.) fire raw on Kruber's polearm SM
        -- and silently no-op — visible as missing swing animations.
        --
        -- Fix: when template/key resolution doesn't hit, ask `_3p_remap_triggers`
        -- whether the wield event (now potentially the patcher-rewritten value)
        -- has an associated career-prefix remap. The same lookup already powers
        -- the override branch at line ~1127 and the redirect branch at line
        -- ~1156; we're now also calling it from the wield-event path so the
        -- swing remap installs regardless of which path the wield event took.
        --
        -- Symmetric coverage: the elf-spear-on-Saltzpyre case (which the
        -- patcher rewrites `to_spear → to_2h_billhook` for wh_*) gets the
        -- same fallback for the inverse mapping.
        if not state.remap then
            local trigger_remap = _resolve_3p_remap(event_name, career)
            if trigger_remap then state.remap = trigger_remap end
        end
    end

    -- Flails on non-native careers: certain release events either play the
    -- wrong animation or play nothing on the cross-career 3P body, even
    -- though has_animation_event reports them TRUE. attack_swing_heavy is
    -- the only event that produces a visible heavy strike on both flails.
    -- We can't use the remap table — adding these events to it corrupts the
    -- SM chain (same pattern as billhook attack_swing_stab_02). Direct
    -- func() call works.
    --
    -- v0.12.35 — was previously is_local-only because the global
    -- `_current_weapon_key` tracked only the local viewer. Now uses
    -- state.key (per-unit weapon) and unit career, so a remote Saltzpyre
    -- husk wielding es_1h_flail also gets the fix on the local viewer's
    -- screen. The flail-key gate is what keeps this from hijacking other
    -- weapons that fire the same event names.
    if state and career then
        local target = nil
        if state.key == "es_1h_flail" then
            if career:sub(1, 3) ~= "wh_" then
                -- Saltzpyre's flail on non-Saltzpyre. H1 release fires
                -- attack_swing_left (light name → wrong anim), H2 release
                -- fires attack_swing_heavy_left (plays nothing on the
                -- cross skeleton).
                if event_name == "attack_swing_left"
                    or event_name == "attack_swing_heavy_left" then
                    target = "attack_swing_heavy"
                end
            else
                -- Saltzpyre native: push-attack release fires
                -- attack_swing_right but doesn't visibly animate (vanilla
                -- SM bug — confirmed via wt force3p from idle).
                -- attack_swing_right_diagonal plays a visible L2-style
                -- swing on Saltzpyre's flail SM, best stand-in.
                if event_name == "attack_swing_right" then
                    target = "attack_swing_right_diagonal"
                end
            end
        elseif state.key == "bw_1h_flail_flaming"
            and career:sub(1, 3) ~= "bw_" then
            -- Sienna's flaming flail on non-Sienna. H1 release
            -- (attack_swing_heavy_down) fires natively as the correct
            -- overhead — DO NOT touch it. Only H2 (attack_swing_heavy_left)
            -- is broken and needs the redirect.
            if event_name == "attack_swing_heavy_left" then
                target = "attack_swing_heavy"
            end
        end
        if target then
            return func(unit, target, ...)
        end
    end

    -- 3P attack remap (per-unit)
    if state and state.remap then
        local target = state.remap[event_name]
        if target and _safe_has_anim(unit, target) then
            if _log_anims then
                local msg = "  REMAP " .. event_name .. " -> " .. target
                mod:info(msg)
                mod:echo(msg)
            end
            -- v0.12.88-dev: sampled _dbg trace (1-in-N). Cross-character
            -- anim REMAP path is rarer than the top-level hook fire rate
            -- (only fires when state.remap is populated AND the source
            -- event has a substitute), so 1-in-30 is enough to confirm
            -- the path is hit without flooding mid-combat. Captures
            -- career so combo bugs ("REMAP fires for the wrong career")
            -- are visible.
            _anim_event_remap_count = _anim_event_remap_count + 1
            if _anim_event_remap_count % _ANIM_EVENT_SAMPLE_REMAP_N == 0 then
                _dbg("[wt:anim] event=REMAP src=%s -> tgt=%s career=%s tmpl=%s key=%s sample=%d",
                    tostring(event_name), tostring(target), tostring(career),
                    tostring(state.template), tostring(state.key), _anim_event_remap_count)
            end
            pcall(func, unit, target, ...)
            return
        end
        -- Force-fire path for SM-corrupting events (see
        -- feedback_animation_remap_rules). Adding `attack_swing_stab_02 ->
        -- attack_swing_left_diagonal` to the remap table broke ALL
        -- animations on the billhook SM (v0.9.43); calling
        -- _original_animation_event directly with the same target works.
        -- Block is GUARDED to only fire when the spear-to-billhook remap
        -- is active (v0.9.56 — without this guard, the billhook force-fires
        -- hijacked Kruber's spear+shield H1/H2).
        local force_target = nil
        if state.remap == _3p_remap_spear_to_billhook then
            if event_name == "attack_swing_stab_02" then
                force_target = "attack_swing_left_diagonal"
            elseif event_name == "attack_swing_heavy_left" then
                force_target = "attack_swing_heavy_stab"
            elseif event_name == "attack_swing_heavy_stab" then
                force_target = "attack_swing_heavy_left_diagonal"
            end
        end
        if force_target and _original_animation_event and _safe_has_anim(unit, force_target) then
            if _log_anims then
                local msg = "  FORCE " .. event_name .. " -> " .. force_target
                mod:info(msg)
                mod:echo(msg)
            end
            pcall(_original_animation_event, unit, force_target)
            return
        end
    end

    -- Career-aware redirects: phantom events exist on all skeletons but only
    -- play real animations on the correct character. Redirect by career prefix.
    local career_redir = _career_anim_redirect[event_name]
    if career_redir then
        if career_redir.overrides and career and career_redir.overrides[career] then
            local target = career_redir.overrides[career]
            if _safe_has_anim(unit, target) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap and state then state.remap = remap end
                if _log_anims then
                    local msg = "  REDIR " .. event_name .. " -> " .. target
                    mod:info(msg)
                    mod:echo(msg)
                end
                pcall(func, unit, target, ...)
                return
            elseif _log_anims then
                mod:info("  REDIR FAIL: " .. target .. " not on unit")
            end
        end
        local matches_prefix = career and career:sub(1, #career_redir.prefix) == career_redir.prefix
        -- v0.12.60: gate redirect on a resolved career. When career=nil
        -- (preview units — MenuWorldPreviewer's character_unit has no
        -- career_system extension), `matches_prefix` is false, which made
        -- the prior `should_redirect` formula evaluate true and fire the
        -- cross-character redirect on any unit that happened to author the
        -- alt event. Kruber's preview body authors BOTH `to_polearm` and
        -- `to_spear`, so previewing halberd / Tuskgor / billhook (all
        -- resolving to `to_polearm` via wield_anim_career_3p) silently
        -- routed through `to_polearm → to_spear` and landed the body in
        -- the wrong stance. The redirect mechanism is only meant for
        -- in-mission cross-character ports where the wielder's career is
        -- known; for anonymous units, fall through to native firing.
        local should_redirect = career and (career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix))
        if should_redirect then
            if _safe_has_anim(unit, career_redir.alt) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap and state then state.remap = remap end
                if _log_anims then
                    local msg = "  REDIR " .. event_name .. " -> " .. career_redir.alt
                    mod:info(msg)
                    mod:echo(msg)
                end
                pcall(func, unit, career_redir.alt, ...)
                return
            elseif _log_anims then
                mod:info("  REDIR FAIL: " .. career_redir.alt .. " not on unit")
            end
        end
        pcall(func, unit, event_name, ...)
        return
    end

    -- Standard redirect: only fire if original event is missing from skeleton.
    local alt = _anim_redirect[event_name]
    if alt then
        if _safe_has_anim(unit, event_name) then
            return func(unit, event_name, ...)
        end
        if _safe_has_anim(unit, alt) then
            pcall(func, unit, alt, ...)
            return
        end
    end

    -- Suffix-based redirect: swap weapon suffix based on career.
    if career then
        local target = _try_suffix_redirect(unit, event_name, career)
        if target then
            if _log_anims then mod:info("  SUFFIX -> " .. target) end
            pcall(func, unit, target, ...)
            return
        end
    end

    pcall(func, unit, event_name, ...)
end)

-- Pull item_data for the slot being wielded and copy template/key into the
-- per-unit state. Shared by both wield hooks below.
local function _populate_unit_state_from_wield(self, slot_name)
    local unit = self._unit
    if not unit then return end
    local equipment = self._equipment or self.equipment
    local slots = equipment and equipment.slots
    local slot_data = slots and slots[slot_name]
    local item_data = slot_data and slot_data.item_data
    if not item_data then return end
    local s = _state_for(unit)
    if s then
        s.template = item_data.template
        s.key = item_data.key
    end
end

-- Local-player wield. Populates state AND captures the 1P hands unit ref
-- (needed for the redirect-skip early-return in the animation_event hook).
-- v0.12.77 (Issue #26): converted to `mod:safe_hook` — this hook fans out
-- to per-unit state population + diagnostic dumps; a raise inside here
-- previously could silently kill every later wield consumer in the chain
-- (cosmetics_tweaker / LA / cwv all stack on the same Class.method).
-- v0.12.84-dev: promoted to `mod:traced_hook` (Layer 3) — wield is event-rate
-- (one fire per slot swap, NOT per-frame), so trace lines are safe. With
-- enable_debug_logging on, every wield emits paired
-- `[wt:trace] event=enter|exit class=SimpleInventoryExtension method=wield`
-- lines. Catches "did the wield hook fire?" diagnostics without grepping
-- through downstream state population logs.
mod:traced_hook("SimpleInventoryExtension", "wield", function(func, self, slot_name, ...)
    _populate_unit_state_from_wield(self, slot_name)

    -- Local-only side effects: capture the 1P hands unit ref and log details.
    local ok, pm = pcall(function() return Managers.player end)
    if ok and pm then
        local player = pm:local_player()
        if player and self._unit == player.player_unit then
            _local_fp_unit = self._first_person_unit
            if _log_anims then
                local s = _state_for(self._unit)
                mod:info("[WIELD] slot=" .. tostring(slot_name) .. " template=" .. tostring(s and s.template) .. " key=" .. tostring(s and s.key))
                local equipment = self._equipment or self.equipment
                local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
                local item_data = slot_data and slot_data.item_data
                if item_data then
                    for k, v in pairs(item_data) do
                        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                            mod:info("[WIELD]   " .. tostring(k) .. " = " .. tostring(v))
                        end
                    end
                else
                    mod:info("[WIELD] item_data is nil, slot_data=" .. tostring(slot_data))
                end
            end

            -- v0.12.74-dev: debug-mode wield diagnostic. Separate from the
            -- `_log_anims`/`/animlog`-driven block above so users can enable
            -- the universal `enable_debug_logging` toggle from the VMF
            -- settings panel without also touching the chat-command
            -- animation log. Cache the toggle once to avoid two `mod:get`
            -- calls per wield. (v0.12.81-dev: renamed from `wt_debug_mode`.)
            --
            -- Fields chosen are the ones that drive 3P presentation on
            -- the receiver: career_name (3P skeleton selector — see
            -- _3p_state_machine_paths block above), item_key, template,
            -- and the template's `anim_event_3p` + `wield_anim_3p`
            -- (the per-template default 3P clip names). The actual 3P
            -- skeleton path is derived from career_name via the profile
            -- (e.g. `wh_` -> witch_hunter base, `es_` -> empire_soldier).
            local s = _state_for(self._unit)
            local equipment = self._equipment or self.equipment
            local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
            local item_data = slot_data and slot_data.item_data
            local item_key = (item_data and (item_data.key or item_data.name)) or "?"
            local template = (s and s.template) or (item_data and item_data.template) or "?"
            local tmpl_tbl = Weapons and Weapons[template]
            local anim_event_3p = (tmpl_tbl and tmpl_tbl.anim_event_3p) or "?"
            local wield_anim_3p = (tmpl_tbl and tmpl_tbl.wield_anim_3p) or "?"
            local career_name = self._career_name or "?"
            _dbg("[wield] slot=%s career=%s key=%s template=%s anim_event_3p=%s wield_anim_3p=%s",
                tostring(slot_name), tostring(career_name),
                tostring(item_key), tostring(template),
                tostring(anim_event_3p), tostring(wield_anim_3p))
        end
    end
    return func(self, slot_name, ...)
end)

-- Husk (remote-player) wield. SEPARATE CLASS from SimpleInventoryExtension —
-- per unit_extension_templates.lua, husk_extensions uses SimpleHuskInventoryExtension
-- (line 71). v0.12.35 hooked only the self-owned class, so remote players'
-- weapon switches never populated _unit_state[husk_unit] on the local viewer's
-- machine, and the animation_event hook had no per-husk weapon info to drive
-- redirects. Adding the parallel hook here completes the per-unit state plumbing
-- for the multiplayer case.
--
-- No local side effects — husks never represent the local viewer's 1P hands.
-- v0.12.77 (Issue #26): converted to `mod:safe_hook` — same chain-isolation
-- rationale as the local-player wield above. Husk wield is the entry point
-- for cross-character 3P remap on every non-local peer in multiplayer.
mod:safe_hook("SimpleHuskInventoryExtension", "wield", function(func, self, slot_name, ...)
    _populate_unit_state_from_wield(self, slot_name)
    return func(self, slot_name, ...)
end)

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

    local scale_factor = nil
    for prefix, factor in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            scale_factor = factor
            break
        end
    end
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

-- Grip offset: shift weapon along its local axes to adjust hand position.
-- Values are {x, y, z} in the weapon's local space. +z = grip lower on weapon.
-- Optional `hand` field: "right" or "left" restricts to one hand (default both).
-- Same dual-path note as scale (above): in-game and menu preview both apply
-- via the same helper.
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
    -- NOTE: this table is the SINGLE SOURCE OF TRUTH for every 3P grip nudge
    -- (preview AND in-game read it). Two application paths consume it:
    --   * SMALL static nudges (the 0.05-0.15 entries above): a one-shot additive
    --     write at create_equipment / preview spawn via _offset_weapon_units. Fine
    --     for small deltas the engine's per-frame attachment re-apply doesn't
    --     visibly disturb.
    --   * STOMP-PRONE large offsets (the scythe): ALSO listed in
    --     _DURABLE_GRIP_OFFSETS below, which re-applies the SAME value every frame
    --     in-game so the engine's per-tick canonical-pose reset can't erase it.
    -- NEVER bake a tuned hold-pose value as a raw
    -- unit_attachment_node_linking.third_person write on a SHARED template
    -- (staff_scythe is shared with Sienna) — that breaks the native wielder. The
    -- durable re-apply is career-gated to es_ instead. (es_handgun-on-Saltzpyre
    -- offset was mis-baked into a linking table in v0.12.135 and reverted in .136.)
    -- Full rationale + the preview-OK/in-game-wrong post-mortem: OFFSETS.md.
}

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
--   every frame keeps the value visible"). So a large grip drop (the +6 scythe)
--   looked right in preview and reverted to raw position in-game.
--
-- HOW THE DURABLE PATH WORKS:
--   For weapon_keys listed here, _reapply_durable_grip_offsets() runs every frame
--   (driven from weapon_tweaker_backend.lua's mod.update) on the LOCAL player's
--   wielded 3P weapon unit(s). It is ADDITIVE-from-canonical: it reads the
--   freshly-reset canonical local_position the engine just wrote this tick and
--   adds the offset, so the result is stable frame-to-frame and NEVER compounds
--   (the read-and-add is safe ONLY because the engine resets node 0 each tick;
--   that reset is the very thing that makes a one-shot fail). This matches the
--   ADDITIVE semantics of the one-shot preview path (current + pos), so the SAME
--   value in _weapon_grip_offsets means the same thing in both views.
--
-- INVARIANTS (do not break):
--   * 3P-ONLY: writes only right_unit_3p / left_unit_3p. NEVER 1P (universal
--     first person, the user's hard rule — feedback_cross_char_transforms_3p_only).
--   * CAREER-ONLY: gated on the same prefix match as _offset_weapon_units, so
--     only the receiving career (es_ = Kruber) is moved; the native wielder
--     (Sienna's bw_*) finds no prefix and is untouched.
--   * LOCAL player only (owner-authoritative; husks re-pose from their own host
--     anyway). Keeps the per-frame cost to one unit.
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
}

local function _offset_weapon_units(slot_data, weapon_key, career_name)
    if not weapon_key or not career_name then return end

    local overrides = _weapon_grip_offsets[weapon_key]
    if not overrides then return end

    local offset = nil
    for prefix, off in pairs(overrides) do
        if career_name:sub(1, #prefix) == prefix then
            offset = off
            break
        end
    end
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
            -- POTENTIAL BUG (LOW): `Unit.local_position` is NOT pcall-wrapped
            -- (only set_local_position is). If `unit` is invalid/destroyed
            -- between the `if unit then` check and this line, this crashes
            -- the whole hook. Same wrap pattern as scale would be safer.
            -- POTENTIAL BUG (LOW): if create_equipment fires multiple times for
            -- the same unit instance (e.g. weapon swap that re-wields the same
            -- key), the offset compounds (current = previous_offset_position).
            -- Vanilla units start at zero local_position so the first apply
            -- is correct; subsequent applies double up. Not currently a known
            -- issue because spawning re-creates the unit instance.
            local current = Unit.local_position(unit, 0)
            pcall(Unit.set_local_position, unit, 0, current + pos)
        end
    end
    _dbg("Offset %s on %s by {%.3f, %.3f, %.3f} (hand=%s)", weapon_key, career_name, offset[1], offset[2], offset[3], tostring(hand or "both"))
end

-- Resolve the career-prefix-matched offset entry for (weapon_key, career_name)
-- from _weapon_grip_offsets. Returns the {x, y, z[, hand]} array or nil. Shared
-- by the one-shot path above and the durable per-frame re-apply below so both
-- read the SAME single source of truth with identical prefix-match semantics.
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

-- DURABLE per-frame grip-offset re-apply (see _DURABLE_GRIP_OFFSETS header).
-- Called every frame from weapon_tweaker_backend.lua's mod.update. Re-applies
-- the scythe's (and any future _DURABLE_GRIP_OFFSETS member's) grip offset to
-- the LOCAL player's wielded 3P weapon unit(s) so the engine's per-tick
-- canonical-pose reset can't stomp it. 3P-ONLY, career-gated, additive-from-
-- canonical (read the freshly-reset local_position + add offset = stable, never
-- compounds — see header). Exposed on the mod table because the backend module
-- is a separate dofile scope (mod:dofile is NOT a singleton —
-- reference_vmf_dofile_not_singleton); the function closes over the file-scope
-- _weapon_grip_offsets / _DURABLE_GRIP_OFFSETS here, the single source of truth.
function mod._reapply_durable_grip_offsets()
    if not next(_DURABLE_GRIP_OFFSETS) then return end

    local career_name = _local_career_name()
    if not career_name then return end

    local pm = Managers and Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    local punit = lp and lp.player_unit
    if not punit then return end

    local inv = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(punit, "inventory_system")
    if not inv then return end

    -- Identify the wielded weapon key. Only re-apply if it's a durable member;
    -- otherwise this is a cheap early-out on the common (non-scythe) frame.
    local slot_name = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
    if not slot_name then return end
    local equipment = inv._equipment
    if not equipment then return end
    local slot_data = equipment.slots and equipment.slots[slot_name]
    local weapon_key = slot_data and (slot_data.id
        or (slot_data.item_data and slot_data.item_data.key))
    if not weapon_key or not _DURABLE_GRIP_OFFSETS[weapon_key] then return end

    local offset = _resolve_grip_offset(weapon_key, career_name)
    if not offset then return end  -- career not in this weapon's offset map (e.g. Sienna native)

    local pos = Vector3(offset[1], offset[2], offset[3])
    local hand = offset.hand
    -- 3P-ONLY (never *_unit_1p). The currently-wielded 3P units are the live
    -- ones the engine is re-posing each frame, so these are exactly what gets
    -- stomped without this re-apply.
    local right_3p = equipment.right_hand_wielded_unit_3p
    local left_3p  = equipment.left_hand_wielded_unit_3p
    local function apply(unit)
        if unit and Unit.alive and Unit.alive(unit) then
            -- ADDITIVE-from-canonical: read the engine's just-reset local pos and
            -- add the offset. Stable frame-to-frame; never compounds because the
            -- engine reset zeroes our prior write before we read.
            local ok_cur, current = pcall(Unit.local_position, unit, 0)
            if ok_cur and current then
                pcall(Unit.set_local_position, unit, 0, current + pos)
            end
        end
    end
    if hand == "right" then
        apply(right_3p)
    elseif hand == "left" then
        apply(left_3p)
    else
        apply(right_3p)
        apply(left_3p)
    end
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
        return nil
    end
    if result and item_data then
        local weapon_key = item_data.name
        _scale_weapon_units(result, weapon_key, career_name)
        _offset_weapon_units(result, weapon_key, career_name)
    end
    return result
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

local _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
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
    -- The Empire longbow is native to es_HUNTSMAN only (can_wield). On the OTHER
    -- Kruber careers it is a CROSS-CAREER unlock whose 3P longbow aim state does not
    -- drive the native `draw_bow`, so the charged aim/zoom (action_two, kind="aim",
    -- anim_event="draw_bow") must render via the universal `to_zoom` — exactly as it
    -- did before v0.12.191, when the (now-removed) global mutation applied to_zoom to
    -- everyone. Native Huntsman keeps `draw_bow` (that was #210). Keyed by FULL career
    -- name so es_huntsman is excluded from the crossbow remap. (#210 follow-up.)
    _3p_template_remaps.longbow_empire_template = _3p_template_remaps.longbow_empire_template or {}
    _3p_template_remaps.longbow_empire_template.es_mercenary      = _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _3p_template_remaps.longbow_empire_template.es_knight         = _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _3p_template_remaps.longbow_empire_template.es_questingknight = _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _3p_template_remaps.longbow_empire_template.wh_               = _SP_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:tpl_patch] event=applied template=longbow_empire_template career_overrides=%d (wield) + runtime remap for cross-career es_ (Merc/FK/GK) + wh_; native es_huntsman untouched",
        n_career_overrides)
end

_patch_longbow_empire_template_for_saltzpyre()

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
local _WIELD_PATCHES_MODULE = mod:dofile("scripts/mods/weapon_tweaker/wt_wield_patches")
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
-- network-REGISTERED Kruber repeating-handgun events, which Kruber's
-- empire_soldier 3P body authors AND which exist in NetworkLookup.anims:
--   to_repeating_handgun         (anims_lookup_table.lua:670 — handgun has no
--                                 distinct not-loaded wield; its loaded wield is
--                                 the correct fallback)
--   to_repeating_handgun_noammo  (anims_lookup_table.lua:671 — handgun's own
--                                 wield_anim_no_ammo, repeating_handguns.lua:312)
-- These are 3P wield-FALLBACK fields only — never anim_event/wield_anim (1P).
-- Saltzpyre's Volley Crossbow (wh_crossbow_repeater, repeating_crossbows.lua)
-- already uses to_repeating_crossbow / _noammo (both REGISTERED) so it never
-- crashed — no patch needed there. Do NOT instead register the `_elf` names into
-- _anim_redirect (lines ~484-485): those redirect ONTO the same unregistered
-- `_elf` events and carry this identical latent crash for any non-elf wielder;
-- they're only safe today because they ride the direct (non-networked)
-- Unit.animation_event path behind _safe_has_anim.
local _KRUBER_REPEATER_CAREERS = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
}
local _NOT_LOADED_NO_AMMO_CAREER_PATCHES = {
    -- we_crossbow_repeater (Kerillian Repeater Crossbow) ported onto Kruber.
    repeating_crossbow_elf_template = {
        not_loaded = "to_repeating_handgun",
        no_ammo    = "to_repeating_handgun_noammo",
        careers    = _KRUBER_REPEATER_CAREERS,
    },
}

local function _apply_not_loaded_no_ammo_career_patches(patches)
    if not Weapons then return end
    for template_name, spec in pairs(patches) do
        local tpl = Weapons[template_name]
        if tpl then
            tpl.wield_anim_not_loaded_career = tpl.wield_anim_not_loaded_career or {}
            tpl.wield_anim_no_ammo_career   = tpl.wield_anim_no_ammo_career   or {}
            local n = 0
            for _, career in ipairs(spec.careers) do
                if spec.not_loaded then tpl.wield_anim_not_loaded_career[career] = spec.not_loaded end
                if spec.no_ammo    then tpl.wield_anim_no_ammo_career[career]    = spec.no_ammo end
                n = n + 1
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
-- table hook here intercepts EVERY spawn path (preview AND in-mission). Purely
-- subtractive -- only links whose node is genuinely absent (which would fatal anyway)
-- are dropped; valid links are untouched, so it can NOT regress visibility (cf. the
-- v0.12.112/.113 global-mutation bug that broke elf bows -- this never mutates valid data).
-- WT_LINK_UNITS_NODE_GUARD_MARKER

-- Pure, engine-free filter (unit-testable): drop links whose source/target node is
-- absent. src_has(name)/tgt_has(name) are node-presence predicates. Returns
-- (linking, dropped): the ORIGINAL table when nothing drops (zero-copy fast path),
-- else a filtered contiguous copy. On `mod` (not a new file-scope local) so the
-- end-of-file regression test can reach it without tripping the 200-locals cap.
mod._wt_link_filter = function(linking, src_has, tgt_has)
    local safe, dropped = nil, 0
    local n = #linking
    for i = 1, n do
        local e = linking[i]
        local ok = (type(e.source) ~= "string" or src_has(e.source))
               and (type(e.target) ~= "string" or tgt_has(e.target))
        if ok then
            if safe then safe[#safe + 1] = e end
        else
            if not safe then
                safe = {}
                for j = 1, i - 1 do safe[j] = linking[j] end
            end
            dropped = dropped + 1
        end
    end
    return (safe or linking), dropped
end

if GearUtils and GearUtils.link_units and Unit and Unit.has_node then
    mod:hook(GearUtils, "link_units", function(func, world, attachment_node_linking, link_table, source, target)
        if type(attachment_node_linking) == "table" and source and target then
            local filtered, dropped = mod._wt_link_filter(
                attachment_node_linking,
                function(name) return Unit.has_node(source, name) end,
                function(name) return Unit.has_node(target, name) end)
            if dropped > 0 then
                _dbg("[wt:link_guard] dropped %d attachment link(s) with a missing source/target node (would engine-fatal)", dropped)
                return func(world, filtered, link_table, source, target)
            end
        end
        return func(world, attachment_node_linking, link_table, source, target)
    end)
end

-- ============================================================
-- Authentic Brace of Pistols — toggleable flintlock-style override
-- ============================================================
-- Patches `Weapons.brace_of_pistols_template_1` in place when the
-- `authentic_brace_of_pistols` VMF setting is ON at mod init. Five
-- changes, all toggleable via the one setting:
--
--   1. Damage: every firing sub-action's `impact_data.damage_profile`
--      switches from `shot_carbine` (vanilla brace) to a clone of
--      `shot_sniper` (Kruber's handgun) with the near→far dropoff
--      flattened AND cleave_distribution halved (≈2x penetration:
--      from ~3 targets → ~6). Plus `ignore_shield_hit = true` on the
--      sub-action, which is what lets the handgun ignore shields.
--      Combined effect: armor-piercing, shield-breaking, full damage at
--      all ranges, passes through ~6 enemies.
--   2. Right-click is left vanilla. Lock-target / fast_shot rapid-fire
--      kept intact. (Previous revisions tried to disable or replace it
--      with a handgun-style zoom — both reverted in v0.12.15 because
--      rapid fire was reachable via paths we couldn't fully exorcise.
--      v0.12.19-v0.12.21 instead make secondary fire deliberately less
--      accurate than primary — see step 5. Speed was slowed in v0.12.19
--      then brought back to vanilla in v0.12.21 — see step 7.)
--   3. Manual reload re-enabled (v0.12.19). User wants single-shot
--      manual reload back; `weapon_reload.default` condition_funcs are
--      left vanilla. `auto_reload` chain is unchanged.
--   4. Ammo: `ammo_per_clip = 6`, `ammo_per_reload = 1`, `max_ammo = 12`.
--      Six rounds in the mag, six rounds in reserve, reloads one shot at
--      a time. (Vanilla: clip 12 / reload 2 / max 30. v0.12.16-v0.12.18:
--      clip 12 / reload 12 / max 12, no-reserve.) Each manual reload
--      animation loads one round; player can keep tapping R to top up
--      the clip one round at a time, can interrupt with a shot. Matches
--      a flintlock-pistol-bandolier feel.
--   6. (Removed in v0.12.15) fast_shot chain rewrite. Reverted along with
--      step 2; rapid fire is allowed.
--   7. Action speed: PRIMARY/all-other actions run at 2x speed (mult 0.5);
--      SECONDARY FIRE (`action_one.fast_shot` rapid-fire cadence) runs at
--      VANILLA speed (mult 1.0 — was 2.0 in v0.12.19-v0.12.20; user asked
--      to double it in v0.12.21). Chain-into-fast_shot start_times from
--      any source action also use the slow mult, so entering rapid fire
--      from RMB now takes the vanilla delay. Walks `tpl.actions[*][*]`
--      and scales `total_time`, `total_time_secondary`, `fire_time`,
--      `minimum_hold_time`, `cooldown`, `reload_time`, and every chain
--      `start_time`. 0/math.huge are skipped. The split walker is kept
--      even though mult=1.0 is a no-op, so future re-tunes (1.3, 1.5,
--      etc.) don't need a rewrite.
--   5. Spread: dramatically less accurate, with secondary fire MUCH
--      more inaccurate than primary. Default brace spread cloned +
--      widened by `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT` (2.0);
--      `pistol_special` spread (used by RMB lock-target AND rapid-fire
--      shots) cloned + widened by `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`
--      (9.0 = 4.5× the primary multiplier). Primary clone is set as
--      `default_spread_template`; secondary clone overrides
--      `spread_template_override` on EVERY sub-action of every action
--      that pointed to `pistol_special` (action_two.default lock-target
--      and action_one.[default|fast_shot|special_action_shoot]). The
--      walk over every action — instead of only action_one — is what
--      makes the reticle jump to the full wide size the moment RMB is
--      pressed, instead of the prior two-step "RMB jump to vanilla
--      pistol_special, then LMB jump to wider clone".
--
-- All five patches are template-level globals so the change applies
-- to every wielder (Saltzpyre native + Kruber via WT cross-access).
-- A restart is required to toggle off because the in-place patches
-- can't be cleanly reverted without snapshotting + restoring vanilla.

local function _wt_clone_shot_sniper_no_dropoff()
    if not DamageProfileTemplates then return nil end
    local source = DamageProfileTemplates.shot_sniper
    if not source then return nil end
    local key = "wt_authentic_pistol"
    if DamageProfileTemplates[key] then return key end

    local clone = table.clone(source, true)

    -- Flatten near/far dropoff: mirror near values to far so range no
    -- longer reduces damage. shot_sniper has separate `armor_modifier_near`
    -- vs `armor_modifier_far` and per-target `power_distribution_near`
    -- vs `power_distribution_far`.
    if clone.armor_modifier_near then
        clone.armor_modifier_far = table.clone(clone.armor_modifier_near, true)
    end
    if clone.default_target then
        if clone.default_target.power_distribution_near then
            clone.default_target.power_distribution_far = table.clone(clone.default_target.power_distribution_near, true)
        end
        -- range_modifier_settings is the curve that interpolates between
        -- near and far. With both endpoints equal we don't strictly need
        -- to remove it, but clearing it makes the no-dropoff intent
        -- explicit.
        clone.default_target.range_modifier_settings = nil
    end

    -- Double penetration. `cleave_distribution.attack` / `.impact` is the
    -- fraction of cleave power consumed per target hit; halving each value
    -- lets projectiles pass through ~2x as many enemies before running
    -- out of cleave. shot_sniper vanilla is 0.3/0.3 (≈3 targets);
    -- wt_authentic_pistol becomes 0.15/0.15 (≈6 targets).
    if clone.cleave_distribution then
        if type(clone.cleave_distribution.attack) == "number" then
            clone.cleave_distribution.attack = clone.cleave_distribution.attack / 2
        end
        if type(clone.cleave_distribution.impact) == "number" then
            clone.cleave_distribution.impact = clone.cleave_distribution.impact / 2
        end
    end

    DamageProfileTemplates[key] = clone

    -- Register in NetworkLookup.damage_profiles. The lookup is built once at
    -- game load (network_lookup.lua:2203) and frozen with an __index metatable
    -- that errors on missing keys. PlayerProjectileUnitExtension (line 92)
    -- looks up `NetworkLookup.damage_profiles[impact_data.damage_profile]` at
    -- projectile spawn — without this registration every brace shot crashes
    -- with "Table damage_profiles does not contain key: wt_authentic_pistol",
    -- which is exactly what made v0.12.6 silently no-op. Same pattern CWV uses
    -- for its custom damage-profile clones (character_weapon_variants.lua:1364).
    if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
        local tbl = NetworkLookup.damage_profiles
        local idx = #tbl + 1
        rawset(tbl, idx, key)
        rawset(tbl, key, idx)
    end

    return key
end

-- Primary spread mult: applied to the default brace spread used by
-- single-shot LMB (action_one.default). 2× wider than vanilla.
-- Dialled back from 3× per user feel-test 2026-05-22 — single-shot LMB
-- felt too inaccurate for the primary mode of fire. Secondary mult stays at 9×.
local _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT = 2.0
-- Secondary spread mult: applied to pistol_special, which both
-- action_two.default (lock-target / RMB aim) and action_one.fast_shot
-- (rapid-fire shot) override to via `spread_template_override`. 9×
-- (dialled back from 12× in v0.12.26 — final tune per user).
local _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT = 9.0

local function _wt_scale_spread(t, mult)
    for k, v in pairs(t) do
        if type(v) == "table" then
            _wt_scale_spread(v, mult)
        elseif type(v) == "number" then
            t[k] = v * mult
        end
    end
end

local function _wt_clone_spread_wider(source_key, dest_key, mult)
    if not SpreadTemplates then return nil end
    local source = SpreadTemplates[source_key]
    if not source then return nil end
    if SpreadTemplates[dest_key] then return dest_key end
    local clone = table.clone(source, true)
    _wt_scale_spread(clone, mult)
    SpreadTemplates[dest_key] = clone
    return dest_key
end

local function _wt_clone_brace_spread_wider()
    -- Default-stance spread (used by single-shot from action_one.default).
    -- Brace spread template is nested two levels deep (continuous/immediate →
    -- still/moving/etc → max_pitch/max_yaw/immediate_pitch/immediate_yaw).
    return _wt_clone_spread_wider("brace_of_pistols",
        "wt_authentic_brace_of_pistols_spread",
        _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT)
end

local function _wt_clone_pistol_special_spread_wider()
    -- pistol_special is what fast_shot (rapid-fire, action_two→fast_shot
    -- chain) uses via `spread_template_override`. Secondary mult (higher)
    -- so rapid fire is noticeably less accurate than single shots.
    return _wt_clone_spread_wider("pistol_special",
        "wt_authentic_brace_pistol_special_spread",
        _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT)
end

local function _apply_authentic_brace_mode()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then
        mod:warning("[wt authentic-brace] brace_of_pistols_template_1 not found — patch skipped")
        return
    end
    local tpl = Weapons.brace_of_pistols_template_1

    -- 1) Damage profile + shield/armor piercing on all firing sub-actions.
    local damage_profile_key = _wt_clone_shot_sniper_no_dropoff()
    if not damage_profile_key then
        mod:warning("[wt authentic-brace] failed to clone shot_sniper — bailing")
        return
    end
    if tpl.actions and tpl.actions.action_one then
        for _, sub_name in ipairs({ "default", "fast_shot", "special_action_shoot" }) do
            local sub = tpl.actions.action_one[sub_name]
            if sub then
                if sub.impact_data then
                    sub.impact_data.damage_profile = damage_profile_key
                end
                sub.ignore_shield_hit = true
            end
        end
    end

    -- 2) (Removed in v0.12.15) Right-click is left alone — vanilla brace
    -- lock-target / fast_shot rapid-fire kept intact. The previous attempts
    -- to swap it for a handgun-style optical zoom and to scrub the
    -- fast_shot rapid-fire chain were both reverted: the user reported the
    -- rapid-fire path was reachable through paths we never tracked down,
    -- and would rather lean into the rapid-fire than keep chasing it. The
    -- accuracy reduction in step (5) compensates by making rapid fire
    -- highly inaccurate.

    -- 3) Manual reload re-enabled (v0.12.19). Earlier revisions disabled
    -- weapon_reload.default by stubbing its condition_funcs with
    -- _disable_action so the only reload path was the auto-load-empty
    -- chain. The user has changed their mind: they want manual reload
    -- back, one shot at a time. We leave weapon_reload.default at vanilla
    -- (no condition_func override) and rely on ammo_per_reload=1 (step 4)
    -- for the single-shot-per-cycle behavior.

    -- 4) Ammo: 6 in the mag, 6 in reserve, reload one shot at a time.
    -- ammo_per_clip = 6 (mag size, the number you can fire before reload
    -- is required), max_ammo = 12 (mag + reserve, total carry), so reserve
    -- = max_ammo - ammo_per_clip = 6. ammo_per_reload = 1 means each
    -- reload animation cycle loads one round; the player can interrupt
    -- with a shot at any time (vanilla brace already supports this via
    -- weapon_reload.default's chain into action_one) or keep tapping R to
    -- top up the clip one round at a time.
    if tpl.ammo_data then
        tpl.ammo_data.ammo_per_clip = 6
        tpl.ammo_data.ammo_per_reload = 1
        tpl.ammo_data.max_ammo = 12
    end

    -- 6) (Removed in v0.12.15) fast_shot chain rewrite was reverted along
    -- with the right-click aim mutation in step (2). Rapid fire is allowed
    -- to remain reachable through whatever vanilla path the engine uses;
    -- v0.12.19 makes secondary fire deliberately slower (step 7) and less
    -- accurate (step 5) instead of trying to block it.

    -- 7) Action speed: PRIMARY/all-other actions run at 2x speed
    -- (_FAST_MULT = 0.5 → halved timings). SECONDARY FIRE
    -- (action_one.fast_shot — the rapid-fire shot triggered by RMB-hold)
    -- runs at VANILLA speed (_SLOW_MULT = 1.0 → no scaling). This was
    -- 2.0 (50% of vanilla, i.e. 2x slower) in v0.12.19-v0.12.20; user
    -- felt that was too slow, asked to double the speed in v0.12.21 →
    -- 1.0 lands secondary fire at vanilla pacing while primary stays
    -- at 2x. Net: secondary is half the speed of primary, but at the
    -- vanilla cadence the engine ships with. Chain start_times use:
    --   * SLOW if the chain's SOURCE sub-action is secondary (so internal
    --     fast_shot pacing — the self-loop at start_time=0.25 — stays at
    --     vanilla 0.25s, giving ~4 shots/sec).
    --   * SLOW if the chain's TARGET sub-action is fast_shot (so the
    --     RMB-into-rapid-fire chain from action_two.default at
    --     start_time=0.25 also stays vanilla).
    --   * FAST otherwise.
    -- Skip 0/math.huge — neither "instant" nor "hold-forever" semantics
    -- should be scaled. With _SLOW_MULT=1.0 the "slow" branches are
    -- effectively no-ops; the structure is retained so the asymmetry
    -- can be re-tuned (e.g. back to 1.5 / 2.0) without rewriting the
    -- walker.
    local _FAST_MULT = 0.5  -- 2x speed for primary / non-secondary actions
    local _SLOW_MULT = 1.0  -- vanilla speed for secondary fire (was 2.0 in v0.12.19-v0.12.20)
    local function _is_secondary_sub(action_name, sub_name)
        return action_name == "action_one" and sub_name == "fast_shot"
    end
    local function _chain_targets_secondary(chain, source_action_name)
        -- chain.action is the target action; if absent it defaults to the
        -- source action's name (per ActionUtils chain resolution).
        local target_action = chain.action or source_action_name
        return target_action == "action_one" and chain.sub_action == "fast_shot"
    end
    local function _scale_time(field, mult)
        if type(field) ~= "number" then return field end
        if field == 0 or field == math.huge then return field end
        return field * mult
    end
    if tpl.actions then
        for action_name, sub_actions in pairs(tpl.actions) do
            for sub_name, sub in pairs(sub_actions) do
                if type(sub) == "table" then
                    local is_secondary = _is_secondary_sub(action_name, sub_name)
                    local sub_mult = is_secondary and _SLOW_MULT or _FAST_MULT
                    sub.total_time           = _scale_time(sub.total_time, sub_mult)
                    sub.total_time_secondary = _scale_time(sub.total_time_secondary, sub_mult)
                    sub.fire_time            = _scale_time(sub.fire_time, sub_mult)
                    sub.minimum_hold_time    = _scale_time(sub.minimum_hold_time, sub_mult)
                    sub.cooldown             = _scale_time(sub.cooldown, sub_mult)
                    sub.reload_time          = _scale_time(sub.reload_time, sub_mult)
                    if sub.allowed_chain_actions then
                        for _, chain in ipairs(sub.allowed_chain_actions) do
                            local chain_mult
                            if is_secondary or _chain_targets_secondary(chain, action_name) then
                                chain_mult = _SLOW_MULT
                            else
                                chain_mult = _FAST_MULT
                            end
                            chain.start_time = _scale_time(chain.start_time, chain_mult)
                        end
                    end
                end
            end
        end
    end

    -- 5) Spread: dramatically less accurate. Both the default spread (single
    -- shot from action_one.default) AND the pistol_special spread (used by
    -- fast_shot rapid-fire via `spread_template_override`) are widened by
    -- the same multiplier. Without the second clone, holding RMB + LMB
    -- enters rapid fire which falls back to vanilla pistol_special spread
    -- and the "dramatic" feel only shows on single shots.
    local spread_key = _wt_clone_brace_spread_wider()
    if spread_key then
        tpl.default_spread_template = spread_key
    end
    -- Replace `spread_template_override = "pistol_special"` everywhere it
    -- appears on the template, not just in action_one. Critically this
    -- catches `action_two.default` (the RMB lock-target / aim action)
    -- which vanilla also overrides to pistol_special. v0.12.20 and earlier
    -- only patched action_one.[default|fast_shot|special_action_shoot] —
    -- that meant pressing RMB jumped the reticle to the vanilla
    -- pistol_special max spread (≈1.0), and then pressing LMB triggered
    -- action_one.fast_shot which jumped it again to our wider clone
    -- (≈1.0 × secondary_mult). The user saw this as the reticle
    -- "unnaturally going from small to large" — a two-step jump on RMB
    -- then LMB. With this patch the override on action_two.default uses
    -- the same wider clone, so the reticle jumps to the correct (large)
    -- size the moment the player takes aim. `override_spread_template`
    -- in `weapon_spread_extension.lua:168-177` instantly sets
    -- `current_pitch = state_settings.max_pitch`, so no lerp is visible.
    local rapid_spread_key = _wt_clone_pistol_special_spread_wider()
    if rapid_spread_key and tpl.actions then
        for _, sub_actions in pairs(tpl.actions) do
            for _, sub in pairs(sub_actions) do
                if type(sub) == "table" and sub.spread_template_override == "pistol_special" then
                    sub.spread_template_override = rapid_spread_key
                end
            end
        end
    end

    mod:info("[wt authentic-brace] applied: damage=%s, primary_spread=%s (%sx), secondary_spread=%s (%sx, applied to ALL pistol_special overrides incl. action_two.default), ammo=6/12 (reload 1 at a time, manual reload re-enabled), primary-speed=2x, secondary-fire-speed=vanilla (slow_mult=1.0)",
        damage_profile_key,
        tostring(spread_key), tostring(_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT),
        tostring(rapid_spread_key), tostring(_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT))
end

-- audit 2026-06-07 (PROJECT_STANDARDS §9.3 gated-registration divergence):
-- ALWAYS register the custom damage profile into NetworkLookup at load — even
-- when the toggle is OFF — so wt_authentic_pistol resolves to the SAME network
-- index on every peer running this wt version, regardless of each peer's toggle
-- state. Only the template PATCHING (usage) below stays gated. Without this, a
-- host with the brace ON and a client with it OFF diverge on the
-- damage_profiles index -> "Table damage_profiles does not contain key" crash /
-- silent wrong-damage desync when a networked brace shot is decoded.
-- (_wt_clone_shot_sniper_no_dropoff is idempotent; same load timing as before.)
-- RESIDUAL: full cross-MOD-SET determinism (a peer that also runs CWV/other
-- NetworkLookup appenders vs one that doesn't) still requires routing through
-- bt's shared sorted registry — the proper long-term fix, tracked as follow-up.
-- Regression: wt_authentic_pistol_profile_registered_unconditionally.
if not _wt_clone_shot_sniper_no_dropoff() then
    -- Ungated (mod:warning): if the profile can't register at load (tables not
    -- ready), a networked brace shot would desync / crash on the other peer when
    -- the toggle is on. Surface it without requiring Debug Logging.
    mod:warning("[wt:authentic-brace] wt_authentic_pistol damage-profile registration failed at load (DamageProfileTemplates/NetworkLookup not ready)")
end
if mod:get("authentic_brace_of_pistols") then
    _apply_authentic_brace_mode()
end

-- ============================================================
-- Warrior Priest punch buff (Reckoner Greathammer special)
-- ============================================================
-- Toggle that TRIPLES stagger and DOUBLES damage of the Warrior Priest 2h
-- hammer's special attack -- the "punch" (anim attack_slam) reached via the
-- weapon's push-stagger special. The punch action lives on the priest hammer
-- template (Weapons.two_handed_hammer_priest_template) and vanilla points at the
-- shared `light_blunt_smiter_stab` damage profile -- which other weapons also
-- use, so we must NOT mutate it in place. Instead we register a private cloned
-- profile (`wt_priest_punch_buffed`) with the punch's damage (power_distribution
-- .attack x2) and stagger (.impact x3) scaled on its default_target + targets,
-- then repoint ONLY the punch action's damage_profile at it while the toggle is
-- on (restoring the original key when off).
--
-- Like wt_authentic_pistol, the profile is registered into NetworkLookup
-- UNCONDITIONALLY at load (gated registration would desync the network index
-- between a host with the toggle on and a client with it off -- PROJECT_STANDARDS
-- §9.3). Only the action repoint is toggle-gated.
do
    local PRIEST_PUNCH_PROFILE = "wt_priest_punch_buffed"
    local PRIEST_PUNCH_SRC = "light_blunt_smiter_stab"
    local PRIEST_HAMMER_TMPL = "two_handed_hammer_priest_template"
    local DAMAGE_MULT = 2  -- doubles damage
    local STAGGER_MULT = 3  -- triples stagger

    -- Scale a power-level node's damage (attack) / stagger (impact). Resolves a
    -- string ref to PowerLevelTemplates and returns an OWN copy so the shared
    -- vanilla table is never mutated.
    local function _scaled_node(node)
        if type(node) == "string" then
            node = rawget(_G, "PowerLevelTemplates") and PowerLevelTemplates[node]
        end
        if type(node) ~= "table" then return node end
        local c = table.clone(node, true)
        local pd = c.power_distribution
        if type(pd) == "table" then
            if type(pd.attack) == "number" then pd.attack = pd.attack * DAMAGE_MULT end
            if type(pd.impact) == "number" then pd.impact = pd.impact * STAGGER_MULT end
        end
        return c
    end

    -- Register the cloned+scaled profile. Idempotent; mirrors
    -- _wt_clone_shot_sniper_no_dropoff's NetworkLookup registration.
    local function _register_priest_punch_profile()
        local DPT = rawget(_G, "DamageProfileTemplates")
        if not DPT then return false end
        if DPT[PRIEST_PUNCH_PROFILE] then return true end
        local src = DPT[PRIEST_PUNCH_SRC]
        if not src then return false end
        local clone = table.clone(src, true)
        clone.default_target = _scaled_node(clone.default_target)
        if type(clone.targets) == "string" then
            clone.targets = rawget(_G, "PowerLevelTemplates") and PowerLevelTemplates[clone.targets]
        end
        if type(clone.targets) == "table" then
            local nt = {}
            for i, t in ipairs(clone.targets) do nt[i] = _scaled_node(t) end
            clone.targets = nt
        end
        DPT[PRIEST_PUNCH_PROFILE] = clone
        if NetworkLookup and NetworkLookup.damage_profiles
            and not rawget(NetworkLookup.damage_profiles, PRIEST_PUNCH_PROFILE) then
            local tbl = NetworkLookup.damage_profiles
            local idx = #tbl + 1
            rawset(tbl, idx, PRIEST_PUNCH_PROFILE)
            rawset(tbl, PRIEST_PUNCH_PROFILE, idx)
        end
        return true
    end

    -- Captured once so toggling off restores the exact vanilla key.
    local _punch_orig_profile

    -- Repoint the punch action's damage_profile based on the toggle. Iterates the
    -- template's action groups and finds the `punch` sub-action (no dependence on
    -- which group it lives in).
    mod.wt_apply_priest_punch_buff = function()
        local tpl = rawget(_G, "Weapons") and Weapons[PRIEST_HAMMER_TMPL]
        if not (tpl and tpl.actions) then return end
        local enabled = mod:get("wt_priest_punch_buff")
        local use_profile = enabled and DamageProfileTemplates and DamageProfileTemplates[PRIEST_PUNCH_PROFILE] and PRIEST_PUNCH_PROFILE or nil
        for _, group in pairs(tpl.actions) do
            if type(group) == "table" and type(group.punch) == "table" then
                if _punch_orig_profile == nil then
                    _punch_orig_profile = group.punch.damage_profile or PRIEST_PUNCH_SRC
                end
                group.punch.damage_profile = use_profile or _punch_orig_profile
            end
        end
    end

    -- ALWAYS register at load (network-index determinism); repoint per toggle.
    if not _register_priest_punch_profile() then
        mod:warning("[wt:priest-punch] damage-profile registration failed at load (DamageProfileTemplates/NetworkLookup not ready)")
    end
    mod.wt_apply_priest_punch_buff()
end

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
    if item_data.name == "es_longbow" or item_data.name == "we_longbow" then
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
    if item_name ~= "es_longbow" and item_name ~= "we_longbow" then return end
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

    local fake_slot = { right_unit_3p = unit }
    _scale_weapon_units(fake_slot, weapon_key, career_name)
    _offset_weapon_units(fake_slot, weapon_key, career_name)

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

--[[
WEAPON-TRAIT POOL FILTERING
---------------------------
Lets the user enable/disable individual weapon traits from the VMF settings.
Adventure traits default ON (vanilla behaviour); Chaos Wastes traits default
OFF and only show in the UI when the `crafting_in_modded` mod is installed.

Mechanism: rewrite `WeaponTraits.combinations[pool]` (the table that
`crafting_in_modded` reads when rolling a trait on a crafted/rerolled weapon).
Every CW trait already lives in `WeaponTraits.traits` and `BuffTemplates`
because `weapon_traits_morris.lua` merges them in at load — they only fail to
appear in adventure because the vanilla `combinations.melee` / `.ranged_*`
pools don't list them. Adding them to those pools is sufficient.

`crafting_in_modded` does NOT hardcode any trait keys; it picks from
`WeaponTraits.combinations[master.trait_table_name]` at runtime
(see standard_forge.lua _reroll_traits + _make_craft_synth). So mutating
those tables here propagates to cim's reroll/craft UI automatically.

NOTE on file ordering: this block must come BEFORE the lifecycle callbacks
(`on_game_state_changed`, `on_setting_changed`, `on_disabled`) below — Lua 5.1
locals aren't hoisted, so a callback declared above us couldn't see these
local functions and would resolve to a nil global lookup at call time.
]]

-- Trait-key membership per pool. The toggle for a trait controls every pool
-- it can appear in. CW-cross-pool traits (headhunter, stagger_aoe_on_crit,
-- shield_splinters, deus_crit_chain_lightning) are listed once per pool they
-- belong to so the rebuilder can pick them up; the user-facing widget is a
-- single checkbox under whichever group is most natural.
local _trait_pool_sources = {
    melee = {
        vanilla = {
            "melee_attack_speed_on_crit",
            "melee_timed_block_cost",
            "melee_counter_push_power",
            "melee_increase_damage_on_block",
            "melee_reduce_cooldown_on_crit",
            "melee_shield_on_assist",
        },
        cw = {
            "stagger_aoe_on_crit",
            "armor_breaker",
            "shield_of_isha",
            "bloodthirst",
            "headhunter",
            "home_run",
            "shield_splinters",
            "serrated_blade",
            "crescendo_strike",
            "follow_up",
            "always_blocking",
            "deus_big_swing_stagger",
            "deus_crit_chain_lightning",
            "deus_collateral_damage_on_melee_killing_blow",
            "melee_heal_on_crit",
        },
    },
    ranged_ammo = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_replenish_ammo_headshot",
            "ranged_reduce_cooldown_on_crit",
            "ranged_replenish_ammo_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "refilling_shot",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
            "deus_ammo_pickup_reload_speed",
        },
    },
    ranged_heat = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_reduced_overcharge",
            "ranged_reduce_cooldown_on_crit",
            "ranged_remove_overcharge_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
        },
    },
    trollhammer_torpedo = {
        vanilla = {
            "ranged_restore_stamina_headshot",
            "ranged_reduce_cooldown_on_crit",
            "ranged_increase_power_level_vs_armour_crit",
            "ranged_consecutive_hits_increase_power",
            "melee_timed_block_cost",
            "melee_increase_damage_on_block",
        },
        cw = {
            "headhunter",
            "stagger_aoe_on_crit",
            "shield_splinters",
            "refilling_shot",
            "piercing_projectiles",
            "deus_extra_shot",
            "deus_crit_chain_lightning",
            "deus_ranged_crit_explosion",
            "deus_ammo_pickup_reload_speed",
        },
    },
}

-- Snapshot of vanilla pools. Captured the first time apply_trait_filters runs
-- (so DLC/morris additions are already merged in). Used to revert on
-- on_disabled and to detect "no managed pool yet" cases.
local _initial_trait_pools = nil

local function _snapshot_trait_pools()
    if _initial_trait_pools then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    _initial_trait_pools = {}
    for pool_key, _ in pairs(_trait_pool_sources) do
        local existing = WeaponTraits.combinations[pool_key]
        if existing then
            local copy = {}
            for i, entry in ipairs(existing) do
                copy[i] = { entry[1] }
            end
            _initial_trait_pools[pool_key] = copy
        end
    end
end

local function _trait_enabled(trait_key, is_cw)
    local prefix = is_cw and "cw_trait_" or "trait_"
    return mod:get(prefix .. trait_key) == true
end

local function apply_trait_filters()
    -- RETIRED 2026-06-29 (user request): the "Weapon Traits (Adventure)" menu was
    -- removed, so there are no toggles to honor — leave the vanilla trait roll pools
    -- untouched. Kept as a no-op stub (+ the mod._apply_trait_filters / _revert exports
    -- and call sites) so nothing dangles; the dead _trait_pool_sources / snapshot
    -- helpers below can be deleted in a later cleanup pass.
    if true then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    _snapshot_trait_pools()
    if not _initial_trait_pools then return end

    for pool_key, sources in pairs(_trait_pool_sources) do
        local current = WeaponTraits.combinations[pool_key]
        if current then
            local seen = {}
            local rebuilt = {}
            local function _push(trait_key, is_cw)
                if seen[trait_key] then return end
                if not _trait_enabled(trait_key, is_cw) then return end
                if not WeaponTraits.traits[trait_key] then return end
                seen[trait_key] = true
                rebuilt[#rebuilt + 1] = { trait_key }
            end
            for _, t in ipairs(sources.vanilla) do _push(t, false) end
            for _, t in ipairs(sources.cw) do _push(t, true) end

            -- Empty pool → fall back to vanilla snapshot to avoid "no traits
            -- to roll" stalls in cim. Users who want zero traits can disable
            -- the mod outright.
            if #rebuilt == 0 and _initial_trait_pools[pool_key] then
                for i, entry in ipairs(_initial_trait_pools[pool_key]) do
                    rebuilt[i] = { entry[1] }
                end
            end

            -- Mutate in place so any code holding a reference to the pool
            -- table sees the new contents.
            for i = #current, 1, -1 do current[i] = nil end
            for i, entry in ipairs(rebuilt) do current[i] = entry end
        end
    end
end

local function revert_trait_pools()
    if not _initial_trait_pools then return end
    if not WeaponTraits or not WeaponTraits.combinations then return end
    for pool_key, snapshot in pairs(_initial_trait_pools) do
        local current = WeaponTraits.combinations[pool_key]
        if current then
            for i = #current, 1, -1 do current[i] = nil end
            for i, entry in ipairs(snapshot) do current[i] = { entry[1] } end
        end
    end
end

mod._apply_trait_filters = apply_trait_filters
mod._revert_trait_pools = revert_trait_pools

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
    patch_career_actions_on_weapons()
    apply_trait_filters()
    -- Re-attempt the Necromancer FX force-load (idempotent). DLC ownership can be
    -- unresolved at mod-init even for owners; by any state transition it's resolved,
    -- so this guarantees bw_necromancer's soul_rip particles are resident before the
    -- staff can be wielded in a mission (2026-06-29 nicho create_particles crash).
    mod._force_load_necromancer_fx_package()
    -- Re-apply Big Rebalance writes on every state transition.  Most BR
    -- changes mutate Weapons/DamageProfileTemplates which the engine
    -- caches at boot, so this is largely defensive — but cheap and
    -- consistent with the existing pattern in this hook.
    big_rebalance.apply_all()

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

-- Clean disable: strip every cross-career career name this mod added to ItemMasterList[*].can_wield
-- and every ability action it injected into Weapons[*].actions. Without this, disabling the mod
-- via VMF would leave cross-career unlocks active on every affected weapon until game restart.
-- The restore-and-mutate phases of apply_weapon_unlocks / patch_career_actions_on_weapons already
-- handle the strip step on every call, so we just clear the management state and re-call: every
-- mod:get("unlock_*") read returns nil/false post-disable, so the add-back phase contributes nothing.
local function clear_weapon_unlocks()
    if not ItemMasterList then return end
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            local item = rawget(ItemMasterList, weapon_key)
            if item and item.can_wield then
                for i = #item.can_wield, 1, -1 do
                    if item.can_wield[i] == career then
                        table.remove(item.can_wield, i)
                    end
                end
            end
        end
    end
end

local function clear_career_action_injections()
    if not Weapons then return end
    for tmpl_key, actions in pairs(_career_action_injections) do
        local tmpl = Weapons[tmpl_key]
        if tmpl and tmpl.actions then
            for action_name in pairs(actions) do
                tmpl.actions[action_name] = nil
            end
        end
    end
    _career_action_injections = {}
end

mod.on_disabled = function()
    clear_weapon_unlocks()
    clear_career_action_injections()
    revert_trait_pools()
    mod:info("Weapon Tweaker disabled — cross-career unlocks, ability action injections, and trait-pool filters reverted")
end

mod.on_setting_changed = function(setting_id)
    if setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
        weapon_backend.refresh_on_setting_change(mod)
    elseif setting_id and (setting_id:find("^trait_") or setting_id:find("^cw_trait_")) then
        apply_trait_filters()
    elseif setting_id and setting_id:find("^br_") then
        -- Big Rebalance toggles: re-apply on every change.  Most BR writes
        -- are idempotent (direct field assignments on shared template
        -- tables) so re-running the whole apply is safe at runtime.  The
        -- master registration block runs once per session (re-init is a
        -- no-op after the first pass).
        big_rebalance.apply_all()
    elseif setting_id and setting_id:find("^wt_dev_anim_") then
        -- Dev: 3P anim picker — mutate live Weapons.<tpl> tables.
        _wt_dev_anim_picker.on_setting_changed(setting_id)
    elseif setting_id == "wt_priest_punch_buff" then
        if mod.wt_apply_priest_punch_buff then mod.wt_apply_priest_punch_buff() end
    elseif setting_id == "wt_brett_sword_shield_buff" then
        if mod.wt_apply_brett_buff then mod.wt_apply_brett_buff() end
    end
    -- wt_dev_hp_* settings are read by the hold-pose tuner's per-frame hook
    -- via mod:get directly, no dispatcher branch needed.
end

mod:command("dump", "Dump equipped item data to log", function()
    local player = Managers.player:local_player()
    if not player then
        mod:echo("No local player found")
        return
    end

    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    mod:echo("Career: " .. tostring(career_name))
    mod:info("=== EQUIPPED ITEM DUMP for %s ===", career_name)

    local inventory_ext = ScriptUnit.extension(player.player_unit, "inventory_system")
    local equipment = inventory_ext and inventory_ext:equipment()
    if not equipment or not equipment.slots then
        mod:echo("No equipment data available")
        return
    end

    for slot_name, slot_data in pairs(equipment.slots) do
        if slot_data.item_data then
            local item = slot_data.item_data
            local key = item.key or "?"
            local item_type = item.item_type or item.data and item.data.item_type or "?"
            local template = item.template or item.data and item.data.template or "?"
            local rarity = item.rarity or "?"
            local left = item.left_hand_unit or item.data and item.data.left_hand_unit or "none"
            local right = item.right_hand_unit or item.data and item.data.right_hand_unit or "none"

            mod:echo("%s: %s (%s)", slot_name, key, item_type)
            mod:info("[%s] key=%s  item_type=%s  template=%s  rarity=%s", slot_name, key, item_type, template, rarity)
            mod:info("[%s] left_hand_unit=%s", slot_name, left)
            mod:info("[%s] right_hand_unit=%s", slot_name, right)

            if item.can_wield then
                mod:info("[%s] can_wield=%s", slot_name, table.concat(item.can_wield, ", "))
            end

            if item.data then
                for data_key, data_val in pairs(item.data) do
                    if type(data_val) ~= "table" then
                        mod:info("[%s] data.%s=%s", slot_name, tostring(data_key), tostring(data_val))
                    end
                end
            end
        end
    end

    mod:info("=== END EQUIPPED ITEM DUMP ===")
    mod:echo("Dump written to log")
end)

mod:command("dump_actions", "Dump weapon action anim events (usage: /dump_actions [pattern])", function(pattern)
    pattern = pattern or ""
    if not Weapons then mod:echo("Weapons not loaded yet.") return end
    local tmpl_count = 0
    local action_count = 0
    local sorted_keys = {}
    for tmpl_key, _ in pairs(Weapons) do
        if tmpl_key:find(pattern, 1, true) then
            sorted_keys[#sorted_keys + 1] = tmpl_key
        end
    end
    table.sort(sorted_keys)
    for _, tmpl_key in ipairs(sorted_keys) do
        local tmpl = Weapons[tmpl_key]
        local header = "=== " .. tmpl_key .. " (wield_anim=" .. tostring(tmpl.wield_anim) .. ") ==="
        mod:echo(header)
        mod:info(header)
        tmpl_count = tmpl_count + 1
        if tmpl.actions then
            for action_name, action_data in pairs(tmpl.actions) do
                for sub_name, sub in pairs(action_data) do
                    if type(sub) == "table" and (sub.anim_event or sub.anim_event_3p) then
                        local ae = tostring(sub.anim_event or "-")
                        local ae3 = tostring(sub.anim_event_3p or "-")
                        local line = "  " .. action_name .. "." .. sub_name .. "  1P=" .. ae .. "  3P=" .. ae3
                        mod:echo(line)
                        mod:info(line)
                        action_count = action_count + 1
                    end
                end
            end
        end
    end
    local summary = "dump_actions: " .. tmpl_count .. " templates, " .. action_count .. " actions"
    mod:echo(summary)
    mod:info(summary)
end)

mod:command("dump_weapons", "Dump all weapons with native careers and localized names", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded.") return end
    local Localize = Localize
    local count = 0
    local total = 0
    local types_seen = {}
    local sorted = {}
    for key, item in pairs(ItemMasterList) do
        total = total + 1
        local t = item.item_type or item.slot_type or "nil"
        types_seen[t] = (types_seen[t] or 0) + 1
        if item.can_wield then
            sorted[#sorted + 1] = key
        end
    end
    table.sort(sorted)
    mod:echo("ItemMasterList: " .. total .. " total, " .. #sorted .. " with can_wield")
    local type_parts = {}
    for t, c in pairs(types_seen) do type_parts[#type_parts + 1] = t .. "=" .. c end
    mod:info("Types: " .. table.concat(type_parts, ", "))
    mod:info("=== WEAPON DUMP: key | item_type | slot_type | display_name | can_wield ===")
    for _, key in ipairs(sorted) do
        local item = rawget(ItemMasterList, key)
        local display = key
        if item.display_name then
            local ok, loc = pcall(Localize, item.display_name)
            if ok and loc then display = loc end
        end
        local wield = table.concat(item.can_wield, ",")
        local it = tostring(item.item_type or "nil")
        local st = tostring(item.slot_type or "nil")
        local line = key .. " | " .. it .. " | " .. st .. " | " .. display .. " | " .. wield
        mod:info(line)
        count = count + 1
    end
    mod:info("=== END WEAPON DUMP: %d weapons ===", count)
    mod:echo("Dumped " .. count .. " weapons to log")
end)

-- Install basic backend hooks (UI filtering and can_wield override)
weapon_backend.install(mod, weapon_unlock_map, apply_weapon_unlocks)
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

-- ============================================================
-- Core's Big Rebalance — initial apply.
-- Runs once at mod load, after every helper in this file is defined
-- so the apply functions can safely call anything they need.
-- See `weapon_tweaker_big_rebalance_registrations.lua` for the
-- cross-mod alphabetical registration list.
-- ============================================================
big_rebalance.apply_all()

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================

_rt_register("husk_extension_hooked", function()
    -- v0.12.37: SimpleHuskInventoryExtension.wield must be hooked (separate
    -- class from SimpleInventoryExtension — hooking only the local class
    -- silently no-ops on remote-player husks per feedback_vt2_husk_extension_class_pair).
    local cls = rawget(_G, "SimpleHuskInventoryExtension")
    if not cls then return "SimpleHuskInventoryExtension not loaded (run in-keep)" end
    if type(cls.wield) ~= "function" then return "SimpleHuskInventoryExtension.wield missing" end
    -- VMF replaces the class method with its hook wrapper. We can't easily
    -- introspect VMF's hook table portably, so leave this as a presence-of-
    -- class check + an embedded comment marker proving wt hooks it.
    local _MARKER = "SimpleHuskInventoryExtension"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("anim_remap_per_unit", function()
    -- v0.12.35: _unit_state is a weak-keyed per-3P-body table — not a single
    -- _current_weapon_template global. Verify shape.
    if type(_unit_state) ~= "table" then return "_unit_state missing (should be weak-keyed per-unit table)" end
    local mt = getmetatable(_unit_state)
    if not (mt and mt.__mode and mt.__mode:find("k")) then
        return "_unit_state missing weak-key metatable (__mode='k')"
    end
end)

_rt_register("wh_priest_no_bows", function()
    -- Per feedback_vt2_no_bows_on_warrior_priest: wh_priest must NOT receive
    -- bows / crossbows / longbows because his 3P body lacks the anims.
    local bow_keys = {
        we_longbow = true, es_longbow = true, we_shortbow = true,
        we_shortbow_hagbane = true, wh_crossbow = true, dr_crossbow = true,
        we_crossbow_repeater = true, wh_crossbow_repeater = true,
    }
    local found = {}
    local list = weapon_unlock_map and weapon_unlock_map.wh_priest
    if type(list) == "table" then
        for _, k in ipairs(list) do
            if bow_keys[k] then found[#found + 1] = k end
        end
    end
    if #found > 0 then return "bows on wh_priest: " .. table.concat(found, ", ") end
end)

_rt_register("billhook_anim_remap_present", function()
    -- v0.12.64: 3P remap fallback for the unconditional weapon-change block.
    -- Verify the _suffix_career_map covers wh_priest billhook remap entry that
    -- redirects to_2h_billhook.
    if type(_suffix_career_map) ~= "table" then
        return "_suffix_career_map missing"
    end
    -- Embedded constant marker for the fix:
    local _MARKER = "_2h_billhook"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("wt_safe_hook_installed", function()
    -- v0.12.77 (Issue #26): pcall-isolated `mod:safe_hook` wrapper. The helper
    -- is required from `_safe_hook.lua` near the top of this file, BEFORE any
    -- `mod:hook(...)` call site. If the require ever drops out of the load
    -- order (refactor / bad merge), every `mod:safe_hook(...)` site below
    -- crashes at module load with "attempt to call a nil value (method
    -- 'safe_hook')". This check surfaces the regression at /wt_regression_test
    -- time rather than letting it manifest as a load failure.
    --
    -- 1. Source-pattern marker constant set by `_safe_hook.lua`.
    if CT_WT_SAFE_HOOK_MARKER_v0_12_74 ~= "wt-safe-hook-pcall-isolated" then
        return "safe_hook marker absent — was _safe_hook.lua require removed?"
    end
    -- 2. Runtime: both methods must be callable functions on the mod table.
    if type(mod.safe_hook) ~= "function" then
        return "mod.safe_hook is not a function (got " .. type(mod.safe_hook) .. ")"
    end
    if type(mod.safe_hook_safe) ~= "function" then
        return "mod.safe_hook_safe is not a function (got " .. type(mod.safe_hook_safe) .. ")"
    end
end)

-- v0.12.80-dev: hard regression test for the multi-return + nil-hole bug
-- class that shipped 3 versions in 2 hours (v0.12.77/.78/.79). The marker
-- constant check above (`wt_safe_hook_installed`) only proves the module
-- loaded — it does NOT exercise the actual multi-return path that broke
-- silently in v0.12.77 (collapse to single return) and again in v0.12.78
-- (`unpack(results, 2)` without explicit `j`, non-deterministic with nil
-- holes per Lua 5.1 `#table` undefined behavior).
--
-- This fixture builds a fresh dummy class on every test invocation (fresh
-- table identity = fresh hook target, so VMF's "duplicate hook" guard never
-- trips and the check is rerunnable any number of times), wraps a method
-- that mimics the worst-case `GearUtils.spawn_inventory_unit` return shape
-- (5 returns, 2 nil holes at positions 2 and 4 — more aggressive than the
-- real one), and asserts positional integrity through `safe_hook`.
_rt_register("wt_safe_hook_preserves_multi_returns_with_nil_holes", function()
    -- Each run uses a fresh table identity so VMF treats it as a new hook
    -- target (no double-registration error on repeated /wt_regression_test).
    local _dummy_class = {
        -- Returns 5 values, with two nil holes (positions 2 and 4) — mimics
        -- and exceeds the melee-weapon `GearUtils.spawn_inventory_unit`
        -- return shape (`weapon_3p, ammo_3p_nil, weapon_1p, ammo_1p_nil`).
        method = function(self, ...) return 1, nil, 2, nil, 3 end,
        -- Error path: handler that raises so we can prove safe_hook catches
        -- + logs without crashing and the chain continues to vanilla.
        raiser = function(self) error("test-raise: safe_hook fixture") end,
    }

    -- Wrap the method via safe_hook. Handler just forwards everything so any
    -- return-mangling is attributable to the wrapper, not the body.
    mod:safe_hook(_dummy_class, "method", function(func, ...)
        return func(...)
    end)

    -- Call the safe-hooked method. Capture every return positionally using
    -- the `select("#", ...)` + table-pack idiom — the same one safe_hook
    -- itself must use internally to be correct.
    local function _capture(...) return select("#", ...), { ... } end
    local n, r = _capture(_dummy_class:method())

    -- Assertion 1: full count preserved (catches the v0.12.77 collapse-to-1
    -- bug and the v0.12.78 non-deterministic-#table truncation).
    if n ~= 5 then
        return string.format(
            "safe_hook truncated multi-return: got n=%d expected 5 (results=%s,%s,%s,%s,%s)",
            n, tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]), tostring(r[5]))
    end
    -- Assertion 2: positional integrity. Each slot exact value, including
    -- the two intentional nil holes. Catches any future "compact away nils"
    -- regression in the unpack path.
    if r[1] ~= 1 then
        return "safe_hook positional integrity: r[1] expected 1, got " .. tostring(r[1])
    end
    if r[2] ~= nil then
        return "safe_hook positional integrity: r[2] expected nil, got " .. tostring(r[2])
    end
    if r[3] ~= 2 then
        return "safe_hook positional integrity: r[3] expected 2, got " .. tostring(r[3])
    end
    if r[4] ~= nil then
        return "safe_hook positional integrity: r[4] expected nil, got " .. tostring(r[4])
    end
    if r[5] ~= 3 then
        return "safe_hook positional integrity: r[5] expected 3, got " .. tostring(r[5])
    end

    -- Error-path coverage: safe_hook a raiser, call it, assert it doesn't
    -- crash. safe_hook's contract is "log + fall through to vanilla" so the
    -- raiser's `error(...)` will fire twice (once in the handler, once in
    -- the vanilla fall-through call to `func(...)`). The outer pcall here
    -- catches the vanilla raise; we ONLY care that the wrapper itself
    -- didn't propagate an uncaught Lua error from inside safe_hook's own
    -- bookkeeping (e.g. nil-method-deref, bad unpack args). We accept
    -- either outcome (pcall ok=true OR ok=false with the test-raise
    -- message) as long as the wrapper didn't blow up with its own error.
    mod:safe_hook(_dummy_class, "raiser", function(func, ...)
        return func(...)
    end)
    local raiser_ok, raiser_err = pcall(function() _dummy_class:raiser() end)
    -- raiser_ok == false is expected (vanilla raises after handler logged);
    -- raiser_ok == true would also be acceptable (engine swallowed it).
    -- What we DON'T want is a wrapper-internal failure like "attempt to
    -- call nil" or "bad argument #2 to 'unpack'".
    if not raiser_ok then
        local err_str = tostring(raiser_err)
        if not err_str:find("test%-raise") then
            return "safe_hook error path: wrapper raised its own error instead of vanilla fall-through: " .. err_str
        end
    end
end)

-- v0.12.84-dev: Layer 3 traced_hook smoke test. Sister check to the
-- v0.12.77 `wt_safe_hook_installed` marker — proves the traced_hook module
-- attached both methods AND the trace lines don't crash when emitted.
-- Does NOT exercise the actual log-line contents (that's a manual
-- in-game verification — toggle `enable_debug_logging` on and watch the
-- log file for `[wt:trace] event=enter|exit ...` pairs around any of the
-- three migrated hook sites: SimpleInventoryExtension.wield,
-- GearUtils.create_equipment, GearUtils.spawn_inventory_unit).
_rt_register("wt_priest_punch_buff_wired", function()
    -- The buffed punch profile must register at load (network-index determinism)
    -- and the apply fn must exist. Mirrors the authentic-pistol guard.
    if type(mod.wt_apply_priest_punch_buff) ~= "function" then
        return "mod.wt_apply_priest_punch_buff missing"
    end
    local DPT = rawget(_G, "DamageProfileTemplates")
    if not DPT then return "skip: DamageProfileTemplates not loaded" end
    if not DPT.wt_priest_punch_buffed then
        return "wt_priest_punch_buffed damage profile not registered at load"
    end
    if NetworkLookup and NetworkLookup.damage_profiles
        and not rawget(NetworkLookup.damage_profiles, "wt_priest_punch_buffed") then
        return "wt_priest_punch_buffed missing from NetworkLookup.damage_profiles (would desync/crash networked)"
    end
    -- The clone must actually be scaled vs the source on default_target (2x dmg /
    -- 3x stagger), proving the power_distribution scale ran.
    local src = DPT.light_blunt_smiter_stab
    local buf = DPT.wt_priest_punch_buffed
    local function pd(p) return type(p)=="table" and type(p.default_target)=="table" and p.default_target.power_distribution or nil end
    local sp, bp = pd(src), pd(buf)
    if type(sp)=="table" and type(bp)=="table" and type(sp.attack)=="number" and type(sp.impact)=="number" then
        if math.abs(bp.attack - sp.attack * 2) > 0.0001 then return "punch damage not 2x on default_target" end
        if math.abs(bp.impact - sp.impact * 3) > 0.0001 then return "punch stagger not 3x on default_target" end
    end
end)

_rt_register("wt_traced_hook_present", function()
    -- 1. Source-pattern marker constant set by `_safe_hook.lua` (Layer 3
    --    section). If the require ever drops out of the load order or the
    --    Layer 3 block gets deleted, this surfaces at /wt_regression_test.
    if CT_WT_TRACED_HOOK_MARKER_v0_12_84 ~= "wt-traced-hook-layer3-installed" then
        return "traced_hook marker absent — was Layer 3 block removed from _safe_hook.lua?"
    end
    -- 2. Runtime: both Layer 3 methods must be callable functions on the
    --    mod table.
    if type(mod.traced_hook) ~= "function" then
        return "mod.traced_hook is not a function (got " .. type(mod.traced_hook) .. ")"
    end
    if type(mod.traced_hook_safe) ~= "function" then
        return "mod.traced_hook_safe is not a function (got " .. type(mod.traced_hook_safe) .. ")"
    end
    -- 3. Smoke: install traced_hook on a fresh dummy class (fresh identity
    --    so VMF's duplicate-hook guard never trips). We DON'T assert "no
    --    trace lines emitted" — that would require log-file inspection — but
    --    a crash inside the tracing closure would surface here.
    local _dummy_class = {
        method = function(self, a, b) return a, nil, b end,  -- 3 returns w/ nil hole
    }
    mod:traced_hook(_dummy_class, "method", function(func, ...)
        return func(...)
    end)
    local r1, r2, r3 = _dummy_class:method(7, 9)
    if r1 ~= 7 or r2 ~= nil or r3 ~= 9 then
        return string.format("traced_hook return-shape broken: r1=%s r2=%s r3=%s",
            tostring(r1), tostring(r2), tostring(r3))
    end
    -- 4. Second smoke with a different dummy class to verify the trace-emit
    --    path doesn't crash when mod:debug fires.
    local _dummy_class_b = {
        method = function(self, a, b) return a, nil, b end,
    }
    mod:traced_hook(_dummy_class_b, "method", function(func, ...)
        return func(...)
    end)
    local s1, s2, s3 = _dummy_class_b:method(11, 13)
    if s1 ~= 11 or s2 ~= nil or s3 ~= 13 then
        return string.format("traced_hook return-shape broken (second smoke): s1=%s s2=%s s3=%s",
            tostring(s1), tostring(s2), tostring(s3))
    end
end)

-- Guard for WT_LINK_UNITS_NODE_GUARD_MARKER: the GearUtils.link_units crash filter
-- must drop links whose source/target node is absent and leave all-present links
-- untouched (zero-copy). Engine-free — uses synthetic node-presence predicates.
_rt_register("link_units_node_guard", function()
    if type(mod._wt_link_filter) ~= "function" then
        return "mod._wt_link_filter missing (GearUtils.link_units crash guard reverted?)"
    end
    local linking = {
        { source = "j_hips",                   target = "j_page_nr1_01" }, -- both present -> keep
        { source = "j_rightweaponcomponent11", target = "j_page_nr2_01" }, -- source absent -> drop
        { source = "j_spine",                  target = "j_no_such_node"  }, -- target absent -> drop
    }
    local present_src = { j_hips = true, j_spine = true }
    local present_tgt = { j_page_nr1_01 = true, j_page_nr2_01 = true }
    local out, dropped = mod._wt_link_filter(linking,
        function(n) return present_src[n] == true end,
        function(n) return present_tgt[n] == true end)
    if dropped ~= 2 then return "LINK-GUARD: expected 2 dropped, got " .. tostring(dropped) end
    if #out ~= 1 then return "LINK-GUARD: expected 1 surviving link, got " .. tostring(#out) end
    if out[1].source ~= "j_hips" then return "LINK-GUARD: wrong link survived (expected j_hips)" end
    -- all-present must be a zero-copy no-op (returns the SAME table, 0 dropped)
    local same = { { source = "j_hips", target = "j_page_nr1_01" } }
    local out2, d2 = mod._wt_link_filter(same, function() return true end, function() return true end)
    if d2 ~= 0 or out2 ~= same then return "LINK-GUARD: all-present case must return the original table unchanged" end
end)

_rt_register("wt_itemmasterlist_uses_rawget", function()
    -- v0.12.72/.73: defensive `rawget(ItemMasterList, key)` (GH #8) at 5 known
    -- mutation sites (~L175, 208, 226, 277, 3835 of weapon_tweaker.lua). The
    -- strict-table-lookup lint covers static-pattern regressions; this runtime
    -- check is the belt-and-suspenders companion required by §15 of
    -- PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: the marker constant must be present (catches
    --    accidental code deletion / revert).
    if CT_WT_ITEMMASTERLIST_RAWGET_MARKER_v0_12_73 ~= "wt-itemmasterlist-rawget-hardened" then
        return "RAWGET marker absent — was the v0.12.72 ItemMasterList hardening reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key must return nil rather than
    --    raise. If ItemMasterList ever grows a strict __index, this would
    --    surface the regression at boot.
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) == "table" then
        local ok, value = pcall(rawget, iml, "__wt_rawget_probe_does_not_exist__")
        if not ok then
            return "rawget(ItemMasterList, <bad-key>) RAISED — strict-metatable behavior changed"
        end
        if value ~= nil then
            return "rawget(ItemMasterList, <bad-key>) returned non-nil — unexpected"
        end
    end
end)

_rt_register("wt_authentic_pistol_profile_registered_unconditionally", function()
    -- audit 2026-06-07 (PROJECT_STANDARDS §9.3): the custom damage profile must be
    -- registered in NetworkLookup on EVERY peer regardless of the authentic-brace
    -- toggle, or the network index diverges between peers with the toggle on vs off
    -- (RPC crash / wrong-damage desync). Assert it's present even when the toggle
    -- is off. Fails if a future edit re-gates the registration behind the toggle.
    local DPT = rawget(_G, "DamageProfileTemplates")
    local NL  = rawget(_G, "NetworkLookup")
    if not (DPT and NL and NL.damage_profiles) then
        return "skip: DamageProfileTemplates/NetworkLookup not loaded"
    end
    if not rawget(DPT, "wt_authentic_pistol") then
        return "wt_authentic_pistol missing from DamageProfileTemplates (registration not unconditional)"
    end
    if not rawget(NL.damage_profiles, "wt_authentic_pistol") then
        return "wt_authentic_pistol missing from NetworkLookup.damage_profiles (peer index would diverge)"
    end
end)

_rt_register("wt_br_trueflight_speed_falloff_matches_vanilla", function()
    -- v0.12.116: the BR true-flight fire reimpl shipped vanilla's per-projectile
    -- speed falloff sign-flipped — speed * (i * 0.05 - 1) instead of vanilla's
    -- speed * (1 - i * 0.05) (action_true_flight_bow.lua:152) — so with
    -- br_hook_trueflight_fire on, every projectile after the first launched
    -- BACKWARDS at negative speed under multi-shot fires. The formula now lives in
    -- mod._wt_tf_projectile_speed (file scope in weapon_tweaker_big_rebalance.lua).
    local f = mod._wt_tf_projectile_speed
    if type(f) ~= "function" then
        return "_wt_tf_projectile_speed missing — BR true-flight falloff regressed or moved"
    end
    if f(10, 1) ~= 10 then
        return "i=1 (first projectile) must pass speed through unmodified"
    end
    local expected = 10 * (1 - 2 * 0.05)  -- vanilla falloff for i=2
    local got = f(10, 2)
    if math.abs(got - expected) > 1e-9 then
        return string.format("i=2: expected %.4f (vanilla falloff), got %.4f (sign-flip regression?)", expected, got)
    end
    for i = 2, 5 do
        if f(10, i) <= 0 then
            return string.format("i=%d produced non-positive speed %.4f — projectile would fire backwards", i, f(10, i))
        end
    end
end)

_rt_register("wt_br_trueflight_extra_shot_gating_matches_vanilla", function()
    -- v0.12.117 (Issue #74): the BR true-flight fire reimpl gated
    -- set_shooting/ammo/overcharge on `self.extra_buff_shot`, which is only ever
    -- assigned false — so extra-shot-buff projectiles wrongly bumped spread state
    -- and charged ammo/overcharge. Vanilla derives a per-projectile is_extra_shot
    -- (action_true_flight_bow.lua:128,132): extra_shots_idx = num_projectiles -
    -- num_extra_shots + 1; is_extra_shot = extra_shots_idx <= i. The formula now
    -- lives in mod._wt_tf_is_extra_shot; assert it matches vanilla's truth table.
    local f = mod._wt_tf_is_extra_shot
    if type(f) ~= "function" then
        return "_wt_tf_is_extra_shot missing — BR true-flight extra-shot gating regressed or moved"
    end
    -- No extra shots: nothing is an extra shot.
    for i = 1, 3 do
        if f(i, 3, 0) then return string.format("i=%d flagged extra with num_extra_shots=0", i) end
    end
    -- 5 projectiles, 2 extra: vanilla idx = 5-2+1 = 4 → i=1..3 normal, i=4..5 extra.
    for i = 1, 3 do
        if f(i, 5, 2) then return string.format("i=%d flagged extra (expected normal; idx=4)", i) end
    end
    for i = 4, 5 do
        if not f(i, 5, 2) then return string.format("i=%d not flagged extra (expected extra; idx=4)", i) end
    end
    -- nil num_extra_shots must behave as 0 (start_action always sets it, but the
    -- helper is the last line of defense).
    if f(1, 1, nil) then return "nil num_extra_shots treated as extra shot" end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised on call" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised on call" end
    -- #240 / §17B: _dbg_alert must be log-only (engine printf), never mod:warning
    -- (which posts to chat). The marker is set only on the printf-routed helper.
    if mod._wt_alerts_log_only_marker ~= "wt-alert-helpers-log-only-printf-240" then
        return "_dbg_alert not rerouted to log-only printf (#240 regression)"
    end
end)



_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/weapon_tweaker/weapon_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

-- ============================================================
-- Wield-time weapon-data dump  (v0.12.90-dev)
-- ============================================================
-- When `enable_debug_logging` is ON, every local-player wield emits a
-- structured dump of the wielded weapon's ItemMasterList entry: animations,
-- state machines, can_wield list, resolved unit paths. Lets the user (and
-- Claude) read the log to see exactly what wt sees the moment a weapon is
-- equipped -- useful for diagnosing "weapon X isn't available on career Y"
-- or "wrong 3P anim on cross-character port" without in-game repro.
--
-- Also exposed as `/wt_dump_wielded` for one-shot dumps of the currently
-- held weapon (forces a dump regardless of the toggle).
local function _wt_dump_weapon_data(item_key, source)
    if type(item_key) ~= "string" or item_key == "" then
        mod:debug("[wt:wield_dump] no item_key (source=%s)", tostring(source))
        return
    end
    local iml = rawget(_G, "ItemMasterList")
    local entry = iml and rawget(iml, item_key)
    if type(entry) ~= "table" then
        mod:debug("[wt:wield_dump] %s (source=%s) -- no ItemMasterList entry",
            item_key, tostring(source))
        return
    end
    mod:debug("[wt:wield_dump] === %s (source=%s) ===", item_key, tostring(source))
    mod:debug("[wt:wield_dump]   slot_type=%s item_type=%s template=%s",
        tostring(entry.slot_type), tostring(entry.item_type), tostring(entry.template))
    mod:debug("[wt:wield_dump]   display_name=%s inventory_icon=%s required_dlc=%s",
        tostring(entry.display_name), tostring(entry.inventory_icon),
        tostring(entry.required_dlc))
    mod:debug("[wt:wield_dump]   anim_event=%s wield_anim=%s",
        tostring(entry.anim_event), tostring(entry.wield_anim))
    mod:debug("[wt:wield_dump]   anim_event_3p=%s wield_anim_3p=%s",
        tostring(entry.anim_event_3p), tostring(entry.wield_anim_3p))
    mod:debug("[wt:wield_dump]   state_machine=%s state_machine_3p=%s",
        tostring(entry.state_machine), tostring(entry.state_machine_3p))
    if type(entry.can_wield) == "table" then
        mod:debug("[wt:wield_dump]   can_wield=[%s]",
            table.concat(entry.can_wield, ","))
    end
    if entry.left_hand_unit or entry.right_hand_unit then
        mod:debug("[wt:wield_dump]   1p left=%s right=%s",
            tostring(entry.left_hand_unit), tostring(entry.right_hand_unit))
    end
    if entry.left_hand_unit_3p or entry.right_hand_unit_3p then
        mod:debug("[wt:wield_dump]   3p left=%s right=%s",
            tostring(entry.left_hand_unit_3p), tostring(entry.right_hand_unit_3p))
    end
end

-- Hook: SimpleInventoryExtension._wield_slot fires for every local-player
-- wield. slot_data.id carries the item key. hook_safe so we never perturb
-- the wield path. Husk extension intentionally NOT hooked -- we want our
-- own equips, not teammates'.
mod:hook_safe("SimpleInventoryExtension", "_wield_slot",
    function(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
        local item_key = slot_data
            and (slot_data.id
                or (slot_data.item_data and slot_data.item_data.key))
        _wt_dump_weapon_data(item_key, "wield_slot")
    end)

mod:command("wt_dump_wielded",
    "Dump everything wt knows about the currently wielded weapon.",
    function()
        local pm = Managers.player
        local lp = pm and pm:local_player()
        local punit = lp and lp.player_unit
        if not punit then
            mod:echo("[wt_dump_wielded] no local player unit")
            return
        end
        local inv = ScriptUnit.has_extension(punit, "inventory_system")
        if not inv then
            mod:echo("[wt_dump_wielded] no inventory extension")
            return
        end
        local slot = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
        local slot_data = slot and inv.get_slot_data and inv:get_slot_data(slot)
        local item_key = slot_data
            and (slot_data.id
                or (slot_data.item_data and slot_data.item_data.key))
        _wt_dump_weapon_data(item_key, "command")
        mod:echo("[wt_dump_wielded] dumped %s -- see console log",
            tostring(item_key))
    end)

_rt_register("widget_unlock_map_consistency", function()
    -- Bug class: a (career, weapon) pair lives in `weapon_unlock_map` but
    -- the companion `unlock_<career>_<weapon>` VMF widget is missing from
    -- weapon_tweaker_data.lua. The runtime apply logic supports the unlock
    -- but the toggle is silently unreachable from the VMF settings UI -- so
    -- the user can never turn it on. Burned 2026-05-25: es_sword_shield_breton
    -- was in es_knight's weapon_unlock_map array but had no widget in
    -- melee_es_knight, so Foot Knight couldn't get Bretonnian Sword and
    -- Shield (wt v0.12.89-dev -> v0.12.90-dev fix). Same check also catches
    -- the inverse: dead widgets that don't map to anything.
    if type(weapon_unlock_map) ~= "table" then
        return "weapon_unlock_map unreachable"
    end
    local ok, data = pcall(mod.dofile, mod,
        "scripts/mods/weapon_tweaker/weapon_tweaker_data")
    if not ok or type(data) ~= "table" then
        return "weapon_tweaker_data not loadable: " .. tostring(data)
    end
    -- Walk the nested widget tree, harvest every setting_id.
    local widget_ids = {}
    local function _harvest(w)
        if type(w) ~= "table" then return end
        if type(w.setting_id) == "string" then
            widget_ids[w.setting_id] = true
        end
        if type(w.sub_widgets) == "table" then
            for _, s in ipairs(w.sub_widgets) do _harvest(s) end
        end
        if type(w.widgets) == "table" then
            for _, s in ipairs(w.widgets) do _harvest(s) end
        end
        for _, s in ipairs(w) do _harvest(s) end
    end
    _harvest(data)
    -- Forward: every map (career, weapon) needs a widget.
    local missing_widgets = {}
    for career, weapons in pairs(weapon_unlock_map) do
        if type(weapons) == "table" then
            for _, weapon in ipairs(weapons) do
                local key = "unlock_" .. career .. "_" .. weapon
                if not widget_ids[key] then
                    missing_widgets[#missing_widgets + 1] = key
                end
            end
        end
    end
    if #missing_widgets > 0 then
        return string.format("widget missing for unlock_map entries: %s",
            table.concat(missing_widgets, ", "))
    end
    -- Reverse: every "unlock_<career>_<weapon>" widget needs a map entry.
    -- Both career names and weapon keys contain underscores, so simple
    -- string.match is ambiguous -- walk each known career prefix instead.
    local missing_map = {}
    for sid, _ in pairs(widget_ids) do
        if type(sid) == "string" and sid:sub(1, 7) == "unlock_" then
            local matched = false
            for career, weapons in pairs(weapon_unlock_map) do
                local pfx = "unlock_" .. career .. "_"
                if sid:sub(1, #pfx) == pfx then
                    local w = sid:sub(#pfx + 1)
                    if type(weapons) == "table" then
                        for _, mw in ipairs(weapons) do
                            if mw == w then matched = true; break end
                        end
                    end
                    if matched then break end
                end
            end
            if not matched then
                missing_map[#missing_map + 1] = sid
            end
        end
    end
    if #missing_map > 0 then
        return string.format(
            "widget(s) present but missing from weapon_unlock_map: %s",
            table.concat(missing_map, ", "))
    end
end)

_rt_register("xchar_unwielded_attach_node_safe", function()
    -- Bug class: a cross-character port adds (career, weapon) where the
    -- weapon's attachment_node_linking references a body-specific source
    -- node like `a_unwielded_crossbow` that the equipping career's body
    -- skeleton does NOT author. `Unit.node()` on the missing node bypasses
    -- pcall and engine-fatals -- typically the moment the inventory
    -- previewer opens or the weapon transitions to unwielded in-game.
    -- Burned 2026-05-25 (crashify 9ef21d18-0926-4c1b-b53f-9655a38f9447):
    -- wh_crossbow on Kruber crashed "a_unwielded_crossbow" in the
    -- inventory screen because Kruber's body lacks that node. Fixed by
    -- _patch_xchar_unwielded_attachment_safe() substituting `j_hips`.
    --
    -- This check walks every cross-character port in weapon_unlock_map,
    -- looks up each weapon's attachment_node_linking, and flags any
    -- `third_person.unwielded[].source` that still looks body-specific
    -- (`a_unwielded_*` prefix) -- those are candidates for the same crash
    -- class on bodies that don't author that node. Pre-shipped bodies
    -- only author `a_unwielded_*` nodes for weapons their own career
    -- vanilla-wields, so any `a_unwielded_<weapon>` source on a weapon
    -- being ported to a different character is a red flag.
    if type(weapon_unlock_map) ~= "table" then return end
    if not AttachmentNodeLinking then return end
    if not rawget(_G, "ItemMasterList") then return end
    if not rawget(_G, "Weapons") then return end
    local iml = ItemMasterList

    -- Build career -> base prefix lookup so we know which weapons are
    -- "native" to each career (we only want to flag CROSS-character ports,
    -- not the weapon's own vanilla career).
    local _NATIVE_PREFIX = {
        es_ = { es_mercenary = true, es_huntsman = true,
                es_knight = true,    es_questingknight = true },
        dr_ = { dr_ranger = true,    dr_ironbreaker = true,
                dr_slayer = true,    dr_engineer = true },
        we_ = { we_waywatcher = true, we_maidenguard = true,
                we_shade = true,      we_thornsister = true },
        wh_ = { wh_captain = true,   wh_bountyhunter = true,
                wh_zealot = true,    wh_priest = true },
        bw_ = { bw_adept = true,     bw_scholar = true,
                bw_unchained = true, bw_necromancer = true },
    }
    local function _is_native(career, weapon_key)
        for pfx, careers in pairs(_NATIVE_PREFIX) do
            if weapon_key:sub(1, #pfx) == pfx then
                return careers[career] == true
            end
        end
        return false   -- es_deus_* / unknown prefix -- treat as cross-char
    end

    local risky = {}  -- {career, weapon_key, source_node}
    for career, weapons in pairs(weapon_unlock_map) do
        if type(weapons) == "table" then
            for _, weapon_key in ipairs(weapons) do
                if not _is_native(career, weapon_key) then
                    local entry = rawget(iml, weapon_key)
                    local tpl_name = entry and entry.template
                    local tpl = tpl_name and rawget(Weapons, tpl_name)
                    if type(tpl) == "table" then
                        local linkings = {
                            tpl.left_hand_attachment_node_linking,
                            tpl.right_hand_attachment_node_linking,
                            tpl.ammo_unit_attachment_node_linking,
                        }
                        for _, link in ipairs(linkings) do
                            if type(link) == "table" and type(link.third_person) == "table" then
                                local unw = link.third_person.unwielded
                                if type(unw) == "table" then
                                    for _, e in ipairs(unw) do
                                        local src = e and e.source
                                        if type(src) == "string"
                                                and src:sub(1, 11) == "a_unwielded" then
                                            risky[#risky + 1] = string.format(
                                                "%s/%s -> %s", career, weapon_key, src)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if #risky > 0 then
        return string.format(
            "cross-char port(s) with body-specific unwielded source node "
            .. "(crash risk -- substitute with j_hips or run-time hook): %s",
            table.concat(risky, "; "))
    end
end)

-- v0.12.99-dev: VMF rejects `type = "group"` widgets with zero `sub_widgets`
-- at init ("must have at least 1 sub_widget") and the whole mod fails to
-- load — silent surfacing failure that's hard to debug from in-game. Walk
-- the live data tree recursively; fail with the offending setting_id if
-- any group is empty. Burned twice: v0.12.96-dev (empty character bucket
-- in dev anim picker) and v0.12.98-dev (empty top-level picker group when
-- mod._weapon_unlock_map was nil at _data.lua time).
_rt_register("vmf_no_empty_group_widgets", function()
    -- Reload the same data file VMF reads. mod:dofile is idempotent for
    -- pure data builders (no side effects), so calling here at regression
    -- time doesn't disturb VMF's bound copy. We walk what VMF sees.
    local data = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_data")
    if not data or not data.options or not data.options.widgets then
        return "could not load weapon_tweaker_data.lua for inspection"
    end
    local offenders = {}
    local function _walk(widgets, path)
        if type(widgets) ~= "table" then return end
        for _, w in ipairs(widgets) do
            if type(w) == "table" and w.type == "group" then
                local sid = w.setting_id or "?"
                local children = w.sub_widgets
                if type(children) ~= "table" or #children == 0 then
                    offenders[#offenders + 1] = path .. "/" .. sid .. " (group has 0 sub_widgets)"
                else
                    _walk(children, path .. "/" .. sid)
                end
            end
        end
    end
    _walk(data.options.widgets, "")
    if #offenders > 0 then
        return string.format("%d empty VMF group(s) found (would trip 'must have at least 1 sub_widget' at boot): %s",
            #offenders, table.concat(offenders, "; "))
    end
end)

_rt_register("fire_fx_package_resident", function()
    -- GH #128 (v0.12.159-dev): cross-character fire weapons (Drakefire Pistols,
    -- Drakegun, Fireball/Flamethrower staves) CTD'd non-native careers because
    -- their AOE explosion particles ride the Sienna career package bw_unchained,
    -- which a cross-char wielder never loads. wt force-loads it at mod init
    -- (_force_load_fire_explosion_packages). If that load is removed/renamed the
    -- crash returns; this asserts the package is resident.
    if not (Managers and Managers.package) then return "skip: Managers.package not ready (run in-keep)" end
    local pkg = "resource_packages/careers/bw_unchained"
    if not Managers.package:has_loaded(pkg) then
        return "fire-fx package NOT resident (#128 regression) -- " .. pkg
    end
end)

_rt_register("necromancer_fx_package_resident_if_dlc", function()
    -- v0.12.163-dev: the Necromancy/Soulstealer Staff (bw_necromancy_staff) on a
    -- cross-char wielder needs bw_necromancer's particles
    -- (fx/wpnfx_necromancer_skullstaff_*), which are NOT in bw_unchained. wt
    -- force-loads bw_necromancer at mod init, GATED on the Necromancer DLC
    -- (`shovel`) being owned (force-loading a non-owned DLC package would itself
    -- crash). So this only asserts residence when the DLC is owned.
    if not (Managers and Managers.package and Managers.unlock) then return "skip: managers not ready (run in-keep)" end
    local um = Managers.unlock
    if not (um.dlc_exists and um.is_dlc_unlocked and um:dlc_exists("shovel") and um:is_dlc_unlocked("shovel")) then
        return "skip: Necromancer (shovel) DLC not owned -- package intentionally not force-loaded"
    end
    local pkg = "resource_packages/careers/bw_necromancer"
    if not Managers.package:has_loaded(pkg) then
        return "necromancer fx package NOT resident (soulstealer-crash regression) -- " .. pkg
    end
end)

_rt_register("no_dwarf_dual_hammers_on_saltzpyre", function()
    -- v0.12.164-dev: dr_dual_wield_hammers removed from the non-WP Saltzpyre
    -- careers (redundant with wh_dual_hammer "Dual Skullsplitters" they already
    -- have). Guard that a future unlock-map edit doesn't silently re-add it.
    if type(weapon_unlock_map) ~= "table" then return "skip: weapon_unlock_map not loaded" end
    local bad = {}
    for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
        local list = weapon_unlock_map[c]
        if type(list) == "table" then
            for _, k in ipairs(list) do
                if k == "dr_dual_wield_hammers" then bad[#bad + 1] = c end
            end
        end
    end
    if #bad > 0 then return "dr_dual_wield_hammers back on Saltzpyre: " .. table.concat(bad, ", ") end
end)

_rt_register("saltzpyre_dual_axes_wield_axe_falchion", function()
    -- v0.12.168: Bardin's "Dual Axes" (dual_wield_axes_template_1) on Saltzpyre must
    -- wield as the Dual Axe & Falchion (to_dual_axe_sword_wh), NOT WP Dual Hammers
    -- (to_dual_hammers_priest). Guards the wt_wield_patches.bulk entry from reverting.
    local wp = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.bulk
    local e = wp and wp.dual_wield_axes_template_1
    if not e then return "skip: wield-patch module not loaded" end
    for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
        if e[c] ~= "to_dual_axe_sword_wh" then
            return "dual axes " .. c .. " wield = " .. tostring(e[c]) .. " (expected to_dual_axe_sword_wh)"
        end
    end
end)

_rt_register("saltzpyre_dagger_wield_falchion", function()
    -- v0.12.168: Sienna's "Dagger" (one_handed_daggers_template_1) on Saltzpyre must
    -- wield as 1H Falchion (to_1h_sword), NOT Fencing Sword/Rapier (to_fencing_sword).
    local wp = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.bulk
    local e = wp and wp.one_handed_daggers_template_1
    if not e then return "skip: wield-patch module not loaded" end
    for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
        if e[c] ~= "to_1h_sword" then
            return "dagger " .. c .. " wield = " .. tostring(e[c]) .. " (expected to_1h_sword)"
        end
    end
end)

_rt_register("kruber_has_saltzpyre_crossbow", function()
    -- #138: wh_crossbow (Saltzpyre's "Crossbow") kept getting dropped from Kruber's
    -- unlock_map despite working (baked anims/offsets + the a_unwielded_crossbow
    -- j_hips crash-fix via _patch_xchar_unwielded_attachment_safe). Guard it stays
    -- in all 4 Kruber careers so it can't silently vanish from the menu again.
    if type(weapon_unlock_map) ~= "table" then return "skip: weapon_unlock_map not loaded" end
    local missing = {}
    for _, c in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
        local list = weapon_unlock_map[c]
        local found = false
        if type(list) == "table" then
            for _, k in ipairs(list) do if k == "wh_crossbow" then found = true; break end end
        end
        if not found then missing[#missing + 1] = c end
    end
    if #missing > 0 then return "wh_crossbow missing from Kruber unlock_map: " .. table.concat(missing, ", ") end
end)

_rt_register("no_redundant_bardin_1h_on_saltzpyre", function()
    -- #187: Bardin's dr_1h_axe (≡ Saltzpyre wh_1h_axe) and dr_1h_hammer
    -- (≡ Saltzpyre wh_1h_hammer Skullsplitter) are redundant on Saltzpyre and were
    -- removed (kept their entries to re-add to Saltzpyre = a bug). Guard them out of
    -- the non-WP Saltzpyre unlock lists.
    if type(weapon_unlock_map) ~= "table" then return "skip: weapon_unlock_map not loaded" end
    local bad = {}
    for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
        local list = weapon_unlock_map[c]
        if type(list) == "table" then
            for _, k in ipairs(list) do
                if k == "dr_1h_axe" or k == "dr_1h_hammer" then bad[#bad + 1] = c .. ":" .. k end
            end
        end
    end
    if #bad > 0 then return "redundant Bardin 1h back on Saltzpyre: " .. table.concat(bad, ", ") end
end)

_rt_register("dev_picker_names_localized", function()
    -- #159: the dev 3P Anim Picker must show DOCUMENTED localized weapon names,
    -- never raw internal keys (the tester saw "Sienna bw_deus_01" instead of
    -- "Sienna: Coruscation Staff" because the seven staves were missing from the
    -- old hardcoded _WEAPON_NAME and fell back to the key). _weapon_display_name
    -- now resolves from the Availability loc; this guards every catalog weapon.
    if not (_wt_dev_anim_picker and _wt_dev_anim_picker.unresolved_display_names) then
        return "skip: picker has no unresolved_display_names()"
    end
    local bad = _wt_dev_anim_picker.unresolved_display_names()
    if type(bad) == "table" and #bad > 0 then
        return "picker weapons showing raw internal keys (no documented name): " .. table.concat(bad, ", ")
    end
end)

_rt_register("dev_picker_group_labels_registered", function()
    -- #159/#197 END-TO-END: the REGISTERED localized label for every picker weapon
    -- group (the actual string VMF renders) must resolve to a real name — not a raw
    -- internal key (#159), and not an unregistered <key>/bare setting_id (#197 — a
    -- label registered before names could resolve). This checks the registered value
    -- (mod:localize on the group sid), NOT a freshly-recomputed label, so it would
    -- have CAUGHT #197 (the in-game `dev_picker_names_localized` test rebuilds fresh
    -- and so resolved correctly even while the registered menu labels were raw).
    if not (_wt_dev_anim_picker and _wt_dev_anim_picker.catalog_group_keys) then
        return "skip: picker has no catalog_group_keys()"
    end
    local entries = _wt_dev_anim_picker.catalog_group_keys()
    if type(entries) ~= "table" or #entries == 0 then return "skip: empty picker catalog" end
    local bad = {}
    for _, e in ipairs(entries) do
        local s = mod:localize(e.sid)
        if type(s) ~= "string" or s == "" then
            bad[#bad + 1] = e.weapon_key .. "=<empty>"
        elseif s == e.sid or s:sub(1, 1) == "<" then
            bad[#bad + 1] = e.weapon_key .. "=<unregistered>"
        elseif s:find(e.weapon_key, 1, true) then
            bad[#bad + 1] = e.weapon_key .. "=<raw-key>"
        end
    end
    if #bad > 0 then
        return "picker group labels not localized (registered values): " .. table.concat(bad, ", ")
    end
end)

_rt_register("wt_loc_raw_published", function()
    -- #197: the dev picker resolves documented weapon names by reading
    -- mod._wt_loc_raw directly (NOT mod:localize, which errors "localization file was
    -- not loaded" when the catalog is built before loc registration). Guard that the
    -- localization file still publishes the raw table with the unlock entries.
    if type(mod._wt_loc_raw) ~= "table" then
        return "mod._wt_loc_raw not published by localization file — picker names fall back to raw keys (#197)"
    end
    if type(mod._wt_loc_raw["unlock_es_mercenary_bw_deus_01"]) ~= "table" then
        return "mod._wt_loc_raw present but missing expected unlock entries"
    end
end)

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

-- ============================================================
-- Dev tooling installs (v0.12.96-dev)
-- ============================================================
-- Both modules expose M.install(). Called HERE, at the bottom of wt.lua, so
-- the template patchers above have already populated `Weapons.<template>`
-- with their initial values — the anim picker reads from those live tables
-- at install time to seed its dropdown defaults.
_wt_dev_anim_picker.install()

mod:info("[mem-probe] wt boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_WT) / 1024)
_wt_dev_hold_pose.install()