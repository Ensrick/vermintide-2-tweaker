return function(H, repo_root)
local root = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"); file:close()
    return (source:gsub("\r\n", "\n"))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = clone(child) end
    return copy
end
local function between(source, first, last)
    local from = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, from + #first, true), last)
    return source:sub(from, finish - 1)
end
local function fixture()
    local native_contacts = 0
    local function native_call()
        native_contacts = native_contacts + 1; error("unexpected native call")
    end
    local forbidden = setmetatable({}, { __index = function()
        native_contacts = native_contacts + 1; error("unexpected native contact")
    end, __call = native_call })
    local env = setmetatable({
        Unit = { alive = native_call, local_position = native_call, local_scale = native_call,
            local_rotation = native_call, set_local_pose = native_call },
        Vector3 = setmetatable({ to_elements = native_call }, { __call = native_call }),
        Quaternion = { from_euler_angles_xyz = native_call },
        Matrix4x4 = { from_quaternion_position_scale = native_call },
        Vector3Box = forbidden, QuaternionBox = forbidden,
        Managers = forbidden, NetworkLookup = forbidden, ItemMasterList = forbidden,
        printf = function() error("unexpected engine log") end,
        table = setmetatable({ clone = clone }, { __index = table }),
    }, { __index = _G })
    env._G = env
    local function load(name)
        local chunk = assert(loadfile(root .. name .. ".lua"))
        setfenv(chunk, env)
        return chunk()
    end
    local mod = { dofile = function(_, path)
        return load(assert(path:match("/([^/]+)$")))
    end }
    local om = {}
    for name, module in pairs({
        greataxe = "_cwv_greataxe", crowbill_family = "_cwv_crowbill_family",
        crowbill_hammer_mode = "_cwv_crowbill_hammer_mode",
        crowbill_presentation = "_cwv_crowbill_presentation",
        husk_transform_policy = "_cwv_husk_transform_policy",
        peer_resolver = "_cwv_peer_resolver", combat_style_policy = "_cwv_combat_styles",
        combat_style_appearance = "_cwv_combat_style_appearance",
        appearance_descriptor = "_lib_appearance_descriptor",
    }) do om[name] = load(module) end
    local install = load("_cwv_weapon_transform_owner")
    -- The real owner authors the Imperial record. Its whole install is safe
    -- only when the explicit appearance API is supplied; this seed install
    -- never calls the writer or any retained API.
    local seed = {}
    for _, name in ipairs({ "greataxe", "crowbill_family", "crowbill_hammer_mode",
        "crowbill_presentation", "husk_transform_policy", "peer_resolver",
        "combat_style_appearance" }) do seed[name] = om[name] end
    install(mod, { om = seed, variant_definitions = {}, find_def = function() end,
        custom_illusions = {}, custom_skin_keys = {}, appearance_api = {} })
    local entry = read(root .. "character_weapon_variants.lua")
    local inverse = between(entry, "\tlocal imperial_transform =", "\n\t-- #786: engine surfaces")
    local presentations = between(entry, "\t\tpresentations = {", "\n\t\tstyle_descriptor_transform =")
        :gsub("^%s*presentations = ", ""):gsub(",%s*$", "")
    local author = assert(loadstring(inverse .. "\nreturn " .. presentations,
        "=issue692_actual_authored_presentation"))
    setfenv(author, { _type_transforms = seed.weapon_transform.type_transforms })
    local authored = author()
    om.combat_styles = om.combat_style_policy.install({ get = function() return nil end }, {
        presentations = authored,
    })
    local base = { right_hand_unit =
        "units/weapons/player/wpn_emp_gk_sword_01_t1/wpn_emp_gk_sword_01_t1" }
    local deps = { mod = mod, om = om, transform_owner = install,
        find_def = function() end, base_item = base }
    return { check = load("_cwv_issue692_transform_check"), deps = deps, load = load,
        authored = authored, entry = entry, env = env,
        native_contacts = function() return native_contacts end }
end

H.test("CWV #692 named application check reads real authored and immutable production path", function()
    local f = fixture()
    local before = clone(f.authored)
    local err, proof = f.check.run(f.deps)
    H.equal(err, nil)
    H.equal(proof.scope, "detached_production_writer")
    H.equal(proof.transformed_units, 4)
    H.equal(proof.retained_writes, 8)
    H.equal(proof.live_surfaces_verified, false)
    H.deep_equal(f.authored, before)
    H.equal(f.native_contacts(), 0)
end)

for _, missing in ipairs({ "mod", "om", "transform_owner", "find_def", "base_item" }) do
    local name = missing
    H.test("CWV #692 missing " .. name .. " fails instead of skipping", function()
        local f = fixture()
        f.deps[name] = nil
        local result = f.check.run(f.deps)
        H.equal(type(result), "string")
        H.truthy(result:find("#692 dependency missing:", 1, true))
    end)
end

for _, missing in ipairs({ "greataxe", "crowbill_family", "crowbill_hammer_mode",
    "crowbill_presentation", "husk_transform_policy", "peer_resolver",
    "combat_style_appearance", "combat_styles", "combat_style_policy", "appearance_descriptor" }) do
    local name = missing
    H.test("CWV #692 missing real " .. name .. " library fails", function()
        local f = fixture()
        f.deps.om[name] = nil
        H.equal(type(f.check.run(f.deps)), "string")
    end)
end

for _, missing in ipairs({ "apply_cwv_hand_transform", "plan_cwv_hand_transform" }) do
    local name = missing
    H.test("CWV #692 dropped production " .. name .. " fails", function()
        local f = fixture()
        local actual = f.deps.transform_owner
        f.deps.transform_owner = function(mod, ctx)
            actual(mod, ctx)
            ctx.om.weapon_transform[name] = nil
        end
        H.equal(type(f.check.run(f.deps)), "string")
    end)
end

H.test("CWV #692 dropped production apply cannot pass with a true setter result", function()
    local f = fixture()
    local actual = f.deps.transform_owner
    f.deps.transform_owner = function(mod, ctx)
        actual(mod, ctx)
        ctx.om.weapon_transform.apply_cwv_hand_transform = function() return true end
    end
    local err = f.check.run(f.deps)
    H.truthy(err and err:find("retained right scale axis 1", 1, true), err)
end)

H.test("CWV #692 successful-but-discarded pose writes fail retained-value oracle", function()
    local f = fixture()
    local actual = f.deps.transform_owner
    f.deps.transform_owner = function(mod, ctx)
        ctx.appearance_api.unit.set_local_pose = function() return true end
        actual(mod, ctx)
    end
    local err = f.check.run(f.deps)
    H.truthy(err and err:find("retained right scale axis 1", 1, true), err)
end)

H.test("CWV #692 disconnected appearance API fails rather than touching native units", function()
    local f = fixture()
    local actual = f.deps.transform_owner
    f.deps.transform_owner = function(mod, ctx)
        ctx.appearance_api = nil
        actual(mod, ctx)
    end
    H.equal(type(f.check.run(f.deps)), "string")
    H.truthy(f.native_contacts() > 0, "native-contact poison must expose lost dependency")
end)

for _, mutation in ipairs({
    { name = "axis", change = function(p) p.right_hand_scale[1], p.right_hand_scale[3] = p.right_hand_scale[3], p.right_hand_scale[1] end },
    { name = "sign", change = function(p) p.right_hand_offset[3] = -p.right_hand_offset[3] end },
    { name = "wrong order", change = function(p) p.right_hand_scale[2] = 0.8 end },
    { name = "rotation", change = function(p) p.right_hand_rotation = { 90, 0, 0 } end },
}) do
    local spec = mutation
    H.test("CWV #692 authored " .. spec.name .. " error is observable", function()
        local f = fixture()
        spec.change(f.authored.bretonnian_greatsword_inverse)
        H.equal(type(f.check.run(f.deps)), "string")
    end)
end

H.test("CWV #692 missing authored presentation and immutable descriptor both fail", function()
    local f = fixture()
    f.authored.bretonnian_greatsword_inverse = nil
    H.equal(type(f.check.run(f.deps)), "string")
    f = fixture()
    f.deps.om.combat_style_appearance.build = function() return nil, "planted rejection" end
    H.truthy(f.check.run(f.deps):find("descriptor build failed", 1, true))
    f = fixture()
    f.deps.om.combat_style_appearance.transform_decision = function() return false end
    H.truthy(f.check.run(f.deps):find("immutable transform definition", 1, true))
end)

H.test("CWV #692 disconnected catalogue transform and transformed native controls fail", function()
    local f = fixture()
    local actual = f.deps.om.combat_style_policy.package
    f.deps.om.combat_style_policy.package = function(item, style)
        local result = actual(item, style)
        result.presentation = nil
        return result
    end
    H.truthy(f.check.run(f.deps):find("style presentation wire disconnected", 1, true))
    f = fixture()
    actual = f.deps.om.combat_style_appearance.transform_decision
    f.deps.om.combat_style_appearance.transform_decision = function(descriptor)
        if descriptor.style_id == "bretonnian" then return {} end
        return actual(descriptor)
    end
    H.truthy(f.check.run(f.deps):find("native style unexpectedly transforms", 1, true))
end)

local function installed_render(f, child, registrar)
    local rows, picker_installs, logs = {}, 0, 0
    f.deps.mod._cwv_dev_anim_picker = { install = function() picker_installs = picker_installs + 1 end }
    f.deps.mod.info = function() logs = logs + 1 end
    f.env._MEM_PROBE_T0_CWV = 0
    f.env.collectgarbage = function(mode) H.equal(mode, "count"); return 0 end
    local ctx = { issue692_check = child, issue692_register = registrar,
        issue692_transform_owner = f.deps.transform_owner, issue692_base_item = f.deps.base_item,
        om = f.deps.om, find_def = f.deps.find_def,
        rt_register = function(name, callback) rows[#rows + 1] = { name = name, run = callback } end }
    f.load("_cwv_regression_render")(f.deps.mod, ctx)
    H.equal(picker_installs, 1); H.equal(logs, 2)
    return rows, ctx
end

H.test("CWV #692 actual render owner installs the cached registrar at its exact boundary", function()
    local f = fixture()
    local rows, ctx = installed_render(f, f.check, f.check.register)
    H.equal(rows[1].name, f.check.NAME)
    H.equal(rows[2].name, "cwv_unit_bearing_variants_registered")
    H.equal(rows[1].run(), nil)
    ctx.issue692_check = nil
    H.equal(rows[1].run(), "#692 deterministic application check owner missing")
end)

H.test("CWV #692 absent check table still installs an explicit failing named check", function()
    local f = fixture()
    local rows = installed_render(f, nil, f.check.register)
    H.equal(rows[1].name, f.check.NAME)
    H.equal(rows[1].run(), "#692 deterministic application check owner missing")
end)

H.test("CWV #692 missing mandatory registrar visibly refuses render installation", function()
    local f = fixture()
    local ok, err = pcall(installed_render, f, f.check, nil)
    H.equal(ok, false); H.truthy(tostring(err):find("#692 registration owner missing", 1, true))
    local token = {}
    ok, err = pcall(installed_render, f, f.check, function() error(token, 0) end)
    H.equal(ok, false); H.equal(err, token)
end)

H.test("CWV #692 entry reuses the single installed transform constructor and exact context", function()
    local f = fixture()
    local fields = {}
    for _, name in ipairs({ "issue692_check", "issue692_transform_owner", "issue692_base_item", "issue692_register" }) do
        fields[#fields + 1] = assert(f.entry:match("\n\t" .. name .. " = ([^\n]+)"), name)
    end
    local declaration = between(f.entry, "_om.install_weapon_transforms = ",
        "\n\n-- Re-bound under their original names")
    local check_declaration = assert(f.entry:match("\n(_om.issue692_check = [^\n]+)"))
    local calls, installs, check_loads = 0, 0, 0
    local definitions, illusions, skins, find_def = {}, {}, {}, function() end
    local constructor = function(mod, ctx)
        installs = installs + 1
        H.equal(mod, f.deps.mod)
        H.equal(ctx.om, f.deps.om); H.equal(ctx.variant_definitions, definitions)
        H.equal(ctx.find_def, find_def); H.equal(ctx.custom_illusions, illusions)
        H.equal(ctx.custom_skin_keys, skins)
        local keys = 0; for _ in pairs(ctx) do keys = keys + 1 end
        H.equal(keys, 5, "live installer dependency tuple changed")
    end
    local loader = f.deps.mod.dofile
    f.deps.mod.dofile = function(mod, path)
        if path == "scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner" then
            calls = calls + 1
            return constructor
        end
        if path == "scripts/mods/character_weapon_variants/_cwv_issue692_transform_check" then check_loads = check_loads + 1 end
        return loader(mod, path)
    end
    local chunk = assert(loadstring("local mod, ItemMasterList, _om, _variant_definitions, "
        .. "_find_def, _custom_illusions, _custom_skin_keys = ...\n"
        .. declaration .. "\n" .. check_declaration .. "\nreturn {" .. table.concat(fields, "\n") .. "}",
        "=issue692_actual_entry_install_and_dependencies"))
    local values = chunk(f.deps.mod, { es_bastard_sword = f.deps.base_item },
        f.deps.om, definitions, find_def, illusions, skins)
    H.equal(calls, 1, "live and regression paths must share one constructor load")
    H.equal(installs, 1, "entry must retain the original live installer timing")
    H.equal(type(values[1].run), "function")
    H.equal(values[2], constructor, "regression context must use the installed constructor identity")
    H.equal(f.deps.om.install_weapon_transforms, constructor)
    H.equal(values[3], f.deps.base_item)
    H.equal(check_loads, 1); H.equal(values[4], values[1].register)
end)
end
