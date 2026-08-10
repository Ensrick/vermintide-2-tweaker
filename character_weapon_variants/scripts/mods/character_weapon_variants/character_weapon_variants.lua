local mod = get_mod("character_weapon_variants")
_MEM_PROBE_T0_CWV = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.1.509-dev"
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
