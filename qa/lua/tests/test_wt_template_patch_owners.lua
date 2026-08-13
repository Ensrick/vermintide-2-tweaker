-- Boundary test for the #1159 template-patch owner extractions (wt + wt_dev).
--
-- Engine-free. Asserts the structural contract of the split across BOTH streams
-- of the mirror pair: bare-dofile wiring at the former execution position for
-- both owners, the load-order facts that make the move behavior-neutral (the
-- NetworkLookup.damage_profiles append order is the wire index, and the
-- template patchers must still run before the rebalance rewrite of the same
-- brace template), entry-side absence of every moved file-scope local, the
-- accessor idioms the chunk boundary needs, the #210 career-scoped remap
-- contract, the #431 wire-safe fallback records, and exact public/dev parity of
-- both owners.
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

        H.test(stream.tag .. ": moved file-scope locals left the entry (template owner)", function()
            for _, decl in ipairs({
                "local _BRACE_REPEATER_BASE_WIELD_3P",
                "local _BRACE_REPEATER_ANIM_REMAP_3P",
                "local function _patch_brace_template_for_kruber",
                "local _SP_LONGBOW_CROSSBOW_WIELD_3P",
                "local _SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P",
                "local function _patch_longbow_empire_template_for_saltzpyre",
                "local _WE_LONGBOW_CROSSBOW_WIELD_3P",
                "local function _patch_longbow_template_1_for_saltzpyre",
                "local _WE_MOONFIRE_CROSSBOW_ANIM_REMAP_3P",
                "local function _patch_moonfire_template_1_for_saltzpyre",
                "local _WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P",
                "local function _patch_repeating_pistol_template_1_for_kruber",
                "local _WIELD_PATCHES_MODULE",
                "local _WIELD_ANIM_CAREER_3P_PATCHES",
                "local function _apply_wield_anim_career_3p_patches",
                "local _KRUBER_REPEATER_CAREERS",
                "local _WH_REPEATER_CAREERS",
                "local _NOT_LOADED_NO_AMMO_CAREER_PATCHES",
                "local function _apply_not_loaded_no_ammo_career_patches",
            }) do
                H.equal(count_plain(templates, decl) > 0, true,
                    decl .. " must be declared in the template owner")
                H.equal(count_plain(entry, decl), 0, decl .. " must not remain in the entry")
            end
        end)

        H.test(stream.tag .. ": moved file-scope locals left the entry (rebalance owner)", function()
            for _, decl in ipairs({
                "local function _wt_clone_shot_sniper_no_dropoff",
                "local _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT",
                "local _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT",
                "local function _wt_scale_spread",
                "local function _wt_clone_spread_wider",
                "local function _wt_clone_brace_spread_wider",
                "local function _wt_clone_pistol_special_spread_wider",
                "local function _apply_authentic_brace_mode",
                "local function _patch_kruber_1h_sword_push_combo_revert",
            }) do
                H.equal(count_plain(balance, decl), 1,
                    decl .. " must be declared once in the rebalance owner")
                H.equal(count_plain(entry, decl), 0, decl .. " must not remain in the entry")
            end
            -- The three toggle reads are the owner's only settings dependency.
            for _, toggle in ipairs({
                'mod:get("authentic_brace_of_pistols")',
                'mod:get("wt_revert_1h_sword_push_combo")',
                'mod:get("wt_priest_punch_buff")',
            }) do
                H.equal(count_plain(balance, toggle), 1, toggle .. " must live in the owner")
                H.equal(count_plain(entry, toggle), 0, toggle .. " must not remain in the entry")
            end
        end)

        H.test(stream.tag .. ": chunk-boundary accessors are the published values", function()
            -- The moved lines closed over the entry's file-scope helpers. Each
            -- owner must re-read the SAME published function/table, never invent
            -- a private one.
            H.equal(count_plain(templates, "local _dbg                = mod._wt.dbg"), 1)
            H.equal(count_plain(templates, "local _dbg_alert          = mod._wt.dbg_alert"), 1)
            H.equal(count_plain(templates,
                "local _3p_template_remaps = mod._wt.three_p_template_remaps"), 1)
            H.equal(count_plain(balance, "local _dbg = mod._wt.dbg"), 1)
            -- ...and the entry must actually publish dbg_alert, which it did not
            -- need to before this split.
            H.equal(count_plain(entry, "mod._wt.dbg_alert         = _dbg_alert"), 1)
            H.equal(count_plain(entry, "local function _dbg_alert("), 1)
            -- The runtime-check dependency table used to read two entry locals
            -- that now live in the owner; it must read them off the namespace.
            H.equal(count_plain(templates,
                "mod._wt.wield_patches_module      = _WIELD_PATCHES_MODULE"), 1)
            H.equal(count_plain(templates,
                "mod._wt.wield_anim_career_patches = _WIELD_ANIM_CAREER_3P_PATCHES"), 1)
            H.equal(count_plain(entry,
                "    wield_patches_module = mod._wt.wield_patches_module,"), 1)
            H.equal(count_plain(entry,
                "    wield_anim_career_patches = mod._wt.wield_anim_career_patches,"), 1)
        end)

        H.test(stream.tag .. ": #210 remaps stay career-scoped, never global mutation", function()
            -- The Empire and elf longbow crossbow remaps must register in the
            -- runtime funnel under a career prefix, with the native prefix
            -- explicitly opted out. Mutating the shared template for every
            -- career is exactly what broke Kruber's native draw_bow (#210).
            for _, needle in ipairs({
                "_3p_template_remaps.longbow_empire_template.wh_               = "
                    .. "_SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P",
                "_3p_template_remaps.longbow_empire_template.es_mercenary      = false",
                "_3p_template_remaps.longbow_template_1.we_ = false",
                "_3p_template_remaps.we_deus_01_template_1.we_ = false",
            }) do
                H.equal(count_plain(templates, needle), 1, needle .. " must live in the owner")
                H.equal(count_plain(entry, needle), 0, needle .. " must not remain in the entry")
            end
            -- 3P-only discipline: the owner writes career-keyed 3P wield fields
            -- and never a 1P field.
            H.equal(count_plain(templates, "tpl.wield_anim_career_3p") > 0, true)
            -- Two mentions on the lazy-init line plus the per-career write.
            H.equal(count_plain(templates, "tpl.wield_anim_not_loaded_career"), 3)
            H.equal(count_plain(templates, "tpl.wield_anim_no_ammo_career"), 3)
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
