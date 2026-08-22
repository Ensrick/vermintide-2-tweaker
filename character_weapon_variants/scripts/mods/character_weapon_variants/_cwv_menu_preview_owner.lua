-- _cwv_menu_preview_owner.lua
-- CWV keep/menu preview-surface owner (#1159).
--
-- Owns every MENU-side reconstruction of a CWV variant: the surfaces that
-- rebuild a variant's visual outside the live gameplay world, plus the picker
-- list that decides which illusions such a rebuild may show.
--   * the previewer definition resolver - `_find_preview_slot_info`,
--     `_crowbill_def_from_spawn_data`, `_resolve_preview_def` - and the shared
--     post-spawn applier `_cwv_spawn_item_post` behind BOTH HeroPreviewer and
--     MenuWorldPreviewer `_spawn_item`: the #482 bid ladder rung the previewer
--     needs (its info table carries no item_data), the string-slot_type ->
--     numeric-slot_index KEY BRIDGE, the #760 Outrider stance replay, the
--     per-hand transforms selected through the shared #482 consumer contract,
--     the #604 Crowbill presentation with its
--     TeamPreviewer identity diagnostic, and the #474/#617/#792 Old Musket
--     stance + texture + armed-pose branch;
--   * the #604 TeamPreviewer identity bridge `_om._crowbill_team_peer` and the
--     `TeamPreviewer._spawn_hero` hook that stamps lobby/score wearer identity
--     onto the hero previewer the applier above then reads;
--   * the cosmetic picker's cwv-only illusion filter (`_is_cwv_item` +
--     `HeroWindowItemCustomization._setup_illusions`) with its layout recompute;
--   * the two preview teardown edges (`HeroPreviewer._destroy_item_units_by_slot`
--     and `LootItemUnitPreviewer._destroy_units`) that forget Crowbill transform
--     state at the source-backed destruction point rather than by weak-key luck;
--   * CIM's public `cim_preview_context_v1` marker, which identifies the exact
--     returned Athanor previewer across Weapons, Properties and Overview so the
--     shared LootItemUnitPreviewer consumer can distinguish it from an ordinary
--     illusion browser;
--   * the illusion browser / Athanor craft pane (`LootItemUnitPreviewer.spawn_units`):
--     the #597 mod-unit fallback pre-pass, the issue 419 browser mesh-swap
--     pre-pass, the def ladder, the unit transforms and the #617 Old Musket
--     authored-material bind.
-- Originally extracted from the entry file. This owner now also contains the
-- hardened #1155 exact preview identity, attachment-recipe, fallback, and
-- stable-edge behavior; hook ownership and relative registration order remain
-- unchanged.
--
-- BOUNDARY - this owner is the MENU third of CWV's three presentation surfaces:
--   * WORLD/BOT equipment stays in the entry's `GearUtils.create_equipment`
--     hook, immediately above this module's load point. It keeps its own
--     `_crowbill_transform_miss_seen` / `_crowbill_transform_miss_total`
--     evidence counters, which nothing in here reads.
--   * REMOTE (husk) display stays in the husk-path module and its entry-side
--     spawn adapters.
--   * `_resolve_cwv_def`, `_find_def` and the transform maps themselves are
--     shared producers, not menu surface, so none of them moved here. `_find_def`
--     stays in the entry; the resolver and the maps were subsequently gathered
--     into _cwv_weapon_transform_owner.lua by the #1159 weapon-transform slice.
--     That owner now publishes the #482 transform-consumer contract used here;
--     menu surfaces no longer maintain private identity/transform ladders.
-- The five moved file-scope helpers each had ZERO references outside the moved
-- range before the move (proved with the block-depth scope probe over the
-- pristine entry), so nothing in the entry can reach in here any more.
--
-- Registers exactly eight hooks, each the mod's SOLE registration on its
-- (Class, method) pair: TeamPreviewer._spawn_hero,
-- HeroWindowItemCustomization._setup_illusions, HeroPreviewer._spawn_item,
-- MenuWorldPreviewer._spawn_item, HeroPreviewer._destroy_item_units_by_slot,
-- LootItemUnitPreviewer._destroy_units, LootItemUnitPreviewer.spawn_units and
-- LootItemUnitPreviewer._enable_item_units_visibility.
-- VMF silently DROPS a duplicate registration on a pair, so re-adding any of
-- these to the entry would shadow this owner rather than chain with it.
-- `_om.old_musket_preview_pose.install(...)` below is a CALL into a module the
-- entry already loaded, not another inline registration in this owner.
--
-- Load-time deps: only the ctx table plus the `_om` slots the entry populates
-- in its module block (`_om.old_musket_preview_pose` is the sole one read at
-- load; everything else is read inside a hook body). The owner loads at the
-- exact point the moved block ran, so those slots are as populated as before.
--
-- ctx bindings are all BY VALUE, which is sound because every one of them is
-- declared once at entry file scope, before this load point, and never
-- rebound - verified with the same scope probe, so no late-binding accessor is
-- needed. The two maps are mutated in place after this point; passing the
-- table reference preserves that, as it did when the block was inline:
--   om, dbg, dbg_alert                      entry lines 55 / 269 / 273
--   resolve_field, skin_transform_map        entry lines 4357 / 4364
--   crowbill_transform_by_unit, is_unit     entry lines 4452 / 4556
--   transform_unit, apply_cwv_hand_transform  entry lines 4662 / 4700
--
-- No native resource boundary moved with this block: it contains no
-- World.create_particles / create_screen_gui / Material.set_texture /
-- Unit.set_texture_for_materials / Managers.package call, so it needs no
-- `-- resource-safety:` marker. The Old Musket texture work it triggers is
-- owned (and annotated) by _cwv_old_musket_preview.lua, which this file only
-- calls through `_om.old_musket_appearance.reconcile`.
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating
-- the moved block as file-scope code: an anonymous `function(` wrapper makes
-- every construct-then-call pair below read as a closure capturing its own
-- body. See the same note in _cwv_musket_runtime.lua.
local function install(mod, ctx)
local _om = ctx.om
local _dbg = ctx.dbg
local _dbg_alert = ctx.dbg_alert
local _resolve_field = ctx.resolve_field
local _is_unit = ctx.is_unit
local _transform_unit = ctx.transform_unit
local _apply_cwv_hand_transform = ctx.apply_cwv_hand_transform
local _skin_transform_map = ctx.skin_transform_map
local _crowbill_transform_by_unit = ctx.crowbill_transform_by_unit
local _get_mod = ctx.get_mod or get_mod
local _transform_consumers = assert(_om._cwv_transform_consumers,
	"cwv menu preview owner requires transform consumer contract")

-- #1155: LootItemUnitPreviewer is shared by ordinary illusion browsers and
-- CIM's Athanor. Consume CIM's public exact-instance contract rather than
-- maintaining a second constructor hook that covered only Properties and went
-- stale when the failing screen was ForgeWeapons. Generic previewers deliberately
-- resolve to illusion_browser; malformed/foreign context fails closed.
local function _preview_backend_id(item)
	local data = type(item) == "table" and item.data or nil
	local bid = type(item) == "table" and (item.backend_id or item.ItemInstanceId
		or (data and (data.backend_id or data.ItemInstanceId))) or nil
	return type(bid) == "string" and bid ~= "" and #bid <= 128 and bid or nil
end

local function _cwv_cim_preview_context(previewer)
	if type(previewer) ~= "table" or type(_get_mod) ~= "function" then
		return nil, "absent"
	end
	local has_marker = rawget(previewer, "_cim_preview_context") ~= nil
	local ok_mod, provider = pcall(_get_mod, "cim_dev")
	local accessor = ok_mod and provider and provider._cim_preview_context_for
	if type(accessor) ~= "function" then
		return nil, has_marker and "provider_unavailable" or "absent"
	end
	local ok_context, context = pcall(accessor, previewer)
	if not ok_context or type(context) ~= "table"
			or context.contract ~= "cim_preview_context_v1"
			or context.surface ~= "cim_preview"
			or context.provider ~= "cim_dev"
			or type(context.generation) ~= "number" or context.generation <= 0
			or context.generation ~= context.generation
			or context.generation == math.huge
			or context.generation % 1 ~= 0
			or context.exact_backend_identity ~= true
			or type(context.backend_id) ~= "string" or context.backend_id == ""
			or #context.backend_id > 128
			or (context.constructor ~= "overview"
				and context.constructor ~= "weapons"
				and context.constructor ~= "properties") then
		return nil, has_marker and "context_invalid" or "absent"
	end
	local item_bid = _preview_backend_id(previewer._item)
	if item_bid == nil or item_bid ~= context.backend_id then
		return nil, "identity_mismatch"
	end
	return context, "ready"
end
_om._cwv_cim_preview_context = _cwv_cim_preview_context
local function _cwv_loot_preview_surface(previewer)
	local context, reason = _cwv_cim_preview_context(previewer)
	return (context or reason ~= "absent") and "cim_preview" or "illusion_browser"
end
_om._cwv_loot_preview_surface = _cwv_loot_preview_surface

local function _find_preview_slot_info(self, item_name, spawn_data)
	if not self._item_info_by_slot then return nil, nil end
	if spawn_data then
		local exact_slot, exact = _om.old_musket_preview_pose.resolve_spawn_slot(
			self, item_name, spawn_data)
		if exact_slot then return exact_slot, exact end
		return nil, nil
	end
	for slot_id, info in pairs(self._item_info_by_slot) do
		if info and info.name == item_name then
			return slot_id, info
		end
	end
	return nil, nil
end

local function _crowbill_def_from_spawn_data(spawn_data)
	for _, row in ipairs(spawn_data or {}) do
		local unit_name = row and (row.unit_name or row.right_hand_unit)
		local def = unit_name and _crowbill_transform_by_unit[unit_name]
		if def then return def, unit_name end
	end
	return nil, nil
end

local function _resolve_preview_def(self, item_name, spawn_data)
	local slot_type, info = _find_preview_slot_info(self, item_name, spawn_data)
	local model_def = info and _crowbill_def_from_spawn_data(info.spawn_data)
	return _transform_consumers.preview(item_name, info, model_def), info, slot_type
end
_om._cwv_preview_transform_decision = _resolve_preview_def

local function _old_musket_preview_stance(info)
	local team_mode = info and info.cwv_team_musket_mode
	if team_mode == "melee" or team_mode == "ranged" then return team_mode end
	local item_data = info and info.item_data
	if item_data and item_data.mod_data
			and item_data.mod_data.cwv_musket_stance == "melee" then
		return "melee"
	end
	local cached = info and info.backend_id and _om._old_musket_modes_by_backend
		and _om._old_musket_modes_by_backend[info.backend_id]
	return cached == "melee" and "melee" or "ranged"
end

local function _old_musket_attachment_recipes()
	local rifle_template = Weapons and Weapons.old_musket_template
	local polearm_template = Weapons and Weapons.old_musket_template_melee
	local rifle = rifle_template and rifle_template.right_hand_attachment_node_linking
		and rifle_template.right_hand_attachment_node_linking.third_person
	local polearm = polearm_template and polearm_template.right_hand_attachment_node_linking
		and polearm_template.right_hand_attachment_node_linking.third_person
	return rifle, polearm
end

local function _old_musket_character_profile(row, stance)
	local rifle, polearm = _old_musket_attachment_recipes()
	return _om.old_musket_preview_pose.resolve_character_attachment_profile(
		row, stance, rifle, polearm, _om.old_musket_attachment_profiles)
end

-- HeroPreviewer._spawn_item reads each row's attachment recipe before it links
-- the unit (world_hero_previewer.lua:895-914). The item name still resolves the
-- inherited handgun template, so a cached melee stance otherwise spawns the
-- custom Musket on the rifle parent and no later transform can repair that
-- frame mismatch. Rewrite only the exact custom right-hand row, before vanilla
-- consumes it, to the immutable registered stance template's 3P recipe.
local function _prepare_old_musket_character_attachment(self, item_name, spawn_data)
	-- TeamPreviewer-backed lobby/score surfaces are deliberately outside this
	-- pilot. They do not carry a source-qualified Old Musket slot/stance, so a
	-- custom mesh here would be an unposed, unverified reconstruction. Convert
	-- only exact authored Old Musket rows back to the resident vanilla Handgun
	-- and stamp the shared terminal fallback marker before vanilla reads them.
	if self and self._cwv_team_preview then
		local marker = _om.mod_unit_preview and _om.mod_unit_preview.FALLBACK_MARKER
			or "_cwv_mod_unit_preview_fallback_v1"
		local replaced = false
		for _, row in ipairs(spawn_data or {}) do
			if type(row) == "table" then
				local fallback
				if row.unit_name == _om.old_musket_preview.UNIT_3P then
					fallback = _om.old_musket_preview.NETWORK_PACKAGE_ALIAS_3P
				elseif row.unit_name == _om.old_musket_preview.UNIT then
					fallback = _om.old_musket_preview.NETWORK_PACKAGE_ALIAS_1P
				end
				if type(fallback) == "string" and fallback ~= "" then
					row.unit_name = fallback
					row[marker] = fallback
					replaced = true
				end
			end
		end
		return not replaced
	end
	local def, info, slot_type = _om._cwv_preview_transform_decision(
		self, item_name, spawn_data)
	if not def or def.item_key ~= "cwv_es_musket_old" then return true end
	local row, reason = _om.old_musket_preview_pose.resolve_right_hand_spawn_row(
		info, slot_type, _om.old_musket_preview.UNIT_3P)
	if not row then
		_dbg_alert("[cwv:1155] Old Musket attachment prepare rejected reason=%s",
			tostring(reason))
		return false
	end
	local stance = _old_musket_preview_stance(info)
	local rifle, polearm = _old_musket_attachment_recipes()
	local desired = stance == "melee" and polearm or rifle
	if type(desired) ~= "table" then
		_dbg_alert("[cwv:1155] Old Musket attachment prepare rejected reason=attachment_recipe_missing stance=%s",
			tostring(stance))
		return false
	end
	-- Validate the immutable registered recipe and profile vocabulary before
	-- touching the live spawn row. HeroPreviewer consumes this table inside the
	-- vanilla call below, so a rejected preparation must leave its exact raw
	-- shape intact rather than feeding vanilla a half-accepted CWV parent frame.
	local candidate = { unit_attachment_node_linking = desired }
	local profile, profile_reason = _old_musket_character_profile(candidate, stance)
	if not profile then
		_dbg_alert("[cwv:1155] Old Musket attachment prepare rejected reason=%s stance=%s",
			tostring(profile_reason), tostring(stance))
		return false
	end
	row.unit_attachment_node_linking = desired
	return true
end

local function _cwv_spawn_item_post(self, item_name, spawn_data)
	local def, info, slot_type = _om._cwv_preview_transform_decision(
		self, item_name, spawn_data)
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
	-- read it from there to bridge the two keying conventions. Old Musket is the
	-- strict exception below: it selects the exact custom right-hand row because
	-- dual-hand spawn data is authored left-then-right.
	-- The previous implementation had a "fall back: match by item_name"
	-- loop that iterated `self._item_info_by_slot` and stored the iterator
	-- key — that key is the STRING slot_type, which is exactly the wrong
	-- thing to look up `equip_units` with. Don't reintroduce.
	-- #1155: retain the exact custom right-hand unit that this generation
	-- spawned. A base-handgun path, missing/malformed row, duplicate right-hand
	-- row, or slot mismatch is terminal; none may reach material/pose replay.
	local old_musket_spawn_row, old_musket_attachment_profile
	if def.item_key == "cwv_es_musket_old" then
		local row, reason = _om.old_musket_preview_pose.resolve_right_hand_spawn_row(
			info, slot_type, _om.old_musket_preview.UNIT_3P)
		if not row then
			_dbg_alert("[cwv:1155] Old Musket preview spawn rejected reason=%s",
				tostring(reason))
			return
		end
		old_musket_spawn_row = row
		local stance = _old_musket_preview_stance(info)
		if slot_type ~= self._wielded_slot_type then
			_dbg("[cwv:1155] Old Musket preview attachment skipped reason=not_wielded slot=%s active=%s",
				tostring(slot_type), tostring(self._wielded_slot_type))
			return
		end
		local profile, profile_reason = _old_musket_character_profile(row, stance)
		if not profile then
			_dbg_alert("[cwv:1155] Old Musket preview attachment rejected reason=%s stance=%s",
				tostring(profile_reason), tostring(stance))
			return
		end
		old_musket_attachment_profile = profile
	end
	local slot_index = old_musket_spawn_row and old_musket_spawn_row.slot_index
		or (info and info.spawn_data and info.spawn_data[1]
			and info.spawn_data[1].slot_index)
	if not slot_index then return end

	local slot = equip_units[slot_index]
	if type(slot) ~= "table" then return end

	-- #760: the previewer resolves the inherited BASE Trollhammer template, so
	-- mutating that table would also change the real Trollhammer on Saltzpyre.
	-- Replay one exact item+career stance after the item-specific preview spawn.
	-- This is reconstruction-bound (not per-frame) and leaves Kruber untouched.
	local preview_wield, preview_reason = _om.outrider_animation.runtime_event(
		def.item_key, self._current_career_name,
		NetworkLookup and NetworkLookup.anims)
	if preview_wield then
		local _, result = _om.outrider_animation.dispatch_event(
			self.character_unit, preview_wield, Unit)
		_om.outrider_animation.emit_evidence(printf, "inventory_preview",
			self._current_career_name, preview_wield, result, "exact_item")
	elseif preview_reason then
		_om.outrider_animation.emit_evidence(printf, "inventory_preview",
			self._current_career_name,
			_om.outrider_animation.SALTZPYRE_WIELD_3P,
			"skip_" .. tostring(preview_reason), "exact_item")
	end

	-- Preview spawns 3P-style models; use _3p override if set, else unified.
	if slot.right and _is_unit(slot.right) then
		local _, preview_unit_name = _crowbill_def_from_spawn_data(info and info.spawn_data)
		_apply_cwv_hand_transform(slot.right, def, "right", "3p", "inventory_preview",
			preview_unit_name, info and info.skin_name)
	end
	if slot.left and _is_unit(slot.left) then
		_apply_cwv_hand_transform(slot.left, def, "left", "3p", "inventory_preview",
			nil, info and info.skin_name)
	end
	-- #604: MenuWorldPreviewer/HeroPreviewer is the shared reconstruction
	-- seam for inventory mannequin, keep/lobby, and score/team presentations.
	-- Applying here therefore covers all three consumers without surface-specific
	-- copies.  The mode cache is keyed by the real backend instance when present.
	if slot.right and _is_unit(slot.right) and def.crowbill_mode_family
			and _om._apply_crowbill_presentation then
		local preview_rotation = _resolve_field(def, "right_hand_rotation_3p")
			or _resolve_field(def, "right_hand_rotation")
		local team_peer = self._cwv_team_wearer_peer or self._cos_wearer_peer
		local team_identity = team_peer and _om.crowbill_runtime
			and _om.crowbill_runtime.identity_for_peer
			and _om.crowbill_runtime.identity_for_peer(team_peer, "slot_melee", def.item_key)
		local preview_identity = team_identity
			or _om._crowbill_render_identity(info and info.item_data, def,
				info and info.backend_id or def.item_key .. ":preview:" .. tostring(slot_index))
		local preview_surface = "inventory_preview"
		if self._cwv_team_preview then
			preview_surface = self._cwv_team_peer_source == "score_snapshot"
				and "score_preview" or "lobby_preview"
		end
		_om._apply_crowbill_presentation(slot.right, def, preview_identity,
			preview_surface, preview_rotation)
		-- Source audit: TeamPreviewer receives profile/career, while
		-- LevelEndView drops peer_id. The hook below restores the exact human
		-- peer from the immutable score snapshot (or live profile sync). If an
		-- unfamiliar TeamPreviewer producer lacks both, log once per row rather
		-- than silently claiming remote mode parity.
		if self._cwv_team_preview and not team_peer then
			_om.crowbill_preview_diag_seen = _om.crowbill_preview_diag_seen or {}
			_om.crowbill_preview_diag_count = _om.crowbill_preview_diag_count or 0
			local token = tostring(self._cwv_team_profile_index) .. ":"
				.. tostring(self._cwv_team_career_index) .. ":" .. tostring(def.item_key)
			if not _om.crowbill_preview_diag_seen[token]
					and _om.crowbill_preview_diag_count < 16 then
				_om.crowbill_preview_diag_seen[token] = true
				_om.crowbill_preview_diag_count = _om.crowbill_preview_diag_count + 1
				pcall(printf, "[cwv:604] TEAM-PREVIEW identity unresolved profile=%s career=%s family=%s evidence=%d/16 chat=false",
					tostring(self._cwv_team_profile_index),
					tostring(self._cwv_team_career_index), tostring(def.item_key),
					_om.crowbill_preview_diag_count)
			end
		end
	end

	-- v0.1.293: bind cwv_es_musket_old textures + track for live tuning in the
	-- character-preview UI. v0.1.318: pass the stance mode so 3P-MELEE
	-- transforms apply when the player has the musket in melee stance.
	-- Mode is read from item_data.mod_data.cwv_musket_stance.
	-- v0.1.326 originally added inline material diagnostics here. #617 now
	-- routes this preview through the same resource-gated per-unit painter as
	-- every other surface; direct shared Material writes are forbidden.
	if def.item_key == "cwv_es_musket_old" and slot.right and _is_unit(slot.right) then
		local _stance = _old_musket_preview_stance(info)
		local item_data = info and info.item_data
		_dbg("[cwv preview] firing for cwv_es_musket_old: unit=%s stance=%s", tostring(slot.right), _stance)
		-- Preview construction owns the first bounded authored-material bind. The
		-- loading_done transition below is the separate stable retry edge.
		local unit = slot.right
		local observed_unit_name = old_musket_spawn_row.unit_name
		local musket_surface = "inventory_preview"
		if self._cwv_team_preview then
			musket_surface = self._cwv_team_peer_source == "score_snapshot"
				and "score_team" or "lobby"
		end
		local appearance = _om.old_musket_appearance.reconcile(unit,
			musket_surface, "instance_load", item_data or {
				backend_id = info and info.backend_id,
				cwv_key = "cwv_es_musket_old",
			}, _stance, {
				unit_name = observed_unit_name,
				attachment_profile = old_musket_attachment_profile,
			})
		_dbg("[cwv preview] descriptor retained=%s reason=%s",
			tostring(appearance and appearance.retained == true),
			tostring(appearance and appearance.reason))
		-- Vanilla resolves preview animation from the inherited es_handgun name,
		-- so melee mode otherwise keeps the rifle idle even when the mesh pose is
		-- correct. #792: do not replay here. Vanilla can still trigger a delayed
		-- menu pose later in this post-update, overwriting this spawn-time event.
		-- Arm one compact record for the final `_loading_done` edge instead.
		local stance_template = _stance == "melee" and Weapons.old_musket_template_melee
			or Weapons.old_musket_template
		local wield_event = _om.old_musket_preview_pose.resolve_wield_event(
			stance_template, self._current_career_name)
		if wield_event and slot_type == self._wielded_slot_type
				and self.character_unit and Unit.alive(self.character_unit) then
			_om.old_musket_preview_pose.arm(self, {
				character_unit = self.character_unit,
				item_name = item_name,
				backend_id = info and info.backend_id,
				slot_type = slot_type,
				slot_index = slot_index,
				stance = _stance,
				surface = musket_surface,
				attachment_profile = old_musket_attachment_profile,
				attachment_node_linking = old_musket_spawn_row.unit_attachment_node_linking,
				unit_name = observed_unit_name,
				wield_event = wield_event,
			})
		end
	elseif def.item_key == "cwv_es_musket_old" then
		-- v0.1.341-dev: promoted to `_dbg_alert` — "gate failed" is an
		-- alert (CWV musket preview won't render correctly).
		_dbg_alert("[cwv preview] cwv_es_musket_old gate failed: slot.right=%s _is_unit=%s",
			tostring(slot and slot.right), tostring(slot and slot.right and _is_unit(slot.right)))
	end
end

_om.old_musket_preview_pose.install(mod, function(unit, _, mode, record)
	return _om.old_musket_appearance.reconcile(unit,
		record and record.surface or "inventory_preview", "preview_open", {
		backend_id = record and record.backend_id,
		cwv_key = "cwv_es_musket_old", skin = "cwv_es_musket_old_skin",
	}, mode, {
		unit_name = record and record.unit_name,
		attachment_profile = record and record.attachment_profile,
	})
end, printf, _dbg)

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
	local players = _om.peer_resolver.human_players(pm)
	if type(players) ~= "table" then return nil, "live_unavailable" end
	for _, player in pairs(players) do
		local local_id_ok, local_id = pcall(player.local_player_id, player)
		local pi, ci = _om.peer_resolver.profile_by_peer(psync, player.peer_id,
			local_id_ok and local_id or 1)
		if pi == profile_index and ci == career_index then
			return player.peer_id, "live_profile"
		end
	end
	return nil, "live_miss"
end

mod:hook("TeamPreviewer", "_spawn_hero", function(func, self, hero_previewer, hero_data)
	if hero_previewer and type(hero_data) == "table" then
		local ok, peer, source = pcall(_om._crowbill_team_peer,
			hero_data.profile_index, hero_data.career_index, self._context)
		hero_previewer._cwv_team_preview = true
		hero_previewer._cwv_team_profile_index = hero_data.profile_index
		hero_previewer._cwv_team_career_index = hero_data.career_index
		hero_previewer._cwv_team_wearer_peer = ok and peer or nil
		hero_previewer._cwv_team_peer_source = ok and source or "resolver_error"
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
	local prepared = _prepare_old_musket_character_attachment(self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	_dbg("[cwv preview hook] HeroPreviewer._spawn_item fired item_name=%s self=%s",
		tostring(item_name), tostring(self))
	if prepared then _cwv_spawn_item_post(self, item_name, spawn_data) end
	return result
end)

mod:hook("MenuWorldPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local prepared = _prepare_old_musket_character_attachment(self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	_dbg("[cwv preview hook] MenuWorldPreviewer._spawn_item fired item_name=%s self=%s",
		tostring(item_name), tostring(self))
	if prepared then _cwv_spawn_item_post(self, item_name, spawn_data) end
	return result
end)

-- Explicit preview teardown for #604. Weak-key pruning is only a fallback:
-- preview units can remain alive until their world is released, so forgetting
-- at the source-backed destruction edge prevents stale baseline/presentation
-- state from surviving a slot reconstruction.
mod:hook("HeroPreviewer", "_destroy_item_units_by_slot", function(func, self, slot_type)
	local info = self._item_info_by_slot and self._item_info_by_slot[slot_type]
	local equipment = self._equipment_units
	for _, row in ipairs(info and info.spawn_data or {}) do
		local slot = equipment and equipment[row.slot_index]
		if slot then
			if row.right_hand or row.despawn_both_hands_units then
				_om._cwv_forget_crowbill_transform_unit(slot.right, "hero_preview_slot_destroy")
			end
			if row.left_hand or row.despawn_both_hands_units then
				_om._cwv_forget_crowbill_transform_unit(slot.left, "hero_preview_slot_destroy")
			end
		end
	end
	return func(self, slot_type)
end)

mod:hook("LootItemUnitPreviewer", "_destroy_units", function(func, self)
	for _, unit in ipairs(self._spawned_units or {}) do
		_om._cwv_forget_crowbill_transform_unit(unit, "item_preview_destroy")
	end
	return func(self)
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
-- (#419) The wrapper body is a NAMED function, not an anonymous hook closure.
-- The regression that owns this issue has to prove ORDER -- that the mesh-swap
-- pre-pass rewrites the recipe BEFORE vanilla `spawn_units` reads it -- and the
-- only honest way to do that offline is to call the real wrapper with a spy in
-- place of vanilla. Calling the hooked method itself would run the engine's
-- World.spawn_unit. Naming the body makes the delivery contract executable:
-- deleting the pre-pass call below makes the spy observe base units and the
-- check fails, which the pure descriptor/adapter checks could not detect.
_om._cwv_browser_transform_decision = function(item, spawn_data)
	local item_data = item and item.data
	local weapon_key = (item_data and item_data.key) or (item and item.key)
	if not weapon_key then return nil, nil, nil, nil end
	local explicit_skin_def = _skin_transform_map[weapon_key]
	local model_def, preview_unit_name = _crowbill_def_from_spawn_data(spawn_data)
	local def, cwv_key = _transform_consumers.browser(
		item, weapon_key, model_def, explicit_skin_def)
	return def, cwv_key, preview_unit_name, weapon_key
end

local function _reconcile_old_musket_loot(self, units, spawn_data, edge)
	local item = self and self._item
	local descriptor = item and _om._old_musket_preview_descriptor(item)
	if not descriptor then return 0, 0 end
	local cim_context, cim_reason = _cwv_cim_preview_context(self)
	local surface = _cwv_loot_preview_surface(self)
	local preview_identity, preview_generation
	if surface == "illusion_browser" then
		-- LootItemUnitPreviewer owns one construction -> visible lifecycle per
		-- spawned preview.  Selecting an illusion reconstructs the previewer with
		-- a new stable preview item, so neither the equipped backend id nor a
		-- synthetic rifle/bayonet stance identifies this visible row. Bind both
		-- edges to the exact previewer+item token and a monotonically increasing
		-- session generation (#1156).
		if edge == "instance_load" then
			local next_generation = math.floor(tonumber(
				_om._cwv_old_musket_browser_generation) or 0) + 1
			_om._cwv_old_musket_browser_generation = next_generation
			self._cwv_old_musket_preview_generation = next_generation
		end
		preview_generation = self._cwv_old_musket_preview_generation
		local data = type(item.data) == "table" and item.data or nil
		local item_token = _preview_backend_id(item)
			or item.skin or (data and data.skin)
			or item.key or (data and data.key)
		local viewer_token = self._unique_id or tostring(self)
		local candidate = string.format("%s:%s", tostring(viewer_token),
			tostring(item_token or "unknown"))
		if #candidate <= 128 then preview_identity = candidate end
	end
	if surface == "cim_preview" then
		if not cim_context then
			_dbg_alert("[cwv:1155] CIM preview rejected reason=%s",
				tostring(cim_reason))
			return 0, 0
		end
		local latest = tonumber(_om._cwv_cim_latest_generation) or 0
		if cim_context.generation < latest then
			_dbg_alert("[cwv:1155] CIM preview rejected reason=stale_generation current=%s observed=%s",
				tostring(latest), tostring(cim_context.generation))
			return 0, 0
		end
		if cim_context.generation > latest then
			_om._cwv_cim_latest_generation = cim_context.generation
		end
	end
	local targets = _om._old_musket_preview_texture_targets(
		descriptor, units, spawn_data)
	local mode = descriptor.mode or "ranged"
	local unit_paths = {}
	for index, unit in ipairs(units or {}) do
		unit_paths[unit] = spawn_data and spawn_data[index]
			and spawn_data[index].unit_name or nil
	end
	local retained = 0
	for _, unit in ipairs(targets) do
		if _is_unit(unit) then
			local result = _om.old_musket_appearance.reconcile(unit,
				surface, edge, item, mode, {
					unit_name = unit_paths[unit],
					attachment_profile = _om.old_musket_attachment_profiles.display_3p_rifle,
					cim_generation = cim_context and cim_context.generation or nil,
					preview_identity = preview_identity,
					preview_generation = preview_generation,
				})
			if result and result.retained then retained = retained + 1 end
		end
	end
	if #targets > 0 then
		pcall(printf,
			"[cwv:617/1155] Old Musket preview material retained: surface=%s edge=%s item=%s mode=%s targets=%d retained=%d descriptor=true",
			tostring(surface), tostring(edge), tostring(descriptor.item_key),
			tostring(mode), #targets, retained)
	end
	return retained, #targets
end
_om._cwv_reconcile_old_musket_loot = _reconcile_old_musket_loot

_om._cwv_browser_spawn_units = function(func, self, spawn_data)
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

	-- For cwv_* items, item_data.key returns the BASE weapon key (e.g.
	-- "es_bastard_sword"), NOT "cwv_es_longsword". Always resolve the cwv key
	-- from the backend_id (pattern documented in feedback_cwv_backend_id_lookup.md).
	-- The cwv-keyed transform map then takes precedence over the base-key map so
	-- variant-specific scales/offsets apply correctly.
	local def, _, preview_unit_name, weapon_key =
		_om._cwv_browser_transform_decision(item, spawn_data)
	if not weapon_key then return units end
	local preview_descriptor = _om._old_musket_preview_descriptor(item)
	if not def and not preview_descriptor then return units end

	-- LootItemUnitPreviewer (illusion / cosmetic browser) spawns 3P-style models;
	-- prefer _3p override if set, else unified.
	local scale  = def and (_resolve_field(def, "right_hand_scale_3p")  or _resolve_field(def, "left_hand_scale_3p")
	          or _resolve_field(def, "right_hand_scale")     or _resolve_field(def, "left_hand_scale"))
	local offset = def and (_resolve_field(def, "right_hand_offset_3p") or _resolve_field(def, "left_hand_offset_3p")
	          or _resolve_field(def, "right_hand_offset")    or _resolve_field(def, "left_hand_offset"))
	local rotation = def and (_resolve_field(def, "right_hand_rotation_3p") or _resolve_field(def, "left_hand_rotation_3p")
	          or _resolve_field(def, "right_hand_rotation")    or _resolve_field(def, "left_hand_rotation"))
	if scale or offset or rotation then
		for _, unit in ipairs(units) do
			if def.crowbill_model_key then
				_apply_cwv_hand_transform(unit, def, "right", "3p", "item_browser",
					preview_unit_name, weapon_key)
			else
				_transform_unit(unit, scale, offset, rotation)
			end
		end
	end
	-- #604: LootItemUnitPreviewer backs the item browser/customization pane.
	-- It uses the same committed base*local-flip resolver as world equipment.
	if def and def.crowbill_mode_family and _om._apply_crowbill_presentation then
		local browser_identity = _om._crowbill_render_identity(item_data, def,
			item.backend_id or def.item_key .. ":item_browser")
		for _, unit in ipairs(units) do
			_om._apply_crowbill_presentation(unit, def, browser_identity,
				"item_browser", rotation)
		end
	end

	-- #617/#1155: record the exact construction edge now; the source-backed
	-- visibility/mip-stable hook below owns the one later preview_open retry.
	_reconcile_old_musket_loot(self, units, spawn_data, "instance_load")

	return units
end
mod._cwv_browser_spawn_units = _om._cwv_browser_spawn_units  -- #419 delivery-contract handle

mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
	return _om._cwv_browser_spawn_units(func, self, spawn_data)
end)

-- `present_item` calls this only after packages are loaded and any requested
-- mip streaming has completed. It is the stable final-writer edge for both the
-- ordinary illusion browser and all three CIM Athanor constructors.
mod:hook_safe("LootItemUnitPreviewer", "_enable_item_units_visibility",
		function(self, _, _, visible)
	if visible == true then
		_reconcile_old_musket_loot(self, self._spawned_units,
			self._units_to_spawn, "preview_open")
	end
end)

end

return install
