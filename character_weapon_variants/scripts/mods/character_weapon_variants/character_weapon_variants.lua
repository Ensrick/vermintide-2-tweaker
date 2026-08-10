local mod = get_mod("character_weapon_variants")
_MEM_PROBE_T0_CWV = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.1.506-dev"
mod._cwv_acquisition = mod:dofile("scripts/mods/character_weapon_variants/_cwv_acquisition")
mod._cwv_old_musket_interrupt = mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_interrupt")
mod._cwv_dev_anim_picker = mod:dofile("scripts/mods/character_weapon_variants/cwv_dev_anim_picker")
mod._cwv_smoke_bomb_probe = mod:dofile("scripts/mods/character_weapon_variants/_cwv_smoke_bomb_probe")
mod._cwv_smoke_bomb_probe.install(mod)
-- #915: vanilla-ownership provenance for every illusion-source registry scan.
mod._cwv_illusion_provenance = mod:dofile("scripts/mods/character_weapon_variants/_cwv_illusion_provenance")

-- RPC schema for cwv's own VMF mod-to-mod channels (VMF_RECIPES section 10).
-- The peer-parity beacon and feature-owned channels (including #604 Crowbill
-- mode) each validate their own fixed schema. Bump ONLY when a shared cwv
-- network_send payload shape changes. Kept on `mod` (a table field, not a
-- file-scope local) because this chunk sits at the Lua 5.1 200-local ceiling
-- (see the `_om` note below) -- a new top-level local could overflow it.
mod.CWV_RPC_SCHEMA = 1

-- v0.1.332: source-pattern marker constant for the /cwv_regression_test
-- `cwv_networklookup_uses_rawget` check (audit `.test_coverage_audit_2026-05-24.md`
-- PARTIAL row 5 — promoted to PASS by adding a runtime check beside the
-- existing strict-table-lookup lint coverage at the 3 RPC-handler sites).
local CT_CWV_NETWORKLOOKUP_RAWGET_MARKER_v0_1_332 = "cwv-networklookup-rawget-hardened-3-sites"
local CT_CWV_ITEMMASTERLIST_RAWGET_MARKER_v0_1_333 = "cwv-itemmasterlist-rawget-auto-register-all"
-- v0.1.338: source-pattern marker constant for the /cwv_regression_test
-- `cwv_slot_extension_scoped` check. The slot_melee "ranged" extension at
-- line ~3730 was previously applied broadly to every career in CareerSettings
-- (28 careers), which produced a dual-state-machine collision on Grail Knight
-- (and likely other careers) — both melee state machines competing for the
-- same FP rig produced wrong-grip / corrupted-looking first-person weapons.
-- v0.1.338 narrows the extension to ONLY careers that own at least one
-- variant flagged `cross_slot = true` (currently the Old Musket → 4 Empire
-- careers). Source-pattern: must walk `_variant_definitions` and union the
-- `careers` arrays of every entry with `cross_slot = true`.
local CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338 = "cwv-slot-extension-scoped-to-cross-slot-variant-careers"
mod._cwv_fix_markers = { nl_rawget = CT_CWV_NETWORKLOOKUP_RAWGET_MARKER_v0_1_332, iml_rawget = CT_CWV_ITEMMASTERLIST_RAWGET_MARKER_v0_1_333, slot_extension = CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338 } -- #1148
-- v0.1.339 (Issue #33): belt-and-suspenders counter that the consolidated
-- `mod:hook_safe("SimpleInventoryExtension", "wield", ...)` registration site
-- (~line 1336) increments exactly once. Regression test
-- `cwv_wield_hook_unique` asserts this is 1 — catches accidental reintroduction
-- of a duplicate hook_safe on the same (Class, method) which VMF silently
-- shadows (VMF_RECIPES.md § 1). Original burn: v0.1.336 added a second
-- registration ~line 9499 for the debug-mode wield dump, shadowing the
-- line-1336 cross-access tracking and silently breaking 3P anim remap.
-- v0.1.337 consolidated both bodies; v0.1.339 adds this regression guard.

-- Issue #1: old-musket + shared musket-pool runtime state, consolidated into a
-- single file-scope local holder instead of ~28 bare globals. Kept as ONE table
-- (not individual `local`s) because the main chunk already sits at 199/200 Lua
-- 5.1 locals; 28 more file-scope locals overflow the 200-local ceiling (that is
-- what broke the v0.1.330/331 attempt). Fields keep their original names so the
-- refactor is a pure `_om.` prefix with no behavior change.
local _om = {}
_om.infantry_spear = mod:dofile("scripts/mods/character_weapon_variants/_cwv_infantry_spear"); _om.javelin_gate = mod:dofile("scripts/mods/character_weapon_variants/_cwv_javelin_gate")
_om.cross_slot_filter = mod:dofile("scripts/mods/character_weapon_variants/_cwv_cross_slot_filter")
_om.exact_appearance = mod:dofile("scripts/mods/character_weapon_variants/_cwv_exact_appearance"); _om.appearance_lifecycle_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_appearance_lifecycle")
_om.identity_peer_pull = mod:dofile("scripts/mods/character_weapon_variants/_cwv_identity_peer_pull")
_om.husk_transform_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_husk_transform_policy"); _om.appearance_fade = mod:dofile("scripts/mods/character_weapon_variants/_cwv_appearance_fade")(mod, _om)
_om.greataxe = mod:dofile("scripts/mods/character_weapon_variants/_cwv_greataxe"); _om.dawi_maces = mod:dofile("scripts/mods/character_weapon_variants/_cwv_dawi_maces")
_om.crowbill_family = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_family"); _om.crowbill_hammer_mode = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_hammer_mode")
_om.crowbill_presentation = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_presentation"); _om.peer_resolver = mod:dofile("scripts/mods/character_weapon_variants/_cwv_peer_resolver")
_om.crowbill_runtime = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_runtime"); _om.combat_style_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_combat_styles")
_om.rapier_contract = mod:dofile("scripts/mods/character_weapon_variants/_cwv_rapier_contract"); _om.inventory_icons = mod:dofile("scripts/mods/character_weapon_variants/_cwv_inventory_icons")
_om.outrider_animation = mod:dofile("scripts/mods/character_weapon_variants/_cwv_outrider_animation"); _om.style_rewield = mod:dofile("scripts/mods/character_weapon_variants/_cwv_style_rewield")
-- Public sibling-renderer contract: call resolve(icon, renderer), never guess atlas residency.
mod._cwv_inventory_icons = _om.inventory_icons
-- #787: mod data registered the private atlas before this script runs. Finish
-- its VMF-missing masked+saturated variant so the exact Athanor Gui may prove
-- and retain the paired icon instead of taking the single-axe fallback.
_om.icon_variants = _om.inventory_icons.complete_masked_saturated(rawget(_G, "UIAtlasHelper"))
pcall(printf, "[cwv:787] paired icon atlas variants=%d expected=%d",
	_om.icon_variants, 9)
mod._cwv_crowbill_family = _om.crowbill_family
mod._cwv_crowbill_hammer_mode = _om.crowbill_hammer_mode
mod._cwv_crowbill_presentation = _om.crowbill_presentation
mod._cwv_crowbill_runtime = _om.crowbill_runtime
_om.damage_profile_wire = mod:dofile("scripts/mods/character_weapon_variants/_cwv_damage_profile_wire")
-- #423/#424 exact-catalog wire system. wire_catalog is the byte-identical copy of
-- tools/shared_lib/_lib_wire_catalog.lua (MOD_DEPENDENCIES.md standalone invariant
-- forbids a get_mod() runtime dep); thrown_wire_policy is the pure disposition
-- policy; exact_wire_runtime owns both exact peer channels and the send hook.
_om.wire_catalog = mod:dofile("scripts/mods/character_weapon_variants/_lib_wire_catalog")
_om.thrown_wire_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_thrown_wire_policy")
_om.exact_wire_runtime = mod:dofile("scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime")
_om.cosmetic_skin_wire = mod:dofile("scripts/mods/character_weapon_variants/_cwv_cosmetic_skin_wire")
_om.profile_package_wire = mod:dofile("scripts/mods/character_weapon_variants/_cwv_profile_package_wire")
_om.deus_identity = mod:dofile("scripts/mods/character_weapon_variants/_cwv_deus_identity")
_om.mod_unit_preview = mod:dofile("scripts/mods/character_weapon_variants/_cwv_mod_unit_preview")
_om.resource_residency = mod:dofile("scripts/mods/character_weapon_variants/_lib_resource_residency")
_om.appearance_descriptor = mod:dofile("scripts/mods/character_weapon_variants/_lib_appearance_descriptor")
_om.weapon_appearance = mod:dofile("scripts/mods/character_weapon_variants/_lib_weapon_appearance").new()
_om.old_musket_appearance_policy = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_old_musket_appearance")
_om.old_musket_preview = mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_preview")
_om.old_musket_preview.set_resource_residency(_om.resource_residency)
_om.old_musket_preview_pose = mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_preview_pose")
_om.musket_ammo_pool_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_ammo_pool")
mod._cwv_preview_descriptor = _om.old_musket_preview -- resource-mode compatibility; resolver is installed with the pilot below
_om.mod_unit_preview.install({ _om.greataxe, _om.crowbill_family, _om.old_musket_preview, _om.profile_package_wire })
_om.mace_hammer_identity_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_mace_hammer_identity")
_om.mace_hammer_identity = _om.mace_hammer_identity_policy.new()
-- #1145 (#660 Wave A): per-wearer re-wield coalescer + mid-destroy guard; both
-- CWV re-wield edges enqueue here. Rationale in the module header. Loaded
-- BEFORE _cwv_exact_pair_state so that module can see mod._cwv_rewield.
mod._cwv_rewield = mod:dofile("scripts/mods/character_weapon_variants/_cwv_rewield_coalescer")
mod._cwv_rewield.install(mod)
mod:dofile("scripts/mods/character_weapon_variants/_cwv_exact_pair_state").install(mod, _om)

-- Single source of truth for the husk override-unit package ref (issue #418).
-- Used by BOTH the residency force-load producer (_force_load_husk_override_units)
-- AND the preview/browser mesh-swap consumer's has_loaded gate. A duplicated bare
-- literal at the two sites silently degraded every preview swap to the base mesh
-- on any rename (no crash, no log) -- keep both ends on this constant.
_om.HUSK_OVERRIDE_REF = "cwv_husk_override_units"

-- ============================================================================
-- issue 423 (BUG_CLASSES 31, GAMEPLAY axis): cwv damage-profile wire-safety map.
-- ----------------------------------------------------------------------------
-- Every cwv-cloned damage_profile is appended to NetworkLookup.damage_profiles
-- with a modded (out-of-vanilla-range) index. rpc_attack_hit is client->server
-- (weapon_system.lua:182); a cwv CLIENT's hit would ship that index to a non-cwv
-- HOST whose strict decode (weapon_system.lua:243 -- no rawget) fatals -> lobby
-- drop. The send-gate (search "[cwv:423]" below) substitutes the vanilla SOURCE
-- profile id whenever peer parity is unconfirmed; this map records, at clone time,
-- the vanilla source each cwv profile was derived from so the substitution is the
-- base weapon's own behavior (a GAMEPLAY axis: we degrade damage, we don't crash).
-- _om (not a top-level local) per the Lua 5.1 200-local ceiling.
_om._cwv_damage_profile_wire_source = {}   -- cwv profile key -> vanilla source name
_om._cwv_wire_fallback_profile_id  = nil   -- captured vanilla id; belt-and-suspenders
-- #423 exact catalog: bumped by every producer. The snapshot pins the value it
-- captured, so a mapping recorded AFTER finalization invalidates the catalog
-- instead of leaving a cwv id proven by a stale identity.
_om._cwv_damage_profile_generation = 0
function _om._record_cwv_dp_source(cwv_key, source_name)
    -- Record only genuine vanilla sources (never chain onto another cwv profile).
    if type(cwv_key) ~= "string" or type(source_name) ~= "string" then return end
    if source_name:sub(1, 4) == "cwv_" then return end
    _om._cwv_damage_profile_generation = _om._cwv_damage_profile_generation + 1
    _om._cwv_damage_profile_wire_source[cwv_key] = source_name
    if not _om._cwv_wire_fallback_profile_id then
        local dp = rawget(_G, "NetworkLookup")
        dp = dp and dp.damage_profiles
        local sid = dp and rawget(dp, source_name)
        if type(sid) == "number" then _om._cwv_wire_fallback_profile_id = sid end
    end
end

-- ============================================================================
-- Peer-parity beacon (issue 371 / issue 424 / BUG_CLASSES 31)
-- ============================================================================
-- Shared, COPIED single-source lib (master: tools/shared_lib/_lib_peer_parity.lua;
-- MOD_DEPENDENCIES.md standalone invariant forbids a get_mod() runtime dep). It
-- proves "does every lobby peer have cwv?" over VMF's own mod-to-mod channel
-- (wire-safe by construction -- no vanilla NetworkLookup key, no vanilla RPC),
-- and auto-disables GAMEPLAY features whose modded indices would crash a non-cwv
-- peer, re-enabling once everyone has the mod. mod:dofile returns a fresh module
-- per call (not a singleton) so the lib is a FACTORY; build ONE instance here.
-- Fail-safe: features stay inert until all peers are positively confirmed; any
-- beacon error forces them OFF.
do
    local ok, factory = pcall(function()
        return mod:dofile("scripts/mods/character_weapon_variants/_lib_peer_parity")
    end)
    if ok and type(factory) == "function" then
        local ok2, inst = pcall(factory, mod, {
            channel        = "cwv_peer_parity_present",
            schema         = mod.CWV_RPC_SCHEMA,
            mod_label      = "Character Weapon Variants",
            echo_prefix    = "[cwv]",
        })
        if ok2 and type(inst) == "table" then
            mod._cwv_peer_parity = inst
            -- #1158 install-transaction fanout (LANDED): install() runs receiver
            -- registration and mod.update ownership in ONE pcall and returns the
            -- commit boolean. The instance stays published either way -- the
            -- gated-feature registrations below need it, and the lib now
            -- hard-gates every peer query and tick() on the same commit, so an
            -- uninstalled beacon answers false to all of them. The boolean is
            -- consumed as EVIDENCE so a non-committing install is visible in the
            -- log instead of silently permanent.
            local ok_install, committed = pcall(function() return inst:install() end)
            if ok_install and committed == true then
                mod:info("[cwv:371] peer-parity beacon installed (channel=cwv_peer_parity_present)")
            else
                -- mod:info, not mod:warning: VMF's warning channel posts to CHAT
                -- (#427). This is log-only operational evidence.
                mod:info("[cwv:371] WARNING peer-parity install did not commit (%s); gated features stay inert (fail-safe)",
                    tostring(committed))
            end
        else
            mod:warning("[cwv:371] peer-parity factory failed: %s", tostring(inst))
        end
    else
        mod:warning("[cwv:371] peer-parity lib failed to load: %s", tostring(factory))
    end
end

mod:info("Character Weapon Variants v%s loading", MOD_VERSION)
-- v0.1.344: removed the in-game chat banner echo per PROJECT_STANDARDS.md
-- § 3.6 "Chat-echo policy". The applied marker line further down
-- ([cwv] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- and lands in the log file (visible across console_log-*.log). The old
-- `feedback_version_bump.md` rationale (visibility without opening the log)
-- is now satisfied by the applied marker line itself plus the version
-- suffix in the Workshop title — chat banner was redundant.

-- /cwv_regression_test scaffold (v0.1.331). See corresponding _rt_register
-- calls at the end of this file. Each registered check is a function returning
-- nil for PASS or a string for FAIL. Same pattern as ct/cosmetics_tweaker.
-- Doctrine: PROJECT_STANDARDS §15 — "every bug requires a test."
-- Renamed from `regression_test` per `feedback_vt2_chat_command_syntax.md` /
-- ct v0.7.91 — chat commands are globally namespaced and `regression_test`
-- is already claimed by `cim`.
-- #1156: opts.known_defect marks a check as a KNOWN OPEN defect - its failure is an XFAIL (never a suite failure), its success an XPASS (a LOUD failure: verify the fix or drop the annotation).
local _RT_CHECKS = {}
local function _rt_register(name, fn, opts)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn, defect = opts and opts.known_defect }
end
mod:command("cwv_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail, xfail = 0, 0, 0
    mod:echo("=== cwv regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        local d = c.defect and tostring(c.defect)
        if ok and err == nil and d then
            mod:echo("  XPASS: %s -- open issue %s no longer reproduces; verify the fix or drop known_defect", c.name, d); fail = fail + 1
            pcall(printf, "[regression] XPASS %s -- open issue %s no longer reproduces; verify the fix or drop known_defect", c.name, d)
        elseif ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1; mod:info("[regression] PASS %s", c.name)
        elseif d then
            mod:echo("  XFAIL: %s (open issue %s) -- %s", c.name, d, tostring(err)); xfail = xfail + 1
            pcall(printf, "[regression] XFAIL %s (open issue %s): %s", c.name, d, tostring(err))
        else
            mod:echo("  FAIL: %s -- %s", c.name, tostring(err)); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, tostring(err))
        end
    end
    mod:echo("=== %d passed, %d failed, %d xfail (known defects) ===", pass, fail, xfail)
end)
mod:info("[regression-test-command] registered as /cwv_regression_test")

-- #1145: checks register from the module that owns the guarded code (§2.2a
-- rule 6), keeping marker and reader in one file (the #1148 scope-loss class).
mod._cwv_rewield.install_checks(mod, _rt_register)

-- ============================================================================
-- Debug-mode logging helper (v0.1.336; gate renamed v0.1.340)
-- ============================================================================
-- Both route through VMF logging (mod:debug / mod:warning), gated by VMF
-- output_mode. _dbg uses mod:debug (output_mode_debug gate); _dbg_alert uses
-- mod:warning (output_mode_warning gate). Safe to leave call sites in hot
-- paths -- VMF skips formatting when the output mode is off.
--
-- KEEP UNCONDITIONAL (do NOT route through _dbg):
--   * mod:info("Character Weapon Variants v%s ...") boot lines.
--   * mod:warning / mod:error -- guards must always surface.
--   * Registration FAILURE logs at load time (we need to see them).
--   * Template-creation summary lines ("Created <foo>_template ...") --
--     these fire once at boot and document the registered table contents.
--
-- v0.1.351-dev: per-mod toggle removed; _dbg routes through VMF output_mode.
-- `_dbg` = confirmation / expected behavior — mod:debug (file only).
-- `_dbg_alert` = unexpected / wrong / mismatch — LOG-ONLY via pcall-guarded
-- engine printf (#427/issue 240: mod:warning posts to CHAT under VMF defaults;
-- printf always lands in console-*.log, even with mod logging OFF, and never
-- in chat; pcall so a format slip never faults the caller).
local function _dbg(fmt, ...)
    mod:debug("[cwv:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[cwv:dbg] " .. fmt, ...) then
        pcall(printf, "[cwv:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/character_weapon_variants/character_weapon_variants_data")
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

mod:info("[cwv:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[cwv] v%s loaded", MOD_VERSION))
end

-- ============================================================================
-- DESIGN INTENT — READ BEFORE "FIXING" CROSS-CHARACTER BASE TEMPLATES
-- ============================================================================
-- CWV variants INTENTIONALLY clone from cross-character base templates. When
-- you see `base_weapon = "bw_1h_mace"` on a Kruber variant, or
-- `base_weapon = "wh_1h_hammer"` on a Bardin variant, that is the FEATURE,
-- not a bug. The whole point of this mod is semi-lore-friendly variants that
-- bring another character's moveset onto a receiver — Kruber wielding
-- Sienna's 2H mace, Bardin wielding Saltzpyre's priest hammer, Kruber
-- wielding Kerillian's dual swords, etc.
--
-- The 1P side just works (universal across characters). The 3P side is the
-- discipline: `anim_event_3p` remap onto the receiver's good-enough native
-- 3P vocabulary so other players in the lobby see something plausible, plus
-- receiver-appropriate `AttachmentNodeLinking` to avoid foreign unwielded
-- bones. See ISAAK_RECIPE.md for the lessons-learned reference, and the
-- ANIMATION_FIX_PLAYBOOK.md for the full per-action remap procedure.
-- ============================================================================

-- ============================================================================
-- ANIMATION ARCHITECTURE — READ BEFORE TOUCHING ANY ANIM CODE BELOW
-- ============================================================================
-- 1P (first-person) animations are UNIVERSAL across all six characters and all
-- weapons. The first_person_base unit is shared; any weapon's 1P state machine
-- and clips play correctly on any character's first-person view, by default,
-- with zero work from us.
--
-- This means: do not override anim_event (1P), wield_anim (1P), or
-- state_machine on any cloned template, and do not author per-character
-- variants of a template "to fix 1P" — there is nothing to fix. The 1P side
-- works automatically.
--
-- ALL animation work in this file is 3P-only:
--   * anim_event_3p          — per-action 3P body anim event
--   * wield_anim_3p          — 3P body wield/equip pose
--   * wield_anim_career_3p   — per-career 3P wield override
--
-- The 3P body skeleton is character-specific (Kruber's empire skeleton has a
-- different event vocabulary than Kerillian's elf skeleton, etc.). When a
-- cross-character weapon's 3P anims look wrong, the fix lives in this 3P
-- vocabulary — never in any 1P field.
--
-- This rule keeps recurring as a misunderstanding. Every animation-touching
-- function below carries an inline reminder. See memory note
-- `feedback_1p_animations_universal.md` for the full rationale.
-- ============================================================================

-- ============================================================
-- Cross-character weapon analogues (public API)
-- ============================================================
-- Vanilla weapon items that are mechanically analogous and may share
-- cosmetic/visual assets when this mod is loaded. Other mods (e.g.
-- cosmetics_tweaker) read this to expand cosmetic targeting beyond a
-- single character.

-- v0.1.329-dev: removed unused public exports `mod.weapon_analogues` table
-- and `mod.get_analogues(item_key)` function. Repo grep + sibling-mod scan
-- (cosmetics_tweaker LA bridge, weapon_tweaker, gt_lobby manifest -- formerly lobby_tweaker, retired 2026-05-25)
-- confirmed zero external consumers. Cleanup per audit roadmap #13.
--
-- KNOWN PENDING (this file): 22 bare-global function/data declarations in
-- the Old Musket section (~line 4500+) need conversion to local forward-decl
-- pattern. Attempted in v0.1.330/331 today but introduced a Stingray
-- bundler crash; reverted. See:
--   https://github.com/Ensrick/vermintide-2-tweaker/issues/1
-- Plus an 8800-line file size that needs split per RECIPES.md:
--   https://github.com/Ensrick/vermintide-2-tweaker/issues/2

-- ============================================================
-- Policy-backed catalog is isolated so the entry file remains orchestration.
_om.variant_catalog = mod:dofile("scripts/mods/character_weapon_variants/_cwv_variant_catalog")({ om = _om })
local _career_weapon_actions = mod:dofile(
	"scripts/mods/character_weapon_variants/_lib_career_weapon_actions")
local _cwv_career_weapon_actions = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_career_weapon_actions")
-- Keep this on the mod table: the entry chunk is at Lua 5.1's local ceiling.
mod._cwv_effective_weapon_templates = mod:dofile(
	"scripts/mods/character_weapon_variants/_lib_effective_weapon_templates")
local _career_action_owner = "character_weapon_variants"
local _es_all_careers = _om.variant_catalog.es_all_careers
local _wh_all_careers = _om.variant_catalog.wh_all_careers
local _bw_all_careers = _om.variant_catalog.bw_all_careers
local _variant_definitions = _om.variant_catalog.definitions

-- Issue #599: default-on mace/hammer identity. CWV Dual Maces need an independent clone
-- because their source moveset is Bardin's Dual Hammers; changing that shared
-- template for speed would otherwise make the hammer family faster as well.
-- Native semantic families are explicit in `_cwv_mace_hammer_identity.lua`;
-- no name-pattern scan can accidentally catch a two-handed hammer.
do
	local policy = _om.mace_hammer_identity_policy
	local state = _om.mace_hammer_identity
	local function deep_clone(value)
		return table.clone(value, true)
	end
	local ok, err = state:ensure_cwv_dual_mace_template(Weapons, deep_clone)
	if not ok then
		mod:warning("[cwv:599] Dual Maces clone unavailable: %s", tostring(err))
	end

	local function register_damage_profile(profile_name)
		local lookup = NetworkLookup and NetworkLookup.damage_profiles
		if type(profile_name) ~= "string" or not lookup or rawget(lookup, profile_name) then return end
		local index = #lookup + 1
		rawset(lookup, index, profile_name)
		rawset(lookup, profile_name, index)
	end

	_om._apply_mace_hammer_identity = function(enabled)
		state:apply(enabled, Weapons, DamageProfileTemplates, PowerLevelTemplates,
			deep_clone, _om._record_cwv_dp_source, register_damage_profile)
		mod:info("[cwv:599] enabled=%s mace_speed=%.3f hammer_damage=%.3f hammer_cleave=%.3f",
			tostring(not not enabled), policy.MACE_SPEED_MULT,
			policy.HAMMER_DAMAGE_MULT, policy.HAMMER_CLEAVE_MULT)
	end

	_om._apply_mace_hammer_identity(mod:get(policy.SETTING_ID) ~= false)

	function mod.on_setting_changed(setting_id)
		if setting_id == policy.SETTING_ID then
			_om._apply_mace_hammer_identity(mod:get(policy.SETTING_ID) ~= false)
		end
	end

	-- #1002: opt into GUI Tweaker's owner-level bulk transaction. CWV's
	-- current setting callback owns one whole-template apply; run it at most
	-- once after all Equipment DEFAULT/profile values are persisted.
	function mod.on_settings_batch_changed(setting_ids)
		for i = 1, #(setting_ids or {}) do
			if setting_ids[i] == policy.SETTING_ID then
				_om._apply_mace_hammer_identity(mod:get(policy.SETTING_ID) ~= false)
				break
			end
		end
		pcall(printf, "[cwv:1002] settings=%d notifications=1", #(setting_ids or {}))
	end
end

-- #604: gameplay and transport owner. This builds a separate hammer template
-- from the exact Crowbill donor and installs one transition-only state channel.
do
	local ok, err = _om.crowbill_runtime.install(mod, _om)
	if not ok then
		mod:warning("[cwv:604] Crowbill hammer runtime unavailable: %s", tostring(err))
	end
end

-- Install at the original hook-registration point; order is part of the contract.
_om.cross_access = mod:dofile("scripts/mods/character_weapon_variants/_cwv_cross_access")(mod, {
	om = _om,
	dbg = _dbg,
	es_all_careers = _es_all_careers,
	wh_all_careers = _wh_all_careers,
})
local _cross_access_action_remap = _om.cross_access.action_remap
local _cwv_wield_hook_registration_count = _om.cross_access.wield_hook_registration_count
-- Core weapon-template constructors are isolated in one behavior-neutral owner.
-- Install exactly once at the original registration point; call order is load-bearing.
-- CWV_CORE_TEMPLATES_INSTALL_ONCE_v1
local _clone_damage_profile = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_core_templates")(mod, {
	om = _om,
	Weapons = Weapons,
	DamageProfileTemplates = DamageProfileTemplates,
	PowerLevelTemplates = PowerLevelTemplates,
	NetworkLookup = NetworkLookup,
	ItemMasterList = ItemMasterList,
	AttachmentNodeLinking = AttachmentNodeLinking,
	Projectiles = Projectiles,
	ActionTemplates = ActionTemplates,
	printf = printf,
}).clone_damage_profile

-- ============================================================
-- Crossbow base-template patches for Kruber (v0.1.347-dev)
-- ============================================================
-- Saltzpyre Crossbow → Kruber Handgun base-template patches. Migrated
-- from weapon_tweaker (it removed Kruber's wh_crossbow unlock and
-- ceded ownership to CWV's cwv_es_crossbow variant). The inventory
-- previewer looks up `Weapons[item.name].template` -> "crossbow_template_1"
-- (variants inherit entry.name from the base IML key — same constraint
-- as the outrider variant, see comment in
-- `_create_outrider_grenade_launcher_template`), so the Kruber wield_anim
-- must live on the base template, not a clone. Saltzpyre's wh_crossbow is
-- unaffected: his careers (wh_*) don't match the es_*-keyed entries.
--
-- Patched UNCONDITIONALLY (idempotent + Saltzpyre-safe). Gating only the
-- variant registration (in _auto_register_all) is enough — without the
-- variant registered, Kruber never holds the crossbow so the es_* entries
-- are dead data.
--
-- Wrapped in `do ... end` so the locals release back to the main chunk
-- (Lua 5.1 200-locals-per-function ceiling — see CLAUDE.md "Stingray /
-- Lua engine quirks").
do
	local function _patch_crossbow_template_for_kruber()
		if not Weapons or not Weapons.crossbow_template_1 then return end
		local tpl = Weapons.crossbow_template_1
		tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
		tpl.wield_anim_career_3p.es_mercenary       = "to_handgun"
		tpl.wield_anim_career_3p.es_huntsman        = "to_handgun"
		tpl.wield_anim_career_3p.es_knight          = "to_handgun"
		tpl.wield_anim_career_3p.es_questingknight  = "to_handgun"
		tpl.wield_anim_no_ammo_career_3p = tpl.wield_anim_no_ammo_career_3p or {}
		tpl.wield_anim_no_ammo_career_3p.es_mercenary       = "to_handgun_noammo"
		tpl.wield_anim_no_ammo_career_3p.es_huntsman        = "to_handgun_noammo"
		tpl.wield_anim_no_ammo_career_3p.es_knight          = "to_handgun_noammo"
		tpl.wield_anim_no_ammo_career_3p.es_questingknight  = "to_handgun_noammo"
	end
	_patch_crossbow_template_for_kruber()

	-- Lazy-built Kruber-safe third_person attachment table for wh_crossbow.
	-- The vanilla `crossbow_template_1.left_hand_attachment_node_linking.third_person
	-- .unwielded[1].source` is `a_unwielded_crossbow` — a body node only Saltzpyre's
	-- skeleton authors. The inventory previewer's `Unit.node(kruber_body,
	-- "a_unwielded_crossbow")` call bypasses pcall (engine fatal — see
	-- feedback_vt2_unit_node_not_pcall_safe). Substitute per-spawn during
	-- MenuWorldPreviewer.equip_item below; see the hook for the apply logic.
	local _cwv_crossbow_kruber_safe_third_person
	local function _build_crossbow_kruber_safe_third_person()
		if _cwv_crossbow_kruber_safe_third_person then
			return _cwv_crossbow_kruber_safe_third_person
		end
		local tpl = Weapons and Weapons.crossbow_template_1
		local src = tpl and tpl.left_hand_attachment_node_linking
						and tpl.left_hand_attachment_node_linking.third_person
		if type(src) ~= "table" then return nil end
		_cwv_crossbow_kruber_safe_third_person = {
			display   = src.display,   -- reference, unchanged
			wielded   = src.wielded,   -- reference, unchanged (j_leftweaponattach is universal)
			unwielded = { { source = "j_hips", target = 0 } },
		}
		return _cwv_crossbow_kruber_safe_third_person
	end

	-- Preview-time attachment-node guard for wh_crossbow on Kruber. Substitutes
	-- each spawn entry's `unit_attachment_node_linking` with the Kruber-safe
	-- table built above so the previewer's `Unit.node(..., "a_unwielded_crossbow")`
	-- call never fires on Kruber's body. Ported from weapon_tweaker
	-- `_wt_crossbow_kruber_attach_safe_apply` (v0.12.93-dev) minus the noisy
	-- per-step diagnostic lines that were only needed during the original
	-- debug pass — collapsed to a single summary `_dbg` on success.
	-- CONSOLIDATED hook_safe on (MenuWorldPreviewer, equip_item) — hook_safe does
	-- NOT chain on the same Class.method, so both preview-time concerns live here:
	--   Block A: wh_crossbow Kruber attach-node safety (avoid engine-fatal Unit.node).
	--   Block B: cwv variant mesh-swap on the inventory preview (issue 237,
	--            WEAPON_APPEARANCE_STANDARD §4.1 unit-resolution layer).
	-- Never add a second hook_safe on this pair — merge new concerns in here.
	mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_name, slot, backend_id, skin, skip_wield_anim)
		local slot_type = (type(slot) == "table" and slot.type) or nil
		if not slot_type then return end
		local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
		if not info or not info.spawn_data then return end

		-- Block A — wh_crossbow Kruber attach-node safety: substitute the left-hand
		-- entry's node linking so the previewer never calls
		-- Unit.node(kruber_body, "a_unwielded_crossbow") (engine-fatal, bypasses pcall).
		if item_name == "wh_crossbow" then
			local career = self._current_career_name
			if career and career:sub(1, 3) == "es_" then
				local safe = _build_crossbow_kruber_safe_third_person()
				if safe then
					local swapped = 0
					for _, entry in ipairs(info.spawn_data) do
						if entry.left_hand then
							entry.unit_attachment_node_linking = safe
							swapped = swapped + 1
						end
					end
					if swapped > 0 then
						_dbg("[cwv xbow-kruber attach] swapped=%d on career=%s", swapped, career)
					end
				end
			end
		end

		-- Block B — issue 237: rewrite the spawned MESH to the cwv variant's
		-- authored units on the inventory-preview path (path 3), which otherwise
		-- spawns the base weapon's mesh (a cwv clone keeps entry.name = base, so
		-- vanilla resolves the base units). Data mutation on the precomputed
		-- spawn_data BEFORE vanilla's World.spawn_unit (weapon_tweaker's preview-
		-- swap pattern). The helper lives near _find_def (defined far below) and
		-- is reached through the _om upvalue table, exactly like the husk helpers.
		if _om._cwv_preview_meshswap_apply then
			_om._cwv_preview_meshswap_apply(item_name, backend_id, skin, info)
		end
	end)
end

-- ============================================================
-- Musket / Old Musket runtime owner (#1159)
-- ============================================================
-- Both musket families' template construction, damage-profile clones, stance
-- toggle, remote fire-report observation and shared reserve-ammo pool live in
-- `_cwv_musket_runtime`. Loaded HERE, at the exact point the inline block ran,
-- so template registration and hook order are unchanged. The consolidated
-- BackendUtils.get_item_template hook stays below: it also routes combat-style
-- and Crowbill templates, and VMF drops a second hook on the same pair.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_runtime")(mod, { om = _om, dbg = _dbg })

-- ============================================================
-- Musket template-swap hook (BackendUtils.get_item_template)
-- ============================================================
-- Reads the per-item stance flag on item_data.mod_data and returns the
-- appropriate template. Without this hook, vanilla returns
-- musket_template (the one set on the variant def) regardless of stance.
-- The toggle helper above flips the flag and forces a destroy+add+wield
-- cycle, which makes vanilla call get_item_template again, which we
-- intercept here to return musket_template_melee on melee stance.

mod:hook("BackendUtils", "get_item_template", function(func, item_data, backend_id)
	local template = func(item_data, backend_id)
	if not item_data then return template end
	-- #620: one per-instance style owner chooses among pre-registered immutable
	-- templates. This remains in the existing singleton BackendUtils hook so a
	-- second VMF registration cannot shadow the musket/Crowbill paths.
	if _om.combat_styles and _om.combat_styles.resolve_template then
		local style_template = _om.combat_styles:resolve_template(item_data, backend_id)
		if style_template then return style_template end
	end
	-- #604: local owner selects one of two pre-registered Crowbill templates.
	-- Remote equipment remains the vanilla source template on the wire.
	if _om.crowbill_runtime and _om.crowbill_runtime.resolve_template then
		local crowbill_template = _om.crowbill_runtime.resolve_template(item_data, backend_id)
		if crowbill_template then return crowbill_template end
	end

	-- v0.1.301: identify variant family — cwv_es_musket vs cwv_es_musket_old.
	-- Both use mod_data.cwv_musket_stance as the per-item stance flag (it's
	-- per-item via mod_data so no name collision); we just return different
	-- template pairs depending on which family.
	local is_old_musket = false
	local is_musket     = false
	local canonical_key = _om._cwv_key_for_item
		and _om._cwv_key_for_item(item_data.backend_id or backend_id, item_data)
	if canonical_key == "cwv_es_musket_old" then
		is_old_musket = true
	elseif canonical_key == "cwv_es_musket" then
		is_musket = true
	elseif item_data.template == "old_musket_template" or item_data.template == "old_musket_template_melee" then
		is_old_musket = true
	elseif item_data.template == "musket_template" or item_data.template == "musket_template_melee" then
		is_musket = true
	else
		local bid = item_data.backend_id or backend_id
		if type(bid) == "string" then
			if bid:match("^cwv_es_musket_old_") then
				is_old_musket = true
			elseif bid:match("^cwv_es_musket_") then
				is_musket = true
			end
		end
	end
	if not (is_musket or is_old_musket) then return template end

	-- Read stance from mod_data; default to ranged.
	local stance = item_data.mod_data and item_data.mod_data.cwv_musket_stance or "ranged"
	if is_old_musket then
		if stance == "melee" and Weapons.old_musket_template_melee then
			return Weapons.old_musket_template_melee
		end
		return Weapons.old_musket_template or template
	end
	if stance == "melee" and Weapons.musket_template_melee then
		return Weapons.musket_template_melee
	end
	return Weapons.musket_template or template
end)

-- ============================================================
-- Cross-slot inventory: musket items appear in BOTH ranged AND melee
-- inventory grids
-- ============================================================
-- v0.1.268: per user direction, both `cwv_es_musket` (ranged-slot
-- inheritance) and `cwv_es_musket_polearm` (melee-slot inheritance)
-- should be equippable in EITHER slot. Player picks which musket
-- goes where; equipping consumes the item from both lists.
--
-- Mechanism: vanilla's `BackendInterfaceItemPlayfab:get_filtered_items`
-- evaluates the slot-grid filter string ("slot_type == ranged" /
-- "slot_type == melee") against each backend item. Our hook detects
-- those filters and APPENDS any musket items the player owns that
-- weren't already in the result. Since each item is a unique backend
-- entry, equipping it in one slot prevents it from showing as
-- available in the other (the slot tracks the equipped ItemId).
--
-- This is a UI-layer trick — the items keep their declared slot_type
-- in IML; the filter just becomes permissive for our muskets. The
-- equip path doesn't check slot_type compatibility, so vanilla accepts
-- the cross-slot equip without complaint. The wielded weapon's
-- behavior is determined by its template (musket_template), not by
-- its slot, so it fires identically in either slot.

-- v0.1.308: list of cwv item-key prefixes that should be cross-slot
-- equippable. These items inherit slot_type="ranged" via their base_weapon
-- but the player should be able to equip them in either slot_ranged or
-- slot_melee via the cross-slot inject below. Other cwv ranged weapons
-- (e.g. cwv_es_outrider_grenade_launcher) are NOT in this list and remain
-- ranged-only.
local _CWV_CROSS_SLOT_PREFIXES = {
	"cwv_es_musket",          -- musket family (covers cwv_es_musket and cwv_es_musket_old + backend_ids)
}

-- v0.1.327: check ALL candidate id fields, not just the first non-nil one.
-- Earlier `data.key or data.name or item.ItemId or item.backend_id` would
-- short-circuit on the first non-nil — if `data.name` happened to be the
-- inherited base name "es_handgun", the function returned false even though
-- `item.ItemId` was "cwv_es_musket_old_001". Likely root cause of "musket
-- doesn't appear in melee slot" in v0.1.316+ (post-filter scoping dropped
-- the item because the gate returned false).
local function _is_cwv_musket_item(item)
	if not item then return false end
	local data = item.data or item.master_item or item
	local bid = item.backend_id or item.ItemInstanceId
		or (data and (data.backend_id or data.ItemInstanceId))
	local canonical_key = _om._cwv_key_for_item and _om._cwv_key_for_item(bid, item)
	if canonical_key == "cwv_es_musket" or canonical_key == "cwv_es_musket_old" then
		return true
	end
	local function _check(key)
		if type(key) ~= "string" then return false end
		for _, prefix in ipairs(_CWV_CROSS_SLOT_PREFIXES) do
			if string.find(key, prefix, 1, true) == 1 then
				return true
			end
		end
		return false
	end
	if _check(data and data.key) then return true end
	if _check(data and data.name) then return true end
	if _check(item.ItemId) then return true end
	if _check(item.backend_id) then return true end
	if _check(data and data.backend_id) then return true end
	if _check(data and data.mod_data and data.mod_data.backend_id) then return true end
	return false
end

-- ============================================================
-- Career slot-type override + scoped post-filter
-- ============================================================
-- v0.1.312: combine the v0.1.304 broad career override (which actually
-- surfaced items in the melee grid) with a post-filter on the result that
-- removes non-allowlisted ranged items. End result: only items flagged
-- with `def.cross_slot = true` (currently just `cwv_es_musket_old`) appear
-- in BOTH grids; other ranged weapons stay in slot_ranged only.
--
-- History:
--   v0.1.304 — added "ranged" to slot_melee. Worked but showed ALL ranged.
--   v0.1.310 — reverted to cross-slot inject only. Didn't surface items.
--   v0.1.311 — tried entry.slot_type = "cwv_dual" custom. Item disappeared
--              from BOTH grids (MIL/vanilla doesn't accept unknown slot_type).
--   v0.1.312 — back to broad career override + post-filter for scope.
-- v0.1.313: iterate ALL careers (not just hardcoded Kruber list). Append
-- "ranged" to any career's slot_melee that's exactly {"melee"} (i.e., the
-- default Kruber-style careers). Also clean up cwv_dual leftovers from
-- v0.1.311. Mutation deferred via `mod.on_all_mods_loaded` to ensure
-- CareerSettings is fully populated.
-- Post-filter REMOVED (was scoping items too aggressively or not running
-- on the path the user's UI uses). v0.1.304 broad behavior is restored —
-- ALL ranged weapons will appear in melee grid until we confirm what's
-- breaking, then re-scope.
--
-- v0.1.338 (BUG FIX — Grail Knight FP rig corruption): the broad mutation
-- above hit ALL 28 careers in `CareerSettings`. Once a career's `slot_melee`
-- accepts both `"melee"` and `"ranged"`, the keep loadout/preview resolver
-- can pick up TWO defaults for the same slot (one melee item, one ranged
-- item), leading to two FP state machines fighting over a single first-person
-- rig. User confirmed via bisect that disabling CWV restores the FP rig;
-- Grail Knight (`es_questingknight`) was the consistent repro case
-- (`es_bastard_sword` 2H + `es_sword_shield_breton` 1H+shield both spawning
-- their FP units, with two state_machines loaded simultaneously). See marker
-- constant `CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338` near the top of file.
--
-- Fix: only mutate careers that actually need cross-slot support — careers
-- that own at least one variant flagged `cross_slot = true`. Right now that's
-- the four Empire careers (`_es_all_careers`) because only `cwv_es_musket_old`
-- is cross-slot. Other 24 careers are left alone, restoring vanilla slot
-- behavior everywhere a cross-slot variant can't be equipped. The bug surface
-- remains on the 4 Empire careers (where the musket is the whole point of the
-- feature), but is removed from the other 24 careers where the broad mutation
-- was pure overshoot.
local function _cwv_collect_cross_slot_careers()
	local set = {}
	for _, def in ipairs(_variant_definitions) do
		if def.cross_slot == true and type(def.careers) == "table" then
			for _, career_name in ipairs(def.careers) do
				set[career_name] = true
			end
		end
	end
	return set
end
do _om._collect_cross_slot_careers = _cwv_collect_cross_slot_careers   -- #1148: the relocated check reads it through _om, not as a bare global
	local function _do_extend()
		if not CareerSettings then
			mod:warning("[cwv slot] CareerSettings nil — skip extension")
			return 0
		end
		local allowed_careers = _cwv_collect_cross_slot_careers()
		local allowed_count = 0
		for _ in pairs(allowed_careers) do allowed_count = allowed_count + 1 end
		if allowed_count == 0 then
			mod:info("[cwv slot] no cross_slot variants defined — skip slot_melee extension")
			return 0
		end
		local extended, skipped = 0, 0
		for career_name, career in pairs(CareerSettings) do
			if type(career) == "table" and career.item_slot_types_by_slot_name then
				local slot_map = career.item_slot_types_by_slot_name
				if slot_map.slot_melee then
					-- Cleanup cwv_dual leftovers from v0.1.311 — apply this
					-- unconditionally to every career so legacy state from
					-- prior versions is purged even on careers that we no
					-- longer extend.
					for i = #slot_map.slot_melee, 1, -1 do
						if slot_map.slot_melee[i] == "cwv_dual" then
							table.remove(slot_map.slot_melee, i)
						end
					end
					if slot_map.slot_ranged then
						for i = #slot_map.slot_ranged, 1, -1 do
							if slot_map.slot_ranged[i] == "cwv_dual" then
								table.remove(slot_map.slot_ranged, i)
							end
						end
					end
					-- v0.1.338: only extend careers that own a cross_slot
					-- variant. Other careers keep vanilla slot_melee.
					if allowed_careers[career_name] then
						local has_ranged = false
						for _, t in ipairs(slot_map.slot_melee) do
							if t == "ranged" then has_ranged = true; break end
						end
						if not has_ranged then
							slot_map.slot_melee[#slot_map.slot_melee + 1] = "ranged"
							extended = extended + 1
						end
					else
						-- Also REVERT any pre-v0.1.338 in-memory mutation on
						-- non-allowed careers, in case the broad extension
						-- already ran (e.g. CareerSettings was populated
						-- before this file reloaded). Drop only the trailing
						-- "ranged" we would have added — never touch a slot
						-- that legitimately listed "ranged" originally
						-- (vanilla doesn't, but be defensive).
						for i = #slot_map.slot_melee, 1, -1 do
							if slot_map.slot_melee[i] == "ranged" then
								table.remove(slot_map.slot_melee, i)
								skipped = skipped + 1
								break
							end
						end
					end
				end
			end
		end
		pcall(printf, "[cwv slot] extended slot_melee with 'ranged' on %d careers (scoped to cross_slot variants; %d non-allowed careers reverted)", extended, skipped)
		return extended
	end
	_om._slot_extension_log_only = true
	_do_extend()
	-- Re-run after all mods loaded in case CareerSettings was partial earlier.
	function mod.on_all_mods_loaded()
		_do_extend()
	end
end

-- v0.1.314: SINGLE consolidated post-filter hook on get_filtered_items.
-- The career mutation above adds "ranged" to slot_melee, which surfaces
-- ALL ranged weapons in the melee grid. This filter scopes that down so
-- only items whose key matches `_CWV_CROSS_SLOT_PREFIXES` (currently the
-- musket and jav+shield families) remain in a MELEE-ONLY result. Native
-- melee items are kept untouched. A combined `(melee or ranged)` category
-- is deliberately not narrowed: Career Tweaker uses that category when
-- Foot Knight's secondary slot accepts both weapon types (#935).
--
-- Replaces the prior dual-hook setup (inject + post-filter) that had
-- potential chain-ordering issues. One hook, one job: take the result
-- vanilla produces, drop the unwanted ranged items from melee grid.
--
-- #935: the primary and secondary loadout categories can both serialize to
-- the same `(melee or ranged)` filter. ItemGridUI therefore carries the
-- category's exact slot_name across the synchronous backend call; filter text
-- alone is not treated as surface identity.
mod:hook("ItemGridUI", "_on_category_index_change", function(func, self, index, ...)
	local settings = self._category_settings and self._category_settings[index]
	local slot_name = settings and (settings.slot_name or settings.name)
	self._cwv_filter_slot_name =
		(slot_name == "slot_melee" or slot_name == "slot_ranged") and slot_name or nil
	return func(self, index, ...)
end)

mod:hook("ItemGridUI", "_get_items_by_filter", function(func, self, item_filter)
	local previous = _om._cwv_filter_slot_name
	_om._cwv_filter_slot_name = self._cwv_filter_slot_name
	local ok, result = pcall(func, self, item_filter)
	_om._cwv_filter_slot_name = previous
	if not ok then
		error(result)
	end
	return result
end)

mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self, filter, params)
	local items = func(self, filter, params)
	if not items or type(filter) ~= "string" then return items end

	-- #424: a Tuskgor Javelin is a genuine modded thrown-resource feature, not
	-- merely an alternate icon. Keep it out of the ranged loadout picker until
	-- the peer-parity feature is positively enabled. Persisted/equipped items are
	-- not deleted; the action gate below covers that hot-join state.
	if string.find(filter, "slot_type == ranged", 1, true) then
		local gate = mod._cwv_peer_parity
		local state = "disabled"
		if gate and type(gate.applied_state) == "function" then
			local ok, applied = pcall(gate.applied_state, gate)
			if ok then state = applied end
		end
		local hidden
		items, hidden = _om.javelin_gate.filter_unavailable(items, state)
		if hidden > 0 then
			_dbg("[cwv:424] hid %d Tuskgor Javelin row(s): peer capability is %s",
				hidden, tostring(state))
		end
	end
	local slot_name = _om._cwv_filter_slot_name
	if not _om.cross_slot_filter.should_narrow(filter, slot_name) then
		if _om.cross_slot_filter.kind(filter) == "combined" then
			_dbg("[cwv:935] preserved combined equipment category slot=%s",
				tostring(slot_name))
		end
		return items
	end

	local filtered, kept, dropped, dropped_examples =
		_om.cross_slot_filter.apply(items, filter, slot_name, _is_cwv_musket_item)
	_dbg("[cwv melee-grid filter] kept=%d  dropped_ranged=%d  drop_samples=[%s]",
		kept, dropped, table.concat(dropped_examples, ", "))
	return filtered
end)

-- ============================================================
-- Defensive WeaponSpreadExtension.init hook
-- ============================================================
-- v0.1.265: vanilla `WeaponSpreadExtension.init` does
-- `ItemMasterList[item_name]` to fetch the weapon's template — for
-- our cwv polearm musket variant `item_name` is the inherited base
-- name "es_2h_heavy_spear" (per `feedback_cwv_clone_name_clobber.md`),
-- so the lookup returns the BASE spear IML whose template has no
-- `default_spread_template`. Vanilla then sets
-- `self.spread_settings = SpreadTemplates[nil] = nil`, which crashes
-- the next update frame's arithmetic on `state_settings.max_pitch`.
--
-- Our `BackendUtils.get_item_template` hook can't intercept because
-- the call comes from a name-keyed lookup with no cwv marker.
--
-- Defensive fix: hook init AFTER vanilla, check for nil
-- spread_settings, fall back to handgun spread defaults. This only
-- triggers when the original lookup returned a template without
-- spread settings — vanilla weapons that have proper spread settings
-- never hit the nil branch.

mod:hook_safe("WeaponSpreadExtension", "init", function(self, extension_init_context, unit, extension_init_data)
	if not self.spread_settings and SpreadTemplates and SpreadTemplates.handgun then
		self.spread_settings = SpreadTemplates.handgun
		mod:info("[cwv musket] patched WeaponSpreadExtension nil spread_settings → SpreadTemplates.handgun (item_name=%s)",
			tostring(extension_init_data and extension_init_data.item_name))
	end
end)

-- Belt-and-suspenders: also patch in update. v0.1.265's init-only hook
-- fired (per log) but the user still crashed, suggesting either a fresh
-- spread extension was created without our init hook firing, OR
-- spread_settings became nil at some point post-init. Wrapping update
-- with `mod:hook` (full wrapper) lets us patch BEFORE vanilla's update
-- logic runs each frame — guaranteed safety.
mod:hook("WeaponSpreadExtension", "update", function(func, self, unit, input, dt, context, t)
	if not self.spread_settings and SpreadTemplates and SpreadTemplates.handgun then
		self.spread_settings = SpreadTemplates.handgun
	end
	return func(self, unit, input, dt, context, t)
end)

-- ============================================================
-- Musket bayonet — child-link a scaled 1H sword to the rifle unit
-- ============================================================
-- The musket carries a fixed bayonet visual: a copy of Kruber's 1H
-- sword (`wpn_emp_sword_02_t1`), scaled thin/short, spawned as its
-- own unit and `World.link_unit`'d to the rifle unit so it inherits
-- the rifle's transform (any animation, swap, holster motion etc.
-- carries the bayonet along). Two units total — one linked to the 1P
-- rifle (player's first-person view) and one to the 3P rifle (other
-- players + previewer + Versus opponents). Both spawned in the
-- `GearUtils.spawn_inventory_unit` post-hook below.
--
-- Lifetime: each bayonet is tracked on the rifle's unit data via
-- `Unit.set_data(rifle, "cwv_musket_bayonet", bayonet_unit)`. When
-- vanilla destroys the rifle (weapon swap, pickup drop, level end),
-- the `GearUtils.destroy_wielded` hook below reads that data slot,
-- destroys the bayonet, and falls through to vanilla. Without this
-- the bayonet would orphan as a free-floating world unit.
--
-- Position/scale tuning: the rifle .unit's local +Y is barrel-forward
-- (verified by visual reference to Kruber's vanilla wield pose), so
-- the bayonet sits at +Y 0.55m relative to the rifle root and is
-- scaled to a thin spike. These two constants are the tuning knobs —
-- if the bayonet floats off the muzzle or reads too thick/long, edit
-- _MUSKET_BAYONET_LOCAL_TRANSLATION and _MUSKET_BAYONET_SCALE.
--
-- Cross-character package note: the rifle's package is auto-loaded
-- by inventory (right_hand_unit), but the sword unit isn't part of
-- that chain. Force-load the sword via `Managers.package:load`
-- (Tuskgor Javelin pup pattern, per `feedback_cwv_cross_character_unit_packages.md`).

-- v0.1.212: switched to wpn_emp_sword_03_t1 — the "Soldier's Longsword"
-- cosmetic skin for `es_1h_sword` (verified via cosmetics_tweaker/
-- VETERAN_SKIN_CATALOG.md:900). v0.1.211's wpn_emp_sword_04_t1 turned
-- out to be the falchion mesh (matching_item_key = "wh_1h_falchion"
-- in item_master_list_weapon_skins.lua:5185), not a real es_1h_sword
-- variant — explains "that's the falchion model". The new path is a
-- proper Kruber 1H sword distinct from the default skin_01 mesh.
local _MUSKET_BAYONET_UNIT_1P    = "units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1"
local _MUSKET_BAYONET_UNIT_3P    = "units/weapons/player/wpn_emp_sword_03_t1/wpn_emp_sword_03_t1_3p"
-- {x, y, z} relative to rifle root. v0.1.206: re-deduced axis convention
-- from the user's prior "elongate the rifle on the Y axis" hint — rifle's
-- local +Y IS the barrel direction (which is why scaling Y stretches the
-- rifle along its length). v0.1.204's {0, 0, 0.55} placed the bayonet
-- 0.55m along rifle's local +Z, which must be the perpendicular "up"
-- axis — explains "floating above". v0.1.205 went MORE along Z (worse).
-- v0.1.206 puts the bayonet along +Y (toward muzzle) with zero Z offset:
--   * X 0    (centered on the barrel)
--   * Y 1.0  (push 1.0m toward the muzzle along the barrel)
--   * Z 0    (no vertical offset; bayonet sits AT barrel level)
-- TUNABLE — if the bayonet is still misplaced, edit these and rebuild.
-- Orientation rotation below is per v0.1.204 user confirmation; don't
-- touch the rotation constants.
local _MUSKET_BAYONET_LOCAL_TRANSLATION = { 0, 0.8, 0.025 }
-- Rotation: the sword model's blade extends along +Y (1H sword convention).
-- Rotate -90° about X to align the blade with the rifle's barrel direction.
-- v0.1.204 user confirmed this orientation is correct. Don't change unless
-- the rifle .unit's local axis convention is empirically different.
local _MUSKET_BAYONET_LOCAL_ROTATION_AXIS  = { 1, 0, 0 }
local _MUSKET_BAYONET_LOCAL_ROTATION_ANGLE = -math.pi / 2
-- Scale: applied in the bayonet's MODEL space (before rotation). Y is the
-- blade-length axis; X/Z thin the blade cross-section.
local _MUSKET_BAYONET_SCALE = { 0.35, 0.6, 0.2 }

local _MUSKET_BAYONET_DATA_KEY = "cwv_musket_bayonet"

-- Weak-keyed table mapping rifle units to their bayonet child units. Used
-- by the visibility-sync hook below (vanilla wield doesn't propagate
-- visibility to linked child units, so when a player holsters the rifle
-- the bayonet stays visible floating in space). Weak rifle keys = entries
-- auto-cleared when the rifle is GC'd.
local _musket_bayonet_pairs = setmetatable({}, { __mode = "k" })

local function _force_load_musket_bayonet_units()
	if not (Managers and Managers.package) then return end
	local function _load(unit_path, ref)
		local ok, err = pcall(function()
			Managers.package:load(unit_path, ref, nil, true, true)
		end)
		if ok then
			mod:info("[cwv musket-bayonet] force-loaded %s (ref=%s)", unit_path, ref)
		else
			mod:warning("[cwv musket-bayonet] failed to force-load %s: %s", unit_path, tostring(err))
		end
	end
	_load(_MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")
	_load(_MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")
end

_force_load_musket_bayonet_units()

-- ============================================================
-- Musket melee template — force-load polearm state machine
-- ============================================================
-- v0.1.227: reverted from Kerillian's elf spear back to Kruber's NATIVE
-- tuskgor spear (`two_handed_heavy_spears_template`) per user direction.
-- The elf spear's animations didn't read well on the rifle, and the
-- display_unit caused load issues. Tuskgor is Kruber-native; only the
-- polearm state machine needs force-loading (vanilla loads it for
-- Kruber only when his loadout includes es_2h_heavy_spear).

local _MUSKET_MELEE_STATE_MACHINE = "units/beings/player/first_person_base/state_machines/melee/polearm"

local function _force_load_musket_melee_assets()
	if not (Managers and Managers.package) then return end
	local ok, err = pcall(function()
		Managers.package:load(_MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm", nil, true, true)
	end)
	if ok then
		mod:info("[cwv musket-melee] force-loaded %s (ref=%s)", _MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm")
	else
		mod:warning("[cwv musket-melee] failed to force-load %s: %s", _MUSKET_MELEE_STATE_MACHINE, tostring(err))
	end
end

_force_load_musket_melee_assets()

-- ============================================================
-- Generated dual-weapon first-person residency (Issue #586)
-- ============================================================
-- Vanilla ProfileSynchronizer derives its first-person package list from the
-- backend loadout it sees while build_inventory_lists() runs. A CWV resync can
-- replace that loadout immediately afterwards. #586 first reproduced this with
-- Dual Axes. Crash c41fc284-f1cf-42b7-b519-bddc52aed4cf then proved the class
-- is not axe-specific: Rain's synchronized Dual Maces reached
-- PlayerUnitFirstPerson:set_state_machine(".../melee/dual_hammers") with the
-- prior loadout's package set and faulted in ResourceManager before Lua could
-- recover.
--
-- Hold the complete, source-verified set used by CWV's generated dual-weapon
-- owners for CWV's lifetime. Every path is present in vanilla's
-- inventory_package_list.lua:267-274 and comes directly from the corresponding
-- weapon template (dual_wield_swords.lua:1515, dual_wield_axes.lua:1929,
-- dual_wield_hammers.lua:1739, dual_wield_hammer_sword.lua:1591,
-- dual_wield_hammers_priest.lua:1745). This closes the stale-resync window by
-- construction when another paired variant is added to the catalog below.
-- Loads are synchronous because residency is a precondition of the next wield.
_om.DUAL_WEAPON_FP_RESIDENCY = {
	{
		path = "units/beings/player/first_person_base/state_machines/melee/dual_swords",
		ref = "cwv_dual_fp_sm_dual_swords",
		items = { cwv_es_dual_swords = true },
	},
	{
		path = "units/beings/player/first_person_base/state_machines/melee/dual_hammer_sword_es",
		ref = "cwv_dual_fp_sm_sword_mace",
		items = { cwv_es_sword_and_mace = true },
	},
	{
		path = "units/beings/player/first_person_base/state_machines/melee/dual_axes",
		ref = "cwv_dual_axes_fp_state_machine",
		items = { cwv_es_dual_axes = true, cwv_wh_dual_axes = true },
	},
	{
		path = "units/beings/player/first_person_base/state_machines/melee/dual_hammers",
		ref = "cwv_dual_fp_sm_dual_hammers",
		items = { cwv_es_dual_maces = true, cwv_wh_dual_maces = true },
	},
	{
		path = "units/beings/player/first_person_base/state_machines/melee/dual_hammers_priest",
		ref = "cwv_dual_fp_sm_priest_hammers",
		items = { cwv_es_dual_warpriest_hammers = true },
	},
}

-- Backward-compatible #586 inspection fields; the lifecycle below owns the
-- full catalog now, while these continue to identify the original Axes lease.
_om.DUAL_AXES_FP_STATE_MACHINE = _om.DUAL_WEAPON_FP_RESIDENCY[3].path
_om.DUAL_AXES_FP_RESIDENCY_REF = _om.DUAL_WEAPON_FP_RESIDENCY[3].ref
_om._dual_weapon_fp_residency_held = {}
_om._dual_weapon_fp_residency_complete = false
_om._dual_axes_fp_residency_held = false

_om._acquire_dual_weapon_fp_residency = function(reason)
	local package_manager = Managers and Managers.package
	if not package_manager then
		pcall(printf, "[cwv:586] package manager unavailable; dual-weapon FP residency not acquired (%s)", tostring(reason))
		return false
	end

	local complete = true
	for _, lease in ipairs(_om.DUAL_WEAPON_FP_RESIDENCY) do
		local path = lease.path
		local ref = lease.ref
		local held = package_manager:has_loaded(path, ref) and true or false
		if not held then
			-- Do not pcall this: invalid package failures occur later in engine C
			-- and cannot be caught. The closed source-derived catalog is the guard.
			package_manager:load(path, ref, nil, false, true)
			held = package_manager:has_loaded(path, ref) and true or false
			if held then
				pcall(printf, "[cwv:586] acquired dual FP residency path=%s reason=%s ref=%s",
					path, tostring(reason), ref)
			else
				pcall(printf, "[cwv:586] dual FP package did not become resident after synchronous load: %s", path)
			end
		end
		_om._dual_weapon_fp_residency_held[path] = held
		if not held then complete = false end
	end
	_om._dual_weapon_fp_residency_complete = complete
	_om._dual_axes_fp_residency_held = _om._dual_weapon_fp_residency_held[_om.DUAL_AXES_FP_STATE_MACHINE] == true
	return complete
end

_om._release_dual_weapon_fp_residency = function(reason)
	local package_manager = Managers and Managers.package
	for _, lease in ipairs(_om.DUAL_WEAPON_FP_RESIDENCY) do
		if package_manager and (package_manager:reference_count(lease.path, lease.ref) or 0) > 0 then
			package_manager:unload(lease.path, lease.ref)
			pcall(printf, "[cwv:586] released dual FP residency path=%s reason=%s ref=%s",
				lease.path, tostring(reason), lease.ref)
		end
		_om._dual_weapon_fp_residency_held[lease.path] = false
	end
	_om._dual_weapon_fp_residency_complete = false
	_om._dual_axes_fp_residency_held = false
end

-- Preserve the original #586 callable surface for diagnostics while making
-- every lifecycle acquisition/release systemic.
_om._acquire_dual_axes_fp_residency = _om._acquire_dual_weapon_fp_residency
_om._release_dual_axes_fp_residency = _om._release_dual_weapon_fp_residency

_om._acquire_dual_weapon_fp_residency("mod_load")

-- ============================================================
-- Cross-character husk residency owner (#1159)
-- ============================================================
-- The `dr_shield_axe` base-unit force-load (#280), the data-driven
-- override-unit residency pass with its attempt-capped all-mods-loaded retry
-- (issues 396/401), and the `start_weapon_fx` nil-slot crash floor that backs
-- them up (#280) all live in the husk-residency owner module dofiled below.
-- It loads HERE, at the exact point the inline blocks ran, so the boot-time
-- load order, the `mod.on_all_mods_loaded` chain position and the hook order
-- are unchanged. The husk wield diagnostic below stays in the entry: it
-- dispatches the exact-identity, combat-style, Crowbill and fade channels,
-- not residency.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_husk_residency_owner")(mod, { om = _om, variant_definitions = _variant_definitions })

-- ============================================================
-- Husk wield diagnostic  (issues 395, 398 — DIAGNOSTICS ONLY)
-- ============================================================
-- Neither issue has a confirmed code fix yet; this arms the disambiguating
-- evidence the next paired CLIENT log needs, without changing behavior.
--   * Issue 398 (weapon sounds not applied on husk): logs `template` — the
--     husk resolves item_template via the BASE item_data (name = base
--     weapon), so for a CWV variant this is expected to be the BASE template,
--     NOT the CWV template. Template-level sound swaps live on the CWV
--     template, so they never reach the husk. A log showing template=<base
--     template> confirms that mechanism (ties to the #392 base-resolution
--     umbrella, out of scope here).
--   * Issue 395 (rapier not unequipped on husk after swap): logs the wielded
--     3P weapon units still live on `equipment` AFTER the swap completed, so a
--     rapier unit that survived `GearUtils.destroy_equipment` (or a swap whose
--     item-id resync never reached the husk) is visible in the trace.
-- #620 upgraded the single post-observation hook to one full wrapper so a
-- strictly synchronous remote owner+slot style context exists while vanilla
-- resolves BackendUtils.get_item_template. The context is always cleared even
-- if vanilla errors; every prior post-wield observer remains consolidated here.
-- Pre-flight (CLAUDE.md #8): CWV's only other
-- SimpleHuskInventoryExtension hook is on `start_weapon_fx` (above) — this is
-- the sole hook on (SimpleHuskInventoryExtension, _wield_slot) in CWV.
mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
	-- #660: BackendUtils.get_item_units runs synchronously inside vanilla wield,
	-- before the per-hand spawn hooks know which peer/slot they belong to. Keep a
	-- strictly scoped context so the upstream hand-selection adapter can consume
	-- the same exact remote descriptor as the later mesh/transform adapters.
	_om._appearance_husk_wield_context = {
		owner_unit_3p = self and self._unit,
		slot_name = slot_name,
	}
	if _om.combat_styles and _om.combat_styles.begin_husk_wield then
		_om.combat_styles:begin_husk_wield(self, slot_name)
	end
	local ok, err = pcall(func, self, world, equipment, slot_name, unit_1p, unit_3p)
	_om._appearance_husk_wield_context = nil
	if _om.combat_styles and _om.combat_styles.end_husk_wield then
		_om.combat_styles:end_husk_wield()
	end
	if not ok then error(err) end
	-- #760: a remote husk receives the vanilla Trollhammer item shape for wire
	-- safety, so its local item-template lookup cannot see the Outrider's
	-- Saltzpyre career map. The semantic identity channel is the positive
	-- variant proof. Re-apply the same vanilla Repeater Pistol stance once at
	-- the existing husk-wield reconstruction edge; no custom animation id or
	-- extra RPC is sent. A late identity delivery already re-wields this slot.
	local slot = equipment and equipment.slots and equipment.slots[slot_name]
	local item_data = slot and slot.item_data
	local descriptor = _om._husk_identity_descriptor
		and _om._husk_identity_descriptor(self and self._unit, slot_name,
			item_data and item_data.name)
	local husk_wield, husk_reason = _om.outrider_animation.husk_event(
		descriptor, self and self._career_name,
		NetworkLookup and NetworkLookup.anims)
	if husk_wield then
		local _, result = _om.outrider_animation.dispatch_event(
			unit_3p, husk_wield, Unit)
		_om.outrider_animation.emit_evidence(printf, "remote_husk_3p",
			self and self._career_name, husk_wield, result, "exact_identity")
	elseif husk_reason then
		_om.outrider_animation.emit_evidence(printf, "remote_husk_3p",
			self and self._career_name,
			_om.outrider_animation.SALTZPYRE_WIELD_3P,
			"skip_" .. tostring(husk_reason), "exact_identity")
	end
	pcall(function()
		local item_template = slot and slot.item_template
		local function _live(u) return (u and Unit.alive(u)) and tostring(u) or "nil" end
		printf("[cwv husk-wield] slot=%s item_name=%s backend_id=%s skin=%s template=%s | wielded r3p=%s l3p=%s (issues 395/398 diag)",
			tostring(slot_name),
			tostring(item_data and item_data.name),
			tostring(item_data and item_data.backend_id),
			tostring(slot and slot.skin),
			tostring(item_template and item_template.name),
			_live(equipment and equipment.right_hand_wielded_unit_3p),
			_live(equipment and equipment.left_hand_wielded_unit_3p))
	end)
	if _om._exact_pair_on_husk_wield then
		_om._exact_pair_on_husk_wield(self, slot_name)
	end
	if _om.crowbill_runtime and _om.crowbill_runtime.on_husk_wield then
		_om.crowbill_runtime.on_husk_wield(self, slot_name)
	end
	if _om.combat_styles and _om.combat_styles.on_husk_wield then
		_om.combat_styles:on_husk_wield(self, slot_name)
	end; if descriptor then _om.appearance_fade.husk_wield(self, equipment) end -- #922 complete post-adapter snapshot
end)
-- #922 post-_reapply_fade forced re-enroll lives in _cwv_appearance_fade.lua.
_cwv_husk_wield_diag_installed = true

local function _spawn_and_link_musket_bayonet(world, rifle_unit, bayonet_unit_path, package_ref)
	if not world or not rifle_unit or not Unit.alive(rifle_unit) then return nil end
	if not (Managers and Managers.package and Managers.package:has_loaded(bayonet_unit_path, package_ref)) then
		-- Package not ready yet — bail silently; bayonet will be missing on
		-- this equip. Player can re-equip after the load completes (rare race
		-- only at first equip immediately after mod load).
		return nil
	end
	local pos = Unit.world_position(rifle_unit, 0)
	local rot = Unit.world_rotation(rifle_unit, 0)
	local ok_spawn, bayonet = pcall(World.spawn_unit, world, bayonet_unit_path, pos, rot)
	if not ok_spawn or not bayonet then
		mod:warning("[cwv musket-bayonet] spawn failed: %s", tostring(bayonet))
		return nil
	end

	-- Link to root node. The child inherits the parent's full transform
	-- (translation + rotation + scale). Subsequent local_position/scale
	-- ops override the inherited translation/scale at composition time.
	pcall(World.link_unit, world, bayonet, 0, rifle_unit, 0)

	local t = _MUSKET_BAYONET_LOCAL_TRANSLATION
	pcall(Unit.set_local_position, bayonet, 0, Vector3(t[1], t[2], t[3]))
	local r_axis = _MUSKET_BAYONET_LOCAL_ROTATION_AXIS
	local r_ang  = _MUSKET_BAYONET_LOCAL_ROTATION_ANGLE
	pcall(Unit.set_local_rotation, bayonet, 0, Quaternion.axis_angle(Vector3(r_axis[1], r_axis[2], r_axis[3]), r_ang))
	local s = _MUSKET_BAYONET_SCALE
	pcall(Unit.set_local_scale, bayonet, 0, Vector3(s[1], s[2], s[3]))

	return bayonet
end

local function _attach_musket_bayonets(world, rifle_3p, rifle_1p)
	-- Idempotent: skip per-rifle if a bayonet is already tracked for it.
	-- Without this, a code path that re-fires our spawn hook on the same
	-- rifle (e.g. cosmetic application that refreshes equipment without
	-- going through destroy_wielded) would attach a SECOND bayonet,
	-- leaving the first as an orphan tracked-but-not-cleaned-up unit.
	local skipped_3p, skipped_1p = false, false
	if rifle_3p and Unit.alive(rifle_3p) and not _musket_bayonet_pairs[rifle_3p] then
		local bayonet_3p = _spawn_and_link_musket_bayonet(world, rifle_3p, _MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")
		if bayonet_3p then
			pcall(Unit.set_data, rifle_3p, _MUSKET_BAYONET_DATA_KEY, bayonet_3p)
			_musket_bayonet_pairs[rifle_3p] = bayonet_3p
		end
	elseif rifle_3p then
		skipped_3p = true
	end
	if rifle_1p and Unit.alive(rifle_1p) and not _musket_bayonet_pairs[rifle_1p] then
		local bayonet_1p = _spawn_and_link_musket_bayonet(world, rifle_1p, _MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")
		if bayonet_1p then
			pcall(Unit.set_data, rifle_1p, _MUSKET_BAYONET_DATA_KEY, bayonet_1p)
			_musket_bayonet_pairs[rifle_1p] = bayonet_1p
		end
	elseif rifle_1p then
		skipped_1p = true
	end
	-- Diagnostic log: counts pairs after each attach so duplicate-attach
	-- bugs are visible in mod log. v0.1.239 added to debug user-reported
	-- "floating bayonet on both melee and ranged".
	local pair_count = 0
	for _ in pairs(_musket_bayonet_pairs) do pair_count = pair_count + 1 end
	_dbg("[cwv musket-bayonet] attach: 3p=%s 1p=%s (skipped: 3p=%s 1p=%s) total_pairs=%d",
		tostring(rifle_3p ~= nil), tostring(rifle_1p ~= nil),
		tostring(skipped_3p), tostring(skipped_1p), pair_count)
end

local function _detach_musket_bayonet(world, rifle_unit)
	if not world or not rifle_unit then return end
	local has_data = false
	local ok_check = pcall(function() has_data = Unit.has_data(rifle_unit, _MUSKET_BAYONET_DATA_KEY) end)
	if not ok_check or not has_data then return end
	local bayonet
	pcall(function() bayonet = Unit.get_data(rifle_unit, _MUSKET_BAYONET_DATA_KEY) end)
	if not bayonet then return end
	-- Hide the bayonet IMMEDIATELY before queuing for deletion. mark_for_deletion
	-- runs at the end of the next frame; without the visibility flag, the
	-- bayonet stays rendered for that frame at its last world position
	-- (frozen where the rifle was when destroyed). User reported this as
	-- a "floating bayonet" after stance toggle — the old bayonet flickered
	-- visible while the new rifle's bayonet was already attached.
	pcall(Unit.set_unit_visibility, bayonet, false)
	if Managers and Managers.state and Managers.state.unit_spawner then
		pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
	else
		pcall(World.destroy_unit, world, bayonet)
	end
end

mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
	-- Husk MESH re-key (issues 396/401, #474/#475) -- WEAPON_APPEARANCE_STANDARD
	-- section 3. MUST run BEFORE the vanilla spawn: the husk resolves the BASE
	-- item_data (name = base weapon), so vanilla spawn_inventory_unit would select
	-- the BASE mesh even for a cross-character variant (#392). Resolution is
	-- SKIN-PRIMARY (#474: a wire skin in a cwv namespace positively identifies the
	-- variant regardless of can_wield); a present non-cwv skin NEVER re-keys
	-- (#475 Invariant 1); only a skinless echo falls back to the base+career
	-- signal with can_wield evaluated lazily at wield time. Residency-guarded
	-- (vanilla overrides via the resident-3p helper, mod-bundled custom meshes
	-- via the custom-bundle predicate). No-op when nothing resolves.
	-- COMPLETE husk adapter, PRE-SPAWN half (issues 394/398/399/401/474/476/482/
	-- 719 -- BUG_CLASSES class 27; body in the husk-path module, entry is
	-- size-ratcheted). One call resolves the FULL variant definition: mesh re-key
	-- with fail-closed residency (KEEP base identity when an override/donor
	-- material is not resident -- the #474 MeshObject AV killer), pre-spawn
	-- ammo-nil (#399), and clone-template identity for the spawn (#398).
	-- `suppress` is the #478 residency-gated defer: vanilla only reached this
	-- hand because item_units[hand.."_hand_unit"] is truthy
	-- (simple_husk_inventory_extension.lua:665/669), so returning all-nil is
	-- exactly a hand vanilla never spawned. The template override feeds ONLY the
	-- vanilla call below; owner-path gates further down keep reading the
	-- caller's item_template.
	local husk_spawn_template
	if not owner_unit_1p and _om._husk_adapter_pre then
		local suppress, husk_tpl = _om._husk_adapter_pre(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)
		if suppress then
			if _om._probe_279_spawn then
				_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, nil, "deferred_478")
			end
			return nil, nil, nil, nil
		end
		husk_spawn_template = husk_tpl
	end
	local v_w3p, v_a3p, v_w1p, v_a1p =
		func(world, hand, husk_spawn_template or item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

	-- issue 279 (2nd repro): capture the full ammo-attach decision at EVERY
	-- spawn (owner + husk, both hands) for a no_ammo_unit variant's base. Self-gates
	-- on base being a no_ammo base; pure diagnostic (see the helper for the trace).
	if _om._probe_279_spawn then
		_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, v_a3p, nil)
	end

	-- ============================================================
	-- Husk (remote-player) CWV apply -- COMPLETE adapter, POST-SPAWN half
	-- ============================================================
	-- This hook is the ONLY GearUtils path that fires for husks:
	-- SimpleHuskInventoryExtension._wield_slot -> spawn_inventory_unit
	-- (simple_husk_inventory_extension.lua:666/670). The owner/bot path runs
	-- GearUtils.create_equipment (1P rig present); husks have no 1P rig, so
	-- `owner_unit_1p == nil` is the husk/bot discriminator, and everything here
	-- is IDEMPOTENT with the create_equipment apply so a bot spawn reaching both
	-- paths is harmless. Post half = #399 ammo-strip net (returns true -> nil
	-- the captured ammo return), transform/texture/presentation apply
	-- (397/394/604), and the #579 per-hand compare probe. Helpers live on `_om`
	-- (populated at load time; entry locals are not visible from the module).
	if not owner_unit_1p and _om._husk_adapter_post then
		if _om._husk_adapter_post(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p, v_a3p) then
			v_a3p = nil
		end
	end

	-- Gate: only attach for the musket variant on its right-hand spawn.
	-- IMPORTANT: cwv variants inherit `entry.name` from the base weapon
	-- (per `feedback_cwv_clone_name_clobber.md` — clobbering crashes equip),
	-- so `item_data.name` for cwv_es_musket is "es_handgun", not the cwv key.
	-- Compare the template-table reference instead. v0.1.205: the musket
	-- has TWO templates (ranged + melee for stance toggle); fire for both.
	if hand ~= "right" then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	if not item_template or not Weapons then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	local _bid_for_tex = item_data and (item_data.backend_id or item_data.ItemInstanceId)
	local _spawn_cwv_key = item_data and _om._cwv_key_for_item
		and _om._cwv_key_for_item(_bid_for_tex, item_data)
	local _spawn_is_old_musket = _spawn_cwv_key == "cwv_es_musket_old"
		or item_template == Weapons.old_musket_template
		or item_template == Weapons.old_musket_template_melee
	-- v0.1.300-301: gate accepts both musket families (cwv_es_musket and
	-- cwv_es_musket_old), ranged and melee templates. The bayonet attach
	-- is suppressed below for old musket (its mesh has bayonet baked in);
	-- texture/transform/FX-proxy fire for either family.
	if item_template ~= Weapons.musket_template and item_template ~= Weapons.musket_template_melee
	   and item_template ~= Weapons.old_musket_template and item_template ~= Weapons.old_musket_template_melee then
		if owner_unit_1p and _om._cwv_musket_unregister_slot then
			_om._cwv_musket_unregister_slot(owner_unit_3p, slot_name)
		end
		return v_w3p, v_a3p, v_w1p, v_a1p
	end
	if owner_unit_1p and not _spawn_is_old_musket and _om._cwv_musket_unregister_slot then
		_om._cwv_musket_unregister_slot(owner_unit_3p, slot_name)
	end

	-- Old Musket exact identity enters the Phase-3 appearance reconciler for
	-- both render perspectives, then keeps the established hidden vanilla rifle
	-- proxy solely for FX emission. All work is gated on the canonical backend id.
	if _spawn_is_old_musket then
		-- v0.1.295: distinguish ranged vs melee mode for 1P transform tuning.
		-- The user wants different pos/rot/scale per stance.
		local _mode = (item_template == Weapons.musket_template_melee
		               or item_template == Weapons.old_musket_template_melee) and "melee" or "ranged"
		_om.old_musket_appearance.reconcile(v_w1p, "owner_1p", "equip",
			item_data, _mode, { unit_name = _om.old_musket_preview.UNIT })
		_om.old_musket_appearance.reconcile(v_w3p, "owner_3p", "equip",
			item_data, _mode, { unit_name = _om.old_musket_preview.UNIT_3P })
		_om._spawn_old_musket_fx_proxy(world, v_w1p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",     owner_unit_1p, "j_rightweaponattach")
		_om._spawn_old_musket_fx_proxy(world, v_w3p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p", owner_unit_3p, "j_rightweaponattach")

		-- v0.1.306: register the spawned ammo extension into the shared
		-- reserve pool so cross-slot equipped cwv muskets share reserve
		-- ammo (chambered ammo stays per-item). 1P unit only — 3P doesn't
		-- have ammo_system in vanilla rifle template.
		if _om._cwv_musket_register_ammo_ext and v_w1p and Unit.alive(v_w1p)
				and ScriptUnit.has_extension(v_w1p, "ammo_system") then
			_om._cwv_musket_register_ammo_ext(
				ScriptUnit.extension(v_w1p, "ammo_system"), owner_unit_3p, slot_name)
		end
	end

	-- v0.1.248: aggressive orphan prune BEFORE attaching new bayonet.
	-- Catches stale entries from any code path that bypassed our
	-- destroy_wielded cleanup hook (e.g. world transition / hot-load /
	-- any equipment re-creation that doesn't go through destroy_slot).
	-- Without this, an orphan from a previous spawn floats while a
	-- fresh bayonet attaches to the new rifle — user sees a SECOND
	-- floating bayonet on every equip.
	local orphans_pruned = 0
	for rifle, bayonet in pairs(_musket_bayonet_pairs) do
		if not Unit.alive(rifle) then
			if Unit.alive(bayonet) then
				pcall(Unit.set_unit_visibility, bayonet, false)
				if Managers and Managers.state and Managers.state.unit_spawner then
					pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
				end
			end
			_musket_bayonet_pairs[rifle] = nil
			orphans_pruned = orphans_pruned + 1
		end
	end
	if orphans_pruned > 0 then
		_dbg("[cwv musket-bayonet] pruned %d orphan(s) before new attach", orphans_pruned)
	end

	-- v0.1.278: skip bayonet attach for cwv_es_musket_old — the custom mesh
	-- already has a fixed bayonet baked into the model.
	local _is_old_musket = _spawn_is_old_musket

	if not _is_old_musket then
		-- pcall outer: bayonet failure should never break the equip itself.
		pcall(_attach_musket_bayonets, world, v_w3p, v_w1p)
	end
	-- v0.1.286: cwv_es_musket_old overlay system DELETED. The variant now uses
	-- our custom mesh path as right_hand_unit and the vanilla GearUtils pipeline
	-- spawns it directly. See PackageManager hooks at top of file for the
	-- "Resource not found" workaround, and the .unit files for the
	-- `data.mat_to_use` vanilla-material reference that gives FP rendering.

	-- v0.1.220: in melee mode (musket_template_melee), the polearm
	-- attachment_node_linking holds the rifle perpendicular to its
	-- intended orientation. Apply rotations to correct it. v0.1.226
	-- composes Y barrel-spin + Z. v0.1.227: melee template is back to
	-- Kruber's tuskgor spear (also AttachmentNodeLinking.polearm) so
	-- same correction applies.
	if item_template == Weapons.musket_template_melee then
		-- v0.1.241: per user "rotate along z-axis about 90 degrees more",
		-- bump outermost q_z2 from π to 3π/2 (adds another 90° at the
		-- outermost composition position).
		-- Total composition: `q_z2(3π/2) * q_y(-π/2) * q_z(π/2) * q_x(π)`.
		local q_y  = Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2)
		local q_z  = Quaternion.axis_angle(Vector3(0, 0, 1), math.pi / 2)
		local q_x  = Quaternion.axis_angle(Vector3(1, 0, 0), math.pi)
		local q_z2 = Quaternion.axis_angle(Vector3(0, 0, 1), math.pi * 1.5)
		local q    = Quaternion.multiply(q_z2, Quaternion.multiply(Quaternion.multiply(q_y, q_z), q_x))
		if v_w3p and Unit.alive(v_w3p) then
			pcall(Unit.set_local_rotation, v_w3p, 0, q)
		end
		if v_w1p and Unit.alive(v_w1p) then
			pcall(Unit.set_local_rotation, v_w1p, 0, q)
		end

		-- v0.1.227: per user, scale the rifle DOWN in 1st person ONLY
		-- when in melee mode (3P stays at the type-level scale so other
		-- players see the normal-sized musket-bayonet). Multiply the
		-- existing local scale by the factor below — the type-level
		-- {0.9, 1.35, 0.9} is already applied by the
		-- GearUtils.create_equipment hook by the time we get here.
		-- Reading current scale and multiplying composes correctly
		-- regardless of pre-existing scale.
		-- v0.1.247: per-axis scale factors per user "0.8x and 0.8y"
		-- (Z unchanged). v0.1.265: Y bumped 0.8 → 1.2 per user "make
		-- 1P melee 1.8y" — composes against type-level 1P Y of 1.5 to
		-- give 1.5 * 1.2 = 1.8 for 1P melee. 3P unchanged at 1.35.
		local _MELEE_1P_SCALE_FACTOR = { 0.8, 1.2, 1.0 }  -- TUNABLE per-axis
		if v_w1p and Unit.alive(v_w1p) then
			pcall(function()
				local current = Unit.local_scale(v_w1p, 0)
				local cx, cy, cz = Vector3.to_elements(current)
				local f = _MELEE_1P_SCALE_FACTOR
				Unit.set_local_scale(v_w1p, 0, Vector3(cx * f[1], cy * f[2], cz * f[3]))
			end)
		end

		-- v0.1.229: melee grip height/forward offset. After the rotation
		-- correction the rifle sits too low and slightly back from where
		-- a polearm grip should hold it. Apply a translation delta on
		-- top of vanilla's attachment_node_linking offset (read current
		-- local position, ADD our delta, set back). Compose-friendly so
		-- it doesn't fight the polearm attachment offset.
		--   Y +0.1 — push slightly forward along the rifle's barrel axis
		--   Z -0.3 — drop the grip height
		-- Applied to BOTH 1P and 3P so the held view and other players
		-- see the same pose. TUNABLE constants.
		local _MELEE_LOCAL_OFFSET = { 0, 0.06, -0.3 }
		local function _apply_melee_offset(unit)
			if not unit or not Unit.alive(unit) then return end
			pcall(function()
				local current = Unit.local_position(unit, 0)
				local cx, cy, cz = Vector3.to_elements(current)
				Unit.set_local_position(unit, 0, Vector3(
					cx + _MELEE_LOCAL_OFFSET[1],
					cy + _MELEE_LOCAL_OFFSET[2],
					cz + _MELEE_LOCAL_OFFSET[3]))
			end)
		end
		_apply_melee_offset(v_w3p)
		_apply_melee_offset(v_w1p)
	end

	return v_w3p, v_a3p, v_w1p, v_a1p
end)

-- ============================================================
-- Musket bayonet visibility sync
-- ============================================================
-- VT2's wield system DOESN'T destroy the rifle's units when the player
-- swaps to a different weapon — it just hides them via
-- Unit.set_unit_visibility(rifle, false). The bayonet is a separate
-- World.link_unit'd unit that doesn't inherit the rifle's visibility
-- flag (Stingray links transforms, not visibility), so it stays visible
-- floating in space when the rifle is hidden.
--
-- Fix: track all spawned bayonet pairs in a weak-keyed table. Hook the
-- inventory paths that change wielded state (`_wield_slot` runs whenever
-- the player switches weapons). After each, walk the table and set each
-- bayonet's visibility based on whether its rifle is the currently-
-- wielded weapon. When player wields the rifle: bayonet shows. When they
-- swap to a different slot: bayonet hides.

-- (_musket_bayonet_pairs declared above near the bayonet constants so
-- _attach_musket_bayonets can register entries directly.)

-- Sync visibility of all tracked bayonets based on current wielded state.
-- Also opportunistically destroys ORPHAN bayonets (rifle is dead but
-- bayonet still alive — happens when a code path bypasses our
-- destroy_wielded cleanup hook, e.g. cosmetic application or any
-- equipment refresh that swaps the rifle without firing destroy_wielded).
local function _sync_all_bayonets_visibility(equipment)
	if not equipment then return end
	local wielded_3p = equipment.right_hand_wielded_unit_3p
	local wielded_1p = equipment.right_hand_wielded_unit
	local orphans, shown, hidden = 0, 0, 0
	for rifle, bayonet in pairs(_musket_bayonet_pairs) do
		if not Unit.alive(rifle) then
			-- Orphan: rifle gone but bayonet lingers. Hide and destroy.
			if Unit.alive(bayonet) then
				pcall(Unit.set_unit_visibility, bayonet, false)
				if Managers and Managers.state and Managers.state.unit_spawner then
					pcall(function() Managers.state.unit_spawner:mark_for_deletion(bayonet) end)
				end
			end
			_musket_bayonet_pairs[rifle] = nil
			orphans = orphans + 1
		elseif Unit.alive(bayonet) then
			local should_show = (rifle == wielded_3p) or (rifle == wielded_1p)
			pcall(Unit.set_unit_visibility, bayonet, should_show)
			if should_show then shown = shown + 1 else hidden = hidden + 1 end
		end
	end
	if orphans + shown + hidden > 0 then
		_dbg("[cwv musket-bayonet] sync: orphans=%d shown=%d hidden=%d", orphans, shown, hidden)
	end
end

-- Hook the wield path. Full wrapper because we need PRE and POST work:
--   PRE  — detect if the outgoing wielded weapon is one of our cwv muskets
--          AND mid-reload. If so, flag item_data so we can cancel the
--          auto-reload-on-wield that vanilla triggers when wielding back.
--   POST — sync bayonet visibility against the new wielded state (existing
--          v0.1.281 behavior), AND if the newly-wielded weapon is a flagged
--          cwv musket that just got auto-reload-on-wield kicked off, abort it.
-- v0.1.305: anti-exploit. User report: empty rifle reload start → swap to
-- melee → swap back → fully reloaded immediately. Root cause: vanilla
-- `SimpleInventoryExtension._wield_slot:2046-2068` auto-starts a reload
-- on wield if ammo_count == 0. The earlier abort_reload (line 1937) of the
-- old reload progress was working, but vanilla's auto-on-wield gave the
-- player a free "instant restart" of the reload that they could complete
-- visually without paying the full reload_time wait. Fix: when our cwv
-- musket was reloading at unwield time, abort the auto-reload-on-wield
-- when re-wielded. Player must press R explicitly to start a fresh reload.
-- v0.1.306: backend_id is stored at `item_data.mod_data.backend_id` for cwv
-- entries (see _build_entry — `entry.mod_data.backend_id = backend_id`).
-- Sometimes vanilla also copies it to `item_data.backend_id` directly
-- (other hooks in this file rely on that), so check BOTH locations.
local function _item_backend_id(item_data)
	if not item_data then return nil end
	local bid = item_data.backend_id
	if type(bid) ~= "string" then
		bid = item_data.mod_data and item_data.mod_data.backend_id
	end
	return type(bid) == "string" and bid or nil
end

mod:hook("SimpleInventoryExtension", "_wield_slot", function(orig, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
	-- PRE — detect unwield-of-reloading-cwv-musket.
	local outgoing_unit = equipment.right_hand_wielded_unit
	if outgoing_unit and Unit.alive(outgoing_unit) and ScriptUnit.has_extension(outgoing_unit, "ammo_system") then
		local outgoing_slot = equipment.wielded_slot
		local outgoing_slot_data = outgoing_slot and equipment.slots[outgoing_slot]
		local outgoing_item_data = outgoing_slot_data and outgoing_slot_data.item_data
		local outgoing_bid = _item_backend_id(outgoing_item_data)
		if outgoing_bid and outgoing_bid:match("^cwv_es_musket") then
			local ammo_ext = ScriptUnit.extension(outgoing_unit, "ammo_system")
			if ammo_ext and ammo_ext.is_reloading and ammo_ext:is_reloading() then
				outgoing_item_data.mod_data = outgoing_item_data.mod_data or {}
				outgoing_item_data.mod_data.cwv_musket_reload_interrupted = true
			end
		end
	end

	-- Run vanilla. Vanilla aborts the outgoing reload (clean) AND triggers
	-- auto-reload-on-wield for the incoming weapon if its clip is empty.
	local result = orig(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)

	-- POST — cancel the auto-reload-on-wield for flagged cwv musket items.
	local incoming_item_data = slot_data and slot_data.item_data
	local incoming_bid = _item_backend_id(incoming_item_data)
	if incoming_bid and incoming_bid:match("^cwv_es_musket")
			and incoming_item_data.mod_data
			and incoming_item_data.mod_data.cwv_musket_reload_interrupted then
		-- One-shot flag: clear after handling so a future manual reload works.
		incoming_item_data.mod_data.cwv_musket_reload_interrupted = nil
		local incoming_unit = equipment.right_hand_wielded_unit
		if incoming_unit and Unit.alive(incoming_unit) and ScriptUnit.has_extension(incoming_unit, "ammo_system") then
			local ammo_ext = ScriptUnit.extension(incoming_unit, "ammo_system")
			if ammo_ext and ammo_ext.is_reloading and ammo_ext:is_reloading() then
				pcall(function() ammo_ext:abort_reload() end)
			end
		end
	end

	-- POST — bayonet visibility sync (v0.1.281 behavior, preserved).
	_sync_all_bayonets_visibility(self._equipment or equipment)

	-- v0.1.322: hide the duplicated 3P offhand spare boar spear for cwv
	-- javelin variants. Vanilla _wield_slot (simple_inventory_extension.lua:2153)
	-- sets ammo_unit_3p visible when the weapon is wielded. For our javelin
	-- the IML's `left_hand_unit` AND the resolved `ammo_unit` both point
	-- at the boar spear (per v0.1.314 revert — keeping ammo_unit on the
	-- held mesh is mandatory for projectile/pickup paths). Result: 3P
	-- renders two boar spears (held + spare offhand). We can't blank
	-- ammo_unit on the data table without breaking the ammo paths, so we
	-- runtime-hide the spawned 3P instance instead. 1P offhand left alone.
	local js_bid = _item_backend_id(slot_data and slot_data.item_data)
	if js_bid and (js_bid:match("^cwv_es_javelin_") or js_bid:match("^cwv_wh_javelin_")) then
		if slot_data.left_ammo_unit_3p and Unit.alive(slot_data.left_ammo_unit_3p) then
			pcall(Unit.set_unit_visibility, slot_data.left_ammo_unit_3p, false)
		end
		if slot_data.right_ammo_unit_3p and Unit.alive(slot_data.right_ammo_unit_3p) then
			pcall(Unit.set_unit_visibility, slot_data.right_ammo_unit_3p, false)
		end
	end; local incoming_cwv_key = _om._cwv_key_for_item(incoming_bid, incoming_item_data); if incoming_cwv_key then _om.appearance_fade.owner_wield(self, equipment) end -- #922 owner 3P

	return result
end)

-- v0.1.263: hook FP/3P camera-mode toggle methods. When player switches
-- between first-person and third-person view, vanilla toggles the
-- relevant rifle units' visibility — but `World.link_unit` doesn't
-- propagate visibility to children, so the linked bayonet keeps
-- rendering in BOTH cameras (visible from 3P even though 1P rifle is
-- hidden). User reported this as a "floating dagger" in third-person
-- view. Now the bayonet's visibility mirrors its parent rifle's
-- per-camera state.
mod:hook_safe("SimpleInventoryExtension", "show_first_person_inventory", function(self, show)
	local equipment = self._equipment
	if not equipment then return end
	local rifle_1p = equipment.right_hand_wielded_unit
	if rifle_1p and Unit.alive(rifle_1p) then
		local bayonet = _musket_bayonet_pairs[rifle_1p]
		if bayonet and Unit.alive(bayonet) then
			pcall(Unit.set_unit_visibility, bayonet, show)
		end
	end
end)

mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", function(self, show)
	local equipment = self._equipment
	if not equipment then return end
	local rifle_3p = equipment.right_hand_wielded_unit_3p
	if rifle_3p and Unit.alive(rifle_3p) then
		local bayonet = _musket_bayonet_pairs[rifle_3p]
		if bayonet and Unit.alive(bayonet) then
			pcall(Unit.set_unit_visibility, bayonet, show)
		end
	end

	-- v0.1.322: re-hide cwv javelin 3P spare boar spear when the engine
	-- toggles 3P inventory visibility to true (camera switch, level start).
	-- Without this, the _wield_slot-time hide is undone on every FP→3P
	-- camera flip. show=false naturally hides everything, no work needed.
	if show then
		local wielded_slot = equipment.wielded_slot
		local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
		local item_data = slot_data and slot_data.item_data
		local bid = _item_backend_id(item_data)
		if bid and (bid:match("^cwv_es_javelin_") or bid:match("^cwv_wh_javelin_")) then
			if slot_data.left_ammo_unit_3p and Unit.alive(slot_data.left_ammo_unit_3p) then
				pcall(Unit.set_unit_visibility, slot_data.left_ammo_unit_3p, false)
			end
			if slot_data.right_ammo_unit_3p and Unit.alive(slot_data.right_ammo_unit_3p) then
				pcall(Unit.set_unit_visibility, slot_data.right_ammo_unit_3p, false)
			end
		end
	end
end)

-- Cleanup: when the rifle is destroyed (weapon swap, holster, level end),
-- destroy any bayonet linked to it. Run BEFORE vanilla so we still have a
-- live unit handle to read get_data from.
mod:hook("GearUtils", "destroy_wielded", function(func, world, wielded_unit)
	if wielded_unit and Unit.alive(wielded_unit) then
		if _om._cwv_forget_crowbill_transform_unit then
			_om._cwv_forget_crowbill_transform_unit(wielded_unit, "destroy_wielded")
		end
		-- Also clear any tracking entry to avoid using a dead key.
		_musket_bayonet_pairs[wielded_unit] = nil
		_detach_musket_bayonet(world, wielded_unit)
		-- v0.1.293: destroy Old Musket FX-proxy (hidden vanilla rifle) when
		-- our custom mesh is destroyed.
		if _om._destroy_old_musket_fx_proxy then
			_om._destroy_old_musket_fx_proxy(wielded_unit)
		end
	end
	return func(world, wielded_unit)
end)

-- ============================================================
-- cwv_es_musket_old — LA-pattern PackageManager hooks
-- ============================================================
-- v0.1.286: completely replaced the v0.1.277-285 overlay system with the
-- Loremaster's Armoury pattern. Our custom mesh path IS the variant's
-- right_hand_unit; vanilla GearUtils spawns it directly, which means the
-- mesh gets the engine's first-person rendering pipeline for free (no
-- shadow in FP, correct depth, draws under the FP hand model).
--
-- The .unit file references a VANILLA material via `data.mat_to_use`,
-- so the spawned mesh uses an existing vanilla 1P/3P material that has
-- the FP rendering shader baked in. See LA's utils/hooks.lua for the
-- prior art that informed this pattern.
--
-- The two hooks below intercept the engine's package_manager.load /
-- unload / has_loaded calls. When the engine tries to package-load our
-- custom unit path (which has no sibling .package file), we silently
-- no-op (load/unload) or report success (has_loaded). The unit data is
-- already in our master bundle via the unit-glob, so the engine can
-- still find it for World.spawn_unit + GearUtils linking.
--
-- v0.1.271-276 had this same crash; the early "fix" attempts (sibling
-- packages, .mod packages list, etc.) all failed because the engine's
-- global Application.resource_package only finds vanilla bundles. The
-- LA pattern avoids the lookup entirely by hooking before it runs.

local _LA_PATTERN_CUSTOM_PACKAGES = {
	["units/cwv_es_musket_custom/cwv_es_musket_custom"]    = true,
	["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] = true,
}

-- (#474) Husk re-key residency arm for MOD-BUNDLED custom meshes. These units
-- live in cwv's own master bundle (always resident while the mod is loaded);
-- their load lifecycle is owned by the LA-pattern PackageManager hooks below,
-- and they must NEVER be queued through the vanilla residency force-load pass
-- (issue 403 boot fatal). `_om._resident_override_3p` deliberately rejects
-- them (vanilla-prefix gate, issue 418), so the husk mesh re-key needs this
-- second predicate to accept a skin-resolved custom mesh (the Old Musket).
-- Requires BOTH the base and "_3p" forms whitelisted: the husk spawn appends
-- "_3p" to whatever lands in item_units.
_om._husk_custom_bundle_unit = function(base_unit)
	if type(base_unit) ~= "string" or base_unit == "" then return false end
	return _LA_PATTERN_CUSTOM_PACKAGES[base_unit] == true
		and _LA_PATTERN_CUSTOM_PACKAGES[base_unit .. "_3p"] == true
end

mod:hook(PackageManager, "load", function(func, self, package_name, reference_name, callback, asynchronous, prioritize)
	if _LA_PATTERN_CUSTOM_PACKAGES[package_name] then return end
	return func(self, package_name, reference_name, callback, asynchronous, prioritize)
end)

mod:hook(PackageManager, "unload", function(func, self, package_name, reference_name)
	if _LA_PATTERN_CUSTOM_PACKAGES[package_name] then return end
	return func(self, package_name, reference_name)
end)

mod:hook(PackageManager, "has_loaded", function(func, self, package_name, reference_name)
	if _LA_PATTERN_CUSTOM_PACKAGES[package_name] then return true end
	return func(self, package_name, reference_name)
end)

-- v0.1.287: register custom-mesh unit paths in NetworkLookup.inventory_packages.
-- The engine syncs equip events across multiplayer via this table — when our
-- custom right_hand_unit is equipped, the engine indexes `inventory_packages`
-- by our path. That table has a strict __index that errors on unknown keys
-- (see feedback_vt2_strict_lookup_rawget.md). LA's solution: alias our path
-- to an existing vanilla path's network index (forward direction only — we
-- do NOT overwrite the reverse index->path mapping like LA's skin-replacement
-- code does, because we don't want to hijack vanilla equip events).
-- Crash trail: v0.1.286 — "Table inventory_packages does not contain key:
-- units/cwv_es_musket_custom/cwv_es_musket_custom_3p" on equip.
do
	local nl_inventory = NetworkLookup and NetworkLookup.inventory_packages
	if nl_inventory then
		local vanilla_1p_idx = rawget(nl_inventory, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1")
		local vanilla_3p_idx = rawget(nl_inventory, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p")
		if vanilla_1p_idx then
			nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom"] = vanilla_1p_idx
		end
		if vanilla_3p_idx then
			nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] = vanilla_3p_idx
		end
		-- Issue #597: Greataxe model units live in CWV's resident bundle, but
		-- ProfileSynchronizer still serializes their 1P/3P package names through
		-- the vanilla inventory lookup. Forward-alias every custom name to the
		-- matching Bardin Greataxe index; keep index -> vanilla name untouched.
		local installed = _om.greataxe.install_network_package_aliases(nl_inventory)
		if installed > 0 then
			mod:info("[cwv:597] installed %d Greataxe inventory-package wire aliases", installed)
		end
		local crowbill_aliases = _om.crowbill_family.install_network_package_aliases(nl_inventory)
		if crowbill_aliases > 0 then
			mod:info("[cwv:604] installed %d Crowbill inventory-package wire aliases", crowbill_aliases)
		end
	end
end

-- ============================================================
-- cwv_es_musket_old — runtime texture binding + live-tunable transforms
-- ============================================================
-- Defined as GLOBAL (no `local`) so the spawn_inventory_unit hook above
-- (which is parsed before this code) can reach them at call time. Locals
-- are resolved at parse time and wouldn't be visible — see
-- feedback_lua_forward_reference.md.

-- Mutable transform constants. Edit via `cwv_om_pos_*` / `om_rot_*` /
-- `om_scale_*` commands. Split into three buckets:
--   1P RANGED — musket_template (rifle stance)
--   1P MELEE  — musket_template_melee (polearm stance) [TBD]
--   3P        — both modes share (works at identity per v0.1.295 user feedback)
-- v0.1.295 defaults for 1P ranged from user tune: pos (0, 0.62, 0),
-- rot axis (1,1,-1) @ -90°, scale (1, 1.2, 1.4).
-- v0.1.297: rotation state is now a QuaternionBox (or nil for identity). The
-- previous `{ax, ay, az, radians}` axis-angle table couldn't represent
-- composed rotations (e.g., diagonal axis-angle + an additional barrel-roll).
-- Quaternions compose via `Quaternion.multiply(q1, q2)` so the new
-- `cwv_om_rotmul_*` commands can stack rotations on top of whatever's
-- currently applied.
-- v0.1.298: WRAP in `QuaternionBox(...)`. Stingray's raw Quaternion type is
-- a stack-allocated temporary — valid only within the frame it was created.
-- Storing the raw value in a Lua global makes it stale across frames (the
-- memory gets recycled by other Quaternion temporaries). v0.1.297 stored
-- raw Quaternions; the gun appeared correct on first frame after equip but
-- then the rotation became garbage as the temp slot was reused. Vanilla
-- pattern (e.g., `bt_attack_action.lua:99`): `QuaternionBox(rotation)` to
-- box for long-term storage, `:unbox()` to get a fresh raw Quaternion when
-- you need to pass it to an API that wants a raw value.
-- Defaults for 1P-RANGED match v0.1.295 user-tuned values.
_om._CWV_OLD_MUSKET_POS_1P_RANGED   = { 0, 0.62, 0 }
_om._CWV_OLD_MUSKET_ROT_1P_RANGED   = QuaternionBox(Quaternion.axis_angle(Vector3(1, 1, -1), -math.pi / 2))
_om._CWV_OLD_MUSKET_SCALE_1P_RANGED = { 1, 1.2, 1.4 }

-- v0.1.299 1P MELEE defaults from user live-tune: pos (0, 0.06, 0),
-- rot axis (0, 1, 0) @ -90° (pure Y-axis rotation), scale identity.
_om._CWV_OLD_MUSKET_POS_1P_MELEE   = { 0, 0.06, 0 }
_om._CWV_OLD_MUSKET_ROT_1P_MELEE   = QuaternionBox(Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2))
_om._CWV_OLD_MUSKET_SCALE_1P_MELEE = { 1, 1, 1 }

-- v0.1.318: 3P split into _RANGED / _MELEE.
-- v0.1.320: final tuned values from user live-tune:
--   3P-RANGED — pos (0, 0.64, -0.01), rot Euler XYZ (-90, -90, 0), scale (1, 1.1, 1.1)
--   3P-MELEE  — pos (0, 0.045, 0.1) (unchanged from v0.1.318), rot (0, 1, 0) @ -90°
--               (unchanged), scale (1, 1.1, 1.1) (matched to 3P-RANGED per user
--               "do the same scaling for melee as well")
_om._CWV_OLD_MUSKET_POS_3P_RANGED   = { 0, 0.64, -0.01 }
_om._CWV_OLD_MUSKET_ROT_3P_RANGED   = QuaternionBox(Quaternion.from_euler_angles_xyz(-90, -90, 0))
_om._CWV_OLD_MUSKET_SCALE_3P_RANGED = { 1, 1.1, 1.1 }

_om._CWV_OLD_MUSKET_POS_3P_MELEE   = { 0, 0.045, 0.1 }
_om._CWV_OLD_MUSKET_ROT_3P_MELEE   = QuaternionBox(Quaternion.axis_angle(Vector3(0, 1, 0), -math.pi / 2))
_om._CWV_OLD_MUSKET_SCALE_3P_MELEE = { 1, 1.1, 1.1 }

-- #617/#742: the dedicated policy owns every preflight and native texture write.
_om._old_musket_texture_resources_ready = _om.old_musket_preview.texture_resources_ready
_om._prepare_old_musket_preview_material = _om.old_musket_preview.prepare_preview_material
_om._old_musket_unit_materials_ready = _om.old_musket_preview.unit_materials_ready
_om._apply_old_musket_textures = _om.old_musket_preview.apply_textures

_om._old_musket_transform_components = function(perspective, mode)
	local pos, rot, scale
	if perspective == "1p" then
		if mode == "melee" then
			pos, rot, scale = _om._CWV_OLD_MUSKET_POS_1P_MELEE, _om._CWV_OLD_MUSKET_ROT_1P_MELEE, _om._CWV_OLD_MUSKET_SCALE_1P_MELEE
		else
			pos, rot, scale = _om._CWV_OLD_MUSKET_POS_1P_RANGED, _om._CWV_OLD_MUSKET_ROT_1P_RANGED, _om._CWV_OLD_MUSKET_SCALE_1P_RANGED
		end
	else
		if mode == "melee" then
			pos, rot, scale = _om._CWV_OLD_MUSKET_POS_3P_MELEE, _om._CWV_OLD_MUSKET_ROT_3P_MELEE, _om._CWV_OLD_MUSKET_SCALE_3P_MELEE
		else
			pos, rot, scale = _om._CWV_OLD_MUSKET_POS_3P_RANGED, _om._CWV_OLD_MUSKET_ROT_3P_RANGED, _om._CWV_OLD_MUSKET_SCALE_3P_RANGED
		end
	end
	return pos, rot, scale
end

-- #1155 Phase 3: one canonical immutable descriptor + one bounded lifecycle
-- reconciler now owns all Old Musket surface application. The policy module
-- above retains only resource preflight; it no longer owns a preview recipe.
_om.old_musket_appearance = _om.old_musket_appearance_policy.new({
	descriptor = _om.appearance_descriptor,
	weapon_appearance = _om.weapon_appearance,
	policy = _om.old_musket_preview,
	unit = Unit,
	vector = { to_elements = Vector3.to_elements },
	-- Retail Quaternion is a callable table; the pilot needs both construction
	-- from descriptor x/y/z/w data and independent `to_elements` readback.
	quaternion = Quaternion,
	transform_source = _om._old_musket_transform_components,
	canonical_key = function(item)
		local data = item and item.data
		local bid = item and (item.backend_id or item.ItemInstanceId
			or (data and (data.backend_id or data.ItemInstanceId)))
		return _om._cwv_key_for_item and _om._cwv_key_for_item(bid, item)
	end,
	printf = printf,
})
_om._old_musket_preview_descriptor = function(item)
	local bid = item and (item.backend_id or item.ItemInstanceId
		or (item.data and (item.data.backend_id or item.data.ItemInstanceId)))
	local mode = bid and _om._old_musket_modes_by_backend
		and _om._old_musket_modes_by_backend[bid] or nil
	return _om.old_musket_appearance.resolve(item, mode, "illusion_browser")
end
_om._old_musket_preview_texture_targets = function(descriptor, units, spawn_data)
	return _om.old_musket_appearance.preview_targets(descriptor, units, spawn_data)
end
mod._cwv_resolve_preview_descriptor = _om._old_musket_preview_descriptor

-- #474: Old Musket stance is explicit, durable presentation state. Vanilla's
-- equipment RPC deliberately carries the base es_handgun identity, so the
-- stance cannot be inferred by a remote husk. This VMF channel sends one small
-- transition record on toggle/wield/state-entry and a query/reply on join. It
-- never polls or transmits per frame. Receivers cache by owner+slot; a late
-- husk/preview reconstruction consumes the same state as an immediate update.
-- Implementation lives in _cwv_old_musket_wire.lua (state caches, both-wire
-- acceptors, publish/query/fire). Dofiled HERE so its _om exports exist before
-- the fire-dispatch block above first runs and before the identity register
-- (defined later) routes into them.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_wire")(mod, { om = _om })

-- v0.1.293 approach A: spawn a hidden vanilla rifle alongside our custom mesh
-- so sound/VFX actions (which look up named nodes like "fx_muzzle" / "j_hammer"
-- on the weapon unit) can find them. The vanilla rifle's flow events + FX
-- emission points are baked into its compiled .unit; our custom mesh has none.
-- We hide the vanilla rifle (visibility=false), link it to our mesh, and proxy
-- Unit.node/Unit.has_node lookups so any action calling
-- `Unit.node(our_mesh, "fx_muzzle")` gets the vanilla rifle's node back.
-- Result: muzzle flash, smoke, sound, casing-eject all emit from the right
-- world position (our mesh's hand-attached position, since the proxy is
-- linked) while only our custom mesh renders.
_om._CWV_OLD_MUSKET_FX_PROXY = setmetatable({}, { __mode = "k" })  -- our_unit -> proxy_unit

_om._spawn_old_musket_fx_proxy = function(world, our_unit, vanilla_path, owner_unit, owner_hand_node_name)
	if not our_unit or not Unit.alive(our_unit) then
		-- v0.1.341-dev: promoted to `_dbg_alert` — "invalid unit" is an
		-- alert condition (the FX proxy can't be installed; FX won't fire).
		_dbg_alert("[cwv old-musket fx] our_unit invalid; skip proxy for %s", vanilla_path)
		return
	end
	if not Managers.state or not Managers.state.unit_spawner then
		-- v0.1.341-dev: promoted to `_dbg_alert` — "not available" is an
		-- alert (FX proxy can't be installed without unit_spawner).
		_dbg_alert("[cwv old-musket fx] unit_spawner not available; skip proxy")
		return
	end
	-- v0.1.296: link the proxy directly to the player's hand-attach bone
	-- rather than to our_unit's root. Why: our visible mesh has a rotation
	-- (e.g., axis (1,1,-1) @ -90° for 1P-ranged) that re-orients the gun to
	-- align with the player's grip. If the proxy inherits that rotation,
	-- its "fx_muzzle" node ends up pointing toward the camera/stomach
	-- instead of forward, so muzzle flash + bullet trail spawn at weird
	-- locations. By linking the proxy to the same bone vanilla rifle would
	-- link to, the proxy gets vanilla's natural pose — muzzle ends up where
	-- a vanilla empire-handgun's muzzle would be (in front of hand). That
	-- matches what the player visually expects regardless of how our
	-- visible mesh is reoriented.
	-- Falls back to linking to our_unit's root if the player unit + node
	-- aren't available (defensive only — they should always be present
	-- when called from the spawn_inventory_unit hook).
	local ok, proxy = pcall(function()
		return Managers.state.unit_spawner:spawn_local_unit(vanilla_path, Vector3(0, 0, 0), Quaternion.identity())
	end)
	if not ok or not proxy then
		mod:warning("[cwv old-musket fx] spawn proxy failed for %s: %s", vanilla_path, tostring(proxy))
		return
	end
	local linked_to = "fallback(our_unit root)"
	local lok = false
	if owner_unit and Unit.alive(owner_unit) and owner_hand_node_name and Unit.has_node(owner_unit, owner_hand_node_name) then
		local hand_idx = Unit.node(owner_unit, owner_hand_node_name)
		lok = pcall(World.link_unit, world, proxy, 0, owner_unit, hand_idx)
		linked_to = string.format("owner_unit %s.%s(idx=%d)", tostring(owner_unit), owner_hand_node_name, hand_idx)
	else
		lok = pcall(World.link_unit, world, proxy, 0, our_unit, 0)
	end
	-- Reset proxy's local transform so it sits exactly at the link parent's
	-- node. Without this the proxy retains its spawn-time pose relative to
	-- the new parent, which can shift its node offsets in world space.
	pcall(Unit.set_local_position, proxy, 0, Vector3(0, 0, 0))
	pcall(Unit.set_local_rotation, proxy, 0, Quaternion.identity())
	pcall(Unit.set_local_scale, proxy, 0, Vector3(1, 1, 1))
	local vok = pcall(Unit.set_unit_visibility, proxy, false)
	_om._CWV_OLD_MUSKET_FX_PROXY[our_unit] = proxy
	_dbg("[cwv old-musket fx] proxy spawned: path=%s linked_to=%s link_ok=%s vis_ok=%s",
		vanilla_path, linked_to, tostring(lok), tostring(vok))
end

_om._destroy_old_musket_fx_proxy = function(our_unit)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[our_unit]
	if proxy and Unit.alive(proxy) then
		if Managers and Managers.state and Managers.state.unit_spawner then
			pcall(function() Managers.state.unit_spawner:mark_for_deletion(proxy) end)
		end
	end
	_om._CWV_OLD_MUSKET_FX_PROXY[our_unit] = nil
end

-- Proxy Unit.node lookups: when called on our custom mesh and the requested
-- name doesn't resolve on it, redirect to the linked vanilla rifle. has_node
-- returns true if either has the node. Hooks are global (every Unit.node call
-- in the game routes through), but the proxy-table lookup is a cheap weak-
-- table read.
-- Capture the pre-hook Unit.has_node BEFORE installing any hooks so the
-- Unit.node hook can probe our mesh without invoking its own hook chain.
local _orig_unit_has_node = Unit.has_node
mod:hook(Unit, "node", function(orig, unit, name)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) and not _orig_unit_has_node(unit, name) then
		return orig(proxy, name)
	end
	return orig(unit, name)
end)
mod:hook(Unit, "has_node", function(orig, unit, name)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(unit, name) or orig(proxy, name)
	end
	return orig(unit, name)
end)

-- v0.1.294: flow events drive most weapon FX in VT2 (muzzle flash, smoke,
-- bullet trail, casing eject, dry-fire click — all baked into the rifle's
-- compiled .unit as flow graph nodes triggered by named events fired from
-- Lua action code like ActionHandgun:line 194 `Unit.flow_event(weapon_unit,
-- "lua_bullet_trail")`). Our custom mesh has no flow graph, so firing on it
-- no-ops. Redirect to the proxy (which has the full vanilla flow graph).
-- Same proxy-table-lookup pattern as Unit.node hook above.
mod:hook(Unit, "flow_event", function(orig, unit, event_name)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(proxy, event_name)
	end
	return orig(unit, event_name)
end)
-- Flow VARIABLES seed values that flow graph nodes read (e.g. "hit_position"
-- on line 192 of action_handgun.lua). Redirect to proxy for the same reason.
mod:hook(Unit, "set_flow_variable", function(orig, unit, name, value)
	local proxy = _om._CWV_OLD_MUSKET_FX_PROXY[unit]
	if proxy and Unit.alive(proxy) then
		return orig(proxy, name, value)
	end
	return orig(unit, name, value)
end)

_om._reapply_old_musket_transforms_all = function()
	local count = _om.old_musket_appearance.reapply_tracked()
	mod:echo("[cwv old-musket] descriptor generation replayed to %d retained unit(s)", count)
end

-- v0.1.290: filter attachment_node_linking entries that reference skeleton
-- nodes not present on our custom mesh. The vanilla empire-rifle template's
-- `AttachmentNodeLinking.rifles.first_person.wielded` links 4 player-side
-- hand-component bones to 4 weapon-side rig nodes (j_lock, j_hammer,
-- j_trigger, plus node 0). Our FBX has no skeleton (just mesh geometry),
-- so the engine's `Unit.node(target, "j_lock")` call in `GearUtils.link_units`
-- crashes with `[Script Error]: j_lock`. Filter: keep entries whose target
-- is a node-index (always 0 = root, safe on any unit) or whose named target
-- actually resolves; drop the rest. The root link is what physically
-- attaches the weapon to the hand — the others are decorative finger-pose
-- attachments that only matter for vanilla rifles with the full rig.
mod:hook("GearUtils", "link_units", function(orig, world, attachment_node_linking, link_table, source, target)
	if not target then return orig(world, attachment_node_linking, link_table, source, target) end
	-- v0.1.291: `Unit.has_node` returns a boolean — verified used in vanilla
	-- ai_bot_group_system.lua:190 and similar. The v0.1.290 attempt used
	-- `pcall(Unit.node, ...)`, but Stingray's Unit.node throws an error that
	-- pcall doesn't catch (engine-level fatal, not a Lua error). has_node
	-- is the correct safe-existence API.
	for _, entry in ipairs(attachment_node_linking) do
		local tgt = entry.target
		if type(tgt) == "string" and not Unit.has_node(target, tgt) then
			-- Found a missing node — filter the whole table.
			local safe = {}
			for _, e in ipairs(attachment_node_linking) do
				local t = e.target
				if type(t) ~= "string" or Unit.has_node(target, t) then
					safe[#safe + 1] = e
				end
			end
			return orig(world, safe, link_table, source, target)
		end
	end
	return orig(world, attachment_node_linking, link_table, source, target)
end)

-- ============================================================
-- Tuskgor Javelin template (modified javelin_template)
-- 15 max ammo, no auto-catch reload, ammo pickups refill, 2x damage, 0.5x speed
--
-- ANIM ADDENDUM: this template clone is shared across Kruber and Saltzpyre
-- variants (cwv_es_javelin / cwv_wh_javelin). 1P animations are universal —
-- the 1P state machine and clips reference shared first_person_base assets
-- and play correctly on every character without intervention. Only 3P body
-- anims need cross-character work, via anim_event_3p / wield_anim_3p /
-- wield_anim_career_3p. See top-of-file ANIMATION ARCHITECTURE.
-- ============================================================
--
-- Differs from the longsword/sword+shield clones in two important ways:
--
-- 1. Ammo system: vanilla javelin uses `unique_ammo_type=true` + a custom
--    auto-replenish action (`weapon_reload.default` with `kind="catch"`) that
--    magically refills the player's javelin stack to max whenever they're
--    below it. We override `condition_func`/`chain_condition_func` to always
--    return false, which keeps the action defined for state-machine/network
--    purposes but prevents it from ever firing — turning the weapon into a
--    finite-stack thrown weapon. Combined with `block_ammo_pickup=false` and
--    `unique_ammo_type=false`, vanilla ammo crates refill it like any other
--    Kruber ranged weapon (handgun/blunderbuss/longbow style).
--
-- 2. Damage profile shape: the throw projectile uses `thrown_javelin`, which
--    is an INLINE damage profile (`default_target.power_distribution_near.attack`
--    is a literal number) — NOT the PowerLevelTemplates string-key indirection
--    used by melee weapons. The shared `_clone_damage_profile` helper assumes
--    the string-key shape, so we use a dedicated `_clone_inline_throw_profile`
--    for the throw and reuse `_clone_damage_profile` for the melee stab
--    sub-actions (which DO use the string-key shape).
--
-- The "half speed" axis multiplies `total_time` and `minimum_hold_time` on
-- `kind="thrown_projectile"` sub-actions, plus `attack_meta_data.minimum_charge_time`
-- (the wind-up). Most javelin sub-actions don't carry `anim_time_scale`, so
-- the longsword-style anim_time_scale multiplication is mostly a no-op here —
-- timing fields are the actual lever.

local _TJ_DAMAGE_MULT          = 2.0
local _TJ_SPEED_MULT           = 0.5   -- action speed: half = 2x wind-up + recovery duration
local _TJ_PROJECTILE_SPEED_MULT = 0.9  -- in-flight projectile velocity (sub_action.speed) — slower than vanilla javelin
local _TJ_MAX_AMMO             = 10

-- Custom projectile + pickup keys (registered below). Variant defs reference
-- these via projectile_units_template / pickup_template_name /
-- link_pickup_template_name, which the skin registration mirrors onto the
-- weapon skin entry so the engine resolves them at projectile spawn time.
local _TJ_PROJECTILE_KEY        = "cwv_tuskgor_javelin"
local _TJ_PICKUP_KEY            = "cwv_tuskgor_javelin_pickup"
local _TJ_LINK_PICKUP_KEY       = "cwv_tuskgor_javelin_link_pickup"
-- Pickup + in-flight unit selection.
--
-- v0.1.73 split the in-flight unit (boar spear) from the pickup unit (elf
-- javelin prj_*_3ps), with the rationale that the elf javelin had verified
-- physics + correct axes for pickup spawn while the held boar spear _3p
-- might lack those.
--
-- v0.1.118 reverts to using the boar spear _3p for BOTH paths, because:
--   * The elf javelin _3ps unit is in the woods DLC's per-weapon package,
--     which is loaded with the elf's `we_javelin` inventory entry — but
--     OUR cwv_es_javelin item declares the boar spear in left_hand_unit/
--     right_hand_unit, so the package loader never queues the elf javelin
--     unit for our equipped variant. Result: `World.spawn_unit` crashes
--     when the engine tries to spawn the unloaded prj_we_javelin_01_3ps
--     pickup unit (crash GUID b7936944).
--   * The mod-tools compiler doesn't ship DLC units locally, so we can't
--     reference the elf javelin in our resource_packages/.package file.
--   * The boar spear _3p IS reliably loaded (it's our held mesh).
--
-- Trade-off: the boar spear may have weak physics for pickup interaction
-- and wrong local axes (hand-attachment), so v0.1.71's symptoms (no F/E
-- prompt + 90° rotation off) may resurface. But those are now actually
-- diagnosable since the link_pickup branch is finally engaged. We can
-- iterate from there with rotation hooks and see if pickup interaction
-- actually works with the held mesh.
local _TJ_BOAR_SPEAR_UNIT       = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p"
-- v0.1.164: carrier-unit pattern. Probe data (v0.1.137 dump) confirmed the
-- boar spear _3p has 0 actors while pup_dw_thrown_axe_01_t1 has 3. Without
-- actors the interactor's aim raycast finds nothing → no E-prompt. Use the
-- throwing axe pup as the actual spawn unit (real interaction collision)
-- and attach the boar spear visually as a child via World.link_unit at
-- extensions_ready time. Player sees boar spear, interacts with throwing
-- axe collision underneath. Force-loaded via Managers.package:load() at
-- mod init since base inventory doesn't queue the pup package.
local _TJ_THROWING_AXE_PUP      = "units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1"
local _TJ_PICKUP_UNIT           = _TJ_THROWING_AXE_PUP
-- v0.1.314: REVERTED v0.1.258 / v0.1.263's pull-back fix. The
-- `pos - Quaternion.forward(rot) * offset` math along the spear's forward
-- axis didn't visibly change stuck-javelin depth — see TODO in
-- character_weapon_variants/TODO.md. Constant kept at 0 so the math
-- branch is a no-op; the spawn position equals the parent's pose
-- exactly. Real fix is unknown — likely the parent unit's rotation
-- doesn't have its forward axis aligned with the spear's pointing
-- direction (so `Quaternion.forward(rot)` is the wrong axis), or the
-- parent isn't at the contact point we assume.
local _TJ_VISUAL_PULL_BACK_M    = 0

-- ============================================================================
-- issue 424 (BUG_CLASSES 31): thrown-variant NetworkLookup wire-safety
-- ============================================================================
-- The Tuskgor Javelin appends pickup, husk, and projectile lookup keys.
-- The full sender/hot-join containment rationale and hooks live in
-- _cwv_javelin_gate.lua; this entry file retains only the configured map.

_om._TJ_INFLIGHT_MODDED_UNIT   = _TJ_BOAR_SPEAR_UNIT
_om._TJ_INFLIGHT_SAFE_TEMPLATE = "javelin"   -- vanilla ProjectileUnits key (elf javelin)
-- The exact thrown-resource spec: the five appended rows plus the proven
-- vanilla donor each one degrades to. `pickup_fallbacks` is the ONLY declared
-- donor map; a cwv_-prefixed pickup absent from it is not "keep the custom id"
-- (the pre-#424 nil-ambiguity that let `cwv_tuskgor_javelin_bomb` wire its own
-- appended index) but a DROP -- see _cwv_thrown_wire_policy.is_owned_pickup.
_om._TJ_WIRE_SPEC = {
	projectile_key        = _TJ_PROJECTILE_KEY,
	safe_projectile_key   = _om._TJ_INFLIGHT_SAFE_TEMPLATE,
	inflight_unit         = _TJ_BOAR_SPEAR_UNIT,
	safe_projectile_unit  = "units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps",
	carrier_unit          = _TJ_PICKUP_UNIT,
	pickup_key            = _TJ_PICKUP_KEY,
	link_pickup_key       = _TJ_LINK_PICKUP_KEY,
	safe_pickup_key       = "ammo_throwing_axe_01_t1",
	safe_link_pickup_key  = "link_ammo_throwing_axe_01_t1",
	pickup_fallbacks = {
		-- cwv thrown-impact pickup key -> a base-game pickup with a boot-stable
		-- pickup_names index on every peer (throwing axe: same pup_ unit, and the
		-- link_ variant shares our `limited_owned_pickup_unit` template).
		[_TJ_PICKUP_KEY]      = "ammo_throwing_axe_01_t1",
		[_TJ_LINK_PICKUP_KEY] = "link_ammo_throwing_axe_01_t1",
	},
}
_om._tj_pickup_wire_map = _om._TJ_WIRE_SPEC.pickup_fallbacks
-- Three-valued by construction: RIDE_CUSTOM (send `name` as given) /
-- SUBSTITUTE (send the returned proven vanilla donor) / DROP (suppress the
-- spawn). The optional override exists for deterministic regression checks
-- only; live callers omit it and the exact thrown verdict decides.
function _om._tj_pickup_disposition(pickup_name, exact_override)
	local exact = exact_override
	if exact == nil then
		local ok, safe = pcall(mod._cwv_thrown_wire_safe)
		exact = ok and safe == true
	end
	return _om.thrown_wire_policy.pickup_disposition(
		pickup_name, exact, _om._TJ_WIRE_SPEC, _G)
end
-- UNCONDITIONAL in-flight floor (never parity- or toggle-gated): our boar-spear
-- husk must never ride a vanilla GameObject. Returns the vanilla donor table,
-- the input unchanged when it is not ours, or nil when the donor cannot be
-- proven -- the ProjectileSystem preflight in _cwv_javelin_gate refuses the
-- spawn on nil rather than let vanilla dereference it.
function _om._wire_safe_projectile_units(projectile_units)
	local disposition, resolved = _om.thrown_wire_policy.projectile_disposition(
		projectile_units, _om._TJ_WIRE_SPEC, _G)
	if disposition == _om.thrown_wire_policy.DROP then return nil end
	return resolved
end

local function _register_tuskgor_javelin_assets()
	-- 1. Projectile unit — controls the in-flight + stuck mesh when the throw
	-- action's `use_weapon_skin = true` resolves to our skin's
	-- projectile_units_template = _TJ_PROJECTILE_KEY.
	if not ProjectileUnits then
		mod:warning("ProjectileUnits global missing — projectile/pickup model swap unavailable")
		return
	end
	if not ProjectileUnits[_TJ_PROJECTILE_KEY] then
		ProjectileUnits[_TJ_PROJECTILE_KEY] = {
			dummy_linker_unit_name = _TJ_BOAR_SPEAR_UNIT,
			projectile_unit_name   = _TJ_BOAR_SPEAR_UNIT,
		}
		if NetworkLookup and NetworkLookup.projectile_units
			and not rawget(NetworkLookup.projectile_units, _TJ_PROJECTILE_KEY)
		then
			local tbl = NetworkLookup.projectile_units
			local idx = #tbl + 1
			rawset(tbl, idx, _TJ_PROJECTILE_KEY)
			rawset(tbl, _TJ_PROJECTILE_KEY, idx)
		end
		mod:info("Registered ProjectileUnits.%s -> %s", _TJ_PROJECTILE_KEY, _TJ_BOAR_SPEAR_UNIT)
	end

	-- 1b. Husk lookup injection — required for non-link pickup spawn path.
	-- PlayerProjectileUnitExtension._spawn_pickup_projectile (player_projectile_unit_extension.lua:1382)
	-- looks up `NetworkLookup.husks[pickup_unit_name]` before sending the spawn
	-- RPC. The boar spear's `_3p` unit was never registered as husk-spawnable
	-- (anvil_common_settings.lua:8-18 declares the throwing axe's pup_/prj_/_3p
	-- variants in `husk_lookup`, but the boar spear only got the held _3p
	-- declaration in anvil_equipment_settings.lua's player_units list — that
	-- list doesn't feed into NetworkLookup.husks). Without this injection,
	-- throws that take the non-link path (friendly hits, shields, certain
	-- terrain with allow_link=false) crash with the "Table husks does not
	-- contain key" error from network_lookup.lua's __index metamethod.
	-- v0.1.71 hit this crash on the very first thrown javelin.
	if NetworkLookup and NetworkLookup.husks
		and not rawget(NetworkLookup.husks, _TJ_BOAR_SPEAR_UNIT)
	then
		local tbl = NetworkLookup.husks
		local idx = #tbl + 1
		rawset(tbl, idx, _TJ_BOAR_SPEAR_UNIT)
		rawset(tbl, _TJ_BOAR_SPEAR_UNIT, idx)
		mod:info("Injected '%s' into NetworkLookup.husks at index %d", _TJ_BOAR_SPEAR_UNIT, idx)
	end

	-- 1c. Throwing axe pup unit force-load + husks injection.
	-- Carrier-unit pattern (v0.1.164): the boar spear has 0 actors so the
	-- interactor can't detect aim hits on it. The throwing axe pup unit has
	-- 3 actors (verified via cwv_probe_unit). Use the throwing axe pup as
	-- the actual spawned pickup, attach the boar spear visually as a child
	-- in the extensions_ready hook below.
	-- The pup unit isn't loaded by base inventory (only loads when Bardin
	-- equips throwing axes AND throws one). Force-load via the same API
	-- vanilla pickup_package_loader uses (`Managers.package:load(unit_path,
	-- ref, nil, async, prioritize)`), reference at pickup_package_loader.lua:191.
	if Managers and Managers.package then
		local ok, err = pcall(function()
			Managers.package:load(_TJ_THROWING_AXE_PUP, "cwv_throwing_axe_pup", nil, true, true)
		end)
		if ok then
			mod:info("Force-loaded throwing axe pup unit: %s", _TJ_THROWING_AXE_PUP)
		else
			mod:warning("Failed to force-load throwing axe pup: %s", tostring(err))
		end
	end
	if NetworkLookup and NetworkLookup.husks
		and not rawget(NetworkLookup.husks, _TJ_THROWING_AXE_PUP)
	then
		local tbl = NetworkLookup.husks
		local idx = #tbl + 1
		rawset(tbl, idx, _TJ_THROWING_AXE_PUP)
		rawset(tbl, _TJ_THROWING_AXE_PUP, idx)
		mod:info("Injected '%s' into NetworkLookup.husks at index %d", _TJ_THROWING_AXE_PUP, idx)
	end

	-- 2. Pickup templates — define ground pickup + linked-pickup (stuck variant).
	-- Modeled after anvil_pickup_settings.lua's throwing_axe pickups, but the
	-- can_interact / outline checks query for ammo_type "throwing_javelin"
	-- (vanilla javelin's ammo_type, which we kept on tuskgor_javelin_template)
	-- so only players wielding our javelin can pick these up — and any actual
	-- elf carrying we_javelin would also see them, which is fine since they
	-- share the ammo_type.
	if not Pickups or not Pickups.ammo then
		mod:warning("Pickups.ammo missing — link_pickup behavior unavailable")
		return
	end
	if not Pickups.ammo[_TJ_PICKUP_KEY] then
		local function _can_interact(interactor_unit, _interactable_unit, _data)
			local inv = ScriptUnit.has_extension(interactor_unit, "inventory_system")
			local result = inv and inv:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
			_dbg("[cwv stick] can_interact_func -> %s (inv=%s)", tostring(result), tostring(inv ~= nil))
			return result
		end
		local function _outline_available(local_player_unit)
			local inv = ScriptUnit.has_extension(local_player_unit, "inventory_system")
			return inv and inv:has_ammo_consuming_weapon_equipped("throwing_javelin") or false
		end
		local function _on_pick_up(_world, _interactor_unit, _is_server, interactable_unit)
			_dbg("[cwv stick] on_pick_up_func fired")
			local peer_id = Network.peer_id()
			local pickup_system = Managers.state.entity:system("pickup_system")
			pickup_system:delete_limited_owned_pickup_unit(peer_id, interactable_unit)
		end
		local base = {
			ammo_kind            = "thrown",
			consumable_item      = true,
			debug_pickup_category = "throwing_weapons",
			hud_description      = "cwv_interaction_ammunition_javelin",  -- v0.1.183: own loc string (was "interaction_ammunition_axe" — wrong text)
			local_pickup_sound   = true,
			only_once            = true,
			outline_distance     = "small_pickup",
			pickup_sound_event   = "pickup_ammo",
			refill_amount        = 1,
			spawn_weighting      = 1e-06,
			type                 = "ammo",
			can_interact_func    = _can_interact,
			outline_available_func = _outline_available,
			on_pick_up_func      = _on_pick_up,
		}
		-- v0.1.118: unit_name = boar spear _3p for both variants (held mesh
		-- is reliably loaded for our cwv weapon, unlike the elf javelin
		-- prj_*_3ps which is in the woods DLC's per-weapon package).
		-- v0.1.119: unit_template_name = "limited_owned_pickup_unit" for BOTH
		-- variants (was "limited_owned_pickup_projectile_unit" for the
		-- non-link/dropped variant). The "_projectile_unit" template requires
		-- the unit to have a physics actor named "throw" for bouncy ground
		-- pickup behavior — the boar spear _3p doesn't have that actor and
		-- crashes Actor.create_actor (crash GUID 86d07a4e on dummy hit). The
		-- non-projectile template doesn't need it; pickups spawn statically
		-- at the impact position instead of bouncing. Acceptable trade-off.
		Pickups.ammo[_TJ_PICKUP_KEY] = table.clone(base)
		Pickups.ammo[_TJ_PICKUP_KEY].unit_name          = _TJ_PICKUP_UNIT
		Pickups.ammo[_TJ_PICKUP_KEY].unit_template_name = "limited_owned_pickup_unit"
		Pickups.ammo[_TJ_PICKUP_KEY].pickup_name        = _TJ_PICKUP_KEY
		Pickups.ammo[_TJ_LINK_PICKUP_KEY] = table.clone(base)
		Pickups.ammo[_TJ_LINK_PICKUP_KEY].unit_name          = _TJ_PICKUP_UNIT
		Pickups.ammo[_TJ_LINK_PICKUP_KEY].unit_template_name = "limited_owned_pickup_unit"
		Pickups.ammo[_TJ_LINK_PICKUP_KEY].pickup_name        = _TJ_LINK_PICKUP_KEY
		-- Re-attach the function refs after table.clone (closures get shallow-copied
		-- correctly, but be explicit so a future refactor doesn't trip us).
		for _, key in ipairs({ _TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY }) do
			Pickups.ammo[key].can_interact_func      = _can_interact
			Pickups.ammo[key].outline_available_func = _outline_available
			Pickups.ammo[key].on_pick_up_func        = _on_pick_up
		end

		-- AllPickups is built once at boot from Pickups.<group>.<name> and is
		-- the lookup the pickup system reads. Mirror our entries in.
		if AllPickups then
			AllPickups[_TJ_PICKUP_KEY]      = Pickups.ammo[_TJ_PICKUP_KEY]
			AllPickups[_TJ_LINK_PICKUP_KEY] = Pickups.ammo[_TJ_LINK_PICKUP_KEY]
		end

		-- NetworkLookup.pickup_names is built from AllPickups at boot. Mirror
		-- our keys in via rawset (the table has an error-throwing __index).
		if NetworkLookup and NetworkLookup.pickup_names then
			local tbl = NetworkLookup.pickup_names
			for _, key in ipairs({ _TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY }) do
				if not rawget(tbl, key) then
					local idx = #tbl + 1
					rawset(tbl, idx, key)
					rawset(tbl, key, idx)
				end
			end
		end

		mod:info("Registered pickups: %s + %s (boar spear unit, ammo_type=throwing_javelin)",
			_TJ_PICKUP_KEY, _TJ_LINK_PICKUP_KEY)
	end
end

-- ============================================================
-- Stuck-pickup rotation cleanup (Tuskgor Javelin) — INSTRUMENTED
-- ============================================================
-- v0.1.81 hooked ProjectileLinkerSystem.link_pickup but that fires AFTER
-- PickupSystem._spawn_pickup has already set the unit's world rotation
-- (pickup_system.lua:1441 _spawn_pickup → 1446 link_pickup). For the common
-- "stuck in a level wall" case, hit_unit doesn't have a projectile_linker_system
-- extension, so link_pickup falls through to the else branch which never
-- re-applies link_rotation. The hook therefore had no effect on wall-sticks.
--
-- v0.1.82 moves the hook earlier: PickupSystem.rpc_spawn_linked_pickup runs
-- server-side BEFORE _spawn_pickup is called, with link_rotation as a parameter
-- we can rewrite. Modifying it here propagates through the spawn AND through
-- the subsequent rpc_link_pickup that fans to clients.
--
-- Also rotation logic upgraded: horizontal-projection variant. The engine
-- applies random_pitch (math.pi/6 to math.pi/3 = 30°-60° around unit-left)
-- and random_roll (±18° around unit-forward) on top of the clean directional
-- look. To wipe both completely, project the rotated forward onto the
-- horizontal plane (Stingray world: x,y horizontal; z vertical) and rebuild
-- look using world up. Cost: floor/ceiling sticks would point sideways
-- instead of into-the-surface. Acceptable trade-off given vertical walls
-- are >90% of stick locations.
--
-- Verbose logging (mod:info) on every fire — input rotation axes, output
-- rotation axes, pickup name. Lets us see in console.log whether the hook
-- fires AND whether the math produces the correction we expect.
local function _log_quat(prefix, q)
	-- v0.1.336: helper only ever called from the `[cwv stick]` diagnostic
	-- hooks below, all of which are now gated on `cwv_debug_mode`. Route
	-- through `_dbg` so the formatting cost is also skipped when off.
	local fwd = Quaternion.forward(q)
	local rgt = Quaternion.right(q)
	local up  = Quaternion.up(q)
	_dbg("  %s: fwd=(%.2f,%.2f,%.2f) right=(%.2f,%.2f,%.2f) up=(%.2f,%.2f,%.2f)",
		prefix,
		Vector3.x(fwd), Vector3.y(fwd), Vector3.z(fwd),
		Vector3.x(rgt), Vector3.y(rgt), Vector3.z(rgt),
		Vector3.x(up),  Vector3.y(up),  Vector3.z(up))
end

local function _is_our_pickup(pickup_name)
	return pickup_name == _TJ_PICKUP_KEY or pickup_name == _TJ_LINK_PICKUP_KEY
end

local function _clean_horizontal_rotation(rot)
	local fwd = Quaternion.forward(rot)
	local horizontal = Vector3(Vector3.x(fwd), Vector3.y(fwd), 0)
	if Vector3.length(horizontal) <= 0.01 then return rot, false end
	horizontal = Vector3.normalize(horizontal)
	local clean = Quaternion.look(horizontal, Vector3.up())
	-- v0.1.119: boar spear's local +Z is the tip axis (held mesh, hand grip
	-- pose). Engine's Quaternion.look orients local +Y to forward, so the
	-- visible tip ends up pointing world up — user reports "stuck straight
	-- up and down vertically". Post-multiply by a -90° rotation around the
	-- unit's local right axis (+X) to swing local +Z (tip) onto local +Y
	-- (link_direction). After this, the visible tip points along link_direction
	-- = into the wall.
	local tip_correction = Quaternion(Vector3.right(), -math.pi / 2)
	return Quaternion.multiply(clean, tip_correction), true
end

-- ============================================================================
-- THE ACTUAL FIX (v0.1.97): force projectile/action system to use our cloned
-- template, not the base.
-- ============================================================================
-- v0.1.96 diagnostic confirmed the engine reads `javelin_template` (base) at
-- projectile init, NOT `tuskgor_javelin_template`. Cause: per memory note
-- `feedback_cwv_backend_id_lookup.md`, `item_data.name`/`.key` returns the
-- BASE weapon key for cwv items. The projectile system does
-- `ItemMasterList[item_name]` (item_name = "we_javelin") then
-- `BackendUtils.get_item_template(item_data)` reads `item_data.template`
-- which is the base template name. Our cloned template was dead code at
-- runtime — every stat/timing/impact_data override never took effect.
--
-- Hook `BackendUtils.get_item_template`. When the backend_id matches our cwv
-- javelin pattern, return `Weapons.tuskgor_javelin_template` instead of the
-- resolved base template.
--
-- Scope: only fires when backend_id matches `cwv_..._javelin_001`. Other cwv
-- weapons hit the same bug in principle but happen to share the SAME template
-- name as their base (e.g. cwv_es_longsword still uses `imperial_longsword_template`
-- which the engine resolves correctly via the base lookup since our clone IS
-- registered under that exact name). Javelin is special because we cloned to
-- a DIFFERENT name (`tuskgor_javelin_template` vs base `javelin_template`)
-- and the engine doesn't know about the rename.
-- v0.1.97 hook on BackendUtils.get_item_template was a no-op: the projectile
-- system passes `ItemMasterList[item_name]` where item_name = "we_javelin"
-- (BASE key, since cwv items return base for item_data.name/.key per memory
-- `feedback_cwv_backend_id_lookup.md`). The base entry has no backend_id, so
-- the cwv match never fired.
--
-- v0.1.98 fix: hook PlayerProjectileUnitExtension.init AFTER vanilla init
-- runs, look up the OWNER's slot_ranged backend_id (where the cwv prefix
-- actually lives), and if it matches our javelin pattern, swap
-- self._current_action / self._impact_data / self.projectile_info to point
-- at our cloned tuskgor_javelin_template's throw_charged sub-action. The
-- projectile then reads OUR fields for the rest of its lifecycle (impact
-- handling, link_pickup, pickup_settings, etc.).
-- Single init hook combining the v0.1.98 fix and the v0.1.96 diagnostic
-- trace. v0.1.99 had two separate `hook_safe` registrations on the same
-- method which silently never fired (VMF doesn't chain multiple hook_safe
-- handlers for one method).
mod:hook_safe("PlayerProjectileUnitExtension", "init", function(self, extension_init_context, unit, extension_init_data)
	-- 1) Diagnostic trace (always fires).
	local item = extension_init_data and extension_init_data.item_name or "?"
	local tmpl = extension_init_data and extension_init_data.item_template_name or "?"
	local action = extension_init_data and extension_init_data.action_name or "?"
	local sub = extension_init_data and extension_init_data.sub_action_name or "?"
	_dbg("[cwv stick] PROJ INIT item=%s tmpl=%s action=%s sub=%s",
		tostring(item), tostring(tmpl), tostring(action), tostring(sub))

	-- 2) Post-fix: if this projectile belongs to one of our cwv javelin
	--    variants, swap the action data references onto our cloned template.
	--    Filter to javelin-class items only to avoid log spam on arrows/bolts.
	if item ~= "we_javelin" then return end

	local owner_unit = extension_init_data and extension_init_data.owner_unit
	if not owner_unit then
		_dbg("[cwv stick] post-fix BAIL: no owner_unit in extension_init_data")
		return
	end
	local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
	if not inv then
		_dbg("[cwv stick] post-fix BAIL: no inventory_system extension on owner")
		return
	end
	local slot_data = inv:get_slot_data("slot_ranged")
	if not slot_data then
		_dbg("[cwv stick] post-fix BAIL: no slot_ranged slot_data")
		return
	end
	-- v0.1.106 diagnostic dump revealed: slot_data.id is the slot NAME
	-- ("slot_ranged"), slot_data.backend_id is nil. The cwv identifier
	-- actually lives in slot_data.skin (e.g. "cwv_es_javelin_skin").
	-- Match the skin field instead.
	local skin = slot_data.skin
	if type(skin) ~= "string" or not skin:match("^cwv_.+_javelin_skin$") then
		_dbg("[cwv stick] post-fix BAIL: skin=%s did not match cwv javelin pattern", tostring(skin))
		return
	end

	if not (Weapons and Weapons.tuskgor_javelin_template) then return end
	local our_template = Weapons.tuskgor_javelin_template
	local lookup = self.action_lookup_data
	if not lookup then return end
	local action_group = our_template.actions and our_template.actions[lookup.action_name]
	local our_action = action_group and action_group[lookup.sub_action_name]
	if not our_action then return end

	self._current_action = our_action
	self._impact_data    = our_action.impact_data
	self.projectile_info = our_action.projectile_info or self.projectile_info
	if our_action.impact_data and our_action.impact_data.damage_profile then
		local dmg_id = rawget(NetworkLookup.damage_profiles, our_action.impact_data.damage_profile)
		if dmg_id then self._impact_damage_profile_id = dmg_id end
	end
	_dbg("[cwv stick] init post-fix swap: skin=%s -> tuskgor_javelin_template (action=%s sub=%s, link=%s link_pickup=%s)",
		tostring(skin), tostring(lookup.action_name), tostring(lookup.sub_action_name),
		tostring(our_action.impact_data and our_action.impact_data.link),
		tostring(our_action.impact_data and our_action.impact_data.link_pickup))

	-- v0.1.125–v0.1.156 carried a child-node rotation correction here for the
	-- boar spear's wrong-axis in-flight visual. v0.1.157 made the in-flight
	-- unit the vanilla elf javelin (correctly authored, +Y is tip), so the
	-- correction is no longer applicable — and would actively wrongly rotate
	-- the elf javelin's child nodes. Removed.
end)

mod:hook_safe("PlayerProjectileUnitExtension", "hit_level_unit", function(self, impact_data, hit_unit)
	local lookup = self.action_lookup_data
	local tmpl = lookup and lookup.item_template_name or "?"
	-- v0.1.345-dev: dummy-path marker. Historical crash GUID 86d07a4e (see
	-- ~line 5210 above) fired when the Tuskgor Javelin's pickup spawn on
	-- dummy hits routed through `limited_owned_pickup_projectile_unit` —
	-- whose physics actor name "throw" doesn't exist on the boar spear _3p
	-- mesh, crashing `Actor.create_actor`. The fix swapped to
	-- `limited_owned_pickup_unit` (no physics). hit_level_unit is the
	-- engine entry point that dispatches to pickup spawn (PATH A
	-- `rpc_spawn_linked_pickup` for `link_pickup=true`, PATH B
	-- `rpc_spawn_pickup_projectile` otherwise). Capture hit_unit shape
	-- so dummy hits are identifiable.
	local hit_unit_alive = hit_unit and Unit.alive(hit_unit)
	_dbg("[cwv stick] HIT_LEVEL_UNIT tmpl=%s link=%s link_pickup=%s hit_unit_alive=%s",
		tostring(tmpl),
		tostring(impact_data and impact_data.link),
		tostring(impact_data and impact_data.link_pickup),
		tostring(hit_unit_alive))
	-- v0.1.345-dev: dummy-path explicit marker — if hit_unit is a training
	-- dummy (heuristic: live unit with no health_system extension, or a
	-- level unit named "training_dummy"), log explicitly so the next session
	-- log captures whether the historical crash path is reached.
	if hit_unit_alive and ScriptUnit and ScriptUnit.has_extension
			and not ScriptUnit.has_extension(hit_unit, "health_system") then
		_dbg("[cwv:dummy_path] event=hit_level_unit_no_health_system tmpl=%s — was historical crash site (GUID 86d07a4e on dummy hit), monitoring",
			tostring(tmpl))
	end
end)

mod:hook("PlayerProjectileUnitExtension", "_handle_linking", function(func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, damage_amount, allow_link, shield_blocked, hit_enemy_or_player)
	local lookup = self.action_lookup_data
	local tmpl = lookup and lookup.item_template_name or "?"
	_dbg("[cwv stick] HANDLE_LINKING tmpl=%s allow_link=%s link=%s link_pickup=%s",
		tostring(tmpl), tostring(allow_link),
		tostring(impact_data and impact_data.link),
		tostring(impact_data and impact_data.link_pickup))
	return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, damage_amount, allow_link, shield_blocked, hit_enemy_or_player)
end)

-- One-shot dump command: read the live runtime tuskgor_javelin_template's
-- impact_data. Tells us if our modifications actually persisted into the
-- runtime template state, or if something overwrote them.
mod:command("cwv_dump_javelin_impact", "Dump runtime tuskgor_javelin_template throw_charged.impact_data", function()
	if not Weapons or not Weapons.tuskgor_javelin_template then
		mod:echo("Weapons.tuskgor_javelin_template not found")
		return
	end
	mod:echo("=== tuskgor_javelin_template runtime dump ===")
	for action_name, action_group in pairs(Weapons.tuskgor_javelin_template.actions) do
		if type(action_group) == "table" then
			for sub_name, sub in pairs(action_group) do
				if type(sub) == "table" and sub.kind == "thrown_projectile" then
					mod:echo("action.%s.%s:", action_name, sub_name)
					mod:echo("  speed=%s total_time=%s",
						tostring(sub.speed), tostring(sub.total_time))
					if sub.impact_data then
						local i = sub.impact_data
						mod:echo("  link=%s link_pickup=%s wall_nail=%s",
							tostring(i.link), tostring(i.link_pickup), tostring(i.wall_nail))
						mod:echo("  flow_walls=%s flow_init=%s",
							tostring(i.flow_event_on_walls), tostring(i.flow_event_on_init))
						mod:echo("  pickup_settings=%s",
							tostring(i.pickup_settings))
					else
						mod:echo("  impact_data = nil")
					end
				end
			end
		end
	end
end)

-- Path A entry on thrower's side — trace + issue 424 wire-safe substitution.
-- The vanilla body encodes NetworkLookup.pickup_names[pickup_name] and sends
-- rpc_spawn_linked_pickup (player_projectile_unit_extension.lua:1354-1359);
-- while parity is unconfirmed, swapping the cwv key for a vanilla one BEFORE
-- func() keeps a non-cwv peer from cold-decoding the appended index
-- (BUG_CLASSES 31). Confirmed-CWV lobbies retain the functional original.
mod:hook("PlayerProjectileUnitExtension", "_spawn_linked_pickup_projectile", function(func, self, pickup_name, ...)
	if _is_our_pickup(pickup_name) then
		_dbg("[cwv stick:trace] _spawn_linked_pickup_projectile fired (pickup=%s)", tostring(pickup_name))
	end
	local disposition, safe = _om._tj_pickup_disposition(pickup_name)
	if disposition == _om.thrown_wire_policy.DROP then
		printf("[cwv:424] linked pickup DROPPED %s (no exact row and no proven vanilla donor)", tostring(pickup_name))
		return
	elseif disposition == _om.thrown_wire_policy.SUBSTITUTE then
		printf("[cwv:424] linked pickup wire-safe %s -> %s", tostring(pickup_name), tostring(safe))
		return func(self, safe, ...)
	end
	return func(self, pickup_name, ...)
end)

-- Path B entry on thrower's side — trace + issue 424 wire-safe substitution.
-- Encodes pickup_name_id (+ pickup-unit husk id, already vanilla) and sends
-- rpc_spawn_pickup_projectile (player_projectile_unit_extension.lua:1376-1395).
mod:hook("PlayerProjectileUnitExtension", "_spawn_pickup_projectile", function(func, self, pickup_name, ...)
	if _is_our_pickup(pickup_name) then
		_dbg("[cwv stick:trace] _spawn_pickup_projectile (PATH B) fired (pickup=%s)", tostring(pickup_name))
	end
	local disposition, safe = _om._tj_pickup_disposition(pickup_name)
	if disposition == _om.thrown_wire_policy.DROP then
		printf("[cwv:424] dropped pickup SUPPRESSED %s (no exact row and no proven vanilla donor)", tostring(pickup_name))
		return
	elseif disposition == _om.thrown_wire_policy.SUBSTITUTE then
		printf("[cwv:424] dropped pickup wire-safe %s -> %s", tostring(pickup_name), tostring(safe))
		return func(self, safe, ...)
	end
	return func(self, pickup_name, ...)
end)
_om._tj_pickup_wire_hook_installed = true

-- issue 424 (BUG_CLASSES 31): in-flight projectile husk / projectile_units axis.
-- The Tuskgor Javelin BOMB throws a boar-spear in-flight unit that is a cwv-only
-- NetworkLookup.husks key; ProjectileSystem.spawn_player_projectile spawns it via
-- spawn_network_unit (projectile_system.lua:247-249), and the same cwv
-- projectile_units_template rides TransientPackageLoader.hot_join_sync
-- (transient_package_loader.lua:187-193). Substitute the resolved projectile_units
-- (returned by _get_projectile_units_names, projectile_system.lua:159-176) to the
-- vanilla "javelin" entry so the projectile GameObject encodes a vanilla husk and
-- the transient sync encodes a vanilla projectile_units index; a joining/present
-- non-cwv peer never cold-decodes an appended index. Cosmetic only (in-flight mesh
-- becomes the slim vanilla javelin); the action's impact_data/damage are untouched.
-- Sole cwv hook on this method (grep-verified). Ungateable pure swap.
mod:hook("ProjectileSystem", "_get_projectile_units_names", function(func, self, projectile_info, owner_unit)
	return _om._wire_safe_projectile_units(func(self, projectile_info, owner_unit))
end)
_om._projectile_wire_hook_installed = true

-- Path A server-side: PickupSystem.rpc_spawn_linked_pickup.
mod:hook("PickupSystem", "rpc_spawn_linked_pickup", function(func, self, channel_id, pickup_name_id, link_position, link_rotation, spawn_type_id, hit_unit_go_id, node_index, is_level_unit, spawn_limit, material_settings_name_id)
	local pickup_name = NetworkLookup and NetworkLookup.pickup_names and rawget(NetworkLookup.pickup_names, pickup_name_id)
	if _is_our_pickup(pickup_name) then
		_dbg("[cwv stick] PATH A rpc_spawn_linked_pickup fired (pickup=%s)", tostring(pickup_name))
		_log_quat("  input ", link_rotation)
		local cleaned, ok = _clean_horizontal_rotation(link_rotation)
		if ok then link_rotation = cleaned; _log_quat("  output", link_rotation)
		else _dbg("  forward is near-vertical; skipping correction") end
	end
	return func(self, channel_id, pickup_name_id, link_position, link_rotation, spawn_type_id, hit_unit_go_id, node_index, is_level_unit, spawn_limit, material_settings_name_id)
end)

-- Path B server-side: ProjectileSystem.rpc_spawn_pickup_projectile (DIFFERENT
-- class than PickupSystem). Pickup has physics so it bounces/lands rather
-- than sticking; align rotation with velocity for a sensible resting pose.
mod:hook("ProjectileSystem", "rpc_spawn_pickup_projectile", function(func, self, channel_id, projectile_unit_name_id, projectile_unit_template_name_id, network_position, network_rotation, network_velocity, network_angular_velocity, pickup_name_id, pickup_spawn_type_id, spawn_limit, always_show, objective_active, material_settings_name_id)
	local pickup_name = NetworkLookup and NetworkLookup.pickup_names and rawget(NetworkLookup.pickup_names, pickup_name_id)
	if _is_our_pickup(pickup_name) then
		_dbg("[cwv stick] PATH B rpc_spawn_pickup_projectile fired (pickup=%s)", tostring(pickup_name))
		local vel = AiAnimUtils.velocity_network_scale(network_velocity)
		if vel and Vector3.length(vel) > 0.1 then
			local fwd = Vector3.normalize(vel)
			local cleaned = Quaternion.look(fwd, Vector3.up())
			network_rotation = AiAnimUtils.rotation_network_scale(cleaned, true)
			_log_quat("  velocity-aligned", cleaned)
		end
	end
	return func(self, channel_id, projectile_unit_name_id, projectile_unit_template_name_id, network_position, network_rotation, network_velocity, network_angular_velocity, pickup_name_id, pickup_spawn_type_id, spawn_limit, always_show, objective_active, material_settings_name_id)
end)

-- v0.1.248: parent→visual map for the outline mirror hook below. Weak keys so
-- entries auto-clear when a parent unit gets GC'd without _detach firing.
local _carrier_visuals = setmetatable({}, { __mode = "k" })

-- Carrier-unit pattern (v0.1.164, hook target fixed in v0.1.172): when our
-- pickup spawns (the throwing axe pup unit — chosen for its baked-in
-- interaction collision actors), spawn the boar spear _3p mesh as a visual
-- on top, link it to the parent's transform so it follows wall-stuck
-- position/rotation, and shrink the parent to near-zero scale so only the
-- boar spear is visible.
--
-- v0.1.172 fix: hook target was `PickupUnitExtension` (base class) and
-- silently never fired. Per memory `feedback_vt2_class_hook_derived.md`,
-- VT2's class() copies methods into derived classes at definition time, so
-- a hook on the base never fires for derived-class instances. Our pickup
-- uses `unit_template_name = "limited_owned_pickup_unit"` which instantiates
-- `LimitedOwnedPickupUnitExtension`. Hook the derived class instead, plus
-- the two siblings as cheap insurance for future variants.
local function _attach_carrier_visual(self)
	if not _is_our_pickup(self.pickup_name) then return end
	local parent = self.unit
	if not parent then return end
	_dbg("[cwv stick] extensions_ready fired (pickup=%s)", tostring(self.pickup_name))

	-- Clean rotation — orient the parent so the spear visual hangs off it
	-- pointing into the wall.
	local current_rot = Unit.world_rotation(parent, 0)
	local cleaned, did_clean = _clean_horizontal_rotation(current_rot)
	if did_clean then
		Unit.set_local_rotation(parent, 0, cleaned)
	end

	-- Spawn boar spear visual at parent's pose, pulled back along the
	-- forward (into-wall) axis so the spear doesn't sit too deep in the
	-- geometry. See _TJ_VISUAL_PULL_BACK_M for the offset.
	local world = self.world or (Managers.world and Managers.world:world("level_world"))
	if not world then return end
	local pos = Unit.world_position(parent, 0)
	local rot = Unit.world_rotation(parent, 0)
	if _TJ_VISUAL_PULL_BACK_M and _TJ_VISUAL_PULL_BACK_M ~= 0 then
		local fwd = Quaternion.forward(rot)
		pos = pos - fwd * _TJ_VISUAL_PULL_BACK_M
	end
	local ok_spawn, visual = pcall(World.spawn_unit, world, _TJ_BOAR_SPEAR_UNIT, pos, rot)
	if not ok_spawn or not visual then
		mod:warning("[cwv stick] failed to spawn boar spear visual: %s", tostring(visual))
		return
	end

	-- v0.1.175: do NOT link visual to parent. World.link_unit composes the
	-- child's transform with the parent's, so shrinking the parent to 0.001
	-- scale (below) made the boar spear inherit that scale and disappear
	-- too. For our use case the pickup is static (link_pickup attaches it
	-- to a wall via projectile_linker_system, parent doesn't move after
	-- spawn), so the visual doesn't need to track the parent. Spawn at
	-- parent's pose once, leave as free-standing world unit at scale 1.0.
	-- Edge case: javelins stuck in moving enemies won't have visual follow;
	-- revisit if that materializes in practice.

	-- v0.1.183: switched from scale-to-tiny hide to Unit.set_unit_visibility.
	-- Scale-to-0.001 also shrunk the OutlineExtension's silhouette target,
	-- killing the white tagged-pickup outline. Visibility is a render flag
	-- independent of physics — actors still detect interaction, mesh isn't
	-- drawn, and the outline shader may still compute on the hidden mesh
	-- (the shader's target rect is per-unit metadata, not directly tied to
	-- the rendered pass). If the outline is STILL missing after this change,
	-- the OutlineExtension genuinely needs a visible mesh and we'll need to
	-- attach it to the boar spear visual instead.
	pcall(Unit.set_unit_visibility, parent, false)

	self._cwv_visual_unit = visual
	self._cwv_world       = world
	_carrier_visuals[parent] = visual
	_dbg("[cwv stick] carrier visual attached: parent=%s child=%s", tostring(_TJ_PICKUP_UNIT), tostring(_TJ_BOAR_SPEAR_UNIT))
end

local function _detach_carrier_visual(self)
	if self.unit then _carrier_visuals[self.unit] = nil end
	if not self._cwv_visual_unit then return end
	local visual = self._cwv_visual_unit
	self._cwv_visual_unit = nil
	if Managers and Managers.state and Managers.state.unit_spawner then
		pcall(function() Managers.state.unit_spawner:mark_for_deletion(visual) end)
	elseif self._cwv_world then
		pcall(World.destroy_unit, self._cwv_world, visual)
	end
end

-- v0.1.248: mirror outline_unit calls from parent (hidden) → visual.
-- Why: `Unit.set_unit_visibility(parent, false)` (the hide path used by the
-- carrier pattern since v0.1.190) excludes the parent from every render pass,
-- including the outline pass. Tagged-pickup outlines stopped showing because
-- the engine outlines the parent throwing-axe unit, not our visual boar
-- spear. Forwarding every outline_unit call onto the visual gives it the
-- same outline state without needing the parent visible.
mod:hook("OutlineSystem", "outline_unit", function(func, self, unit, flag, channel, do_outline, apply_method, outline_settings)
	local visual = _carrier_visuals[unit]
	if visual and Unit.alive(visual) then
		pcall(func, self, visual, flag, channel, do_outline, apply_method, outline_settings)
	end
	return func(self, unit, flag, channel, do_outline, apply_method, outline_settings)
end)

mod:hook_safe("LimitedOwnedPickupUnitExtension", "extensions_ready", _attach_carrier_visual)
mod:hook_safe("LifeTimePickupUnitExtension",     "extensions_ready", _attach_carrier_visual)
mod:hook_safe("PlayerTeleportingPickupExtension","extensions_ready", _attach_carrier_visual)
mod:hook_safe("LimitedOwnedPickupUnitExtension", "destroy",          _detach_carrier_visual)
mod:hook_safe("LifeTimePickupUnitExtension",     "destroy",          _detach_carrier_visual)
mod:hook_safe("PlayerTeleportingPickupExtension","destroy",          _detach_carrier_visual)

-- Linker-extension branch (rare).
mod:hook("ProjectileLinkerSystem", "link_pickup", function(func, self, pickup_unit, link_position, link_rotation, hit_unit, node_index)
	local ok, pickup_name = pcall(Unit.get_data, pickup_unit, "pickup_name")
	if ok and _is_our_pickup(pickup_name) then
		_dbg("[cwv stick] link_pickup fired (linker-extension branch, pickup=%s)", tostring(pickup_name))
		_log_quat("  input ", link_rotation)
		local cleaned, did = _clean_horizontal_rotation(link_rotation)
		if did then link_rotation = cleaned; _log_quat("  output", link_rotation) end
	end
	return func(self, pickup_unit, link_position, link_rotation, hit_unit, node_index)
end)

local function _clone_inline_throw_profile(source_name, prefix, damage_mult)
	if not DamageProfileTemplates then return source_name end
	local source = DamageProfileTemplates[source_name]
	if not source then return source_name end

	local new_name = prefix .. source_name
	_om._record_cwv_dp_source(new_name, source_name)   -- issue 423 wire-safe map
	if DamageProfileTemplates[new_name] then return new_name end

	local clone = table.clone(source, true)

	-- thrown_javelin shape (verified against
	-- damage_profile_templates_dlc_woods.lua:263): default_target carries
	-- power_distribution_near / power_distribution_far, each with .attack
	-- (damage) and .impact (stagger). We multiply only .attack so "double
	-- damage" doesn't accidentally amp stagger too. Also handle the generic
	-- power_distribution case in case a future thrown profile uses it.
	local function scale_target(target)
		if type(target) ~= "table" then return end
		if target.power_distribution_near and target.power_distribution_near.attack then
			target.power_distribution_near.attack = target.power_distribution_near.attack * damage_mult
		end
		if target.power_distribution_far and target.power_distribution_far.attack then
			target.power_distribution_far.attack = target.power_distribution_far.attack * damage_mult
		end
		if target.power_distribution and target.power_distribution.attack then
			target.power_distribution.attack = target.power_distribution.attack * damage_mult
		end
	end

	scale_target(clone.default_target)
	if type(clone.targets) == "table" then
		for _, t in ipairs(clone.targets) do scale_target(t) end
	end

	DamageProfileTemplates[new_name] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, new_name) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, new_name)
		rawset(tbl, new_name, idx)
	end

	return new_name
end

-- Module-scope so it can't be re-created per call (Lua closure identity matters
-- for VMF hook bookkeeping, and the function is small enough to share).
local function _always_false() return false end

-- 3P body wield routing for Tuskgor Javelin (Kruber + Saltzpyre variants).
-- Each character body has a different "spear+shield" sub-graph in its master SM:
--   * Kruber  (empire-soldier 3P body): es_deus_01 — Empire Chaos Wastes spear+shield
--   * Saltzpyre wh_captain/bountyhunter/zealot (witch-hunter 3P body): no native
--     spear+shield SM, falls back to 1h_sword_shield (closest in-stance analog)
--   * Saltzpyre wh_priest: native 1h_hammer_shield (warrior priest stance)
-- Mappings sourced from weapon_tweaker.lua's _career_anim_redirect / _suffix_career_map
-- which already encodes the cross-character spear+shield routing rules.
local _tj_wield_3p_by_career = {
	es_mercenary      = "to_es_deus_01",
	es_huntsman       = "to_es_deus_01",
	es_knight         = "to_es_deus_01",
	es_questingknight = "to_es_deus_01",
	wh_captain        = "to_1h_sword_shield",
	wh_bountyhunter   = "to_1h_sword_shield",
	wh_zealot         = "to_1h_sword_shield",
	wh_priest         = "to_1h_hammer_shield",
}

-- 3P body event remap for Tuskgor Javelin. Routes the elf javelin template's
-- action events to events that are commonly authored across es_deus_01,
-- 1h_sword_shield, AND 1h_hammer_shield — so the same anim_event_3p plays
-- visibly regardless of which sub-graph the body wielded into. Verified
-- against the source templates: attack_swing_stab, attack_swing_charge_stab,
-- attack_swing_heavy_stab, attack_swing_heavy_left, attack_push, parry_pose
-- all appear in 1h_swords_shield.lua, es_deus_01.lua, and dual_wield_hammers_priest
-- families (the priest hammer+shield template uses these too).
--
-- TRADE-OFF: shield-stance SMs are MELEE-ONLY. attack_throw and throw_charge
-- have no equivalent — body stands still during the throw windup/release while
-- the projectile system fires the javelin from 1P. Throw mechanics still work
-- (projectile spawn / damage / pickup are separate from the 3P clip); just no
-- visible body throw motion. Same for `reload`. User-accepted trade vs.
-- keeping the elf javelin SM (which may not be authored on Kruber/Saltzpyre
-- 3P bodies, leading to silent wield failure).
--
-- 1P UNCHANGED: the source javelin SM remains the 1P state_machine and handles
-- all 1P playback (including throw windup) correctly via first_person_base.
local _tj_anim_remap = {
	-- Light combo chain: 3-step stab progression
	attack_chain_01          = "attack_swing_stab",
	attack_chain_02          = "attack_swing_heavy_left",   -- left-side strike for variety
	attack_chain_03          = "attack_swing_heavy_stab",   -- combo finisher
	-- Directional lights → stab-flavored events
	attack_swing_left        = "attack_swing_heavy_left",
	attack_swing_right       = "attack_swing_stab",
	attack_swing_up          = "attack_swing_heavy_stab",
	-- Charges/heavy stabs
	attack_swing_charge      = "attack_swing_charge_stab",
	attack_swing_stab_charge = "attack_swing_charge_stab",
	attack_swing_stab_02     = "attack_swing_heavy_stab",
	-- attack_swing_stab unchanged (universal across all three target SMs)
	-- attack_throw, throw_charge, reload: deliberately not remapped — see header
}

-- Careers that need the base-template wield-patch for the inventory previewer
-- (HeroPreviewer reads BASE javelin_template, not our clone — same pattern as
-- elven_sword_shield and imperial_dual_swords). Same set as the keys of
-- _tj_wield_3p_by_career, but kept ordered for the loop.
local _tj_kruber_saltzpyre_careers = {
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
	"wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
}

-- ANIM ADDENDUM: this function only touches stats + (eventually) 3P fields.
-- 1P is universal across characters — see top-of-file ANIMATION ARCHITECTURE.
local function _create_tuskgor_javelin_template()
	if not Weapons or not Weapons.javelin_template then
		mod:warning("javelin_template not found — Tuskgor Javelin stat modifications unavailable")
		return
	end
	if Weapons.tuskgor_javelin_template then return end

	local template = table.clone(Weapons.javelin_template, true)

	-- Ammo system rewrite: finite stack, vanilla pickups refill.
	if template.ammo_data then
		template.ammo_data.max_ammo            = _TJ_MAX_AMMO
		template.ammo_data.block_ammo_pickup   = false
		template.ammo_data.unique_ammo_type    = false
		-- Keep ammo_per_clip / ammo_per_reload at 1 (vanilla) — those control
		-- how many javelins are "drawn" per reload anim, not pickup behaviour.
	end

	-- Disable the magic auto-catch reload (vanilla refills on-demand).
	if template.actions.weapon_reload and template.actions.weapon_reload.default then
		template.actions.weapon_reload.default.condition_func       = _always_false
		template.actions.weapon_reload.default.chain_condition_func = _always_false
	end

	-- Half throw speed: extend wind-up before the projectile fires.
	if template.attack_meta_data and template.attack_meta_data.minimum_charge_time then
		template.attack_meta_data.minimum_charge_time =
			template.attack_meta_data.minimum_charge_time * (1 / _TJ_SPEED_MULT)
	end

	for _, action_group in pairs(template.actions) do
		if type(action_group) == "table" then
			for _, sub_action in pairs(action_group) do
				if type(sub_action) == "table" then
					-- anim_time_scale (mostly a no-op for javelin — kept for parity
					-- with the other template clones in case a sub-action does set it)
					if sub_action.anim_time_scale then
						sub_action.anim_time_scale = sub_action.anim_time_scale * _TJ_SPEED_MULT
					end
					-- Slow the throw action: total_time + minimum_hold_time.
					-- fire_time stays put — moving it would desync the projectile
					-- spawn point on the animation.
					if sub_action.kind == "thrown_projectile" then
						if sub_action.total_time and sub_action.total_time ~= math.huge then
							sub_action.total_time = sub_action.total_time * (1 / _TJ_SPEED_MULT)
						end
						if sub_action.minimum_hold_time then
							sub_action.minimum_hold_time = sub_action.minimum_hold_time * (1 / _TJ_SPEED_MULT)
						end
						-- Projectile flight speed (sub_action.speed) — slower in-air
						-- velocity. Distinct from the action timing fields above:
						-- those control wind-up/recovery, this controls how fast the
						-- thrown javelin actually travels.
						if sub_action.speed then
							sub_action.speed = sub_action.speed * _TJ_PROJECTILE_SPEED_MULT
						end
						-- Throwing-axe-style stick + pickup. Vanilla javelin uses
						-- `link = true` + `wall_nail = true` + `flow_event_on_walls
						-- = "teleport_out"` (the magic auto-recall behavior). Strip
						-- those and replace with the throwing-axe combo:
						-- `link_pickup = true` + `pickup_settings = {...}`. The
						-- engine then spawns a pickup on the stuck projectile that
						-- the player can walk up to and grab for +1 ammo.
						-- Reference: 1h_throwing_axes.lua:80-89 / 163-172.
						if sub_action.impact_data then
							local imp = sub_action.impact_data
							imp.link                  = nil
							imp.wall_nail             = nil
							imp.flow_event_on_init    = nil
							imp.flow_event_on_walls   = nil
							imp.link_pickup           = true
							imp.no_stop_on_friendly_fire = true
							imp.pickup_settings       = {
								use_weapon_skin = true,
								link_hit_zones  = { "head", "neck", "torso" },
							}
							-- v0.1.123: vanilla javelin depth = 0.7 buries most of
							-- the spear shaft in the wall; user reports "sticks
							-- way too deep". Throwing axe uses 0.2; pick 0.25 for
							-- a long polearm so the tip + a bit of shaft penetrates
							-- while most of the shaft sticks out.
							imp.depth                 = 0.25
							imp.depth_offset          = -0.2
						end
					end
					-- Melee stab damage profiles use the PowerLevelTemplates
					-- string-key indirection — existing helper handles those.
					if sub_action.damage_profile then
						sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_tj_", {
							damage = _TJ_DAMAGE_MULT,
						})
					end
					-- Throw projectile damage profile is INLINE — needs the
					-- inline-clone helper, not the string-key one.
					if sub_action.impact_data and sub_action.impact_data.damage_profile then
						sub_action.impact_data.damage_profile = _clone_inline_throw_profile(
							sub_action.impact_data.damage_profile, "cwv_tj_", _TJ_DAMAGE_MULT
						)
					end
					-- 3P body anim remap: route elf javelin events to
					-- 1h_spear_shield-vocab events so Kruber/Saltzpyre's
					-- 3P bodies play visible spear stabs for the melee combo.
					-- Throw/reload events deliberately not remapped — see
					-- _tj_anim_remap header for rationale.
					if sub_action.anim_event and _tj_anim_remap[sub_action.anim_event] then
						sub_action.anim_event_3p = _tj_anim_remap[sub_action.anim_event]
					end
				end
			end
		end
	end

	-- 3P wield: route each cwv-javelin career into its character body's native
	-- spear+shield sub-graph (or closest analog for Saltzpyre, which has no
	-- native spear+shield SM). Elf careers (we_*) wielding the vanilla
	-- we_javelin keep their native to_javelin wield because we patch only
	-- the cwv-using careers below.
	template.wield_anim_3p = "to_es_deus_01"  -- default for unrecognised careers
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for career, wield in pairs(_tj_wield_3p_by_career) do
		template.wield_anim_career_3p[career] = wield
	end

	Weapons.tuskgor_javelin_template = template

	-- BASE TEMPLATE PATCH: HeroPreviewer (inventory character preview) reads
	-- the base javelin_template's wield_anim_career_3p, NOT our clone's, so
	-- the menu preview pose follows the vanilla javelin wield unless we
	-- patch the base. Scoped tightly to Kruber + Saltzpyre careers so elf
	-- careers fall through to the original wield_anim. Same pattern as
	-- _create_imperial_dual_swords_template / _create_elven_sword_shield_template.
	local base = Weapons.javelin_template
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for career, wield in pairs(_tj_wield_3p_by_career) do
			base.wield_anim_career_3p[career] = wield
		end
	end
	mod:info("Created tuskgor_javelin_template (max_ammo=%d, ammo_pickups=on, no auto-catch, link_pickup stick, %.0f%% dmg, %.0f%% action speed, %.0f%% projectile speed, 3p wield=es_*->to_es_deus_01, wh_*->to_1h_sword_shield, wh_priest->to_1h_hammer_shield)",
		_TJ_MAX_AMMO, _TJ_DAMAGE_MULT * 100, _TJ_SPEED_MULT * 100, _TJ_PROJECTILE_SPEED_MULT * 100)
end

_register_tuskgor_javelin_assets()
_create_tuskgor_javelin_template()

-- ============================================================================
-- issue 424: fail-closed mixed-lobby Tuskgor Javelin feature gate.
-- ORDER MATTERS: the exact thrown channel must exist before the gate installs,
-- because gate_state() reads mod._cwv_thrown_wire_safe. Both run AFTER
-- _register_tuskgor_javelin_assets so every appended row is capturable.
_om.exact_wire_runtime.install_thrown(mod, _om, _G, _om._TJ_WIRE_SPEC)
_om.javelin_gate.install({
	mod = mod,
	om = _om,
	pickup_key = _TJ_PICKUP_KEY,
	link_pickup_key = _TJ_LINK_PICKUP_KEY,
	projectile_key = _TJ_PROJECTILE_KEY,
	inflight_unit = _TJ_BOAR_SPEAR_UNIT,
	safe_template_key = _om._TJ_INFLIGHT_SAFE_TEMPLATE,
	wire_safe = mod._cwv_thrown_wire_safe,
	catalog_intact = mod._cwv_thrown_catalog_intact,
	donor_policy = _om.thrown_wire_policy,
	globals = _G,
})

-- ============================================================================
-- Tuskgor Javelin (BOMB SLOT) — single-use thrown spear "grenade"  (v0.1.352-dev)
-- ============================================================================
-- A NEW archetype for CWV: an item that lives in slot_grenade (the bomb slot)
-- rather than a backend weapon slot. It is acquired via a NEW grenade pickup
-- injected into Pickups.grenades — it does NOT replace frag/fire bombs, it just
-- joins the bomb-pickup pool that can spawn in every game mode.
--
-- BEHAVIOUR (per user 2026-06-29): NOT a bomb. It is the literal javelin throw
-- in the grenade slot — a single straight-flying spear that:
--   * pierces ARMOUR  (damage profile armor_modifier raised across the board)
--   * penetrates SEVERAL enemies in a line: cleave_distribution drives the
--     projectile's _max_mass (player_projectile_unit_extension.lua get_max_targets),
--     so the spear keeps travelling until cumulative enemy mass is spent, THEN
--     links/sticks (link/wall_nail).
--   * goes through SHIELDS  (thrown_javelin damage profile shield_break = true)
--   * high damage to MONSTERS + on HEADSHOT (power scale + headshot boost curve)
--   * single use (ammo_data.max_ammo = 1, destroy_when_out_of_ammo = true)
--
-- WHY it can't use the normal _variant_definitions path: slot_grenade items are
-- stored_in_backend = false, never equipped from the keep, and resolved via
-- ItemMasterList[key].temporary_template -> Weapons[name]. So it is registered
-- directly as ItemMasterList entry + Weapons template + Pickups.grenades entry,
-- NOT a MoreItemsLibrary backend item.
--
-- MECHANICS CONFIRMED (decompiled source, 2026-06-29):
--   * kind = "thrown_projectile" => ActionThrownProjectile is registered for
--     everyone (weapon_unit_extension.lua:101-106 merges every DLC's
--     action_classes_lookup; throwing axes ship with the game). It applies
--     DIRECT impact damage from impact_data.damage_profile with NO aoe / NO
--     explosion — unlike kind="charged_projectile" (vanilla grenades) which
--     always explodes.
--   * Pickup pool: pickup_system reads Pickups.grenades directly via weighted
--     random; AllPickups + NetworkLookup.pickup_names are built at boot, so a
--     post-boot mod entry must be mirrored in manually (same as the ranged
--     javelin's ammo pickups above). The grenade group is renormalised to sum
--     to 1.0 (guards the pickup-sampler total<1.0 crash class).
--   * MP: the equipped grenade syncs by item_name index (rpc_add_equipment ->
--     NetworkLookup.item_names); the husk (remote) view reads right_hand_unit
--     from the ItemMasterList entry; the HUD slot icon reads ItemMasterList.hud_icon.
--   * Mesh load: PickupPackageLoader._load_pickup preloads the temporary_template's
--     right/left_hand_unit (+_3p), so the boar spear loads automatically for the
--     pickup; its _3p IS the projectile unit, already husk-registered by
--     _register_tuskgor_javelin_assets above (ProjectileUnits "cwv_tuskgor_javelin").
--
-- Wrapped in do...end so its locals release back to the top-level chunk
-- (Lua 5.1 200-local limit — this file is large).
do
	local _TJB_TEMPLATE_NAME    = "cwv_tuskgor_javelin_bomb_template"
	local _TJB_ITEM_KEY         = "cwv_grenade_tuskgor_javelin"
	local _TJB_PICKUP_KEY       = "cwv_tuskgor_javelin_bomb"
	local _TJB_DAMAGE_PROFILE   = "cwv_tuskgor_javelin_bomb"
	local _TJB_PROJECTILE_INFO  = "cwv_tuskgor_javelin_bomb"
	-- Reuse the ranged javelin's boar-spear ProjectileUnits entry (registered +
	-- husk-injected by _register_tuskgor_javelin_assets above).
	local _TJB_PROJECTILE_UNITS = _TJ_PROJECTILE_KEY   -- "cwv_tuskgor_javelin"
	local _TJB_HELD_UNIT        = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01"
	-- Interim world-pickup model: the frag-bomb pickup unit (has interaction
	-- actors + is always loaded). A spear-shaped carrier pickup can replace this
	-- later (see the ranged javelin's throwing-axe-pup carrier pattern).
	local _TJB_PICKUP_UNIT      = "units/weapons/player/pup_grenades/pup_grenade_01_t1"
	local _TJB_SPAWN_SHARE      = 0.15   -- fraction of grenade-pool rolls that are the javelin
	local _TJB_DAMAGE_MULT      = 2.5
	local _TJB_DEPTH            = 1.5
	local _TJB_CLEAVE           = 2.5
	local _TJB_HEADSHOT_BOOST   = 3.0
	local _TJB_THROW_SPEED      = 5000

	-- Feature master switch (declared HERE, above every register/inject function,
	-- so all of them capture it as an upvalue -- a local declared below them would
	-- be invisible to the closures and silently resolve to a nil global).
	--
	-- ⚠ TEMPORARILY DISABLED (v0.1.354-dev) — REGRESSION TRIAGE.
	-- After this bomb-slot block was added (v0.1.352/.353), the user reported
	-- that ALL CWV variant weapons stopped appearing (musket, dual axes,
	-- axe+shield, etc.). The 23.56 log shows the mod loading fully with NO
	-- registration error, so the cause is a global side-effect of running this
	-- block at file load (suspects: NetworkLookup.item_names injection, the
	-- Pickups.grenades renormalise, or the javelin_template clone). Guarded OFF
	-- to restore content immediately; if content returns with this off, the
	-- cause is confirmed here and the feature is re-introduced surgically. This
	-- is SEPARATE from the peer-parity gate below (issue 371): the gate governs
	-- WHEN the pool injects in a mixed lobby; this switch governs WHETHER the
	-- feature exists at all while the load-time regression is unresolved.
	local _TJB_FEATURE_ON = false

	-- 1. Damage profile — buffed thrown_javelin (armour pierce, multi-pierce,
	--    monster + headshot damage; keeps shield_break). Deep-cloned so the
	--    vanilla thrown_javelin (used by the ranged javelin + Kerillian) is
	--    untouched.
	local function _register_profile()
		if not DamageProfileTemplates then return end
		if DamageProfileTemplates[_TJB_DAMAGE_PROFILE] then return end
		local source = DamageProfileTemplates.thrown_javelin
		if not source then
			mod:warning("thrown_javelin damage profile missing — bomb javelin unavailable")
			return
		end
		local p = table.clone(source, true)
		p.shield_break = true
		local function bump_armor(m)
			if m and m.attack then
				for i = 1, #m.attack do m.attack[i] = math.max(m.attack[i], 1.5) end
			end
		end
		bump_armor(p.armor_modifier_near)
		bump_armor(p.armor_modifier_far)
		p.cleave_distribution = p.cleave_distribution or {}
		p.cleave_distribution.attack = _TJB_CLEAVE
		p.cleave_distribution.impact = _TJB_CLEAVE
		if p.default_target then
			p.default_target.boost_curve_coefficient_headshot = _TJB_HEADSHOT_BOOST
			local function scale(t) if t and t.attack then t.attack = t.attack * _TJB_DAMAGE_MULT end end
			scale(p.default_target.power_distribution_near)
			scale(p.default_target.power_distribution_far)
			scale(p.default_target.power_distribution)
		end
		DamageProfileTemplates[_TJB_DAMAGE_PROFILE] = p
		if NetworkLookup and NetworkLookup.damage_profiles
			and not rawget(NetworkLookup.damage_profiles, _TJB_DAMAGE_PROFILE) then
			local tbl = NetworkLookup.damage_profiles
			local idx = #tbl + 1
			rawset(tbl, idx, _TJB_DAMAGE_PROFILE)
			rawset(tbl, _TJB_DAMAGE_PROFILE, idx)
		end
	end

	-- 2. Projectile — boar spear in flight (NOT the woods-DLC elf javelin unit,
	--    which isn't loaded for our item). Reuses the husk-registered boar-spear
	--    ProjectileUnits entry.
	local function _register_projectile()
		if not Projectiles or not Projectiles.javelin then
			mod:warning("Projectiles.javelin missing — bomb javelin projectile unavailable")
			return
		end
		if Projectiles[_TJB_PROJECTILE_INFO] then return end
		local p = table.clone(Projectiles.javelin, true)
		p.projectile_units_template = _TJB_PROJECTILE_UNITS
		p.use_weapon_skin = false
		Projectiles[_TJB_PROJECTILE_INFO] = p
	end

	-- 3. Weapon template — the JAVELIN moveset (melee stabs + aimed throw) made
	--    into a ONE-SHOT consumable that lives in the grenade slot: full size,
	--    keeps the melee attacks, throwing it consumes it (destroy on out-of-ammo).
	--    Cloned from javelin_template (NOT the grenade template) so it carries the
	--    full action set + boot-populated lookup_data; the projectile resolves THIS
	--    template via our ItemMasterList entry's temporary_template
	--    (backend_interface_item.lua:770 reads temporary_template first), so no
	--    runtime template-swap hook is needed.
	local function _register_template()
		if not Weapons then return end
		if Weapons[_TJB_TEMPLATE_NAME] then return end
		local source = Weapons.javelin_template
		if not source then
			mod:warning("javelin_template missing — bomb javelin unavailable")
			return
		end
		local t = table.clone(source, true)

		-- Held mesh: boar spear, FULL SIZE (no scale override anywhere — the
		-- ranged variant's 0.80 shrink lives on the item def, which this item
		-- does not set).
		t.right_hand_unit = _TJB_HELD_UNIT
		t.left_hand_unit  = _TJB_HELD_UNIT

		-- One-shot: a single javelin, destroyed when thrown. No refill, no
		-- vanilla auto-catch recall.
		if t.ammo_data then
			t.ammo_data.max_ammo = 1
			t.ammo_data.ammo_per_clip = 1
			t.ammo_data.ammo_per_reload = 1
			t.ammo_data.block_ammo_pickup = true
			t.ammo_data.unique_ammo_type = false
			t.ammo_data.reload_on_ammo_pickup = false
			t.ammo_data.destroy_when_out_of_ammo = true
		end
		if t.actions and t.actions.weapon_reload and t.actions.weapon_reload.default then
			local function _false() return false end
			t.actions.weapon_reload.default.condition_func = _false
			t.actions.weapon_reload.default.chain_condition_func = _false
		end

		-- Walk sub-actions: buff the melee stabs, and rewrite the throw to the
		-- buffed boar-spear projectile (direct impact, multi-pierce, no recovery —
		-- it sticks where it lands and is gone).
		for _, action_group in pairs(t.actions) do
			if type(action_group) == "table" then
				for _, sub in pairs(action_group) do
					if type(sub) == "table" then
						-- Melee stab damage (string-key profiles) — buff to match.
						if sub.kind == "sweep" and sub.damage_profile then
							sub.damage_profile = _clone_damage_profile(sub.damage_profile, "cwv_tjb_", { damage = _TJB_DAMAGE_MULT })
						end
						-- The throw (kind = "thrown_projectile").
						if sub.kind == "thrown_projectile" then
							sub.speed = _TJB_THROW_SPEED
							sub.projectile_info = Projectiles[_TJB_PROJECTILE_INFO] or sub.projectile_info
							sub.impact_data = {
								damage_profile = (DamageProfileTemplates[_TJB_DAMAGE_PROFILE] and _TJB_DAMAGE_PROFILE) or "thrown_javelin",
								depth = _TJB_DEPTH,
								depth_damage_modifier_min = 1,
								depth_damage_modifier_max = 1.2,
								depth_offset = -0.2,
								link = true,
								wall_nail = true,
								no_stop_on_friendly_fire = true,
								flow_event_on_init = "link_projectile_show",
								flow_event_on_walls = "teleport_out",
							}
						end
					end
				end
			end
		end

		Weapons[_TJB_TEMPLATE_NAME] = t
		mod:info("Created %s (javelin moveset, one-shot, full size, slot_grenade)", _TJB_TEMPLATE_NAME)
	end

	-- 4. ItemMasterList entry + NetworkLookup.item_names (MP equip sync). Husk
	--    view reads right_hand_unit here; HUD slot icon reads hud_icon here.
	local function _register_item()
		if not ItemMasterList then return end
		if rawget(ItemMasterList, _TJB_ITEM_KEY) then return end
		rawset(ItemMasterList, _TJB_ITEM_KEY, {
			name = _TJB_ITEM_KEY,
			key = _TJB_ITEM_KEY,
			description = "cwv_grenade_tuskgor_javelin_description",
			display_name = "cwv_grenade_tuskgor_javelin_name",
			gamepad_hud_icon = "hud_icon_bomb_01",
			hud_icon = "hud_inventory_icon_bomb",
			inventory_icon = "icons_placeholder",
			is_local = true,
			item_type = "grenade",
			right_hand_unit = _TJB_HELD_UNIT,   -- husk (remote) view reads this
			rarity = "exotic",
			slot_type = "grenade",
			temporary_template = _TJB_TEMPLATE_NAME,
			can_wield = CanWieldAllItemTemplates,
		})
		if NetworkLookup and NetworkLookup.item_names
			and not rawget(NetworkLookup.item_names, _TJB_ITEM_KEY) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, _TJB_ITEM_KEY)
			rawset(tbl, _TJB_ITEM_KEY, idx)
		end
	end

	-- 5. Pickup settings + resolve-by-name lookups. Registered UNCONDITIONALLY so
	--    every peer can resolve a host-spawned pickup even if their own toggle is
	--    off. AllPickups + Pickups.grenades share the same settings object (as
	--    vanilla does).
	local _pickup_settings = {
		bots_mule_pickup = true,
		consumable_item = true,
		debug_pickup_category = "grenades",
		dupable = true,
		hud_description = "cwv_tuskgor_javelin_bomb",
		individual_pickup = false,
		item_description = "cwv_tuskgor_javelin_bomb",
		item_name = _TJB_ITEM_KEY,
		local_pickup_sound = true,
		only_once = true,
		pickup_sound_event = "pickup_grenade",
		slot_name = "slot_grenade",
		type = "inventory_item",
		unit_name = _TJB_PICKUP_UNIT,
		pickup_name = _TJB_PICKUP_KEY,
		spawn_weighting = 0,   -- set during pool injection (step 6)
	}
	local function _register_pickup_lookups()
		if AllPickups and not AllPickups[_TJB_PICKUP_KEY] then
			AllPickups[_TJB_PICKUP_KEY] = _pickup_settings
		end
		if NetworkLookup and NetworkLookup.pickup_names
			and not rawget(NetworkLookup.pickup_names, _TJB_PICKUP_KEY) then
			local tbl = NetworkLookup.pickup_names
			local idx = #tbl + 1
			rawset(tbl, idx, _TJB_PICKUP_KEY)
			rawset(tbl, _TJB_PICKUP_KEY, idx)
		end
	end

	-- 6. Pool membership — add to Pickups.grenades + renormalise the group to sum
	--    to 1.0. Gated on the local toggle (the host's pool decides what spawns in
	--    their game; clients still resolve via step 5). Runs once (existence guard).
	local function _inject_pool()
		-- Master switch first: with the feature OFF the register functions never
		-- ran, so there is no backing template/ItemMasterList/NetworkLookup entry
		-- and injecting a pool member would spawn an unregistered pickup. The
		-- peer-parity gate calls this as its on_enable, so this guard also keeps
		-- the gate inert while the load-time regression triage is unresolved.
		if not _TJB_FEATURE_ON then return end
		if not Pickups or not Pickups.grenades then return end
		if Pickups.grenades[_TJB_PICKUP_KEY] then return end
		local enabled = true
		local ok, v = pcall(function() return mod:get("enable_cwv_tuskgor_javelin_bomb") end)
		if ok and v == false then enabled = false end
		if not enabled then
			mod:info("Tuskgor Javelin bomb disabled by setting — not added to the grenade pool")
			return
		end
		-- Pre-renorm raw weight so the final normalised share ~= _TJB_SPAWN_SHARE
		-- (the other entries were already normalised to sum ~1.0 at boot).
		_pickup_settings.spawn_weighting = _TJB_SPAWN_SHARE / (1 - _TJB_SPAWN_SHARE)
		Pickups.grenades[_TJB_PICKUP_KEY] = _pickup_settings
		local total = 0
		for _, s in pairs(Pickups.grenades) do total = total + (s.spawn_weighting or 0) end
		if total > 0 then
			for _, s in pairs(Pickups.grenades) do
				s.spawn_weighting = (s.spawn_weighting or 0) / total
			end
		end
		mod:info("Injected '%s' into the grenade pickup pool (share ~%.0f%%)", _TJB_PICKUP_KEY, _TJB_SPAWN_SHARE * 100)
	end

	-- Peer-parity on_disable: pull the bomb back OUT of the grenade pool and
	-- renormalise the remaining entries to sum ~1.0, so a lobby with a non-cwv
	-- peer never has the modded pickup rolled into the world (issue 371/424:
	-- the WORLD/pool pickup is the GAMEPLAY axis that cannot be wire-substituted).
	-- Idempotent: no-op when the bomb was never injected. Inject/eject cycles are
	-- stable -- eject restores the other entries to a ~1.0 sum and inject always
	-- resets the bomb's raw weight to the same pre-norm value.
	local function _eject_pool()
		if not Pickups or not Pickups.grenades then return end
		if not Pickups.grenades[_TJB_PICKUP_KEY] then return end
		Pickups.grenades[_TJB_PICKUP_KEY] = nil
		local total = 0
		for _, s in pairs(Pickups.grenades) do total = total + (s.spawn_weighting or 0) end
		if total > 0 then
			for _, s in pairs(Pickups.grenades) do
				s.spawn_weighting = (s.spawn_weighting or 0) / total
			end
		end
		mod:info("Ejected '%s' from the grenade pickup pool (peer-parity: a peer lacks cwv)", _TJB_PICKUP_KEY)
		-- #424: an already-spawned bomb is retracted by the javelin gate's on_disable.
	end

	-- Registration (UNCONDITIONAL when the feature is on -- class-31: registration
	-- parity is NEVER peer-gated; every peer that has cwv registers the same
	-- damage-profile / projectile / template / ItemMasterList / NetworkLookup /
	-- AllPickups indices). Only the pool INJECTION (what actually spawns in the
	-- world) is the gameplay axis, and that is gated by the peer-parity beacon
	-- below -- NOT called directly here. (_TJB_FEATURE_ON is the separate
	-- load-time-regression master switch declared at the top of this block.)
	if _TJB_FEATURE_ON then
		_register_profile()
		_register_projectile()
		_register_template()
		_register_item()
		_register_pickup_lookups()
	end

	-- Peer-parity gate for the WORLD/pool pickup injection (issue 371 / issue 424
	-- / BUG_CLASSES 31). Registered UNCONDITIONALLY (independent of
	-- _TJB_FEATURE_ON) so the gated-feature registry is populated for the
	-- regression suite; _inject_pool self-guards on _TJB_FEATURE_ON + the setting,
	-- so registering here is fully inert while the master switch is off. When the
	-- feature is on, the beacon calls _inject_pool once all peers are confirmed to
	-- have cwv and _eject_pool the moment one does not -- so a non-cwv client never
	-- has the modded grenade rolled into their world (which would CTD them on the
	-- server-authoritative rpc_spawn_pickup). The NetworkLookup/AllPickups/
	-- ItemMasterList registration above stays unconditional (registration parity
	-- is never gated); only this spawn/pool FEATURE gates.
	_om._TJB_REGISTRATION_UNGATED_MARKER = "cwv-tjb-networklookup-registration-never-peer-gated"
	-- #424: enrol the bomb in the javelin gate's world sweep (install() ran above).
	_om.javelin_gate.fence_pickup(_TJB_PICKUP_KEY)
	if mod._cwv_peer_parity and type(mod._cwv_peer_parity.register_gated_feature) == "function" then
		mod._cwv_peer_parity:register_gated_feature("cwv_tuskgor_javelin_bomb_pool", {
			label      = "cwv_gated_javelin_bomb_pool",
			on_enable  = function() _inject_pool() end,
			on_disable = function() _eject_pool() end,
		})
		mod:info("[cwv:371] gated 'cwv_tuskgor_javelin_bomb_pool' behind peer-parity beacon")
	end

	-- Test/grant command: drop the one-shot Tuskgor Javelin straight into the
	-- local player's bomb slot (bypasses the random pickup pool). Wield it with
	-- the grenade key, then melee-stab or aim+throw; throwing it consumes it.
	mod:command("cwv_give_javelin", "Give the single-use Tuskgor Javelin into your bomb slot", function()
		local player = Managers.player and Managers.player:local_player()
		local unit = player and player.player_unit
		if not (unit and Unit.alive(unit)) then mod:echo("[cwv] no local player unit (be in a level)"); return end
		local inv = ScriptUnit.has_extension(unit, "inventory_system")
		if not inv then mod:echo("[cwv] no inventory extension on player unit"); return end
		local item_data = rawget(ItemMasterList, _TJB_ITEM_KEY)
		if not item_data then mod:echo("[cwv] javelin-bomb item not registered"); return end
		-- The /give path bypasses PickupPackageLoader, which normally preloads the
		-- temporary_template's held + _3p (projectile) units — force-load them so
		-- the held mesh + thrown projectile don't spawn an unloaded unit.
		if Managers.package then
			pcall(function() Managers.package:load(_TJB_HELD_UNIT, "cwv_javelin_bomb", nil, true, true) end)
			pcall(function() Managers.package:load(_TJB_HELD_UNIT .. "_3p", "cwv_javelin_bomb", nil, true, true) end)
		end
		local ok_add, err_add = pcall(function() inv:add_equipment("slot_grenade", item_data) end)
		if not ok_add then mod:echo("[cwv] add_equipment failed: " .. tostring(err_add)); return end
		pcall(function() inv:wield("slot_grenade") end)
		mod:echo("[cwv] Tuskgor Javelin granted to bomb slot — wield (grenade key), melee or aim+throw. One use.")
	end)
end

-- ============================================================
-- Rapier template (modified fencing_sword_template_1)
-- Saltzpyre's fencing-sword moveset cloned for Kruber. Pistol-shoot
-- weapon special (action_three, kind="handgun") disabled via
-- _always_false condition_func — keeps the action defined for
-- state-machine / network consistency but it never fires. Same pattern
-- as the tuskgor javelin auto-catch reload disable (v0.1.65).
--
-- 3P wield routes to Kruber's native to_1h_sword SM (the empire-soldier
-- body authors no fencing-sword wield), and per-action remap covers
-- fencing events not in 1h_sword's closed vocabulary.
--
-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
-- ARCHITECTURE.
-- ============================================================

-- 3P remap — source (fencing_sword_template_1) → target
-- (one_handed_swords_template_1, Kruber 1h sword vocabulary).
-- Closed list for to_1h_sword (verified against 1h_swords.lua):
--   charges:   attack_swing_charge_left, attack_swing_charge_right_pose,
--              attack_swing_charge_left_pose
--   strikes:   attack_swing_heavy, attack_swing_heavy_right,
--              attack_swing_left_diagonal, attack_swing_right,
--              attack_swing_down, attack_swing_right_diagonal
--   universal: attack_push, parry_pose
-- Source events already in target (attack_swing_right,
-- attack_swing_right_diagonal, attack_push, parry_pose) need no entry.
-- #284: rapier constructor + its two private 3P remap tables wrapped in a
-- do..end so their top-level locals release after the block (Lua 5.1 200-local
-- limit). `_always_false` (referenced inside) stays declared above the block.
do
local _RAPIER_ANIM_REMAP_3P = {
	-- Stab charge → heavy charge (closest charge anim).
	attack_swing_stab_charge = "attack_swing_charge_left",
	-- Stab strike → right_diagonal (closest forward-leaning strike).
	attack_swing_stab        = "attack_swing_right_diagonal",
	-- Source has plain attack_swing_left; target has _left_diagonal only.
	attack_swing_left        = "attack_swing_left_diagonal",
}

local _rapier_kruber_wield_3p = {
	es_mercenary      = "to_1h_sword",
	es_huntsman       = "to_1h_sword",
	es_knight         = "to_1h_sword",
	es_questingknight = "to_1h_sword",
}

local function _create_rapier_template()
	if not Weapons or not Weapons.fencing_sword_template_1 then
		mod:warning("fencing_sword_template_1 not found — Rapier template unavailable")
		return
	end
	if Weapons.rapier_template then return end

	local template = table.clone(Weapons.fencing_sword_template_1, true)

	-- Disable the pistol action and remove its ammo contract together. Keeping
	-- cloned ammo_data while omitting the left-hand pistol makes the stock HUD
	-- request ammo_system from a nil unit when this melee weapon occupies Grail
	-- Knight's second (slot_ranged) weapon slot (#807).
	_om.rapier_contract.disable_pistol(template, _always_false)

	-- Per-action 3P remap on every sub-action whose anim_event has a
	-- substitute. 3P-only — never write anim_event (1P).
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table"
							and sub_action.anim_event
							and _RAPIER_ANIM_REMAP_3P[sub_action.anim_event] then
						sub_action.anim_event_3p = _RAPIER_ANIM_REMAP_3P[sub_action.anim_event]
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_1h_sword"
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for k, v in pairs(_rapier_kruber_wield_3p) do
		template.wield_anim_career_3p[k] = v
	end

	Weapons.rapier_template = template

	-- Patch the BASE template's wield_anim_career_3p so the inventory
	-- previewer (HeroPreviewer reads BASE template, not our clone — see
	-- feedback_cwv_previewer_template_lookup.md) shows the right wield
	-- pose for Kruber careers. Scoped to es_* only — Saltzpyre careers
	-- fall through to original behavior (his body has the fencing wield
	-- authored natively).
	local base = Weapons.fencing_sword_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(_rapier_kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	mod:info("Created rapier_template (pistol-shoot disabled, 3p anim remap: %d entries, wield_3p=to_1h_sword for es_*)",
		3)
end

_create_rapier_template()
end -- #284: end rapier constructor do..end block

-- NOTE: brace_repeater_template + cwv_es_brace_repeater variant moved to
-- weapon_tweaker in v0.1.187 (CWV-side). The functionality lives there
-- now as a 3P unit swap on Kruber's vanilla wh_brace_of_pistols
-- cross-access — no separate inventory item.

-- ============================================================
-- Optional mod detection
-- ============================================================

local function _detect_companion_mods()
	local wt = get_mod("wt")
	local cos = get_mod("cosmetics_tweaker")  -- #70: was misnamed `ct` (ct is the chaos_wastes id)

	if wt then
		mod:info("weapon_tweaker detected")
	end
	if cos then
		mod:info("cosmetics_tweaker detected")
	end

	return wt, cos
end

-- ============================================================
-- Localization
-- ============================================================

local _display_names = {}
local _item_text = mod:dofile("scripts/mods/character_weapon_variants/_cwv_item_text")

for _, def in ipairs(_variant_definitions) do
	_display_names[def.item_key .. "_name"] = def.display_name
	_display_names[def.item_key .. "_description"] =
		_item_text.description(def.display_name, def.description)
	if def.skin_display_name then
		_display_names[def.item_key .. "_skin_name"] = def.skin_display_name
	end
	-- item_type → display_name mapping. `_build_entry` sets
	-- `entry.item_type = def.item_type or def.item_key`, so vanilla UI calls
	-- `Localize(item_data.item_type)` always hit one of these keys.
	-- Without this mapping, those calls would fall through to vanilla's
	-- localization for the BASE weapon's item_type (e.g. "bw_dagger" →
	-- "Dagger") because cwv variants inherit `entry.name` / `entry.key` from
	-- the clone — see `feedback_cwv_clone_name_clobber.md`. The explicit
	-- override here ensures the cwv variant always displays its own name in
	-- weapon-type labels, loot drop banners, and the cosmetics inventory
	-- header.
	-- Multiple variants can share def.item_type (e.g. the Imperial Longsword
	-- owner and its illusion-only siblings). The FIRST owning definition is the
	-- canonical weapon-family label. Never let a later curated/skin-only entry
	-- rename the owned weapon in inventory headers (issue #396).
	local effective_item_type = def.item_type or def.item_key
	if _display_names[effective_item_type] == nil then
		_display_names[effective_item_type] = def.display_name
	end
end

-- #597 model names are intentionally provisional while the converted axes are
-- reviewed in-game. Keep them in the same global localization surface used by
-- generated variant skins so the picker never shows raw manifest keys.
for _, model in ipairs(_om.greataxe.usable_models()) do
	_display_names[model.key .. "_name"] = model.display_name
	_display_names[model.key .. "_description"] = model.description or "A Greataxe model awaiting final review and naming."
end
for _, model in ipairs(_om.crowbill_family.usable_models()) do
	_display_names[model.key .. "_name"] = model.display_name
	_display_names[model.key .. "_description"] = model.description
		or "A Crowbill model awaiting final review and naming."
end

-- Pickup HUD popup strings. Vanilla pickup interaction code calls Localize()
-- on `pickup_settings.hud_description` (interactions.lua:1572 →
-- interaction_ui.lua:684). VMF's per-mod _localization.lua strings are
-- exposed via mod:localize(), NOT auto-registered into the global Localize —
-- so unrecognized keys come back as `<key>` from vanilla Localize. Translate
-- directly in this hook for any pickup loc key the mod defines.
local _pickup_hud_strings = {
	cwv_interaction_ammunition_javelin = "Tuskgor Javelin",
}

-- audit 2026-06-07 (F15, v0.1.349-dev): prefix helper derives its compare
-- length from #prefix so the mace+sword rename can't silently die on an
-- off-by-one again. The prior inline `key:sub(1, 30) ==
-- "es_dual_wield_hammer_sword_skin"` compared 30 chars against a 31-char
-- literal -> ALWAYS false -> the rename never fired for any skinned mace+sword.
-- Centralizing the length on the literal makes the bug structurally impossible.
local _MACE_SWORD_SKIN_PREFIX = "es_dual_wield_hammer_sword_skin"
local function _has_prefix(s, prefix)
	return type(s) == "string" and s:sub(1, #prefix) == prefix
end
-- Exposed for the /cwv_regression_test prefix-match behavioral check.
mod._cwv_has_prefix = _has_prefix
mod._cwv_mace_sword_skin_prefix = _MACE_SWORD_SKIN_PREFIX

mod:hook(_G, "Localize", function(func, key)
	if _display_names[key] then
		return _display_names[key]
	end
	if _pickup_hud_strings[key] then
		return _pickup_hud_strings[key]
	end
	-- Vanilla mace+sword rename — gated on the user-facing toggle. The
	-- inventory/cosmetics UI uses the APPLIED SKIN's display_name key (not
	-- always the IML weapon's display_name), so we have to catch every
	-- `es_dual_wield_hammer_sword_skin_*_name` variant — skin_01, skin_02,
	-- skin_03, runed variants, magic variants, etc. Without the wildcard,
	-- a player who applied any non-default illusion (skin_02 etc.) would
	-- still see "Mace and Sword" because the displayed key is the skin's,
	-- not the weapon's. Pattern: anything starting with the weapon prefix
	-- and ending in `_name`.
	-- Toggle is read at hook fire so it responds to runtime changes without
	-- a mod reload.
	-- audit 2026-06-07 (F15, v0.1.349-dev): use the #prefix-based helper. The
	-- old `key:sub(1, 30) == "<31-char literal>"` was off-by-one and never
	-- matched, so the mace_sword_tweak rename was silently dead for every
	-- skinned mace+sword variant (skin_01/02/03, runed, magic, etc.).
	if _has_prefix(key, _MACE_SWORD_SKIN_PREFIX)
			and key:sub(-5) == "_name"
			and mod:get("mace_sword_tweak") then
		return "Cudgel and Short Sword"
	end
	return func(key)
end)

-- ============================================================
-- Cross-character weapon unlocks (can_wield patches)
-- ============================================================

local _weapon_unlocks = {
	{
		item_key = "wh_1h_axe",
		add_careers = {
			"es_mercenary",
			"es_huntsman",
			"es_knight",
			"es_questingknight",
		},
	},
}

local function _apply_weapon_unlocks()
	for _, unlock in ipairs(_weapon_unlocks) do
		-- rawget: ItemMasterList __index crashifies on missing keys; defensive against
		-- future _weapon_unlocks entries referencing DLC-gated items the user lacks.
		local item = rawget(ItemMasterList, unlock.item_key)
		if item and item.can_wield then
			local existing = {}
			for _, career in ipairs(item.can_wield) do
				existing[career] = true
			end
			for _, career in ipairs(unlock.add_careers) do
				if not existing[career] then
					item.can_wield[#item.can_wield + 1] = career
					existing[career] = true
				end
			end
			mod:info("Unlocked %s for: %s", unlock.item_key, table.concat(unlock.add_careers, ", "))
		else
			mod:warning("Cannot unlock %s — not found in ItemMasterList", unlock.item_key)
		end
	end
end

_apply_weapon_unlocks()

-- Skin/illusion registrars stay at their original load-bearing registration boundary.
-- CWV_SKIN_REGISTRY_INSTALL_ONCE_v1
local _skin_state = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_skin_registry")(mod, {
	om = _om,
	variant_definitions = _variant_definitions,
	WeaponSkins = WeaponSkins,
	ItemMasterList = ItemMasterList,
	NetworkLookup = NetworkLookup,
	printf = printf,
})
local _custom_illusions = _skin_state.custom_illusions
local _custom_skin_keys = _skin_state.custom_skin_keys
mod:dofile("scripts/mods/character_weapon_variants/_cwv_illusion_families")(mod, {
	om = _om,
	custom_skin_keys = _custom_skin_keys,
	illusion_provenance = mod._cwv_illusion_provenance,
	es_all_careers = _es_all_careers,
	wh_all_careers = _wh_all_careers,
	es_careers = _skin_state.es_careers,
	wh_careers = _skin_state.wh_careers,
	kruber_1h_dual_skin_keys = _skin_state.kruber_1h_dual_skin_keys,
	WeaponSkins = WeaponSkins,
	ItemMasterList = ItemMasterList,
	NetworkLookup = NetworkLookup,
})

mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
	local mirror = self._backend_mirror
	if not mirror or not mirror._unlocked_weapon_skins then return end
	for skin_key, _ in pairs(_custom_skin_keys) do
		local skin_item = rawget(ItemMasterList, skin_key)
		local required_dlc = skin_item and skin_item.required_dlc
		local owns_required_dlc = not required_dlc
			or not Managers.unlock
			or Managers.unlock:is_dlc_unlocked(required_dlc)
		if owns_required_dlc then
			mirror._unlocked_weapon_skins[skin_key] = true
		end
	end
end)

-- ============================================================
-- Item registration owner (#1159)
-- ============================================================
-- Definition row -> live backend item. The owner holds the #482 identity
-- ladder behind `_om._cwv_key_for_item`, the `_build_entry` ItemMasterList
-- clone constructor, the deferred once-per-session `_auto_register_all` pass
-- (StateInGameRunning.on_enter) with its #661 career-action integration, #567
-- reverse-index rebuild, inline NetworkLookup.item_names append and #592
-- Blacksmith seeds, plus the #273 Deus identity installer and its
-- DeusMechanism._setup_run boundary.
--
-- It loads HERE, where the item-creation helper ran, because
-- `mod._cwv_resolve_item_key = _om._cwv_key_for_item` below reads the resolver
-- at load time. The give command and the shared preview / illusion-browser
-- descriptors stay in this entry: command surface and the #1158
-- exact-appearance channel respectively, not registration.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_item_registration_owner")(mod, {
	om = _om,
	dbg = _dbg,
	dbg_alert = _dbg_alert,
	variant_definitions = _variant_definitions,
	custom_skin_keys = _custom_skin_keys,
	career_weapon_actions = _career_weapon_actions,
	cwv_career_weapon_actions = _cwv_career_weapon_actions,
	career_action_owner = _career_action_owner,
})

-- ============================================================
-- Give command
-- ============================================================

local function _find_def(item_key)
	for _, def in ipairs(_variant_definitions) do
		if def.item_key == item_key then
			return def
		end
	end
	return nil
end

-- Shared override-mesh residency guard (issue #418). Given a base unit path,
-- return its resident "_3p" override form or nil. Encapsulates the vanilla-
-- player-mesh prefix + invisible-weapon sentinel + "_3p" suffix + has_loaded
-- residency check that was inlined (and drifting) across the inventory-preview
-- swap and the illusion browser. A non-vanilla, sentinel, or non-resident target
-- returns nil so callers degrade to the base mesh -- never an engine-fatal
-- World.spawn_unit on a non-resident/custom mesh (issue 403 class). Keyed on the
-- single _om.HUSK_OVERRIDE_REF constant so producer and consumer can't drift.
_om._resident_override_3p = function(base_unit)
	if type(base_unit) ~= "string" or base_unit == "" then return nil end
	if base_unit:find("units/weapons/player/", 1, true) ~= 1 then return nil end
	if base_unit:find("wpn_invisible_weapon", 1, true) then return nil end
	local want = base_unit .. "_3p"
	if not (Managers and Managers.package) then return nil end
	local ok, res = pcall(Managers.package.has_loaded, Managers.package, want, _om.HUSK_OVERRIDE_REF)
	if not (ok and res == true) then return nil end
	return want
end

-- ============================================================
-- Shared preview descriptor (issues 237/419/660) — WEAPON_APPEARANCE_STANDARD §4.1
-- ============================================================
-- Paths 3/4 (inventory preview + illusion browser) receive the variant's BASE
-- weapon key and spawn the BASE mesh; the owner/husk paths swap at the data
-- level (`_build_entry` writes the override units onto the cloned entry) but the
-- previewers do not, so a cross-character melee variant (e.g. the elf Sword &
-- Shield, cwv_we_sword_shield) shows its base's Kruber mesh on the character-
-- preview model. This rewrites the previewer's precomputed `spawn_data`
-- entry.unit_name to the variant's authored 3P unit BEFORE vanilla spawns it
-- (weapon_tweaker's preview-swap pattern: mutate the recipe, never
-- despawn/respawn). unit_name ONLY — cwv melee variants reuse the base
-- template's node vocabulary (`_build_entry` keeps the base template), so the
-- node linking is already correct and we never risk an engine-fatal Unit.node
-- on a swapped mesh. Idempotent: when `BackendUtils.get_item_units` already
-- forced the override (skinless owner-style resolution), entry.unit_name already
-- equals the target and the rewrite is a no-op.
--
-- Both preview engines now resolve identity and units exactly once here. Their
-- wrappers only select the engine recipe adapter: MenuWorldPreviewer exposes
-- right/left flags, while LootItemUnitPreviewer has rebound the recipe to the
-- vanilla base-unit identity. This retires the duplicated #237/#419 fallback
-- resolvers that drifted into two separate fixes for the same concern.
--
-- SAFETY (#237/#419): the spawn target is gated by `_om._preview_override_3p`:
-- husk residency resolver first (co-op unchanged); else only a non-sentinel
-- vanilla `units/weapons/player/` or mod-bundled `units/cwv_` mesh passing the
-- #478 spawn floor (`_om._husk_unit_spawnable`, incl. the #474 Old Musket donor
-- gate) swaps; anything else degrades to the base mesh, never an engine-fatal
-- World.spawn_unit (issue 403 class). Ammo-unit entries are skipped. A
-- user-selected illusion (non-empty `skin` arg) wins, as in get_item_units.
_om._cwv_resolve_spawn_descriptor = function(backend_id, item_data, explicit_skin, stored_skin)
    local cwv_key = _om._cwv_key_for_item(backend_id, item_data)
    local def = cwv_key and _find_def(cwv_key) or nil
    if not def then return nil, nil, cwv_key, "variant_missing" end
    local base = ItemMasterList and rawget(ItemMasterList, def.base_weapon)
    local descriptor, reason = _om.exact_appearance.resolve_spawn_descriptor({
        explicit_skin = explicit_skin,
        stored_skin = stored_skin,
        backend_id = backend_id,
        weapon_skins = WeaponSkins and WeaponSkins.skins,
        variant = def,
        base = base,
        skin_from_backend = function(bid)
            local backend = Managers and Managers.backend
            local iface = backend and backend:get_interface("items")
            return iface and iface.get_skin and iface:get_skin(bid)
        end,
    })
    return descriptor, def, cwv_key, reason
end

_om._cwv_preview_meshswap_apply = function(item_name, backend_id, skin, info)
    local stored_skin = type(info) == "table" and info.skin_name or nil
    local descriptor, def, cwv_key = _om._cwv_resolve_spawn_descriptor(
        backend_id, nil, skin, stored_skin)
    if not descriptor then return end
    local swapped = _om.exact_appearance.apply_spawn_descriptor(
        descriptor, info and info.spawn_data, _om._preview_override_3p, "hand_flags")
    if swapped > 0 then
        printf("[cwv:660] surface=inventory descriptor=%s key=%s bid=%s swapped=%d source=%s R=%s L=%s",
            tostring(descriptor.fingerprint), tostring(cwv_key), tostring(backend_id), swapped,
            tostring(descriptor.source), tostring(def.right_hand_unit), tostring(def.left_hand_unit))
    end
end
mod._cwv_preview_meshswap_apply = _om._cwv_preview_meshswap_apply; mod._cwv_resolve_item_key = _om._cwv_key_for_item -- exact provider identity; #237 preview handle

-- Illusion-browser mesh-swap pre-pass (issue 419) — WEAPON_APPEARANCE_STANDARD
-- §3 path 4. The browser's data-level resolution is SUPPOSED to cover this:
-- `LootItemUnitPreviewer._load_item_units` calls `BackendUtils.get_item_units`
-- (loot_item_unit_previewer.lua:270) and our hook there forces the def's units.
-- But `_load_item_units` REBINDS item_data to the BASE ItemMasterList entry
-- first (`item_key = item_data.key or item.key` then `item_data =
-- ItemMasterList[item_key]`, loot_item_unit_previewer.lua:254-255) — a cwv
-- clone keeps `key` = base key, so the get_item_units hook receives the BASE
-- entry and the #482 ladder's `item_data.cwv_key` rung is structurally dead on
-- this path. A crafted instance with a UUID backend_id (Athanor, issue 482)
-- then rides the pcall-guarded backend rung ALONE; when that lookup misses,
-- the browser spawns the base mesh and the transform pass scales the WRONG
-- mesh (the issue 419 distortion). `self._item` still carries the ORIGINAL
-- item.data (the stamped clone), so resolving the ladder HERE sees rung 2 and
-- cannot miss a stamped instance.
--
-- Guards mirror `_cwv_preview_meshswap_apply` (issue 237): an applied illusion
-- wins (skin data already carries the variant units for cwv skins); the spawn
-- target is gated by `_om._preview_override_3p` (#237/#419: husk resolver, then
-- the #478/#474 spawn floor) — else degrade to the base mesh, never an
-- engine-fatal World.spawn_unit (issue 403 class). Hand identity by exact
-- base-unit-name match ("_3p" already appended by _load_item_units,
-- loot_item_unit_previewer.lua:286/302): ammo/already-swapped entries don't
-- match, pass through untouched (idempotent vs get_item_units — no double-handling).
_om._cwv_browser_meshswap_apply = function(item, spawn_data)
    if not item or type(spawn_data) ~= "table" then return end
    local stored_skin = item.data and item.data.mod_data and item.data.mod_data.skin
    local descriptor, def, cwv_key = _om._cwv_resolve_spawn_descriptor(
        item.backend_id, item.data, item.skin, stored_skin)
    if not descriptor then return end
    local swapped = _om.exact_appearance.apply_spawn_descriptor(
        descriptor, spawn_data, _om._preview_override_3p, "base_identity")
    if swapped > 0 then
        printf("[cwv:660] surface=browser descriptor=%s key=%s bid=%s swapped=%d source=%s R=%s L=%s",
            tostring(descriptor.fingerprint), tostring(cwv_key), tostring(item.backend_id), swapped,
            tostring(descriptor.source), tostring(def.right_hand_unit), tostring(def.left_hand_unit))
    end
end
mod._cwv_browser_meshswap_apply = _om._cwv_browser_meshswap_apply  -- exposed for /cwv regression (issue 419)

-- issue #538: /cwv_give must REFUSE skin_only (illusion-only) variants. A
-- skin_only def (e.g. cwv_es_longsword_nordland) is deliberately excluded from
-- _auto_register_all because it exists only to seed a custom skin/illusion entry,
-- never a real craftable definition. The command is now entirely informational
-- (#592), while the discriminator preserves the more specific illusion guidance.
-- Exposed on
-- _om so the regression suite can assert the guard exists without driving the full
-- give path (which has echo + registration side effects). io is nil in the retail
-- sandbox, so a source self-grep check is impossible; this predicate is the seam.
_om._give_refuses_skin_only = function(def)
	return not not (def and def.skin_only)
end

local function _give_variant(item_key)
	local def = _find_def(item_key)
	if not def then
		mod:echo("Unknown variant: %s", item_key)
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end

	-- issue #538: illusion-only variants are never handed out as real items.
	if _om._give_refuses_skin_only(def) then
		mod:echo("%s is an illusion-only variant - use the illusion browser", def.display_name)
		return
	end
	mod:echo("Craft %s through Crafting in Modded", def.display_name)
end

-- Animation remapping handled entirely via template, 3P-only:
-- - anim_event_3p overrides in elven_sword_shield_template (attack anims)
-- - wield_anim_3p = "to_1h_spear_shield" (wield anim, 3P body)
-- 1P animations work universally across all characters and are never touched
-- by this mod — see top-of-file ANIMATION ARCHITECTURE for the rule.

-- ============================================================
-- Model scaling and grip offsets
-- ============================================================
--
-- Two layers, in precedence order:
--   1. Per-variant fields on the def (`right_hand_scale`, `right_hand_offset`,
--      `left_hand_scale`, `left_hand_offset`) — model-specific overrides.
--   2. Type-level entry in `_type_transforms[item_type]` — applies to every
--      variant sharing that item_type. This is how a "weapon type" gets
--      defined as a single tunable: each `cwv_*` item_type represents a new
--      conceptual weapon (e.g. cwv_imperial_longsword), and any change to
--      the type cascades to all variants of that type automatically.
--
-- A variant only needs the per-variant fields when it deviates from its type.
-- The type table is the canonical place to tune family-wide proportions /
-- grip behaviour, so a future "make Imperial Longswords thinner" change is
-- one edit, not three.

local _type_transforms = {
	-- Imperial Longsword family (Imperial Longsword, Helmgart Watchsword, Black Guard Blade).
	-- Y trims 20% off width (Imperial greatsword's wide axis is Y, not X like the
	-- Bretonian — this is independent of cosmetics_tweaker's `_breton_sword_thiccc`
	-- factor `{0.65, 1, 1}` on `wpn_emp_gk_sword_*`); Z trims 10% off blade length.
	-- Lateral X grip nudge so the hand sits on the hilt after Y-thinning. Sign per
	-- `feedback_grip_offset_sign.md`.
	cwv_imperial_longsword = {
		right_hand_scale  = { 1.0, 0.8, 0.9 },
		-- User-tuned along Z. The negative direction is correct for this model
		-- family (flipped from `feedback_grip_offset_sign.md`'s general
		-- "+Z = grip lower" rule — per-model authoring axes can invert it).
		right_hand_offset = { 0, 0, -0.065 },
	},
	-- Longsword + Shield: same right-hand sword mesh as the 2H Imperial
	-- Longsword family (`wpn_empire_2h_sword_04_t1`), per-perspective
	-- scaled. 3P body shows the smaller-feeling sword (better silhouette
	-- next to a shield, where a 2H greatsword reads too oversized),
	-- while 1P keeps the original 2H family scale because the held view
	-- looked too small at the shrunk values. Tuning history:
	--   v0.1.197 unified {1.0, 0.8, 0.9} — matches 2H family
	--   v0.1.206 unified {0.85, 0.65, 0.75} — −0.15 on every axis
	--   v0.1.210 SPLIT — 1P back to {1.0, 0.8, 0.9}, 3P stays at {0.85, 0.65, 0.75}
	-- Resolution: `_1p`/`_3p` variants override the unified field for
	-- that perspective only (per `_resolve_field`). Grip offset is
	-- unified — same Z=-0.065 works for both perspectives. Left hand
	-- (the shield) is untouched. Variant uses its own item_type (not
	-- cwv_imperial_longsword) so it can carry its own curated
	-- shield-illusion picker — that's why this is a separate entry
	-- rather than sharing the 2H family's type.
	cwv_es_longsword_shield = {
		right_hand_scale_1p = { 1.0, 0.8, 0.9 },     -- 1P held view: full 2H family scale
		right_hand_scale_3p = { 0.9, 0.7, 0.8 },  -- 3P body: shrunk for shield pairing (+0.05 each axis v0.1.309)
		right_hand_offset   = { 0, 0, -0.065 },
	},
	-- Maul: scale Kruber's 1H mace meshes (mace+sword mace + es_1h_mace
	-- skins) up to a 2H silhouette. User-tuned to {1.075, 1.075, 1.4}
	-- v0.1.171 (was {1.4, 1.4, 2.0} in v0.1.168 — too big). The lighter
	-- X/Y bump keeps the mace from looking inflated; Z +40% adds enough
	-- length to read as a 2H maul. Type-level so default + every illusion
	-- in cwv_es_maul_skins picker inherit.
	cwv_es_maul = {
		right_hand_scale  = { 1.0, 1.0, 1.6 },
		-- Grip offset Z lowers Kruber's hand toward the haft. Per
		-- `feedback_grip_offset_sign.md`, +Z lowers grip on this family.
		-- Tuning history: 0.5 (v0.1.176) → 0.35 (v0.1.213) — the original
		-- pulled the hand too far toward the bottom of the haft; this is
		-- a more moderate drop.
		right_hand_offset = { 0, 0, 0.2 },
	},
	-- Rapier: lightly broaden the fencing-sword mesh — X +5%, Y +15%,
	-- Z native. Tuning history:
	--   v0.1.187 {1.1, 1.25, 1.0} initial basket-hilt feel
	--   v0.1.191 {1.1, 1.45, 1.0} Y bump
	--   v0.1.196 {1.0, 1.75, 1.0} maximal Y for broadsword silhouette
	--   v0.1.212 {1.05, 1.15, 1.0} restored to a subtler bump per user —
	--     v0.1.196's 1.75 read as exaggerated; this is a lighter touch.
	-- Type-level so the default mesh + every wh_fencing_sword_skin_*
	-- illusion in cwv_es_rapier_skins inherits.
	cwv_es_rapier = {
		right_hand_scale = { 1.05, 1.15, 1.0 },
	},
	-- Musket: stretch Kruber's rifle 1.35x along Y (length axis) and
	-- thin X/Z (barrel/cross-section). v0.1.250 dropped X/Z another 0.1
	-- (`0.9 → 0.8`). v0.1.256 split Y per perspective: 3P stays 1.35,
	-- 1P bumped to 1.5 (+0.15) per user "1P needs 0.15 longer on Y" —
	-- held view reads slightly short of where the muzzle should be.
	-- Per-perspective via `_resolve_field` precedence: `_1p` field
	-- overrides the unified `right_hand_scale` for 1P only.
	cwv_es_musket = {
		right_hand_scale    = { 0.8, 1.35, 0.8 },
		right_hand_scale_1p = { 0.8, 1.5,  0.8 },
	},
	-- Old Musket (cwv_es_musket_old): custom mesh is already the right
	-- shape (proportions baked into the FBX) — no Y stretch needed, no
	-- X/Z thinning, so it carries NO generic scale/offset. But it still
	-- needs its bespoke pose + textures applied on the resolver-driven
	-- render paths (inventory preview / illusion browser), which bail at
	-- the nil-def guard unless the def is registered. `force_register`
	-- (issue 409) puts it into `_transform_map` with no transform values,
	-- so `_resolve_preview_def` returns it and `_cwv_spawn_item_post`
	-- reaches the Old-Musket pose/texture block instead of early-returning.
	-- (Its actual pose is still the absolute per-perspective/stance pose in
	-- the `_om` module — the custom mesh needs an absolute reset, not the
	-- generic additive offset.)
	cwv_es_musket_old = { force_register = true },
}

-- Per-variant override > type-level default > nil.
local function _resolve_field(def, field)
	if def[field] ~= nil then return def[field] end
	local tt = def.item_type and _type_transforms[def.item_type]
	return tt and tt[field] or nil
end

local _transform_map = {}
local _skin_transform_map = {}
for _, def in ipairs(_variant_definitions) do
	-- Register if EITHER the def itself OR its type contributes any transform.
	-- This is what lets a variant with no per-variant scale fields still pick
	-- up the type-level entry — without it, _transform_map[item_key] is nil
	-- and `_resolve_cwv_def` returns nil at apply time.
	-- Includes the per-perspective `_1p` / `_3p` variants so a def that only
	-- sets a 1P-specific or 3P-specific transform is still registered.
	-- Issue 409: `force_register` lets a custom-mesh item that needs NO generic
	-- scale/offset (native authored scale) still enter `_transform_map`, so every
	-- resolver-driven render path (preview, illusion browser) resolves its def and
	-- reaches its rotation/texture apply instead of bailing at the nil-def guard.
	-- Rotation fields are also gate signals now — a rotation-only def must register.
	if _resolve_field(def, "force_register")
			or _resolve_field(def, "right_hand_scale")
			or _resolve_field(def, "left_hand_scale")
			or _resolve_field(def, "right_hand_offset")
			or _resolve_field(def, "left_hand_offset")
			or _resolve_field(def, "right_hand_scale_1p")
			or _resolve_field(def, "left_hand_scale_1p")
			or _resolve_field(def, "right_hand_offset_1p")
			or _resolve_field(def, "left_hand_offset_1p")
			or _resolve_field(def, "right_hand_scale_3p")
			or _resolve_field(def, "left_hand_scale_3p")
			or _resolve_field(def, "right_hand_scale_multiplier_3p")
			or _resolve_field(def, "left_hand_scale_multiplier_3p")
			or _resolve_field(def, "right_hand_offset_3p")
			or _resolve_field(def, "left_hand_offset_3p")
			or _resolve_field(def, "right_hand_rotation")
			or _resolve_field(def, "left_hand_rotation")
			or _resolve_field(def, "right_hand_rotation_1p")
			or _resolve_field(def, "left_hand_rotation_1p")
			or _resolve_field(def, "right_hand_rotation_3p")
			or _resolve_field(def, "left_hand_rotation_3p")
			-- Issue #417: a variant that OVERRIDES a hand unit (renders its own
			-- mesh) must resolve a def on every def-keyed path too, or the mesh
			-- swaps (via _find_def, registration-independent) while transform and
			-- texture bail at the nil-def guard -- silently. That trap forced the
			-- per-item `force_register` crutch (the musket, #409). Registering on
			-- unit-override presence generalizes the crutch: mesh-bearing =>
			-- def-resolving, so units and every other concern stay coupled for all
			-- current AND future variants. Behavior-neutral today (WA.apply no-ops
			-- on nil scale/offset/rotation; texture stays musket-gated).
			or _resolve_field(def, "right_hand_unit")
			or _resolve_field(def, "left_hand_unit") then
		_transform_map[def.item_key] = def
		if not def.no_skin then
			_skin_transform_map[def.item_key .. "_skin"] = def
		end
	end
end

-- Exposed for /cwv_regression_test (musket_old_force_registered, #409).
mod._cwv_transform_registered = function(key) return _transform_map[key] ~= nil end
-- Exposed for cwv_unit_bearing_variants_registered (#417): the test asserts every
-- def declaring a hand-unit override is registered (mesh-bearing => def-resolving).
_om._variant_defs = _variant_definitions

-- #597 Greataxe model transforms are illusion-specific. The generated base
-- skin uses `<item>_skin`, while the manifest calls that same row `_skin_01`;
-- bind both names to Model 01's reviewed transform. Every later model gets a
-- synthetic def even when it has no transform, which deliberately blocks the
-- dynamic inherit pass below from leaking Model 01's scale/offset/rotation to
-- Models 02-05. These defs feed the same shared WeaponAppearance path used by
-- owner/bot 3P, husks, inventory, lobby, score/team, and item previews.
for index, model in ipairs(_om.greataxe.usable_models()) do
	local transform_def = {
		item_key = model.key,
		right_hand_scale_3p = model.right_hand_scale_3p,
		right_hand_offset_3p = model.right_hand_offset_3p,
		right_hand_rotation_3p = model.right_hand_rotation_3p,
	}
	_skin_transform_map[model.key] = transform_def
	if index == 1 then
		_skin_transform_map[_om.greataxe.ITEM_KEY .. "_skin"] = transform_def
	end
end

-- #604 Crowbill transforms are model-specific. Register every
-- model as an explicit control so a reviewed tune can never leak into a sibling
-- through the dynamic family-inheritance pass below. These synthetic defs feed
-- the same shared WeaponAppearance consumers as Greataxe: owner/bot 3P, remote
-- husks, inventory/lobby/score character previews, and item/Athanor previews.
-- The exact spawned unit path is also indexed: default-rarity/CIM blacksmith
-- instances are intentionally skinless, and GearUtils may receive base-shaped
-- item_data, but the resolved unit is still an unambiguous model identity.
-- Default Model 01 additionally becomes the variant fallback so a skinless
-- default instance resolves the same transform before/after reconstruction.
local _crowbill_transform_by_unit = {}
for _, model in ipairs(_om.crowbill_family.usable_models()) do
	local base_def = _find_def(model.variant_key)
	local transform_def = base_def and table.clone(base_def, true) or {}
	transform_def.item_key = model.variant_key
	transform_def.crowbill_model_key = model.key
	transform_def.crowbill_mode_family = _om.crowbill_family.HAMMER_MODE_FAMILY
	transform_def.right_hand_unit = model.right_hand_unit
	transform_def.right_hand_scale = model.right_hand_scale
	transform_def.right_hand_offset = model.right_hand_offset
	transform_def.right_hand_rotation = model.right_hand_rotation
	transform_def.right_hand_scale_1p = model.right_hand_scale_1p
	transform_def.right_hand_offset_1p = model.right_hand_offset_1p
	transform_def.right_hand_rotation_1p = model.right_hand_rotation_1p
	transform_def.right_hand_scale_3p = model.right_hand_scale_3p
	transform_def.right_hand_scale_multiplier_3p = model.right_hand_scale_multiplier_3p
	transform_def.right_hand_offset_3p = model.right_hand_offset_3p
	transform_def.right_hand_rotation_3p = model.right_hand_rotation_3p
	_skin_transform_map[model.key] = transform_def
	_crowbill_transform_by_unit[model.right_hand_unit] = transform_def
	_crowbill_transform_by_unit[model.right_hand_unit .. "_3p"] = transform_def
	if _om.crowbill_family.model_for_variant(model.variant_key) == model then
		_transform_map[model.variant_key] = transform_def
	end
end

_om._cwv_crowbill_transform_by_unit = _crowbill_transform_by_unit

-- Custom illusions with their own scale/offset fields (e.g. greathammer
-- skins applied to 1H mace targets need to scale the oversized 2H model
-- down). These aren't variant defs — they live in `_custom_illusions` —
-- but the apply path keys by skin_key, so we register them in
-- `_skin_transform_map` with a synthetic def carrying just the transform
-- fields. `_resolve_field` reads `def[field]` first, finds these directly.
for _, illusion in ipairs(_custom_illusions) do
	local has_transform = illusion.right_hand_scale or illusion.left_hand_scale
		or illusion.right_hand_offset or illusion.left_hand_offset
		or illusion.right_hand_scale_1p or illusion.left_hand_scale_1p
		or illusion.right_hand_scale_3p or illusion.left_hand_scale_3p
	if has_transform then
		_skin_transform_map[illusion.skin_key] = {
			item_key             = illusion.skin_key,  -- for log/identification
			right_hand_scale     = illusion.right_hand_scale,
			left_hand_scale      = illusion.left_hand_scale,
			right_hand_offset    = illusion.right_hand_offset,
			left_hand_offset     = illusion.left_hand_offset,
			right_hand_scale_1p  = illusion.right_hand_scale_1p,
			left_hand_scale_1p   = illusion.left_hand_scale_1p,
			right_hand_scale_3p  = illusion.right_hand_scale_3p,
			left_hand_scale_3p   = illusion.left_hand_scale_3p,
			right_hand_offset_1p = illusion.right_hand_offset_1p,
			left_hand_offset_1p  = illusion.left_hand_offset_1p,
			right_hand_offset_3p = illusion.right_hand_offset_3p,
			left_hand_offset_3p  = illusion.left_hand_offset_3p,
		}
	end
end

-- Inherit-from-variant pass for dynamically-registered cross-character
-- illusions (registered via _register_*_illusions functions, NOT via
-- _custom_illusions). Detection: skin_key starts with a known variant
-- item_key followed by "_". The dynamic illusion shares the variant's
-- type-level transform via the variant's def — `_resolve_field` falls
-- through to `_type_transforms[def.item_type]` when the def has no
-- per-field override, so this gives the dynamic illusion picker preview
-- the same scale the variant's default mesh uses in-game.
--
-- The in-game render path (`GearUtils.create_equipment` →
-- `_resolve_cwv_def`) already handles this via the backend_id fallback —
-- it resolves the cwv variant from the equipped item's backend_id and
-- finds the type-level transform there. The picker (`LootItemUnitPreviewer`)
-- doesn't have a backend_id on the previewed weapon_skin entry, so
-- without this pass it shows un-scaled illusions.
--
-- Per-illusion overrides in _custom_illusions take precedence (above
-- block), so a dynamic illusion that needs a different scale than its
-- variant should be moved to _custom_illusions with explicit scale fields.
--
-- LONGEST-MATCH RULE (v0.1.255): when multiple variant defs share a
-- prefix relationship (e.g. `cwv_es_longsword` is a prefix of
-- `cwv_es_longsword_shield`), the iterate-and-break loop used to pick
-- whichever def appeared FIRST in `_variant_definitions` — so
-- `cwv_es_longsword_shield_*` illusions inherited from the 2H Imperial
-- Longsword variant instead of the shield-specific one, applying the
-- wrong scale. Now we walk every variant, track the longest item_key
-- that's a prefix of the skin_key, and use that one.
for skin_key in pairs(_custom_skin_keys) do
	if not _skin_transform_map[skin_key] then
		local best_def = nil
		local best_len = 0
		for _, def in ipairs(_variant_definitions) do
			if _transform_map[def.item_key]
					and #def.item_key > best_len
					and skin_key:sub(1, #def.item_key + 1) == def.item_key .. "_" then
				best_def = def
				best_len = #def.item_key
			end
		end
		if best_def then
			_skin_transform_map[skin_key] = _transform_map[best_def.item_key]
		end
	end
end

local function _is_unit(v) return _om.peer_resolver.alive_unit(v, Unit) end

-- ============================================================
-- WeaponAppearance (WA) — copied shared appearance primitive (#420)
-- ============================================================
-- The byte-identical bundled library owns scale / offset / position / rotation
-- math for a weapon unit, called by EVERY render path:
--   1. in-world owner/bot  — GearUtils.create_equipment
--   2. husk (remote)       — GearUtils.spawn_inventory_unit (owner_unit_1p==nil)
--   3. inventory preview    — MenuWorldPreviewer/_spawn_item -> _cwv_spawn_item_post
--   4. illusion browser     — LootItemUnitPreviewer.spawn_units
-- Full contract: docs/WEAPON_APPEARANCE_STANDARD.md. Identity, hand,
-- perspective, residency, and render-path resolution remain CWV-owned.
--
-- Conventions (DO NOT reintroduce per-site copies of this math):
--   * scale    — ABSOLUTE set. Idempotent by nature.
--   * offset   — ADDITIVE nudge from the mesh's native local position. Guarded
--                idempotent (weak table) because MenuWorldPreviewer's _spawn_item
--                super-call fires the hook TWICE per spawn and additive would
--                double. (This is why scale/rotation/position, being absolute,
--                need no guard.)
--   * position — ABSOLUTE set, for custom meshes that need a full pose reset
--                (e.g. the Old Musket). Mutually exclusive with offset; if both
--                are present, position wins.
--   * rotation — ABSOLUTE set. Accepts EITHER {x,y,z} Euler DEGREES (the human-
--                tunable standard: Quaternion.from_euler_angles_xyz takes degrees,
--                memory reference_vt2_euler_angles_degrees) OR a QuaternionBox /
--                raw Quaternion for hand-authored non-principal-axis poses.
--   * 1P and 3P are applied to SEPARATE units BY THE CALLER; the library never
--     infers perspective, so a 3P change can never touch the 1P grip (and vice
--     versa). Callers resolve `<field>_1p` / `<field>_3p` / unified via
--     `_resolve_field` and hand WA the already-resolved value.
local _WA_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_lib_weapon_appearance")
local WA = _WA_LIBRARY.new()
mod._wa_to_quaternion_for_rt = WA.to_quaternion -- compatibility: /cwv regression
mod._cwv_weapon_appearance = WA  -- cross-file / cross-mod handle (Phase 2+)

-- #604 Crowbill pick/hammer presentation.  One owner composes the authored
-- base rotation with the mode-local 180-degree Z flip for every render path.
-- The owner weak-tracks spawned units so a Weapon Special/network transition
-- reapplies once; it never runs from update and never derives from a previously
-- flipped unit pose.
_om.crowbill_mode_state = _om.crowbill_mode_state or _om.crowbill_hammer_mode.new()
_om.crowbill_presentation_owner = _om.crowbill_presentation.new({
	alive = function(unit) return unit and Unit.alive(unit) end,
	mode_for = function(identity) return _om.crowbill_mode_state:mode(identity) end,
	-- Raw Stingray quaternions are frame-temporary. Persist only QuaternionBox
	-- values in the presentation record and unbox immediately before compose.
	retain_rotation = function(rotation) return rotation and QuaternionBox(rotation) or nil end,
	resolve_rotation = function(rotation)
		return rotation and rotation.unbox and rotation:unbox() or rotation
	end,
	rotation_ops = {
		identity = function() return Quaternion.identity() end,
		axis_angle = function(axis, degrees)
			return Quaternion.axis_angle(Vector3(axis[1], axis[2], axis[3]), math.rad(degrees))
		end,
		-- base * delta applies the delta in the weapon model's local space.
		multiply = function(base, delta) return Quaternion.multiply(base, delta) end,
	},
	write_rotation = function(unit, rotation)
		return pcall(Unit.set_local_rotation, unit, 0, rotation)
	end,
})

_om._crowbill_render_identity = function(item_data, def, fallback)
	local bid = item_data and (item_data.backend_id
		or (item_data.mod_data and item_data.mod_data.backend_id))
	if type(bid) == "string" and bid ~= "" then return bid end
	if type(fallback) == "string" and fallback ~= "" then return fallback end
	return def and def.item_key or nil
end

_om._apply_crowbill_presentation = function(unit, def, identity, surface, base_rotation, explicit_mode)
	if not (def and def.crowbill_mode_family == _om.crowbill_family.HAMMER_MODE_FAMILY)
			or not (unit and Unit.alive(unit)) then return false end
	local base = WA.to_quaternion(base_rotation)
	if not base then
		local ok, current = pcall(Unit.local_rotation, unit, 0)
		if ok then base = current end
	end
	return _om.crowbill_presentation_owner:apply(unit, identity, surface, base, explicit_mode)
end

-- Live-state seam used by the Weapon Special/RPC owner.  The returned payload
-- is the hammer-mode module's bounded transition envelope; callers send it once
-- on a real transition and use `_cwv_crowbill_apply_remote_mode` on receipt.
mod._cwv_crowbill_set_mode = function(identity, mode)
	local changed, payload, err = _om.crowbill_mode_state:set_mode(identity, mode)
	if changed then _om.crowbill_presentation_owner:reapply(identity, mode) end
	return changed, payload, err
end
mod._cwv_crowbill_apply_remote_mode = function(payload)
	local changed, err = _om.crowbill_mode_state:apply_remote(payload)
	if changed then
		_om.crowbill_presentation_owner:reapply(payload.identity, payload.mode)
	end
	return changed, err
end
mod._cwv_crowbill_apply_presentation = _om._apply_crowbill_presentation

-- Legacy thin wrappers so existing call sites read unchanged; `_transform_unit`
-- now also carries rotation. New code should call WA.apply directly.
local function _apply_scale(unit, scale_tbl)  WA.apply_scale(unit, scale_tbl) end
local function _apply_offset(unit, offset_tbl) WA.apply_offset(unit, offset_tbl) end
local function _transform_unit(unit, scale_tbl, offset_tbl, rotation)
	return WA.apply(unit, { scale = scale_tbl, offset = offset_tbl, rotation = rotation })
end

-- #604 single transform-scheduling owner. Every world/presentation consumer
-- calls this helper, which resolves the same hand+perspective fields and emits
-- one bounded scheduling line per spawned tuned Crowbill unit. Retained proof
-- is deliberately deferred to the durable owner's next-tick pre/final samples.
local _crowbill_transform_diag_seen = setmetatable({}, { __mode = "k" })
local _crowbill_transform_diag_total = 0
_om._cwv_crowbill_transform_delivery = { counts = {} }
local _DURABLE_TRANSFORM_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_durable_transform")
local _RELATIVE_SCALE_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_relative_scale")
local _TRANSFORM_EVIDENCE_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_transform_evidence")
local _CROWBILL_TRANSFORM_RUNTIME_LIBRARY = mod:dofile(
	"scripts/mods/character_weapon_variants/_cwv_crowbill_transform_runtime")
local _crowbill_transform_runtime = _CROWBILL_TRANSFORM_RUNTIME_LIBRARY.new({
	om = _om,
	appearance = WA,
	durable_library = _DURABLE_TRANSFORM_LIBRARY,
	relative_library = _RELATIVE_SCALE_LIBRARY,
	evidence_library = _TRANSFORM_EVIDENCE_LIBRARY,
	emit = printf,
})
local _durable_crowbill_owner = _crowbill_transform_runtime.durable
_om._cwv_durable_crowbill_owner, _om._cwv_crowbill_transform_evidence = _durable_crowbill_owner, _crowbill_transform_runtime.evidence
_om._cwv_forget_crowbill_transform_unit = function(unit, reason)
	if not unit then return false end
	_durable_crowbill_owner:forget(unit, reason)
	return true
end
local function _triplet_text(value)
	if type(value) ~= "table" then return "nil" end
	return string.format("%.3f,%.3f,%.3f", value[1] or 0, value[2] or 0, value[3] or 0)
end
local function _apply_cwv_hand_transform(unit, def, hand, perspective, surface, unit_name, skin)
	if not def then return false end
	local prefix = hand == "left" and "left_hand_" or "right_hand_"
	local scale = _resolve_field(def, prefix .. "scale_" .. perspective)
		or _resolve_field(def, prefix .. "scale")
	local scale_multiplier = _resolve_field(def, prefix .. "scale_multiplier_" .. perspective)
		or _resolve_field(def, prefix .. "scale_multiplier")
	local offset = _resolve_field(def, prefix .. "offset_" .. perspective)
		or _resolve_field(def, prefix .. "offset")
	local rotation = _resolve_field(def, prefix .. "rotation_" .. perspective)
		or _resolve_field(def, prefix .. "rotation")
	local applied = _transform_unit(unit, scale, offset, rotation)
	local generation
	if def.crowbill_model_key and (scale or scale_multiplier or offset or rotation)
			and unit and _is_unit(unit)
			and _durable_crowbill_owner then
		-- Offset is authored as native+delta, but durable replay must be absolute
		-- or it would accumulate every frame. Capture the resolved post-write
		-- position in a Vector3Box; raw Stingray vectors are frame-temporary.
		local position_box
		if offset then
			local ok, position = pcall(Unit.local_position, unit, 0)
			if ok and position then position_box = Vector3Box(position) end
		end
		local _, assigned_generation = _durable_crowbill_owner:track(unit, {
			def = def,
			model_key = def.crowbill_model_key,
			hand = hand,
			perspective = perspective,
			surface = surface,
			unit_name = unit_name,
			skin = skin,
			scale = scale,
			scale_multiplier = scale_multiplier,
			position = position_box,
			rotation = rotation,
		})
		generation = assigned_generation
	end
	if def.crowbill_model_key and (scale or scale_multiplier or offset or rotation) and unit
			and _is_unit(unit) and _crowbill_transform_diag_total < 64 then
		local surfaces = _crowbill_transform_diag_seen[unit]
		if not surfaces then
			surfaces = {}
			_crowbill_transform_diag_seen[unit] = surfaces
		end
		local token = tostring(surface) .. ":" .. tostring(perspective) .. ":" .. tostring(hand)
		if not surfaces[token] then
			surfaces[token] = true
			_crowbill_transform_diag_total = _crowbill_transform_diag_total + 1
			local counts = _om._cwv_crowbill_transform_delivery.counts
			counts[surface] = (counts[surface] or 0) + 1
			pcall(printf,
				"[cwv:604] transform scheduled surface=%s perspective=%s hand=%s variant=%s model=%s unit=%s skin=%s generation=%s scale_multiplier=(%s) absolute_scale=(%s) offset=(%s) rotation=(%s) initial_apply=%s count=%d/64",
				tostring(surface), tostring(perspective), tostring(hand),
				tostring(def.item_key), tostring(def.crowbill_model_key),
				tostring(unit_name), tostring(skin), tostring(generation),
				_triplet_text(scale_multiplier), _triplet_text(scale),
				_triplet_text(offset), _triplet_text(rotation), tostring(applied),
				_crowbill_transform_diag_total)
		end
	end
	return applied
end

-- Vanilla mace+sword cosmetic tweak (toggleable via "mace_sword_tweak"
-- setting, default ON). When the toggle is on:
--   * The vanilla `es_dual_wield_hammer_sword` item gets renamed to
--     "Cudgel and Short Sword" via the Localize hook below.
--   * The sword half (left_hand_unit = wpn_emp_sword_06_t1) is scaled to
--     {0.7, 0.7, 1.0} on the 3P body so the mace and sword visually match
--     the standalone Cudgel + Shortsword variants.
-- This is the VANILLA item, not the CWV `cwv_es_sword_and_mace` (Sword and
-- Mace) variant — that one is a separate weapon and is unaffected by this
-- toggle.
local _ES_MACE_SWORD_TWEAK_DEF = {
	item_key        = "es_dual_wield_hammer_sword",
	-- Right hand (mace, wpn_emp_mace_04_t2) keeps native scale.
	-- Left hand (sword, wpn_emp_sword_06_t1) shrinks to match the
	-- cwv_es_shortsword variant.
	left_hand_scale = { 0.7, 0.7, 1.0 },
}

-- #620 Combat Style runtime. The policy is engine-free; this install supplies
-- the exact source-backed template/identity/network seams and one style-owned
-- Imperial transform record. Kerillian's style clones its donor plus cloned
-- damage/power rows, so no vanilla or sibling style table is ever mutated.
do
	local policy = _om.combat_style_policy
	local bretonnian_greatsword, bretonnian_greatsword_err =
		policy.build_bretonnian_greatsword_template(Weapons,
			function(value) return table.clone(value, true) end, _clone_damage_profile)
	if bretonnian_greatsword then
		Weapons[policy.BRETONNIAN_GREATSWORD_TEMPLATE] = bretonnian_greatsword
		mod:info("[cwv:648] registered Bretonnian receiver Greatsword style (stagger=%.0f%% cleave=%.0f%%; native Bretonnian reach)",
			policy.BRETONNIAN_GREATSWORD_STAGGER_MULT * 100,
			policy.BRETONNIAN_GREATSWORD_CLEAVE_MULT * 100)
	else
		mod:warning("[cwv:648] Bretonnian receiver Greatsword style unavailable: %s",
			tostring(bretonnian_greatsword_err))
	end

	local kerillian, err = policy.build_kerillian_template(Weapons,
		function(value) return table.clone(value, true) end, _clone_damage_profile)
	if kerillian then
		Weapons[policy.KERILLIAN_TEMPLATE] = kerillian
		mod:info("[cwv:648] registered Kerillian Greatsword style (speed=%.0f%% damage=%.1f%% stagger=%.0f%% cleave=%.0f%%)",
			policy.KERILLIAN_SPEED_MULT * 100, policy.KERILLIAN_DAMAGE_MULT * 100,
			policy.KERILLIAN_STAGGER_MULT * 100, policy.KERILLIAN_CLEAVE_MULT * 100)
	else
		mod:warning("[cwv:620] Kerillian Greatsword style unavailable: %s", tostring(err))
	end

	local saltz_bretonnian, saltz_bretonnian_err =
		policy.build_saltz_bretonnian_template(Weapons,
			function(value) return table.clone(value, true) end)
	if saltz_bretonnian then
		Weapons[policy.SALTZ_BRETONNIAN_TEMPLATE] = saltz_bretonnian
		mod:info("[cwv:645] registered Saltzpyre Greatsword receiver styles (Kerillian/Bretonnian)")
	else
		mod:warning("[cwv:645] Saltzpyre Bretonnian Greatsword style unavailable: %s",
			tostring(saltz_bretonnian_err))
	end

	local spear_shield_templates, spear_shield_err = policy.build_spear_shield_templates(Weapons,
		function(value) return table.clone(value, true) end)
	if spear_shield_templates then
		for template_name, template in pairs(spear_shield_templates) do
			Weapons[template_name] = template
		end
		mod:info("[cwv:645] registered reciprocal Spear and Shield styles (Kruber<->Elven)")
	else
		mod:warning("[cwv:645] reciprocal Spear and Shield styles unavailable: %s",
			tostring(spear_shield_err))
	end

	-- Owner-side style resource ownership plus the #786 Stage C observer-side
	-- residency read. Both live in the policy module next to the authored
	-- allowlist they are derived from.
	local acquire_style_resource, style_resource_resident =
		policy.new_resource_acquirer(function() return Managers and Managers.package end)

	local imperial_transform = _type_transforms.cwv_imperial_longsword
	local inverse_bretonnian_scale = {
		1 / imperial_transform.right_hand_scale[1],
		1 / imperial_transform.right_hand_scale[2],
		1 / imperial_transform.right_hand_scale[3],
	}
	local inverse_bretonnian_offset = {
		-imperial_transform.right_hand_offset[1],
		-imperial_transform.right_hand_offset[2],
		-imperial_transform.right_hand_offset[3],
	}

	-- #786: engine surfaces for the guarded husk re-wield. Policy, coalescer and
	-- the authored catalogue are the only authorities; nothing here reads back
	-- the state a re-wield just produced.
	local _style_rewield_deps = {
		policy = policy, coalescer = mod._cwv_rewield, printf = printf,
		unit_api = Unit, script_unit = ScriptUnit, probe_state = {},
		style_resource_resident = style_resource_resident,
		peer_player = function(peer_id) return _om.peer_resolver.peer_player(
			Managers and Managers.player, peer_id, 1) end,
		item_key = function(item_data) return _om.combat_styles
			and _om.combat_styles:member_key(item_data) end,
		effective_template = function(item_data, unit, slot_name)
			return _om.combat_styles and _om.combat_styles:effective_template_name(
				item_data, nil, unit, slot_name) end,
	}

	_om.combat_styles = policy.install(mod, {
		cwv_key_for_item = function(backend_id, item_data)
			return _om._cwv_key_for_item(backend_id, item_data)
		end,
		presentations = {
			imperial_longsword = {
				item_key = "cwv_style_imperial_longsword",
				right_hand_scale = imperial_transform.right_hand_scale,
				right_hand_offset = imperial_transform.right_hand_offset,
			},
			greatsword_bretonnian = {
				item_key = "cwv_style_greatsword_bretonnian",
				-- Reuse the reviewed Imperial Longsword proportions only on
				-- third-person/presentation consumers. The first-person Greatsword
				-- unit remains untouched and follows the Bretonnian state machine.
				right_hand_scale_3p = imperial_transform.right_hand_scale,
				right_hand_offset_3p = imperial_transform.right_hand_offset,
			},
			bretonnian_greatsword_inverse = {
				item_key = "cwv_style_bretonnian_greatsword_inverse",
				-- #692: reciprocal presentation for the native Bretonnian mesh
				-- under Greatsword/Kerillian state machines. Unified fields are
				-- intentional: owner 1P and every 3P/preview consumer need the
				-- same physical correction.
				right_hand_scale = inverse_bretonnian_scale,
				right_hand_offset = inverse_bretonnian_offset,
			},
		},
		owns_dlc = function(dlc_name)
			local unlock = Managers and Managers.unlock
			if not unlock or type(unlock.is_dlc_unlocked) ~= "function" then return false end
			local ok, owned = pcall(unlock.is_dlc_unlocked, unlock, dlc_name)
			return ok and owned == true
		end,
		-- Temporary, bounded #645 evidence. Removed when the remaining candidate
		-- family is promoted or explicitly declined; the policy caps each family.
		diagnostics_enabled = function() return true end,
		acquire_style_resource = acquire_style_resource,
		peer_for_owner = function(owner_unit)
			local pm = Managers and Managers.player
			local player = _om.peer_resolver.owner(pm, owner_unit)
			if not player then return nil end
			if type(player.peer_id) == "string" then return player.peer_id end
			local nok, value = pcall(player.network_id, player)
			return nok and value or nil
		end,
		rewield = _om.style_rewield,
		send_identity_slots = function(slots, edge, force)
			return _om._cwv_send_identity_slots
				and _om._cwv_send_identity_slots(slots, edge, force) end,
		-- #786 A1/A2: the husk re-wield DEFERS into the #1145 coalescer and the
		-- verdict is AND-semantics against the authored catalogue; both live in
		-- _cwv_style_rewield. Returns (queued, reason), never a sync success.
		rebuild_remote = function(peer_id, slot_name, family_id, style_id, on_verdict)
			return _om.style_rewield.queue_rebuild(_style_rewield_deps, peer_id,
				slot_name, family_id, style_id, on_verdict) end,
	})
	mod.cycle_combat_style = function()
		return _om.combat_styles and _om.combat_styles:cycle_wielded()
	end
	policy.install_loadout_ui(mod, _om.combat_styles)

	-- #620 legacy retirement: preserve every exact CIM UUID and its complete
	-- forged payload while rewriting only the item family and corresponding
	-- shield-free illusion key. The old item remains a hidden promo IML row so
	-- CIM can always restore it before this bounded migration runs.
	local migrated_legacy_styles = false
	_om._migrate_legacy_style_items = function()
		if migrated_legacy_styles then return 0 end
		local cim
		for _, mod_id in ipairs({ "cim_dev", "cim", "crafting_in_modded" }) do
			local ok, candidate = pcall(get_mod, mod_id)
			if ok and candidate then cim = candidate; break end
		end
		if not cim then return 0 end
		local saved = cim:get("forged_weapons")
		if type(saved) ~= "table" then return 0 end

		local patches, plan_err = policy.plan_legacy_migrations(saved,
			function(item_key)
				return type(ItemMasterList) == "table" and rawget(ItemMasterList, item_key) ~= nil
			end,
			function(skin_key, target_item)
				local skin = type(ItemMasterList) == "table" and rawget(ItemMasterList, skin_key)
				return skin and skin.matching_item_key == target_item
			end)
		if not patches then
			mod:warning("[cwv:620] legacy style migration deferred: %s", tostring(plan_err))
			return 0
		end
		if #patches == 0 then migrated_legacy_styles = true; return 0 end

		local identities, rollback = {}, {}
		for _, patch in ipairs(patches) do
			identities[#identities + 1] = {
				identity = patch.identity, item_key = patch.target_item, style_id = patch.style_id,
			}
		end
		-- Seed every exact style in one settings write before the item rows change.
		-- If CIM persistence fails the old compatibility item still uses the same
		-- style, so this ordering is safe and the migration remains retryable.
		_om.combat_styles:migrate_identities(identities)

		for _, patch in ipairs(patches) do
			local persisted = saved[patch.identity]
			local live = cim._cim_get_craft and cim._cim_get_craft(patch.identity)
			rollback[#rollback + 1] = {
				persisted = persisted, item_key = persisted.item_key, skin = persisted.skin,
				live = live, live_item_key = live and live.item_key, live_skin = live and live.skin,
			}
			persisted.item_key, persisted.skin = patch.target_item, patch.skin
			if live then live.item_key, live.skin = patch.target_item, patch.skin end
		end

		local persist_ok, persist_err = pcall(function()
			if cim._cim_persist_crafts then cim._cim_persist_crafts()
			else cim:set("forged_weapons", saved) end
		end)
		if not persist_ok then
			for _, old in ipairs(rollback) do
				old.persisted.item_key, old.persisted.skin = old.item_key, old.skin
				if old.live then old.live.item_key, old.live.skin = old.live_item_key, old.live_skin end
			end
			mod:warning("[cwv:620] legacy style migration persistence failed; rows rolled back: %s",
				tostring(persist_err))
			return 0
		end

		-- Best-effort repair of wrappers already restored this session. The saved
		-- CIM row is authoritative; a missing backend interface never invalidates
		-- the committed migration and will reconstruct correctly next session.
		for _, patch in ipairs(patches) do
			pcall(function()
				local items = Managers.backend:get_interface("items")
				local item = items and items:get_item_from_id(patch.identity)
				if item then
					item.key, item.ItemId = patch.target_item, patch.target_item
					item.skin = patch.skin
					item.data = rawget(ItemMasterList, patch.target_item) or item.data
					if type(item.mod_data) == "table" then item.mod_data.cwv_key = nil end
				end
			end)
		end
		migrated_legacy_styles = true
		printf("[cwv:620] migrated %d legacy UUID(s) to canonical combat-style items", #patches)
		return #patches
	end
end

local function _resolve_cwv_def(item_data, skin, resolved_unit_name)
	if _om.combat_styles and _om.combat_styles.transform_decision then
		local style_decision = _om.combat_styles:transform_decision(item_data,
			item_data and item_data.backend_id)
		if style_decision ~= nil then return style_decision or nil end
	end
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin] end
	-- #604: exact spawned Crowbill model identity outranks the base-shaped item
	-- row. This is the canonical path for skinless default-rarity/CIM instances.
	if resolved_unit_name and _crowbill_transform_by_unit[resolved_unit_name] then
		return _crowbill_transform_by_unit[resolved_unit_name]
	end
	if not item_data then return nil end
	-- CLARIFY: backend_id resolution is the canonical path for cwv items per
	-- memory note feedback_cwv_backend_id_lookup.md — item_data.key/.name return
	-- the BASE weapon key, never the cwv_* key.
	-- #482 ladder: bid pattern (`cwv_<key>_NNN`, CWV's own instances + cim
	-- standard-forge crafts, issue 390) -> item_data.cwv_key stamp -> backend
	-- lookup. The stamp rung is what restores scale/grip for Athanor-crafted
	-- instances, whose UUID backend_id the pattern can never match.
	local cwv_key = _om._cwv_key_for_item(item_data.backend_id, item_data)
	if cwv_key and _transform_map[cwv_key] then return _transform_map[cwv_key] end
	-- Vanilla item key fallback (used by the mace_sword_tweak path below; cwv
	-- items don't reach here because backend_id resolution above takes over).
	local key = item_data.key or item_data.name
	if key and _transform_map[key] then return _transform_map[key] end
	-- Vanilla mace+sword cosmetic tweak — gated on the user-facing toggle so
	-- it can be disabled at runtime without a mod reload. Per
	-- feedback_cwv_backend_id_lookup.md, `item_data.key` returns the BASE
	-- weapon key for cwv variants too — so we must check the backend_id
	-- prefix to ensure we don't accidentally apply this to
	-- cwv_es_sword_and_mace (which shares the same base_weapon).
	if key == "es_dual_wield_hammer_sword" and mod:get("mace_sword_tweak") then
		local bid_str = item_data.backend_id
		local is_cwv_variant = bid_str and type(bid_str) == "string" and bid_str:sub(1, 4) == "cwv_"
		if not is_cwv_variant then
			return _ES_MACE_SWORD_TWEAK_DEF
		end
	end
	return nil
end

-- #660 canonical world identity. Owner, bot, and remote adapters may differ in
-- how they obtain the item key, but once a CWV definition is known they resolve
-- the same exact item/model/skin descriptor here. Unknown selected skins fail
-- closed; no caller reconstructs a default model behind that stronger identity.
_om._cwv_resolve_world_descriptor = function(item_data, explicit_skin, resolved_unit_name,
		identity_key, instance_id)
	local backend_id = item_data and (item_data.backend_id
		or (item_data.mod_data and item_data.mod_data.backend_id))
	local cwv_key = identity_key or _om._cwv_key_for_item(backend_id, item_data)
	local def = cwv_key and _find_def(cwv_key)
	if not def then
		local transform_def = _resolve_cwv_def(item_data, explicit_skin, resolved_unit_name)
		if transform_def and transform_def.item_key and not transform_def.skin_only then
			def = transform_def
			cwv_key = transform_def.item_key
		end
	end
	if not (def and cwv_key and not def.skin_only) then return nil, nil, "not_cwv" end
	local base = def.base_weapon and rawget(ItemMasterList, def.base_weapon)
	if type(base) ~= "table" then return nil, def, "base_missing" end
	local skin = explicit_skin
	if skin == "n/a" or skin == "" then skin = nil end
	local descriptor, reason = _om.exact_appearance.resolve_spawn_descriptor({
		provider = "cwv",
		instance_id = instance_id or backend_id,
		variant = def,
		base = base,
		base_item_key = def.base_weapon,
		fallback_item_key = def.base_weapon,
		explicit_skin = skin,
		backend_id = skin and nil or backend_id,
		weapon_skins = WeaponSkins and WeaponSkins.skins,
		skin_from_backend = function(bid)
			local backend = Managers and Managers.backend
			local iface = backend and backend:get_interface("items")
			local value = iface and iface.get_skin and iface:get_skin(bid)
			return value ~= "n/a" and value or nil
		end,
	})
	return descriptor, def, reason
end

_om._cwv_resolve_crowbill_transform = function(skin, resolved_unit_name, variant_key)
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin], "skin" end
	if resolved_unit_name and _crowbill_transform_by_unit[resolved_unit_name] then
		return _crowbill_transform_by_unit[resolved_unit_name], "unit"
	end
	if variant_key and _transform_map[variant_key]
			and _transform_map[variant_key].crowbill_model_key then
		return _transform_map[variant_key], "variant_default"
	end
	return nil, "miss"
end

-- #604 schema-2 exact identity must select the reconstructed model definition,
-- not its transform-free base variant. Production and regression share this policy.
_om._cwv_husk_transform_policy = _om.husk_transform_policy.bind({ find_def = _find_def,
	resolve_def = _resolve_cwv_def, resolve_field = _resolve_field,
	model_by_unit = _crowbill_transform_by_unit })
_om._cwv_select_husk_transform_def = _om._cwv_husk_transform_policy.select
_om._cwv_husk_transform_apply_plan = _om._cwv_husk_transform_policy.plan

-- Husk display / transform / ledger machinery (issues 397/394/399/474/475/478/395/660)
-- lives in the husk-path module (OOP W5, PROJECT_STANDARDS §2.2a). The three
-- husk-reaching hooks above (GearUtils.spawn_inventory_unit,
-- SimpleHuskInventoryExtension._wield_slot / start_weapon_fx) stay in this entry and
-- reach the resulting _om._husk_* helpers via deferred lookup. Dofiled HERE so the
-- module's file-local dependencies are already defined at this point in load.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_husk_path")(mod, {
	om = _om,
	variant_definitions = _variant_definitions,
	find_def = _find_def,
	is_unit = _is_unit,
	apply_cwv_hand_transform = _apply_cwv_hand_transform,
	triplet_text = _triplet_text,
})

-- ============================================================
-- BackendUtils.get_item_units override
-- ============================================================
-- Force the cwv def's right_hand_unit / left_hand_unit overrides into the
-- result table when the call resolves to a cwv item AND no skin is being
-- applied. Fixes inventory preview rendering the BASE weapon's mesh on
-- default-rarity CWV blacksmith templates.
--
-- WHY this is needed:
-- The CWV entry inherits `entry.name` and `entry.key` from the base weapon
-- (per `feedback_cwv_clone_name_clobber.md` — clobbering them crashes
-- equip). Vanilla `BackendUtils.get_item_units` reads
-- `item_data.right_hand_unit` directly from whatever item_data was passed
-- in. If the upstream caller's lookup chain landed on the BASE entry
-- (e.g. via `ItemMasterList[item.name]` where item.name is the inherited
-- base name), `item_data.right_hand_unit` is the base mesh.
--
-- Pre-v0.1.87 we worked around this by pre-applying the cwv skin via
-- `mod_data.CustomData.skin = "<item_key>_skin"`, which forced
-- BackendUtils to use the skin's right_hand_unit (= the cwv mesh).
-- v0.1.87 removed that for default-rarity items so the forge would treat
-- them as unlocked blacksmith templates — but that exposed this latent
-- base-mesh-fallback bug.
--
-- The fix: detect cwv items by backend_id pattern (`cwv_<key>_001`) and,
-- when no skin ended up applied, replace the result's per-hand unit
-- paths with the variant def's overrides. When a skin IS applied (curated
-- exotic / unique cwv weapons that ship with their own illusion, OR a
-- user who manually applied a different cwv illusion via the cosmetic
-- menu), `result.skin` is non-nil and we leave it alone — the user's
-- chosen illusion wins.
if BackendUtils then
	mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
		local result = func(item_data, backend_id, skin, career_name)
		if not result then return result end
		-- #579: every unit-table consumer (owner 3P, remote husk and the
		-- previewers before their spawn recipe is built) consumes the same exact
		-- per-hand WeaponSkins row. Cosmetics may subsequently replace the saved
		-- offhand for this exact instance; CWV owns the selected primary skin.
		local exact = _om.exact_appearance.resolve({
			explicit_skin = result.skin or skin,
			backend_id = backend_id or (item_data and item_data.backend_id),
			weapon_skins = WeaponSkins and WeaponSkins.skins,
			skin_from_backend = function(bid)
				local backend = Managers and Managers.backend
				local iface = backend and backend:get_interface("items")
				return iface and iface.get_skin and iface:get_skin(bid)
			end,
		})
		if exact then
			-- Fill structural gaps only. Another chained mod may already have
			-- composed an exact per-instance offhand onto this canonical skin.
			_om.exact_appearance.apply_item_units(exact, result, true)
		end

		-- HISTORICAL: this hook used to mirror right_hand_unit → left_hand_unit
		-- for `_kruber_1h_dual_skin_keys` skins. The mirror was needed back when
		-- those skin entries deliberately omitted `left_hand_unit` to avoid a
		-- `j_leftweaponattach` crash on a single-sword display rig. v0.1.145
		-- removed the mirror: skin entries now carry `left_hand_unit = right_hand_unit`
		-- directly AND use `display_dual_weapons` (the rig that authors both
		-- attach nodes), so vanilla `BackendUtils.get_item_units` populates
		-- `result.left_hand_unit` from the skin entry without our help, on both
		-- in-game and previewer call paths. See `J_LEFTWEAPONATTACH_INVESTIGATION.md`.

		-- Husk calls carry no backend id. Correct skinless cross-character
		-- handedness here, before SimpleHuskInventoryExtension branches on the
		-- returned right/left fields and before the per-hand spawn hook can run.
		if not backend_id then
			_om._husk_preselect_units(result, item_data, backend_id, skin, career_name)
			return result
		end

		-- Backend_id pattern `cwv_<key>_NNN` covers CWV and cim-crafted instances
		-- (issue 390), then the #482 ladder fallbacks (item_data.cwv_key stamp /
		-- backend lookup) for crafted instances with UUID backend_ids.
		-- Anything that resolves no cwv key passes through.
		local cwv_key = _om._cwv_key_for_item(backend_id, item_data)
		if not cwv_key then return result end
		_om.profile_package_wire.mark_runtime(result, cwv_key, (_find_def(cwv_key) or {}).base_weapon)
		local descriptor = _om._cwv_resolve_world_descriptor and
			_om._cwv_resolve_world_descriptor(item_data, result.skin or skin,
				result.right_hand_unit, cwv_key, backend_id)
		if not descriptor then return result end

		-- The same descriptor now owns owner/bot world spawn and preview unit
		-- identity. A selected skin composes with a sibling exact offhand; an
		-- unskinned CWV instance replaces the inherited vanilla base units.
		_om.exact_appearance.apply_item_units(descriptor, result,
			result.skin ~= nil and result.skin ~= "")
		return result
	end)
end

-- ============================================================
-- issue 278: net-safe loadout sync for cwv variant keys
-- ============================================================
-- `SimpleInventoryExtension.add_equipment` (simple_inventory_extension.lua:885)
-- and `LoadoutUtils.hot_join_sync` (loadout_utils.lua:62) broadcast
-- `rpc_sync_loadout_slot` with `item_id = NetworkLookup.item_names[item.key]`
-- (loadout_utils.lua:25). For a cwv_* key that numeric id is a LOCAL
-- index-append (`#tbl + 1` in `_auto_register_all`), so its value depends on
-- every other mod that appended to item_names on THIS peer before us —
-- e.g. Loremaster's Armoury clone entries (appended by cosmetics_tweaker's
-- `_la_bridge.register_all` only on peers where LA is enabled). Host with LA
-- + client without LA = the host's cwv id (3243 in the issue-278 crash log)
-- doesn't exist on the client, and the receiving peer's decode
-- (`NetworkLookup.item_names[item_id]`, loadout_utils.lua:72) hits the strict
-- __index error metamethod (network_lookup.lua:2521) -> client CTD.
--
-- Fix (same shape as cosmetics_tweaker's LA net-safe substitution,
-- cosmetics_tweaker.lua v0.8.60-dev): substitute a SHADOW item whose `.key`
-- is the variant's `base_weapon` (a vanilla ItemMasterList key with an
-- identical, boot-time-stable item_names index on every peer) before the RPC
-- encodes. Local state is untouched (the shadow lives only for this call);
-- remote peers' `PlayerManager._player_loadouts` (inspect/Tab UI) show the
-- base weapon — consistent with what the husk already renders for cwv items
-- (husk equipment syncs by the inherited base `.name`, see issue 280 notes).
--
-- LoadoutUtils is a PLAIN TABLE (`LoadoutUtils = LoadoutUtils or {}`), so
-- table-form hook with a nil guard (same BackendUtils pitfall, CLAUDE.md
-- "Hooking"). Sole CWV hook on (LoadoutUtils, sync_loadout_slot) — verified
-- by pre-flight grep; cosmetics_tweaker/cim hook the same function from THEIR
-- mod registrations, which VMF chains fine across mods.
if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
	mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
		local key = item and item.key
		if type(key) == "string" and key:sub(1, 4) == "cwv_" then
			local def = _find_def(key)
			local base_key = def and def.base_weapon
			if base_key and rawget(ItemMasterList, base_key)
					and NetworkLookup and NetworkLookup.item_names
					and rawget(NetworkLookup.item_names, base_key) then
				local shadow = {}
				for k, v in pairs(item) do shadow[k] = v end
				shadow.key = base_key
				shadow.ItemId = base_key
				printf("[cwv:278] sync_loadout_slot net-safe: %s -> %s (slot=%s)",
					key, base_key, tostring(slot_name))
				return func(player, slot_name, shadow, sync_to_specific_peer_id)
			end
			-- No safe fallback key: better to skip the sync (remote loadout
			-- panel shows the previous item) than to CTD every peer whose
			-- item_names table diverges from ours.
			printf("[cwv:278] ALERT sync_loadout_slot SKIPPED for %s (no vanilla base_weapon fallback resolvable)",
				tostring(key))
			return
		end
		return func(player, slot_name, item, sync_to_specific_peer_id)
	end)
	_cwv_net_safe_loadout_hook_installed = true
end

-- WIRE-SAFETY: weapon_skin_id axis of issue 278 / issue 371; issue 741 retires
-- the issue-495 parity exception. A cwv-registered NetworkLookup.weapon_skins
-- key is undefined on a peer without cwv: any sender that encodes
-- weapon_skin_id = NetworkLookup.weapon_skins[<live slot skin>] onto
-- rpc_add_equipment fatals that peer on decode (inventory_system.lua:300 -> strict
-- __index, network_lookup.lua:2362). THREE vanilla senders read live slot data
-- (the same set cosmetics covers for issue 421):
--   * SimpleInventoryExtension.game_object_initialized (initial spawn,
--     simple_inventory_extension.lua:258-264)
--   * SimpleInventoryExtension._spawn_resynced_loadout (every mid-session
--     (re)equip, :1443-1457, encode :1451)
--   * GearUtils.hot_join_sync (host replays worn slots to each joining peer,
--     gear_utils.lua:462-488, encode :484)
-- UNCONDITIONAL FALLBACK (issue 741 / BUG_CLASSES 31, 64): same-mod presence and
-- schema agreement do not prove numeric NetworkLookup parity. Another
-- skin-appending mod can shift weapon_skins indexes between two CWV peers. Every
-- CWV skin is therefore nulled to vanilla "n/a" for all three vanilla senders,
-- without consulting the roster. The real skin travels as a stable string key on
-- cwv_item_identity and remote husks consume that reconstructed descriptor.
-- Key set: _om._skin_keys (base variant skins) + _custom_skin_keys
-- (pairing/illusion registrations) + the cwv_ name prefix as belt-and-suspenders
-- (every cwv-injected weapon_skins key is cwv_-prefixed; no vanilla key is).
-- Sole cwv hooks on all three methods (grep-verified 2026-07-12). No item_id
-- concern: cwv keeps item_data.name = base_weapon, a universal vanilla index.
-- do-block: cwv's main chunk sits at the Lua 5.1 200-local ceiling -- these
-- helpers must not cost enduring top-level slots.
do
	-- Single source of truth for the cwv-skin predicate: the same pure module
	-- that drives the update_cosmetic_slot sender null (below). Behavior is
	-- identical to the pre-v0.1.447 inline form (base key set / custom key set /
	-- cwv_ prefix) -- see _cwv_cosmetic_skin_wire.is_cwv_skin.
	local function _wire_skin(skin)
		return _om.cosmetic_skin_wire.is_cwv_skin(skin, _om._skin_keys, _custom_skin_keys)
	end
	_om._wire_skin_predicate = _wire_skin   -- exported for /cwv_regression_test

	-- The presence-only `_wire_parity_live` predicate that used to live here was
	-- removed with the #423 exact-catalog conversion: its one consumer (the
	-- damage-profile send gate) now reads mod._cwv_damage_wire_safe, which
	-- requires the exact catalog on top of the same committed applied_state.
	-- Appearance never needed it -- #741 forbids numeric CWV skin ids on the
	-- vanilla wire in every lobby shape.

	-- #396 positive owner identity. Vanilla equipment RPCs deliberately encode a
	-- CWV clone as its stable base item name, so the receiver cannot distinguish
	-- an Imperial Longsword from a native Bretonnian Longsword when the selected
	-- skin is nil/vanilla-looking. Carry only the missing item-key axis over VMF's
	-- same-mod channel; the ordinary vanilla RPC remains authoritative for slot and
	-- wield timing, while this descriptor is authoritative for CWV skin/units. The
	-- side channel is absence-safe for non-CWV
	-- peers and bounded to equip/resync/parity edges (never per-frame).
	local _IDENTITY_SCHEMA = _om.appearance_lifecycle_policy.SCHEMA
	mod._cwv_identity_surfaces = {
		network = true,
		owner_spawn = true,
		bot_spawn = true,
		remote_husk = true,
		husk_wield = true,
	}

	local lifecycle = _om.appearance_lifecycle_policy.new({
		resolve_local = function(slot_data, slot_name)
			local item_data = slot_data and slot_data.item_data
			local base_name = item_data and item_data.name
			if not item_data then return nil, base_name end
			local backend_id = item_data.backend_id
				or (item_data.mod_data and item_data.mod_data.backend_id)
			local key = _om._cwv_key_for_item(backend_id, item_data)
			if not key then return nil, base_name end
			local skin = slot_data.skin
			local descriptor = _om._cwv_resolve_world_descriptor(item_data, skin,
				nil, key, backend_id)
			return descriptor, base_name
		end,
		resolve_remote = function(payload, sender_peer_id)
			local def = type(payload.item_key) == "string" and _find_def(payload.item_key)
			if not def or def.skin_only or def.base_weapon ~= payload.base_item_key then
				return nil, "item_or_base"
			end
			local skin = payload.skin_key ~= "" and payload.skin_key or nil
			local descriptor, _, reason = _om._cwv_resolve_world_descriptor(
				{ name = def.base_weapon }, skin, nil, def.item_key,
				tostring(sender_peer_id) .. ":" .. tostring(payload.slot))
			return descriptor, reason
		end,
		send = function(recipient, schema, payload, edge)
			-- #474: stance rides the delivering channel. Stamped only on Old
			-- Musket payloads so every other item's wire shape is unchanged;
			-- receivers without this build ignore the extra field.
			if payload and payload.item_key == "cwv_es_musket_old"
					and _om._old_musket_mode_for_local_slot then
				local ok_mode, mode = pcall(_om._old_musket_mode_for_local_slot, payload.slot)
				if ok_mode and (mode == "melee" or mode == "ranged") then
					payload.musket_mode = mode
				end
			end
			-- #786 B1: the Combat Style axis rides the SAME delivering channel,
			-- generalized from the #474 stance rider. Stamped only when the live
			-- local slot is this payload's exact item, so a NATIVE style member
			-- (most of them are) publishes its style though item_key is "".
			if payload and _om.combat_styles then
				local ok_style, rider = pcall(_om.combat_styles.local_style_rider,
					_om.combat_styles, payload.slot,
					payload.item_key ~= "" and payload.item_key or payload.base_item_key)
				if ok_style and rider then payload.style = rider end
			end
			local ok = pcall(mod.network_send, mod, "cwv_item_identity",
				recipient, schema, payload)
			if ok then
				pcall(printf,
					"[cwv:660] lifecycle=%s adapter=identity_send recipient=%s slot=%s descriptor=%s",
					tostring(edge), tostring(recipient), tostring(payload.slot),
					tostring(payload.fingerprint ~= "" and payload.fingerprint or "native"))
			end
			return ok
		end,
	})
	_om._appearance_lifecycle = lifecycle

	_om._cwv_identity_payloads = function(slots)
		local payloads = {}
		for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
			local payload = lifecycle:payload_for(slot_name,
				type(slots) == "table" and slots[slot_name] or nil)
			if payload then payloads[#payloads + 1] = payload end
		end
		return payloads
	end

	_om._cwv_accept_identity = function(sender_peer_id, schema, payload)
		return lifecycle:accept(sender_peer_id, schema, payload)
	end

	_om._cwv_identity_descriptor_for_peer = function(peer_id, slot_name, base_name)
		return lifecycle:descriptor(peer_id, slot_name, base_name)
	end

	mod._cwv_peer_appearance = { schema = 1, resolve_peer = _om._cwv_identity_descriptor_for_peer }

	_om._cwv_identity_def_for_peer = function(peer_id, slot_name, base_name)
		local descriptor, state = lifecycle:descriptor(peer_id, slot_name, base_name)
		local def = descriptor and _find_def(descriptor.variant_key)
		return def, state
	end

	_om._husk_identity_descriptor = function(owner_unit_3p, slot_name, base_name)
		if not owner_unit_3p then return nil, "none" end
		local player
		pcall(function() player = Managers.player:owner(owner_unit_3p) end)
		local peer_id = player and (player.peer_id or (player.network_id and player:network_id()))
		return lifecycle:descriptor(peer_id, slot_name, base_name)
	end

	_om._husk_identity_def = function(owner_unit_3p, slot_name, base_name)
		local descriptor, state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
		return descriptor and _find_def(descriptor.variant_key) or nil, state
	end

	local function _send_identity_slots(slots, context, force, recipient, partial)
		local sent = lifecycle:publish(slots, context, recipient or "others", force, partial)
		if sent > 0 then
			pcall(printf, "[cwv:396/660] exact identity replay: context=%s recipient=%s slots=%d",
				tostring(context), tostring(recipient or "others"), sent)
		end
		return sent
	end
	_om._cwv_send_identity_slots = _send_identity_slots

	local peer_pull = _om.identity_peer_pull.bind(lifecycle, _send_identity_slots, _om.appearance_lifecycle_policy, printf)
	_om._cwv_request_peer_identities = peer_pull.request

	mod:network_register("cwv_item_identity", function(sender_peer_id, schema, payload)
		-- #474: the Old Musket shot report rides this channel (the dedicated
		-- mode channel never delivered in the 2026-07-18 paired logs). The
		-- sentinel slot fails valid_slot() in accept() on builds without this
		-- code, so mixed-version lobbies drop it safely.
		if type(payload) == "table" and payload.slot == "cwv_musket_fire" then
			if schema == _IDENTITY_SCHEMA and _om._old_musket_play_remote_fire then
				_om._old_musket_play_remote_fire(sender_peer_id, payload.fire_event,
					"identity_channel")
			end
			return
		end
		if type(payload) == "table"
				and payload.slot == _om.appearance_lifecycle_policy.REQUEST_SLOT then
			peer_pull.accept(sender_peer_id, schema, payload)
			return
		end
		-- #660 cold-join delivery acknowledgement. A targeted send from inside
		-- GearUtils.hot_join_sync can be accepted by the sender before the joining
		-- peer's VMF handler is ready. The sender retries only the two semantic
		-- identity slots on a bounded cadence until this ACK proves receipt.
		if type(payload) == "table"
				and payload.slot == _om.appearance_lifecycle_policy.ACK_SLOT then
			local accepted = lifecycle:accept_ack(sender_peer_id, schema, payload)
			if accepted then
				pcall(printf,
					"[cwv:660] lifecycle=hot_join_retry adapter=identity_ack peer=%s slot=%s descriptor=%s pending=%d",
					tostring(sender_peer_id), tostring(payload.ack_slot),
					tostring(payload.fingerprint), lifecycle:pending_delivery_count())
			end
			return
		end
		local changed, descriptor, reason = _om._cwv_accept_identity(sender_peer_id, schema, payload)
		-- #474: apply stance BEFORE the changed-gate. A stance toggle changes
		-- musket_mode while the identity signature stays identical, so the
		-- accept() dedupe must not swallow it.
		if type(payload) == "table" and payload.item_key == "cwv_es_musket_old"
				and (payload.musket_mode == "melee" or payload.musket_mode == "ranged")
				and _om._old_musket_accept_mode then
			_om._old_musket_accept_mode(sender_peer_id, payload.slot,
				payload.musket_mode, nil, "identity_channel")
		end
		-- #786 B3: apply the style axis BEFORE the changed-gate, for the same
		-- reason as the stance rider above -- a style switch leaves the identity
		-- signature byte-identical, so accept()'s dedupe would swallow it. Both
		-- channels converge on ONE state; this path owns the guarded re-wield.
		local style_owned = false
		if type(payload) == "table" and _om.combat_styles then
			local fam, sid = _om.combat_style_policy.decode_style_rider(payload.style)
			if fam then style_owned = _om.combat_styles:accept_style_edge(
				sender_peer_id, payload.slot, fam, sid, "identity") == true end
		end
		-- ACK both a first delivery and a duplicate retry. `descriptor` is non-nil
		-- only after this peer reconstructed the exact local resources, so the ACK
		-- never falsely confirms an unavailable/fingerprint-mismatched appearance.
		if descriptor then
			local ack = lifecycle:ack_payload(payload)
			if ack then
				pcall(mod.network_send, mod, "cwv_item_identity",
					sender_peer_id, _IDENTITY_SCHEMA, ack)
			end
		end
		if not changed then return end
		pcall(printf, "[cwv:396/660] exact identity received: peer=%s slot=%s key=%s descriptor=%s state=%s",
			tostring(sender_peer_id), tostring(payload and payload.slot),
			tostring(payload and payload.item_key),
			tostring(descriptor and descriptor.fingerprint or "vanilla"), tostring(reason))
		-- Rebuild the currently wielded husk once, DEFERRED through the per-wearer
		-- coalescer (#1145: one re-wield per wearer per frame, husk game object
		-- re-checked at drain). Arrival ordering converges without polling; the
		-- resolution and both gates live in the coalescer module.
		-- #786: skip when the style ledger already queued THIS (peer, slot) --
		-- the coalescer keeps newest-wins, so an unverified duplicate would
		-- replace the ledger's verifying executor and strand its verdict.
		if not style_owned then
			mod._cwv_rewield.request_peer_rewield(sender_peer_id, payload and payload.slot)
		end
	end)

	-- Issues #476/#741 diagnostic. The vanilla decision is now invariant: NULL.
	-- Exact remote appearance is independently observable on the semantic
	-- cwv_item_identity lifecycle logs, so a failed illusion can be assigned to the
	-- descriptor/husk consumer without ever re-enabling an unsafe numeric replay.
	_om._probe_476_logged = {}
	_om._probe_476 = function(context, skin)
		local key = tostring(context) .. "|" .. tostring(skin)
		if _om._probe_476_logged[key] then return end
		_om._probe_476_logged[key] = true
		pcall(printf,
			"[cwv:476/741] husk illusion transport (%s): skin=%s vanilla_wire=NULL identity_channel=cwv_item_identity",
			tostring(context), tostring(skin))
	end

	local _null_logged = {}
	local function _wire_null_skins(slots, send_fn, context)
		return _om.cosmetic_skin_wire.with_safe_slots(
			slots, _om._skin_keys, _custom_skin_keys, send_fn,
			function(_, skin)
				_om._probe_476(context, skin)
				local lk = tostring(context) .. "|" .. tostring(skin)
				if not _null_logged[lk] then
					_null_logged[lk] = true
					pcall(printf,
						"[cwv:741] wire skin null (%s): %s -> n/a (exact identity via cwv_item_identity)",
						tostring(context), tostring(skin))
				end
			end)
	end
	_om._wire_null_skins = _wire_null_skins   -- exported for /cwv_regression_test

	mod._cwv_skin_wire_surfaces = {}

	mod:hook("SimpleInventoryExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
		local slots = self and self._equipment and self._equipment.slots
		if not slots then
			return func(self, unit, unit_go_id)
		end
		_send_identity_slots(slots, "game_object_initialized", true)
		local r1, r2, r3, r4 = _wire_null_skins(slots, function()
			return func(self, unit, unit_go_id)
		end, "game_object_initialized")
		if _om._exact_pair_publish_inventory then
			_om._exact_pair_publish_inventory(self, "game_object_initialized")
		end
		-- Fatshark initializes and sends the complete vanilla equipment snapshot
		-- inside the wrapped function.  Request exact peer identities only after
		-- that boundary, and only for this VM's local human unit.
		peer_pull.request(unit, "game_object_initialized_ready")
		return r1, r2, r3, r4
	end)
	mod._cwv_skin_wire_surfaces.game_object_initialized = true
	mod._cwv_identity_surfaces.game_object_initialized = true
	mod._cwv_identity_surfaces.mission_transition = true
	mod._cwv_identity_surfaces.mission_transition_peer_pull = true

	mod:hook("SimpleInventoryExtension", "_spawn_resynced_loadout", function(func, self, equipment_to_spawn, skip_wield)
		if equipment_to_spawn and equipment_to_spawn.slot_id then
			-- #476 Defect B: single-slot resync = PARTIAL publish; no native record for the absent slot (see lifecycle module).
			_send_identity_slots({ [equipment_to_spawn.slot_id] = equipment_to_spawn },
				"spawn_resynced_loadout", false, nil, true)
		end
		if not (equipment_to_spawn and equipment_to_spawn.skin) then
			return func(self, equipment_to_spawn, skip_wield)
		end
		-- Single slot-shaped table; wrap in a one-element array for the helper.
		local r1, r2, r3, r4 = _wire_null_skins({ equipment_to_spawn }, function()
			return func(self, equipment_to_spawn, skip_wield)
		end, "spawn_resynced_loadout")
		if _om._exact_pair_publish_inventory then
			_om._exact_pair_publish_inventory(self, "spawn_resynced_loadout")
		end
		return r1, r2, r3, r4
	end)
	mod._cwv_skin_wire_surfaces.spawn_resynced_loadout = true
	mod._cwv_identity_surfaces.spawn_resynced_loadout = true

	mod:hook("GearUtils", "hot_join_sync", function(func, peer_id, unit, equipment, additional_items)
		local slots = equipment and equipment.slots
		if not slots then
			return func(peer_id, unit, equipment, additional_items)
		end
		-- #660: target the exact semantic descriptor to the joining CWV peer
		-- before vanilla's base-id equipment replay. VMF drops this channel for a
		-- peer without CWV; vanilla still receives only the safe base item/skin.
		-- Track exact slots BEFORE the first attempt so a very fast receiver ACK
		-- cannot race ahead of the pending ledger. The 2026-07-18 paired logs prove
		-- this first attempt may be dropped mid-handshake; the bounded retry below
		-- closes that readiness gap without weakening the vanilla fallback.
		local tracked = lifecycle:track_delivery(peer_id, slots, "hot_join_retry")
		_send_identity_slots(slots, "hot_join_sync", true, peer_id)
		if tracked > 0 then
			pcall(printf,
				"[cwv:660] lifecycle=hot_join_sync adapter=identity_delivery_tracked peer=%s slots=%d interval=%.1fs max_attempts=%d",
				tostring(peer_id), tracked,
				_om.appearance_lifecycle_policy.RETRY_INTERVAL,
				_om.appearance_lifecycle_policy.MAX_RETRY_ATTEMPTS)
		end
		local r1, r2, r3, r4 = _wire_null_skins(slots, function()
			return func(peer_id, unit, equipment, additional_items)
		end, "hot_join_sync")
		if _om._exact_pair_publish_local then
			_om._exact_pair_publish_local("hot_join_sync")
		end
		return r1, r2, r3, r4
	end)
	mod._cwv_skin_wire_surfaces.hot_join_sync = true
	mod._cwv_identity_surfaces.hot_join_sync = true

	-- #423 FOURTH sender (profile-sync / scoreboard channel). The three hooks
	-- above cover only rpc_add_equipment. CosmeticUtils.update_cosmetic_slot is a
	-- SEPARATE skin sender: SimpleInventoryExtension.add_equipment
	-- (simple_inventory_extension.lua:880) calls it on every (re)equip with
	-- slot_equipment_data.skin; vanilla encodes weapon_skins[skin] and
	-- player:set_data(slot.."_skin", id) into GameSession player-sync data
	-- broadcast to EVERY peer (cosmetic_utils.lua:244-250). A peer WITHOUT cwv
	-- decodes it on the scoreboard / playerlist read path (get_weapon_skin_name,
	-- cosmetic_utils.lua:168-178) and fatals -- the 2026-07-18 crash was
	-- weapon_skins index 924 (cwv_es_musket_old_skin) via
	-- rpc_sync_players_session_score at mission end. Husk rendering never reads
	-- this field, so the null is UNCONDITIONAL (never parity-gated) -- mirrors
	-- cosmetics' ct_* null at cosmetics_tweaker.lua:6200 (issue 421). CosmeticUtils
	-- is a plain table -> table-form hook + nil guard (CLAUDE.md "Hooking").
	-- cosmetics/cim hook the same function from THEIR mod ids; VMF chains those.
	if CosmeticUtils then
		mod:hook(CosmeticUtils, "update_cosmetic_slot", function(func, player, slot, item_name, skin_name)
			local safe, subbed = _om.cosmetic_skin_wire.wire_safe_skin(
				skin_name, _om._skin_keys, _custom_skin_keys)
			if subbed then
				local lk = "update_cosmetic_slot|" .. tostring(skin_name)
				if not _null_logged[lk] then   -- once per skin; no equip-spam
					_null_logged[lk] = true
					-- Log the LOCAL weapon_skins index so this apply-site line
					-- correlates with the [gut:272] pre-crash probe, which reports the
					-- divergent numeric index ("weapon_skins does not contain key: 924").
					local nl = rawget(_G, "NetworkLookup")
					local idx = nl and nl.weapon_skins and rawget(nl.weapon_skins, skin_name)
					pcall(printf, "[cwv:skin-wire] wire skin null (update_cosmetic_slot %s): %s (local weapon_skins idx=%s) -> n/a",
						tostring(slot), tostring(skin_name), tostring(idx))
				end
			end
			return func(player, slot, item_name, safe)
		end)
		mod._cwv_skin_wire_surfaces.update_cosmetic_slot = true
	end

	-- #741: a numeric vanilla skin replay can never be made safe by mod presence.
	-- Exact appearance recovery instead uses the acknowledged, bounded semantic
	-- identity delivery already stepped below.
	mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired = true
	mod._cwv_identity_surfaces.peer_ready = true

	local previous_update = mod.update
	mod.update = function(dt)
		if previous_update then previous_update(dt) end
		if _om._cwv_durable_crowbill_owner then
			_om._cwv_durable_crowbill_owner:step()
		end
		if _om.combat_styles and _om.combat_styles.step then
			_om.combat_styles:step(dt)
		end
		local identity_sent, identity_expired = lifecycle:step_deliveries(dt)
		peer_pull.step(dt)
		if identity_sent > 0 then
			pcall(printf,
				"[cwv:660] lifecycle=hot_join_retry adapter=identity_send attempts=%d pending=%d",
				identity_sent, lifecycle:pending_delivery_count())
		end
		if identity_expired > 0 then
			pcall(printf,
				"[cwv:660] lifecycle=hot_join_retry adapter=identity_timeout expired=%d pending=%d",
				identity_expired, lifecycle:pending_delivery_count())
		end
	end
end
_om._skin_wire_hook_installed = true

-- ============================================================================
-- issue 423 (BUG_CLASSES 31 + 64, GAMEPLAY axis): cwv damage-profile SEND-gate.
-- ----------------------------------------------------------------------------
-- rpc_attack_hit is client->server (weapon_system.lua:182). A cwv CLIENT landing
-- a hit with a profile-cloning variant would ship the cwv (out-of-vanilla-range)
-- NetworkLookup.damage_profiles index to the HOST, whose strict decode
-- (weapon_system.lua:243 -- NetworkLookup.damage_profiles[id], NO rawget) fatals
-- when the host lacks cwv -> lobby drop (issue 278 / BUG_CLASSES 31 class).
-- Unconditional registration only buys cwv<->cwv index parity, and #423 showed
-- that same-mod presence still does not prove the INTEGERS agree.
--
-- The hook, the exact catalog and the send state machine now live in
-- _cwv_exact_wire_runtime.install_damage -- the sole cwv registration on
-- WeaponSystem.send_rpc_attack_hit; do NOT re-add one here. It must run LAST:
-- capture() finalizes the whole cwv_* profile namespace, so every
-- _record_cwv_dp_source producer above has to have run first.
_om.exact_wire_runtime.install_damage(mod, _om)

-- NOTE: the per-perspective 1P/3P unit swap mechanism (previously used
-- for cwv_es_brace_repeater) was moved to weapon_tweaker in v0.1.187 —
-- it now hooks `GearUtils.spawn_inventory_unit` for vanilla
-- `wh_brace_of_pistols` on Kruber careers, swapping the 3P unit to
-- the repeater. No CWV variant currently uses the override mechanism;
-- if a future variant needs different 1P vs 3P meshes, restore the
-- hook here from git history.

local _crowbill_transform_miss_seen = {}
local _crowbill_transform_miss_total = 0
_om._appearance_world_seen = setmetatable({}, { __mode = "k" })
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	if not result then return result end

	local backend_id = item_data and (item_data.backend_id
		or (item_data.mod_data and item_data.mod_data.backend_id))
	local cwv_key = _om._cwv_key_for_item(backend_id, item_data)
	local descriptor
	if cwv_key then
		local reason
		descriptor, _, reason = _om._cwv_resolve_world_descriptor(item_data,
			result.skin, result.right_hand_unit_name, cwv_key, backend_id)
		if not descriptor then
			pcall(printf,
				"[cwv:660] lifecycle=world_spawn adapter=%s descriptor=DECLINED key=%s skin=%s reason=%s",
				is_bot and "bot" or "owner", tostring(cwv_key),
				tostring(result.skin), tostring(reason))
			_om.appearance_fade.created(unit_3p, result, is_bot); return result
		end
		local observed_unit = result.right_unit_3p or result.left_unit_3p
		if observed_unit and not _om._appearance_world_seen[observed_unit] then
			_om._appearance_world_seen[observed_unit] = descriptor.fingerprint
			pcall(printf,
				"[cwv:660] lifecycle=world_spawn adapter=%s slot=%s descriptor=%s right=%s left=%s",
				is_bot and "bot" or "owner", tostring(slot_name),
				tostring(descriptor.fingerprint), tostring(descriptor.right_hand_unit),
				tostring(descriptor.left_hand_unit))
		end
	end
	if cwv_key == "cwv_es_musket_old" then
		local musket_mode = item_data and item_data.mod_data
			and item_data.mod_data.cwv_musket_stance or "ranged"
		if not is_bot then
			_om.old_musket_appearance.reconcile(result.right_unit_1p,
				"owner_1p", "equip", item_data, musket_mode,
				{ unit_name = result.right_hand_unit_name })
		end
		_om.old_musket_appearance.reconcile(result.right_unit_3p,
			is_bot and "bot" or "owner_3p", "equip", item_data, musket_mode,
			{ unit_name = _om.old_musket_preview.UNIT_3P })
	end

	local def = _resolve_cwv_def(item_data, result.skin, result.right_hand_unit_name)
	if not def then
		local base_name = item_data and item_data.name
		local unit_name = result.right_hand_unit_name
		local looks_crowbill = base_name == _om.crowbill_family.SOURCE_ITEM
			or (type(unit_name) == "string" and unit_name:find("crowbill", 1, true))
		if looks_crowbill and _crowbill_transform_miss_total < 16 then
			local token = tostring(base_name) .. ":" .. tostring(unit_name) .. ":" .. tostring(result.skin)
			if not _crowbill_transform_miss_seen[token] then
				_crowbill_transform_miss_seen[token] = true
				_crowbill_transform_miss_total = _crowbill_transform_miss_total + 1
				pcall(printf,
					"[cwv:604] TRANSFORM MISS surface=create_equipment base=%s key=%s cwv_key=%s bid=%s mod_bid=%s skin=%s unit=%s career=%s count=%d/16",
					tostring(base_name), tostring(item_data and item_data.key),
					tostring(item_data and item_data.cwv_key),
					tostring(item_data and item_data.backend_id),
					tostring(item_data and item_data.mod_data and item_data.mod_data.backend_id),
					tostring(result.skin), tostring(unit_name), tostring(career_name),
					_crowbill_transform_miss_total)
			end
		end
		return result
	end

	_dbg("Applying transforms (slot=%s, skin=%s, item_key=%s, 3p_only=%s)",
		tostring(slot_name), tostring(result.skin), def.item_key, tostring(def.scale_3p_only or false))

	-- Per-perspective resolution: `_1p` / `_3p` variants override the unified
	-- field for that perspective only; if absent the unified field is used.
	-- scale_3p_only: skip 1P units (held first-person view) entirely but still
	-- apply 3P transforms (other players see this) and preview paths
	-- (HeroPreviewer / LootItemUnitPreviewer hooks below — 3P-style models).
	local right_scale     = _resolve_field(def, "right_hand_scale")
	local left_scale      = _resolve_field(def, "left_hand_scale")
	local right_offset    = _resolve_field(def, "right_hand_offset")
	local left_offset     = _resolve_field(def, "left_hand_offset")
	local right_scale_1p  = _resolve_field(def, "right_hand_scale_1p")  or right_scale
	local left_scale_1p   = _resolve_field(def, "left_hand_scale_1p")   or left_scale
	local right_offset_1p = _resolve_field(def, "right_hand_offset_1p") or right_offset
	local left_offset_1p  = _resolve_field(def, "left_hand_offset_1p")  or left_offset
	local right_scale_3p  = _resolve_field(def, "right_hand_scale_3p")  or right_scale
	local left_scale_3p   = _resolve_field(def, "left_hand_scale_3p")   or left_scale
	local right_offset_3p = _resolve_field(def, "right_hand_offset_3p") or right_offset
	local left_offset_3p  = _resolve_field(def, "left_hand_offset_3p")  or left_offset
	-- Rotation (WeaponAppearance): absolute-set orientation, resolved per hand
	-- per perspective exactly like scale/offset. nil = leave native orientation.
	local right_rot       = _resolve_field(def, "right_hand_rotation")
	local left_rot        = _resolve_field(def, "left_hand_rotation")
	local right_rot_1p    = _resolve_field(def, "right_hand_rotation_1p") or right_rot
	local left_rot_1p     = _resolve_field(def, "left_hand_rotation_1p")  or left_rot
	local right_rot_3p    = _resolve_field(def, "right_hand_rotation_3p") or right_rot
	local left_rot_3p     = _resolve_field(def, "left_hand_rotation_3p")  or left_rot
	if not def.scale_3p_only then
		_apply_cwv_hand_transform(result.right_unit_1p, def, "right", "1p", "owner_1p",
			result.right_hand_unit_name, result.skin)
		_apply_cwv_hand_transform(result.left_unit_1p, def, "left", "1p", "owner_1p",
			result.left_hand_unit_name, result.skin)
	end
	_apply_cwv_hand_transform(result.right_unit_3p, def, "right", "3p",
		is_bot and "bot" or "owner_3p", result.right_hand_unit_name, result.skin)
	_apply_cwv_hand_transform(result.left_unit_3p, def, "left", "3p",
		is_bot and "bot" or "owner_3p", result.left_hand_unit_name, result.skin)

	-- #604: same absolute pick/hammer face on held 1P and owner/bot 3P.
	-- Presentation composes from the authored rotation captured here; the weak
	-- record prevents the 180-degree delta accumulating on lifecycle replays.
	if def.crowbill_mode_family and _om._apply_crowbill_presentation then
		local crowbill_identity = _om._crowbill_render_identity(item_data, def,
			def.item_key .. ":" .. tostring(slot_name))
		_om._apply_crowbill_presentation(result.right_unit_1p, def, crowbill_identity,
			"owner_1p", right_rot_1p)
		_om._apply_crowbill_presentation(result.right_unit_3p, def, crowbill_identity,
			is_bot and "bot" or "owner_3p", right_rot_3p)
	end

	if cwv_key then _om.appearance_fade.created(unit_3p, result, is_bot) end; return result
end)

-- ============================================================
-- Keep/menu preview-surface owner (#1159)
-- ============================================================
-- Every MENU-side reconstruction of a CWV variant moved verbatim into one
-- owner: the shared HeroPreviewer / MenuWorldPreviewer `_spawn_item` applier
-- and its def resolver, the #604 TeamPreviewer lobby/score identity bridge,
-- the cosmetic picker's cwv-only illusion filter, the two preview teardown
-- edges, and the illusion browser / Athanor craft pane
-- (LootItemUnitPreviewer.spawn_units) with its #597 fallback, issue 419
-- mesh-swap pre-pass and #617 Old Musket texture rebind.
--
-- The other two presentation surfaces stay put: WORLD/BOT equipment is the
-- `GearUtils.create_equipment` hook directly above (it owns the transform-miss
-- evidence counters, which the menu owner never reads), and REMOTE husk display
-- is the husk module reached from the spawn hooks far above.
--
-- It loads HERE, at the exact point the moved block ran, so every hook it
-- registers keeps its original position relative to the surfaces around it.
-- All ten context bindings are entry file-scope locals declared above and
-- never rebound, so passing them by value cannot go stale.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_menu_preview_owner")(mod, {
	om = _om,
	dbg = _dbg,
	dbg_alert = _dbg_alert,
	resolve_field = _resolve_field,
	is_unit = _is_unit,
	transform_unit = _transform_unit,
	apply_cwv_hand_transform = _apply_cwv_hand_transform,
	transform_map = _transform_map,
	skin_transform_map = _skin_transform_map,
	crowbill_transform_by_unit = _crowbill_transform_by_unit,
})

-- Install commands and final callbacks only after every gameplay/render hook above.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_commands_lifecycle")(mod, {
    mod_version = MOD_VERSION,
    om = _om,
    dbg = _dbg,
    detect_companion_mods = _detect_companion_mods,
    variant_definitions = _variant_definitions,
    registered_keys = _om.item_registration.registered_keys,
    give_variant = _give_variant,
})

local _cwv_regression_context = {
	mod_version = MOD_VERSION,
	om = _om,
	dbg = _dbg,
	rt_register = _rt_register,
	variant_definitions = _variant_definitions,
	registered_keys = _om.item_registration.registered_keys,
	display_names = _display_names,
	find_def = _find_def,
	build_entry = _om.item_registration.build_entry,
	auto_register_all = _om.item_registration.auto_register_all,
	cross_access_action_remap = _cross_access_action_remap,
	wield_hook_registration_count = _cwv_wield_hook_registration_count,
	transform_map = _transform_map,
	skin_transform_map = _skin_transform_map,
	crowbill_transform_by_unit = _crowbill_transform_by_unit,
	custom_skin_keys = _custom_skin_keys,
}
mod:dofile("scripts/mods/character_weapon_variants/_cwv_regression_identity")(mod, _cwv_regression_context)
mod:dofile("scripts/mods/character_weapon_variants/_cwv_regression_render")(mod, _cwv_regression_context)
