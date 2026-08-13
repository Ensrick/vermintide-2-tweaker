local mod = get_mod("character_weapon_variants")
_MEM_PROBE_T0_CWV = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.1.514-dev"
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
-- Musket equip-surface owner, phase 1 (#1159)
-- ============================================================
-- The cross-slot inventory recognizer, the v0.1.338 scoped career slot_melee
-- override with its ItemGridUI / get_filtered_items post-filter, the defensive
-- WeaponSpreadExtension pair and the whole musket bayonet child-unit lifecycle
-- (constants, ledger, package force-loads, spawn / wield / camera / destroy
-- hooks) live in the musket equip-surface owner. That block was INTERLEAVED
-- here, so the owner installs in two phases: this load runs the first half at
-- the exact point the inline code did and hands back the second half, which the
-- entry calls at its own former position further down.
local _install_musket_spawn_surface =
	mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_equip_surface")(mod, {
		om = _om,
		dbg = _dbg,
		variant_definitions = _variant_definitions,
	})

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

-- ============================================================
-- Musket equip-surface owner, phase 2 (#1159)
-- ============================================================
-- Second half of the owner loaded above: the bayonet spawn / attach / detach
-- helpers and the GearUtils.spawn_inventory_unit, SimpleInventoryExtension
-- _wield_slot / show_first_person_inventory / show_third_person_inventory and
-- GearUtils.destroy_wielded registrations. Called HERE so those five hooks
-- register in the same order relative to every other cwv hook as before.
_install_musket_spawn_surface()

-- ============================================================
-- Custom-mesh runtime owner (#1159)
-- ============================================================
-- Everything that makes a CWV MOD-BUNDLED custom weapon mesh behave like a
-- vanilla weapon unit moved verbatim into one owner: the LA-pattern
-- PackageManager load/unload/has_loaded shims with the #474 husk bundle-unit
-- predicate, the forward-only NetworkLookup.inventory_packages aliases (Old
-- Musket plus the #597 Greataxe and #604 Crowbill installs), the Old Musket
-- transform constants and their single `_om._old_musket_transform_components`
-- reader, the #617/#742 texture re-exports and the #1155 Phase 3 appearance
-- pilot with its preview descriptor seams, the #474 stance-channel dofile, the
-- v0.1.293 FX-proxy lifecycle with its four Unit node/flow redirect hooks, and
-- the v0.1.290 attachment-node filter.
--
-- The Old Musket's item/template/stance behavior stays in _cwv_musket_runtime,
-- its native texture writes stay in _cwv_old_musket_preview, and the bayonet
-- child-unit lifecycle stays in this entry directly above - a bayonet is a
-- second vanilla unit linked to the rifle, not a custom-mesh gap.
--
-- It loads HERE, at the exact point the moved block ran, so every hook keeps its
-- original registration position and every `_om` slot it publishes appears at
-- the same moment in load as before.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_custom_mesh_runtime")(mod, {
	om = _om,
	dbg = _dbg,
	dbg_alert = _dbg_alert,
})

-- ============================================================
-- Tuskgor Javelin runtime owner (#1159)
-- ============================================================
-- Registration, pickup/projectile wire containment, carrier visuals, the
-- finite-stack weapon template, and the grenade-slot variant share one owner.
local _javelin_runtime =
	mod:dofile("scripts/mods/character_weapon_variants/_cwv_javelin_runtime_owner")(mod, {
		om = _om,
		dbg = _dbg,
		clone_damage_profile = _clone_damage_profile,
	})
local _always_false = _javelin_runtime.always_false

-- Rapier construction retains its historical post-javelin install point.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_rapier_runtime_owner")(mod, {
	om = _om,
	always_false = _always_false,
})

-- NOTE: brace_repeater_template + cwv_es_brace_repeater variant moved to
-- weapon_tweaker in v0.1.187 (CWV-side). The functionality lives there
-- now as a 3P unit swap on Kruber's vanilla wh_brace_of_pistols
-- cross-access — no separate inventory item.

-- Variant localization/unlock bootstrap. Its returned phases preserve the
-- historical skin-registration and item-registration boundaries below.
local _finish_variant_skins =
	mod:dofile("scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner")(mod, {
		om = _om,
		variant_definitions = _variant_definitions,
	})
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

local _finish_variant_registration = _finish_variant_skins(_custom_skin_keys)

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

local _variant_runtime = _finish_variant_registration()
local _detect_companion_mods = assert(_variant_runtime.detect_companion_mods, "cwv variant bootstrap did not export detect_companion_mods")
local _find_def, _give_variant = _variant_runtime.find_def, _variant_runtime.give_variant
-- ============================================================
-- Weapon transform owner (#1159)
-- ============================================================
-- Which transform record applies to an item/skin/unit, and how that record is
-- written onto a spawned weapon unit, both live in the weapon-transform owner
-- dofiled below. It holds the authored type table, `_resolve_field`, the four
-- transform registries (variant / skin / Greataxe / Crowbill-by-unit), the shared
-- WeaponAppearance instance, the #604 Crowbill presentation and durable-transform
-- wiring, the single per-hand applier, and the `_resolve_cwv_def` /
-- `_om._cwv_resolve_crowbill_transform` / husk transform-policy resolvers.
--
-- It is a PRODUCER, not a surface: it registers no hook, no network channel and
-- no command. The four consumers stay put and keep calling in - the
-- `GearUtils.create_equipment` world/bot hook below (which keeps its own
-- transform-miss evidence counters), the keep/menu preview owner, the husk
-- display module, and the #1158 exact-appearance descriptors. Loaded HERE, at the
-- exact point the inline blocks ran, so registry construction still happens
-- before the Combat Style install below reads `cwv_imperial_longsword` out of the
-- type table and before any surface can resolve a def.
mod:dofile("scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner")(mod, {
	om = _om,
	variant_definitions = _variant_definitions,
	find_def = _find_def,
	custom_illusions = _custom_illusions,
	custom_skin_keys = _custom_skin_keys,
})

-- Re-bound under their original names so every surviving statement below is
-- byte-identical to what it was before the move. Each value is the same object
-- the owner built; the maps are shared table references, not copies.
local _type_transforms            = _om.weapon_transform.type_transforms
local _resolve_field              = _om.weapon_transform.resolve_field
local _transform_map              = _om.weapon_transform.transform_map
local _skin_transform_map         = _om.weapon_transform.skin_transform_map
local _crowbill_transform_by_unit = _om.weapon_transform.crowbill_transform_by_unit
local _is_unit                    = _om.weapon_transform.is_unit
local _transform_unit             = _om.weapon_transform.transform_unit
local _triplet_text               = _om.weapon_transform.triplet_text
local _apply_cwv_hand_transform   = _om.weapon_transform.apply_cwv_hand_transform
local _resolve_cwv_def            = _om.weapon_transform.resolve_cwv_def

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

-- Exact item/loadout identity transport owner (#1159).
mod:dofile("scripts/mods/character_weapon_variants/_cwv_item_identity_transport_owner")(mod, {
	om = _om,
	find_def = _find_def,
	custom_skin_keys = _custom_skin_keys,
})

-- NOTE: the per-perspective 1P/3P unit swap mechanism (previously used
-- for cwv_es_brace_repeater) was moved to weapon_tweaker in v0.1.187 —
-- it now hooks `GearUtils.spawn_inventory_unit` for vanilla
-- `wh_brace_of_pistols` on Kruber careers, swapping the 3P unit to
-- the repeater. No CWV variant currently uses the override mechanism;
-- if a future variant needs different 1P vs 3P meshes, restore the
-- hook here from git history.

-- Owner/bot world-equipment reconstruction surface (#1159).
mod:dofile("scripts/mods/character_weapon_variants/_cwv_world_equipment_owner")(mod, {
	om = _om,
	dbg = _dbg,
	resolve_field = _resolve_field,
	resolve_cwv_def = _resolve_cwv_def,
	apply_cwv_hand_transform = _apply_cwv_hand_transform,
})

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
