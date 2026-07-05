local mod = get_mod("gt_dev")

-- _gt_melee_warning.lua -- client-side early-warning cue for enemy melee windups.
--
-- Issue #308 (Melee Latency Smoothing). VT2 is host-authoritative for enemy
-- melee hits, so this changes NOTHING about outcomes: it is a purely local,
-- cosmetic/informational cue. When a nearby enemy plays an attack-windup
-- animation aimed at the local player, we fire a short sound and/or a red
-- screen-edge flash so the player can begin their (client-instant) dodge about
-- one RTT earlier than the enemy animation alone would suggest.
--
-- How windups are detected: we hook_safe `AnimationSystem.anim_event`
-- (animation_system.lua:119) -- the single convergence point where BOTH the
-- host's local anim plays AND client-received plays land (the client RPC
-- receiver `rpc_anim_event` at :375 re-invokes anim_event(unit, event, true)).
-- RPC dispatch is DYNAMIC (network_event_delegate.lua:52 re-looks-up
-- `object[callback_name]` each call), so the class-method hook fires on the
-- wire path too. At this point `event_name` is already a plain string and
-- `unit` is resolved -- no NetworkLookup / unit_storage decode needed.
--
-- Cues, scheduling, and the always-on dev diagnostic (`[gt_dev:MW]`) run off
-- gt's shared per-frame tick (`mod._gt_register_update`); the screen flash is
-- drawn from a hook_safe on `IngameHud.update` (the proven HUD-composite path,
-- mirrored from gut's _gut_respawn_timer.lua). All toggles default OFF.
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile
-- (runs after the main chunk, so mod._gt_register_update already exists).

local UIRenderer   = UIRenderer
local UISceneGraph = UISceneGraph
local Vector3      = Vector3
local Vector2      = Vector2
local Quaternion   = Quaternion
local Unit         = Unit
local ScriptUnit   = ScriptUnit

-- ============================================================
-- Tuning constants
-- ============================================================
-- Detection radius (m). Attack reach is ~3-5m (breed action ranges); a slightly
-- larger window gives the cue time to lead the swing.
local _MELEE_WARN_RANGE = 6.0
-- Enemy must be roughly facing the local player for the windup to count as
-- "aimed at you". dot(forward, dir_to_player) >= this (~72 deg half-cone at 0.3;
-- lenient because the enemy may still be turning into the swing).
local _FACING_DOT = 0.3
-- Default assumed impact delay (s) for attack anims with no measured value.
-- Set to 0 so the cue fires immediately on windup start for unverified anims
-- (issue #308 spec: "if no delay known, cue immediately on windup start").
-- Verified per-(breed, anim) delays below override this.
local _DEFAULT_IMPACT_DELAY = 0.0
-- Window (s) after a windup within which a subsequent local-player damage tick
-- is attributed to it, for the [gt_dev:MW] tuning probe.
local _DAMAGE_WINDOW = 3.0
-- Screen-edge flash duration (s) and peak alpha (0-255) -- kept subtle.
local _FLASH_DUR        = 0.45
local _FLASH_PEAK_ALPHA = 150
local _EDGE_THICKNESS    = 90  -- edge-strip thickness on the 1920x1080 canvas

-- Short, non-looping 2D UI cue. PingSystem plays "hud_ping" every mission
-- (ping_system.lua:308 selects it, :853 fires it 2D), so it is always resident
-- during play -- unlike menu-only banks.
local _WARN_SOUND = "hud_ping"

-- ============================================================
-- Attack-windup vocabulary + measured impact delays
-- ============================================================
-- Data-driven per issue #308: { [breed_name] = { [anim_name] = delay_or_false } }.
-- A numeric value is the measured windup->threat delay in SECONDS; `false`
-- marks a known attack anim whose real delay is [unverified] (Lua can't store a
-- nil VALUE, so `false` stands in for "known attack, use _DEFAULT_IMPACT_DELAY").
-- The presence of a per-breed table also flags the breed as an "elite" for the
-- elites_only scope. Any attack-prefixed anim not listed still counts (generic
-- fallback below) at the default delay.
--
-- Verified delays are `bot_threat_start_time` (or `damage_done_time` for combo
-- breeds) read from the breed action data / bt attack actions. Citations point
-- at the decompiled source under Vermintide-2-Source-Code/.
local _ATTACK_DELAYS = {
    -- breed_skaven_storm_vermin.lua: special_attack_cleave/sweep bot_threat_start_time = 0.5
    skaven_storm_vermin = {
        attack_special  = 0.5,   -- special_attack_cleave.attack_anim (breed_skaven_storm_vermin.lua:489)
        attack_pounce   = 0.5,   -- special_attack_sweep.attack_anim   (:539)
        attack_pounce_2 = 0.5,   -- special_attack_sweep.attack_anim   (:539)
        attack_push     = false, -- push_attack (:565) [unverified]
    },
    -- Commander shares skaven_storm_vermin action_data (breed_skaven_storm_vermin.lua:751-752).
    skaven_storm_vermin_commander = {
        attack_special  = 0.5,
        attack_pounce   = 0.5,
        attack_pounce_2 = 0.5,
        attack_push     = false, -- [unverified]
    },
    -- breed_chaos_warrior.lua
    chaos_warrior = {
        attack_cleave_01     = 1.25,  -- special_attack_cleave bot_threat_start_time (:569)
        attack_cleave_02     = 1.25,  -- (:569)
        attack_sweep_01      = 0.4,   -- special_attack_sweep bot_threat_start_time (:621)
        attack_sweep_02      = 0.4,   -- (:621)
        attack_sweep_03      = 0.4,   -- (:621)
        attack_run           = 0.5,   -- running_attack_right (:713)
        attack_sweep_run_01  = 0.5,   -- running_attack_right (:713)
        attack_pounce        = 0.5,   -- special_attack_launch (:751)
        attack_quick_01      = false, -- special_attack_quick (anim-driven) [unverified]
        attack_quick_02      = false, -- [unverified]
        attack_push          = false, -- [unverified]
        attack_push_2        = false, -- [unverified]
    },
    -- breed_chaos_raider.lua (mauler). NOTE: attack_cleave appears in BOTH the
    -- running (1.0) and special (0.7) actions; only one delay can be stored per
    -- anim name -- 0.7 chosen as the common melee value. The [gt_dev:MW] probe
    -- exists to disambiguate these in-game.
    chaos_raider = {
        attack_cleave    = 0.7,   -- special_attack_cleave (:554); running variant ~1.0 (:521) [ambiguous]
        attack_cleave_02 = 0.7,   -- special_attack_cleave (:554)
        attack_pounce    = 0.6,   -- special_attack_sweep (:592)
        attack_pounce_2  = 0.6,
        attack_pounce_3  = 0.6,
        attack_pounce_4  = 0.6,
        attack_push      = false, -- push_attack (:628) [unverified]
    },
    -- breed_beastmen_bestigor.lua
    beastmen_bestigor = {
        attack_special  = 0.5,   -- special_attack_cleave bot_threat_start_time (:571)
        attack_pounce   = 0.5,   -- special_attack_sweep (:605)
        attack_pounce_2 = 0.5,   -- (:605)
        attack_push     = false, -- push_attack (:645) [unverified]
    },
    -- breed_skaven_plague_monk.lua (combo attack; anim-callback damage)
    skaven_plague_monk = {
        attack_heavy         = 1.1,   -- combo_attacks damage_done_time (:958)
        attack_wild_flailing = 0.9,   -- combo_attacks damage_done_time (:971)
        attack_pounce        = false, -- frenzy_attack (:818) [unverified]
        attack_quick_1       = false, -- [unverified]
        attack_quick_2       = false, -- [unverified]
        attack_quick_3       = false, -- [unverified]
        attack_medium        = false, -- [unverified]
        attack_medium_2      = false, -- [unverified]
    },
    -- breed_chaos_berzerker.lua (savage; combo attack, anim-callback damage)
    chaos_berzerker = {
        attack_combo_2_finish = 1.246, -- damage_done_time (:1169)
        attack_combo_3_finish = 1.0,   -- damage_done_time (:1171)
        attack_pounce         = false, -- frenzy_attack (:980) [unverified]
        attack_combo_1_01     = false, -- [unverified]
        attack_combo_2_01     = false, -- [unverified]
        attack_combo_3_01     = false, -- [unverified]
    },
}

-- Generic windup filter for the all_melee scope + elite anims not listed above.
-- Nearly every melee attack anim in the breed data begins with "attack_"; a few
-- boss variants (SV champion/warlord) use "charge_attack_". Non-attack anims
-- (idle/move/hit/death) are excluded.
local function _is_attack_anim(name)
    return name:find("^attack_") ~= nil or name:find("^charge_attack_") ~= nil
end

-- ============================================================
-- Runtime state (scalars / small tables only -- no engine temporaries stored)
-- ============================================================
local _pending    = {}    -- array of fire-at game-times (scheduled cues)
local _flash_until = nil   -- game-time the screen flash fades out at
local _mw_last_windup_t     = nil
local _mw_last_windup_breed = nil
local _mw_last_windup_anim  = nil
local _mw_prev_hp           = nil  -- last-sampled local-player health fraction

local _ROOT_SG_DEF = {
    root = { scale = "hud_scale_fit", position = { 0, 0, (UILayer and UILayer.hud) or 100 }, size = { 1920, 1080 } },
}
local _render_settings = { snap_pixel_positions = true }
local _scenegraph      = nil

-- ============================================================
-- Helpers
-- ============================================================
local function _game_time()
    return Managers.time and Managers.time:time("game")
end

local function _local_player_unit()
    local pl = Managers.player and Managers.player:local_player()
    local u = pl and pl.player_unit
    if not u or not Unit.alive(u) then return nil end
    return u
end

local function _local_player_pos()
    local u = _local_player_unit()
    if not u then return nil end
    return POSITION_LOOKUP[u] or Unit.world_position(u, 0)
end

local function _local_player_hp_pct()
    local u = _local_player_unit()
    if not u then return nil end
    if not ScriptUnit.has_extension(u, "health_system") then return nil end
    local he = ScriptUnit.extension(u, "health_system")
    -- PlayerUnitHealthExtension.current_health_percent (player_unit_health_extension.lua:1000).
    -- READ ONLY -- never mutate the health extension (gameplay-facing).
    if not he or not he.current_health_percent then return nil end
    local ok, pct = pcall(he.current_health_percent, he)
    if ok and type(pct) == "number" then return pct end
    return nil
end

-- Fire a short 2D UI cue via the level world's Wwise handle. pcall-guarded:
-- WwiseWorld.trigger_event C-faults on a non-resident event.
local function _play_warn_sound()
    local wm = Managers.world
    if not wm then return end
    local world = wm:world("level_world")
    if not world then return end
    local ww = wm:wwise_world(world)
    if not ww then return end
    pcall(WwiseWorld.trigger_event, ww, _WARN_SOUND)
end

-- ============================================================
-- Windup detection (event-driven; hook_safe on AnimationSystem.anim_event)
-- ============================================================
-- Grep-verified: no other gt_dev hook targets (AnimationSystem, anim_event),
-- so this is a singleton (duplicate-hook rule).
mod:hook_safe("AnimationSystem", "anim_event", function(self, unit, event_name, skip_sync)
    if not mod:get("gt_melee_warning") then return end
    if not unit or type(event_name) ~= "string" then return end
    if not Unit.alive(unit) then return end

    -- Enemy filter: Unit.get_data(unit,"breed") returns the breed TABLE husk-side
    -- (ai_husk_base_extension.lua:11); .name is the breed key (breeds.lua:306).
    -- Players/props have no breed data -> nil -> skip.
    local breed = Unit.get_data(unit, "breed")
    if type(breed) ~= "table" then return end
    local bname = breed.name
    if type(bname) ~= "string" then return end

    local delays = _ATTACK_DELAYS[bname]  -- nil for non-elite breeds
    local scope  = mod:get("gt_melee_warning_scope") or "elites_only"
    if scope == "elites_only" and delays == nil then return end

    -- Resolve whether this anim is an attack windup + its (possibly default) delay.
    local delay
    if delays ~= nil then
        local v = delays[event_name]
        if v ~= nil then
            delay = (v ~= false) and v or _DEFAULT_IMPACT_DELAY
        elseif _is_attack_anim(event_name) then
            delay = _DEFAULT_IMPACT_DELAY
        else
            return  -- known elite breed, but this anim is not an attack
        end
    else
        -- all_melee scope, non-elite breed
        if not _is_attack_anim(event_name) then return end
        delay = _DEFAULT_IMPACT_DELAY
    end

    -- Target heuristic: enemy must be in range and facing the local player.
    -- Cheap math, only on attack-anim events. Vectors are frame-temporaries
    -- used inline (never stored).
    local ppos = _local_player_pos()
    if not ppos then return end
    local epos = POSITION_LOOKUP[unit] or Unit.world_position(unit, 0)
    if not epos then return end
    local dist = Vector3.distance(ppos, epos)
    if dist > _MELEE_WARN_RANGE then return end
    local rot = Unit.local_rotation(unit, 0)  -- node 0 (root) always exists
    if rot then
        local fwd    = Quaternion.forward(rot)
        local to_dir = Vector3.normalize(ppos - epos)
        if Vector3.dot(fwd, to_dir) < _FACING_DOT then return end
    end

    -- Always-on dev diagnostic (issue #308 step 6): one line per detected windup.
    -- Engine printf so it lands in console_logs even with mod logging off.
    printf("[gt_dev:MW] windup breed=%s anim=%s dist=%.1f delay=%.2f", bname, event_name, dist, delay)

    -- Schedule the cue + stamp the windup for the damage-delta probe.
    local now = _game_time()
    if now then
        _mw_last_windup_t     = now
        _mw_last_windup_breed = bname
        _mw_last_windup_anim  = event_name
        local lead = (tonumber(mod:get("gt_melee_warning_lead")) or 100) / 1000
        local fire_at = now + delay - lead
        if fire_at < now then fire_at = now end
        if #_pending < 32 then
            _pending[#_pending + 1] = fire_at
        end
    end
end)

-- ============================================================
-- Cue firing + damage-delta probe (gt shared per-frame tick)
-- ============================================================
local function _fire_cue(now)
    if mod:get("gt_melee_warning_audio") then _play_warn_sound() end
    if mod:get("gt_melee_warning_visual") then _flash_until = now + _FLASH_DUR end
end

-- Read-only damage probe: watch the local player's health fraction; on a drop
-- within _DAMAGE_WINDOW of the last windup, printf the measured delta. This is
-- the tuning harness for refining _ATTACK_DELAYS. No health-extension hook --
-- pure read (issue #308 forbids gameplay-facing hooks here).
local function _probe_damage(now)
    local hp = _local_player_hp_pct()
    if hp == nil then _mw_prev_hp = nil; return end
    local prev = _mw_prev_hp
    _mw_prev_hp = hp
    if prev and hp < prev - 0.001 then
        if _mw_last_windup_t and (now - _mw_last_windup_t) <= _DAMAGE_WINDOW then
            printf("[gt_dev:MW] windup->damage delta=%.3f breed=%s anim=%s dmg=%.1f%%",
                now - _mw_last_windup_t,
                _mw_last_windup_breed or "?", _mw_last_windup_anim or "?",
                (prev - hp) * 100)
            _mw_last_windup_t = nil  -- consume so one windup maps to one damage line
        end
    end
end

mod._gt_register_update("melee_warning", function(dt)
    if not mod:get("gt_melee_warning") then
        -- toggled off: drop any queued cues + reset probe baseline
        if _pending[1] then for i = #_pending, 1, -1 do _pending[i] = nil end end
        _mw_prev_hp = nil
        _flash_until = nil
        return
    end
    local now = _game_time()
    if not now then return end

    -- Drain due cues, compacting the survivors in place (no table.remove churn).
    if _pending[1] then
        local kept = 0
        for i = 1, #_pending do
            local fa = _pending[i]
            if now >= fa then
                _fire_cue(now)
            else
                kept = kept + 1
                _pending[kept] = fa
            end
        end
        for i = #_pending, kept + 1, -1 do _pending[i] = nil end
    end

    _probe_damage(now)
end)

-- ============================================================
-- Screen-edge flash draw (HUD-composite path)
-- ============================================================
-- Draw four solid edge strips against the 1920x1080 hud_scale_fit canvas.
-- Color is {alpha, r, g, b}; alpha fades with the flash timer.
local function _draw_edges(r, alpha)
    local col = { alpha, 200, 40, 40 }
    local W, H, z, TH = 1920, 1080, 998, _EDGE_THICKNESS
    UIRenderer.draw_rect(r, Vector3(0, 0, z),          Vector2(W, TH), col)  -- bottom
    UIRenderer.draw_rect(r, Vector3(0, H - TH, z),     Vector2(W, TH), col)  -- top
    UIRenderer.draw_rect(r, Vector3(0, 0, z),          Vector2(TH, H), col)  -- left
    UIRenderer.draw_rect(r, Vector3(W - TH, 0, z),     Vector2(TH, H), col)  -- right
end

-- Grep-verified: no other gt_dev hook targets (IngameHud, update), so singleton.
mod:hook_safe("IngameHud", "update", function(self, dt, t)
    if not _flash_until then return end
    if not (mod:get("gt_melee_warning") and mod:get("gt_melee_warning_visual")) then
        _flash_until = nil
        return
    end
    local now = _game_time()
    if not now then return end
    local remain = _flash_until - now
    if remain <= 0 then _flash_until = nil; return end

    local renderer = (self._ingame_ui_context and self._ingame_ui_context.ui_renderer)
        or (Managers.ui and Managers.ui._ingame_ui_context and Managers.ui._ingame_ui_context.ui_top_renderer)
    if not renderer then return end
    local input = self._ingame_ui_context and self._ingame_ui_context.input_manager
        and self._ingame_ui_context.input_manager:get_service("ingame_menu")
    if not _scenegraph then _scenegraph = UISceneGraph.init_scenegraph(_ROOT_SG_DEF) end

    local a = math.floor(_FLASH_PEAK_ALPHA * (remain / _FLASH_DUR))
    if a < 0 then a = 0 elseif a > 255 then a = 255 end

    UIRenderer.begin_pass(renderer, _scenegraph, input, dt, nil, _render_settings)
    _draw_edges(renderer, a)
    UIRenderer.end_pass(renderer)
end)
