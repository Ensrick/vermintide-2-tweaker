-- _gut_native_loadout_commands.lua -- native-loadout status and official repair commands.
--
-- Installs the existing ordered commands with private callbacks from the durable native
-- owner. Realm/backend reads remain command-time reads; this module owns no store,
-- writer, hook, lifecycle callback or persistence settings.
--
-- Owned by: _gut_native_loadouts.lua. Consumed via: one private mod:dofile/install.
local Commands = {}

function Commands.install(mod, deps)
    assert(type(mod) == "table" and type(mod.command) == "function", "command registrar required")
    assert(type(deps) == "table", "native command dependencies required")
    local _adventure_mode = assert(type(deps.adventure_mode) == "function" and deps.adventure_mode, "adventure_mode function required")
    local _in_modded_realm = assert(type(deps.in_modded_realm) == "function" and deps.in_modded_realm, "in_modded_realm function required")
    local _store = assert(type(deps.store) == "function" and deps.store, "store function required")
    local _resolve_item_raw = assert(type(deps.resolve_item_raw) == "function" and deps.resolve_item_raw, "resolve_item_raw function required")
    local BackendCommit = assert(type(deps.backend_commit) == "table" and deps.backend_commit, "backend_commit table required")
    local COSMETIC_SLOT_SET = assert(type(deps.cosmetic_slot_set) == "table" and deps.cosmetic_slot_set, "cosmetic_slot_set table required")
    local WEAPON_SLOT_SET = assert(type(deps.weapon_slot_set) == "table" and deps.weapon_slot_set, "weapon_slot_set table required")
    local LOADOUT_SLOT_NAMES = assert(type(deps.loadout_slot_names) == "table" and deps.loadout_slot_names, "loadout_slot_names table required")
    local GEAR_SLOT_NAMES = assert(type(deps.gear_slot_names) == "table" and deps.gear_slot_names, "gear_slot_names table required")
    local MODE_OFF = assert(type(deps.mode_off) == "string" and deps.mode_off, "mode_off string required")
    local RESOLVE_YES = assert(type(deps.resolve_yes) == "number" and deps.resolve_yes, "resolve_yes number required")
    local RESOLVE_NO = assert(type(deps.resolve_no) == "number" and deps.resolve_no, "resolve_no number required")

    -- ==================================================================
    -- /gut_loadout_status (issue #375 diagnostics) -- echo the modded loadout store state
    -- to CHAT (visible with mod-logging off) plus a per-row slot dump to the console log, so
    -- "is the loadout system even working" is answerable at a glance: mode, realm, and for
    -- each career whether it seeded, how many loadout rows exist, the selected index, and
    -- (console) which gear/cosmetic slots each row actually holds.
    -- ==================================================================
    -- issue #387 presentation-side resolution probe. SAFE to call get_item_from_id here because
    -- this runs in a chat-command context, NOT inside a mirror read hook (the v0.2.173 recursion
    -- was get_item_from_id called from within the get_character_data hook). Returns the resolved
    -- item key (or nil) so a dangling/unresolvable weapon id -- the id that leaves a slot stuck on
    -- the previous weapon at switch time -- is visible per row.
    local function _probe_resolve(id)
        if id == nil then return nil end
        local ok, key = pcall(function()
            local iface = Managers.backend:get_interface("items")
            local item = iface and iface:get_item_from_id(id)
            return item and item.data and (item.data.key or item.data.name)
        end)
        return ok and key or nil
    end

    local function _slot_resolves(slot_name, id)
        if id == nil then return false end
        if _probe_resolve(id) ~= nil then return true end
        if COSMETIC_SLOT_SET[slot_name] and rawget(_G, "ItemMasterList") and rawget(ItemMasterList, id) then
            return true
        end
        return false
    end

    mod:command("gut_loadout_status", "Show the modded loadout store state + resolve gear ids (issue #375/#387)", function(career_arg)
        local mode = _adventure_mode()
        mod:echo(string.format("[loadouts] realm_modded=%s mode=%s", tostring(_in_modded_realm()), tostring(mode)))
        if mode == MODE_OFF then
            mod:echo("  feature INERT here (official realm / Versus / not in a backend view) -- store is not consulted")
        end
        local filter = (career_arg and career_arg ~= "") and career_arg or nil
        local store = _store()
        local any = false
        for career_name, entry in pairs(store) do
            if not filter or career_name == filter then
                any = true
                local rows = entry.loadouts or {}
                -- Count unresolvable WEAPON ids across rows (the #387 stuck-weapon signature).
                local weapon_fail = 0
                local slot_integrity_fail = 0
                for i = 1, #rows do
                    local row = rows[i]
                    for _, slot in ipairs(LOADOUT_SLOT_NAMES) do
                        local id = row and row[slot]
                        if id == nil or not _slot_resolves(slot, id) then
                            slot_integrity_fail = slot_integrity_fail + 1
                        end
                    end
                    for slot in pairs(WEAPON_SLOT_SET) do
                        local id = row and row[slot]
                        if id ~= nil and _probe_resolve(id) == nil then weapon_fail = weapon_fail + 1 end
                    end
                end
                mod:echo(string.format("  %s: seeded=%s slots_v2=%s loadouts=%d selected=%s bot=%s weapon_ids_unresolvable=%d slot_integrity_failures=%d",
                    tostring(career_name), tostring(entry._seeded and true or false), tostring(entry._slot_integrity_v2 and true or false),
                    #rows, tostring(entry.selected_index), tostring(entry.bot_index), weapon_fail, slot_integrity_fail))
                for i = 1, #rows do
                    local row = rows[i]
                    local filled = {}
                    local missing = {}
                    for _, s in ipairs(LOADOUT_SLOT_NAMES) do
                        if row and row[s] ~= nil then filled[#filled + 1] = s
                        else missing[#missing + 1] = s end
                    end
                    printf("[gut:NATIVE_LOADOUTS] status career=%s row=%d selected=%s slots=[%s] missing=[%s] talents=%s",
                        tostring(career_name), i, tostring(i == entry.selected_index),
                        table.concat(filled, ","), table.concat(missing, ","), tostring(row and row.talents))
                    -- issue #387: resolve each GEAR slot id both ways -- raw registry (what the
                    -- get_character_data fallback consults) AND get_item_from_id (what the hero-view
                    -- presentation consults). A slot with raw=UNKNOWN/YES but get_item_from_id=FAIL is
                    -- exactly the stuck-weapon case: served from the store, unpresentable at switch.
                    if row then
                        for _, s in ipairs(GEAR_SLOT_NAMES) do
                            local id = row[s]
                            if id ~= nil then
                                local raw = _resolve_item_raw(id)
                                local rawname = (raw == RESOLVE_YES and "raw=YES") or (raw == RESOLVE_NO and "raw=NO") or "raw=UNKNOWN"
                                local key = _probe_resolve(id)
                                printf("[gut:NATIVE_LOADOUTS] status-resolve career=%s row=%d %s id=%s %s get_item_from_id=%s",
                                    tostring(career_name), i, s, tostring(id), rawname, tostring(key or "<FAIL>"))
                            end
                        end
                    end
                end
            end
        end
        if not any then
            if filter then mod:echo("  no store entry for '" .. filter .. "'")
            else mod:echo("  store EMPTY -- open a modded hero view (and switch a loadout slot) to seed from official") end
        end
    end)

    -- ==================================================================
    -- /scrub_official_loadouts (issue #402) -- OFFICIAL-realm repair for the pre-isolation #174
    -- bleed: modded/dangling native loadout ids committed to the OFFICIAL cloud loadouts
    -- BEFORE the modded-realm isolation (this file) existed. Audit 2026-07-06 (decompiled source):
    -- every runtime write that diverges official _career_data from its mirror (and so reaches the
    -- PlayFab cloud) funnels through PlayFabMirrorBase.set_character_data -- it writes _career_data
    -- at :1933 BEFORE delegating to set_career_read_only_data at :1941, so it is the SOLE choke
    -- point, and weapons, cosmetics, accessories, frame, and pose all persist through the same
    -- row-slot path. We hook it and no-op it in modded, so NO new leak is possible. But rows
    -- already corrupted by the pre-isolation bleed never self-heal -- this repairs them.
    --
    -- REPORT (default, read-only, safe anywhere): list every official loadout slot in
    --   LOADOUT_SLOT_NAMES whose stored id is missing or does NOT resolve by the slot-appropriate
    --   policy (backend item, or for cosmetics a known ItemMasterList key).
    -- APPLY (`/scrub_official_loadouts apply`): replace each broken slot's id with a resolvable id
    --   the player ALREADY OWNS for that same slot (taken from another of their official loadout
    --   rows). It writes ONLY a value it has verified resolves, into a slot that is CURRENTLY broken,
    --   so it can never break a working slot; if no owned replacement resolves it reports and skips
    --   (re-equip that slot manually). HARD-GATED to the OFFICIAL realm: in modded, set_character_data
    --   is captured to the store, so the official write would never land -- refuse and say so.
    -- ==================================================================
    mod:command("scrub_official_loadouts", "Repair modded/dangling OFFICIAL loadout slot ids (issue #402; add 'apply' to write, default report-only)", function(arg)
        local do_apply = (arg == "apply")
        if do_apply and _in_modded_realm() then
            mod:echo("[scrub] REFUSED -- you are in the MODDED realm; an official write is captured to the modded store here.")
            mod:echo("[scrub] Enter the OFFICIAL (EAC-trusted) realm, open the hero view, then run: /scrub_official_loadouts apply")
            return
        end
        local ok_m, mirror = pcall(function() return Managers.backend:get_interface("items")._backend_mirror end)
        if not ok_m or not mirror or type(mirror._career_data) ~= "table" then
            mod:echo("[scrub] backend not ready -- open the hero view first, then re-run")
            return
        end
        -- A replacement must itself resolve; only ever an id the player already owns for this slot.
        local function _owned_replacement(slot, rows)
            for i = 1, #rows do
                local id = rows[i] and rows[i][slot]
                if _slot_resolves(slot, id) then return id end
            end
            return nil
        end
        mod:echo(string.format("[scrub] official loadout audit (%s)%s",
            do_apply and "APPLY" or "report-only", _in_modded_realm() and " [WARN: modded realm -- report only]" or ""))
        local broken, fixed, skipped = 0, 0, 0
        for career_name, rows in pairs(mirror._career_data) do
            if type(rows) == "table" then
                for i = 1, #rows do
                    local row = rows[i]
                    if type(row) == "table" then
                        for _, slot in ipairs(LOADOUT_SLOT_NAMES) do
                            local id = row[slot]
                            if not _slot_resolves(slot, id) then
                                broken = broken + 1
                                printf("[gut:NATIVE_LOADOUTS] #402 official BROKEN career=%s row=%d slot=%s id=%s",
                                    tostring(career_name), i, slot, tostring(id))
                                if do_apply then
                                    local repl = _owned_replacement(slot, rows)
                                    if repl ~= nil then
                                        local ok_w = pcall(function() mirror:set_character_data(career_name, slot, repl, nil, i) end)
                                        if ok_w then
                                            fixed = fixed + 1
                                            printf("[gut:NATIVE_LOADOUTS] #402 official REPAIRED career=%s row=%d slot=%s -> %s",
                                                tostring(career_name), i, slot, tostring(repl))
                                        else
                                            skipped = skipped + 1
                                        end
                                    else
                                        skipped = skipped + 1
                                        printf("[gut:NATIVE_LOADOUTS] #402 official NO-OWNED-REPLACEMENT career=%s row=%d slot=%s (re-equip this slot manually)",
                                            tostring(career_name), i, slot)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if broken == 0 then
            mod:echo("[scrub] official loadouts clean -- no broken native loadout slots")
        elseif do_apply then
            local skipped_suffix = skipped > 0 and string.format(" (%d skipped -- re-equip manually)", skipped) or ""
            if fixed == 0 then
                mod:echo(string.format("[scrub] repaired 0/%d broken slot(s)%s; no cloud commit was requested",
                    broken, skipped_suffix))
                return
            end

            local function commit_complete(status)
                local committed, detail = BackendCommit.classify_status(status)
                if committed then
                    mod:echo(string.format("[scrub] cloud commit complete -- repaired %d/%d broken slot(s)%s",
                        fixed, broken, skipped_suffix))
                    printf("[gut:NATIVE_LOADOUTS] #402 cloud commit SUCCESS fixed=%d broken=%d skipped=%d status=%s",
                        fixed, broken, skipped, tostring(status))
                else
                    mod:echo(string.format("[scrub] repair is local but cloud commit FAILED (%s); retry /scrub_official_loadouts apply",
                        detail))
                    printf("[gut:NATIVE_LOADOUTS] #402 cloud commit FAILED fixed=%d broken=%d skipped=%d status=%s",
                        fixed, broken, skipped, detail)
                end
            end

            local requested, commit_id = BackendCommit.request(Managers and Managers.backend, commit_complete)
            if requested then
                mod:echo(string.format("[scrub] repaired %d/%d broken slot(s)%s; cloud commit requested (id=%s)",
                    fixed, broken, skipped_suffix, tostring(commit_id)))
                printf("[gut:NATIVE_LOADOUTS] #402 cloud commit REQUESTED id=%s fixed=%d broken=%d skipped=%d",
                    tostring(commit_id), fixed, broken, skipped)
            else
                mod:echo(string.format("[scrub] repaired %d/%d locally%s, but cloud commit could not start (%s)",
                    fixed, broken, skipped_suffix, tostring(commit_id)))
                printf("[gut:NATIVE_LOADOUTS] #402 cloud commit NOT-STARTED fixed=%d broken=%d skipped=%d reason=%s",
                    fixed, broken, skipped, tostring(commit_id))
            end
        else
            mod:echo(string.format("[scrub] found %d broken slot(s) -- see console for ids. To fix: enter the OFFICIAL realm and run /scrub_official_loadouts apply", broken))
        end
    end)

    return { slot_resolves = _slot_resolves }
end

return Commands
