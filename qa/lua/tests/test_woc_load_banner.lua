-- Locks the log-provable WOC load banner (ct model: pcall(printf, ...)).
-- Pinned live-test cards key on a "[WOC:LOAD]" line that survives VMF mod
-- logging OFF; mod:info/mod:echo cannot provide that proof.
return function(H, repo_root)
	local path = repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()

	H.test("WOC emits the canonical [WOC:LOAD] banner via pcall(printf)", function()
		local banner = 'pcall(printf, "[WOC:LOAD] v%s enabled fp=%s OK", '
			.. 'MOD_VERSION, _settings_fingerprint())'
		H.truthy(source:find(banner, 1, true))
	end)

	H.test("WOC banner renders to the log-provable card shape", function()
		local version = source:match('local MOD_VERSION = "([^"]+)"')
		H.truthy(version)
		local rendered = string.format(
			"[WOC:LOAD] v%s enabled fp=%s OK", version, "1a2b3c4d")
		H.truthy(rendered:match(
			"^%[WOC:LOAD%] v%d+%.%d+%.%d+[%w%-%.]* enabled fp=%x+ OK$"))
	end)

	H.test("WOC keeps the pre-existing mod:info and mod:echo load lines", function()
		H.truthy(source:find(
			'mod:info("[WOC] enabled v%s settings_fp=%s (Blightreaper)"',
			1, true))
		H.truthy(source:find(
			'mod:echo(string.format("[WOC] v%s loaded", MOD_VERSION))',
			1, true))
	end)
end
