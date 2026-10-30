-- resource-safety: cwv1159-husk-residency-force-load
--
-- Offline lock for #401: the husk override-unit residency ledger must record
-- SUCCESS (not attempts), and failed loads must be re-attempted on a bounded
-- retry path. The pass lives in _cwv_husk_residency_owner (moved verbatim out
-- of the CWV entry chunk by the #1159 slice), so these are source-pattern
-- locks on the exact ordering and retry markers in that module, plus an
-- entry-side assertion that no shadowing copy of the pass was left behind.
-- The deferred runtime query/lease bodies are also executed below through the
-- actual early owner and late husk installer; no resource algorithm is copied.

local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local entry_path = mod_root .. "_cwv_husk_residency_owner.lua"
    local main_entry_path = mod_root .. "character_weapon_variants.lua"
    local husk_path = mod_root .. "_cwv_husk_path.lua"
    local VANILLA = "units/weapons/player/wpn_qa_residency/wpn_qa_residency"
    local CUSTOM = "units/cwv_qa_borrowed/cwv_qa_borrowed"
    local DONOR = "units/weapons/player/wpn_qa_donor/wpn_qa_donor_3p"
    local function pack(...) return { n = select("#", ...), ... } end

    local function fixture(defer_husk)
        local f = { om = { HUSK_OVERRIDE_REF = "cwv_husk_override_units" },
            boot = { loads = {}, reads = {}, lines = {}, hooks = {} },
            loads = {}, reads = {}, lines = {}, queries = {} }
        local booting = true
        local env = setmetatable({ ItemMasterList = {
                dr_shield_axe = { right_hand_unit = VANILLA, can_wield = {} },
            }, WeaponSkins = { skins = {} }, Weapons = {},
            ScriptUnit = { has_extension = function() return false end },
            Unit = { alive = function() return true end },
            printf = function(fmt, ...)
                local target = booting and f.boot.lines or f.lines
                target[#target + 1] = string.format(fmt, ...)
            end,
        }, { __index = _G })
        env._G = env
        env.Application = { can_get = function(...)
            f.queries[#f.queries + 1] = pack(...); return true
        end }
        local package_manager = {}
        package_manager.load = function(...)
            local target = booting and f.boot.loads or f.loads
            target[#target + 1] = pack(...)
            if not booting and f.load_body then return f.load_body(...) end
        end
        package_manager.has_loaded = function(...)
            local target = booting and f.boot.reads or f.reads
            target[#target + 1] = pack(...)
            if not booting and f.loaded_body then return f.loaded_body(...) end
            return true
        end
        env.Managers = { package = package_manager }
        f.env, f.package = env, package_manager
        local mod = { hook = function(_, class, method, callback)
            assert(class == "SimpleHuskInventoryExtension" and method == "start_weapon_fx")
            f.boot.hooks[#f.boot.hooks + 1] = callback
        end }
        local function load(path)
            local chunk = assert(loadfile(path)); setfenv(chunk, env); return chunk()
        end
        load(entry_path)(mod, { om = f.om, variant_definitions = {} })
        booting = false
        local husk = load(husk_path)
        function f.install_husk()
            husk(mod, { om = f.om, variant_definitions = {}, find_def = function() end,
                is_unit = function(u) return u ~= nil end,
                apply_cwv_hand_transform = function() return true end,
                triplet_text = function() return "qa" end })
        end
        f.om.exact_appearance = load(mod_root .. "_cwv_exact_appearance.lua")
        if not defer_husk then f.install_husk() end
        return f
    end

    local function find_all(source, needle)
        local positions = {}
        local from = 1
        while true do
            local at = source:find(needle, from, true)
            if not at then break end
            positions[#positions + 1] = at
            from = at + 1
        end
        return positions
    end

    H.test("CWV husk residency force-loads keep their resource-safety marker", function()
        -- check_native_resource_safety is a diff gate: all Managers.package:load
        -- boundaries in this module are covered by one file-level marker, and the
        -- token must resolve to qa/ evidence. This test IS that evidence, so the
        -- marker and all four boundaries it covers are pinned together here.
        local source = read(entry_path)
        H.truthy(source:find("resource-safety: cwv1159-husk-residency-force-load", 1, true),
            "husk-residency owner lost its resource-safety marker")
        -- Match the executable call form, not the bare prefix: a doc comment
        -- above the first pass quotes the idiom as
        -- `Managers.package:load(unit_path, ref, nil, sync=true, ...)`, so a
        -- prefix count would read 3 and drift the moment that prose is edited.
        H.equal(#find_all(source, "Managers.package:load(path, ref, nil, true, true)"), 2,
            "exactly two boot package-load boundaries remain")
        H.equal(#find_all(source, "Managers.package:load(donor, _om.HUSK_OVERRIDE_REF, nil, true, true)"), 1,
            "exactly one deferred donor lease boundary remains")
        H.equal(#find_all(source, "Managers.package:load(path, _om.HUSK_OVERRIDE_REF, nil, true, true)"), 1,
            "exactly one deferred override lease boundary remains")
        H.equal(#find_all(read(main_entry_path), "resource-safety: cwv1159-husk-residency-force-load"), 0,
            "the marker must not be duplicated back into the entry")
        local residency_source = source
        local module_source = read(husk_path)
        for _, marker in ipairs({
            "_om._husk_material_donor_ready = function(base_unit)",
            "_om._husk_lease_override = function(base_unit)",
            "app.can_get",
            "[cwv:474] husk donor-material lease",
        }) do
            local first = residency_source:find(marker, 1, true)
            H.truthy(first, "missing residency owner anchor: " .. marker)
            H.equal(residency_source:find(marker, first + #marker, true), nil,
                "residency anchor must have one owner: " .. marker)
            H.equal(module_source:find(marker, 1, true), nil,
                "husk path must not retain residency anchor: " .. marker)
        end
        H.truthy(module_source:find("local _resource_ready = _om._install_husk_residency_queries(_husk_log_once)", 1, true))
        H.truthy(residency_source:find("return _resource_ready", 1, true), "owner returns the exact private resource closure")
    end)

    H.test("CWV #401 residency ledger records success only AFTER the load call", function()
        local source = read(entry_path)
        local ledger_writes = find_all(source, "_loaded[path] = true")
        H.equal(#ledger_writes, 1,
            "exactly one ledger write expected in the residency pass")
        local load_call = source:find(
            "Managers.package:load(path, ref, nil, true, true)", 1, true)
        H.truthy(load_call, "residency force-load call missing")
        H.truthy(load_call < ledger_writes[1],
            "#401: the ledger must be written AFTER the pcall load, "
            .. "inside the success branch -- not before the attempt")
        -- The write must sit inside `if ok then`, i.e. between the pcall result
        -- check and the failure branch.
        local ok_branch = source:find("if ok then", load_call, true)
        H.truthy(ok_branch and ok_branch < ledger_writes[1],
            "#401: ledger write is not guarded by the load-call success branch")
    end)

    H.test("CWV #401 failed residency loads are re-attempted on a bounded retry", function()
        local source = read(entry_path)
        H.truthy(source:find("_attempts[path] = (_attempts[path] or 0) + 1", 1, true),
            "per-path attempt counter missing")
        H.truthy(source:find("(_attempts[path] or 0) < _MAX_LOAD_ATTEMPTS", 1, true),
            "attempt cap missing -- the retry must be bounded")
        H.truthy(source:find("_MAX_LOAD_ATTEMPTS = {}, 3", 1, true)
                or source:find("local _MAX_LOAD_ATTEMPTS = 3", 1, true),
            "bounded retry cap constant missing")
        local calls = find_all(source, "_force_load_husk_override_units()")
        H.truthy(#calls >= 2,
            "the residency pass must run again on the retry edge "
            .. "(boot pass + on_all_mods_loaded), found " .. #calls .. " call(s)")
        H.truthy(source:find("previous_on_all_mods_loaded", 1, true),
            "the retry edge must preserve the earlier mod.on_all_mods_loaded handler")
    end)

    H.test("CWV #1159 the entry keeps no shadowing copy of the residency pass", function()
        -- The pass moved to _cwv_husk_residency_owner. A leftover copy in the
        -- entry would double every force-load and re-chain on_all_mods_loaded
        -- twice, so the entry must be clear of every producer marker.
        local entry = read(main_entry_path)
        for _, marker in ipairs({
            "local function _force_load_husk_override_units()",
            "local function _force_load_axe_shield_husk_units()",
            "_loaded[path] = true",
            "_attempts[path] = (_attempts[path] or 0) + 1",
            "_om._husk_override_unit_needs_residency = function(def, field)",
        }) do
            H.equal(#find_all(entry, marker), 0,
                "entry must not retain residency-pass marker: " .. marker)
        end
        -- ...and it must load the owner exactly once, at one site.
        H.equal(#find_all(entry, "_cwv_husk_residency_owner"), 1,
            "entry must dofile the residency owner from exactly one site")
    end)

    H.test("CWV #2 deferred residency installation preserves the boot prefix", function()
        local f = fixture(true)
        H.equal(type(f.om._install_husk_residency_queries), "function")
        local exports = { "_husk_resource_ready", "_husk_custom_unit_material_donors",
            "_husk_material_donor_ready", "_husk_lease_override", "_husk_unit_spawnable",
            "_preview_override_3p" }
        for _, key in ipairs(exports) do H.equal(rawget(f.om, key), nil, "late export is not eager: " .. key) end
        H.equal(#f.boot.loads, 2, "actual axe/shield boot prefix retained")
        H.equal(#f.boot.reads, 2)
        H.equal(#f.boot.lines, 2)
        H.equal(#f.boot.hooks, 1)
        H.equal(#f.queries, 0)
        f.install_husk()
        for _, key in ipairs(exports) do
            H.equal(type(f.om[key]), key == "_husk_custom_unit_material_donors" and "table" or "function",
                "actual husk install publishes deferred export: " .. key)
        end
        H.equal(#f.loads, 0, "defining deferred helpers must not lease")
        H.equal(#f.reads, 0, "defining deferred helpers must not query packages")
        H.equal(#f.queries, 0, "defining deferred helpers must not query resources")
        H.equal(#f.boot.loads, 2, "boot observations are not cleared or replayed")
        H.equal(#f.boot.hooks, 1)
    end)

    H.test("CWV #2 resource truth and package fallback remain late and exact", function()
        local f = fixture()
        H.equal(f.om._husk_resource_ready("unit", VANILLA), true, "exact true resource verdict")
        H.deep_equal(f.queries[1], pack("unit", VANILLA), "can_get is a plain two-argument call")
        for _, value in ipairs({ false, 1, "true", {} }) do
            f.env.Application = { can_get = function() return value end }
            H.equal(f.om._husk_resource_ready("unit", VANILLA), false)
        end
        f.env.Application = { can_get = function() return nil end }
        H.equal(f.om._husk_resource_ready("unit", VANILLA), false)
        f.env.Application = false
        H.equal(f.om._husk_resource_ready("unit", VANILLA), nil)
        f.env.Application = { can_get = "not callable" }
        H.equal(f.om._husk_resource_ready("unit", VANILLA), nil)
        local opaque = {}
        f.env.Application = { can_get = function() error(opaque) end }
        H.equal(f.om._husk_resource_ready("unit", VANILLA), nil)
        f.env.Application = { can_get = function() return false end }
        H.equal(f.om._husk_unit_spawnable(VANILLA), false)
        H.equal(#f.reads, 0, "known false must not fall back to package bookkeeping")
        f.env.Application = false
        H.equal(f.om._husk_unit_spawnable(VANILLA), true)
        H.deep_equal(f.reads[1], pack(f.package, VANILLA .. "_3p"), "fallback preserves self/path and no ref")
        for _, value in ipairs({ false, 1, "true" }) do
            f.loaded_body = function() return value end
            H.equal(f.om._husk_unit_spawnable(VANILLA), false)
        end
        f.loaded_body = function() error(opaque) end
        H.equal(f.om._husk_unit_spawnable(VANILLA), false)
        f.env.Managers = false
        H.equal(f.om._husk_unit_spawnable(VANILLA), false)
        local replacement = {}
        replacement.has_loaded = function(self, path)
            H.equal(self, replacement); H.equal(path, VANILLA .. "_3p"); return true
        end
        f.env.Managers = { package = replacement }
        H.equal(f.om._husk_unit_spawnable(VANILLA), true, "package manager is read at call time")
    end)

    H.test("CWV #2 donor leases consume attempts before failure and prefer 3p", function()
        local f = fixture()
        H.equal(f.om._husk_material_donor_ready(CUSTOM), true, "undeclared donor needs no lease")
        H.equal(#f.loads, 0)
        f.om._husk_custom_unit_material_donors[CUSTOM] = "wrong-base-donor"
        f.om._husk_custom_unit_material_donors[CUSTOM .. "_3p"] = DONOR
        f.env.Application = false
        f.load_body = function() error({}) end
        H.equal(f.om._husk_material_donor_ready(CUSTOM), false)
        H.deep_equal(f.loads[1], pack(f.package, DONOR, f.om.HUSK_OVERRIDE_REF, nil, true, true))
        H.equal(f.om._husk_material_donor_ready(CUSTOM), false)
        H.equal(#f.loads, 1, "throwing first donor load still consumes its attempt")
        H.equal(#f.lines, 1)
        H.truthy(f.lines[1]:find("lease FAILED:", 1, true))
        f.env.Application = { can_get = function(kind, name)
            H.equal(kind, "material"); H.equal(name, DONOR); return true
        end }
        H.equal(f.om._husk_material_donor_ready(CUSTOM), true, "late donor residency admits without another lease")
        H.equal(#f.loads, 1)
        H.equal(f.om._husk_material_donor_ready(nil), false)
        H.equal(f.om._husk_material_donor_ready(""), false)
    end)

    H.test("CWV #2 override leases preserve attempt order tuples and current ref", function()
        local f = fixture()
        for _, value in ipairs({ false, 1, "", CUSTOM, "units/weapons/player/wpn_invisible_weapon" }) do
            H.equal(f.om._husk_lease_override(value), false)
        end
        H.equal(f.om._husk_lease_override(nil), false)
        H.equal(#f.loads, 0)
        f.load_body = function(_, path)
            if path == VANILLA then error({}) end
        end
        H.equal(f.om._husk_lease_override(VANILLA), true, "3p success survives base load failure")
        H.deep_equal(f.loads[1], pack(f.package, VANILLA, "cwv_husk_override_units", nil, true, true))
        H.deep_equal(f.loads[2], pack(f.package, VANILLA .. "_3p", "cwv_husk_override_units", nil, true, true))
        local repeated = f.om._husk_lease_override(VANILLA)
        H.equal(#f.loads, 2, "override attempts are consumed before protected loads")
        H.equal(repeated, false, "repeat reports no new queue work")
        f.om.HUSK_OVERRIDE_REF = "qa-current-second-ref"
        local second = VANILLA .. "_second"
        f.load_body = function(_, path) if path == second .. "_3p" then error({}) end end
        H.equal(f.om._husk_lease_override(second), true, "base success survives 3p load failure")
        H.deep_equal(f.loads[3], pack(f.package, second, "qa-current-second-ref", nil, true, true),
            "new override load uses current reference")
        H.deep_equal(f.loads[4], pack(f.package, second .. "_3p", "qa-current-second-ref", nil, true, true))
        local third = VANILLA .. "_third"
        f.load_body = function() error({}) end
        H.equal(f.om._husk_lease_override(third), false, "all protected loads failed")
        H.equal(#f.loads, 6)
        H.equal(f.om._husk_lease_override(third), false)
        H.equal(#f.loads, 6)
        H.equal(#f.lines, 6, "one log per attempted path, no repeat logs")
        f.env.Managers = false
        H.equal(f.om._husk_lease_override(VANILLA .. "_no_manager"), false)
        H.equal(#f.loads, 6)
    end)

    H.test("CWV #2 real preview keeps borrowed meshes BASE and reads current collaborators", function()
        local f = fixture()
        f.om._husk_custom_bundle_unit = function(unit) return unit == CUSTOM end
        f.om._husk_custom_unit_material_donors[CUSTOM .. "_3p"] = DONOR
        f.env.Application = { can_get = function() return false end }
        H.equal(f.om._preview_override_3p(CUSTOM), nil, "borrowed preview must keep BASE without donor material")
        H.equal(#f.loads, 1)
        f.env.Application = { can_get = function() return true end }
        H.equal(f.om._preview_override_3p(CUSTOM), CUSTOM .. "_3p")
        f.om._husk_custom_unit_material_donors[CUSTOM .. "_3p"] = nil
        f.env.Application = false
        H.equal(f.om._preview_override_3p(CUSTOM), CUSTOM .. "_3p", "self-contained bundle needs no foreign donor")
        local resident, spawnable = function() return "qa-resident-3p" end, function() error("not reached") end
        f.om._resident_override_3p, f.om._husk_unit_spawnable = resident, spawnable
        H.equal(f.om._preview_override_3p(CUSTOM), "qa-resident-3p")
        f.om.exact_appearance = { resolve_preview_3p = function(base, actual_resident, actual_spawnable)
            H.equal(base, CUSTOM); H.equal(actual_resident, resident); H.equal(actual_spawnable, spawnable)
            return "late resolver"
        end }
        H.equal(f.om._preview_override_3p(CUSTOM), "late resolver")
    end)

    H.test("CWV #2 residency installations isolate state and reset on husk reinstall", function()
        local a, b = fixture(), fixture()
        H.equal(rawequal(a.om._husk_custom_unit_material_donors, b.om._husk_custom_unit_material_donors), false)
        a.env.Application, b.env.Application = false, false
        a.om._husk_custom_unit_material_donors[CUSTOM] = DONOR
        b.om._husk_custom_unit_material_donors[CUSTOM] = DONOR
        H.equal(a.om._husk_material_donor_ready(CUSTOM), false)
        H.equal(b.om._husk_material_donor_ready(CUSTOM), false)
        H.equal(#a.loads, 1); H.equal(#b.loads, 1)
        H.equal(#a.lines, 1); H.equal(#b.lines, 1)
        a.om._husk_lease_override(VANILLA)
        local old = a.om._husk_custom_unit_material_donors
        a.install_husk()
        H.equal(rawequal(a.om._husk_custom_unit_material_donors, old), false)
        H.equal(next(a.om._husk_custom_unit_material_donors), nil, "donor declarations reset")
        a.om._husk_custom_unit_material_donors[CUSTOM] = DONOR
        a.om._husk_material_donor_ready(CUSTOM)
        H.equal(a.om._husk_lease_override(VANILLA), true)
        H.equal(#a.loads, 6, "both runtime attempt ledgers reset for a new husk install")
        H.equal(#a.lines, 6, "new parent logger is passed on each husk install")
        H.equal(#b.loads, 1); H.equal(#b.lines, 1)
    end)

    H.test("CWV #2 uncaught residency errors preserve opaque identity and prefix", function()
        local f = fixture()
        local opaque = {}
        f.env.Application = false
        f.om._husk_custom_unit_material_donors[CUSTOM] = DONOR
        f.env.printf = function() error(opaque) end
        local ok, err = pcall(f.om._husk_material_donor_ready, CUSTOM)
        H.equal(ok, false); H.equal(rawequal(err, opaque), true, "logger error identity retained")
        H.equal(#f.loads, 1, "load prefix survives logger error")
        H.equal(f.om._husk_material_donor_ready(CUSTOM), false, "attempt remains consumed after logger error")
        H.equal(#f.loads, 1)
        f.om._husk_custom_bundle_unit = function() error(opaque) end
        ok, err = pcall(f.om._husk_unit_spawnable, CUSTOM)
        H.equal(ok, false); H.equal(rawequal(err, opaque), true, "predicate error identity retained")
        f.om.exact_appearance = { resolve_preview_3p = function() error(opaque) end }
        ok, err = pcall(f.om._preview_override_3p, CUSTOM)
        H.equal(ok, false); H.equal(rawequal(err, opaque), true, "resolver error identity retained")
    end)
end
