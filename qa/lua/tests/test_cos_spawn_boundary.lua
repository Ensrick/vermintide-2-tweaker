return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("Cosmetics #270 preserves native UnitSpawner semantics", function()
        local source = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua")
        local begin_at = assert(source:find(
            'mod:hook("UnitSpawner", "spawn_local_unit"', 1, true))
        local end_at = assert(source:find(
            "-- v0.9.5: HeroPreviewer._spawn_item_unit hook REMOVED", begin_at, true))
        local hook = source:sub(begin_at, end_at - 1)

        H.truthy(hook:find(
            "local unit = func(self, unit_name, position, rotation, material)", 1, true))
        H.truthy(hook:find("if not unit or not unit_alive(unit) then", 1, true))
        H.truthy(hook:find("replace_textures(unit)", 1, true))
        H.truthy(hook:find("add_particles(unit, self.world)", 1, true))
        H.equal(hook:find("Application.can_get", 1, true), nil)
        H.equal(hook:find("World.spawn_unit", 1, true), nil)
        H.equal(hook:find("POSITION_LOOKUP", 1, true), nil)
        H.equal(hook:find("return nil", 1, true), nil)

        local _, delegates = hook:gsub(
            "func%(self, unit_name, position, rotation, material%)", "")
        H.equal(delegates, 1, "native spawn must be delegated exactly once")
    end)

    H.test("Cosmetics #270 optional attachments retain their narrow residency gate", function()
        local source = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        local begin_at = assert(source:find(
            'mod:hook(AttachmentUtils, "create_attachment"', 1, true))
        local end_at = assert(source:find(
            "-- #270/#950: reject dead units", begin_at, true))
        local hook = source:sub(begin_at, end_at - 1)
        H.truthy(hook:find('local is_headpiece = slot_name == "slot_hat"', 1, true))
        H.truthy(hook:find("not _unit_resident(path)", 1, true))
        H.truthy(hook:find("if is_headpiece and type(path)", 1, true))
        H.truthy(hook:find(
            "return { unit = nil, name = item_data and item_data.name, item_data = item_data }",
            1, true))
        H.equal(hook:find('slot_name ~= "slot_hat"', 1, true), nil)
    end)
end
