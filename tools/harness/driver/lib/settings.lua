-- tools/harness/driver/lib/settings.lua: T.set, one mod option per call, undone when the case ends (WP-H-06 step 3).
--
-- A helper group: sent with the plan like the driver (tools/harness/New-RigProfile.ps1 -LibDir), compiled by the
-- driver, and installed into every case's T with install(T, ctx) (vt2_rig_driver.lua, load_libs and new_T).
-- Documented in tools/harness/API.md.

return function (T, ctx)
	local case = ctx.case
	local saved = {}

	-- Changes one option of a loaded VMF mod for this case with the mod's own setter and its on_setting_changed
	-- event: VMFMod:set(setting_id, value, notify_mod)
	-- (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:46-61; the event is
	-- vmf.mod_setting_changed_event, modules/core/events.lua:79-84). The value held before the first T.set of that
	-- option in this case is put back the same way when the case ends (case.cleanups runs newest first, also after
	-- ERROR and TIMEOUT). VMF writes settings only into the run profile's user settings (settings.lua:18-33), which the
	-- rig builds from a copy; no backend call is made.
	-- Returns the value held before this call. A mod that is not loaded makes the case INCONCLUSIVE.
	function T.set(mod_id, setting_id, value)
		local mod = ctx.find_mod(mod_id)

		T.require(mod ~= nil and type(mod.get) == "function" and type(mod.set) == "function", "mod " .. tostring(mod_id) .. " loaded")

		local key = tostring(mod_id) .. "\n" .. tostring(setting_id)
		local previous = mod:get(setting_id)

		if not saved[key] then
			saved[key] = true
			case.cleanups[#case.cleanups + 1] = function ()
				mod:set(setting_id, previous, true)
				ctx.out("SET RESTORE id=%s mod=%s setting=%s value=%s", case.id, tostring(mod_id), tostring(setting_id), ctx.q(previous))
			end
		end

		-- on_setting_changed handlers may touch units, so the setter runs in the main update (T.main).
		T.main(function ()
			mod:set(setting_id, value, true)
		end)

		ctx.out("SET id=%s mod=%s setting=%s value=%s was=%s", case.id, tostring(mod_id), tostring(setting_id), ctx.q(value), ctx.q(previous))

		return previous
	end
end
