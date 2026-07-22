local mod = get_mod("gut_dev")

-- ============================================================================
-- NumericUI compatibility: real-time cooldown + authoritative teammate ammo
-- ============================================================================
-- VT2 applies cooldown reduction by making the ability cooldown DECREASE FASTER, not
-- by shortening it. career_extension.lua:244-246:
--   local mult = buff_extension:apply_buffs_to_value(1, "cooldown_regen")
--   self:reduce_activated_ability_cooldown(dt * mult, i)
-- So the raw value from CareerExtension.current_ability_cooldown() ticks down faster
-- than wall-clock under CDR. NumericUI displays that raw value for the local player
-- (NumericUI.lua:1466: math.ceil(career_extension:current_ability_cooldown())), so its
-- on-screen cooldown number visibly SPEEDS UP instead of counting real seconds.
--
-- Fix (from our side, no NumericUI rebuild): while NumericUI is computing its
-- own-player stats — inside its hook on UnitFramesHandler._sync_player_stats — divide
-- the cooldown READ by that SAME cooldown_regen multiplier. cd/mult is the real
-- seconds remaining: it ticks at 1/sec and shows the accurate reduced cooldown. A flag
-- gates it so ONLY NumericUI's display is touched — the game's cooldown logic, the
-- ability-bar fill (current_ability_cooldown_percentage), and bot AI all keep the raw
-- value. (Verified: vanilla _sync_player_stats reads only ability_percentage, never
-- current_ability_cooldown, so the flag can't leak to a vanilla read.)
--
-- No-op if NumericUI isn't installed. Graceful no-op (raw value = original behaviour,
-- no crash) in the unlikely event hook order ever nests us INSIDE NumericUI's hook.
--
-- Issue #249: NumericUI derives teammate absolute ammo from ammo_percentage times
-- the weapon template's static max. That cannot represent Quiver Cascade's dynamic
-- total_ammo capacity. Vanilla already exposes the exact pair through both owner and
-- husk InventoryExtension:ammo_status(), so the existing singleton sync wrapper repairs
-- NumericUI's retained string after its calculation. No RPC, buff recomputation, or
-- global weapon-template mutation is needed.

if not get_mod("NumericUI") then return {} end

local ScriptUnit = ScriptUnit
local Unit       = Unit
local AmmoCore   = mod:dofile("scripts/mods/gui_tweaker_dev/_numericui_ammo_core")

local _in_sync = false
local _logged  = false
local _ammo_log_count = 0
local _ammo_error_count = 0
local AMMO_LOG_LIMIT = 12
local AMMO_ERROR_LIMIT = 3
local AMMO_ADAPTER_MARKER = "numericui:authoritative_inventory_ammo_v1"

-- The cooldown_regen multiplier currently on the ability owner (1 = no CDR).
local function _cdr_multiplier(career_extension)
    local unit = career_extension and career_extension._unit
    if not (unit and Unit.alive(unit)) then return 1 end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return 1 end
    local ok, mult = pcall(buff_ext.apply_buffs_to_value, buff_ext, 1, "cooldown_regen")
    if ok and type(mult) == "number" and mult > 0 then return mult end
    return 1
end

local function _mark_widget_dirty(widget, dynamic_widget)
    if widget._set_widget_dirty then
        widget._set_widget_dirty(widget, dynamic_widget)
    end
    if widget.set_dirty then
        widget.set_dirty(widget)
    end
end

-- #249 consolidated apply site: NumericUI already owns this sync call, so repair its
-- retained output inside the existing GUT wrapper instead of registering a second hook.
local function _repair_numericui_ammo(unit_frame)
    local player_data = unit_frame and unit_frame.player_data
    local data = unit_frame and unit_frame.data
    local widget = unit_frame and unit_frame.widget
    if not (player_data and data and widget) or player_data.own_player then return end

    local mode = AmmoCore.mode_key(data.show_teammate_ammo)
    local extensions = player_data.extensions
    local inventory = extensions and extensions.inventory
    if not mode or data.is_overcharge or not (inventory and inventory.ammo_status) then return end

    local ok, raw_current, raw_max = pcall(inventory.ammo_status, inventory)
    if not ok then return end
    local current_ammo, max_ammo = AmmoCore.normalize(raw_current, raw_max)
    if not current_ammo then return end

    local dynamic_widget = widget._widget_by_feature
        and widget._widget_by_feature(widget, "default", "dynamic")
    local content = dynamic_widget and dynamic_widget.content
    if not content then return end

    local numeric_before = data.cur_ammo
    if data._gut249_current ~= current_ammo
        or data._gut249_max ~= max_ammo
        or data._gut249_mode ~= mode then
        data._gut249_string, data._gut249_style = AmmoCore.format(mode, current_ammo, max_ammo)
        data._gut249_current = current_ammo
        data._gut249_max = max_ammo
        data._gut249_mode = mode
    end

    data.cur_ammo = current_ammo
    content.ammo_string = data._gut249_string
    content.ammo_style = data._gut249_style
    _mark_widget_dirty(widget, dynamic_widget)

    if _ammo_log_count < AMMO_LOG_LIMIT and numeric_before ~= current_ammo then
        _ammo_log_count = _ammo_log_count + 1
        pcall(printf,
            "[gut:249] corrected peer ammo numeric=%s authoritative=%d/%d mode=%d sample=%d/%d",
            tostring(numeric_before), current_ammo, max_ammo, mode,
            _ammo_log_count, AMMO_LOG_LIMIT)
    end
end

local function _local_ammo_evidence()
    local state = Managers and Managers.state
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player()
    local unit = player and player.player_unit
    if not (unit and Unit.alive(unit)) then
        pcall(printf, "[gut:249] LOCAL FAIL no living local player")
        return
    end

    local inventory = ScriptUnit.has_extension(unit, "inventory_system")
    if not (inventory and inventory.ammo_status) then
        pcall(printf, "[gut:249] LOCAL FAIL no ranged ammo extension")
        return
    end

    local ok, raw_current, raw_max = pcall(inventory.ammo_status, inventory)
    local current_ammo, max_ammo
    if ok then
        current_ammo, max_ammo = AmmoCore.normalize(raw_current, raw_max)
    end
    if not current_ammo then
        pcall(printf, "[gut:249] LOCAL FAIL invalid ammo_status current=%s max=%s",
            tostring(raw_current), tostring(raw_max))
        return
    end

    local equipment = inventory.equipment and inventory:equipment()
    local ranged = equipment and equipment.slots and equipment.slots.slot_ranged
    local item_data = ranged and ranged.item_data
    local item_template = item_data and BackendUtils.get_item_template(item_data)
    local base_max = item_template and item_template.ammo_data and item_template.ammo_data.max_ammo

    local game = state and state.network and state.network:game()
    local storage = state and state.unit_storage
    local go_id = storage and storage:go_id(unit)
    local wire_current, wire_max, wire_fraction
    if game and go_id and GameSession.game_object_exists(game, go_id) then
        local wire_ok, a, b, c = pcall(function()
            return GameSession.game_object_field(game, go_id, "current_ammo"),
                GameSession.game_object_field(game, go_id, "max_ammo"),
                GameSession.game_object_field(game, go_id, "ammo_percentage")
        end)
        if wire_ok then
            wire_current, wire_max, wire_fraction = a, b, c
        end
    end

    local buff = ScriptUnit.has_extension(unit, "buff_system")
    local stack_count = 0
    if buff and buff.num_buff_stacks then
        local stack_ok, count = pcall(buff.num_buff_stacks, buff, "ct_meta_ammo_stack_1")
        if stack_ok and type(count) == "number" then stack_count = count end
    end

    local pass = wire_current == current_ammo and wire_max == max_ammo
    pcall(printf,
        "[gut:249] LOCAL %s exact=%d/%d wire=%s/%s fraction=%s template_base=%s quiver_stacks=%d numericui=%s",
        pass and "PASS" or "FAIL", current_ammo, max_ammo,
        tostring(wire_current), tostring(wire_max), tostring(wire_fraction),
        tostring(base_max), stack_count, tostring(get_mod("NumericUI") ~= nil))
end

-- Flag the window of NumericUI's whole _sync_player_stats pass. We load after NumericUI
-- so our hook is the OUTERMOST wrapper and encloses NumericUI's hook. pcall so the flag
-- is ALWAYS reset even if the chain errors (a stuck-true flag would wrongly divide
-- every cooldown read); re-raise to preserve the original error.
mod:hook("UnitFramesHandler", "_sync_player_stats", function(func, self, unit_frame)
    _in_sync = true
    local ok, err = pcall(func, self, unit_frame)
    _in_sync = false
    if not ok then error(err, 0) end

    local repair_ok, repair_err = pcall(_repair_numericui_ammo, unit_frame)
    if not repair_ok and _ammo_error_count < AMMO_ERROR_LIMIT then
        _ammo_error_count = _ammo_error_count + 1
        pcall(printf, "[gut:249] repair failed safely: %s (%d/%d)",
            tostring(repair_err), _ammo_error_count, AMMO_ERROR_LIMIT)
    end
end)

-- Capture BOTH returns (cooldown, max_cooldown) so we don't collapse the multi-return.
mod:hook("CareerExtension", "current_ability_cooldown", function(func, self, ability_id)
    local cd, max_cd = func(self, ability_id)
    if _in_sync and type(cd) == "number" and cd > 0 then
        local mult = _cdr_multiplier(self)
        if mult > 1 then
            if not _logged then
                _logged = true
                mod:debug("[gut] NumericUI cooldown realtime-fix active: raw=%.1f mult=%.3f -> shown=%.1f",
                    cd, mult, cd / mult)
            end
            cd = cd / mult
        end
    end
    return cd, max_cd
end)

mod:command("verify_boon_ammo_hud",
    "Report exact local and replicated ammo for Quiver Cascade HUD verification (#249)",
    function()
        local ok, err = pcall(_local_ammo_evidence)
        if not ok then
            pcall(printf, "[gut:249] LOCAL FAIL diagnostic error=%s", tostring(err))
        end
    end)

if type(mod._gut_rt_register) == "function" then
    mod._gut_rt_register("issue249_numericui_authoritative_ammo", function()
        if AMMO_ADAPTER_MARKER ~= "numericui:authoritative_inventory_ammo_v1" then
            return "#249 adapter marker missing or changed"
        end
        if type(AmmoCore.normalize) ~= "function" or type(AmmoCore.format) ~= "function" then
            return "#249 authoritative ammo policy missing"
        end
    end)
end

pcall(printf,
    "[gut:249] applied authoritative NumericUI ammo adapter via InventoryExtension:ammo_status")

return {}
