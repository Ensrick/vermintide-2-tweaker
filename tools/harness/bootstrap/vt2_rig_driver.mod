-- VT2 test rig bootstrap. This is the whole Workshop item: it never changes.
--
-- It does nothing unless ALL of these hold:
--   1. the game runs in the modded realm,
--   2. the command line carries  -vt2-test-run <nonce>,
--   3. the profile's user_settings.config has a table  vt2_rig_plan  with the same nonce and a driver_hex string.
-- Then it compiles the driver source delivered in the plan (hex text) and returns the driver object, whose
-- update / on_game_state_changed callbacks the game's own mod manager calls. No mod framework is required.
return {
	run = function ()
		local dev = rawget(_G, "Development")
		local params = dev and dev.application_parameter
		local nonce = params and params["vt2-test-run"]

		if not rawget(_G, "MODDED_REALM") or type(nonce) ~= "string" then
			return {}
		end

		local ok, plan = pcall(Application.user_setting, "vt2_rig_plan")

		if not ok or type(plan) ~= "table" or plan.nonce ~= nonce or type(plan.driver_hex) ~= "string" then
			return {}
		end

		local function say(text)
			print(string.format("[vt2t:%s] %s", nonce, text))
		end

		local source = plan.driver_hex:gsub("%x%x", function (byte)
			return string.char(tonumber(byte, 16))
		end)
		local chunk, compile_error = loadstring(source, "=vt2_rig_driver")

		if not chunk then
			say("BOOTSTRAP ERROR compile " .. tostring(compile_error))

			return {}
		end

		local ran, driver = pcall(chunk, plan, nonce)

		if not ran or type(driver) ~= "table" then
			say("BOOTSTRAP ERROR run " .. tostring(driver))

			return {}
		end

		say("BOOTSTRAP OK")

		return driver
	end,
	packages = {
		"resource_packages/vt2_rig_driver/vt2_rig_driver",
	},
}
