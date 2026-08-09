-- OWNER: Curse lighting and injected-map performance census (Phase 5 #1159)
-- RESPONSIBILITY: own curse sky/map profiles, current-node helpers, the bounded
-- performance census constants, and the single CameraManager shading hook.
-- PUBLIC SURFACE: stable exhaustive owner map published as
-- mod._ct_curse_lighting_owner; CT_PERF_* legacy globals are republished.
-- INVARIANTS: one hook at the original entry boundary, action-time dependencies,
-- no network/RPC/command ownership, and reload-stable callback identity.
-- Owned by: chaos_wastes_tweaker_dev.lua.
-- Consumed via: one ordered installer call plus the current_node_is_belakor
-- facade retained by later pickup code.

local PERF_CENSUS_MARKER = "perf104:flowstate_enemy_fps_census_v0.7.214"
local PERF_WINDOW = 5.0

return function(ctx)
    assert(type(ctx) == "table", "_ct_curse_lighting_owner requires context")
    local mod = assert(ctx.mod, "_ct_curse_lighting_owner requires mod")
    assert(type(ctx.on_injected_adventure_level) == "function",
        "_ct_curse_lighting_owner requires injected-level gate")
    assert(type(ctx.adventure_base_from_level_key) == "function",
        "_ct_curse_lighting_owner requires adventure-key resolver")
    assert(type(ctx.get_managers) == "function",
        "_ct_curse_lighting_owner requires Managers accessor")
    assert(type(ctx.get_level_helper) == "function",
        "_ct_curse_lighting_owner requires LevelHelper accessor")
    assert(type(ctx.get_shading_environment) == "function",
        "_ct_curse_lighting_owner requires ShadingEnvironment accessor")
    assert(type(ctx.make_vector3) == "function",
        "_ct_curse_lighting_owner requires Vector3 constructor")
    assert(type(ctx.printf) == "function",
        "_ct_curse_lighting_owner requires printf")

    local state = mod._ct_curse_lighting_owner_state
    if not state then
        state = { api = {}, hook_installed = false }
        mod._ct_curse_lighting_owner_state = state
    end
    state.api = state.api or {}

    -- Refresh before the idempotence guard. The registered callback and public
    -- helpers close over this holder, never an obsolete entry chunk.
    state.on_injected_adventure_level = ctx.on_injected_adventure_level
    state.adventure_base_from_level_key = ctx.adventure_base_from_level_key
    state.get_managers = ctx.get_managers
    state.get_level_helper = ctx.get_level_helper
    state.get_shading_environment = ctx.get_shading_environment
    state.make_vector3 = ctx.make_vector3
    state.printf = ctx.printf

-- ============================================================
-- Curse SKY / atmosphere tinting (CameraManager.shading_callback)
-- ============================================================
-- Light.set_color only tints individual lights — adventure-level skies, sun,
-- and atmospheric fog stay vanilla. Peregrinaje (bundle-unpacked, file
-- 92BC0C4E7BFF8C3A.lua) drives sky/sun/fog via ShadingEnvironment.set_vector3
-- on keys like `skydome_tint_color`, `sun_color`, `secondary_sun_color`,
-- `ambient_tint`, `fog_color`. Vanilla CameraManager.shading_callback
-- (camera_manager.lua:283-368) runs per frame with a live shading_env handle;
-- vanilla `MoodHandler.apply_environment_variables` is called at line 346 to
-- overlay any active moods. We hook_safe AFTER vanilla so the curse tint
-- multiplies the post-mood sky color.
--
-- Stingray re-seeds the shading_environment from the level's baked template
-- every frame, so no save/restore — when the player leaves the cursed node
-- and we stop applying, the level's vanilla atmosphere returns automatically.
-- Per-curse lighting PROFILES instead of a single flat tint. Each profile
-- specifies a different multiplicative tint per shading-environment variable so
-- the scene reads as "themed atmosphere" rather than "uniform color filter":
--   - sky (skydome_tint_color):    the headline color — strongest hue
--   - sun (sun_color):             warmer / cooler accent, not pure-color
--   - secondary_sun (fill):        subtler, often neutral-toward-tint
--   - ambient_tint (mid):          moody, shifts whole scene tone
--   - ambient_tint_top (zenith):   slight contrast cue at the top of ambient
--   - fog_color (haze):            second strongest accent, ties scene together
--   - exposure (scalar):           tiny dim/bright tweak for mood
-- All values are multiplicative on top of the level's baked atmosphere, so the
-- result blends with the underlying environment instead of replacing it.
if not state.curse_sky_profiles then
state.curse_sky_profiles = {
    -- KHORNE — blood-red dominant. v0.7.18: toned ~30% toward neutral
    -- so the exterior color isn't oppressive (user feedback).
    khorne = {
        skydome_tint_color   = { 1.32, 0.51, 0.44 },
        sun_color            = { 1.21, 0.76, 0.62 },
        secondary_sun_color  = { 1.14, 0.65, 0.58 },
        ambient_tint         = { 1.04, 0.69, 0.62 },
        ambient_tint_top     = { 1.14, 0.58, 0.51 },
        fog_color            = { 1.39, 0.48, 0.44 },
        exposure_mul         = 0.95,
    },
    -- NURGLE — sickly bog green. v0.7.18 toned ~30% toward neutral. v0.7.46
    -- further tones the green channel ~10–15% on every slot and shifts toward
    -- yellow so it reads as jaundiced/sickly without overwhelming. Per user:
    -- "outdoor greens a bit less intense, but still visibly a sickly greenish-yellow."
    nurgle = {
        skydome_tint_color   = { 0.78, 1.05, 0.55 },   -- was {0.62, 1.21, 0.58} — softer sky, more yellow tint
        sun_color            = { 1.05, 1.02, 0.65 },   -- was {0.97, 1.11, 0.69} — pull green down, lean yellow
        secondary_sun_color  = { 0.92, 0.98, 0.66 },   -- was {0.79, 1.04, 0.69}
        ambient_tint         = { 0.88, 0.95, 0.68 },   -- was {0.76, 1.00, 0.72} — softer bounce
        ambient_tint_top     = { 0.82, 1.00, 0.60 },   -- was {0.69, 1.07, 0.62}
        fog_color            = { 0.80, 1.05, 0.55 },   -- was {0.65, 1.14, 0.58} — fog less aggressively green
        exposure_mul         = 1.00,
    },
    -- TZEENTCH — cobalt sky lit by orange daylight, deep-blue point lights.
    -- v0.7.18: toned ~30% toward neutral on sun/ambient (user feedback —
    -- the deep-orange exterior in v0.7.17 was too oppressive). Cobalt sky
    -- and cool blue fog are also pulled slightly to neutral.
    tzeentch = {
        skydome_tint_color   = { 0.62, 0.76, 1.35 },   -- cobalt sky (softer)
        sun_color            = { 1.39, 0.72, 0.44 },   -- orange direct sun (softer than v0.7.17)
        secondary_sun_color  = { 1.28, 0.79, 0.55 },
        ambient_tint         = { 1.25, 0.86, 0.58 },
        ambient_tint_top     = { 1.32, 0.76, 0.48 },
        fog_color            = { 0.76, 0.83, 1.21 },   -- cool blue fog (softer)
        exposure_mul         = 1.04,
    },
    -- SLAANESH — pink + lilac, with hot magenta highlights. Sun is a peach
    -- counterpoint to the pink sky for visual depth. Ambient drinks the pink.
    slaanesh = {
        skydome_tint_color   = { 1.35, 0.50, 1.15 },
        sun_color            = { 1.30, 0.85, 0.95 },
        secondary_sun_color  = { 1.20, 0.65, 1.05 },
        ambient_tint         = { 1.15, 0.65, 1.05 },
        ambient_tint_top     = { 1.30, 0.55, 1.20 },
        fog_color            = { 1.25, 0.40, 1.10 },
        exposure_mul         = 0.97,
    },
    -- BELAKOR — twilight purple. v0.7.21 brightened interiors; v0.7.207-dev
    -- brightens them further after a report that already-dark INTERIOR maps
    -- (repro: Devious Delvings / dlc_termite_2, a mines level) went near-black
    -- under the curse. Root cause: these tints are MULTIPLICATIVE, so a factor
    -- < 1 on the interior channels (ambient / fill / exposure) crushes a scene
    -- whose baked atmosphere is already dim. Fix: the interior-bounce channels
    -- no longer darken at all (ambient/fill/exposure >= 1.0) and only carry the
    -- purple HUE (green pulled below blue); the EXTERIOR sky + direct sun stay
    -- dim so open-air Belakor missions keep their oppressive mood. VISUAL -
    -- needs in-game confirmation; if still off, wire a live brightness knob.
    belakor = {
        skydome_tint_color   = { 0.45, 0.30, 0.70 },   -- exterior sky: still dim + purple
        sun_color            = { 0.62, 0.60, 0.92 },   -- exterior direct sun: slightly dim
        secondary_sun_color  = { 0.90, 0.85, 1.10 },   -- fill: near-neutral, lifted (was 0.55/0.50/0.90) — interiors
        ambient_tint         = { 1.00, 0.90, 1.22 },   -- interior bounce: NO darkening, purple-shifted (was 0.75/0.65/1.00)
        ambient_tint_top     = { 0.92, 0.85, 1.18 },   -- top ambient: near-neutral, purple (was 0.60/0.55/1.00)
        fog_color            = { 0.45, 0.35, 0.80 },   -- keep fog purple
        exposure_mul         = 1.02,                    -- tiny lift, no global dim (was 0.92)
    },
}
end

-- ============================================================
-- Per-MAP curse-lighting brightness overrides (#258, #271)
-- ============================================================
-- A few injected adventure maps read too dark even after the per-curse profile
-- and the global curse_lighting_brightness knob. This table adds an EXTRA
-- per-channel multiplier for those specific maps, applied ON TOP of the profile
-- tint and the global knob inside the shading_callback below. Keyed by the
-- injected-adventure BASE level_key (resolved from the CW permutation level_id via
-- adventure_base_from_level_key), then by curse theme; "*" = every curse. A missing
-- map, theme, or channel resolves to 1.0 (no change), so no other map regresses.
-- Channel names match state.curse_sky_profiles vars, plus "exposure".
--   #258 The Well of Dreams (dlc_termite_3): under Tzeentch the upper-hemisphere
--        ambient (ambient_tint_top) crushes to near-black. Double it (amb_top
--        +100%). Tzeentch only; other curses on this map read fine. (Sibling mod
--        vdl made the analogous Adventure-mode fix for the same map/channel.)
--   #271 Devious Delvings (dlc_termite_2): a dark mines interior. The curse look
--        needs ~2x brighter overall, for EVERY curse -- doubling the four interior
--        levers the brightness knob drives = "set the knob to 2.0 for this map only".
if not state.curse_map_brightness then
state.curse_map_brightness = {
    dlc_termite_3 = {
        tzeentch = { ambient_tint_top = 2.0 },
    },
    dlc_termite_2 = {
        ["*"] = {
            secondary_sun_color = 2.0,
            ambient_tint        = 2.0,
            ambient_tint_top    = 2.0,
            exposure            = 2.0,
        },
    },
}
end

local api = state.api
if not api.current_node_theme then
    api.current_node_theme = function()
        local Managers = state.get_managers()
        if not (Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
        local mechanism = Managers.mechanism:game_mechanism()
        if not mechanism or not mechanism.get_deus_run_controller then return nil end
        local run = mechanism:get_deus_run_controller()
        if not run or not run.get_current_node then return nil end
        local node = run:get_current_node()
        return node and node.theme or nil
    end

    api.current_node_curse = function()
        local Managers = state.get_managers()
        if not (Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
        local mechanism = Managers.mechanism:game_mechanism()
        if not mechanism or not mechanism.get_deus_run_controller then return nil end
        local run = mechanism:get_deus_run_controller()
        if not run or not run.get_current_node then return nil end
        local node = run:get_current_node()
        return node and node.curse or nil
    end

    -- v0.7.64: locus only spawns on the actual Belakor-cursed mission.
    api.current_node_is_belakor = function()
        return api.current_node_curse() == "curse_belakor_totems"
    end
end

local _current_node_theme = api.current_node_theme
local _current_node_curse = api.current_node_curse
local _current_node_is_belakor = api.current_node_is_belakor

-- The public map is a replaceable namespace, not the private identity owner.
-- Exhaustively rebuild the map supplied by the current entry generation so
-- removed exports and foreign sentinels cannot survive a reload.
local exports = mod._ct_curse_lighting_owner
if type(exports) ~= "table" or exports == api then
    exports = {}
end
for key in pairs(exports) do
    exports[key] = nil
end
exports.current_node_theme = api.current_node_theme
exports.current_node_curse = api.current_node_curse
exports.current_node_is_belakor = api.current_node_is_belakor
exports.curse_sky_profiles = state.curse_sky_profiles
exports.curse_map_brightness = state.curse_map_brightness
exports.perf_census_marker = PERF_CENSUS_MARKER
exports.perf_window = PERF_WINDOW

-- Republish every exact public boundary before the idempotence guard.
mod._ct_curse_lighting_owner = exports
CT_PERF_CENSUS_MARKER = PERF_CENSUS_MARKER
CT_PERF_WINDOW = PERF_WINDOW

if state.hook_installed then
    return exports
end

-- #104 perf census tuning: sample window (seconds) and marker.
mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
    local Managers = state.get_managers()
    local LevelHelper = state.get_level_helper()
    local ShadingEnvironment = state.get_shading_environment()
    local Vector3 = state.make_vector3
    if not state.on_injected_adventure_level() then return end
    -- #104 perf census (diagnose-before-mitigate). The shading_callback is the
    -- per-frame, injected-map-gated path, so sample a throttled LOAD census here
    -- BEFORE the curse-theme early returns below (so it runs on EVERY injected
    -- frame, cursed or not). User reports FPS drops localized to the first-grimoire
    -- Chest of Trials on Blood in the Darkness; the leading suspect is the same
    -- cursed_chest objective_unit / networked-flow-state load that overflowed the
    -- 512 cap (#262) - hundreds of linked objective_units tank framerate long
    -- before they crash. This prints flow-state count + live enemy count + avg fps
    -- + worst single frame every CT_PERF_WINDOW s so a repro AT the chest shows
    -- exactly what spikes. Cheap per frame (one guarded clock read + a counter).
    do
        local now = (Managers and Managers.time and Managers.time:time("game")) or nil
        if now then
            local st = mod._ct_perf
            if not st or now < st.census then
                st = { last = now, census = now, frames = 0, worst = 0 }
                mod._ct_perf = st
            end
            local dt = now - st.last
            st.last = now
            if dt > st.worst then st.worst = dt end
            st.frames = st.frames + 1
            local elapsed = now - st.census
            if elapsed >= CT_PERF_WINDOW then
                local nfs = Managers.state and Managers.state.networked_flow_state
                local flow_states = (nfs and type(nfs._num_states) == "number") and nfs._num_states or -1
                -- v0.7.216: the ConflictDirector manager is Managers.state.conflict, NOT
                -- Managers.state.conflict_director (that key is nil), so the first census
                -- shipped enemies=-1 on every line. `_num_spawned_ai` is the live alive-AI
                -- count (conflict_director.lua:2169).
                local cd = Managers.state and Managers.state.conflict
                local enemies = (cd and type(cd._num_spawned_ai) == "number") and cd._num_spawned_ai or -1
                local lvl = "?"
                local gm = Managers.state and Managers.state.game_mode
                if gm and gm.level_key then
                    local ok, k = pcall(gm.level_key, gm)
                    if ok and k then lvl = k end
                end
                pcall(state.printf,
                    "[ct:perf] level=%s theme=%s window=%.1fs frames=%d avg_fps=%.1f worst_frame_ms=%.1f flow_states=%d enemies=%d",
                    tostring(lvl), tostring(_current_node_theme() or "none"),
                    elapsed, st.frames, (elapsed > 0 and st.frames / elapsed) or 0,
                    st.worst * 1000, flow_states, enemies)
                st.census = now
                st.frames = 0
                st.worst = 0
            end
        end
    end
    local theme = _current_node_theme()
    if not theme or theme == "wastes" then return end
    local profile = state.curse_sky_profiles[theme]
    if not profile then return end

    -- User brightness knob (#243): scales the INTERIOR channels (fill, ambient
    -- bounce, exposure) so an already-dark injected map can be lifted to taste
    -- without touching the exterior sky/sun/fog color that carries the curse
    -- mood. 1.0 = the baked profile exactly as-is (no behavior change). One
    -- cheap settings read per callback, dwarfed by the ShadingEnvironment calls.
    local b = tonumber(mod:get("curse_lighting_brightness")) or 1.0

    -- Per-MAP brightness override (#258, #271): resolve an EXTRA per-channel
    -- multiplier for maps that read too dark even after the profile + global knob.
    -- Keyed by injected-adventure BASE key (from the CW permutation level_id) then
    -- by curse theme, falling back to "*" = all curses. Missing map/theme/channel =
    -- 1.0 (no change), so no other map regresses. Applied ON TOP of profile + b.
    local map_over
    do
        local ls = LevelHelper and LevelHelper:current_level_settings()
        local base_key = ls and state.adventure_base_from_level_key(ls.level_id)
        local per_map = base_key and state.curse_map_brightness[base_key]
        if per_map then
            map_over = per_map[theme] or per_map["*"]
        end
    end
    local function map_mul(var_name)
        return (map_over and map_over[var_name]) or 1.0
    end

    -- Multiply each existing color by the curse profile's per-var tint (and, for
    -- interior channels, by the user brightness `s`). ShadingEnvironment.vector3
    -- returns a fresh Vector3 each call (valid within this frame) — safe to read,
    -- multiply, and write back.
    local function mul_set(var_name, s)
        local t = profile[var_name]
        if not t then return end
        s = (s or 1.0) * map_mul(var_name)
        local v = ShadingEnvironment.vector3(shading_env, var_name)
        if v then
            ShadingEnvironment.set_vector3(shading_env, var_name,
                Vector3(v.x * t[1] * s, v.y * t[2] * s, v.z * t[3] * s))
        end
    end
    mul_set("skydome_tint_color")      -- exterior sky: curse hue only, no brightness lift
    mul_set("sun_color")               -- exterior direct sun: no lift
    mul_set("secondary_sun_color", b)  -- fill light (interior): lifted by brightness
    mul_set("ambient_tint", b)         -- interior bounce: lifted
    mul_set("ambient_tint_top", b)     -- interior top ambient: lifted
    mul_set("fog_color")               -- exterior haze: no lift

    local exp = (profile.exposure_mul or 1.0) * b * map_mul("exposure")
    if exp ~= 1.0 then
        local cur = ShadingEnvironment.scalar(shading_env, "exposure")
        if cur then
            ShadingEnvironment.set_scalar(shading_env, "exposure", cur * exp)
        end
    end
end)
state.hook_installed = true

    return exports
end
