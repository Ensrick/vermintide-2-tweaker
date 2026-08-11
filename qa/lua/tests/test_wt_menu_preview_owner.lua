-- Boundary test for the #1159 menu/inventory preview surface owner (wt + wt_dev).
--
-- Engine-free. Asserts the structural contract of the split across BOTH streams
-- of the mirror pair: bare-dofile wiring at the former execution position, the
-- load-order window after the in-game 3P swap owner, single ownership of BOTH
-- MenuWorldPreviewer seams, the derived-class hook invariant, entry-side absence
-- of every moved file-scope local, the one publication that hands the #603
-- selector back to the entry's runtime-check dependency table, and exact
-- public/dev parity of the owner itself.
return function(H, repo_root)
    local STREAMS = {
        {
            tag = "wt",
            dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            entry = "weapon_tweaker.lua",
            ns = "weapon_tweaker",
            mod_id = "wt",
        },
        {
            tag = "wt_dev",
            dir = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            entry = "weapon_tweaker_dev.lua",
            ns = "weapon_tweaker_dev",
            mod_id = "wt_dev",
        },
    }

    local OWNER = "_wt_menu_preview_owner.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    -- Absence assertions run against CODE, not prose. The moved block carries a
    -- long comment that deliberately spells out the HeroPreviewer trap, and the
    -- entry keeps a stub comment naming the module it handed the code to, so
    -- full-line comments are dropped before any "must not appear" check.
    local function code_only(source)
        local kept = {}
        for line in (source .. "\n"):gmatch("([^\n]*)\n") do
            if not line:match("^%s*%-%-") then kept[#kept + 1] = line end
        end
        return table.concat(kept, "\n")
    end

    for _, stream in ipairs(STREAMS) do
        local entry = read(stream.dir .. stream.entry)
        local owner = read(stream.dir .. OWNER)
        local dofile_call = 'mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_menu_preview_owner")'

        H.test(stream.tag .. ": owner is bare-dofile'd exactly once by the entry", function()
            H.equal(count_plain(entry, dofile_call), 1)
            H.equal(count_plain(owner, "function M.install"), 0)
            H.equal(count_plain(owner, "return function"), 0)
            H.equal(count_plain(owner, 'local mod = get_mod("' .. stream.mod_id .. '")'), 1)
        end)

        H.test(stream.tag .. ": dofile sits after the 3P swap owner and before the lifecycle callbacks", function()
            local swap_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_ingame_3p_swap_owner")', 1, true)
            local owner_at = entry:find(dofile_call, 1, true)
            local lifecycle_at = entry:find("mod.on_game_state_changed = function(status, state_name)", 1, true)
            H.truthy(swap_at, "3P swap owner dofile must exist in the entry")
            H.truthy(owner_at, "preview owner dofile must exist in the entry")
            H.truthy(lifecycle_at, "the on_game_state_changed lifecycle callback must exist in the entry")
            H.truthy(swap_at < owner_at, "preview owner must load after the in-game 3P swap owner")
            H.truthy(owner_at < lifecycle_at, "preview owner must load before the lifecycle callbacks")
        end)

        H.test(stream.tag .. ": both previewer seams are owned once, and left the entry", function()
            H.equal(count_plain(owner, 'mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_name, slot,'), 1)
            H.equal(count_plain(owner, 'mod:hook("MenuWorldPreviewer", "_spawn_item_unit", function(func, self, unit,'), 1)
            for _, verb in ipairs({ "mod:hook(", "mod:hook_safe(", "mod:traced_hook(", "mod:safe_hook(" }) do
                for _, method in ipairs({ "equip_item", "_spawn_item_unit" }) do
                    H.equal(count_plain(entry, verb .. '"MenuWorldPreviewer", "' .. method .. '"'), 0,
                        verb .. " must not re-register MenuWorldPreviewer." .. method .. " in the entry")
                end
            end
        end)

        H.test(stream.tag .. ": the derived-class + no-chain invariants travelled with the code", function()
            -- class() copies parent methods at definition time, so hooking
            -- HeroPreviewer never fires on a MenuWorldPreviewer instance. The
            -- moved comment block explains that trap at length, so this reads
            -- code only.
            H.equal(count_plain(code_only(owner), '"HeroPreviewer"'), 0, "the owner must not hook the base previewer class")
            H.equal(count_plain(code_only(entry), '"HeroPreviewer"'), 0, "the entry must not hook the base previewer class either")
            -- hook_safe does not chain, so all four preview helpers are called
            -- from the single equip_item body rather than registering their own.
            for _, helper in ipairs({
                "_wt_capture_preview_item_key",
                "_wt_longbow_preview_swap_apply",
                "_wt_repeating_pistol_preview_swap_apply",
                "_wt_hammer_book_preview_swap_apply",
            }) do
                H.equal(count_plain(owner, "local " .. helper), 1, helper .. " must be forward-declared once in the owner")
                H.equal(count_plain(owner, helper .. " = function("), 1, helper .. " must be assigned once in the owner")
                H.equal(count_plain(owner, helper .. "(self, item"), 1, helper .. " must be dispatched from the one hook body")
                H.equal(count_plain(entry, helper), 0, helper .. " must not remain in the entry")
            end
        end)

        H.test(stream.tag .. ": every moved file-scope local left the entry", function()
            for _, decl in ipairs({
                "local _wt_longbow_preview_swap_apply",
                "local _wt_repeating_pistol_preview_swap_apply",
                "local _wt_hammer_book_preview_swap_apply",
                "local _wt_capture_preview_item_key",
                "local function _is_unit(v)",
                "local _mwp_pending_keys",
                "local function _wt603_post_spawn_preview_event",
                "local _wt_paired_preview_transform",
            }) do
                H.equal(count_plain(owner, decl), 1, decl .. " must be declared once in the owner")
                H.equal(count_plain(entry, decl), 0, decl .. " must not remain in the entry")
            end
            -- The #735 paired-transform adapter is installed from here, not the
            -- entry (whose stub comment still names the module it handed off).
            H.equal(count_plain(owner, "_wt_paired_preview_transform.install(mod, {"), 1)
            H.equal(count_plain(code_only(entry), "_wt_paired_preview_transform"), 0)
        end)

        H.test(stream.tag .. ": crossings are late-bound through mod._wt, published before the dofile", function()
            local publications = {
                { field = "validate_attachment_sources", local_name = "_wt_validate_attachment_sources" },
                { field = "scale_weapon_units", local_name = "_scale_weapon_units" },
                { field = "resolve_grip_offset", local_name = "_resolve_grip_offset" },
                { field = "offset_weapon_units", local_name = "_offset_weapon_units" },
                { field = "resolve_rotation_override", local_name = "_resolve_rotation_override" },
                { field = "track_3p_rotation_units", local_name = "_wt569_track_3p_units" },
                { field = "grip_offset_policy", local_name = "_wt_grip_offset_policy" },
            }
            local dofile_at = entry:find(dofile_call, 1, true)
            for _, row in ipairs(publications) do
                local publish_at = entry:find("mod._wt." .. row.field .. " ", 1, true)
                H.truthy(publish_at, row.field .. " must be published by the entry")
                H.truthy(publish_at < dofile_at, row.field .. " must be published BEFORE the owner dofile")
                H.equal(count_plain(owner, "= mod._wt." .. row.field), 1,
                    row.field .. " must be read exactly once by the owner")
                H.equal(count_plain(owner, "local " .. row.local_name .. " "), 1,
                    row.local_name .. " must be a file-local in the owner")
            end
            -- Match whole declarations: "= mod._wt.dbg" is also a prefix of the
            -- dbg_alert accessor other owners use.
            -- Four values this owner reads are published by the EARLIER swap-owner
            -- block. If that block is ever removed or reordered these reads go
            -- nil silently, so pin the ordering here too.
            for _, field in ipairs({
                "is_sp_crossbow_presentation_item",
                "brace_repeater_3p_unit",
                "sp_crossbow_3p_unit",
                "skullsplitter_hand_policy",
            }) do
                local publish_at = entry:find("mod._wt." .. field .. " ", 1, true)
                H.truthy(publish_at, field .. " must still be published by the entry")
                H.truthy(publish_at < dofile_at, field .. " must be published BEFORE the preview owner dofile")
                H.equal(count_plain(owner, "= mod._wt." .. field), 1,
                    field .. " must be read exactly once by the preview owner")
            end
            for _, decl in ipairs({
                "local _dbg                              = mod._wt.dbg\n",
                "local _local_career_name                = mod._wt.local_career_name\n",
                "local _safe_has_anim                    = mod._wt.safe_has_anim\n",
                "local _resolve_preview_wield_event      = mod._wt.resolve_preview_wield_event\n",
            }) do
                H.equal(count_plain(owner, decl), 1, decl:gsub("\n", "") .. " must be read from the namespace")
            end
        end)

        H.test(stream.tag .. ": the #603 selector is published back to the runtime-check deps", function()
            -- The only outbound crossing of this slice. The entry's dependency
            -- table is built at the very end of the file, long after this owner
            -- loads, so the namespace read is always populated.
            H.equal(count_plain(owner, "mod._wt.post_spawn_preview_event = _wt603_post_spawn_preview_event"), 1)
            H.equal(count_plain(entry, "post_spawn_preview_event = mod._wt.post_spawn_preview_event,"), 1)
            H.equal(count_plain(entry, "post_spawn_preview_event = _wt603_post_spawn_preview_event"), 0)
            local owner_at = entry:find(dofile_call, 1, true)
            local deps_at = entry:find("post_spawn_preview_event = mod._wt.post_spawn_preview_event,", 1, true)
            H.truthy(owner_at < deps_at, "the owner must load before the dependency table reads it")
            -- The selector itself is unchanged: the exact #603 tuple only.
            H.equal(count_plain(owner, 'if weapon_key == "dr_dual_wield_axes"'), 1)
            H.equal(count_plain(owner, 'return "to_dual_hammers"'), 1)
        end)

        H.test(stream.tag .. ": the preview surface stays 3P-only", function()
            -- The previewer body is self.character_unit; 1P is never previewed.
            local code = code_only(owner)
            H.equal(count_plain(code, "_unit_1p"), 0, "the preview owner must not touch a 1P unit")
            H.truthy(count_plain(code, "self.character_unit") > 0, "the 3P preview body is the only unit read")
        end)

        H.test(stream.tag .. ": no native resource boundary moved with the code", function()
            local code = code_only(owner)
            for _, risky in ipairs({
                "World.create_particles",
                "World.create_screen_gui",
                "Material.set_texture",
                "Unit.set_texture_for_materials",
                "Managers.package:load(",
                "Managers.package:unload(",
            }) do
                H.equal(count_plain(code, risky), 0, risky .. " must not appear in this owner")
            end
        end)
    end

    H.test("public and dev owners are identical after stream normalization", function()
        local public_owner = read(STREAMS[1].dir .. OWNER)
        local dev_owner = read(STREAMS[2].dir .. OWNER)
        local normalized = dev_owner
            :gsub('get_mod%("wt_dev"%)', 'get_mod("wt")')
            :gsub("scripts/mods/weapon_tweaker_dev/", "scripts/mods/weapon_tweaker/")
        H.equal(normalized, public_owner)
    end)
end
