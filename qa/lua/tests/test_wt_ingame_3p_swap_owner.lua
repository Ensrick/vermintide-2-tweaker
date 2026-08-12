-- Boundary test for the #1159 in-game 3P weapon-mesh swap owner (wt + wt_dev).
--
-- Engine-free. Asserts the structural contract of the split across BOTH streams
-- of the mirror pair: bare-dofile wiring at the former execution position, the
-- load-order window between the NetworkLookup-appending owners above and the
-- preview owner below, single ownership of the GearUtils.spawn_inventory_unit
-- seam, entry-side absence of every moved file-scope local, the late-binding
-- accessors that replace the closed-over entry locals, the 3P-only invariant on
-- the swap helpers, and exact public/dev parity of the owner itself.
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

    local OWNER = "_wt_ingame_3p_swap_owner.lua"

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

    -- Absence assertions run against CODE, not prose. The moved blocks carry
    -- long explanatory comments that legitimately name the very identifiers and
    -- classes the invariants forbid at a call site, so full-line comments are
    -- dropped first. Nothing here spans a line boundary inside a string.
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
        local dofile_call = 'mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_ingame_3p_swap_owner")'

        H.test(stream.tag .. ": owner is bare-dofile'd exactly once by the entry", function()
            H.equal(count_plain(entry, dofile_call), 1)
            -- Bare dofile, not an installer and never an anonymous returned
            -- function: the module body must run at file scope exactly where the
            -- block used to execute, which is what preserves hook order.
            H.equal(count_plain(owner, "function M.install"), 0)
            H.equal(count_plain(owner, "return function"), 0)
            H.equal(count_plain(owner, 'local mod = get_mod("' .. stream.mod_id .. '")'), 1)
        end)

        H.test(stream.tag .. ": dofile sits between the NetworkLookup owners and the preview owner", function()
            local balance_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_weapon_balance_patches")', 1, true)
            local moonfire_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_moonfire_aoe")', 1, true)
            local owner_at = entry:find(dofile_call, 1, true)
            local preview_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_menu_preview_owner")', 1, true)
            H.truthy(balance_at, "balance-patch owner dofile must exist in the entry")
            H.truthy(moonfire_at, "moonfire owner dofile must exist in the entry")
            H.truthy(owner_at, "3P swap owner dofile must exist in the entry")
            H.truthy(preview_at, "preview owner dofile must exist in the entry")
            -- Both owners above append to NetworkLookup at load, so the swap
            -- dispatch must stay downstream of them; the preview owner stays
            -- downstream of the swap dispatch.
            H.truthy(balance_at < owner_at, "swap owner must load after _wt_weapon_balance_patches")
            H.truthy(moonfire_at < owner_at, "swap owner must load after _wt_moonfire_aoe")
            H.truthy(owner_at < preview_at, "swap owner must load before the preview owner")
        end)

        H.test(stream.tag .. ": the spawn_inventory_unit seam is owned once, and left the entry", function()
            H.equal(count_plain(owner, 'mod:traced_hook("GearUtils", "spawn_inventory_unit", function(func, world, hand,'), 1)
            -- Whole-entry cardinality: no registration of any kind may remain.
            for _, verb in ipairs({ "mod:hook(", "mod:hook_safe(", "mod:traced_hook(", "mod:safe_hook(" }) do
                H.equal(count_plain(entry, verb .. '"GearUtils", "spawn_inventory_unit"'), 0,
                    verb .. ' must not re-register spawn_inventory_unit in the entry')
            end
            -- The three helpers are plain functions called from that one body,
            -- never second registrations (VMF drops a duplicate silently).
            for _, helper in ipairs({
                "_wt_longbow_3p_swap_apply",
                "_wt_repeating_pistol_3p_swap_apply",
                "_wt_hammer_book_3p_swap_apply",
            }) do
                H.equal(count_plain(owner, "local " .. helper), 1, helper .. " must be forward-declared once in the owner")
                H.equal(count_plain(owner, helper .. " = function("), 1, helper .. " must be assigned once in the owner")
                H.equal(count_plain(entry, helper), 0, helper .. " must not remain in the entry")
            end
        end)

        H.test(stream.tag .. ": every moved file-scope local left the entry", function()
            for _, decl in ipairs({
                "local _wt_longbow_3p_swap_apply",
                "local _wt_repeating_pistol_3p_swap_apply",
                "local _wt_hammer_book_3p_swap_apply",
            }) do
                H.equal(count_plain(owner, decl), 1, decl .. " must be declared once in the owner")
                H.equal(count_plain(entry, decl), 0, decl .. " must not remain in the entry")
            end
        end)

        H.test(stream.tag .. ": crossings are late-bound through mod._wt, published before the dofile", function()
            local publications = {
                { field = "is_sp_crossbow_presentation_item", local_name = "_is_sp_crossbow_presentation_item" },
                { field = "brace_repeater_3p_unit", local_name = "_BRACE_REPEATER_3P_UNIT" },
                { field = "sp_crossbow_3p_unit", local_name = "_SP_CROSSBOW_3P_UNIT" },
                { field = "sp_crossbow_bolt_3p_unit", local_name = "_SP_CROSSBOW_BOLT_3P_UNIT" },
                { field = "skullsplitter_hand_policy", local_name = "_wt_skullsplitter_hand_policy" },
            }
            local dofile_at = entry:find(dofile_call, 1, true)
            for _, row in ipairs(publications) do
                local publish_at = entry:find("mod._wt." .. row.field, 1, true)
                H.truthy(publish_at, row.field .. " must be published by the entry")
                H.truthy(publish_at < dofile_at, row.field .. " must be published BEFORE the owner dofile")
                -- The owner reads the published value; it must not re-derive it
                -- (a second mod:dofile of a policy returns a different table).
                H.equal(count_plain(owner, "= mod._wt." .. row.field), 1,
                    row.field .. " must be read exactly once by the owner")
                H.equal(count_plain(owner, "local " .. row.local_name .. " "), 1,
                    row.local_name .. " must be a file-local in the owner")
            end
            -- These three were already on the namespace before this slice.
            -- Match the whole declaration: "= mod._wt.dbg" is also a prefix of
            -- "= mod._wt.dbg_alert".
            for _, decl in ipairs({
                "local _dbg                              = mod._wt.dbg\n",
                "local _dbg_alert                        = mod._wt.dbg_alert\n",
                "local _unit_career_name                 = mod._wt.unit_career_name\n",
            }) do
                H.equal(count_plain(owner, decl), 1, decl:gsub("\n", "") .. " must be read from the namespace")
            end
        end)

        H.test(stream.tag .. ": the swap helpers stay 3P-only", function()
            -- 1P is universal across all six characters; a swap that reassigned
            -- or destroyed v_w1p / v_a1p would break every native wielder's
            -- first person. Vanilla's 1P pair is captured once and forwarded.
            local code = code_only(owner)
            H.equal(count_plain(code, "v_w1p ="), 0, "the owner must never assign the 1P weapon unit")
            H.equal(count_plain(code, "mark_for_deletion(v_w1p"), 0, "the owner must never destroy a 1P weapon unit")
            H.equal(count_plain(code, "set_unit_visibility(v_w1p"), 0, "the owner must never hide a 1P weapon unit")
            H.equal(count_plain(code, "mark_for_deletion(v_a1p"), 0, "the owner must never destroy a 1P ammo unit")
            H.equal(count_plain(code, "set_unit_visibility(v_a1p"), 0, "the owner must never hide a 1P ammo unit")
            -- The ONLY write to the 1P pair is the multi-assignment that
            -- captures vanilla's four returns, once, in the dispatch body.
            H.equal(count_plain(code, "local v_w3p, v_a3p, v_w1p, v_a1p ="), 1,
                "vanilla's four returns are captured exactly once")
            H.equal(count_plain(code, "v_a1p ="), 1,
                "the capture is the only assignment that names the 1P ammo unit")
            H.truthy(count_plain(code, "v_w1p, v_a1p") > 1, "vanilla 1P returns must be forwarded unchanged")
        end)

        H.test(stream.tag .. ": no native resource boundary moved with the code", function()
            -- The gate in check_native_resource_safety.ps1 covers particles, GUI,
            -- textures and package load/unload. This owner only reads package
            -- residency, which is not one of them - so it needs no token, and
            -- must not acquire one of those calls by accident later.
            local code = code_only(owner)
            for _, risky in ipairs({
                "World.create_particles",
                "World.create_screen_gui",
                "Material.set_texture",
                "Managers.package:load(",
                "Managers.package:unload(",
            }) do
                H.equal(count_plain(code, risky), 0, risky .. " must not appear in this owner")
            end
            H.truthy(count_plain(code, "Managers.package:has_loaded(") > 0,
                "package residency checks travelled with the swap helpers")
        end)

        H.test(stream.tag .. ": visibility re-hide belongs to the 3P swap owner", function()
            local code = code_only(owner)
            H.equal(count_plain(code,
                'mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory"'), 1)
            H.equal(count_plain(code,
                'mod:hook_safe("SimpleHuskInventoryExtension", "show_third_person_inventory"'), 1)
            H.equal(count_plain(code, "local function _rehide_hidden_3p_units"), 1)
            H.equal(count_plain(code_only(entry), "_rehide_hidden_3p_units"), 0,
                "the entry must not retain a second visibility owner")
        end)
    end

    H.test("public and dev owners are identical after stream normalization", function()
        local public_owner = read(STREAMS[1].dir .. OWNER)
        local dev_owner = read(STREAMS[2].dir .. OWNER)
        local normalized = dev_owner:gsub('get_mod%("wt_dev"%)', 'get_mod("wt")')
        H.equal(normalized, public_owner)
    end)
end
