-- Boundary test for the #1159 template-patch owner extractions (wt + wt_dev).
--
-- Engine-free. Asserts the load-bearing structural contract of the split
-- across BOTH streams of the mirror pair: bare-dofile wiring at the former
-- execution position for both owners, the load-order facts that make the move
-- behavior-neutral (the NetworkLookup.damage_profiles append order is the wire
-- index, and the template patchers must still run before the rebalance rewrite
-- of the same brace template), the #210 career-scoped remap contract, the #431
-- wire-safe fallback records, hook/command cardinality, and exact public/dev
-- parity of both owners. (#1308 retired the moved-local spelling lists and the
-- whitespace-aligned accessor pins; the load-bearing entry-side absences live
-- in qa/rt_textual_invariants.psd1.)
return function(H, repo_root)
    local STREAMS = {
        {
            tag = "wt",
            dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            entry = "weapon_tweaker.lua",
            ns = "weapon_tweaker",
            mod_id = "wt",
            dev = false,
        },
        {
            tag = "wt_dev",
            dir = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            entry = "weapon_tweaker_dev.lua",
            ns = "weapon_tweaker_dev",
            mod_id = "wt_dev",
            dev = true,
        },
    }

    local OWNERS = {
        templates = "_wt_cross_char_template_patches.lua",
        balance = "_wt_weapon_balance_patches.lua",
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    for _, stream in ipairs(STREAMS) do
        local entry = read(stream.dir .. stream.entry)
        local templates = read(stream.dir .. OWNERS.templates)
        local balance = read(stream.dir .. OWNERS.balance)
        local templates_dofile =
            'mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_cross_char_template_patches")'
        local balance_dofile =
            'mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_weapon_balance_patches")'

        H.test(stream.tag .. ": both owners are bare-dofile'd exactly once", function()
            H.equal(count_plain(entry, templates_dofile), 1)
            H.equal(count_plain(entry, balance_dofile), 1)
            -- Bare dofile, not an installer call. Each module body must run at
            -- file scope exactly where its block used to execute; that position
            -- is what preserves the order of the Weapons.* writes and, for the
            -- rebalance owner, the NetworkLookup append order.
            for _, owner in ipairs({ templates, balance }) do
                H.equal(count_plain(owner, "function M.install"), 0)
                H.equal(count_plain(owner, "return function"), 0)
                H.equal(count_plain(owner, 'local mod = get_mod("' .. stream.mod_id .. '")'), 1)
            end
        end)

        H.test(stream.tag .. ": owners load in the order their writes depend on", function()
            local wield_patches_at =
                entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_anim_remap")', 1, true)
            local templates_at = entry:find(templates_dofile, 1, true)
            local balance_at = entry:find(balance_dofile, 1, true)
            local moonfire_at =
                entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_moonfire_aoe")', 1, true)
            H.truthy(wield_patches_at, "_wt_anim_remap dofile must exist in the entry")
            H.truthy(templates_at, "template-patch owner dofile must exist in the entry")
            H.truthy(balance_at, "rebalance owner dofile must exist in the entry")
            H.truthy(moonfire_at, "moonfire owner dofile must exist in the entry")
            -- _3p_template_remaps is published by the anim-remap module, and the
            -- template owner writes career-scoped rows into it.
            H.truthy(wield_patches_at < templates_at,
                "template-patch owner must load after the anim-remap module publishes the remap table")
            -- Both owners rewrite Weapons.brace_of_pistols_template_1. The
            -- cross-character wield/anim patch ran first before the split and
            -- must still run first after it.
            H.truthy(templates_at < balance_at,
                "template-patch owner must load before the rebalance owner")
            -- The rebalance clones append to NetworkLookup.damage_profiles ahead
            -- of the moonfire owner's explosion_templates append; keeping the
            -- relative order keeps every registration index stable.
            H.truthy(balance_at < moonfire_at,
                "rebalance owner must load before the moonfire owner")
        end)

        -- #1308: the exhaustive moved-file-scope-local lists and the
        -- whitespace-aligned chunk-boundary accessor pins were retired as
        -- spelling pins. The two entry-side absences that are load-bearing
        -- (a re-declared damage-profile clone or template patcher would append
        -- a duplicate NetworkLookup index / re-run outside the owner) are
        -- locked by qa/rt_textual_invariants.psd1 (#431/#1159 rows).

        H.test(stream.tag .. ": #210 remaps stay career-scoped, never global mutation", function()
            -- The Empire and elf longbow crossbow remaps must register in the
            -- runtime funnel under a career prefix, with the native prefix
            -- explicitly opted out. Mutating the shared template for every
            -- career is exactly what broke Kruber's native draw_bow (#210).
            -- Lua patterns, not exact strings: the invariant is which keys are
            -- written, never the alignment whitespace around the equals sign.
            for _, pattern in ipairs({
                "_3p_template_remaps%.longbow_empire_template%.wh_%s*=%s*_SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P",
                "_3p_template_remaps%.longbow_empire_template%.es_mercenary%s*=%s*false",
                "_3p_template_remaps%.longbow_template_1%.we_%s*=%s*false",
                "_3p_template_remaps%.we_deus_01_template_1%.we_%s*=%s*false",
            }) do
                H.truthy(templates:find(pattern), pattern .. " must live in the owner")
                H.equal(entry:find(pattern), nil, pattern .. " must not remain in the entry")
            end
            -- 3P-only discipline: the owner writes career-keyed 3P wield fields
            -- and never a 1P field.
            H.equal(count_plain(templates, "tpl.wield_anim_career_3p") > 0, true)
            H.equal(count_plain(templates, "tpl.wield_anim_not_loaded_career") > 0, true)
            H.equal(count_plain(templates, "tpl.wield_anim_no_ammo_career") > 0, true)
            H.equal(count_plain(templates, "tpl.anim_event ="), 0)
            H.equal(count_plain(templates, "tpl.wield_anim ="), 0)
            H.equal(count_plain(templates, "tpl.state_machine"), 0)
        end)

        H.test(stream.tag .. ": #431 wire contract travelled with both clones", function()
            -- Both custom damage profiles append forward AND reverse into
            -- NetworkLookup.damage_profiles, unconditionally at load, and record
            -- their vanilla clone source as the send-floor fallback.
            H.equal(count_plain(balance, "rawset(tbl, idx, key)"), 1)
            H.equal(count_plain(balance, "rawset(tbl, key, idx)"), 1)
            H.equal(count_plain(balance, "rawset(tbl, idx, PRIEST_PUNCH_PROFILE)"), 1)
            H.equal(count_plain(balance, "rawset(tbl, PRIEST_PUNCH_PROFILE, idx)"), 1)
            H.equal(count_plain(balance,
                'mod._wt431_custom_profile_fallback[key] = "shot_sniper"'), 1)
            H.equal(count_plain(balance,
                "mod._wt431_custom_profile_fallback[PRIEST_PUNCH_PROFILE] = PRIEST_PUNCH_SRC"), 1)
            -- Registration is ungated; only the repoint is toggle-gated. The
            -- unconditional call sits outside the `if mod:get(...)` guard.
            H.equal(count_plain(balance, "if not _wt_clone_shot_sniper_no_dropoff() then"), 1)
            H.equal(count_plain(balance, "if not _register_priest_punch_profile() then"), 1)
            -- The two functions the parity module and the entry call by name
            -- stay published on `mod`, not turned into module locals.
            H.equal(count_plain(balance, "mod._wt431_brace_repoint = function()"), 1)
            H.equal(count_plain(balance, "mod.wt_apply_priest_punch_buff = function()"), 1)
            H.equal(count_plain(entry, "mod._wt431_brace_repoint = function()"), 0)
            H.equal(count_plain(entry, "mod.wt_apply_priest_punch_buff = function()"), 0)
            -- The entry still dispatches the punch buff from the rework runtime.
            H.equal(count_plain(entry,
                "if mod.wt_apply_priest_punch_buff then mod.wt_apply_priest_punch_buff() end"), 1)
        end)

        H.test(stream.tag .. ": neither owner registers a hook or a command", function()
            -- Cardinality proof for the move: the two blocks were hook-free and
            -- command-free before, so the owners must stay that way. A hook added
            -- here would be a second registration on a pair the entry already
            -- owns, which VMF silently drops.
            for _, owner in ipairs({ templates, balance }) do
                H.equal(count_plain(owner, "mod:hook("), 0)
                H.equal(count_plain(owner, "mod:hook_safe("), 0)
                H.equal(count_plain(owner, "mod:safe_hook"), 0)
                H.equal(count_plain(owner, "mod:traced_hook"), 0)
                H.equal(count_plain(owner, "mod:command("), 0)
            end
        end)
    end

    H.test("dev keeps bounded #316 probe edges while both streams share the gameplay owner", function()
        local dev_entry = read(STREAMS[2].dir .. STREAMS[2].entry)
        local public_entry = read(STREAMS[1].dir .. STREAMS[1].entry)
        -- The start/finish probe overlay stays in the dev entry. Its post-update
        -- observation is passed into the byte-shared gameplay owner so that
        -- VMF still sees only one registration on that method.
        H.equal(count_plain(dev_entry, "-- WT_DEV_OVERLAY_BEGIN:longbow-live-probe-hooks"), 1)
        H.equal(count_plain(dev_entry, "-- WT_DEV_OVERLAY_END:longbow-live-probe-hooks"), 1)
        -- Start/finish remain diagnostic-only. The post-update pair moved to
        -- the shared owner so VMF still sees exactly one registration there.
        H.equal(count_plain(dev_entry, 'mod:hook_safe("ActionAim"'), 2)
        H.equal(count_plain(public_entry, "longbow-live-probe-hooks"), 0)
        H.equal(count_plain(public_entry, 'mod:hook_safe("ActionAim"'), 0)
        local dev_templates = read(STREAMS[2].dir .. OWNERS.templates)
        local public_templates = read(STREAMS[1].dir .. OWNERS.templates)
        H.equal(count_plain(dev_templates,
            '"scripts/mods/weapon_tweaker_dev/_wt_longbow_variable_zoom").install(mod, Weapons)'), 1)
        H.equal(count_plain(public_templates,
            '"scripts/mods/weapon_tweaker/_wt_longbow_variable_zoom").install(mod, Weapons)'), 1)
        local dev_zoom = read(STREAMS[2].dir .. "_wt_longbow_variable_zoom.lua")
        local public_zoom = read(STREAMS[1].dir .. "_wt_longbow_variable_zoom.lua")
        H.equal(count_plain(dev_zoom, 'mod:hook_safe("ActionAim", "client_owner_post_update"'), 1)
        H.equal(count_plain(public_zoom, 'mod:hook_safe("ActionAim", "client_owner_post_update"'), 1)
        for _, owner in ipairs({ OWNERS.templates, OWNERS.balance }) do
            -- Prose about ActionAim rode along inside a #316 provenance comment;
            -- what must never appear here is a registration or a probe print.
            H.equal(count_plain(read(STREAMS[2].dir .. owner), 'mod:hook_safe("ActionAim"'), 0,
                owner .. " must not register the dev probe")
            H.equal(count_plain(read(STREAMS[2].dir .. owner), "[wt:316]"), 0,
                owner .. " must not carry the dev probe telemetry")
        end
        -- The probe still registers after the template patches it observes.
        local dofile_at =
            dev_entry:find('mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_cross_char_template_patches")', 1, true)
        local probe_at = dev_entry:find("-- WT_DEV_OVERLAY_BEGIN:longbow-live-probe-hooks", 1, true)
        H.truthy(dofile_at and probe_at)
        H.truthy(dofile_at < probe_at, "probe must arm after the template patches are applied")
    end)

    H.test("public and dev owners are identical after stream normalization", function()
        for _, owner in ipairs({ OWNERS.templates, OWNERS.balance }) do
            local public_owner = read(STREAMS[1].dir .. owner)
            local dev_owner = read(STREAMS[2].dir .. owner)
            local normalized = dev_owner
                :gsub('get_mod%("wt_dev"%)', 'get_mod("wt")')
                :gsub("scripts/mods/weapon_tweaker_dev/", "scripts/mods/weapon_tweaker/")
            H.equal(normalized, public_owner, owner .. " must be stream-identical")
        end
    end)
end
