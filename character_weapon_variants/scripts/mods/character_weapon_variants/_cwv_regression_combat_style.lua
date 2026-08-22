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

end
