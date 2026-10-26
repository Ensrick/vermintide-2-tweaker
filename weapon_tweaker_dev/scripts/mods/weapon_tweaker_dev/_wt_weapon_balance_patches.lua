-- Toggle-gated weapon rebalance owner (#1159).
--
-- Extracted verbatim from the entry: the Authentic Brace of Pistols override,
-- the issue #348 Kruber Empire one-handed sword push-combo revert, and the
-- Warrior Priest greathammer punch buff. Each rewrites a vanilla Weapons.*
-- template in place at load behind its own VMF checkbox, and two of them
-- register a cloned damage profile.
--
-- The entry keeps a bare dofile at the former execution position, and that
-- position is load-bearing: wt_authentic_pistol and wt_priest_punch_buffed
-- append to NetworkLookup.damage_profiles, so their append ORDER (after
-- _wt_brett_sword_shield_buff's clone, before the axe-balance clones near the
-- end of the entry) is the process-local index every wt peer must agree on.
-- Moving the dofile would renumber the wire - BUG_CLASSES 64.
--
-- Both clones stay registered even with their toggle OFF (PROJECT_STANDARDS
-- 9.3 gated-registration divergence) and record a wire-safe vanilla fallback
-- for the issue-431 send floor; only the template repoint is toggle-gated.
-- The Priest punch tail now commits its profile/lookup/fallback atomically
-- through _wt_priest_punch_owner at the same registration position (#428).
-- Offline evidence: qa/lua/tests/test_wt_template_patch_owners.lua.

local mod = get_mod("wt_dev")

-- Late-binding accessor: the entry's file-scope _dbg does not cross the chunk
-- boundary; mod._wt.dbg is the same function it published far above this
-- module's load position.
local _dbg = mod._wt.dbg

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
--      flattened AND the existing cleave_distribution values retained
--      at 0.15 (half the native 0.3). Plus `ignore_shield_hit = true` on the
--      sub-action, which is what lets the handgun ignore shields.
--      Combined effect: armor-piercing, shield-breaking, full damage at
--      all ranges; this registration migration changes no cleave balance.
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

local _wt428_pistol, _wt428_pistol_validate
local function _wt_clone_shot_sniper_no_dropoff()
    if type(_wt428_pistol) ~= "table" or type(_wt428_pistol_validate) ~= "function"
        or rawget(mod, "_wt428_authentic_pistol_owner") ~= _wt428_pistol
        or rawget(_wt428_pistol, "validate") ~= _wt428_pistol_validate then return nil end
    local ok, valid = pcall(_wt428_pistol_validate)
    if ok and valid == true then
        return "wt_authentic_pistol"
    end
end

-- issue 431: parity-gated repoint for the authentic-brace damage profile.
-- _apply_authentic_brace_mode snapshots each firing sub-action's vanilla
-- damage_profile into mod._wt431_brace_profile_slots (once, at apply time);
-- this function (re)points them at wt_authentic_pistol only while every other
-- human peer is confirmed to run wt, and restores the vanilla keys the moment
-- one is not (a non-wt peer would fatal decoding our appended NetworkLookup
-- index off rpc_attack_hit -- BUG_CLASSES 31). No-op until the mode has been
-- applied (slots empty). Called from _apply_authentic_brace_mode and from the
-- issue-431 peer-parity callbacks (_wt431_damage_profile_parity.lua). The rest
-- of the authentic-brace mode (ammo/spread/speed) never rides a lookup index,
-- so it stays applied regardless of parity.
-- The retained transaction owner publishes this callback at registration below.

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
        -- issue 431: snapshot the vanilla damage_profile keys ONCE, then route
        -- the repoint through mod._wt431_brace_repoint so the peer-parity gate
        -- can revert/re-apply it live. The snapshot guard keeps a hypothetical
        -- second apply from capturing our own custom key as "original".
        mod._wt431_brace_profile_slots = mod._wt431_brace_profile_slots or {}
        local slots = mod._wt431_brace_profile_slots
        local first_apply = (#slots == 0)
        for _, sub_name in ipairs({ "default", "fast_shot", "special_action_shoot" }) do
            local sub = tpl.actions.action_one[sub_name]
            if sub then
                if sub.impact_data and first_apply then
                    slots[#slots + 1] = {
                        impact_data = sub.impact_data,
                        original    = sub.impact_data.damage_profile,
                        custom      = damage_profile_key,
                    }
                end
                sub.ignore_shield_hit = true
            end
        end
        mod._wt431_brace_repoint()
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
_wt428_pistol = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_authentic_pistol_owner").install(mod)
_wt428_pistol_validate = type(_wt428_pistol) == "table" and rawget(_wt428_pistol, "validate")
if not _wt428_pistol then
    -- Ungated (mod:warning): if the profile can't register at load (tables not
    -- ready), a networked brace shot would desync / crash on the other peer when
    -- the toggle is on. Surface it without requiring Debug Logging.
    mod:warning("[wt:authentic-brace] wt_authentic_pistol damage-profile registration failed at load (DamageProfileTemplates/NetworkLookup not ready)")
end
if mod:get("authentic_brace_of_pistols") then
    _apply_authentic_brace_mode()
end

-- ============================================================
-- Issue #348 -- revert Patch 6.11.0 Kruber 1h sword push-attack combo
-- ============================================================
-- Game v6.11.0 (Vermintide-2-Source-Code @abe82ab4, 2026-05-18) reworked
-- Kruber's Empire one-handed sword (`Weapons.one_handed_swords_template_1`).
-- The relevant change: the push-attack (`light_attack_bopp`) combo continuation
-- was repointed from `default` (-> first light `light_attack_left`, a horizontal
-- sweep, good for hordes) to `default_left` (-> third light `light_attack_last`,
-- the single-target overhead). The user finds the overhead-terminated combo worse
-- for horde work and wants the pre-6.11.0 chain back.
--
-- The revert below restores the EXACT v6.10.0 `light_attack_bopp.allowed_chain_actions`
-- table, verified verbatim from the decompile at commit 5ff26df1
-- (`git diff 5ff26df1 abe82ab4 -- .../1h_swords.lua`). Only the push-attack chain
-- is reverted; 6.11.0's other, unrelated changes to this sword (dodge_count 3->6,
-- the third light's damage_profile, movement multipliers) are deliberately LEFT as
-- current -- the issue is only about the combo routing.
--
-- Wire-safe by construction: this only re-routes `sub_action` between vanilla
-- action names (`default`, `default_left`, `light_attack_*`) that exist in the
-- base template on every peer. No NetworkLookup key is added and no damage profile
-- is repointed, so a peer without the mod cannot diverge or crash (PROJECT_STANDARDS
-- §9.3; same wire class as the ungated Big Rebalance chain edits). No peer-parity
-- gate needed. Scope note: only Kruber's Empire sword changed in 6.11.0 -- Sienna's
-- flaming sword (`flaming_sword_template_1`, `1h_swords_wizard.lua`) was NOT touched,
-- so there is nothing to revert on her side.
--
-- Applied once at init when the toggle is on (mirrors `authentic_brace_of_pistols`);
-- toggling requires a restart, which the option description states. Mutates the
-- shared template global in place -- intended, since the chain is a property of the
-- weapon and should revert for every career that wields it.
local function _patch_kruber_1h_sword_push_combo_revert()
    if not Weapons or not Weapons.one_handed_swords_template_1 then
        pcall(printf, "[wt:348] skip: Weapons.one_handed_swords_template_1 missing (revert not applied)")
        return
    end
    local ao = Weapons.one_handed_swords_template_1.actions
        and Weapons.one_handed_swords_template_1.actions.action_one
    local bopp = ao and ao.light_attack_bopp
    if not (bopp and bopp.allowed_chain_actions) then
        pcall(printf, "[wt:348] skip: light_attack_bopp chain missing on one_handed_swords_template_1")
        return
    end
    -- Pre-6.11.0 (v6.10.0 @5ff26df1) light_attack_bopp.allowed_chain_actions, verbatim.
    bopp.allowed_chain_actions = {
        { action = "action_one",   end_time = 1.2, input = "action_one",      release_required = "action_two_hold", start_time = 0.55, sub_action = "default" },
        { action = "action_one",   end_time = 1.2, input = "action_one_hold", release_required = "action_two_hold", start_time = 0.55, sub_action = "default" },
        { action = "action_one",                   input = "action_one",                                            start_time = 0.85, sub_action = "default" },
        { action = "action_two",                   input = "action_two_hold",                                       start_time = 0.55, sub_action = "default" },
        { action = "action_wield",                 input = "action_wield",                                          start_time = 0.5,  sub_action = "default" },
    }
    pcall(printf, "[wt:348] reverted Kruber Empire 1h sword push-attack combo to pre-6.11.0 (light_attack_bopp -> default first-light sweep)")
    _dbg("[wt:tpl_patch] event=applied template=one_handed_swords_template_1 feature=revert_push_combo issue=348")
end

if mod:get("wt_revert_1h_sword_push_combo") then
    _patch_kruber_1h_sword_push_combo_revert()
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
    local owner, reason = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_priest_punch_owner").install(mod)
    if not owner then
        pcall(printf, "[wt:428] priest-punch transaction rejected (%s); owned registration/repoint not installed", tostring(reason))
    end
end
-- Private entry-to-check dependency: retain the already-installed verifier.
return _wt_clone_shot_sniper_no_dropoff
