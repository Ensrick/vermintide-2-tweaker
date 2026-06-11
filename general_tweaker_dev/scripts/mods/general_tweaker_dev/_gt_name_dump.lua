local mod = get_mod("gt_dev")

-- ============================================================================
-- Self-refreshing vanilla-name localization dump (Phase 1 of the name-map loop)
-- ============================================================================
-- WHY THIS EXISTS
--   tools/gen-name-map/gen-name-map.ps1 resolves every MOD-created display name
--   from repo data, but leaves ~3,010 VANILLA names `unresolved` because the
--   English strings live in undumped `.package` bundles, NOT in the decompiled
--   source. The ONLY runtime place those strings exist resolved is the running
--   game, where Localize(loc_key) returns the real English. This module walks
--   the in-memory data tables on keep/inn entry and emits
--       [gt:name_dump] <loc_key>\t<English>
--   lines to the console log, in the SAME tab-separated shape as
--   dumps/boon_loc_dump.txt. A repo-side step (the generator itself) greps the
--   newest console-*.log for those lines and ingests them. No manual command.
--
-- WHY CONSOLE-LOG OUTPUT (not a real file)
--   PHASE-0 FINDING (verified against the existing gt `/dump_level` code, line
--   ~5472): VMF mods CANNOT write arbitrary files. `io.open(path, "w")` is
--   sandboxed out, `mod:get_temp_data_directory` does not exist in this VMF
--   build, and `Application.save_user_settings_to_file` is not callable from
--   sandboxed mod code. The established gt doctrine for every dump command is
--   to emit to the console log with a greppable prefix and let a repo-side
--   step parse the newest `%APPDATA%\Fatshark\Vermintide 2\console_logs\*.log`.
--   We follow that doctrine here with the `[gt:name_dump]` prefix.
--
-- BUILD-VERSION GATE
--   Vanilla English COULD only change across a game patch. So we store the
--   last-dumped build id (Application.build_identifier()) in VMF settings and
--   only (re)dump when the current build differs. A player who never patches
--   dumps exactly once, ever; a patch re-fires the dump automatically — which
--   is exactly when names could have changed. That is the "happens
--   automatically when needed" the maintainer asked for.
--
-- LOGGING (PROJECT_STANDARDS.md § 3.6)
--   The dump payload lines go through `mod:info` (operational telemetry that
--   must land in the log regardless of the debug toggle, same as every other
--   gt dump). The "dump completed" CONFIRMATION is `_dbg` (log only). A FAILURE
--   to dump is `_dbg_alert` (chat + log, gated on debug logging). The applied
--   marker is untouched.
-- ============================================================================

local M = {}

local NAME_DUMP_PREFIX = "[gt:name_dump]"
-- VMF settings key that remembers the build id we last dumped for. Namespaced
-- so it can't collide with any user-facing setting in the data widget tree.
local LAST_DUMPED_BUILD_KEY = "gt_name_dump_last_build"

-- file-local debug helpers mirror the main file's two-channel discipline
-- (PROJECT_STANDARDS.md § 3.6). Both gate on `enable_debug_logging`.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[gt:name_dump] " .. fmt, ...)
    end
end
local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:warning("[gt:name_dump] " .. fmt, ...)
        mod:echo("[gt:name_dump] " .. string.format(fmt, ...))
    end
end

local function _safe_localize(key)
    if not key or key == "" then return nil end
    local ok, result = pcall(Localize, key)
    if not ok then return nil end
    -- Localize returns the key verbatim when there is no string-table entry.
    -- Such a "resolution" is worthless (the generator already has the loc key),
    -- so treat key-equals-result as unresolved and skip emitting it.
    if result == nil or result == key then return nil end
    -- Strip the rare leading/trailing whitespace; collapse newlines so each
    -- emitted line stays a single tab-separated record the parser can split.
    result = tostring(result):gsub("[\r\n]+", " ")
    return result
end

local function _current_build()
    local b = rawget(_G, "BUILD")
    if b == nil then
        local ok, res = pcall(function() return Application.build_identifier() end)
        if ok then b = res end
    end
    if b == nil then
        local ok, res = pcall(function() return Application.build() end)
        if ok then b = res end
    end
    return b and tostring(b) or "unknown"
end

-- ----------------------------------------------------------------------------
-- The walk. Collects loc_key -> English into a dedup map (first non-nil wins),
-- then emits sorted `[gt:name_dump] <loc_key>\t<English>` lines via mod:info.
-- Returns (emitted_count, source_counts_table).
-- ----------------------------------------------------------------------------
local function _collect_and_emit()
    local pairs_map = {}        -- loc_key -> English
    local counts = { iml = 0, iml_desc = 0, career = 0, hero = 0, breed = 0 }

    local function consider(loc_key, bucket)
        if not loc_key or loc_key == "" then return end
        if pairs_map[loc_key] ~= nil then return end   -- already resolved
        local eng = _safe_localize(loc_key)
        if eng then
            pairs_map[loc_key] = eng
            if bucket then counts[bucket] = (counts[bucket] or 0) + 1 end
        end
    end

    -- 1) ItemMasterList: display_name + description loc keys. This covers
    --    weapons, hats, skins, frames, weapon_skins, trinkets, deeds, etc. —
    --    the bulk of the ~3,010 unresolved vanilla entries.
    local IML = rawget(_G, "ItemMasterList")
    if IML then
        for _, item in pairs(IML) do
            if type(item) == "table" then
                consider(item.display_name, "iml")
                consider(item.description, "iml_desc")
            end
        end
    end

    -- 2) Careers + heroes via SPProfiles (mirrors /dump_glossary's source). The
    --    career display_name is a loc key (e.g. "dr_ironbreaker"); the hero
    --    ingame_display_name / display_name likewise.
    local SPProfiles = rawget(_G, "SPProfiles")
    if SPProfiles then
        for _, profile in ipairs(SPProfiles) do
            if type(profile) == "table" then
                consider(profile.ingame_display_name or profile.display_name, "hero")
                if profile.careers then
                    for _, career in ipairs(profile.careers) do
                        if type(career) == "table" then
                            consider(career.display_name or career.name, "career")
                        end
                    end
                end
            end
        end
    end

    -- 3) Breeds: boss breeds carry a `display_name` loc key; most fodder breeds
    --    don't. Emit whatever resolves; the generator keys breeds by the breed
    --    key itself, so a resolved display_name loc key is bonus coverage.
    local Breeds = rawget(_G, "Breeds")
    if Breeds then
        for _, breed in pairs(Breeds) do
            if type(breed) == "table" then
                consider(breed.display_name, "breed")
            end
        end
    end

    -- Emit deterministically (sorted by loc_key) so two dumps of the same build
    -- produce byte-identical log slices — easy to diff / verify.
    local keys = {}
    for k in pairs(pairs_map) do keys[#keys + 1] = k end
    table.sort(keys)

    local build = _current_build()
    -- Header line carries provenance the generator records: build id + count.
    mod:info("%s BEGIN build=%s count=%d", NAME_DUMP_PREFIX, build, #keys)
    for _, k in ipairs(keys) do
        -- Tab-separated, same shape as boon_loc_dump.txt (key<TAB>English).
        mod:info("%s %s\t%s", NAME_DUMP_PREFIX, k, pairs_map[k])
    end
    mod:info("%s END build=%s count=%d", NAME_DUMP_PREFIX, build, #keys)

    return #keys, counts, build
end

-- ----------------------------------------------------------------------------
-- Public: run a dump. `force` bypasses the build-version gate (manual command).
-- Returns true if a dump was emitted, false if skipped/failed.
-- ----------------------------------------------------------------------------
function M.run_dump(force)
    -- Data tables must be loaded; in the keep they always are. Bail quietly if
    -- somehow called too early (this is the conservative-default `_dbg` path,
    -- not an alert — an unmet precondition is not an error per § 3.6).
    if not rawget(_G, "ItemMasterList") then
        _dbg("ItemMasterList not loaded yet; skipping name dump")
        return false
    end

    local build = _current_build()
    local last = mod:get(LAST_DUMPED_BUILD_KEY)
    if not force and last == build then
        _dbg("name dump already current for build=%s; skipping", build)
        return false
    end

    local ok, count, counts, dumped_build = pcall(_collect_and_emit)
    if not ok then
        -- A genuine failure (walk threw) IS the alert path per § 3.6.
        _dbg_alert("name dump FAILED: %s", tostring(count))
        return false
    end

    mod:set(LAST_DUMPED_BUILD_KEY, dumped_build)
    -- Confirmation is log-only (`_dbg`), per § 3.6 two-channel discipline.
    _dbg("name dump complete build=%s emitted=%d (iml=%d iml_desc=%d career=%d hero=%d breed=%d)%s",
        dumped_build, count, counts.iml, counts.iml_desc, counts.career, counts.hero, counts.breed,
        force and " [forced]" or "")
    return true
end

-- ----------------------------------------------------------------------------
-- Auto-fire on keep/inn entry. We hook into gt's existing on_game_state_changed
-- chain via the wrapper pattern already used in this file (line ~1026 wraps it
-- for the keep-context dump). We only fire on StateIngame "enter" — at that
-- point ItemMasterList / SPProfiles / Breeds are populated. The build-version
-- gate inside run_dump() ensures we emit at most once per build.
-- ----------------------------------------------------------------------------
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        if status == "enter" and state_name == "StateIngame"
            and mod:get("gt_auto_name_dump") then
            -- Defer is unnecessary: by StateIngame-enter the data tables are
            -- loaded. run_dump() is internally gated + pcall-isolated.
            M.run_dump(false)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Manual force-dump command. User-invoked, so the reply belongs in chat
-- (PROJECT_STANDARDS.md § 3.6 chat-echo matrix: command bodies are an OK row).
-- ----------------------------------------------------------------------------
mod:command("gt_dump_names", "Force a vanilla loc_key->English name dump to the console log (ignores the build-version gate)", function()
    local ok = M.run_dump(true)
    if ok then
        mod:echo("/gt_dump_names: name dump written to console log (grep '" .. NAME_DUMP_PREFIX .. "').")
    else
        mod:echo("/gt_dump_names: dump did not run -- is a level loaded? (ItemMasterList must be populated). Check the console log.")
    end
end)

mod._gt_name_dump = M
return M
