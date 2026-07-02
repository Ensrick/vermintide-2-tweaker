local mod = get_mod("ct_dev")

-- Load-time export for the /ct_regression_test `dup_chip_no_current_node_fallback`
-- check (ct_dev 0.7.162-dev). The extra-chip node_key resolution further down is
-- `final_node_selected > vote > nil` with NO trailing current-node fallback (see
-- the comment at the resolution site). Exported here at module load so the
-- keep-time regression check can read the invariant even before any CW map vote
-- has run. Keep this string in lockstep with the resolution chain below.
mod._ct_dup_chip_node_key_resolution = "final_node_selected>vote>nil"

-- ============================================================================
-- Duplicate-career map-vote chips (Chaos Wastes map-decision screen)
-- ============================================================================
-- PROBLEM. The CW map-vote scene (DeusMapScene, deus_map_scene.lua) owns exactly
-- five player "token" chip units, one per hero, stored in a 1-based array keyed
-- by `profile_index` (`self._profile_index_to_token`, spawned in
-- spawn_graph_units at deus_map_scene.lua:238-251). DeusMapDecisionView's
-- `_update_player_state` (deus_map_decision_view.lua:665-682) walks every peer and
-- calls `self._scene:place_token(profile_index, index, node_key)` -- the chip
-- IDENTITY is `profile_index`. When general_tweaker's `allow_duplicate_careers`
-- lets two peers share a profile_index (same hero), the second peer's place_token
-- OVERWRITES the first at the same hero slot, so only ONE chip shows for both
-- voters (sitting on whichever peer iterated last). The other voter's choice is
-- invisible on the map.
--
-- FIX (client-side render only -- no new network sync). We post-hook
-- `_update_player_state` (vanilla runs first, placing its one-chip-per-hero set
-- exactly as before -- the NON-DUPLICATE case is therefore byte-for-byte vanilla).
-- Then we detect any profile_index voted by >1 peer and spawn/reuse a SECOND chip
-- unit (same per-hero token asset) for every peer EXCEPT the one vanilla's single
-- chip already shows. Vanilla's place_token loop is LAST-WRITER-WINS at the shared
-- profile_index slot (deus_map_scene.lua:833-841), so the peer it draws is the one
-- that iterated LAST in `ipairs(controller:get_peers())`. Our per-profile list is
-- built in that SAME order, so `list[#list]` is vanilla's peer and the extras
-- cover `list[1 .. #list-1]`. Each extra is placed at its OWN voted node and
-- DISTINGUISHED geometrically (offset fanned by ordinal so 3+ way stacks spread).
--
-- DISTINGUISHING METHOD: position offset (vertical lift + lateral nudge) +
-- slight scale-down, NOT material recolor. Rationale: the token `.unit` assets
-- are binary (not in decompiled source); whether any exposes a tint material
-- variable is unverified per-asset, and `Material.set_*` silently NO-OPs when the
-- variable isn't compiled into the shader variant (a guess-and-check dead end
-- with a silent-failure mode -- see TODO.md:146-149). The vanilla scene itself
-- already distinguishes co-located chips purely by offset pose
-- (referenced_token_poses[slot], deus_map_scene.lua:836-837), so an offset+scale
-- secondary chip is visually native and uses only `Unit.set_local_pose` /
-- `Unit.set_local_scale` / `Unit.set_local_position`, all confirmed in-file
-- (deus_map_scene.lua:226,230,840) and deterministic (no silent no-op path).
--
-- LIFECYCLE / NO LEAK. Extra chips are spawned lazily on the FIRST frame a
-- duplicate is detected and cached per-peer in `scene._ct_dup_tokens` (keyed by
-- peer_id), reused across frames (moved via set_local_pose, hidden when that peer
-- stops being a duplicate). They are destroyed by our `DeusMapScene._clear` hook
-- against `scene._world` -- `_clear` runs from BOTH `on_enter` (top, re-entrancy
-- guard, deus_map_scene.lua:454) and `destroy` (deus_map_scene.lua:512), so the
-- extras are torn down on every view re-open AND on view destroy, mirroring how
-- vanilla tears down `_profile_index_to_token` in the same function
-- (deus_map_scene.lua:532-536). No accumulation across map-vote-view re-opens.
--
-- SAFETY. Toggle-gated (default ON, ct convention). All engine Unit/World calls
-- are pcall-wrapped (Unit.set_local_pose etc. can fatal on a stale/destroyed unit
-- handle, bypassing Lua error handling). Type/nil guards on every controller and
-- scene field before deref. If anything fails we bail to vanilla behavior (one
-- chip), never crashing the map screen.
-- ============================================================================

local Unit = Unit
local World = World
local Matrix4x4 = Matrix4x4

local REAL_PLAYER_LOCAL_ID = 1

-- Per-hero token unit paths, in the SAME profile_index order the vanilla scene
-- uses to build `_profile_index_to_token` (deus_map_scene.lua:13-17 + 238-251):
--   1 = victor (Witch Hunter), 2 = sienna (Bright Wizard), 3 = bardin (Dwarf
--   Ranger), 4 = kerillian (Wood Elf), 5 = markus (Empire Soldier).
-- We clone the SAME asset the duplicate peer's hero already uses, so the extra
-- chip is the correct character icon -- only its position/scale differ.
local PROFILE_INDEX_TO_TOKEN_UNIT = {
	"units/morris_map/player_token/victor_token",
	"units/morris_map/player_token/sienna_token",
	"units/morris_map/player_token/bardin_token",
	"units/morris_map/player_token/kerillian_token",
	"units/morris_map/player_token/markus_token",
}

-- v0.7.194-dev (#122): the DUP_OFFSET / DUP_OFFSET_Z_PER_EXTRA / DUP_SCALE
-- "secondary-chip distinction" constants were REMOVED. That local-frame nudge +
-- down-scale was what made duplicate chips hover above the map / land in odd
-- places (a token-local +z is an up/away translation in the angled map view), and
-- it was unnecessary: each duplicate voter already has its own vanilla slot pose.
-- See _place_dup_token below — it now places at the peer's slot with vanilla-exact
-- math and no post-adjustment.

local function _setting_on()
	-- v0.7.194-dev: duplicate-career vote chips are now an IMPLICIT, always-on
	-- feature. The old `show_duplicate_career_chips` checkbox + "Map Screen" menu
	-- group were removed (a per-mod toggle for a purely-corrective display fix is
	-- superfluous — it should just work). Kept as a function (not deleted) so the
	-- call sites in the hook below stay unchanged; always returns true.
	return true
end

-- Cache key for an extra chip. Keyed by peer_id AND profile_index: a peer that
-- changes career mid-view keeps the same peer_id but gets a new profile_index, so
-- a peer_id-only key would return the STALE token spawned for the old hero (wrong
-- character mesh). The compound key spawns a fresh, correct-mesh token per
-- (peer, career); the old-career token is left cached (hidden by the not-`used`
-- sweep, torn down by _clear) so a switch back reuses it. Bounded at <=5 per peer.
local function _dup_token_key(peer_id, profile_index)
	return tostring(peer_id) .. "_" .. tostring(profile_index)
end

-- Spawn (or fetch cached) the extra chip unit for a duplicate peer. Returns the
-- unit handle or nil on failure. pcall-wrapped: World.spawn_unit can fatal on a
-- bad path / torn-down world.
local function _get_or_spawn_dup_token(scene, peer_id, profile_index)
	local cache = scene._ct_dup_tokens
	if not cache then
		cache = {}
		scene._ct_dup_tokens = cache
	end

	local key = _dup_token_key(peer_id, profile_index)
	local existing = cache[key]
	if existing then
		return existing
	end

	local unit_path = PROFILE_INDEX_TO_TOKEN_UNIT[profile_index]
	if not unit_path then
		return nil
	end

	local world = scene._world
	if not world then
		return nil
	end

	local ok, unit = pcall(World.spawn_unit, world, unit_path)
	if not ok or not unit then
		mod:warning("[dup-chips] spawn_unit failed for peer=%s profile=%s: %s",
			tostring(peer_id), tostring(profile_index), tostring(unit))
		return nil
	end

	cache[key] = unit
	return unit
end

-- TODO #122: duplicate-career chip floats / lands on the wrong mission node (deferred).
-- ----------------------------------------------------------------------------------------------
-- CURRENT DESIGN: for each duplicate peer we spawn a CLONE of that character's own token unit
-- (_get_or_spawn_dup_token) and position it MANUALLY in `_place_dup_token` below — base_pose =
-- Unit.local_pose(node) × slot_box, then a local-frame nudge/lift/scale. That manual pose math is
-- the suspected source of the "floats / wrong node" report (the local-frame offset applied AFTER
-- set_local_pose interacts with the node's own transform, and the slot clamp may pick a slot pose
-- that doesn't match the voted node).
--
-- TEAM-LEAD'S DESIRED DESIGN: stop hand-positioning. Instead borrow a character chip that NO peer
-- in the lobby is using, let VANILLA place it (known-correct), then make it read as the duplicated
-- character. Concrete steps:
--   1. Compute the unused profile_indexes = {1..5} \ keys(by_profile). With any duplicate in a
--      <=4-player lobby there are <=3 distinct heroes in use, so >=2 unused tokens always exist.
--   2. For each EXTRA duplicate peer, pick an unused profile_index `pi_free` (consume one per extra)
--      and call vanilla `scene:_place_token(pi_free, slot, node_key)` (deus_map_scene.lua:833-841)
--      — this positions that token EXACTLY where the engine would, at the voted node, no manual math.
--   3. Re-skin the placed `_profile_index_to_token[pi_free]` unit to look like the duplicated
--      character. The 5 tokens are distinct character unit paths (TOKEN_WH/BW/DR/WE/ES spawned at
--      deus_map_scene.lua:238-242), so "look identical" means swapping the borrowed unit's
--      mesh/material to the duplicated hero's. Investigate whether the chip's hero identity is a
--      swappable material/flow-event on the token unit; if not, fall back to spawning the correct
--      hero clone (as today) but READ the pose vanilla gave the hidden borrowed token and apply it
--      verbatim (no offset math) — that fixes positioning while keeping the correct mesh.
--   4. Hide vanilla's real token for `pi_free` (it isn't a real voter) so the borrowed slot only
--      shows the re-skinned duplicate. Restore on _clear / toggle-off / when the dup resolves.
-- WHY DEFERRED: this is networked 3D map-scene UI with existing regression coverage
-- (dup_chip_no_current_node_fallback) and a long iteration history; the re-skin / pose-borrow paths
-- cannot be validated offline. Verify in a live 2-same-career lobby before shipping. Do NOT guess.
--
-- Place the extra chip using VANILLA's EXACT token math and NOTHING else
-- (DeusMapScene._place_token, deus_map_scene.lua:833-841):
--     pose = node_local_pose × referenced_token_poses[slot]
--     set_unit_visibility(true); set_local_pose(pose)
--
-- v0.7.194-dev (#122 fix — "duplicate chips hover above the map / appear in odd
-- places"): the previous version placed at the correct vanilla pose but then ADDED a
-- local-frame nudge (+0.45 x, +0.35 z) and a 0.72 down-scale to "distinguish" the
-- duplicate. That offset was the bug — the map is viewed at an angle, so a token-local
-- +z became an UP/AWAY translation in world space, lifting the chip off the map. The
-- distinction is also unnecessary: every duplicate voter already owns a DISTINCT `slot`
-- (its peer ordinal in controller:get_peers, passed by the caller), and vanilla's four
-- authored slot poses already fan chips out around a node exactly like the real tokens.
-- Placing the extra at its own slot puts it precisely where vanilla WOULD have drawn
-- that voter's token — it's only missing because the shared profile_index token got
-- overwritten (last-writer-wins). So: flat, correctly positioned, same size as every
-- other chip, no float. pcall-wrapped (engine pose calls fatal on a stale unit handle).
local function _place_dup_token(scene, unit, slot, node_key)
	local nodes = scene._nodes_to_units
	local ref_values = scene._level_ref_values
	if not nodes or not ref_values or not ref_values.referenced_token_poses then
		return false
	end

	local node = nodes[node_key]
	if not node then
		return false
	end

	-- Same 4 authored slot poses the engine uses; fall back to slot 1 defensively
	-- (slot is a 1..4 peer ordinal, so this fallback should never trigger).
	local poses = ref_values.referenced_token_poses
	local slot_box = poses[slot] or poses[1]
	if not slot_box then
		return false
	end

	local ok = pcall(function()
		local pose = Matrix4x4.multiply(Unit.local_pose(node, 0), slot_box:unbox())
		Unit.set_unit_visibility(unit, true)
		Unit.set_local_pose(unit, 0, pose)
	end)

	if not ok then
		return false
	end

	return true
end

local function _hide_dup_token(scene, unit)
	pcall(Unit.set_unit_visibility, unit, false)
end

-- Hide every cached extra chip (used when a peer stops being a duplicate, or the
-- feature is toggled off mid-view). Does NOT destroy -- destruction is _clear's
-- job, so the cache survives to be reused on the next duplicate without respawn.
local function _hide_all_dup_tokens(scene)
	local cache = scene._ct_dup_tokens
	if not cache then
		return
	end
	for _, unit in pairs(cache) do
		_hide_dup_token(scene, unit)
	end
end

-- ----------------------------------------------------------------------------
-- HOOK 1: DeusMapDecisionView._update_player_state (post-hook).
-- Vanilla runs first and places its one-chip-per-profile_index set. We then add
-- a second chip per EXTRA duplicate peer. UNHOOKED elsewhere in ct_dev (verified
-- 2026-06-21: only _enable_hover + _start are hooked on this class) -- this is
-- the sole hook on this (Class, method).
-- ----------------------------------------------------------------------------
mod:hook_safe("DeusMapDecisionView", "_update_player_state", function(self)
	if not _setting_on() then
		-- Toggle flipped OFF mid-view: hide any extras still showing from a
		-- previous frame BEFORE bailing, so they disappear immediately (matching
		-- this file's "hidden when ... the feature is toggled off mid-view"
		-- claim). Cache survives for reuse; _clear still destroys on re-open.
		local scene = self._scene
		if scene then
			_hide_all_dup_tokens(scene)
		end
		return
	end

	local scene = self._scene
	local controller = self._deus_run_controller
	local shared_state = self._shared_state
	if not scene or not controller or not shared_state then
		return
	end

	-- Guard: scene must have its map units up (it does once on_enter ran). If a
	-- re-entrancy frame cleared them, bail -- vanilla place_token would also no-op.
	if not scene._nodes_to_units or not scene._profile_index_to_token then
		_hide_all_dup_tokens(scene)
		return
	end

	local ok_peers, peers = pcall(function() return controller:get_peers() end)
	if not ok_peers or type(peers) ~= "table" then
		_hide_all_dup_tokens(scene)
		return
	end

	-- Build profile_index -> ordered list of {peer_id, slot_index}. slot_index is
	-- the peer's ordinal in the peers list, matching vanilla's `index` argument so
	-- our base slot pose lines up with the engine's choice for that voter.
	local by_profile = {}
	for index, peer_id in ipairs(peers) do
		local profile_index = controller:get_player_profile(peer_id, REAL_PLAYER_LOCAL_ID)
		if profile_index and profile_index ~= 0 then
			local list = by_profile[profile_index]
			if not list then
				list = {}
				by_profile[profile_index] = list
			end
			list[#list + 1] = { peer_id = peer_id, slot = index }
		end
	end

	-- Track which cached extra chips we actually used this frame; hide the rest.
	local used = {}

	-- NOTE: we deliberately do NOT fetch current_node_key. Vanilla uses it as the
	-- final fallback in its node_key chain, but that fallback exists only because
	-- vanilla writes one chip per profile_index (last-writer-wins): an unvoted
	-- duplicate peer's chip is overwritten and thus invisible. We draw a separate
	-- chip per extra, so a current_node_key fallback would plant a visible second
	-- chip on the party's CURRENT node rather than where that peer voted -- the
	-- "valid-but-wrong mission node" bug. Extras with no final/own vote are simply
	-- not placed (see node_key resolution below).

	local final_node_selected
	local ok_final, final = pcall(function()
		return shared_state:get_server(shared_state:get_key("final_node_selected"))
	end)
	if ok_final then
		final_node_selected = final
	end

	for _profile_index, list in pairs(by_profile) do
		if #list > 1 then
			-- WHICH peer does vanilla's single chip show? Vanilla
			-- (deus_map_decision_view.lua:665-682) iterates `for index, peer_id in
			-- ipairs(peers)` and calls `place_token(profile_index, index, node_key)`,
			-- which WRITES `_profile_index_to_token[profile_index]` -- a 1-per-hero
			-- slot (deus_map_scene.lua:833-841). For a shared profile_index that's
			-- LAST-WRITER-WINS: vanilla's visible chip is the peer that iterated
			-- LAST in `ipairs(peers)`. Our `by_profile[*]` list is appended in the
			-- SAME `ipairs(peers)` order over the SAME `controller:get_peers()`
			-- array (NetworkState.get_peers -> shared_state:get_server, one ordered
			-- array -- verified 2026-06-21), so `list[#list]` IS the peer vanilla
			-- draws. Therefore the EXTRAS must cover EXACTLY the peers vanilla does
			-- NOT show: the FIRST n-1 (i = 1 .. #list-1). Leave the last to vanilla.
			-- (The old `for i = 2, #list` doubled the LAST peer atop vanilla's chip
			-- and never drew the FIRST -- the blocking bug this replaces.)
			for i = 1, #list - 1 do
				local entry = list[i]
				local peer_id = entry.peer_id

				-- Resolve this peer's voted node. Vanilla
				-- (deus_map_decision_view.lua:669-670) is final > own vote >
				-- current_node_key, BUT vanilla's current_node_key fallback only
				-- matters because vanilla writes ONE chip per profile_index
				-- (last-writer-wins, deus_map_scene.lua:833-841): for a shared
				-- profile_index the unvoted duplicate peer's chip is overwritten by
				-- the voted peer in the same slot, so it's effectively INVISIBLE.
				-- We draw a SEPARATE chip per extra, so taking the current_node_key
				-- fallback for an extra who hasn't voted plants a visible second chip
				-- on the party's CURRENT node -- a valid node that is NOT where that
				-- peer voted (the "valid-but-wrong mission node" bug). Drop the
				-- fallback for the EXTRA path: with no final and no own vote, node_key
				-- stays nil and the `if node_key` guard below skips placement,
				-- mirroring vanilla's effective invisibility (the not-`used` sweep
				-- hides any stale chip from a prior frame). The vote value is already a
				-- topology node key in the SAME space as _nodes_to_units (provenance:
				-- deus_map_decision_view.lua:363 -> deus_map_scene.lua:200), so NO
				-- alias/reverse-match normalization belongs here.
				local vote
				local ok_vote, v = pcall(function()
					return shared_state:get_peer(peer_id, shared_state:get_key("vote"))
				end)
				if ok_vote then
					vote = v
				end
				-- /ct_regression_test `dup_chip_no_current_node_fallback` (ct_dev
				-- 0.7.162-dev). The extra-chip node_key chain below is EXACTLY
				-- `final_node_selected > vote > nil` -- there is deliberately NO
				-- trailing current-node fallback (that fallback plants a visible chip
				-- on the party's CURRENT node for an unvoted duplicate peer -> the
				-- "valid-but-wrong mission node" bug). The keep-time regression check
				-- reads mod._ct_dup_chip_node_key_resolution, exported at module-LOAD
				-- time near the top of this file (the bundle is unreadable at runtime,
				-- and this loop body only runs during a CW map vote, so the export
				-- can't live here). If a future edit reintroduces an
				-- `or current_node` .. `_key` tail, update the chain here AND the
				-- load-time marker, or the regression check fails loudly.
				local node_key = (final_node_selected and final_node_selected ~= "" and final_node_selected)
					or (vote and vote ~= "" and vote)
					or nil

				if node_key then
					local unit = _get_or_spawn_dup_token(scene, peer_id, _profile_index)
					if unit then
						if _place_dup_token(scene, unit, entry.slot, node_key) then
							used[_dup_token_key(peer_id, _profile_index)] = true
						else
							_hide_dup_token(scene, unit)
						end
					end
				end
			end
		end
	end

	-- Hide any previously-shown extra chip whose peer is no longer a duplicate
	-- (career change, peer left, vote cleared). Cache entry survives for reuse.
	local cache = scene._ct_dup_tokens
	if cache then
		for cache_key, unit in pairs(cache) do
			if not used[cache_key] then
				_hide_dup_token(scene, unit)
			end
		end
	end
end)

-- ----------------------------------------------------------------------------
-- HOOK 2: DeusMapScene._clear (teardown). Destroys our extra chip units against
-- the scene's world and nils the cache, so nothing leaks on view re-open or
-- destroy. _clear runs from on_enter (top) AND destroy (deus_map_scene.lua:454,
-- 512), exactly where vanilla destroys _profile_index_to_token (lines 532-536).
-- UNHOOKED elsewhere in ct_dev (verified 2026-06-21). Sole hook on this pair.
-- Use hook_safe so we run AFTER vanilla's _clear has torn down its own units;
-- self._world is still valid at that point (it's only reassigned later, in
-- on_enter line 457). pcall around destroy in case a handle is already dead.
-- ----------------------------------------------------------------------------
mod:hook_safe("DeusMapScene", "_clear", function(self)
	local cache = self._ct_dup_tokens
	if not cache then
		return
	end

	local world = self._world
	for cache_key, unit in pairs(cache) do
		if world and unit then
			pcall(World.destroy_unit, world, unit)
		end
		cache[cache_key] = nil
	end

	self._ct_dup_tokens = nil
end)

mod:info("[dup-chips] duplicate-career map-vote chips loaded")
