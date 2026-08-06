-- Engine-free coverage for the appearance-parity comparison core
-- (tools/shared_lib/_lib_appearance_parity.lua), issue 371 / issue 737.
local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function occurrences(haystack, needle)
    local count, position = 0, 1
    while true do
        local first, last = haystack:find(needle, position, true)
        if not first then return count end
        count = count + 1
        position = last + 1
    end
end

return function(H, repo_root)
    local MASTER = repo_root .. "/tools/shared_lib/_lib_appearance_parity.lua"
    local COPY   = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_appearance_parity.lua"
    local P = dofile(MASTER)

    -- A host manifest entry as _gt_lobby_modded_manifest.lua would serialize it.
    local function host(id, version)
        return { id = id, version = version or "version_unavailable",
            mode = "R", workshop_id = "0", display_name = id }
    end

    H.test("matched appearance mods (both wt_dev, same version) report no asymmetry", function()
        local h = { host("wt_dev", "0.12.275-dev"), host("gt", "0.2.245-dev") }
        local l = {
            wt_dev = { enabled = true, version = "0.12.275-dev" },
            gt     = { enabled = true, version = "0.2.245-dev" },
        }
        H.equal(#P.diff(h, l), 0)
    end)

    H.test("issue 737: appearance mod enabled locally, absent on host -> presence_local_only", function()
        -- Host ran wt DISABLED, so it is absent from the (enabled-only) manifest.
        local h = { host("gt", "0.2.245-dev") }
        local l = { wt_dev = { enabled = true, version = "" } }
        local d = P.diff(h, l)
        H.equal(#d, 1)
        H.equal(d[1].kind, "presence_local_only")
        H.equal(d[1].label, "Weapon Tweaker")
        local line = P.format_banner(d[1])
        H.truthy(line:find("Parity warning: Weapon Tweaker", 1, true))
        H.truthy(line:find("host: not present", 1, true))
        H.truthy(line:find("you: enabled", 1, true))
        H.truthy(line:find("modded appearance may desync", 1, true))
    end)

    H.test("appearance mod enabled on host, absent locally -> presence_host_only", function()
        local h = { host("WOC", "") }
        local l = {}
        local d = P.diff(h, l)
        H.equal(#d, 1)
        H.equal(d[1].kind, "presence_host_only")
        H.equal(d[1].label, "Weapons of Chaos")
        H.truthy(P.format_banner(d[1]):find("you: not present", 1, true))
    end)

    H.test("stream split (host wt, you wt_dev) -> version record showing both ids", function()
        local h = { host("wt", "0.12.274-beta") }
        local l = { wt_dev = { enabled = true, version = "0.12.275-dev" } }
        local d = P.diff(h, l)
        H.equal(#d, 1)
        H.equal(d[1].kind, "version")
        H.equal(d[1].show_ids, true)
        local line = P.format_banner(d[1])
        H.truthy(line:find("host: wt 0.12.274-beta", 1, true))
        H.truthy(line:find("you: wt_dev 0.12.275-dev", 1, true))
    end)

    H.test("same id, different version -> version record without ids", function()
        local h = { host("cosmetics_tweaker", "0.9.20") }
        local l = { cosmetics_tweaker = { enabled = true, version = "0.9.21" } }
        local d = P.diff(h, l)
        H.equal(#d, 1)
        H.equal(d[1].kind, "version")
        H.equal(d[1].show_ids, false)
        local line = P.format_banner(d[1])
        H.truthy(line:find("host: 0.9.20", 1, true))
        H.truthy(line:find("you: 0.9.21", 1, true))
    end)

    H.test("unknown versions on both sides never fabricate a version mismatch", function()
        local h = { host("character_weapon_variants", "version_unavailable") }
        local l = { character_weapon_variants = { enabled = true, version = "" } }
        H.equal(#P.diff(h, l), 0)
    end)

    H.test("locally-disabled appearance mod counts as absent", function()
        local h = { host("cim", "") }
        local l = { cim = { enabled = false, version = "" } }
        local d = P.diff(h, l)
        H.equal(#d, 1)
        H.equal(d[1].kind, "presence_host_only")
        H.equal(d[1].label, "Crafting in Modded")
    end)

    H.test("cim vs cim_dev is one family but a flagged stream split", function()
        -- Same family (one label), but host on stable cim and client on cim_dev
        -- are different builds registering into the shared spaces independently -
        -- the dangerous case, so it warns with both ids shown even when versions
        -- are unknown (same handling as the wt / wt_dev split above).
        local h = { host("cim", "") }
        local l = { cim_dev = { enabled = true, version = "" } }
        local d = P.diff(h, l)
        H.equal(#d, 1)
        H.equal(d[1].kind, "version")
        H.equal(d[1].show_ids, true)
        H.equal(d[1].label, "Crafting in Modded")
        local line = P.format_banner(d[1])
        H.truthy(line:find("host: cim (enabled)", 1, true))
        H.truthy(line:find("you: cim_dev (enabled)", 1, true))
    end)

    H.test("non-appearance mods are ignored entirely", function()
        local h = { host("ct", ""), host("enemy_tweaker", ""), host("event_tweaker", "") }
        local l = { crt = { enabled = true, version = "" }, mp = { enabled = true, version = "" } }
        H.equal(#P.diff(h, l), 0)
    end)

    H.test("multiple asymmetric families yield one record each, sorted by family", function()
        local h = { host("cim", "") }  -- host-only
        local l = {
            wt_dev = { enabled = true, version = "" },  -- local-only
            WOC    = { enabled = true, version = "" },  -- local-only
        }
        local d = P.diff(h, l)
        H.equal(#d, 3)
        H.equal(d[1].family, "crafting_in_modded")
        H.equal(d[2].family, "weapon_tweaker")
        H.equal(d[3].family, "weapons_of_chaos")
    end)

    H.test("composition key is stable for identical input and changes on a local toggle", function()
        local h  = { host("wt_dev", "0.12.275-dev") }
        local on  = { wt_dev = { enabled = true,  version = "0.12.275-dev" } }
        local off = { wt_dev = { enabled = false, version = "0.12.275-dev" } }
        H.equal(P.composition_key(h, on), P.composition_key(h, on))
        H.truthy(P.composition_key(h, on) ~= P.composition_key(h, off))
    end)

    H.test("composition key changes when the host's appearance set changes", function()
        local l = { wt_dev = { enabled = true, version = "0.12.275-dev" } }
        local host_matched = { host("wt_dev", "0.12.275-dev") }
        local host_absent  = { host("gt", "0.2.245-dev") }
        H.truthy(P.composition_key(host_matched, l) ~= P.composition_key(host_absent, l))
    end)

    H.test("parse_manifest round-trips the producer wire format", function()
        local text = table.concat({
            "wt_dev\t0.12.275-dev\tR\t3748824853\tTweaker: Weapons",
            "gt\tversion_unavailable\tC\t0\tGeneral Tweaker",
        }, "\n")
        local entries = P.parse_manifest(text)
        H.equal(#entries, 2)
        H.equal(entries[1].id, "wt_dev")
        H.equal(entries[1].version, "0.12.275-dev")
        H.equal(entries[2].id, "gt")
        H.equal(entries[2].version, "version_unavailable")
    end)

    H.test("empty / nil inputs are safe", function()
        H.equal(#P.diff(nil, nil), 0)
        H.equal(#P.diff({}, {}), 0)
        H.equal(#P.parse_manifest(nil), 0)
        H.equal(#P.parse_manifest(""), 0)
    end)

    H.test("gt_dev runtime copy is byte-identical and manifested", function()
        H.equal(read(COPY), read(MASTER),
            "copy drift: re-copy tools/shared_lib/_lib_appearance_parity.lua into general_tweaker_dev")
        local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
        H.truthy(manifest:find(
            '"general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_appearance_parity.lua"',
            1, true), "gt_dev appearance-parity consumer is absent from the shared-library manifest")
    end)

    H.test("gt_dev loads the appearance-parity owner and library exactly once", function()
        local entry = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua")
        local owner = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_lobby_appearance_parity.lua")
        H.equal(occurrences(entry,
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_lobby_appearance_parity")'), 1,
            "gt_dev entry must load the appearance-parity owner exactly once")
        H.equal(occurrences(owner,
            'local PARITY = mod:dofile("scripts/mods/general_tweaker_dev/_lib_appearance_parity")'), 1,
            "appearance-parity owner must load its shared-library copy exactly once")
    end)
end
