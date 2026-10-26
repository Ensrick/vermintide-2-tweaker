-- _cwv_musket_runtime.lua
-- CWV Musket and Old Musket runtime owner (#1159).
--
-- Owns load-time construction of all four musket weapon templates
-- (musket_template, musket_template_melee, old_musket_template,
-- old_musket_template_melee) together with their cloned damage profiles and
-- NetworkLookup registrations, the special-key stance toggle plus its
-- destroy/add/wield cycle, the ActionHandgun observation that mirrors the Old
-- Musket shot report to peers (#474), the shared musket reserve-ammo pool
-- (#932), and the owner-local primary-slot ammo HUD adapter (#1108).
--
-- Exports (all on ctx.om, same names the entry published before the split):
-- musket_ammo_pool, musket_ammo_hud, _CWV_MUSKET_AMMO_EXTS,
-- _CWV_RESERVE_PER_MUSKET,
-- _cwv_musket_pool_cap, _cwv_musket_register_ammo_ext,
-- _cwv_musket_unregister_slot, _old_musket_remote_fire_event,
-- _is_old_musket_ranged_action, _old_musket_shot_completed,
-- _dispatch_old_musket_remote_fire, _old_musket_remote_fire_hook_installed.
--
-- Registers ActionHandgun.client_owner_post_update plus one post-sync observer
-- on each native equipment HUD. The
-- consolidated BackendUtils.get_item_template hook is retained as a private
-- installer called by the entry at its original position, preserving native-first
-- combat-style, Crowbill and Musket precedence without a second hook.
--
-- Load-time deps: Weapons, DamageProfileTemplates and SpreadTemplates must
-- already exist (this loads at the same point in the entry as before). Runtime
-- deps resolved lazily through ctx.om: _cwv_key_for_item, _record_cwv_dp_source,
-- _old_musket_record_and_publish, _old_musket_publish_fire,
-- musket_ammo_pool_policy and mod._cwv_old_musket_interrupt. The HUD policy is
-- loaded and installed here so the owner-local presentation seam stays here.
--
-- Named (not anonymous) so the offline forward-reference lint keeps treating the
-- moved block as file-scope code: an anonymous `function(` wrapper makes every
-- construct-then-call pair below read as a closure capturing its own body.
local function install(mod, ctx)
local _om = ctx.om
local _dbg = ctx.dbg
local _old_musket_shot, _old_musket_fire, _old_musket_melee
local _old_musket_factory = assert(ctx.old_musket_shot_factory, "Old Musket private factory disconnected")
local _network_lookup = assert(_old_musket_factory.network_lookup, "Old Musket private lookup helper disconnected")
local _old_musket_melee_new = assert(_old_musket_factory.melee_factory, "Old Musket private melee factory disconnected")
_old_musket_melee = _old_musket_melee_new({ state = _om,
	profiles = function() return DamageProfileTemplates end,
	lookup = function() return NetworkLookup and NetworkLookup.damage_profiles end,
	weapons = function() return Weapons end,
	action_templates = function() return ActionTemplates end,
	clone = function(value) return table.clone(value, true) end, emit = printf,
})
local function _old_musket_target_template(stance)
	if stance == "melee" then return _old_musket_melee.template() end
	if _old_musket_fire and _old_musket_shot and _old_musket_shot.admit({ item_key = "cwv_es_musket_old", template = "old_musket_template" }) then
		return Weapons.old_musket_template
	end
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
	local canonical_key = _om._cwv_key_for_item
		and _om._cwv_key_for_item(item_data.backend_id, item_data)
	local is_musket     = canonical_key == "cwv_es_musket"
		or (item_data.template == "musket_template" or item_data.template == "musket_template_melee")
	local is_old_musket = canonical_key == "cwv_es_musket_old"
		or (item_data.template == "old_musket_template" or item_data.template == "old_musket_template_melee")
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
	local current = item_data.mod_data and item_data.mod_data.cwv_musket_stance or "ranged"
	local next_stance = (current == "ranged") and "melee" or "ranged"
	-- #428: the target must be retained before any stance, wire, ammo or slot mutation.
	local bid = item_data.backend_id
	local legacy_old = type(bid) == "string" and bid:match("^cwv_es_musket_old_")
	if (is_old_musket or legacy_old) and not _old_musket_target_template(next_stance) then return end
	item_data.mod_data = item_data.mod_data or {}
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
		-- #932: shared-reserve sync is owned by the pool controller in
		-- _cwv_musket_ammo_pool.lua (a dead nil-guarded call sat here).
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

_old_musket_shot = _old_musket_factory.new({
	state = _om,
	profiles = function() return rawget(_G, "DamageProfileTemplates") end,
	lookup = function() local nl = rawget(_G, "NetworkLookup"); return nl and rawget(nl, "damage_profiles") end,
	weapons = function() return rawget(_G, "Weapons") end,
	clone = function(value) return table.clone(value, true) end,
	damage_multiplier = _OLD_MUSKET_DAMAGE_MULT, emit = printf,
})

local function _create_cwv_old_musket_damage_profile()
	return _old_musket_shot.prepare()
end

local function _create_old_musket_template()
	if not Weapons or not Weapons.handgun_template_1 then
		mod:warning("handgun_template_1 not found — old_musket_template unavailable")
		return
	end
	if rawget(Weapons, "old_musket_template") ~= nil then _old_musket_shot.reject("foreign_template"); return end

	local template = table.clone(Weapons.handgun_template_1, true)
	local damage_key = _create_cwv_old_musket_damage_profile()
	if not damage_key then return end
	local shot_rows = {}

	-- Swap damage_profile on every shot_sniper firing sub-action.
	if template.actions then
		for action_name, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for sub_action_name, sub_action in pairs(action_group) do
					if type(sub_action) == "table" and sub_action.damage_profile == "shot_sniper" then
						sub_action.damage_profile = damage_key
						shot_rows[#shot_rows + 1] = { action = sub_action, group = action_name, name = sub_action_name }
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

	if not _old_musket_shot.publish_template(Weapons, template, shot_rows) then return end
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
		_old_musket_fire = function(func, self, dt, t, world, can_damage)
			if not _old_musket_shot.guard(self, t) then return end
			local action = self.current_action
			local before_state = self.state
			local before_extra = self.extra_buff_shot
			local result = func(self, dt, t, world, can_damage)
			if _om._old_musket_shot_completed(action, before_state, before_extra,
					self.state, self.extra_buff_shot) then
				_om._dispatch_old_musket_remote_fire(self)
			end
			return result
		end
		mod:hook("ActionHandgun", "client_owner_post_update", _old_musket_fire)
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

local function _create_old_musket_template_melee()
	if not Weapons or not Weapons.two_handed_heavy_spears_template then
		mod:warning("two_handed_heavy_spears_template not found — old_musket_template_melee unavailable")
		return
	end
	local complete, mode = _old_musket_melee.construct(Weapons.two_handed_heavy_spears_template, function(template)
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

		return mod._cwv_old_musket_interrupt.audit(template, "action_three") == true
	end)
	if not complete then return end
	if mode ~= "custom" then return end -- the bounded owner log identifies native degradation, not 0.9x damage
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
-- #932: the old global extension set could mix owners and merely copied one
-- 10-round reserve, so two muskets never produced the promised 20-round pool.
-- Keep native ammo extensions/chambers, but own reserve state per player+slot.
_om.musket_ammo_hud_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_ammo_hud")
_om.musket_ammo_pool = _om.musket_ammo_pool_policy.install(mod, {
	reserve_per_musket = 10,
	alive = function(unit) return unit and Unit.alive(unit) end,
	log = function(edge, owner, slot_name, reserve, capacity)
		_dbg("[cwv:932] ammo_pool edge=%s owner=%s slot=%s reserve=%d capacity=%d",
			tostring(edge), tostring(owner), tostring(slot_name), reserve, capacity)
	end,
})
_om._CWV_MUSKET_AMMO_EXTS = _om.musket_ammo_pool.extensions
_om._CWV_RESERVE_PER_MUSKET = _om.musket_ammo_pool.reserve_per_musket
_om._cwv_musket_pool_cap = function(ext_or_owner)
	return _om.musket_ammo_pool:capacity_for(ext_or_owner)
end
_om._cwv_musket_register_ammo_ext = function(ext, owner, slot_name)
	return _om.musket_ammo_pool:register(ext, owner, slot_name)
end
_om._cwv_musket_unregister_slot = function(owner, slot_name)
	return _om.musket_ammo_pool:unregister_slot(owner, slot_name)
end
_om.musket_ammo_hud = _om.musket_ammo_hud_policy.install(mod, _om.musket_ammo_pool)

local function install_template_router()
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
		local selected = _old_musket_target_template(stance) or _old_musket_target_template("ranged")
		if not selected then error("[cwv:428] Old Musket effective template authority lost") end
		return selected
	end
	if stance == "melee" and Weapons.musket_template_melee then
		return Weapons.musket_template_melee
	end
	return Weapons.musket_template or template
end)
end

return { network_lookup = _network_lookup, install_template_router = install_template_router, admit_old_musket = function(def)
	return _old_musket_fire ~= nil and _old_musket_shot.admit(def) and _old_musket_melee.ready()
end, check_old_musket = function()
	if not _old_musket_fire then return "#428 existing Handgun callback was not installed" end
	return _old_musket_shot.check(_old_musket_fire) or _old_musket_melee.check()
end }
end

return install
