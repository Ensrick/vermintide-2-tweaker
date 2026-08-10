-- Boundary test for the #1159 Moonfire Bow AOE owner extraction (wt + wt_dev).
--
-- Engine-free. Asserts the structural contract of the split across BOTH streams
-- of the mirror pair: bare-dofile wiring at the former execution position, hook
-- ownership and cardinality on the six projectile-impact seams, entry-side
-- absence of every moved file-scope local, the #535 registration needles that
-- keep the AoE template resolvable locally and wire-deterministic, the single
-- annotated native particle boundary (resource-safety token
-- wt_535_moonfire_aoe_owner), and exact public/dev parity of the owner itself.
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

    for _, stream in ipairs(STREAMS) do
        local entry = read(stream.dir .. stream.entry)
        local owner = read(stream.dir .. "_wt_moonfire_aoe.lua")
        local dofile_call = 'mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_moonfire_aoe")'

        H.test(stream.tag .. ": owner is bare-dofile'd exactly once by the entry", function()
            H.equal(count_plain(entry, dofile_call), 1)
            -- Bare dofile, not an installer call. The module body must run at
            -- file scope exactly where the block used to execute, which is what
            -- preserves hook-registration order and the _rt_register append order.
            H.equal(count_plain(owner, "function M.install"), 0)
            H.equal(count_plain(owner, "return function"), 0)
            H.equal(count_plain(owner, 'local mod = get_mod("' .. stream.mod_id .. '")'), 1)
            -- The moved lines closed over the entry's file-scope _rt_register.
            -- The owner must re-read the same published function, not invent one.
            H.equal(count_plain(owner, "local _rt_register = mod._wt.rt_register"), 1)
        end)

        H.test(stream.tag .. ": dofile sits between _wt_regression and the 3P swap dispatch", function()
            local regression_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_regression")', 1, true)
            local owner_at = entry:find(dofile_call, 1, true)
            local swap_at = entry:find("local _wt_longbow_3p_swap_apply", 1, true)
            H.truthy(regression_at, "_wt_regression dofile must exist in the entry")
            H.truthy(owner_at, "moonfire owner dofile must exist in the entry")
            H.truthy(swap_at, "3P swap forward declarations must exist in the entry")
            -- _rt_register must already be published, and the impact hooks must
            -- still register before the cross-character swap dispatch below.
            H.truthy(regression_at < owner_at, "moonfire owner must load after _wt_regression")
            H.truthy(owner_at < swap_at, "moonfire owner must load before the 3P swap dispatch")
        end)

        H.test(stream.tag .. ": the impact hook loop is owned once, and left the entry", function()
            -- One source registration site expanding to 2 classes x 3 methods.
            H.equal(count_plain(owner, "mod:hook_safe(cls, method_name, function(self, impact_data, hit_unit, hit_position)"), 1)
            H.equal(count_plain(entry, "mod:hook_safe(cls, method_name,"), 0)
            -- Quoted class names only: the entry still carries an unrelated
            -- PlayerProjectileUnitExtension mention in a #431 damage-profile
            -- comment, which is prose, not a hook root.
            for _, needle in ipairs({
                '"PlayerProjectileUnitExtension"',
                '"PlayerProjectileHuskExtension"',
                "_moonfire_hooked_classes",
                "_moonfire_hooked_methods",
            }) do
                H.equal(count_plain(owner, needle) > 0, true, needle .. " must live in the owner")
                H.equal(count_plain(entry, needle), 0, needle .. " must not remain in the entry")
            end
            -- Whole-mod cardinality on the three impact methods: nothing outside
            -- the owner may re-hook them, in either stream.
            for _, method in ipairs({ '"hit_enemy"', '"hit_level_unit"', '"hit_non_level_unit"' }) do
                H.equal(count_plain(entry, method), 0, method .. " must not be referenced by the entry")
            end
        end)

        H.test(stream.tag .. ": every moved file-scope local left the entry", function()
            for _, decl in ipairs({
                "local _MOONFIRE_PUFF_FX",
                "local _MOONFIRE_AOE_NAME",
                "local _MOONFIRE_AOE_TEMPLATE",
                "local _moonfire_jitter_offsets",
                "local function _is_moonfire_arrow",
                "local function _wt_moonfire_on_hit",
            }) do
                H.equal(count_plain(owner, decl), 1, decl .. " must be declared once in the owner")
                H.equal(count_plain(entry, decl), 0, decl .. " must not remain in the entry")
            end
            -- The toggle read is the owner's only settings dependency.
            H.equal(count_plain(owner, 'mod:get("moonfire_aoe_revert")'), 1)
            H.equal(count_plain(entry, 'mod:get("moonfire_aoe_revert")'), 0)
        end)

        H.test(stream.tag .. ": #535 registration needles travelled intact", function()
            -- Local resolution: ExplosionUtils.get_template reads ExplosionTemplates
            -- by the .name the template itself carries, so both must be present.
            H.equal(count_plain(owner, "name = _MOONFIRE_AOE_NAME,"), 1)
            H.equal(count_plain(owner, "ExplosionTemplates[_MOONFIRE_AOE_NAME] = _MOONFIRE_AOE_TEMPLATE"), 1)
            -- Wire index determinism: forward AND reverse append, rawget-guarded.
            H.equal(count_plain(owner, "rawset(lookup, idx, _MOONFIRE_AOE_NAME)"), 1)
            H.equal(count_plain(owner, "rawset(lookup, _MOONFIRE_AOE_NAME, idx)"), 1)
            H.equal(count_plain(owner, 'mod._wt535_explosion_template_fallback[_MOONFIRE_AOE_NAME] = "machinegun_poison_arrow"'), 1)
            -- The regression check moved with the code it guards.
            H.equal(count_plain(owner, '_rt_register("wt_535_moonfire_explosion_registered"'), 1)
            H.equal(count_plain(entry, "wt_535_moonfire_explosion_registered"), 0)
        end)

        H.test(stream.tag .. ": the single native particle boundary stays annotated", function()
            H.equal(count_plain(owner, "World.create_particles("), 1)
            H.equal(count_plain(owner, "-- resource-safety: wt_535_moonfire_aoe_owner"), 1)
            -- The FX id is the Moonbow's own authored effect; it must not be
            -- rewritten into a free-standing string literal at the call site.
            H.equal(count_plain(owner, 'local _MOONFIRE_PUFF_FX = "fx/wpnfx_we_deus_01_impact"'), 1)
            H.equal(count_plain(owner, "World.create_particles(world, _MOONFIRE_PUFF_FX, p, Quaternion.identity())"), 1)
        end)
    end

    H.test("public and dev owners are identical after stream normalization", function()
        local public_owner = read(STREAMS[1].dir .. "_wt_moonfire_aoe.lua")
        local dev_owner = read(STREAMS[2].dir .. "_wt_moonfire_aoe.lua")
        local normalized = dev_owner:gsub('get_mod%("wt_dev"%)', 'get_mod("wt")')
        H.equal(normalized, public_owner)
    end)
end
