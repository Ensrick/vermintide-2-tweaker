-- _ct_diag_tab_native533.lua — #533/#571 Chaos Wastes hold-Tab layout census.
-- Observation-only: arms on the player-list activation edge in any live Deus
-- run, then waits for the animated right banner to settle before sampling the
-- final scenegraph and CT collectible rows after vanilla _draw.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: mod:dofile contract.
local mod = get_mod("ct_dev")
local M = {}

local RECORD_CAP = 64
local SETTLE_FRAMES = 3
local MAX_WAIT_FRAMES = 120
local SETTLE_EPSILON = 0.25
local records = 0
local seen = {}

local function scalar(v)
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    return "<" .. t .. ">"
end

local function compact(v, depth, budget, visited)
    if type(v) ~= "table" then return scalar(v) end
    if depth <= 0 then return "<table>" end
    if visited[v] then return "<cycle>" end
    visited[v] = true
    local keys = {}
    for k in pairs(v) do
        if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
        if budget.n <= 0 then out[#out + 1] = "..." break end
        budget.n = budget.n - 1
        out[#out + 1] = tostring(k) .. "=" .. compact(v[k], depth - 1, budget, visited)
    end
    visited[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end

local function emit(key, fmt, ...)
    if records >= RECORD_CAP or seen[key] then return false end
    seen[key] = true
    records = records + 1
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = "format-error:" .. tostring(fmt) end
    if rawget(_G, "printf") then pcall(printf, "[ct:571-native] %s", line) end
    return true
end

local function current_deus_level()
    local dc
    local mm = Managers and Managers.mechanism
    local mech = mm and mm.game_mechanism and mm:game_mechanism()
    if mech and mech.get_deus_run_controller then dc = mech:get_deus_run_controller() end
    local ls = LevelHelper and LevelHelper.current_level_settings and LevelHelper:current_level_settings()
    if not (dc and ls) then return false, ls, "outside-deus" end
    return true, ls, ls.mechanism == "deus" and "native-deus" or "injected-adventure"
end

local function vec(v, n)
    local out = {}
    for i = 1, n do out[i] = tostring(v and v[i] or "nil") end
    return table.concat(out, ",")
end

local function dump_node(level, sg, name)
    local node = sg and sg[name]
    if not node then
        emit(level .. "|node|" .. name .. "|missing", "node=%s missing", name)
        return
    end
    local wp, size = node.world_position, node.size
    local x, y = tonumber(wp and wp[1]), tonumber(wp and wp[2])
    local w, h = tonumber(size and size[1]), tonumber(size and size[2])
    emit(level .. "|node|" .. name .. "|" .. vec(wp, 3) .. "|" .. vec(size, 2),
        "node=%s parent=%s align=%s/%s local=[%s] world=[%s] size=[%s] bounds=[%s,%s,%s,%s]",
        name, tostring(node.parent), tostring(node.horizontal_alignment),
        tostring(node.vertical_alignment), vec(node.position, 3), vec(wp, 3), vec(size, 2),
        tostring(x), tostring(y), tostring(x and w and x + w), tostring(y and h and y + h))
end

local function dump_widget(level, name, widget)
    if not widget then
        emit(level .. "|widget|" .. name .. "|missing", "widget=%s missing", name)
        return
    end
    local content = compact(widget.content, 3, { n = 42 }, {})
    local style = compact(widget.style, 3, { n = 72 }, {})
    emit(level .. "|widget|" .. name .. "|" .. tostring(widget.scenegraph_id),
        "widget=%s scenegraph=%s offset=[%s] content=%s style=%s",
        name, tostring(widget.scenegraph_id), vec(widget.offset, 3), content, style)
end

local function dump_ct_row(capture_key, loot, index, row, layout)
    local widget = row and row.widget
    if not widget then
        emit(capture_key .. "|ct-row|" .. tostring(index) .. "|missing",
            "ct_row=%s missing", tostring(index))
        return
    end
    local styles = widget.style or {}
    local icon = styles.icon or {}
    local text = styles.text or {}
    local counter = styles.counter_text or {}
    local offset = widget.offset or {}
    local world_x = tonumber(loot and loot.world_position and loot.world_position[1])
    local world_y = tonumber(loot and loot.world_position and loot.world_position[2])
    local icon_w = tonumber(icon.texture_size and icon.texture_size[1]) or 0
    local icon_h = tonumber(icon.texture_size and icon.texture_size[2]) or 0
    local bound = layout and layout.bounds and layout.bounds[index]
    local text_w = tonumber(bound and bound.text_w) or 0
    local text_h = tonumber(text.area_size and text.area_size[2]) or 0
    local x = world_x and world_x + (tonumber(offset[1]) or 0) or nil
    local y = world_y and world_y + (tonumber(offset[2]) or 0) or nil
    emit(capture_key .. "|ct-row|" .. tostring(index),
        "ct_row=%d key=%s title=%q amount=%s scenegraph=%s widget_offset=[%s] origin=[%s,%s] icon_size=[%s] text_offset=[%s] text_area=[%s] measured_text_w=%s text_font=%s counter_offset=[%s] nominal_right=%s nominal_top=%s",
        index, tostring(row.key), tostring(row.title),
        tostring(widget.content and widget.content.amount), tostring(widget.scenegraph_id),
        vec(offset, 3), tostring(x), tostring(y), vec(icon.texture_size, 2),
        vec(text.offset, 3), vec(text.area_size, 2), tostring(text_w), tostring(text.font_size),
        vec(counter.offset, 3), tostring(x and x + icon_w + text_w),
        tostring(y and y + math.max(icon_h, text_h)))
end

local function geometry(self)
    local sg = self and self._ui_scenegraph
    local banner = sg and sg.banner_right
    local loot = sg and sg.loot_objective
    local divider = sg and sg.collectibles_divider
    if not (banner and loot and divider) then return nil end
    return {
        banner_x = tonumber(banner.world_position and banner.world_position[1]),
        loot_x = tonumber(loot.world_position and loot.world_position[1]),
        loot_y = tonumber(loot.world_position and loot.world_position[2]),
        divider_y = tonumber(divider.world_position and divider.world_position[2]),
    }
end

local function close(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) <= SETTLE_EPSILON
end

local function geometry_settled(self)
    local now = geometry(self)
    if not now then return false end
    local prev = self._ct_diag_native533_geometry
    self._ct_diag_native533_geometry = now
    self._ct_diag_native533_wait_frames = (self._ct_diag_native533_wait_frames or 0) + 1
    if prev and close(now.banner_x, prev.banner_x) and close(now.loot_x, prev.loot_x)
        and close(now.loot_y, prev.loot_y) and close(now.divider_y, prev.divider_y) then
        self._ct_diag_native533_stable_frames = (self._ct_diag_native533_stable_frames or 0) + 1
    else
        self._ct_diag_native533_stable_frames = 0
    end
    return self._ct_diag_native533_stable_frames >= SETTLE_FRAMES
        or self._ct_diag_native533_wait_frames >= MAX_WAIT_FRAMES
end

function M.arm(self, active)
    if not active or not self then return end
    local in_deus, ls, context = current_deus_level()
    if in_deus then
        self._ct_diag_native533_armed = true
        self._ct_diag_native533_level = tostring(ls.level_id or ls.level_name or "unknown")
        self._ct_diag_native533_context = context
        self._ct_diag_native533_geometry = nil
        self._ct_diag_native533_wait_frames = 0
        self._ct_diag_native533_stable_frames = 0
    end
end

function M.capture(self)
    if not (self and self._ct_diag_native533_armed and self._active) then return false end
    local in_deus, ls, context = current_deus_level()
    if not in_deus then return false end
    if not geometry_settled(self) then return false end
    self._ct_diag_native533_armed = nil
    local level = self._ct_diag_native533_level or tostring(ls.level_id or "unknown")
    local rl = rawget(_G, "RESOLUTION_LOOKUP") or {}
    local safe = Application and Application.user_setting and Application.user_setting("safe_rect") or nil
    local sg = self._ui_scenegraph
    local capture_key = table.concat({ level, context, tostring(rl.res_w) .. "x" .. tostring(rl.res_h),
        tostring(rl.scale), tostring(safe) }, "|")
    emit(capture_key .. "|header",
        "view=IngamePlayerListUI provider=LevelHelper.current_level_settings level=%s context=%s mechanism=%s mission_count=%s active=%s res=%sx%s scale=%s inv_scale=%s safe_rect=%s settled_frames=%s wait_frames=%s loot_objectives=%s ct_overlay=%s",
        level, context, tostring(ls.mechanism), tostring(self._mission_count), tostring(self._active),
        tostring(rl.res_w), tostring(rl.res_h), tostring(rl.scale), tostring(rl.inv_scale),
        tostring(safe), tostring(self._ct_diag_native533_stable_frames),
        tostring(self._ct_diag_native533_wait_frames), compact(ls.loot_objectives, 2, { n = 24 }, {}),
        tostring(self._ct_deus_collectibles ~= nil))
    for _, name in ipairs({ "screen", "banner_right", "loot_objective", "collectibles_name",
                            "collectibles_divider", "node_info" }) do
        dump_node(capture_key, sg, name)
    end
    dump_widget(capture_key, "collectibles_name", self._collectibles_name)
    dump_widget(capture_key, "collectibles_divider", self._collectibles_divider)
    dump_widget(capture_key, "node_info", self._node_info_widget)
    local missions = self._mission_widgets
    emit(capture_key .. "|mission-widgets|" .. tostring(type(missions) == "table" and #missions or -1),
        "mission_widgets count=%s table=%s", tostring(type(missions) == "table" and #missions or nil),
        compact(missions, 2, { n = 30 }, {}))
    if type(missions) == "table" then
        for i = 1, math.min(#missions, 4) do dump_widget(capture_key, "mission[" .. i .. "]", missions[i]) end
    end
    local cw = self._ct_deus_collectibles
    if cw then
        emit(capture_key .. "|ct-layout", "ct_layout=%s", compact(cw.layout, 3, { n = 32 }, {}))
        local loot = sg and sg.loot_objective
        for i = 1, math.min(#(cw.rows or {}), 4) do
            dump_ct_row(capture_key, loot, i, cw.rows[i], cw.layout)
        end
    end
    emit(capture_key .. "|summary",
        "capture complete records=%d cap=%d trigger=_set_active(true)->settled-post-draw contexts=native-deus,injected-adventure chat=false",
        records, RECORD_CAP)
    return true
end

function M.regression()
    if RECORD_CAP ~= 64 then return "#571 diagnostic record cap drifted" end
    if SETTLE_FRAMES ~= 3 or MAX_WAIT_FRAMES ~= 120 then
        return "#571 diagnostic settle contract drifted"
    end
    if type(M.arm) ~= "function" or type(M.capture) ~= "function" then
        return "#571 diagnostic lifecycle missing"
    end
end

function M.install()
    mod:hook_safe("IngamePlayerListUI", "_set_active", function(self, active)
        M.arm(self, active)
    end)
end

return M
