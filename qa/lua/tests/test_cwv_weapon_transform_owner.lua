-- test_cwv_weapon_transform_owner.lua
-- Offline coverage for the #1159 CWV weapon-transform owner extraction.
--
-- The owner answers ONE question - which transform record applies to an
-- item/skin/unit, and how it is written onto a spawned weapon unit - and it is a
-- PRODUCER, never a surface. These checks pin that: the producers live exactly
-- once and in the owner, the entry keeps the four consumer surfaces plus the
-- re-binds they call through, and the owner absorbs no sibling owner's job.
return function(H, repo_root)
    local root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
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

    local entry = read("character_weapon_variants.lua")
    local owner = read("_cwv_weapon_transform_owner.lua")
    local menu_preview = read("_cwv_menu_preview_owner.lua")
    local husk = read("_cwv_husk_path.lua")
    local registration = read("_cwv_item_registration_owner.lua")
    local husk_residency = read("_cwv_husk_residency_owner.lua")
    local musket = read("_cwv_musket_runtime.lua")

    H.test("CWV weapon-transform owner holds every transform producer", function()
        -- Three moved ranges, each an unbroken byte-identical block. Every
        -- producer below now lives exactly ONCE, in the owner, and nowhere else.
        local owned = {
            "local _type_transforms = {",
            "local function _resolve_field(def, field)",
            "local _transform_map = {}",
            "local _skin_transform_map = {}",
            "local _crowbill_transform_by_unit = {}",
            "local function _is_unit(v)",
            "local WA = _WA_LIBRARY.new()",
            "local function _apply_scale(unit, scale_tbl)",
            "local function _apply_offset(unit, offset_tbl)",
            "local function _transform_unit(unit, scale_tbl, offset_tbl, rotation)",
            "local function _triplet_text(value)",
            "local function _apply_cwv_hand_transform(unit, def, hand, perspective, surface, unit_name, skin)",
            "local _ES_MACE_SWORD_TWEAK_DEF = {",
            "local function _resolve_cwv_def(item_data, skin, resolved_unit_name)",
            "_om._cwv_resolve_crowbill_transform = function(skin, resolved_unit_name, variant_key)",
            "_om._cwv_husk_transform_policy = _om.husk_transform_policy.bind({ find_def = _find_def,",
        }
        for _, marker in ipairs(owned) do
            H.equal(count_plain(owner, marker), 1, "transform owner owns " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- The cross-file handles the moved code publishes keep their names, so
        -- every sibling module and the /cwv regression suite still resolve them.
        local handles = {
            "mod._cwv_transform_registered = function(key)",
            "mod._wa_to_quaternion_for_rt = WA.to_quaternion",
            "mod._cwv_weapon_appearance = WA",
            "mod._cwv_crowbill_set_mode = function(identity, mode)",
            "mod._cwv_crowbill_apply_remote_mode = function(payload)",
            "mod._cwv_crowbill_apply_presentation = _om._apply_crowbill_presentation",
            "_om._cwv_durable_crowbill_owner, _om._cwv_crowbill_transform_evidence",
            "_om._cwv_forget_crowbill_transform_unit = function(unit, reason)",
            "_om._cwv_select_husk_transform_def = _om._cwv_husk_transform_policy.select",
            "_om._cwv_husk_transform_apply_plan = _om._cwv_husk_transform_policy.plan",
            "_om._variant_defs = _variant_definitions",
        }
        for _, handle in ipairs(handles) do
            H.equal(count_plain(owner, handle), 1, "transform owner publishes " .. handle)
            H.equal(count_plain(entry, handle), 0, "entry no longer publishes " .. handle)
        end
    end)

    H.test("CWV weapon-transform owner is a producer, never a surface", function()
        -- It registers nothing. A hook, channel or command appearing here would
        -- mean a surface migrated in, and VMF would silently shadow whichever
        -- registration on that pair loaded second.
        for _, forbidden in ipairs({
            "mod:hook", "mod:network_register", "mod:command",
            "mod.on_game_state_changed", "mod.on_all_mods_loaded",
            "mod.on_enabled", "mod.on_disabled", "mod.on_unload", "mod.update",
        }) do
            H.equal(count_plain(owner, forbidden), 0,
                "transform owner must not contain " .. forbidden)
        end

        -- No native resource boundary moved with it, so it correctly carries no
        -- resource-safety marker and needs no native_resource_contracts row.
        for _, forbidden in ipairs({
            "World.create_particles", "World.create_screen_gui",
            "Material.set_texture", "Unit.set_texture_for_materials",
            "Managers.package:load", "Managers.package:unload",
            "resource-safety:",
        }) do
            H.equal(count_plain(owner, forbidden), 0,
                "transform owner must not contain " .. forbidden)
        end
    end)

    H.test("CWV weapon-transform owner takes a named install and by-value ctx", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true),
            "owner must use a named install wrapper")
        H.equal(count_plain(owner, "return function("), 0,
            "owner must not be an anonymous chunk")
        H.truthy(owner:find("\nreturn install\n", 1, true),
            "owner must return its named install")

        -- All five ctx bindings are declared once at entry file scope above the
        -- load point and never rebound, so the by-value capture cannot go stale.
        local ctx_fields = {
            "om", "variant_definitions", "find_def",
            "custom_illusions", "custom_skin_keys",
        }
        for _, field in ipairs(ctx_fields) do
            H.equal(count_plain(owner, "local _" .. field .. " = ctx." .. field), 1,
                "owner localizes ctx." .. field)
        end
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner")(mod, {'), 1,
            "entry installs the transform owner exactly once")
    end)

    H.test("CWV entry re-binds the transform producers its surfaces still call", function()
        -- The ten producers that survived the move keep their original entry
        -- names, which is why every remaining statement in the entry is
        -- byte-identical. Each re-bind must exist exactly once and must read the
        -- owner's published namespace, never rebuild the value.
        local rebinds = {
            "_type_transforms", "_resolve_field", "_transform_map",
            "_skin_transform_map", "_crowbill_transform_by_unit", "_is_unit",
            "_transform_unit", "_triplet_text", "_apply_cwv_hand_transform",
            "_resolve_cwv_def",
        }
        H.equal(count_plain(owner, "_om.weapon_transform = {"), 1,
            "owner publishes exactly one export namespace")
        local exports_at = assert(owner:find("_om.weapon_transform = {", 1, true))
        local exports_end = assert(owner:find("\n}", exports_at, true))
        local exports = owner:sub(exports_at, exports_end)
        for _, name in ipairs(rebinds) do
            local key = name:sub(2)
            H.equal(count_plain(entry, "= _om.weapon_transform." .. key), 1,
                "entry re-binds " .. name .. " from the owner namespace")
            H.truthy(exports:find("\n\t" .. key .. "%s+= " .. name .. ",\n"),
                "owner exports " .. key .. " as the object it built")
        end
        H.equal(count_plain(entry, "_om.weapon_transform"), #rebinds,
            "entry reads the namespace only for the re-binds")
    end)

    H.test("CWV transform consumers stay on their own side of the boundary", function()
        -- Four surfaces consume this producer and NONE of them moved. Pin the
        -- code forms, not the names, because the owner's header comment names
        -- all four.
        local entry_only = {
            -- WORLD / BOT equipment, with its own transform-miss counters.
            'mod:hook("GearUtils", "create_equipment"',
            "local def = _resolve_cwv_def(item_data, result.skin",
            "_crowbill_transform_miss_total = _crowbill_transform_miss_total + 1",
            "_apply_cwv_hand_transform(result.right_unit_3p, def, \"right\", \"3p\",",
            -- #1158 exact-appearance descriptors and their get_item_units hook.
            "_om._cwv_resolve_world_descriptor = function(item_data, explicit_skin, resolved_unit_name,",
            'mod:hook(BackendUtils, "get_item_units"',
            -- The shared def finder every owner reaches through.
            "local function _find_def(item_key)",
            -- Combat Style authors TEMPLATES; it only reads one authored record
            -- out of the type table the transform owner publishes.
            "local imperial_transform = _type_transforms.cwv_imperial_longsword",
        }
        for _, marker in ipairs(entry_only) do
            H.equal(count_plain(entry, marker), 1, "entry keeps " .. marker)
            H.equal(count_plain(owner, marker), 0,
                "transform owner must not absorb " .. marker)
        end

        -- The MENU and REMOTE surfaces keep consuming through their ctx tables,
        -- which the entry now fills from the re-bound producers.
        for _, field in ipairs({ "resolve_field", "is_unit", "transform_unit",
                "apply_cwv_hand_transform", "transform_map", "skin_transform_map",
                "crowbill_transform_by_unit", "triplet_text" }) do
            H.truthy(entry:find(field .. " = _" .. field .. ",", 1, true),
                "entry still injects " .. field .. " into a consumer ctx")
        end
        H.truthy(menu_preview:find("local _resolve_field = ctx.resolve_field", 1, true),
            "menu preview owner still consumes resolve_field by ctx")
        H.truthy(husk:find("apply_cwv_hand_transform", 1, true),
            "husk path still consumes the shared per-hand applier")
        H.truthy(husk:find("_om._cwv_select_husk_transform_def", 1, true),
            "husk path still resolves through the husk transform policy")
    end)

    H.test("CWV weapon-transform owner absorbs no sibling owner's job", function()
        for _, forbidden in ipairs({
            -- registration owner
            "local function _build_entry", "_auto_register_all",
            -- husk owners
            "_force_load_husk_override_units", "_om._husk_adapter_pre",
            "start_weapon_fx",
            -- menu preview owner. Code forms only: the moved transform comments
            -- legitimately NAME the previewer surfaces they feed.
            "local function _cwv_spawn_item_post(",
            'mod:hook("LootItemUnitPreviewer"',
            -- musket runtime
            "musket_template_melee", "old_musket_template",
            -- commands / regression
            "_rt_register", "_give_variant",
        }) do
            H.equal(count_plain(owner, forbidden), 0,
                "transform owner must not contain " .. forbidden)
        end

        -- And the siblings did not quietly gain a second copy of the producers.
        for _, source in ipairs({ menu_preview, husk, registration, husk_residency, musket }) do
            H.equal(count_plain(source, "local function _resolve_field(def, field)"), 0)
            H.equal(count_plain(source, "local function _resolve_cwv_def(item_data, skin, resolved_unit_name)"), 0)
            H.equal(count_plain(source, "local _type_transforms = {"), 0)
        end
    end)

    H.test("CWV transform gate signals and tuned records survived the move", function()
        -- Issue 409 force_register and issue 417 unit-bearing registration are
        -- the two gate signals that decide `_transform_map` membership; losing
        -- either silently degrades a variant to the nil-def bail.
        H.truthy(owner:find('_resolve_field(def, "force_register")', 1, true),
            "issue 409 force_register gate signal")
        H.truthy(owner:find('_resolve_field(def, "right_hand_unit")', 1, true),
            "issue 417 unit-bearing gate signal")
        H.truthy(owner:find("cwv_es_musket_old = { force_register = true }", 1, true),
            "Old Musket force_register row")

        -- The longest-match inherit rule (v0.1.255) fixed shield illusions
        -- inheriting the 2H Imperial Longsword scale. Pin the rule and its code.
        H.truthy(owner:find("LONGEST-MATCH RULE", 1, true))
        H.truthy(owner:find('skin_key:sub(1, #def.item_key + 1) == def.item_key .. "_"', 1, true))

        -- Authored per-family records the user tuned by eye. A silent change
        -- here is invisible offline, so pin the exact triples.
        local tuned = {
            "right_hand_scale  = { 1.0, 0.8, 0.9 },",
            "right_hand_offset = { 0, 0, -0.065 },",
            "right_hand_scale_1p = { 1.0, 0.8, 0.9 },",
            "right_hand_scale_3p = { 0.9, 0.7, 0.8 },",
            "right_hand_scale  = { 1.0, 1.0, 1.6 },",
            "right_hand_offset = { 0, 0, 0.2 },",
            "right_hand_scale = { 1.05, 1.15, 1.0 },",
            "right_hand_scale    = { 0.8, 1.35, 0.8 },",
            "right_hand_scale_1p = { 0.8, 1.5,  0.8 },",
            "left_hand_scale = { 0.7, 0.7, 1.0 },",
        }
        for _, record in ipairs(tuned) do
            H.equal(count_plain(owner, record), 1, "tuned record preserved: " .. record)
        end
    end)

    H.test("CWV transform evidence markers moved with the code that emits them", function()
        -- The bounded 64-shot #604 scheduling line is the in-game grep the
        -- Crowbill transform work is verified against.
        local marker = "[cwv:604] transform scheduled surface=%s perspective=%s hand=%s variant=%s model=%s unit=%s skin=%s generation=%s scale_multiplier=(%s) absolute_scale=(%s) offset=(%s) rotation=(%s) initial_apply=%s count=%d/64"
        H.equal(count_plain(owner, marker), 1, "owner keeps the #604 scheduling marker")
        H.equal(count_plain(entry, marker), 0, "entry no longer prints it")
        H.truthy(owner:find("_crowbill_transform_diag_total < 64", 1, true),
            "the 64-shot cap moved with the marker")

        -- The world-surface TRANSFORM MISS counter is the paired evidence on the
        -- consumer side and must NOT have followed the producer out.
        local miss = "[cwv:604] TRANSFORM MISS surface=create_equipment"
        H.equal(count_plain(entry, miss), 1, "entry keeps the world transform-miss marker")
        H.equal(count_plain(owner, miss), 0, "owner must not absorb the world-surface counter")
    end)
end
