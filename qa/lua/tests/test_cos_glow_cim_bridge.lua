-- Issue 48: CIM stores one bounded opaque backup for an exact item+illusion.
return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_cim_bridge.lua"
    local Bridge = dofile(path)

    local function state(r)
        return { rune = { r = r or 255, g = 20, b = 30, intensity = 1.5 } }
    end

    H.test("Cosmetics #48 CIM blob is bounded and exact-instance scoped", function()
        local source = state(300)
        source.unbounded = { nested = { payload = true } }
        local blob = Bridge.make_blob("backend:bid-a|skin:magic", source)
        H.equal(blob.schema, 1)
        H.equal(blob.provider, "cosmetics_tweaker.glow")
        H.equal(blob.identity, "backend:bid-a|skin:magic")
        H.equal(blob.state.rune.r, 255)
        H.equal(blob.state.unbounded, nil)
        source.rune.g = 99
        H.equal(blob.state.rune.g, 20)
    end)

    H.test("Cosmetics #48 CIM restore rejects schema and illusion drift", function()
        local identity = "backend:bid-a|skin:magic"
        local record = { custom_glow = Bridge.make_blob(identity, state()) }
        local restored, reason = Bridge.state_from_record(record, identity)
        H.equal(reason, "matched")
        H.equal(restored.rune.b, 30)
        H.equal(Bridge.state_from_record(record, "backend:bid-a|skin:runed"), nil)
        record.custom_glow.schema = 99
        H.equal(Bridge.state_from_record(record, identity), nil)
    end)

    H.test("Cosmetics #48 CIM bridge prefers the dev stream", function()
        local stable, dev = {}, {}
        local function get_mod(name)
            if name == "cim" then return stable end
            if name == "cim_dev" then return dev end
        end
        H.equal(Bridge.resolve_cim(get_mod), dev)
    end)

    H.test("Cosmetics #48 CIM write and read use public exact-craft APIs", function()
        local records = { ["bid-a"] = {} }
        local cim = {
            _cim_get_craft = function(bid) return records[bid] end,
            _cim_set_custom_glow = function(bid, blob)
                if not records[bid] then return false end
                records[bid].custom_glow = blob
                return true
            end,
        }
        local identity = "backend:bid-a|skin:magic"
        H.equal(Bridge.write(cim, "bid-a", identity, state()), true)
        local restored = Bridge.read(cim, "bid-a", identity)
        H.equal(restored.rune.r, 255)
        H.equal(Bridge.write(cim, "vanilla", identity, state()), false)
    end)

    H.test("Cosmetics #48 CIM clear cannot erase another illusion", function()
        local identity = "backend:bid-a|skin:magic"
        local record = { custom_glow = Bridge.make_blob(identity, state()) }
        local writes = 0
        local cim = {
            _cim_get_craft = function() return record end,
            _cim_set_custom_glow = function(_, blob)
                writes = writes + 1
                record.custom_glow = blob
                return true
            end,
        }
        H.equal(Bridge.clear(cim, "bid-a", "backend:bid-a|skin:runed"), false)
        H.equal(writes, 0)
        H.equal(Bridge.clear(cim, "bid-a", identity), true)
        H.equal(writes, 1)
        H.equal(record.custom_glow, nil)
    end)

    H.test("Cosmetics #48 CIM bridge fails closed on malformed siblings", function()
        H.equal(Bridge.write(nil, "bid", "identity", state()), false)
        H.equal(Bridge.read({}, "bid", "identity"), nil)
        H.equal(Bridge.make_blob("identity", { rune = { r = "bad" } }), nil)
    end)

    H.test("Cosmetics #48 CIM registration is bounded and idempotent", function()
        local lifecycle, registrations = {}, 0
        local cim = {
            _cim_get_craft = function() end,
            _cim_set_custom_glow = function() return true end,
            _cim_register_restore_callback = function()
                registrations = registrations + 1
                return true
            end,
        }
        H.equal(Bridge.registration_status(lifecycle), "pending")
        H.equal(Bridge.ensure_registration(lifecycle, nil, 0, function() end), false)
        H.equal(Bridge.ensure_registration(lifecycle, cim, 0.5, function() end), false)
        H.equal(registrations, 0)
        H.equal(Bridge.ensure_registration(lifecycle, cim, 1, function() end), true)
        H.equal(Bridge.registration_status(lifecycle), "registered")
        H.equal(Bridge.ensure_registration(lifecycle, cim, 2, function() end), true)
        H.equal(registrations, 1)
    end)

    H.test("Cosmetics #48 CIM restore callback rebinds realized units once", function()
        local unit_a, unit_b = {}, {}
        local seen, repaints = {}, 0
        local imported = Bridge.rebind_units(
            { [unit_a] = "bid-a", [unit_b] = "bid-b" },
            { [unit_a] = { skin = "magic" }, [unit_b] = { skin = "runed" } },
            function(backend_id, slot_data)
                seen[backend_id] = slot_data.skin
                return backend_id == "bid-a" and state() or nil
            end,
            function() repaints = repaints + 1 end)
        H.equal(imported, 1)
        H.equal(seen["bid-a"], "magic")
        H.equal(seen["bid-b"], "runed")
        H.equal(repaints, 1)
    end)
end
