-- career_tweaker / _crt_diagnostics.lua
--
-- Responsibility: Read-only talent/buff diagnostics. Owns the /crt_dump_talents
-- command, the reusable dump body (mod.crt_dump_career_talents), and the
-- auto-dump data-harness that captures a reworked career's live talent/buff map
-- to the log once per session (no /command needed). Pure reads; no gameplay
-- effect.
--
-- Public surface (via mod fields, consumed by the entry's lifecycle callbacks):
--   mod.crt_dump_career_talents(career, reason) -> bool   -- reusable dump body
--   mod._crt_auto_dump_check()          -- dump if local career is under rework
--   mod._crt_dump_retry_tick(dt)        -- per-frame retry pump (driven by mod.update)
--   mod._crt_start_dump_retry()         -- arm the ~20s retry window (StateIngame enter)
--
-- Manifest position: after the module dofiles (needs `mod`). The entry's
-- mod.update calls mod._crt_dump_retry_tick(dt); on_game_state_changed calls
-- mod._crt_start_dump_retry(); HeroWindowTalents.on_enter (in the independent
-- _crt_talent_menu_guard) calls mod._crt_auto_dump_check(). All are runtime,
-- mod-field-guarded, so load
-- order relative to those callers is not load-bearing. Split out of
-- career_tweaker.lua (v0.3.57-dev, Phase 1 OOP decomposition); pure structural
-- move, no behavior change.

local mod = get_mod("crt")
mod._crt = mod._crt or {}

-- Dump a career's CURRENT (live, post-rework) talent tree so we can re-point
-- reworks whose target talent name was guessed from a stale decompile. The
-- running game has the real data the local decompile may lack (e.g. the Zealot
-- "Holy Fortitude" talent isn't in the decompile by that name). Usage:
--   /crt_dump_talents            (defaults to wh_zealot)
--   /crt_dump_talents wh_zealot
-- Logs [crt:talent] lines (enable Debug Logging) + each talent's first buff's
-- stat_buff/bonus/multiplier so the HP/max_health talent is identifiable.
-- Reusable dump body. `reason` tags the log ("manual"/"auto"). Writes [crt:talent]
-- lines via mod:info (always goes to the console_logs file, regardless of the
-- chat-echo gate), so an auto-dump lands in the log even with Debug Logging off.
-- Also prints each buff template's full proc fields (proc_chance/chunk_size/
-- max_stacks/duration/event/buff_func/buff_to_add) so a tweak can be wired from
-- the dump alone without re-grepping the source.
mod.crt_dump_career_talents = function(career, reason)
    career = (career and career ~= "" and career) or "wh_zealot"
    local CS = rawget(_G, "CareerSettings")
    local TT = rawget(_G, "TalentTrees")
    local TL = rawget(_G, "TalentIDLookup")
    local TA = rawget(_G, "Talents")
    local BT = rawget(_G, "BuffTemplates")
    local cs = CS and CS[career]
    if not cs then mod:info("[crt:talent] unknown career: %s", tostring(career)); return false end
    local hero = cs.profile_name
    local tree = TT and TT[hero] and TT[hero][cs.talent_tree_index]
    if not tree then mod:info("[crt:talent] no talent tree for %s", tostring(career)); return false end
    mod:info("[crt:talent] === %s (hero=%s tree=%s) [%s] ===", tostring(career), tostring(hero), tostring(cs.talent_tree_index), tostring(reason or "manual"))
    for row_i, row in ipairs(tree) do
        for col_i, tname in ipairs(row) do
            local lookup = TL and TL[tname]
            local talent = lookup and TA and TA[lookup.hero_name] and TA[lookup.hero_name][lookup.talent_id]
            local buffs = talent and talent.buffs
            local buffstr = (type(buffs) == "table") and table.concat(buffs, ",") or "?"
            local disp = tname
            local lok, loc = pcall(Localize, tname)
            if lok and loc and loc ~= tname and not tostring(loc):find("^<") then disp = loc end
            mod:info("[crt:talent] [%d,%d] %s | name=%s | buffs=[%s] | icon=%s",
                row_i, col_i, disp, tname, buffstr, tostring(talent and talent.icon))
            if type(buffs) == "table" then
                for _, bn in ipairs(buffs) do
                    local bt = BT and BT[bn]
                    local b1 = bt and bt.buffs and bt.buffs[1]
                    if b1 then
                        mod:info("[crt:talent]      buff %s | stat_buff=%s bonus=%s multiplier=%s proc_chance=%s chunk_size=%s max_stacks=%s duration=%s event=%s buff_func=%s buff_to_add=%s",
                            tostring(bn), tostring(b1.stat_buff), tostring(b1.bonus), tostring(b1.multiplier),
                            tostring(b1.proc_chance), tostring(b1.chunk_size), tostring(b1.max_stacks),
                            tostring(b1.duration), tostring(b1.event), tostring(b1.buff_func), tostring(b1.buff_to_add))
                    end
                end
            end
        end
    end
    return true
end

mod:command("crt_dump_talents", "Dump a career's live talents + buffs (default wh_zealot)", function(career)
    local ok = mod.crt_dump_career_talents(career, "manual")
    if ok then mod:echo("[crt] dumped " .. tostring((career ~= "" and career) or "wh_zealot") .. " talents to log — paste the [crt:talent] lines") end
end)

-- ============================================================
-- Auto-dump talents for careers under active rework (bw_unchained, es_mercenary)
-- ============================================================
-- Data-harness (PROJECT_STANDARDS debug doctrine): when the local player is on a
-- career we're actively reworking, dump its talent/buff map to the log
-- automatically (once per career per session) so the exact internal names +
-- proc values are captured from normal play -- no /command needed. Pure read; no
-- gameplay effect. Add a career here while it's being worked on.
local _CRT_AUTO_DUMP_CAREERS = { bw_unchained = true, es_mercenary = true }
local _crt_auto_dumped = {}

-- Resolve the LOCAL player's career, NEVER throwing. The whole body is pcall'd
-- because `Managers.player:local_player()` itself raises "Network backend has
-- not been set" (player_manager.lua:559) at early states (StateSplashScreen /
-- StateLoading) -- that was the v0.3.33 error spam (only the inner lookups were
-- guarded, not local_player). Prefer the career_system extension on the spawned
-- unit (reliable once spawned); fall back to player:career_name() (which itself
-- returns nil until the profile's display_name loads, so it's the weaker source).
local function _crt_local_career()
    local ok, career = pcall(function()
        local pm = Managers.player
        local p = pm and pm:local_player()
        if not p then return nil end
        local unit = p.player_unit
        if unit and Unit.alive(unit) then
            local ce = ScriptUnit.has_extension(unit, "career_system")
            if ce then
                local n = ce:career_name()
                if type(n) == "string" then return n end
            end
        end
        if p.career_name then
            local n = p:career_name()
            if type(n) == "string" then return n end
        end
        return nil
    end)
    return (ok and type(career) == "string") and career or nil
end

-- Exposed so the lifecycle hooks (on_game_state_changed), the per-frame retry,
-- and the talent-window on_enter hook can all drive it; resolves at call time.
-- De-dupe is set ONLY on a SUCCESSFUL dump, so an early call that resolves the
-- career but hits a not-yet-ready talent table can still succeed on a retry.
mod._crt_auto_dump_check = function()
    local career = _crt_local_career()
    if not (career and _CRT_AUTO_DUMP_CAREERS[career]) then return end
    if _crt_auto_dumped[career] then return end
    mod:info("[crt:talent] auto-dump for %s (career under rework) -------------------", career)
    if mod.crt_dump_career_talents(career, "auto") then
        _crt_auto_dumped[career] = true
    end
end

-- Per-frame retry window: career/unit aren't ready at StateIngame *enter*, so
-- after each enter we retry the (throw-proof, de-duped) check ~1x/sec for a short
-- window until it dumps. Guarantees the dump fires when you're actually playing a
-- reworked career, without depending on opening the talent screen. Pumped from
-- the entry's mod.update (which also drives the OE cooldown tick).
local _crt_dump_retry_left = 0
local _crt_dump_retry_acc = 0
mod._crt_dump_retry_tick = function(dt)
    if _crt_dump_retry_left <= 0 then return end
    _crt_dump_retry_left = _crt_dump_retry_left - (dt or 0)
    _crt_dump_retry_acc = _crt_dump_retry_acc + (dt or 0)
    if _crt_dump_retry_acc >= 1.0 then
        _crt_dump_retry_acc = 0
        if mod._crt_auto_dump_check then mod._crt_auto_dump_check() end
    end
end
mod._crt_start_dump_retry = function()
    _crt_dump_retry_left = 20.0
    _crt_dump_retry_acc = 1.0  -- fire on the next frame, then ~1x/sec
end

-- ============================================================
-- Issue #699: Foot Knight effect-icon presentation census
-- ============================================================
-- BuffUI consumes the live sub-template's `icon` and indexes its widget by the
-- sub-template `name` [src: scripts/ui/hud_ui/buff_ui.lua:105-134,216-267].
-- The mechanics regression already proved the authored fields exist, but that
-- cannot distinguish a missing active buff, an unavailable atlas entry, a full
-- HUD widget pool, a misleading bookkeeping icon, an atlas identity alias, or
-- a third-party HideBuffs disposition. This automatic, transition-only census
-- captures those runtime boundaries without a command or HUD mutation.
local _CRT_NUMB_TO_PAIN_ICON = "sienna_unchained_reduced_damage_taken_after_venting"
local _CRT_FK_ICON_SPECS = {
    {
        outer = "crt_fk_uninterruptible_heavies",
        active = "crt_fk_uninterruptible_heavies",
        role = "bookkeeping-heavy-immunity",
    },
    {
        outer = "crt_fk_rock_dodge_distance",
        active = "crt_fk_rock_dodge_distance",
        role = "bookkeeping-rock-dodge-penalty",
    },
    {
        outer = "crt_fk_rock_shield_power",
        active = "crt_fk_rock_shield_power",
        role = "conditional-rock-shield-power",
        expected_icon = "markus_knight_passive_block_cost_aura",
    },
    {
        outer = "crt_fk_teamwork_great_power",
        active = "crt_fk_teamwork_great_power",
        role = "conditional-teamwork-great-power",
        expected_icon = "markus_knight_damage_taken_ally_proximity",
    },
    {
        outer = "crt_fk_final_march",
        active = "crt_fk_final_march_power",
        role = "timed-final-march",
        expected_icon = "markus_knight_movement_speed_on_incapacitated_allies",
    },
}

local _crt_fk_icon_probe_accumulator = 0
local _crt_fk_icon_last = {}
local _CRT_FK_ICON_LOG_CAP = 64
local _crt_fk_icon_log_count = 0

local function _crt_fk_icon_log(format, ...)
    if _crt_fk_icon_log_count >= _CRT_FK_ICON_LOG_CAP then return false end
    _crt_fk_icon_log_count = _crt_fk_icon_log_count + 1
    pcall(printf, format, ...)
    return true
end

local function _crt_fk_icon_local_unit()
    local player_manager = Managers.player
    local player = player_manager and player_manager.local_player
        and player_manager:local_player()
    return player and player.player_unit
end

-- Mirror BuffUI._sync_buffs exactly: while spectating, its widget collection
-- is sourced from `_spectated_player_unit`, not the local player's unit. This
-- lets the same bounded census cover the host spectating a bot without adding
-- a second presentation path or any network traffic.
local function _crt_fk_icon_observed_unit(hud)
    local spectated = hud and hud._is_spectator and hud._spectated_player_unit
    if spectated and Unit.alive(spectated) then return spectated, "spectated" end
    return _crt_fk_icon_local_unit(), "local"
end

local function _crt_fk_icon_atlas_identity(icon)
    if type(icon) ~= "string" or not UIAtlasHelper
       or not UIAtlasHelper.get_atlas_settings_by_texture_name then
        return false, "none"
    end
    if UIAtlasHelper.has_atlas_settings_by_texture_name then
        local ok, present = pcall(UIAtlasHelper.has_atlas_settings_by_texture_name, icon)
        if not ok or present ~= true then return false, "missing" end
    end
    local ok, settings = pcall(UIAtlasHelper.get_atlas_settings_by_texture_name, icon)
    if not ok or type(settings) ~= "table" then return false, "missing" end
    local uv00, uv11 = settings.uv00 or {}, settings.uv11 or {}
    return true, string.format("%s:%.6f,%.6f:%.6f,%.6f",
        tostring(settings.material_name), tonumber(uv00[1]) or -1,
        tonumber(uv00[2]) or -1, tonumber(uv11[1]) or -1,
        tonumber(uv11[2]) or -1)
end

local function _crt_fk_icon_hidebuffs_disposition(buff_type)
    local hide_buffs = get_mod("HideBuffs")
    local manager = hide_buffs and hide_buffs.bm
    if not manager then return false, false, false end

    local hidden, priority = false, false
    if manager.is_hidden_buff then
        local ok, result = pcall(manager.is_hidden_buff, buff_type)
        hidden = ok and result == true
    end
    if manager.is_priority_buff then
        local ok, result = pcall(manager.is_priority_buff, buff_type)
        priority = ok and result == true
    end
    return true, hidden, priority
end

mod._crt_foot_knight_icon_probe_tick = function(dt)
    _crt_fk_icon_probe_accumulator = _crt_fk_icon_probe_accumulator + (dt or 0)
    if _crt_fk_icon_probe_accumulator < 0.25 then return end
    _crt_fk_icon_probe_accumulator = 0

    local hud
    if Managers.ui and Managers.ui.get_hud_component then
        local ok, component = pcall(Managers.ui.get_hud_component, Managers.ui, "BuffUI")
        if ok then hud = component end
    end
    local unit, subject = _crt_fk_icon_observed_unit(hud)
    if not (unit and Unit.alive(unit)) then return end
    local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_extension then return end

    local active_by_name = {}
    local buffs = buff_extension:active_buffs()
    for _, buff in ipairs(buffs or {}) do
        local template = not buff.removed and buff.template
        if template then
            if type(buff.buff_type) == "string" then active_by_name[buff.buff_type] = buff end
            if type(template.name) == "string" then active_by_name[template.name] = buff end
        end
    end

    local widget_count = hud and hud._active_buff_widgets and #hud._active_buff_widgets or -1
    local unused_widget_count = hud and hud._unused_buff_widgets
        and #hud._unused_buff_widgets or -1
    local widget_capacity = widget_count >= 0 and unused_widget_count >= 0
        and widget_count + unused_widget_count or -1

    for _, spec in ipairs(_CRT_FK_ICON_SPECS) do
        local state_key = subject .. ":" .. spec.outer
        local active_buff = active_by_name[spec.active]
        if active_buff then
            local active_template = active_buff.template or {}
            local icon = active_template.icon
            local atlas, atlas_identity = _crt_fk_icon_atlas_identity(icon)
            local _, numb_identity = _crt_fk_icon_atlas_identity(_CRT_NUMB_TO_PAIN_ICON)
            local widget = hud and hud._buff_name_to_widget
                and hud._buff_name_to_widget[active_template.name]
            local widget_icon = widget and widget.content and widget.content.texture_icon
            local expected_visible = spec.expected_icon ~= nil
            local semantic_match = icon == spec.expected_icon
                and widget_icon == spec.expected_icon
            if not expected_visible then
                semantic_match = icon == nil and widget == nil
            end
            local numb_collision = icon == _CRT_NUMB_TO_PAIN_ICON
                or widget_icon == _CRT_NUMB_TO_PAIN_ICON
                or (atlas and atlas_identity == numb_identity)
            local hide_buffs, hidden, priority =
                _crt_fk_icon_hidebuffs_disposition(active_buff.buff_type or spec.active)
            local signature = table.concat({
                subject, tostring(spec.role), tostring(spec.expected_icon), tostring(icon),
                tostring(atlas), tostring(atlas_identity), tostring(widget ~= nil),
                tostring(widget_icon), tostring(semantic_match), tostring(numb_collision),
                tostring(widget_count), tostring(widget_capacity), tostring(hide_buffs),
                tostring(hidden), tostring(priority),
            }, "|")
            if _crt_fk_icon_last[state_key] ~= signature then
                _crt_fk_icon_last[state_key] = signature
                _crt_fk_icon_log(
                    "[crt:699] icon active=true subject=%s buff=%s role=%s template=%s expected=%s icon=%s atlas=%s atlas_id=%s widget=%s widget_icon=%s semantic_match=%s numb_collision=%s hud_widgets=%d hud_capacity=%d hidebuffs=%s hidden=%s priority=%s",
                    subject, tostring(spec.outer), tostring(spec.role),
                    tostring(active_template.name), tostring(spec.expected_icon), tostring(icon),
                    tostring(atlas), tostring(atlas_identity), tostring(widget ~= nil),
                    tostring(widget_icon), tostring(semantic_match), tostring(numb_collision),
                    widget_count, widget_capacity, tostring(hide_buffs), tostring(hidden),
                    tostring(priority))
            end
        elseif _crt_fk_icon_last[state_key]
           and _crt_fk_icon_last[state_key] ~= "inactive" then
            _crt_fk_icon_last[state_key] = "inactive"
            _crt_fk_icon_log("[crt:699] icon active=false subject=%s buff=%s",
                subject, tostring(spec.outer))
        end
    end
end
