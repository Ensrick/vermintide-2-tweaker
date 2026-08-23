-- _cwv_regression_combat_style.lua - executable Combat Style transaction checks.
--
-- This owner loads after the broader identity checks and before the
-- husk/ammo/projectile checks. It must remain engine-object neutral: detached
-- dependency overrides drive the production runtime without touching live gear.
return function(mod, ctx)
local _om = ctx.om
local _rt_register = ctx.rt_register

_rt_register("issue774_mission_combat_style_interruption", function()
	-- #940 proved the mission-mounted UI reaches this shared transaction; #944
	-- repaired its interruption boundary. Exercise the actual installed runtime
	-- against detached objects so /cwv_regression_test verifies that repair
	-- without touching the player's equipped item or any network channel.
	local policy = _om.combat_style_policy
	if type(policy) ~= "table" or type(policy.install) ~= "function"
			or type(policy.interrupt_equipment_actions) ~= "function" then
		return "#774/#944 Combat Style interruption policy is not installed"
	end

	local sequence = 0
	local function probe(action_name, action_kind, stop_mode)
		sequence = sequence + 1
		local item = {
			backend_id = "issue774_runtime_probe_" .. tostring(sequence),
			name = "es_2h_sword",
		}
		local weapon_unit = {}
		local counts = { stop = 0, persist = 0, destroy = 0, add = 0, wield = 0 }
		local equipment = {
			wielded_slot = "slot_melee",
			slots = { slot_melee = { item_data = item } },
			right_hand_wielded_unit = weapon_unit,
		}
		local inventory = {
			equipment = function() return equipment end,
			destroy_slot = function() counts.destroy = counts.destroy + 1 end,
			add_equipment = function() counts.add = counts.add + 1 end,
			wield = function() counts.wield = counts.wield + 1 end,
		}
		local weapon = {
			current_action_name = action_name,
			current_action_settings = { kind = action_kind },
		}
		function weapon:has_current_action()
			return self.current_action_settings ~= nil
		end
		function weapon:stop_action(reason)
			counts.stop = counts.stop + 1
			if reason ~= "interrupted" then error("non-canonical interrupt reason") end
			if stop_mode == "fail" then error("synthetic interrupt failure") end
			self.current_action_settings = nil
		end
		local probe_mod = {
			get = function() return nil end,
			set = function()
				counts.persist = counts.persist + 1
			end,
		}
		local isolated = policy.install(probe_mod, {
			local_equipment = function() return inventory, "issue774_probe_owner" end,
			prepare_style_descriptor = function() return true end,
			weapon_extension = function(unit)
				return unit == weapon_unit and weapon or nil
			end,
		})
		local changed, detail = isolated:set_item_style(item, nil, "kerillian",
			"issue774_runtime_probe", true)
		return {
			changed = changed,
			detail = detail,
			counts = counts,
			style = isolated:describe(item).style_id,
		}
	end

	local ordinary = probe("action_one", "sweep", "ok")
	if ordinary.changed ~= true or ordinary.counts.stop ~= 1
			or ordinary.counts.persist ~= 1 or ordinary.counts.destroy ~= 1
			or ordinary.counts.add ~= 1 or ordinary.counts.wield ~= 1
			or ordinary.style ~= "kerillian" then
		return "#774 ordinary action did not interrupt once and commit one style rebuild"
	end

	local career = probe("action_career_release", "career_skill", "ok")
	if career.changed ~= false or career.detail ~= "career action active"
			or career.counts.stop ~= 0 or career.counts.persist ~= 0
			or career.counts.destroy ~= 0 or career.counts.add ~= 0
			or career.counts.wield ~= 0 or career.style ~= "greatsword" then
		return "#774 career action did not fail closed before interruption or commit"
	end

	local failed = probe("action_one", "sweep", "fail")
	if failed.changed ~= false or failed.detail ~= "weapon action interrupt failed"
			or failed.counts.stop ~= 1 or failed.counts.persist ~= 0
			or failed.counts.destroy ~= 0 or failed.counts.add ~= 0
			or failed.counts.wield ~= 0 or failed.style ~= "greatsword" then
		return "#774 failed interruption persisted or rebuilt a rejected style"
	end
end)

_rt_register("issue660_greatsword_style_appearance_transaction", function()
	local appearance = _om.combat_style_appearance
	local descriptor_api = _om.appearance_descriptor
	local lifecycle_policy = _om.appearance_lifecycle_policy
	local style_policy = _om.combat_style_policy
	if type(appearance) ~= "table" or type(descriptor_api) ~= "table"
			or type(lifecycle_policy) ~= "table" or type(style_policy) ~= "table" then
		return "#660 Greatsword appearance transaction modules are unavailable"
	end
	local function build(style_id)
		local package = style_policy.package("es_2h_sword", style_id)
		return appearance.build({ descriptor = descriptor_api,
			encode_style_rider = style_policy.encode_style_rider }, {
			slot_name = "slot_melee",
			row = { item_key = "es_2h_sword", family_id = "greatsword",
				style_id = style_id, package = package },
			world = { base_item_key = "es_2h_sword", source = "runtime_check",
				right_hand_unit = "units/cwv_rt/greatsword" },
			base = { key = "es_2h_sword",
				right_hand_unit = "units/cwv_rt/greatsword_base" },
			presentation = style_id == "bretonnian" and {
				right_hand_scale_3p = { 1, 0.8, 0.9 },
				right_hand_offset_3p = { -0.1, 0, 0 },
			} or nil,
		})
	end
	local current = build("bretonnian")
	if not current or current.style_rider ~= "greatsword:bretonnian"
			or current.effective_template ~= "bastard_sword_template" then
		return "#660 Greatsword descriptor did not retain style/template"
	end
	local lifecycle = lifecycle_policy.new({
		resolve_local = function(_, slot_name)
			return slot_name == "slot_melee" and current or nil,
				slot_name == "slot_melee" and "es_2h_sword" or "es_longbow"
		end,
		resolve_remote = function(payload)
			local _, style_id = style_policy.decode_style_rider(payload.style)
			return style_id and build(style_id) or nil
		end,
		send = function() return true end,
	})
	local payload = lifecycle:payload_for("slot_melee", {})
	local changed, remote, reason = lifecycle:accept(
		"issue660-runtime-peer", lifecycle_policy.SCHEMA, payload)
	if changed ~= true or reason ~= "exact" or not remote
			or remote.fingerprint ~= current.fingerprint then
		return "#660 Greatsword receiver did not reconstruct the sender descriptor"
	end
	local old_fingerprint = current.fingerprint
	current = build("greatsword")
	if not current or current.fingerprint == old_fingerprint then
		return "#660 Greatsword style switch did not advance appearance fingerprint"
	end
	local tampered = {}
	for key, value in pairs(payload) do tampered[key] = value end
	tampered.style = "greatsword:greatsword"
	local _, rejected = lifecycle:accept(
		"issue660-runtime-tamper", lifecycle_policy.SCHEMA, tampered)
	if rejected ~= nil then
		return "#660 Greatsword receiver accepted a tampered style/fingerprint pair"
	end
end)

_rt_register("issue604_crowbill_template_ownership", function()
	local runtime = mod._cwv_crowbill_runtime
	local policy = mod._cwv_crowbill_hammer_mode
	local weapons = rawget(_G, "Weapons")
	if type(runtime) ~= "table" or runtime._installed ~= true
			or type(runtime.resolve_template) ~= "function"
			or type(policy) ~= "table" or type(weapons) ~= "table" then
		return "#604 Crowbill template-ownership dependencies missing"
	end
	local source = weapons[policy.SOURCE_TEMPLATE_KEY]
	local pick = weapons[runtime.PICK_TEMPLATE_KEY]
	local hammer = weapons[policy.HAMMER_TEMPLATE_KEY]
	if type(source) ~= "table" or type(pick) ~= "table" or type(hammer) ~= "table" then
		return "#604 Crowbill source/pick/hammer templates not all registered"
	end
	local native_pick = runtime.resolve_template({
		name = "bw_1h_crowbill", template = policy.SOURCE_TEMPLATE_KEY,
		backend_id = "cwv-regression-native-crowbill",
		mod_data = { cwv_crowbill_mode = policy.MODE_PICK },
	})
	local imperial_pick = runtime.resolve_template({
		cwv_key = "cwv_es_imperial_crowbill",
		backend_id = "cwv-regression-imperial-crowbill",
		mod_data = { cwv_crowbill_mode = policy.MODE_PICK },
	})
	local native_hammer = runtime.resolve_template({
		name = "bw_1h_crowbill", template = policy.SOURCE_TEMPLATE_KEY,
		backend_id = "cwv-regression-native-hammer",
		mod_data = { cwv_crowbill_mode = policy.MODE_HAMMER },
	})
	if native_pick ~= source then
		return "native Sienna Crowbill normal face lost its burning donor"
	end
	if imperial_pick ~= pick then
		return "Imperial Crowbill normal face lost its non-burning pick template"
	end
	if native_hammer ~= hammer then
		return "native Sienna Crowbill Hammer face lost the shared hammer template"
	end
end)

end
