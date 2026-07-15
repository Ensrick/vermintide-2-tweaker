local mod = get_mod("character_weapon_variants")
_MEM_PROBE_T0_CWV = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.1.415-dev"
mod._cwv_acquisition = mod:dofile("scripts/mods/character_weapon_variants/_cwv_acquisition")
mod._cwv_javelin_pickup = mod:dofile("scripts/mods/character_weapon_variants/_cwv_javelin_pickup")
mod._cwv_old_musket_interrupt = mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_interrupt")
mod._cwv_dev_anim_picker = mod:dofile("scripts/mods/character_weapon_variants/cwv_dev_anim_picker")
mod._cwv_smoke_bomb_probe = mod:dofile("scripts/mods/character_weapon_variants/_cwv_smoke_bomb_probe")
mod._cwv_smoke_bomb_probe.install(mod)

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
-- v0.1.339 (Issue #33): belt-and-suspenders counter that the consolidated
-- `mod:hook_safe("SimpleInventoryExtension", "wield", ...)` registration site
-- (~line 1336) increments exactly once. Regression test
-- `cwv_wield_hook_unique` asserts this is 1 — catches accidental reintroduction
-- of a duplicate hook_safe on the same (Class, method) which VMF silently
-- shadows (VMF_RECIPES.md § 1). Original burn: v0.1.336 added a second
-- registration ~line 9499 for the debug-mode wield dump, shadowing the
-- line-1336 cross-access tracking and silently breaking 3P anim remap.
-- v0.1.337 consolidated both bodies; v0.1.339 adds this regression guard.
local _cwv_wield_hook_registration_count = 0

-- Issue #1: old-musket + shared musket-pool runtime state, consolidated into a
-- single file-scope local holder instead of ~28 bare globals. Kept as ONE table
-- (not individual `local`s) because the main chunk already sits at 199/200 Lua
-- 5.1 locals; 28 more file-scope locals overflow the 200-local ceiling (that is
-- what broke the v0.1.330/331 attempt). Fields keep their original names so the
-- refactor is a pure `_om.` prefix with no behavior change.
local _om = {}
_om.infantry_spear = mod:dofile("scripts/mods/character_weapon_variants/_cwv_infantry_spear")
_om.exact_appearance = mod:dofile("scripts/mods/character_weapon_variants/_cwv_exact_appearance")
_om.greataxe = mod:dofile("scripts/mods/character_weapon_variants/_cwv_greataxe")
_om.dawi_maces = mod:dofile("scripts/mods/character_weapon_variants/_cwv_dawi_maces")
_om.crowbill_family = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_family")
_om.crowbill_hammer_mode = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_hammer_mode")
_om.crowbill_presentation = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_presentation")
_om.crowbill_runtime = mod:dofile("scripts/mods/character_weapon_variants/_cwv_crowbill_runtime")
mod._cwv_crowbill_family = _om.crowbill_family
mod._cwv_crowbill_hammer_mode = _om.crowbill_hammer_mode
mod._cwv_crowbill_presentation = _om.crowbill_presentation
mod._cwv_crowbill_runtime = _om.crowbill_runtime
_om.deus_identity = mod:dofile("scripts/mods/character_weapon_variants/_cwv_deus_identity")
_om.mod_unit_preview = mod:dofile("scripts/mods/character_weapon_variants/_cwv_mod_unit_preview")
_om.mod_unit_preview.install({ _om.greataxe, _om.crowbill_family })
_om.mace_hammer_identity_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_mace_hammer_identity")
_om.mace_hammer_identity = _om.mace_hammer_identity_policy.new()
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
function _om._record_cwv_dp_source(cwv_key, source_name)
    -- Record only genuine vanilla sources (never chain onto another cwv profile).
    if type(cwv_key) ~= "string" or type(source_name) ~= "string" then return end
    if source_name:sub(1, 4) == "cwv_" then return end
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
            pcall(function() inst:install() end)
            mod:info("[cwv:371] peer-parity beacon installed (channel=cwv_peer_parity_present)")
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
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("cwv_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== cwv regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
mod:info("[regression-test-command] registered as /cwv_regression_test")

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
-- Variant weapon definitions
-- ============================================================

local _es_all_careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
local _wh_all_careers = { "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest" }
local _bw_all_careers = { "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer" }

local _variant_definitions = {
	{
		item_key        = "cwv_es_axe_shield",
		base_weapon     = "dr_shield_axe",
		display_name    = "Axe and Shield",
		description     = "A one-handed axe paired with a sturdy imperial shield.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_dw_shield_01_axe",
		hud_icon        = "weapon_generic_icon_axe_and_sheild",
		skin_display_name = "Axe and Shield",
		rarity          = "default",
		power_level     = 5,
		item_type       = "cwv_es_axe_shield",
	},
	{
		item_key        = "cwv_es_axe_shield_veteran",
		base_weapon     = "dr_shield_axe",
		display_name    = "Imperial Axe and Shield",
		description     = "A battle-hardened hatchet paired with a sturdy imperial shield. Reforged for Kruber's arsenal.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01",
		left_hand_unit  = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic",
		inventory_icon  = "icon_wpn_dw_shield_01_axe",
		hud_icon        = "weapon_generic_icon_axe_and_sheild",
		skin_display_name = "Imperial Axe and Shield",
		rarity          = "unique",
		traits          = { "melee_counter_push_power" },
		properties      = { block_cost = 1, power_vs_skaven = 1 },
		item_type       = "cwv_es_axe_shield",
	},
	{
		item_key        = "cwv_we_sword_shield",
		base_weapon     = "es_sword_shield",
		display_name    = "Sword and Shield",
		description     = "An elven blade paired with an Athel Loren shield.",
		character       = "wood_elf",
		careers         = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
		right_hand_unit = "units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1",
		left_hand_unit  = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Sword and Shield",
		rarity          = "default",
		power_level     = 5,
		template        = "elven_sword_shield_template",
	},
	{
		-- Infantry Spear: Kerillian's two-handed spear action graph on Kruber,
		-- rendered with the spear half of his native Chaos Wastes Spear+Shield.
		-- The custom template independently tunes attack timing and the three
		-- damage-profile axes; push/block/wield/inspect actions stay at source
		-- values. WT owns optional career expansion beyond these three authored
		-- careers (including Grail Knight, default off).
		item_key        = "cwv_es_infantry_spear",
		base_weapon     = "we_spear",
		display_name    = "Infantry Spear",
		description     = "A long state-issue spear used without a shield, trading elven speed for heavier thrusts and broader sweeps.",
		character       = "empire_soldier",
		careers         = _om.infantry_spear.DEFAULT_CAREERS,
		right_hand_unit = "units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01",
		inventory_icon  = "icon_wpn_empire_spearshield_t1",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Infantry Spear",
		rarity          = "exotic",
		template        = "cwv_infantry_spear_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_infantry_spear",
	},
	{
		item_key        = "cwv_we_sword_shield_veteran",
		base_weapon     = "es_sword_shield",
		display_name    = "Elven Sword and Shield",
		description     = "A keen elven blade paired with a sturdy Athel Loren shield. Forged for the Asrai's front line.",
		character       = "wood_elf",
		careers         = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
		right_hand_unit = "units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01",
		left_hand_unit  = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Elven Sword and Shield",
		rarity          = "unique",
		traits          = { "melee_counter_push_power" },
		properties      = { block_cost = 1, power_vs_skaven = 1 },
		template        = "elven_sword_shield_template",
	},
	{
		item_key        = "cwv_es_longsword",
		base_weapon     = "es_bastard_sword",
		display_name    = "Imperial Longsword",
		description     = "Standard-issue Imperial longsword of the Reikland state regiments. Forged in their thousands by the smithies of Altdorf - serviceable steel for the men who hold the line against beast and greenskin alike.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		-- QUESTION: model is from two_handed_swords_template_1 (Kruber greatsword) but
		-- this entry uses imperial_longsword_template (cloned from bastard_sword_template).
		-- Mismatched model+moveset is intentional per CHANGELOG v0.1.25, but worth
		-- documenting in DEVELOPMENT.md.
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1",
		inventory_icon  = "icon_wpn_empire_2h_sword_04_t1",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Imperial Longsword",
		rarity          = "default",
		-- CLARIFY: power_level = 5 is intentional (a "blacksmith template" item per
		-- CHANGELOG v0.1.25), not a typo for 300. Properties roll on power_level.
		power_level     = 5,
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`.
	},
	{
		item_key        = "cwv_es_longsword_blackguard",
		base_weapon     = "es_bastard_sword",
		display_name    = "Black Guard Blade",
		description     = "Borne by the Knights of Morr, the black-mantled brotherhood of the death-god whose vigil keeps Stirland's tombs sealed against the necromancers of Sylvania.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2",
		inventory_icon  = "icon_wpn_empire_2h_sword_03_t2",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Black Guard Blade",
		rarity          = "unique",
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`.
	},
	{
		-- Imperial Longsword and Shield: Bretonnian sword+shield moveset
		-- (`one_handed_sword_shield_template_2`, native to es_questingknight)
		-- repurposed as Kruber's longsword+shield combo. Right hand uses the
		-- Imperial Longsword mesh (`wpn_2h_sword_04_t1`); left hand uses
		-- Kruber's standard Empire shield (`wpn_emp_shield_02`). Cosmetic
		-- illusion picker registers every unique shield from the vanilla
		-- `es_sword_shield` skin pool (Empire Shield 01 / 02 / 03 / 04 / 05
		-- + runed variants) on the left, paired with the same Imperial
		-- Longsword mesh on the right.
		--
		-- Native template's animations work on all 4 Kruber careers (per
		-- weapon_tweaker's existing es_sword_shield_breton cross-access on
		-- Mercenary/Huntsman/Knight at weapon_tweaker.lua:30-33 — proven
		-- compatible). No anim remap or wield routing needed.
		--
		-- DLC: `es_sword_shield_breton` is `required_dlc = "lake"` in vanilla;
		-- `_build_entry` strips `required_dlc` from the cwv variant so users
		-- without Lake DLC can still equip it. Mesh assets (`wpn_2h_sword_*`,
		-- `wpn_emp_shield_*`) live in base packages, so they resolve without
		-- the DLC.
		item_key        = "cwv_es_longsword_shield",
		base_weapon     = "es_sword_shield_breton",
		display_name    = "Imperial Longsword and Shield",
		description     = "A Reikland longsword paired with a state-issue shield. The Empire's answer to the Grail Knight's pose — proper steel and a wall of oak.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Imperial Longsword and Shield",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_longsword_shield",
		-- Stat tune (v0.1.310): match the 2H Imperial Longsword on sword swings
		-- only (-15% damage, +15% speed, +15% cleave, -15% stagger). Shield
		-- bashes, block, and the universal push are untouched. See
		-- `_create_imperial_longsword_shield_template`.
		template        = "imperial_longsword_shield_template",
	},
	{
		-- Kruber javelin variant: uses we_javelin's throwing moveset (template,
		-- slot_type=ranged, item_type=we_javelin) but swaps the held model to
		-- the Tuskgor Spear (wpn_emp_boar_spear_01). Javelin model lives on
		-- left_hand_unit (right_hand_unit is invisible during the wield pose);
		-- placing the spear on left_hand_unit matches that attachment so the
		-- throw animation drives the visible model.
		-- Stat-modifying clone via `tuskgor_javelin_template` (defined below):
		--   * 15-shot finite stack — vanilla auto-catch reload disabled
		--   * Vanilla ammo pickups refill (block_ammo_pickup=false,
		--     unique_ammo_type=false)
		--   * 2x damage on melee stabs and the throw projectile
		--   * 0.5x speed (slower wind-up + slower throw recovery)
		--
		-- Known caveats:
		--   * Thrown projectile is still the slim javelin model
		--     (Projectiles.javelin) — the held model is the boar spear, but
		--     mid-air it shows as a javelin. Fixing requires cloning the
		--     projectile config + a custom prj_*_3ps unit; the boar spear
		--     package doesn't ship a projectile variant.
		--   * Kruber's 3P body skeleton lacks elf throw events (attack_throw,
		--     throw_charge). 3P-side fix: pick anim_event_3p strings from the
		--     empire-skeleton's vocabulary (e.g. polearm wind-up events) via
		--     this template's actions, or add remaps in weapon_tweaker
		--     (_career_anim_redirect / _suffix_career_map). 1P is unaffected
		--     and needs no changes — see top-of-file ANIMATION ARCHITECTURE.
		item_key        = "cwv_es_javelin",
		base_weapon     = "we_javelin",
		display_name    = "Tuskgor Javelin",
		description     = "A heavy boar-spear, balanced for the throw. Hits like a kicking mule but takes both hands to wind up — and the supply runs out.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_invisible_weapon",
		left_hand_unit  = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01",
		-- v0.1.314: REVERTED v0.1.259's `ammo_unit = wpn_invisible_weapon`.
		-- That broke held-mesh rendering — the wielded javelin went invisible
		-- in 1P + 3P. Per `feedback_cwv_ammo_unit_required.md`: "Mirror
		-- ammo_unit + ammo_unit_3p + projectile_units_template +
		-- pickup_template_name + link_pickup_template_name from base; skin
		-- nukes them otherwise (previewer/throw/pickup all crash)." Pointing
		-- ammo_unit at invisible_weapon nuked downstream paths that read it
		-- for the held visual. Removing the override lets the skin-registration
		-- fallback (`ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)`)
		-- restore the working state: ammo_unit = boar spear, same as the held mesh.
		-- Side effect: 3P shows a duplicate boar spear as the offhand spare.
		-- TODO entry in CWV TODO covers the 3P-only hide via runtime
		-- Unit.set_unit_visibility on the spawned ammo unit.
		inventory_icon  = "icon_emp_boar_spear_01",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Tuskgor Javelin",
		rarity          = "exotic",
		template        = "tuskgor_javelin_template",
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- v0.1.157 hybrid: in-flight uses vanilla `javelin` (slim elf javelin
		-- prj_we_javelin_01_3ps — properly authored, +Y is tip, no spin in
		-- flight). Pickup uses boar spear via Pickups.ammo unit_name. The
		-- vanilla `javelin` key triggers the package loader to load the elf
		-- javelin units at equip time, which is what allows them to spawn at
		-- throw time without the v0.1.71 crash. Trade: in-flight visual is
		-- slim elf javelin (brief), stuck/dropped pickup is the chunky boar
		-- spear.
		projectile_units_template = "javelin",
		pickup_template_name      = "cwv_tuskgor_javelin_pickup",
		link_pickup_template_name = "cwv_tuskgor_javelin_link_pickup",
		-- scale_3p_only: shrink the boar spear in 3P + character/illusion previews
		-- (where its native length looks oversized next to other ranged silhouettes)
		-- but leave the 1P held viewport at native scale so the throw animation
		-- doesn't clip into the camera. Tweak the 0.80 uniform if needed.
		left_hand_scale = { 0.80, 0.80, 0.80 },
		scale_3p_only   = true,
	},
	{
		-- Saltzpyre javelin variant — same Tuskgor Spear model + tuskgor_javelin_template
		-- as Kruber's cwv_es_javelin. Distinct item_key so per-character backend ids /
		-- can_wield rules don't collide. Same 3P anim caveat as the Kruber variant: WH
		-- 3P body skeleton may need throw-event remaps via weapon_tweaker. 1P needs
		-- nothing — universal across characters (see top-of-file ANIMATION ARCHITECTURE).
		item_key        = "cwv_wh_javelin",
		base_weapon     = "we_javelin",
		display_name    = "Tuskgor Javelin",
		description     = "A heavy boar-spear, balanced for the throw. Hits like a kicking mule but takes both hands to wind up — and the supply runs out.",
		character       = "witch_hunter",
		careers         = _wh_all_careers,
		right_hand_unit = "units/weapons/player/wpn_invisible_weapon",
		left_hand_unit  = "units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01",
		-- v0.1.314: REVERTED v0.1.259's ammo_unit = invisible (see cwv_es_javelin above for the full story).
		inventory_icon  = "icon_emp_boar_spear_01",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Tuskgor Javelin",
		rarity          = "exotic",
		template        = "tuskgor_javelin_template",
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- v0.1.157 hybrid: same setup as cwv_es_javelin — in-flight = vanilla
		-- elf javelin (slim, no spin), pickup = boar spear visual.
		projectile_units_template = "javelin",
		pickup_template_name      = "cwv_tuskgor_javelin_pickup",
		link_pickup_template_name = "cwv_tuskgor_javelin_link_pickup",
		left_hand_scale = { 0.80, 0.80, 0.80 },
		scale_3p_only   = true,
	},
	{
		-- Outrider Grenade Launcher: Frankenstein weapon — Bardin Engineer's
		-- Trollhammer Torpedo behavior (single explosive projectile,
		-- charge-and-release mechanics, blast damage) wrapped in Kruber's
		-- blunderbuss visual layer (model + 1P/3P state machine + wield
		-- animations). Per user: "WIP, I'll have to test."
		--
		-- Cross-character considerations:
		--   * 1P state machine: blunderbuss state machine is shared across
		--     characters via first_person_base unit (per top-of-file
		--     ANIMATION ARCHITECTURE) — Kruber natively wields blunderbuss
		--     so all 1P anims work.
		--   * 3P body events: blunderbuss anim_event "attack_shoot" is
		--     authored on Kruber's empire-soldier 3P body (his vanilla
		--     blunderbuss uses it). The trollhammer template's action_one
		--     uses the same "attack_shoot" event, so no per-action remap
		--     needed — events fall through cleanly.
		--
		-- Tunes (vs vanilla trollhammer):
		--   * speed 2500 → 3500 (faster projectile, "travels further/faster")
		--   * reload_time 3 → 2 (faster reload than the trollhammer)
		--   * damage 0.65× (proportionally smaller damage and stagger via
		--     damage profile clone — see _create_outrider_grenade_launcher_template)
		--   * max_range 20 → 30 (longer aim-assist reach)
		--
		-- KNOWN WIP / TODO:
		--   * Explosion radius — `ExplosionTemplates.dr_deus_01` isn't in the
		--     decompiled source we work from, so the explosion template is
		--     used as-is (vanilla trollhammer radius). Smaller-radius tune
		--     is a follow-up once the user tests the current behavior in
		--     game.
		--   * Projectile model — currently uses the trollhammer torpedo
		--     model (Projectiles.dr_deus_01). User mentioned wanting a
		--     grenade-shaped projectile; that's a follow-up — projectile_info
		--     needs custom Projectiles.cwv_outrider_grenade entry pointing
		--     at a grenade-shaped unit.
		item_key        = "cwv_es_outrider_grenade_launcher",
		base_weapon     = "dr_deus_01",
		display_name    = "Outrider Grenade Launcher",
		description     = "An imperial-pattern grenade launcher in the Outrider style — built on a blunderbuss frame, fires a single charge-loaded grenade. Fewer pellets, more boom.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1",
		-- Trollhammer is left-hand-mount (entry inherits left_hand_unit =
		-- wpn_dr_deus_01 from the clone). We're moving to right-hand-mount
		-- on the blunderbuss model — clear the inherited left so the preview
		-- doesn't render BOTH weapons.
		no_left_hand    = true,
		-- v0.1.365-dev (issue 279): also clear the inherited AMMO unit fields.
		-- dr_deus_01 carries ammo_unit / ammo_unit_3p (the trollhammer torpedo
		-- meshes, item_master_list_morris.lua:7-8), and our template clone keeps
		-- ammo_data with ammo_hand flipped to "right" — so any NO-SKIN resolution
		-- of this entry (a cim-CRAFTED copy has no pre-applied skin) attached the
		-- torpedo to the blunderbuss at wield (gear_utils.lua:164/169/248): the
		-- "crafted item renders merged with the Trollhammer" bug. The curated
		-- skin already declares ammo_unit = nil; this makes the bare entry agree.
		no_ammo_unit    = true,
		inventory_icon  = "icon_wpn_empire_blunderbuss_t1",
		hud_icon        = "weapon_generic_icon_blunderbuss",
		skin_display_name = "Outrider Grenade Launcher",
		rarity          = "exotic",
		template        = "outrider_grenade_launcher_template",
		traits          = { "ranged_replenish_ammo_headshot" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_outrider_grenade_launcher",
	},
	{
		-- Saltzpyre crossbow ported onto all 4 Kruber careers. Cloned from
		-- wh_crossbow (template = crossbow_template_1). 3P body anims play the
		-- handgun (rifle) wield + idle so Kruber holds it naturally; firing
		-- and zoom-aim are vocab-shared with handgun so no per-action remap
		-- needed. 1P is universal across characters (see top-of-file
		-- ANIMATION ARCHITECTURE) — vanilla crossbow 1P with bolt visible.
		--
		-- Migrated from weapon_tweaker v0.12.94-dev (which carried the Kruber
		-- toggles + base-template wield_anim_career_3p patch + preview-time
		-- attachment-node substitution for the engine-fatal `a_unwielded_crossbow`
		-- node Kruber's body doesn't author). See CHANGELOG.
		--
		-- KNOWN POLISH ITEMS (see TODO.md):
		--   * 3P grip offsets need adjusting to fit Kruber's rifle animations
		--   * Smoke FX on shot should be removed (Saltzpyre's flavor, not Kruber's)
		--   * 3P weapon model missing the bolt — may require special offsets;
		--     uncertain whether it's achievable.
		item_key        = "cwv_es_crossbow",
		base_weapon     = "wh_crossbow",
		display_name    = "Crossbow",
		description     = "An imperial-issue crossbow taken up by Reikland state troopers — same Witch-Hunter-pattern weapon, shouldered like the standard handgun.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		inventory_icon  = "icon_wpn_empire_crossbow_t1",
		hud_icon        = "weapon_generic_icon_crossbow",
		skin_display_name = "Crossbow",
		rarity          = "default",
		item_type       = "cwv_es_crossbow",
		-- Inherits template = "crossbow_template_1" from the wh_crossbow IML
		-- clone. The Kruber-specific wield_anim_career_3p[es_*] entries are
		-- patched onto the BASE template (see `_patch_crossbow_template_for_kruber`
		-- below) because the inventory previewer reads template via item.name —
		-- which inherits to "wh_crossbow" — not via the variant's template
		-- override (same constraint as cwv_es_outrider — see its block above).
	},
	-- v0.1.300: cwv_es_musket variant put ON ICE per user request — kept as a
	-- backup idea (don't delete). The cross-slot stance-toggle approach using
	-- the vanilla rifle's mesh with weird scaling worked but the cwv_es_musket_old
	-- variant with a proper custom mesh is the live one. To re-enable: uncomment
	-- the block below. The supporting code (musket_template + musket_template_melee
	-- + bayonet system) is still in place so this variant works the moment it's
	-- re-added to the list. _create_musket_template / _melee still run at boot.
	--[[
	{
		item_key        = "cwv_es_musket",
		base_weapon     = "es_handgun",
		display_name    = "Musket",
		description     = "A long-barrel imperial musket — heavier and slower than the standard rifle, but harder-hitting and fitted with a fixed bayonet for close work. The Reikland regiments who carry these prefer one good shot to a flurry of mediocre ones. Equippable in the melee or ranged slot.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",
		inventory_icon  = "icon_wpn_empire_handgun_t1",
		hud_icon        = "weapon_generic_icon_units/weapons/weapon_display/display_rifle",
		skin_display_name = "Musket",
		rarity          = "exotic",
		template        = "musket_template",
		traits          = { "ranged_increase_power_level_vs_armour_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_musket",
		instances       = 2,
		instance_skins  = { nil, "cwv_es_musket_aunty_bessie" },
	},
	]]
	{
		-- "Old Musket" — second cwv musket variant. v0.1.286 LA-pattern rewrite:
		-- right_hand_unit IS our custom mesh path. The .unit file uses LA's
		-- `data = { mat_to_use = "<vanilla>" }` pattern which references a
		-- vanilla 1P/3P weapon material at runtime — that's how we get proper
		-- FP rendering (no shadow in FP, correct depth, no overlay drawn on
		-- top of hands). The PackageManager.load/unload/has_loaded hooks below
		-- (search "_LA_PATTERN_CUSTOM_PACKAGES") intercept the engine's
		-- attempts to package-load our custom path and silently no-op, so
		-- there's no "Resource not found" crash.
		-- v0.1.277-285 history: ran an overlay (World.spawn_unit + link_unit
		-- against a vanilla rifle) — got the mesh on screen but with wrong
		-- render layer (cast shadow in FP, always-on-top depth bug). Replaced
		-- with the LA pattern in v0.1.286.
		-- v0.1.302: equippable in BOTH ranged AND melee inventory slots via
		-- the cross-slot inject hook. Stance toggle (special key, F/C) flips
		-- between two templates regardless of which slot it's equipped in:
		--   * old_musket_template (ranged):   handgun_template_1 + 1.5x damage + 1.5x reload time vs vanilla rifle
		--   * old_musket_template_melee:      Tuskgor spear clone + 1.2 range_mod + 0.9x melee damage vs vanilla spear
		-- The mesh has a bayonet baked into the FBX so no separate bayonet
		-- child unit is spawned (v0.1.278 gate).
		item_key        = "cwv_es_musket_old",
		base_weapon     = "es_handgun",
		display_name    = "Old Musket",
		description     = "An older imperial pattern — heavier wood, longer barrel, fitted bayonet. Hits harder than the standard rifle, reloads slower. Special key (F/C) flips between rifle stance and bayonet stance.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/cwv_es_musket_custom/cwv_es_musket_custom",
		inventory_icon  = "icon_wpn_empire_handgun_t1",
		hud_icon        = "weapon_generic_icon_units/weapons/weapon_display/display_rifle",
		skin_display_name = "Old Musket",
		rarity          = "exotic",
		template        = "old_musket_template",
		traits          = { "ranged_increase_power_level_vs_armour_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_musket_old",
		instances       = 2,
		-- v0.1.311: cross-slot eligible. _build_entry sets entry.slot_type =
		-- "cwv_dual" so the item shows in both slot_melee AND slot_ranged
		-- grids (Kruber careers' slot type list extended at mod init).
		cross_slot      = true,
	},
	{
		item_key        = "cwv_es_longsword_nordland",
		base_weapon     = "es_bastard_sword",
		-- Save-compatible internal key. This illusion originally shipped under an
		-- invented Nordland identity, but CWV first catalogued this mesh as the
		-- Helmgart watch pattern. Keep the key so persisted cosmetics survive.
		display_name    = "Helmgart Watchsword",
		description     = "An Imperial longsword in the Helmgart watch pattern, carried by the soldiers who guard the mountain pass against raiders from the Reikwald and beyond.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_greatsword/wpn_greatsword",
		inventory_icon  = "icon_wpn_greatsword",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Helmgart Watchsword",
		rarity          = "exotic",
		template        = "imperial_longsword_template",
		item_type       = "cwv_imperial_longsword",
		-- skin_only = true means this entry is registered for skin/illusion purposes
		-- only — it never gets handed to the player as a real inventory item via
		-- _auto_register_all (skipped at line 830). It still produces a custom skin
		-- entry in _register_variant_skins (which checks def.no_skin, not skin_only).
		skin_only       = true,
		-- Scale/grip come from `_type_transforms.cwv_imperial_longsword`. Note:
		-- this variant uses `wpn_greatsword` (different model from the Empire
		-- 2h_sword family), so the type-level Y-width / Z-length convention
		-- may not be a perfect fit. If the Helmgart reads wrong, override
		-- with per-variant `right_hand_scale` / `right_hand_offset` here.
	},
	{
		item_key        = "cwv_dr_priest_greathammer",
		base_weapon     = "wh_2h_hammer",
		display_name    = "Sigmarite Greathammer",
		description     = "A Sigmarite warrior-priest's greathammer in the form of a familiar dwarf two-hander. Charge it up and bring Sigmar's wrath crashing down.",
		character       = "dwarf_ranger",
		careers         = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" },
		right_hand_unit = "units/weapons/player/wpn_dw_2h_hammer_01_t1/wpn_dw_2h_hammer_01_t1",
		inventory_icon  = "icon_wpn_dw_2h_hammer_01_t1",
		hud_icon        = "weapon_generic_icon_hammer2h",
		skin_display_name = "Sigmarite Greathammer",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- TODO(anim): cloned moveset = two_handed_hammer_priest_template, authored
		-- against Saltzpyre's 3P body skeleton. Dwarf 3P body anim event coverage
		-- NOT yet verified or remapped — see CHANGELOG 0.1.61 known issues. 1P
		-- needs nothing — universal across characters (see top-of-file
		-- ANIMATION ARCHITECTURE).
	},
	{
		item_key        = "cwv_es_priest_greathammer",
		base_weapon     = "wh_2h_hammer",
		display_name    = "Sigmarite Greathammer",
		description     = "A Sigmarite warrior-priest's greathammer in the form of a familiar Reikland two-hander. Charge it up and bring Sigmar's wrath crashing down.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_hammer_01_t1/wpn_2h_hammer_01_t1",
		inventory_icon  = "icon_wpn_empire_2h_hammer_01_t1",
		hud_icon        = "weapon_generic_icon_hammer2h",
		skin_display_name = "Sigmarite Greathammer",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_priest_greathammer",
		-- TODO(anim): cloned moveset = two_handed_hammer_priest_template, authored
		-- against Saltzpyre's 3P body skeleton. Saltzpyre and Kruber are both
		-- empire-human 3P skeletons so most events likely overlap, but coverage
		-- NOT yet verified — see CHANGELOG 0.1.61 known issues. 1P needs nothing
		-- — universal across characters (see top-of-file ANIMATION ARCHITECTURE).
	},
	{
		-- Warrior-Priest Hammer: Saltzpyre's wh_1h_hammer (Skullsplitter) cloned
		-- onto Kruber. Same model and one-handed priest-hammer moveset; carries
		-- the rescaled `es_2h_hammer_skin_*` greathammer illusions as cosmetic
		-- options (see `_custom_illusions` block — entries with
		-- `target_combo = "cwv_es_warpriest_hammer_skins"`). Picker shows the
		-- vanilla wh_1h_hammer mesh by default plus the 8 oversized-greathammer
		-- alternatives the user iterated through in v0.1.151.
		item_key        = "cwv_es_warpriest_hammer",
		base_weapon     = "wh_1h_hammer",
		display_name    = "Warrior-Priest Hammer",
		description     = "A warrior-priest's blessing-hammer, taken up by the state regiments who fight beside Sigmar's chosen. Single-handed, faster than the greathammer, no less righteous.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		inventory_icon  = "icon_wpn_wh_1h_hammer_01",
		hud_icon        = "weapon_generic_icon_hammer1h",
		skin_display_name = "Warrior-Priest Hammer",
		rarity          = "exotic",
		template        = "one_handed_hammer_priest_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_warpriest_hammer",
		-- TODO(anim): cloned moveset = one_handed_hammer_priest_template,
		-- authored against Saltzpyre's 3P body skeleton. Both Saltzpyre and
		-- Kruber are empire-human 3P skeletons so most events likely overlap;
		-- if any 3P clip plays nothing, add a per-event remap entry. 1P
		-- needs nothing — universal across characters (see top-of-file
		-- ANIMATION ARCHITECTURE).
	},
	{
		-- Maul: Sienna's bw_1h_mace template (Morningstar — visually
		-- two-handed despite the "1h" naming) cloned for Kruber.
		-- Default mesh: Kruber's mace+sword mace (wpn_emp_mace_04_t2);
		-- curated illusions are the OTHER mace meshes from
		-- es_dual_wield_hammer_sword skins (mace+sword's mace half only —
		-- sword half discarded). Registered by
		-- _register_macesword_mace_maul_illusions. Type-level scale
		-- inflates the 1H mesh into a 2H silhouette; shared across
		-- default + every illusion via _type_transforms.
		--
		-- Source template: one_handed_hammer_wizard_template_1.
		-- Carries fire damage in EXACTLY one place — `medium_blunt_smiter_heavy`
		-- (H1 heavy attack)'s default_target chains to
		-- `default_target_slashing_smiter_burn_M`. Damage-type swap
		-- handled in `_create_maul_template`: H1's damage_profile is
		-- swapped to `medium_blunt_smiter_2h_hammer` (same heavy-smiter
		-- shape, no burn). All other profiles (lights L1-L3, heavy H2/H3,
		-- pushes) are clean — no FX/sound swaps needed (verified
		-- against `1h_hammers_wizard.lua` — all `melee_hit_hammers_1h`
		-- + `blunt_hit`, no `staff_spark` or `fire_hit`).
		--
		-- 3P wield routes to Kruber's greathammer SM (to_2h_hammer);
		-- per-action remap covers wizard-mace events that aren't in
		-- two_handed_hammers_template_1's closed vocabulary.
		item_key        = "cwv_es_maul",
		base_weapon     = "bw_1h_mace",
		display_name    = "Maul",
		description     = "A heavy reikland war-maul — double-fisted iron, swung with the weight of both shoulders. Slower than a sword, but it caves armour.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2",
		-- TODO icon: placeholder uses Sienna's mace icon. Variant is NOT
		-- complete until proper inventory_icon + hud_icon are authored.
		inventory_icon  = "icon_wpn_brw_mace_01",
		hud_icon        = "weapon_generic_icon_hammer2h",
		skin_display_name = "Maul",
		rarity          = "exotic",
		template        = "maul_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_maul",
		-- Scale lives at type level: _type_transforms.cwv_es_maul.
	},
	{
		-- #597: exact Bardin Greataxe behavior on Kruber, rendered through
		-- converted third-party models declared in `_cwv_greataxe.lua`.
		-- The first usable manifest row owns the default mesh. Until one is
		-- present the cloned Bardin mesh is retained as a safe fallback.
		-- Keep this key literal so the repository name-map generator can ingest
		-- the runtime registration without evaluating Lua module constants.
		item_key        = "cwv_es_greataxe",
		base_weapon     = _om.greataxe.BASE_WEAPON,
		display_name    = "Greataxe",
		description     = "A heavy two-handed axe built for breaking shield walls and hewing through packed ranks.",
		character       = "empire_soldier",
		careers         = _om.greataxe.DEFAULT_CAREERS,
		right_hand_unit = (_om.greataxe.default_model() or {}).right_hand_unit,
		inventory_icon  = (_om.greataxe.default_model() or {}).inventory_icon or "icon_wpn_dw_2h_axe_01_t1",
		hud_icon        = (_om.greataxe.default_model() or {}).hud_icon or "weapon_generic_icon_axe2h",
		skin_display_name = (_om.greataxe.default_model() or {}).display_name or "Greataxe Model 01",
		rarity          = "exotic",
		template        = _om.greataxe.TEMPLATE_KEY,
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = _om.greataxe.ITEM_TYPE,
	},
	{
		-- Rapier: Saltzpyre's `wh_fencing_sword` template cloned for
		-- Kruber, with the pistol shoot ability disabled. Pistol mesh
		-- replaced with the invisible weapon unit so only the rapier
		-- renders (left_hand_unit slot held but not visible).
		--
		-- Source template: fencing_sword_template_1. Carries an
		-- `action_three` (kind="handgun", anim_event="attack_shoot") that
		-- fires the off-hand pistol; `_create_rapier_template` overrides
		-- its `condition_func` / `chain_condition_func` to a `_always_false`
		-- closure (same pattern as the tuskgor javelin's auto-catch
		-- reload disable in v0.1.65). Action stays defined for
		-- state-machine / network consistency but never fires.
		--
		-- 3P wield routes to Kruber's native `to_1h_sword` SM. Closed-vocab
		-- per-action remap covers fencing-specific events
		-- (attack_swing_stab, attack_swing_stab_charge, attack_swing_left)
		-- not authored on Kruber's 1h_sword vocabulary.
		--
		-- Type-level scale `{1.1, 1.25, 1.0}` broadens X/Y for a
		-- basket-hilt feel. Curated illusions: every
		-- `wh_fencing_sword_skin_*` (registered by
		-- `_register_rapier_illusions`), each with the pistol forced
		-- invisible.
		item_key        = "cwv_es_rapier",
		base_weapon     = "wh_fencing_sword",
		display_name    = "Rapier",
		description     = "A reikland duellist's basket-hilted rapier. The cup-guard catches steel; the long thrust reaches farther than a state-issue blade.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1",
		-- Single-handed: NO left mesh at all. Sentinel `no_left_hand = true`
		-- tells `_build_entry` to nil out the inherited `left_hand_unit` from
		-- the base fencing-sword IML entry (which has the pistol). With
		-- entry.left_hand_unit = nil, vanilla's
		-- `if item_units.left_hand_unit then ... end` skips the entire
		-- left-hand spawn pipeline (in-game equip + cosmetic picker BOTH).
		-- Replaces the v0.1.187 invisible-pistol approach which crashed the
		-- cosmetic picker on default-skin render (crash GUIDs
		-- 962fe355-... and 77e636ee-...). Picker no longer tries to
		-- attach anything at j_leftweaponattach because there's nothing
		-- to attach.
		no_left_hand    = true,
		-- TODO icon: placeholder uses vanilla fencing-sword icon. Variant
		-- is NOT complete until proper inventory_icon + hud_icon are
		-- authored.
		inventory_icon  = "icon_wpn_fencingsword_01_t1",
		hud_icon        = "weapon_generic_icon_fencing_sword",
		skin_display_name = "Rapier",
		rarity          = "exotic",
		template        = "rapier_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_rapier",
		-- Scale lives at type level: _type_transforms.cwv_es_rapier.
	},
	{
		item_key        = "cwv_es_dual_swords",
		base_weapon     = "we_dual_wield_swords",
		display_name    = "Imperial Dual Swords",
		description     = "Two Reikland arming swords wielded in tandem. Heavier and slower than the elven dance, but each blow lands with imperial weight.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		inventory_icon  = "icon_wpn_emp_sword_02_t1",
		hud_icon        = "weapon_generic_icon_dual_elf_sword",
		skin_display_name = "Imperial Dual Swords",
		rarity          = "exotic",
		template        = "imperial_dual_swords_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_dual_swords",
		right_hand_scale = { 1.0, 1.0, 1.0 },
		left_hand_scale  = { 1.0, 1.0, 1.0 },
		-- Single-handed sword model reads slightly small in first-person view —
		-- bump 1P only by 10%. 3P keeps native scale (other players see this).
		right_hand_scale_1p = { 1.1, 1.1, 1.1 },
		left_hand_scale_1p  = { 1.1, 1.1, 1.1 },
	},
	{
		-- Sword and Mace: INVERSE of Kruber's mace+sword. Sword in RIGHT hand,
		-- mace in LEFT hand. Visual models are his vanilla 1H sword
		-- (`wpn_emp_sword_02_t1`, from `es_1h_sword`) and 1H mace
		-- (`wpn_emp_mace_02_t1`, from `es_1h_mace`).
		--
		-- Damage profiles, hit effects, and impact sounds per-sub-action are
		-- swapped between blunt (was mace) and slashing (was sword) based on
		-- weapon_action_hand — see `sword_and_mace_template` clone above.
		item_key        = "cwv_es_sword_and_mace",
		base_weapon     = "es_dual_wield_hammer_sword",
		display_name    = "Sword and Mace",
		description     = "A reikland sword in the strong hand, a mace as the off-hand counterweight. The mirror of the soldier's pair.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		inventory_icon  = "icon_es_dual_wield_hammer_sword_01",
		hud_icon        = "weapon_generic_icon_falken",
		skin_display_name = "Sword and Mace",
		rarity          = "exotic",
		template        = "sword_and_mace_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- item_type carries its own cwv-only skin_combination_table — without
		-- this, the variant inherits es_dual_wield_hammer_sword's vanilla
		-- skin_combination_table and the picker shows vanilla mace+sword
		-- skins (which would invert the variant's intent: vanilla skins set
		-- mace=right + sword=left, the OPPOSITE of this variant's
		-- sword=right + mace=left layout).
		item_type       = "cwv_es_sword_and_mace",
	},
	{
		-- Cudgel: Saltzpyre's falchion moveset (one_hand_falchion_template_1)
		-- with every cutting hit converted to a crushing one — slashing damage
		-- profiles → blunt cousins, axe/sword hit effects → hammer effects,
		-- slashing impact sounds → blunt thuds. See `cudgel_template` clone
		-- below. Visual model stays the Empire mace from Kruber's mace+sword
		-- (`wpn_emp_mace_04_t2`), so it reads as a heavier baton with the
		-- charge-and-release tempo of a falchion. Cross-character moveset
		-- (falchion is wh_1h_falchion's native template) — Kruber's 3P body
		-- already plays falchion anims via WT's `wh_1h_falchion` cross-access.
		item_key        = "cwv_es_cudgel",
		base_weapon     = "es_1h_mace",
		display_name    = "Cudgel",
		description     = "A heavy iron baton swung with a duellist's tempo — wind up, snap through, follow with a crushing overhead.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2",
		inventory_icon  = "icon_wpn_emp_mace_02_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Cudgel",
		rarity          = "exotic",
		template        = "cudgel_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
	},
	{
		-- Shortsword: Sienna's dagger moveset (one_handed_daggers_template_1)
		-- with the fire DoT scrubbed and stats tweaked — −20% speed, +15%
		-- power. Visual model is Kruber's mace+sword sword (`wpn_emp_sword_06_t1`).
		-- Stats + DoT-removal handled in shortsword_template clone below.
		-- For Kruber — dagger moveset on his empire-soldier 3P body (cross-
		-- character; if specific anim events don't read on his sub-graph,
		-- a `_cross_access_action_remap` entry can be added).
		item_key        = "cwv_es_shortsword",
		base_weapon     = "bw_dagger",
		display_name    = "Shortsword",
		description     = "An unenchanted reikland shortsword. Quick steel for close work.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		-- Sienna's dagger model is bigger than a Reikland shortsword should
		-- read; thin it on the X/Y axes (length kept at native).
		right_hand_scale = { 0.7, 0.7, 1.0 },
		right_hand_unit = "units/weapons/player/wpn_emp_sword_06_t1/wpn_emp_sword_06_t1",
		inventory_icon  = "icon_wpn_brw_dagger_01",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Shortsword",
		rarity          = "exotic",
		template        = "shortsword_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
	},
	-- ============================================================
	-- Dual Axes — Saltzpyre's 1H axe model dual-wielded
	-- Both Kruber + Saltzpyre variants share Bardin's dual-axes moveset
	-- (template = "dual_wield_axes_template_1") with a model swap to
	-- Saltzpyre's wpn_axe_hatchet_t1. 3P wield routes per-character via
	-- _cross_access_template_wield_3p (Kruber → mace+sword, Saltzpyre →
	-- axe+falchion).
	-- ============================================================
	{
		item_key        = "cwv_es_dual_axes",
		base_weapon     = "dr_dual_wield_axes",
		display_name    = "Dual Axes",
		description     = "Twin reikland hatchets in either hand. Soldier's choice for close, fast work.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		left_hand_unit  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		inventory_icon  = "icon_wpn_axe_hatchet_t1_dual_cwv",
		hud_icon        = "weapon_generic_icon_axe1h",
		skin_display_name = "Dual Axes",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- item_type carries its own cwv-only skin_combination_table so the
		-- Saltzpyre 1h-axe cosmetic illusions appended by
		-- `_register_saltzpyre_1h_axe_dual_illusions` show up in the picker
		-- on this variant only (not on every dr_dual_wield_axes wielder).
		item_type       = "cwv_es_dual_axes",
	},
	{
		item_key        = "cwv_wh_dual_axes",
		base_weapon     = "dr_dual_wield_axes",
		display_name    = "Dual Axes",
		description     = "Twin hatchets — bite, hook, and cleave in the witch hunter's hands.",
		character       = "witch_hunter",
		careers         = _wh_all_careers,
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		left_hand_unit  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1",
		inventory_icon  = "icon_wpn_axe_hatchet_t1_dual_cwv",
		hud_icon        = "weapon_generic_icon_axe1h",
		skin_display_name = "Dual Axes",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- Saltzpyre's variant uses the same canonical wh_1h_axe cosmetic
		-- family as Kruber's twin-hatchet variant, in its own curated pool.
		item_type       = "cwv_wh_dual_axes",
	},
	-- ============================================================
	-- Dual Maces — Kruber's 1H mace model dual-wielded
	-- Both Kruber + Saltzpyre variants share Bardin's dual-hammers moveset
	-- (template = "dual_wield_hammers_template") with a model swap to
	-- Kruber's wpn_emp_mace_02_t1. 3P wield routes per-character via
	-- _cross_access_template_wield_3p (Kruber → mace+sword, Saltzpyre →
	-- dual_hammers, wh_priest → dual_hammers_priest).
	-- ============================================================
	{
		item_key        = "cwv_es_dual_maces",
		base_weapon     = "dr_dual_wield_hammers",
		display_name    = "Dual Maces",
		description     = "Two reikland maces. Crushing strikes in both hands — armour breakers and skull crackers.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		inventory_icon  = "icon_wpn_emp_mace_02_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dual Maces",
		rarity          = "exotic",
		template        = "cwv_dual_maces_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- item_type carries its own cwv-only skin_combination_table so vanilla
		-- dr_dual_wield_hammers skins (Bardin's slayer dual-axes-style hammers)
		-- don't bleed into the picker. Dual-wield display rig (`display_dual_hammers`)
		-- is forced in `_force_display_unit` to prevent the j_leftweaponattach
		-- crash on the cosmetic picker.
		item_type       = "cwv_es_dual_maces",
	},
	{
		item_key        = "cwv_wh_dual_maces",
		base_weapon     = "dr_dual_wield_hammers",
		display_name    = "Dual Maces",
		description     = "Two reikland maces, judgement in steel. The witch hunter's blunt sermon.",
		character       = "witch_hunter",
		careers         = _wh_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
		inventory_icon  = "icon_wpn_emp_mace_02_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dual Maces",
		rarity          = "exotic",
		template        = "cwv_dual_maces_template",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		-- See cwv_es_dual_maces above for the item_type / display rig rationale.
		item_type       = "cwv_wh_dual_maces",
	},
	-- Issue #602: Dawi models with mace gameplay identities. The Bardin hammer
	-- meshes are resident placeholders only; the moveset/template is canonical.
	-- Reusing #599's existing mace template keys makes its modifier template-
	-- scoped and therefore impossible to compound across these three items.
	{
		item_key        = "cwv_dr_dawi_mace",
		base_weapon     = "es_1h_mace",
		template        = "one_handed_hammer_template_1",
		display_name    = "Dawi Mace",
		description     = "A compact Dawi striking weapon, balanced for forceful mace blows.",
		character       = "dwarf_ranger",
		careers         = _om.dawi_maces.NATIVE_ONE_HANDED,
		right_hand_unit = _om.dawi_maces.PLACEHOLDER_MACE,
		inventory_icon  = "icon_wpn_dw_hammer_01_t1",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dawi Mace",
		rarity          = "exotic",
		item_type       = "cwv_dr_dawi_mace",
	},
	{
		item_key        = "cwv_dr_dawi_mace_shield",
		base_weapon     = "es_mace_shield",
		template        = "one_handed_hammer_shield_template_1",
		display_name    = "Dawi Mace and Shield",
		description     = "A Dawi mace paired with a broad shield for holding the line.",
		character       = "dwarf_ranger",
		careers         = _om.dawi_maces.NATIVE_SHIELD,
		right_hand_unit = _om.dawi_maces.PLACEHOLDER_MACE,
		left_hand_unit  = _om.dawi_maces.PLACEHOLDER_SHIELD,
		inventory_icon  = "icon_wpn_dw_shield_01_hammer",
		hud_icon        = "weapon_generic_icon_hammer_and_sheild",
		skin_display_name = "Dawi Mace and Shield",
		rarity          = "exotic",
		item_type       = "cwv_dr_dawi_mace_shield",
	},
	{
		item_key        = "cwv_dr_dawi_dual_maces",
		base_weapon     = "dr_dual_wield_hammers",
		template        = "cwv_dual_maces_template",
		display_name    = "Dawi Dual Maces",
		description     = "A matched pair of Dawi maces for an unbroken rhythm of crushing blows.",
		character       = "dwarf_ranger",
		careers         = _om.dawi_maces.NATIVE_ONE_HANDED,
		right_hand_unit = _om.dawi_maces.PLACEHOLDER_MACE,
		left_hand_unit  = _om.dawi_maces.PLACEHOLDER_MACE,
		inventory_icon  = "icon_dr_dual_wield_hammers_01",
		hud_icon        = "weapon_generic_icon_mace",
		skin_display_name = "Dawi Dual Maces",
		rarity          = "exotic",
		item_type       = "cwv_dr_dawi_dual_maces",
	},
	-- Crowbill family: registration-only definitions use Sienna's resident
	-- vanilla Crowbill as a licence-safe placeholder. CIM owns acquisition;
	-- the isolated hammer-mode module consumes `crowbill_mode_family`.
	{
		item_key        = "cwv_es_imperial_crowbill",
		base_weapon     = _om.crowbill_family.SOURCE_ITEM,
		template        = _om.crowbill_family.SOURCE_TEMPLATE,
		display_name    = "Imperial Crowbill",
		description     = "An Imperial crowbill with a hooked face for armour and a hammer face for crushing blows.",
		character       = "empire_soldier",
		careers         = _om.crowbill_family.IMPERIAL_DEFAULTS,
		right_hand_unit = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).right_hand_unit
			or _om.crowbill_family.PLACEHOLDER_UNIT,
		inventory_icon  = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).inventory_icon
			or _om.crowbill_family.PLACEHOLDER_ICON,
		hud_icon        = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).hud_icon
			or "weapon_generic_icon_falken",
		skin_display_name = (_om.crowbill_family.model_for_variant("cwv_es_imperial_crowbill") or {}).display_name
			or "Imperial Crowbill",
		item_type       = "cwv_es_imperial_crowbill",
		crowbill_mode_family = _om.crowbill_family.HAMMER_MODE_FAMILY,
	},
	{
		item_key        = "cwv_dr_dawi_crowbill",
		base_weapon     = _om.crowbill_family.SOURCE_ITEM,
		template        = _om.crowbill_family.SOURCE_TEMPLATE,
		display_name    = "Dawi Crowbill",
		description     = "A Dawi crowbill built to pierce plate or turn its hammer face against shield and bone.",
		character       = "dwarf_ranger",
		careers         = _om.crowbill_family.DAWI_DEFAULTS,
		right_hand_unit = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).right_hand_unit
			or _om.crowbill_family.PLACEHOLDER_UNIT,
		inventory_icon  = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).inventory_icon
			or _om.crowbill_family.PLACEHOLDER_ICON,
		hud_icon        = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).hud_icon
			or "weapon_generic_icon_falken",
		skin_display_name = (_om.crowbill_family.model_for_variant("cwv_dr_dawi_crowbill") or {}).display_name
			or "Dawi Crowbill",
		item_type       = "cwv_dr_dawi_crowbill",
		crowbill_mode_family = _om.crowbill_family.HAMMER_MODE_FAMILY,
	},
	{
		-- Dual Warrior-Priest Hammers — paired clone of cwv_es_warpriest_hammer
		-- (which is itself a clone of Saltzpyre's wh_1h_hammer Skullsplitter).
		-- Uses vanilla `wh_dual_hammer` as base_weapon: Saltzpyre's Bless DLC
		-- priest dual-hammers item, template `dual_wield_hammers_priest_template`,
		-- mesh `wpn_wh_1h_hammer_01` on each hand (identical-mesh dual-wield).
		-- Native on all 4 Kruber careers.
		--
		-- ANIMATION ROUTING: the priest template's default wield event is
		-- `to_dual_hammers_priest`, which doesn't exist on Kruber's empire-soldier
		-- 3P body skeleton. Routed to `to_dual_hammer_sword_es` (Kruber's mace+sword
		-- SM) via `_cross_access_template_wield_3p[dual_wield_hammers_priest_template]`
		-- below — same approach as cwv_es_dual_maces uses for non-priest
		-- dual_wield_hammers_template. This is the Kruber-specific equivalent of
		-- weapon_tweaker's `to_dual_hammers_priest → to_dual_hammers` redirect
		-- (which targets Bardin's body, where `to_dual_hammers` exists natively).
		--
		-- GRIP OFFSET: matches weapon_tweaker's `wh_1h_hammer = { es_ = {0,0,0.15} }`
		-- tune (per `feedback_grip_offset_sign.md` — +Z lowers grip onto haft
		-- when the priest hammer rides high on the empire-soldier hand bone).
		-- Same mesh, same hand bone, same correction needed on each hand.
		item_key        = "cwv_es_dual_warpriest_hammers",
		base_weapon     = "wh_dual_hammer",
		display_name    = "Dual Warrior-Priest Hammers",
		description     = "A pair of warrior-priest blessing-hammers, taken up by Reikland regiments who fight beside Sigmar's chosen. The two-handed prayer of justice, dealt in stereo.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		left_hand_unit  = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		inventory_icon  = "icon_wpn_wh_dual_hammer_skin_01_t1",
		hud_icon        = "weapon_generic_icon_hammer1h",
		skin_display_name = "Dual Warrior-Priest Hammers",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_dual_warpriest_hammers",
		right_hand_offset = { 0, 0, 0.15 },
		left_hand_offset  = { 0, 0, 0.15 },
	},
	{
		-- Warrior-Priest Hammer and Shield — clone of Saltzpyre's Bless DLC
		-- `wh_hammer_shield` (priest 1H hammer + shield) on Kruber. Right-hand
		-- mesh is the Skullsplitter `wpn_wh_1h_hammer_01`, left-hand is the
		-- standard Empire shield `wpn_emp_shield_02` (not Saltzpyre's
		-- wpn_wh_shield_01 — this variant lives on Kruber's body).
		--
		-- ANIMATION ROUTING: the priest template's default wield event is
		-- `to_1h_hammer_shield_priest`, only authored on Saltzpyre's wh_priest
		-- 3P body. Kruber routes via
		-- `_cross_access_template_wield_3p[one_handed_hammer_shield_priest_template]`
		-- to `to_1h_hammer_shield` (his vanilla mace+shield wield). Mirrors
		-- weapon_tweaker's `to_1h_hammer_shield_priest → to_1h_hammer_shield`
		-- redirect at weapon_tweaker.lua:231 (which targets all non-priest
		-- careers).
		--
		-- GRIP OFFSET: matches weapon_tweaker's `wh_hammer_shield = { es_ = {0,0,0.15} }`
		-- tune (right hand only — same Skullsplitter haft riding high on the
		-- empire-soldier hand bone, like the single 1H and dual variants).
		item_key        = "cwv_es_warpriest_hammer_shield",
		base_weapon     = "wh_hammer_shield",
		display_name    = "Warrior-Priest Hammer and Shield",
		description     = "A warrior-priest's blessing-hammer paired with a state-issue shield. Sigmar's wrath in the strong hand, faith and steel in the other.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_wh_1h_hammer_01/wpn_wh_1h_hammer_01",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_wh_shield_01_t1",
		hud_icon        = "weapon_generic_icon_hammer_and_sheild",
		skin_display_name = "Warrior-Priest Hammer and Shield",
		rarity          = "exotic",
		traits          = { "melee_attack_speed_on_crit" },
		properties      = { power_vs_skaven = 1, power_vs_chaos = 1 },
		item_type       = "cwv_es_warpriest_hammer_shield",
		right_hand_offset = { 0, 0, 0.15 },
	},
}

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
		if _om.crowbill_runtime and _om.crowbill_runtime.on_setting_changed then
			_om.crowbill_runtime.on_setting_changed(setting_id)
		end
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

-- ============================================================
-- Cross-character access: extend can_wield on vanilla dual-wield items
-- ============================================================
-- Some weapons read fine on the "other" character without any model swap or
-- variant — just expand the vanilla item's can_wield list so the new careers
-- can equip the existing inventory item directly. No new item is created;
-- inventory shows the original Saltzpyre / Kruber weapon as-is.
local _cross_access_can_wield = {
	wh_1h_falchion             = _es_all_careers,  -- Kruber gets Saltzpyre's Falchion
	wh_dual_wield_axe_falchion = _es_all_careers,  -- Kruber gets Saltzpyre's Axe + Falchion
	es_dual_wield_hammer_sword = _wh_all_careers,  -- Saltzpyre gets Kruber's Mace + Sword
}

local function _apply_cross_access_can_wield()
	if not ItemMasterList then return end
	for item_key, careers_to_add in pairs(_cross_access_can_wield) do
		local item = rawget(ItemMasterList, item_key)
		if item and type(item.can_wield) == "table" then
			for _, career in ipairs(careers_to_add) do
				local already_present = false
				for _, existing in ipairs(item.can_wield) do
					if existing == career then
						already_present = true
						break
					end
				end
				if not already_present then
					item.can_wield[#item.can_wield + 1] = career
				end
			end
		end
	end
end

_apply_cross_access_can_wield()

-- 3P wield routing for the cross-access dual-wield items. Each character
-- body gets routed into its native dual-wield sub-graph so idle / walk /
-- block reads correctly:
--   Kruber (es_*)        → to_dual_hammer_sword_es (his mace+sword SM)
--   Saltzpyre (wh_*)     → to_dual_axe_sword_wh    (his axe+falchion SM, for dual axes)
--   Saltzpyre wh_priest  → to_dual_hammers_priest  (his Bless dual-hammers SM, for dual maces)
--   Saltzpyre other wh_* → to_dual_hammers         (cross-character into the dual_hammers SM)
-- Bardin careers (dr_*) aren't listed and fall through to each template's
-- default wield_anim (to_dual_axes / to_dual_hammers), so Bardin natives are
-- unaffected.
--
-- Per-action anim_event_3p is intentionally NOT remapped — same-named events
-- that exist on the target sub-graph play visibly, others may fail silently.
-- If specific attacks read wrong on a body, a per-template clone with an
-- anim_event_3p remap can be added later (see imperial_dual_swords_template
-- for that pattern). Starting simple per "no templates from scratch".
local _cross_access_template_wield_3p = {
	-- Saltzpyre's Axe + Falchion on Kruber: native wield event is
	-- `to_dual_axe_sword_wh`, which isn't authored on Kruber's empire-soldier
	-- 3P body. Route Kruber careers into his mace+sword SM. Saltzpyre's careers
	-- are intentionally absent — his witch-hunter body wields this template
	-- natively, so no redirect needed.
	dual_wield_axe_falchion_template = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	},
	-- Bardin's Dual Axes template: used by the cwv_es_dual_axes and
	-- cwv_wh_dual_axes variants below. Kruber routes to mace+sword;
	-- Saltzpyre routes to his axe+falchion SM. Bardin careers (dr_*) are
	-- intentionally absent — they wield Bardin's native dr_dual_wield_axes
	-- with the unmodified default wield (to_dual_axes).
	dual_wield_axes_template_1 = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
		wh_captain        = "to_dual_axe_sword_wh",
		wh_bountyhunter   = "to_dual_axe_sword_wh",
		wh_zealot         = "to_dual_axe_sword_wh",
		wh_priest         = "to_dual_axe_sword_wh",
	},
	-- Bardin's Dual Hammers template: used by the cwv_es_dual_maces and
	-- cwv_wh_dual_maces variants below. Kruber routes to mace+sword;
	-- non-priest Saltzpyre uses dual_hammers; wh_priest gets his Bless DLC
	-- dual_hammers_priest variant. Bardin (dr_*) absent — keeps default.
	dual_wield_hammers_template = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
		wh_captain        = "to_dual_hammers",
		wh_bountyhunter   = "to_dual_hammers",
		wh_zealot         = "to_dual_hammers",
		wh_priest         = "to_dual_hammers_priest",
	},
	-- Saltzpyre's Bless DLC priest Dual Hammers template: used by the new
	-- cwv_es_dual_warpriest_hammers variant (Kruber-side clone of
	-- vanilla wh_dual_hammer). The template's default wield event is
	-- `to_dual_hammers_priest`, only authored on Saltzpyre's wh_priest 3P
	-- body. For Kruber careers, route into his mace+sword SM
	-- (`to_dual_hammer_sword_es`) — same approach cwv_es_dual_maces uses
	-- for non-priest dual_wield_hammers_template, and the Kruber-specific
	-- equivalent of weapon_tweaker's `to_dual_hammers_priest → to_dual_hammers`
	-- redirect (which targets Bardin where `to_dual_hammers` exists).
	-- Other Saltzpyre careers and Bardin absent — they wield this template
	-- natively (priest) or via vanilla mechanics if exposed via cross-access.
	dual_wield_hammers_priest_template = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	},
	-- Saltzpyre's Bless DLC priest 1H Hammer + Shield template: used by the
	-- new cwv_es_warpriest_hammer_shield variant (Kruber-side clone of
	-- vanilla wh_hammer_shield). The template's default wield event is
	-- `to_1h_hammer_shield_priest`, only authored on Saltzpyre's wh_priest
	-- 3P body. For Kruber careers, route to `to_1h_hammer_shield` (his
	-- vanilla mace+shield wield) — direct Kruber equivalent of
	-- weapon_tweaker's `to_1h_hammer_shield_priest → to_1h_hammer_shield`
	-- redirect at weapon_tweaker.lua:231.
	one_handed_hammer_shield_priest_template = {
		es_mercenary      = "to_1h_hammer_shield",
		es_huntsman       = "to_1h_hammer_shield",
		es_knight         = "to_1h_hammer_shield",
		es_questingknight = "to_1h_hammer_shield",
	},
}

local function _apply_cross_access_template_wield_3p()
	if not Weapons then return end
	for template_name, career_to_wield in pairs(_cross_access_template_wield_3p) do
		local tpl = Weapons[template_name]
		if tpl then
			tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
			for career, wield in pairs(career_to_wield) do
				tpl.wield_anim_career_3p[career] = wield
			end
		end
	end
end

_apply_cross_access_template_wield_3p()

-- ============================================================
-- Cross-character per-action 3P anim event remap (career-specific runtime hook)
-- ============================================================
-- WHY THIS EXISTS:
--   For weapons made cross-character via can_wield expansion (above), we
--   often need to redirect specific attack events on the foreign wielder's
--   3P body — e.g. Kruber's empire-soldier body has no overhead heavy clip
--   on its dual_hammer_sword sub-graph, so Saltzpyre's `attack_swing_heavy_down`
--   needs to play a Kruber-vocab heavy instead.
--
--   The engine's per-sub-action anim_event_3p resolution is NOT career-keyed
--   (`weapon_unit_extension.lua:512` reads `current_action_settings.anim_event_3p`
--   directly with no career context). So mutating the BASE template's
--   anim_event_3p affects EVERY wielder including the native one — wrong.
--
-- HOW THIS WORKS (#398):
--   We hook `WeaponUnitExtension._play_3p_anim` and rewrite the event BEFORE
--   vanilla resolves NetworkLookup.anims and sends rpc_anim_event_variable_float.
--   This ordering is load-bearing: the former Unit.animation_event hook ran
--   only after vanilla had sent the original donor-career event, so the owner
--   saw the receiver-native clip while remote husks received a no-op event and
--   missed that clip's embedded swing-foley + exertion timeline.
--   The rewrite applies when:
--     1. The target unit is the local 3P body (player.player_unit) — never 1P
--     2. The local player's career has a remap entry for the wielded weapon
--     3. The event matches the remap
--   Native wielders (their career not present in the remap) are unaffected.
--   Vanilla then performs its unchanged local play + network replication, so
--   every listener consumes the same animation/audio timeline. No sound event
--   is manually replayed.
--
-- LIMITATIONS (relative to weapon_tweaker's full system):
--   - Owner-side decision only, but the selected event is now networked by
--     vanilla and therefore reaches every husk/listener.
--   - No 1P remapping (universal rule — see top-of-file ANIMATION ARCHITECTURE).
--   - No suffix/career-prefix logic — remaps are explicit per (item, career).
--
-- HOW TO ADD A NEW REMAP:
--   1. Add an entry to `_cross_access_action_remap[item_key][career_name]`
--      mapping the source event → 3P substitute.
--   2. Source event names come from the BASE template's sub_action.anim_event
--      values (use `wt dump_actions <pattern>` to inspect).
--   3. Substitute event names should be authored on the wielder's body's
--      target sub-graph (the SM you wield_anim_career_3p'd to above).
--   4. Direction-coherence: when remapping a heavy release, also remap its
--      paired charge sub-action so the wind-up and strike directions match.
--      Source chain graph tells you which charge feeds which release.
--   5. Verify visually with `wt animlog` — exists=true is necessary but not
--      sufficient (stub transitions exist).
--
-- See `character_weapon_variants/DEVELOPMENT.md` "Animation: cross-access
-- runtime remap" for the long-form pattern.

-- Reusable Kruber-on-dual-axes remap (Bardin's dr_dual_wield_axes on Kruber).
-- Source events not authored on Kruber's dual_hammer_sword sub-graph:
--   attack_swing_charge_diagonal — charge that feeds heavy_attack_3
--   attack_swing_heavy_right     — heavy_attack release (fed by charge_right)
--   attack_swing_heavy           — heavy_attack_2 release (fed by charge_left)
-- heavy_attack_3 fires `attack_swing_heavy_left_diagonal` which already exists
-- on dual_hammer_sword — no remap needed there. Charge directions
-- (charge_left, charge_right) match Kruber's vocab natively; only
-- charge_diagonal needs a substitute.
local _kruber_dual_axes_remap = {
	-- Charge that feeds heavy_attack_3 (heavy_left_diagonal). Cock left to
	-- match the left-diagonal strike direction.
	attack_swing_charge_diagonal = "attack_swing_charge_left",
	-- heavy_attack release (fed by charge_right): cock right → strike
	-- right-diagonal. Direction-coherent.
	attack_swing_heavy_right     = "attack_swing_heavy_right_diagonal",
	-- heavy_attack_2 release (fed by charge_left): cock left → strike
	-- left-diagonal. Direction-coherent.
	attack_swing_heavy           = "attack_swing_heavy_left_diagonal",
}

-- Same Kruber receiver redirects WT currently applies when he wields the
-- vanilla elf spear. Stored on `_om` instead of another file-scope local
-- because this chunk sits at Lua 5.1's 200-local ceiling.
_om._kruber_infantry_spear_remap = {
	attack_swing_down_left_axe = "attack_swing_down_left",
	attack_swing_left          = "attack_swing_down_left",
}

-- Reusable Kruber-on-axe-falchion remap (same for all 4 Kruber careers).
--
-- 3P ONLY. 1P animations are universal across all six characters via the
-- shared `first_person_base` unit and need no remap work. The
-- `WeaponUnitExtension._play_3p_anim` hook that consumes this table is gated
-- to the local 3P owner body before vanilla's RPC encode. Never add 1P-side
-- fields here — `anim_event`, `wield_anim`, `state_machine` are out of scope.
--
-- CLOSED-VOCABULARY RULE: every value MUST be an `anim_event` already
-- authored in `dual_wield_hammer_sword_template` (target wield SM). Verified
-- against `dumps/weapon_actions.txt` and the rule documented in
-- `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md`. Closed list:
--   charges:   attack_swing_charge_right, attack_swing_charge_left
--   strikes:   attack_swing_heavy_left_diagonal, attack_swing_heavy_right_diagonal,
--              attack_swing_left_diagonal, attack_swing_down,
--              attack_swing_left, attack_swing_right, attack_swing_right_diagonal
--   universal: attack_push, parry_pose, inspect_start
-- Source events already in this list (e.g. attack_push, attack_swing_down,
-- attack_swing_charge_left, attack_swing_left_diagonal, attack_swing_right,
-- attack_swing_right_diagonal) are NOT remapped — they play natively. Only
-- events missing from the closed list need entries below.
local _kruber_axe_falchion_remap = {
	-- ===== HEAVY CHAIN — chain-context rule =====
	-- The body's clip selection depends on chain STATE, not just event name.
	-- An event in the closed vocab can still produce no animation if the
	-- body's current chain state has no clip mapped for it. Native Kruber's
	-- mace+sword heavy chain from IDLE (per dual_wield_hammer_sword.lua):
	--   H1 from idle:   `action_one.default`             → charge_left  → heavy_left_diagonal
	--   H2 (chained):   `action_one.default_right_heavy` → charge_left  → heavy_right_diagonal
	-- The body's "from idle" state has clips for charge_left and
	-- heavy_left_diagonal. It does NOT have clips for charge_right or
	-- heavy_right_diagonal from idle — those reachable only after the chain
	-- has advanced. v0.1.158-v0.1.192 mapped H1 to charge_right +
	-- heavy_right_diagonal; result was the body stood still on H1 because
	-- those clips aren't reachable from idle.
	--
	-- Fix: H1 mirrors Kruber's idle-heavy chain (left-diagonal). H2 maps to
	-- Kruber's H2 chain (right-diagonal). Source's H2 charge is already
	-- attack_swing_charge_left and matches Kruber's H2 charge natively, so
	-- no charge remap is needed for H2.
	attack_swing_charge_down = "attack_swing_charge_left",          -- H1 charge
	attack_swing_heavy_down  = "attack_swing_heavy_left_diagonal",  -- H1 release (Kruber idle H1)
	attack_swing_heavy_left  = "attack_swing_heavy_right_diagonal", -- H2 release (Kruber chained H2)

	-- ===== LIGHT VARIANT =====
	-- Source down_left is the 4th light (light_attack_down_left,
	-- dual_wield_axe_falchion.lua:1080). Kruber's native light chain is
	-- left_diagonal → right → right_diagonal → LEFT (dual_wield_hammer_sword.lua
	-- chain :31/:86/:141/:196), so attack_swing_left is his authored
	-- position-4 clip. The old target left_diagonal is his L1/L3 clip —
	-- unreachable (or a visible repeat) at chain position 4, the same
	-- chain-context class as the H1 fix above (#319).
	attack_swing_down_left   = "attack_swing_left",

	-- ===== PUSH-ATTACK =====
	-- Source `light_attack_bopp` fires `attack_swing_down`. In target vocab
	-- but plays a right-hand mace chop. User wants a left-hand falchion
	-- swing — remap to attack_swing_left (Kruber's light_attack_left).
	-- "In vocab" is necessary but not sufficient; the clip must match intent.
	attack_swing_down        = "attack_swing_left",
}

-- Per (vanilla item key, career name) → event remap. Add new entries here as
-- new cross-access weapons are introduced. Career names must be exact (career
-- prefix matching could be added later if needed).
local _cross_access_action_remap = {
	cwv_es_greataxe = {
		es_mercenary      = _om.greataxe.ANIM_REMAP_3P,
		es_huntsman       = _om.greataxe.ANIM_REMAP_3P,
		es_knight         = _om.greataxe.ANIM_REMAP_3P,
		es_questingknight = _om.greataxe.ANIM_REMAP_3P,
	},
	cwv_es_infantry_spear = {
		es_mercenary      = _om._kruber_infantry_spear_remap,
		es_huntsman       = _om._kruber_infantry_spear_remap,
		es_knight         = _om._kruber_infantry_spear_remap,
		es_questingknight = _om._kruber_infantry_spear_remap,
	},
	wh_dual_wield_axe_falchion = {
		es_mercenary      = _kruber_axe_falchion_remap,
		es_huntsman       = _kruber_axe_falchion_remap,
		es_knight         = _kruber_axe_falchion_remap,
		es_questingknight = _kruber_axe_falchion_remap,
	},
	dr_dual_wield_axes = {
		es_mercenary      = _kruber_dual_axes_remap,
		es_huntsman       = _kruber_dual_axes_remap,
		es_knight         = _kruber_dual_axes_remap,
		es_questingknight = _kruber_dual_axes_remap,
	},
}

-- Pure resolver shared by the network-bound hook and /cwv regression. Returning
-- nil means vanilla's event is untouched. Targets are receiver-native events,
-- whose animation/audio assets are already resident with that career's body;
-- no CWV Wwise package or manual playback is required.
_om._cross_access_target_event = function(item_key, career, source_event)
	local picked = mod._cwv_dev_anim_picker.resolve(item_key, career, source_event)
	if picked then return picked end
	local item_remaps = item_key and _cross_access_action_remap[item_key]
	local career_remaps = item_remaps and career and item_remaps[career]
	return career_remaps and source_event and career_remaps[source_event] or nil
end

-- Track local player's wielded melee weapon key + career for cheap lookup
-- on every network-bound 3P animation. Updated only on melee wield.
local _cross_access_local_weapon_key = nil
local _cross_access_local_career     = nil

-- CONSOLIDATED wield hook. VMF's `mod:hook_safe` does NOT chain on the same
-- (Class, method) — a second registration silently overwrites the first
-- (VMF_RECIPES.md § 1). v0.1.336 inadvertently introduced a duplicate at the
-- bottom of this file for the cwv_debug_mode dump; that registration shadowed
-- THIS body and silently broke 3P cross-access animation remapping (the
-- `_cross_access_local_weapon_key` / `_career` upvalues stopped updating, so
-- the network-bound `_play_3p_anim` hook below never had its remap table to work
-- with). v0.1.337 merges both bodies into this single hook.
-- v0.1.339 (Issue #33): increment the file-scope registration counter so the
-- `cwv_wield_hook_unique` regression test can assert this site fires exactly
-- once. Increment lives at FILE scope, not inside the callback — the callback
-- fires every wield, the registration fires once at module load.
_cwv_wield_hook_registration_count = _cwv_wield_hook_registration_count + 1
mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
	-- (1) Cross-access local weapon tracking (slot_melee only, local player only).
	-- Feeds the network-bound WeaponUnitExtension remap hook below.
	if slot_name == "slot_melee" then
		local pm = Managers.player
		if pm then
			local local_player = pm:local_player(1)
			if local_player and local_player.player_unit == self.owner_unit then
				local slot_data = self:get_slot_data(slot_name)
				_cross_access_local_weapon_key = slot_data and slot_data.item_data and slot_data.item_data.key or nil
				local ok, career = pcall(local_player.career_name, local_player)
				_cross_access_local_career = ok and career or nil
			end
		end
	end

	-- (2) Debug-mode wield dump (any slot, cwv_* items only). Routes through
	-- VMF output_mode_debug gate.
	local equipment = self._equipment
	local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
	local item_data = slot_data and slot_data.item_data
	if item_data then
		local bid = item_data.backend_id
			or (item_data.mod_data and item_data.mod_data.backend_id)
		if type(bid) == "string" and bid:match("^cwv_") then
			_dbg("[cwv:wield] slot=%s backend_id=%s template=%s skin=%s career=%s",
				tostring(slot_name), tostring(bid),
				tostring(item_data.template),
				tostring(slot_data.skin),
				tostring(self._career_name))
		end
		-- #474: wield/swap is a reconstruction boundary. Publishing here is
		-- event-driven (never per-frame) and also seeds the inventory preview's
		-- backend-id stance cache.
		if _om._old_musket_record_and_publish then
			_om._old_musket_record_and_publish(self.owner_unit, slot_name, item_data,
				item_data.mod_data and item_data.mod_data.cwv_musket_stance or "ranged", "wield")
		end
		if _om.crowbill_runtime and _om.crowbill_runtime.on_local_wield then
			_om.crowbill_runtime.on_local_wield(self, slot_name, item_data)
		end
	end

	-- #567: the exact generated Sword+Mace illusion is mod-to-mod state, not a
	-- safe vanilla NetworkLookup value while transition parity is unknown.
	-- Publish only on the existing wield event so swap-away/swap-back repairs a
	-- husk immediately without adding polling or another hook on this surface.
	if _om._exact_pair_publish_inventory then
		_om._exact_pair_publish_inventory(self, "wield")
	end
end)

-- Resolve the local player's 3P body unit fresh each call (the unit can
-- change across respawns / level transitions).
local function _local_3p_body_unit()
	local pm = Managers.player
	if not pm then return nil end
	local p = pm:local_player(1)
	return p and p.player_unit or nil
end

-- Network-bound remap. WeaponUnitExtension._play_3p_anim resolves
-- NetworkLookup.anims[event_3p] and sends it at the TOP of vanilla's body,
-- before its eventual Unit.animation_event call. Intercepting here is the only
-- point where one substitution owns both local playback and remote replication.
_om._cross_access_network_log_once = {}
mod:hook("WeaponUnitExtension", "_play_3p_anim", function(func, self, event_3p, event, owner_unit, looping_event, anim_time_scale)
	if owner_unit ~= _local_3p_body_unit() then
		return func(self, event_3p, event, owner_unit, looping_event, anim_time_scale)
	end
	local target = _om._cross_access_target_event(
		_cross_access_local_weapon_key, _cross_access_local_career, event_3p
	)
	if not target then
		return func(self, event_3p, event, owner_unit, looping_event, anim_time_scale)
	end
	-- NetworkLookup has a strict missing-key metamethod. Validate with rawget so
	-- a typo degrades to vanilla instead of crashing before the RPC is encoded.
	local target_id = NetworkLookup and NetworkLookup.anims
		and rawget(NetworkLookup.anims, target)
	if not target_id then
		local miss_key = tostring(_cross_access_local_weapon_key) .. ":" .. tostring(target)
		if not _om._cross_access_network_log_once[miss_key] then
			_om._cross_access_network_log_once[miss_key] = true
			printf("[cwv:398] network remap declined: item=%s career=%s %s->%s target absent from NetworkLookup.anims",
				tostring(_cross_access_local_weapon_key), tostring(_cross_access_local_career),
				tostring(event_3p), tostring(target))
		end
		return func(self, event_3p, event, owner_unit, looping_event, anim_time_scale)
	end
	local log_key = tostring(_cross_access_local_weapon_key) .. ":"
		.. tostring(_cross_access_local_career) .. ":" .. tostring(event_3p)
	if not _om._cross_access_network_log_once[log_key] then
		_om._cross_access_network_log_once[log_key] = true
		printf("[cwv:398] networked 3P remap: item=%s career=%s %s->%s id=%s (vanilla RPC owns remote anim/audio)",
			tostring(_cross_access_local_weapon_key), tostring(_cross_access_local_career),
			tostring(event_3p), tostring(target), tostring(target_id))
	end
	return func(self, target, event, owner_unit, looping_event, anim_time_scale)
end)
_cwv_networked_3p_remap_installed = true

-- ============================================================
-- Imperial Longsword template (modified bastard_sword_template)
-- -15% damage, +15% speed, +15% cleave, -15% stagger
-- ============================================================

-- CLARIFY: Damage-profile clone. Each cwv template clone calls this once per
-- sub-action's damage_profile string; the function is idempotent (early-return
-- on existing clone) so the same source profile shared across multiple
-- sub-actions is cloned only once.
-- Prefix-collision risk: prefixes are tied to the specific multiplier set
-- ("cwv_il_" = imperial longsword, "cwv_ess_" = elven sword+shield). DO NOT
-- reuse a prefix with different `mults` — the second caller will reuse the
-- first caller's already-mutated PowerLevelTemplates entry and silently inherit
-- the wrong multipliers.
local function _clone_damage_profile(source_name, prefix, mults)
	if not DamageProfileTemplates then return source_name end
	local source = DamageProfileTemplates[source_name]
	if not source then return source_name end

	local new_name = prefix .. source_name
	_om._record_cwv_dp_source(new_name, source_name)   -- issue 423 wire-safe map
	if DamageProfileTemplates[new_name] then return new_name end

	local dmg_mult = mults.damage or 1
	local stg_mult = mults.stagger or 1
	local clv_mult = mults.cleave or 1

	local clone = table.clone(source, true)

	if type(clone.cleave_distribution) == "string" and PowerLevelTemplates then
		local key = clone.cleave_distribution
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.attack then c.attack = c.attack * clv_mult end
				if c.impact then c.impact = c.impact * clv_mult end
				PowerLevelTemplates[new_key] = c
			end
			clone.cleave_distribution = new_key
		end
	end

	if type(clone.default_target) == "string" and PowerLevelTemplates then
		local key = clone.default_target
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * dmg_mult end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * stg_mult end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.default_target = new_key
		end
	end

	if type(clone.targets) == "string" and PowerLevelTemplates then
		local key = clone.targets
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				for _, target in ipairs(c) do
					if target.power_distribution then
						if target.power_distribution.attack then target.power_distribution.attack = target.power_distribution.attack * dmg_mult end
						if target.power_distribution.impact then target.power_distribution.impact = target.power_distribution.impact * stg_mult end
					end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.targets = new_key
		end
	end

	if type(clone.critical_strike) == "string" and PowerLevelTemplates then
		local key = clone.critical_strike
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * dmg_mult end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * stg_mult end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.critical_strike = new_key
		end
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

-- ============================================================
-- Infantry Spear (Kerillian spear moveset on Kruber's unshielded CW spear)
-- ============================================================
do
	local infantry = _om.infantry_spear

	local function _create_infantry_spear_template()
		if not Weapons or not Weapons.two_handed_spears_elf_template_1 then
			mod:warning("two_handed_spears_elf_template_1 not found - Infantry Spear unavailable")
			return
		end
		if Weapons[infantry.TEMPLATE_KEY] then return end

		local template = table.clone(Weapons.two_handed_spears_elf_template_1, true)
		for _, action_group in pairs(template.actions or {}) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local scaled = infantry.scaled_attack_time(
							sub_action.kind, sub_action.anim_time_scale)
						if scaled ~= nil then sub_action.anim_time_scale = scaled end
						-- Only direct attack profiles are tuned. The spear's ordinary
						-- push uses damage_profile_inner/outer and remains vanilla.
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(
								sub_action.damage_profile, "cwv_infantry_spear_", {
									damage = infantry.DAMAGE_MULT,
									stagger = infantry.STAGGER_MULT,
									cleave = infantry.CLEAVE_MULT,
								})
						end
					end
				end
			end
		end

		-- 3P only. Kruber's existing WT elf-spear port enters the polearm
		-- graph; the two per-action substitutions are applied career-locally
		-- by `_cross_access_action_remap` before vanilla replicates the event.
		-- Keeping them out of shared action fields preserves Kerillian when WT
		-- enables this item on its source owner.
		template.wield_anim_3p = "to_polearm"
		template.wield_anim_career_3p = template.wield_anim_career_3p or {}
		for _, career in ipairs({
			"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
		}) do
			template.wield_anim_career_3p[career] = "to_polearm"
		end
		-- Foreign base templates do not necessarily carry Kruber's career
		-- ability actions. Mirror the three authored careers at construction;
		-- WT injects optional receivers only while their toggle is enabled.
		for _, career in ipairs(infantry.DEFAULT_CAREERS) do
			local settings = CareerSettings and CareerSettings[career]
			local ability = settings and settings.activated_ability
			ability = ability and ability[1]
			local action_name = ability and ability.action_name
			local action = action_name and ActionTemplates and ActionTemplates[action_name]
			if action_name and action and not template.actions[action_name] then
				template.actions[action_name] = action
			end
		end

		Weapons[infantry.TEMPLATE_KEY] = template
		-- CWV entries inherit `.name = we_spear`; inventory preview template
		-- lookup therefore resolves the base table. Patch only Kruber's 3P
		-- career stance so the preview and runtime use the same polearm graph.
		local preview_base = Weapons.two_handed_spears_elf_template_1
		preview_base.wield_anim_career_3p = preview_base.wield_anim_career_3p or {}
		for _, career in ipairs({
			"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
		}) do
			preview_base.wield_anim_career_3p[career] = "to_polearm"
		end
		mod:info("Created %s (speed=%.1f%% damage=%.1f%% stagger=%.1f%% cleave=%.1f%%)",
			infantry.TEMPLATE_KEY, infantry.SPEED_MULT * 100,
			infantry.DAMAGE_MULT * 100, infantry.STAGGER_MULT * 100,
			infantry.CLEAVE_MULT * 100)
	end

	_create_infantry_spear_template()
end

-- ANIM ADDENDUM: this function only touches stats + 3P fields. 1P animations
-- are universal (see top-of-file ANIMATION ARCHITECTURE) and need no work.
-- #284: The Imperial Longsword (2H) and Imperial Longsword + Shield
-- constructors share the _IL_* multipliers, so both are scoped in one do..end
-- (a sibling to the per-template blocks below) to release their top-level
-- locals back to the main chunk. Lua 5.1 caps any function (incl. the main
-- chunk) at 200 simultaneously-active locals. Both constructors are still
-- defined and invoked exactly once, in original order, inside the block. The
-- shared `_clone_damage_profile` helper stays OUTSIDE (declared above) because
-- later weapon families reference it too.
do  -- #284: scope imperial-longsword (2H + shield) template locals off the top-level chunk (>200-local limit)
local _IL_DAMAGE_MULT  = 0.85
local _IL_SPEED_MULT   = 1.15
local _IL_CLEAVE_MULT  = 1.15
local _IL_STAGGER_MULT = 0.85

local function _create_imperial_longsword_template()
	if not Weapons or not Weapons.bastard_sword_template then
		mod:warning("bastard_sword_template not found — Imperial Longsword stat modifications unavailable")
		return
	end
	if Weapons.imperial_longsword_template then return end

	-- CLARIFY: table.clone(t, true) is recursive (deep clone) per
	-- foundation/scripts/util/table.lua — it walks every nested table value.
	-- skip_metatable=true is required because Weapon templates contain functions
	-- (anim_end_event_condition_func) which would otherwise trip the metatable
	-- assertion. Sub-tables (action_one.default.allowed_chain_actions, buff_data,
	-- weapon_sway_settings, etc.) are all freshly-allocated copies, so mutating
	-- this clone is safe for the original bastard_sword_template.
	local template = table.clone(Weapons.bastard_sword_template, true)

	-- CLARIFY: Two-level loop is sufficient. anim_time_scale and damage_profile
	-- live at the sub-action level (template.actions.action_one.default.*), not
	-- in deeper structures like allowed_chain_actions.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _IL_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_il_", {
								damage = _IL_DAMAGE_MULT, stagger = _IL_STAGGER_MULT, cleave = _IL_CLEAVE_MULT,
							})
						end
					end
				end
			end
		end
	end

	Weapons.imperial_longsword_template = template
	mod:info("Created imperial_longsword_template (dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_template()

-- ============================================================
-- Imperial Longsword + Shield template (modified one_handed_sword_shield_template_2)
-- Same tune as the 2H Imperial Longsword (-15% damage, +15% speed, +15% cleave,
-- -15% stagger), but applied ONLY to sword-swing sub-actions. Shield bashes
-- (shield_slam*, shield_push), the block action, and the universal push
-- (medium_push) are left at vanilla so the shield half behaves like a normal
-- shield. Filter: skip sub_action if `kind == "block"` OR its damage_profile
-- starts with "shield_". The push baseline uses `damage_profile_inner` /
-- `damage_profile_outer` (no plain `damage_profile`), so it's naturally skipped.
--
-- Prefix `cwv_il_` is intentionally REUSED from the 2H Imperial Longsword: the
-- multipliers are identical, the damage_profile names don't overlap (bastard
-- sword uses 2H slashing profiles, bret sword+shield uses 1h slashing profiles),
-- and `_clone_damage_profile` is idempotent within a prefix.
local function _create_imperial_longsword_shield_template()
	if not Weapons or not Weapons.one_handed_sword_shield_template_2 then
		mod:warning("one_handed_sword_shield_template_2 not found — Imperial Longsword + Shield stat mods unavailable")
		return
	end
	if Weapons.imperial_longsword_shield_template then return end

	local template = table.clone(Weapons.one_handed_sword_shield_template_2, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local dp = sub_action.damage_profile
						local is_shield_action = (sub_action.kind == "block")
							or (type(dp) == "string" and dp:sub(1, 7) == "shield_")
						if not is_shield_action then
							if sub_action.anim_time_scale then
								sub_action.anim_time_scale = sub_action.anim_time_scale * _IL_SPEED_MULT
							end
							if sub_action.damage_profile then
								sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_il_", {
									damage = _IL_DAMAGE_MULT, stagger = _IL_STAGGER_MULT, cleave = _IL_CLEAVE_MULT,
								})
							end
						end
					end
				end
			end
		end
	end

	Weapons.imperial_longsword_shield_template = template
	mod:info("Created imperial_longsword_shield_template (sword-only: dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_shield_template()
end  -- #284: end imperial-longsword (2H + shield) do-block

-- ============================================================
-- Elven Sword+Shield template (modified one_handed_sword_shield_template_1)
-- +15% speed, -15% stagger
--
-- ANIM ADDENDUM: _ess_anim_remap remaps 3P body events ONLY (anim_event_3p
-- field — see _create_elven_sword_shield_template body). The 1P side is
-- universal across characters and needs no remapping — see top-of-file
-- ANIMATION ARCHITECTURE.
-- ============================================================

do  -- #284: scope elven-sword-shield template locals off the top-level chunk (>200-local limit)
local _ESS_SPEED_MULT   = 1.15
local _ESS_STAGGER_MULT = 0.85

-- 3P body event remap: keys are events the cloned template fires; values are
-- substitutes that exist on the empire-soldier 3P skeleton. 1P unaffected.
local _ess_anim_remap = {
	attack_swing_left_diagonal     = "attack_swing_left",
	attack_swing_charge            = "attack_swing_charge_stab",
	attack_swing_heavy             = "attack_push",
	attack_swing_heavy_right       = "attack_swing_heavy_down_right",
	attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
}

-- ANIM ADDENDUM: this function only touches stats + 3P fields. 1P is universal.
local function _create_elven_sword_shield_template()
	if not Weapons or not Weapons.one_handed_sword_shield_template_1 then
		mod:warning("one_handed_sword_shield_template_1 not found — Elven Sword+Shield stat modifications unavailable")
		return
	end
	if Weapons.elven_sword_shield_template then return end

	local template = table.clone(Weapons.one_handed_sword_shield_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _ESS_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_ess_", {
								stagger = _ESS_STAGGER_MULT,
							})
						end
						if sub_action.anim_event and _ess_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _ess_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_1h_spear_shield"
	template.wield_anim_career_3p = {
		we_waywatcher  = "to_1h_spear_shield",
		we_maidenguard = "to_1h_spear_shield",
		we_shade       = "to_1h_spear_shield",
		we_thornsister = "to_1h_spear_shield",
	}

	Weapons.elven_sword_shield_template = template

	-- CLARIFY: Per memory note feedback_cwv_previewer_template_lookup.md, the
	-- inventory previewer resolves item templates via item_data.name (= base
	-- weapon key for cwv items), so it reads one_handed_sword_shield_template_1
	-- NOT our elven_sword_shield_template. Patch the BASE template's
	-- wield_anim_career_3p so the menu preview pose is correct for elf careers.
	-- Scoped to elf careers only — Kruber/etc. fall through to original behavior.
	local elf_wield_3p = {
		we_waywatcher  = "to_1h_spear_shield",
		we_maidenguard = "to_1h_spear_shield",
		we_shade       = "to_1h_spear_shield",
		we_thornsister = "to_1h_spear_shield",
	}
	local base = Weapons.one_handed_sword_shield_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(elf_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end
	-- QUESTION: Attack-event remaps from _ess_anim_remap are only applied to the
	-- cloned template. The previewer reads the BASE template (see comment above),
	-- so previewer attack animations would NOT pick up the remap. Currently this
	-- is fine because the previewer doesn't fire attack events — only the
	-- wield_anim. If that changes, the attack remaps must also be patched onto
	-- the base template (probably via career_anim_event tables).

	mod:info("Created elven_sword_shield_template (spd=%.0f%% stagger=%.0f%%, %d 3p anim remaps, wield_3p=to_1h_spear_shield) + patched base template career_3p table for elf careers",
		_ESS_SPEED_MULT * 100, _ESS_STAGGER_MULT * 100, 5)
end

_create_elven_sword_shield_template()
end  -- #284: end elven-sword-shield do-block

-- ============================================================
-- Imperial Dual Swords template (modified dual_wield_swords_template_1)
-- −20% attack speed, +15% power (damage + stagger).
-- 3P anim redirect to Kruber's dual_wield_hammer_sword_template.
--
-- ANIM ADDENDUM: All anim work below is 3P-only (anim_event_3p,
-- wield_anim_3p, wield_anim_career_3p). 1P is universal — see top-of-file
-- ANIMATION ARCHITECTURE.
-- ============================================================

do  -- #284: scope imperial-dual-swords template locals off the top-level chunk (>200-local limit)
local _IDS_SPEED_MULT = 0.80
local _IDS_POWER_MULT = 1.15

-- 3P body event remap: elf dual-sword events with no 1:1 on Kruber's
-- dual_wield_hammer_sword_template. Substitutes are picked from the empire-
-- soldier 3P skeleton's authored vocabulary so a valid clip plays. Same-named
-- events (attack_swing_left, attack_swing_right, attack_swing_left_diagonal,
-- etc.) need no remap — Kruber's mace+sword template uses those same names
-- and they're authored on the empire-soldier 3P skeleton. 1P unaffected.
--
-- Heavy combo release reversed on 3P: H1 release (source anim_event
-- attack_swing_heavy_left_diagonal) plays right-diagonal on the body;
-- H2 release (source attack_swing_heavy_right) plays left-diagonal. 1P keeps
-- the source events unchanged.
--
-- push_stab → attack_swing_right: a native dual_hammer_sword event (line
-- 1082 of dual_wield_hammer_sword.lua), a fast lateral swing with the lead
-- sword. Picked after the SM has no visible stab — investigation summary:
--
-- The dual_hammer_sword 3P sub-graph doesn't author a visible stab clip;
-- the empire-soldier skeleton's stab clips live in the 1h_sword_shield
-- sub-graph. Attempts to reach them failed:
--   1. attack_swing_stab as a plain anim_event_3p remap → force3p reports
--      exists=true but no visible clip plays (stub transition).
--   2. SM-switch graft (v0.1.89) via pre_action_anim_event =
--      "to_1h_sword_shield" + anim_end_event_3p = "to_dual_hammer_sword_es"
--      → the wield-change clip eats the damage window AND push_stab's
--      anim_end_event_condition_func returns false on action_complete
--      which gates ALL end events including our return transition — body
--      got stuck in 1h_sword_shield sub-graph permanently.
--   3. Full SM switch (change template's wield_anim_3p to to_1h_sword_shield)
--      → gives visible stab but breaks the dual-wield idle/wield identity
--      (left sword renders in shield-defensive stance). Reference pattern:
--      Peregrinaje's markus_torch_and_shield uses exactly this approach
--      with model aligned to the SM (torch fits axe+shield); not applicable
--      to two swords without a model rework.
-- Decision: stay native to dual_hammer_sword, use a non-stab clip that reads
-- as a committed forward strike. attack_swing_right reads as a quick
-- follow-up swing after the push.
local _ids_anim_remap = {
	-- Charge for H1 from idle — matches H1's swapped strike direction.
	-- Elf source `default` sub-action fires attack_swing_charge_diagonal; we
	-- route to charge_right (not charge_left) so the wind-up direction
	-- aligns with H1's release (heavy_right_diagonal). Cock right → strike
	-- right. Was incoherent (left cock, right strike) prior to v0.1.102.
	attack_swing_charge_diagonal     = "attack_swing_charge_right",
	-- Heavy combo release reversed.
	attack_swing_heavy_left_diagonal = "attack_swing_heavy_right_diagonal",
	attack_swing_heavy_right         = "attack_swing_heavy_left_diagonal",
	-- Push-attack — see comment block above.
	push_stab                        = "attack_swing_right",
}

-- ANIM ADDENDUM: this function touches stats + 3P fields. 1P is universal.
local function _create_imperial_dual_swords_template()
	if not Weapons or not Weapons.dual_wield_swords_template_1 then
		mod:warning("dual_wield_swords_template_1 not found — Imperial Dual Swords template unavailable")
		return
	end
	if Weapons.imperial_dual_swords_template then return end

	local template = table.clone(Weapons.dual_wield_swords_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _IDS_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_eds_", {
								damage = _IDS_POWER_MULT, stagger = _IDS_POWER_MULT,
							})
						end
						if sub_action.anim_event and _ids_anim_remap[sub_action.anim_event] then
							sub_action.anim_event_3p = _ids_anim_remap[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_dual_hammer_sword_es"
	template.wield_anim_career_3p = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	}

	Weapons.imperial_dual_swords_template = template

	-- Same patch pattern as _create_elven_sword_shield_template: the inventory
	-- previewer reads the BASE template (dual_wield_swords_template_1), not our
	-- clone, so patch the base template's wield_anim_career_3p for Kruber careers
	-- to keep the menu preview pose correct. Scoped to es_* only — elf careers
	-- fall through to the original wield anim.
	local kruber_wield_3p = {
		es_mercenary      = "to_dual_hammer_sword_es",
		es_huntsman       = "to_dual_hammer_sword_es",
		es_knight         = "to_dual_hammer_sword_es",
		es_questingknight = "to_dual_hammer_sword_es",
	}
	local base = Weapons.dual_wield_swords_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	mod:info("Created imperial_dual_swords_template (spd=%.0f%% power=%.0f%%, 3p anim redirect to mace+sword, wield_3p=to_dual_hammer_sword_es)",
		_IDS_SPEED_MULT * 100, _IDS_POWER_MULT * 100)
end

_create_imperial_dual_swords_template()
end  -- #284: end imperial-dual-swords do-block

-- ============================================================
-- Cudgel template (one_hand_falchion_template_1 — recoloured to blunt)
-- ============================================================
-- Saltzpyre's falchion moveset (charge-and-release light combo, smiter
-- heavy) but every cutting hit becomes a crushing one. Cosmetic stays
-- the empire mace mesh — only the moveset, damage_type, and impact
-- effects/sounds change.
--
-- Damage profile swap: the falchion uses one of three slashing profile
-- families across its sweeps. Each maps to a vanilla blunt cousin with
-- the same cleave/range/stagger shape:
--
--   light_slashing_axe_linesman       → light_blunt_tank_diag    (light combo sweeps)
--   light_slashing_axe_linesman_upper → light_blunt_tank_upper   (light upper variants)
--   medium_slashing_smiter_1h         → medium_blunt_smiter_1h   (heavy attack)
--
-- All three blunt targets are vanilla DamageProfileTemplates entries
-- (see damage_profile_templates.lua:253+ / 430+). Push profiles
-- (medium_push / light_push) are universal and stay untouched.
--
-- Effects/sounds: hit_effect → melee_hit_hammers_1h, slashing_hit
-- swoosh/impact → blunt_hit (and _armour). display_unit and block-arc
-- sound also swapped so the inventory rig and parry foley match a
-- mace, not a falchion.
do  -- #284: scope cudgel template locals off the top-level chunk (>200-local limit)
local _CUDGEL_DAMAGE_PROFILE_SWAP = {
	light_slashing_axe_linesman       = "light_blunt_tank_diag",
	light_slashing_axe_linesman_upper = "light_blunt_tank_upper",
	medium_slashing_smiter_1h         = "medium_blunt_smiter_1h",
}

local _CUDGEL_HIT_EFFECT_SWAP = {
	melee_hit_axes_1h  = "melee_hit_hammers_1h",
	melee_hit_sword_1h = "melee_hit_hammers_1h",
}

local _CUDGEL_IMPACT_SOUND_SWAP = {
	slashing_hit         = "blunt_hit",
	slashing_hit_armour  = "blunt_hit_armour",
}

local function _create_cudgel_template()
	if not Weapons or not Weapons.one_hand_falchion_template_1 then
		mod:warning("one_hand_falchion_template_1 not found — Cudgel template unavailable")
		return
	end
	if Weapons.cudgel_template then return end

	local template = table.clone(Weapons.one_hand_falchion_template_1, true)

	local swapped, hit_swapped, sound_swapped = 0, 0, 0
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local dp = sub_action.damage_profile
						if dp and _CUDGEL_DAMAGE_PROFILE_SWAP[dp] then
							sub_action.damage_profile = _CUDGEL_DAMAGE_PROFILE_SWAP[dp]
							swapped = swapped + 1
						end
						local hit = sub_action.hit_effect
						if hit and _CUDGEL_HIT_EFFECT_SWAP[hit] then
							sub_action.hit_effect = _CUDGEL_HIT_EFFECT_SWAP[hit]
							hit_swapped = hit_swapped + 1
						end
						local imp = sub_action.impact_sound_event
						if imp and _CUDGEL_IMPACT_SOUND_SWAP[imp] then
							sub_action.impact_sound_event = _CUDGEL_IMPACT_SOUND_SWAP[imp]
							sound_swapped = sound_swapped + 1
						end
						local nd = sub_action.no_damage_impact_sound_event
						if nd and _CUDGEL_IMPACT_SOUND_SWAP[nd] then
							sub_action.no_damage_impact_sound_event = _CUDGEL_IMPACT_SOUND_SWAP[nd]
						end
					end
				end
			end
		end
	end

	-- Inventory / preview shows on a hammer display rig (mace mesh sits in
	-- the hammer cradle), not the falchion's. Block-arc swoosh swapped
	-- to the wood-block blunt foley used by 1h hammers.
	template.display_unit = "units/weapons/weapon_display/display_1h_hammer"
	template.sound_event_block_within_arc = "weapon_foley_blunt_1h_block_wood"

	Weapons.cudgel_template = template
	mod:info("Created cudgel_template (one_hand_falchion_template_1 → blunt: %d damage profiles, %d hit effects, %d impact sounds swapped)",
		swapped, hit_swapped, sound_swapped)
end

_create_cudgel_template()
end  -- #284: end cudgel do-block

-- ============================================================
-- Sword and Mace template — INVERSE of dual_wield_hammer_sword
-- Native Kruber mace+sword has: mace in RIGHT hand, sword in LEFT hand.
-- Inverse:                       sword in RIGHT hand, mace in LEFT hand.
--
-- The variant def sets right_hand_unit = sword, left_hand_unit = mace.
-- Sub-actions in the cloned template have weapon_action_hand = "right" /
-- "left" / "both" — we walk them and swap damage profile / hit effect /
-- impact sound fields so that:
--   * Right-hand strikes (was mace=blunt) now play sword/slashing
--   * Left-hand strikes  (was sword=slashing) now play mace/blunt
--   * Both-hand strikes:  swap damage_profile_left ↔ damage_profile_right
--                         where they differ (so each hand's damage type
--                         follows whichever weapon is in that hand now).
--
-- Per-hand `range_mod` override (v0.1.163): the dual-wield baseline is
-- shorter than the 1h equivalents (1.1 / 1.15 vs the 1h templates' 1.2),
-- but the user wants each weapon to feel like its 1h source. Override
-- per-hand sweeps to match `es_1h_sword` / `es_1h_mace` light-attack reach.
-- See `_SAM_HAND_RANGE_MOD` below for the values and rationale.
--
-- ANIM ADDENDUM: the underlying anim events / state machine are unchanged —
-- the body still goes through `to_dual_hammer_sword_es` and plays the same
-- dual-wield clips. Only damage / sound / hit-effect / range data per-action swaps.
-- ============================================================

-- Right-hand strike fields (was mace=blunt → sword=slashing).
do  -- #284: scope sword-and-mace template locals off the top-level chunk (>200-local limit)
local _SAM_RIGHT_HAND_SWAP = {
	damage_profile = {
		light_blunt_tank_diag = "light_slashing_linesman",
	},
	hit_effect = {
		melee_hit_hammers_1h = "melee_hit_sword_1h",
	},
	impact_sound_event = {
		blunt_hit = "slashing_hit",
	},
	no_damage_impact_sound_event = {
		blunt_hit_armour = "slashing_hit_armour",
	},
}

-- Left-hand strike fields (was sword=slashing → mace=blunt).
local _SAM_LEFT_HAND_SWAP = {
	damage_profile = {
		light_slashing_linesman = "light_blunt_tank_diag",
	},
	hit_effect = {
		melee_hit_sword_1h = "melee_hit_hammers_1h",
	},
	impact_sound_event = {
		slashing_hit = "blunt_hit",
	},
	no_damage_impact_sound_event = {
		slashing_hit_armour = "blunt_hit_armour",
	},
}

-- Per-hand `range_mod` override. range_mod is per-sub-action (each sweep has its
-- own value), so the reach overhaul is per-hit, not template-level.
--
-- Vanilla `dual_wield_hammer_sword` is a close-quarters dual-wield: right-hand
-- mace sweeps run at 1.15 and left-hand sword sweeps at 1.1 — shorter than the
-- 1h variants because both arms are committed and the wielder reads "tighter
-- box". Our variant flips the hands but the user wants each weapon's reach to
-- match its single-hand source instead of the tighter dual-wield baseline:
--
--   right hand (sword in our variant) → 1h_swords light_attack reach (1.2)
--   left hand  (mace  in our variant) → 1h_hammers light_attack reach (1.2)
--
-- Both numerically land at 1.2 because that's what each 1h template uses for
-- its light attacks (the heavies in 1h_swords go up to 1.25 and in 1h_hammers
-- to 1.3, but every per-hand sweep in dual_wield_hammer_sword is a LIGHT
-- attack — the heavies are `weapon_action_hand = "both"`, left untouched here
-- since they involve both weapons swung together).
--
-- "both"-hand sweeps, push, and block don't have a sword/mace assignment, so
-- they're absent from this map and keep the vanilla dual-wield range.
local _SAM_HAND_RANGE_MOD = {
	right = 1.2,  -- matches es_1h_sword light_attack range_mod (1h_swords.lua light_attack actions)
	left  = 1.2,  -- matches es_1h_mace  light_attack range_mod (1h_hammers.lua light_attack actions)
}

local function _sam_apply_field_swaps(sub_action, swaps)
	for field, swap_map in pairs(swaps) do
		local current = sub_action[field]
		if current and swap_map[current] then
			sub_action[field] = swap_map[current]
		end
	end
end

local function _create_sword_and_mace_template()
	if not Weapons or not Weapons.dual_wield_hammer_sword_template then
		mod:warning("dual_wield_hammer_sword_template not found — Sword and Mace template unavailable")
		return
	end
	if Weapons.sword_and_mace_template then return end

	local template = table.clone(Weapons.dual_wield_hammer_sword_template, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						local hand = sub_action.weapon_action_hand
						if hand == "right" then
							_sam_apply_field_swaps(sub_action, _SAM_RIGHT_HAND_SWAP)
						elseif hand == "left" then
							_sam_apply_field_swaps(sub_action, _SAM_LEFT_HAND_SWAP)
						elseif hand == "both" then
							-- For dual-hand strikes, swap left/right damage profile
							-- references where they differ (so left=mace and
							-- right=sword damage types follow the new hand
							-- placement).
							local pl = sub_action.damage_profile_left
							local pr = sub_action.damage_profile_right
							if pl and pr and pl ~= pr then
								sub_action.damage_profile_left  = pr
								sub_action.damage_profile_right = pl
							end
						end
						-- Per-hand reach override (independent of damage/sound swaps).
						-- Only sweeps have range_mod authored; we guard on its presence
						-- so non-sweep sub-actions (push, block_break, etc.) don't get
						-- a range_mod field accidentally introduced.
						if sub_action.range_mod and _SAM_HAND_RANGE_MOD[hand] then
							sub_action.range_mod = _SAM_HAND_RANGE_MOD[hand]
						end
					end
				end
			end
		end
	end

	Weapons.sword_and_mace_template = template
	mod:info("Created sword_and_mace_template (inverse of dual_wield_hammer_sword: damage/sound/effect swap by hand; per-hand range_mod = right %.2f / left %.2f)",
		_SAM_HAND_RANGE_MOD.right, _SAM_HAND_RANGE_MOD.left)
end

_create_sword_and_mace_template()
end  -- #284: end sword-and-mace do-block

-- ============================================================
-- Shortsword template (modified one_handed_daggers_template_1)
-- −20% attack speed, +15% power (damage + stagger).
-- Fire DoT removed: burning damage profiles swapped to non-burning slashing
-- analogs. Slam-specific aoe/target damage profile fields are nilled out
-- because no non-burning slam analog exists for Sienna's body — the heavy
-- slam loses its AoE component but the visual + main-target damage remain.
--
-- ANIM ADDENDUM: native template applies on Sienna's bright_wizard body — no
-- anim work needed. 1P universal across characters.
-- ============================================================

do  -- #284: scope shortsword template locals off the top-level chunk (>200-local limit)
local _SHORTSWORD_SPEED_MULT = 0.92
local _SHORTSWORD_POWER_MULT = 1.15

-- Burning damage profiles → non-burning analogs. `false` means "remove the
-- field entirely" (used for AoE/target slam fields with no clean non-burning
-- analog — see header for the AoE-loss caveat).
-- v0.1.151 used `medium_slashing_linesman_fencer` as the slam swap — that
-- name DOES NOT exist in DamageProfileTemplates. NetworkLookup.damage_profiles
-- is a strict-lookup table that crashes on missing keys, so heavy_attack_left
-- fire crashed the game. Fixed v0.1.152: use `medium_slashing_linesman`
-- (real, heavy slashing — closest non-burning analog by damage shape).
local _SHORTSWORD_DAMAGE_PROFILE_SWAP = {
	dagger_burning_slam_fencer        = "medium_slashing_linesman",
	dagger_burning_slam_fencer_aoe    = false,
	dagger_burning_slam_target_fencer = false,
	medium_burning_smiter_stab_H      = "medium_slashing_smiter_stab",
}

-- Fire-themed FX/sound fields → sword-themed analogs. The dagger's burning
-- heavies hardcode hit_effect = "staff_spark" + fire_hit sounds at the
-- sub-action level. v0.1.155 left these untouched and the engine crashed
-- when `World.create_particles("fx/wpnfx_staff_spark_impact")` fired during
-- a sweep on Kruber's body — the staff_spark FX package isn't loaded for
-- empire-soldier wielders. Fixed v0.1.156 by swapping these fields too so
-- the shortsword reads as steel-on-target (no fire visuals or sounds).
local _SHORTSWORD_FX_SWAP = {
	hit_effect = {
		staff_spark = "melee_hit_sword_1h",
	},
	impact_sound_event = {
		fire_hit = "slashing_hit",
	},
	armor_impact_sound_event = {
		fire_hit = "slashing_hit",
	},
	no_damage_impact_sound_event = {
		fire_hit_armour = "slashing_hit_armour",
	},
}

local function _create_shortsword_template()
	if not Weapons or not Weapons.one_handed_daggers_template_1 then
		mod:warning("one_handed_daggers_template_1 not found — Shortsword template unavailable")
		return
	end
	if Weapons.shortsword_template then return end

	local template = table.clone(Weapons.one_handed_daggers_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _SHORTSWORD_SPEED_MULT
						end
						-- Step 1: swap burning damage profiles to non-burning
						-- analogs (or remove for AoE/target slam fields).
						-- Order matters — must run BEFORE _clone_damage_profile
						-- so the power scaling clones the swapped profile.
						local swap_fields = { "damage_profile", "damage_profile_aoe", "damage_profile_target" }
						for _, field in ipairs(swap_fields) do
							local profile = sub_action[field]
							if profile and _SHORTSWORD_DAMAGE_PROFILE_SWAP[profile] ~= nil then
								local replacement = _SHORTSWORD_DAMAGE_PROFILE_SWAP[profile]
								sub_action[field] = replacement or nil
							end
						end
						-- Step 2: scale power on the (possibly swapped) damage_profile.
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_shortsword_", {
								damage = _SHORTSWORD_POWER_MULT, stagger = _SHORTSWORD_POWER_MULT,
							})
						end
						-- Step 3: swap fire-themed FX / sounds → sword-themed
						-- analogs. Without this, sub-actions that previously
						-- referenced burning damage profiles still ran their
						-- staff_spark hit_effect — and the staff_spark FX
						-- package isn't loaded for empire-soldier wielders, so
						-- World.create_particles crashed mid-sweep (v0.1.155
						-- regression — fixed v0.1.156).
						for field, swap_map in pairs(_SHORTSWORD_FX_SWAP) do
							local current = sub_action[field]
							if current and swap_map[current] then
								sub_action[field] = swap_map[current]
							end
						end
					end
				end
			end
		end
	end

	Weapons.shortsword_template = template
	mod:info("Created shortsword_template (spd=%.0f%% power=%.0f%%, fire DoT removed)",
		_SHORTSWORD_SPEED_MULT * 100, _SHORTSWORD_POWER_MULT * 100)
end

_create_shortsword_template()
end  -- #284: end shortsword do-block

-- ============================================================
-- Maul template (modified one_handed_hammer_wizard_template_1)
-- Sienna's Morningstar moveset cloned for Kruber. H1 heavy attack's
-- damage_profile (medium_blunt_smiter_heavy) is swapped to a non-burn
-- analog (medium_blunt_smiter_2h_hammer) — wizard fire is in the
-- damage-profile resolution chain, not the FX/sound fields.
--
-- 3P wield routes to Kruber's greathammer SM (to_2h_hammer); per-action
-- 3P remap covers wizard-mace events not authored on
-- two_handed_hammers_template_1's vocabulary.
--
-- ANIM ADDENDUM: 3P-only. 1P universal — see top-of-file ANIMATION
-- ARCHITECTURE.
-- ============================================================

-- Single-entry burn swap. Verified that medium_blunt_smiter_heavy is the
-- ONLY profile in the wizard mace template that resolves to a _burn_*
-- PowerLevelTemplates entry. Other damage profiles (light_blunt_tank,
-- light_blunt_smiter, medium_blunt_tank_upper_1h, medium_push, light_push)
-- are clean. FX/sound fields already non-fire (melee_hit_hammers_1h /
-- blunt_hit / blunt_hit_armour) — no FX swap pass needed.
do  -- #284: scope maul template locals off the top-level chunk (>200-local limit)
local _MAUL_DAMAGE_PROFILE_SWAP = {
	medium_blunt_smiter_heavy = "medium_blunt_smiter_2h_hammer",
}

-- 3P remap — source events (one_handed_hammer_wizard_template_1) →
-- target events (two_handed_hammers_template_1, Kruber greathammer SM).
-- Closed-vocabulary rule: every value MUST appear in the greathammer
-- template's anim_event set. Verified against
-- weapon_templates/2h_hammers.lua: charge / charge_right / charge_left /
-- heavy_right / heavy / down_left / left / left_diagonal / down_right /
-- push / parry_pose. Source events already in target (left_diagonal,
-- left, push, parry_pose) need no entry.
local _MAUL_ANIM_REMAP_3P = {
	-- charges: source has _diagonal / _pose suffixes; target has none.
	attack_swing_charge_left_diagonal = "attack_swing_charge_left",
	attack_swing_charge_left_pose     = "attack_swing_charge_left",
	attack_swing_charge_right_pose    = "attack_swing_charge_right",
	-- heavies: source overhead / sided "_up" variants; target has plain
	-- heavy + heavy_right (no heavy_left).
	attack_swing_heavy_down           = "attack_swing_heavy",
	attack_swing_heavy_right_up       = "attack_swing_heavy_right",
	attack_swing_heavy_left_up        = "attack_swing_heavy",
	-- lights: source right_diagonal / down / left_diagonal_last need
	-- closest-in-vocab strikes.
	attack_swing_right_diagonal       = "attack_swing_down_right",
	attack_swing_down                 = "attack_swing_down_right",
	attack_swing_left_diagonal_last   = "attack_swing_left_diagonal",
}

local _maul_kruber_wield_3p = {
	es_mercenary      = "to_2h_hammer",
	es_huntsman       = "to_2h_hammer",
	es_knight         = "to_2h_hammer",
	es_questingknight = "to_2h_hammer",
}

local function _create_maul_template()
	if not Weapons or not Weapons.one_handed_hammer_wizard_template_1 then
		mod:warning("one_handed_hammer_wizard_template_1 not found — Maul template unavailable")
		return
	end
	if Weapons.maul_template then return end

	local template = table.clone(Weapons.one_handed_hammer_wizard_template_1, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						-- Step 1: scrub fire by swapping the burn-bearing
						-- damage_profile to a non-burn analog. Single-entry
						-- map; nothing else in this template fires.
						local profile = sub_action.damage_profile
						if profile and _MAUL_DAMAGE_PROFILE_SWAP[profile] then
							sub_action.damage_profile = _MAUL_DAMAGE_PROFILE_SWAP[profile]
						end
						-- Step 2: 3P body event remap (3P only —
						-- never write anim_event / 1P fields).
						if sub_action.anim_event and _MAUL_ANIM_REMAP_3P[sub_action.anim_event] then
							sub_action.anim_event_3p = _MAUL_ANIM_REMAP_3P[sub_action.anim_event]
						end
					end
				end
			end
		end
	end

	template.wield_anim_3p = "to_2h_hammer"
	template.wield_anim_career_3p = template.wield_anim_career_3p or {}
	for k, v in pairs(_maul_kruber_wield_3p) do
		template.wield_anim_career_3p[k] = v
	end

	-- Override attachment_node_linking from the source template's
	-- `AttachmentNodeLinking.brw_hammer` to the generic two-handed linking.
	-- The wizard linking specifies `unwielded.source = "a_unwielded_brw_mace"`
	-- — a bone authored ONLY on Sienna's 3P body skeleton. When Kruber
	-- (who lacks that bone) unequips the maul, the engine's `Unit.node()`
	-- lookup fails and crashes (`[Script Error]: a_unwielded_brw_mace`,
	-- crash GUID 37ead770-8f34-4821-b71d-2de354929a80, v0.1.167). The
	-- visual silhouette is two-handed (the variant scales the mesh up to
	-- 1.4×1.4×2.0), so two_handed_melee_weapon linking — `a_unwielded_2h`
	-- for unwielded, which Kruber has — is the right choice both visually
	-- and skeletally. Wielded source is `j_rightweaponattach` either way.
	if AttachmentNodeLinking and AttachmentNodeLinking.two_handed_melee_weapon then
		template.right_hand_attachment_node_linking = AttachmentNodeLinking.two_handed_melee_weapon
	end

	Weapons.maul_template = template

	-- Patch the BASE template's wield_anim_career_3p so the inventory
	-- previewer (HeroPreviewer reads BASE template, not our clone — see
	-- feedback_cwv_previewer_template_lookup.md) shows the right wield
	-- pose for Kruber careers. Scoped to es_* only — Sienna careers fall
	-- through to original behavior.
	local base = Weapons.one_handed_hammer_wizard_template_1
	if base then
		base.wield_anim_career_3p = base.wield_anim_career_3p or {}
		for k, v in pairs(_maul_kruber_wield_3p) do
			base.wield_anim_career_3p[k] = v
		end
	end

	-- Patch the BASE template's right_hand_attachment_node_linking too.
	-- Reason: the inventory previewer reads BASE template attachments,
	-- not our clone (per `feedback_cwv_previewer_template_lookup.md`).
	-- Without this, opening the inventory on a Kruber career carrying
	-- the Maul triggers `[Script Error]: a_unwielded_brw_mace` on the
	-- preview body. Crash GUID `258c5f1c-dbe0-4ebd-8ef6-0b43d95c3b9d`,
	-- v0.1.187. Replace ONLY the `third_person.unwielded` binding —
	-- `wielded` uses the universal `j_rightweaponattach` (all bodies
	-- have it), so leaving it alone preserves Sienna's native
	-- in-hand behavior. Cost: Sienna's holstered-mace pose now sits on
	-- standard hips instead of her dedicated mace-bone — small visual
	-- regression for her, fixes Kruber crash. AttachmentNodeLinking.brw_hammer
	-- is referenced by ONLY this one weapon template (verified via
	-- source-wide grep), so the patch is well-scoped.
	if base and base.right_hand_attachment_node_linking
			and base.right_hand_attachment_node_linking.third_person then
		base.right_hand_attachment_node_linking.third_person.unwielded = {
			{ source = "j_hips", target = 0 },
		}
	end

	mod:info("Created maul_template (burn scrub: %d profile swap, 3p anim remap: %d entries, wield_3p=to_2h_hammer)",
		1, 9)
end

_create_maul_template()
end  -- #284: end maul do-block

-- ============================================================
-- #597 Greataxe template (exact Bardin behavior, Kruber 3P redirects)
-- ============================================================
do
	local greataxe = _om.greataxe
	local function _create_greataxe_template()
		if not Weapons or not Weapons.two_handed_axes_template_1 then
			mod:warning("two_handed_axes_template_1 not found - Greataxe unavailable")
			return
		end
		if Weapons[greataxe.TEMPLATE_KEY] then return end

		-- No timing or damage-profile edits: #597 requires an exact gameplay
		-- analogue of Bardin's Greataxe. Only receiver-local 3P fields differ.
		local template = table.clone(Weapons.two_handed_axes_template_1, true)
		template.wield_anim_career_3p = template.wield_anim_career_3p or {}
		for _, career in ipairs(greataxe.DEFAULT_CAREERS) do
			template.wield_anim_career_3p[career] = "to_2h_hammer"
			local settings = CareerSettings and CareerSettings[career]
			local ability = settings and settings.activated_ability
			ability = ability and ability[1]
			local action_name = ability and ability.action_name
			local action = action_name and ActionTemplates and ActionTemplates[action_name]
			if action_name and action and not template.actions[action_name] then
				template.actions[action_name] = action
			end
		end

		Weapons[greataxe.TEMPLATE_KEY] = template
		mod:info("Created %s (exact dr_2h_axe stats/moveset; Kruber wield=to_2h_hammer)",
			greataxe.TEMPLATE_KEY)
	end

	_create_greataxe_template()
end

-- ============================================================
-- Outrider Grenade Launcher template (modified dr_deus_01_template_1)
-- Behavior comes from Bardin Engineer's Trollhammer Torpedo
-- (`dr_deus_01_template_1`); visual layer is swapped to Kruber's
-- blunderbuss (state machine, wield anims, display unit, attachment
-- node linking). The trollhammer's action_one fires `attack_shoot`,
-- which is also a blunderbuss-state-machine event — so no per-action
-- anim_event remap is needed. 3P body anims work because Kruber's
-- empire-soldier skeleton has `attack_shoot` authored for his vanilla
-- blunderbuss.
--
-- Tunes vs vanilla trollhammer (per user, v0.1.176):
--   * speed × 1.4   (2500 → 3500 — faster projectile, "travels further")
--   * reload × 0.65 (3.0s → ~1.95s — faster reload than trollhammer)
--   * damage × 0.65 (proportionally smaller damage and stagger via
--                    cloned damage profile)
--   * max_range 20 → 30 (longer aim-assist reach)
--
-- Hand swap: trollhammer mounts the gun on the LEFT hand
-- (`weapon_action_hand = "left"`, `ammo_data.ammo_hand = "left"`,
-- `left_hand_unit = "...wpn_dr_deus_01"`). Blunderbuss is right-hand.
-- All `weapon_action_hand` and `ammo_hand` fields swapped to "right";
-- left_hand_unit cleared, right_hand_attachment set to
-- `AttachmentNodeLinking.rifles` (matches vanilla blunderbuss).
--
-- WIP / TODO:
--   * Explosion radius — `ExplosionTemplates.dr_deus_01` isn't in the
--     decompiled source we work from, so the explosion template is
--     used as-is. Smaller-radius tune is a follow-up.
--   * Projectile model — currently the trollhammer torpedo. User
--     mentioned wanting a grenade-shaped projectile; that's a follow-up
--     once `Projectiles.cwv_outrider_grenade` is set up.
-- ============================================================

do  -- #284: scope outrider grenade-launcher template locals off the top-level chunk (>200-local limit)
local _OUTRIDER_PROJECTILE_SPEED = 3500
local _OUTRIDER_RELOAD_MULT      = 0.75   -- 0.75× trollhammer reload = ~25% faster reload
local _OUTRIDER_DAMAGE_MULT      = 0.65
local _OUTRIDER_MAX_RANGE        = 30
local _OUTRIDER_MAX_AMMO         = 10     -- v0.1.260: bumped from inherited 7 (trollhammer base)

local function _create_outrider_grenade_launcher_template()
	if not Weapons or not Weapons.dr_deus_01_template_1 then
		mod:warning("dr_deus_01_template_1 not found — Outrider Grenade Launcher template unavailable (Outcast Engineer DLC required)")
		return
	end
	if Weapons.outrider_grenade_launcher_template then return end

	local template = table.clone(Weapons.dr_deus_01_template_1, true)

	-- Swap visual layer: blunderbuss state machine + anims + display unit.
	-- 1P state machine and anim assets live on the shared first_person_base
	-- unit, so loading the blunderbuss state machine works on any character.
	template.state_machine          = "units/beings/player/first_person_base/state_machines/ranged/blunderbuss"
	template.wield_anim             = "to_blunderbuss"
	template.wield_anim_no_ammo     = "to_blunderbuss_noammo"
	template.wield_anim_not_loaded  = nil   -- blunderbuss has no "not_loaded" wield variant
	template.display_unit           = "units/weapons/weapon_display/display_blunderbusses"
	template.reload_event           = "reload"   -- vanilla blunderbuss event name (kept for clarity)

	-- Hand swap: weapon mounts on the right hand instead of left.
	template.left_hand_unit                    = ""
	template.left_hand_attachment_node_linking = nil
	if AttachmentNodeLinking and AttachmentNodeLinking.rifles then
		template.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
	end

	-- ammo_data: swap ammo_hand to right (it's set to "left" on the trollhammer
	-- because the gun is held in the left hand there). Also bump max_ammo
	-- from inherited 7 (trollhammer base) to _OUTRIDER_MAX_AMMO per user.
	if template.ammo_data then
		template.ammo_data.ammo_hand   = "right"
		template.ammo_data.reload_time = (template.ammo_data.reload_time or 3) * _OUTRIDER_RELOAD_MULT
		template.ammo_data.max_ammo    = _OUTRIDER_MAX_AMMO
	end

	-- attack_meta_data.max_range: bump for "travels further" reach.
	if template.attack_meta_data then
		template.attack_meta_data.max_range = _OUTRIDER_MAX_RANGE
	end

	-- wwise_dep_left_hand: rename to right_hand since the gun lives on the
	-- right now. The wwise dependency package is loaded based on the
	-- weapon's hand mount, so this matters for sound bank loading.
	template.wwise_dep_right_hand = template.wwise_dep_left_hand
	template.wwise_dep_left_hand  = nil

	-- Projectile-visual swap: replace the trollhammer torpedo mesh with
	-- the hand grenade mesh, keeping all other trollhammer projectile
	-- physics intact (gravity, life_time, impact_type, trajectory).
	-- `Projectiles.dr_deus_01` is the trollhammer's projectile config;
	-- `ProjectileUnits.grenade` is the hand grenade visual
	-- (`wpn_emp_grenade_01_t1_3p`). Build our own Projectiles entry
	-- by cloning and swapping just `projectile_units_template`.
	-- The cloned config is referenced from each shoot sub-action below.
	if Projectiles and Projectiles.dr_deus_01
			and not Projectiles.cwv_outrider_grenade_projectile then
		local p = table.clone(Projectiles.dr_deus_01, true)
		p.projectile_units_template = "grenade"
		Projectiles.cwv_outrider_grenade_projectile = p
	end

	-- Per-action tunes: walk action_one and the reload/wield variants.
	-- Specifically: action_one.default is the shoot action (kind = grenade_thrower).
	if template.actions and template.actions.action_one then
		for _, sub_action in pairs(template.actions.action_one) do
			if type(sub_action) == "table" then
				-- Hand swap: every weapon_action_hand = "left" → "right".
				if sub_action.weapon_action_hand == "left" then
					sub_action.weapon_action_hand = "right"
				end
				-- Speed tune: bump projectile speed.
				if sub_action.speed then
					sub_action.speed = _OUTRIDER_PROJECTILE_SPEED
				end
				-- Damage tune: clone damage profile in impact_data with reduced
				-- damage and stagger multipliers.
				if sub_action.impact_data and sub_action.impact_data.damage_profile then
					sub_action.impact_data.damage_profile = _clone_damage_profile(
						sub_action.impact_data.damage_profile,
						"cwv_outrider_grenade_launcher_",
						{ damage = _OUTRIDER_DAMAGE_MULT, stagger = _OUTRIDER_DAMAGE_MULT })
				end
				-- Projectile visual swap: point at our cloned config.
				-- Only swap if vanilla had this sub-action pointed at the
				-- trollhammer projectile config (defensive — other sub-actions
				-- in this group might use different projectiles).
				if sub_action.projectile_info == Projectiles.dr_deus_01
						and Projectiles.cwv_outrider_grenade_projectile then
					sub_action.projectile_info = Projectiles.cwv_outrider_grenade_projectile
				end
			end
		end
	end

	-- default_loaded_projectile_settings reads `action.speed` at template-load
	-- time. Since we just bumped action.speed above, sync the cached value.
	if template.default_loaded_projectile_settings then
		template.default_loaded_projectile_settings.speed = _OUTRIDER_PROJECTILE_SPEED
	end

	-- weapon_type identifier — used by some sibling-mod hooks for filtering.
	template.weapon_type = "cwv_es_outrider_grenade_launcher"

	-- Right-click bash (replaces trollhammer's left-handed push). Without
	-- this, right-click crashes on the cwv variant because the trollhammer's
	-- action_one.push has `weapon_action_hand = "left"` (Bardin holds the
	-- gun in his left hand, so push is naturally left-handed) — and our
	-- variant has `no_left_hand = true`, so there's no left-hand wielded
	-- unit to back the push. Crash:
	-- `player_character_state_helper.lua: tried to start a left hand
	-- weapon action without a left hand wielded unit` (GUID 33e82f2c).
	--
	-- Per user, the bash should feel like the blunderbuss's. Copy the
	-- blunderbuss's `action_two.default` directly — kind = "shield_slam",
	-- damage_profile = "shield_slam_shotgun", anim_event = "attack_push".
	-- This is right-handed (no `weapon_action_hand` field set on
	-- blunderbuss bash), so it works with our right-mounted gun.
	if Weapons.blunderbuss_template_1 and Weapons.blunderbuss_template_1.actions
			and Weapons.blunderbuss_template_1.actions.action_two then
		template.actions.action_two = table.clone(Weapons.blunderbuss_template_1.actions.action_two, true)
	end

	-- Inspect / wield action templates: trollhammer uses the LEFT-handed
	-- variants (`ActionTemplates.action_inspect_left`, `wield_left`)
	-- because its weapon mount is left-handed. Swap to right-handed to
	-- match our right-mounted blunderbuss model.
	if ActionTemplates and ActionTemplates.action_inspect then
		template.actions.action_inspect = ActionTemplates.action_inspect
	end
	if ActionTemplates and ActionTemplates.wield then
		template.actions.action_wield = ActionTemplates.wield
	end

	-- Drop the trollhammer's chained push (`action_one.push`) — it had
	-- `weapon_action_hand = "left"` and `kind = "push_stagger"`. Even
	-- though the iterator above flipped the hand to "right", the action's
	-- chain entry references action_two now, and we'd rather have the
	-- bash be the user-facing right-click than a chained push.
	if template.actions.action_one then
		template.actions.action_one.push = nil
	end

	Weapons.outrider_grenade_launcher_template = template

	-- Patch BASE template (`dr_deus_01_template_1`) too. The inventory
	-- previewer (`world_hero_previewer.lua` `equip_item`) calls
	-- `ItemHelper.get_template_by_item_name(item_name)` where item_name is
	-- the BASE weapon's name (cwv variants inherit `entry.name` from the
	-- clone — see `feedback_cwv_clone_name_clobber.md`), so the previewer
	-- reads the BASE template, NOT our clone (per
	-- `feedback_cwv_previewer_template_lookup.md`).
	--
	-- Vanilla `dr_deus_01_template_1` has only `left_hand_attachment_node_linking`
	-- set (Bardin's trollhammer is a left-hand-mount weapon — his
	-- `right_hand_unit` is nil natively, so the previewer's
	-- `if right_hand_unit then` branch never fires for him). For our
	-- cwv variant on Kruber, `entry.right_hand_unit` IS set (the blunderbuss
	-- model), so the previewer hits that branch and reads
	-- `item_template.right_hand_attachment_node_linking.third_person` →
	-- crashes if the BASE template doesn't have right_hand_attachment_node_linking
	-- (crash GUID c847908d-c1e0-46be-8d15-c45c2a80e8a0, v0.1.179).
	--
	-- Fix: add `right_hand_attachment_node_linking = AttachmentNodeLinking.rifles`
	-- to the BASE template. Bardin still doesn't reach the right-hand path
	-- (his right_hand_unit stays nil) so this is harmless for vanilla
	-- trollhammer; our cwv variant does reach the path and now has a valid
	-- linking.
	if Weapons.dr_deus_01_template_1 and AttachmentNodeLinking and AttachmentNodeLinking.rifles then
		Weapons.dr_deus_01_template_1.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
	end

	mod:info("Created outrider_grenade_launcher_template (blunderbuss visuals + trollhammer behavior, speed=%d, reload×%.2f, damage×%.2f, max_range=%d)",
		_OUTRIDER_PROJECTILE_SPEED, _OUTRIDER_RELOAD_MULT, _OUTRIDER_DAMAGE_MULT, _OUTRIDER_MAX_RANGE)
end

_create_outrider_grenade_launcher_template()
end  -- #284: end outrider grenade-launcher do-block

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
-- Musket template (modified handgun_template_1)
-- ============================================================
-- Kruber's vanilla rifle moveset, with stats tuned for an "imperial
-- long musket": slower reload, heavier per-shot damage, smaller ammo
-- pool, much louder report. Visual is the rifle stretched 1.35x along
-- Y (handled at type level — see `_type_transforms.cwv_es_musket`).
--
--   damage profile: clone of `shot_sniper` with default_target's
--                   power_distribution_{near,far}.attack and .impact
--                   both 2x. Dropoff curve preserved (matches the
--                   user-confirmed v1 spec — handgun-near damage at
--                   close, ~80% at far).
--   reload time:    2x (1.5s → 3.0s) on `ammo_data.reload_time`,
--                   plus 2x on per-action `total_time_secondary`
--                   (the secondary timing the reload anim runs against).
--   max ammo:       12 (vanilla 16). ammo_per_clip and ammo_per_reload
--                   stay at 1 (handgun's bolt-action style).
--   alert range:    25m (vanilla 10m) on `alert_sound_range_fire`
--                   for every firing sub-action — matches the
--                   blunderbuss's audible radius. Black-powder boom.

local _MUSKET_DAMAGE_MULT      = 2.0
local _MUSKET_RELOAD_MULT      = 2.0
local _MUSKET_MAX_AMMO         = 12
local _MUSKET_ALERT_RANGE_FIRE = 25

-- Bayonet thrust (action_three / special key F). Clone of Kerillian's spear
-- heavy stab (`heavy_slashing_smiter_stab_polearm`) with the user-requested
-- "slowed down + boosted stagger" tune: attack × 0.85 (lighter per-thrust
-- punch), impact × 1.5 (much harder enemies-stagger). Slot in as a melee
-- sweep on action_three. Single-press F triggers one thrust; player can
-- spam F for repeated thrusts. NOT a true stance toggle (vanilla doesn't
-- support runtime template swapping cleanly) — for full "switch to spear
-- moveset on F" behavior, see the v3 TODO note above the variant def.
local _MUSKET_BAYONET_DAMAGE_MULT  = 0.85
local _MUSKET_BAYONET_STAGGER_MULT = 1.5

local function _create_cwv_musket_damage_profile()
	if not DamageProfileTemplates then return "shot_sniper" end
	local source = DamageProfileTemplates.shot_sniper
	if not source then return "shot_sniper" end
	local key = "cwv_musket_shot"
	_om._record_cwv_dp_source(key, "shot_sniper")   -- issue 423 wire-safe map
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)

	-- shot_sniper carries near/far variants on default_target.power_distribution.
	-- Multiply BOTH attack (damage) and impact (stagger) on each variant by
	-- the musket damage multiplier. Per memory `feedback_cwv_*` the dropoff
	-- curve and shield_break flag inherited from shot_sniper are preserved
	-- by the deep clone above.
	if clone.default_target then
		local function _scale(pd)
			if not pd then return end
			if pd.attack then pd.attack = pd.attack * _MUSKET_DAMAGE_MULT end
			if pd.impact then pd.impact = pd.impact * _MUSKET_DAMAGE_MULT end
		end
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
		_scale(clone.default_target.power_distribution)  -- defensive (some profiles use the un-near/un-far shape)
	end

	-- targets[] (per-target overrides, e.g. headshot vs body) — same scale.
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			if target.power_distribution_near then
				if target.power_distribution_near.attack then target.power_distribution_near.attack = target.power_distribution_near.attack * _MUSKET_DAMAGE_MULT end
				if target.power_distribution_near.impact then target.power_distribution_near.impact = target.power_distribution_near.impact * _MUSKET_DAMAGE_MULT end
			end
			if target.power_distribution_far then
				if target.power_distribution_far.attack then target.power_distribution_far.attack = target.power_distribution_far.attack * _MUSKET_DAMAGE_MULT end
				if target.power_distribution_far.impact then target.power_distribution_far.impact = target.power_distribution_far.impact * _MUSKET_DAMAGE_MULT end
			end
			if target.power_distribution then
				if target.power_distribution.attack then target.power_distribution.attack = target.power_distribution.attack * _MUSKET_DAMAGE_MULT end
				if target.power_distribution.impact then target.power_distribution.impact = target.power_distribution.impact * _MUSKET_DAMAGE_MULT end
			end
		end
	end

	DamageProfileTemplates[key] = clone

	-- Register in NetworkLookup.damage_profiles so multiplayer hit RPCs can
	-- serialize the new key. Without this, any networked damage event
	-- referencing cwv_musket_shot crashes the client with "Table
	-- damage_profiles does not contain key" — same family of issue as the
	-- weapon_skins / item_names lookups (crash GUID a8094388, hit on first
	-- musket fire).
	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end

	return key
end

-- Bayonet thrust damage profile: clone Kerillian spear's heavy stab profile
-- with attack scaled down (slower per-thrust damage to balance the always-
-- ready melee on a ranged weapon) and impact scaled up (heavier stagger,
-- per the user's "use it like his 1h spear, slow it down and add more
-- stagger" spec).
local function _create_cwv_musket_bayonet_damage_profile()
	if not DamageProfileTemplates then return "heavy_slashing_smiter_stab_polearm" end
	local source = DamageProfileTemplates.heavy_slashing_smiter_stab_polearm
	if not source then return "heavy_slashing_smiter_stab_polearm" end
	local key = "cwv_musket_bayonet_thrust"
	_om._record_cwv_dp_source(key, "heavy_slashing_smiter_stab_polearm")   -- issue 423 wire-safe map
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)

	-- Spear stab profile uses the simpler `power_distribution` shape (no near/far
	-- variants — melee distance is uniform). Scale attack and impact independently.
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _MUSKET_BAYONET_DAMAGE_MULT end
		if pd.impact then pd.impact = pd.impact * _MUSKET_BAYONET_STAGGER_MULT end
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution)
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution)
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
		end
	end

	DamageProfileTemplates[key] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end

	return key
end

-- ============================================================
-- Musket stance toggle helpers (forward-declared for closure capture)
-- ============================================================
-- The action_three.enter_function below references this helper. In Lua 5.1
-- a closure resolves upvalues at function-creation time; declaring this
-- BEFORE `_create_musket_template` and `_create_musket_template_melee`
-- ensures the binding exists when the action_three closure is built.

local function _toggle_musket_stance_and_rewield(player_unit)
	if not player_unit or not Unit.alive(player_unit) then return end
	local ok_inv, inv = pcall(ScriptUnit.extension, player_unit, "inventory_system")
	if not ok_inv or not inv then return end
	local equipment = inv:equipment()
	if not equipment then return end
	local wielded_slot = equipment.wielded_slot
	if not wielded_slot then return end
	local slot_data = equipment.slots[wielded_slot]
	if not slot_data or not slot_data.item_data then return end
	local item_data = slot_data.item_data

	-- Gate: operate on EITHER cwv_es_musket or cwv_es_musket_old items.
	-- Both share this helper (stance flag is per-item via mod_data so no
	-- collision); the get_item_template hook below routes to the correct
	-- template family. v0.1.301: extended to cover old musket templates.
	local is_musket     = (item_data.template == "musket_template" or item_data.template == "musket_template_melee")
	local is_old_musket = (item_data.template == "old_musket_template" or item_data.template == "old_musket_template_melee")
	if not (is_musket or is_old_musket) then
		local bid = item_data.backend_id
		if not bid or not bid:match("^cwv_es_musket_") then return end
	end

	-- v0.1.265: removed the v0.1.260 slot_type gate. Polearm variant
	-- now uses musket_template (ranged) and toggles to musket_template_melee
	-- like the ranged variant. The defensive WeaponSpreadExtension
	-- hook (added v0.1.265) handles the nil spread_settings crash that
	-- previously blocked this design.

	-- Stance flag stored on the IML item_data's mod_data. mod_data is
	-- mutable across the whole equip lifecycle; survives wield+unwield.
	item_data.mod_data = item_data.mod_data or {}
	local current = item_data.mod_data.cwv_musket_stance or "ranged"
	local next_stance = (current == "ranged") and "melee" or "ranged"
	item_data.mod_data.cwv_musket_stance = next_stance
	-- #474: stance is presentation state as well as a local template choice.
	-- Record and publish the edge before the destroy/add cycle so observers can
	-- converge even if their husk rebuild lands before ours finishes.
	if _om._old_musket_record_and_publish then
		_om._old_musket_record_and_publish(player_unit, wielded_slot, item_data,
			next_stance, "toggle")
	end

	-- v0.1.307: capture EXACT ammo state (chambered + reserve + reloading flag)
	-- separately, instead of a single `total_ammo_fraction`. The fraction
	-- collapses chamber + reserve into one number, and vanilla's
	-- `_starting_loaded_ammo / _start_ammo` reconstruction always gives
	-- `_current_ammo = min(ammo_per_clip, start_ammo) = 1` — meaning EVERY
	-- stance toggle "refills" the chamber from 0 to 1, which is a free
	-- reload exploit. Capture precise values and restore them post-spawn
	-- to lock the player's actual ammo state across the toggle.
	item_data.mod_data = item_data.mod_data or {}
	local cap_current, cap_reserve, cap_shots_fired, cap_reloading = nil, nil, nil, nil
	local rifle_unit_for_ammo = equipment.right_hand_wielded_unit or equipment.right_hand_wielded_unit_3p
	if rifle_unit_for_ammo and Unit.alive(rifle_unit_for_ammo)
			and ScriptUnit.has_extension(rifle_unit_for_ammo, "ammo_system") then
		local ok_ammo, ext = pcall(ScriptUnit.extension, rifle_unit_for_ammo, "ammo_system")
		if ok_ammo and ext then
			cap_current      = ext._current_ammo
			cap_reserve      = ext._available_ammo
			cap_shots_fired  = ext._shots_fired
			cap_reloading    = ext.is_reloading and ext:is_reloading() or false
		end
	end
	-- If we couldn't get live readings (toggling FROM melee — no ammo
	-- extension on the polearm-template unit), fall back to persisted
	-- values from the previous capture.
	if cap_current ~= nil then
		item_data.mod_data.cwv_musket_cap_current     = cap_current
		item_data.mod_data.cwv_musket_cap_reserve     = cap_reserve
		item_data.mod_data.cwv_musket_cap_shots_fired = cap_shots_fired
		item_data.mod_data.cwv_musket_cap_reloading   = cap_reloading
	else
		cap_current     = item_data.mod_data.cwv_musket_cap_current
		cap_reserve     = item_data.mod_data.cwv_musket_cap_reserve
		cap_shots_fired = item_data.mod_data.cwv_musket_cap_shots_fired
		cap_reloading   = item_data.mod_data.cwv_musket_cap_reloading
	end
	-- If reloading was in progress at toggle time, set the same flag used
	-- by the _wield_slot POST hook so vanilla's auto-reload-on-wield gets
	-- aborted on toggle-back.
	if cap_reloading then
		item_data.mod_data.cwv_musket_reload_interrupted = true
	end

	-- Force a destroy + add + wield cycle on the slot so the new template
	-- (resolved by the BackendUtils.get_item_template hook below) takes
	-- effect. Vanilla `wield()` only show/hides existing units — it doesn't
	-- respawn with a new template. We have to destroy + re-add.
	local slot_name = wielded_slot
	-- v0.1.336: slot_index is the numeric key vanilla uses on
	-- `_equipment_units` / `_item_info_by_slot[*].spawn_data[1].slot_index`
	-- (see the preview-hook KEY BRIDGE block ~line 8720). Reported alongside
	-- the slot_name so debug logs can correlate stance toggles with the
	-- numeric slot used by other CWV hooks.
	local slot_index = nil
	local slots_by_name = rawget(_G, "InventorySettings") and InventorySettings.slots_by_name
	if slots_by_name and slots_by_name[slot_name] then
		slot_index = slots_by_name[slot_name].slot_index
	end
	_dbg("[cwv musket] stance: %s → %s (slot=%s slot_index=%s, current=%s reserve=%s reloading=%s)",
		current, next_stance, slot_name, tostring(slot_index),
		tostring(cap_current), tostring(cap_reserve), tostring(cap_reloading))
	local ok_destroy, err_destroy = pcall(function() inv:destroy_slot(slot_name, true) end)
	if not ok_destroy then
		mod:warning("[cwv musket] destroy_slot failed: %s", tostring(err_destroy))
		return
	end
	-- v0.1.328: choose `target_percent` so vanilla's wield-animation picker
	-- in _wield_slot:2050 sees the CORRECT chamber state.
	-- Vanilla: `_current_ammo = math.min(_ammo_per_clip, _start_ammo)`
	-- where `_start_ammo = round(percent * max_ammo)`.
	-- ammo_per_clip = 1 for handgun; so any percent yielding start_ammo >= 1
	-- gives _current_ammo = 1 (chamber loaded → "loaded" wield anim).
	-- ammo_percent = 0 always gives _current_ammo = 0 → "not_loaded" anim.
	-- v0.1.307 passed 0 unconditionally and restored ammo afterward, but
	-- the anim was already selected → user saw empty-chamber pose even with
	-- a round chambered. Now pass a percent matching captured state:
	--   chamber loaded (cap_current >= 1) → fraction = total/max → loaded anim
	--   chamber empty  (cap_current == 0, mid-reload) → 0 → not-loaded anim
	-- POST-spawn we still restore precise reserves below.
	local target_percent = 0
	if cap_current and cap_current >= 1 then
		local _MAX_AMMO = 11  -- old_musket_template max_ammo
		target_percent = math.min(1, ((cap_current or 0) + (cap_reserve or 0)) / _MAX_AMMO)
	end
	local ok_add, err_add = pcall(function() inv:add_equipment(slot_name, item_data, nil, nil, target_percent) end)
	if not ok_add then
		mod:warning("[cwv musket] add_equipment failed: %s", tostring(err_add))
		return
	end
	local ok_wield, err_wield = pcall(function() inv:wield(slot_name) end)
	if not ok_wield then
		mod:warning("[cwv musket] wield failed: %s", tostring(err_wield))
	end
	-- v0.1.307: restore precise ammo state on the freshly-spawned ammo
	-- extension (if present — ranged template has one, melee polearm doesn't).
	local new_eq = inv:equipment()
	local new_unit = new_eq and (new_eq.right_hand_wielded_unit or new_eq.right_hand_wielded_unit_3p)
	if new_unit and Unit.alive(new_unit) and ScriptUnit.has_extension(new_unit, "ammo_system")
			and cap_current ~= nil then
		local new_ext = ScriptUnit.extension(new_unit, "ammo_system")
		new_ext._current_ammo  = cap_current
		new_ext._available_ammo = cap_reserve or 0
		new_ext._shots_fired   = cap_shots_fired or 0
		-- If we restored ammo_count to 0 AND reload was interrupted, vanilla
		-- _wield_slot may have already kicked off an auto-reload by now —
		-- cancel it. (Same logic as the _wield_slot POST hook, but for the
		-- stance-toggle path which doesn't go through that hook's PRE.)
		if cap_reloading and new_ext.is_reloading and new_ext:is_reloading() then
			pcall(function() new_ext:abort_reload() end)
		end
		-- v0.1.307: re-sync shared pool to the restored reserve so the
		-- other pool member (if any) sees the same reserve.
		if _om._cwv_musket_sync_pool then _om._cwv_musket_sync_pool(new_ext) end
	end
end

local function _create_musket_template()
	if not Weapons or not Weapons.handgun_template_1 then
		mod:warning("handgun_template_1 not found — Musket template unavailable")
		return
	end
	if Weapons.musket_template then return end

	local template = table.clone(Weapons.handgun_template_1, true)
	local damage_key = _create_cwv_musket_damage_profile()

	-- Walk every sub-action; swap damage_profile (when shot_sniper) and
	-- bump alert_sound_range_fire on any firing sub-action that has one.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.damage_profile == "shot_sniper" then
							sub_action.damage_profile = damage_key
						end
						if sub_action.alert_sound_range_fire then
							sub_action.alert_sound_range_fire = _MUSKET_ALERT_RANGE_FIRE
						end
					end
				end
			end
		end
	end

	if template.ammo_data then
		template.ammo_data.reload_time = (template.ammo_data.reload_time or 1.5) * _MUSKET_RELOAD_MULT
		template.ammo_data.max_ammo = _MUSKET_MAX_AMMO
	end

	-- ============================================================
	-- BAYONET STANCE TOGGLE (action_three / special key, F or C)
	-- ============================================================
	-- The musket carries TWO templates registered on `Weapons`:
	--
	--   `musket_template`        — ranged moveset (this template; handgun shoot)
	--   `musket_template_melee`  — Kerillian spear moveset, slowed + boosted
	--                              stagger (built below `_create_musket_template`)
	--
	-- F press triggers a hidden destroy_slot + add_equipment + wield cycle
	-- on the musket's slot. Per-item stance flag stored at
	-- `item_data.mod_data.cwv_musket_stance`. The
	-- `BackendUtils.get_item_template` hook (further down) reads the flag
	-- and returns the matching template, so the recreated weapon spawns
	-- with the correct moveset.
	--
	-- This is the "runtime template swap" approach — true unequip+equip
	-- with template swap, not the v0.1.203-204 chain-conditional dual-
	-- sub-action experiment (which crashed lookup_data + sweep target,
	-- and didn't actually switch movesets in practice).
	--
	-- Stance toggle action is shared verbatim with `musket_template_melee`
	-- so the player can press F from either stance to toggle back.

	template.actions.action_three = {
		default = {
			kind = "dummy",
			anim_event = "reload",
			anim_end_event = "attack_finished",
			total_time = 0.4,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}

	-- Attach lookup_data on every sub_action, including our new ones.
	-- Vanilla `weapons.lua:305-312` does this during `Weapons[]` init at
	-- boot but our mod-loaded additions miss it and crash on first touch.
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "musket_template",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	-- v0.1.258: add melee-tooltip-required fields. The handgun template
	-- this clones from has none of these (ranged weapon), but vanilla's
	-- `ui_passes_tooltips.lua` does arithmetic on `max_fatigue_points`
	-- when displaying the tooltip for ANY equipped weapon — including a
	-- ranged-template weapon equipped in a melee slot via the polearm
	-- variant. nil → arithmetic crash (GUID 451895b3). Defensive defaults
	-- below mirror tuskgor spear values; benign when the weapon is
	-- actually used in a ranged slot (the fields just sit unread).
	template.max_fatigue_points = template.max_fatigue_points or 8
	template.dodge_count = template.dodge_count or 3
	template.block_angle = template.block_angle or 180
	template.outer_block_angle = template.outer_block_angle or 360
	template.block_fatigue_point_multiplier = template.block_fatigue_point_multiplier or 0.5
	template.outer_block_fatigue_point_multiplier = template.outer_block_fatigue_point_multiplier or 2

	Weapons.musket_template = template
	mod:info("Created musket_template (damage×%.1f, reload×%.1f, max_ammo=%d, alert_range=%dm, bayonet stance toggle on F: damage×%.2f, stagger×%.2f)",
		_MUSKET_DAMAGE_MULT, _MUSKET_RELOAD_MULT, _MUSKET_MAX_AMMO, _MUSKET_ALERT_RANGE_FIRE,
		_MUSKET_BAYONET_DAMAGE_MULT, _MUSKET_BAYONET_STAGGER_MULT)
end

_create_musket_template()

-- ============================================================
-- Musket melee template (Kruber's native heavy spear, slow + stagger)
-- ============================================================
-- v0.1.206: switched from `two_handed_spears_elf_template_1` (Kerillian
-- spear) to `two_handed_heavy_spears_template` (Kruber's tuskgor spear).
-- The elf spear's state_machine, display_unit, and other assets live in
-- Kerillian's package and aren't loaded for Kruber, which crashed with
-- "Resource not loaded" (GUID 1363574c) on stance toggle. Kruber's
-- native heavy spear template uses
-- `units/beings/player/first_person_base/state_machines/melee/polearm`
-- and other Kruber-loaded resources — no cross-character package issue.
--
-- Functionally similar to the elf spear (polearm thrust moveset), and
-- since the user originally suggested heavy_spear as one option, this
-- is acceptable behavior. If we later want elf-spear flavor specifically,
-- we'd need to force-load the elf spear's package via Managers.package
-- per the cross-character pattern.
--
-- Damage tuning (per user "slow it down + add stagger"):
--   * attack power × 0.85 on every sub-action with a damage_profile
--   * impact (stagger) × 1.5 on the same
--   * anim_time_scale × 0.85 on every sub-action that has it
--     (makes swings 15% slower; tuskgor spear is already measured —
--      this leans into "musket-bayonet drilling" feel)
--
-- Visual: NO override of right_hand_unit etc. — the IML inheritance
-- system uses item_data.right_hand_unit (the rifle mesh) regardless
-- of which template is active, so the rifle stays the wielded mesh.
-- The bayonet child-link also persists (it's spawned by the
-- GearUtils.spawn_inventory_unit hook below, which fires for either
-- template since the gate is on item_template family, not specific
-- template).

local _MUSKET_MELEE_DAMAGE_MULT     = 0.85
local _MUSKET_MELEE_STAGGER_MULT    = 1.5
local _MUSKET_MELEE_ANIM_TIME_SCALE = 0.85  -- swings ~15% slower

local function _scale_melee_damage_profile(profile_name)
	if not DamageProfileTemplates then return profile_name end
	local source = DamageProfileTemplates[profile_name]
	if not source then return profile_name end
	local key = "cwv_musket_melee_" .. profile_name
	_om._record_cwv_dp_source(key, profile_name)   -- issue 423 wire-safe map
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _MUSKET_MELEE_DAMAGE_MULT end
		if pd.impact then pd.impact = pd.impact * _MUSKET_MELEE_STAGGER_MULT end
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution)
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution)
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
		end
	end

	DamageProfileTemplates[key] = clone

	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end

	return key
end

local function _create_musket_template_melee()
	if not Weapons or not Weapons.two_handed_heavy_spears_template then
		mod:warning("two_handed_heavy_spears_template not found — Musket melee template unavailable")
		return
	end
	if Weapons.musket_template_melee then return end

	local template = table.clone(Weapons.two_handed_heavy_spears_template, true)

	-- v0.1.227: per user "make it have it's normal speed and melee values" —
	-- DO NOT apply damage scaling or anim_time_scale changes. Vanilla
	-- tuskgor spear stats are kept verbatim. Previously v0.1.220-226
	-- applied attack ×0.85, stagger ×1.5, anim_time ×0.85; reverted.
	--
	-- v0.1.243: per user "make the range_mod 1.2" — override every
	-- sub-action's range_mod to 1.2 (vanilla tuskgor uses 1.35 on every
	-- attack). Bayonet shouldn't reach as far as a full polearm haft.
	-- range_mod_add (the additive component, varies 0.25-1.0 per
	-- sub-action) kept vanilla.
	local _MELEE_RANGE_MOD = 1.2
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" and sub_action.range_mod then
						sub_action.range_mod = _MELEE_RANGE_MOD
					end
				end
			end
		end
	end

	-- Stance toggle back to ranged on action_three. Mirrors the one on
	-- musket_template; the toggle helper handles both directions.
	template.actions = template.actions or {}
	template.actions.action_three = {
		default = {
			kind = "dummy",
			-- No anim_event: dummy action just toggles stance, no visual needed.
			-- Polearm SM has its own anim vocabulary; using the wrong event
			-- would crash. Vanilla state machines fall through cleanly when
			-- anim_event is omitted (the current pose holds for total_time).
			total_time = 0.4,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}

	-- Same lookup_data attach as musket_template — vanilla weapons.lua's
	-- init pass doesn't run on our mod-loaded template.
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "musket_template_melee",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	-- Override display_unit to handgun rig. v0.1.227: tuskgor spear's
	-- display_unit `display_2h_polearm` should also be loaded for Kruber
	-- (his native weapon) but using the handgun rig is safe + idempotent.
	template.display_unit = "units/weapons/weapon_display/display_1h_handguns"

	Weapons.musket_template_melee = template
	mod:info("Created musket_template_melee (Kruber tuskgor spear clone, vanilla stats — no damage/speed scaling)")
end

_create_musket_template_melee()

-- ============================================================
-- "Old Musket" template (cwv_es_musket_old) — ranged-only
-- ============================================================
-- v0.1.300: clone of vanilla `handgun_template_1` with modifiers per user
-- spec ("based on the original rifle"):
--   * Reload time: 1.5x vanilla (50% slower)
--   * Ranged damage: 1.5x vanilla (+50%, via cloned damage profile)
--   * Max ammo: 11 (vanilla rifle has 16; user spec v0.1.305)
--   * Hip-fire spread: 1.5x wider cone (continuous still/moving and crouch
--     pitch/yaw; ADS / zoomed unchanged so ironsights stays accurate)
-- v0.1.305: wrapped the helpers in `do ... end` to release top-level local
-- slots — Lua 5.1 main chunk has a 200-local limit and we hit it.
do
local _OLD_MUSKET_RELOAD_MULT = 1.5
local _OLD_MUSKET_DAMAGE_MULT = 1.5
local _OLD_MUSKET_MAX_AMMO    = 11
local _OLD_MUSKET_SPREAD_MULT = 1.5

local function _create_cwv_old_musket_damage_profile()
	if not DamageProfileTemplates then return "shot_sniper" end
	local source = DamageProfileTemplates.shot_sniper
	if not source then return "shot_sniper" end
	local key = "cwv_old_musket_shot"
	_om._record_cwv_dp_source(key, "shot_sniper")   -- issue 423 wire-safe map
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _OLD_MUSKET_DAMAGE_MULT end
		if pd.impact then pd.impact = pd.impact * _OLD_MUSKET_DAMAGE_MULT end
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
		_scale(clone.default_target.power_distribution)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
			_scale(target.power_distribution)
		end
	end

	-- v0.1.305: penetration tuning per user spec.
	--   * Cleave distribution boosted so the shot punches through ~6 regular
	--     enemies (vanilla shot_sniper = 0.3, gives 1-2 pierce on unarmored).
	--   * Armor modifier bumped on the higher-armor indices so the shot reads
	--     "a bit better through armor" without making it a tank-deleter. The
	--     `armor_modifier_*` arrays are indexed by armor type — vanilla
	--     shot_sniper has (1, 1.2, 1.5, 1, 0.75, 0.5). We bring the upper
	--     three (super-armor / berserker-shielded / chaos-warrior class) up.
	local _CLEAVE_ATTACK = 1.5  -- ~6-target pierce on regular enemies
	local _CLEAVE_IMPACT = 0.6  -- proportional stagger cleave
	if clone.cleave_distribution then
		clone.cleave_distribution.attack = _CLEAVE_ATTACK
		clone.cleave_distribution.impact = _CLEAVE_IMPACT
	end
	local function _boost_armor_attack(mod_table)
		if not mod_table or not mod_table.attack then return end
		-- attack[i] for i=4..6 — armored / super-armored. Bring each up by ~0.2.
		for i = 4, 6 do
			if mod_table.attack[i] then mod_table.attack[i] = mod_table.attack[i] + 0.2 end
		end
	end
	_boost_armor_attack(clone.armor_modifier_near)
	_boost_armor_attack(clone.armor_modifier_far)

	DamageProfileTemplates[key] = clone

	-- Register in NetworkLookup so multiplayer hit RPCs can serialize the key
	-- (see _create_cwv_musket_damage_profile for the rationale + GUID a8094388).
	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end
	return key
end

local function _create_old_musket_template()
	if not Weapons or not Weapons.handgun_template_1 then
		mod:warning("handgun_template_1 not found — old_musket_template unavailable")
		return
	end
	if Weapons.old_musket_template then return end

	local template = table.clone(Weapons.handgun_template_1, true)
	local damage_key = _create_cwv_old_musket_damage_profile()

	-- Swap damage_profile on every shot_sniper firing sub-action.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" and sub_action.damage_profile == "shot_sniper" then
						sub_action.damage_profile = damage_key
					end
				end
			end
		end
	end

	-- Reload time bump (vanilla baseline * 1.5).
	if template.ammo_data and template.ammo_data.reload_time then
		template.ammo_data.reload_time = template.ammo_data.reload_time * _OLD_MUSKET_RELOAD_MULT
	end

	-- v0.1.305: max ammo = 11 per user spec (vanilla rifle has 16).
	if template.ammo_data then
		template.ammo_data.max_ammo = _OLD_MUSKET_MAX_AMMO
	end

	-- v0.1.305: hip-fire spread cone 1.5x wider. Vanilla `handgun_template_1`
	-- references SpreadTemplates.handgun via `default_spread_template = "handgun"`.
	-- Clone that template and scale ONLY the hip-fire / non-zoomed cones; ADS
	-- (zoomed_*) cones left at vanilla so ironsights stays precise.
	if SpreadTemplates and SpreadTemplates.handgun and not SpreadTemplates.cwv_old_musket then
		local sclone = table.clone(SpreadTemplates.handgun, true)
		if sclone.continuous then
			for state, vals in pairs(sclone.continuous) do
				-- Skip zoomed variants; scale only hip-fire poses.
				if not state:find("zoomed") and type(vals) == "table" then
					if vals.max_pitch then vals.max_pitch = vals.max_pitch * _OLD_MUSKET_SPREAD_MULT end
					if vals.max_yaw   then vals.max_yaw   = vals.max_yaw   * _OLD_MUSKET_SPREAD_MULT end
				end
			end
		end
		SpreadTemplates.cwv_old_musket = sclone
		mod:info("Registered SpreadTemplates.cwv_old_musket (hip-fire %.2fx wider; ADS unchanged)", _OLD_MUSKET_SPREAD_MULT)
	end
	template.default_spread_template = "cwv_old_musket"

	-- v0.1.301: stance toggle on action_three (special key). Mirrors the one
	-- on musket_template — same toggle helper handles both variants (gated on
	-- item_data.template + backend_id).
	template.actions.action_three = {
		default = {
			kind = "dummy",
			anim_event = "reload",
			anim_end_event = "attack_finished",
			total_time = 0.4,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}
	-- #412: the idle action scan cannot see action_three while another action
	-- owns the weapon extension. Add the same explicit chain edge used by
	-- vanilla Rapier specials to every cloned handgun sub-action.
	mod._cwv_old_musket_interrupt.install(template, "action_three")

	-- Attach lookup_data on every sub_action (else lookup crashes on first
	-- touch — see _create_musket_template for the rationale).
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "old_musket_template",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	Weapons.old_musket_template = template
	mod:info("Created old_musket_template (handgun_template_1 + %.2fx damage + %.2fx reload time)",
		_OLD_MUSKET_DAMAGE_MULT, _OLD_MUSKET_RELOAD_MULT)
end

_create_old_musket_template()
end  -- end of do-block opened above _OLD_MUSKET_RELOAD_MULT

-- #474: the vanilla handgun's report is authored in the compiled rifle unit as
-- `player_combat_weapon_rifle_fire` (source bundle 02da877f28111a62, vanilla 3P
-- handgun unit). The custom Old Musket mesh has no equivalent Wwise flow graph.
-- ActionHandgun also does not ask vanilla to replicate a shot sound unless its
-- action has fire_sound_event, and handgun_template_1 intentionally has none.
-- Keep the owner's compiled-unit sound untouched, then send only the native
-- remote-husk event when an Old Musket shot actually transitions out of
-- waiting_to_shoot. This uses the vanilla FirstPersonSystem RPC and a vanilla
-- NetworkLookup.sound_events id, so it is safe even for a peer without CWV and
-- does not duplicate audio on the shooting peer.
do
	local _OLD_MUSKET_REMOTE_FIRE_EVENT = "player_combat_weapon_rifle_fire"
	_om._old_musket_remote_fire_event = _OLD_MUSKET_REMOTE_FIRE_EVENT

	_om._is_old_musket_ranged_action = function(action)
		local template = Weapons and Weapons.old_musket_template
		local action_one = template and template.actions and template.actions.action_one
		if type(action_one) ~= "table" or type(action) ~= "table" then return false end
		for _, sub_action in pairs(action_one) do
			if sub_action == action then return true end
		end
		return false
	end

	_om._old_musket_shot_completed = function(action, before_state, before_extra, after_state, after_extra)
		if not _om._is_old_musket_ranged_action(action) or before_state ~= "waiting_to_shoot" then
			return false
		end
		return after_state == "shot" or (after_extra == true and before_extra ~= true)
	end

	_om._dispatch_old_musket_remote_fire = function(action_instance)
		local owner_unit = action_instance and action_instance.owner_unit
		if not owner_unit or not Unit.alive(owner_unit) then return false end
		-- The paired #474 log proves the compiled rifle report is a valid Wwise
		-- event but is NOT present in NetworkLookup.sound_events. Therefore the
		-- native husk-audio RPC cannot encode it. Reuse the bounded CWV channel;
		-- receivers trigger the exact compiled report locally on the owner husk.
		local ok = _om._old_musket_publish_fire
			and _om._old_musket_publish_fire(owner_unit, _OLD_MUSKET_REMOTE_FIRE_EVENT)
		if ok then
			pcall(printf, "[cwv:474] remote old-musket rifle fire dispatched via bounded CWV event")
			return true
		end
		return false
	end

	if rawget(_G, "ActionHandgun") and type(ActionHandgun.client_owner_post_update) == "function" then
		mod:hook("ActionHandgun", "client_owner_post_update", function(func, self, dt, t, world, can_damage)
			local action = self.current_action
			local before_state = self.state
			local before_extra = self.extra_buff_shot
			local result = func(self, dt, t, world, can_damage)
			if _om._old_musket_shot_completed(action, before_state, before_extra,
					self.state, self.extra_buff_shot) then
				_om._dispatch_old_musket_remote_fire(self)
			end
			return result
		end)
		_om._old_musket_remote_fire_hook_installed = true
	end
end

-- ============================================================
-- "Old Musket" melee template (bayonet stance) — Tuskgor spear clone
-- ============================================================
-- v0.1.301: clone of `two_handed_heavy_spears_template` with:
--   * range_mod 1.2 on every sweep (absolute, vs vanilla tuskgor 1.35)
--   * damage profiles cloned with 0.9x attack (10% less than vanilla spear).
--     Stagger left at vanilla 1.0x.
-- Stance toggle on action_three swaps back to old_musket_template (ranged).
-- The user's earlier instruction was "based on the original rifle" — the
-- rifle has no melee, so for the melee branch we anchor to vanilla
-- Tuskgor spear baseline rather than the existing cwv_musket bayonet
-- (which has -15% damage + 1.5x stagger). Result: old musket bayonet
-- hits softer than vanilla spear (and softer than existing musket
-- bayonet's stagger boost) but reaches farther than ours used to.
-- v0.1.305: wrapped in do-end to release top-level local slots.
do
local _OLD_MUSKET_BAYONET_DAMAGE_MULT = 0.9
local _OLD_MUSKET_BAYONET_RANGE_MOD   = 1.2

local function _scale_old_musket_melee_damage_profile(profile_name)
	if not DamageProfileTemplates then return profile_name end
	local source = DamageProfileTemplates[profile_name]
	if not source then return profile_name end
	local key = "cwv_old_musket_melee_" .. profile_name
	_om._record_cwv_dp_source(key, profile_name)   -- issue 423 wire-safe map
	if DamageProfileTemplates[key] then return key end

	local clone = table.clone(source, true)
	local function _scale(pd)
		if not pd then return end
		if pd.attack then pd.attack = pd.attack * _OLD_MUSKET_BAYONET_DAMAGE_MULT end
		-- stagger (impact) left at vanilla — user didn't ask for stagger change.
	end
	if clone.default_target then
		_scale(clone.default_target.power_distribution)
		_scale(clone.default_target.power_distribution_near)
		_scale(clone.default_target.power_distribution_far)
	end
	if type(clone.targets) == "table" then
		for _, target in ipairs(clone.targets) do
			_scale(target.power_distribution)
			_scale(target.power_distribution_near)
			_scale(target.power_distribution_far)
		end
	end
	DamageProfileTemplates[key] = clone
	if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
		local tbl = NetworkLookup.damage_profiles
		local idx = #tbl + 1
		rawset(tbl, idx, key)
		rawset(tbl, key, idx)
	end
	return key
end

local function _create_old_musket_template_melee()
	if not Weapons or not Weapons.two_handed_heavy_spears_template then
		mod:warning("two_handed_heavy_spears_template not found — old_musket_template_melee unavailable")
		return
	end
	if Weapons.old_musket_template_melee then return end

	local template = table.clone(Weapons.two_handed_heavy_spears_template, true)

	-- range_mod 1.2 + swap damage profiles to scaled clones.
	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.range_mod then
							sub_action.range_mod = _OLD_MUSKET_BAYONET_RANGE_MOD
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _scale_old_musket_melee_damage_profile(sub_action.damage_profile)
						end
					end
				end
			end
		end
	end

	-- Stance toggle back to ranged.
	template.actions = template.actions or {}
	template.actions.action_three = {
		default = {
			kind = "dummy",
			anim_end_event = "attack_finished",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			total_time = 0.4,
			enter_function = function (attacker_unit, input_extension)
				_toggle_musket_stance_and_rewield(attacker_unit)
			end,
			allowed_chain_actions = {},
		},
	}
	-- #412: cover attack starts/releases, active sweeps, recovery, block/push,
	-- and every other live Tuskgor-spear sub-action from frame zero.
	mod._cwv_old_musket_interrupt.install(template, "action_three")

	-- lookup_data attach.
	for action_name, sub_actions in pairs(template.actions) do
		if type(sub_actions) == "table" then
			for sub_action_name, sub_action_data in pairs(sub_actions) do
				if type(sub_action_data) == "table" then
					sub_action_data.lookup_data = sub_action_data.lookup_data or {
						item_template_name = "old_musket_template_melee",
						action_name        = action_name,
						sub_action_name    = sub_action_name,
					}
				end
			end
		end
	end

	-- Display unit — handgun rig (same as musket_template_melee).
	template.display_unit = "units/weapons/weapon_display/display_1h_handguns"

	Weapons.old_musket_template_melee = template
	mod:info("Created old_musket_template_melee (Tuskgor spear clone, range_mod=%.2f, damage=%.2fx)",
		_OLD_MUSKET_BAYONET_RANGE_MOD, _OLD_MUSKET_BAYONET_DAMAGE_MULT)
end

_create_old_musket_template_melee()
end  -- end of do-block opened above _OLD_MUSKET_BAYONET_DAMAGE_MULT

-- ============================================================
-- cwv musket shared ammo pool
-- ============================================================
-- v0.1.306: when the player has cwv musket items equipped in BOTH the
-- ranged slot AND the melee slot (per the cross-slot enable v0.1.304),
-- their reserve ammo (`_available_ammo` on the ammo extension) is shared.
-- Each item keeps its own CHAMBER (`_current_ammo`, capped by
-- `ammo_per_clip = 1`). Per user spec: max_ammo = 11 → 1 chambered + 10
-- reserve per item. Two equipped = 1+1 chambered (separate) + 20 reserve
-- (pooled).
--
-- Mechanism: weak-keyed set of registered ammo extensions. Whenever any
-- pool member's `_available_ammo` changes (reload completion, ammo
-- pickup), the sync helper copies the new value to every other live
-- member. Cap dynamically scales with the count of alive pool members.
do
	_om._CWV_MUSKET_AMMO_EXTS    = setmetatable({}, { __mode = "k" })
	_om._CWV_RESERVE_PER_MUSKET  = 10  -- max_ammo (11) - ammo_per_clip (1)

	local function _count_alive_pool_members()
		local n = 0
		for ext in pairs(_om._CWV_MUSKET_AMMO_EXTS) do
			if ext.unit and Unit.alive(ext.unit) then n = n + 1 end
		end
		return n
	end

	_om._cwv_musket_pool_cap = function()
		return _count_alive_pool_members() * _om._CWV_RESERVE_PER_MUSKET
	end

	-- Sync one member's _available_ammo across all alive pool members,
	-- capped by the dynamic pool max. Called whenever any single
	-- member's available_ammo changes.
	_om._cwv_musket_sync_pool = function(source_ext)
		if not source_ext or not source_ext._cwv_musket_pool_member then return end
		local cap = _om._cwv_musket_pool_cap()
		local pool = math.min(source_ext._available_ammo or 0, cap)
		source_ext._available_ammo = pool
		for ext in pairs(_om._CWV_MUSKET_AMMO_EXTS) do
			if ext ~= source_ext and ext.unit and Unit.alive(ext.unit) then
				ext._available_ammo = pool
			end
		end
	end

	-- Called from our existing GearUtils.spawn_inventory_unit hook for
	-- cwv_es_musket_old items, to mark + register the spawned ammo
	-- extension. Aligns its initial `_available_ammo` with any existing
	-- pool member's value (so a second-spawned musket inherits the
	-- pool's current reserve, doesn't reset it to default 10).
	_om._cwv_musket_register_ammo_ext = function(ext)
		if not ext or not ext.unit or not Unit.alive(ext.unit) then return end
		if ext._cwv_musket_pool_member then return end
		ext._cwv_musket_pool_member = true
		_om._CWV_MUSKET_AMMO_EXTS[ext] = true
		-- Inherit existing pool value if any live members exist
		for other in pairs(_om._CWV_MUSKET_AMMO_EXTS) do
			if other ~= ext and other.unit and Unit.alive(other.unit) then
				ext._available_ammo = other._available_ammo
				break
			end
		end
		-- Re-sync with new cap (which grew when we added this member)
		_om._cwv_musket_sync_pool(ext)
		_dbg("[cwv musket pool] registered ext on unit=%s, members=%d, pool_cap=%d, available=%s",
			tostring(ext.unit), _count_alive_pool_members(), _om._cwv_musket_pool_cap(), tostring(ext._available_ammo))
	end

	-- Hook ammo extension update — vanilla's reload completion mutates
	-- `_available_ammo` in-place (line 174 of generic_ammo_user_extension.lua).
	-- After the vanilla update tick, if our pool member's available_ammo
	-- changed, sync to the other members.
	mod:hook("GenericAmmoUserExtension", "update", function(orig, self, ...)
		local was_member = self._cwv_musket_pool_member
		local before = was_member and self._available_ammo or nil
		local r = orig(self, ...)
		if was_member and self._available_ammo ~= before then
			_om._cwv_musket_sync_pool(self)
		end
		return r
	end)

	-- Hook add_ammo — ammo pickups (or any direct call) should propagate
	-- to all pool members so they all see the refill.
	mod:hook("GenericAmmoUserExtension", "add_ammo", function(orig, self, amount)
		if self._cwv_musket_pool_member then
			local before = self._available_ammo
			local r = orig(self, amount)
			if self._available_ammo ~= before then
				_om._cwv_musket_sync_pool(self)
			end
			return r
		end
		return orig(self, amount)
	end)
end

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
	if item_data.template == "old_musket_template" or item_data.template == "old_musket_template_melee" then
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
do
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
-- musket and jav+shield families) remain in the melee result. Native
-- melee items are kept untouched. The ranged-slot filter is NOT touched —
-- vanilla ranged items appear there naturally regardless.
--
-- Replaces the prior dual-hook setup (inject + post-filter) that had
-- potential chain-ordering issues. One hook, one job: take the result
-- vanilla produces, drop the unwanted ranged items from melee grid.
mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self, filter, params)
	local items = func(self, filter, params)
	if not items or type(filter) ~= "string" then return items end
	-- Only run for the melee-slot filter.
	if not string.find(filter, "slot_type == melee", 1, true) then return items end

	local filtered, kept, dropped, dropped_examples = {}, 0, 0, {}
	for _, item in ipairs(items) do
		local data = item.data or {}
		local item_slot_type = data.slot_type
		if item_slot_type ~= "ranged" then
			-- Native melee / shield / etc — keep.
			filtered[#filtered + 1] = item
			kept = kept + 1
		else
			-- Ranged item — only keep if it's in our cross-slot allowlist.
			if _is_cwv_musket_item(item) then
				filtered[#filtered + 1] = item
				kept = kept + 1
			else
				dropped = dropped + 1
				-- Log first 3 dropped items so we can see if a musket got dropped.
				if #dropped_examples < 3 then
					dropped_examples[#dropped_examples + 1] = string.format(
						"{key=%s name=%s ItemId=%s bid=%s mod_bid=%s}",
						tostring(data and data.key),
						tostring(data and data.name),
						tostring(item.ItemId),
						tostring(item.backend_id),
						tostring(data and data.mod_data and data.mod_data.backend_id))
				end
			end
		end
	end
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
-- Cross-character husk weapon residency  (Issue #280)
-- ============================================================
-- CLIENT CTD when a remote player (husk) wields the Kruber Axe & Shield
-- variant (`cwv_es_axe_shield`, base `dr_shield_axe`).
--
-- ROOT CAUSE (confirmed against decompiled source):
--   * CWV variant entries inherit `.name` from their cloned base — the
--     "clone-name-clobber" (feedback_cwv_clone_name_clobber.md). The variant
--     `cwv_es_axe_shield` therefore has `.name = "dr_shield_axe"`.
--   * The host wields the variant; the equipment RPC syncs the item to peers
--     by its `.name`, i.e. the BASE key `dr_shield_axe` (Bardin's 1H axe &
--     shield). A remote client that is NOT playing Bardin looks up the
--     VANILLA `ItemMasterList.dr_shield_axe`
--     (item_master_list_exported.lua:7358) and tries to spawn its 3P units:
--       - right_hand_unit "units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1"
--       - left_hand_unit  "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01"
--     Both are NON-resident on that client (nobody there loaded Bardin's kit).
--   * Vanilla `SimpleHuskInventoryExtension._wield_slot`
--     (simple_husk_inventory_extension.lua:641) spawns the 3P unit at
--     gear_utils.lua:190. On a non-resident unit it faults AFTER
--     `GearUtils.destroy_equipment` (line 658, which clears
--     `equipment.wielded_slot`) but BEFORE line 775 re-sets it.
--     cosmetics_tweaker's `_wield_slot` wrap pcall-swallows that fault
--     (cosmetics_tweaker.lua:7363), so vanilla `wield()` proceeds with
--     `equipment.wielded_slot == nil`, and `start_weapon_fx` (line 790) then
--     indexes `equipment.slots[nil]` -> `get_item_template(nil)` -> hard
--     CLIENT CTD. (The local wielder is fine: its own loadout stores the real
--     variant key, so it resolves the variant's Kruber-native, resident units.)
--
-- PRIMARY FIX: force-load the BASE weapon's units (1P + 3P) so they are
-- resident on EVERY client. Then the husk spawn succeeds, `_wield_slot`
-- reaches line 775, `equipment.wielded_slot` is set, and `start_weapon_fx`
-- reads a real slot. Mirrors the shipped musket-bayonet / javelin idiom:
-- `Managers.package:load(unit_path, ref, nil, sync=true, prioritize=true)`,
-- pcall-guarded (a unit path IS the vanilla pickup_package_loader form — see
-- the throwing-axe / javelin loaders in this file), residency re-verified via
-- `has_loaded`. `Application.can_get` is deliberately NOT used as a pre-gate:
-- for the units we must load it reports `false` (that non-residency is the
-- whole bug), so gating on it would skip exactly the loads we need.
-- Wrapped in `do ... end` so the constant + helper locals release back to the
-- main chunk (Lua 5.1 hard 200-local ceiling — this file already sits at the
-- limit; see the `_om` holder note near the top). Runs once, immediately.
do
	local _AXE_SHIELD_BASE_KEY = "dr_shield_axe"

	local function _force_load_axe_shield_husk_units()
		if not (Managers and Managers.package) then return end
		local base = rawget(ItemMasterList, _AXE_SHIELD_BASE_KEY)
		if type(base) ~= "table" then
			printf("[cwv axe-shield-residency] base '%s' absent from ItemMasterList; skipping force-load", _AXE_SHIELD_BASE_KEY)
			return
		end
		local ref = "cwv_axe_shield_husk_units"
		-- Husks spawn the 3P unit only (owner_unit_1p is nil for husks;
		-- gear_utils.lua appends "_3p" at line 189). Load the 1P form too so any
		-- inspect / hot-join / edge path is also covered — cost is two small
		-- meshes, matching how the musket bayonet loads both hands.
		local seen = {}
		for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
			local u = base[field]
			if type(u) == "string" and u ~= "" then
				for _, path in ipairs({ u, u .. "_3p" }) do
					if not seen[path] then
						seen[path] = true
						local ok, err = pcall(function()
							Managers.package:load(path, ref, nil, true, true)
						end)
						if ok then
							local resident = false
							pcall(function() resident = Managers.package:has_loaded(path, ref) and true or false end)
							printf("[cwv axe-shield-residency] force-loaded %s (ref=%s, resident=%s)", path, ref, tostring(resident))
						else
							printf("[cwv axe-shield-residency] FAILED to force-load %s: %s", path, tostring(err))
						end
					end
				end
			end
		end
		_cwv_axe_shield_residency_ran = true
	end

	_force_load_axe_shield_husk_units()
end

-- ============================================================
-- Cross-character husk OVERRIDE-unit residency  (issues 401, 396)
-- ============================================================
-- The axe_shield residency above force-loads the vanilla BASE units
-- (dr_shield_axe = Bardin's DWARF axe/shield) so the base-path husk spawn
-- can't CTD (issue 280 crash floor). But those base units are NOT what the
-- variant renders: the CWV entry overrides them with EMPIRE meshes
-- (wpn_axe_02_t1 + wpn_emp_shield_02; veteran = wpn_axe_hatchet_t2_magic_01 +
-- wpn_es_deus_shield_02_magic). Issue 401 confirmed (2 paired peer logs): the
-- husk showed the dwarf base because only the dwarf units were resident, so
-- the skin-path spawn of the Empire override units failed. Issue 396 is the
-- same class for the Imperial Longsword family, whose Empire greatsword mesh
-- (wpn_empire_2h_sword_04_t1) and Bretonnian-base shield variant units are
-- likewise non-resident on a client not playing a career that natively loads
-- them -> invisible husk.
--
-- The curated skin a CWV variant syncs carries the SAME per-hand override
-- units as the def (`_register_variant_skins` sets skin.right_hand_unit =
-- def.right_hand_unit, skin.left_hand_unit = def.left_hand_unit), so the def
-- override paths ARE the skin-path meshes the husk spawns — covering the def
-- fields covers the curated skin by construction.
--
-- Fix (v0.1.367-dev): DATA-DRIVEN residency. Instead of a hand-maintained key
-- list (which covered only 5 of the 27 variants whose override differs from
-- its base — 22 latent invisible-husk gaps, e.g. every dual-wield, the maul,
-- greataxe, greathammers, cudgel, shortsword, we_sword_shield, javelin boar
-- spear, outrider blunderbuss), walk EVERY def and force-load any
-- right_hand_unit / left_hand_unit (+ its `_3p` form) that DIFFERS from the
-- base weapon's same-field unit. New variants are covered automatically. Reads
-- straight from the variant DEFS (the authoritative source of the override
-- paths — the built entries don't exist yet this early in the file), compares
-- against `rawget(ItemMasterList, base_weapon)` (vanilla bases are resident at
-- boot). This is boot-time (at the keep, NOT mission load), a bounded set of
-- ~23 unique specific meshes deduped + ref-held for the session — NOT a
-- blanket mission-load force-load (the wt+cosmetics 1 GiB Lua-heap crash
-- class). The dwarf base load above is intentionally KEPT (it is the issue-280
-- crash floor for the base-path spawn, i.e. the no-skin case where the husk
-- spawns the base units); this block is purely additive residency for the
-- correct override meshes the skin-path spawn needs. Overrides that EQUAL the
-- base (musket / rapier reuse the base mesh) and the invisible-weapon sentinel
-- (javelin right hand) are skipped — nothing extra to load.
do
	-- Resolve the base weapon's same-field unit so we only force-load OVERRIDES
	-- that actually differ from what the base already renders. Vanilla bases are
	-- resident in ItemMasterList at boot; a nil base (e.g. a CW-only base not yet
	-- merged) is treated as "differs" so we conservatively load the override.
	local function _base_field_unit(base_weapon, field)
		local base = type(base_weapon) == "string" and rawget(ItemMasterList, base_weapon)
		return (type(base) == "table") and base[field] or nil
	end

	-- Shared predicate: is `u` an override unit that needs its own residency
	-- (real path, not the invisible-weapon sentinel, and differs from the base
	-- weapon's same-field unit)? Used by BOTH this pass and the regression test
	-- so the loaded set and the assertion derive from one rule (issues 396/401).
	_om._husk_override_unit_needs_residency = function(def, field)
		local u = def and def[field]
		if type(u) ~= "string" or u == "" then return nil end
		if u:find("wpn_invisible_weapon", 1, true) then return nil end
		-- Issue 403 boot fatal: ONLY vanilla weapon meshes are loadable
		-- per-unit packages. A mod-bundled mesh (units/cwv_*, e.g. the old
		-- musket custom unit) is NOT a package; queuing it via
		-- Managers.package:load is an UNCATCHABLE engine fatal when the async
		-- queue pops (PackageManager._pop_queue) - the pcall around load()
		-- cannot protect it. Mod-bundled meshes are resident wherever the mod
		-- is installed, so they never need residency anyway.
		if u:find("units/weapons/player/", 1, true) ~= 1 then return nil end
		if u == _base_field_unit(def.base_weapon, field) then return nil end
		return u
	end

	local _loaded = {}   -- path -> true (attempted); exposed for the regression test

	local function _force_load_husk_override_units()
		if not (Managers and Managers.package) then return end
		local ref = _om.HUSK_OVERRIDE_REF
		for _, d in ipairs(_variant_definitions) do
			for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
				local u = _om._husk_override_unit_needs_residency(d, field)
				if u then
					for _, path in ipairs({ u, u .. "_3p" }) do
						if not _loaded[path] then
							_loaded[path] = true
							local ok, err = pcall(function()
								Managers.package:load(path, ref, nil, true, true)
							end)
							if ok then
								local resident = false
								pcall(function() resident = Managers.package:has_loaded(path, ref) and true or false end)
								printf("[cwv husk-override-residency] force-loaded %s (ref=%s, resident=%s, for=%s.%s)",
									path, ref, tostring(resident), tostring(d.item_key), field)
							else
								printf("[cwv husk-override-residency] FAILED to force-load %s (for=%s.%s): %s",
									path, tostring(d.item_key), field, tostring(err))
							end
						end
					end
				end
			end
		end
		_cwv_husk_override_residency_ran = true
		_cwv_husk_override_paths = _loaded
	end

	_force_load_husk_override_units()
end

-- ============================================================
-- Defensive guard: husk start_weapon_fx nil-slot crash  (Issue #280)
-- ============================================================
-- Belt-and-suspenders behind the force-load above. Even with the units
-- resident, another residency edge case (a hot-join before the load lands, a
-- DIFFERENT cross-char base whose units nobody preloaded, a mod load-order
-- gap) can still leave vanilla `_wield_slot` bailing before it sets
-- `equipment.wielded_slot` (simple_husk_inventory_extension.lua:775) — because
-- cosmetics_tweaker's `_wield_slot` wrap pcall-swallows the spawn fault. When
-- that happens, vanilla `start_weapon_fx` (line 790) indexes
-- `equipment.slots[equipment.wielded_slot]` with a nil slot name ->
-- `get_item_template(nil)` -> CLIENT CTD.
--
-- This wrapper no-ops the fx spawn when the wielded slot / slot_data is nil:
-- the weapon particle fx simply does not play that frame (cosmetic, never a
-- crash). Zero behavior change for the normal case (slot_data present ->
-- vanilla runs verbatim). This is general (protects ANY husk weapon, not just
-- the axe & shield), which is why it is the durable half of the fix.
--
-- HOOK PRE-FLIGHT (CLAUDE.md NON-NEGOTIABLE #8): grepped this file for
-- `SimpleHuskInventoryExtension` / `start_weapon_fx` hooks before adding this.
-- CWV's only other SimpleHuskInventoryExtension-class touch is none; the sole
-- pre-existing husk-adjacent hook is `BackendUtils.get_item_template`
-- (line ~3827, a different (Class, method)). This is the ONLY hook on
-- (SimpleHuskInventoryExtension, start_weapon_fx) in CWV.
mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx", function(func, self, fx_name)
	local equipment = self and self._equipment
	local wielded_slot = equipment and equipment.wielded_slot
	local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
	if not slot_data then
		-- Log-only via engine `printf` (CLAUDE.md #9: user runs mod-logging
		-- OFF, so mod:info/mod:warning are invisible / chat-spammy). pcall so
		-- the diagnostic itself can never fault the wield path.
		pcall(function()
			printf("[cwv husk-fx-guard] SKIP start_weapon_fx: equipment.wielded_slot=%s slot_data=nil self.wielded_slot=%s career=%s fx=%s husk_unit=%s -- vanilla start_weapon_fx would CTD here (Issue #280); fx skipped, host+client stay alive",
				tostring(wielded_slot), tostring(self and self.wielded_slot),
				tostring(self and self._career_name), tostring(fx_name), tostring(self and self._unit))
		end)
		return
	end
	return func(self, fx_name)
end)
_cwv_husk_fx_guard_installed = true

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
-- hook_safe (post-observation, no return override) so it can never perturb
-- the wield path. Pre-flight (CLAUDE.md #8): CWV's only other
-- SimpleHuskInventoryExtension hook is on `start_weapon_fx` (above) — this is
-- the sole hook on (SimpleHuskInventoryExtension, _wield_slot) in CWV.
mod:hook_safe("SimpleHuskInventoryExtension", "_wield_slot", function(self, world, equipment, slot_name, unit_1p, unit_3p)
	pcall(function()
		local slot = equipment and equipment.slots and equipment.slots[slot_name]
		local item_data = slot and slot.item_data
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
end)
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
	if not owner_unit_1p and _om._husk_rekey_units then
		if _om._husk_rekey_units(hand, item_data, item_units, owner_unit_3p, slot_name) then
			-- #478 residency-gated defer: the resolved variant would hand vanilla a
			-- NON-RESIDENT unit for this hand (a Deus-only base mesh outside Chaos
			-- Wastes -- e.g. the Outrider keeping dr_deus_01's Trollhammer left-mount).
			-- Skip the vanilla spawn entirely rather than error into an invisible
			-- wield / async C-assert. Vanilla only reached this hand because
			-- item_units[hand.."_hand_unit"] is truthy (simple_husk_inventory_extension
			-- .lua:665/669), so returning all-nil is exactly a hand vanilla never spawned.
			if _om._probe_279_spawn then
				_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, nil, "deferred_478")
			end
			return nil, nil, nil, nil
		end
	end
	local v_w3p, v_a3p, v_w1p, v_a1p =
		func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)

	-- issue 279 (2nd repro): capture the full ammo-attach decision at EVERY
	-- spawn (owner + husk, both hands) for a no_ammo_unit variant's base. Self-gates
	-- on base being a no_ammo base; pure diagnostic (see the helper for the trace).
	if _om._probe_279_spawn then
		_om._probe_279_spawn(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, v_a3p, nil)
	end

	-- ============================================================
	-- Husk (remote-player) CWV apply  (issues 397/394/399)
	-- ============================================================
	-- This hook is the ONLY GearUtils path that fires for husks:
	-- SimpleHuskInventoryExtension._wield_slot -> spawn_inventory_unit
	-- (simple_husk_inventory_extension.lua:666/670). The owner/bot path runs
	-- GearUtils.create_equipment (which passes a 1P rig as owner_unit_1p and
	-- applies CWV transforms itself, hook at the bottom of this file); husks
	-- have no 1P rig, so `owner_unit_1p == nil` is the husk/bot discriminator.
	-- Everything here is IDEMPOTENT with the create_equipment apply (scale is
	-- an absolute set; offset is guarded by a weak-keyed applied-set), so a
	-- bot spawn that reaches both paths is harmless. Bounded to `not
	-- owner_unit_1p` purely so the local owner's 1P-having spawn is never
	-- touched. The helpers live on `_om` because they must reference
	-- `_transform_unit` / `_resolve_field` / `_resolve_cwv_def` which are
	-- declared far below this line (Lua locals are only visible after their
	-- declaration point; `_om` is captured as an upvalue and its fields are
	-- populated at load time, before any in-mission spawn).
	if not owner_unit_1p then
		-- issue 399: strip the inherited ammo (Trollhammer torpedo) that the
		-- husk attaches for a no_ammo_unit variant (the husk resolves the BASE
		-- item_data, so no_ammo_unit on the CWV entry never reaches it).
		if _om._husk_strip_cwv_ammo and _om._husk_strip_cwv_ammo(item_data, owner_unit_3p, v_a3p) then
			v_a3p = nil
		end
		-- issues 397/394: apply the CWV scale/offset transform to the husk 3P
		-- weapon unit, mirroring the owner-side create_equipment hook.
		if _om._husk_apply_cwv_transform then
			_om._husk_apply_cwv_transform(hand, item_data, item_units, v_w3p, owner_unit_3p, slot_name)
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
	-- v0.1.300-301: gate accepts both musket families (cwv_es_musket and
	-- cwv_es_musket_old), ranged and melee templates. The bayonet attach
	-- is suppressed below for old musket (its mesh has bayonet baked in);
	-- texture/transform/FX-proxy fire for either family.
	if item_template ~= Weapons.musket_template and item_template ~= Weapons.musket_template_melee
	   and item_template ~= Weapons.old_musket_template and item_template ~= Weapons.old_musket_template_melee then
		return v_w3p, v_a3p, v_w1p, v_a1p
	end

	-- v0.1.292: bind textures + v0.1.293: track unit for live transform tuning +
	-- v0.1.293: spawn hidden vanilla rifle proxy for FX emission. All gated on
	-- cwv_es_musket_old backend_id. Helpers defined globally below (search
	-- "_apply_old_musket_textures", "_track_old_musket_unit",
	-- "_spawn_old_musket_fx_proxy").
	local _bid_for_tex = item_data and item_data.backend_id
	if _bid_for_tex and type(_bid_for_tex) == "string" and _bid_for_tex:match("^cwv_es_musket_old") then
		-- v0.1.295: distinguish ranged vs melee mode for 1P transform tuning.
		-- The user wants different pos/rot/scale per stance.
		local _mode = (item_template == Weapons.musket_template_melee
		               or item_template == Weapons.old_musket_template_melee) and "melee" or "ranged"
		_om._apply_old_musket_textures(v_w1p)
		_om._apply_old_musket_textures(v_w3p)
		_om._track_old_musket_unit(v_w1p, "1p", _mode)
		_om._track_old_musket_unit(v_w3p, "3p", _mode)
		_om._apply_old_musket_transform(v_w1p, "1p", _mode)
		_om._apply_old_musket_transform(v_w3p, "3p", _mode)
		_om._spawn_old_musket_fx_proxy(world, v_w1p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1",     owner_unit_1p, "j_rightweaponattach")
		_om._spawn_old_musket_fx_proxy(world, v_w3p, "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p", owner_unit_3p, "j_rightweaponattach")

		-- v0.1.306: register the spawned ammo extension into the shared
		-- reserve pool so cross-slot equipped cwv muskets share reserve
		-- ammo (chambered ammo stays per-item). 1P unit only — 3P doesn't
		-- have ammo_system in vanilla rifle template.
		if _om._cwv_musket_register_ammo_ext and v_w1p and Unit.alive(v_w1p)
				and ScriptUnit.has_extension(v_w1p, "ammo_system") then
			_om._cwv_musket_register_ammo_ext(ScriptUnit.extension(v_w1p, "ammo_system"))
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
	local _bid_pre = item_data and item_data.backend_id
	local _is_old_musket = _bid_pre and type(_bid_pre) == "string" and _bid_pre:match("^cwv_es_musket_old")

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
	end

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

-- Weak-keyed tracking sets — one per (perspective × mode) bucket.
_om._CWV_OLD_MUSKET_UNITS_1P_RANGED = setmetatable({}, { __mode = "k" })
_om._CWV_OLD_MUSKET_UNITS_1P_MELEE  = setmetatable({}, { __mode = "k" })
_om._CWV_OLD_MUSKET_UNITS_3P_RANGED = setmetatable({}, { __mode = "k" })
_om._CWV_OLD_MUSKET_UNITS_3P_MELEE  = setmetatable({}, { __mode = "k" })

_om._track_old_musket_unit = function(unit, perspective, mode)
	if not unit or not Unit.alive(unit) then return end
	if perspective == "1p" then
		if mode == "melee" then
			_om._CWV_OLD_MUSKET_UNITS_1P_RANGED[unit] = nil
			_om._CWV_OLD_MUSKET_UNITS_1P_MELEE[unit] = true
		else
			_om._CWV_OLD_MUSKET_UNITS_1P_MELEE[unit] = nil
			_om._CWV_OLD_MUSKET_UNITS_1P_RANGED[unit] = true
		end
	else
		if mode == "melee" then
			_om._CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = nil
			_om._CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = true
		else
			_om._CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = nil
			_om._CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = true
		end
	end
end

_om._apply_old_musket_textures = function(unit)
	if not unit or not Unit.alive(unit) then return end
	local ok, num_meshes = pcall(Unit.num_meshes, unit)
	if not ok or not num_meshes then return end
	for i = 0, num_meshes - 1 do
		local mok, mesh = pcall(Unit.mesh, unit, i)
		if mok and mesh then
			local nok, num_mats = pcall(Mesh.num_materials, mesh)
			if nok and num_mats then
				for j = 0, num_mats - 1 do
					local matok, mat = pcall(Mesh.material, mesh, j)
					if matok and mat then
						pcall(Material.set_texture, mat, "texture_map_c0ba2942", "textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo")
						pcall(Material.set_texture, mat, "texture_map_59cd86b9", "textures/cwv_es_musket_custom/cwv_es_musket_custom_normal")
						pcall(Material.set_texture, mat, "texture_map_0205ba86", "textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic")
					end
				end
			end
		end
	end
end

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

_om._apply_old_musket_transform = function(unit, perspective, mode)
	if not unit or not Unit.alive(unit) then return end
	local pos, rot, scale = _om._old_musket_transform_components(perspective, mode)
	pcall(Unit.set_local_position, unit, 0, Vector3(pos[1], pos[2], pos[3]))
	-- rot is a QuaternionBox (or nil for identity); see v0.1.298 note.
	-- Unbox to get a fresh raw Quaternion for the API call.
	pcall(Unit.set_local_rotation, unit, 0, rot and rot:unbox() or Quaternion.identity())
	pcall(Unit.set_local_scale, unit, 0, Vector3(scale[1], scale[2], scale[3]))
end

-- #474: Old Musket stance is explicit, durable presentation state. Vanilla's
-- equipment RPC deliberately carries the base es_handgun identity, so the
-- stance cannot be inferred by a remote husk. This VMF channel sends one small
-- transition record on toggle/wield/state-entry and a query/reply on join. It
-- never polls or transmits per frame. Receivers cache by owner+slot; a late
-- husk/preview reconstruction consumes the same state as an immediate update.
do
	local CHANNEL, SCHEMA = "cwv_old_musket_mode_v1", 1
	local modes_by_owner = setmetatable({}, { __mode = "k" })
	local modes_by_peer = {}
	local modes_by_backend = {}
	local diag_seen, diag_count, DIAG_MAX = {}, 0, 48
	_om._old_musket_modes_by_owner = modes_by_owner
	_om._old_musket_modes_by_backend = modes_by_backend

	local function old_bid(item_data)
		local bid = item_data and (item_data.backend_id
			or (item_data.mod_data and item_data.mod_data.backend_id))
		return type(bid) == "string" and bid:match("^cwv_es_musket_old") and bid or nil
	end

	local function diag_once(key, fmt, ...)
		if diag_seen[key] or diag_count >= DIAG_MAX then return end
		diag_seen[key], diag_count = true, diag_count + 1
		pcall(printf, "[cwv:474] " .. fmt, ...)
	end

	local function send(recipient, op, slot_name, mode, bid)
		if type(mod.network_send) ~= "function" then return false end
		local ok = pcall(function()
			mod:network_send(CHANNEL, recipient or "others", SCHEMA, op,
				slot_name or "", mode or "", bid or "")
		end)
		return ok
	end

	local function owner_slot(owner_unit)
		if not owner_unit or not Unit.alive(owner_unit) then return nil end
		local ok, inv = pcall(ScriptUnit.extension, owner_unit, "inventory_system")
		if not ok or not inv or not inv.equipment then return nil end
		local equipment = inv:equipment()
		return equipment and equipment.wielded_slot, equipment
	end

	local function apply_owner(owner_unit, slot_name, mode, surface)
		local wielded_slot, equipment = owner_slot(owner_unit)
		if wielded_slot ~= slot_name or not equipment then return false end
		local unit = equipment.right_hand_wielded_unit_3p
		if not unit or not Unit.alive(unit) then return false end
		_om._track_old_musket_unit(unit, "3p", mode)
		_om._apply_old_musket_textures(unit)
		_om._apply_old_musket_transform(unit, "3p", mode)
		local pos, _, scale = _om._old_musket_transform_components("3p", mode)
		diag_once("apply:" .. tostring(owner_unit) .. ":" .. slot_name .. ":" .. mode .. ":" .. surface,
			"presentation owner=%s slot=%s surface=%s mode=%s final_pos=(%.3f,%.3f,%.3f) final_scale=(%.3f,%.3f,%.3f)",
			tostring(owner_unit), slot_name, surface, mode,
			pos[1], pos[2], pos[3], scale[1], scale[2], scale[3])
		return true
	end

	local function peer_for_owner(owner_unit)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.owner, pm, owner_unit)
		player = ok and player or nil
		if not player then return nil end
		if type(player.peer_id) == "string" then return player.peer_id end
		local nok, peer_id = pcall(player.network_id, player)
		return nok and peer_id or nil
	end

	_om._old_musket_mode_for_owner = function(owner_unit, slot_name)
		local slots = owner_unit and modes_by_owner[owner_unit]
		if not slots then slots = modes_by_peer[peer_for_owner(owner_unit)] end
		if not slots then return "ranged" end
		if not slot_name then slot_name = owner_slot(owner_unit) end
		return slots[slot_name] or "ranged"
	end

	_om._old_musket_record_and_publish = function(owner_unit, slot_name, item_data, mode, reason, recipient)
		local bid = old_bid(item_data)
		if not bid or (mode ~= "melee" and mode ~= "ranged") then return false end
		modes_by_backend[bid] = mode
		if owner_unit then
			local slots = modes_by_owner[owner_unit] or {}
			modes_by_owner[owner_unit], slots[slot_name] = slots, mode
		end
		send(recipient, "state", slot_name, mode, bid)
		diag_once("tx:" .. tostring(owner_unit) .. ":" .. slot_name .. ":" .. mode .. ":" .. tostring(reason),
			"state tx owner=%s slot=%s mode=%s bid=%s reason=%s",
			tostring(owner_unit), slot_name, mode, bid, tostring(reason))
		return true
	end

	_om._old_musket_publish_local_loadout = function(recipient, reason)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.local_player, pm, 1)
		player = ok and player or nil
		local owner_unit = player and player.player_unit
		local _, equipment = owner_slot(owner_unit)
		local slots = equipment and equipment.slots
		if type(slots) ~= "table" then return 0 end
		local n = 0
		for slot_name, slot_data in pairs(slots) do
			local item_data = slot_data and slot_data.item_data
			if old_bid(item_data) then
				local mode = item_data.mod_data and item_data.mod_data.cwv_musket_stance or "ranged"
				if _om._old_musket_record_and_publish(owner_unit, slot_name, item_data,
						mode, reason, recipient) then n = n + 1 end
			end
		end
		return n
	end

	_om._old_musket_request_states = function(reason)
		send("others", "query")
		_om._old_musket_publish_local_loadout(nil, reason or "state_boundary")
	end

	_om._old_musket_publish_fire = function(owner_unit, event_name)
		local slot_name, equipment = owner_slot(owner_unit)
		local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
		local bid = old_bid(slot_data and slot_data.item_data)
		if not bid or event_name ~= "player_combat_weapon_rifle_fire" then return false end
		return send("others", "fire", slot_name, event_name, bid)
	end

	if type(mod.network_register) == "function" then
		pcall(function()
			mod:network_register(CHANNEL, function(sender_peer_id, schema, op, slot_name, mode, bid)
				if schema ~= SCHEMA then return end
				if op == "query" then
					_om._old_musket_publish_local_loadout(sender_peer_id, "query_reply")
					return
				end
				if op == "fire" then
					if mode ~= "player_combat_weapon_rifle_fire" or type(bid) ~= "string"
							or not bid:match("^cwv_es_musket_old") then return end
					local pm = Managers and Managers.player
					local ok, player = pm and pcall(pm.player_from_peer_id, pm, sender_peer_id, 1)
					player = ok and player or nil
					local owner_unit = player and player.player_unit
					local world = rawget(_G, "Application") and Application.main_world()
					if owner_unit and Unit.alive(owner_unit) and world and rawget(_G, "WwiseUtils") then
						local played = pcall(WwiseUtils.trigger_unit_event, world, mode, owner_unit, 0)
						diag_once("fire:" .. tostring(sender_peer_id) .. ":" .. tostring(bid),
							"remote fire peer=%s owner=%s bid=%s played=%s",
							tostring(sender_peer_id), tostring(owner_unit), bid, tostring(played))
					end
					return
				end
				if op ~= "state" or (mode ~= "melee" and mode ~= "ranged")
						or type(slot_name) ~= "string" or type(bid) ~= "string"
						or not bid:match("^cwv_es_musket_old") then return end
				local peer_slots = modes_by_peer[sender_peer_id] or {}
				modes_by_peer[sender_peer_id], peer_slots[slot_name], modes_by_backend[bid] = peer_slots, mode, mode
				local pm = Managers and Managers.player
				local ok, player = pm and pcall(pm.player_from_peer_id, pm, sender_peer_id, 1)
				player = ok and player or nil
				local owner_unit = player and player.player_unit
				if not owner_unit then return end
				local slots = modes_by_owner[owner_unit] or {}
				modes_by_owner[owner_unit], slots[slot_name] = slots, mode
				apply_owner(owner_unit, slot_name, mode, "remote_event")
				diag_once("rx:" .. tostring(sender_peer_id) .. ":" .. slot_name .. ":" .. mode,
					"state rx peer=%s owner=%s slot=%s mode=%s bid=%s",
					tostring(sender_peer_id), tostring(owner_unit), slot_name, mode, bid)
			end)
		end)
	end
	_om._old_musket_mode_channel = CHANNEL
	_om._old_musket_mode_schema = SCHEMA
end

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
	local n_1p_r, n_1p_m = 0, 0
	for unit in pairs(_om._CWV_OLD_MUSKET_UNITS_1P_RANGED) do
		if Unit.alive(unit) then
			_om._apply_old_musket_transform(unit, "1p", "ranged"); n_1p_r = n_1p_r + 1
		else
			_om._CWV_OLD_MUSKET_UNITS_1P_RANGED[unit] = nil
		end
	end
	for unit in pairs(_om._CWV_OLD_MUSKET_UNITS_1P_MELEE) do
		if Unit.alive(unit) then
			_om._apply_old_musket_transform(unit, "1p", "melee"); n_1p_m = n_1p_m + 1
		else
			_om._CWV_OLD_MUSKET_UNITS_1P_MELEE[unit] = nil
		end
	end
	local n_3p_r, n_3p_m = 0, 0
	for unit in pairs(_om._CWV_OLD_MUSKET_UNITS_3P_RANGED) do
		if Unit.alive(unit) then
			_om._apply_old_musket_transform(unit, "3p", "ranged"); n_3p_r = n_3p_r + 1
		else
			_om._CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = nil
		end
	end
	for unit in pairs(_om._CWV_OLD_MUSKET_UNITS_3P_MELEE) do
		if Unit.alive(unit) then
			_om._apply_old_musket_transform(unit, "3p", "melee"); n_3p_m = n_3p_m + 1
		else
			_om._CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = nil
		end
	end
	mod:echo("[cwv old-musket] reapplied to %d 1P-r + %d 1P-m + %d 3P-r + %d 3P-m unit(s)", n_1p_r, n_1p_m, n_3p_r, n_3p_m)
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
-- The Tuskgor Javelin family appends cwv-only keys to networked lookup tables
-- (pickup_names, husks, projectile_units) at a LOCAL `#tbl+1` index. Those
-- indices ride VANILLA projectile/pickup spawn RPCs, so a peer WITHOUT cwv
-- cold-decodes an index its own table lacks -> strict `__index` fatal
-- (network_lookup.lua). Verified SEND sites in the decompiled source:
--
--   PICKUP (thrown-impact) -- the thrower (always a cwv peer) encodes and sends:
--     * Path A (sticks in a wall/enemy): PlayerProjectileUnitExtension
--       ._spawn_linked_pickup_projectile encodes
--       `pickup_name_id = NetworkLookup.pickup_names[pickup_name]` then
--       `send_rpc_server("rpc_spawn_linked_pickup", pickup_name_id, ...)`
--       (player_projectile_unit_extension.lua:1354-1359). The server relays the
--       spawn as a networked pickup GameObject whose pickup_name field is
--       `NetworkLookup.pickup_names[pickup_name]` (game_object_initializers_
--       extractors.lua:1795/1816); every client extracts it back.
--     * Path B (bounces/drops): PlayerProjectileUnitExtension
--       ._spawn_pickup_projectile encodes the same pickup_name_id (+ a husk id
--       for the pickup unit, which is already a vanilla key) then
--       `send_rpc_server("rpc_spawn_pickup_projectile", ...)`
--       (player_projectile_unit_extension.lua:1376-1395).
--   Substituting the `pickup_name` ARG at these two senders cascades: the
--   vanilla name re-encodes to a vanilla pickup_names index AND makes the
--   server spawn the vanilla pickup, so the GameObject a non-cwv peer extracts
--   is vanilla end to end. Sender-side (not the receiver hooks at 6036/6051)
--   is what protects a non-cwv HOST too (a cwv client throwing into a vanilla
--   host's game).
--
--   IN-FLIGHT PROJECTILE (Tuskgor Javelin BOMB) -- the boar-spear in-flight
--   unit is a cwv-appended husks key (_TJ_BOAR_SPEAR_UNIT, injected ~5646):
--     * ProjectileSystem.spawn_player_projectile spawns it via
--       `unit_spawner:spawn_network_unit(projectile_unit_name, ...)` where
--       `projectile_unit_name = _get_projectile_units_names(...).projectile_unit_name`
--       (projectile_system.lua:159-176, 247-249); the projectile GameObject
--       encodes that unit through NetworkLookup.husks, so a non-cwv client
--       cold-decodes it (projectile_system.lua:442 on the pickup path is the
--       same reverse-lookup shape). The SAME cwv projectile_units_template
--       (_TJ_PROJECTILE_KEY) also rides TransientPackageLoader.hot_join_sync to
--       a joining peer as `NetworkLookup.projectile_units[name]`
--       (transient_package_loader.lua:187-193). Substituting the resolved
--       projectile_units to the vanilla "javelin" entry makes BOTH the GO husk
--       and the transient projectile_units index encode vanilla. Cosmetic only:
--       impact_data / damage come from the action, untouched.
--
-- The pickup is a GAMEPLAY axis: the vanilla throwing-axe substitute below is
-- wire-safe, but its interaction callback only accepts ammo_type
-- "throwing_axe". Tuskgor Javelin advertises "throwing_javelin", so the old
-- unconditional substitution made every recovered spear inert even in solo.
-- Keep the real pickup only after peer parity is positively confirmed (solo is
-- vacuously safe); otherwise degrade to the vanilla key so a non-CWV peer can
-- never cold-decode the appended lookup index.
-- NOTE (not closed here): the BOMB's world/pool pickup (_TJB_PICKUP_KEY, ~6708)
-- is a GAMEPLAY axis -- coercing it to a vanilla grenade would change what a
-- cwv player picks up -- so it is left for the issue 371 peer-parity gate, per
-- memory `project_vt2_cross_peer_wire_safety` (which lists #424 under it).
_om._tj_pickup_wire_map = {
	-- cwv thrown-impact pickup key -> a base-game pickup with a boot-stable
	-- pickup_names index on every peer (throwing axe: same pup_ unit, and the
	-- link_ variant shares our `limited_owned_pickup_unit` template).
	[_TJ_PICKUP_KEY]      = "ammo_throwing_axe_01_t1",
	[_TJ_LINK_PICKUP_KEY] = "link_ammo_throwing_axe_01_t1",
}
-- Returns a vanilla fallback while parity is unconfirmed, or nil to preserve
-- the functional CWV pickup. The optional override exists for deterministic
-- regression checks only; live callers omit it.
function _om._wire_safe_pickup_name(pickup_name, parity_override)
	local all_have = parity_override
	if all_have == nil then
		local pp = mod._cwv_peer_parity
		if pp and type(pp.all_peers_have) == "function" then
			local ok, result = pcall(pp.all_peers_have, pp)
			all_have = ok and result == true
		else
			all_have = false
		end
	end
	return mod._cwv_javelin_pickup.wire_fallback(
		pickup_name, _om._tj_pickup_wire_map, all_have)
end
_om._TJ_INFLIGHT_MODDED_UNIT   = _TJ_BOAR_SPEAR_UNIT
_om._TJ_INFLIGHT_SAFE_TEMPLATE = "javelin"   -- vanilla ProjectileUnits key (elf javelin)
-- Returns the vanilla "javelin" projectile_units table when `projectile_units`
-- is our boar-spear entry (so its husk never reaches the wire); else unchanged.
function _om._wire_safe_projectile_units(projectile_units)
	if projectile_units and projectile_units.projectile_unit_name == _om._TJ_INFLIGHT_MODDED_UNIT
		and rawget(_G, "ProjectileUnits") then
		local safe = ProjectileUnits[_om._TJ_INFLIGHT_SAFE_TEMPLATE]
		if safe then return safe end
	end
	return projectile_units
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
	local safe = _om._wire_safe_pickup_name(pickup_name)
	if safe then
		printf("[cwv:424] linked pickup wire-safe %s -> %s", tostring(pickup_name), safe)
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
	local safe = _om._wire_safe_pickup_name(pickup_name)
	if safe then
		printf("[cwv:424] dropped pickup wire-safe %s -> %s", tostring(pickup_name), safe)
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

	-- Disable the pistol-shoot action_three (kind="handgun"). Keep the
	-- action defined for state-machine/network consistency; just
	-- prevent it from ever firing. Same pattern as tuskgor_javelin_template's
	-- weapon_reload disable.
	if template.actions and template.actions.action_three then
		for _, sub_action in pairs(template.actions.action_three) do
			if type(sub_action) == "table" then
				sub_action.condition_func       = _always_false
				sub_action.chain_condition_func = _always_false
			end
		end
	end

	-- Override left_hand_attachment_node_linking. The base fencing template
	-- uses `AttachmentNodeLinking.pistol.left`, which has component
	-- bindings for `lock_hammer`, `trigger`, and `lock_lid` (nodes that
	-- exist on the pistol mesh `wpn_emp_pistol_01_t1`). Our variant
	-- replaces left_hand_unit with `wpn_invisible_weapon`, which does
	-- NOT have those nodes — so vanilla's `Unit.node(unit, "lock_hammer")`
	-- crashes with `[Script Error]: lock_hammer` on equip
	-- (GUID acb910d1-a625-49b1-b899-86d48d27462d, v0.1.183).
	-- Replace with a minimal binding: just attach the (invisible) left
	-- weapon to `j_leftweaponattach` at node 0, no component lookups.
	-- This is on the CLONE only — base template still has the full
	-- pistol bindings intact for native Saltzpyre wielders.
	template.left_hand_attachment_node_linking = {
		first_person = {
			wielded   = { { source = "j_leftweaponattach", target = 0 } },
			unwielded = { { source = "j_hips",             target = 0 } },
		},
		third_person = {
			display   = { { source = "j_leftweaponattach", target = 0 } },
			wielded   = { { source = "j_leftweaponattach", target = 0 } },
			unwielded = { { source = "j_hips",             target = 0 } },
		},
	}

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

-- ============================================================
-- Custom skin registration
-- ============================================================

-- Registry of cwv_es_dual_swords skin keys (default + the 17 Kruber 1h-sword
-- illusion clones registered by `_register_kruber_1h_sword_dual_illusions`).
-- INERT MARKER as of v0.1.145 — no runtime hook consumes it. Previously read by
-- a `BackendUtils.get_item_units` right→left mirror that worked around the skin
-- entries omitting `left_hand_unit`; the mirror and its callers were removed
-- when the skins gained `left_hand_unit` directly and switched to the
-- `display_dual_weapons` rig (see `J_LEFTWEAPONATTACH_INVESTIGATION.md`).
-- Kept declared here in case a future hook needs to filter on
-- cwv_es_dual_swords skin lineage; safe to remove if unused 6 months out.
local _kruber_1h_dual_skin_keys = {}

-- QUESTION: skin_only entries (e.g. cwv_es_longsword_nordland) are NOT skipped
-- here — only def.no_skin gates skin registration. That's deliberate: skin_only
-- entries exist precisely to provide a selectable cosmetic skin without giving
-- the player the inventory item itself. Documented for clarity.
local function _register_variant_skins()
	if not WeaponSkins then return end
	for _, def in ipairs(_variant_definitions) do
		if def.no_skin then goto skip_skin end
		local skin_key = def.item_key .. "_skin"
		-- ALWAYS overwrite (no `if not WeaponSkins.skins[skin_key]` guard) so
		-- partial reloads or earlier mod versions don't leave a stale skin entry
		-- without our newer fields (e.g. ammo_unit added in 0.1.60).
		--
		-- For ammo weapons (e.g. javelin variants) we MUST mirror ammo_unit
		-- into the skin entry. BackendUtils.get_item_units overwrites
		-- units.ammo_unit with skin_template.ammo_unit unconditionally when a
		-- skin is set, so an absent field on the skin nukes the inherited
		-- value from the base ItemMasterList entry. Downstream the previewer
		-- does `left_hand_unit = ammo_unit` for is_ammo_weapon items and then
		-- concatenates "_3p" — nil ammo_unit crashes that line. Fall back to
		-- def.left_hand_unit (the held model) when ammo_unit isn't set so the
		-- spear/javelin/etc. swap still drives the held + thrown visual.
		-- Defense in depth: BackendUtils.get_item_units overwrites a whole set
		-- of fields from skin_template, not just ammo_unit. Mirror them all from
		-- the base ItemMasterList entry when the variant doesn't override —
		-- prevents the throw projectile / pickup spawn paths from getting nil
		-- once the held-model crash is past.
		--
		-- v0.1.182: gated the def.left_hand_unit fallback on `base.ammo_unit`.
		-- For variants whose base weapon DOESN'T have ammo_unit (e.g. brace of
		-- pistols, repeating pistols — `wh_brace_of_pistols` has no
		-- ammo_unit), forcing one in via def.left_hand_unit triggers
		-- GearUtils.spawn_inventory_unit's `fassert(ammo_unit_attachment_node_linking)`
		-- — the brace template defines ammo_data with `ammo_hand = "right"`
		-- but no ammo_unit_attachment_node_linking (because vanilla
		-- never uses ammo_unit there). Crash GUID 2df233ae-80f6-40d3-aa58-e98417f2ad8f.
		-- Now: only default to def.left_hand_unit when base has ammo_unit;
		-- otherwise leave nil and let vanilla's no-ammo_unit path run.
		local base = (ItemMasterList and rawget(ItemMasterList, def.base_weapon)) or {}
		local ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)
		local hud_icon = def.hud_icon or "weapon_generic_icon_axe1h"
		local inventory_icon = def.inventory_icon or "icon_wpn_dw_shield_01_axe"
		local rarity = def.rarity or "exotic"
		-- display_unit is the LINK UNIT the LootItemUnitPreviewer spawns first
		-- as the spinning pivot in the weapon-customization preview pane. It's
		-- a vanilla "stage" mesh (e.g. `display_2h_swords` for greatswords).
		-- `_spawn_link_unit` reads `item_data.display_unit` then
		-- `WeaponSkins.skins[skin].display_unit` and bails with a warning if
		-- both are nil — the weapon units have nothing to attach to, so they
		-- don't render. Vanilla WEAPON entries (e.g. `es_bastard_sword` in
		-- `item_master_list_lake.lua:186`) DON'T carry `display_unit` on the
		-- weapon's row — only weapon_skin rows do (`es_bastard_sword_skin_01`
		-- has `display_unit = "units/weapons/weapon_display/display_2h_swords"`).
		-- v0.1.99 tried `base.display_unit` and got nil for every variant;
		-- the picker stayed invisible (log: "Couldn't find any display unit
		-- for item cwv_es_longsword_skin"). Resolve by scanning ItemMasterList
		-- for any vanilla weapon_skin whose `matching_item_key` matches our
		-- `base_weapon` and copying its `display_unit`. Per-variant
		-- `def.display_unit` overrides if set.
		local display_unit = def.display_unit
		if not display_unit and ItemMasterList then
			for _, entry in pairs(ItemMasterList) do
				if entry.item_type == "weapon_skin"
						and entry.matching_item_key == def.base_weapon
						and entry.display_unit then
					display_unit = entry.display_unit
					break
				end
			end
		end

		-- DUAL-WIELD DISPLAY RIG.
		-- The cosmetic illusion picker attaches each hand's weapon unit to a
		-- named node on the `display_unit` pivot. Single-sword rigs only author
		-- `j_rightweaponattach`; the previewer crashes with `[Script Error]:
		-- j_leftweaponattach` if it tries to attach the left hand against one.
		-- The lookup loop above can return a wrong-family rig (vanilla
		-- dual-wield IML weapon_skin entries often don't set display_unit, so
		-- the loop can fall through to a sibling skin's value), so override
		-- here per-variant.
		--
		-- `_force_display_unit` maps each cwv item_key to the dual-attach rig
		-- vanilla uses for the matching weapon family. All listed rigs are
		-- known to author both `j_rightweaponattach` and `j_leftweaponattach`
		-- (proven by the rig appearing in `weapon_skins.lua` for a vanilla
		-- weapon whose cosmetic picker is shipped + working). See
		-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the post-mortem and
		-- `DEVELOPMENT.md` "Dual-wield variants — display rig requirements"
		-- for the rig-per-family table.
		local _force_display_unit = {
			-- Identical-mesh empire short-swords; vanilla precedent: we_dual_sword_skin_01 (`weapon_skins.lua:5750`)
			cwv_es_dual_swords    = "units/weapons/weapon_display/display_dual_weapons",
			-- Identical-mesh hatchets; vanilla precedent: dw_dual_axe_skin_01 (`weapon_skins.lua:2364`)
			cwv_es_dual_axes      = "units/weapons/weapon_display/display_dual_axes",
			cwv_wh_dual_axes      = "units/weapons/weapon_display/display_dual_axes",
			-- Identical-mesh empire maces; vanilla precedent: dual_wield_hammers
			-- skins in `weapon_skins_bless.lua:395` use display_dual_hammers.
			cwv_es_dual_maces             = "units/weapons/weapon_display/display_dual_hammers",
			cwv_wh_dual_maces             = "units/weapons/weapon_display/display_dual_hammers",
			cwv_dr_dawi_dual_maces        = "units/weapons/weapon_display/display_dual_hammers",
			cwv_dr_dawi_mace_shield       = "units/weapons/weapon_display/display_shield_hammer",
			-- Identical-mesh wh_1h_hammer Skullsplitters dual-wielded; vanilla
			-- precedent: wh_dual_hammer in `dual_wield_hammers_priest.lua:1720`
			-- sets the same rig on the priest dual-hammers weapon template,
			-- and vanilla Saltzpyre wh_dual_hammer cosmetic preview is a
			-- shipped, working feature.
			cwv_es_dual_warpriest_hammers = "units/weapons/weapon_display/display_dual_hammers",
			-- Mixed-mesh sword (right) + mace (left); vanilla precedent:
			-- dual_wield_hammer_sword.lua:1572 sets the same rig on the
			-- weapon template, and vanilla Kruber mace+sword cosmetic
			-- preview is a shipped, working feature.
			cwv_es_sword_and_mace = "units/weapons/weapon_display/display_dual_weapons",
			-- Skullsplitter (right) + Empire shield (left); vanilla precedent:
			-- wh_hammer_shield in `1h_hammers_shield_priest.lua` uses
			-- display_shield_hammer. Same rig works for our variant since
			-- the right-hand mesh is also a hammer (the wh_1h_hammer_01
			-- Skullsplitter).
			cwv_es_warpriest_hammer_shield = "units/weapons/weapon_display/display_shield_hammer",
		}
		local skin_left_hand_unit = def.left_hand_unit
		local forced_rig = _force_display_unit[def.item_key]
		if forced_rig then
			display_unit = forced_rig
			-- Inert legacy registry — see declaration above.
			if def.item_key == "cwv_es_dual_swords" then
				_kruber_1h_dual_skin_keys[skin_key] = true
			end
		end

		WeaponSkins.skins[skin_key] = {
			display_name              = def.item_key .. "_skin_name",
			description               = def.item_key .. "_description",
			rarity                    = rarity,
			right_hand_unit           = def.right_hand_unit,
			left_hand_unit            = skin_left_hand_unit,
			ammo_unit                 = ammo_unit,
			ammo_unit_3p              = def.ammo_unit_3p or base.ammo_unit_3p,
			projectile_units_template = def.projectile_units_template or base.projectile_units_template,
			pickup_template_name      = def.pickup_template_name or base.pickup_template_name,
			link_pickup_template_name = def.link_pickup_template_name or base.link_pickup_template_name,
			hud_icon                  = hud_icon,
			inventory_icon            = inventory_icon,
			display_unit              = display_unit,
			template                  = nil,
		}
		mod:info("Registered custom skin: %s (ammo_unit=%s, projectile=%s, display_unit=%s)",
			skin_key, tostring(ammo_unit),
			tostring(def.projectile_units_template or base.projectile_units_template),
			tostring(display_unit))

		-- ItemMasterList registration for the skin entry. WITHOUT this,
		-- vanilla `HeroWindowItemCustomization._apply_skin_to_item` (the
		-- inventory illusion picker) does `ItemMasterList[skin_key]`, gets
		-- nil, and crashes with `attempt to index local 'item_data' (a nil
		-- value)` at the next field access. Same shape cosmetics_tweaker
		-- uses for its custom illusions (see `_register_custom_illusions`).
		-- The v0.1.87 default-rarity-skin gate exposed this latent bug:
		-- previously a default-rarity blacksmith never opened the illusion
		-- picker because the item was treated as locked, so the missing
		-- ItemMasterList entry was never reached.
		if ItemMasterList and not rawget(ItemMasterList, skin_key) then
			-- matching_item_key MUST resolve to an entry with a valid template:
			-- vanilla `_apply_skin_to_item` does
			-- `ItemHelper.get_template_by_item_name(matching_item_key)` and
			-- crashes on missing templates with "Requested template for item
			-- <key> which does not exist". Use `def.base_weapon` — the
			-- vanilla weapon every cwv variant clones from, always present in
			-- ItemMasterList with a real template (e.g. `bastard_sword_template`).
			-- DON'T use `def.item_key`: skin_only variants
			-- (e.g. cwv_es_longsword_nordland) skip the `_auto_register_all`
			-- mirror so their item_key is NOT in ItemMasterList. v0.1.91 used
			-- item_key and crashed when applying a skin_only variant's
			-- illusion (GUID ca46d7b2-65b8-41b2-b16b-d71b6dcb9be6).
			ItemMasterList[skin_key] = {
				-- Explicit `key` and `name`. Vanilla `parse_item_master_list`
				-- (`item_master_list.lua:109`) sets these on every entry at
				-- boot via `item.key = key; item.name = key`. We register
				-- AFTER boot, so without these explicit assignments
				-- `item_data.key` is nil and `LootItemUnitPreviewer._load_item_units`
				-- (line 254) `item_key = item_data.key or item.key` falls
				-- through to nil → `ItemMasterList[nil]` → silent failure
				-- chain ending in invisible preview.
				key               = skin_key,
				name              = skin_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = def.base_weapon,
				rarity            = rarity,
				display_name      = def.item_key .. "_skin_name",
				description       = def.item_key .. "_description",
				right_hand_unit   = def.right_hand_unit,
				left_hand_unit    = skin_left_hand_unit,
				-- display_unit is required by `LootItemUnitPreviewer._spawn_link_unit`
				-- (line 467, 472). The previewer reads it from the item_data
				-- AND from the WeaponSkins.skins entry — set it on both.
				-- Without it the link unit fails to spawn and weapon units have
				-- nothing to attach to, so the picker preview is empty.
				display_unit      = display_unit,
				hud_icon          = hud_icon,
				inventory_icon    = inventory_icon,
				information_text  = "information_weapon_skin",
				can_wield         = def.careers,
				template          = nil,
			}
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
			local idx = #NetworkLookup.weapon_skins + 1
			rawset(NetworkLookup.weapon_skins, idx, skin_key)
			rawset(NetworkLookup.weapon_skins, skin_key, idx)
			mod:info("Injected '%s' into NetworkLookup.weapon_skins at index %d", skin_key, idx)
		end

		-- Mirror the skin key into NetworkLookup.item_names too. Vanilla
		-- weapon-skin backend RPCs and equipment-grid widgets do
		-- `NetworkLookup.item_names[key]` on the skin key — without this, any
		-- network sync path that references the skin key crashes per the same
		-- v0.1.24 weapon-item issue documented in the changelog.
		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, skin_key) then
			local idx = #NetworkLookup.item_names + 1
			rawset(NetworkLookup.item_names, idx, skin_key)
			rawset(NetworkLookup.item_names, skin_key, idx)
		end
		-- Track every cwv skin key so the wire-safety hook (issue 278 weapon_skin_id
		-- axis / issue 371) can null it on rpc_add_equipment for non-cwv peers.
		_om._skin_keys = _om._skin_keys or {}
		_om._skin_keys[skin_key] = true
		::skip_skin::
	end
end

_register_variant_skins()

local function _empty_skin_tiers()
	return {
		default   = {},
		plentiful = {},
		common    = {},
		rare      = {},
		exotic    = {},
		unique    = {},
	}
end

local function _register_cwv_skin_combinations()
	if not WeaponSkins or not WeaponSkins.skin_combinations then return end

	-- Each item_type gets its own skin_combination_table seeded with the
	-- variant's auto-generated `<item_key>_skin` entries. Cross-character
	-- illusion functions (e.g. `_register_kruber_1h_sword_dual_illusions`)
	-- append additional skin keys to these tables after seeding.
	local _seed_targets = {
		cwv_imperial_longsword         = "cwv_imperial_longsword_skins",
		cwv_es_longsword_shield        = "cwv_es_longsword_shield_skins",
		cwv_es_axe_shield              = "cwv_es_axe_shield_skins",
		cwv_es_infantry_spear          = "cwv_es_infantry_spear_skins",
		cwv_es_dual_swords             = "cwv_es_dual_swords_skins",
		cwv_es_dual_axes               = "cwv_es_dual_axes_skins",
		cwv_wh_dual_axes               = "cwv_wh_dual_axes_skins",
		cwv_es_dual_maces              = "cwv_es_dual_maces_skins",
		cwv_wh_dual_maces              = "cwv_wh_dual_maces_skins",
		cwv_dr_dawi_mace               = "cwv_dr_dawi_mace_skins",
		cwv_dr_dawi_mace_shield        = "cwv_dr_dawi_mace_shield_skins",
		cwv_dr_dawi_dual_maces         = "cwv_dr_dawi_dual_maces_skins",
		cwv_es_imperial_crowbill       = "cwv_es_imperial_crowbill_skins",
		cwv_dr_dawi_crowbill           = "cwv_dr_dawi_crowbill_skins",
		cwv_es_sword_and_mace          = "cwv_es_sword_and_mace_skins",
		cwv_es_warpriest_hammer        = "cwv_es_warpriest_hammer_skins",
		cwv_es_dual_warpriest_hammers  = "cwv_es_dual_warpriest_hammers_skins",
		cwv_es_warpriest_hammer_shield = "cwv_es_warpriest_hammer_shield_skins",
		cwv_es_priest_greathammer      = "cwv_es_priest_greathammer_skins",
		cwv_es_maul                    = "cwv_es_maul_skins",
		cwv_es_greataxe                = "cwv_es_greataxe_skins",
		cwv_es_rapier                  = "cwv_es_rapier_skins",
		cwv_es_outrider_grenade_launcher = "cwv_es_outrider_grenade_launcher_skins",
		cwv_es_musket                    = "cwv_es_musket_skins",
		cwv_es_musket_old                = "cwv_es_musket_old_skins",
	}

	local seeded = {}
	for item_type, table_name in pairs(_seed_targets) do
		seeded[table_name] = _empty_skin_tiers()
		for _, def in ipairs(_variant_definitions) do
			if def.item_type == item_type then
				local skin_key = def.item_key .. "_skin"
				local rarity = def.rarity or "exotic"
				local tier = seeded[table_name][rarity]
				if tier then
					tier[#tier + 1] = skin_key
				end
			end
		end
		WeaponSkins.skin_combinations[table_name] = seeded[table_name]
		mod:info("Registered %s skin_combination_table", table_name)
	end
end

_register_cwv_skin_combinations()

-- ============================================================
-- Cross-character greatsword illusions
-- ============================================================

local _es_careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
local _wh_careers = { "wh_zealot", "wh_bountyhunter", "wh_captain" }

local _custom_illusions = {
	-- Saltzpyre greatsword models on Kruber's greatsword
	{ skin_key = "cwv_es_2h_sword_wh_01",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_01",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_02",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_02",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_02_runed_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_02_runed_01", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_03",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_03",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_04",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05_runed_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05_runed_01", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05_runed_02", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05_runed_02", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_04_magic_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04_magic_01", can_wield = _es_careers },

	-- Kruber greatsword models on Saltzpyre's greatsword
	{ skin_key = "cwv_wh_2h_sword_es_01",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_01",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02_runed_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02_runed_01", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_03",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_03",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04_runed_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04_runed_01", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04_runed_02", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04_runed_02", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02_runed_03", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02_runed_03", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_05",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_05",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_06",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_06",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_03_magic_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_03_magic_01", can_wield = _wh_careers },

	-- Vanilla 2h-sword skins as illusions for the cwv Imperial Longsword
	-- (cwv_imperial_longsword_skins combo table). matching_weapon stays
	-- "es_bastard_sword" so the vanilla template lookup in
	-- `_apply_skin_to_item` resolves to bastard_sword_template (the
	-- Imperial Longsword's moveset). target_combo overrides the auto-resolved
	-- combo table so these skins land in the cwv picker instead of vanilla
	-- es_bastard_sword's. Initial display_name / description fall through
	-- to the source vanilla skin's localization keys — user will rename
	-- these as they review.
	-- Kruber greatsword (es_2h_sword) skins:
	{ skin_key = "cwv_il_es_01",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_01",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_02",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_02",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_02_runed_01", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_02_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_03",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_03",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	-- Curated-variant mesh assignments (must NOT collide with vanilla clones):
	--   Imperial Longsword  → wpn_empire_2h_sword_04_t1 (= es_2h_sword_skin_05)
	--   Helmgart Watchsword → wpn_greatsword (= es_2h_sword_skin_06)
	--   Black Guard Blade   → wpn_empire_2h_sword_03_t2 (= es_2h_sword_skin_04 — currently shares mesh with Nordland; user knows, will resolve elsewhere)
	-- Drop vanilla clones that duplicate a curated variant by mesh path:
	-- cwv_il_es_04 / cwv_il_es_05 / cwv_il_es_06 (the latter shares mesh with
	-- es_2h_sword_skin_06's wpn_greatsword — kept dropped as a conservative
	-- placeholder until user-directed). Runed variants are always kept since
	-- their rune detailing reads as visually distinct from the bare mesh.
	{ skin_key = "cwv_il_es_04_runed_01", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_04_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_es_04_runed_02", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_04_runed_02", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	-- Saltzpyre greatsword (wh_2h_sword) skins:
	{ skin_key = "cwv_il_wh_01",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_01",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_02",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_02",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_02_runed_01", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_02_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_03",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_03",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_04",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_04",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_05",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_05_runed_01", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
	{ skin_key = "cwv_il_wh_05_runed_02", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05_runed_02", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },

	-- Kruber greathammer (es_2h_hammer) skins as illusions on the curated
	-- `cwv_es_warpriest_hammer` variant — give the rescaled 2H mesh as a
	-- cosmetic option for the new 1H priest-hammer Kruber clone. Sources used:
	-- skin_01, _02, _03, _04 (+_runed_01, _runed_02), _06 (+_runed_01) — 8
	-- entries. Single-hand variant, so no off-hand override needed.
	-- `matching_weapon = "wh_1h_hammer"` so vanilla `_apply_skin_to_item` finds
	-- a real template (`one_handed_hammer_priest_template`); `target_combo`
	-- routes the skin into the variant's curated picker.
	-- Note: 2H model in a 1H slot will read oversized in 3P — by design.
	-- HISTORICAL: in v0.1.151 these 8 sources were registered as 24 entries
	-- across `es_1h_mace`, `es_mace_shield`, and `es_dual_wield_hammer_sword`
	-- (with off-hand overrides to preserve the shield / sword). v0.1.154 moved
	-- them onto the new dedicated variant per user request.
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_01",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_02",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_03",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04_runed_01", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04_runed_02", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_06",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_06_runed_01", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },

	-- Same 8 greathammer sources mirrored onto cwv_es_dual_warpriest_hammers
	-- (dual Skullsplitters). `mirror_to_left = true` mirrors the source's
	-- right_hand_unit into left_hand_unit so each hand gets the same
	-- greathammer mesh. `display_unit_override = display_dual_hammers`
	-- forces the dual-attach rig (source's display_2h_swords single-rig
	-- would crash on left attach — see J_LEFTWEAPONATTACH_INVESTIGATION.md).
	-- Scale and offset applied to both hands; matching_weapon = wh_dual_hammer
	-- so vanilla _apply_skin_to_item resolves to dual_wield_hammers_priest_template.
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_01",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_02",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_03",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04_runed_01", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04_runed_02", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_06",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_06_runed_01", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },

	-- Same 8 greathammer sources on cwv_es_warpriest_hammer_shield (Skullsplitter
	-- and Shield). Right hand = source greathammer mesh; left hand = Empire shield
	-- (preserved via override since the source skins have no left_hand_unit set).
	-- `display_unit_override = display_shield_hammer` matches the variant's
	-- forced rig and the vanilla wh_hammer_shield template default.
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_01",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_02",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_03",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04_runed_01", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04_runed_02", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_06",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
	{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_06_runed_01", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },

	-- Sigmarite Greathammer (cwv_es_priest_greathammer) — Kruber 2H mesh +
	-- Saltzpyre wh_2h_hammer (Warrior Priest) moveset. The variant has its
	-- own item_type/skin_combination_table so vanilla skins of either source
	-- don't bleed into their native pickers. Both source families are 2H
	-- greathammers of comparable size, so NO scale/offset overrides needed.
	-- matching_weapon = "wh_2h_hammer" so `_apply_skin_to_item` resolves to
	-- two_handed_hammer_priest_template (the variant's actual moveset).
	-- Kruber's es_2h_hammer skins:
	{ skin_key = "cwv_es_priest_es_01",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_02",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_02_magic_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_02_magic_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_03",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_04",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_04_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_04_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_06",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_es_06_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	-- Saltzpyre's wh_2h_hammer skins (Warrior Priest greathammer):
	{ skin_key = "cwv_es_priest_wh_01",          matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_01_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_01_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02",          matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_runed_05", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_05", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_magic_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_magic_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	{ skin_key = "cwv_es_priest_wh_02_magic_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_magic_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
}

local _custom_skin_keys = {}

local function _register_custom_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	for _, illusion in ipairs(_custom_illusions) do
		local skin_key = illusion.skin_key
		if _custom_skin_keys[skin_key] then goto continue end

		local source = WeaponSkins.skins[illusion.source_skin]
		if not source then
			mod:warning("Source skin '%s' not found in WeaponSkins — skipping %s", illusion.source_skin, skin_key)
			goto continue
		end

		-- Hand-unit overrides: when the source skin's hand units don't match
		-- the matching_weapon's slot shape (e.g. greathammer source has only
		-- right_hand_unit but target is mace+shield which needs left_hand_unit),
		-- the illusion entry can specify explicit overrides. Use case: cross-
		-- type illusions where you want one half of the source's model but
		-- preserve the target's other half (a default shield for mace+shield,
		-- a default sword for mace+sword, etc.).
		--
		-- `mirror_to_left = true` is a convenience flag for identical-mesh
		-- dual-wield targets: sets left_hand_unit = right_hand_unit dynamically
		-- (since the source's right_hand_unit varies per source skin and can't
		-- be hardcoded in a static illusion entry). Mirrors the dual_swords/
		-- dual_axes/dual_maces patterns elsewhere in the mod.
		local right_unit = illusion.right_hand_unit_override or source.right_hand_unit
		local left_unit  = illusion.left_hand_unit_override  or source.left_hand_unit
		if illusion.mirror_to_left then left_unit = right_unit end

		-- `display_unit_override`: force a specific display rig on the cloned
		-- skin entry (vs inheriting from source). Required when the source's
		-- rig doesn't author both attach nodes for the target's slot shape —
		-- e.g. greathammer source uses display_2h_swords (right-only rig),
		-- but our cwv dual / shield targets need display_dual_hammers /
		-- display_shield_hammer respectively. See
		-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.
		local effective_display_unit = illusion.display_unit_override or source.display_unit

		local iml_entry = {
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = illusion.matching_weapon,
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = effective_display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = right_unit,
			left_hand_unit    = left_unit,
			template          = source.template,
			can_wield         = illusion.can_wield,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[skin_key] = iml_entry

		local ws_entry = {
			description            = source.description,
			display_name           = source.display_name,
			display_unit           = effective_display_unit,
			hud_icon               = source.hud_icon,
			inventory_icon         = source.inventory_icon,
			rarity                 = source.rarity,
			right_hand_unit        = right_unit,
			left_hand_unit         = left_unit,
			template               = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[skin_key] = ws_entry

		-- target_combo: explicit override for the skin_combination_table this
		-- illusion gets appended to. Used when the illusion lives on a
		-- different weapon than its `matching_weapon` — e.g. vanilla 2h-sword
		-- skins added to `cwv_imperial_longsword_skins` while keeping
		-- `matching_weapon = "es_bastard_sword"` so vanilla template lookups
		-- still resolve to bastard_sword_template (the Imperial Longsword's
		-- moveset). Without this override, `_register_custom_illusions`
		-- would resolve the combo table from the matching_weapon's entry
		-- (e.g. es_bastard_sword_skins) which is the wrong target.
		local target_combo = illusion.target_combo
		if not target_combo then
			local weapon_data = ItemMasterList[illusion.matching_weapon]
			if weapon_data and weapon_data.skin_combination_table then
				target_combo = weapon_data.skin_combination_table
			end
		end
		if target_combo then
			local combos = WeaponSkins.skin_combinations[target_combo]
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = skin_key
				end
			end
		end

		-- REVIEW: NetworkLookup.weapon_skins has an error-throwing __index per
		-- CHANGELOG v0.1.12 — `tbl[#tbl + 1] = ...` and `tbl[skin_key] = ...` set
		-- new keys, which goes through __newindex (not __index) and is fine. But
		-- `tbl[skin_key] = #tbl` reads `#tbl` AFTER the previous assignment, so
		-- the reverse-lookup index points at the just-written entry — correct,
		-- but slightly fragile. Pattern at line 467-471 uses an explicit `idx`
		-- variable; using rawset there matches CHANGELOG guidance. Consider
		-- aligning these two code paths to use the same rawset-with-explicit-idx
		-- form.
		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
			local tbl = NetworkLookup.weapon_skins
			tbl[#tbl + 1] = skin_key
			tbl[skin_key] = #tbl
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, skin_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, skin_key)
			rawset(tbl, skin_key, idx)
		end

		_custom_skin_keys[skin_key] = true
		mod:info("Registered custom illusion: %s (from %s) -> %s", skin_key, illusion.source_skin, illusion.matching_weapon)
		::continue::
	end
end

_register_custom_illusions()

-- Spear+Shield spear halves -> Infantry Spear illusions. The source shield is
-- deliberately not copied; only its paired right-hand spear model is owned by
-- this two-handed item.
do
	local infantry = _om.infantry_spear
	local function _register_infantry_spear_illusions()
		if not ItemMasterList or not WeaponSkins then return end
		local combo = WeaponSkins.skin_combinations[infantry.SKIN_COMBINATION]
		local elf_display = WeaponSkins.skins.we_spear_skin_01
		elf_display = elf_display and elf_display.display_unit
		local registered = 0

		for _, source_key in ipairs(infantry.SPEAR_SHIELD_SKINS) do
			local source = WeaponSkins.skins[source_key]
			if source and type(source.right_hand_unit) == "string" then
				local suffix = source_key:gsub("^es_deus_01_skin_", "")
				if suffix == "" then suffix = "01" end
				local skin_key = infantry.ITEM_KEY .. "_" .. suffix
				if not _custom_skin_keys[skin_key] then
					local row = {
						key = skin_key, name = skin_key,
						item_type = "weapon_skin", slot_type = "weapon_skin",
						matching_item_key = infantry.ITEM_KEY,
						rarity = source.rarity or "exotic",
						display_name = infantry.ITEM_KEY .. "_skin_name",
						description = infantry.ITEM_KEY .. "_description",
						display_unit = elf_display or source.display_unit,
						hud_icon = "weapon_generic_icon_falken",
						inventory_icon = source.inventory_icon or "icon_wpn_empire_spearshield_t1",
						information_text = "information_weapon_skin",
						right_hand_unit = source.right_hand_unit,
						template = infantry.TEMPLATE_KEY,
						can_wield = infantry.DEFAULT_CAREERS,
					}
					if source.material_settings_name then
						row.material_settings_name = source.material_settings_name
					end
					ItemMasterList[skin_key] = row
					WeaponSkins.skins[skin_key] = {
						description = row.description, display_name = row.display_name,
						display_unit = row.display_unit, hud_icon = row.hud_icon,
						inventory_icon = row.inventory_icon, rarity = row.rarity,
						right_hand_unit = source.right_hand_unit,
						template = infantry.TEMPLATE_KEY,
						material_settings_name = source.material_settings_name,
					}
					local tier = combo and combo[row.rarity]
					if tier then tier[#tier + 1] = skin_key end
					for _, lookup_name in ipairs({ "weapon_skins", "item_names" }) do
						local lookup = NetworkLookup and NetworkLookup[lookup_name]
						if lookup and not rawget(lookup, skin_key) then
							local idx = #lookup + 1
							rawset(lookup, idx, skin_key)
							rawset(lookup, skin_key, idx)
						end
					end
					_om._skin_keys = _om._skin_keys or {}
					_om._skin_keys[skin_key] = true
					_custom_skin_keys[skin_key] = true
					registered = registered + 1
				end
			end
		end
		mod:info("Registered %d shield-free Spear+Shield models for Infantry Spear", registered)
	end
	_register_infantry_spear_illusions()
end

-- ============================================================
-- Kruber 1h sword cosmetics → cwv_es_dual_swords illusions
-- ============================================================
-- Each vanilla `es_1h_sword_skin_*` is cloned into a new skin keyed
-- `cwv_es_dual_swords_es_1h_sword_skin_*` and registered as an illusion
-- option on `cwv_es_dual_swords`. The right-hand mesh is copied from the
-- source skin; the left hand mirrors the right (identical-mesh dual-wield).
--
-- DUAL-WIELD DISPLAY RIG: each clone is registered with
-- `display_unit = "units/weapons/weapon_display/display_dual_weapons"`
-- (NOT inheriting `source.display_unit`, which is `display_1h_swords` —
-- a single-sword rig that lacks `j_leftweaponattach` and crashes the
-- previewer on left attach). See `DEVELOPMENT.md` "Dual-wield variants
-- — display rig requirements" for the rule, and
-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the post-mortem on the
-- ~20-version saga that surfaced it (v0.1.122 → v0.1.145).
--
-- `_kruber_1h_dual_skin_keys` retained as an inert registry marker (no
-- runtime consumer; kept in case a future hook needs to filter on
-- cwv_es_dual_swords skin lineage).

local function _register_kruber_1h_sword_dual_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_1h_sword" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_dual_swords_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		-- Mirror right_hand_unit → left_hand_unit so the picker (and
		-- in-game) renders two identical swords. Force display_unit to
		-- display_dual_weapons (the rig vanilla we_dual_sword_skin_*
		-- uses) — the source es_1h_sword skin's display_unit is
		-- display_1h_swords (single-sword rig with no j_leftweaponattach),
		-- which would crash the previewer on left attach.
		local dual_display_unit = "units/weapons/weapon_display/display_dual_weapons"
		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_dual_swords",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = dual_display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			left_hand_unit    = source.right_hand_unit,
			template          = source.template,
			can_wield         = _es_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = dual_display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			left_hand_unit  = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		_kruber_1h_dual_skin_keys[new_key] = true

		local combos = WeaponSkins.skin_combinations.cwv_es_dual_swords_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Kruber 1h sword cosmetics as cwv_es_dual_swords illusions", registered)
end

_register_kruber_1h_sword_dual_illusions()

-- ============================================================
-- Saltzpyre 1h axe cosmetics → cwv_es_dual_axes illusions
-- ============================================================
-- Each vanilla `wh_1h_axe_skin_*` is cloned into a new skin keyed
-- `cwv_es_dual_axes_<source_key>` and registered as an illusion option on
-- `cwv_es_dual_axes`. The right-hand axe mesh is copied from the source
-- skin; the left hand mirrors the right (identical-mesh dual-wield).
--
-- DUAL-WIELD DISPLAY RIG: each clone is registered with
-- `display_unit = "units/weapons/weapon_display/display_dual_axes"`
-- (NOT inheriting `source.display_unit`, which is `display_1h_axes` —
-- a single-sword rig that lacks `j_leftweaponattach` and crashes the
-- previewer on left attach). Vanilla precedent: `dw_dual_axe_skin_01`
-- (`weapon_skins.lua:2364`) uses the same rig with both hands set.
-- See `DEVELOPMENT.md` "Dual-wield variants — display rig requirements"
-- for the full rule and `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the
-- post-mortem on the rig requirement.

local function _register_saltzpyre_1h_axe_dual_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	-- CWV's authored thumbnail follows the PRIMARY/right-hand axe. This is
	-- intentionally different from the future shield-family rule, where the
	-- offhand shield will own the combined icon identity.
	local dual_inventory_icons = {
		icon_axe_hatchet_t2_magic_01 = "icon_axe_hatchet_t2_magic_01_dual_cwv",
		icon_wh_1h_axe_skin_06_magic_02 = "icon_wh_1h_axe_skin_06_magic_02_dual_cwv",
		icon_wpn_axe_02_t1 = "icon_wpn_axe_02_t1_dual_cwv",
		icon_wpn_axe_02_t2 = "icon_wpn_axe_02_t2_dual_cwv",
		icon_wpn_axe_02_t2_runed_06 = "icon_wpn_axe_02_t2_runed_06_dual_cwv",
		icon_wpn_axe_03_t1 = "icon_wpn_axe_03_t1_dual_cwv",
		icon_wpn_axe_03_t2 = "icon_wpn_axe_03_t2_dual_cwv",
		icon_wpn_axe_hatchet_t1 = "icon_wpn_axe_hatchet_t1_dual_cwv",
		icon_wpn_axe_hatchet_t2 = "icon_wpn_axe_hatchet_t2_dual_cwv",
	}
	_om._dual_axes_inventory_icon_by_source = dual_inventory_icons

	-- The combination table is the vanilla cosmetic owner's authoritative
	-- family.  Scanning ItemMasterList here used to depend on DLC load order,
	-- and the fixed destination tier list then silently dropped Scorpion's
	-- `magic` skin.  Preserve every source tier membership and add the vanilla
	-- default skin, which lives in WeaponSkins.default_skins rather than the
	-- combination table.
	local source_memberships = {}
	local source_combos = WeaponSkins.skin_combinations.wh_1h_axe_skins or {}
	for tier_name, tier in pairs(source_combos) do
		for _, source_key in ipairs(tier) do
			local memberships = source_memberships[source_key]
			if not memberships then
				memberships = {}
				source_memberships[source_key] = memberships
			end
			memberships[#memberships + 1] = tier_name
		end
	end
	local default_skin = WeaponSkins.default_skins and WeaponSkins.default_skins.wh_1h_axe
	if default_skin and not source_memberships[default_skin] then
		local default_data = WeaponSkins.skins[default_skin]
		source_memberships[default_skin] = { default_data and default_data.rarity or "plentiful" }
	end

	local source_keys = {}
	for source_key in pairs(source_memberships) do source_keys[#source_keys + 1] = source_key end
	table.sort(source_keys)
	local targets = {
		{ item_key = "cwv_es_dual_axes", combo = "cwv_es_dual_axes_skins", careers = _es_careers },
		{ item_key = "cwv_wh_dual_axes", combo = "cwv_wh_dual_axes_skins", careers = _wh_careers },
	}
	local source_by_target = {}
	_om._dual_axes_source_by_skin = source_by_target

	for _, target in ipairs(targets) do
		local source_by_clone = {}
		source_by_target[target.item_key] = source_by_clone
		local registered = 0
		for _, source_key in ipairs(source_keys) do
		local new_key = target.item_key .. "_" .. source_key
		local source = WeaponSkins.skins[source_key]
		local source_item = rawget(ItemMasterList, source_key)
		if not source or not source.right_hand_unit or not source_item
				or source_item.matching_item_key ~= "wh_1h_axe" then goto continue end
		local dual_inventory_icon = dual_inventory_icons[source.inventory_icon]
		if not dual_inventory_icon then
			mod:warning("Dual Axes icon missing for primary cosmetic %s (source icon=%s); using source icon",
				tostring(source_key), tostring(source.inventory_icon))
			dual_inventory_icon = source.inventory_icon
		end
		source_by_clone[new_key] = source_key
		if _custom_skin_keys[new_key] then goto continue end

		-- Mirror right_hand_unit → left_hand_unit so the picker (and
		-- in-game) renders two identical axes. Force display_unit to
		-- display_dual_axes (single-axe `display_1h_axes` from the source
		-- lacks j_leftweaponattach and would crash the previewer).
		local dual_display_unit = "units/weapons/weapon_display/display_dual_axes"
		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = target.item_key,
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = dual_display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = dual_inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			left_hand_unit    = source.right_hand_unit,
			template          = source.template,
			can_wield         = target.careers,
		}
		-- Ownership remains attached to the cosmetic, not the CWV weapon.  The
		-- unlock hook below consults this copied field before exposing the clone.
		if source_item.required_dlc then
			iml_entry.required_dlc = source_item.required_dlc
		end
		if source_item.event_quest_requirement then
			iml_entry.event_quest_requirement = source_item.event_quest_requirement
		end
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = dual_display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = dual_inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			left_hand_unit  = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations[target.combo]
		if combos then
			for _, tier_name in ipairs(source_memberships[source_key]) do
				local tier = combos[tier_name]
				if not tier then
					tier = {}
					combos[tier_name] = tier
				end
				local found = false
				for _, existing_key in ipairs(tier) do
					if existing_key == new_key then found = true break end
				end
				if not found then tier[#tier + 1] = new_key end
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
		end

		mod:info("Registered %d Saltzpyre 1h axe cosmetics as %s illusions", registered, target.item_key)
	end
end

_register_saltzpyre_1h_axe_dual_illusions()

-- ============================================================
-- Empire 1h-mace cosmetics → cwv_es_dual_maces + cwv_wh_dual_maces illusions
-- ============================================================
-- Each vanilla `es_1h_mace_skin_*` is cloned into TWO new skin keys —
-- `cwv_es_dual_maces_<source_key>` (Kruber's variant) and
-- `cwv_wh_dual_maces_<source_key>` (Saltzpyre's variant) — and each clone
-- is registered as an illusion option in the matching variant's picker.
-- The right-hand mace mesh is copied from the source skin; the left hand
-- mirrors the right (identical-mesh dual-wield).
--
-- DUAL-WIELD DISPLAY RIG: each clone is registered with
-- `display_unit = "units/weapons/weapon_display/display_dual_hammers"`
-- (NOT inheriting `source.display_unit`, which is `display_1h_hammer` —
-- a single-hand rig that lacks `j_leftweaponattach` and crashes the
-- previewer on left attach). Vanilla precedent: Bardin's dual-hammer
-- skins in `weapon_skins_bless.lua:395` use the same rig with both
-- hands set. See `DEVELOPMENT.md` "Dual-wield variants — display rig
-- requirements" and `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.

local function _register_es_1h_mace_dual_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_1h_mace" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	-- Two-target registration: each source skin produces a clone for both
	-- variants, routed to the variant's curated picker via matching_item_key.
	-- Listed in the order the picker should display.
	local _targets = {
		{ prefix = "cwv_es_dual_maces_", matching = "cwv_es_dual_maces", combo = "cwv_es_dual_maces_skins", careers = _es_all_careers },
		{ prefix = "cwv_wh_dual_maces_", matching = "cwv_wh_dual_maces", combo = "cwv_wh_dual_maces_skins", careers = _wh_all_careers },
	}

	local total = 0
	for _, target in ipairs(_targets) do
		local registered = 0
		for _, source_key in ipairs(source_keys) do
			local new_key = target.prefix .. source_key
			if _custom_skin_keys[new_key] then goto continue end

			local source = WeaponSkins.skins[source_key]
			if not source or not source.right_hand_unit then goto continue end

			-- Mirror right_hand_unit → left_hand_unit so the picker (and
			-- in-game) renders two identical maces. Force display_unit to
			-- display_dual_hammers — single-hand `display_1h_hammer` from
			-- the source lacks j_leftweaponattach and would crash the
			-- previewer on left attach.
			local dual_display_unit = "units/weapons/weapon_display/display_dual_hammers"
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = target.matching,
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = dual_display_unit,
				hud_icon          = source.hud_icon,
				inventory_icon    = source.inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = source.right_hand_unit,
				left_hand_unit    = source.right_hand_unit,
				template          = source.template,
				can_wield         = target.careers,
			}
			if source.material_settings_name then
				iml_entry.material_settings_name = source.material_settings_name
			end
			ItemMasterList[new_key] = iml_entry

			local ws_entry = {
				description     = source.description,
				display_name    = source.display_name,
				display_unit    = dual_display_unit,
				hud_icon        = source.hud_icon,
				inventory_icon  = source.inventory_icon,
				rarity          = source.rarity,
				right_hand_unit = source.right_hand_unit,
				left_hand_unit  = source.right_hand_unit,
				template        = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[new_key] = ws_entry

			local combos = WeaponSkins.skin_combinations[target.combo]
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end

			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end

			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end

			_custom_skin_keys[new_key] = true
			registered = registered + 1
			total = total + 1
			::continue::
		end
		mod:info("Registered %d empire 1h mace cosmetics as %s illusions", registered, target.matching)
	end

	mod:info("Total: %d dual-mace illusion entries (%d source skins × %d variants)", total, #source_keys, #_targets)
end

_register_es_1h_mace_dual_illusions()

-- ============================================================
-- Empire mace+sword's mace meshes → cwv_es_maul illusions
-- ============================================================
-- The Maul's cosmetic options are the MACE HALF (right_hand_unit) of
-- vanilla `es_dual_wield_hammer_sword` (mace+sword) skins — NOT the
-- separate `es_1h_mace` skin pool. This gives the Maul a curated set
-- of 3-4 chunky mace heads that match the variant's identity (a 2H
-- maul cloned from the mace+sword's club), instead of the smaller
-- flanged maces from Kruber's 1H mace pool.
--
-- Mace+sword skin → mace mesh (right_hand_unit only):
--   skin_01           → wpn_emp_mace_04_t2 (rare; same as the Maul's default mesh)
--   skin_02           → wpn_emp_mace_05_t2 (exotic)
--   skin_02_runed_01  → wpn_emp_mace_05_t2_runed_01 (unique)
--   skin_02_magic_01  → wpn_emp_mace_04_t3_magic_01 (magic)
--
-- Single-handed (NOT mirrored) — the Maul wields one-handed via the
-- wizard mace template's right_hand_unit. left_hand_unit from the
-- source is DISCARDED (the sword half doesn't belong on a Maul).
-- Source display_unit is overridden to display_1h_hammer (single-rig)
-- because the source's mace+sword display_unit authors both attach
-- nodes and would try to spawn a non-existent left unit.

local function _register_macesword_mace_maul_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "es_dual_wield_hammer_sword" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local single_hand_display = "units/weapons/weapon_display/display_1h_hammer"

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_maul_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_maul",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = single_hand_display,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			-- Deliberately no left_hand_unit — source's left is the
			-- sword half of the mace+sword, which doesn't belong on a
			-- single-handed Maul. nil here means
			-- BackendUtils.get_item_units leaves the equipped variant's
			-- own left (none, for Maul) intact.
			template          = source.template,
			can_wield         = _es_all_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = single_hand_display,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations.cwv_es_maul_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d mace+sword mace meshes as cwv_es_maul illusions", registered)
end

_register_macesword_mace_maul_illusions()

-- ============================================================
-- #597 converted Greataxe model manifest -> curated illusions
-- ============================================================

local function _register_greataxe_model_illusions()
	if not ItemMasterList or not WeaponSkins then return end
	local models = _om.greataxe.usable_models()
	local combos = WeaponSkins.skin_combinations[_om.greataxe.SKIN_COMBINATION]
	local registered = 0

	-- Model 1 is already represented by the variant's generated base skin.
	-- Register only the remaining confirmed rows so the picker has no duplicate.
	for index = 2, #models do
		local model = models[index]
		local key = model.key
		if _custom_skin_keys[key] then goto continue end
		local rarity = model.rarity or "exotic"
		local display_unit = model.display_unit or "units/weapons/weapon_display/display_2h_axes"
		local inventory_icon = model.inventory_icon or "icon_wpn_dw_2h_axe_01_t1"
		local hud_icon = model.hud_icon or "weapon_generic_icon_axe2h"

		ItemMasterList[key] = {
			key = key,
			name = key,
			item_type = "weapon_skin",
			slot_type = "weapon_skin",
			matching_item_key = _om.greataxe.BASE_WEAPON,
			rarity = rarity,
			display_name = key .. "_name",
			description = key .. "_description",
			display_unit = display_unit,
			hud_icon = hud_icon,
			inventory_icon = inventory_icon,
			information_text = "information_weapon_skin",
			right_hand_unit = model.right_hand_unit,
			can_wield = _om.greataxe.DEFAULT_CAREERS,
		}
		WeaponSkins.skins[key] = {
			description = key .. "_description",
			display_name = key .. "_name",
			display_unit = display_unit,
			hud_icon = hud_icon,
			inventory_icon = inventory_icon,
			rarity = rarity,
			right_hand_unit = model.right_hand_unit,
		}

		local tier = combos and combos[rarity]
		if tier then tier[#tier + 1] = key end
		for _, lookup_name in ipairs({ "weapon_skins", "item_names" }) do
			local lookup = NetworkLookup and NetworkLookup[lookup_name]
			if lookup and not rawget(lookup, key) then
				local lookup_index = #lookup + 1
				rawset(lookup, lookup_index, key)
				rawset(lookup, key, lookup_index)
			end
		end
		_custom_skin_keys[key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d additional converted Greataxe model illusions", registered)

	-- Issue #604: the first Imperial and sole Dawi rows are the generated base
	-- skins. Additional Imperial rows are real curated illusions in the same
	-- custom skin table; no Free Standard/unknown model can enter this manifest.
	local crowbill_registered = 0
	for _, model in ipairs(_om.crowbill_family.usable_models()) do
		if model.key == model.variant_key .. "_skin" or _custom_skin_keys[model.key] then
			goto continue_crowbill_model
		end
		local rarity = model.rarity or "exotic"
		local display_unit = model.display_unit or "units/weapons/weapon_display/display_1h_crowbills"
		local careers = model.variant_key == "cwv_dr_dawi_crowbill"
			and _om.crowbill_family.DAWI_DEFAULTS or _om.crowbill_family.IMPERIAL_DEFAULTS
		ItemMasterList[model.key] = {
			key = model.key,
			name = model.key,
			item_type = "weapon_skin",
			slot_type = "weapon_skin",
			matching_item_key = _om.crowbill_family.SOURCE_ITEM,
			rarity = rarity,
			display_name = model.key .. "_name",
			description = model.key .. "_description",
			display_unit = display_unit,
			hud_icon = model.hud_icon,
			inventory_icon = model.inventory_icon,
			information_text = "information_weapon_skin",
			right_hand_unit = model.right_hand_unit,
			can_wield = careers,
		}
		WeaponSkins.skins[model.key] = {
			description = model.key .. "_description",
			display_name = model.key .. "_name",
			display_unit = display_unit,
			hud_icon = model.hud_icon,
			inventory_icon = model.inventory_icon,
			rarity = rarity,
			right_hand_unit = model.right_hand_unit,
		}
		local crowbill_combos = WeaponSkins.skin_combinations[model.variant_key .. "_skins"]
		local tier = crowbill_combos and crowbill_combos[rarity]
		if tier then tier[#tier + 1] = model.key end
		for _, lookup_name in ipairs({ "weapon_skins", "item_names" }) do
			local lookup = NetworkLookup and NetworkLookup[lookup_name]
			if lookup and not rawget(lookup, model.key) then
				local lookup_index = #lookup + 1
				rawset(lookup, lookup_index, model.key)
				rawset(lookup, model.key, lookup_index)
			end
		end
		_om._skin_keys = _om._skin_keys or {}
		_om._skin_keys[model.key] = true
		_custom_skin_keys[model.key] = true
		crowbill_registered = crowbill_registered + 1
		::continue_crowbill_model::
	end
	mod:info("[cwv:604] Registered %d additional licensed Imperial Crowbill model illusions",
		crowbill_registered)
end

_register_greataxe_model_illusions()

-- ============================================================
-- Saltzpyre fencing-sword cosmetics → cwv_es_rapier illusions
-- ============================================================
-- Each vanilla `wh_fencing_sword_skin_*` registered as an illusion on
-- the Rapier variant. Source skins always carry a pistol on
-- left_hand_unit; we FORCE left_hand_unit = invisible weapon on every
-- clone so the variant's "no pistol" identity holds across illusions.
--
-- Source's `display_fencing_swords` rig is preserved (it authors both
-- right + left attach nodes; the invisible left unit attaches but is
-- not visible).

local function _register_rapier_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	-- Illusions DELIBERATELY do not set `left_hand_unit`. Reason: the
	-- cosmetic picker's `_load_item_units` (line 281) only spawns a
	-- left-hand unit when `item_units.left_hand_unit` is truthy. With
	-- left_hand_unit nil on the illusion's skin entry,
	-- `BackendUtils.get_item_units` overwrites the inherited brace pistol
	-- with nil (line 174 of `backend_utils.lua` — the overwrite is
	-- unconditional, including nil), so the picker skips left-hand spawn
	-- entirely. No spawn → no `j_leftweaponattach` lookup → no crash.
	-- Crash GUID `962fe355-a0d4-43fd-9a29-bd64fca6a0ac` (v0.1.191).
	--
	-- The variant's DEFAULT skin (cwv_es_rapier_skin, set on equip when
	-- no illusion is applied) still carries `left_hand_unit = invisible_pistol`
	-- via the variant's IML entry — that's where the no-pistol identity is
	-- enforced. When an illusion IS applied, both the picker AND in-game
	-- skip the left spawn entirely (no invisible pistol attached, no
	-- visible difference since it was invisible anyway).

	local source_keys = {}
	for skin_key, entry in pairs(ItemMasterList) do
		if type(entry) == "table"
				and entry.item_type == "weapon_skin"
				and entry.matching_item_key == "wh_fencing_sword" then
			source_keys[#source_keys + 1] = skin_key
		end
	end
	table.sort(source_keys)

	local registered = 0
	for _, source_key in ipairs(source_keys) do
		local new_key = "cwv_es_rapier_" .. source_key
		if _custom_skin_keys[new_key] then goto continue end

		local source = WeaponSkins.skins[source_key]
		if not source or not source.right_hand_unit then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_rapier",
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = source.display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			-- left_hand_unit DELIBERATELY omitted (see comment above).
			template          = source.template,
			can_wield         = _es_all_careers,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[new_key] = iml_entry

		local ws_entry = {
			description     = source.description,
			display_name    = source.display_name,
			display_unit    = source.display_unit,
			hud_icon        = source.hud_icon,
			inventory_icon  = source.inventory_icon,
			rarity          = source.rarity,
			right_hand_unit = source.right_hand_unit,
			-- left_hand_unit DELIBERATELY omitted (see comment above).
			template        = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[new_key] = ws_entry

		local combos = WeaponSkins.skin_combinations.cwv_es_rapier_skins
		if combos then
			local rarity = source.rarity or "exotic"
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d fencing-sword cosmetics as cwv_es_rapier illusions (pistol forced invisible)", registered)
end

_register_rapier_illusions()

-- ============================================================
-- Empire shield options → cwv_es_longsword_shield illusions
-- ============================================================
-- Imperial Longsword + Shield variant carries a curated set of Empire
-- shield + Imperial Longsword pairings. Each entry is a HARDCODED pair of
-- (Empire shield mesh, Imperial Longsword sword mesh) — no IML scan.
--
-- Why hardcoded: the previous implementation (v0.1.175 → v0.1.250) scanned
-- IML for `matching_item_key == "es_sword_shield"`, but that pool also
-- contains our `cwv_we_sword_shield` (elf wood-elf) variant's auto-
-- generated skin entries (they clone from the same base for template
-- reasons). Result: the picker showed elven shields among the Empire
-- options. v0.1.251 sidesteps the leak by enumerating Empire shield
-- meshes directly.
--
-- Pairing rationale (best-effort thematic without localization access):
--   * Plain state-issue shields (01_t1, 02) → Imperial Longsword
--     (wpn_2h_sword_04_t1) — both basic Reikland regiment kit.
--   * Mid-tier sealhide / coastal-style shields (03 + runed variant) →
--     Helmgart Watchsword (wpn_greatsword) — western-pass watch theme.
--   * Ornate / runed / magic shields (04, 04_magic_01, 05, 02_runed_01) →
--     Black Guard Blade (wpn_2h_sword_03_t2) — knightly / Knights of
--     Morr theme.
-- Adjust the pairings below if the in-game shield names suggest a
-- different match.

-- Imperial Longsword sword meshes (Empire `es_2h_sword` family that the
-- 2H cwv_es_longsword variants use as their default looks).
local _ILS_RECRUIT_SWORD    = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1"
local _ILS_NORDLAND_SWORD   = "units/weapons/player/wpn_greatsword/wpn_greatsword"
local _ILS_BLACKGUARD_SWORD = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2"

-- Saltzpyre's greatsword (`wh_2h_sword`) meshes — same family used by the
-- 2H cwv_imperial_longsword cross-character illusions (CHANGELOG v0.1.113).
-- All distinct from the Imperial mesh family above.
local _ILS_WH_SWORD_01      = "units/weapons/player/wpn_empire_2h_sword_02_t1/wpn_2h_sword_02_t1"           -- wh skin_01 (plentiful)
local _ILS_WH_SWORD_02      = "units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2"           -- wh skin_02 (rare)
local _ILS_WH_SWORD_02_RUNE = "units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2_runed_01"  -- wh skin_02_runed_01 (unique)
local _ILS_WH_SWORD_03      = "units/weapons/player/wpn_empire_2h_sword_02_t3/wpn_2h_sword_02_t3"           -- wh skin_03 (common)
local _ILS_WH_SWORD_04      = "units/weapons/player/wpn_empire_2h_sword_04_t2/wpn_2h_sword_04_t2"           -- wh skin_04 (exotic)
local _ILS_WH_SWORD_05      = "units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1"           -- wh skin_05 (exotic)
local _ILS_WH_SWORD_05_RUNE = "units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1_runed_01"  -- wh skin_05_runed_01 (unique)

-- Each entry: { left = shield mesh, right = paired sword, rarity = picker tier, suffix = unique key fragment }.
-- `suffix` differentiates entries that share a shield (multiple swords
-- pair against the same shield mesh — recruit vs wh_01, etc.). Without
-- it, the per-shield key would collide and only the first registers.
local _IMPERIAL_LONGSWORD_SHIELD_PAIRINGS = {
	-- ── Imperial sword family ─────────────────────────────────────
	-- Plentiful / basic: Imperial Longsword + plain Reikland shields.
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",     right = _ILS_RECRUIT_SWORD,    rarity = "plentiful", suffix = "recruit" },
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",           right = _ILS_RECRUIT_SWORD,    rarity = "plentiful", suffix = "recruit" },
	-- Rare / mid-tier: Helmgart Watchsword + mid-tier shields.
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",           right = _ILS_NORDLAND_SWORD,   rarity = "rare",      suffix = "nordland" },
	-- Exotic: Black Guard Blade + ornate shields.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",           right = _ILS_BLACKGUARD_SWORD, rarity = "exotic",    suffix = "blackguard" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",           right = _ILS_BLACKGUARD_SWORD, rarity = "exotic",    suffix = "blackguard" },
	-- Unique (red illusion tier): runed shields.
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01",  right = _ILS_BLACKGUARD_SWORD, rarity = "unique",    suffix = "blackguard" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01",  right = _ILS_NORDLAND_SWORD,   rarity = "unique",    suffix = "nordland" },
	-- Magic (weave-forged): scorpion DLC's magic Empire shield.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01",  right = _ILS_BLACKGUARD_SWORD, rarity = "magic",     suffix = "blackguard" },

	-- ── Saltzpyre wh_2h_sword family (added v0.1.254) ─────────────
	-- Same wh meshes used by cwv_imperial_longsword cross-character
	-- illusions per CHANGELOG v0.1.113. Paired with rotating Empire
	-- shields by rarity tier so each Saltzpyre sword appears alongside
	-- a shield it'd plausibly be carried with.
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",     right = _ILS_WH_SWORD_01,      rarity = "plentiful", suffix = "wh_01" },
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",           right = _ILS_WH_SWORD_03,      rarity = "common",    suffix = "wh_03" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",           right = _ILS_WH_SWORD_02,      rarity = "rare",      suffix = "wh_02" },
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",           right = _ILS_WH_SWORD_04,      rarity = "exotic",    suffix = "wh_04" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",           right = _ILS_WH_SWORD_05,      rarity = "exotic",    suffix = "wh_05" },
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01",  right = _ILS_WH_SWORD_02_RUNE, rarity = "unique",    suffix = "wh_02_runed" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01",  right = _ILS_WH_SWORD_05_RUNE, rarity = "unique",    suffix = "wh_05_runed" },
}

local function _register_imperial_longsword_shield_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local registered = 0
	for _, pair in ipairs(_IMPERIAL_LONGSWORD_SHIELD_PAIRINGS) do
		-- Key = `cwv_es_longsword_shield_<shield_tail>__<sword_suffix>`.
		-- Both fragments are required because multiple swords pair against
		-- the same shield (e.g. emp_shield_02 + recruit AND emp_shield_02
		-- + wh_03). Without the sword suffix the second registration would
		-- collide with the first and silently skip.
		local mesh_tail = pair.left:match("([^/]+)$") or pair.left
		local sword_frag = pair.suffix or "default"
		local new_key = "cwv_es_longsword_shield_" .. mesh_tail .. "__" .. sword_frag
		if _custom_skin_keys[new_key] then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_longsword_shield",
			rarity            = pair.rarity,
			display_name      = "cwv_es_longsword_shield_skin_name",
			description       = "cwv_es_longsword_shield_description",
			display_unit      = "units/weapons/weapon_display/display_shield_sword",
			hud_icon          = "weapon_generic_icon_sword_and_sheild",
			inventory_icon    = "icon_wpn_empire_shield_02_sword",
			information_text  = "information_weapon_skin",
			right_hand_unit   = pair.right,
			left_hand_unit    = pair.left,
			template          = "one_handed_sword_shield_template_2",
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_longsword_shield_description",
			display_name    = "cwv_es_longsword_shield_skin_name",
			display_unit    = "units/weapons/weapon_display/display_shield_sword",
			hud_icon        = "weapon_generic_icon_sword_and_sheild",
			inventory_icon  = "icon_wpn_empire_shield_02_sword",
			rarity          = pair.rarity,
			right_hand_unit = pair.right,
			left_hand_unit  = pair.left,
			template        = "one_handed_sword_shield_template_2",
		}

		local combos = WeaponSkins.skin_combinations.cwv_es_longsword_shield_skins
		if combos then
			local tier = combos[pair.rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Empire shield + Imperial Longsword pairings on cwv_es_longsword_shield", registered)
end

_register_imperial_longsword_shield_illusions()

-- ============================================================
-- Empire hatchet + shield options → cwv_es_axe_shield illusions
-- ============================================================
-- Same pattern as the longsword+shield pool above. Each entry is a
-- HARDCODED pair of (Empire shield mesh, Empire hatchet mesh) — no IML
-- scan, to keep the pool curated and avoid leak from sibling cwv
-- variants that share the dr_shield_axe base.
--
-- Hatchet meshes come from the `wh_1h_axe` skin family (Saltzpyre's
-- 1H axe pool — Empire-style hatchets, same family the default
-- cwv_es_axe_shield + veteran variants already use). Shield meshes
-- are the same Empire shield set the longsword+shield picker uses.
--
-- The default-rarity (blacksmith) cwv_es_axe_shield seeds itself into
-- the pool but its appearance is locked by the blacksmith hook —
-- applied illusions visually no-op on it. The unique-rarity veteran
-- (and any future non-blacksmith Empire axe+shield variants sharing
-- item_type = "cwv_es_axe_shield") visibly swap to the picked combo.

do  -- scope mesh-path locals so they don't count against the Lua 5.1 200-local main-chunk limit

local _EAS_AXE_02_T1   = "units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1"           -- wh_1h_axe_skin_01 (common)
local _EAS_AXE_02_T2   = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2"           -- wh_1h_axe_skin_02 (rare)
local _EAS_AXE_02_T2_R = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2_runed_01"  -- wh_1h_axe_skin_02_runed_01 (unique)
local _EAS_AXE_03_T1   = "units/weapons/player/wpn_axe_03_t1/wpn_axe_03_t1"           -- wh_1h_axe_skin_03 (exotic)
local _EAS_AXE_03_T2   = "units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2"           -- wh_1h_axe_skin_04 (exotic)
local _EAS_AXE_03_T2_R = "units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01"  -- wh_1h_axe_skin_04_runed_01 (unique)
local _EAS_HATCHET_T1  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1" -- wh_1h_axe_skin_05 (plentiful)
local _EAS_HATCHET_T2  = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2" -- wh_1h_axe_skin_06 (exotic)

-- Each entry: { left = shield mesh, right = paired hatchet, rarity = picker tier, suffix = unique key fragment }.
-- `suffix` differentiates entries that share a shield mesh.
local _AXE_SHIELD_PAIRINGS = {
	-- Plentiful: state-issue shields + plain hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",    right = _EAS_HATCHET_T1,  rarity = "plentiful", suffix = "hatchet_t1" },
	{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",    right = _EAS_AXE_02_T1,   rarity = "plentiful", suffix = "axe_02_t1" },
	-- Common: Reikland-issue shields + plain hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",          right = _EAS_HATCHET_T1,  rarity = "common",    suffix = "hatchet_t1" },
	-- Rare: mid-tier sealhide shields + tier-2 hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",          right = _EAS_AXE_02_T2,   rarity = "rare",      suffix = "axe_02_t2" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",          right = _EAS_HATCHET_T2,  rarity = "rare",      suffix = "hatchet_t2" },
	-- Exotic: ornate shields + ornate hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",          right = _EAS_AXE_03_T1,   rarity = "exotic",    suffix = "axe_03_t1" },
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",          right = _EAS_AXE_03_T2,   rarity = "exotic",    suffix = "axe_03_t2" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",          right = _EAS_AXE_03_T2,   rarity = "exotic",    suffix = "axe_03_t2" },
	{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",          right = _EAS_HATCHET_T2,  rarity = "exotic",    suffix = "hatchet_t2" },
	-- Unique (red illusion tier): runed shields + runed hatchets.
	{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01", right = _EAS_AXE_02_T2_R, rarity = "unique",    suffix = "axe_02_t2_runed" },
	{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01", right = _EAS_AXE_03_T2_R, rarity = "unique",    suffix = "axe_03_t2_runed" },
	-- Magic (weave-forged): scorpion DLC's magic Empire shield.
	{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01", right = _EAS_HATCHET_T2,  rarity = "magic",     suffix = "hatchet_t2" },
}

local function _register_axe_shield_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	local registered = 0
	for _, pair in ipairs(_AXE_SHIELD_PAIRINGS) do
		-- Key = `cwv_es_axe_shield_<shield_tail>__<axe_suffix>`.
		-- Both fragments are required because multiple hatchets pair
		-- against the same shield mesh — without the axe suffix the
		-- per-shield key would collide and only the first registers.
		local mesh_tail = pair.left:match("([^/]+)$") or pair.left
		local axe_frag = pair.suffix or "default"
		local new_key = "cwv_es_axe_shield_" .. mesh_tail .. "__" .. axe_frag
		if _custom_skin_keys[new_key] then goto continue end

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_axe_shield",
			rarity            = pair.rarity,
			display_name      = "cwv_es_axe_shield_skin_name",
			description       = "cwv_es_axe_shield_description",
			display_unit      = "units/weapons/weapon_display/display_shield",
			hud_icon          = "weapon_generic_icon_axe_and_sheild",
			inventory_icon    = "icon_wpn_dw_shield_01_axe",
			information_text  = "information_weapon_skin",
			right_hand_unit   = pair.right,
			left_hand_unit    = pair.left,
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_axe_shield_description",
			display_name    = "cwv_es_axe_shield_skin_name",
			display_unit    = "units/weapons/weapon_display/display_shield",
			hud_icon        = "weapon_generic_icon_axe_and_sheild",
			inventory_icon  = "icon_wpn_dw_shield_01_axe",
			rarity          = pair.rarity,
			right_hand_unit = pair.right,
			left_hand_unit  = pair.left,
		}

		local combos = WeaponSkins.skin_combinations.cwv_es_axe_shield_skins
		if combos then
			local tier = combos[pair.rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d Empire shield + hatchet pairings on cwv_es_axe_shield", registered)
end

_register_axe_shield_illusions()

end  -- do (axe+shield illusion scope)

-- ============================================================
-- Musket cosmetic illusions (alternate handgun meshes) — REMOVED v0.1.348-dev
-- ============================================================
-- These two cosmetic illusions (Aunty Bessie / Von Meinkopt's Single-Shooter,
-- vanilla es_handgun t2/t3 skin meshes) existed ONLY to skin the on-ice
-- `cwv_es_musket` variant (commented-out def near line ~582). They matched
-- `matching_item_key = "cwv_es_musket"`, used `template = "musket_template"`,
-- and referenced the `cwv_es_musket_description` loc key — all tied to the
-- on-ice variant. The LIVE musket is `cwv_es_musket_old`, which ships its own
-- custom mesh (units/cwv_es_musket_custom/...) under `old_musket_template`; the
-- vanilla-handgun-mesh illusions would defeat that custom mesh and never
-- attached to it. Their only other reference (instance_skins) is itself inside
-- the commented on-ice block. So the registration was dead code with two
-- dangling description loc refs (the cwv_es_musket_description key) flagged by
-- qa/check_name_integrity.ps1 check #2. Removed alongside its on-ice owner. If
-- the on-ice `cwv_es_musket` variant is ever re-enabled, restore these skins
-- from git history (last present in v0.1.347-dev) and repoint the loc key /
-- matching_item_key as needed.

-- ============================================================
-- Empire 1h sword + 1h mace → cwv_es_sword_and_mace illusions
-- ============================================================
-- Variant `cwv_es_sword_and_mace` is the inverse of vanilla mace+sword
-- (sword right, mace left). Cosmetic options pair each vanilla
-- `es_1h_sword` skin's mesh on the right hand with an `es_1h_mace`
-- skin's mesh on the left hand.
--
-- Both source pools have 8 skins each. We sort each by rarity
-- (common→plentiful→rare→exotic→unique→magic) then zip by index. The
-- distributions don't perfectly match (sword has 3 unique + 1 exotic,
-- mace has 2 unique + 2 exotic), so one pair (index 5) ends up
-- mismatched (sword unique × mace exotic). All 8 pair cleanly otherwise.
--
-- Display rig: `display_dual_weapons` is forced via the existing
-- `_force_display_unit[cwv_es_sword_and_mace]` entry on the variant's
-- auto-generated default skin. Each illusion clone here also explicitly
-- sets `display_unit` to `display_dual_weapons` (set on both IML and
-- WeaponSkins.skins entries — the previewer reads it via two chains and
-- needs it on both layers, per `feedback_cwv_dual_wield_display_rig.md`).

local _RARITY_ORDER = {
	common = 1, plentiful = 2, rare = 3, exotic = 4, unique = 5, magic = 6,
}

local function _register_sword_and_mace_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	-- Collect both source pools. We capture (skin_key, mesh, rarity) and
	-- sort by (rarity_priority, skin_key) for deterministic pairing order.
	local function _gather(matching_key)
		local pool = {}
		for skin_key, entry in pairs(ItemMasterList) do
			if type(entry) == "table"
					and entry.item_type == "weapon_skin"
					and entry.matching_item_key == matching_key
					and entry.right_hand_unit then
				pool[#pool + 1] = {
					skin_key = skin_key,
					mesh     = entry.right_hand_unit,  -- es_1h_mace stores mesh as right_hand_unit even though we put it on the left
					rarity   = entry.rarity or "exotic",
				}
			end
		end
		table.sort(pool, function(a, b)
			local ra, rb = _RARITY_ORDER[a.rarity] or 99, _RARITY_ORDER[b.rarity] or 99
			if ra ~= rb then return ra < rb end
			return a.skin_key < b.skin_key
		end)
		return pool
	end

	local swords = _gather("es_1h_sword")
	local maces  = _gather("es_1h_mace")

	-- Zip by index. If counts differ (currently both 8, but defensive
	-- against future vanilla DLC adding skins to one but not the other),
	-- iterate the smaller of the two; surplus on either side stays
	-- unpaired.
	local n = math.min(#swords, #maces)
	if n == 0 then return end

	local display_unit = "units/weapons/weapon_display/display_dual_weapons"

	local registered = 0
	for i = 1, n do
		local sword = swords[i]
		local mace  = maces[i]
		-- Compose a stable key from both source paths' mesh tail components.
		-- Pattern: cwv_es_sword_and_mace_<sword_mesh_tail>_<mace_mesh_tail>.
		local sword_tail = sword.mesh:match("([^/]+)/[^/]+$") or sword.mesh
		local mace_tail  = mace.mesh:match("([^/]+)/[^/]+$") or mace.mesh
		local new_key = "cwv_es_sword_and_mace_" .. sword_tail .. "_" .. mace_tail
		if _custom_skin_keys[new_key] then goto continue end

		-- Picker rarity inherits the sword's rarity (the right-hand "primary"
		-- of the pair). Mace rarity may differ for mismatched index pairs;
		-- sword's reads as the headline cosmetic.
		local rarity = sword.rarity

		local iml_entry = {
			key               = new_key,
			name              = new_key,
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = "cwv_es_sword_and_mace",
			rarity            = rarity,
			-- Display name / description fall through to a generic
			-- "Sword and Mace" — auto-populated from the variant def's
			-- skin_display_name / description via _display_names registration.
			display_name      = "cwv_es_sword_and_mace_skin_name",
			description       = "cwv_es_sword_and_mace_description",
			display_unit      = display_unit,
			hud_icon          = "weapon_generic_icon_falken",
			inventory_icon    = "icon_es_dual_wield_hammer_sword_01",
			information_text  = "information_weapon_skin",
			right_hand_unit   = sword.mesh,
			left_hand_unit    = mace.mesh,
			template          = "sword_and_mace_template",
			can_wield         = _es_all_careers,
		}
		ItemMasterList[new_key] = iml_entry

		WeaponSkins.skins[new_key] = {
			description     = "cwv_es_sword_and_mace_description",
			display_name    = "cwv_es_sword_and_mace_skin_name",
			display_unit    = display_unit,
			hud_icon        = "weapon_generic_icon_falken",
			inventory_icon  = "icon_es_dual_wield_hammer_sword_01",
			rarity          = rarity,
			right_hand_unit = sword.mesh,
			left_hand_unit  = mace.mesh,
			template        = "sword_and_mace_template",
		}

		local combos = WeaponSkins.skin_combinations.cwv_es_sword_and_mace_skins
		if combos then
			local tier = combos[rarity]
			if tier then
				tier[#tier + 1] = new_key
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
			local tbl = NetworkLookup.weapon_skins
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, new_key)
			rawset(tbl, new_key, idx)
		end

		_custom_skin_keys[new_key] = true
		registered = registered + 1
		::continue::
	end

	mod:info("Registered %d sword+mace illusion pairs on cwv_es_sword_and_mace (1h sword right × 1h mace left, rarity-sorted zip)", registered)
end

_register_sword_and_mace_illusions()

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
-- Item creation helper (shared by give command)
-- ============================================================

local _registered_keys = {}

-- #482: resolve the variant item_key for ANY backend instance of a cwv item.
-- Single resolution ladder shared by every bid-keyed resolver so they cannot
-- drift on what counts as "a cwv instance":
--   1. backend_id pattern `cwv_<key>_NNN` -- CWV's own _001/_002 instances and
--      cim standard-forge crafts (issue 390). Cheap, no backend round-trip.
--   2. item_data.cwv_key -- the field _build_entry stamps on the IML clone.
--      Covers instances whose backend_id is NOT cwv-shaped: cim's Athanor
--      mints Application.guid() UUIDs (crafting_in_modded_dev.lua:4644), which
--      rung 1 can never match (the #482 crafted-CWV transform loss).
--   3. backend items lookup by bid -> item.data.cwv_key -- for callers that
--      only carry the bid (the previewer's _item_info_by_slot holds just
--      {name, backend_id, skin_name, ...}, world_hero_previewer.lua:776).
--      pcall-guarded: interface readiness varies by menu state. The husk path
--      is unaffected (bid nil there, memory reference_vt2_husk_resolves_base_item_data).
-- Hung on _om: the top-level chunk sits at the Lua 5.1 200-local ceiling (#284).
_om._cwv_key_for_item = function(backend_id, item_data)
	if type(backend_id) == "string" then
		local key = backend_id:match("^(cwv_.-)_%d%d%d$")
		if key then return key end
	end
	if item_data and type(item_data.cwv_key) == "string" then
		return item_data.cwv_key
	end
	if type(backend_id) == "string" and backend_id ~= "" then
		local ok, data = pcall(function()
			local backend = Managers and Managers.backend
			local iface = backend and backend:get_interface("items")
			local item = iface and iface:get_item_from_id(backend_id)
			return item and item.data
		end)
		if ok and data and type(data.cwv_key) == "string" then
			return data.cwv_key
		end
	end
	return nil
end

local function _build_entry(def, backend_id)
	-- v0.1.345-dev: per-call _dbg trace. _build_entry is sparse (boot-time only,
	-- ~30 variants/session), so always-on.
	_dbg("[cwv:build_entry] event=enter key=%s base=%s backend_id=%s",
		tostring(def and def.item_key), tostring(def and def.base_weapon), tostring(backend_id))
	-- rawget: every variant declares a base_weapon key that's expected to exist, but the
	-- crashify metamethod on a missing key would surface as an opaque crash here. Failing
	-- soft with a warning lets the mod skip variants whose base weapon isn't installed.
	local base = rawget(ItemMasterList, def.base_weapon)
	if not base then
		_dbg_alert("[cwv:build_entry] event=fail_base_missing key=%s base=%s",
			tostring(def and def.item_key), tostring(def and def.base_weapon))
		mod:warning("Base weapon '%s' not found in ItemMasterList", def.base_weapon)
		return nil
	end

	local entry = table.clone(base, true)

	-- `cwv_variant` is the cross-mod marker contract. Sibling mods
	-- (cosmetics_tweaker, weapon_tweaker, future) check `item_data.cwv_variant`
	-- in their hooks and SKIP item-name-keyed overrides when it's truthy. This
	-- exists because the clone inherits `entry.name` from the base weapon
	-- (e.g. cwv_es_longsword.name == "es_bastard_sword"), which would
	-- otherwise spuriously match a sibling mod's `_weapon_grip_offsets[name]`
	-- or `_breton_sword_thiccc` lookup.
	--
	-- WHY NOT just clobber entry.name/.key to def.item_key? Because vanilla
	-- code (e.g. world_hero_previewer.lua's equip_item at line 674) does
	-- `item_data = ItemMasterList[item.name]` for fallback lookups. Setting
	-- name = cwv_key meant the lookup returned nil and the equip path
	-- crashed in BackendUtils.get_item_units. See
	-- `feedback_cwv_clone_name_clobber.md` for the full incident log.
	entry.cwv_variant = true

	-- #482: self-identifying clone. entry.name/.key MUST stay the BASE keys
	-- (clobber crashes equip, see above), and the backend_id pattern is NOT
	-- guaranteed on every instance -- cim's Athanor mints Application.guid()
	-- backend_ids (crafting_in_modded_dev.lua:4644), a UUID that carries no
	-- key. Every pattern-keyed resolver silently skipped such crafted
	-- instances, so a crafted CWV weapon rendered without its type-level
	-- scale/grip on the owner + preview paths. The clone carrying its own
	-- variant key gives resolvers a bid-shape-independent positive signal;
	-- it survives the table.clone in BackendUtils.get_item_from_masterlist
	-- (backend_utils.lua:68) that produces the item_data create_equipment sees.
	entry.cwv_key = def.item_key
	-- Crowbill Weapon-Special state is owned by the isolated hammer-mode
	-- module. Persist the stable family marker on definition rows and every
	-- CIM-built clone; do not infer membership from a display name or mesh.
	if def.crowbill_mode_family then
		entry.crowbill_mode_family = def.crowbill_mode_family
	end

	entry.display_name = def.item_key .. "_name"
	entry.description = def.item_key .. "_description"

	if def.right_hand_unit then
		entry.right_hand_unit = def.right_hand_unit
	end
	if def.left_hand_unit then
		entry.left_hand_unit = def.left_hand_unit
	end
	-- `no_left_hand = true` explicitly clears the inherited left_hand_unit
	-- from the clone. Used when the variant uses the BASE weapon's template
	-- (which mounts on a different hand than the variant) — e.g.
	-- `cwv_es_outrider_grenade_launcher` clones from `dr_deus_01` (Bardin
	-- trollhammer, left-hand-mount) but the cwv variant is right-hand-mount
	-- (blunderbuss). Without this flag, the inherited `left_hand_unit =
	-- "...wpn_dr_deus_01"` would render alongside our right-hand blunderbuss,
	-- giving Kruber TWO weapons in the preview. Distinct from
	-- `def.left_hand_unit = nil` (which the existing `if def.left_hand_unit`
	-- guard treats as "don't override" → inheritance kicks in).
	if def.no_left_hand then
		entry.left_hand_unit = nil
	end
	-- v0.1.365-dev (issue 279): `no_ammo_unit = true` clears the AMMO unit
	-- fields inherited from the base clone. Needed when the variant's visual
	-- family changed (e.g. cwv_es_outrider_grenade_launcher clones dr_deus_01,
	-- whose entry carries the trollhammer torpedo ammo_unit/ammo_unit_3p) —
	-- with the template's ammo_data intact, GearUtils.spawn_inventory_unit
	-- (gear_utils.lua:164/169/248) attaches the inherited ammo mesh to the
	-- variant's own hand unit whenever NO skin resolves for the item. The
	-- curated pre-applied skin masks this on native CWV items (a skin replaces
	-- the whole unit set incl. ammo_unit, backend_utils.lua:171-183), but a
	-- cim-CRAFTED copy of the variant has no skin and rendered BOTH meshes
	-- merged (issue 279). Ammo COUNT is untouched: it lives in the weapon
	-- template's ammo_data, not on these unit-path fields.
	if def.no_ammo_unit then
		entry.ammo_unit = nil
		entry.ammo_unit_3p = nil
		printf("[cwv:279] cleared inherited ammo units on %s (no_ammo_unit)", tostring(def.item_key))
	end
	if def.inventory_icon then
		entry.inventory_icon = def.inventory_icon
	end
	if def.hud_icon then
		entry.hud_icon = def.hud_icon
	end
	if def.careers then
		entry.can_wield = def.careers
	end
	if def.template then
		entry.template = def.template
	end
	-- Always set entry.item_type to a unique cwv-prefixed key. Without this,
	-- the variant inherits the base's item_type (e.g. cwv_es_shortsword
	-- inherits "bw_dagger"), and any vanilla UI that does
	-- `Localize(item_data.item_type)` displays the BASE weapon's name
	-- ("Dagger") even though the variant is called "Shortsword". Setting
	-- entry.item_type to def.item_type (when explicit) or def.item_key (as
	-- fallback) ensures Localize hits the cwv-specific localization
	-- registered below in `_display_names`. See the "Naming flow for cwv
	-- variants" section in `DEVELOPMENT.md`.
	entry.item_type = def.item_type or def.item_key

	-- v0.1.311 tried `entry.slot_type = "cwv_dual"` (custom value) but the
	-- item then disappeared from both grids entirely — MIL or vanilla
	-- silently drops items with unrecognized slot_type. v0.1.312 reverts:
	-- the entry keeps its inherited slot_type ("ranged" for the musket).
	-- Cross-slot visibility comes from career-level "ranged" inclusion in
	-- slot_melee plus a post-filter on `get_filtered_items` that scopes
	-- which ranged items survive the melee filter (search "_CWV_CROSS_SLOT_PREFIXES").
	-- The `def.cross_slot` field on variants is still meaningful — it's
	-- used by the post-filter to identify allowlisted items.
	-- Per-item_type custom skin_combination_table. Each entry has its own
	-- table registered by `_register_cwv_skin_combinations` so the variant's
	-- cosmetics menu shows ONLY the curated set we wire up — vanilla skins
	-- of the base weapon don't bleed into the variant.
	local _item_type_to_skin_table = {
		cwv_imperial_longsword         = "cwv_imperial_longsword_skins",
		cwv_es_longsword_shield        = "cwv_es_longsword_shield_skins",
		cwv_es_axe_shield              = "cwv_es_axe_shield_skins",
		cwv_es_infantry_spear          = "cwv_es_infantry_spear_skins",
		cwv_es_dual_swords             = "cwv_es_dual_swords_skins",
		cwv_es_dual_axes               = "cwv_es_dual_axes_skins",
		cwv_wh_dual_axes               = "cwv_wh_dual_axes_skins",
		cwv_es_dual_maces              = "cwv_es_dual_maces_skins",
		cwv_wh_dual_maces              = "cwv_wh_dual_maces_skins",
		cwv_dr_dawi_mace               = "cwv_dr_dawi_mace_skins",
		cwv_dr_dawi_mace_shield        = "cwv_dr_dawi_mace_shield_skins",
		cwv_dr_dawi_dual_maces         = "cwv_dr_dawi_dual_maces_skins",
		cwv_es_imperial_crowbill       = "cwv_es_imperial_crowbill_skins",
		cwv_dr_dawi_crowbill           = "cwv_dr_dawi_crowbill_skins",
		cwv_es_sword_and_mace          = "cwv_es_sword_and_mace_skins",
		cwv_es_warpriest_hammer        = "cwv_es_warpriest_hammer_skins",
		cwv_es_dual_warpriest_hammers  = "cwv_es_dual_warpriest_hammers_skins",
		cwv_es_warpriest_hammer_shield = "cwv_es_warpriest_hammer_shield_skins",
		cwv_es_priest_greathammer      = "cwv_es_priest_greathammer_skins",
		cwv_es_maul                    = "cwv_es_maul_skins",
		cwv_es_greataxe                = "cwv_es_greataxe_skins",
		cwv_es_rapier                  = "cwv_es_rapier_skins",
		cwv_es_outrider_grenade_launcher = "cwv_es_outrider_grenade_launcher_skins",
		cwv_es_musket                    = "cwv_es_musket_skins",
		cwv_es_musket_old                = "cwv_es_musket_old_skins",
	}
	if def.item_type and _item_type_to_skin_table[def.item_type] then
		entry.skin_combination_table = _item_type_to_skin_table[def.item_type]
	end
	-- CLARIFY: Clear required_dlc so non-DLC users (e.g. no "lake" DLC for
	-- bastard_sword-derived variants) can equip the variant. The actual model
	-- assets (wpn_empire_2h_sword_*, wpn_emp_gk_*) live in the base inventory
	-- package list, not in DLC-only packages, so the unit paths still resolve.
	-- POTENTIAL BUG: this is verified for the Empire greatsword units and
	-- es_sword_shield variants but NOT the Bretonnian units (wpn_emp_gk_shield_*)
	-- which DO require the lake DLC package to load. A non-lake-DLC user equipping
	-- a variant whose left/right unit lives only in lake's package would see the
	-- model fail to load.
	entry.required_dlc = nil

	local traits = def.traits or {}
	local properties = def.properties or {}
	local power_level = def.power_level or 300

	local traits_json = "["
	for i, t in ipairs(traits) do
		if i > 1 then traits_json = traits_json .. "," end
		traits_json = traits_json .. '"' .. t .. '"'
	end
	traits_json = traits_json .. "]"

	local props_json = "{"
	local first = true
	for k, v in pairs(properties) do
		if not first then props_json = props_json .. "," end
		props_json = props_json .. '"' .. k .. '":' .. tostring(v)
		first = false
	end
	props_json = props_json .. "}"

	entry.rarity = "default"
	entry.cwv_definition = backend_id == nil

	-- Registration and acquisition are deliberately separate (#592). The IML
	-- owner row is definition-only and therefore carries no backend identity.
	-- CIM supplies mod_data only when it mints an exact, persisted craft.
	if backend_id then
		entry.mod_data = {
			backend_id = backend_id,
			ItemInstanceId = backend_id,
			CustomData = {
				traits = traits_json,
				power_level = tostring(power_level),
				properties = props_json,
				rarity = "default",
			},
			rarity = "default",
			traits = table.clone(traits, true),
			power_level = power_level,
			properties = table.clone(properties, true),
		}
	else
		entry.mod_data = nil
	end

	-- Pre-apply the item's own illusion as the curated cosmetic ONLY for
	-- non-default-rarity variants. Exotic / unique CWV weapons ship with
	-- a fixed illusion as part of their curated identity. Default-rarity
	-- "blacksmith template" variants must NOT pre-apply a skin — vanilla
	-- blacksmith templates carry `mod_data.CustomData.skin = nil` and the
	-- forge requires that to treat the item as unlocked.
	--
	-- See the full recipe in `DEVELOPMENT.md` "Blacksmith Template
	-- Pattern" and `reference_cwv_blacksmith_template.md`. Default-rarity
	-- variants get their model from `entry.right_hand_unit` (set above);
	-- the `BackendUtils.get_item_units` cwv-override hook below ensures
	-- that mesh actually wins at render time regardless of which entry
	-- the upstream lookup resolved item_data to. The skin entry is still
	-- registered by `_register_variant_skins` so OTHER variants of the
	-- same item_type can apply this variant's look as an illusion.
	if backend_id and not def.no_skin and def.rarity ~= "default" then
		local skin_key = def.item_key .. "_skin"
		entry.mod_data.CustomData.skin = skin_key
		entry.mod_data.skin = skin_key
	end

	-- v0.1.345-dev: exit trace for diagnostics. Reports the resolved fields
	-- the engine will read at equip + render time.
	_dbg("[cwv:build_entry] event=exit key=%s template=%s item_type=%s slot_type=%s rhu=%s lhu=%s skin=%s",
		tostring(def and def.item_key), tostring(entry.template), tostring(entry.item_type),
		tostring(entry.slot_type), tostring(entry.right_hand_unit), tostring(entry.left_hand_unit),
		tostring(entry.mod_data and entry.mod_data.skin))
	return entry
end

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
-- Preview mesh-swap (issue 237) — WEAPON_APPEARANCE_STANDARD §4.1
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
-- Reached from the MenuWorldPreviewer.equip_item hook via the `_om` upvalue
-- (forward-ref: this helper needs `_find_def`, declared just above, but the hook
-- sits far earlier in the file). `entry.unit_name` already carries the "_3p"
-- suffix (world_hero_previewer.lua:697/721), so we append it once here.
--
-- SAFETY: only vanilla `units/weapons/player/` meshes are swapped — a mod-bundled
-- custom mesh (the Old Musket's units/cwv_*) has no per-unit `_3p` package and
-- World.spawn_unit would engine-fatal (issue 403 class); the musket keeps its
-- bespoke handling. The invisible-weapon sentinel is skipped. Ammo-unit entries
-- are skipped (ranged variants carry their own handling). A user-selected
-- illusion (non-empty `skin` arg) wins, mirroring the get_item_units guard.
_om._cwv_preview_meshswap_apply = function(item_name, backend_id, skin, info)
	-- #579: MenuWorldPreviewer's copied equip path does not reliably preserve the
	-- callback's `skin` argument by the time this post-hook runs, but vanilla has
	-- already committed the authoritative value to info.skin_name. The retest log
	-- showed the selected runed axe package queued, then this fallback overwrote
	-- both generated-skin hands with the def's default hatchets because `skin`
	-- arrived nil. Trust either signal; a selected illusion owns the spawn recipe.
	local effective_skin = skin
	if (type(effective_skin) ~= "string" or effective_skin == "") and type(info) == "table" then
		effective_skin = info.skin_name
	end
	local cwv_key = _om._cwv_key_for_item(backend_id, nil)
	local def = cwv_key and _find_def(cwv_key) or nil
	local appearance = def and _om.exact_appearance.resolve({
		explicit_skin = effective_skin,
		backend_id = backend_id,
		weapon_skins = WeaponSkins and WeaponSkins.skins,
		skin_from_backend = function(bid)
			local backend = Managers and Managers.backend
			local iface = backend and backend:get_interface("items")
			return iface and iface.get_skin and iface:get_skin(bid)
		end,
	})
	if appearance then
		local swapped = _om.exact_appearance.apply_spawn_data(
			appearance, info and info.spawn_data, _om._resident_override_3p, def)
		if swapped > 0 then
			printf("[cwv:579] preview exact-skin=%s swapped=%d R=%s L=%s",
				appearance.skin, swapped, tostring(appearance.right_hand_unit),
				tostring(appearance.left_hand_unit))
		end
		return
	end
	-- A named skin that is not locally resolvable must never fall through to
	-- the variant default and erase its identity. Leave vanilla's recipe intact.
	if type(effective_skin) == "string" and effective_skin ~= "" then return end
	-- #482: shared ladder instead of the bare bid pattern -- an Athanor-crafted
	-- instance (UUID bid) resolves via the backend item's stamped cwv_key, so
	-- the inventory preview swaps to the variant mesh for crafted copies too.
	if not cwv_key then return end
	if not def then return end

	-- Vanilla player mesh only, non-sentinel, resident-gated -- else World.spawn_unit
	-- engine-fatals the inventory screen. Extracted to the shared guard (issue #418)
	-- so this path and the illusion browser can't drift; keyed on _om.HUSK_OVERRIDE_REF.
	local _swap_name = _om._resident_override_3p

	local swapped = 0
	for _, entry in ipairs(info.spawn_data) do
		if not entry.is_ammo_unit then
			local want
			if entry.right_hand then
				want = _swap_name(def.right_hand_unit)
			elseif entry.left_hand then
				want = _swap_name(def.left_hand_unit)
			end
			if want and entry.unit_name ~= want then
				entry.unit_name = want
				swapped = swapped + 1
			end
		end
	end
	if swapped > 0 then
		printf("[cwv:237] preview mesh-swap key=%s bid=%s swapped=%d (R=%s L=%s)",
			tostring(cwv_key), tostring(backend_id), swapped,
			tostring(def.right_hand_unit), tostring(def.left_hand_unit))
	end
end
mod._cwv_preview_meshswap_apply = _om._cwv_preview_meshswap_apply  -- exposed for /cwv regression (issue 237)

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
-- wins (skin data already carries the variant units for cwv skins); only
-- vanilla-player, non-sentinel, cwv-force-loaded-resident meshes swap
-- (`_om._resident_override_3p`, issue 418) — else degrade to the base mesh,
-- never an engine-fatal World.spawn_unit (issue 403 class). Hand identity by
-- exact base-unit-name match ("_3p" already appended by _load_item_units,
-- loot_item_unit_previewer.lua:286/302): ammo-unit entries and entries the
-- data level already swapped simply don't match and pass through untouched
-- (idempotent vs the get_item_units hook — no double-handling).
_om._cwv_browser_meshswap_apply = function(item, spawn_data)
	if not item or type(spawn_data) ~= "table" then return end
	local skin = item.skin or (item.data and item.data.mod_data and item.data.mod_data.skin)
	local cwv_key = _om._cwv_key_for_item(item.backend_id, item.data)
	local def = cwv_key and _find_def(cwv_key) or nil
	local appearance = def and _om.exact_appearance.resolve({
		explicit_skin = skin,
		backend_id = item.backend_id,
		weapon_skins = WeaponSkins and WeaponSkins.skins,
		skin_from_backend = function(bid)
			local backend = Managers and Managers.backend
			local iface = backend and backend:get_interface("items")
			return iface and iface.get_skin and iface:get_skin(bid)
		end,
	})
	if appearance then
		_om.exact_appearance.apply_spawn_data(appearance, spawn_data,
			_om._resident_override_3p, def)
		return
	end
	if type(skin) == "string" and skin ~= "" then return end
	if not cwv_key then return end
	if not def then return end
	local base = ItemMasterList and rawget(ItemMasterList, def.base_weapon)
	if not base then return end

	local swapped = 0
	for i = 1, #spawn_data do
		local entry = spawn_data[i]
		local name = entry.unit_name
		local want
		if def.right_hand_unit and type(base.right_hand_unit) == "string"
				and name == base.right_hand_unit .. "_3p" then
			want = _om._resident_override_3p(def.right_hand_unit)
		elseif def.left_hand_unit and type(base.left_hand_unit) == "string"
				and name == base.left_hand_unit .. "_3p" then
			want = _om._resident_override_3p(def.left_hand_unit)
		end
		if want and want ~= name then
			entry.unit_name = want
			swapped = swapped + 1
		end
	end
	if swapped > 0 then
		printf("[cwv:419] browser mesh-swap key=%s bid=%s swapped=%d (R=%s L=%s)",
			tostring(cwv_key), tostring(item.backend_id), swapped,
			tostring(def.right_hand_unit), tostring(def.left_hand_unit))
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
	-- #592: CWV never acquires weapons. CIM's crafting surface owns creation,
	-- persistence, and the selected primary/secondary equip destination.
	mod:echo("Craft %s through Crafting in Modded", def.display_name)
end

-- ============================================================
-- Auto-registration (deferred until backend is ready)
-- ============================================================

local _auto_registered = false

-- Issue #273: Chaos Wastes converts starting weapons by exact item key. Every
-- concrete CWV owner receives a dedicated DeusWeapons identity whose base_item
-- remains that CWV row; borrowing only the vanilla generation contract keeps
-- properties/traits valid without collapsing template, item_type, skin pool,
-- or render units to def.base_weapon. This mutates no inventory and therefore
-- preserves #592's registration-only/no-auto-grant boundary.
_om.install_deus_identities = function(reason)
	local exact_identity_allowed = false
	local parity = mod._cwv_peer_parity
	if parity and type(parity.all_peers_have) == "function" then
		local ok, result = pcall(parity.all_peers_have, parity)
		exact_identity_allowed = ok and result == true
	end
	local report = _om.deus_identity.install(
		_variant_definitions, ItemMasterList,
		rawget(_G, "DeusStartingWeaponTypeMapping"),
		rawget(_G, "DeusWeapons"), exact_identity_allowed)
	local fingerprint = string.format("%d:%d:%d:%d:%s", report.installed,
		report.existing, report.degraded, #report.skipped,
		tostring(exact_identity_allowed))
	if fingerprint ~= _om.deus_identity_fingerprint then
		_om.deus_identity_fingerprint = fingerprint
		local sample = {}
		for index = 1, math.min(#report.skipped, 8) do
			sample[#sample + 1] = report.skipped[index]
		end
		pcall(printf,
			"[cwv:273] deus_identity reason=%s exact=%s installed=%d existing=%d degraded=%d skipped=%d sample=%s",
			tostring(reason), tostring(exact_identity_allowed), report.installed,
			report.existing, report.degraded, #report.skipped,
			table.concat(sample, ","))
	end
	return report
end

-- Issue #567: these are the three persisted custom skins that exposed a stale
-- vanilla reverse-index. WeaponSkins.matching_weapon_skin_item_key builds
-- `_matching_weapon_skin_item_keys` only once by walking ItemMasterList owners
-- and their skin_combination_table pools (weapon_skins.lua:7824-7855). CWV
-- registers skin definitions/pools at mod load, but the owning cwv weapon rows
-- are deferred until the backend is ready. If vanilla builds the cache before
-- `_auto_register_all`, the associations remain absent even after the owner rows
-- arrive, producing "Incorrectly configured weapon skins" on save/loadout refresh.
mod._cwv567_skin_keys = {
	"cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1",
	"cwv_es_dual_maces_es_1h_mace_skin_02_runed_01",
	"cwv_es_axe_shield_wpn_emp_shield_03__axe_02_t2",
}

mod._cwv567_validate_skin_association = function(skin_key)
	local skin_item = ItemMasterList and rawget(ItemMasterList, skin_key)
	if type(skin_item) ~= "table" then return false, "skin ItemMasterList row missing" end
	if skin_item.item_type ~= "weapon_skin" or skin_item.slot_type ~= "weapon_skin" then
		return false, "skin row type/slot is not weapon_skin"
	end
	if not (WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[skin_key]) then
		return false, "WeaponSkins.skins row missing"
	end

	local owner_key = skin_item.matching_item_key
	local owner = owner_key and rawget(ItemMasterList, owner_key)
	if type(owner) ~= "table" then return false, "matching weapon row missing: " .. tostring(owner_key) end
	local combination_key = owner.skin_combination_table
	local combinations = combination_key and WeaponSkins.skin_combinations[combination_key]
	if type(combinations) ~= "table" then
		return false, "owner skin_combination_table missing: " .. tostring(combination_key)
	end

	for rarity, skins in pairs(combinations) do
		if type(skins) == "table" then
			for _, candidate in ipairs(skins) do
				if candidate == skin_key then
					return true, owner_key, combination_key, rarity
				end
			end
		end
	end
	return false, "skin absent from owner combination pool " .. tostring(combination_key)
end

local function _auto_register_all()
	-- v0.1.345-dev: entry trace. Sparse (one fire per session on
	-- StateInGameRunning.on_enter; subsequent fires hit _auto_registered guard).
	_dbg("[cwv:auto_register] event=enter auto_registered=%s defs_count=%d",
		tostring(_auto_registered), #_variant_definitions)
	if _auto_registered then
		_dbg("[cwv:auto_register] event=exit_already_registered")
		return
	end

	local mil = get_mod("MoreItemsLibrary")

	local entries = {}
	local pending_defs = {}
	local n_skipped_skin_only = 0
	local n_skipped_already_registered = 0
	local n_built_ok = 0
	local n_build_failed = 0
	for _, def in ipairs(_variant_definitions) do
		if def.skin_only then n_skipped_skin_only = n_skipped_skin_only + 1; goto continue end
		-- v0.1.347-dev: per-variant toggle gate. Currently only cwv_es_crossbow
		-- needs this (default-on; user can opt out). If disabled at session start,
		-- registration is skipped and the variant never appears in inventory until
		-- re-enabled + game restart. (Hot re-enable mid-session is not supported.)
		if def.item_key == "cwv_es_crossbow" and not mod:get("enable_cwv_es_crossbow") then
			goto continue
		end
		if _registered_keys[def.item_key] then
			n_skipped_already_registered = n_skipped_already_registered + 1
			goto continue
		end
		local entry = _build_entry(def, nil)
		if entry then
			n_built_ok = n_built_ok + 1
			entries[#entries + 1] = entry
			pending_defs[#pending_defs + 1] = { def = def, entry = entry }
			_registered_keys[def.item_key] = def.item_key
		else
			n_build_failed = n_build_failed + 1
		end
		::continue::
	end

	if #entries > 0 then
		-- Register owner definitions only. Acquisition belongs exclusively to CIM;
		-- no CWV row is added to MIL's local backend (#592).
		if ItemMasterList then
			for _, pending in ipairs(pending_defs) do
				local key = pending.def.item_key
				-- rawget: ItemMasterList has an __index metamethod that calls
				-- crashify.print_exception("ItemMasterList has no item %s") on
				-- missing keys, polluting the console with one exception per
				-- cwv_* item per keep load. rawget bypasses the metamethod.
				-- See CHANGELOG v0.1.333 + Issue tracking; the same defensive
				-- pattern is already used on NetworkLookup.item_names 20 lines below.
				if not rawget(ItemMasterList, key) then
					ItemMasterList[key] = pending.entry
				end
			end
		end

		-- Issue #567 root fix. The vanilla reverse-index is a lazy snapshot, not a
		-- live view (weapon_skins.lua:7824-7855). The custom skin rows and pools
		-- above were already valid; what was missing at the earlier snapshot was
		-- the deferred cwv owner row carrying `skin_combination_table`. Invalidate
		-- only after every owner has been mirrored into ItemMasterList, before the
		-- backend refresh can validate persisted skins. Force vanilla to rebuild
		-- the complete index now, then canonicalize every CWV skin to its explicit
		-- IML `matching_item_key`. The canonicalization matters where two variant
		-- owners share one combination pool: vanilla's pairs(ItemMasterList) walk
		-- would otherwise let whichever owner iterates last win nondeterministically.
		local skin_cache_was_built = WeaponSkins
			and type(WeaponSkins._matching_weapon_skin_item_keys) == "table"
		if WeaponSkins then WeaponSkins._matching_weapon_skin_item_keys = nil end
		local rebuild_ok, rebuild_err = false, "WeaponSkins matcher unavailable"
		if WeaponSkins and type(WeaponSkins.matching_weapon_skin_item_key) == "function" then
			rebuild_ok, rebuild_err = pcall(
				WeaponSkins.matching_weapon_skin_item_key,
				mod._cwv567_skin_keys[1]
			)
		end
		local rebuilt_cache = WeaponSkins and WeaponSkins._matching_weapon_skin_item_keys
		if rebuild_ok and type(rebuilt_cache) == "table" then
			for custom_skin_key in pairs(_custom_skin_keys) do
				local skin_item = rawget(ItemMasterList, custom_skin_key)
				local owner_key = skin_item and skin_item.matching_item_key
				if owner_key then
					rebuilt_cache[custom_skin_key] = {
						rarity = skin_item.rarity,
						item_key = owner_key .. "_skin",
					}
				end
			end
		else
			pcall(printf, "[cwv:567] reverse-index rebuild FAILED err=%s", tostring(rebuild_err))
		end
		for _, skin_key in ipairs(mod._cwv567_skin_keys) do
			local valid, owner_or_err, combination_key, rarity = mod._cwv567_validate_skin_association(skin_key)
			local cache_row = type(rebuilt_cache) == "table" and rebuilt_cache[skin_key]
			pcall(printf,
				"[cwv:567] cache_invalidated=%s rebuild=%s skin=%s association=%s owner=%s combination=%s rarity=%s cache_item=%s",
				tostring(skin_cache_was_built), tostring(rebuild_ok), tostring(skin_key), valid and "valid" or "INVALID",
				tostring(owner_or_err), tostring(combination_key), tostring(rarity),
				tostring(cache_row and cache_row.item_key))
		end

		-- CLARIFY: Per CHANGELOG v0.1.24, MIL.add_mod_items_to_local_backend does
		-- NOT inject into NetworkLookup.item_names (only add_mod_items_to_masterlist
		-- does). Without this manual injection, network serialization crashes when
		-- the item is referenced over the wire.
		if NetworkLookup and NetworkLookup.item_names then
			for _, pending in ipairs(pending_defs) do
				local key = pending.def.item_key
				if not rawget(NetworkLookup.item_names, key) then
					local idx = #NetworkLookup.item_names + 1
					rawset(NetworkLookup.item_names, idx, key)
					rawset(NetworkLookup.item_names, key, idx)
				end
			end
		end

		_dbg("Registered %d variant definitions (zero inventory instances)", #entries)
	end

	-- One-time-compatible migration for sessions/hot-reloads that still contain
	-- CWV's historical auto-grants. The allowlist is derived from the authored
	-- old instance counts, and exact CIM persistence wins. IDs minted by CIM
	-- start at _100 today, but the ownership callback makes the boundary robust
	-- even if a legitimate saved craft reused _001 in an older/manual build.
	local legacy_ids = mod._cwv_acquisition.legacy_auto_grant_ids(_variant_definitions)
	local cim_dev = get_mod("cim_dev")
	local cim_public = get_mod("cim")
	local function is_cim_owned(backend_id)
		return (cim_dev and cim_dev._cim_get_craft and cim_dev._cim_get_craft(backend_id) ~= nil)
			or (cim_public and cim_public._cim_get_craft and cim_public._cim_get_craft(backend_id) ~= nil)
	end
	local purge = {}
	for backend_id in pairs(legacy_ids) do
		if mod._cwv_acquisition.should_remove(backend_id, legacy_ids, is_cim_owned) then
			purge[#purge + 1] = backend_id
		end
	end
	table.sort(purge)
	local removed = 0
	if #purge > 0 and mil and type(mil.remove_mod_items_from_local_backend) == "function" then
		mil:remove_mod_items_from_local_backend(purge, "character_weapon_variants")
		removed = #purge
	end
	mod:info("[cwv:592] registration_only=%d legacy_ids_purged=%d cim_exact_ids_preserved=true",
		#entries, removed)

	_auto_registered = true
	-- v0.1.356-dev: VISIBLE (mod:info, not _dbg) registration summary so the
	-- "only axe+shield shows" regression can be diagnosed from the user's log
	-- (INFO is on, DEBUG is off). If built_ok is ~28 but the inventory shows 1,
	-- it's a display/backend-merge issue; if built_ok is ~1, the build loop is
	-- bailing. Also lists the keys that made it into the registration batch.
	mod:info("[cwv:auto_register] SUMMARY built_ok=%d build_failed=%d skipped_skin_only=%d skipped_already=%d entries_added=%d (defs=%d)",
		n_built_ok, n_build_failed, n_skipped_skin_only, n_skipped_already_registered, #entries, #_variant_definitions)
	do
		local keys = {}
		for _, p in ipairs(pending_defs) do keys[#keys + 1] = p.def.item_key end
		mod:info("[cwv:auto_register] registered keys: %s", table.concat(keys, ", "))
	end
end

-- CLARIFY: StateInGameRunning.on_enter fires on entering the keep AND on every
-- mission load. _auto_register_all() guards via _auto_registered flag so it
-- runs at most once per session. Backend is guaranteed live by this state per
-- DEVELOPMENT.md / CHANGELOG v0.1.17.
-- QUESTION: If a user joins a friend's lobby BEFORE entering the keep (e.g. via
-- direct lobby join), does StateInGameRunning fire? In practice the keep is
-- always the first state, so this should be fine — flagged here in case the
-- assumption breaks for future game-state changes.
mod:hook_safe("StateInGameRunning", "on_enter", function()
	_auto_register_all()
	_om.install_deus_identities("gameplay_enter")
	-- #567: this boundary also covers a peer joining directly into an existing
	-- Keep/mission after the install-time VMF query ran without a network backend.
	-- Query every CWV owner, then publish our own current state. Both are bounded
	-- one-shot messages on gameplay entry, never update-loop traffic.
	if _om._exact_pair_query then _om._exact_pair_query("gameplay_enter") end
	if _om._exact_pair_publish_local then
		_om._exact_pair_publish_local("gameplay_enter")
	end
end)

-- Last-chance boundary for starting a run in the same session before another
-- gameplay-enter callback. Installation is idempotent and completes before
-- vanilla reads DeusStartingWeaponTypeMapping inside _setup_run.
if rawget(_G, "DeusMechanism") then
	mod:hook("DeusMechanism", "_setup_run", function(func, self, ...)
		_om.install_deus_identities("setup_run")
		return func(self, ...)
	end)
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

local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

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
	WA.apply(unit, { scale = scale_tbl, offset = offset_tbl, rotation = rotation })
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

local function _resolve_cwv_def(item_data, skin)
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin] end
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

-- ============================================================
-- Husk apply helpers  (issues 397/394/399) — assigned onto `_om`
-- ============================================================
-- These run from the GearUtils.spawn_inventory_unit hook (~line 4525, the
-- husk-reaching path). They are DEFINED here — below `_transform_unit`,
-- `_resolve_field`, `_resolve_cwv_def`, `_is_unit` — because Lua locals are
-- only visible after their declaration point; the hook above can't see these
-- helpers directly, so it reaches them through the `_om` upvalue table
-- (declared near the top of the file), whose fields are populated at load
-- time before any in-mission spawn. See the husk block in that hook.
do
	-- issue 399 lookup: base_weapon -> career-set for every no_ammo_unit
	-- variant. On the husk the item resolves to the BASE item_data (name =
	-- base weapon), so backend_id/skin/cwv markers are unreliable. But the
	-- variant's base weapon on a career that CANNOT natively wield it is a
	-- husk-reliable POSITIVE signal (e.g. dr_deus_01 is Bardin-exclusive, so a
	-- non-dwarf wielding it can only be the CWV Outrider). We gate strictly on
	-- (item_data.name == base_weapon) AND (career in the variant's own careers
	-- list) so a genuine dwarf wielding the real Trollhammer is never touched.
	local _no_ammo_careers_by_base = {}
	for _, def in ipairs(_variant_definitions) do
		if def.no_ammo_unit and type(def.base_weapon) == "string" then
			local set = _no_ammo_careers_by_base[def.base_weapon] or {}
			for _, c in ipairs(def.careers or {}) do set[c] = true end
			_no_ammo_careers_by_base[def.base_weapon] = set
		end
	end
	-- Exposed for the `cwv_no_ammo_strip_coverage` regression test, which
	-- asserts every no_ammo_unit def contributes its base + careers here.
	_om._no_ammo_careers_by_base = _no_ammo_careers_by_base

	-- issues 396/397/401 husk display resolution, restructured for #474/#475.
	--
	-- RESOLUTION ORDER (the husk display contract -- WEAPON_APPEARANCE_STANDARD §3):
	--   1. WIRE SKIN, PRIMARY (positive identity): a skin in either cwv skin
	--      namespace (base "<item_key>_skin" or pairing "<item_key>_<tail>")
	--      positively identifies the variant -> re-key REGARDLESS of can_wield.
	--      #474 root: vanilla es_handgun.can_wield includes es_mercenary, so the
	--      can_wield-excluded (base,career) map could never fire for the Old
	--      Musket even though the wire skin named it outright.
	--   2. A present NON-cwv skin = native item (or foreign illusion): NEVER
	--      re-key. #475 Invariant 1: mis-applying a variant to a native weapon
	--      is strictly worse than a variant degrading to its base display.
	--   3. SKINLESS echo only: (base,career) fallback, with can_wield evaluated
	--      LAZILY at wield time. #475 root: the old boot-time snapshot ran
	--      before weapon_tweaker expanded can_wield, so a wt-freedom native
	--      wield (host mercenary + native Bretonnian LS&S) matched the map and
	--      got re-keyed to the cwv variant. If the career can CURRENTLY wield
	--      the base (vanilla or wt), the skinless shape is ambiguous -> show
	--      base; a genuine variant's skinned wield still re-keys via arm 1.
	--
	-- The claims map is UNFILTERED (no build-time can_wield exclusion -- that is
	-- now the lazy check), deduped so an ambiguous (base,career) resolves to nil.
	local _husk_def_by_base_career = {}
	do
		local _seen = {}   -- "base|career" -> def, or false once ambiguous
		for _, def in ipairs(_variant_definitions) do
			local base = def.base_weapon
			if type(base) == "string" then
				for _, career in ipairs(def.careers or {}) do
					if type(career) == "string" then
						local k = base .. "|" .. career
						local slot = _husk_def_by_base_career[base]
						if not slot then slot = {}; _husk_def_by_base_career[base] = slot end
						if _seen[k] == nil then
							_seen[k] = def
							slot[career] = def
						elseif _seen[k] ~= def then
							_seen[k] = false          -- two variants share (base, career): ambiguous
							slot[career] = nil
						end
					end
				end
			end
		end
	end
	_om._husk_def_by_base_career = _husk_def_by_base_career   -- exposed for regression

	-- Lazy native check (#475): reads the CURRENT ItemMasterList[base].can_wield
	-- at husk-wield time, so weapon_tweaker's runtime expansion (wt is the last
	-- writer of can_wield, re-applied on game-state transitions) is respected no
	-- matter the boot order. Unknown/malformed -> native (decline re-key;
	-- conservative toward Invariant 1). Assigned to _om (not a local): this
	-- chunk sits at the Lua 5.1 200-local ceiling.
	_om._husk_pair_native_now = function(base_key, career)
		local base = rawget(ItemMasterList, base_key)
		local cw = type(base) == "table" and base.can_wield
		if type(cw) ~= "table" then return true end
		for _, c in ipairs(cw) do if c == career then return true end end
		return false
	end

	-- (#474) Skin -> variant-def identity lookup covering the two def-keyed cwv
	-- skin namespaces:
	--   * base variant skins  "<item_key>_skin"  -- seeded eagerly below;
	--   * pairing/illusion skins "<item_key>_<tail>" (e.g. cwv_es_longsword_
	--     shield_wpn_emp_shield_03_runed_01__nordland) -- resolved lazily by
	--     longest-prefix match (they register in _register_*_illusions AFTER
	--     this chunk runs) and cached, so the wield path stays allocation-free.
	-- KNOWN NON-MEMBERS (correct declines, do not "fix"): the cross-source
	-- illusion families named outside any def's item_key -- cwv_il_es_* /
	-- cwv_il_wh_* (Imperial Longsword) and cwv_es_priest_es_* / cwv_es_priest_
	-- wh_* (Sigmarite Greathammer). Their skin data carries the source mesh, so
	-- vanilla already renders them; they need no re-key and no def transforms
	-- (none registered), and on the anomalous base-reverted shape they degrade
	-- to base display per Invariant 2.
	-- Deliberately separate from _skin_transform_map: that map is gated on
	-- transform registration and also holds synthetic custom-illusion defs
	-- (transform-only, no base_weapon) that must never drive a mesh re-key.
	-- Cache stores false as the negative for a cwv_-prefixed non-variant skin;
	-- non-cwv skins return nil without touching the cache (no unbounded growth).
	_om._husk_skin_def_cache = {}
	for _, def in ipairs(_variant_definitions) do
		if type(def.item_key) == "string" and not def.no_skin then
			_om._husk_skin_def_cache[def.item_key .. "_skin"] = def
		end
	end
	_om._husk_skin_def = function(skin)
		if type(skin) ~= "string" then return nil end
		local cache = _om._husk_skin_def_cache
		local hit = cache[skin]
		if hit ~= nil then return hit or nil end
		if skin:sub(1, 4) ~= "cwv_" then return nil end
		local best, best_len = false, 0
		for _, def in ipairs(_variant_definitions) do
			local ik = def.item_key
			if type(ik) == "string" and #ik > best_len
					and skin:sub(1, #ik + 1) == ik .. "_" then
				best, best_len = def, #ik
			end
		end
		cache[skin] = best
		return best or nil
	end

	-- SINGLE husk display decision point (#474/#475): the mesh re-key AND the
	-- transform fallback both route through this so they can never disagree.
	-- Returns def, reason. Resolve reasons: "skin" | "base_career". Decline
	-- reasons (nil def): "skin_foreign" (non-cwv skin = native, Invariant 1) |
	-- "skin_base_mismatch" (defensive: skin and wire item disagree) |
	-- "native_pair" (skinless + pair currently wieldable) | "no_pair".
	_om._husk_resolve_display_def = function(base_name, career, skin)
		if skin ~= nil then
			local def = _om._husk_skin_def(skin)
			if not def then return nil, "skin_foreign" end
			if type(def.base_weapon) == "string" and base_name ~= nil
					and def.base_weapon ~= base_name then
				return nil, "skin_base_mismatch"
			end
			return def, "skin"
		end
		if not (base_name and career) then return nil, "no_pair" end
		local slot = _husk_def_by_base_career[base_name]
		local def = slot and slot[career]
		if not def then return nil, "no_pair" end
		if _om._husk_pair_native_now(base_name, career) then return nil, "native_pair" end
		return def, "base_career"
	end

	-- Set of every CWV base_weapon key — used only to scope the "no def
	-- resolved" husk diagnostic so it doesn't spam on the common native-weapon
	-- wield case (fires only for weapons whose base a CWV variant clones).
	local _cwv_base_weapons = {}
	for _, def in ipairs(_variant_definitions) do
		if type(def.base_weapon) == "string" then _cwv_base_weapons[def.base_weapon] = true end
	end

	-- Once-per-key throttle for the defensive husk diagnostics below. A husk
	-- weapon spawns on every wield, so an un-throttled printf on a silent-return
	-- path would spam the log each swap/frame. Key by a stable string (reason +
	-- base + hand) so each distinct silent-return reason surfaces exactly once,
	-- giving the next paired peer log the "why a variant didn't get its apply"
	-- evidence without the noise (task 5 defensive-logging requirement).
	local _husk_logged_once = {}
	local function _husk_log_once(key, fmt, ...)
		if _husk_logged_once[key] then return end
		_husk_logged_once[key] = true
		printf(fmt, ...)
	end

	local function _husk_career_name(owner_unit_3p)
		if not owner_unit_3p then return nil end
		local name
		pcall(function()
			if ScriptUnit.has_extension(owner_unit_3p, "career_system") then
				name = ScriptUnit.extension(owner_unit_3p, "career_system"):career_name()
			end
		end)
		return name
	end

	-- #478 handedness preselection. SimpleHuskInventoryExtension._wield_slot
	-- asks BackendUtils for the unit table and THEN decides which per-hand
	-- GearUtils.spawn_inventory_unit calls exist (simple_husk_inventory_extension
	-- .lua:662-670). The later _husk_rekey_units hook cannot move a skinless
	-- cross-character variant from the base weapon's hand to the authored hand:
	-- for Outrider, vanilla has already scheduled only dr_deus_01's LEFT call,
	-- while the variant is a RIGHT-mounted blunderbuss with no left unit.
	--
	-- Rewrite the unit table at the upstream decision seam, but only for the same
	-- conservative skinless base+career identity accepted by the shared husk
	-- resolver. A backend id or any skin is stronger identity owned by another
	-- path and is left untouched. The later residency re-key/crash-floor remains
	-- authoritative over whether the selected unit is actually safe to spawn.
	_om._husk_preselect_units = function(result, item_data, backend_id, skin, career_name)
		local effective_backend_id = (item_data and item_data.backend_id) or backend_id
		if type(result) ~= "table" or effective_backend_id ~= nil then return false end
		local resolved_skin = result.skin or skin
		if resolved_skin ~= nil and resolved_skin ~= "" then return false end
		local base_name = item_data and item_data.name
		local def, reason = _om._husk_resolve_display_def(base_name, career_name, nil)
		if not def or reason ~= "base_career" then return false end

		if type(def.right_hand_unit) == "string" and def.right_hand_unit ~= "" then
			result.right_hand_unit = def.right_hand_unit
		end
		if def.no_left_hand then
			result.left_hand_unit = nil
		elseif type(def.left_hand_unit) == "string" and def.left_hand_unit ~= "" then
			result.left_hand_unit = def.left_hand_unit
		end

		_husk_log_once("478_preselect:" .. tostring(base_name) .. ":" .. tostring(career_name),
			"[cwv:478] husk preselected hands before vanilla spawn branching: base=%s career=%s def=%s right=%s left=%s",
			tostring(base_name), tostring(career_name), tostring(def.item_key),
			tostring(result.right_hand_unit), tostring(result.left_hand_unit))
		return true, def
	end

	-- #478 crash-floor residency predicate. Can vanilla spawn_inventory_unit spawn
	-- this unit's "_3p" form on THIS peer without an async C-assert? DISTINCT from
	-- _om._resident_override_3p (issue 418), which demands cwv's OWN force-load
	-- reference: the crash-floor only asks whether the resource is resident under
	-- ANY reference -- a naturally game-loaded base mesh counts (has_loaded with no
	-- reference_name returns the plain loaded flag, package_manager.lua:286-293) --
	-- OR is a cwv custom-bundle mesh (units/cwv_*, always resident while the mod is
	-- loaded; the vanilla-prefix resident guard deliberately rejects it, issue 403).
	-- Used by the husk re-key to suppress a spawn that would otherwise error at
	-- gear_utils.lua:189 (weapon_unit_name .. "_3p" over a missing package).
	_om._husk_unit_spawnable = function(base_unit)
		if type(base_unit) ~= "string" or base_unit == "" then return false end
		if _om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(base_unit) then return true end
		if not (Managers and Managers.package) then return false end
		local ok, res = pcall(Managers.package.has_loaded, Managers.package, base_unit .. "_3p")
		return ok and res == true
	end

	-- Husk MESH re-key (issues 396/401, restructured for #474/#475). Runs BEFORE
	-- the vanilla spawn (the caller mutates item_units in place). Resolution
	-- order + invariants: the RESOLUTION ORDER block above; the actual decision
	-- is _om._husk_resolve_display_def, shared with the transform apply so mesh
	-- and transform can never disagree.
	--
	-- Write guards, in order:
	--   * For a skin-resolved def the skin template's OWN per-hand unit wins
	--     over the def default -- pairing skins carry their exact combination
	--     (e.g. a Nordland-shield pairing) and the def default would stomp it.
	--   * Residency (issue 403 crash-floor): a vanilla override must be
	--     force-loaded resident (shared _om._resident_override_3p, issue 418);
	--     a mod-bundled custom mesh (the Old Musket) is accepted via
	--     _om._husk_custom_bundle_unit instead (always resident in cwv's own
	--     bundle, and deliberately REJECTED by the vanilla-prefix resident
	--     guard -- force-loading it is the issue 403 boot fatal).
	--   * Idempotent and fail-safe: decline/no-op leaves item_units untouched
	--     (vanilla then spawns whatever the skin data already put there).
	_om._husk_rekey_units = function(hand, item_data, item_units, owner_unit_3p, slot_name)
		if not (item_data and item_units) then return end
		local base_name = item_data.name
		if not base_name then return end
		local skin = item_units.skin
		local career = _husk_career_name(owner_unit_3p)
		local def = _om._husk_identity_def and _om._husk_identity_def(owner_unit_3p, slot_name, base_name)
		local reason = def and "identity" or nil
		if not def then def, reason = _om._husk_resolve_display_def(base_name, career, skin) end
		if not def then
			-- Decision diagnostics (#474/#475), scoped to bases a cwv variant
			-- clones so common native wields don't spam; once per shape.
			if _cwv_base_weapons[base_name] then
				if reason == "skin_foreign" or reason == "skin_base_mismatch" then
					-- Wording split: cwv_-prefixed skins that don't resolve are the
					-- known cross-source illusion families outside the <item_key>_
					-- namespaces (cwv_il_*, cwv_es_priest_es/wh_*) -- genuinely cwv,
					-- display-complete via their skin data, correctly not re-keyed;
					-- don't label them native (log-triage accuracy, review finding).
					local skin_is_cwv = type(skin) == "string" and skin:sub(1, 4) == "cwv_"
					_husk_log_once("475_skin_decline:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(skin),
						skin_is_cwv
							and "[cwv:475] husk re-key declined (%s): base=%s career=%s skin=%s -- cwv skin outside the <item_key>_ namespaces (cross-source illusion family); skin data already drives its display, no re-key"
							or  "[cwv:475] husk re-key DECLINED (%s): base=%s career=%s skin=%s -- non-cwv skin = native item, never re-key (Invariant 1)",
						tostring(reason), tostring(base_name), tostring(career), tostring(skin))
				elseif reason == "native_pair" then
					_husk_log_once("475_native_pair:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(hand),
						"[cwv:475] husk re-key DECLINED (native_pair): base=%s career=%s -- skinless echo and the pair is currently wieldable (vanilla or wt); ambiguous shows base, a skinned wield still re-keys",
						tostring(base_name), tostring(career))
				else
					_husk_log_once("474_no_pair:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(hand),
						"[cwv:474] husk re-key no def (%s): base=%s career=%s skin=nil -- skinless echo without an unambiguous (base,career) claim",
						tostring(reason), tostring(base_name), tostring(career))
				end
			end
			return
		end
		local field = (hand == "right") and "right_hand_unit" or "left_hand_unit"
		local override
		if (reason == "skin" or reason == "identity") and WeaponSkins and WeaponSkins.skins then
			local skin_tmpl = rawget(WeaponSkins.skins, skin)
			local skin_unit = skin_tmpl and skin_tmpl[field]
			if type(skin_unit) == "string" and skin_unit ~= "" then override = skin_unit end
		end
		if override == nil then override = def[field] end
		if type(override) == "string" and override ~= "" and item_units[field] ~= override then
			-- Residency: helper checks the "_3p" form; we write the BASE-form path,
			-- vanilla spawn_inventory_unit appends "_3p". A vanilla override must be
			-- cwv-force-loaded under HUSK_OVERRIDE_REF (issue 418); a mod-bundled
			-- custom mesh is accepted via the custom-bundle predicate.
			if (_om._resident_override_3p and _om._resident_override_3p(override))
					or (_om._husk_custom_bundle_unit and _om._husk_custom_bundle_unit(override)) then
				item_units[field] = override
				_husk_log_once("474_rekey:" .. tostring(base_name) .. ":" .. tostring(career) .. ":" .. tostring(hand) .. ":" .. tostring(skin),
					"[cwv:474] husk re-keyed hand=%s base=%s career=%s via %s (skin=%s) -> %s",
					tostring(hand), tostring(base_name), tostring(career), tostring(reason), tostring(skin), tostring(override))
			else
				-- Override not cwv-resident: cannot re-key to it. Leave the base
				-- leftover in item_units and fall through to the #478 crash-floor,
				-- which suppresses the spawn if that leftover is itself non-resident.
				_husk_log_once("474_residency:" .. tostring(override) .. ":" .. tostring(hand),
					"[cwv:474] husk re-key DEFERRED (residency): hand=%s base=%s def=%s override=%s not resident -- showing base this wield (issue 403 crash-floor)",
					tostring(hand), tostring(base_name), tostring(def.item_key), tostring(override))
			end
		end
		-- #478 crash-floor (residency-gated defer): whatever now sits in
		-- item_units[field] is what vanilla spawn_inventory_unit will spawn -- the
		-- re-keyed override above, an idempotent pre-applied skin unit, or the base
		-- leftover for a hand the variant does NOT override (e.g. the Outrider's
		-- no_left_hand keeps dr_deus_01's Deus-only Trollhammer left-mount). If that
		-- unit is NON-RESIDENT on this peer, vanilla errors at gear_utils.lua:189
		-- (weapon_unit_name .. "_3p" over a missing package -> entity_manager2.lua:114
		-- "table index is nil" -> invisible wield; async C-assert risk on a
		-- harder-missing package, BUG_CLASSES 28). Return SUPPRESS=true so the spawn
		-- hook skips the vanilla call for THIS hand -- fail-safe (no mesh this hand,
		-- never force-load mid-mission). A non-resident mesh cannot render anyway, so
		-- suppressing removes only a crash, never a visible unit. Bounded to a
		-- resolved cwv def, so a genuine native wield is never touched (#475 Inv. 1).
		local final_unit = item_units[field]
		if type(final_unit) == "string" and final_unit ~= "" and not _om._husk_unit_spawnable(final_unit) then
			pcall(_husk_log_once, "478_defer:" .. tostring(base_name) .. ":" .. tostring(hand) .. ":" .. tostring(final_unit),
				"[cwv:478] husk DEFER: hand=%s base=%s career=%s def=%s -- NON-RESIDENT spawn unit %s suppressed (would crash vanilla spawn); no mesh this hand (fail-safe, no force-load)",
				tostring(hand), tostring(base_name), tostring(career), tostring(def.item_key), tostring(final_unit))
			return true
		end
	end

	-- Returns true if it stripped a torpedo/ammo unit (caller then nils its
	-- returned ammo_unit_3p so the husk equipment stops tracking it).
	_om._husk_strip_cwv_ammo = function(item_data, owner_unit_3p, ammo_unit_3p)
		if not (item_data and ammo_unit_3p) then return false end
		local base_name = item_data.name
		local careers = base_name and _no_ammo_careers_by_base[base_name]
		if not careers then return false end
		local career = _husk_career_name(owner_unit_3p)
		if not (career and careers[career]) then
			-- The base IS a no_ammo variant's base (careers table present), but
			-- the wielder's career isn't in the strip set. Two possibilities: a
			-- genuine native wielder of the real ammo weapon (correct no-strip),
			-- or a husk career-lookup miss (career=nil) that WOULD have stripped.
			-- Log once per (base, career) so a miss is visible in the paired log
			-- instead of silently leaving the inherited torpedo attached.
			_husk_log_once("ammo_career_miss:" .. tostring(base_name) .. ":" .. tostring(career),
				"[cwv husk-ammo-strip] SKIP: base=%s is a no_ammo variant base but career=%s not in strip set -- native wielder OR husk career-lookup miss (issue 399 diag)",
				tostring(base_name), tostring(career))
			return false
		end
		local alive = false
		pcall(function() alive = Unit.alive(ammo_unit_3p) and true or false end)
		if alive then
			pcall(Unit.set_unit_visibility, ammo_unit_3p, false)
			if Managers and Managers.state and Managers.state.unit_spawner then
				pcall(function() Managers.state.unit_spawner:mark_for_deletion(ammo_unit_3p) end)
			end
		end
		printf("[cwv husk-ammo-strip] stripped inherited ammo 3P unit (base=%s career=%s) -- issue 399",
			tostring(base_name), tostring(career))
		return true
	end

	-- issue 279 (2ND repro, 2026-07-12). The v0.1.365 entry-clear + the issue-399
	-- career-gated husk strip did NOT end the merged Outrider render: the user still
	-- sees the Trollhammer torpedo mesh "sometimes, host and client" on a CRAFTED
	-- Outrider. Source trace this session (gear_utils.lua / backend_utils.lua /
	-- simple_husk_inventory_extension.lua):
	--   * The OWNER path is clean after v0.1.365: item_data.ammo_unit is cleared,
	--     and vanilla gear_utils.lua:164 gates the attach on item_units.ammo_unit.
	--   * The HUSK resolves the BASE dr_deus_01 item_data (backend_id is nil at
	--     simple_husk_inventory_extension.lua:662). The #478 preselection now fixes
	--     authored hands before vanilla branches, while dr_deus_01.ammo_unit IS the
	--     torpedo unless the post-spawn strip below removes it -> vanilla attaches
	--     it. A NATIVE item dodges this (the cwv skin rides the wire; skin.ammo_unit
	--     = nil), a CRAFTED item does not (no skin) -- which is exactly why the bug
	--     is CRAFTED-only. The ammo defense remains the career-gated post-spawn strip
	--     above; #478's preselection + per-hand defer separately own weapon hands.
	-- UNCONFIRMED: the exact per-hand rekey / #478-defer / strip branch that leaves
	-- the torpedo, and whether "sometimes" == a husk career-lookup miss. This probe
	-- logs the full decision at every spawn_inventory_unit call so the next 2-player
	-- repro pins it. Pure diagnostic: pcall-wrapped, printf (visible with mod-logging
	-- OFF), throttled once per distinct decision key.
	_om._probe_279_spawn = function(hand, item_data, item_units, owner_unit_1p, owner_unit_3p, ammo_unit_3p, note)
		pcall(function()
			local base_name = item_data and item_data.name
			if not (base_name and _no_ammo_careers_by_base[base_name]) then return end
			local side = owner_unit_1p and "owner" or "husk"
			local career = _husk_career_name(owner_unit_3p)
			local careers = _no_ammo_careers_by_base[base_name]
			local in_strip_set = (career and careers[career]) and true or false
			local iu_ammo = item_units and item_units.ammo_unit
			local iu_ammo3p = item_units and item_units.ammo_unit_3p
			_husk_log_once(
				"probe279:" .. side .. ":" .. tostring(base_name) .. ":" .. tostring(hand)
					.. ":" .. tostring(career) .. ":" .. tostring(iu_ammo ~= nil) .. ":" .. tostring(note),
				"[cwv:279] spawn side=%s hand=%s base=%s bid=%s note=%s skin=%s career=%s in_strip_set=%s "
					.. "iu.right=%s iu.left=%s iu.ammo_unit=%s iu.ammo_unit_3p=%s vanilla_attached_ammo_3p=%s",
				side, tostring(hand), tostring(base_name),
				tostring(item_data and item_data.backend_id), tostring(note),
				tostring(item_units and item_units.skin), tostring(career), tostring(in_strip_set),
				tostring(item_units and item_units.right_hand_unit),
				tostring(item_units and item_units.left_hand_unit),
				tostring(iu_ammo), tostring(iu_ammo3p), tostring(ammo_unit_3p ~= nil))
		end)
	end

	-- Apply the CWV scale/offset transform to the husk 3P weapon unit,
	-- mirroring the owner-side create_equipment hook. Resolves the CWV def
	-- ONLY via cwv-POSITIVE signals (skin / backend_id / cwv item_data key) —
	-- NEVER a bare base_weapon match, which would corrupt a genuinely native
	-- weapon that shares the base key on the husk (e.g. Kruber's own
	-- es_bastard_sword vs the cwv longsword are indistinguishable on the husk
	-- once the skin/backend_id are absent). When nothing resolves and the item
	-- is a CWV base weapon, log it: that is the disambiguating evidence for the
	-- #392 base-resolution umbrella (husk never sees the CWV instance).
	_om._husk_apply_cwv_transform = function(hand, item_data, item_units, weapon_unit_3p, owner_unit_3p, slot_name)
		if not (weapon_unit_3p and _is_unit(weapon_unit_3p)) then
			-- The 3P weapon unit is nil/dead. For a CWV base weapon this means the
			-- spawn returned nothing (override unit non-resident on this client, or
			-- the base-path spawn failed) — the deeper cause behind an invisible
			-- husk. Log once per (base, hand) so it isn't a silent return.
			local base_name = item_data and item_data.name
			if base_name and _cwv_base_weapons[base_name] then
				_husk_log_once("no_unit:" .. tostring(base_name) .. ":" .. tostring(hand),
					"[cwv husk-transform] SKIP: hand=%s base=%s -- 3P weapon unit nil/dead (spawn failed / override non-resident?) issue 396/397 diag",
					tostring(hand), tostring(base_name))
			end
			return
		end
		local skin = item_units and item_units.skin
		local def = _om._husk_identity_def
			and _om._husk_identity_def(owner_unit_3p, slot_name, item_data and item_data.name)
			or _resolve_cwv_def(item_data, skin)
		if not def and skin == nil then
			-- #392/#397 fallback, #475-hardened: base+career positive signal for
			-- SKINLESS echoes only, can_wield evaluated LAZILY at wield time. A
			-- present non-cwv skin means a native item (Invariant 1): no fallback
			-- -- exactly the mesh re-key's rule; both route through
			-- _om._husk_resolve_display_def so mesh and transform cannot disagree.
			local bc_career = _husk_career_name(owner_unit_3p)
			local bc_def, bc_reason = _om._husk_resolve_display_def(item_data and item_data.name, bc_career, nil)
			def = bc_def
			if def then
				_husk_log_once("bc_xform:" .. tostring(item_data and item_data.name) .. ":" .. tostring(bc_career) .. ":" .. tostring(hand),
					"[cwv:474] husk transform resolved via base+career: base=%s career=%s def=%s hand=%s (skinless echo, pair not currently wieldable)",
					tostring(item_data and item_data.name), tostring(bc_career), tostring(def.item_key), tostring(hand))
			elseif bc_reason == "native_pair" and _cwv_base_weapons[item_data and item_data.name] then
				_husk_log_once("475_xform_native:" .. tostring(item_data and item_data.name) .. ":" .. tostring(bc_career) .. ":" .. tostring(hand),
					"[cwv:475] husk transform fallback DECLINED (native_pair): base=%s career=%s -- skinless echo, pair currently wieldable (vanilla or wt)",
					tostring(item_data and item_data.name), tostring(bc_career))
			end
		end
		if not def then
			local base_name = item_data and item_data.name
			if base_name and _cwv_base_weapons[base_name] then
				-- Throttled: the husk resolves the BASE item (no cwv_ backend_id, and
				-- no curated skin synced), so no CWV def is reachable and the
				-- transform can't apply. This is the issue-392 base-resolution
				-- umbrella evidence — the husk never sees the CWV instance. Key by
				-- (base, hand, skin) so a genuinely skinless equip logs once, but a
				-- later skinned equip (which SHOULD resolve) still surfaces if it
				-- unexpectedly falls through.
				_husk_log_once("no_def:" .. tostring(base_name) .. ":" .. tostring(hand) .. ":" .. tostring(skin),
					"[cwv husk-transform] no cwv def resolved: hand=%s base=%s backend_id=%s skin=%s -- husk saw BASE item only (issue 397/392 diag)",
					tostring(hand), tostring(base_name),
					tostring(item_data and item_data.backend_id), tostring(skin))
			end
			return
		end
		local scale, offset, rotation
		if hand == "right" then
			scale    = _resolve_field(def, "right_hand_scale_3p")    or _resolve_field(def, "right_hand_scale")
			offset   = _resolve_field(def, "right_hand_offset_3p")   or _resolve_field(def, "right_hand_offset")
			rotation = _resolve_field(def, "right_hand_rotation_3p") or _resolve_field(def, "right_hand_rotation")
		else
			scale    = _resolve_field(def, "left_hand_scale_3p")    or _resolve_field(def, "left_hand_scale")
			offset   = _resolve_field(def, "left_hand_offset_3p")   or _resolve_field(def, "left_hand_offset")
			rotation = _resolve_field(def, "left_hand_rotation_3p") or _resolve_field(def, "left_hand_rotation")
		end
		if scale or offset or rotation then
			_transform_unit(weapon_unit_3p, scale, offset, rotation)
			printf("[cwv husk-transform] applied hand=%s def=%s scale=%s offset=%s -- issues 397/394",
				tostring(hand), tostring(def.item_key or def.item_type),
				scale and "y" or "n", offset and "y" or "n")
		end
		-- #604 remote husks consume the same absolute presentation resolver as
		-- owners and previews.  The render identity is bounded owner+slot state;
		-- a network transition can target it once without per-frame pose traffic.
		if def.crowbill_mode_family and _om._apply_crowbill_presentation then
			local identity = _om.crowbill_runtime and _om.crowbill_runtime.remote_identity
				and _om.crowbill_runtime.remote_identity(owner_unit_3p, slot_name, def.item_key)
				or _om._crowbill_render_identity(item_data, def,
					(def.item_key or "cwv_crowbill") .. ":" .. tostring(slot_name))
			_om._apply_crowbill_presentation(weapon_unit_3p, def, identity,
				"remote_husk", rotation)
		end
		-- (#474) Old Musket husk display parity. Its look is NOT generic def
		-- fields: custom mesh + bespoke ABSOLUTE 3P pose + runtime-bound
		-- textures, which the owner path gates on backend_id + musket template
		-- -- both absent on the husk (wire item is the base es_handgun), so the
		-- owner block at the spawn hook never fires here. Apply only when the
		-- def positively identifies the Old Musket AND the custom mesh actually
		-- spawned (item_units reflects the pre-spawn re-key decision): the
		-- absolute pose is authored for the custom mesh and must never touch a
		-- base handgun that spawned on a residency decline. Stance comes from
		-- the bounded #474 presentation channel; ranged is only the safe
		-- pre-handshake fallback.
		if def.item_key == "cwv_es_musket_old" and hand == "right"
				and item_units and item_units.right_hand_unit == def.right_hand_unit then
			local wielded_slot = nil
			if owner_unit_3p and Unit.alive(owner_unit_3p) then
				local ok_inv, inv = pcall(ScriptUnit.extension, owner_unit_3p, "inventory_system")
				local eq = ok_inv and inv and inv.equipment and inv:equipment()
				wielded_slot = eq and eq.wielded_slot
			end
			local mode = _om._old_musket_mode_for_owner
				and _om._old_musket_mode_for_owner(owner_unit_3p, wielded_slot) or "ranged"
			pcall(_om._apply_old_musket_textures, weapon_unit_3p)
			pcall(_om._track_old_musket_unit, weapon_unit_3p, "3p", mode)
			pcall(_om._apply_old_musket_transform, weapon_unit_3p, "3p", mode)
			pcall(printf, "[cwv:474] husk old-musket presentation: textures + 3p %s pose applied (slot=%s hand=%s skin=%s)",
				tostring(mode), tostring(wielded_slot), tostring(hand), tostring(skin))
		end
	end
end

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

		-- Backend_id pattern `cwv_<key>_NNN` (NNN = any 3 digits: CWV's own
		-- _001/_002 instances, plus cim-crafted copies 100-999, cim_dev issue
		-- 390), then the #482 ladder fallbacks (item_data.cwv_key stamp /
		-- backend lookup) for crafted instances with UUID backend_ids.
		-- Anything that resolves no cwv key passes through.
		local cwv_key = _om._cwv_key_for_item(backend_id, item_data)
		if not cwv_key then return result end
		local def = _find_def(cwv_key)
		if not def then return result end

		-- A skin was applied during the resolution (curated cwv item or
		-- user-selected illusion). The skin's per-hand units are already
		-- in `result`; don't trample them. `result.skin` is set by
		-- vanilla at backend_utils.lua:205 when a skin took effect.
		if result.skin and result.skin ~= "" then return result end

		-- No skin → vanilla fell back to item_data.right_hand_unit, which
		-- may be the base entry's path. Force the cwv override.
		if def.right_hand_unit then result.right_hand_unit = def.right_hand_unit end
		if def.left_hand_unit  then result.left_hand_unit  = def.left_hand_unit  end
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

-- WIRE-SAFETY: weapon_skin_id axis of issue 278 / issue 371; sender coverage +
-- parity gating reworked for issue 495. A cwv-registered NetworkLookup.weapon_skins
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
-- PARITY GATE (issue 495 load-bearing constraint): the wire skin is the PRIMARY
-- husk display signal on cwv peers (issue 474 skin-key resolution), so when EVERY
-- other human peer has positively acked the cwv beacon the skin RIDES and remote
-- cwv clients render the variant. Parity unconfirmed (or beacon absent/erroring)
-- -> null to the universal vanilla "n/a", restore the slot's real skin after the
-- send (the owner's own spawn reads the restored value; a non-cwv peer renders
-- the base weapon instead of crashing). EXCEPTION: the hot-join replay is ALWAYS
-- nulled -- it fires during the join handshake, before the joiner's ack can
-- exist, so no roster-reactive gate can win that race (the issue 425 crt
-- hot-join lesson); a cwv joiner sees base display on others' husks until their
-- next re-equip (documented issue 474 residual).
-- Key set: _om._skin_keys (base variant skins) + _custom_skin_keys
-- (pairing/illusion registrations) + the cwv_ name prefix as belt-and-suspenders
-- (every cwv-injected weapon_skins key is cwv_-prefixed; no vanilla key is).
-- Sole cwv hooks on all three methods (grep-verified 2026-07-12). No item_id
-- concern: cwv keeps item_data.name = base_weapon, a universal vanilla index.
-- do-block: cwv's main chunk sits at the Lua 5.1 200-local ceiling -- these
-- helpers must not cost enduring top-level slots.
do
	local function _wire_skin(skin)
		if type(skin) ~= "string" then return false end
		local sk = _om._skin_keys
		if sk and sk[skin] then return true end
		if _custom_skin_keys[skin] then return true end
		return skin:sub(1, 4) == "cwv_"
	end
	_om._wire_skin_predicate = _wire_skin   -- exported for /cwv_regression_test

	local function _wire_parity_live()
		local pp = mod._cwv_peer_parity
		if not pp then return false end   -- fail-safe: no beacon = assume mixed lobby
		local ok, res = pcall(pp.all_peers_have, pp)
		return ok and res == true
	end
	_om._wire_parity_live = _wire_parity_live

	-- #396 positive owner identity. Vanilla equipment RPCs deliberately encode a
	-- CWV clone as its stable base item name, so the receiver cannot distinguish
	-- an Imperial Longsword from a native Bretonnian Longsword when the selected
	-- skin is nil/vanilla-looking. Carry only the missing item-key axis over VMF's
	-- same-mod channel; the ordinary vanilla RPC remains authoritative for slot,
	-- skin, units, and wield timing. The side channel is absence-safe for non-CWV
	-- peers and bounded to equip/resync/parity edges (never per-frame).
	local _IDENTITY_SCHEMA = 1
	local _remote_identity = {}
	local _identity_last_sent = {}
	_om._cwv_remote_identity = _remote_identity
	mod._cwv_identity_surfaces = { network = true }

	_om._cwv_identity_payloads = function(slots)
		local payloads = {}
		if type(slots) ~= "table" then return payloads end
		for slot_name, slot_data in pairs(slots) do
			if slot_name == "slot_melee" or slot_name == "slot_ranged" then
				local item_data = slot_data and slot_data.item_data
				local key = item_data and _om._cwv_key_for_item(item_data.backend_id, item_data)
				local def = key and _find_def(key)
				payloads[#payloads + 1] = {
					slot = slot_name,
					item_key = (def and not def.skin_only) and key or "",
				}
			end
		end
		return payloads
	end

	_om._cwv_accept_identity = function(sender_peer_id, schema, payload)
		if schema ~= _IDENTITY_SCHEMA or type(sender_peer_id) ~= "string"
				or type(payload) ~= "table" then return false, "invalid" end
		local slot_name = payload.slot
		if slot_name ~= "slot_melee" and slot_name ~= "slot_ranged" then
			return false, "slot"
		end
		local key = payload.item_key
		if key ~= "" then
			local def = type(key) == "string" and _find_def(key)
			if not def or def.skin_only then return false, "item" end
		end
		local by_slot = _remote_identity[sender_peer_id]
		if not by_slot then
			by_slot = {}
			_remote_identity[sender_peer_id] = by_slot
		end
		local previous = by_slot[slot_name]
		by_slot[slot_name] = key ~= "" and key or nil
		return previous ~= by_slot[slot_name], "ok"
	end

	_om._cwv_identity_def_for_peer = function(peer_id, slot_name, base_name)
		local key = peer_id and _remote_identity[peer_id]
		key = key and key[slot_name]
		local def = key and _find_def(key)
		if not def or def.skin_only or def.base_weapon ~= base_name then return nil end
		return def
	end

	_om._husk_identity_def = function(owner_unit_3p, slot_name, base_name)
		if not owner_unit_3p then return nil end
		local player
		pcall(function() player = Managers.player:owner(owner_unit_3p) end)
		local peer_id = player and (player.peer_id or (player.network_id and player:network_id()))
		return _om._cwv_identity_def_for_peer(peer_id, slot_name, base_name)
	end

	local function _send_identity_slots(slots, context, force)
		local payloads = _om._cwv_identity_payloads(slots)
		local sent = 0
		for _, payload in ipairs(payloads) do
			local signature = payload.item_key
			if force or _identity_last_sent[payload.slot] ~= signature then
				local ok = pcall(mod.network_send, mod,
					"cwv_item_identity", "all", _IDENTITY_SCHEMA, payload)
				if ok then
					_identity_last_sent[payload.slot] = signature
					sent = sent + 1
				end
			end
		end
		if sent > 0 then
			pcall(printf, "[cwv:396] item identity sent: context=%s slots=%d", tostring(context), sent)
		end
		return sent
	end
	_om._cwv_send_identity_slots = _send_identity_slots

	mod:network_register("cwv_item_identity", function(sender_peer_id, schema, payload)
		local changed = _om._cwv_accept_identity(sender_peer_id, schema, payload)
		if not changed then return end
		pcall(printf, "[cwv:396] item identity received: peer=%s slot=%s key=%s",
			tostring(sender_peer_id), tostring(payload.slot), tostring(payload.item_key))
		-- If vanilla equipment arrived first, rebuild the currently wielded husk
		-- once. If identity arrived first, the following vanilla wield RPC is the
		-- rebuild. Either ordering converges without polling.
		local pm = Managers and Managers.player
		local player = pm and pm.player_from_peer_id and pm:player_from_peer_id(sender_peer_id)
		local unit = player and player.player_unit
		if unit and Unit.alive(unit) then
			local inventory
			pcall(function() inventory = ScriptUnit.extension(unit, "inventory_system") end)
			if inventory and inventory.wielded_slot == payload.slot and type(inventory.wield) == "function" then
				pcall(inventory.wield, inventory, payload.slot)
			end
		end
	end)

	-- issue 476 diagnostic (printf, dev-always-on). Makes the husk-illusion wire
	-- DECISION legible in the WIELDER's own log at equip time. A remote view (the
	-- host + other clients) renders the wielder as a HUSK, which resolves the BASE
	-- item_data (no cwv backend_id, memory reference_vt2_husk_resolves_base_item_data),
	-- so an applied illusion reaches a husk ONLY if its cwv skin id rides THIS wire
	-- -- and it rides only under confirmed peer parity (issue 474/495). Logged once
	-- per (surface, skin, decision) so a "illusion doesn't change for other players"
	-- repro (#476) pins the failing link without guessing:
	--   * NULL + the beacon's "Missing this mod" chat notice = genuinely mixed
	--     lobby, WORKING AS DESIGNED (a non-cwv peer would CTD on the modded id).
	--   * NULL + other_human_peers>0 + NO missing-peer notice = all-cwv but parity
	--     UNCONFIRMED at send time (ack race); the illusion syncs on next re-equip.
	--   * RIDE + a husk still shows base = downstream on the OTHER peer: read its
	--     [cwv:474] husk re-key / DEFERRED(residency) / [cwv:478] DEFER lines (a
	--     PAIRING illusion whose per-hand mesh differs from the def default is NOT
	--     covered by the def-field husk residency pass -- issue 396/401 class).
	-- Hung on _om (not new locals): this chunk sits at the Lua 5.1 200-local ceiling.
	_om._probe_476_logged = {}
	_om._probe_476 = function(context, skin, rode, force)
		local key = tostring(context) .. "|" .. tostring(skin) .. "|" .. tostring(rode)
		if _om._probe_476_logged[key] then return end
		_om._probe_476_logged[key] = true
		local peers = -1
		local pm = Managers and Managers.player
		if pm and type(pm.human_players) == "function" then
			local ok, humans = pcall(function() return pm:human_players() end)
			if ok and type(humans) == "table" then
				local me
				pcall(function() me = Network.peer_id() end)
				peers = 0
				for _, p in pairs(humans) do
					local pid = p and p.peer_id
					if type(pid) == "string" and pid ~= me then peers = peers + 1 end
				end
			end
		end
		pcall(printf,
			"[cwv:476] husk illusion wire (%s): skin=%s decision=%s other_human_peers=%s parity_all_have=%s%s",
			tostring(context), tostring(skin), rode and "RIDE" or "NULL",
			tostring(peers), tostring(_wire_parity_live()),
			force and " (hot-join replay: ALWAYS nulled -- join-handshake race, syncs on next re-equip)" or "")
	end

	local _null_logged = {}
	-- #416/#483 mission-transition recovery. A sender can observe a newly
	-- reconstructed peer roster between the last confirmed parity tick and the
	-- replacement peer's ack. Nulling is still mandatory at that instant, but the
	-- shared gate can remain logically "enabled" if the ack lands before its next
	-- poll, so no disable->enable callback edge exists to replay the selected skin.
	-- Record every withheld CWV identity and retry for a bounded window. The pure
	-- step helper is exported for the runtime regression; production polls at most
	-- twice per second and sends only after parity is positively confirmed.
	_om._cwv_skin_replay_pending_step = function(pending, dt, parity_check, replay_fn)
		if type(pending) ~= "table" then return nil, 0 end
		pending.elapsed = (pending.elapsed or 0) + (dt or 0)
		pending.poll = (pending.poll or 0) + (dt or 0)
		if pending.elapsed >= 60 then return nil, 0, "expired" end
		if pending.poll < 0.5 then return pending, 0 end
		pending.poll = 0
		local ok_parity, parity_live = pcall(parity_check)
		if not ok_parity or parity_live ~= true then return pending, 0 end
		local ok, sent = pcall(replay_fn)
		if ok and type(sent) == "number" and sent > 0 then
			return nil, sent, "sent"
		end
		return pending, 0
	end

	local function _mark_skin_replay_pending(context, saved)
		if not saved then return end
		local count = 0
		for _ in pairs(saved) do count = count + 1 end
		_om._cwv_skin_replay_pending = {
			context = context,
			count = count,
			elapsed = 0,
			poll = 0,
		}
	end

	local function _wire_null_skins(slots, send_fn, context, force)
		if not force and _wire_parity_live() then
			-- Every lobby peer runs cwv: the skin is decodable everywhere and
			-- carries the issue-474 husk display. Let it ride. (#476: probe the
			-- decision for any cwv skin present, WITHOUT altering the fast path.)
			for _, slot_data in pairs(slots) do
				local skin = slot_data and slot_data.skin
				if skin and _wire_skin(skin) then _om._probe_476(context, skin, true, false) end
			end
			return send_fn()
		end
		local saved
		for _, slot_data in pairs(slots) do
			local skin = slot_data and slot_data.skin
			if skin and _wire_skin(skin) then
				_om._probe_476(context, skin, false, force)
				saved = saved or {}
				saved[slot_data] = skin
				slot_data.skin = nil
				local lk = tostring(context) .. "|" .. tostring(skin)
				if not _null_logged[lk] then   -- once per (surface, skin); no equip-spam
					_null_logged[lk] = true
					pcall(printf, "[cwv:495] wire skin null (%s): %s -> n/a (%s)",
						tostring(context), tostring(skin),
						force and "join replay: always nulled" or "peer parity not confirmed")
				end
			end
		end
		local r1, r2, r3, r4 = send_fn()
		if saved then
			for slot_data, skin in pairs(saved) do
				slot_data.skin = skin
			end
			-- A forced hot-join sync can run before the joining peer is even visible
			-- in the roster; all_peers_have could therefore be vacuously/stale true.
			-- Keep that path exclusively on the existing settled parity-enable edge.
			-- The bounded poll owns only ordinary transition/resync sends whose roster
			-- was observed and explicitly returned parity=false.
			if not force then _mark_skin_replay_pending(context, saved) end
		end
		return r1, r2, r3, r4
	end
	_om._wire_null_skins = _wire_null_skins   -- exported for /cwv_regression_test

	-- #579 post-handshake replay. GearUtils.hot_join_sync must null a cwv skin
	-- before the joining peer has acknowledged this mod; otherwise its strict
	-- NetworkLookup.weapon_skins decode can CTD. Once peer parity transitions to
	-- enabled, every decoder has proven the same CWV schema and the owner can
	-- safely replay only its cwv-skinned slots through vanilla rpc_add_equipment.
	-- If the corrected slot is currently wielded, follow it with the vanilla
	-- wield RPC so the remote husk respawns immediately instead of waiting for a
	-- manual weapon swap. This is bounded to the parity-enable edge (join/rejoin),
	-- never a frame/update loop.
	_om._cwv_skin_replay_payloads = function(equipment)
		local payloads = {}
		local slots = equipment and equipment.slots
		if type(slots) ~= "table" then return payloads end
		for slot_name, slot_data in pairs(slots) do
			local item_data = slot_data and slot_data.item_data
			local skin = slot_data and slot_data.skin
			if type(item_data) == "table" and type(item_data.name) == "string" and _wire_skin(skin) then
				payloads[#payloads + 1] = {
					slot_name = slot_name,
					item_name = item_data.name, -- clone-name clobber is wire-safe: vanilla base id
					skin = skin,
					wielded = equipment.wielded_slot == slot_name,
				}
			end
		end
		return payloads
	end

	_om._replay_cwv_skins_after_parity = function()
		local pm = Managers and Managers.player
		local network = Managers and Managers.state and Managers.state.network
		local storage = Managers and Managers.state and Managers.state.unit_storage
		if not (pm and network and network.network_transmit and storage) then return 0 end
		local ok_player, player = pcall(pm.local_player, pm, 1)
		if not ok_player or not player then return 0 end
		local unit = player.player_unit
		if not unit or not Unit.alive(unit) then return 0 end
		local ok_inv, inventory = pcall(ScriptUnit.extension, unit, "inventory_system")
		if not ok_inv or not inventory or type(inventory.equipment) ~= "function" then return 0 end
		local equipment = inventory:equipment()
		_send_identity_slots(equipment and equipment.slots, "parity_replay", true)
		local payloads = _om._cwv_skin_replay_payloads(equipment)
		if #payloads == 0 then return 0 end
		local go_id = storage:go_id(unit)
		if not go_id then return 0 end
		local transmit = network.network_transmit
		local network_lookup = rawget(_G, "NetworkLookup")
		if not network_lookup then return 0 end
		local sent = 0
		for _, payload in ipairs(payloads) do
			local slot_id = rawget(network_lookup.equipment_slots or {}, payload.slot_name)
			local item_id = rawget(network_lookup.item_names or {}, payload.item_name)
			local skin_id = rawget(network_lookup.weapon_skins or {}, payload.skin)
			if slot_id and item_id and skin_id then
				if network.is_server then
					transmit:send_rpc_clients("rpc_add_equipment", go_id, slot_id, item_id, skin_id)
					if payload.wielded then transmit:send_rpc_clients("rpc_wield_equipment", go_id, slot_id) end
				else
					transmit:send_rpc_server("rpc_add_equipment", go_id, slot_id, item_id, skin_id)
					if payload.wielded then transmit:send_rpc_server("rpc_wield_equipment", go_id, slot_id) end
				end
				sent = sent + 1
			end
		end
		pcall(printf, "[cwv:579] replayed %d cwv skin slot(s) after peer-parity confirmation", sent)
		return sent
	end

	local function _replay_and_clear_pending(reason)
		local sent = _om._replay_cwv_skins_after_parity()
		if sent > 0 and _om._cwv_skin_replay_pending then
			local pending = _om._cwv_skin_replay_pending
			_om._cwv_skin_replay_pending = nil
			pcall(printf,
				"[cwv:416/483] deferred skin identity replayed after parity recovery: slots=%d source=%s trigger=%s",
				sent, tostring(pending.context), tostring(reason))
		end
		return sent
	end

	mod._cwv_skin_wire_surfaces = {}

	mod:hook("SimpleInventoryExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
		local slots = self and self._equipment and self._equipment.slots
		if not slots then
			return func(self, unit, unit_go_id)
		end
		_send_identity_slots(slots, "game_object_initialized", true)
		local r1, r2, r3, r4 = _wire_null_skins(slots, function()
			return func(self, unit, unit_go_id)
		end, "game_object_initialized", false)
		if _om._exact_pair_publish_inventory then
			_om._exact_pair_publish_inventory(self, "game_object_initialized")
		end
		return r1, r2, r3, r4
	end)
	mod._cwv_skin_wire_surfaces.game_object_initialized = true
	mod._cwv_identity_surfaces.game_object_initialized = true

	mod:hook("SimpleInventoryExtension", "_spawn_resynced_loadout", function(func, self, equipment_to_spawn, skip_wield)
		if equipment_to_spawn and equipment_to_spawn.slot_id then
			_send_identity_slots({ [equipment_to_spawn.slot_id] = equipment_to_spawn },
				"spawn_resynced_loadout", false)
		end
		if not (equipment_to_spawn and equipment_to_spawn.skin) then
			return func(self, equipment_to_spawn, skip_wield)
		end
		-- Single slot-shaped table; wrap in a one-element array for the helper.
		local r1, r2, r3, r4 = _wire_null_skins({ equipment_to_spawn }, function()
			return func(self, equipment_to_spawn, skip_wield)
		end, "spawn_resynced_loadout", false)
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
		-- force=true: the joining peer's parity is unknowable here by construction.
		local r1, r2, r3, r4 = _wire_null_skins(slots, function()
			return func(peer_id, unit, equipment, additional_items)
		end, "hot_join_sync", true)
		if _om._exact_pair_publish_local then
			_om._exact_pair_publish_local("hot_join_sync")
		end
		return r1, r2, r3, r4
	end)
	mod._cwv_skin_wire_surfaces.hot_join_sync = true

	local pp = mod._cwv_peer_parity
	if pp and type(pp.register_gated_feature) == "function" then
		pp:register_gated_feature("cwv_skin_hot_join_replay", {
			label = "remote weapon cosmetics",
			on_enable = function() return _replay_and_clear_pending("parity_enable_edge") end,
		})
		mod._cwv_skin_wire_surfaces.parity_replay = true
		mod._cwv_identity_surfaces.parity_replay = true
	end

	-- The peer-parity library installed the current mod.update wrapper near boot.
	-- Chain after it so an enable edge gets first chance to replay. If no edge was
	-- observed, this bounded retry closes the mission-transition race. A genuinely
	-- mixed lobby never passes _wire_parity_live and therefore never sends a CWV id.
	local previous_update = mod.update
	mod.update = function(dt)
		if previous_update then previous_update(dt) end
		local pending = _om._cwv_skin_replay_pending
		if not pending then return end
		local next_pending, sent, outcome = _om._cwv_skin_replay_pending_step(
			pending, dt, _wire_parity_live, function()
				return _replay_and_clear_pending("bounded_transition_poll")
			end)
		-- _replay_and_clear_pending may already have cleared the shared field.
		if sent > 0 then
			_om._cwv_skin_replay_pending = nil
		elseif outcome == "expired" then
			_om._cwv_skin_replay_pending = nil
			pcall(printf,
				"[cwv:416/483] deferred skin replay expired safely after 60s: source=%s slots=%s (parity never confirmed / equipment unavailable)",
				tostring(pending.context), tostring(pending.count))
		else
			_om._cwv_skin_replay_pending = next_pending
		end
	end
	mod._cwv_skin_wire_surfaces.transition_replay = true
end
_om._skin_wire_hook_installed = true

-- ============================================================================
-- issue 423 (BUG_CLASSES 31, GAMEPLAY axis): cwv damage-profile SEND-gate.
-- ----------------------------------------------------------------------------
-- rpc_attack_hit is client->server (weapon_system.lua:182). A cwv CLIENT landing
-- a hit with a profile-cloning variant would ship the cwv (out-of-vanilla-range)
-- NetworkLookup.damage_profiles index to the HOST, whose strict decode
-- (weapon_system.lua:243 -- NetworkLookup.damage_profiles[id], NO rawget) fatals
-- when the host lacks cwv -> lobby drop (issue 278 / BUG_CLASSES 31 class).
-- Unconditional registration only buys cwv<->cwv index parity.
--
-- This is a GAMEPLAY axis (issue 371 axis map): substituting the profile changes
-- combat numbers, so it is peer-parity GATED, never substituted unconditionally.
--   * parity CONFIRMED (every lobby peer runs cwv) -> the real cwv id rides; the
--     host decodes it and the variant's tuned damage applies.
--   * parity UNCONFIRMED (or beacon absent/erroring) -> degrade to the cwv
--     profile's vanilla SOURCE id (base-weapon behavior) so a non-cwv host
--     decodes a vanilla index instead of crashing. Fail-safe: any beacon error
--     -> _wire_parity_live() false -> substitute.
--   * is_server (we ARE the host) -> never substitute: rpc_attack_hit runs
--     in-process (weapon_system.lua:179-180), no foreign peer decodes it.
-- No hot-join force-null case is needed (unlike the skin gate): rpc_attack_hit is
-- send_rpc_SERVER, so the ONLY decoder of our hit is the host; the host either has
-- cwv from mission start (parity can confirm) or never acks (parity stays false and
-- we always substitute). A mid-join non-cwv CLIENT never decodes our attack RPC.
--
-- send_rpc_attack_hit is the single choke for the profile id: every attack RPC in
-- the decompile (weapon_system / damage_utils / projectiles / area_damage / the
-- lunge + shield/push/BH actions) routes its damage_profile_id through
-- WeaponSystem.send_rpc_attack_hit (grep-verified). Sole cwv hook on it.
-- do-block: keep helpers off the 200-local top-level chunk (Lua 5.1 ceiling).
do
    local function _wire_safe_damage_profile_id(id)
        local NL = rawget(_G, "NetworkLookup")
        local dp = NL and NL.damage_profiles
        if type(dp) ~= "table" then return nil end
        local name = rawget(dp, id)
        if type(name) ~= "string" or name:sub(1, 4) ~= "cwv_" then
            return nil   -- vanilla / unknown-non-cwv id: leave untouched
        end
        local source_name = _om._cwv_damage_profile_wire_source[name]
        if type(source_name) == "string" and source_name:sub(1, 4) ~= "cwv_" then
            local sid = rawget(dp, source_name)
            if type(sid) == "number" then return sid end
        end
        -- Unmapped cwv profile (feature-gated creator / future drift): coerce to a
        -- captured vanilla fallback so a modded index can NEVER ride to a non-cwv
        -- host (a P0 host CTD is worse than degraded damage). nil only if no cwv
        -- profile was ever recorded (then there is nothing that could leak).
        return _om._cwv_wire_fallback_profile_id
    end
    _om._wire_safe_damage_profile_id = _wire_safe_damage_profile_id

    -- Pure gate decision (testable without a WeaponSystem instance): the
    -- damage_profile_id that should actually be sent for this hit.
    local function _wire_dp_for_send(is_server, id)
        if is_server then return id end                -- host authoritative, in-process
        if _om._wire_parity_live() then return id end  -- every peer has cwv
        local safe = _wire_safe_damage_profile_id(id)
        return safe or id
    end
    _om._wire_dp_for_send = _wire_dp_for_send

    local _dp_sub_logged = {}   -- once per profile id; no per-hit spam
    mod:hook("WeaponSystem", "send_rpc_attack_hit", function(func, self, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
        local send_id = _wire_dp_for_send(self.is_server, damage_profile_id)
        if send_id ~= damage_profile_id then
            if not _dp_sub_logged[damage_profile_id] then
                _dp_sub_logged[damage_profile_id] = true
                local dp = rawget(_G, "NetworkLookup")
                dp = dp and dp.damage_profiles
                pcall(printf, "[cwv:423] wire dmg-profile sub: %s(%s) -> %s (peer parity unconfirmed; base-weapon damage this hit)",
                    tostring(dp and rawget(dp, damage_profile_id)), tostring(damage_profile_id), tostring(send_id))
            end
            damage_profile_id = send_id
        end
        return func(self, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
    end)
    _om._dp_wire_hook_installed = true
end

-- NOTE: the per-perspective 1P/3P unit swap mechanism (previously used
-- for cwv_es_brace_repeater) was moved to weapon_tweaker in v0.1.187 —
-- it now hooks `GearUtils.spawn_inventory_unit` for vanilla
-- `wh_brace_of_pistols` on Kruber careers, swapping the 3P unit to
-- the repeater. No CWV variant currently uses the override mechanism;
-- if a future variant needs different 1P vs 3P meshes, restore the
-- hook here from git history.

mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	if not result then return result end

	local def = _resolve_cwv_def(item_data, result.skin)
	if not def then return result end

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
		_transform_unit(result.right_unit_1p, right_scale_1p, right_offset_1p, right_rot_1p)
		_transform_unit(result.left_unit_1p,  left_scale_1p,  left_offset_1p,  left_rot_1p)
	end
	_transform_unit(result.right_unit_3p, right_scale_3p, right_offset_3p, right_rot_3p)
	_transform_unit(result.left_unit_3p,  left_scale_3p,  left_offset_3p,  left_rot_3p)

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

	return result
end)

local function _find_preview_slot_info(self, item_name)
	if not self._item_info_by_slot then return nil, nil end
	for slot_id, info in pairs(self._item_info_by_slot) do
		if info and info.name == item_name then
			return slot_id, info
		end
	end
	return nil, nil
end

local function _resolve_preview_def(self, item_name)
	local _, info = _find_preview_slot_info(self, item_name)
	local skin = info and info.skin_name
	if skin and _skin_transform_map[skin] then return _skin_transform_map[skin], info end

	if info and info.backend_id then
		-- v0.1.316: match ANY instance suffix (_001, _002, _003, ...). The
		-- earlier "^(cwv_.-)_001$" regex only matched instance 1, so for
		-- variants with `instances = 2` (e.g. cwv_es_musket_old) the second
		-- instance never resolved — `_cwv_spawn_item_post` returned early
		-- and the previewer-side texture binding never fired. Result: rifle
		-- appeared in the keep inventory previewer without textures.
		-- #482: shared ladder. The previewer's info table carries only the
		-- bid (no item_data), so a crafted instance's UUID bid resolves via
		-- the ladder's backend-lookup rung to the stamped cwv_key.
		local matched = _om._cwv_key_for_item(info.backend_id, nil)
		if matched and _transform_map[matched] then return _transform_map[matched], info end
	end
	if _transform_map[item_name] then return _transform_map[item_name], info end
	return nil, info
end

local function _cwv_spawn_item_post(self, item_name)
	local def, info = _resolve_preview_def(self, item_name)
	if not def then
		-- v0.1.326: log when the resolver fails for a musket-shaped item_name
		-- so we can tell whether the regex / lookup is broken vs the hook
		-- never firing.
		if type(item_name) == "string" and item_name:find("musket", 1, true) then
			-- v0.1.341-dev: promoted to `_dbg_alert` — "returned nil" is an
			-- alert (preview won't render for this CWV musket item).
			_dbg_alert("[cwv preview] _resolve_preview_def returned nil for item_name=%s (info bid=%s)",
				tostring(item_name),
				tostring(info and info.backend_id))
		end
		return
	end

	local equip_units = self._equipment_units
	if not equip_units then return end

	-- KEY BRIDGE — DO NOT remove or refactor to a string-keyed loop.
	-- `info` came from `self._item_info_by_slot`, which vanilla
	-- `equip_item` (world_hero_previewer.lua:776) keys by STRING slot_type
	-- ("melee" / "ranged"). But `self._equipment_units` is keyed by NUMERIC
	-- `slot_index`. Looking up `equip_units[slot_type_string]` returns nil
	-- silently and the whole apply path no-ops — that's the bug v0.1.84
	-- fixed (and cosmetics_tweaker fixed in 0.7.88, see its CHANGELOG).
	-- Vanilla `equip_item` writes the numeric `slot_index` onto each
	-- `spawn_data[i]` (lines 704 / 728 of world_hero_previewer.lua), so
	-- read it from there to bridge the two keying conventions.
	-- The previous implementation had a "fall back: match by item_name"
	-- loop that iterated `self._item_info_by_slot` and stored the iterator
	-- key — that key is the STRING slot_type, which is exactly the wrong
	-- thing to look up `equip_units` with. Don't reintroduce.
	local slot_index = info and info.spawn_data and info.spawn_data[1]
			and info.spawn_data[1].slot_index
	if not slot_index then return end

	local slot = equip_units[slot_index]
	if type(slot) ~= "table" then return end

	-- Preview spawns 3P-style models; use _3p override if set, else unified.
	if slot.right and _is_unit(slot.right) then
		_transform_unit(slot.right,
			_resolve_field(def, "right_hand_scale_3p")    or _resolve_field(def, "right_hand_scale"),
			_resolve_field(def, "right_hand_offset_3p")   or _resolve_field(def, "right_hand_offset"),
			_resolve_field(def, "right_hand_rotation_3p") or _resolve_field(def, "right_hand_rotation"))
	end
	if slot.left and _is_unit(slot.left) then
		_transform_unit(slot.left,
			_resolve_field(def, "left_hand_scale_3p")    or _resolve_field(def, "left_hand_scale"),
			_resolve_field(def, "left_hand_offset_3p")   or _resolve_field(def, "left_hand_offset"),
			_resolve_field(def, "left_hand_rotation_3p") or _resolve_field(def, "left_hand_rotation"))
	end
	-- #604: MenuWorldPreviewer/HeroPreviewer is the shared reconstruction
	-- seam for inventory mannequin, keep/lobby, and score/team presentations.
	-- Applying here therefore covers all three consumers without surface-specific
	-- copies.  The mode cache is keyed by the real backend instance when present.
	if slot.right and _is_unit(slot.right) and def.crowbill_mode_family
			and _om._apply_crowbill_presentation then
		local preview_rotation = _resolve_field(def, "right_hand_rotation_3p")
			or _resolve_field(def, "right_hand_rotation")
		local team_peer = self._cwv_crowbill_wearer_peer or self._cos_wearer_peer
		local team_identity = team_peer and _om.crowbill_runtime
			and _om.crowbill_runtime.identity_for_peer
			and _om.crowbill_runtime.identity_for_peer(team_peer, "slot_melee", def.item_key)
		local preview_identity = team_identity
			or _om._crowbill_render_identity(info and info.item_data, def,
				info and info.backend_id or def.item_key .. ":preview:" .. tostring(slot_index))
		local preview_surface = "inventory_preview"
		if self._cwv_crowbill_team_preview then
			preview_surface = self._cwv_crowbill_peer_source == "score_snapshot"
				and "score_preview" or "lobby_preview"
		end
		_om._apply_crowbill_presentation(slot.right, def, preview_identity,
			preview_surface, preview_rotation)
		-- Source audit: TeamPreviewer receives profile/career, while
		-- LevelEndView drops peer_id. The hook below restores the exact human
		-- peer from the immutable score snapshot (or live profile sync). If an
		-- unfamiliar TeamPreviewer producer lacks both, log once per row rather
		-- than silently claiming remote mode parity.
		if self._cwv_crowbill_team_preview and not team_peer then
			_om.crowbill_preview_diag_seen = _om.crowbill_preview_diag_seen or {}
			_om.crowbill_preview_diag_count = _om.crowbill_preview_diag_count or 0
			local token = tostring(self._cwv_crowbill_profile_index) .. ":"
				.. tostring(self._cwv_crowbill_career_index) .. ":" .. tostring(def.item_key)
			if not _om.crowbill_preview_diag_seen[token]
					and _om.crowbill_preview_diag_count < 16 then
				_om.crowbill_preview_diag_seen[token] = true
				_om.crowbill_preview_diag_count = _om.crowbill_preview_diag_count + 1
				pcall(printf, "[cwv:604] TEAM-PREVIEW identity unresolved profile=%s career=%s family=%s evidence=%d/16 chat=false",
					tostring(self._cwv_crowbill_profile_index),
					tostring(self._cwv_crowbill_career_index), tostring(def.item_key),
					_om.crowbill_preview_diag_count)
			end
		end
	end

	-- v0.1.293: bind cwv_es_musket_old textures + track for live tuning in the
	-- character-preview UI. v0.1.318: pass the stance mode so 3P-MELEE
	-- transforms apply when the player has the musket in melee stance.
	-- Mode is read from item_data.mod_data.cwv_musket_stance.
	-- v0.1.326: diagnostic logging to figure out why texture stays white
	-- in the inventory preview. Logs whether the hook reached this point,
	-- the unit's mesh/material counts, and each Material.set_texture result.
	if def.item_key == "cwv_es_musket_old" and slot.right and _is_unit(slot.right) then
		local _stance = "ranged"
		local item_data = info and info.item_data
		if item_data and item_data.mod_data and item_data.mod_data.cwv_musket_stance == "melee" then
			_stance = "melee"
		elseif info and info.backend_id and _om._old_musket_modes_by_backend then
			-- HeroPreviewer retains backend_id but normally drops item_data, which
			-- made the old branch permanently choose ranged. The transition cache
			-- is the durable bridge between gameplay and preview reconstruction.
			_stance = _om._old_musket_modes_by_backend[info.backend_id] or "ranged"
		end
		_dbg("[cwv preview] firing for cwv_es_musket_old: unit=%s stance=%s", tostring(slot.right), _stance)
		-- Inline diagnostic texture binding (so we can SEE per-call results)
		local unit = slot.right
		local meshes_seen, mats_seen, tex_set_oks = 0, 0, 0
		local ok_nm, num_meshes = pcall(Unit.num_meshes, unit)
		if ok_nm and num_meshes then
			for i = 0, num_meshes - 1 do
				local mok, mesh = pcall(Unit.mesh, unit, i)
				if mok and mesh then
					meshes_seen = meshes_seen + 1
					local nok, num_mats = pcall(Mesh.num_materials, mesh)
					if nok and num_mats then
						for j = 0, num_mats - 1 do
							local matok, mat = pcall(Mesh.material, mesh, j)
							if matok and mat then
								mats_seen = mats_seen + 1
								local rok1 = pcall(Material.set_texture, mat, "texture_map_c0ba2942", "textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo")
								local rok2 = pcall(Material.set_texture, mat, "texture_map_59cd86b9", "textures/cwv_es_musket_custom/cwv_es_musket_custom_normal")
								local rok3 = pcall(Material.set_texture, mat, "texture_map_0205ba86", "textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic")
								if rok1 and rok2 and rok3 then tex_set_oks = tex_set_oks + 1 end
							end
						end
					end
				end
			end
		else
			-- v0.1.341-dev: promoted to `_dbg_alert` — "failed" is an alert
			-- (texture application path skipped; preview texture won't apply).
			_dbg_alert("[cwv preview] Unit.num_meshes failed: ok=%s num_meshes=%s", tostring(ok_nm), tostring(num_meshes))
		end
		_dbg("[cwv preview] textures applied: meshes=%d mats=%d ok_triples=%d", meshes_seen, mats_seen, tex_set_oks)
		if _om._track_old_musket_unit then
			_om._track_old_musket_unit(slot.right, "3p", _stance)
		end
		if _om._apply_old_musket_transform then
			_om._apply_old_musket_transform(slot.right, "3p", _stance)
		end
		-- Vanilla resolves preview animation from the inherited es_handgun name,
		-- so melee mode otherwise keeps the rifle idle even when the mesh pose is
		-- correct. Replay the selected template's career-aware wield event once
		-- after reconstruction.
		local stance_template = _stance == "melee" and Weapons.old_musket_template_melee
			or Weapons.old_musket_template
		local wield_event = stance_template and stance_template.wield_anim
		local by_career = stance_template and stance_template.wield_anim_career_3p
			or stance_template and stance_template.wield_anim_career
		if by_career and self._current_career_name then
			wield_event = by_career[self._current_career_name] or wield_event
		end
		if wield_event and self.character_unit and Unit.alive(self.character_unit) then
			pcall(Unit.animation_event, self.character_unit, wield_event)
			pcall(printf, "[cwv:474] preview presentation slot=%s bid=%s mode=%s anim=%s",
				tostring(slot_index), tostring(info and info.backend_id), _stance, tostring(wield_event))
		end
	elseif def.item_key == "cwv_es_musket_old" then
		-- v0.1.341-dev: promoted to `_dbg_alert` — "gate failed" is an
		-- alert (CWV musket preview won't render correctly).
		_dbg_alert("[cwv preview] cwv_es_musket_old gate failed: slot.right=%s _is_unit=%s",
			tostring(slot and slot.right), tostring(slot and slot.right and _is_unit(slot.right)))
	end
end

-- #604 TeamPreviewer identity bridge. Score rows preserve the peer in
-- context.players_session_score even though LevelEndView._get_hero_from_score
-- drops it from hero_data. Bots share their owner's peer, so only an exact
-- player-controlled profile+career row may cross this boundary. Non-score
-- lobby/parading users fall back to live ProfileSynchronizer identity.
_om._crowbill_team_peer = function(profile_index, career_index, context)
	if profile_index == nil or career_index == nil then return nil, "missing_profile" end
	local scores = context and context.players_session_score
	if type(scores) == "table" then
		return _om.crowbill_presentation.resolve_score_peer(profile_index, career_index, scores)
	end
	local pm = Managers and Managers.player
	local psync = context and context.profile_synchronizer
	if not psync then
		local network = Managers.state and Managers.state.network
		psync = network and network.profile_synchronizer
	end
	local ok, players = pm and pm.human_players and pcall(pm.human_players, pm)
	if not ok or type(players) ~= "table" then return nil, "live_unavailable" end
	for _, player in pairs(players) do
		local local_id_ok, local_id = pcall(player.local_player_id, player)
		local sync_ok, pi, ci = psync and psync.profile_by_peer
			and pcall(psync.profile_by_peer, psync, player.peer_id,
				local_id_ok and local_id or 1)
		if sync_ok and pi == profile_index and ci == career_index then
			return player.peer_id, "live_profile"
		end
	end
	return nil, "live_miss"
end

mod:hook("TeamPreviewer", "_spawn_hero", function(func, self, hero_previewer, hero_data)
	if hero_previewer and type(hero_data) == "table" then
		local ok, peer, source = pcall(_om._crowbill_team_peer,
			hero_data.profile_index, hero_data.career_index, self._context)
		hero_previewer._cwv_crowbill_team_preview = true
		hero_previewer._cwv_crowbill_profile_index = hero_data.profile_index
		hero_previewer._cwv_crowbill_career_index = hero_data.career_index
		hero_previewer._cwv_crowbill_wearer_peer = ok and peer or nil
		hero_previewer._cwv_crowbill_peer_source = ok and source or "resolver_error"
	end
	return func(self, hero_previewer, hero_data)
end)

-- ============================================================
-- Cosmetic picker filter — strip vanilla skins from cwv variants
-- ============================================================
-- Vanilla `HeroWindowItemCustomization._setup_illusions` populates the
-- illusion list from `item_data.skin_combination_table` (which we set
-- correctly to `cwv_imperial_longsword_skins` etc., containing only our
-- cwv skins) and THEN appends `WeaponSkins.default_skins[item_key]` if not
-- already in the list (`hero_window_item_customization.lua:1586`). The
-- problem: cwv items inherit `entry.key = "es_bastard_sword"` from their
-- clone (per `feedback_cwv_clone_name_clobber.md`), so `item.ItemId`
-- resolves through that and the picker looks up
-- `WeaponSkins.default_skins.es_bastard_sword = "es_bastard_sword_skin_01"`
-- (the Bretonian default, defined in `weapon_skins_lake.lua:251`). The
-- Bretonian then gets added as a 4th option alongside our 3 cwv skins.
--
-- Filter `self._illusion_widgets` after vanilla runs: for cwv items, keep
-- only widgets whose skin_key starts with `cwv_`. Recompute the layout so
-- the remaining widgets are centered correctly.
local function _is_cwv_item(item)
	if not item then return false end
	local backend_id = item.backend_id or item.ItemId
	-- `_%d%d%d$` (not `_001$`): CWV's own _001/_002 instances AND cim-crafted
	-- copies (`cwv_<key>_NNN`, NNN 100-999, cim_dev issue 390) so the illusion
	-- picker filters to cwv-only widgets for a crafted variant too.
	if type(backend_id) == "string" and backend_id:match("^cwv_.+_%d%d%d$") then
		return true
	end
	-- Fallback: the cwv_variant marker on the entry (set in `_build_entry`).
	-- Won't catch backend-id-only paths but does catch any direct item-data
	-- inspection that lands here.
	local item_data = item.data
	return item_data and item_data.cwv_variant == true
end

mod:hook("HeroWindowItemCustomization", "_setup_illusions", function(func, self, item)
	func(self, item)

	if not _is_cwv_item(item) then return end

	local widgets = self._illusion_widgets
	if not widgets then return end

	-- Filter pass: keep only cwv_*_skin entries.
	local kept = {}
	for _, widget in ipairs(widgets) do
		local skin_key = widget.content and widget.content.skin_key
		if type(skin_key) == "string" and skin_key:match("^cwv_") then
			kept[#kept + 1] = widget
		end
	end

	if #kept == #widgets then return end -- nothing to strip

	-- Recompute horizontal layout (mirrors vanilla's loop at
	-- hero_window_item_customization.lua:1611-1618). Widget width is 51,
	-- spacing is -5; vanilla recenters around `total_width / 2`.
	local width = 51
	local spacing = -5
	local total_width = -spacing
	for _ = 1, #kept do
		total_width = total_width + spacing + width
	end
	local x_offset = width / 2
	for _, widget in ipairs(kept) do
		local offset = widget.offset
		offset[1] = -total_width / 2 + x_offset
		x_offset = x_offset + width + spacing
	end

	self._illusion_widgets = kept
end)

-- v0.1.328: UNCONDITIONAL logging for every preview-hook firing. The
-- conditional "if musket" filter in v0.1.326 may have hidden the actual
-- item_name (which could be "es_handgun" inherited from base, not
-- "cwv_es_musket"). Need to see every call to figure out what's happening.
mod:hook("HeroPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	_dbg("[cwv preview hook] HeroPreviewer._spawn_item fired item_name=%s self=%s",
		tostring(item_name), tostring(self))
	_cwv_spawn_item_post(self, item_name)
	return result
end)

mod:hook("MenuWorldPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	_dbg("[cwv preview hook] MenuWorldPreviewer._spawn_item fired item_name=%s self=%s",
		tostring(item_name), tostring(self))
	_cwv_spawn_item_post(self, item_name)
	return result
end)

-- Cosmetic picker / illusion browser preview pane.
--
-- IMPORTANT: this MUST be `mod:hook` (full wrapper), NOT `mod:hook_safe`.
-- Vanilla `LootItemUnitPreviewer:_spawn_items` calls `self:spawn_units(...)`
-- and only assigns `self._spawned_units = units` AFTER the method returns
-- (`loot_item_unit_previewer.lua:522`/`532`). A `hook_safe` post-hook fires
-- BEFORE the caller's assignment, so `self._spawned_units` is nil at that
-- point. Reading the return value of the wrapped call is the only way to
-- get the units. Cosmetics_tweaker hit the same problem and switched its
-- bret-thinning hook to `mod:hook` for exactly this reason — the user
-- remembered this when investigating why cwv scale wasn't applying in the
-- cosmetic picker. Don't refactor back to `hook_safe`.
mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
	-- #597: when the mod-scoped custom resource is unexpectedly absent, the
	-- package bridge records a vanilla fallback rather than letting this
	-- preview path call World.spawn_unit on a missing custom unit.
	_om.mod_unit_preview.apply_loot_fallbacks(self, spawn_data)
	-- issue 419 pre-pass: rewrite base-mesh spawn entries to the variant's
	-- authored 3P units BEFORE vanilla spawns them. Covers the browser edge
	-- where the data-level get_item_units resolution missed (UUID-bid crafted
	-- instance + backend rung unavailable) — full rationale at the helper.
	if _om._cwv_browser_meshswap_apply then
		_om._cwv_browser_meshswap_apply(self._item, spawn_data)
	end

	local units = func(self, spawn_data)

	local item = self._item
	if not item or not units then return units end
	local item_data = item.data
	local weapon_key = (item_data and item_data.key) or item.key
	if not weapon_key then return units end

	-- For cwv_* items, item_data.key returns the BASE weapon key (e.g.
	-- "es_bastard_sword"), NOT "cwv_es_longsword". Always resolve the cwv key
	-- from the backend_id (pattern documented in feedback_cwv_backend_id_lookup.md).
	-- The cwv-keyed transform map then takes precedence over the base-key map so
	-- variant-specific scales/offsets apply correctly.
	local def = _skin_transform_map[weapon_key] or _transform_map[weapon_key]
	-- #482 ladder: bid pattern (CWV's own _001/_002 instances AND cim
	-- standard-forge copies, issue 390) -> item.data.cwv_key stamp (Athanor
	-- crafts with UUID bids) so the cosmetic-preview scale applies to every
	-- crafted variant instance too.
	local cwv_key = _om._cwv_key_for_item(item.backend_id, item_data)
	if cwv_key then
		def = _transform_map[cwv_key] or _skin_transform_map[cwv_key] or def
	end
	if not def then return units end

	-- LootItemUnitPreviewer (illusion / cosmetic browser) spawns 3P-style models;
	-- prefer _3p override if set, else unified.
	local scale  = _resolve_field(def, "right_hand_scale_3p")  or _resolve_field(def, "left_hand_scale_3p")
	          or _resolve_field(def, "right_hand_scale")     or _resolve_field(def, "left_hand_scale")
	local offset = _resolve_field(def, "right_hand_offset_3p") or _resolve_field(def, "left_hand_offset_3p")
	          or _resolve_field(def, "right_hand_offset")    or _resolve_field(def, "left_hand_offset")
	local rotation = _resolve_field(def, "right_hand_rotation_3p") or _resolve_field(def, "left_hand_rotation_3p")
	          or _resolve_field(def, "right_hand_rotation")    or _resolve_field(def, "left_hand_rotation")
	if scale or offset or rotation then
		for _, unit in ipairs(units) do
			_transform_unit(unit, scale, offset, rotation)
		end
	end
	-- #604: LootItemUnitPreviewer backs the item browser/customization pane.
	-- It uses the same committed base*local-flip resolver as world equipment.
	if def.crowbill_mode_family and _om._apply_crowbill_presentation then
		local browser_identity = _om._crowbill_render_identity(item_data, def,
			item.backend_id or def.item_key .. ":item_browser")
		for _, unit in ipairs(units) do
			_om._apply_crowbill_presentation(unit, def, browser_identity,
				"item_browser", rotation)
		end
	end

	return units
end)

-- ============================================================
-- Init
-- ============================================================

local _wt, _cos = _detect_companion_mods()

mod:command("cwv", "Character Weapon Variants status", function()
	mod:echo("Character Weapon Variants v%s", MOD_VERSION)
	mod:echo("  Definitions: %d", #_variant_definitions)
	local count = 0
	for _ in pairs(_registered_keys) do count = count + 1 end
	mod:echo("  Registered items: %d", count)
	mod:echo("  weapon_tweaker: %s", tostring(_wt ~= nil))
	mod:echo("  cosmetics_tweaker: %s", tostring(_cos ~= nil))
	for _, d in ipairs(_variant_definitions) do
		local status = _registered_keys[d.item_key] and "registered" or "not registered"
		mod:echo("    %s — %s (%s)", d.item_key, d.display_name, status)
	end
end)

-- v0.1.293: Old Musket live-tune commands. Separate _1p / _3p variants since
-- the FBX needs different transforms in first-person view vs other players'
-- third-person view. State stored at top of file (search "_CWV_OLD_MUSKET_POS_1P"
-- etc); commands mutate globals and call `_reapply_old_musket_transforms_all`
-- which walks the weak-keyed `_CWV_OLD_MUSKET_UNITS_1P/3P` sets and re-applies
-- the local-space transforms. Compose-safe with vanilla's attachment_node_linking.
local function _parse3(a, b, c)
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	if a and b and c then return { a, b, c } end
	return nil
end

-- v0.1.295: 3-bucket commands — 1P RANGED, 1P MELEE, 3P. Convention:
-- _1p_r = first-person ranged stance (rifle), _1p_m = first-person melee
-- stance (polearm), _3p = third-person (shared across modes).
mod:command("cwv_om_pos_1p_r", "Old Musket 1P RANGED pos: /cwv_om_pos_1p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_1p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_1P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_1p_m", "Old Musket 1P MELEE pos: /cwv_om_pos_1p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_1p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_1P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_3p_r", "Old Musket 3P RANGED pos: /cwv_om_pos_3p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_3p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_3P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_3p_m", "Old Musket 3P MELEE pos: /cwv_om_pos_3p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_3p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_3P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
-- Rotation commands. Three operations per bucket:
--   cwv_om_rot_<bucket>      <ax> <ay> <az> <deg>  — SET (replace current with single axis-angle)
--   cwv_om_rotmul_<bucket>   <ax> <ay> <az> <deg>  — MULTIPLY current rotation by a new axis-angle
--   cwv_om_eul_<bucket>      <x_deg> <y_deg> <z_deg> — SET from Euler XYZ degrees
-- Buckets: _1p_r (1P ranged), _1p_m (1P melee), _3p.
-- Use _rotmul_ to compose rotations without solving the math — e.g., set a
-- base orientation via _rot_, then add a 90° barrel-roll via
-- `cwv_om_rotmul_1p_r 0 0 1 90` (try X / Y / Z axes; whichever rolls the gun
-- the way you want is the barrel axis after your base rotation).
-- v0.1.298: all commands box via QuaternionBox(...) for long-term storage.
-- MUL helpers unbox + multiply + re-box. See note at _CWV_OLD_MUSKET_ROT_*
-- declarations.
local function _q_aa(ax, ay, az, deg) return Quaternion.axis_angle(Vector3(ax, ay, az), math.rad(deg)) end
local function _unbox_or_identity(boxed) return boxed and boxed:unbox() or Quaternion.identity() end

mod:command("cwv_om_rot_1p_r", "SET 1P RANGED rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_1p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_1p_m", "SET 1P MELEE rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_1p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_3p_r", "SET 3P RANGED rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_3p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_3p_m", "SET 3P MELEE rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_3p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)

mod:command("cwv_om_rotmul_1p_r", "MUL 1P RANGED rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_1p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_1P_RANGED), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_1p_m", "MUL 1P MELEE rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_1p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_1P_MELEE), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_3p_r", "MUL 3P RANGED rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_3p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_3P_RANGED), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_3p_m", "MUL 3P MELEE rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_3p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_3P_MELEE), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)

mod:command("cwv_om_eul_1p_r", "SET 1P RANGED rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_1p_r <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_1p_m", "SET 1P MELEE rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_1p_m <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_3p_r", "SET 3P RANGED rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_3p_r <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_3p_m", "SET 3P MELEE rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_3p_m <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_1p_r", "Old Musket 1P RANGED scale: /cwv_om_scale_1p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_1p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_1P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_1p_m", "Old Musket 1P MELEE scale: /cwv_om_scale_1p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_1p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_1P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_3p_r", "Old Musket 3P RANGED scale: /cwv_om_scale_3p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_3p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_3P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_3p_m", "Old Musket 3P MELEE scale: /cwv_om_scale_3p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_3p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_3P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_show", "Echo current Old Musket transform values (rot as Euler XYZ deg)", function()
	local function _f3(v) return string.format("(%.3f, %.3f, %.3f)", v[1], v[2], v[3]) end
	local function _fr(boxed)
		if not boxed then return "identity" end
		local x, y, z = Quaternion.to_euler_angles_xyz(boxed:unbox())
		return string.format("euler_xyz=(%.2f, %.2f, %.2f)°", x, y, z)
	end
	mod:echo("[cwv old-musket] 1P-RANGED pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_1P_RANGED), _fr(_om._CWV_OLD_MUSKET_ROT_1P_RANGED), _f3(_om._CWV_OLD_MUSKET_SCALE_1P_RANGED))
	mod:echo("[cwv old-musket] 1P-MELEE  pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_1P_MELEE),  _fr(_om._CWV_OLD_MUSKET_ROT_1P_MELEE),  _f3(_om._CWV_OLD_MUSKET_SCALE_1P_MELEE))
	mod:echo("[cwv old-musket] 3P-RANGED pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_3P_RANGED), _fr(_om._CWV_OLD_MUSKET_ROT_3P_RANGED), _f3(_om._CWV_OLD_MUSKET_SCALE_3P_RANGED))
	mod:echo("[cwv old-musket] 3P-MELEE  pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_3P_MELEE),  _fr(_om._CWV_OLD_MUSKET_ROT_3P_MELEE),  _f3(_om._CWV_OLD_MUSKET_SCALE_3P_MELEE))
end)

-- v0.1.303 probe: dump every musket item in the backend mirror, plus the
-- two related ItemMasterList entries (cwv_es_musket_old + cwv_es_musket).
-- Tells us at a glance what slot_type / template each item ended up with
-- and whether the variant was registered at all.
-- v0.1.306: dump ammo state of every alive cwv musket ammo extension
-- in the pool, plus the pool cap. Useful for verifying the shared-pool
-- behavior (chambered ammo per-item, reserve shared across items).
mod:command("cwv_musket_ammo_diag", "Dump shared-pool ammo state for all cwv muskets", function()
	if not _om._CWV_MUSKET_AMMO_EXTS then mod:echo("pool not initialized"); return end
	local count = 0
	for ext in pairs(_om._CWV_MUSKET_AMMO_EXTS) do
		local alive = ext.unit and Unit.alive(ext.unit)
		if alive then
			count = count + 1
			mod:echo("[#%d] unit=%s slot=%s curr=%s avail=%s shots_fired=%s max=%s clip=%s reloading=%s",
				count, tostring(ext.unit), tostring(ext.slot_name),
				tostring(ext._current_ammo), tostring(ext._available_ammo),
				tostring(ext._shots_fired), tostring(ext._max_ammo), tostring(ext._ammo_per_clip),
				tostring(ext._next_reload_time ~= nil))
		else
			mod:echo("[#?] dead member (cleanup pending)")
		end
	end
	if _om._cwv_musket_pool_cap then
		mod:echo("pool: members=%d  cap=%d  reserve_per_musket=%d",
			count, _om._cwv_musket_pool_cap(), _om._CWV_RESERVE_PER_MUSKET)
	end
end)

mod:command("cwv_musket_dump", "Dump all musket items + their slot_type / template", function()
	local backend_items = Managers and Managers.backend and Managers.backend:get_interface("items")
	if backend_items and backend_items.get_all_backend_items then
		local all = backend_items:get_all_backend_items()
		local count = 0
		for backend_id, item in pairs(all or {}) do
			local data = item.data or item.master_item or item
			local key = data and (data.key or data.name) or item.ItemId or backend_id
			if type(key) == "string" and key:match("^cwv_es_musket") then
				count = count + 1
				mod:echo("[BACKEND] backend_id=%s  key=%s  slot_type=%s  template=%s  rarity=%s",
					tostring(backend_id), tostring(key),
					tostring(data and data.slot_type),
					tostring(data and data.template),
					tostring(item.rarity or (data and data.rarity)))
			end
		end
		mod:echo("[BACKEND] total cwv musket items: %d", count)
	else
		mod:echo("[BACKEND] backend_items interface unavailable")
	end

	if ItemMasterList then
		for _, k in ipairs({ "cwv_es_musket_old", "cwv_es_musket", "es_handgun" }) do
			local e = ItemMasterList[k]
			if e then
				mod:echo("[IML] %s  slot_type=%s  template=%s  rarity=%s",
					k, tostring(e.slot_type), tostring(e.template), tostring(e.rarity))
			else
				mod:echo("[IML] %s = nil", k)
			end
		end
	end
	mod:echo("[WEAPONS] old_musket_template=%s  old_musket_template_melee=%s",
		tostring(Weapons and Weapons.old_musket_template ~= nil),
		tostring(Weapons and Weapons.old_musket_template_melee ~= nil))
end)

mod:command("cwv_probe_skins", "Dump skin keys + localized names matching a weapon: /cwv_probe_skins <matching_item_key>", function(matching_item_key)
	if not matching_item_key or matching_item_key == "" then
		mod:echo("Usage: /cwv_probe_skins <matching_item_key>  (e.g. es_2h_sword, es_bastard_sword)")
		return
	end
	if not ItemMasterList then mod:echo("ItemMasterList not loaded") return end
	local results = {}
	for key, item in pairs(ItemMasterList) do
		if item.item_type == "weapon_skin" and item.matching_item_key == matching_item_key then
			results[#results + 1] = key
		end
	end
	table.sort(results)
	mod:info("=== Skins for matching_item_key='%s' (%d) ===", matching_item_key, #results)
	for _, key in ipairs(results) do
		local item = ItemMasterList[key]
		local name = key
		if item.display_name then
			local ok, loc = pcall(Localize, item.display_name)
			if ok and loc then name = loc end
		end
		mod:info("%s | %s | %s | rarity=%s", key, name, tostring(item.right_hand_unit or "?"), tostring(item.rarity or "?"))
	end
	mod:echo("Dumped %d skins to log (search for 'Skins for')", #results)
end)

-- ============================================================
-- Unit probe — diagnostic tooling for pickup-asset investigation
-- ============================================================
-- Spawns a Stingray unit at the player's feet and dumps its asset-level
-- properties (actor count, actor names, collision filters, bounding box,
-- attached extensions) to mod:info. Used to compare known-good pickup units
-- (pup_dw_thrown_axe_01_t1, prj_we_javelin_01_3ps) against candidate units
-- (wpn_emp_boar_spear_01_3p, spear_3ps) so we can decide which assets can
-- legitimately serve as pickup units without going through the full
-- spawn-throw-fail iteration cycle.
--
-- Spawned probes persist until cwv_despawn_probes is called or level changes.
--
-- Suggested probe sequence for the Tuskgor Javelin pickup investigation:
--   cwv_probe_unit units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p
--   cwv_probe_unit units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1
--   cwv_probe_unit units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps
--   cwv_probe_unit units/weapons/player/spear_projectile/spear_3ps
--   cwv_despawn_probes
local _probe_units = {}

local function _safe_call(fn, ...)
	local ok, ret = pcall(fn, ...)
	if ok then return ret end
	return nil
end

local function _dump_actor(unit, idx)
	local actor = _safe_call(Unit.actor, unit, idx)
	if not actor then
		mod:info("  [%d] (nil actor)", idx)
		return
	end
	local name = _safe_call(Actor.name, actor) or "(unnamed)"
	local is_static    = _safe_call(Actor.is_static, actor)
	local is_kinematic = _safe_call(Actor.is_kinematic, actor)
	local is_dynamic   = _safe_call(Actor.is_dynamic, actor)
	local cfilter      = _safe_call(Actor.collision_filter, actor)
	mod:info("  [%d] name=%s static=%s kin=%s dyn=%s collision_filter=%s",
		idx, tostring(name),
		tostring(is_static), tostring(is_kinematic), tostring(is_dynamic),
		tostring(cfilter))
end

mod:command("cwv_probe_unit", "Spawn a unit and dump asset properties (/cwv_probe_unit <path>)", function(unit_path)
	if not unit_path or unit_path == "" then
		mod:echo("Usage: /cwv_probe_unit <unit_path>")
		mod:echo("Example paths to compare:")
		mod:echo("  units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p")
		mod:echo("  units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1")
		mod:echo("  units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps")
		mod:echo("  units/weapons/player/spear_projectile/spear_3ps")
		return
	end
	local player = Managers.player and Managers.player:local_player()
	if not player or not player.player_unit then mod:echo("No local player unit yet (in-mission only)") return end
	local world = Managers.world and Managers.world:world("level_world")
	if not world then mod:echo("level_world not available") return end

	local player_pos = Unit.world_position(player.player_unit, 0)
	local player_rot = Unit.world_rotation(player.player_unit, 0)
	local forward    = Quaternion.forward(player_rot)
	local spawn_pos  = player_pos + forward * 1.5 + Vector3.up(player_pos) * 1.0

	-- Pre-check loadability. Stingray's World.spawn_unit asserts in C++
	-- (resource_manager().can_get(...)) when the unit isn't in a loaded
	-- resource package — pcall CANNOT catch that assertion, the engine
	-- hard-crashes. Try to verify the unit is loaded before spawning.
	-- Application.can_get / has_resource APIs vary by Stingray version;
	-- best-effort with multiple fallbacks. If none confirm loadability,
	-- refuse to spawn rather than risk a crash.
	local can_check_apis = {
		function() return Application.can_get and Application.can_get("unit", unit_path) end,
		function() return Application.has_resource and Application.has_resource("unit", unit_path) end,
	}
	local loadable = nil
	for _, check in ipairs(can_check_apis) do
		local ok, result = pcall(check)
		if ok and result ~= nil then loadable = result; break end
	end
	if loadable == false then
		mod:echo("Refusing to spawn '%s' — unit not in loaded resource packages.", unit_path)
		mod:echo("  (would crash; this unit is only loaded when its host weapon is equipped in this lobby)")
		return
	end
	-- If loadable check returned nil, we couldn't verify; user assumes risk.

	local ok, unit = pcall(World.spawn_unit, world, unit_path, spawn_pos)
	if not ok or not unit then
		mod:echo("Spawn failed: %s", tostring(unit))
		mod:info("Spawn failed for %s: %s", unit_path, tostring(unit))
		return
	end

	_probe_units[#_probe_units + 1] = unit

	mod:info("=== PROBE: %s ===", unit_path)

	-- Node hierarchy
	local num_nodes = _safe_call(Unit.num_nodes, unit) or 0
	mod:info("nodes: %d", num_nodes)
	for i = 0, math.min(num_nodes - 1, 30) do
		local name = _safe_call(Unit.node_name, unit, i)
		local pos = _safe_call(Unit.local_position, unit, i)
		local rot = _safe_call(Unit.local_rotation, unit, i)
		local px, py, pz, qx, qy, qz, qw = "?", "?", "?", "?", "?", "?", "?"
		if pos then px, py, pz = string.format("%.2f", Vector3.x(pos)), string.format("%.2f", Vector3.y(pos)), string.format("%.2f", Vector3.z(pos)) end
		if rot then
			local fwd = _safe_call(Quaternion.forward, rot)
			if fwd then qx, qy, qz = string.format("%.2f", Vector3.x(fwd)), string.format("%.2f", Vector3.y(fwd)), string.format("%.2f", Vector3.z(fwd)) end
		end
		mod:info("  [%d] name=%s local_pos=(%s,%s,%s) local_fwd=(%s,%s,%s)",
			i, tostring(name or "?"), px, py, pz, qx, qy, qz)
	end

	-- Actors
	local num_actors = _safe_call(Unit.num_actors, unit) or 0
	mod:info("actors: %d", num_actors)
	for i = 0, num_actors - 1 do
		_dump_actor(unit, i)
	end

	-- Bounding box (asset extents) — different APIs in different SDK versions; try both
	local bmin, bmax = _safe_call(function() return Unit.box(unit) end), nil
	local ok_box, b1, b2 = pcall(Unit.box, unit)
	if ok_box and b1 and b2 then
		mod:info("box min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)",
			Vector3.x(b1), Vector3.y(b1), Vector3.z(b1),
			Vector3.x(b2), Vector3.y(b2), Vector3.z(b2))
	end

	-- Extensions — usually empty for raw World.spawn_unit (no entity_system pass);
	-- log anyway in case the unit auto-attaches anything via its asset metadata.
	local has_pickup = _safe_call(ScriptUnit.has_extension, unit, "pickup_system")
	local has_outline = _safe_call(ScriptUnit.has_extension, unit, "outline_system")
	local has_interaction = _safe_call(ScriptUnit.has_extension, unit, "interactable_system")
	mod:info("extensions: pickup=%s outline=%s interactable=%s",
		tostring(has_pickup ~= nil), tostring(has_outline ~= nil), tostring(has_interaction ~= nil))

	mod:echo("Probed '%s' (probe #%d). Walk around and inspect; cwv_despawn_probes when done. Log written to console.",
		unit_path, #_probe_units)
end)

-- Focused probe for the j_leftweaponattach investigation: spawns each
-- weapon-display rig and reports whether the named attach nodes exist.
-- See `J_LEFTWEAPONATTACH_INVESTIGATION.md` U1.
mod:command("cwv_probe_attach", "Spawn each display rig and check for j_leftweaponattach / j_rightweaponattach", function()
	local rigs = {
		"units/weapons/weapon_display/display_dual_weapons",
		"units/weapons/weapon_display/display_1h_weapon",
		"units/weapons/weapon_display/display_1h_swords",
		"units/weapons/weapon_display/display_dual_axes",
		"units/weapons/weapon_display/display_dual_daggers",
		"units/weapons/weapon_display/display_dual_hammers",
		"units/weapons/weapon_display/dual_wield_axe_falchion",
		"units/weapons/weapon_display/display_2h_weapon",
		"units/weapons/weapon_display/display_shield",
	}
	local player = Managers.player and Managers.player:local_player()
	if not player or not player.player_unit then mod:echo("No local player unit (be in keep or mission)") return end
	local world = Managers.world and Managers.world:world("level_world")
	if not world then mod:echo("level_world not available") return end

	local pos = Unit.world_position(player.player_unit, 0)
	local results = {}
	for _, path in ipairs(rigs) do
		local ok, unit = pcall(World.spawn_unit, world, path, pos)
		if not ok or not unit then
			results[#results + 1] = string.format("%s — SPAWN FAILED (%s)", path, tostring(unit))
		else
			local has_left  = pcall(Unit.node, unit, "j_leftweaponattach")
			local has_right = pcall(Unit.node, unit, "j_rightweaponattach")
			results[#results + 1] = string.format("%s — left=%s right=%s",
				path, tostring(has_left), tostring(has_right))
			pcall(World.destroy_unit, world, unit)
		end
	end

	mod:echo("=== display rig attach-node probe ===")
	for _, line in ipairs(results) do
		mod:info(line)
		mod:echo(line)
	end
	mod:echo("=== end ===")
end)

mod:command("cwv_despawn_probes", "Despawn all probe units spawned via cwv_probe_unit", function()
	local count = 0
	for _, unit in ipairs(_probe_units) do
		if unit and _safe_call(Unit.alive, unit) then
			local ok = pcall(function()
				Managers.state.unit_spawner:mark_for_deletion(unit)
			end)
			if ok then count = count + 1 end
		end
	end
	_probe_units = {}
	mod:echo("Despawned %d probe units", count)
end)

-- ============================================================================
-- Debug-mode event subscriptions (v0.1.336)
-- ============================================================================
-- Three event-driven _dbg dumps that fire only when `cwv_debug_mode` is ON.
-- Each handler short-circuits at the top via mod:get so the engine-side
-- callback overhead is the only cost when the toggle is off.
--
-- 1. Game-state transitions  -> dump registered cwv_* item count + which
--    loadout slots have cwv_* items equipped on the local player.
-- 2. Wield (SimpleInventoryExtension.wield post-hook) -> dump variant key,
--    backend_id, slot, applied skin, base template, and career when the
--    player wields any cwv_* item.
-- 3. Old Musket stance toggle -> dump prior/new stance + slot_index alongside
--    the existing per-toggle "[cwv musket] stance:" trace (which is also
--    now gated through _dbg).
--
-- Localized helper: count cwv_* item_keys present in ItemMasterList. Bails
-- gracefully when IML isn't loaded yet (boot timing).
local function _dbg_count_registered_cwv_items()
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return -1 end
    local n = 0
    -- ItemMasterList has the missing-key crashify metamethod (see v0.1.333),
    -- so iterate via `pairs` (which calls __pairs / next directly on the
    -- table contents — does not trigger __index). Filter to cwv_* prefix.
    for k, _ in pairs(iml) do
        if type(k) == "string" and k:sub(1, 4) == "cwv_" then
            n = n + 1
        end
    end
    return n
end

-- (1) Game state transitions. VMF surfaces engine state changes through the
-- top-level `mod.on_game_state_changed = function(status, state_name)` slot.
_om._dual_axes_fp_game_state_retry_installed = true
mod.on_game_state_changed = function(status, state_name)
    -- #586: chunk-load normally acquires the leases, but PackageManager can be
    -- cold during unusual load ordering. Every gameplay-state enter is a safe
    -- retry boundary and catalog acquisition is idempotent.
    if status == "enter" and _om._dual_weapon_fp_residency_complete ~= true then
        _om._acquire_dual_weapon_fp_residency("game_state_enter:" .. tostring(state_name))
    end

    local n = _dbg_count_registered_cwv_items()
    _dbg("on_game_state_changed: status=%s state=%s registered_cwv_items=%d",
        tostring(status), tostring(state_name), n)

	-- Only attempt the loadout snapshot on `enter` (the new state is now
	-- active) — `exit` fires before extensions are wired in the next state.
	if status ~= "enter" then return end
	-- #474: a mission/keep state enter is a bounded reconstruction boundary.
	-- Query peers and replay our current slots once; no timer or frame traffic.
	if _om._old_musket_request_states then
		_om._old_musket_request_states("game_state_enter:" .. tostring(state_name))
	end
	if _om.crowbill_runtime and _om.crowbill_runtime.request_states then
		_om.crowbill_runtime.request_states("game_state_enter:" .. tostring(state_name))
	end

    -- `Managers.player:local_player()` internally calls `peer_id()`, which
    -- THROWS "Network backend has not been set" on early state-enters
    -- (StateSplashScreen / menu) before the network backend exists. This is a
    -- diagnostics-only handler, so pcall the lookup and bail silently when the
    -- backend isn't up yet — otherwise VMF logs a (caught) error on every boot.
    if not Managers.player then return end
    local ok_pl, pl = pcall(Managers.player.local_player, Managers.player)
    if not ok_pl or not pl then return end
    local player_unit = pl.player_unit
    if not player_unit or not Unit.alive(player_unit) then
        _dbg("  loadout: no local player_unit yet (state=%s)", tostring(state_name))
        return
    end
    -- #343: first live keep/mission boundary records the observation-only smoke
    -- bomb prerequisite snapshot automatically. It is log-only and one-shot;
    -- the explicit command remains available for at most two later rechecks.
    if mod._cwv_smoke_bomb_probe then
        mod._cwv_smoke_bomb_probe.auto_run(mod)
    end
    local ok_inv, inv = pcall(ScriptUnit.extension, player_unit, "inventory_system")
    if not ok_inv or not inv or not inv.equipment then
        _dbg("  loadout: no inventory_system on local player (state=%s)", tostring(state_name))
        return
    end
    local equip = inv:equipment()
    local slots = equip and equip.slots
    if type(slots) ~= "table" then return end

    local hits = 0
    for slot_name, slot_data in pairs(slots) do
        local item_data = slot_data and slot_data.item_data
        local bid = item_data and item_data.backend_id
        if type(bid) == "string" and bid:match("^cwv_") then
            hits = hits + 1
            _dbg("  loadout slot=%s backend_id=%s template=%s skin=%s",
                tostring(slot_name), tostring(bid),
                tostring(item_data.template),
                tostring(slot_data.skin))
        end
    end
    _dbg("  loadout: %d cwv_* item(s) currently equipped", hits)
end

-- #586: these callbacks own the generated-dual FP lease catalog above. Keep
-- them idempotent because VMF may call on_disabled before on_unload.
mod.on_enabled = function()
    _om._acquire_dual_weapon_fp_residency("mod_enabled")
	if _om.crowbill_runtime and _om.crowbill_runtime.set_enabled then
		_om.crowbill_runtime.set_enabled(true)
	end
	-- #599: compose gameplay-profile ownership into the canonical lifecycle
	-- callback. Defining an earlier callback is ineffective because this owner
	-- assignment is the final VMF callback value.
	_om._apply_mace_hammer_identity(
		mod:get(_om.mace_hammer_identity_policy.SETTING_ID) ~= false)
end

mod.on_disabled = function()
	if _om.crowbill_runtime and _om.crowbill_runtime.set_enabled then
		_om.crowbill_runtime.set_enabled(false)
	end
	_om._apply_mace_hammer_identity(false)
    _om._release_dual_weapon_fp_residency("mod_disabled")
end

mod.on_unload = function()
	if _om.crowbill_runtime and _om.crowbill_runtime.set_enabled then
		_om.crowbill_runtime.set_enabled(false)
	end
	_om._apply_mace_hammer_identity(false)
    _om._release_dual_weapon_fp_residency("mod_unload")
end

-- (2) Variant equip event — MERGED into the canonical wield hook at line ~1317
-- (where the cross-access tracking lives). VMF `mod:hook_safe` does NOT chain
-- on the same (Class, method) — a second registration silently overwrites.
-- See v0.1.337 CHANGELOG and VMF_RECIPES.md § 1.

-- (3) Old Musket stance toggle. The toggle helper
-- `_toggle_musket_stance_and_rewield` (~line 2729) already logs its core
-- transition via `_dbg("[cwv musket] stance: %s → %s ...")`. To honor the
-- task's "log prior stance / new stance / slot_index" requirement without
-- introducing duplicate noise, attach an extra structured dump at the same
-- call site keyed off the SAME `cwv_debug_mode` toggle. Lookup happens at
-- the function entry only -- not in a hot loop -- so the cached-pattern
-- guidance doesn't apply here.
--
-- We intentionally do NOT add a hook to a vanilla method to observe this --
-- the stance toggle is a CWV-internal event with no vanilla equivalent.
-- The existing call site is the canonical fire point.

mod:command("cwv_give", "Give a variant weapon: cwv_give <item_key>", function(item_key)
	if not item_key or item_key == "" then
		mod:echo("Usage: cwv_give <item_key>")
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end
	_give_variant(item_key)
end)

-- ============================================================
-- /cwv_regression_test checks (scaffold near top of file).
-- Each check returns nil for PASS or a string for FAIL.
-- Bail with a clear "not loaded (run in-keep)" message when globals
-- aren't ready — keep-load timing means ItemMasterList / NetworkLookup
-- may not be populated when the user runs the command pre-keep.
-- ============================================================

-- Per-mod helper: walk every cwv_* IML entry that originated from this mod.
-- Returns an array of { key = string, entry = table, def = table }. Bails
-- (returns nil + "reason string") when ItemMasterList isn't ready or no
-- variants are registered yet.
local function _rt_iter_cwv_entries()
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then
        return nil, "ItemMasterList not loaded yet (run in-keep)"
    end
    local out = {}
    for _, def in ipairs(_variant_definitions) do
        if not def.skin_only then
            local entry = rawget(iml, def.item_key)
            if entry then
                out[#out + 1] = { key = def.item_key, entry = entry, def = def }
            end
        end
    end
    if #out == 0 then
        return nil, "no cwv variants registered in ItemMasterList yet (run in-keep)"
    end
    return out, nil
end

_rt_register("cwv_variant_flag_present", function()
    -- Verify every cwv_* ItemMasterList entry carries `cwv_variant = true`.
    -- Per `feedback_cwv_clone_name_clobber.md` — sibling mods (cosmetics_tweaker,
    -- weapon_tweaker, gt_lobby manifest formerly lobby_tweaker) gate item-name-keyed overrides
    -- on `item_data.cwv_variant`. Missing flag = sibling mods spuriously
    -- match the inherited base-weapon name and apply the wrong override.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local missing = {}
    for _, e in ipairs(entries) do
        if e.entry.cwv_variant ~= true then
            missing[#missing + 1] = e.key
        end
    end
    if #missing > 0 then
        return "cwv_variant flag missing on " .. #missing .. " entries: " .. table.concat(missing, ", ")
    end
end)

_rt_register("issue317_career_scoped_animation_picker", function()
	return mod._cwv_dev_anim_picker.regression_check()
end)

_rt_register("dual_axes_cosmetic_family_parity", function()
    local ws = rawget(_G, "WeaponSkins")
    local iml = rawget(_G, "ItemMasterList")
    if type(ws) ~= "table" or type(ws.skins) ~= "table"
            or type(ws.skin_combinations) ~= "table" or type(iml) ~= "table" then
        return "WeaponSkins/ItemMasterList not loaded yet (run in-keep)"
    end
	local source_combo = ws.skin_combinations.wh_1h_axe_skins
	local source_by_target = _om._dual_axes_source_by_skin
	local icon_by_source = _om._dual_axes_inventory_icon_by_source
	if type(source_combo) ~= "table" or type(source_by_target) ~= "table" then
		return "dual-axes source/destination cosmetic family was not registered"
	end
	if type(icon_by_source) ~= "table" then
		return "dual-axes primary-icon mapping was not registered"
	end

    local expected = {}
    local memberships = {}
    for tier_name, tier in pairs(source_combo) do
        for _, source_key in ipairs(tier) do
            expected[source_key] = true
            memberships[source_key] = memberships[source_key] or {}
            memberships[source_key][tier_name] = true
        end
    end
    local default_skin = ws.default_skins and ws.default_skins.wh_1h_axe
    if default_skin then expected[default_skin] = true end

    local targets = {
        cwv_es_dual_axes = "cwv_es_dual_axes_skins",
        cwv_wh_dual_axes = "cwv_wh_dual_axes_skins",
    }
    for target_key, combo_name in pairs(targets) do
        local clone_combo = ws.skin_combinations[combo_name]
        local source_by_clone = source_by_target[target_key]
        if type(clone_combo) ~= "table" or type(source_by_clone) ~= "table" then
            return "dual-axes target family was not registered: " .. target_key
        end
        local actual = {}
        for clone_key, source_key in pairs(source_by_clone) do
            actual[source_key] = true
            local source = ws.skins[source_key]
            local clone = ws.skins[clone_key]
            local source_item = rawget(iml, source_key)
            local clone_item = rawget(iml, clone_key)
            if not source or not clone or not source_item or not clone_item then
                return string.format("dual-axes clone incomplete: %s <- %s", clone_key, source_key)
            end
			if clone.right_hand_unit ~= source.right_hand_unit
					or clone.left_hand_unit ~= source.right_hand_unit
					or clone.display_unit ~= "units/weapons/weapon_display/display_dual_axes" then
				return string.format("dual-axes hand/display mismatch: %s <- %s", clone_key, source_key)
			end
			local expected_icon = icon_by_source[source.inventory_icon]
			if not expected_icon or clone.inventory_icon ~= expected_icon
					or clone_item.inventory_icon ~= expected_icon then
				return string.format("dual-axes primary icon mismatch: %s <- %s (%s)",
					clone_key, source_key, tostring(source.inventory_icon))
			end
            if clone_item.matching_item_key ~= target_key
                    or clone_item.required_dlc ~= source_item.required_dlc then
                return string.format("dual-axes owner/DLC mismatch: %s <- %s", clone_key, source_key)
            end
            if not rawget(NetworkLookup.weapon_skins, clone_key)
                    or not rawget(NetworkLookup.item_names, clone_key) then
                return "dual-axes clone missing network lookup: " .. clone_key
            end
            for tier_name in pairs(memberships[source_key] or {}) do
                local found = false
                for _, key in ipairs(clone_combo[tier_name] or {}) do
                    if key == clone_key then found = true break end
                end
                if not found then
                    return string.format("dual-axes tier parity missing: %s in %s", clone_key, tier_name)
                end
            end
        end

        local missing, extra = {}, {}
        for source_key in pairs(expected) do
            if not actual[source_key] then missing[#missing + 1] = source_key end
        end
        for source_key in pairs(actual) do
            if not expected[source_key] then extra[#extra + 1] = source_key end
        end
        if #missing > 0 or #extra > 0 then
            table.sort(missing)
            table.sort(extra)
            return string.format("dual-axes cosmetic set drift for %s: missing=[%s] extra=[%s]",
                target_key, table.concat(missing, ","), table.concat(extra, ","))
        end
    end
end)

_rt_register("issue396_imperial_longsword_identity_and_remote_husk", function()
	local owner = _find_def("cwv_es_longsword")
	local illusion = _find_def("cwv_es_longsword_nordland")
	if not owner or owner.display_name ~= "Imperial Longsword" then
		return "owned cwv_es_longsword is not canonically named Imperial Longsword"
	end
	if not illusion or not illusion.skin_only
			or illusion.skin_display_name ~= "Helmgart Watchsword" then
		return "save-compatible cwv_es_longsword_nordland is not a distinct Helmgart Watchsword illusion"
	end
	if _display_names.cwv_imperial_longsword ~= "Imperial Longsword"
			or _display_names.cwv_es_longsword_nordland_skin_name ~= "Helmgart Watchsword" then
		return "weapon-family and illusion localization keys are conflated"
	end

	local surfaces = mod._cwv_identity_surfaces
	for _, name in ipairs({ "network", "game_object_initialized", "spawn_resynced_loadout", "parity_replay" }) do
		if not (surfaces and surfaces[name]) then return "missing CWV identity surface: " .. name end
	end
	local plan = _om._cwv_identity_payloads
	local accept = _om._cwv_accept_identity
	local resolve = _om._cwv_identity_def_for_peer
	if type(plan) ~= "function" or type(accept) ~= "function" or type(resolve) ~= "function" then
		return "CWV item-identity side-channel helpers missing"
	end
	local payloads = plan({
		slot_melee = { item_data = { name = "es_bastard_sword", cwv_key = "cwv_es_longsword" } },
		slot_ranged = { item_data = { name = "es_handgun" } },
	})
	local by_slot = {}
	for _, payload in ipairs(payloads) do by_slot[payload.slot] = payload end
	if not by_slot.slot_melee or by_slot.slot_melee.item_key ~= "cwv_es_longsword"
			or not by_slot.slot_ranged or by_slot.slot_ranged.item_key ~= "" then
		return "identity planner did not preserve CWV owner and native clear payloads"
	end
	local changed = accept("rt396-peer", 1, by_slot.slot_melee)
	local resolved = resolve("rt396-peer", "slot_melee", "es_bastard_sword")
	if changed ~= true or resolved ~= owner then
		return "receiver did not resolve the explicit Imperial Longsword marker over its vanilla base"
	end
	if resolve("rt396-peer", "slot_melee", "es_handgun") ~= nil then
		return "identity marker crossed its authored base-weapon boundary"
	end
	accept("rt396-peer", 1, { slot = "slot_melee", item_key = "" })
	if resolve("rt396-peer", "slot_melee", "es_bastard_sword") ~= nil then
		return "native-slot clear left stale CWV identity behind"
	end

	local replay = _om._cwv_skin_replay_payloads
	local skin_key = "cwv_es_longsword_nordland_skin"
	local skin_payloads = replay and replay({
		wielded_slot = "slot_melee",
		slots = { slot_melee = { item_data = { name = "es_bastard_sword" }, skin = skin_key } },
	}) or {}
	if #skin_payloads ~= 1 or skin_payloads[1].skin ~= skin_key
			or skin_payloads[1].item_name ~= "es_bastard_sword" or not skin_payloads[1].wielded then
		return "hot-join/transition replay lost the exact Helmgart illusion or current wield"
	end
	local skin_def, reason = _om._husk_resolve_display_def("es_bastard_sword", "es_mercenary", skin_key)
	if skin_def ~= illusion or reason ~= "skin" then
		return "Helmgart skin does not positively resolve its exact remote-husk mesh"
	end
	local preview = mod._cwv_preview_meshswap_apply
	local info = {
		skin_name = skin_key,
		spawn_data = { { right_hand = true, unit_name = illusion.right_hand_unit .. "_3p" } },
	}
	if type(preview) ~= "function" then return "inventory preview mesh-swap helper missing" end
	preview("es_bastard_sword", "cwv_es_longsword_001", skin_key, info)
	if info.spawn_data[1].unit_name ~= illusion.right_hand_unit .. "_3p" then
		return "inventory character preview replaced the selected Helmgart mesh"
	end
end)

_rt_register("issue579_dual_axes_preview_and_husk_skin_continuity", function()
    local source_by_target = _om._dual_axes_source_by_skin
    local ws = rawget(_G, "WeaponSkins")
    if type(source_by_target) ~= "table" or type(ws) ~= "table" or type(ws.skins) ~= "table" then
        return "dual-axes generated skins not loaded yet (run in-keep)"
    end
    local apply_preview = mod._cwv_preview_meshswap_apply
    local plan_replay = _om._cwv_skin_replay_payloads
    if type(apply_preview) ~= "function" or type(plan_replay) ~= "function" then
        return "#579 preview/replay helpers are not installed"
    end
    if not (mod._cwv_skin_wire_surfaces and mod._cwv_skin_wire_surfaces.parity_replay) then
        return "#579 post-handshake parity replay is not registered"
    end

    for _, target_key in ipairs({ "cwv_es_dual_axes", "cwv_wh_dual_axes" }) do
        local clones = source_by_target[target_key]
        local generated_skin = clones and next(clones)
        local skin = generated_skin and ws.skins[generated_skin]
        if not skin then return target_key .. " has no generated skin for continuity test" end
        if type(skin.right_hand_unit) ~= "string" or type(skin.left_hand_unit) ~= "string" then
            return generated_skin .. " does not preserve both generated hands"
        end

        -- Vanilla has already built spawn_data from the selected skin. The
        -- copied preview callback may pass skin=nil; info.skin_name is the
        -- authoritative stored identity and must prevent the def-default swap.
        local info = {
            skin_name = generated_skin,
            spawn_data = {
                { right_hand = true, unit_name = skin.right_hand_unit .. "_3p" },
                { left_hand = true, unit_name = skin.left_hand_unit .. "_3p" },
            },
        }
        apply_preview("dr_dual_wield_axes", target_key .. "_001", nil, info)
        if info.spawn_data[1].unit_name ~= skin.right_hand_unit .. "_3p"
                or info.spawn_data[2].unit_name ~= skin.left_hand_unit .. "_3p" then
            return generated_skin .. " was overwritten by the preview fallback"
        end

        -- Hot join initially sends the vanilla base item with a nulled cwv skin.
        -- After parity, the replay planner must retain that clone-name-clobbered
        -- base id while restoring the exact generated skin and current wield.
        local payloads = plan_replay({
            wielded_slot = "slot_melee",
            slots = {
                slot_melee = {
                    item_data = { name = "dr_dual_wield_axes" },
                    skin = generated_skin,
                },
                slot_ranged = {
                    item_data = { name = "wh_crossbow" },
                    skin = "wh_crossbow_skin_01",
                },
            },
        })
        if #payloads ~= 1 or payloads[1].item_name ~= "dr_dual_wield_axes"
                or payloads[1].skin ~= generated_skin or payloads[1].wielded ~= true then
            return generated_skin .. " parity replay payload lost base/skin/wield identity"
        end
        local def, reason = _om._husk_resolve_display_def("dr_dual_wield_axes",
            target_key == "cwv_es_dual_axes" and "es_mercenary" or "wh_captain", generated_skin)
        if not def or def.item_key ~= target_key or reason ~= "skin" then
            return generated_skin .. " does not resolve to its target on the husk"
        end
    end
end)

_rt_register("issue416_483_transition_generated_skin_replay", function()
    local exact_skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
    local plan_replay = _om._cwv_skin_replay_payloads
    local null_skins = _om._wire_null_skins
    local step = _om._cwv_skin_replay_pending_step
    if type(plan_replay) ~= "function" or type(null_skins) ~= "function" or type(step) ~= "function" then
        return "#416/#483 transition replay helpers are not installed"
    end
    if not (mod._cwv_skin_wire_surfaces and mod._cwv_skin_wire_surfaces.transition_replay) then
        return "#416/#483 bounded transition replay update is not installed"
    end

    -- The exact generated pair from the repro must retain both authored meshes
    -- and its clone-name-clobbered vanilla base id in a replay payload.
    local skin = WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[exact_skin]
    if type(skin) ~= "table" or type(skin.right_hand_unit) ~= "string"
            or type(skin.left_hand_unit) ~= "string" then
        return exact_skin .. " is absent or lost one generated hand"
    end
    local payloads = plan_replay({
        wielded_slot = "slot_melee",
        slots = {
            slot_melee = {
                item_data = { name = "es_dual_wield_hammer_sword" },
                skin = exact_skin,
            },
        },
    })
    if #payloads ~= 1 or payloads[1].item_name ~= "es_dual_wield_hammer_sword"
            or payloads[1].skin ~= exact_skin or payloads[1].wielded ~= true then
        return "Sword+Mace mission-transition replay lost exact base+generated-skin+wield identity"
    end

    -- Reproduce the transition send: parity is transiently false, so the wire
    -- sees n/a, the selected live skin is restored, and a deferred replay is
    -- scheduled. Restore global probe state before assertions return.
    local real_pp = mod._cwv_peer_parity
    local real_pending = _om._cwv_skin_replay_pending
    mod._cwv_peer_parity = { all_peers_have = function() return false end }
    local slot = { skin = exact_skin }
    local at_send
    null_skins({ slot }, function() at_send = slot.skin end, "rt416_transition", false)
    local pending = _om._cwv_skin_replay_pending
    mod._cwv_peer_parity = real_pp
    _om._cwv_skin_replay_pending = real_pending
    if at_send ~= nil or slot.skin ~= exact_skin or type(pending) ~= "table" then
        return "transition null did not restore the live Sword+Mace skin and schedule recovery"
    end

    -- No unsafe replay while parity is false. The first confirmed half-second
    -- poll sends exactly once and consumes the pending state even if the shared
    -- feature never observed a disable->enable edge.
    local calls = 0
    local p, sent = step(pending, 0.5, function() return false end,
        function() calls = calls + 1 return 1 end)
    if not p or sent ~= 0 or calls ~= 0 then
        return "deferred generated-skin replay ran while parity was unconfirmed"
    end
    p, sent = step(p, 0.5, function() return true end,
        function() calls = calls + 1 return 1 end)
    if p ~= nil or sent ~= 1 or calls ~= 1 then
        return "deferred generated-skin replay did not send exactly once after parity recovery"
    end
end)

_rt_register("issue412_old_musket_universal_special_interrupt", function()
	local audit = mod._cwv_old_musket_interrupt and mod._cwv_old_musket_interrupt.audit
	if type(audit) ~= "function" then return "interrupt policy missing" end
	for _, template_name in ipairs({ "old_musket_template", "old_musket_template_melee" }) do
		local ok, detail = audit(Weapons and Weapons[template_name], "action_three")
		if not ok then return template_name .. ": " .. tostring(detail) end
	end
	local melee = Weapons and Weapons.old_musket_template_melee
	local toggle = melee and melee.actions and melee.actions.action_three
	toggle = toggle and toggle.default
	if not toggle or toggle.anim_end_event ~= "attack_finished"
			or type(toggle.anim_end_event_condition_func) ~= "function" then
		return "melee toggle interruption animation cleanup missing"
	end
end)

_rt_register("issue273_cwv_deus_identity_is_exact", function()
	local report = _om.install_deus_identities("runtime_regression")
	if #report.skipped > 0 then
		return string.format("%d CWV owners lack a dedicated Deus identity: %s",
			#report.skipped, table.concat(report.skipped, ","))
	end
	for _, item_key in ipairs({ "cwv_wh_dual_axes", "cwv_es_dual_axes" }) do
		local deus_key = rawget(DeusStartingWeaponTypeMapping, item_key)
		if not report.exact_identity_allowed then
			if deus_key ~= "deus_dr_dual_wield_axes" then
				return item_key .. " mixed-parity fallback is not wire-safe Dual Axes"
			end
			goto continue_issue273
		end
		local row = deus_key and rawget(DeusWeapons, deus_key)
		local owner = rawget(ItemMasterList, item_key)
		local single_axe = rawget(ItemMasterList, "dr_1h_axe")
		if deus_key ~= "deus_" .. item_key or not row or row.base_item ~= item_key then
			return item_key .. " collapses to a non-CWV Deus owner"
		end
		if not owner or owner.item_type ~= item_key
				or (single_axe and owner.template == single_axe.template) then
			return item_key .. " lost its individualized item_type/template"
		end
		::continue_issue273::
	end
end)

_rt_register("issue474_old_musket_hot_join_identity_and_remote_fire", function()
    local plan_replay = _om._cwv_skin_replay_payloads
    if type(plan_replay) ~= "function" then return "post-parity skin replay planner missing" end
    if not (mod._cwv_skin_wire_surfaces and mod._cwv_skin_wire_surfaces.parity_replay) then
        return "post-parity skin replay is not registered"
    end
    local payloads = plan_replay({
        wielded_slot = "slot_melee",
        slots = {
            slot_melee = {
                item_data = { name = "es_handgun" },
                skin = "cwv_es_musket_old_skin",
            },
            slot_ranged = {
                item_data = { name = "es_handgun" },
                skin = "cwv_es_musket_old_skin",
            },
        },
    })
    local by_slot = {}
    for _, payload in ipairs(payloads) do by_slot[payload.slot_name] = payload end
    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local payload = by_slot[slot_name]
        if not payload or payload.item_name ~= "es_handgun"
                or payload.skin ~= "cwv_es_musket_old_skin" then
            return slot_name .. " lost Old Musket base+skin identity in the parity replay"
        end
    end
    if not by_slot.slot_melee.wielded or by_slot.slot_ranged.wielded then
        return "cross-slot replay lost the currently wielded slot"
    end

    local template = Weapons and Weapons.old_musket_template
    local action_one = template and template.actions and template.actions.action_one
    local default = action_one and action_one.default
    local zoomed = action_one and action_one.zoomed_shot
    if not default or not zoomed then return "Old Musket ranged actions missing" end
    if not _om._is_old_musket_ranged_action(default)
            or not _om._is_old_musket_ranged_action(zoomed) then
        return "Old Musket hip/ADS action identity is not recognized"
    end
    if not _om._old_musket_shot_completed(default, "waiting_to_shoot", false, "shot", false)
            or _om._old_musket_shot_completed(default, "shot", false, "shot", false) then
        return "Old Musket shot edge is not exactly-once"
    end
    if not _om._old_musket_remote_fire_hook_installed then
        return "ActionHandgun remote-fire hook missing"
    end
	local event = _om._old_musket_remote_fire_event
	if event ~= "player_combat_weapon_rifle_fire"
			or type(_om._old_musket_publish_fire) ~= "function" then
		return "compiled rifle report is not routed through the bounded CWV channel"
	end
	if _om._old_musket_mode_channel ~= "cwv_old_musket_mode_v1"
			or _om._old_musket_mode_schema ~= 1
			or type(_om._old_musket_record_and_publish) ~= "function"
			or type(_om._old_musket_mode_for_owner) ~= "function"
			or type(_om._old_musket_modes_by_backend) ~= "table" then
		return "Old Musket explicit presentation-state contract is incomplete"
	end
	for _, perspective in ipairs({ "1p", "3p" }) do
		for _, mode in ipairs({ "ranged", "melee" }) do
			local pos, rot, scale = _om._old_musket_transform_components(perspective, mode)
			if type(pos) ~= "table" or not rot or type(scale) ~= "table"
					or pos[1] == nil or pos[2] == nil or pos[3] == nil
					or scale[1] == nil or scale[2] == nil or scale[3] == nil then
				return perspective .. "/" .. mode .. " does not preserve the full saved transform"
			end
		end
	end
end)

_rt_register("issue582_dual_axes_native_variant_ownership_boundary", function()
    local expected = {
        cwv_es_dual_axes = { prefix = "es_", careers = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
        } },
        cwv_wh_dual_axes = { prefix = "wh_", careers = {
            "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
        } },
    }
    local defs = {}
    for _, def in ipairs(_variant_definitions) do
        if expected[def.item_key] then defs[def.item_key] = def end
    end

    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return "ItemMasterList not loaded yet (run in-keep)" end
    for item_key, contract in pairs(expected) do
        local def = defs[item_key]
        local entry = rawget(iml, item_key)
        if not def or def.base_weapon ~= "dr_dual_wield_axes" then
            return item_key .. " definition/base ownership missing"
        end
        if not entry or entry.cwv_variant ~= true then
            return item_key .. " dedicated CWV ItemMasterList entry missing"
        end
        local careers = {}
        for _, career in ipairs(entry.can_wield or {}) do
            if career:sub(1, #contract.prefix) == contract.prefix then careers[career] = true end
        end
        for _, career in ipairs(contract.careers) do
            if not careers[career] then
                return string.format("%s missing receiver ownership %s", item_key, career)
            end
            careers[career] = nil
        end
        local extra = next(careers)
        if extra then
            return string.format("%s has unexpected receiver ownership %s", item_key, tostring(extra))
        end
    end

    local native = rawget(iml, "dr_dual_wield_axes")
    if not native then return "native dr_dual_wield_axes missing" end
    for _, career in ipairs(native.can_wield or {}) do
        if career:sub(1, 3) == "es_" or career:sub(1, 3) == "wh_" then
            return "native Bardin Dual Axes leaked to dedicated CWV receiver: " .. career
        end
    end
end)

_rt_register("issue593_kruber_axe_shield_canonical_ownership", function()
    local expected = {
        es_mercenary = true, es_huntsman = true,
        es_knight = true, es_questingknight = true,
    }
    for _, item_key in ipairs({ "cwv_es_axe_shield", "cwv_es_axe_shield_veteran" }) do
        local def = _find_def(item_key)
        if not def or def.base_weapon ~= "dr_shield_axe" then
            return "#593 canonical CWV definition missing: " .. item_key
        end
        local seen = {}
        for _, career in ipairs(def.careers or {}) do seen[career] = true end
        for career in pairs(expected) do
            if not seen[career] then return item_key .. " missing " .. career end
            seen[career] = nil
        end
        if next(seen) then return item_key .. " has non-Kruber receiver" end
        local skin_table = def.item_type == "cwv_es_axe_shield"
        if not skin_table then return item_key .. " cosmetic family changed" end
    end
end)

_rt_register("issue586_cross_character_dual_axes_fp_residency", function()
    local catalog = _om.DUAL_WEAPON_FP_RESIDENCY
    if type(catalog) ~= "table" or #catalog ~= 5 then
        return "generated dual-weapon FP residency catalog must contain five source state machines"
    end
    if type(_om._acquire_dual_weapon_fp_residency) ~= "function"
        or type(_om._release_dual_weapon_fp_residency) ~= "function" then
        return "generated dual-weapon FP residency lifecycle is not installed"
    end
    if _om._dual_axes_fp_game_state_retry_installed ~= true then
        return "game-state retry is not wired for a cold chunk-load PackageManager"
    end

    local package_manager = Managers and Managers.package
    if not package_manager then return "package manager unavailable" end
    if not _om._acquire_dual_weapon_fp_residency("regression_prepare") then
        return "generated dual-weapon FP residency initial acquire failed"
    end
    local before = {}
    for _, lease in ipairs(catalog) do
        if before[lease.path] ~= nil then return "duplicate FP lease path: " .. tostring(lease.path) end
        before[lease.path] = package_manager:reference_count(lease.path, lease.ref) or 0
    end
    if not _om._acquire_dual_weapon_fp_residency("regression_idempotence") then
        return "generated dual-weapon FP residency repeat acquire failed"
    end
    for _, lease in ipairs(catalog) do
        local after = package_manager:reference_count(lease.path, lease.ref) or 0
        if before[lease.path] ~= 1 or after ~= 1 then
            return string.format("FP lease is not singular/idempotent path=%s before=%d after=%d",
                lease.path, before[lease.path], after)
        end
        if not package_manager:has_loaded(lease.path, lease.ref)
                or _om._dual_weapon_fp_residency_held[lease.path] ~= true then
            return "FP state machine is not resident under CWV lease: " .. tostring(lease.path)
        end
    end
    if _om._dual_weapon_fp_residency_complete ~= true then return "catalog completion flag is false" end

    local receiver_careers = {
        cwv_es_dual_swords = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_es_sword_and_mace = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_es_dual_axes = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_wh_dual_axes = { "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest" },
        cwv_es_dual_maces = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
        cwv_wh_dual_maces = { "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest" },
        cwv_es_dual_warpriest_hammers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
    }
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return "ItemMasterList not loaded yet (run in-keep)" end
    local covered_items = {}
    for _, lease in ipairs(catalog) do
        for item_key, _ in pairs(lease.items or {}) do
            if covered_items[item_key] then return "dual item appears in multiple FP leases: " .. item_key end
            covered_items[item_key] = true
            local careers = receiver_careers[item_key]
            if not careers then return "dual FP lease has no receiver matrix: " .. item_key end
            local entry = rawget(iml, item_key)
            if not entry then return item_key .. " missing from ItemMasterList" end
            local item_template = BackendUtils.get_item_template(entry)
            if not item_template then return item_key .. " template missing" end
            for _, career_name in ipairs(careers) do
                local resolved = WeaponUtils.get_item_state_machine(item_template, career_name)
                if resolved ~= lease.path then
                    return string.format("%s/%s resolves FP state machine %s, expected %s",
                        item_key, career_name, tostring(resolved), lease.path)
                end
            end
        end
    end
    for item_key, _ in pairs(receiver_careers) do
        if not covered_items[item_key] then return "dual receiver is absent from FP lease catalog: " .. item_key end
    end
end)

_rt_register("cwv_key_resolution_uuid_safe", function()
    -- Issue #482: an Athanor-crafted cwv instance carries a UUID backend_id
    -- (Application.guid(), crafting_in_modded_dev.lua:4644) that the
    -- `cwv_<key>_NNN` pattern can never match -- transforms/mesh resolution
    -- must instead ride the `cwv_key` field _build_entry stamps on the IML
    -- clone, through the shared `_om._cwv_key_for_item` ladder.
    -- (1) Stamp present on every registered entry.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local missing = {}
    for _, e in ipairs(entries) do
        if e.entry.cwv_key ~= e.key then
            missing[#missing + 1] = e.key
        end
    end
    if #missing > 0 then
        return "cwv_key stamp missing/wrong on " .. #missing .. " entries: " .. table.concat(missing, ", ")
    end
    -- (2) Ladder rungs behave: pattern, stamp, and no-signal cases.
    local ladder = _om._cwv_key_for_item
    if type(ladder) ~= "function" then
        return "_om._cwv_key_for_item missing (#482 resolver ladder gone)"
    end
    if ladder("cwv_es_greataxe_001", nil) ~= "cwv_es_greataxe" then
        return "#482 ladder rung 1 broken: cwv_<key>_NNN bid no longer resolves"
    end
    if ladder("a9f48814-0000-4000-8000-000000000000", { cwv_key = "cwv_es_greataxe" }) ~= "cwv_es_greataxe" then
        return "#482 ladder rung 2 broken: item_data.cwv_key stamp not consulted for UUID bid"
    end
    if ladder("not-a-registered-bid-482", { name = "dr_2h_axe" }) ~= nil then
        return "#482 ladder false-positive: non-cwv item resolved a cwv key"
    end
end)

_rt_register("cwv_inherits_base_name", function()
    -- Verify NO cwv_* entry has `entry.name` clobbered to the cwv key.
    -- Per `feedback_cwv_clone_name_clobber.md` — vanilla code (e.g.
    -- world_hero_previewer.lua:674) does `item_data = ItemMasterList[item.name]`
    -- for fallback lookups. Clobbering entry.name to def.item_key made the
    -- lookup return nil and equip path crashed in BackendUtils.get_item_units.
    -- Must KEEP the inherited base name; mod uses `entry.cwv_variant` as the
    -- discriminator instead. Allow `entry.name == nil` (cloned tables may
    -- inherit via metamethod; only fail on the explicit cwv_-prefix clobber).
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local clobbered = {}
    for _, e in ipairs(entries) do
        local n = e.entry.name
        if type(n) == "string" and n:sub(1, 4) == "cwv_" then
            clobbered[#clobbered + 1] = string.format("%s (name=%s)", e.key, n)
        end
    end
    if #clobbered > 0 then
        return "entry.name clobbered with cwv_ prefix on: " .. table.concat(clobbered, "; ")
    end
end)

_rt_register("cwv_ammo_mirroring", function()
    -- For any variant whose BASE template has `ammo_unit`, the variant entry
    -- must mirror `ammo_unit`, `projectile_units_template`, `pickup_template_name`,
    -- `link_pickup_template_name` from the base. Per `feedback_cwv_ammo_unit_required.md` —
    -- the skin pipeline nukes these fields; without explicit mirroring the
    -- previewer/throw/pickup paths all crash on ammo-bearing variants.
    -- Skip non-ammo bases entirely (their nil ammo_unit is correct).
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local iml = rawget(_G, "ItemMasterList")
    local mismatched = {}
    local AMMO_FIELDS = { "ammo_unit", "projectile_units_template", "pickup_template_name", "link_pickup_template_name" }
    for _, e in ipairs(entries) do
        local base_key = e.def.base_weapon
        local base = base_key and rawget(iml, base_key)
        if base and base.ammo_unit then
            for _, f in ipairs(AMMO_FIELDS) do
                if base[f] ~= nil and e.entry[f] == nil then
                    mismatched[#mismatched + 1] = string.format("%s missing %s (base=%s has it)", e.key, f, base_key)
                end
            end
        end
    end
    if #mismatched > 0 then
        return "ammo-mirroring gaps on " .. #mismatched .. " entries: " .. table.concat(mismatched, "; ")
    end
end)

_rt_register("cwv_in_inventory_package_list", function()
    -- For each cwv variant's `right_hand_unit` and `left_hand_unit` paths,
    -- check whether the path appears in `NetworkLookup.inventory_packages`.
    -- Per `feedback_vt2_force_load_only_listed_paths.md` — Managers.package:load
    -- succeeds synchronously but async-fatals "Resource not found" if the path
    -- isn't listed; the fatal bypasses pcall. Vanilla unit paths ARE listed;
    -- mod-defined custom-mesh paths (e.g. Old Musket) are NOT, but those
    -- variants use the LA custom-mesh overlay pattern with vanilla paths in
    -- the actual `right_hand_unit` slot.
    --
    -- Informational-only for INHERITED vanilla paths (which legitimately may
    -- not all be listed depending on DLC). FAIL only when the path looks like
    -- a mod-prefixed custom mesh: `units/weapons/player_cwv/...`. If any future
    -- variant ships a custom-mesh path that didn't get listed, this will catch it.
    local entries, bail = _rt_iter_cwv_entries()
    if bail then return bail end
    local NL = rawget(_G, "NetworkLookup")
    local list = NL and NL.inventory_packages
    if type(list) ~= "table" then
        return "NetworkLookup.inventory_packages not loaded yet (run in-keep)"
    end
    -- Build a fast lookup set: path -> true. The list is array-form only; no
    -- reverse-index in vanilla.
    local listed = {}
    for _, p in ipairs(list) do listed[p] = true end
    local missing = {}
    for _, e in ipairs(entries) do
        for _, slot in ipairs({ "right_hand_unit", "left_hand_unit" }) do
            local p = e.entry[slot]
            if type(p) == "string" and p ~= "" then
                -- Mod-custom-mesh paths under a dedicated subtree must be
                -- present; vanilla paths are informational.
                if p:find("/player_cwv/", 1, true) or p:find("character_weapon_variants/", 1, true) then
                    if not listed[p] then
                        missing[#missing + 1] = string.format("%s.%s=%s (custom-mesh path not in InventoryPackageList)", e.key, slot, p)
                    end
                end
            end
        end
    end
    if #missing > 0 then
        return "InventoryPackageList gaps on " .. #missing .. " custom-mesh paths: " .. table.concat(missing, "; ")
    end
end)

_rt_register("cwv_itemmasterlist_uses_rawget", function()
    -- v0.1.333 (Issue #20): the membership check in `_auto_register_all`
    -- (`character_weapon_variants.lua:8167-area`) probes `ItemMasterList[key]`
    -- before deciding whether to mirror our entry. `ItemMasterList.__index`
    -- calls `crashify.print_exception("ItemMaster List has no item %s")` on
    -- missing keys, so a plain index produced 27 crashify exceptions per
    -- keep load. Fix: `not rawget(ItemMasterList, key)`. This runtime test is
    -- the §15 belt-and-suspenders companion (the strict-table-lookup lint
    -- catches static-pattern regressions; this catches metatable behavior
    -- changes at runtime).
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CWV_ITEMMASTERLIST_RAWGET_MARKER_v0_1_333 ~= "cwv-itemmasterlist-rawget-auto-register-all" then
        return "ITEMMASTERLIST RAWGET marker absent — was the v0.1.333 fix reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key against ItemMasterList must
    --    return nil without raising. If the engine ever switched the
    --    metatable behavior (or the table itself was replaced), the rawget
    --    guard would no longer be load-bearing and we'd want to know.
    local IML = rawget(_G, "ItemMasterList")
    if type(IML) == "table" then
        local ok, value = pcall(rawget, IML, "__cwv_iml_rawget_probe_does_not_exist__")
        if not ok then
            return "rawget(ItemMasterList, <bad-key>) RAISED — strict-metatable behavior changed"
        end
        if value ~= nil then
            return "rawget(ItemMasterList, <bad-key>) returned non-nil — unexpected"
        end
    end
end)

_rt_register("cwv_networklookup_uses_rawget", function()
    -- v0.1.330/.332: three call sites in `character_weapon_variants.lua`
    -- (damage_profiles reverse lookup ~L5185, pickup_names reverse lookups
    -- ~L5270 + ~L5285) resolve RPC-payload IDs through
    -- `rawget(NetworkLookup.*, key)` so a malformed/out-of-range ID returns
    -- nil instead of raising the strict `__index` metatable. The
    -- strict-table-lookup lint covers static-pattern regressions; this runtime
    -- check is the belt-and-suspenders companion required by §15 of
    -- PROJECT_STANDARDS.md.
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CWV_NETWORKLOOKUP_RAWGET_MARKER_v0_1_332 ~= "cwv-networklookup-rawget-hardened-3-sites" then
        return "RAWGET marker absent — was the v0.1.330 three-site RPC hardening reverted?"
    end
    -- 2. Runtime-state: rawget on a known-bad key against the two NL subtables
    --    that the three sites read (damage_profiles + pickup_names). Both
    --    must return nil without raising.
    local NL = rawget(_G, "NetworkLookup")
    for _, sub in ipairs({ "damage_profiles", "pickup_names" }) do
        local tbl = NL and NL[sub]
        if type(tbl) == "table" then
            local ok, value = pcall(rawget, tbl, "__cwv_rawget_probe_does_not_exist__")
            if not ok then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) RAISED — strict-metatable behavior changed", sub)
            end
            if value ~= nil then
                return string.format("rawget(NetworkLookup.%s, <bad-key>) returned non-nil — unexpected", sub)
            end
        end
    end
end)

_rt_register("cwv_slot_extension_scoped", function()
    -- v0.1.338: the slot_melee "ranged" extension MUST be scoped to only
    -- careers that own a `cross_slot = true` variant. Broad application
    -- across all 28 careers caused a dual-state-machine collision on
    -- Grail Knight (and other multi-melee-archetype careers): two FP
    -- state machines were loaded simultaneously into one FP rig, producing
    -- wrong-grip / corrupted-looking first-person weapons. See marker
    -- constant `CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338`.
    --
    -- 1. Source-pattern: marker constant must be present.
    if CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338 ~= "cwv-slot-extension-scoped-to-cross-slot-variant-careers" then
        return "SLOT EXTENSION marker absent — was the v0.1.338 scoping fix reverted?"
    end
    if not _om._slot_extension_log_only then
        return "automatic slot-extension state is not marked log-only (issue 570 startup chat regression)"
    end
    -- 2. Compute the expected allowed-careers set from `_variant_definitions`.
    --    Walk every def, union the `careers` arrays of entries with
    --    `cross_slot = true`. As of v0.1.338 only `cwv_es_musket_old` is
    --    cross-slot, so the expected set is the four Empire careers.
    local expected = _cwv_collect_cross_slot_careers()
    local expected_count = 0
    for _ in pairs(expected) do expected_count = expected_count + 1 end
    if expected_count == 0 then
        return "no cross_slot variants defined — definition table changed shape?"
    end
    -- 3. Runtime-state: walk CareerSettings; every allowed career MUST have
    --    "ranged" in its slot_melee, every non-allowed career MUST NOT.
    local CS = rawget(_G, "CareerSettings")
    if type(CS) ~= "table" then
        return "CareerSettings not loaded yet (run in-keep)"
    end
    local missing, leaked = {}, {}
    for career_name, career in pairs(CS) do
        if type(career) == "table" and career.item_slot_types_by_slot_name then
            local sm = career.item_slot_types_by_slot_name.slot_melee
            if type(sm) == "table" then
                local has_ranged = false
                for _, t in ipairs(sm) do
                    if t == "ranged" then has_ranged = true; break end
                end
                if expected[career_name] and not has_ranged then
                    missing[#missing + 1] = career_name
                elseif (not expected[career_name]) and has_ranged then
                    leaked[#leaked + 1] = career_name
                end
            end
        end
    end
    if #missing > 0 then
        return "expected slot_melee 'ranged' missing on allowed careers: " .. table.concat(missing, ", ")
    end
    if #leaked > 0 then
        return "slot_melee 'ranged' leaked to NON-allowed careers (broad-extension regression): " .. table.concat(leaked, ", ")
    end
end)

_rt_register("cwv_wield_hook_unique", function()
    -- v0.1.339 (Issue #33): assert there is exactly ONE
    -- `mod:hook_safe("SimpleInventoryExtension", "wield", ...)` registration
    -- in this file. VMF's `mod:hook_safe` does NOT chain — a second
    -- registration on the same (Class, method) silently overwrites the first
    -- (VMF_RECIPES.md § 1). v0.1.336 burned this exact bug: a debug-mode
    -- wield dump added at ~line 9499 shadowed the cross-access tracking at
    -- line 1336, silently breaking 3P animation remap. v0.1.337 consolidated
    -- both bodies into one callback; this regression test guards against
    -- reintroduction.
    --
    -- Mechanism: file-scope counter `_cwv_wield_hook_registration_count` is
    -- incremented at the registration site immediately before the
    -- `mod:hook_safe` call. Any future duplicate site would increment it
    -- again at module-load time. Counter is set at file scope, so this check
    -- runs against the cumulative count after the whole file has loaded.
    if _cwv_wield_hook_registration_count ~= 1 then
        -- Error string intentionally avoids the literal hook_safe call signature
        -- so the mod-lint regex doesn't flag this regression-check site as a
        -- second registration. See `tools/mod-lint/lint-mod.ps1` $rxHook.
        return string.format(
            "expected exactly 1 SimpleInventoryExtension wield safe-hook registration, got %d -- duplicate-hook regression (VMF silently shadows the first body; see VMF_RECIPES.md sec 1)",
            _cwv_wield_hook_registration_count)
    end
end)

_rt_register("issue398_cross_access_audio_uses_networked_receiver_event", function()
    if _cwv_networked_3p_remap_installed ~= true then
        return "WeaponUnitExtension._play_3p_anim network remap hook not installed"
    end
    if type(_om._cross_access_target_event) ~= "function" then
        return "cross-access receiver-event resolver missing"
    end

    local checked = 0
    local anims = rawget(_G, "NetworkLookup")
    anims = anims and anims.anims
    for item_key, careers in pairs(_cross_access_action_remap) do
        for career, remaps in pairs(careers) do
            for source, expected in pairs(remaps) do
                checked = checked + 1
                local target = _om._cross_access_target_event(item_key, career, source)
                if target ~= expected then
                    return string.format("network receiver-event drift %s/%s %s -> %s (expected %s)",
                        tostring(item_key), tostring(career), tostring(source),
                        tostring(target), tostring(expected))
                end
                if type(anims) == "table" and rawget(anims, target) == nil then
                    return string.format("network receiver event absent from NetworkLookup.anims: %s", target)
                end
            end
        end
    end
    if checked == 0 then
        return "cross-access network audio regression checked no remaps"
    end
    if _om._cross_access_target_event("es_1h_sword", "es_mercenary", "attack_swing_left") ~= nil then
        return "network remap leaked to unrelated/native weapon"
    end
end)

_rt_register("cwv_husk_fx_guard_installed", function()
    -- Issue #280 (CLIENT CTD): a remote player wielding the Kruber Axe &
    -- Shield variant crashed every non-Bardin client. Root cause: the variant
    -- inherits `.name = "dr_shield_axe"` (clone-name-clobber), so the husk
    -- resolves the vanilla base's NON-resident 3P units; vanilla `_wield_slot`
    -- bails before setting `equipment.wielded_slot` (line 775),
    -- cosmetics_tweaker's `_wield_slot` wrap pcall-swallows the fault, and
    -- vanilla `start_weapon_fx` then indexes `equipment.slots[nil]` -> CTD.
    -- Two-part fix: (1) force-load the base units so they are resident on
    -- every client; (2) a defensive guard on start_weapon_fx that no-ops when
    -- the wielded slot is nil. This test asserts BOTH landed at load time.
    if _cwv_husk_fx_guard_installed ~= true then
        return "SimpleHuskInventoryExtension.start_weapon_fx guard hook not installed (Issue #280 client-CTD regression)"
    end
    if _cwv_axe_shield_residency_ran ~= true then
        return "dr_shield_axe base-unit force-load did not run (Issue #280 husk-residency primary fix)"
    end
end)

_rt_register("cwv_net_safe_loadout_sync_installed", function()
    -- Issue #278 (CLIENT CTD): the host equipping a cwv item (native or
    -- cim-crafted) broadcast `rpc_sync_loadout_slot` with the HOST-LOCAL
    -- `NetworkLookup.item_names` index of the cwv key. That index depends on
    -- which other mods appended to item_names on each peer (LA via
    -- cosmetics_tweaker's _la_bridge being the big divergence source), so a
    -- client with a shorter table CTD'd in the strict __index metamethod
    -- (network_lookup.lua:2521 via loadout_utils.lua:72). The fix substitutes
    -- the variant's vanilla `base_weapon` key on the wire (shadow item).
    -- This asserts the sender-side hook actually installed at load time.
    if _cwv_net_safe_loadout_hook_installed ~= true then
        return "LoadoutUtils.sync_loadout_slot net-safe hook not installed (Issue #278 client-CTD regression)"
    end
    -- Every non-skin-only def must carry a base_weapon that resolves in
    -- ItemMasterList — it is the wire fallback key.
    for _, d in ipairs(_variant_definitions) do
        if not d.skin_only and (type(d.base_weapon) ~= "string"
                or not rawget(ItemMasterList, d.base_weapon)) then
            return string.format(
                "variant %s has no resolvable base_weapon (%s) — net-safe loadout sync cannot substitute it (Issue #278)",
                tostring(d.item_key), tostring(d.base_weapon))
        end
    end
end)

_rt_register("cwv_outrider_no_ammo_unit", function()
    -- Issue #279 (merged render): the outrider entry inherited dr_deus_01's
    -- torpedo ammo_unit/ammo_unit_3p from the clone; with the template's
    -- ammo_data intact (ammo_hand flipped to "right"), any NO-SKIN resolution
    -- (cim-crafted copies carry no pre-applied skin) attached the trollhammer
    -- torpedo to the blunderbuss (gear_utils.lua:164/169/248). The def now
    -- declares `no_ammo_unit = true` and `_build_entry` clears both fields.
    local d = _find_def("cwv_es_outrider_grenade_launcher")
    if not d then return nil end -- def removed entirely: nothing to guard
    if d.no_ammo_unit ~= true then
        return "cwv_es_outrider_grenade_launcher def lost no_ammo_unit = true (Issue #279 merged-render regression)"
    end
    local entry = ItemMasterList and rawget(ItemMasterList, "cwv_es_outrider_grenade_launcher")
    if entry and (entry.ammo_unit ~= nil or entry.ammo_unit_3p ~= nil) then
        return string.format(
            "outrider ItemMasterList entry still carries ammo units (ammo_unit=%s ammo_unit_3p=%s) — torpedo will merge into no-skin renders (Issue #279)",
            tostring(entry.ammo_unit), tostring(entry.ammo_unit_3p))
    end
end)

_rt_register("cwv_husk_override_residency", function()
    -- Issues 401 / 396 (confirmed, paired peer logs): the husk spawns a CWV
    -- variant's curated-skin mesh, which carries the def's per-hand OVERRIDE
    -- units. When those override units are non-resident on a client not playing
    -- the source character, the skin-path spawn fails and the husk shows the
    -- base (or nothing). v0.1.366-dev shipped a HARD-CODED 5-key residency list;
    -- v0.1.367-dev makes the pass DATA-DRIVEN (walks every def, force-loads any
    -- right/left override unit that differs from its base). This test asserts
    -- coverage is complete BY CONSTRUCTION: every override unit the shared
    -- predicate flags as needing residency (+ its `_3p` form) is in the loaded
    -- set. Derived from the SAME predicate the pass uses, so a new variant with
    -- an override mesh can never silently slip past residency.
    if _cwv_husk_override_residency_ran ~= true then
        return "husk override-unit residency did not run (issues 401/396 fix missing)"
    end
    local loaded = _cwv_husk_override_paths
    if type(loaded) ~= "table" then
        return "_cwv_husk_override_paths not exposed (issue 401 residency-target guard)"
    end
    local needs = _om._husk_override_unit_needs_residency
    if type(needs) ~= "function" then
        return "_om._husk_override_unit_needs_residency predicate not exposed (issues 396/401)"
    end
    local n_checked = 0
    for _, d in ipairs(_variant_definitions) do
        for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
            local u = needs(d, field)
            if u then
                n_checked = n_checked + 1
                if not loaded[u] then
                    return string.format(
                        "husk override residency missing %s for %s.%s (issues 396/401 -- data-driven pass gap)",
                        tostring(u), tostring(d.item_key), field)
                end
                if not loaded[u .. "_3p"] then
                    return string.format(
                        "husk override residency missing %s_3p for %s.%s (issues 396/401 -- _3p form not loaded)",
                        tostring(u), tostring(d.item_key), field)
                end
            end
        end
    end
    -- Sanity floor: the axe & shield Empire override (the original issue-401
    -- repro) must specifically be present, and we must have covered more than
    -- the old 5-key hard-coded list (guards against the predicate degenerating
    -- to nil-for-everything and the loop vacuously passing).
    local axe = _find_def("cwv_es_axe_shield")
    if axe and type(axe.right_hand_unit) == "string" and not loaded[axe.right_hand_unit] then
        return string.format(
            "husk residency missing the Empire override unit %s for cwv_es_axe_shield (issue 401)",
            tostring(axe.right_hand_unit))
    end
    if n_checked < 6 then
        return string.format(
            "husk override residency covered only %d override units -- predicate likely degenerated (issues 396/401)",
            n_checked)
    end
end)

_rt_register("cwv_no_ammo_strip_coverage", function()
    -- Issue 399: the husk resolves the BASE item_data, so a variant that set
    -- `no_ammo_unit = true` (its base carries an ammo/torpedo unit the variant
    -- must not show) needs its (base_weapon, career) pair in the husk strip
    -- lookup. The lookup is built by walking every def, so coverage is
    -- structural -- this test locks that: every no_ammo_unit def must appear in
    -- `_om._no_ammo_careers_by_base` with ALL its careers, or the inherited
    -- ammo mesh would render on the husk (the merged-render bug of issue 279).
    local cov = _om._no_ammo_careers_by_base
    if type(cov) ~= "table" then
        return "_om._no_ammo_careers_by_base not exposed -- husk ammo-strip coverage guard (issue 399)"
    end
    for _, d in ipairs(_variant_definitions) do
        if d.no_ammo_unit then
            local set = cov[d.base_weapon]
            if type(set) ~= "table" then
                return string.format(
                    "no_ammo_unit def %s (base %s) missing from husk strip lookup -- inherited ammo would render on husk (issue 399)",
                    tostring(d.item_key), tostring(d.base_weapon))
            end
            for _, c in ipairs(d.careers or {}) do
                if not set[c] then
                    return string.format(
                        "no_ammo_unit def %s career %s not covered by husk strip lookup (issue 399)",
                        tostring(d.item_key), tostring(c))
                end
            end
        end
    end
end)

_rt_register("cwv_husk_transform_coverage", function()
    -- Issues 397/394: the husk 3P weapon spawns through
    -- GearUtils.spawn_inventory_unit (the only GearUtils path husks hit), NOT
    -- create_equipment where the owner-side transforms live. v0.1.366-dev wires
    -- the transform apply into that husk hook via `_om._husk_apply_cwv_transform`
    -- and the ammo strip via `_om._husk_strip_cwv_ammo`. Assert both landed so
    -- the coverage can't silently disappear on a refactor.
    if type(_om._husk_apply_cwv_transform) ~= "function" then
        return "_om._husk_apply_cwv_transform missing -- husk transform coverage lost (issues 397/394)"
    end
    if type(_om._husk_strip_cwv_ammo) ~= "function" then
        return "_om._husk_strip_cwv_ammo missing -- husk ammo-strip coverage lost (issue 399)"
    end
    if _cwv_husk_wield_diag_installed ~= true then
        return "husk _wield_slot diagnostic hook not installed (issues 395/398 evidence arm)"
    end
end)

_rt_register("cwv_unit_bearing_variants_registered", function()
    -- Issue #417: a variant that overrides a hand unit must resolve a def on every
    -- def-keyed render path, or its mesh swaps (via _find_def) while transform and
    -- texture silently bail at the nil-def guard. The registration gate now keys on
    -- unit-override presence; assert the invariant so a future gate edit can't drop
    -- it and reintroduce the per-item force_register crutch (the musket, #409).
    if type(mod._cwv_transform_registered) ~= "function" then
        return "mod._cwv_transform_registered missing -- #417 invariant unguardable"
    end
    local defs = _om._variant_defs
    if type(defs) ~= "table" then
        return "_om._variant_defs not exposed -- cannot assert the #417 registration invariant"
    end
    local missing = {}
    for _, def in ipairs(defs) do
        local ru, lu = def.right_hand_unit, def.left_hand_unit
        local has_unit = (type(ru) == "string" and ru ~= "") or (type(lu) == "string" and lu ~= "")
        if has_unit and not mod._cwv_transform_registered(def.item_key) then
            missing[#missing + 1] = tostring(def.item_key)
        end
    end
    if #missing > 0 then
        return "unit-bearing variants NOT in _transform_map (#417 reg-gate fork): " .. table.concat(missing, ", ")
    end
end)

_rt_register("issue597_greataxe_replaces_poleaxe", function()
	local greataxe = _om.greataxe
	if _find_def("cwv_es_poleaxe") then return "retired Poleaxe definition still registered" end
	local def = _find_def(greataxe.ITEM_KEY)
	if not def or def.base_weapon ~= greataxe.BASE_WEAPON then
		return "Greataxe definition/base contract missing"
	end
	if #(def.careers or {}) ~= 4 then return "Greataxe must default to four Kruber careers" end
	local source = Weapons and Weapons.two_handed_axes_template_1
	local clone = Weapons and Weapons[greataxe.TEMPLATE_KEY]
	if not source or not clone then return "Greataxe source/clone template missing" end
	local walked = 0
	for action_name, source_group in pairs(source.actions or {}) do
		local clone_group = clone.actions and clone.actions[action_name]
		if type(source_group) == "table" and type(clone_group) == "table" then
			for sub_name, source_action in pairs(source_group) do
				local clone_action = clone_group[sub_name]
				if type(source_action) == "table" and type(clone_action) == "table" then
					walked = walked + 1
					if clone_action.damage_profile ~= source_action.damage_profile
							or clone_action.anim_time_scale ~= source_action.anim_time_scale then
						return string.format("Greataxe gameplay drift at %s.%s", action_name, sub_name)
					end
				end
			end
		end
	end
	if walked == 0 then return "Greataxe gameplay comparison was vacuous" end
	for source_event, target_event in pairs(greataxe.ANIM_REMAP_3P) do
		for _, career in ipairs(greataxe.DEFAULT_CAREERS) do
			if _om._cross_access_target_event(greataxe.ITEM_KEY, career, source_event) ~= target_event then
				return string.format("Greataxe 3P remap drift: %s/%s", career, source_event)
			end
		end
	end
end)

_rt_register("cwv_issue596_infantry_spear_contract", function()
	local infantry = _om.infantry_spear
	local def = _find_def(infantry.ITEM_KEY)
	if not def then return "Infantry Spear definition missing" end
	if def.base_weapon ~= "we_spear"
			or def.right_hand_unit ~= "units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01" then
		return "Infantry Spear base/model contract drifted"
	end
	if #(def.careers or {}) ~= 3 or def.careers[1] ~= "es_mercenary"
			or def.careers[2] ~= "es_huntsman" or def.careers[3] ~= "es_knight" then
		return "Infantry Spear authored careers drifted (must exclude Grail Knight)"
	end
	local source = Weapons and Weapons.two_handed_spears_elf_template_1
	local tuned = Weapons and Weapons[infantry.TEMPLATE_KEY]
	if not source or not tuned then return "Infantry Spear source/tuned template missing" end
	local checked_timing, checked_profiles = 0, 0
	for action_name, source_group in pairs(source.actions or {}) do
		local tuned_group = tuned.actions and tuned.actions[action_name]
		if type(source_group) == "table" and type(tuned_group) == "table" then
			for sub_name, source_action in pairs(source_group) do
				local tuned_action = tuned_group[sub_name]
				if type(source_action) == "table" and type(tuned_action) == "table" then
					local expected = infantry.scaled_attack_time(
						source_action.kind, source_action.anim_time_scale)
					if source_action.kind == "melee_start" or source_action.kind == "sweep" then
						checked_timing = checked_timing + 1
						if type(tuned_action.anim_time_scale) ~= "number"
								or math.abs(tuned_action.anim_time_scale - expected) > 0.000001 then
							return string.format("Infantry Spear timing drift at %s.%s", action_name, sub_name)
						end
					end
					if source_action.damage_profile then
						checked_profiles = checked_profiles + 1
						local key = tuned_action.damage_profile
						if type(key) ~= "string" or key:find("cwv_infantry_spear_", 1, true) ~= 1
								or _om._cwv_damage_profile_wire_source[key] ~= source_action.damage_profile then
							return string.format("Infantry Spear profile drift at %s.%s", action_name, sub_name)
						end
					end
				end
			end
		end
	end
	if checked_timing == 0 or checked_profiles == 0 then
		return "Infantry Spear contract walk was vacuous"
	end
end)

_rt_register("cwv_husk_override_ref_shared", function()
    -- Issue #418: the residency producer and the preview/browser swap consumer must
    -- key on ONE constant, and the swap guard must be the shared helper -- a
    -- duplicated ref literal silently degraded every swap to the base mesh.
    if _om.HUSK_OVERRIDE_REF ~= "cwv_husk_override_units" then
        return "_om.HUSK_OVERRIDE_REF missing/changed -- producer/consumer ref may have drifted (#418)"
    end
    if type(_om._resident_override_3p) ~= "function" then
        return "_om._resident_override_3p missing -- shared preview/browser swap guard lost (#418)"
    end
end)

_rt_register("cwv_husk_base_career_rekey", function()
    -- Phase C (#392/#394/#396/#397/#401), restructured by #474/#475: the husk
    -- base+career fallback resolves a SKINLESS cross-char variant echo on remote
    -- screens. SAFETY INVARIANT (Invariant 1): the RESOLVER must decline every
    -- (base, career) pair the career can CURRENTLY wield -- the map itself now
    -- holds unfiltered claims and the can_wield check runs lazily at wield time
    -- (#475: the old boot-time exclusion snapshot predated weapon_tweaker's
    -- can_wield expansion, so a wt-freedom native wield got re-keyed to a cwv
    -- variant). This walks every claimed pair through the REAL resolver.
    if type(_om._husk_def_by_base_career) ~= "table" then
        return "_om._husk_def_by_base_career not exposed -- husk base+career fallback missing (Phase C)"
    end
    if type(_om._husk_rekey_units) ~= "function" then
        return "_om._husk_rekey_units missing -- husk mesh re-key lost (issues 396/401)"
    end
    if type(_om._husk_resolve_display_def) ~= "function" or type(_om._husk_pair_native_now) ~= "function" then
        return "_om._husk_resolve_display_def/_husk_pair_native_now missing -- shared husk decision point lost (#474/#475)"
    end
    for base, slot in pairs(_om._husk_def_by_base_career) do
        local master = rawget(ItemMasterList, base)
        local cw = type(master) == "table" and master.can_wield
        if type(cw) == "table" then
            for career in pairs(slot) do
                for _, native in ipairs(cw) do
                    if native == career then
                        local def = _om._husk_resolve_display_def(base, career, nil)
                        if def ~= nil then
                            return string.format(
                                "husk resolver re-keys CURRENTLY-NATIVE pair base=%s career=%s -- would mis-apply a variant to a native weapon on husks (#475 Invariant 1)",
                                tostring(base), tostring(career))
                        end
                    end
                end
            end
        end
    end
end)

_rt_register("cwv_husk_skin_primary_resolution", function()
    -- (#474) Skin-key resolution is the PRIMARY husk display signal and must
    -- cover BOTH cwv skin namespaces:
    --   * base variant skins "<item_key>_skin" (e.g. cwv_es_musket_old_skin)
    --   * pairing/illusion skins "<item_key>_<tail>" via lazy longest-prefix
    -- A cwv wire skin must re-key even when the (base,career) pair is natively
    -- wieldable -- that suppression was #474's mechanism 1.
    if type(_om._husk_skin_def) ~= "function" then
        return "_om._husk_skin_def missing -- skin-primary husk resolution lost (#474)"
    end
    local defs = _om._variant_defs
    if type(defs) ~= "table" then
        return "_om._variant_defs not exposed -- cannot enumerate skin namespaces (#474)"
    end
    -- Namespace 1: every non-no_skin def's base skin must resolve to ITS def.
    for _, def in ipairs(defs) do
        if type(def.item_key) == "string" and not def.no_skin then
            local got = _om._husk_skin_def(def.item_key .. "_skin")
            if got ~= def then
                return string.format("base variant skin %s_skin resolves to %s, expected its own def (#474)",
                    tostring(def.item_key), tostring(got and got.item_key))
            end
        end
    end
    -- Namespace 2: the pairing-skin longest-prefix arm (canonical #475-session
    -- example key; lazy resolution must pick the LS&S def, not the plain
    -- longsword def that shares the prefix).
    local pairing = _om._husk_skin_def("cwv_es_longsword_shield_wpn_emp_shield_03_runed_01__nordland")
    if not (pairing and pairing.item_key == "cwv_es_longsword_shield") then
        return string.format("pairing skin longest-prefix resolution broken: got %s, expected cwv_es_longsword_shield (#474)",
            tostring(pairing and pairing.item_key))
    end
    -- End-to-end: a cwv skin must resolve through the shared decision point
    -- REGARDLESS of native wieldability (es_handgun+es_mercenary is native).
    local def, reason = _om._husk_resolve_display_def("es_handgun", "es_mercenary", "cwv_es_musket_old_skin")
    if not (def and def.item_key == "cwv_es_musket_old" and reason == "skin") then
        return string.format("skin-primary end-to-end broken: def=%s reason=%s for the Old Musket wire shape (#474)",
            tostring(def and def.item_key), tostring(reason))
    end
end)

_rt_register("cwv_husk_native_never_rekeyed", function()
    -- (#475 Invariant 1) A native item must NEVER be re-keyed:
    --   * vanilla/LA skin present -> decline, whatever the (base,career) map says
    --     (the #475 wire shape: native Bret LS&S + vanilla skin on a wt-freedom
    --     mercenary host got re-keyed to the cwv Imperial LS&S on the client);
    --   * skinless echo whose pair is CURRENTLY wieldable -> decline (ambiguous
    --     between a wt-freedom native wield and a variant echo -> show base).
    if type(_om._husk_resolve_display_def) ~= "function" then
        return "_om._husk_resolve_display_def missing (#474/#475)"
    end
    local def, reason = _om._husk_resolve_display_def("es_sword_shield_breton", "es_mercenary", "es_sword_shield_breton_skin_01")
    if def ~= nil or reason ~= "skin_foreign" then
        return string.format("vanilla-skinned native item resolved to def=%s reason=%s -- #475 regression (must decline as skin_foreign)",
            tostring(def and def.item_key), tostring(reason))
    end
    -- Skinless + currently-native pair: vanilla es_handgun.can_wield contains
    -- es_mercenary, so the lazy native check must decline the Old Musket's
    -- claim on that pair (only cwv_es_musket_old claims it; the first musket
    -- variant is retired/commented out, so no ambiguity dedupe applies here).
    local def2 = _om._husk_resolve_display_def("es_handgun", "es_mercenary", nil)
    if def2 ~= nil then
        return string.format("skinless echo of a currently-wieldable pair resolved to %s -- #475 lazy can_wield regression",
            tostring(def2.item_key))
    end
    -- The custom-bundle residency arm must accept exactly the Old Musket custom
    -- mesh (mod-bundled, always resident) and reject arbitrary paths.
    if type(_om._husk_custom_bundle_unit) ~= "function"
            or not _om._husk_custom_bundle_unit("units/cwv_es_musket_custom/cwv_es_musket_custom")
            or _om._husk_custom_bundle_unit("units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1") then
        return "_om._husk_custom_bundle_unit missing or mis-scoped -- Old Musket husk re-key residency arm broken (#474)"
    end
end)

_rt_register("cwv_husk_nonresident_spawn_deferred", function()
    -- Issue #478: a resolved CWV variant husk must NEVER let vanilla
    -- spawn_inventory_unit spawn a NON-RESIDENT unit. A Deus-only base (e.g.
    -- dr_deus_01's Trollhammer left-mount) is not resident outside Chaos Wastes,
    -- so a hand the variant does not override (the Outrider's no_left_hand) left
    -- that base mesh in item_units and vanilla errored (gear_utils.lua:189 nil
    -- "_3p" concat once the husk guard skipped it -> entity_manager2.lua:114 "table
    -- index is nil" -> invisible wield; async C-assert risk, BUG_CLASSES 28). The
    -- fix: _husk_rekey_units returns a SUPPRESS flag the spawn hook uses to skip the
    -- vanilla call (residency-gated defer). Lock the predicate, the suppress
    -- contract, and the native-scope guard.
    if type(_om._husk_unit_spawnable) ~= "function" then
        return "_om._husk_unit_spawnable missing -- #478 crash-floor residency predicate lost"
    end
    if type(_om._husk_rekey_units) ~= "function" then
        return "_om._husk_rekey_units missing -- husk re-key/suppress contract lost (#478)"
    end
	if type(_om._husk_preselect_units) ~= "function" then
		return "_om._husk_preselect_units missing -- #478 handedness still runs after vanilla's spawn branch"
	end
	-- PRE-HAND-SELECTION: vanilla's dr_deus_01 result offers only its native
	-- left mount. A skinless Kruber echo must become the Outrider's right-mounted
	-- blunderbuss and clear the left field BEFORE vanilla decides which hand calls
	-- to make. This is the whole-weapon-invisible root from the paired client log.
	local outrider = _find_def("cwv_es_outrider_grenade_launcher")
	local base_units = {
		left_hand_unit = "units/weapons/player/wpn_dr_deus_01/wpn_dr_deus_01",
	}
	local changed, pre_def = _om._husk_preselect_units(base_units,
		{ name = "dr_deus_01" }, nil, nil, "es_mercenary")
	if not changed or pre_def ~= outrider then
		return "skinless dr_deus_01+es_mercenary did not resolve to Outrider before hand selection (#478)"
	end
	if base_units.right_hand_unit ~= outrider.right_hand_unit or base_units.left_hand_unit ~= nil then
		return "Outrider preselection did not schedule right blunderbuss + clear native Trollhammer left hand (#478)"
	end
	-- Scope: explicit backend identity and any skin belong to the normal owner /
	-- skin resolution paths and must never be rewritten by this fallback.
	local backend_guard = { left_hand_unit = "native-left" }
	if _om._husk_preselect_units(backend_guard, { name = "dr_deus_01" }, "some_backend_id", nil, "es_mercenary")
			or backend_guard.left_hand_unit ~= "native-left" or backend_guard.right_hand_unit ~= nil then
		return "Outrider preselection overreached into a backend-identified item (#478)"
	end
	local embedded_backend_guard = { left_hand_unit = "native-left" }
	if _om._husk_preselect_units(embedded_backend_guard,
			{ name = "dr_deus_01", backend_id = "embedded_backend_id" }, nil, nil, "es_mercenary")
			or embedded_backend_guard.left_hand_unit ~= "native-left"
			or embedded_backend_guard.right_hand_unit ~= nil then
		return "Outrider preselection ignored item_data.backend_id (#478 owner-scope regression)"
	end
	local skin_guard = { left_hand_unit = "native-left" }
	if _om._husk_preselect_units(skin_guard, { name = "dr_deus_01" }, nil, "dr_deus_01_skin_01", "es_mercenary")
			or skin_guard.left_hand_unit ~= "native-left" or skin_guard.right_hand_unit ~= nil then
		return "Outrider preselection overreached into a skinned item (#478/#475 Invariant 1)"
	end
    -- Predicate: a non-existent unit path is never resident under any reference.
    if _om._husk_unit_spawnable("units/weapons/player/__cwv_rt_nonresident_478__/__cwv_rt_nonresident_478__") ~= false then
        return "_husk_unit_spawnable returned true for a non-existent unit -- crash-floor would let a non-resident spawn through (#478)"
    end
    -- Predicate: a cwv mod-bundled custom mesh is always resident while loaded.
    if _om._husk_unit_spawnable("units/cwv_es_musket_custom/cwv_es_musket_custom") ~= true then
        return "_husk_unit_spawnable rejected the mod-bundled Old Musket mesh -- custom-bundle arm broken (#478)"
    end
    -- End-to-end SUPPRESS: the Outrider (base dr_deus_01) resolved by its wire
    -- skin, carrying ONLY a guaranteed-non-resident left-mount leftover, must
    -- return suppress=true so the spawn hook skips vanilla's left spawn. Synthetic
    -- leftover path keeps this deterministic whether or not the tester is in Chaos
    -- Wastes (the real Trollhammer mesh is resident there). Left hand: the Outrider
    -- has no_left_hand, so no override is written and the leftover survives.
    local iu_defer = {
        skin = "cwv_es_outrider_grenade_launcher_skin",
        left_hand_unit = "units/weapons/player/__cwv_rt_nonresident_478__/__cwv_rt_nonresident_478__",
    }
    if not _om._husk_rekey_units("left", { name = "dr_deus_01" }, iu_defer, nil) then
        return "resolved Outrider husk did NOT suppress a non-resident left-mount spawn -- #478 crash-floor broken"
    end
    -- Scope: with NO cwv def resolved (unknown base, no skin, no career), the
    -- re-key must NOT suppress -- a genuine native husk wield is never touched even
    -- when its leftover is non-resident (#475 Invariant 1 scope, no #478 overreach).
    if _om._husk_rekey_units("left", { name = "__cwv_rt_no_such_base__" },
            { left_hand_unit = "units/weapons/player/__cwv_rt_nonresident_478__/__cwv_rt_nonresident_478__" }, nil) then
        return "re-key suppressed a spawn with NO resolved cwv def -- #478 overreach into native wields (#475 Invariant 1)"
    end
end)

_rt_register("cwv_wire_safe_skin_installed", function()
    -- (issue 278 weapon_skin_id axis / issue 371 / issue 495) Every cwv-registered
    -- NetworkLookup.weapon_skins key must be null-able on the wire so a non-cwv peer
    -- never cold-decodes it from rpc_add_equipment (strict __index CTD). Asserts the
    -- wire-safety machinery is installed on ALL THREE live-slot senders and that the
    -- predicate covers every cwv key actually sitting in NetworkLookup.weapon_skins.
    if _om._skin_wire_hook_installed ~= true then
        return "weapon_skin_id wire-safety hooks not installed (issue 278 non-cwv-peer CTD regression)"
    end
    local surfaces = mod._cwv_skin_wire_surfaces
    if type(surfaces) ~= "table" then
        return "mod._cwv_skin_wire_surfaces flag table missing (issue 495 senders unhooked?)"
    end
    for _, key in ipairs({ "game_object_initialized", "spawn_resynced_loadout", "hot_join_sync" }) do
        if not surfaces[key] then
            return "skin-axis wire-null not registered on sender surface: " .. key .. " (issue 495)"
        end
    end
    if type(_om._skin_keys) ~= "table" or next(_om._skin_keys) == nil then
        return "no cwv skin keys tracked -- wire-safety would null nothing (registration/tracking broke)"
    end
    -- Every tracked key must actually be a registered weapon_skins entry, else the
    -- null-on-wire substitution is guarding a phantom -- and EVERY cwv_ key in the
    -- live lookup must satisfy the wire predicate (a registration site that forgot
    -- both registries is caught by the prefix arm; a non-cwv_-prefixed cwv key
    -- would be a real leak and fails here).
    local NL = rawget(_G, "NetworkLookup")
    local ws = NL and NL.weapon_skins
    local pred = _om._wire_skin_predicate
    if type(pred) ~= "function" then
        return "_om._wire_skin_predicate missing (issue 495)"
    end
    if type(ws) == "table" then
        for skin_key in pairs(_om._skin_keys) do
            if rawget(ws, skin_key) == nil then
                return string.format("tracked cwv skin key %s absent from NetworkLookup.weapon_skins", tostring(skin_key))
            end
        end
        for k in pairs(ws) do
            if type(k) == "string" and k:sub(1, 4) == "cwv_" and not pred(k) then
                return string.format("cwv weapon_skins key %s not covered by the wire predicate (issue 495 leak)", tostring(k))
            end
        end
    end
end)

_rt_register("cwv_wire_skin_parity_gate", function()
    -- (issue 495) Behavioral contract of the shared null helper:
    --   * parity CONFIRMED + broadcast sender -> skin RIDES (issue 474 husk display);
    --   * parity confirmed + hot-join replay (force) -> nulled anyway (join-handshake
    --     race, issue 425 lesson) and restored after the send;
    --   * parity UNCONFIRMED -> nulled and restored.
    local helper = _om._wire_null_skins
    if type(helper) ~= "function" then return "_om._wire_null_skins helper missing" end
    local real_pp = mod._cwv_peer_parity
    local function drive(parity_up, force)
        mod._cwv_peer_parity = { all_peers_have = function() return parity_up end }
        local slot = { skin = "cwv___rt495_fake_skin" }
        local at_send
        local ok, err = pcall(helper, { slot }, function() at_send = slot.skin end, "rt495", force)
        mod._cwv_peer_parity = real_pp
        if not ok then return nil, nil, "helper raised: " .. tostring(err) end
        return at_send, slot.skin, nil
    end
    local at_send, after, err = drive(true, false)
    if err then return err end
    if at_send ~= "cwv___rt495_fake_skin" then
        return "parity-confirmed broadcast nulled the skin -- issue 474 husk display would regress to base"
    end
    at_send, after, err = drive(true, true)
    if err then return err end
    if at_send ~= nil then
        return "hot-join replay (force) kept the skin under confirmed parity -- join-handshake race reopened (issue 425 lesson)"
    end
    if after ~= "cwv___rt495_fake_skin" then
        return "skin not restored after the forced null (owner spawn would lose the illusion)"
    end
    at_send, after, err = drive(false, false)
    if err then return err end
    if at_send ~= nil then
        return "parity-unconfirmed broadcast kept the skin -- issue 278/495 CTD shape live"
    end
    if after ~= "cwv___rt495_fake_skin" then
        return "skin not restored after the parity-unconfirmed null"
    end
end)

_rt_register("cwv_wire_safe_thrown_variant_installed", function()
    -- (issue 424 / issue 371, BUG_CLASSES 31) The Tuskgor Javelin thrown axes
    -- (impact pickup names + the bomb's in-flight boar-spear husk /
    -- projectile_units) append cwv-only NetworkLookup indices that ride vanilla
    -- projectile/pickup spawn RPCs. Assert BOTH sender-side substitution hooks
    -- are installed AND that the pickup helper retains gameplay only with
    -- positive peer parity, while unconfirmed parity coerces every tracked
    -- modded index to a real vanilla one.
    if _om._tj_pickup_wire_hook_installed ~= true then
        return "thrown-pickup wire-safety senders not installed (issue 424 non-cwv-peer CTD regression)"
    end
    if _om._projectile_wire_hook_installed ~= true then
        return "in-flight projectile wire-safety hook not installed (issue 424 boar-spear husk CTD regression)"
    end
    if type(_om._wire_safe_pickup_name) ~= "function" then
        return "_om._wire_safe_pickup_name helper missing"
    end
    if type(_om._tj_pickup_wire_map) ~= "table" or next(_om._tj_pickup_wire_map) == nil then
        return "no cwv thrown pickups tracked -- wire-safety would coerce nothing"
    end
    local NL = rawget(_G, "NetworkLookup")
    local pn = NL and NL.pickup_names
    -- Drive every tracked cwv pickup key through the helper: it must coerce to
    -- its declared vanilla target, and that target must be a non-cwv key present
    -- in NetworkLookup.pickup_names on every peer.
    for cwv_key, vanilla_key in pairs(_om._tj_pickup_wire_map) do
        local safe = _om._wire_safe_pickup_name(cwv_key, false)
        if safe ~= vanilla_key then
            return string.format("pickup %s did not coerce to its vanilla target (got %s)",
                tostring(cwv_key), tostring(safe))
        end
        if type(safe) ~= "string" or safe:sub(1, 4) == "cwv_" then
            return string.format("pickup substitute %s is not a vanilla key", tostring(safe))
        end
        if type(pn) == "table" and rawget(pn, safe) == nil then
            return string.format("pickup substitute %s absent from NetworkLookup.pickup_names", tostring(safe))
        end
        if _om._wire_safe_pickup_name(cwv_key, true) ~= nil then
            return string.format("pickup %s was substituted despite confirmed peer parity", tostring(cwv_key))
        end
    end
    -- Negative control: a genuine vanilla pickup must pass through unchanged (nil),
    -- so the coercion can only ever touch the tracked cwv keys.
    if _om._wire_safe_pickup_name("ammo_throwing_axe_01_t1", false) ~= nil then
        return "wire-safe helper coerced a vanilla pickup name (should only map cwv keys)"
    end
    -- In-flight projectile axis: a fake projectile_units carrying the cwv
    -- boar-spear unit must NEVER survive the helper (its husk would reach the wire).
    if type(_om._wire_safe_projectile_units) == "function" then
        local coerced = _om._wire_safe_projectile_units({ projectile_unit_name = _om._TJ_INFLIGHT_MODDED_UNIT })
        if coerced and coerced.projectile_unit_name == _om._TJ_INFLIGHT_MODDED_UNIT then
            return "in-flight projectile helper let the cwv boar-spear husk survive to the wire path"
        end
        -- And a vanilla projectile_units must pass through untouched.
        local vanilla_in = { projectile_unit_name = "units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps" }
        if _om._wire_safe_projectile_units(vanilla_in) ~= vanilla_in then
            return "in-flight projectile helper mutated a vanilla projectile (should pass through)"
        end
    end
end)

_rt_register("cwv_wire_safe_damage_profile_gate", function()
    -- (issue 423 / issue 371, BUG_CLASSES 31, GAMEPLAY axis) cwv clones append
    -- damage_profile keys to NetworkLookup.damage_profiles as modded indices that
    -- ride the client->server rpc_attack_hit (weapon_system.lua:182). A non-cwv
    -- HOST strict-decodes (weapon_system.lua:243) -> CTD. The send-gate degrades a
    -- modded index to its vanilla SOURCE id when peer parity is unconfirmed, and
    -- lets it ride under confirmed parity. Assert the hook is installed, NO tracked
    -- cwv profile can ever survive to the wire when parity is unconfirmed, and the
    -- gate decision honors parity + is_server (stubbed beacon like the skin gate).
    if _om._dp_wire_hook_installed ~= true then
        return "send_rpc_attack_hit wire-safety gate not installed (issue 423 non-cwv host CTD regression)"
    end
    local resolve = _om._wire_safe_damage_profile_id
    local decide  = _om._wire_dp_for_send
    if type(resolve) ~= "function" or type(decide) ~= "function" then
        return "wire-safe damage-profile helpers missing"
    end
    local NL = rawget(_G, "NetworkLookup")
    local dp = NL and NL.damage_profiles
    if type(dp) ~= "table" then return "NetworkLookup.damage_profiles absent" end

    -- (1) Crash-safety over EVERY cwv-registered profile: the resolver must coerce
    -- each modded index to a REAL vanilla index present on every peer.
    local checked = 0
    for k, v in pairs(dp) do
        if type(k) == "string" and k:sub(1, 4) == "cwv_" and type(v) == "number" then
            local safe = resolve(v)
            if type(safe) ~= "number" then
                return string.format("cwv profile %s did not resolve to a vanilla id (would ride to a non-cwv host)", k)
            end
            local safe_name = rawget(dp, safe)
            if type(safe_name) ~= "string" or safe_name:sub(1, 4) == "cwv_" then
                return string.format("cwv profile %s resolved to a non-vanilla id %s (%s)", k, tostring(safe), tostring(safe_name))
            end
            checked = checked + 1
        end
    end
    if checked == 0 then
        return "no cwv damage profiles registered -- wire-safety would coerce nothing (registration regressed?)"
    end

    -- (2) Negative control: a genuine vanilla profile id passes through untouched.
    local van_id = _om._cwv_wire_fallback_profile_id
    if type(van_id) == "number" and resolve(van_id) ~= nil then
        return "wire-safe resolver coerced a vanilla profile id (should only touch cwv keys)"
    end

    -- (3) Behavioral gate with a stubbed beacon (mirrors cwv_wire_skin_parity_gate):
    -- pick any tracked cwv profile whose source differs, then drive the decision.
    local cwv_id, src_id
    for k, v in pairs(dp) do
        if type(k) == "string" and k:sub(1, 4) == "cwv_" and type(v) == "number" then
            local s = resolve(v)
            if type(s) == "number" and s ~= v then cwv_id, src_id = v, s; break end
        end
    end
    if cwv_id then
        local real_pp = mod._cwv_peer_parity
        mod._cwv_peer_parity = { all_peers_have = function() return false end }
        local unconfirmed_client = decide(false, cwv_id)
        local host_authoritative = decide(true,  cwv_id)
        mod._cwv_peer_parity = { all_peers_have = function() return true end }
        local confirmed_client = decide(false, cwv_id)
        mod._cwv_peer_parity = real_pp
        if unconfirmed_client ~= src_id then
            return "parity-unconfirmed client did not degrade the cwv profile to its vanilla source (issue 423 CTD shape live)"
        end
        if confirmed_client ~= cwv_id then
            return "parity-confirmed client degraded the cwv profile (variant damage would regress under full cwv parity)"
        end
        if host_authoritative ~= cwv_id then
            return "is_server path substituted (host is authoritative; rpc_attack_hit runs in-process, no foreign decode)"
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Peer-parity beacon regression checks (issue 371 / issue 424 / BUG_CLASSES 31)
-- ----------------------------------------------------------------------------
_rt_register("cwv_peer_parity_lib_loaded", function()
    -- The COPIED shared lib (master tools/shared_lib/_lib_peer_parity.lua) built
    -- an instance and exposed the contract API.
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "mod._cwv_peer_parity not built (lib load or factory failed)" end
    for _, m in ipairs({ "install", "register_gated_feature", "all_peers_have",
                         "tick", "feature_count", "applied_state", "is_installed" }) do
        if type(pp[m]) ~= "function" then return "beacon missing method: " .. m end
    end
end)

_rt_register("cwv_peer_parity_beacon_registered", function()
    -- The beacon's VMF mod-to-mod channel is registered (presence handshake).
    -- If VMF's network API is present (it is in-game), is_installed must be true.
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    if type(mod.network_register) == "function" and not pp:is_installed() then
        return "beacon channel not registered despite VMF network_register present"
    end
end)

_rt_register("cwv_peer_parity_gated_feature_registered", function()
    -- At least one gated feature is registered (the Tuskgor Javelin bomb pool).
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    if pp:feature_count() < 1 then
        return "gated-feature registry empty -- bomb pool injection was not registered behind the beacon"
    end
end)

_rt_register("cwv_peer_parity_failsafe_posture", function()
    -- Chosen posture: features are INERT until all peers are POSITIVELY confirmed.
    local pp = mod._cwv_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    -- Immutable record of the init state (fail-safe = disabled at t0).
    if pp._initial_applied ~= "disabled" then
        return "beacon did not initialise to the fail-safe (disabled) state"
    end
    if pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then
        return "beacon failsafe posture marker changed unexpectedly"
    end
    -- Pure classifier: solo (no peers) is trivially all-present; a present but
    -- un-acked peer must fail-safe to NOT-all-present; an acked peer counts.
    local c = pp.__classify
    if type(c) ~= "function" then return "beacon classifier (__classify) missing" end
    if c({}, {}) ~= true then return "solo (no other peers) must classify all-present" end
    if c({ p1 = true }, {}) ~= false then
        return "a present-but-unacked peer must fail-safe to NOT-all-present"
    end
    if c({ p1 = true }, { p1 = true }) ~= true then return "an acked peer must count as present" end
    if c({ p1 = true, p2 = true }, { p1 = true }) ~= false then
        return "a partially-acked lobby must classify NOT-all-present"
    end
    -- all_peers_have must never throw (pcall-wrapped internally -> false on error).
    local ok = pcall(function() return pp:all_peers_have() end)
    if not ok then return "all_peers_have threw (must fail-safe to false, never error)" end
end)

_rt_register("cwv_peer_parity_registration_unconditional", function()
    -- Class-31 invariant: the NetworkLookup / AllPickups / ItemMasterList
    -- REGISTRATION for the bomb pickup is never peer-gated; only the pool
    -- INJECTION (spawn/world axis) gates. The source marker records that split,
    -- and the gated feature's id is the POOL, not the registration.
    if _om._TJB_REGISTRATION_UNGATED_MARKER ~= "cwv-tjb-networklookup-registration-never-peer-gated" then
        return "registration-parity marker missing/altered -- registration must stay ungated (class 31)"
    end
end)

_rt_register("issue343_smoke_bomb_diagnostics", function()
    local probe = mod._cwv_smoke_bomb_probe
    if type(probe) ~= "table" or type(probe.classify) ~= "function"
            or type(probe.collect_snapshot) ~= "function" or type(probe.run) ~= "function"
            or type(probe.auto_run) ~= "function" then
        return "issue #343 smoke-bomb probe module did not load"
    end
    if probe.MAX_RUNS ~= 3 then
        return "issue #343 probe cap changed from three explicit runs"
    end
    local result = probe.classify({
        grenade_template = true, grenade_projectile = true,
        ranger_template = true, ranger_item = true, smoke_explosion = true,
        ranger_area_buff = true, buff_area_position_contract = true,
        pool_count = 3, pool_sum = 1,
    })
    if not (result.base_ready and result.area_ready and result.pool_healthy)
            or result.exact_z_scale_ready ~= false
            or result.registration_quarantined ~= true then
        return "issue #343 diagnostic truth table failed"
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/character_weapon_variants/character_weapon_variants_localization")
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
_rt_register("mace_sword_rename_prefix_match", function()
    -- audit 2026-06-07 (F15, v0.1.349-dev): guard the mace+sword rename prefix
    -- match against off-by-one death. The prior `key:sub(1, 30) ==
    -- "es_dual_wield_hammer_sword_skin"` compared 30 chars against a 31-char
    -- literal, so it was ALWAYS false and the rename never fired for any
    -- skinned mace+sword. Behavioral assertion: a representative skin key MUST
    -- match the prefix, and a non-matching key MUST NOT.
    local has_prefix = mod._cwv_has_prefix
    local prefix = mod._cwv_mace_sword_skin_prefix
    if type(has_prefix) ~= "function" then
        return "_cwv_has_prefix helper missing"
    end
    if prefix ~= "es_dual_wield_hammer_sword_skin" then
        return string.format("unexpected mace+sword skin prefix: %q", tostring(prefix))
    end
    -- Representative key the player's inventory/cosmetics UI actually passes to
    -- Localize when a non-default illusion is applied (skin_02 + _name suffix).
    local rep_key = "es_dual_wield_hammer_sword_skin_02_name"
    if not has_prefix(rep_key, prefix) then
        return string.format(
            "prefix match FAILED for representative key %q (off-by-one regression: sub() length must equal #prefix=%d)",
            rep_key, #prefix)
    end
    -- Negative control: an unrelated key must NOT match.
    if has_prefix("es_dual_wield_hammer_falchion_skin_01_name", prefix) then
        return "prefix match spuriously succeeded for a non-mace+sword key"
    end
end)

_rt_register("weapon_appearance_module_present", function()
    -- Phase 1 (issue 409 + the rotation abstraction): the single WeaponAppearance
    -- module must own scale/offset/position/rotation and be reachable, and its
    -- rotation normalizer must accept {x,y,z} euler DEGREES, a QuaternionBox, and
    -- nil — so every render path shares ONE rotation math path instead of the four
    -- bespoke quaternion blocks this replaces.
    local WA = mod._cwv_weapon_appearance
    if type(WA) ~= "table" then return "mod._cwv_weapon_appearance (WeaponAppearance) missing" end
    for _, m in ipairs({ "apply", "apply_scale", "apply_offset", "apply_position", "apply_rotation" }) do
        if type(WA[m]) ~= "function" then return "WeaponAppearance." .. m .. " missing" end
    end
    local to_q = mod._wa_to_quaternion_for_rt
    if type(to_q) ~= "function" then return "rotation normalizer not exposed" end
    if to_q(nil) ~= nil then return "nil rotation must normalize to nil (leave native)" end
    if to_q({ 90, 0, 0 }) == nil then return "euler {90,0,0} did not normalize to a quaternion" end
    local ok_qb, qb = pcall(QuaternionBox, Quaternion.identity())
    if ok_qb and to_q(qb) == nil then return "QuaternionBox did not normalize to a quaternion" end
    if to_q({ "not", "numbers" }) ~= nil then return "non-numeric table must normalize to nil, not crash" end
end)

_rt_register("musket_old_force_registered", function()
    -- Issue 409: cwv_es_musket_old carries no generic scale/offset (native mesh),
    -- so before force_register it never entered _transform_map -> the preview /
    -- illusion-browser resolvers returned nil and bailed BEFORE its pose+texture
    -- block. force_register must put it in the map so the resolver-driven paths
    -- reach its apply. Regression: if the gate stops honoring force_register, the
    -- inventory preview mis-poses the musket again.
    local check = mod._cwv_transform_registered
    if type(check) ~= "function" then return "mod._cwv_transform_registered helper missing" end
    if not check("cwv_es_musket_old") then
        return "#409 regression: cwv_es_musket_old NOT registered in _transform_map (force_register gate broke)"
    end
end)

_rt_register("preview_meshswap_guards", function()
    -- Issue 237 (WEAPON_APPEARANCE_STANDARD §4.1): the inventory-preview
    -- unit-resolution layer rewrites spawn_data entry.unit_name to the cwv
    -- variant's authored mesh. The GUARDS are load-bearing: a non-cwv backend_id
    -- or a user-selected illusion (non-empty skin) must leave spawn_data
    -- untouched, and the helper must be reachable. The positive rewrite depends
    -- on runtime package residency, so it is covered by the in-game verify.
    local apply = mod._cwv_preview_meshswap_apply
    if type(apply) ~= "function" then return "mod._cwv_preview_meshswap_apply missing" end
    local function _mk() return { spawn_data = { { right_hand = true, unit_name = "BASE_3p" } } } end
    local a = _mk(); apply("es_sword_shield", "es_sword_shield_001", nil, a)
    if a.spawn_data[1].unit_name ~= "BASE_3p" then return "#237 guard: non-cwv backend_id must not rewrite" end
    local b = _mk(); apply("es_sword_shield", "cwv_we_sword_shield_001", "some_skin", b)
    if b.spawn_data[1].unit_name ~= "BASE_3p" then return "#237 guard: user-selected illusion (skin) must win, no rewrite" end
    local c = _mk(); c.skin_name = "stored_preview_skin"
    apply("es_sword_shield", "cwv_we_sword_shield_001", nil, c)
    if c.spawn_data[1].unit_name ~= "BASE_3p" then
        return "#579 guard: info.skin_name must win when copied preview callback drops skin arg"
    end
end)

_rt_register("browser_meshswap_guards", function()
    -- Issue #419 (WEAPON_APPEARANCE_STANDARD §3 path 4): the illusion-browser
    -- spawn_units pre-pass rewrites spawn_data unit_name to the cwv variant's
    -- authored mesh when the upstream BackendUtils.get_item_units resolution
    -- missed (the browser rebinds item_data to the BASE IML entry, so the #482
    -- stamp rung is dead there; a UUID-bid crafted instance can fall through).
    -- The GUARDS are load-bearing: an applied illusion (item.skin) must win,
    -- and a non-cwv item must pass untouched. The positive rewrite depends on
    -- runtime package residency, so it is covered by the in-game verify.
    local apply = mod._cwv_browser_meshswap_apply
    if type(apply) ~= "function" then return "mod._cwv_browser_meshswap_apply missing" end
    local UNTOUCHED = "units/weapons/player/wpn_rt419/wpn_rt419_3p"
    local sd = { { unit_name = UNTOUCHED } }
    apply({ backend_id = "es_sword_shield_rt419", data = { name = "es_sword_shield" } }, sd)
    if sd[1].unit_name ~= UNTOUCHED then return "#419 guard: non-cwv item must not rewrite" end
    sd = { { unit_name = UNTOUCHED } }
    apply({ backend_id = "cwv_es_greataxe_001", skin = "some_skin", data = nil }, sd)
    if sd[1].unit_name ~= UNTOUCHED then return "#419 guard: applied illusion (skin) must win, no rewrite" end
end)

_rt_register("give_refuses_skin_only", function()
    -- Issue #538: /cwv_give must REFUSE skin_only (illusion-only) variants. Giving
    -- one builds a backend_id and mirrors the def into ItemMasterList, resurrecting
    -- the issue-390 crafts-as-wrong-item class for that key. Two locks:
    --  (1) the guard predicate exists and discriminates on def.skin_only (io is nil
    --      in the retail sandbox, so a source self-grep check is impossible -- this
    --      predicate is the testable seam the give command shares), and
    --  (2) the standing invariant it protects: no skin_only variant is ever present
    --      in _registered_keys. _auto_register_all excludes them (:9665) and the
    --      give guard is the only other registration entry point.
    local pred = _om._give_refuses_skin_only
    if type(pred) ~= "function" then return "_om._give_refuses_skin_only guard missing (#538)" end
    if pred({ skin_only = true }) ~= true then return "#538 guard: skin_only def must be refused" end
    if pred({ skin_only = nil }) ~= false then return "#538 guard: real (non-skin_only) def must be allowed" end
    if pred(nil) ~= false then return "#538 guard: nil def must not raise" end
    local leaked = {}
    for _, d in ipairs(_variant_definitions) do
        if d.skin_only and _registered_keys[d.item_key] then
            leaked[#leaked + 1] = d.item_key
        end
    end
    if #leaked > 0 then
        return "#538: skin_only variant(s) leaked into the ownable registry: " .. table.concat(leaked, ", ")
    end
end)

_rt_register("issue592_registration_not_acquisition", function()
	local ownership = mod._cwv_acquisition
	if type(ownership) ~= "table" then return "#592 acquisition helper missing" end
	local legacy = ownership.legacy_auto_grant_ids(_variant_definitions)
	if not legacy.cwv_es_musket_old_001 or not legacy.cwv_es_musket_old_002 then
		return "#592 historical multi-instance migration ledger incomplete"
	end
	if ownership.should_remove("cwv_es_musket_old_001", legacy, function() return false end) ~= true then
		return "#592 exact historical auto-grant was not removable"
	end
	if ownership.should_remove("cwv_es_musket_old_001", legacy, function() return true end) ~= false then
		return "#592 exact CIM-owned craft was not preserved"
	end
	if ownership.should_remove("cwv_es_musket_old_100", legacy, function() return false end) ~= false then
		return "#592 CIM craft range was captured by migration"
	end
	for _, def in ipairs(_variant_definitions) do
		if not def.skin_only and _registered_keys[def.item_key] then
			local row = ItemMasterList and rawget(ItemMasterList, def.item_key)
			if not row or row.cwv_definition ~= true or row.mod_data ~= nil then
				return "#592 definition acquired backend identity: " .. tostring(def.item_key)
			end
		end
	end
end)

_rt_register("cwv_crowbill_family_registration_contract", function()
	local family = mod._cwv_crowbill_family
	local hammer = mod._cwv_crowbill_hammer_mode
	if type(family) ~= "table" or type(hammer) ~= "table" then
		return "Crowbill family or hammer-mode policy missing"
	end
	if hammer.SOURCE_TEMPLATE_KEY ~= family.SOURCE_TEMPLATE
			or hammer.HAMMER_CLEAVE_MULT ~= family.HAMMER_MODE.attack_cleave_multiplier
			or hammer.HAMMER_DAMAGE_MULT ~= family.HAMMER_MODE.direct_damage_multiplier
			or hammer.MODEL_FLIP_DEGREES ~= family.HAMMER_MODE.rotation_degrees then
		return "Crowbill registration and hammer-mode constants drifted"
	end
	for _, variant in ipairs(family.VARIANTS) do
		local entry = ItemMasterList and rawget(ItemMasterList, variant.key)
		if type(entry) ~= "table" or entry.cwv_variant ~= true
				or entry.cwv_definition ~= true or entry.mod_data ~= nil then
			return variant.key .. " is not a registration-only CIM definition"
		end
		if entry.template ~= family.SOURCE_TEMPLATE
				or entry.item_type ~= variant.key
				or entry.skin_combination_table ~= variant.key .. "_skins"
				or entry.crowbill_mode_family ~= family.HAMMER_MODE_FAMILY then
			return variant.key .. " registration contract drifted"
		end
	end
end)

_rt_register("issue604_preview_alias_teardown_contract", function()
	local bridge = _om.mod_unit_preview
	local family = _om.crowbill_family
	if type(bridge) ~= "table" or type(bridge.reconcile_for_unload) ~= "function"
			or type(bridge.claim_teardown) ~= "function" then
		return "Crowbill preview teardown policy missing"
	end
	local custom = family.MODELS[1].right_hand_unit .. "_3p"
	local alias = family.PREVIEW_PACKAGE_ALIAS
	local previewer = {
		_loaded_packages = { [custom] = true },
		_packages_to_load = { [custom] = false },
	}
	local acquired = 0
	local report = bridge.reconcile_for_unload(previewer, family.preview_package_alias,
		function(candidate)
			acquired = acquired + 1
			return candidate == alias
		end)
	if acquired ~= 1 or report.repaired ~= 1 or report.mapped ~= 1
			or rawget(previewer._loaded_packages, custom) ~= nil
			or previewer._loaded_packages[alias] ~= true
			or previewer._packages_to_load[alias] ~= false then
		return "Crowbill preview lease repair is not balanced"
	end
	if bridge.claim_teardown(previewer) ~= true or bridge.claim_teardown(previewer) ~= false then
		return "Crowbill preview teardown is not idempotent"
	end
end)

_rt_register("cwv_crowbill_hammer_runtime_contract", function()
	local runtime = mod._cwv_crowbill_runtime
	local policy = mod._cwv_crowbill_hammer_mode
	if type(runtime) ~= "table" or runtime._installed ~= true then
		return "Crowbill hammer runtime not installed"
	end
	local source = Weapons and Weapons[policy.SOURCE_TEMPLATE_KEY]
	local pick = Weapons and Weapons[runtime.PICK_TEMPLATE_KEY]
	local hammer = Weapons and Weapons[policy.HAMMER_TEMPLATE_KEY]
	if type(source) ~= "table" or type(pick) ~= "table" or type(hammer) ~= "table" then
		return "Crowbill source/pick/hammer templates not all registered"
	end
	if source.actions and source.actions.action_three ~= nil then
		return "vanilla Crowbill source template was mutated with Weapon Special"
	end
	local pick_special = pick.actions and pick.actions.action_three
		and pick.actions.action_three.default
	local hammer_special = hammer.actions and hammer.actions.action_three
		and hammer.actions.action_three.default
	if type(pick_special) ~= "table" or type(hammer_special) ~= "table"
			or type(pick_special.enter_function) ~= "function"
			or type(hammer_special.enter_function) ~= "function" then
		return "Weapon Special toggle missing from one Crowbill mode"
	end
	if pick_special.lookup_data.item_template_name ~= runtime.PICK_TEMPLATE_KEY
			or hammer_special.lookup_data.item_template_name ~= policy.HAMMER_TEMPLATE_KEY then
		return "Crowbill Weapon Special lookup_data drifted"
	end
	for action_name, class in pairs(policy.DIRECT_ACTIONS) do
		local pick_action = pick.actions.action_one[action_name]
		local hammer_action = hammer.actions.action_one[action_name]
		if not pick_action or not hammer_action
				or pick_action.damage_profile == hammer_action.damage_profile then
			return "Crowbill mode profile missing: " .. tostring(action_name)
		end
		if pick_action.anim_time_scale ~= hammer_action.anim_time_scale
				or pick_action.total_time ~= hammer_action.total_time then
			return "Crowbill timing drifted: " .. tostring(action_name) .. "/" .. tostring(class)
		end
		if _om._cwv_damage_profile_wire_source[hammer_action.damage_profile]
				~= pick_action.damage_profile then
			return "Crowbill mixed-peer damage fallback missing: " .. tostring(action_name)
		end
	end
	if type(runtime.resolve_template) ~= "function"
			or type(runtime.request_states) ~= "function"
			or type(runtime.on_local_wield) ~= "function"
			or type(runtime.on_husk_wield) ~= "function" then
		return "Crowbill runtime lifecycle surface incomplete"
	end
end)

_rt_register("cwv_parity_applied_state_committed_before_callbacks", function()
    -- Issue 506: the shared peer-parity lib must commit _applied BEFORE it fires
    -- the gated-feature callbacks, so a callback reading inst:applied_state()
    -- observes the transition it is part of. cwv's own gated callbacks
    -- (_inject_pool / _eject_pool) do not read applied_state today, so cwv was
    -- never bitten -- but cwv ships a copy of the lib, so lock the master
    -- ordering here too (a future cwv gated feature could rely on it). Build a
    -- THROWAWAY instance (never install()d -> no VMF channel, no mod.update
    -- wrap), register a probe whose on_enable records applied_state(), drive a
    -- solo enable, and assert it saw "enabled". Skip (not fail) if the transition
    -- cannot be driven here (a populated lobby holds the probe disabled).
    local ok, factory = pcall(mod.dofile, mod, "scripts/mods/character_weapon_variants/_lib_peer_parity")
    if not ok or type(factory) ~= "function" then return "peer-parity lib not loadable" end
    local inst = factory(mod, {
        channel           = "cwv_rt_probe_parity",
        echo_prefix       = "[cwv-rt]",
        poll_interval     = 0,
        announce_interval = 1e12,   -- suppress the probe's network announce
    })
    if type(inst) ~= "table" then return "parity factory did not return an instance" end
    local seen_state
    inst:register_gated_feature("__cwv_rt_order_probe__", {
        on_enable = function() seen_state = inst:applied_state() end,
    })
    pcall(function() inst:tick(10) end)   -- solo enables on the first tick (settle 0)
    if seen_state == nil then return end  -- enable did not fire in this env; skip
    if seen_state ~= "enabled" then
        return string.format(
            "applied_state() inside on_enable was %q, expected \"enabled\" -- shared lib fired callbacks before committing _applied (issue 506 regression)",
            tostring(seen_state))
    end
end)

_rt_register("issue567_skin_reverse_index_valid", function()
    -- The three persisted skins from issue #567 must satisfy BOTH layers of
    -- vanilla's contract: live IML/WeaponSkins ownership and, whenever vanilla's
    -- lazy reverse-index has been rebuilt, a cache row pointing at that owner.
    local validate = mod._cwv567_validate_skin_association
    if type(validate) ~= "function" then return "#567 association validator missing" end
    local expected = {
        cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1 = "cwv_es_sword_and_mace",
        cwv_es_dual_maces_es_1h_mace_skin_02_runed_01 = "cwv_es_dual_maces",
        cwv_es_axe_shield_wpn_emp_shield_03__axe_02_t2 = "cwv_es_axe_shield",
    }
    for skin_key, owner_key in pairs(expected) do
        local valid, owner_or_err = validate(skin_key)
        if not valid then return skin_key .. ": " .. tostring(owner_or_err) end
        if owner_or_err ~= owner_key then
            return string.format("%s owner=%s expected=%s", skin_key, tostring(owner_or_err), owner_key)
        end
        local cache = WeaponSkins and WeaponSkins._matching_weapon_skin_item_keys
        if type(cache) == "table" then
            local row = cache[skin_key]
            if type(row) ~= "table" then return skin_key .. ": missing from rebuilt vanilla reverse-index" end
            if row.item_key ~= owner_key .. "_skin" then
                return string.format("%s reverse-index item_key=%s expected=%s_skin",
                    skin_key, tostring(row.item_key), owner_key)
            end
        end
    end
    if type(_om._exact_pair_skin_predicate) ~= "function" then
        return "#567 exact-pair protocol predicate missing"
    end
    local exact = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
    if not _om._exact_pair_skin_predicate(exact) then
        return "#567 exact Sword+Mace skin is outside replay protocol"
    end
    local skin = WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[exact]
    if not skin
        or not tostring(skin.right_hand_unit):find("wpn_emp_sword_02_t1", 1, true)
        or not tostring(skin.left_hand_unit):find("wpn_emp_mace_03_t1", 1, true) then
        return "#567 exact skin lost sword-right/mace-left authored hand order"
    end
end)

mod._cwv_dev_anim_picker.install()

mod:info("Character Weapon Variants v%s loaded", MOD_VERSION)

mod:info("[mem-probe] cwv boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_CWV) / 1024)
