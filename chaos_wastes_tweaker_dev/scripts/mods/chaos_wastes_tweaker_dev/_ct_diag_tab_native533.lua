-- #533 native Chaos Wastes hold-Tab layout census.
-- Observation-only: arms on the native player-list activation edge and samples
-- after vanilla _draw, when UISceneGraph world positions are final.
local mod = get_mod("ct_dev")
local M = {}

local RECORD_CAP = 24
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
    if printf then printf("[ct:533-native] %s", line) else mod:info("[ct:533-native] %s", line) end
    return true
end

local function current_native_deus_level()
    local dc
    local mm = Managers and Managers.mechanism
    local mech = mm and mm.game_mechanism and mm:game_mechanism()
    if mech and mech.get_deus_run_controller then dc = mech:get_deus_run_controller() end
    local ls = LevelHelper and LevelHelper.current_level_settings and LevelHelper:current_level_settings()
    return dc ~= nil and ls and ls.mechanism == "deus", ls
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

function M.arm(self, active)
    if not active or not self then return end
    local native, ls = current_native_deus_level()
    if native then
        self._ct_diag_native533_armed = true
        self._ct_diag_native533_level = tostring(ls.level_id or ls.level_name or "unknown")
    end
end

function M.capture(self)
    if not (self and self._ct_diag_native533_armed and self._active) then return false end
    local native, ls = current_native_deus_level()
    if not native then return false end
    self._ct_diag_native533_armed = nil
    local level = self._ct_diag_native533_level or tostring(ls.level_id or "unknown")
    local rl = rawget(_G, "RESOLUTION_LOOKUP") or {}
    local safe = Application and Application.user_setting and Application.user_setting("safe_rect") or nil
    local sg = self._ui_scenegraph
    emit(level .. "|header|" .. tostring(rl.res_w) .. "x" .. tostring(rl.res_h) .. "|" .. tostring(rl.scale),
        "view=IngamePlayerListUI provider=LevelHelper.current_level_settings level=%s mechanism=%s mission_count=%s active=%s res=%sx%s scale=%s inv_scale=%s safe_rect=%s loot_objectives=%s ct_overlay=%s",
        level, tostring(ls.mechanism), tostring(self._mission_count), tostring(self._active),
        tostring(rl.res_w), tostring(rl.res_h), tostring(rl.scale), tostring(rl.inv_scale),
        tostring(safe), compact(ls.loot_objectives, 2, { n = 24 }, {}),
        tostring(self._ct_deus_collectibles ~= nil))
    for _, name in ipairs({ "screen", "banner_right", "loot_objective", "collectibles_name",
                            "collectibles_divider", "node_info" }) do
        dump_node(level, sg, name)
    end
    dump_widget(level, "collectibles_name", self._collectibles_name)
    dump_widget(level, "collectibles_divider", self._collectibles_divider)
    dump_widget(level, "node_info", self._node_info_widget)
    local missions = self._mission_widgets
    emit(level .. "|mission-widgets|" .. tostring(type(missions) == "table" and #missions or -1),
        "mission_widgets count=%s table=%s", tostring(type(missions) == "table" and #missions or nil),
        compact(missions, 2, { n = 30 }, {}))
    if type(missions) == "table" then
        for i = 1, math.min(#missions, 4) do dump_widget(level, "mission[" .. i .. "]", missions[i]) end
    end
    emit(level .. "|summary", "capture complete records=%d cap=%d trigger=_set_active(true)->post_draw chat=false", records, RECORD_CAP)
    return true
end

function M.regression()
    if RECORD_CAP ~= 24 then return "#533 diagnostic record cap drifted" end
    if type(M.arm) ~= "function" or type(M.capture) ~= "function" then
        return "#533 diagnostic lifecycle missing"
    end
end

function M.install()
    mod:hook_safe("IngamePlayerListUI", "_set_active", function(self, active)
        M.arm(self, active)
    end)
end

return M
