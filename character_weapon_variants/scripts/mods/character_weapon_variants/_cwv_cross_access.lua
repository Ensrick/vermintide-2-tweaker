-- Cross-character access and the single network-bound 3P animation owner.
local _apply_cross_access_can_wield, _apply_cross_access_template_wield_3p
local _local_3p_body_unit
return function(mod, ctx)
local _om = ctx.om
local _dbg = ctx.dbg
local _es_all_careers = ctx.es_all_careers
local _wh_all_careers = ctx.wh_all_careers
local _cwv_wield_hook_registration_count = 0

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

function _apply_cross_access_can_wield()
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

function _apply_cross_access_template_wield_3p()
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
local _cross_access_local_style_item = nil
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
				local wielded_item = slot_data and slot_data.item_data
				_cross_access_local_style_item = wielded_item
				_cross_access_local_weapon_key = wielded_item and wielded_item.key or nil
				if _om.combat_styles and _om.combat_styles.effective_remap_key then
					_cross_access_local_weapon_key = _om.combat_styles:effective_remap_key(wielded_item)
						or _cross_access_local_weapon_key
				end
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
		if _om.combat_styles and _om.combat_styles.on_local_wield then
			_om.combat_styles:on_local_wield(self, slot_name, item_data)
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
function _local_3p_body_unit()
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
	if _om.combat_styles and _om.combat_styles.observe_candidate_action then
		_om.combat_styles:observe_candidate_action(
			_cross_access_local_weapon_key, _cross_access_local_career, event_3p)
	end
	local target = _om.combat_styles and _om.combat_styles.remap_event
		and _om.combat_styles:remap_event(_cross_access_local_style_item, nil,
			_cross_access_local_career, event_3p)
	target = target or _om._cross_access_target_event(
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


return {
	action_remap = _cross_access_action_remap,
	wield_hook_registration_count = _cwv_wield_hook_registration_count,
}
end
