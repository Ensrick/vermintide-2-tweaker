return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_link_policy.lua")

    local function names(values)
        local present = {}
        for _, value in ipairs(values) do
            present[value] = true
        end
        return function(value)
            return present[value] == true
        end
    end

    H.test("Cosmetics #950 preserves a complete attachment map", function()
        local first = { source = "root", target = "root" }
        local second = { source = "hand", target = "hand" }
        local valid, skipped, reason = policy.partition(
            { first, second }, names({ "root", "hand" }), names({ "root", "hand" }))

        H.equal(reason, "ok")
        H.equal(#valid, 2)
        H.equal(valid[1], first)
        H.equal(valid[2], second)
        H.equal(#skipped, 0)
    end)

    H.test("Cosmetics #950 skips only absent optional nodes", function()
        local root = { source = "root", target = "root" }
        local fingertip = { source = "finger4", target = "finger4" }
        local hand = { source = "hand", target = "hand" }
        local valid, skipped = policy.partition(
            { root, fingertip, hand },
            names({ "root", "finger4", "hand" }),
            names({ "root", "hand" }))

        H.equal(#valid, 2)
        H.equal(valid[1], root)
        H.equal(valid[2], hand)
        H.equal(#skipped, 1)
        H.equal(skipped[1].index, 2)
        H.equal(skipped[1].missing, "target")
        H.equal(skipped[1].target, "finger4")
    end)

    H.test("Cosmetics #950 accepts numeric engine node indices", function()
        local numeric = { source = 0, target = 1 }
        local valid, skipped = policy.partition(
            { numeric }, names({}), names({}))

        H.equal(#valid, 1)
        H.equal(valid[1], numeric)
        H.equal(#skipped, 0)
    end)

    H.test("Cosmetics #950 exposes a zero-valid-link result", function()
        local valid, skipped = policy.partition(
            { { source = "head", target = "head" } },
            names({ "head" }), names({}))

        H.equal(#valid, 0)
        H.equal(#skipped, 1)
    end)

    H.test("Cosmetics #950 runtime wrapper delegates the surviving map", function()
        local source_unit = newproxy(true)
        local target_unit = newproxy(true)
        local installed_hook
        local logged_partial = false
        local queued_target
        local source_nodes = names({ "root", "finger4", "hand" })
        local target_nodes = names({ "root", "hand" })
        local root = { source = "root", target = "root" }
        local fingertip = { source = "finger4", target = "finger4" }
        local hand = { source = "hand", target = "hand" }

        local unit_api = {
            alive = function(unit)
                return unit == source_unit or unit == target_unit
            end,
            has_node = function(unit, node)
                return unit == source_unit and source_nodes(node) or target_nodes(node)
            end,
            has_data = function(unit, key)
                return unit == target_unit and key == "unit_name"
            end,
            get_data = function()
                return "pusfume_1p"
            end,
        }

        local ok, err = pcall(function()
            local mod = {
                hook = function(_, _, method, callback)
                    H.equal(method, "link")
                    installed_hook = callback
                end,
                info = function(_, message)
                    if message:find("PARTIAL attach linked=", 1, true) then
                        logged_partial = true
                    end
                end,
            }
            local bridge = {
                registered = true,
                maybe_queue_unit = function(_, target)
                    queued_target = target
                end,
            }
            local attachment_utils = { link = function() end }

            H.truthy(policy.install(mod, attachment_utils, bridge, unit_api))
            H.truthy(installed_hook)

            local delegated
            installed_hook(function(_, delegated_source, delegated_target, links)
                H.equal(delegated_source, source_unit)
                H.equal(delegated_target, target_unit)
                delegated = links
            end, {}, source_unit, target_unit, { root, fingertip, hand })

            H.equal(#delegated, 2)
            H.equal(delegated[1], root)
            H.equal(delegated[2], hand)
            H.truthy(logged_partial)
            H.equal(queued_target, target_unit)
        end)

        if not ok then error(err, 0) end
    end)

    H.test("Cosmetics #950 production hook passes only valid pairs to vanilla", function()
        local entry_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local module_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_link_policy.lua"
        local entry_file = assert(io.open(entry_path, "rb"))
        local entry = entry_file:read("*a")
        entry_file:close()
        local module_file = assert(io.open(module_path, "rb"))
        local source = module_file:read("*a")
        module_file:close()

        H.truthy(entry:find("_cos_attachment_link_policy.install(", 1, true))
        H.truthy(source:find("func(world, source, target, links)", 1, true))
        H.truthy(source:find("PARTIAL attach linked=", 1, true))
        H.equal(source:find("aborting link, no partial state", 1, true), nil)
    end)
end
