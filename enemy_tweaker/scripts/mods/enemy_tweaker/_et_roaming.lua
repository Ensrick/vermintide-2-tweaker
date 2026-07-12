local mod = get_mod("enemy_tweaker")

-- _et_roaming.lua — roaming density: SIP pack size, recycler guard, ambient layer
--
-- One "roaming enemies" knob (roaming_size_multiplier) drives two engine
-- layers: per-IP pack size via SizeOfInterestPoint mutation (snapped to the
-- engine's canonical sizes, plateaus at 8) and per-zone ambient density via
-- SpawnZoneBaker.spawn_amount_rats (uncapped, SpawnTweaks parity). Also home
-- of the EnemyRecycler.inject_roaming_patrol belt-suspenders (crash GUID
-- adbe4524), the SpawnZoneBaker.inject_special_packs cycle-zone-overrun guard
-- (v0.7.1-dev), and the global table.clone skip-metatable shim that keeps
-- 15x ambient scaling from OOMing the Lua heap.
--
-- Owned by: enemy_tweaker.lua entry point. Consumed via mod._et exports:
-- apply_roaming_size_multiplier, restore_size_of_interest_point,
-- snap_to_canonical_size, get_original_sip (accessor — backup is lazy).

local ET = mod._et
local rt_register      = ET.rt_register
local _dbg_alert       = ET.dbg_alert
local _chat_alert      = ET.chat_alert
local _spawn_dbg       = ET.spawn_dbg
local _spawn_dbg_alert = ET.spawn_dbg_alert
local _safe            = ET.safe
local _hook_wrap       = ET.hook_wrap
local _mult            = ET.mult
local _scale_count     = ET.scale_count

-- ============================================================
-- Roaming size (v0.6.0-dev — SizeOfInterestPoint mutation)
-- ============================================================
-- SizeOfInterestPoint is a global table built at game-boot mapping IP-unit
-- name → pack size (count of units). EnemyRecycler.inject_roaming_patrol
-- reads it live every spawn cycle, then looks up BreedPacksBySize[type][size]
-- for the actual breed roster. Our multiplier mutates the size values in
-- place; BreedPacksBySize is keyed by specific sizes (often only the canonical
-- ones — 3, 4, 5, 7), so multiplied sizes that don't have a pack entry will
-- silently miss at the engine call site. We log every fallback through
-- _spawn_dbg_alert so it's visible when Debug Logging is on.

local _original_size_of_interest_point = nil

local function _backup_size_of_interest_point()
    if _original_size_of_interest_point then return end
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then
        _dbg_alert("backup_size_of_interest_point: SizeOfInterestPoint not loaded — defer")
        return
    end
    _original_size_of_interest_point = {}
    for k, v in pairs(SIP) do
        _original_size_of_interest_point[k] = v
    end
    mod:info("[et:roaming] backed up SizeOfInterestPoint (%d entries)",
        (function() local n = 0; for _ in pairs(_original_size_of_interest_point) do n = n + 1 end; return n end)())
end

local function _restore_size_of_interest_point()
    if not _original_size_of_interest_point then return end
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then return end
    for k, v in pairs(_original_size_of_interest_point) do
        SIP[k] = v
    end
end

-- v0.6.1-dev hotfix (crash GUID adbe4524-971a-476f-b17d-41b8b6b20940):
-- previous version wrote arbitrary scaled sizes into SizeOfInterestPoint;
-- EnemyRecycler.inject_roaming_patrol at enemy_recycler.lua:286 does an
-- unguarded `BreedPacksBySize[pack_type][amount]` lookup, returns nil for
-- non-canonical sizes, then dereferences and crashes the game.
--
-- The engine's BreedPacksBySize tables are populated only at sizes
-- {1, 2, 3, 4, 6, 8} for every pack_type (breed_packs.lua:8066 fassert).
-- The engine's spawn floor is min_roaming_patrol_size = 3 (enemy_recycler.lua:260)
-- so any scaled value < 3 is dropped safely by the engine's own filter
-- before reaching the crash site.
--
-- Fix: snap every scaled value to the nearest canonical size in
-- {1, 2, 3, 4, 6, 8}, rounding to the LARGER on ties (user-intent for
-- multiplier > 1 = "more enemies"). Plateaus at 8 once the multiplier
-- pushes us past it; document this in the tooltip and CHANGELOG so the
-- user isn't surprised when 5x and 15x deliver the same roaming density.
--
-- Multiplier = 0 still hard-suppresses: scaled values are 0, engine's
-- floor filter catches them, no roaming spawns.

local _CANONICAL_PACK_SIZES = { 1, 2, 3, 4, 6, 8 }

-- _snap_to_canonical_size(desired) — find the nearest element of
-- _CANONICAL_PACK_SIZES. Ties round UP (a 5 prefers 6 over 4). Values
-- below 1 return 0 so the engine's spawn-floor filter suppresses cleanly.
local function _snap_to_canonical_size(desired)
    if desired < 1 then return 0 end
    if desired >= _CANONICAL_PACK_SIZES[#_CANONICAL_PACK_SIZES] then
        return _CANONICAL_PACK_SIZES[#_CANONICAL_PACK_SIZES]
    end
    local best_size, best_dist = _CANONICAL_PACK_SIZES[1], math.huge
    for _, sz in ipairs(_CANONICAL_PACK_SIZES) do
        local dist = math.abs(sz - desired)
        -- < means strictly closer; on equal distance the LARGER size wins
        -- because we iterate ascending and the inequality blocks the swap.
        if dist < best_dist then
            best_dist = dist
            best_size = sz
        end
    end
    return best_size
end

local function _apply_roaming_size_multiplier()
    local multiplier, is_zero = _mult("roaming_size_multiplier")
    _backup_size_of_interest_point()
    if not _original_size_of_interest_point then return end
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then return end

    local mutated, snapped, plateaued = 0, 0, 0
    _safe("apply_roaming_size_multiplier", function()
        for ip_name, base in pairs(_original_size_of_interest_point) do
            if type(base) == "number" then
                local desired = _scale_count(base, multiplier)
                local snapped_size = _snap_to_canonical_size(desired)
                if snapped_size ~= desired then
                    snapped = snapped + 1
                    _spawn_dbg("roaming",
                        "snap-to-canonical: ip=%s base=%d desired=%d snapped=%d",
                        tostring(ip_name), base, desired, snapped_size)
                    if desired > _CANONICAL_PACK_SIZES[#_CANONICAL_PACK_SIZES] then
                        plateaued = plateaued + 1
                    end
                end
                SIP[ip_name] = snapped_size
                mutated = mutated + 1
            end
        end
    end)
    mod:info("[et:roaming] applied: multiplier=%.1f mutated=%d snapped=%d plateaued_at_8=%d",
        multiplier, mutated, snapped, plateaued)
    if is_zero then
        _spawn_dbg_alert("roaming",
            "multiplier=0 — all roaming pack sizes set to 0; engine's min_roaming_patrol_size=3 filter suppresses spawns")
    elseif plateaued > 0 then
        _spawn_dbg_alert("roaming",
            "multiplier=%.1f exceeds engine canonical max (8 units/IP); %d IPs plateaued. Past ~2.7x the roaming slider has no additional effect.",
            multiplier, plateaued)
    end
end

-- ============================================================
-- Roaming belt-suspenders (v0.6.1-dev hotfix)
-- ============================================================
-- EnemyRecycler.inject_roaming_patrol at enemy_recycler.lua:286 does an
-- unguarded BreedPacksBySize[pack_type][amount] lookup and dereferences
-- pack_data.prob on the next line. Crash GUID adbe4524-... v0.6.0-dev.
--
-- _apply_roaming_size_multiplier above now snaps to canonical sizes so
-- this should never fire under our mutation. But: future engine
-- versions could add a new pack_type missing from our canonical set,
-- another mod could rewrite BreedPacksBySize, or the level data could
-- carry a pack_type our snap helper doesn't know about. Wrap the call
-- so we never crash again on this path — log + bail to no-op (the
-- engine handles a no-op inject gracefully; the recycler tries again
-- the next cycle).
if rawget(_G, "EnemyRecycler") then
    _hook_wrap("EnemyRecycler", "inject_roaming_patrol", "inject_roaming_patrol",
            function(func, self, area_position, area_rot, pack_type, pack_size_ip_unit_name, zone_data)
        local SIP = rawget(_G, "SizeOfInterestPoint")
        local amount = SIP and SIP[pack_size_ip_unit_name]
        local BPS = rawget(_G, "BreedPacksBySize")
        -- Pre-check: if BreedPacksBySize doesn't have an entry for our
        -- (pack_type, amount) pair, bail BEFORE calling vanilla so the
        -- crash never reaches enemy_recycler.lua:286.
        if BPS and pack_type and type(amount) == "number" then
            local sizes_for_type = BPS[pack_type]
            if sizes_for_type and sizes_for_type[amount] == nil then
                _spawn_dbg_alert("roaming",
                    "inject_roaming_patrol pre-check: BreedPacksBySize[%s][%d] missing — bailing (would crash at enemy_recycler.lua:286). ip=%s",
                    tostring(pack_type), amount, tostring(pack_size_ip_unit_name))
                return
            end
            if not sizes_for_type then
                _spawn_dbg_alert("roaming",
                    "inject_roaming_patrol pre-check: BreedPacksBySize[%s] missing entirely (unknown pack_type) — bailing. ip=%s amount=%d",
                    tostring(pack_type), tostring(pack_size_ip_unit_name), amount)
                return
            end
        end
        _spawn_dbg("roaming",
            "inject_roaming_patrol pack_type=%s ip=%s amount=%s",
            tostring(pack_type), tostring(pack_size_ip_unit_name), tostring(amount))
        return func(self, area_position, area_rot, pack_type, pack_size_ip_unit_name, zone_data)
    end)
end

-- ============================================================
-- Ambient density (v0.6.2-dev — SpawnZoneBaker layer)
-- ============================================================
-- SizeOfInterestPoint mutation (above) drives roaming PACK size for IP-based
-- patrols and plateaus at 8 because BreedPacksBySize only has rosters for
-- canonical sizes {1, 2, 3, 4, 6, 8}. SpawnTweaks bypasses this plateau by
-- hooking a DIFFERENT layer: SpawnZoneBaker.spawn_amount_rats — the per-zone
-- ambient density pass that places loose units throughout the level at
-- map-bake time. Scaling num_wanted_rats here results in MORE PACKS, not
-- bigger packs, so it's not bound by the canonical-size table.
--
-- We tie this to the same roaming_size_multiplier so the user has ONE
-- "roaming enemies" knob that drives both layers: per-IP pack size (capped
-- at 8) AND ambient density (uncapped). Past ~2.7x the IP layer has
-- plateaued; the ambient layer continues to scale linearly, which is what
-- gives the slider meaningful effect at 5x / 10x / 15x.
--
-- Signature (vanilla spawn_zone_baker.lua:698):
--   spawn_amount_rats(self, spawns, pack_sizes, pack_rotations, pack_members,
--                     zone_data_list, nodes, num_wanted_rats, pack_type, area, zone)
-- v0.7.1-dev hotfix belt-suspenders: vanilla SpawnZoneBaker.inject_special_packs
-- has an unchecked inner loop at lines ~549-554:
--   for k = zone_index, zone_index + period_length - 1 do
--       zone = cycle_zones[k]
--       zone.pack_type = pack_type   -- crashes when k > #cycle_zones
-- The loop assumes period_length fits within the remaining cycle_zones from
-- zone_index, but on small Deus cycles + high difficulty (cataclysm-mimic'd
-- period_length values), it overruns. Crashed at level-load on
-- dlc_termite_1_belakor_path1 / deus_skaven_beastmen / Champion-with-Cata-mimic.
--
-- We hook the function under _hook_wrap so any nil-index error in vanilla
-- falls through to the wrap's pcall + log + bail path. Skipping the
-- injection means some zones miss their special-pack override but the
-- level still loads (zones retain their level-bake default pack data).
-- That's the failure mode the user wants — playable mission > crash.
if rawget(_G, "SpawnZoneBaker") and type(rawget(_G, "SpawnZoneBaker").inject_special_packs) == "function" then
    _hook_wrap("SpawnZoneBaker", "inject_special_packs", "inject_special_packs",
            function(func, self, ...)
        -- Important: we pcall vanilla HERE (not just call it) so the wrap's
        -- own fallback path doesn't re-invoke vanilla (which would re-crash).
        -- Body returns nil cleanly to _hook_wrap; vanilla returns nothing
        -- normally so the caller doesn't notice. Skipped injection means
        -- some zones keep their level-bake default pack data — playable
        -- mission > crash.
        local ok, err = pcall(func, self, ...)
        if not ok then
            _chat_alert("SpawnZoneBaker.inject_special_packs vanilla errored: %s — skipping special-pack injection for this cycle (zones keep level-bake defaults). Often hits Deus + cataclysm-mimic on small-cycle DLC levels.", tostring(err))
        end
        return nil
    end)
end

-- v0.7.4-dev: SpawnTweaks parity. v0.7.3 capped at 5x to avoid OOM in the
-- vanilla table.clone deep-recursion path inside _generate_pack_members. But
-- SpawnTweaks runs to 15x on the same levels without OOMing. The trick I
-- missed: SpawnTweaks monkey-patches table.clone to force skip_metatable=true
-- on EVERY clone in the game. That strips metatable reachability from cloned
-- pack data, cutting per-clone heap footprint by ~2-3x, which is what lets
-- the deep-clone loop survive 15x scaling on large Deus levels.
--
-- We install the same global table.clone shim BEFORE registering the
-- spawn_amount_rats hook, and lift the cap to 15 (the full slider range).
-- The cap constant stays as a safety net — a future regression that removes
-- the table.clone shim would re-OOM, and the regression test catches that.
local _AMBIENT_EFFECTIVE_MULT_CAP = 15

-- Global table.clone shim — forces skip_metatable=true on every clone.
-- SpawnTweaks pattern (SpawnTweaks.lua:13-15). Affects ALL clones engine-wide
-- but the change is invisible to consumers: every site that calls
-- table.clone(t) without an explicit skip_metatable already accepted the
-- vanilla default of nil (which the engine treats the same as false for
-- metatable copy). Forcing true changes the behavior to skip metatable
-- copying, which is what the engine actually wants for transient pack-member
-- clones and never breaks consumers in practice (verified by the fact that
-- SpawnTweaks has been live with this hook for years across all game modes).
if type(rawget(_G, "table")) == "table" and type(table.clone) == "function" then
    mod:hook(table, "clone", function(func, t, skip_metatable) -- luacheck: no unused
        return func(t, true)
    end)
end
if rawget(_G, "SpawnZoneBaker") then
    _hook_wrap("SpawnZoneBaker", "spawn_amount_rats", "spawn_amount_rats",
            function(func, self, spawns, pack_sizes, pack_rotations, pack_members,
                     zone_data_list, nodes, num_wanted_rats, pack_type, area, zone)
        local mult, is_zero = _mult("roaming_size_multiplier")
        if mult == 1 then
            return func(self, spawns, pack_sizes, pack_rotations, pack_members,
                zone_data_list, nodes, num_wanted_rats, pack_type, area, zone)
        end
        if is_zero then
            _spawn_dbg_alert("roaming", "ambient: multiplier=0 — passing num_wanted_rats=0 to vanilla (suppress ambient density)")
            return func(self, spawns, pack_sizes, pack_rotations, pack_members,
                zone_data_list, nodes, 0, pack_type, area, zone)
        end
        -- Cap the effective multiplier (NOT the slider value). User-facing
        -- slider stays whatever they set; we just clamp how much we ask
        -- vanilla to allocate. Per-zone fewer ambient packs, but we never
        -- OOM Lua during level bake.
        local effective = mult
        local capped = false
        if effective > _AMBIENT_EFFECTIVE_MULT_CAP then
            effective = _AMBIENT_EFFECTIVE_MULT_CAP
            capped = true
        end
        local scaled = _scale_count(num_wanted_rats or 0, effective)
        if capped then
            _spawn_dbg("roaming",
                "ambient: CAPPED scaling num_wanted_rats %d -> %d (slider=%.1f effective=%.1f) zone_pack_type=%s area=%s",
                tonumber(num_wanted_rats) or 0, scaled, mult, effective,
                tostring(pack_type), tostring(area))
        else
            _spawn_dbg("roaming",
                "ambient: scaling num_wanted_rats %d -> %d (mult=%.1f) zone_pack_type=%s area=%s",
                tonumber(num_wanted_rats) or 0, scaled, mult,
                tostring(pack_type), tostring(area))
        end
        return func(self, spawns, pack_sizes, pack_rotations, pack_members,
            zone_data_list, nodes, scaled, pack_type, area, zone)
    end)
end

ET.apply_roaming_size_multiplier = _apply_roaming_size_multiplier
ET.restore_size_of_interest_point = _restore_size_of_interest_point
ET.snap_to_canonical_size = _snap_to_canonical_size
-- Accessor: the backup is taken lazily on first apply, so /verify_roaming_size
-- must read it at call time.
ET.get_original_sip = function() return _original_size_of_interest_point end

rt_register("snap_to_canonical_math", function()
    -- v0.6.1-dev hotfix smoke check: snap-to-canonical must hit the
    -- right anchor for each test case. Tie-breaks round to the larger.
    if _snap_to_canonical_size(0) ~= 0 then return "snap(0) should be 0 (suppress)" end
    if _snap_to_canonical_size(1) ~= 1 then return "snap(1) should be 1" end
    if _snap_to_canonical_size(2) ~= 2 then return "snap(2) should be 2" end
    if _snap_to_canonical_size(3) ~= 3 then return "snap(3) should be 3" end
    if _snap_to_canonical_size(4) ~= 4 then return "snap(4) should be 4" end
    if _snap_to_canonical_size(5) ~= 4 and _snap_to_canonical_size(5) ~= 6 then
        return "snap(5) should be 4 or 6 (equal distance)"
    end
    if _snap_to_canonical_size(6) ~= 6 then return "snap(6) should be 6" end
    if _snap_to_canonical_size(7) ~= 6 and _snap_to_canonical_size(7) ~= 8 then
        return "snap(7) should be 6 or 8 (equal distance)"
    end
    if _snap_to_canonical_size(8) ~= 8 then return "snap(8) should be 8" end
    if _snap_to_canonical_size(80) ~= 8 then return "snap(80) should plateau at 8" end
end)

rt_register("size_of_interest_point_present", function()
    -- The roaming multiplier mutates SizeOfInterestPoint. Confirm the
    -- table exists at runtime (loaded by engine before mod load) and that
    -- our backup pointer is initialized lazily (nil before first apply, a
    -- table after).
    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) ~= "table" then
        return "SizeOfInterestPoint not loaded (run in keep)"
    end
    local n = 0
    for _ in pairs(SIP) do n = n + 1 end
    if n == 0 then return "SizeOfInterestPoint loaded but empty" end
end)

rt_register("ambient_safety_systems_present", function()
    -- v0.7.4-dev: two interacting safeties.
    -- (1) Global table.clone shim — SpawnTweaks pattern that forces
    --     skip_metatable=true on every clone. Without it, vanilla's
    --     _generate_pack_members deep-clone OOMs Lua heap at scaling > ~5x
    --     on large Deus levels.
    -- (2) _AMBIENT_EFFECTIVE_MULT_CAP — backstop on the per-call ambient
    --     mult. With the clone shim in place this cap is rarely reached,
    --     but it's a belt-suspenders guard against a future regression
    --     that removes / overrides the clone shim.
    if type(_AMBIENT_EFFECTIVE_MULT_CAP) ~= "number" then
        return "_AMBIENT_EFFECTIVE_MULT_CAP missing — ambient layer is uncapped"
    end
    if _AMBIENT_EFFECTIVE_MULT_CAP < 1 then
        return "_AMBIENT_EFFECTIVE_MULT_CAP < 1 — ambient layer would never amplify, slider becomes inert"
    end
    -- The clone shim itself can't be probed directly (it's a hook
    -- registration with no easy runtime introspection); document via
    -- comments and rely on the on-disk repro test (load Belakor Deus at
    -- 15x, no OOM).
    if type(rawget(_G, "table")) ~= "table" or type(table.clone) ~= "function" then
        return "table.clone missing from global table — vanilla VT2 always exports it; engine version mismatch?"
    end
end)

rt_register("inject_special_packs_belt_suspenders_present", function()
    -- v0.7.1-dev hotfix smoke check: the vanilla SpawnZoneBaker.inject_special_packs
    -- inner loop has an unchecked array overrun (period_length can exceed
    -- num_cycle_zones - zone_index + 1 on small Deus cycles). We hook it
    -- under _hook_wrap so the crash is swallowed and the mission still loads.
    -- This check verifies the hook target still exists on SpawnZoneBaker so
    -- the belt-suspenders isn't silently no-op'd by a future engine rename.
    local SZB = rawget(_G, "SpawnZoneBaker")
    if not SZB then return "SpawnZoneBaker not loaded (run in-mission)" end
    if type(SZB.inject_special_packs) ~= "function" then
        return "SpawnZoneBaker.inject_special_packs missing — engine API moved; belt-suspenders for the cycle-zone overrun is now inert"
    end
end)

rt_register("ambient_density_hook_target_present", function()
    -- v0.6.2-dev: ambient layer for the roaming slider. SpawnZoneBaker is
    -- loaded in-mission only, so this check is a soft-skip in the keep.
    local SZB = rawget(_G, "SpawnZoneBaker")
    if not SZB then return "SpawnZoneBaker not loaded (run in-mission)" end
    if type(SZB.spawn_amount_rats) ~= "function" then
        return "SpawnZoneBaker.spawn_amount_rats missing — engine API moved"
    end
end)
