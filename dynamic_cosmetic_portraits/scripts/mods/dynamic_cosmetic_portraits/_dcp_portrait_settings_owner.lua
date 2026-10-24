-- (#509) Owner of DCP's persistent swap on the global Mercenary career row
-- (SPProfiles[5].careers[1] = CareerSettings.es_mercenary, a plain table:
-- Vermintide-2-Source-Code scripts/settings/profiles/sp_profiles.lua:132,315-316,
-- career_settings.lua:467-477). Live sync, unload restore and the named
-- regression check career_settings_swap_saves_and_restores all run these same
-- functions. Every write is read back; ownership is released only when the
-- captured vanilla pair is visibly back on the row. The one other writer is the
-- entry file's UnitFramesHandler._sync_player_stats hook: it points
-- portrait_image at one remote player's own portrait for a single synchronous
-- vanilla call and then puts the live value back. It never persists.
local M = {}

local function valid_state(state)
    return type(state) == "table"
end

local function valid_career(career)
    return type(career) == "table"
end

local function valid_portraits(portraits)
    return type(portraits) == "table"
        and type(portraits.hud) == "string"
        and portraits.hud ~= ""
        and type(portraits.medium) == "string"
        and portraits.medium ~= ""
end

function M.new()
    return {
        active = false,
        captured = false,
        career = nil,
        original_portrait_image = nil,
        original_picking_image = nil,
    }
end

local function write_pair(career, portrait_image, picking_image)
    career.portrait_image = portrait_image
    career.picking_image = picking_image
end

function M.apply(state, career, portraits)
    if not valid_state(state) then return false, "state-invalid" end
    if not valid_career(career) then return false, "career-invalid" end
    if not valid_portraits(portraits) then return false, "portraits-invalid" end
    if state.captured and state.career ~= career then
        return false, "career-mismatch"
    end
    -- Per-frame fast path (UnitFrameUI.draw calls sync every frame): an owned
    -- row already showing the requested pair needs no write and no garbage.
    if state.active and state.career == career
            and career.portrait_image == portraits.hud
            and career.picking_image == portraits.medium then
        return true
    end

    local before = {
        active = state.active,
        captured = state.captured,
        career = state.career,
        original_portrait_image = state.original_portrait_image,
        original_picking_image = state.original_picking_image,
        portrait_image = career.portrait_image,
        picking_image = career.picking_image,
    }

    if not state.captured then
        state.original_portrait_image = career.portrait_image
        state.original_picking_image = career.picking_image
        state.career = career
        state.captured = true
    end

    local ok, err = pcall(write_pair, career, portraits.hud, portraits.medium)
    if ok and (career.portrait_image ~= portraits.hud
            or career.picking_image ~= portraits.medium) then
        ok = false
        err = "write-not-visible"
    end
    if not ok then
        local rollback_ok, rollback_err = pcall(
            write_pair, career, before.portrait_image, before.picking_image)
        local restored = rollback_ok
            and career.portrait_image == before.portrait_image
            and career.picking_image == before.picking_image
        if restored then
            state.active = before.active
            state.captured = before.captured
            state.career = before.career
            state.original_portrait_image = before.original_portrait_image
            state.original_picking_image = before.original_picking_image
        else
            -- A partial write is now externally visible. Retain (or recover)
            -- ownership so unload/the next sync can retry the captured original;
            -- clearing capture here would strand a global SPProfiles mutation.
            state.active = true
            state.captured = true
            state.career = career
            if before.captured then
                state.original_portrait_image = before.original_portrait_image
                state.original_picking_image = before.original_picking_image
            end
        end
        local suffix = restored and "" or ":rollback-failed:" .. tostring(rollback_err)
        return false, "apply-failed:" .. tostring(err) .. suffix
    end

    state.active = true
    return true
end

function M.restore(state, career_override)
    if not valid_state(state) then return false, "state-invalid" end
    if not state.active then return true, "inactive" end
    if not state.captured or not valid_career(state.career) then
        return false, "capture-missing"
    end

    local career = career_override or state.career
    if not valid_career(career) then return false, "career-invalid" end
    if career ~= state.career then return false, "career-mismatch" end

    local before_portrait = career.portrait_image
    local before_picking = career.picking_image
    local ok, err = pcall(
        write_pair,
        career,
        state.original_portrait_image,
        state.original_picking_image)
    if ok and (career.portrait_image ~= state.original_portrait_image
            or career.picking_image ~= state.original_picking_image) then
        ok = false
        err = "write-not-visible"
    end
    if not ok then
        pcall(write_pair, career, before_portrait, before_picking)
        return false, "restore-failed:" .. tostring(err)
    end

    state.active = false
    state.captured = false
    state.career = nil
    return true
end

-- Vanilla HUD portrait for the per-player seams (HUD frames, Tab list, score
-- screen) when a subject wears no tracked cosmetic. While the owner holds the
-- row, the live value is DCP's swap and the captured original is vanilla. While
-- it does not, no DCP portrait is on the row, so the live value is what vanilla
-- built the widget from. Never depends on an apply having run: an untracked
-- LOCAL Mercenary never applies, yet remote rows still need correcting.
function M.vanilla_portrait(state, career)
    if valid_state(state) and state.active and state.captured then
        return state.original_portrait_image
    end
    if valid_career(career) then return career.portrait_image end
    return nil
end

local function find_custom(custom_sets, field, value)
    if value == nil then return nil end
    for _, map in ipairs(type(custom_sets) == "table" and custom_sets or {}) do
        for key, set in pairs(type(map) == "table" and map or {}) do
            if type(set) == "table" and set[field] == value then return key end
        end
    end
    return nil
end

-- Body of the named runtime check career_settings_swap_saves_and_restores.
-- Returns a failure string, or nil plus an optional note naming a skipped live
-- half. The named-check adapter reports that note as SKIP, not PASS. ctx fields:
--   live_career  the live SPProfiles[5].careers[1] row (nil => live parts skip)
--   production   the production owner state DCP's sync/unload path uses
--   custom_sets  list of DCP portrait maps (cosmetic key -> { hud = ... })
function M.check_transaction(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    -- 1. Synthetic row: capture, repeat apply keeps the vanilla pair, exact restore.
    local state = M.new()
    local vanilla_hud, vanilla_medium = "issue509_vanilla_hud", "issue509_vanilla_medium"
    local row = { portrait_image = vanilla_hud, picking_image = vanilla_medium }
    local ok, reason = M.apply(state, row, { hud = "issue509_hud_a", medium = "issue509_medium_a" })
    if not ok then return "first semantic apply failed: " .. tostring(reason) end
    ok, reason = M.apply(state, row, { hud = "issue509_hud_b", medium = "issue509_medium_b" })
    if not ok then return "repeat semantic apply failed: " .. tostring(reason) end
    if row.portrait_image ~= "issue509_hud_b" or row.picking_image ~= "issue509_medium_b" then
        return "repeat apply did not expose the new pair"
    end
    if state.original_portrait_image ~= vanilla_hud
            or state.original_picking_image ~= vanilla_medium then
        return "repeat apply overwrote the captured vanilla pair"
    end
    ok, reason = M.restore(state, row)
    if not ok then return "semantic restore failed: " .. tostring(reason) end
    if row.portrait_image ~= vanilla_hud or row.picking_image ~= vanilla_medium then
        return "semantic restore did not restore both vanilla fields"
    end
    if state.active or state.captured or state.career ~= nil then
        return "semantic restore left transaction ownership active"
    end

    -- 2. Live row identity transaction: write the row's own pair back through
    -- the production owner, so nothing visible changes, and require the row to
    -- accept both writes and end exactly as it started.
    local live = ctx.live_career
    local skipped = nil
    if type(live) ~= "table" then
        skipped = "live half skipped: no SPProfiles[5].careers[1] row"
    elseif not valid_portraits({ hud = live.portrait_image, medium = live.picking_image }) then
        skipped = "live half skipped: the live Mercenary row has no portrait pair"
    else
        local hud, medium = live.portrait_image, live.picking_image
        local live_state = M.new()
        ok, reason = M.apply(live_state, live, { hud = hud, medium = medium })
        if not ok then return "live career row apply failed: " .. tostring(reason) end
        ok, reason = M.restore(live_state, live)
        if not ok then return "live career row restore failed: " .. tostring(reason) end
        if live.portrait_image ~= hud or live.picking_image ~= medium then
            return "live identity transaction changed the career row"
        end
    end

    -- 3. Production state: an active owner holds the live row, and its captured
    -- original is never one of DCP's own portraits (a swapped value captured as
    -- vanilla would leak into every later restore).
    local production = ctx.production
    if type(production) == "table" and production.active then
        if not production.captured then
            return "production owner is active without a captured original"
        end
        if type(live) == "table" and production.career ~= live then
            return "production owner holds a row other than the live Mercenary career"
        end
        local key = find_custom(ctx.custom_sets, "hud", production.original_portrait_image)
            or find_custom(ctx.custom_sets, "medium", production.original_picking_image)
        if key then
            return "captured original is DCP portrait " .. tostring(key)
                .. ": a swapped value leaked into the vanilla capture"
        end
    end

    -- 4. Unowned swap: while the owner does not hold the row, no DCP portrait
    -- may be on it, because nothing would restore it on hat removal or unload.
    -- The temporary _sync_player_stats bracket restores synchronously, so it is
    -- never in flight while this check runs.
    if type(production) == "table" and not production.active and type(live) == "table" then
        local key = find_custom(ctx.custom_sets, "hud", live.portrait_image)
            or find_custom(ctx.custom_sets, "medium", live.picking_image)
        if key then
            return "unowned DCP portrait " .. tostring(key)
                .. " is on the live Mercenary row: nothing will restore it"
        end
    end
    return nil, skipped
end

return M
