local mod = get_mod("enemy_tweaker")

-- _et_mimic.lua — difficulty mimic (per-system difficulty override)
--
-- Each Current* settings table is built by patch_settings_with_difficulty
-- against a specific difficulty key. Mimic lets the user override the
-- difficulty key used PER SYSTEM, so they can play on (e.g.) Champion stats
-- but use Cataclysm-1's horde compositions, special spawn frequency, roaming
-- density, etc. Player/enemy stats stay on the real difficulty — only the
-- spawn-side fields are re-patched.
--
-- MIMIC_SYSTEMS maps the user-facing setting → director field name → name of
-- the Current* global. After ConflictDirector.refresh_conflict_director_patches
-- runs, for each system where the user picked a difficulty override, we
-- re-patch from director.<field> with the override difficulty and overwrite
-- the Current* global. Order is important: difficulty mimic runs BEFORE
-- faction-swap, because mimic REPLACES the table and faction-swap mutates
-- in place (enforced in _et_director_hooks.lua).
--
-- Owned by: enemy_tweaker.lua entry point. Consumed via mod._et exports:
-- apply_difficulty_mimic, MIMIC_SYSTEMS.

local ET = mod._et
local _safe      = ET.safe
local _dbg       = ET.dbg
local _dbg_alert = ET.dbg_alert

local MIMIC_SYSTEMS = {
    { setting = "mimic_horde",         field = "horde",         current = "CurrentHordeSettings" },
    { setting = "mimic_specials",      field = "specials",      current = "CurrentSpecialsSettings" },
    { setting = "mimic_pacing",        field = "pacing",        current = "CurrentPacing" },
    { setting = "mimic_pack_spawning", field = "pack_spawning", current = "CurrentPackSpawningSettings" },
    { setting = "mimic_intensity",     field = "intensity",     current = "CurrentIntensitySettings" },
    { setting = "mimic_boss",          field = "boss",          current = "CurrentBossSettings" },
}

local VALID_DIFFICULTIES = {
    normal = true, hard = true, harder = true, hardest = true,
    cataclysm = true, cataclysm_2 = true, cataclysm_3 = true,
}

local function _apply_difficulty_mimic(self)
    local CDs = rawget(_G, "ConflictDirectors")
    local director = CDs and CDs[self.current_conflict_settings]
    if not director then
        _dbg_alert("difficulty_mimic: no director for current_conflict_settings=%s — bail",
            tostring(self and self.current_conflict_settings))
        return
    end
    local mgr = Managers.state and Managers.state.difficulty
    local fallback_difficulty = mgr and mgr.fallback_difficulty
    local CU = rawget(_G, "ConflictUtils")
    if not CU or not CU.patch_settings_with_difficulty then
        _dbg_alert("difficulty_mimic: ConflictUtils.patch_settings_with_difficulty missing — bail")
        return
    end

    for _, m in ipairs(MIMIC_SYSTEMS) do
        local user_difficulty = mod:get(m.setting)
        if user_difficulty and user_difficulty ~= "off"
                and VALID_DIFFICULTIES[user_difficulty]
                and director[m.field] then
            _safe("difficulty_mimic:" .. m.setting, function()
                local rebuilt = CU.patch_settings_with_difficulty(
                    table.clone(director[m.field]), user_difficulty, fallback_difficulty)
                _G[m.current] = rebuilt
                _dbg("difficulty_mimic applied: %s field=%s difficulty=%s",
                    m.setting, m.field, user_difficulty)
            end)
        end
    end
end

ET.MIMIC_SYSTEMS = MIMIC_SYSTEMS
ET.apply_difficulty_mimic = _apply_difficulty_mimic
