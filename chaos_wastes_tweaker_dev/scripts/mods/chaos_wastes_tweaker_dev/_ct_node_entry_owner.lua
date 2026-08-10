--[[
_ct_node_entry_owner - the Chaos Wastes NODE-ENTRY seam (#1159 / #2 file-size
refactor).

RESPONSIBILITY
Owns everything ct does when a run moves INTO a Chaos Wastes graph node, and
nothing else. Every branch below starts from the same walk - the run state's
current (or next) node key, resolved against the run controller's graph - and
either decides what that node does to the player or repairs the vanilla data the
node is about to read:

  * WHETHER THE NODE'S CURSE RUNS. The RUNTIME half of the curse-disable policy:
    the MutatorHandler._activate_mutator veto, plus the save-and-restore of
    node.curse across DeusMechanism._transition_next_node and .start_next_round,
    so the curse mutator never activates while every other reader (UI tooltips,
    save state, network sync) still sees the canonical curse. start_next_round
    additionally forces node.theme = "wastes" so the curse aesthetic cannot load
    behind a suppressed curse. The GENERATION-time half - filtering the curse out
    of the graph as it is built - is _ct_campaign_graph_owner's, and the two
    halves meet only at the is_curse_disabled predicate the entry still owns and
    passes to both.

  * WHAT THE NODE'S CURSE LOOKS LIKE. DeusMechanism.get_current_node_curse nulls
    the name of a disabled curse, and DeusMapDecisionView._enable_hover suppresses
    the curse-themed hover preview of the node it is previewing. The two
    DeusThemeSettings backfills belong to this owner rather than to a data-fixup
    module because they exist ONLY as the crash guard for this owner's own theme
    force: "wastes" is the single theme with no curse_description_color and no
    string icon, so forcing it onto a still-cursed node is precisely what makes
    DeusCurseUI index a nil color table and hand a table to
    UIRenderer.draw_texture. Move the theme force and these move with it.

  * THE #470 VANILLA RANK HOLE. Breeds.curse_mutator_sorcerer's MAX_HEALTH band
    has nothing at rank 8, and that hole exists only while a curse mutator has
    been initialized on the node - the exact path the hooks above gate. The
    backfill is UNCONDITIONAL per the issue 371 never-crash doctrine.

  * WHETHER THE NODE'S WEAPON CHEST CAN PRODUCE A RESULT. Native CW path missions
    ship no LevelSettings[level].deus_weapon_chest_distribution and vanilla
    get_deus_weapon_chest_type asserts on it, so the balanced fallback is injected
    into the level the CURRENT NODE points at - the same
    run_state:get_current_node_key() -> graph[node_key] -> node.level walk the
    curse hooks perform - before the custom altar-mix distribution is built and
    shuffled off that node's level_seed. Two pool guards ride the same seam
    because they decide whether that same chest can yield anything: unknown
    rarities are stripped from get_own_weapon_pool_excludes so chest generation
    cannot index a nil weapon_pool bucket, and the Trollhammer Torpedo's missing
    property pool is aliased so a chest UPGRADE on that weapon yields properties
    instead of traits only.

EXTRACTION
ONE contiguous chunk moved: entry lines 2728-3221 (494 raw / 455 non-empty
lines), MD5 3309e60ddf14a3fce34c68b5f891fb81 over the pristine `git archive`
bytes. Every line is byte-identical to the pre-extraction entry region with
exactly ONE deviation (below). The only additions are this header, the ctx
binding block, and the closing `end` / `return install`. `mod:dofile` is not a
singleton, so the entry calls this installer EXACTLY once, at the exact line the
moved block occupied - immediately after the _ct_boon_offer_view_owner install
and immediately before the _ct_weapon_trait_generation install - so hook
registration order and _rt_register append order are unchanged mod-wide.

THE ONE DEVIATION
`_transition_next_node` reset the entry local `_defeat_recovery_triggered_this_round`
by direct assignment. That local is BOTH written here and read/written from the
entry's own `defeat_recovery_triggered` accessor (the one it hands to
_ct_combat_hooks), so re-declaring it at this module's scope would split one flag
into two storage slots that silently diverge. The line therefore becomes a call
to that SAME accessor, injected as ctx.defeat_recovery_triggered:

    _defeat_recovery_triggered_this_round = false   ->   defeat_recovery_triggered(false)

The accessor's own body is unchanged and still lives in the entry, so there is
still exactly one slot. `qa/lua/tests/test_ct_node_entry_owner.lua` pins the
substitution by installing against a recording accessor and asserting the node
transition drives it to false.

CROSSINGS
Five entry values cross, none of them state:
  * `is_curse_disabled` and `dbg` cross as WRAPPER CLOSURES. Both entry slots are
    forward-declared and filled by assignment (is_curse_disabled at the umbrella
    block, _dbg at the top), and a wrapper costs nothing while making a future
    re-order of this install site incapable of freezing nil into eleven curse
    reads.
  * `effective_setting`, `_rt_register` and `_capture_returns` cross BY VALUE.
    All three are already assigned above this install point and are never
    reassigned - the same by-value form the adjacent _ct_weapon_trait_generation
    install six lines below uses.
Game globals (Breeds, DeusThemeSettings, WeaponProperties, LevelSettings,
DEUS_CHEST_TYPES, HashUtils, Managers, printf, table.shuffle) stay late-bound
inside the callbacks exactly as before.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
  * _ct_campaign_graph_owner shapes the graph BEFORE the run reads it (including
    filter_available_curses / restore_available_curses); this owner acts on a node
    the run is entering NOW. Neither may register the other's hooks.
  * _ct_boon_offer_view_owner installs immediately above and owns WHERE the
    offered-boon widgets sit; WHICH boons are offered stays in the entry's
    generate_random_power_ups hook above that.
  * _ct_weapon_trait_generation installs immediately below and owns the TRAIT
    pool and its four generation hooks; the property-pool alias here is the
    PROPERTY side of the same vanilla upgrade table and deliberately stays with
    the chest that consumes it.
  * _ct_altar_reuse_owner owns DeusChestExtension - the altar unit once it has
    been opened. This owner never touches that class; it only decides what TYPE
    the next chest on this node will be.
  * _ct_curse_lighting_owner owns the sky and light look of a curse; this owner
    owns whether the curse runs at all.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_node_entry_owner.lua.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_node_entry_owner requires a context table")
assert(type(ctx.dbg) == "function",
    "_ct_node_entry_owner requires ctx.dbg (entry _dbg, late-binding wrapper)")
assert(type(ctx.is_curse_disabled) == "function",
    "_ct_node_entry_owner requires ctx.is_curse_disabled (entry predicate, late-binding wrapper)")
assert(type(ctx.effective_setting) == "function",
    "_ct_node_entry_owner requires ctx.effective_setting (entry accessor, bound by value)")
assert(type(ctx.rt_register) == "function",
    "_ct_node_entry_owner requires ctx.rt_register (entry regression registrar, bound by value)")
assert(type(ctx.capture_returns) == "function",
    "_ct_node_entry_owner requires ctx.capture_returns (entry _capture_returns, bound by value)")
assert(type(ctx.defeat_recovery_triggered) == "function",
    "_ct_node_entry_owner requires ctx.defeat_recovery_triggered (entry flag accessor)")

-- The moved chunk below calls every one of these unqualified, exactly as it did
-- in the entry. Binding the ctx values to those same names is what lets those
-- lines stay byte-identical across the move.
local _dbg = ctx.dbg
local is_curse_disabled = ctx.is_curse_disabled
local effective_setting = ctx.effective_setting
local _rt_register = ctx.rt_register
local _capture_returns = ctx.capture_returns
-- The one deviation: see "THE ONE DEVIATION" in the header. This is the entry's
-- OWN accessor over its OWN local, not a second copy of the flag.
local defeat_recovery_triggered = ctx.defeat_recovery_triggered

mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        return
    end
    return func(self, name, ...)
end)

-- #470: vanilla data hole in mutator_curse_skulking_sorcerer.lua. Its local rank
-- constants are broken (CATACLYSM = 6, CATACLYSM_2 = 6 duplicate, CATACLYSM_3 = 7
-- at :9-11), so the MAX_HEALTH table its server_initialize_function assigns onto
-- Breeds.curse_mutator_sorcerer (:36) spans ranks 2..7 with NOTHING at rank 8
-- (cataclysm_3). The base breed's own max_health is a full 8-entry array
-- (breed_chaos_mutator_sorcerer.lua:58-67) - the hole exists only while the curse
-- is initialized. Vanilla CW never reaches rank 8, but ct's progressive difficulty
-- can step a run to cataclysm_3 (difficulty_settings.lua:287); a curse-sorcerer
-- spawn then resolves max_health[8] = nil (conflict_director.lua:1948),
-- GenericHealthExtension.init throws in math.clamp mid extension-add, and the
-- half-initialized hit_reaction extension (registered one slot earlier,
-- unit_extension_templates.lua:403-419, extensions_ready never runs) nil-derefs on
-- the next HitReactionSystem update = host CTD. Fatshark guarded the sibling
-- RESPAWN_TIME lookup with `or RESPAWN_TIME[NORMAL]` (:43) but not MAX_HEALTH.
-- Backfill [8] = 150, Fatshark's evident cataclysm_3 intent (the duplicate-key bug
-- shifted the whole band down one rank). Entries 6/7 stay as-is: re-keying them
-- would change live gameplay values. Swept every other
-- scripts/settings/mutators/mutator_*.lua 2026-07-11: this is the only rank-keyed
-- table landing on a Breed with an unguarded read; egg_of_tzeentch/bolt_of_change
-- sparse tables all carry `or X[NORMAL]` / `or 1` fallbacks.
-- UNCONDITIONAL per issue 371 never-crash doctrine: NOT gated on the progressive
-- difficulty toggle - any other rank-8 source hits the same hole. Predicate
-- exported on mod for /ct_regression_test.
mod._ct_backfill_rank8_max_health = function(mh)
    if type(mh) == "table" and mh[8] == nil and mh[7] ~= nil then
        mh[8] = 150
        return true
    end
    return false
end

-- hook_safe AFTER initialize_mutators: server-only call path (mutator_handler.lua:48),
-- and every template.server.initialize_function has run by then
-- (mutator_handler.lua:644-645), i.e. the sparse table has already landed on the
-- breed. Grep-verified 2026-07-11: sole (MutatorHandler, initialize_mutators) hook
-- in this mod (other MutatorHandler hooks: _activate_mutator above,
-- tweak_pack_spawning_settings in the adventure-inject block).
mod:hook_safe("MutatorHandler", "initialize_mutators", function(self, mutators)
    local breed = Breeds and Breeds.curse_mutator_sorcerer
    local mh = breed and breed.max_health
    if mod._ct_backfill_rank8_max_health(mh) then
        pcall(printf, "[ct:470] backfilled curse_mutator_sorcerer.max_health[8]=150 (vanilla rank hole)")
    end
end)

_rt_register("curse_sorcerer_rank8_backfill", function()
    local fn = mod._ct_backfill_rank8_max_health
    if type(fn) ~= "function" then
        return "mod._ct_backfill_rank8_max_health export missing"
    end
    -- sparse table shaped like the curse MAX_HEALTH band (ranks 6/7 present, 8 missing)
    local sparse = { [6] = 120, [7] = 150 }
    if not fn(sparse) or sparse[8] ~= 150 then
        return "sparse table not backfilled to [8]=150"
    end
    if sparse[6] ~= 120 or sparse[7] ~= 150 then
        return "backfill mutated existing entries"
    end
    -- full 8-entry array (the base breed shape) must pass through untouched
    local full = { 30, 30, 40, 60, 90, 90, 90, 90 }
    if fn(full) or full[8] ~= 90 then
        return "full 8-entry table was modified"
    end
    if fn(nil) or fn({}) then
        return "predicate fired on nil/empty input"
    end
    return nil
end)

mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then
        return nil
    end
    return curse
end)

-- CLARIFY: Save-and-restore pattern for disabled curses. When transitioning into a node, vanilla
-- reads node.curse to spawn the curse mutator. We blank node.curse for the duration of the
-- transition so the mutator doesn't activate, then restore the original value so other code paths
-- (UI tooltips, save state, network sync) still see the canonical curse.
-- POTENTIAL BUG (LOW): If the wrapped `func` errors, restoration is skipped and node.curse stays
-- nil for the rest of the run. Same pattern repeats in start_next_round and _enable_hover.
mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    -- v0.7.39: reset defeat-recovery flag on every level/node transition so each new
    -- mission gets its own one-shot rescue. Forward-declared variable lives near the
    -- defeat-recovery feature block.
    defeat_recovery_triggered(false)

    -- Task B / #117: reset the per-mission Chest of Trials state on every node
    -- transition so each mission's cursed chests start fresh (first chest = vanilla
    -- seed, subsequent chests perturbed + force-rotated). See the always-on cursed-chest
    -- uniqueness hooks (ConflictDirector.start_terror_event + TerrorEventMixer.start_event).
    _ct_cursed_chest_seq = 0
    _ct_cot_block_last = {}   -- #117: reset per-block last-forced trial pick per mission
    _ct_cot_trial_last = {}   -- #463: reset per-block last-forced SPECIFIC trial per mission

    -- (Boon-altar no-repeat taken-boon set deliberately PERSISTS across maps --
    -- only setup_run clears it at run start.)

    local run_controller = self._deus_run_controller
    local graph_data = run_controller and run_controller:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    -- v0.7.107-dev nil-hole audit: DeusMechanism._transition_next_node returns
    -- a single `next_state` value (deus_mechanism.lua:687). Bare unpack is safe
    -- because the result table only ever holds one entry — no internal nil hole
    -- can truncate the return. Left as-is per audit.
    return unpack(results) -- unpack-safe: results holds at most one entry (single-return)
end)

mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local run_controller = self._deus_run_controller
    local current_node = run_controller and run_controller:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    -- CLARIFY: Forcing theme="wastes" prevents the curse-themed visuals/lighting from loading even
    -- though node.curse is suppressed. Without this, the engine could still load curse aesthetic
    -- assets keyed off node.theme (e.g., "tzeentch", "khorne") and produce mismatched visuals.
    -- DIAGNOSTIC (v0.7.142-dev) — client-only "curse lighting not showing": this force fires when
    -- is_curse_disabled() reads the host-synced disable_curse_* value via effective_setting. If a
    -- client's synced value diverged / hasn't arrived, the client suppresses a curse the HOST is
    -- showing and loses the curse sky/lighting. Ungated so a paired host+client log shows the
    -- divergence directly: compare is_curse_disabled per (curse) between the two.
    if saved_curse then
        _dbg("[ct:theme-force] is_server=%s curse=%s theme=%s is_curse_disabled=%s",
            tostring((Managers.player and Managers.player.is_server) and true or false),
            tostring(saved_curse), tostring(saved_theme),
            tostring(is_curse_disabled(saved_curse) and true or false))
    end
    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    -- v0.7.107-dev nil-hole audit: DeusMechanism.start_next_round returns THREE
    -- values (game_mode_key, side_compositions, game_mode_settings) per
    -- deus_mechanism.lua:818. Use _capture_returns so any future signature change
    -- that introduces an interior nil (e.g. an optional middle value) is preserved
    -- end-to-end instead of being silently truncated by `#results`-bounded unpack.
    local n, results = _capture_returns(func(self, ...))

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results, 1, n)
end)

-- NOTE (v0.7.142-dev): the per-node theme/curse/god dump for the host-vs-client
-- lighting diff lives in the EXISTING `GameModeDeus.local_player_game_starts`
-- hook below (`[mission:start]`, ~line 3559) — do NOT add a second hook here
-- (VMF drops it; lint errors). The root-cause signal is the ungated
-- `[ct:theme-force]` line added in the start_next_round hook above.

-- CLARIFY: Suppresses the curse-themed hover preview on the map for nodes whose curse is disabled.
-- Sets theme=nil so the hover view shows the default "wastes" preview instead of (e.g.) the
-- Tzeentch-themed curse preview, accurately reflecting that the player won't experience the curse.
-- POTENTIAL BUG (LOW): Inconsistent return semantics — the disabled-curse path returns nothing
-- (implicit nil), the normal path returns whatever func returns. If a future caller relies on the
-- return value, the disabled path silently differs.
mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]

    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end

    return func(self, node_key, ...)
end)

-- CLARIFY: Custom altar distribution for chests. Vanilla `get_deus_weapon_chest_type` lazily builds
-- self._deus_weapon_chest_distribution from the level's deus_weapon_chest_distribution table on
-- first call per node, then pops one entry per call. We intercept the FIRST call (when distribution
-- is empty), build our own custom distribution if any altar setting is non-zero, write it to
-- self._deus_weapon_chest_distribution, pop one entry, and return it. Subsequent calls find a
-- non-empty distribution and we fall through to vanilla which pops the rest.
-- The custom distribution overrides the entire chest contents — types left at 0 simply don't appear.
-- Filter unknown rarities out of get_own_weapon_pool_excludes. Vanilla
-- `DeusRunController.get_weapon_pool` (line 2130-2134) iterates pool_excludes
-- as the source of truth and does `weapon_pool[pool_rarity][...] = nil`, but
-- weapon_pool only contains the vanilla rarities (plentiful/common/exotic/unique).
-- If a sibling mod (e.g. Peregrinaje) wrote a custom rarity like "modded" to
-- pool_excludes and is no longer active, the `weapon_pool["modded"]` lookup is
-- nil and the indexing crashes with "attempt to index a nil value" inside chest
-- generation (deus_chest_extension.lua:_generate_stored_weapon).
-- We strip non-standard rarities from the returned table so vanilla doesn't trip.
local _VANILLA_RARITIES = { plentiful = true, common = true, exotic = true, unique = true }
mod:hook("DeusRunController", "get_own_weapon_pool_excludes", function(func, self, ...)
    local excludes = func(self, ...)
    if type(excludes) ~= "table" then return excludes end
    for rarity in pairs(excludes) do
        if not _VANILLA_RARITIES[rarity] then
            _dbg("[weapon-pool] stripped unknown rarity '%s' from pool_excludes", tostring(rarity))
            excludes[rarity] = nil
        end
    end
    return excludes
end)

-- ============================================================
-- Fix: Trollhammer Torpedo gets traits but NO properties on CW upgrade
-- ============================================================
-- Vanilla deus weapon-chest upgrade reads WeaponProperties.combinations[property_table_name][rarity]
-- (deus_weapon_generation.lua:161). The Trollhammer Torpedo's property_table_name is
-- "deus_trollhammer_torpedo" (deus_weapons.lua:256), but that key exists ONLY in the TRAIT
-- combinations table, not the PROPERTY combinations table -> the property lookup returns nil, so the
-- torpedo gets traits but ZERO properties on upgrade (reported 2026-06-17). Fix: alias its property
-- pool to the standard ranged-deus pool ("deus_ranged") at load. Idempotent (only when missing),
-- reference-alias is safe (vanilla only reads combinations), no-op if either table is unavailable.
-- TROLLHAMMER_PROPERTY_ALIAS_MARKER
do
    local WP = rawget(_G, "WeaponProperties")
    local combos = WP and WP.combinations
    if combos and rawget(combos, "deus_ranged") and not rawget(combos, "deus_trollhammer_torpedo") then
        combos.deus_trollhammer_torpedo = combos.deus_ranged
        _dbg("[deus-props] aliased deus_trollhammer_torpedo property pool -> deus_ranged (vanilla gap: torpedo had traits but no properties)")
    end
end

_rt_register("trollhammer_property_pool_aliased", function()
    local WP = rawget(_G, "WeaponProperties")
    local combos = WP and WP.combinations
    if not combos then return "skip: WeaponProperties.combinations not loaded" end
    if not rawget(combos, "deus_ranged") then return "skip: deus_ranged property pool absent (vanilla data changed?)" end
    local pool = rawget(combos, "deus_trollhammer_torpedo")
    if pool == nil then return "deus_trollhammer_torpedo property pool still nil -- alias did not apply (torpedo gets no properties)" end
    local n = 0
    for _ in pairs(pool) do n = n + 1 end
    if n == 0 then return "deus_trollhammer_torpedo property pool is empty -- alias did not take" end
end)

-- ============================================================
-- Fix: deus curse banner UI nil theme-color (client/host-crash fix)
-- ============================================================
-- Vanilla DeusCurseUI's curse-info (deus_curse_ui.lua:152) and special-message (:117) paths both
-- read theme_color = DeusThemeSettings[theme].curse_description_color and pass it to
-- _update_description_widget, which assigns it to 5 glow style.color fields (:184-188); the
-- description_start animation then indexes style.<glow>.color[1]. DeusThemeSettings.wastes is the
-- ONLY theme with NO curse_description_color (all 5 god themes + belakor have it), so when ct forces
-- node.theme="wastes" to suppress curse aesthetics (start_next_round / _transition_next_node) while a
-- real curse is still shown, theme_color is nil -> the glow color tables are nil -> the animation
-- crashes "attempt to index field 'color' (a nil value)". Vanilla never hits this (deus_generate_graph
-- forces a god theme for any curse node). Crash 2026-06-17 (sig_citadel_khorne_path5, theme=wastes +
-- curse=curse_corrupted_flesh).
--
-- Fix (v0.7.139-dev): backfill the missing color in DATA at load, instead of hooking the UI.
-- DeusThemeSettings is a boot-global available at mod-load, so this is reliable and timing-free, and
-- it covers BOTH callers (they read theme_color from the same table). The PRIOR approach hooked
-- DeusCurseUI._update_description_widget, but DeusCurseUI lives in scripts/ui/hud_ui/ and isn't loaded
-- until a deus HUD spins up inside an actual CW expedition -- so VMF's string-form hook couldn't
-- resolve the class at the adventure keep, logged a visible "trying to hook object that doesn't
-- exist: DeusCurseUI" error, and likely never installed (reported 2026-06-17). Opaque white matches
-- the icon default; the wastes theme intentionally shows no curse glow, so any opaque value just
-- prevents the nil-index. Idempotent; loops every theme so any future gap is covered. Host and every
-- client run this identically at load, so the data is consistent peer-to-peer.
--
-- SAME-SHAPE SIBLING CRASH (v0.7.156-dev, 2026-06-20) — the curse-DESCRIPTION texture, not the glow:
-- DeusCurseUI's show_curse_info (deus_curse_ui.lua:144-149) and show_special_message (:106-111) both do
--   local icon = theme_settings.icon or { 255, 255, 255, 255 }
-- then _update_description_widget assigns content.theme_icon = icon (:170). The "theme_icon" pass at
-- scenegraph "description_pivot" is pass_type="texture", texture_id="theme_icon"
-- (deus_curse_ui_definitions.lua:317-324), so UIRenderer.draw_texture reads content.theme_icon as the
-- texture NAME -- a STRING. Its content_check_function only tests `~= nil`, NOT string-ness, so the
-- {255,255,255,255} fallback (a TABLE) passes the guard and reaches the renderer. DeusThemeSettings.wastes
-- is the ONLY theme with NO `icon` field (all 5 god themes + belakor have icon="icon_<god>"/"deus_icon_belakor"),
-- so the `or {color}` fallback fires exactly when ct forces theme="wastes" on a still-cursed node ->
-- ui_passes.lua:134 "bad argument #2 to 'UIRenderer_draw_texture' (string expected, got table)". Vanilla
-- never hits it (deus_generate_graph forces a god theme for any curse node). Client crash 2026-06-20 on an
-- injected-adventure level (dlc_termite_*) with a curse active. Same DATA-backfill fix: give every theme a
-- STRING `icon`. "deus_icon_meta_01" is a neutral deus-realm meta icon (gui_icons_atlas, loaded in every CW
-- expedition) -- purely cosmetic for the rare wastes-on-cursed case; the load-bearing requirement is only
-- that it be a valid string so the texture pass stops crashing. Covers BOTH callers (same table read).
-- CURSE_THEME_COLOR_BACKFILL_MARKER  CURSE_THEME_ICON_BACKFILL_MARKER
do
    local TS = rawget(_G, "DeusThemeSettings")
    if type(TS) == "table" then
        local patched = {}
        local patched_icon = {}
        for theme_name, theme in pairs(TS) do
            if type(theme) == "table" and theme.curse_description_color == nil then
                theme.curse_description_color = { 255, 255, 255, 255 }
                patched[#patched + 1] = tostring(theme_name)
            end
            -- texture_id="theme_icon" pass wants a STRING; non-string (or nil -> vanilla's
            -- {color} fallback) crashes UIRenderer.draw_texture. Backfill a valid string.
            if type(theme) == "table" and type(theme.icon) ~= "string" then
                theme.icon = "deus_icon_meta_01"
                patched_icon[#patched_icon + 1] = tostring(theme_name)
            end
        end
        if #patched > 0 then
            _dbg("[curse-ui] backfilled curse_description_color on theme(s) with none: %s (prevents nil-color curse-banner crash when ct forces that theme on a cursed node)",
                table.concat(patched, ", "))
        end
        if #patched_icon > 0 then
            _dbg("[curse-ui] backfilled string icon on theme(s) with none: %s (prevents 'string expected, got table' curse-description texture crash when ct forces that theme on a cursed node)",
                table.concat(patched_icon, ", "))
        end
    end
end

_rt_register("curse_theme_color_backfilled", function()
    local TS = rawget(_G, "DeusThemeSettings")
    if type(TS) ~= "table" then return "skip: DeusThemeSettings not loaded" end
    local wastes = TS.wastes
    if type(wastes) ~= "table" then return "skip: DeusThemeSettings.wastes absent (vanilla data changed?)" end
    local c = wastes.curse_description_color
    if type(c) ~= "table" or #c < 4 then return "DeusThemeSettings.wastes.curse_description_color missing/short -- nil-color curse-banner crash can recur" end
    for i = 1, 4 do if type(c[i]) ~= "number" then return "curse_description_color components must be numbers" end end
    if type(wastes.icon) ~= "string" then return "DeusThemeSettings.wastes.icon not a string -- 'string expected, got table' curse-description texture crash can recur" end
    for theme_name, theme in pairs(TS) do
        if type(theme) == "table" and theme.curse_description_color == nil then
            return "theme '" .. tostring(theme_name) .. "' still has nil curse_description_color"
        end
        if type(theme) == "table" and type(theme.icon) ~= "string" then
            return "theme '" .. tostring(theme_name) .. "' has non-string icon -- curse-description texture pass crashes on a table"
        end
    end
end)

-- ============================================================
-- Guard: native CW path missions with NO deus_weapon_chest_distribution (host-crash fix)
-- ============================================================
-- Vanilla `DeusRunController.get_deus_weapon_chest_type` (deus_run_controller.lua:~2391)
-- reads `LevelSettings[level_key].deus_weapon_chest_distribution` and `assert`s if it
-- is nil, AND it rebuilds from that same table every time the distribution is exhausted.
-- Some native CW path missions (e.g. cemetery_tzeentch_path1 and the other Beastmen /
-- Tzeentch path variants) ship with NO distribution, so the assert HARD-CRASHES the host
-- the moment a deus weapon chest spawns (crash 2026-06-17, nicho, cemetery_tzeentch_path1:
-- "No deus_weapon_chest_distribution set for cemetery_tzeentch_path1" — same class as
-- Issues #58/#60/#68, but fatal rather than just missing pickups). A one-shot patch on
-- self._deus_weapon_chest_distribution is NOT enough (vanilla re-reads LevelSettings on
-- exhaustion), so we inject a balanced fallback INTO LevelSettings[level_key] — idempotent,
-- never overwrites an existing distribution, deterministic across host/clients.
-- Decomposed into pure helpers for the deus_chest_distribution_fallback regression test.
mod._ct_deus_chest_needs_fallback = function(level_settings)
    return level_settings ~= nil and level_settings.deus_weapon_chest_distribution == nil
end

mod._ct_build_deus_chest_fallback = function(chest_types)
    if not chest_types then return nil end
    -- Vanilla {chest_type = amount} shape; one of each type so every chest draws a
    -- sensible variety. Vanilla expands this into a list, shuffles by level_seed, and
    -- re-expands it on exhaustion.
    return {
        [chest_types.upgrade]     = 1,
        [chest_types.swap_melee]  = 1,
        [chest_types.swap_ranged] = 1,
        [chest_types.power_up]    = 1,
    }
end

mod._ct_ensure_deus_chest_distribution = function(drc)
    local LS = rawget(_G, "LevelSettings")
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    if not (LS and DCT and drc) then return end
    -- Resolve the current level_key exactly as vanilla does.
    local run_state = drc._run_state
    local node_key = run_state and run_state:get_current_node_key()
    local graph = drc._get_graph_data and drc:_get_graph_data()
    local node = graph and node_key and graph[node_key]
    local level_key = node and node.level
    if not level_key then return end
    local ls = LS[level_key]
    if not mod._ct_deus_chest_needs_fallback(ls) then return end
    local fallback = mod._ct_build_deus_chest_fallback(DCT)
    if not fallback then return end
    ls.deus_weapon_chest_distribution = fallback
    -- NOT a warning: injecting this fallback is the EXPECTED, correct behavior on every
    -- native CW path mission (dlc_castle_*, cemetery_*, etc.) — those simply ship no
    -- deus_weapon_chest_distribution, and we supply a balanced one so vanilla's assert
    -- can't fire. Nothing to investigate, so it's a file-only debug line, not a warning
    -- (a warning should mean "maybe a problem"; this is working as designed).
    _dbg("[deus-chest] '%s' had no deus_weapon_chest_distribution (native CW path mission) -- injected a balanced fallback (expected for these missions).", tostring(level_key))
end

_rt_register("deus_chest_distribution_fallback", function()
    -- Native CW path missions (e.g. cemetery_tzeentch_path1) can lack a
    -- deus_weapon_chest_distribution; vanilla get_deus_weapon_chest_type asserts and
    -- HARD-CRASHES the host on chest spawn (crash 2026-06-17). ct injects a fallback into
    -- LevelSettings. This pins the inject/skip decision + the fallback shape.
    if not mod._ct_deus_chest_needs_fallback({ deus_weapon_chest_distribution = nil }) then
        return "must flag a level whose deus_weapon_chest_distribution is nil as needing a fallback"
    end
    if mod._ct_deus_chest_needs_fallback({ deus_weapon_chest_distribution = { foo = 1 } }) then
        return "must NOT flag (overwrite) a level that already has a distribution"
    end
    if mod._ct_deus_chest_needs_fallback(nil) then
        return "must NOT inject into a nil level_settings entry"
    end
    local fb = mod._ct_build_deus_chest_fallback({ upgrade = "u", swap_melee = "m", swap_ranged = "r", power_up = "p" })
    if type(fb) ~= "table" then return "fallback must be a table" end
    local n = 0
    for _, amount in pairs(fb) do
        n = n + 1
        if type(amount) ~= "number" or amount < 1 then return "fallback amounts must be positive numbers" end
    end
    if n ~= 4 then return "fallback must cover all 4 chest types, got " .. tostring(n) end
    if not (fb.u and fb.m and fb.r and fb.p) then return "fallback must key on each DEUS_CHEST_TYPES value" end
    if mod._ct_build_deus_chest_fallback(nil) ~= nil then return "must return nil when DEUS_CHEST_TYPES is unavailable (degrade, don't error)" end
end)

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local distribution = self._deus_weapon_chest_distribution
    -- Prevent the vanilla "No deus_weapon_chest_distribution" assert (host crash) on CW
    -- path missions that ship without one. Idempotent; runs before any path that reaches
    -- vanilla's lookup/rebuild (incl. the custom-altar early-return path below).
    mod._ct_ensure_deus_chest_distribution(self)

    if (not distribution or #distribution == 0) and DEUS_CHEST_TYPES then
        -- v0.7.42: effective_setting so client's chest opens see host's distribution.
        -- v0.7.65: sentinel -1 = "Default" (use vanilla random distribution). 0 = literal
        -- zero altars of this type. is_custom is true if ANY altar setting is not the
        -- sentinel (the user has expressed an override). For altars set to Default in a
        -- mixed config (one type explicit, others "Default"), the Default ones contribute
        -- ZERO to the override distribution — explicit per-type control. If users want
        -- vanilla random behavior, ALL four must be "Default".
        local upgrade = effective_setting("chest_upgrade_count") or -1
        local swap_melee = effective_setting("chest_swap_melee_count") or -1
        local swap_ranged = effective_setting("chest_swap_ranged_count") or -1
        local power_up = effective_setting("chest_power_up_count") or -1

        local is_custom = upgrade ~= -1 or swap_melee ~= -1 or swap_ranged ~= -1 or power_up ~= -1
        if is_custom then
            local function as_count(v) return (v == -1) and 0 or v end
            local new_distribution = {}
            for _ = 1, as_count(upgrade)    do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.upgrade    end
            for _ = 1, as_count(swap_melee) do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_melee end
            for _ = 1, as_count(swap_ranged)do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for _ = 1, as_count(power_up)   do new_distribution[#new_distribution + 1] = DEUS_CHEST_TYPES.power_up   end

            if #new_distribution > 0 then
                -- CLARIFY: Seeding the shuffle with the node's level_seed ensures deterministic
                -- altar order across host/clients on the same node. Falls back to seed=0 if any
                -- intermediate is nil (defensive — shouldn't normally happen since this hook only
                -- fires inside an active run).
                local run_state = self._run_state
                local node_key = run_state and run_state:get_current_node_key()
                local graph = self:_get_graph_data()
                local node = graph and node_key and graph[node_key]
                local level_seed_val = node and node.level_seed
                local seed = (level_seed_val and HashUtils and HashUtils.fnv32_hash and HashUtils.fnv32_hash(level_seed_val)) or 0

                -- Issue #6 auto-probe: log shuffle inputs PRE-shuffle so host/client logs can
                -- be diffed offline without the user running /verify_altars manually. Gated on
                -- VMF debug logging via _dbg (file-only, never spams in-game chat).
                local _is_server = (Managers and Managers.player and Managers.player.is_server) or false
                _dbg("[altar:get_chest_type] PRE node=%s level_seed=%s hash=%s eff_u/m/r/p=%s/%s/%s/%s is_server=%s dist=[%s]",
                    tostring(node_key), tostring(level_seed_val), tostring(seed),
                    tostring(upgrade), tostring(swap_melee), tostring(swap_ranged), tostring(power_up),
                    tostring(_is_server), table.concat(new_distribution, ","))

                table.shuffle(new_distribution, seed)

                _dbg("[altar:get_chest_type] POST node=%s seed=%s is_server=%s shuffled=[%s]",
                    tostring(node_key), tostring(seed), tostring(_is_server),
                    table.concat(new_distribution, ","))

                self._deus_weapon_chest_distribution = new_distribution
                local chest_type = new_distribution[#new_distribution]
                new_distribution[#new_distribution] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

end

return install
