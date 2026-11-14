-- B2 audit experiment, layer 2: load REAL mod data-layer modules on top of the REAL vanilla
-- tables (ItemMasterList / Weapons / CareerSettings / BuffTemplates / Breeds loaded by the
-- probe) under a small generic fake VMF, then assert cross-reference invariants.
-- Read-only: mod files are read from the repository, nothing is written there.
local P = ...
local REPO = "<repos>/vermintide-2-tweaker"
local native_loadfile = loadfile

-- ---- generic fake VMF (the whole "general VMF mock" this experiment needed) ----
local MOD_DIRS = { wt = "weapon_tweaker", character_weapon_variants = "character_weapon_variants",
    crt = "career_tweaker", enemy_tweaker = "enemy_tweaker", WOC = "weapons_of_chaos" }
local mods, calls = {}, { hook = 0, hook_safe = 0, command = 0, get = 0, dofile = 0 }
local function new_mod(id)
    local mod = { _id = id, _settings = {}, _hooks = {}, _commands = {} }
    function mod:get(key) calls.get = calls.get + 1; return self._settings[key] end
    function mod:set(key, value) self._settings[key] = value end
    function mod:hook(class, method, fn) calls.hook = calls.hook + 1; self._hooks[#self._hooks + 1] = { class, method, fn } end
    function mod:hook_safe(class, method, fn) calls.hook_safe = calls.hook_safe + 1; self._hooks[#self._hooks + 1] = { class, method, fn, safe = true } end
    function mod:hook_origin(class, method, fn) self._hooks[#self._hooks + 1] = { class, method, fn, origin = true } end
    function mod:command(name, desc, fn) calls.command = calls.command + 1; self._commands[name] = fn end
    function mod:dofile(path)
        calls.dofile = calls.dofile + 1
        local chunk = assert(native_loadfile(REPO .. "/" .. (MOD_DIRS[id] or id) .. "/" .. path .. ".lua"))
        return chunk()
    end
    function mod:echo() end; function mod:info() end; function mod:warning() end; function mod:error() end; function mod:debug() end
    function mod:localize(key) return key end
    return mod
end
rawset(_G, "get_mod", function(id) mods[id] = mods[id] or new_mod(id); return mods[id] end)

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local results = {}
local function report(name, checked, problems)
    results[#results + 1] = string.format("%-58s checked=%-5d problems=%d%s", name, checked, #problems,
        #problems > 0 and ("  e.g. " .. table.concat(problems, "; "):sub(1, 400)) or "")
end

io.write(string.format("VANILLA TABLE SIZES  ItemMasterList=%d Weapons=%d BuffTemplates=%d Breeds=%d CareerSettings=%d\n",
    count(ItemMasterList), count(Weapons), count(BuffTemplates), count(Breeds), count(CareerSettings)))

-- ---- invariant 0 (vanilla self-consistency; proves the loaded tables are real) ----
do
    local checked, problems = 0, {}
    for key, item in pairs(ItemMasterList) do
        if item.slot_type == "melee" or item.slot_type == "ranged" then
            checked = checked + 1
            local template = item.template or item.temporary_template
            if not rawget(Weapons, template) then problems[#problems + 1] = key .. "->" .. tostring(template) end
            for _, career in ipairs(item.can_wield or {}) do
                if not rawget(CareerSettings, career) and career ~= "empire_soldier_tutorial" then
                    problems[#problems + 1] = key .. " can_wield unknown career " .. tostring(career)
                end
            end
        end
    end
    report("vanilla: every melee/ranged item has a Weapons template", checked, problems)
end

-- ---- invariant 1: weapon_tweaker unlock map vs real vanilla tables ----
do
    local data = get_mod("wt"):dofile("scripts/mods/weapon_tweaker/wt_unlock_data")
    local checked, problems, cwv = 0, {}, 0
    for career, weapons in pairs(data.weapon_unlock_map) do
        if not rawget(CareerSettings, career) then problems[#problems + 1] = "unknown career " .. tostring(career) end
        for _, key in ipairs(weapons) do
            checked = checked + 1
            local item = rawget(ItemMasterList, key)
            if type(key) ~= "string" then
                problems[#problems + 1] = career .. ": non-string key"
            elseif key:sub(1, 4) == "cwv_" then
                cwv = cwv + 1 -- registered by the CWV mod at runtime, not vanilla
            elseif not item then
                problems[#problems + 1] = career .. ": " .. key .. " not in ItemMasterList"
            elseif not rawget(Weapons, item.template or item.temporary_template) then
                problems[#problems + 1] = career .. ": " .. key .. " template missing in Weapons"
            else
                -- the port must be CROSS-character: flag rows the receiver can already wield natively
                for _, c in ipairs(item.can_wield or {}) do
                    if c == career then problems[#problems + 1] = career .. ": " .. key .. " is already native (redundant unlock row)" end
                end
            end
        end
    end
    report("wt: weapon_unlock_map keys resolve in vanilla (cwv_ rows=" .. cwv .. ")", checked, problems)
end

-- ---- invariant 2: CWV Dawi Mace variant catalog vs real vanilla tables ----
do
    local policy = assert(native_loadfile(REPO
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_dawi_maces.lua"))()
    local checked, problems = 0, {}
    for _, variant in ipairs(policy.VARIANTS) do
        checked = checked + 1
        local base = rawget(ItemMasterList, variant.base_weapon)
        if not base then problems[#problems + 1] = variant.key .. ": base_weapon " .. tostring(variant.base_weapon) .. " missing" end
        if variant.template:sub(1, 4) ~= "cwv_" and not rawget(Weapons, variant.template) then
            problems[#problems + 1] = variant.key .. ": template " .. variant.template .. " missing in Weapons"
        end
        if base and variant.template:sub(1, 4) ~= "cwv_" and base.template ~= variant.template then
            problems[#problems + 1] = variant.key .. ": template " .. variant.template .. " ~= base item's " .. tostring(base.template)
        end
        for _, career in ipairs(variant.default_careers or {}) do
            if not rawget(CareerSettings, career) then problems[#problems + 1] = variant.key .. ": unknown career " .. career end
        end
    end
    for _, career in ipairs(policy.ALL_CAREERS) do
        checked = checked + 1
        if not rawget(CareerSettings, career) then problems[#problems + 1] = "ALL_CAREERS unknown " .. career end
    end
    for _, unit in ipairs({ policy.PLACEHOLDER_MACE, policy.PLACEHOLDER_SHIELD }) do
        checked = checked + 1
        local found = false
        for _, item in pairs(ItemMasterList) do
            if item.right_hand_unit == unit or item.left_hand_unit == unit or item.unit == unit then found = true; break end
        end
        if not found then
            for _, skin in pairs(rawget(_G, "WeaponSkins") and WeaponSkins.skins or {}) do
                if skin.right_hand_unit == unit or skin.left_hand_unit == unit then found = true; break end
            end
        end
        if not found then problems[#problems + 1] = "placeholder unit not referenced by any vanilla item/skin: " .. unit end
    end
    report("cwv: Dawi Mace catalog resolves in vanilla", checked, problems)
end

io.write("MOD LAYER RESULTS\n  " .. table.concat(results, "\n  ") .. "\n")
io.write(string.format("fake VMF surface used: get_mod + mod:dofile x%d, hook x%d, hook_safe x%d, command x%d, get x%d\n",
    calls.dofile, calls.hook, calls.hook_safe, calls.command, calls.get))
