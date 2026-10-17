-- #1682 weapon-history source anchor coherence (Game Version 6.13.0).
--
-- Upstream Aussiemon/Vermintide-2-Source-Code moved to 6.13.0, so the
-- canonical anchor, every generated catalog and ledger in both Weapon Tweaker
-- streams, and every provenance input that embeds the current revision must
-- move together. A partial re-anchor disables the whole history runtime
-- (_wt_history_catalog.lua refuses mismatched current_source identities), so
-- this suite fails on any file still carrying a retired anchor.

local ANCHOR_REVISION = "93dea911a4cc464a0eb51cfdc3a443297bfc4550"
local ANCHOR_GAME_VERSION = "6.13.0"
local RETIRED_REVISIONS = {
    "038498af2b565bcb10bf5ed225638293a7640c83", -- 6.12.0
    "25fd7b8433e839b678d1c98a7a9af80918cbc252", -- 6.12.1 (#1529)
}
local CATALOG_STEMS = {
    "2_0_6", "2_0_9_1", "2_0_10", "3_1", "3_2", "4_1_1", "4_6",
    "5_2", "6_0", "6_6", "6_8", "6_11_0", "6_11_2",
}
local PATCH_5_2_EVIDENCE = {
    "_wt_history_profiles_5_1_1_dlc_generated",
    "_wt_history_profiles_5_1_1_generated",
    "_wt_history_profiles_5_2_0_dlc_generated",
    "_wt_history_profiles_5_2_0_generated",
    "_wt_history_snapshot_5_1_1_part_1_generated",
    "_wt_history_snapshot_5_1_1_part_2_generated",
    "_wt_history_snapshot_5_2_0_part_1_generated",
    "_wt_history_snapshot_5_2_0_part_2_generated",
    "_wt_history_snapshot_5_2_3_generated",
}
local STREAMS = {
    "weapon_tweaker/scripts/mods/weapon_tweaker/",
    "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
}

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function plain_find(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

local function register(H, repo_root)
    local tool_root = repo_root .. "/tools/weapon-history/"

    local function anchor()
        return assert(loadfile(tool_root .. "current_source_anchor.lua"))()
    end

    -- Every tracked provenance input that embeds the current revision.
    local function provenance_inputs()
        local paths = {}
        for _, stem in ipairs(CATALOG_STEMS) do
            paths[#paths + 1] = tool_root .. "evidence/patch_" .. stem
                .. "/_wt_history_" .. stem .. "_source_catalog.lua"
        end
        for _, name in ipairs(PATCH_5_2_EVIDENCE) do
            paths[#paths + 1] = tool_root .. "evidence/patch_5_2/" .. name .. ".lua"
        end
        paths[#paths + 1] = tool_root
            .. "evidence/patch_2_0_10/_wt_history_2_0_10_routes_oracle.lua"
        paths[#paths + 1] = tool_root
            .. "evidence/patch_4_6/_wt_history_4_6_routes_oracle.lua"
        paths[#paths + 1] = tool_root .. "source_oracle/patch_2_0_10_source_spec.lua"
        paths[#paths + 1] = tool_root .. "source_oracle/patch_4_6_source_spec.lua"
        paths[#paths + 1] = tool_root .. "source_oracle/patch_5_2_source_spec.lua"
        paths[#paths + 1] = tool_root .. "source_oracle/patch_5_2_routes_oracle.lua"
        return paths
    end

    H.test("WT #1682 canonical anchor is the 6.13.0 same-commit tip", function()
        local a = anchor()
        H.equal(a.schema, 2)
        H.equal(a.canonical_url, "https://github.com/Aussiemon/Vermintide-2-Source-Code")
        H.equal(a.default_ref, "refs/heads/master")
        H.equal(a.content_revision, ANCHOR_REVISION)
        H.equal(a.observed_default_tip, ANCHOR_REVISION)
        H.equal(a.observed_tip_content_relation, "same_commit")
        H.equal(#a.observed_tip_metadata_paths, 0)
        H.equal(a.game_version, ANCHOR_GAME_VERSION)
    end)

    H.test("WT #1682 every catalog and ledger in both streams carries the anchor", function()
        local a = anchor()
        local display = "Current (Game Version " .. a.game_version .. ")"
        local label = a.game_version .. " source anchor"
        for _, stream in ipairs(STREAMS) do
            for _, stem in ipairs(CATALOG_STEMS) do
                local path = repo_root .. "/" .. stream .. "_wt_history_" .. stem .. "_catalog.lua"
                local catalog = assert(loadfile(path))()
                H.equal(catalog.current_source.revision, a.content_revision, path)
                H.equal(catalog.current_source.display_name, display, path)
                H.equal(catalog.current_source.label, label, path)
            end
            local ledger_path = repo_root .. "/" .. stream .. "_wt_history_completeness_ledger.lua"
            local ledger = assert(loadfile(ledger_path))()
            H.equal(ledger.current_revision, a.content_revision, ledger_path)
        end
    end)

    H.test("WT #1682 rehydrated Patch 5.2 evidence projects onto the anchor", function()
        local short = anchor().content_revision:sub(1, 8)
        for _, name in ipairs(PATCH_5_2_EVIDENCE) do
            local path = tool_root .. "evidence/patch_5_2/" .. name .. ".lua"
            local evidence = assert(loadfile(path))()
            H.equal(evidence.new_revision, short, path)
        end
    end)

    H.test("WT #1682 no provenance input or catalog keeps a retired anchor", function()
        local a = anchor()
        local paths = provenance_inputs()
        for _, stream in ipairs(STREAMS) do
            for _, stem in ipairs(CATALOG_STEMS) do
                paths[#paths + 1] = repo_root .. "/" .. stream
                    .. "_wt_history_" .. stem .. "_catalog.lua"
            end
            paths[#paths + 1] = repo_root .. "/" .. stream
                .. "_wt_history_completeness_ledger.lua"
        end
        local short = a.content_revision:sub(1, 8)
        for _, path in ipairs(paths) do
            local text = read_file(path)
            for _, retired in ipairs(RETIRED_REVISIONS) do
                H.truthy(not plain_find(text, retired:sub(1, 8)),
                    "retired anchor " .. retired:sub(1, 8) .. " in " .. path)
            end
            H.truthy(plain_find(text, short),
                "current anchor missing from " .. path)
        end
    end)
end

return register
