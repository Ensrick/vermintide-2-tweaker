-- Issue 822 regression (2026-07-19): a single-option dropdown in
-- weapons_of_chaos_data.lua aborted the ENTIRE mod's VMF options init
-- ("'options' table must have at least 2 el..."), so WOC never loaded and
-- the Blightreaper vanished from every inventory. VMF validates at runtime;
-- the static widget-type checker cannot count dynamically built options
-- tables, so this test loads the real data file under a stub and enforces
-- VMF's dropdown arity plus basic widget-shape sanity for every row.
return function(H, repo_root)
	local data_path = repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos_data.lua"

	local function load_data()
		local stub_mod = {
			localize = function(_, key) return "loc:" .. tostring(key) end,
			get = function() return nil end,
			dofile = function(_, script_path)
				return dofile(repo_root .. "/weapons_of_chaos/" .. script_path .. ".lua")
			end,
		}
		local chunk = assert(loadfile(data_path))
		local env = setmetatable({
			get_mod = function() return stub_mod end,
			mod = stub_mod,
		}, { __index = _G })
		setfenv(chunk, env)
		return chunk()
	end

	local function walk_widgets(widgets, visit)
		for _, widget in ipairs(widgets or {}) do
			visit(widget)
			if type(widget["sub_widgets"]) == "table" then
				walk_widgets(widget["sub_widgets"], visit)
			end
		end
	end

	H.test("WOC data file loads and every dropdown satisfies VMF arity", function()
		local data = load_data()
		H.equal(type(data), "table")
		H.equal(type(data.options), "table")
		local dropdowns, checked = 0, 0
		walk_widgets(data.options.widgets, function(widget)
			checked = checked + 1
			H.equal(type(widget.setting_id), "string")
			if widget.type == "dropdown" then
				dropdowns = dropdowns + 1
				H.equal(type(widget.options), "table",
					widget.setting_id .. ": dropdown needs an options table")
				H.truthy(#widget.options >= 2,
					widget.setting_id .. ": VMF requires at least 2 dropdown options, got "
						.. tostring(#widget.options))
				for i, option in ipairs(widget.options) do
					H.equal(type(option.text), "string",
						widget.setting_id .. " option " .. i .. " missing text key")
				end
			end
		end)
		H.truthy(checked > 0, "no widgets walked - data file shape changed")
		-- The picker registers 7 attack-order dropdowns (4 lights + 3 heavies);
		-- the push dropdown must stay absent until a second follow-up unit
		-- exists. A count below 7 means picker rows vanished; exactly 7 pins
		-- the issue 822 fix.
		H.truthy(dropdowns >= 7,
			"expected at least 7 attack-order dropdowns, got " .. tostring(dropdowns))
		local push_present = false
		walk_widgets(data.options.widgets, function(widget)
			if widget.setting_id == "woc_blightreaper_push_follow" then
				push_present = true
				H.truthy(#widget.options >= 2,
					"push dropdown re-registered with fewer than 2 options")
			end
		end)
		H.equal(push_present, false,
			"push dropdown must stay unregistered while only one follow-up unit exists")
	end)
end
