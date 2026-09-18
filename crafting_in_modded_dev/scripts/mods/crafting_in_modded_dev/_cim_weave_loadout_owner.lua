-- _cim_weave_loadout_owner.lua -- CIM-dev mutable Weaves loadout owner.
--
-- RESPONSIBILITY
-- Owns the WRITE half of the Athanor bubble grid: everything between "the user
-- clicked a bubble" and "the equipped item now carries that property", and
-- nothing else:
--   * the amulet slot map (`_AMULET_SLOT_BY_INDEX`, the 10-slot layer size) and
--     the per-slot CRAFT-button dirty marks
--   * the per-property bubble-cap math -- `_bubble_cap`, `_value_for_bubbles`,
--     `_bubbles_for_value`, the `weave_` / `properties_` key normalizer, and the
--     stamina/movespeed caps (#86, #244)
--   * `_store_property_slot` (the write-path slot-array cap) and
--     `_cap_grid_property_arrays` (the #86 read-chokepoint trim)
--   * the `movespeed_2pct_mode` buff-template patch and its settings-change
--     re-apply
--   * the seed/apply pass: `_seed_one_item`, `_forge_seed_item`,
--     `_forge_apply_to_amulet`, `_forge_apply_to_item`
--   * the TEN mutable `BackendInterfaceWeavesPlayFab` hooks that redirect weave
--     loadout reads and writes at our own data:
--     get_loadout_properties / get_loadout_traits / get_loadout_talents /
--     get_mastery / set_loadout_property / remove_loadout_property /
--     set_loadout_trait / remove_loadout_trait / set_loadout_talent /
--     remove_loadout_talent
--
-- EXTRACTED VERBATIM from crafting_in_modded_dev.lua entry lines 1608-2391
-- (732 nonblank), re-indented one level. `mod:dofile` is not a singleton, so the
-- entry calls the installer EXACTLY once, at the precise point this block used
-- to execute: after the `_cim_immutable_relic_ui` install, before the
-- BackendManagerPlayFab commit block. Hook-registration order and cardinality,
-- the load-time `_patch_movespeed_buff()` call, and the
-- `_cim_settings_runtime.install` registration all keep their original timing.
--
-- THE NON-VERBATIM BOUNDARIES
-- Four entry locals the block reads are REASSIGNED after this seam, so a
-- captured reference would go stale:
--   * `_custom_forge_active` -- flipped by `mod.open_forge` and cleared by
--     `HeroViewStateWeaveForge.on_exit` (10 hook-gate reads -> `_is_active()`)
--   * `_forge_item_props` -- rebound to a FRESH table by both of those, so a
--     captured table would keep serving the previous Athanor session's seed
--     (4 lines -> `_get_forge_item_props()`)
--   * `_forged_weapons` -- rebound by `_forge_load` on every backend
--     `_create_interfaces` pass (2 lines -> `_get_forged_weapons()`)
--   * `_amulet_dirty` -- the table itself is stable, but it is created and
--     reset above this seam, so it is read through the same accessor
--     convention for reload safety (2 lines -> `_get_amulet_dirty()`)
-- `_forge_save` is a plain entry-local function that is never reassigned, so it
-- is injected directly. #1141's weapon Apply path passes it a detached candidate
-- registry and publishes the live item/owner record only after persistence;
-- amulet writes retain their existing current-registry call. Every accessor
-- follows the convention the persisted-loadout owner, `_cim_command_owner`, and
-- `_cim_regression_checks` already use, and it keeps the flat `mod._cim_*`
-- public surface from widening.
--
-- THE FORWARD-DECLARATION COUPLING, SOLVED
-- `_bubble_cap`, `_value_for_bubbles`, `_bubbles_for_value`, `_strip_weave`,
-- `_store_property_slot`, and `_cap_grid_property_arrays` were entry forward
-- declarations ASSIGNED (not declared) inside this block. They are declared
-- here instead and handed back through `state.exports`. Only ONE of them has a
-- consumer ABOVE the seam -- `_cim_weave_economy`'s get_property_mastery_costs
-- hook resolves `_bubble_cap` at callback time -- so the entry keeps exactly
-- that one forward declaration and binds it here; the other three the entry
-- still reads are ordinary locals assigned at the seam. `_bubbles_for_value`
-- and `_strip_weave` have no entry consumer at all and are now private.
--
-- PUBLIC SURFACE
-- None. This owner publishes no `mod._cim_*` field; it registers ten hooks and
-- returns the four math helpers the entry re-binds plus a narrow three-function
-- Temper Item draft boundary. The late `_cim_regression_checks` installer still
-- receives the existing math keys; `_cim_temper_runtime` consumes the draft
-- boundary without publishing flat `mod._cim_*` methods.
--
-- COMPOSES WITH, DOES NOT OVERLAP, THE OTHER cim OWNERS
--   * `_cim_weave_economy` owns the 18 READ-ONLY progression/economy hooks
--     ("everything is free"). It installs ABOVE this seam and consumes
--     `bubble_cap` through an injected accessor, so the split is read vs write
--     on the same vanilla class with zero duplicate registrations.
--   * `_cim_accessory_property_runtime` owns the #239/#959 picker-side
--     `HeroWindowWeaveProperties` hooks; the shared admission math lives in
--     `_cim_accessory_property_policy`, which BOTH consume through `mod`.
--   * `_cim_forge_preview_owner` / `_cim_forge_ui_owner` /
--     `_cim_forge_picker_owner` own Athanor view lifecycle, presentation, and
--     category widening. This owner registers no view hook at all.
--   * The persisted-loadout owner owns the PERSISTED equip store and the two
--     equip-capture hooks. This owner registers neither and never reads that
--     store; it edits the live item, and persistence is the injected save.
-- Deliberately NOT included: the `BackendManagerPlayFab.commit` suppression
-- that blocks PlayFab writes while either forge is open stays in the entry,
-- immediately below this seam. It is anti-tamper crash safety covering BOTH
-- craft surfaces (it also consults the standard-forge active flag), so it must
-- never be gated on this owner's install. The #278/#371 wire-safety layer and
-- the Athanor on_enter crash-guard cascade likewise stay where they are.

local function install(ctx)
    assert(type(ctx) == "table", "CIM weave loadout owner requires context")

    local mod = assert(ctx.mod, "CIM weave loadout owner requires mod")

    local state = mod._cim_weave_loadout_owner_state
    if not state then
        state = {}
        mod._cim_weave_loadout_owner_state = state
    end

    -- Refresh the injected dependencies BEFORE the install guard. A development
    -- reload re-executes the entry, which builds fresh closures over the
    -- reloaded forge state; holding the first install's closures would leave the
    -- ten hooks reading the pre-reload session. Same ordering the sibling owners
    -- use (the persisted-loadout owner, _cim_weave_economy, _cim_forge_ui_owner).
    state.is_active = assert(ctx.is_active,
        "CIM weave loadout owner requires the active-forge accessor")
    state.get_forge_item_props = assert(ctx.get_forge_item_props,
        "CIM weave loadout owner requires the seeded-props accessor")
    state.get_forged_weapons = assert(ctx.get_forged_weapons,
        "CIM weave loadout owner requires the forged-weapons accessor")
    state.get_amulet_dirty = assert(ctx.get_amulet_dirty,
        "CIM weave loadout owner requires the amulet dirty-flag accessor")
    state.forge_save = assert(ctx.forge_save,
        "CIM weave loadout owner requires the forge save writer")
    state.temper_transaction = assert(ctx.temper_transaction,
        "CIM weave loadout owner requires the temper transaction policy")
    assert(type(state.temper_transaction.apply_to_item) == "function"
            and type(state.temper_transaction.copy_payload) == "function"
            and type(state.temper_transaction.is_dirty) == "function",
        "CIM weave loadout owner requires the complete temper transaction policy")
    state.get_raw_mirror_item = ctx.get_raw_mirror_item or function(backend_id)
        local managers = rawget(_G, "Managers")
        local backend = managers and managers.backend
        local mirror = backend and type(backend.get_backend_mirror) == "function"
            and backend:get_backend_mirror() or nil
        local items = mirror and mirror._inventory_items
        return type(items) == "table" and rawget(items, backend_id) or nil
    end

    -- mod:dofile is not a singleton. A second install would re-register all ten
    -- BackendInterfaceWeavesPlayFab hooks -- VMF drops the duplicates and warns,
    -- so the entry would silently keep the FIRST install's closures. Hand back
    -- the first exports instead; nothing below this guard runs twice.
    if state.exports then
        return state.exports
    end

    -- One indirection so the moved body keeps its original call text while the
    -- resolvers above stay replaceable across a reload.
    local function _is_active()
        return state.is_active()
    end
    local function _get_forge_item_props()
        return state.get_forge_item_props()
    end
    local function _get_forged_weapons()
        return state.get_forged_weapons()
    end
    local function _get_amulet_dirty()
        return state.get_amulet_dirty()
    end
    local function _forge_save(source)
        return state.forge_save(source)
    end

    -- Mirrors the entry's own forward declarations: the moved body ASSIGNS these
    -- mid-block. `_bubble_cap` is additionally handed back to the entry local
    -- that `_cim_weave_economy`'s cost hook closes over.
    local _bubble_cap
    local _value_for_bubbles
    local _bubbles_for_value
    local _strip_weave
    local _store_property_slot
    local _cap_grid_property_arrays

    -- --- Property/trait/talent storage (redirect to our own data) ---

    -- Maps amulet trait-slot index → adventure jewellery slot. The amulet layout
    -- has 3 trait slots and 3 property layers; vanilla `WeaveCareerProgression`
    -- (`weave_loadout_settings.lua:282-295`) orders them by accessory POOL:
    --   slot 1 = offence_accessory (CHARM)
    --   slot 2 = defence_accessory (NECKLACE)
    --   slot 3 = utility_accessory (TRINKET)
    -- The picker for slot N reads its `category` from that table and renders the
    -- matching property/trait pool, so we MUST seed/apply against the same order
    -- or the bubble grid shows charm options where the player sees necklace data.
    --
    -- VT2's career_settings names the charm slot `slot_ring` (legacy) and the
    -- trinket slot `slot_trinket_1` (note the suffix). `slot_charm`/`slot_trinket`
    -- return nil from `get_loadout_item_id`.
    local _AMULET_SLOT_BY_INDEX = {
        [1] = "slot_ring",         -- offence_accessory → charm
        [2] = "slot_necklace",     -- defence_accessory → necklace
        [3] = "slot_trinket_1",    -- utility_accessory → trinket
    }
    local _AMULET_INDEX_BY_SLOT = {}
    for idx, slot in pairs(_AMULET_SLOT_BY_INDEX) do _AMULET_INDEX_BY_SLOT[slot] = idx end
    local _AMULET_LAYER_SIZE = 10  -- matches amulet_slot_layout's per-layer count

    -- Per-slot dirty tracking for the amulet's CRAFT button. The auto-apply
    -- mutates equipped items in-place on every bubble click (session-only for
    -- vanilla), so the user's bubble edits are already applied by the time they
    -- reach CRAFT — but for vanilla items those edits don't survive a restart.
    -- CRAFT solves that by creating a new modded item per dirty slot. We mark a
    -- slot dirty on any property/trait set/remove against the amulet (item_backend_id == nil).
    -- (`_amulet_dirty` is forward-declared near the top of the Athanor section so
    -- the on_exit hook can reset it; the table itself was created there.)

    local function _mark_amulet_property_dirty(slot_index)
        local layer = math.ceil((slot_index or 0) / _AMULET_LAYER_SIZE)
        if layer >= 1 and layer <= 3 then _get_amulet_dirty()[layer] = true end
    end

    local function _mark_amulet_trait_dirty(slot_index)
        if slot_index and slot_index >= 1 and slot_index <= 3 then
            _get_amulet_dirty()[slot_index] = true
        end
    end

    -- ============================================================
    -- Per-property bubble caps (stamina, movespeed, ...)
    -- ============================================================
    -- Most weave properties scale linearly: 5 bubbles maps to value 0.0..1.0,
    -- engine reads value into a 5-tier variable_bonus / variable_multiplier_max
    -- and gives a proportional effect. cim defaults to that.
    --
    -- A few adventure properties don't fit that mold:
    --
    --   `properties_stamina` has `variable_bonus = {1, 1, 1, 2, 2}` — three
    --   tiers give +1, two tiers give +2. So 1, 2, or 3 filled bubbles ALL
    --   map to "+1 stamina" (visible discontinuity the user reported); 4 or 5
    --   bubbles to "+2". User-facing fix: cap stamina at 2 bubbles, each
    --   bubble = one step (1 bubble = +1, 2 bubbles = +2).
    --
    --   `properties_movespeed` is a FLAT `multiplier = 1.05` — it doesn't
    --   scale with the stored value at all, always +5% if applied. The cim
    --   grid display read raw value-as-percent (so 4/5 bubbles showed "79%
    --   movement speed") even though the actual buff was +5%. Cap at 1
    --   bubble so there's no discrepancy.
    --
    -- Conversion math (`_value_for_bubbles`) for capped properties: place
    -- each bubble's value at the midpoint of its target buff tier so the
    -- resolver in buff_extension.lua:208-216 lands cleanly:
    --   stamina 1/2 → value 0.4 → bonus_index = floor(0.4 / 0.2) + 1 = 3 → +1
    --   stamina 2/2 → value 1.0 → bonus_index = #table = 5 → +2
    --   movespeed 1/1 → value 1.0 → always +5% (no tier lookup)
    -- Per-property bubble cap. Default `movespeed = 1` matches vanilla's single
    -- +5% multiplier. The `movespeed_2pct_mode` VMF toggle uncaps to 5 (each
    -- bubble = +2% multiplier, max +10%) so we read it dynamically.
    -- Keyed by the BARE property name (`stamina` / `movespeed`). Issue #86 take 3:
    -- the game's weave property-picker passes the `WeaveProperties.categories`
    -- key form `weave_stamina` / `weave_movespeed` (NOT `weave_properties_stamina`)
    -- to set_loadout_property / get_property_mastery_costs. Trace:
    --   hero_window_weave_properties.lua:534 iterates WeaveProperties.categories[cat]
    --     → keys are `weave_stamina` / `weave_movespeed` (weave_properties.lua:543+)
    --   :550 stores entry.key = that
    --   :2663 calls set_loadout_property(career, key, ...) with that exact form
    --   backend_interface_weaves_playfab.lua:1031 receives it as `property_name`.
    -- So every runtime caller passes the `weave_<bare>` form. `_strip_weave` strips
    -- only `^weave_`, leaving the BARE `stamina` / `movespeed`. The prior fix keyed
    -- the table `properties_stamina` / `properties_movespeed`, so `_bubble_cap`
    -- MISSED for the real game key and fell back to the default 5 (stamina ate 5
    -- slots; movespeed showed 79% — `|100*(1.05/5 - 1)|` with one bubble). The
    -- previous regression test fooled itself by passing `weave_properties_stamina`,
    -- whose strip-form `properties_stamina` happened to match the (then-misKEYED)
    -- table — a key form the game never actually sends.
    --
    -- Robust fix: normalize ANY caller key form to the bare name and key the table
    -- by bare names. `_bare_property` strips `^weave_` THEN `^properties_`, so it
    -- collapses `weave_properties_X`, `weave_X`, `properties_X`, and bare `X` all to
    -- `X`. `_bubble_cap`, `_value_for_bubbles`, and `_bubbles_for_value` then resolve
    -- correctly regardless of which form reaches them.
    local _PROPERTY_BUBBLE_CAP_STATIC = {
        stamina   = 2,
        movespeed = 1,
    }

    _strip_weave = function(weave_key)
        return (weave_key or ""):gsub("^weave_", "")
    end

    -- Collapse any property key form to its bare name (strip `weave_` then
    -- `properties_`). Handles weave_properties_X / weave_X / properties_X / X.
    local function _bare_property(weave_key)
        local k = _strip_weave(weave_key)
        return (k:gsub("^properties_", ""))
    end

    _bubble_cap = function(weave_key)
        local bare = _bare_property(weave_key)
        if bare == "movespeed" and mod:get("movespeed_2pct_mode") then return 5 end
        -- Default 5: each generic property has a 5-bubble row you fill to scale its
        -- value (1 bubble = 20%, 5 = full — see `_value_for_bubbles`), exactly like
        -- vanilla weaves. v0.8.32-dev briefly forced this to 1, which let each
        -- property take only a SINGLE bubble and destroyed per-property scaling for
        -- every property at once (#86 over-correction, reverted v0.8.33-dev). The
        -- real #86 fix is the distinct-property ceiling (MAX_DISTINCT_PROPERTIES /
        -- the load-time trimmer / KEEP_LIMIT, all raised 2 → 10), NOT the bubble cap.
        -- stamina (2) / movespeed (1) keep their explicit caps; the 10-slot grid is a
        -- shared budget, so 10 distinct properties only fit if you don't max-fill them.
        return _PROPERTY_BUBBLE_CAP_STATIC[bare] or 5
    end

    -- value 0..1 that the engine should resolve for `count` filled bubbles.
    -- Default linear maps count/5 for backward compatibility with the existing
    -- 5-bubble properties.
    _value_for_bubbles = function(weave_key, count)
        local bare = _bare_property(weave_key)
        -- Movespeed 2pct mode: 5 bubbles, each adds 0.2 to the stored value.
        -- buff_extension lerps multiplier as 1 + (max-1)*value. If we also bump
        -- `variable_multiplier_max` from 1.05 → 1.10 (in the load-time patch
        -- below), then 1 bubble (value 0.2) → 1 + 0.10*0.2 = 1.02 = +2%, and
        -- 5 bubbles (value 1.0) → 1 + 0.10*1.0 = 1.10 = +10%.
        if bare == "movespeed" and mod:get("movespeed_2pct_mode") then
            return math.min(count / 5, 1.0)
        end
        local cap = _bubble_cap(weave_key)
        if cap == 5 then
            -- #244: the picker shows an ABSOLUTE fraction of the Weave maximum,
            -- but an Adventure item stores a NORMALIZED interpolation parameter.
            -- Attack speed 3/5 means 3%; storing 0.6 made the ordinary item path
            -- interpolate 60% across 3..5 and display/apply 4.2%.
            local policy = mod._cim244_property_value_policy
            local WP, Weave = rawget(_G, "WeaponProperties"), rawget(_G, "WeaveProperties")
            local adv = WP and WP.properties and WP.properties[bare]
            local weave = Weave and Weave.properties and Weave.properties["weave_" .. bare]
            local adv_value = adv and adv.description_values and adv.description_values[1]
            local weave_value = weave and weave.description_values and weave.description_values[1]
            local converted = policy and policy.storage_for_bubbles(
                adv_value and adv_value.value, weave_value and weave_value.value, count, cap)
            if converted ~= nil then return converted end
            return math.min(count / 5, 1.0)
        end
        if count <= 0 then return 0 end
        if count >= cap then return 1.0 end
        -- For stamina cap=2 and count=1: lands at 0.4 (vanilla tier 2 = +1).
        return (count * 2 - 1) / (cap * 2)
    end

    -- Bubble count to fill for an item that has property value `value`. Inverse
    -- of the apply step — used during seeding. For stamina we use the engine's
    -- own tier-breakpoint (>= 0.6 ⇒ +2) so the visible bubble count matches the
    -- visible +N stamina readout.
    _bubbles_for_value = function(weave_key, value)
        local cap = _bubble_cap(weave_key)
        if value == nil then return 0 end
        if cap == 5 then
            -- Symmetric #244 read path. Normalized zero is the range's valid low
            -- endpoint (3% attack speed), so it must seed three bubbles instead of
            -- making the property disappear on the next Athanor open.
            local bare = _bare_property(weave_key)
            local policy = mod._cim244_property_value_policy
            local WP, Weave = rawget(_G, "WeaponProperties"), rawget(_G, "WeaveProperties")
            local adv = WP and WP.properties and WP.properties[bare]
            local weave = Weave and Weave.properties and Weave.properties["weave_" .. bare]
            local adv_value = adv and adv.description_values and adv.description_values[1]
            local weave_value = weave and weave.description_values and weave.description_values[1]
            local converted = policy and policy.bubbles_for_storage(
                adv_value and adv_value.value, weave_value and weave_value.value, value, cap)
            if converted ~= nil then return converted end
            if value <= 0 then return 0 end
            return math.max(1, math.ceil(value * 5))
        end
        if value <= 0 then return 0 end
        if cap == 1 then return 1 end
        if cap == 2 then
            return value >= 0.6 and 2 or 1
        end
        -- Generic: scale value over cap, floor to integer, clamp.
        return math.max(1, math.min(cap, math.ceil(value * cap)))
    end

    -- Persist a clicked slot_index into the property picker's slot-index array,
    -- applying the two vanilla guards (cross-property collision + per-property use
    -- cap). Pure: mutates `props` only, no UI/backend side effects, so the
    -- /cim_regression_test can drive it with synthetic tables and assert the
    -- PERSISTED array length (the real grid-occupancy driver) — not just the
    -- display value the prior #86 fixes wrongly trusted. Returns the array for the
    -- property after the attempted store. Shared by the live `set_loadout_property`
    -- hook so the test exercises the exact production path.
    --
    -- `props`        : the live `data.properties` table (weave_key -> {slot_index,...})
    -- `property_key` : the game's key form (`weave_movespeed` / `weave_stamina` / ...)
    -- `slot_index`   : the grid slot the game's _find_next_available_slot picked
    local _cim959_store_diag_seen, _cim959_store_diag_count = {}, 0

    _store_property_slot = function(props, property_key, slot_index, layer_size)
        local cap = _bubble_cap and _bubble_cap(property_key) or 5
        local policy = mod._cim959_accessory_property_policy
        if not policy or type(policy.store_property_slot) ~= "function" then
            error("#959 accessory property store policy missing")
        end

        local arr, stored, reason, used_in_scope = policy.store_property_slot(
            props, property_key, slot_index, cap, layer_size)

        -- Bounded log-only apply evidence: once per property/layer/outcome.
        if layer_size and _cim959_store_diag_count < 24 then
            local layer = math.ceil(slot_index / layer_size)
            local token = table.concat({
                tostring(property_key), tostring(layer), tostring(reason),
            }, "|")
            if not _cim959_store_diag_seen[token] then
                _cim959_store_diag_seen[token] = true
                _cim959_store_diag_count = _cim959_store_diag_count + 1
                printf("[cim:959] property store key=%s layer=%d slot=%d result=%s layer_uses=%d",
                    tostring(property_key), layer, slot_index, tostring(reason),
                    tonumber(used_in_scope) or 0)
            end
        end

        return arr, stored, reason, used_in_scope
    end

    -- v0.8.30-dev (#86, READ-CHOKEPOINT guard — the fix the prior four #86 attempts
    -- never tried): grid occupancy is built by vanilla
    -- HeroWindowWeaveProperties._sync_backend_loadout
    -- (hero_window_weave_properties.lua:1478 reads get_loadout_properties(...),
    -- :1551-1556 maps ONE grid slot per slot-index array entry). Every prior #86 fix
    -- capped only the WRITE path (`_store_property_slot`). The write-path cap is
    -- provably correct in source (see /cim_regression_test `picker_caps_persisted_slot_array`),
    -- yet the user STILL sees stamina+movespeed eat 5 slots each — which can only mean
    -- the array reaching the grid is over-filled by a path the write cap doesn't cover
    -- (a deployed build predating the cap, a bypassed hook instance, or a stale seed).
    -- This trims each property's array to its bubble cap at the EXACT point the grid
    -- reads it, so occupancy can never exceed the cap regardless of how it got filled.
    --
    -- Layer-aware: the single-weapon editor (item_backend_id present) is one layer, so
    -- cap the whole array. The amulet editor (item_backend_id == nil) lets one property
    -- legitimately appear once per accessory layer (size `_AMULET_LAYER_SIZE`), so cap
    -- PER LAYER — a blanket trim there would wrongly drop a property the user put on a
    -- second accessory.
    --
    -- Self-reporting: when it actually has to trim (i.e. the over-fill leak is present)
    -- it logs via engine `printf` BEFORE trimming. `printf` writes to the engine console
    -- even with VMF mod-logging OFF (the user's normal config — which is why every prior
    -- `mod:info`/autodump "verification" saw nothing). So if the symptom persists, the
    -- console will carry the raw over-fill count and prove which path leaked, instead of
    -- us guessing. Idempotent: once trimmed, the cached array stays capped, so it logs at
    -- most once per leaking property, not every sync.
    _cap_grid_property_arrays = function(props, item_backend_id)
        if type(props) ~= "table" then return props end
        for property_key, arr in pairs(props) do
            if type(arr) == "table" then
                local cap = _bubble_cap and _bubble_cap(property_key) or 5
                if item_backend_id then
                    -- Single weapon: one layer. Keep the first `cap` entries.
                    local n = #arr
                    if n > cap then
                        printf("[cim #86] grid over-occupancy: key=%s slots=%d > cap=%d (weapon) — trimming to %d",
                            tostring(property_key), n, cap, cap)
                        for i = n, cap + 1, -1 do arr[i] = nil end
                    end
                else
                    -- Amulet: cap per accessory layer, preserve click order.
                    local per_layer, kept, trimmed = {}, {}, false
                    for _, idx in ipairs(arr) do
                        local layer = math.ceil(idx / _AMULET_LAYER_SIZE)
                        local c = per_layer[layer] or 0
                        if c < cap then
                            per_layer[layer] = c + 1
                            kept[#kept + 1] = idx
                        else
                            trimmed = true
                        end
                    end
                    if trimmed then
                        printf("[cim #86] grid over-occupancy: key=%s slots=%d > cap=%d/layer (amulet) — trimming to %d",
                            tostring(property_key), #arr, cap, #kept)
                        for i = #arr, 1, -1 do arr[i] = nil end
                        for i = 1, #kept do arr[i] = kept[i] end
                    end
                end
            end
        end
        return props
    end

    -- ============================================================
    -- Movespeed buff scaling — 2pct toggle apply path patch
    -- ============================================================
    -- Vanilla's `apply_buff_tweak_data` (buff_utils.lua:13-21) runs at engine
    -- load and merges `buff_tweak_data.properties_movespeed = { multiplier = 1.05 }`
    -- into `WeaponProperties.buff_templates.properties_movespeed.buffs[1]`. That
    -- static multiplier short-circuits the variable-value lerp in
    -- buff_extension.lua:200-237 — vanilla movespeed is binary, applied = +5%,
    -- not applied = no buff.
    --
    -- For the `movespeed_2pct_mode` toggle to actually scale per-bubble (1 bubble
    -- = +2%, 5 bubbles = +10%) we need the lerp path to fire. The lerp uses
    -- `variable_multiplier_table = { min, max }` and computes
    -- `multiplier = math.lerp(min, max, variable_value)`. So setting
    -- `variable_multiplier = { 1.0, 1.10 }` with stored values 0.2 / 0.4 / 0.6
    -- / 0.8 / 1.0 yields multipliers 1.02 / 1.04 / 1.06 / 1.08 / 1.10 — exactly
    -- the +2% / +4% / +6% / +8% / +10% the user wants.
    --
    -- When toggle is OFF, restore the vanilla static `multiplier = 1.05` so the
    -- buff still applies at +5% for the default 1-bubble case.
    --
    -- Called: once on mod load, once on every VMF setting change.
    local function _patch_movespeed_buff()
        local WP = rawget(_G, "WeaponProperties")
        local tpl = WP and WP.buff_templates and WP.buff_templates.properties_movespeed
        local sub = tpl and tpl.buffs and tpl.buffs[1]
        if not sub then return end
        if mod:get("movespeed_2pct_mode") then
            sub.multiplier = nil
            sub.variable_multiplier = { 1.0, 1.10 }
        else
            sub.multiplier = 1.05
            sub.variable_multiplier = nil
        end
    end

    -- Apply once at mod load (the buff template is already populated by vanilla
    -- at engine boot, so this just rewrites the multiplier shape).
    _patch_movespeed_buff()

    local _settings_runtime = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_settings_runtime")
    _settings_runtime.install(mod, _patch_movespeed_buff, printf)

    local function _seed_one_item(item, props_out, traits_out, slot_index)
        if not item then return end
        local layer_offset = (slot_index - 1) * _AMULET_LAYER_SIZE
        if item.properties then
            local wp = rawget(_G, "WeaveProperties")
            local wp_props = wp and wp.properties
            local policy = mod._cim959_accessory_property_policy
            local next_slot = layer_offset + 1
            for prop_key, value in pairs(item.properties) do
                local weave_key = "weave_" .. prop_key
                if wp_props and wp_props[weave_key] then
                    -- #959: APPEND into the shared amulet aggregate (assignment
                    -- here overwrote sibling-accessory indices for the same key on
                    -- every reopen), clamped to this accessory's ten-slot layer.
                    next_slot = policy.seed_property_indices(
                        props_out, weave_key, next_slot, _bubbles_for_value(weave_key, value),
                        layer_offset, _AMULET_LAYER_SIZE, printf)
                else
                    mod:info("Forge seed: no weave mapping for prop '%s' (tried '%s')", prop_key, weave_key)
                end
            end
        end
        if item.traits and item.traits[1] then
            local wt = rawget(_G, "WeaveTraits")
            local wt_traits = wt and wt.traits
            local trait_key = item.traits[1]
            local weave_key = "weave_" .. trait_key
            if wt_traits and wt_traits[weave_key] then
                traits_out[weave_key] = slot_index
            else
                mod:info("Forge seed: no weave mapping for trait '%s' (tried '%s')", trait_key, weave_key)
            end
        end
    end

    local function _forge_seed_item(career_name, item_backend_id)
        local key = (career_name or "") .. "|" .. (item_backend_id or "")
        if _get_forge_item_props()[key] then return _get_forge_item_props()[key] end

        local props = {}
        local traits = {}
        local items_backend = Managers.backend:get_interface("items")

        if item_backend_id then
            -- Single-item case: weapon (melee/ranged) editor.
            local item = items_backend and items_backend:get_item_from_id(item_backend_id)
            if item then _seed_one_item(item, props, traits, 1) end
        elseif items_backend and career_name then
            -- Amulet case: aggregate the three equipped accessories into one
            -- bubble grid (charm=layer 1, necklace=layer 2, trinket=layer 3).
            for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
                local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                local item = bid and items_backend:get_item_from_id(bid)
                _seed_one_item(item, props, traits, slot_index)
            end
            -- #959 evidence: bounded per-key layer census per Athanor open.
            mod._cim959_accessory_property_policy.log_seed_census(
                props, _AMULET_LAYER_SIZE, printf)
        end

        _get_forge_item_props()[key] = {properties = props, traits = traits}
        return _get_forge_item_props()[key]
    end

    -- Amulet apply: bubble-grid edits live under the (career, nil) key. Each
    -- property's slot indices span 1..30 — layer N (size 10) = accessory N.
    -- Group per-layer fills, convert back to fractional values, write to each
    -- accessory's `item.properties` / `item.traits` (and persist if modded).
    local function _forge_apply_to_amulet(career_name)
        local key = (career_name or "") .. "|"
        local data = _get_forge_item_props()[key]
        if not data then return end

        local items_backend = Managers.backend:get_interface("items")
        if not items_backend then return end

        -- Group property fills by layer (= accessory slot 1/2/3). Per-property
        -- caps via `_value_for_bubbles` handle stamina/movespeed tier-snapping;
        -- everything else stays on the linear count/5 mapping.
        local per_slot_props = { {}, {}, {} }
        for weave_key, slot_indices in pairs(data.properties or {}) do
            local prop_key = _strip_weave(weave_key)
            local layer_counts = { 0, 0, 0 }
            for _, idx in ipairs(slot_indices) do
                local layer = math.ceil(idx / _AMULET_LAYER_SIZE)
                if layer >= 1 and layer <= 3 then
                    layer_counts[layer] = layer_counts[layer] + 1
                end
            end
            for layer, count in ipairs(layer_counts) do
                if count > 0 then
                    per_slot_props[layer][prop_key] = _value_for_bubbles(weave_key, count)
                end
            end
        end

        -- Map traits by slot index → accessory
        local per_slot_trait = {}
        for weave_key, slot_index in pairs(data.traits or {}) do
            if slot_index >= 1 and slot_index <= 3 then
                per_slot_trait[slot_index] = weave_key:gsub("^weave_", "")
            end
        end

        -- Apply to each accessory
        for slot_index, slot_name in ipairs(_AMULET_SLOT_BY_INDEX) do
            local bid = items_backend:get_loadout_item_id(career_name, slot_name)
            local item = bid and items_backend:get_item_from_id(bid)
            if item then
                local new_props = per_slot_props[slot_index] or {}
                local new_traits = per_slot_trait[slot_index] and { per_slot_trait[slot_index] } or {}
                item.properties = new_props
                item.traits = new_traits

                local cjson_mod = rawget(_G, "cjson")
                if cjson_mod and item.CustomData then
                    item.CustomData.properties = cjson_mod.encode(new_props)
                    item.CustomData.traits = cjson_mod.encode(new_traits)
                end

                local saved = _get_forged_weapons()[bid]
                if saved then
                    saved.properties = new_props
                    saved.traits = new_traits
                    saved.trait = new_traits[1]
                    saved.external_traits = {}
                    _forge_save()
                end
            end
        end
    end

    local function _forge_item_draft_payload(career_name, item_backend_id)
        if not item_backend_id then return nil end
        local data = _forge_seed_item(career_name, item_backend_id)
        return state.temper_transaction.payload_from_grid(
            data, _strip_weave, _value_for_bubbles)
    end

    local function _discard_item_draft(career_name, item_backend_id)
        if not item_backend_id then return false end
        local key = (career_name or "") .. "|" .. item_backend_id
        local registry = _get_forge_item_props()
        local existed = registry[key] ~= nil
        registry[key] = nil
        return existed
    end

    local function _shallow_copy(source)
        local copy = {}
        if type(source) == "table" then
            for key, value in pairs(source) do copy[key] = value end
        end
        return copy
    end

    -- Build a detached presentation candidate without touching either live
    -- surface.  BackendInterfaceItemPlayfab may expose a deep-cloned cache
    -- rather than PlayFabMirrorBase._inventory_items itself, so Apply must
    -- prepare one candidate per distinct row.  CustomData keeps its table
    -- identity on publication; only the two encoded payload fields change.
    local function _item_apply_candidate(source, payload, encode)
        if type(source) ~= "table" then return nil, nil, "item" end

        local candidate = _shallow_copy(source)
        if type(source.CustomData) == "table" then
            candidate.CustomData = _shallow_copy(source.CustomData)
        end

        -- Retain the transaction policy's template/admission semantics, but do
        -- not let it encode yet: encoding below is protected and performed
        -- exactly once per distinct presentation surface.
        local applied, ok, changed = pcall(
            state.temper_transaction.apply_to_item,
            candidate, payload, nil)
        if not applied then
            return nil, nil, "apply_exception:" .. tostring(ok)
        end
        if not ok then return nil, nil, changed end

        local copied, normalized = pcall(
            state.temper_transaction.copy_payload, payload)
        if not copied then
            return nil, nil, "copy_exception:" .. tostring(normalized)
        end
        if type(normalized) ~= "table"
                or type(normalized.properties) ~= "table"
                or type(normalized.traits) ~= "table" then
            return nil, nil, "copy_rejected"
        end

        -- Always detach the published arrays/maps.  This prevents the mirror,
        -- item-interface cache, forge draft and persisted record from sharing a
        -- mutable table even when one of those surfaces was already up to date.
        candidate.properties = normalized.properties
        candidate.traits = normalized.traits

        local custom_changed = false
        if type(candidate.CustomData) == "table" then
            if type(encode) ~= "function" then
                return nil, nil, "json_encoder_unavailable"
            end
            local props_called, encoded_properties = pcall(
                encode, normalized.properties)
            if not props_called then
                return nil, nil, "encode_properties_exception:"
                    .. tostring(encoded_properties)
            end
            local traits_called, encoded_traits = pcall(
                encode, normalized.traits)
            if not traits_called then
                return nil, nil, "encode_traits_exception:"
                    .. tostring(encoded_traits)
            end
            custom_changed = source.CustomData.properties ~= encoded_properties
                or source.CustomData.traits ~= encoded_traits
            candidate.CustomData.properties = encoded_properties
            candidate.CustomData.traits = encoded_traits
        end

        return candidate, changed == true or custom_changed, nil
    end

    local function _publish_item_candidate(target, candidate)
        rawset(target, "properties", candidate.properties)
        rawset(target, "traits", candidate.traits)
        if type(target.CustomData) == "table"
                and type(candidate.CustomData) == "table" then
            rawset(target.CustomData, "properties",
                candidate.CustomData.properties)
            rawset(target.CustomData, "traits",
                candidate.CustomData.traits)
        end
    end

    -- `_forge_save(candidate)` only clones the detached registry into VMF's
    -- settings store; it has no item-backend side effects.  On rejection or an
    -- exception, leave mirror authority and the item-interface cache bit-for-bit
    -- untouched.  Calling native `_refresh` here would rebuild/replace that
    -- cache and violate the retry transaction instead of containing it.
    local function _save_failure_reason(called, result, reason)
        return called
            and "save_rejected:" .. tostring(reason or result)
            or "save_exception:" .. tostring(result)
    end

    local function _forge_apply_to_item(career_name, item_backend_id)
        if not item_backend_id then
            _forge_apply_to_amulet(career_name)
            return true, false
        end
        local items_backend = Managers.backend:get_interface("items")
        local item = items_backend and items_backend:get_item_from_id(item_backend_id)
        if not item then return false, "item" end

        local raw_called, raw_item = pcall(
            state.get_raw_mirror_item, item_backend_id)
        if not raw_called then
            return false, "raw_mirror_accessor_exception:" .. tostring(raw_item)
        end
        if type(raw_item) ~= "table" then
            return false, "raw_mirror_item"
        end

        local payload = _forge_item_draft_payload(career_name, item_backend_id)
        if not payload then return false, "draft" end

        local forged_weapons = _get_forged_weapons()
        local saved = forged_weapons[item_backend_id]
        if type(saved) ~= "table" then return false, "saved_record" end

        local cjson_mod = rawget(_G, "cjson")
        local encode = cjson_mod and cjson_mod.encode

        local candidate_item, item_changed, item_error =
            _item_apply_candidate(item, payload, encode)
        if not candidate_item then return false, item_error end

        local candidate_raw, raw_changed
        if raw_item == item then
            candidate_raw, raw_changed = candidate_item, item_changed
        else
            local raw_error
            candidate_raw, raw_changed, raw_error =
                _item_apply_candidate(raw_item, payload, encode)
            if not candidate_raw then return false, raw_error end
        end

        local copied, saved_payload = pcall(
            state.temper_transaction.copy_payload, payload)
        if not copied then
            return false, "copy_exception:" .. tostring(saved_payload)
        end
        if type(saved_payload) ~= "table" then
            return false, "copy_rejected"
        end
        local candidate_saved = _shallow_copy(saved)
        candidate_saved.properties = saved_payload.properties
        candidate_saved.traits = saved_payload.traits
        candidate_saved.trait = saved_payload.traits[1]
        candidate_saved.external_traits = {}

        local dirty_called, saved_changed = pcall(
            state.temper_transaction.is_dirty, saved, saved_payload)
        if not dirty_called then
            return false, "dirty_exception:" .. tostring(saved_changed)
        end
        saved_changed = saved_changed == true
            or saved.trait ~= candidate_saved.trait
            or (type(saved.external_traits) == "table"
                and next(saved.external_traits) ~= nil)

        if not item_changed and not raw_changed and not saved_changed then
            return true, false
        end

        local candidate_registry = _shallow_copy(forged_weapons)
        candidate_registry[item_backend_id] = candidate_saved

        -- One bounded persistence write at Apply, never one per bubble click.
        -- `save` accepts an alternate source, so the canonical owner store and
        -- the live backend row are still byte-for-byte prior state here.
        local save_called, save_result, save_reason = pcall(
            _forge_save, candidate_registry)
        if not save_called or save_result == false then
            return false, _save_failure_reason(save_called, save_result,
                save_reason)
        end

        -- Publish the raw backend authority first and its item-interface cache
        -- second.  Both rows retain their exact identity and ownership stamps;
        -- only the normalized mutable payload changes.  A later native refresh
        -- therefore reproduces, rather than reverts, the applied item.
        _publish_item_candidate(raw_item, candidate_raw)
        if item ~= raw_item then
            _publish_item_candidate(item, candidate_item)
        end
        rawset(saved, "properties", candidate_saved.properties)
        rawset(saved, "traits", candidate_saved.traits)
        rawset(saved, "trait", candidate_saved.trait)
        rawset(saved, "external_traits", candidate_saved.external_traits)
        return true, true
    end

    mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_properties", function(func, self, career_name, item_backend_id)
        if _is_active() then
            local data = _forge_seed_item(career_name, item_backend_id)
            -- #86 read-path guard: trim each property array to its bubble cap at the
            -- exact point vanilla _sync_backend_loadout reads it to build grid
            -- occupancy. Catches any over-fill the write-path cap missed.
            _cap_grid_property_arrays(data.properties, item_backend_id)
            return data.properties
        end
        return func(self, career_name, item_backend_id)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_traits", function(func, self, career_name, item_backend_id)
        if _is_active() then
            local data = _forge_seed_item(career_name, item_backend_id)
            return data.traits
        end
        return func(self, career_name, item_backend_id)
    end)

    -- Adventure-talent helpers. The amulet UI's talent picker runs against the
    -- weave talent system, but `WeaveLoadoutSettings[career].talent_tree` is
    -- literally `TalentTrees[profile][index]` (see weave_loadout_settings_*.lua),
    -- i.e. the same tree adventure mode uses. So we can map the player's
    -- adventure picks (numeric column 1..3 per row) into the
    -- `{[talent_name] = row}` shape the bubble grid expects.
    local function _get_career_talent_tree(career_name)
        local cs = CareerSettings[career_name]
        if not cs then return nil end
        local TalentTrees = rawget(_G, "TalentTrees")
        if not TalentTrees then return nil end
        local tree = TalentTrees[cs.profile_name]
        return tree and tree[cs.talent_tree_index]
    end

    mod:hook("BackendInterfaceWeavesPlayFab", "get_loadout_talents", function(func, self, career_name)
        if not _is_active() then return func(self, career_name) end
        local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
        if not talents_iface then return {} end
        local picks = talents_iface:get_talents(career_name)
        if not picks then return {} end
        local tree = _get_career_talent_tree(career_name)
        if not tree then return {} end

        local result = {}
        for row, pick in ipairs(picks) do
            local row_talents = tree[row]
            if row_talents and pick and row_talents[pick] then
                result[row_talents[pick]] = row
            end
        end
        return result
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_mastery", function(func, self, career_name, item_backend_id)
        if _is_active() then return 0, 0 end
        local ok, a, b = pcall(func, self, career_name, item_backend_id)
        if ok then return a, b end
        return 0, 0
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
        if mod._cim_autodump_property_write then
            pcall(mod._cim_autodump_property_write, "set_property", career_name, property_key, slot_index, item_backend_id)
        end
        if _is_active() then
            local data = _forge_seed_item(career_name, item_backend_id)
            local props = data.properties
            local accessory_policy = mod._cim959_accessory_property_policy
            local layer_size = item_backend_id == nil and _AMULET_LAYER_SIZE or nil
            -- Ten slots cap distinct keys globally for a weapon and per accessory
            -- layer for the amulet editor (user request 2026-06-29).
            --
            -- Why 2 was the old value: vanilla's HeroWindowItemCustomization
            -- Apply-Skin preview indexes `content["button_hotspot_" .. N]` per
            -- property (hero_window_item_customization.lua:1210-1213); the widget
            -- only ships hotspots 1 and 2, so a 3rd distinct key used to crash that
            -- view ("attempt to index a nil value"). That crash is now INDEPENDENTLY
            -- guarded by cim's replacement `_update_property_option` hook
            -- (standard_forge.lua:192-220), which skips writes for missing hotspot
            -- widgets. With that guard in place the >2 ceiling is no longer load-
            -- bearing — extra properties simply aren't surfaced in that one preview
            -- tab, but they still apply to the buff system and render in the weave
            -- grid. So we can safely open the gate to the full 10-slot grid.
            local MAX_DISTINCT_PROPERTIES = 10
            local property_present_in_scope = accessory_policy.property_present_in_scope(
                props[property_key], slot_index, layer_size)
            if not property_present_in_scope then
                local distinct_in_layer = accessory_policy.count_distinct_properties(
                    props, slot_index, layer_size)
                if distinct_in_layer >= MAX_DISTINCT_PROPERTIES then
                    -- Use mod:warning (not mod:echo) so the user always sees WHY
                    -- their click was rejected. `mod:echo` is silenced unless
                    -- `enable_debug_logging` is on; warnings always surface to chat.
                    -- Without visible feedback this looks like "I clicked, nothing
                    -- happened, mod's broken" — root cause of user report
                    -- 2026-05-25 (issue #47).
                    mod:warning(string.format(
                        "[cim] Max %d distinct properties per %s. Remove one to add %s.",
                        MAX_DISTINCT_PROPERTIES,
                        item_backend_id and "item" or "accessory",
                        _strip_weave(property_key)))
                    return
                end
                if not props[property_key] then props[property_key] = {} end
            end
            -- v0.7.44-alpha: per-property bubble cap rejection REMOVED (issue #49).
            -- Previously: clicks beyond `_bubble_cap(property_key)` for stamina (2)
            -- and movespeed (1) were silently rejected by this hook. The vanilla
            -- bubble grid still showed all 10 slots as clickable, so users would
            -- click "free" slots that did nothing, see no fill, and conclude the
            -- mod was broken. User report 2026-05-25 framed it as stamina/movespeed
            -- "blocking" other properties — really the silent rejection masking a
            -- click that the UI invited.
            --
            -- The game-effect value is still clamped at 1.0 by `_value_for_bubbles`
            -- (lines ~2003) — for stamina cap=2, count>=2 returns 1.0 (= +2 tier);
            -- for movespeed cap=1, count>=1 returns 1.0 (= +5%). So extra clicks
            -- write redundantly to the same value but bubbles fill in the UI and
            -- the user gets the visual feedback they expect.
            --
            -- Known inconsistency: on session reload, `_bubbles_for_value` seeds
            -- only the engine-max bubble count (2 for stamina, 1 for movespeed)
            -- from the persisted value, so "I had 5 stamina bubbles filled" loads
            -- back as 2. The game-effect value (+2 stamina) is correct throughout;
            -- only the displayed bubble count compresses on reload. Documented in
            -- CHANGELOG; full fix would need to persist click-count separately.
            --
            -- The distinct-property cap above (MAX_DISTINCT_PROPERTIES = 2) stays
            -- — it's a vanilla-crash gate for HeroWindowItemCustomization's
            -- Apply-Skin preview (only ships widgets for `button_hotspot_1` / `_2`).
            --
            -- v0.7.55-dev (issue #49 take 2): cap the slot_index array length at
            -- `_bubble_cap(property_key)`. Without this, vanilla's property picker
            -- auto-writes all 5 slot_indices when stamina is selected (each
            -- bubble click → one set_loadout_property call). v0.7.44 removed the
            -- per-click REJECTION so the visual bubble grid renders correctly
            -- (2 filled for stamina because `_value_for_bubbles` clamps), BUT
            -- the underlying props.stamina array now holds 5 slot_indices, which
            -- the inventory render treats as "5 of 10 slots used by stamina" —
            -- blocking a second property from being added even though
            -- MAX_DISTINCT_PROPERTIES would otherwise allow it.
            -- Fix: silently cap the array at the engine bubble cap. Visible
            -- bubble count is unchanged (still 2 for stamina, 1 for movespeed);
            -- only the persisted array is trimmed so the second-property slot
            -- accounting frees up. User report 2026-05-27 EOD framed it as
            -- "WHEN APPLIED IT TAKES 5" — matches this fix.
            -- v0.8.28-dev (#86 take 4 — the persisted-ARRAY over-occupancy bug,
            -- TRACED not assumed): the GRID's slot accounting is driven by the
            -- VALUES in this array, not by the visible bubble count. Vanilla
            -- `_sync_backend_loadout` (hero_window_weave_properties.lua:1553-1556)
            -- does `for _, slot_index in ipairs(slot_indices) do
            -- properties_index_map[slot_index] = key end` — EACH entry in
            -- `props[property_key]` marks ONE grid slot occupied. So a property
            -- occupies exactly `#props[property_key]` grid slots; any entry beyond
            -- its real use-count steals a slot another property could fill.
            -- Movespeed (cap 1) must hold exactly ONE slot_index, stamina (cap 2)
            -- two — and the store now re-applies vanilla's two dropped guards
            -- (cross-property collision + per-property use cap) via the shared
            -- `_store_property_slot` helper. The autodump below logs the resulting
            -- array length so the divergence is visible in-log without trusting the
            -- display. NOTE: with `movespeed_2pct_mode` ON, `_bubble_cap` returns 5
            -- for movespeed by design — it then legitimately occupies up to 5 slots
            -- (each +2%). That CONFIG, not this code, is the only path where
            -- movespeed consumes more than one slot.
            local cap = _bubble_cap and _bubble_cap(property_key) or 5
            local arr = _store_property_slot(props, property_key, slot_index, layer_size)
            if mod._cim_autodump_property_array then
                pcall(mod._cim_autodump_property_array, "set_property", property_key, arr, cap, layer_size)
            end
            if not item_backend_id then _mark_amulet_property_dirty(slot_index) end
            if not item_backend_id then _forge_apply_to_item(career_name, nil) end
            return
        end
        return func(self, career_name, property_key, slot_index, item_backend_id)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_property", function(func, self, career_name, property_key, slot_index, item_backend_id)
        if mod._cim_autodump_property_write then
            pcall(mod._cim_autodump_property_write, "remove_property", career_name, property_key, slot_index, item_backend_id)
        end
        if _is_active() then
            local data = _forge_seed_item(career_name, item_backend_id)
            local slots = data.properties[property_key]
            if slots then
                for i, s in ipairs(slots) do
                    if s == slot_index then
                        table.remove(slots, i)
                        break
                    end
                end
                if #slots == 0 then
                    data.properties[property_key] = nil
                end
            end
            if not item_backend_id then _mark_amulet_property_dirty(slot_index) end
            if not item_backend_id then _forge_apply_to_item(career_name, nil) end
            return
        end
        return func(self, career_name, property_key, slot_index, item_backend_id)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_trait", function(func, self, career_name, trait_key, slot_index, item_backend_id)
        if mod._cim_autodump_property_write then
            pcall(mod._cim_autodump_property_write, "set_trait", career_name, trait_key, slot_index, item_backend_id)
        end
        if _is_active() then
            local data = _forge_seed_item(career_name, item_backend_id)
            data.traits[trait_key] = slot_index
            if not item_backend_id then _mark_amulet_trait_dirty(slot_index) end
            if not item_backend_id then _forge_apply_to_item(career_name, nil) end
            return
        end
        return func(self, career_name, trait_key, slot_index, item_backend_id)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_trait", function(func, self, career_name, trait_key, item_backend_id)
        if mod._cim_autodump_property_write then
            pcall(mod._cim_autodump_property_write, "remove_trait", career_name, trait_key, nil, item_backend_id)
        end
        if _is_active() then
            local data = _forge_seed_item(career_name, item_backend_id)
            local removed_slot = data.traits[trait_key]
            data.traits[trait_key] = nil
            if not item_backend_id then _mark_amulet_trait_dirty(removed_slot) end
            if not item_backend_id then _forge_apply_to_item(career_name, nil) end
            return
        end
        return func(self, career_name, trait_key, item_backend_id)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "set_loadout_talent", function(func, self, career_name, talent_key, slot_index)
        if not _is_active() then return func(self, career_name, talent_key, slot_index) end
        local tree = _get_career_talent_tree(career_name)
        local row_talents = tree and tree[slot_index]
        if not row_talents then return end

        -- Find which column in row `slot_index` this talent_key is.
        local column
        for c, t_name in ipairs(row_talents) do
            if t_name == talent_key then column = c; break end
        end
        if not column then return end

        local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
        if not talents_iface then return end

        local picks = talents_iface:get_talents(career_name)
        if not picks then picks = {} end
        -- Adventure expects 6 picks; default missing rows to column 1 to avoid
        -- nil entries when serialized.
        for i = 1, 6 do
            if not picks[i] then picks[i] = 1 end
        end
        picks[slot_index] = column
        talents_iface:set_talents(career_name, picks)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "remove_loadout_talent", function(func, self, career_name, talent_key)
        if not _is_active() then return func(self, career_name, talent_key) end
        -- No-op: the bubble grid emits remove → set on each pick swap. We commit
        -- the new pick in `set_loadout_talent` directly; vanilla expected pair
        -- semantics aren't needed because adventure rows always have one talent.
    end)

    state.exports = {
        bubble_cap = _bubble_cap,
        value_for_bubbles = _value_for_bubbles,
        store_property_slot = _store_property_slot,
        cap_grid_property_arrays = _cap_grid_property_arrays,
        item_draft_payload = _forge_item_draft_payload,
        apply_item_draft = _forge_apply_to_item,
        discard_item_draft = _discard_item_draft,
    }
    return state.exports
end

return install
