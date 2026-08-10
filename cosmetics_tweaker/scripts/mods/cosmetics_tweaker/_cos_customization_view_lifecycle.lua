-- _cos_customization_view_lifecycle.lua - HeroWindowItemCustomization view lifecycle owner.
--
-- RESPONSIBILITY
-- Owns the two ENDS of a weapon-illusion customization screen visit, and nothing
-- in between:
--
--   * MOUNT (#228 / #235) - the in-mission preview shading-environment guard.
--     gut's and cim's mission-safe widget definitions strip level_name and set
--     environment/ui_hdr, which defines no per-weapon blend variation, so vanilla
--     _present_item -> _update_environment drove a native ShadingEnvironment.blend
--     access violation. This owner re-points the preview world to the resident,
--     studio-lit environment/ui_store_preview and then lets vanilla's variation
--     through; when the re-point cannot happen it pins the blend target to
--     "default" (AV-safe, unlit). The keep path stays a pure pass-through.
--
--   * EXIT - the screen-visit teardown. Clears the active customization identity,
--     closes the glow picker, runs the #200 offhand apply-gate revert when the
--     user left without a genuine Apply, drains the single deferred LA offhand
--     emit, pulse-wields the local body so the committed mesh respawns, and
--     clears the per-backend-id apply-gate state.
--
-- Extracted VERBATIM from cosmetics_tweaker.lua (entry lines 689-1077 at
-- 820457d1) with no behaviour change. Only three statements differ from the
-- original text, all of them the accessor hand-offs described under ENTRY-OWNED
-- STATE below. mod:dofile is not a singleton - the entry calls this installer
-- EXACTLY once, at the exact point the block previously executed, so hook
-- registration order and the load-time log ordering keep their original timing.
-- There is deliberately no re-install guard: a second install would register
-- duplicate hooks that VMF silently drops, which is precisely what a second
-- dofile of the old inline block did.
--
-- HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
-- second hook on the same Class/method pair):
--   HeroWindowItemCustomization._create_preview_widget  (hook_safe)
--   HeroWindowItemCustomization._update_environment     (full hook)
--   HeroWindowItemCustomization.on_exit                 (hook_safe)
--
-- ENTRY-OWNED STATE reached through accessors, never captured by value
--   deps.get_send_la_apply()
--     `_send_la_apply` is FORWARD-DECLARED near the top of the entry and only
--     assigned ~2400 lines later, inside the cos_la_apply block. The inline
--     version of this code worked because it captured the entry's local SLOT and
--     read it at hook-fire time. A by-value hand-off at install time would pass
--     nil and silently kill the deferred-emit drain, so the sender is fetched at
--     call time instead.
--   deps.get_active_customization_backend_id() / set_active_customization_backend_id(v)
--     The customized weapon's backend id is a MUTABLE entry local written from
--     two places: the offhand picker's setter and this owner's on_exit clear.
--     Ownership stays in the entry so both writers keep addressing one slot; this
--     module reads and clears it through the same accessor pair that
--     _cos_offhand_picker and _cos_preview_runtime already use.
--
-- COMPOSES WITH, DOES NOT OVERLAP, the other HeroWindowItemCustomization owners.
-- Four modules hook this same class on DISJOINT methods, and this owner shares no
-- hook with any of them:
--   _cos_offhand_picker      _setup_illusions / _handle_input / _state_draw_overview
--                            (the picker grid itself, and the screen-ENTER anchor)
--   _cos_modded_illusion_swap  the craft-button and illusion-index methods
--   _ui_dump                 on_enter
--   _cos_preview_runtime     the previewer CLASSES (HeroPreviewer /
--                            MenuWorldPreviewer / LootItemUnitPreviewer /
--                            TeamPreviewer), not this window
-- The split is "who owns the VISIT" (this module: mount-time world safety and
-- exit-time teardown) versus "who owns what happens DURING the visit" (the picker
-- and the craft flow). Screen ENTER tracing deliberately stays with
-- _cos_offhand_picker's _setup_illusions hook - see the note kept on the on_exit
-- hook below.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered install call at the former inline position; guarded by
-- qa/lua/tests/test_cos_customization_view_lifecycle.lua.

local CustomizationViewLifecycle = {}

function CustomizationViewLifecycle.install(mod, deps)
    deps = deps or {}

    local RESOURCE_RESIDENCY     = deps.resource_residency
    local _local_player_safe     = deps.local_player_safe
    local GlowPicker             = deps.glow_picker
    local LA_PERSIST             = deps.la_persist
    local OFFHAND_COMMIT         = deps.offhand_commit
    local _offhand_session_state = deps.offhand_session_state
    local _dbg                   = deps.dbg
    local _dbg_alert             = deps.dbg_alert
    local _trace                 = deps.trace

    -- Late-bound / mutable entry state. See ENTRY-OWNED STATE in the header.
    local _get_send_la_apply                    = deps.get_send_la_apply
    local _get_active_customization_backend_id  = deps.get_active_customization_backend_id
    local _set_active_customization_backend_id  = deps.set_active_customization_backend_id

    -- ============================================================
    -- #228 / #235: in-mission weapon-preview shading-environment guard
    -- ============================================================
    -- Opening the weapon-illusion customization screen (HeroWindowItemCustomization,
    -- the loadout-panel gear icon) IN A MISSION crashed with a native Access
    -- violation (0xc0000005, addr 0) in the world render pass:
    --   [0] =[C] blend <- foundation/scripts/util/script_world.lua render
    --   <- foundation/scripts/managers/world/world_manager.lua render
    -- Repro on the reporter's machine: warcamp (Against the Grain), es_deus_01
    -- spear+shield, cog opened mid-mission via the gut in-mission loadout panel
    -- (gut logged "customize view mounting mid-mission (cosmetics path, no cim)").
    --
    -- CORRECTED ROOT CAUSE (supersedes the 0.9.62-dev note, which blamed the level-
    -- less environment/ui_hdr world itself). The customization view builds a 3D
    -- preview world through its viewport UI pass (ui_passes.lua:2436-2492 ->
    -- WorldManager.create_world -> ScriptWorld.create_shading_environment). In the
    -- keep it spawns levels/ui_store_preview/world + environment/ui_store_preview
    -- (keep-resident, hero_window_item_customization.lua:405-406). Mid-mission the
    -- preview level isn't loaded, so cim/gut strip level_name and substitute
    -- shading_environment = "environment/ui_hdr" (crafting_in_modded_dev.lua:2086,
    -- gui_tweaker_dev/_gut_mission_inventory.lua:236). ui_hdr + the "default"
    -- variation is NOT the fault: hero_view.lua:174-177 and loading_view.lua:113-118
    -- create-and-blend exactly that every frame in a mission with no crash, and the
    -- customization window is a child of HeroView so HeroView's own ui_hdr world is
    -- resident while the preview is open. The AV is a MISSING BLEND VARIATION:
    -- _present_item -> _update_environment sets the world's blend target to a
    -- per-weapon variation (item_data.item_preview_environment or "weapons_default_01",
    -- hero_window_item_customization.lua:1377-1381), writing shading_settings[1]
    -- (:583-594). ScriptWorld.render blends shading_settings each frame
    -- (script_world.lua:122). on_enter runs _create_ui_elements (:130) then
    -- _present_item (:132) synchronously, so the FIRST rendered frame blends
    -- {"weapons_default_01",1} -- never the harmless {"default",1}. weapons_default_01
    -- is a variation of environment/ui_store_preview (ships with the keep level);
    -- environment/ui_hdr does not define it, so native ShadingEnvironment.blend
    -- indexes a nil blend object -> AV. (A genuinely-unloaded env RESOURCE throws a
    -- clean "Resource not loaded" fatal instead of an AV -- cf. the forge case at
    -- crafting_in_modded_dev.lua:1945-1949 -- confirming the resource is resident and
    -- only the variation is absent.)
    --
    -- 0.9.62-dev FIX (superseded): neuter the world (nil its shading_environment) so
    -- ScriptWorld.render early-returns before any blend. Stopped the crash but skipped
    -- blend+apply+render_world -> the 3D weapon panel rendered BLANK (#235).
    --
    -- 0.9.64-dev FIX (crash-only, render-preserving): KEEP the env intact so the world
    -- renders and pin the blend target to "default" (the _update_environment hook below
    -- forces force_default=true in mission). That killed both the AV and the blank --
    -- the panel now draws -- but it draws PURE BLACK (user test 2026-07-03). The
    -- 0.9.64-dev prediction "renders LIT under generic UI-HDR lighting" was wrong.
    --
    -- 0.9.65-dev (DIAGNOSTIC): why black. The mission env is NOT ui_store_preview, and
    -- cosmetics does NOT own the widget definition mid-mission -- a sibling mod does.
    -- gut's in-mission loadout panel mounts this view via its "cosmetics path" and its
    -- _create_item_preview_widget_definition substitute STRIPS level_name and sets
    -- shading_environment = "environment/ui_hdr" (gui_tweaker_dev/_gut_mission_inventory
    -- .lua:207,236; cim's equivalent is crafting_in_modded_dev.lua:2079-2106, env
    -- _FORGE_MISSION_SAFE_ENV). So mid-mission the preview world has NO level (no baked
    -- or level light units) and the ui_hdr env. ui_hdr is a 2D-UI TONEMAPPING env: its
    -- only other users render emissive 2D GUI (HeroView HDR-GUI hero_view.lua:167-181,
    -- LoadingView loading_view.lua:113-118). It carries no sun / ambient / IBL to light
    -- a 3D object, so the "default" blend leaves the weapon unlit = BLACK. The keep is
    -- fine because there it is ui_store_preview + levels/ui_store_preview/world + the
    -- keep-resident weapons_default_01 studio-lighting variation.
    --
    -- The 0.9.65-dev instrument answered it (host log 2026-07-03 21:22): ui_hdr has NO
    -- 3D radiance (a 160x exposure boost stayed pure black) and, crucially,
    -- environment/ui_store_preview IS resident mid-mission. So THIS build FIXES it:
    -- re-point the preview world's shading env to ui_store_preview and let vanilla's
    -- studio-lit weapons_default_01 variation blend (re-point block below + the
    -- _update_environment hook). Keep path stays a pure pass-through.
    -- Pre-flight: cosmetics_tweaker hooks _create_preview_widget NOWHERE else.
    mod:hook_safe("HeroWindowItemCustomization", "_create_preview_widget", function(self)
        local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
        if in_keep then return end
        local pw = self and self._preview_widget
        local pass_data = pw and pw.element and pw.element.pass_data
        local vp_data = pass_data and pass_data[1]
        local world = vp_data and vp_data.world
        if not world then
            if printf then printf("[235][cos] in mission: no preview world on _create_preview_widget") end
            return
        end

        -- [235] state capture: the env object, its tonemapping "exposure" (camera_manager
        -- .lua:335 reads/writes this every frame on the gameplay env, so an ok read => a
        -- valid env that exposes it), the live blend target, and whether ANY level spawned
        -- into the preview world (the mission-safe defs strip it -> expect level_spawned=false).
        -- Direct env NAME + whether the def stripped the level. UIWidget.init keeps the
        -- widget's style verbatim (ui_widget.lua:15,41), so the mission-safe def's chosen
        -- shading_environment / level_name are readable straight off the widget style --
        -- no inference needed. This is the decisive "which env is the mission preview".
        local vp_style    = pw.style and pw.style.viewport
        local env_name    = vp_style and vp_style.shading_environment
        local style_level = vp_style and vp_style.level_name
        local env = World.has_data(world, "shading_environment") and World.get_data(world, "shading_environment") or nil
        local ss  = World.has_data(world, "shading_settings") and World.get_data(world, "shading_settings") or nil
        local osd = pw.content and pw.content.object_set_data
        local exp_ok, exp = pcall(function() return env and ShadingEnvironment.scalar(env, "exposure") end)
        if printf then
            printf("[235][cos] mission preview: env_name=%s style_level=%s env_obj=%s exposure_ok=%s exposure=%s blend[1]=%s level_spawned=%s osd_level=%s",
                tostring(env_name), tostring(style_level), tostring(env),
                tostring(exp_ok), tostring(exp),
                tostring(ss and ss[1]), tostring(osd and osd.level ~= nil), tostring(osd and osd.level_name))
        end

        -- Residency probe for the NEXT-round fix (env re-point or spawned light).
        -- can_get may not accept every type string; pcall so a bad type never fatals.
        if printf then
            local function res(kind, name)
                local ok, r = pcall(function() return Application.can_get(kind, name) end)
                if not ok then return "err" end
                return tostring(r)
            end
            printf("[235][cos] residency(shading_environment): ui_hdr=%s ui_store_preview=%s ui_loot_preview=%s",
                res("shading_environment", "environment/ui_hdr"),
                res("shading_environment", "environment/ui_store_preview"),
                res("shading_environment", "environment/ui_loot_preview"))
        end

        -- #235 FIX: re-point this mission preview world's shading env from the unlit
        -- ui_hdr (set by gut/cim's mission-safe def) to environment/ui_store_preview --
        -- the SAME studio-lit env the keep uses, verified RESIDENT mid-mission by the
        -- residency probe above (host log 2026-07-03 21:22: ui_store_preview=true, while
        -- the 160x exposure boost on ui_hdr stayed pure black -> ui_hdr has no 3D
        -- radiance). This is the spawn_level re-point pattern (script_world.lua:399-405):
        -- re-point the EXISTING env object to the new resource. weapons_default_01 is a
        -- variation DEFINED in ui_store_preview (keep witnesses: store_window_item_preview
        -- .lua:88+1367, hero_window_gotwf_item_preview.lua:67+607,
        -- hero_window_item_customization.lua:406+1378), so once the world runs
        -- ui_store_preview the _update_environment hook can let vanilla's weapons_default_01
        -- through with NO #228 AV -- that AV was specifically an UNDEFINED variation on
        -- ui_hdr, structurally impossible on an env that defines it. Runs before the first
        -- render (on_enter _create_ui_elements -> _create_preview_widget:367 precedes
        -- _present_item -> _update_environment). Gated on residency + pcall'd, so a failed
        -- or unavailable re-point leaves the world on ui_hdr and _update_environment falls
        -- back to forcing "default" (unlit but AV-safe). NEVER touches the keep path.
        local store_env = "environment/ui_store_preview"
        local store_resident = RESOURCE_RESIDENCY.shading_environment_resident(
            store_env, Application, nil, "cos_mission_item_preview") == true
        if env and store_resident then
            local ok = pcall(World.set_shading_environment, world, env, store_env)
            if ok then
                World.set_data(world, "cos_preview_env_repointed", true)
                if printf then printf("[235][cos] re-pointed mission preview env %s -> %s (studio-lit, resident); _update_environment will allow weapons_default_01",
                    tostring(env_name), store_env) end
            elseif printf then
                printf("[235][cos] set_shading_environment(%s) FAILED -> staying on ui_hdr, forcing \"default\" (unlit but AV-safe)", store_env)
            end
        elseif printf then
            printf("[235][cos] NOT re-pointing (env=%s store_resident=%s) -> forcing \"default\" (unlit but AV-safe)",
                tostring(env ~= nil), tostring(store_resident))
        end
    end)

    -- #235: pin the in-mission preview world's blend variation to "default".
    -- The world above keeps its environment/ui_hdr shading env. ui_hdr defines the
    -- "default" variation (proven blend-safe by hero_view.lua:174-177 and
    -- loading_view.lua:113-118) but NOT the per-weapon variations (weapons_default_01,
    -- etc.) that vanilla _present_item -> _update_environment requests
    -- (hero_window_item_customization.lua:1377-1381 / :583-594). ScriptWorld.render
    -- blends shading_settings[1] each frame (script_world.lua:122); a variation ui_hdr
    -- lacks -> native ShadingEnvironment.blend AV (the real #228 trigger). Forcing
    -- force_default=true keeps shading_settings[1] = "default", so blend only ever
    -- asks for the variation ui_hdr has (no AV, no blank) -- BUT ui_hdr carries no 3D
    -- scene lighting, so the weapon draws BLACK. #235 FIX: the _create_preview_widget
    -- hook above re-points the mission preview world to environment/ui_store_preview
    -- (resident mid-mission) when it can. When that succeeded (flagged
    -- cos_preview_env_repointed on the world), we let vanilla's weapons_default_01
    -- variation through here instead of forcing "default" -- that variation IS defined in
    -- ui_store_preview, so it blends keep-identically with NO #228 AV, and the weapon is
    -- lit like the keep. If the re-point did NOT happen (env not resident / re-point
    -- failed), fall back to forcing "default" (unlit but AV-safe).
    -- _update_environment is the SOLE writer of shading_settings[1] (only caller is
    -- _present_item), so this one hook covers every re-present (reroll/illusion tabs).
    -- Keep path is a pure pass-through (full per-weapon studio lighting preserved).
    -- Pre-flight: cosmetics_tweaker hooks _update_environment NOWHERE else.
    mod:hook("HeroWindowItemCustomization", "_update_environment", function(func, self, item_preview_environment, force_default)
        local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
        if in_keep then return func(self, item_preview_environment, force_default) end
        -- Did _create_preview_widget re-point this preview world to ui_store_preview?
        local pw = self and self._preview_widget
        local world = pw and pw.element and pw.element.pass_data and pw.element.pass_data[1] and pw.element.pass_data[1].world
        local repointed = world and World.has_data(world, "cos_preview_env_repointed")
            and World.get_data(world, "cos_preview_env_repointed") or false
        -- [235] log each distinct env vanilla requests (once per value), plus whether we
        -- ALLOW it (re-pointed to ui_store_preview) or force "default" (fallback).
        if printf then
            mod._lv235_seen_env = mod._lv235_seen_env or {}
            local k = tostring(item_preview_environment)
            if not mod._lv235_seen_env[k] then
                mod._lv235_seen_env[k] = true
                printf("[235][cos] _update_environment(mission): vanilla requested env=%s force_default_in=%s repointed=%s -> %s",
                    k, tostring(force_default), tostring(repointed),
                    repointed and "ALLOW (studio-lit)" or "forcing \"default\"")
            end
        end
        if repointed then
            return func(self, item_preview_environment, force_default)  -- allow weapons_default_01 -> keep-identical studio lighting
        end
        return func(self, item_preview_environment, true)  -- fallback: pin blend target to "default" (AV-safe)
    end)

    -- v0.9.43-dev SCREEN trace NOTE: the customization view ENTER anchor is
    -- emitted from the `_setup_illusions` hook below ("SCREEN setup_illusions …"),
    -- NOT from a dedicated on_enter hook — `_ui_dump.lua` already wraps
    -- `HeroWindowItemCustomization.on_enter` for THIS mod, and VMF silently drops a
    -- second registration on the same (Class, method) per mod (repo rule /
    -- VMF_RECIPES § 1). `_setup_illusions` fires on screen-enter for the customized
    -- item (and on each re-select) and has the resolved backend_id, so it's the
    -- better enter anchor anyway. SCREEN exit is traced in the on_exit hook here.
    mod:hook_safe("HeroWindowItemCustomization", "on_exit", function(self, params)
        _trace("SCREEN exit bid=%s clearing active_customization_bid=%s pending_la_emit_on_exit=%s",
            tostring(self and self._item_backend_id),
            tostring(_get_active_customization_backend_id()),
            tostring(mod._pending_la_emit_on_exit and "queued" or "none"))
        _set_active_customization_backend_id(nil)
        mod._active_customization_item_type = nil
        -- M1.4: also close the glow picker so it doesn't linger on top of the
        -- next screen. GlowPicker is required at the top of this file so it's
        -- safe to call directly here.
        if GlowPicker and GlowPicker.is_open and GlowPicker.is_open() then
            GlowPicker.close()
        end
        -- v0.9.53-dev (#200): OFFHAND APPLY-GATE. If the user left WITHOUT a genuine
        -- Apply (no craft-complete flagged mod._offhand_committed[bid] this session),
        -- discard the pending offhand pick: REVERT _offhand_selection[bid] to the
        -- baseline snapshotted on screen open and DROP the queued peer broadcast so
        -- nothing reaches the live keep weapon. This is what the user wants — a grid
        -- pick must only stick on Apply, mirroring vanilla's row-1 weapon-illusion
        -- grid. The live body never changed during browse (the #150
        -- _in_create_equipment suppression keeps it at baseline), so reverting is a
        -- no-op visually; it just prevents the un-Applied pick from leaking on exit.
        -- When committed, fall through to the normal drain + pulse-wield below.
        local _exit_bid = self and self._item_backend_id
        if _exit_bid and not (mod._offhand_committed and mod._offhand_committed[_exit_bid]) then
            local baseline = mod._offhand_baseline and mod._offhand_baseline[_exit_bid]
            if baseline ~= nil then
                _offhand_session_state.restore(_exit_bid, baseline)
                mod._pending_la_emit_on_exit = nil  -- skip the drain/pulse-wield below
                mod:info("[cos:weapon-leak] offhand pick NOT applied (no Apply) on exit bid=%s -> reverted to baseline, broadcast dropped",
                    tostring(_exit_bid))
                _trace("SCREEN exit REVERT offhand bid=%s (no Apply this session)", tostring(_exit_bid))
            end
        end
        -- v0.9.3.4-hotfix: drain the deferred LA offhand emits queued by
        -- _ct_on_offhand_pressed. Each preview click overwrote its own queue
        -- slot, so this drains exactly ONE final selection per backend_id —
        -- the one the user left selected when navigating away.
        if mod._pending_la_emit_on_exit then
            local n = OFFHAND_COMMIT.drain(mod, mod._pending_la_emit_on_exit,
                LA_PERSIST, _get_send_la_apply(), function(unit) return Unit.alive(unit) end)
            if n > 0 then
                _dbg("[ct offhand] drained %d deferred LA emit(s) on screen exit", n)
                -- v0.9.3.8: pulse-wield to force fresh weapon-unit spawn.
                --
                -- v0.9.3.7 tried `inv:wield(inv.wielded_slot)` but vanilla
                -- `SimpleInventoryExtension.wield` short-circuits when called
                -- with the SAME slot it's already wielding — no re-spawn,
                -- `BackendUtils.get_item_units` not re-called, new
                -- `_offhand_selection` not read. The user's empirical fix
                -- ("swap main weapon back and forth") works because it wields
                -- a DIFFERENT slot, which is what vanilla actually re-spawns.
                --
                -- This version pulses through the OTHER weapon slot then
                -- back: if currently wielding slot_melee, wield slot_ranged
                -- briefly then slot_melee again. Both slot's units re-spawn,
                -- both fire get_item_units, both pick up the new override.
                -- The visual "swap animation flash" is acceptable on
                -- customization-screen exit.
                --
                -- Guard against keep-context where local_player isn't fully
                -- wired (player_unit nil, inventory_system extension missing).
                local pm = Managers and Managers.player
                local lp = _local_player_safe(pm)
                local pu = lp and lp.player_unit
                -- v0.9.4: per-guard diagnostic. v0.9.3.8 silently bailed in keep
                -- context with zero log output; need to know WHICH guard failed.
                if not pm then
                    _dbg("[ct offhand] pulse-wield SKIP — Managers.player nil")
                elseif not lp then
                    _dbg("[ct offhand] pulse-wield SKIP — local_player nil")
                elseif not pu then
                    _dbg("[ct offhand] pulse-wield SKIP — player_unit nil")
                elseif not Unit.alive(pu) then
                    _dbg("[ct offhand] pulse-wield SKIP — player_unit not alive")
                elseif not (ScriptUnit and ScriptUnit.has_extension) then
                    _dbg("[ct offhand] pulse-wield SKIP — ScriptUnit.has_extension unavailable")
                end
                if pu and Unit.alive(pu) and ScriptUnit and ScriptUnit.has_extension then
                    local inv = ScriptUnit.has_extension(pu, "inventory_system")
                    -- v0.9.5: removed the "wielded_slot is nil" SKIP diagnostic
                    -- since the code below now HANDLES nil (uses keep-wield from
                    -- nil instead of pulse-cycling). Other SKIP messages remain
                    -- as informational diagnostics.
                    if not inv then
                        _dbg("[ct offhand] pulse-wield SKIP — no inventory_system extension on player_unit")
                    elseif not inv.wield then
                        _dbg("[ct offhand] pulse-wield SKIP — inv.wield method missing")
                    elseif not (inv._equipment and inv._equipment.slots) then
                        _dbg("[ct offhand] pulse-wield SKIP — inv._equipment / inv._equipment.slots missing")
                    end
                    if inv and inv.wield and inv._equipment and inv._equipment.slots then
                        local orig_slot = inv.wielded_slot  -- may be NIL in keep
                        local slots = inv._equipment.slots
                        -- v0.9.5: handle wielded_slot=nil case (keep context).
                        -- Previous version bailed entirely when orig_slot was
                        -- nil; the user's keep-mode workflow ALWAYS has nil
                        -- wielded_slot, so the pulse-wield never fired.
                        --
                        -- New approach: if orig_slot is nil, wield ANY equipped
                        -- weapon slot directly. That sets wielded_slot from nil
                        -- to the chosen slot, which DOES fire vanilla's
                        -- _wield_slot path (no short-circuit because nil != slot).
                        -- The visible side effect is the player suddenly
                        -- "drawing" a weapon in keep, which is the EXACT visual
                        -- refresh the user wants — it forces the LA paint to
                        -- apply to the in-keep model.
                        --
                        -- If orig_slot IS set, do the original pulse pattern
                        -- (wield other → wield orig back).
                        if not orig_slot then
                            -- Find any equipped weapon slot. Prefer slot_melee
                            -- since that's where shield+sword changes typically
                            -- target. Fall back to slot_ranged or any other.
                            local target_slot
                            for _, candidate in ipairs({ "slot_melee", "slot_ranged" }) do
                                if slots[candidate] then target_slot = candidate; break end
                            end
                            if not target_slot then
                                for slot_name, slot_data in pairs(slots) do
                                    if slot_data and (slot_name == "slot_melee" or slot_name == "slot_ranged") then
                                        target_slot = slot_name; break
                                    end
                                end
                            end
                            if target_slot then
                                local ok, err = pcall(inv.wield, inv, target_slot)
                                if ok then
                                    _dbg("[ct offhand] keep-wield slot=%s (from nil) to refresh local model",
                                        tostring(target_slot))
                                else
                                    _dbg_alert("[ct offhand] keep-wield errored: %s", tostring(err))
                                end
                            else
                                _dbg("[ct offhand] pulse-wield SKIP — no equipped weapon slot found")
                            end
                        else
                            -- orig_slot is set — do the original pulse pattern.
                            local pulse_slot
                            if orig_slot == "slot_melee" and slots["slot_ranged"] then
                                pulse_slot = "slot_ranged"
                            elseif orig_slot == "slot_ranged" and slots["slot_melee"] then
                                pulse_slot = "slot_melee"
                            else
                                for slot_name, slot_data in pairs(slots) do
                                    if slot_name ~= orig_slot and slot_data then
                                        pulse_slot = slot_name
                                        break
                                    end
                                end
                            end
                            if pulse_slot then
                                local ok1, err1 = pcall(inv.wield, inv, pulse_slot)
                                local ok2, err2 = pcall(inv.wield, inv, orig_slot)
                                if ok1 and ok2 then
                                    _dbg("[ct offhand] pulse-wielded %s -> %s to refresh local model",
                                        tostring(pulse_slot), tostring(orig_slot))
                                else
                                    _dbg_alert("[ct offhand] pulse-wield errored: %s / %s",
                                        tostring(err1), tostring(err2))
                                end
                            else
                                _dbg("[ct offhand] pulse-wield SKIP — no alternate slot to pulse through (wielded=%s)",
                                    tostring(orig_slot))
                            end
                        end
                    end
                end
            end
            mod._pending_la_emit_on_exit = nil
        end
        -- v0.9.53-dev (#200): clear this session's apply-gate state so the next
        -- screen open takes a fresh baseline (and a stale committed flag can't
        -- suppress a later revert). Keyed per-bid; only one customization screen
        -- is open at a time.
        if _exit_bid then
            if mod._offhand_baseline then mod._offhand_baseline[_exit_bid] = nil end
            if mod._offhand_committed then mod._offhand_committed[_exit_bid] = nil end
        end
    end)

    return true
end

return CustomizationViewLifecycle
