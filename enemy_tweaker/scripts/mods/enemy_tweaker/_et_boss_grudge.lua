local mod = get_mod("enemy_tweaker")

-- _et_boss_grudge.lua — GitHub issue 531 "boss balance: behavioral knobs need
-- runtime hooks" — FIRST tranche only: the grudge-mark wiring.
--
-- Two default-OFF toggles reuse the Chaos Wastes grudge-mark buff templates
-- (scripts/settings/grudge_mark_settings.lua:84-111) and apply them host-side to
-- the matching Adventure lord boss at spawn, gated to Cataclysm+:
--   Skarrik (skaven_storm_vermin_warlord)  -> Berserk   = "frenzy"   grudge mark
--                                             = buff  grudge_mark_frenzy
--   Bodvarr (chaos_exalted_champion)        -> Crippling = "crippling" grudge mark
--                                             = buff  grudge_mark_crippling_blow
--
-- These are the two behavioral knobs from issue 450 that could not ship in the
-- pure-data _et_boss_balance.lua module (which registers NO hook). This module
-- owns the single runtime hook the knobs need; the health/armor data knobs stay
-- in _et_boss_balance.lua. Kept separate so that module's "no mod:hook" contract
-- is preserved (DEVELOPMENT.md module map: a new subsystem gets a new module).
--
-- ----------------------------------------------------------------------------
-- Application path (verified against the decompile):
--   ConflictDirector._post_spawn_unit (conflict_director.lua:2029) is the
--   spawn-complete seam every AI spawn funnels through (both spawn paths call it:
--   the queued path at :1865 and the direct _spawn_unit at :2024). Vanilla itself
--   applies CW grudge-mark buffs HERE, at :2041, when optional_data.enhancements
--   is set: TerrorEventUtils.apply_breed_enhancements(ai_unit, breed, optional_data)
--   (terror_event_utils.lua:80). That function (line 90-104) walks the enhancement's
--   buff-template list and calls
--       buff_system:add_buff(unit, buff_name, unit, true)
--   for each. We reproduce exactly that call for the ONE grudge-mark buff template
--   this boss should carry, but only in Adventure (never CW) and only Cataclysm+.
--   Because vanilla runs the identical add_buff at this same seam, the unit's
--   buff extension is proven ready here (and BuffSystem.add_buff self-guards on
--   ScriptUnit.has_extension(unit, "buff_system") at buff_system.lua:278 anyway).
--
-- Client sync (wire safety):
--   BuffSystem.add_buff(self, unit, template_name, attacker, is_server_controlled)
--   (buff_system.lua:277) applies the buff on the server, then broadcasts
--       network_transmit:send_rpc_clients("rpc_add_buff", unit_object_id,
--           NetworkLookup.buff_templates[template_name], attacker_id, server_buff_id, false)
--   (buff_system.lua:302-305). grudge_mark_frenzy / grudge_mark_crippling_blow are
--   VANILLA templates in the base BuffTemplates table, so their NetworkLookup id is
--   the SAME on every peer (NetworkLookup.buff_templates = create_lookup({"n/a"},
--   BuffTemplates), network_lookup.lua:1144). The wire carries a vanilla template
--   id — NO modded key — and non-modded clients apply it normally. We apply ONLY on
--   the server (is_server gate), matching vanilla's server-authoritative model and
--   never tripping the client fassert at buff_system.lua:282.
--
-- Double-apply guards (a CW grudge boss already has marks):
--   1. game_mode_key() == "adventure" — Chaos Wastes is "deus"
--      (game_mode_settings_morris.lua:4), so CW is excluded outright. This is the
--      primary gate the issue asks for.
--   2. optional_data.enhancements == nil — never touch a unit any enhancement
--      path (vanilla grudge marks, a future modded path) is already marking.
--   3. buff_ext:has_buff_type(cfg.buff) == false — the buff is not already on the
--      unit (has_buff_type matches the sub-buff name, buff_extension.lua:1219;
--      both templates' sole sub-buff is named identically to the template).
--
-- DLC gate: none needed. The grudge-mark buff system ships with the free Chaos
-- Wastes (Morris) content that every player owns, and we surface no item to the
-- player — we apply an existing engine buff to an existing boss host-side.
--
-- Host authority: bosses are host-spawned and the buff is server-controlled, so a
-- host-only apply is fully consistent for every player once synced. If a non-host
-- runs the mod its toggle is inert (the is_server gate bails); only the host's
-- setting decides. Documented in the tooltips.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after _et_boss_balance).

local ET = mod._et
local _safe       = ET.safe
local _et_probe   = ET.et_probe
local rt_register = ET.rt_register

-- Cataclysm is difficulty rank 6 (difficulty_settings.lua:186); cataclysm_2 = 7,
-- cataclysm_3 = 8. "Cataclysm+" is therefore rank >= 6. The regression check
-- below asserts this constant still matches DifficultySettings.cataclysm.rank so a
-- vanilla renumber surfaces instead of silently disarming the gate.
local CATACLYSM_RANK = 6

-- Per-boss grudge-mark config. buff = the vanilla grudge-mark buff TEMPLATE name
-- (grudge_mark_settings.lua enhancement -> its buff template); mark = the display
-- name of the grudge mark for the probe/tooltip.
local GRUDGE = {
    {
        setting = "boss_grudge_skarrik_berserk",
        breed   = "skaven_storm_vermin_warlord",
        buff    = "grudge_mark_frenzy",
        mark    = "Berserk",
        label   = "Skarrik",
    },
    {
        setting = "boss_grudge_bodvarr_crippling",
        breed   = "chaos_exalted_champion",
        buff    = "grudge_mark_crippling_blow",
        mark    = "Crippling",
        label   = "Bodvarr",
    },
}

-- breed name -> config, for an O(1) early-out in the hot spawn hook.
local _BY_BREED = {}
for i = 1, #GRUDGE do
    _BY_BREED[GRUDGE[i].breed] = GRUDGE[i]
end

-- Apply the boss's grudge-mark buff if every gate passes. Runs under _safe so a
-- fault here can never disturb the spawn (the hook is a post-callback; vanilla
-- has already finished spawning the unit).
local function _maybe_apply_grudge(ai_unit, optional_data, cfg)
    if not mod:get(cfg.setting) then return end

    -- Host authority: only the server may add a server-controlled buff
    -- (buff_system.lua:282 fasserts otherwise). Clients receive it via rpc_add_buff.
    local network = Managers.state and Managers.state.network
    if not (network and network.is_server) then return end

    -- Adventure only. Excludes Chaos Wastes ("deus"), Weave, Versus - and is the
    -- primary CW double-apply guard (a CW grudge boss already carries its marks).
    local game_mode = Managers.state and Managers.state.game_mode
    if not game_mode or game_mode:game_mode_key() ~= "adventure" then return end

    -- Difficulty gate: Cataclysm+ (rank >= 6).
    local difficulty = Managers.state and Managers.state.difficulty
    local rank = difficulty and difficulty:get_difficulty_rank()
    if type(rank) ~= "number" or rank < CATACLYSM_RANK then return end

    -- Never touch a unit an enhancement path is already marking.
    if optional_data and optional_data.enhancements then return end

    -- Readiness + double-apply guard: buff extension present and buff not already on.
    local buff_ext = ScriptUnit.has_extension(ai_unit, "buff_system")
    if not buff_ext then return end
    if buff_ext:has_buff_type(cfg.buff) then return end

    -- Apply host-side via the vanilla buff system exactly as
    -- TerrorEventUtils.apply_breed_enhancements does (server-controlled -> syncs to
    -- clients via rpc_add_buff carrying the vanilla NetworkLookup buff id).
    local buff_system = Managers.state.entity:system("buff_system")
    buff_system:add_buff(ai_unit, cfg.buff, ai_unit, true)

    _et_probe("boss_grudge_" .. cfg.label, "[et:450] %s grudge mark applied to %s (%s, difficulty rank %d)",
        cfg.mark, cfg.label, cfg.buff, rank)
end

-- ----------------------------------------------------------------------------
-- Single hook on ConflictDirector._post_spawn_unit. Grep-verified: enemy_tweaker
-- hooks ConflictDirector .init / .refresh_conflict_director_patches / .spawn_queued_unit
-- / .update / .update_horde_pacing / .horde_killed / .update_mini_patrol /
-- .calculate_threat_value / .handle_alone_player, but NOT ._post_spawn_unit, so
-- this is a new (Class, method) - no VMF duplicate-hook drop. hook_safe: we only
-- act after the spawn is complete and never change vanilla's return.
-- ----------------------------------------------------------------------------
mod:hook_safe("ConflictDirector", "_post_spawn_unit", function(self, ai_unit, go_id, breed, spawn_pos, spawn_category, spawn_animation, optional_data, spawn_type, spawn_queue_id)
    if type(breed) ~= "table" then return end
    local cfg = _BY_BREED[breed.name]
    if not cfg then return end
    _safe("boss_grudge:" .. breed.name, _maybe_apply_grudge, ai_unit, optional_data, cfg)
end)

-- ----------------------------------------------------------------------------
-- Regression checks (runtime-only, no io — issue 511).
-- ----------------------------------------------------------------------------
rt_register("boss_grudge_targets_present", function()
    -- A vanilla rename of a boss breed or a grudge-mark buff template would make
    -- a toggle silently no-op or, worse, send a bad wire id. Assert every breed
    -- exists and every buff template resolves in BOTH BuffTemplates and
    -- NetworkLookup.buff_templates (the id every peer must share for wire safety).
    local breeds = rawget(_G, "Breeds")
    if not breeds then return "Breeds global missing" end
    local buff_templates = rawget(_G, "BuffTemplates")
    if not buff_templates then return "BuffTemplates global missing" end
    local nl = rawget(_G, "NetworkLookup")
    local nl_buffs = nl and nl.buff_templates
    if not nl_buffs then return "NetworkLookup.buff_templates missing" end
    for i = 1, #GRUDGE do
        local g = GRUDGE[i]
        if not breeds[g.breed] then return "missing boss breed: " .. g.breed end
        if not buff_templates[g.buff] then return "missing grudge buff template: " .. g.buff end
        if rawget(nl_buffs, g.buff) == nil then
            return "grudge buff not in NetworkLookup.buff_templates (wire id absent on peers): " .. g.buff
        end
    end
end)

rt_register("boss_grudge_cataclysm_rank_sane", function()
    -- Guard the difficulty gate against a vanilla rank renumber: our CATACLYSM_RANK
    -- constant must equal DifficultySettings.cataclysm.rank, else Cata+ gating drifts.
    local ds = rawget(_G, "DifficultySettings")
    local cata = ds and ds.cataclysm
    if not cata or type(cata.rank) ~= "number" then
        return "DifficultySettings.cataclysm.rank missing"
    end
    if cata.rank ~= CATACLYSM_RANK then
        return string.format("CATACLYSM_RANK (%d) != DifficultySettings.cataclysm.rank (%d)",
            CATACLYSM_RANK, cata.rank)
    end
end)
