-- #509 (dcp 0.1.30-dev): runs the REAL DCP entry chunk in a test-local
-- environment with engine stubs, so the live wrappers (_sync_portrait_settings,
-- _restore_portrait_settings, mod.on_unload), the #435 per-player seams and the
-- named /dcp_regression_test checks execute instead of being grepped. Nothing
-- here touches the real _G: every global the chunk reads or writes resolves in
-- the sandbox table (env._G = env).
return function(H, repo_root)
    local dcp_root = repo_root .. "/dynamic_cosmetic_portraits"
    local entry_path = dcp_root .. "/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua"
    local VANILLA = "unit_frame_portrait_kruber_mercenary"
    local VANILLA_MEDIUM = "medium_unit_frame_portrait_kruber_mercenary"
    local UNTRACKED_HAT = "dcp509_untracked_hat"
    local UNTRACKED_SKIN = "dcp509_untracked_skin"

    local function mercenary(hat, skin, is_local)
        return {
            local_player = is_local or false,
            career_name = function() return "es_mercenary" end,
            cosmetics = {
                slot_hat = { item_name = hat },
                slot_skin = { item_name = skin or UNTRACKED_SKIN },
            },
        }
    end

    local function load_entry(local_hat, local_skin)
        local f = { hooks = {}, commands = {}, logs = {} }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        local mod = {}
        function mod:dofile(path)
            local chunk = assert(loadfile(dcp_root .. "/" .. path .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        function mod:info() end
        function mod:echo(fmt, ...) f.logs[#f.logs + 1] = string.format(fmt, ...) end
        function mod:warning() end
        function mod:get() return nil end
        function mod:command(name, _, fn) f.commands[name] = fn end
        function mod:hook(obj, method, fn) f.hooks[obj .. "." .. method] = fn end
        function mod:hook_safe(obj, method, fn) f.hooks[obj .. "." .. method] = fn end
        env.get_mod = function() return mod end
        env.printf = function(fmt, ...) f.logs[#f.logs + 1] = string.format(fmt, ...) end
        env.UIAtlasHelper = {
            has_atlas_settings_by_texture_name = function() return true end,
            get_atlas_settings_by_texture_name = function(name)
                local small = name:find("small_portrait_", 1, true) == 1
                return { material_name = "dcp_portrait_atlas",
                    size = small and { 60, 70 } or { 86, 108 } }
            end,
        }
        env.Gui = { material = function() return {} end }
        f.local_player = mercenary(local_hat, local_skin, true)
        env.Managers = {
            ui = { ui_renderer = { gui = {} } },
            player = { local_player_safe = function() return f.local_player end },
        }
        env.CosmeticUtils = {
            get_cosmetic_slot = function(player, slot) return player.cosmetics and player.cosmetics[slot] end,
        }
        env.BackendUtils = { get_loadout_item = function() return nil end }
        f.row = { portrait_image = VANILLA, picking_image = VANILLA_MEDIUM }
        env.SPProfiles = { [5] = { careers = { f.row } } }
        env.Network = { peer_id = function() return "local_peer" end }
        local chunk = assert(loadfile(entry_path))
        setfenv(chunk, env)
        chunk()
        f.env, f.mod = env, mod

        function f:draw() self.hooks["UnitFrameUI.draw"]({}, 0.016) end
        -- Vanilla builds every score row from the global row
        -- (end_view_state_score.lua:504,514), then DCP's hook corrects it.
        function f:score(records)
            local widgets = {}
            for i = 1, #records do
                widgets[i] = { content = { portrait = self.row.portrait_image } }
            end
            self.hooks["EndViewStateScore._setup_player_scores"]({
                peer_id = "local_peer",
                _players_by_widget_index = records,
                _hero_widgets = widgets,
            }, {})
            local shown = {}
            for i = 1, #records do shown[i] = widgets[i].content.portrait end
            return shown
        end
        function f:regression()
            self.logs = {}
            self.commands.dcp_regression_test()
            local results = {}
            for _, line in ipairs(self.logs) do
                local name = line:match("^  PASS: (.+)$")
                if name then results[name] = "PASS" end
                local failed, why = line:match("^  FAIL: (%S+) %-%- (.*)$")
                if failed then results[failed] = "FAIL: " .. why end
                local skipped, note = line:match("^  SKIP: (%S+) %-%- (.*)$")
                if skipped then results[skipped] = "SKIP: " .. note end
            end
            return results
        end
        return f
    end

    local function remote_record(hat, skin)
        return { profile_index = 5, career_index = 1, is_player_controlled = true,
            peer_id = "remote_peer", hat = { item_name = hat }, hero_skin = skin }
    end

    H.test("DCP issue509 score screen shows a remote tracked portrait while the local Mercenary is untracked", function()
        local f = load_entry(UNTRACKED_HAT)
        f:draw()
        H.equal(f.row.portrait_image, VANILLA, "untracked local loadout never swaps")
        local shown = f:score({
            remote_record("mercenary_hat_0001"),
            remote_record(UNTRACKED_HAT, UNTRACKED_SKIN),
        })
        H.equal(shown[1], "portrait_kruber_mercenary_hat_0001",
            "remote row must show its own tracked portrait (#435)")
        H.equal(shown[2], VANILLA, "untracked remote row stays vanilla, never nil")
    end)

    H.test("DCP issue509 score screen corrects remote rows while the local swap is active", function()
        local f = load_entry("mercenary_hat_0003")
        f:draw()
        H.equal(f.row.portrait_image, "portrait_kruber_mercenary_hat_0003")
        local own = remote_record("mercenary_hat_0003")
        own.peer_id = "local_peer"
        local shown = f:score({
            remote_record(UNTRACKED_HAT, UNTRACKED_SKIN),
            remote_record("mercenary_hat_0001"),
            own,
        })
        H.equal(shown[1], VANILLA, "the local swap must not leak onto an untracked remote row")
        H.equal(shown[2], "portrait_kruber_mercenary_hat_0001")
        H.equal(shown[3], "portrait_kruber_mercenary_hat_0003", "local row untouched")
    end)

    H.test("DCP issue509 Tab list and HUD frames resolve remote rows in both local states", function()
        for _, local_hat in ipairs({ UNTRACKED_HAT, "mercenary_hat_0003" }) do
            local f = load_entry(local_hat)
            f:draw()
            local tracked = mercenary("mercenary_hat_0001")
            local untracked = mercenary(UNTRACKED_HAT)
            local list = { _num_players = 2, _players = {
                { player = tracked, portrait_widget = { content = { portrait = f.row.portrait_image } } },
                { player = untracked, portrait_widget = { content = { portrait = f.row.portrait_image } } },
            } }
            f.hooks["IngamePlayerListUI._update_player_information"](list, 0, 0)
            H.equal(list._players[1].portrait_widget.content.portrait,
                "portrait_kruber_mercenary_hat_0001", "Tab tracked row, local " .. local_hat)
            H.equal(list._players[2].portrait_widget.content.portrait, VANILLA,
                "Tab untracked row, local " .. local_hat)

            local live_before = f.row.portrait_image
            for _, case in ipairs({
                { tracked, "portrait_kruber_mercenary_hat_0001" },
                { untracked, VANILLA },
            }) do
                local seen = nil
                f.hooks["UnitFramesHandler._sync_player_stats"](function()
                    seen = f.row.portrait_image
                end, {}, { player_data = { player = case[1] } })
                H.equal(seen, case[2], "HUD frame read, local " .. local_hat)
                H.equal(f.row.portrait_image, live_before, "HUD bracket puts the live value back")
            end
        end
    end)

    H.test("DCP issue509 hat removal through the live sync restores the vanilla pair", function()
        local f = load_entry("mercenary_hat_0003")
        f:draw()
        H.equal(f.row.picking_image, "medium_portrait_kruber_mercenary_hat_0003")
        f.local_player.cosmetics.slot_hat.item_name = UNTRACKED_HAT
        f:draw()
        H.equal(f.row.portrait_image, VANILLA)
        H.equal(f.row.picking_image, VANILLA_MEDIUM)
        f.local_player.cosmetics.slot_hat.item_name = "mercenary_hat_0001"
        f:draw()
        H.equal(f.row.portrait_image, "portrait_kruber_mercenary_hat_0001", "re-equip swaps again")
    end)

    H.test("DCP issue509 on_unload restores the vanilla pair", function()
        local f = load_entry("mercenary_hat_0003")
        f:draw()
        H.equal(f.row.portrait_image, "portrait_kruber_mercenary_hat_0003")
        f.mod.on_unload()
        H.equal(f.row.portrait_image, VANILLA)
        H.equal(f.row.picking_image, VANILLA_MEDIUM)
    end)

    H.test("DCP issue509 named checks pass with and without a tracked local cosmetic", function()
        for _, local_hat in ipairs({ UNTRACKED_HAT, "mercenary_hat_0003" }) do
            local f = load_entry(local_hat)
            f:draw()
            local before = f.row.portrait_image
            local results = f:regression()
            H.equal(results.career_settings_swap_saves_and_restores, "PASS", "local " .. local_hat)
            H.equal(results.score_rows_resolve_without_local_swap_509, "PASS", "local " .. local_hat)
            for name, result in pairs(results) do
                H.equal(result, "PASS", name .. ", local " .. local_hat)
            end
            H.equal(f.row.portrait_image, before, "the checks leave the live row as they found it")
        end
    end)

    H.test("DCP issue509 named check fails on an unowned DCP portrait on the live row", function()
        local f = load_entry(UNTRACKED_HAT)
        f:draw()
        f.row.portrait_image = "portrait_kruber_mercenary_hat_0001"
        local result = f:regression().career_settings_swap_saves_and_restores
        H.truthy(type(result) == "string" and result:find("unowned DCP portrait", 1, true),
            tostring(result))
    end)

    H.test("DCP issue509 named checks report SKIP rather than PASS without their live half", function()
        local f = load_entry(UNTRACKED_HAT)
        f.env.SPProfiles = false  -- false, not nil: nil would fall through to the real _G
        local results = f:regression()
        H.truthy(results.career_settings_swap_saves_and_restores:find("SKIP: ", 1, true) == 1,
            "career check must not report a synthetic-only PASS")
        H.truthy(results.score_rows_resolve_without_local_swap_509:find("SKIP: ", 1, true) == 1,
            "score check must not report an unavailable-live-row PASS")
        local noted = {}
        for _, line in ipairs(f.logs) do
            if line:find("[dcp:509] career_settings_swap_saves_and_restores live half skipped", 1, true) then
                noted.career = true
            end
            if line:find("[dcp:509] score_rows_resolve_without_local_swap_509 skipped", 1, true) then
                noted.score = true
            end
        end
        H.truthy(noted.career, "career check names its skipped live half")
        H.truthy(noted.score, "score check names its skip")
        H.truthy(table.concat(f.logs, "\n"):find("0 failed, 2 skipped", 1, true),
            "the actual runner summary must count both skipped checks")
    end)
end
