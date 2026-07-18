local mod = get_mod("gut_dev")
local _printf = rawget(_G, "printf") or function() end

-- ============================================================================
-- Mod Tweaker — HeroView SUB-STATE (KEEP path)
-- ============================================================================
-- A second presentation of the Mod Tweaker that lives INSIDE the already-open
-- hero_view as a sub-state (modeled on HeroViewStateCompendium / the old Armory
-- mod's HeroViewStateArmory), instead of as a standalone IngameUI view reached by
-- leaving + re-entering hero_view.
--
-- WHY THIS EXISTS (build 2, v0.2.57-dev). The standalone ModTweakerView
-- (_mod_tweaker_view.lua) exited via ingame_ui:transition_with_fade(...), which
-- RECREATES hero_view's renderer; VMF then re-injects Loremaster's Armoury's
-- armoury_atlas into the fresh renderer, a C-level fatal (crash 42c81d84), AND
-- the recreation dumped the player into the deprecated bare IngameView menu. A
-- HeroView sub-state never leaves hero_view and never recreates the renderer, so
-- it kills BOTH symptoms. The standalone view STAYS as the in-mission path (there
-- is no hero_view in a mission); this sub-state is the keep/inn path only.
--
-- The DATA / REGISTRY / DRAW / INPUT substance is ported verbatim from
-- _mod_tweaker_view.lua — only the lifecycle shell changes to the sub-state
-- contract (renderer borrowed from ctx, input read from the parent's shared
-- service, exit via parent:close_menu, no self-made input service / cursor push).

local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
local ordering = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_ordering")
local transactions = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_transaction")
local profiles = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_profiles")
local disabled_sections = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_disabled_sections")
local tab_labels = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_tab_labels")
local label_policy = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_label_policy")
local dx12_diag_module = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_dx12_fence630")
local dx12_diag = mod._gut_dx12_fence630

local UIRenderer = UIRenderer
local UISceneGraph = UISceneGraph
local math = math

-- ---------------------------------------------------------------
-- Registry access (through the controller — single source of truth)
-- ---------------------------------------------------------------

local function _mt()
    return mod.mod_tweaker
end

-- Depth-aware nested walk (gut's NESTED/controller categories). Flattens the tree
-- into `out` + a PARALLEL `depths` array so the drill-down detection logic can run
-- the SAME "next node is deeper" test the VMF flat path uses (VMF already ships a
-- `depth` field; gut's hand-authored tree does not, so we synthesize it here). A
-- node with sub_widgets is appended AND its children are appended at depth+1 — the
-- build loop then skips those children inline (a group collapses them; a non-group
-- parent gets a gear that drills into them).
local function _walk_nested(node, out, depths, d)
    if type(node) ~= "table" then return end
    if type(node.setting_id) == "string" then
        out[#out + 1] = node
        depths[#depths + 1] = d
    end
    if type(node.sub_widgets) == "table" then
        for i = 1, #node.sub_widgets do _walk_nested(node.sub_widgets[i], out, depths, d + 1) end
    end
    if type(node.widgets) == "table" then
        for i = 1, #node.widgets do _walk_nested(node.widgets[i], out, depths, d) end
    end
end

-- ---------------------------------------------------------------
-- VMF auto-discovery. Every installed VMF mod becomes a tab populated from its
-- REAL options, edited live on the real mod object. VMF ships as bytecode, so the
-- runtime shape was reverse-engineered (workflow 2026-06-18): mods are in
-- get_mod("VMF")._mods_unloading_order; each mod's FLATTENED widget list is in
-- get_mod("VMF").options_widgets_data, matched by list[1].mod_name. Field reads
-- are defensive (flat OR content-wrapped) + pcall-guarded so an unexpected shape
-- degrades gracefully instead of crashing — the [mt] debug dump reveals reality.
-- ---------------------------------------------------------------
local MAX_TABS = 8   -- tab nodes that fit the window width; >MAX => paginate

-- The Mod Tweaker is for the USER'S OWN mods only — there isn't room for a tab per
-- installed VMF mod. The shared policy owns this author's registration ids so the
-- standalone and keep-substate presentation paths cannot drift apart (#636).
-- verminious_dreams_lighting (+ _dev) are intentionally OMITTED — they keep their
-- own normal VMF menu and don't belong as a Mod Tweaker tab.
-- HideBuffs and Crosshair Kill Confirmation remain deliberately excluded; their
-- settings are integrated into gut's Interface tab below.

-- Third-party mod whose options fold into a gut category (NOT a tab). #339.
local _CKC_NAME = "Crosshair Kill Confirmation"

local function _nf(node, key)  -- defensive node-field read
    if type(node) ~= "table" then return nil end
    local v = node[key]
    if v == nil and type(node.content) == "table" then v = node.content[key] end
    return v
end

-- (#389) Keep-substate twin of the standalone Mod Tweaker slider registry.
local STEP_OVERRIDES = {
    cim = { base_power_level = 25 }, cim_dev = { base_power_level = 25 },
    ct = { starting_coins = 25 }, ct_dev = { starting_coins = 25 },
}

local function _resolve_step(node, mod_id, setting_id, dec)
    local field = _nf(node, "step")
    if type(field) == "number" and field > 0 then return field end
    local by_mod = mod_id and STEP_OVERRIDES[mod_id]
    local fixed = by_mod and setting_id and by_mod[setting_id]
    if type(fixed) == "number" and fixed > 0 then return fixed end
    return (dec and dec > 0) and (10 ^ -dec) or 1
end

local function _vmf_label(node, mod_obj)
    local t = _nf(node, "title") or _nf(node, "text") or _nf(node, "setting_id") or "?"
    if type(t) ~= "string" then return tostring(t) end
    -- Same "<...>" defence as _vmf_tooltip: VMF can freeze a "<key>" missing-marker into a
    -- title/text field. Strip it, re-localize the inner key now (all mods registered at render
    -- time), and NEVER surface a marker; fall back to the bare key text (a label must be non-nil).
    local inner = string.match(t, "^<(.-)>$")
    local key = inner or t
    if mod_obj and mod_obj.localize then
        local ok, s = pcall(mod_obj.localize, mod_obj, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then
            return label_policy.clean(s)
        end
    end
    return label_policy.clean(key)
end

-- (#207) The node's tooltip DESCRIPTION (the hover-popup body). In VMF widget data the
-- `tooltip` field is usually an ALREADY-localized display string (mods write
-- `tooltip = mod:localize("<id>_tooltip")` in their _data.lua), but it can occasionally be
-- a raw loc key — so mirror _vmf_label's pcall-localize and keep the localized result only
-- when it resolves cleanly (not a "<missing>" marker). Empty / absent tooltip -> nil (the
-- row then has no popup). Reads via _nf so it works for both flat (VMF) + nested (gut) nodes.
local function _vmf_tooltip(node, mod_obj)
    local t = _nf(node, "tooltip")
    if type(t) ~= "string" or t == "" then return nil end
    -- ROOT FIX for the recurring "<...>" in DESCRIPTIONS. VMF can FREEZE a missing-loc
    -- marker ("<key>") into node.tooltip when the tooltip key did not resolve at data-build
    -- time. The old code rejected re-localizing a "<...>" string but then FELL BACK to
    -- returning that same marker (the leak). Instead: strip the brackets to recover the key,
    -- re-localize it now (all mods are registered at render time), and NEVER surface a marker.
    local inner = string.match(t, "^<(.-)>$")   -- "<gut_x_tooltip>" -> "gut_x_tooltip"
    local key = inner or t
    if mod_obj and mod_obj.localize then
        local ok, s = pcall(mod_obj.localize, mod_obj, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then
            return s
        end
    end
    -- Could not localize. Never show a "<...>" marker as the description.
    if inner or string.find(t, "^<") then return nil end
    return t   -- raw value was already plain display text
end

-- (#208) Per-NODE owner resolution for the synthesized "Equipment" category, which merges
-- up to four inventory mods (Cosmetics / Crafting / Weapons / Career Weapon Variants) into
-- one tab. A normal category has a single `mod_obj`/`mod_id`; the Equipment category instead
-- carries `_owners[setting_id] = { mod_id, mod_obj }` for every member setting so get/set/
-- stage/apply route to the OWNING mod object. For every NON-Equipment category `_owners` is
-- nil, so this returns `category.mod_obj` / `category.mod_id` — byte-for-byte the prior path.
local function _owner(category, setting_id)
    local owners = category and category._owners
    if owners and setting_id ~= nil then
        local o = owners[setting_id]
        if o then return o.mod_obj, o.mod_id end
    end
    return category and category.mod_obj, category and category.mod_id
end

local function _cat_get(category, setting_id)
    local mod_obj, mod_id = _owner(category, setting_id)
    if mod_obj then
        local ok, v = pcall(mod_obj.get, mod_obj, setting_id)
        return ok and v or nil
    end
    local MT = _mt()
    return MT and MT:get(mod_id, setting_id)
end

local function _cat_set(category, setting_id, value)
    local mod_obj, mod_id = _owner(category, setting_id)
    if mod_obj then
        -- 3rd arg true => fire the mod's on_setting_changed so it reacts live
        -- (matches stock VMF options behaviour). Persistence is automatic.
        pcall(mod_obj.set, mod_obj, setting_id, value, true)
        return
    end
    local MT = _mt()
    if MT then MT:set(mod_id, setting_id, value) end
end

-- Native menu sound feedback. The real Options menu fires Wwise events on the
-- view's wwise_world: "Play_hud_select" on a commit (options_view.lua:544 etc.)
-- and "Play_hud_hover" on hover-enter (options_view.lua:423 etc.). We resolve a
-- wwise_world off the music_world (pcall-guarded; a missing world is silent, never
-- a crash). A one-time debug probe logs which worlds expose a usable wwise_world,
-- so if Play_hud_* are inaudible the log shows whether the handle resolved.
local _wwise_probed = false
local function _wwise_world()
    local world = Managers.world and Managers.world:world("music_world")
    return world and World.wwise_world(world)
end
local function _wwise_probe()
    if _wwise_probed then return end
    _wwise_probed = true
    pcall(function()
        local names = { "music_world", "top_ingame_view", "level_world" }
        for i = 1, #names do
            local w = Managers.world and Managers.world:has_world(names[i]) and Managers.world:world(names[i])
            local ww = w and World.wwise_world(w)
            mod:debug("[mt:wwise] world '%s' present=%s wwise_world=%s",
                names[i], tostring(w ~= nil), tostring(ww ~= nil))
        end
    end)
end
local function _play_event(event)
    pcall(function()
        local ww = _wwise_world()
        if ww then WwiseWorld.trigger_event(ww, event) end
    end)
end
-- Commit/click sound (checkbox flip, arrow click, dropdown cycle, slider release).
local function _play_click() _play_event("Play_hud_select") end
-- Hover sound — fire on the EDGE (hover-enter) only, never every frame.
local function _play_hover() _play_event("Play_hud_hover") end

-- ---------------------------------------------------------------
-- (#208) EQUIPMENT MERGE. The four inventory-management mods get folded into ONE
-- collapsible "Equipment" tab when 2+ are installed. Disabled members retain their
-- normal section header with no editable rows and a "Disabled in VMF" tooltip. Roles:
--   cosmetics_tweaker -> Cosmetics ; cim/cim_dev -> Crafting ; wt/wt_dev -> Weapons ;
--   character_weapon_variants -> Career Weapon Variants.
-- Sections render top-level (Cosmetics, Crafting, Weapons); CWV nests UNDER Weapons
-- when wt/wt_dev is also active, else sits top-level. N=1-only-CWV just relabels that one tab
-- "Weapons". The synthesized category is FLAT (_flat=true) with a parallel `_depths`
-- array (so each member keeps its own internal group/gear nesting, shifted under its
-- section header) + a `_owners[setting_id]` map so get/set/stage/apply route per-node to
-- the owning mod object (see _owner + the staged-change helpers). TWIN of the standalone
-- view's identical block — keep both in sync.
-- ---------------------------------------------------------------
-- Localize a gut_dev section/tab label; reject a "<missing-key>" marker + fall back to a
-- literal (same guard as _vmf_label). Safe at _rebuild time (loc is registered by then).
local function _equip_loc(key, fallback)
    if mod and mod.localize then
        local ok, s = pcall(mod.localize, mod, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then return s end
    end
    return fallback
end

-- Post-process the _vmf_categories() output (called just before its final sort).
local function _synthesize_equipment(cats)
    local members, n = disabled_sections.select_equipment_members(cats)
    if n == 0 then return cats end

    if n == 1 then
        -- Only the CWV-alone case changes: its single tab is relabeled "Weapons".
        if members.cwv then members.cwv.label = _equip_loc("gut_equip_weapons", "Weapons") end
        return cats
    end

    -- N >= 2: build the merged Equipment category; drop the folded members from the list.
    local folded = {}
    for _, c in pairs(members) do folded[c] = true end
    local rest = {}
    for _, c in ipairs(cats) do if not folded[c] then rest[#rest + 1] = c end end

    local widgets, depths, owners = {}, {}, {}
    local owner_ids, owner_seen = {}, {}
    local function _note_owner(mid)
        if not owner_seen[mid] then owner_seen[mid] = true; owner_ids[#owner_ids + 1] = mid end
    end
    -- One synthetic collapsible group header at `header_depth` (owns no setting).
    local function _add_header(setting_id, label, header_depth, enabled)
        widgets[#widgets + 1] = enabled == false
            and disabled_sections.disabled_header(setting_id, label, header_depth,
                _equip_loc("gut_disabled_in_vmf", disabled_sections.REASON))
            or { setting_id = setting_id, type = "group", title = label }
        depths[#depths + 1] = header_depth
    end
    -- A member's setting nodes (skipping its synthesized VMF header at [1]), rebased so the
    -- member's SHALLOWEST node renders at `target_top_depth` (one level under its section
    -- header), with internal nesting preserved. Records each node's owner.
    local function _add_member(member, target_top_depth)
        if not member or member.enabled == false then return end
        local src = member and member.widgets
        if type(src) ~= "table" then return end
        -- VMF mods' top content usually sits at NATURAL depth 1 (not 0), so blindly adding a
        -- base offset lands it a level too deep — which is why the nested CWV header (correctly
        -- at depth 1) looked un-indented beside wt's content (wrongly at depth 2). Rebase by the
        -- member's OWN minimum natural depth: its shallowest node renders exactly at
        -- target_top_depth (one level under its section header), preserving internal nesting. (#208)
        local min_d
        for i = 2, #src do
            local nd = _nf(src[i], "depth") or 0
            if not min_d or nd < min_d then min_d = nd end
        end
        min_d = min_d or 0
        for i = 2, #src do
            local node = src[i]
            widgets[#widgets + 1] = node
            depths[#depths + 1] = target_top_depth + ((_nf(node, "depth") or 0) - min_d)
            local sid = _nf(node, "setting_id")
            if type(sid) == "string" then
                owners[sid] = { mod_id = member.mod_id, mod_obj = member.mod_obj }
                _note_owner(member.mod_id)
            end
        end
    end

    -- Section order: Cosmetics -> Crafting -> Weapons (deliberate-order exception).
    if members.cosmetics then
        _add_header("__equip_cosmetics", _equip_loc("gut_equip_cosmetics", "Cosmetics"), 0,
            members.cosmetics.enabled)
        _add_member(members.cosmetics, 1)
    end
    if members.crafting then
        _add_header("__equip_crafting", _equip_loc("gut_equip_crafting", "Crafting"), 0,
            members.crafting.enabled)
        _add_member(members.crafting, 1)
    end
    if members.weapons then
        local weapons_header_enabled = members.weapons.enabled ~= false
            or (members.cwv and members.cwv.enabled ~= false)
        _add_header("__equip_weapons", _equip_loc("gut_equip_weapons", "Weapons"), 0,
            weapons_header_enabled)
        _add_member(members.weapons, 1)
        if members.cwv then
            -- CWV nested UNDER Weapons (header depth 1, its settings depth 2+).
            _add_header("__equip_cwv", _equip_loc("gut_equip_cwv", "Career Weapon Variants"), 1,
                members.cwv.enabled)
            _add_member(members.cwv, 2)
        end
    elseif members.cwv then
        -- No wt/wt_dev: CWV sits at the TOP LEVEL of Equipment (no Weapons wrapper).
        _add_header("__equip_cwv", _equip_loc("gut_equip_cwv", "Career Weapon Variants"), 0,
            members.cwv.enabled)
        _add_member(members.cwv, 1)
    end

    rest[#rest + 1] = {
        mod_id = "gut_equipment",
        label = _equip_loc("gut_equip_tab", "Equipment"),
        widgets = widgets,
        _depths = depths,             -- parallel depth array (consumed by _build_rows)
        _owners = owners,             -- setting_id -> { mod_id, mod_obj } (consumed by _owner)
        _owner_mod_ids = owner_ids,   -- member mod_ids (dirty-check + apply iteration)
        mod_obj = nil,                -- spans multiple mods; per-node ownership via _owners
        enabled = true,
        _flat = true,
    }
    return rest
end

-- (#339) Fold Crosshair Kill Confirmation's live options INTO gut's "Interface" tab
-- under the HUD group, as a "Crosshair Kill Confirmation" sub-collapsible -- NOT a
-- top-level tab (the mistake #313 made). Reuses the _synthesize_equipment `_owners`
-- mechanism to route CKC nodes to the real CKC mod, but MUTATES the existing gut
-- category instead of appending a new one. See MOD_TWEAKER_INTEGRATION.md.
--
-- Correctness notes (traps handled):
--   * NEVER mutate VMF's own list in place (it is reused every _rebuild) -- gut's widget
--     array is COPIED and CKC's nodes are shallow-COPIED before stamping depth.
--   * gut's category is MIXED-owner (its own settings + injected CKC settings), so
--     _owner_mod_ids MUST include BOTH gut's id and CKC -- else apply/dirty (which take
--     the `if _owner_mod_ids` branch) would flush ONLY CKC and silently drop every gut
--     Interface edit. mod_obj stays = gut so gut's own settings fall back via _owner.
--   * gut's category is _flat=true; the flat render path reads each node's own `depth`
--     (rebased by the tab's min depth), so injected nodes MUST carry a `depth` in gut's
--     natural depth space (HUD group depth + 1 for the sub-header, +2 for its options).
-- This function is kept byte-parallel with the twin in _mod_tweaker_view.lua.
local function _inject_ckc_into_gut(out)
    local ckc = get_mod(_CKC_NAME)
    if not ckc then return end                        -- CKC not installed: nothing to fold
    local gut_cat
    for _, c in ipairs(out) do
        if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
    end
    if not gut_cat or type(gut_cat.widgets) ~= "table" then return end

    local vmf = get_mod("VMF")
    local wd = vmf and vmf.options_widgets_data
    if type(wd) ~= "table" then return end
    local ckc_list
    for _, list in ipairs(wd) do
        local h = (type(list) == "table") and list[1]
        if h and _nf(h, "mod_name") == _CKC_NAME then ckc_list = list; break end
    end
    if type(ckc_list) ~= "table" or #ckc_list < 2 then return end  -- no real options

    -- Locate the HUD group node in gut's flat list.
    local src = gut_cat.widgets
    local hud_idx, hud_depth
    for i = 1, #src do
        if _nf(src[i], "setting_id") == "gut_hide_hud_ui_group" then
            hud_idx = i; hud_depth = _nf(src[i], "depth") or 0; break
        end
    end
    if not hud_idx then return end
    -- (#527) [CKC-SPLICE-FIRST-527] The block splices at the START of the HUD child
    -- block (immediately after the HUD group header), not the end: collapsible
    -- sub-groups sort FIRST at their level (user doctrine, issue 527), and
    -- "Crosshair Kill Confirmation" precedes "UI Tweaks" A-Z, so the head of the
    -- block IS its alphabetical slot among the HUD sub-groups.
    local ins_idx = hud_idx + 1

    -- Build the CKC sub-group block: a group header at HUD+1, CKC options rebased to HUD+2.
    -- Title is the mod's proper name as a literal (a non-key string): _vmf_label localizes
    -- against gut, gets a "<...>" miss, and falls back to this literal. Keeps the injection
    -- self-contained without editing gut's loc file.
    local block = { { setting_id = "gut_ckc_group", type = "group",
                      title = _CKC_NAME, depth = hud_depth + 1 } }
    local ckc_min
    for i = 2, #ckc_list do
        local d = _nf(ckc_list[i], "depth") or 0
        if not ckc_min or d < ckc_min then ckc_min = d end
    end
    ckc_min = ckc_min or 0
    local owners = gut_cat._owners or {}
    for i = 2, #ckc_list do
        local node = ckc_list[i]
        local nn = {}                                 -- shallow copy (never mutate VMF's node)
        for k, v in pairs(node) do nn[k] = v end
        nn.depth = hud_depth + 2 + ((_nf(node, "depth") or 0) - ckc_min)
        block[#block + 1] = nn
        local sid = _nf(node, "setting_id")
        if type(sid) == "string" then owners[sid] = { mod_id = _CKC_NAME, mod_obj = ckc } end
    end

    -- Splice the block into a COPY of gut's widget list at the START of the HUD child
    -- block (#527; see [CKC-SPLICE-FIRST-527] above).
    local new_w = {}
    for i = 1, ins_idx - 1 do new_w[#new_w + 1] = src[i] end
    for i = 1, #block do new_w[#new_w + 1] = block[i] end
    for i = ins_idx, #src do new_w[#new_w + 1] = src[i] end

    gut_cat.widgets = new_w
    gut_cat._owners = owners
    gut_cat._owner_mod_ids = { gut_cat.mod_id, _CKC_NAME }   -- MIXED: flush BOTH buffers
    -- gut_cat.mod_obj stays = gut (its own settings fall back via _owner)
end

-- (#312) Bridge gut's surfaced "UI Tweaks" toggles to the STOCK UI Tweaks (HideBuffs)
-- mod so the Mod Tweaker reads/writes ITS live settings, not gut's own private copies.
-- gut kept HideBuffs' setting_ids VERBATIM in its data tree (hide_frames, HIDE_BOSS_HP_BAR,
-- ...), but the two mods persist them in SEPARATE VMF namespaces (gut_dev vs HideBuffs) --
-- so a toggle the user set ON in UI Tweaks' own VMF menu showed OFF in the Mod Tweaker
-- (issue #312, user reports 2026-07-10 / 2026-07-12). When HideBuffs is installed + enabled
-- we route every OVERLAPPING checkbox setting_id's get/set to it via the same per-node
-- _owners mechanism the Equipment merge (#208) and CKC injection (#339) use: reads now show
-- HideBuffs' live value, edits stage under a "HideBuffs" buffer and commit as HB:set(id, v,
-- true) (fires its on_setting_changed live + VMF-persists) -- the own-or-pin doctrine that
-- matches the drag-offset sync module (_gut_uitweaks_sync.lua) and the CKC bridge (#313).
-- HideBuffs becomes the single owner of the shared toggles. No-op when HideBuffs is absent
-- or disabled: gut's own copies drive its absorbed hb/ fork exactly as before. Runs AFTER
-- _inject_ckc_into_gut so it MERGES into any CKC-set _owner_mod_ids. Marker
-- [UITWEAKS-BRIDGE-312]. Byte-parallel twin with the one in _mod_tweaker_view.lua.
local function _bridge_uitweaks_to_stock(out)
    local HB = get_mod("HideBuffs")
    if not HB then return end                          -- stock UI Tweaks absent: gut owns its copies
    if type(HB.is_enabled) == "function" then
        local ok_en, en = pcall(HB.is_enabled, HB)
        if ok_en and en == false then
            local gut_cat
            for _, c in ipairs(out) do
                if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
            end
            if gut_cat then
                gut_cat.widgets = disabled_sections.disable_group_subtree(gut_cat.widgets,
                    "hb_group",
                    _equip_loc("gut_disabled_in_vmf", disabled_sections.REASON))
            end
            return                                    -- present but disabled: explained header only
        end
    end
    local names = HB.SETTING_NAMES
    if type(names) ~= "table" then return end
    -- Real HideBuffs setting_ids are the VALUES of SETTING_NAMES (key may differ from id).
    local valid = {}
    for _, sid in pairs(names) do
        if type(sid) == "string" then valid[sid] = true end
    end
    local gut_cat
    for _, c in ipairs(out) do
        if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
    end
    if not gut_cat or type(gut_cat.widgets) ~= "table" then return end

    local owners  = gut_cat._owners or {}
    local bridged = 0
    for i = 1, #gut_cat.widgets do
        local node  = gut_cat.widgets[i]
        local sid   = _nf(node, "setting_id")
        local wtype = _nf(node, "type")
        -- Bridge only OVERLAPPING value toggles: a checkbox whose id is a real HideBuffs
        -- setting. Skips groups, the HIDE_HUD hotkey (keybind, read-only here), and gut's
        -- OWN control settings (gut_uitweaks_sync / the vanilla mirrors are NOT in
        -- SETTING_NAMES). Never override a node already owned (e.g. a CKC-injected one).
        if type(sid) == "string" and valid[sid]
                and (wtype == "checkbox" or wtype == "boolean")
                and owners[sid] == nil then
            owners[sid] = { mod_id = "HideBuffs", mod_obj = HB }
            bridged = bridged + 1
        end
    end
    if bridged == 0 then return end
    gut_cat._owners = owners
    -- Merge "HideBuffs" into _owner_mod_ids so apply/dirty flush ITS staged buffer too.
    -- _inject_ckc_into_gut may have already set this to { gut_id, CKC }; preserve those and
    -- add gut's own id (its non-bridged settings buffer under it) + HideBuffs.
    local ids  = gut_cat._owner_mod_ids or {}
    local seen = {}
    for _, id in ipairs(ids) do seen[id] = true end
    if not seen[gut_cat.mod_id] then ids[#ids + 1] = gut_cat.mod_id end
    seen[gut_cat.mod_id] = true
    if not seen["HideBuffs"] then ids[#ids + 1] = "HideBuffs" end
    gut_cat._owner_mod_ids = ids
    -- gut_cat.mod_obj stays = gut (its own non-bridged settings fall back via _owner).
end

local function _vmf_categories()
    local out = {}
    local vmf = get_mod("VMF")
    if not vmf then return out end

    -- VMF is bytecode; field names are reverse-engineered. Probe once (debug only)
    -- so the log reveals the real shape if these guesses are wrong.
    if not vmf._gut_mt_probed then
        vmf._gut_mt_probed = true
        local tk = {}
        for k, v in pairs(vmf) do if type(v) == "table" then tk[#tk + 1] = tostring(k) end end
        mod:debug("[mt] vmf table fields: {%s}", table.concat(tk, ", "))
        local wd = vmf.options_widgets_data
        if type(wd) == "table" then
            mod:debug("[mt] vmf options_widgets_data: %d mod lists", #wd)
            -- header (n,1) + first real setting node (n,2) for whichever list has one
            for li = 1, math.min(#wd, 4) do
                local list = wd[li]
                if type(list) == "table" and type(list[2]) == "table" then
                    local nk = {}
                    for k, v in pairs(list[2]) do nk[#nk + 1] = tostring(k) .. "=" .. type(v) end
                    mod:debug("[mt] vmf node[%d][2] (%s) keys: {%s}", li,
                        tostring(_nf(list[1], "mod_name")), table.concat(nk, ", "))
                    break
                end
            end
        end
    end

    -- Iterate the per-mod widget lists directly (confirmed in-game 2026-06-19).
    -- Each entry is one mod's flattened widget list: list[1] is a synthesized
    -- header carrying mod_name + readable_mod_name; list[2..] are the setting
    -- nodes. The owning mod object (for get/set) is get_mod(mod_name).
    local widget_data = vmf.options_widgets_data
    if type(widget_data) ~= "table" then return out end
    for _, list in ipairs(widget_data) do
        local header = (type(list) == "table") and list[1]
        local mod_name = header and _nf(header, "mod_name")
        if type(mod_name) == "string" and disabled_sections.is_author_mod(mod_name) then
            local mod_obj = get_mod(mod_name)
            local label = _nf(header, "readable_mod_name") or mod_name
            -- (Fix 3) gut's OWN Mod Tweaker tab reads "Interface" (this IS the interface/GUI
            -- menu), not the VMF readable_mod_name. Label-only override — the mod id, Workshop
            -- title, and .mod/cfg are untouched. Applies to both the stable + dev ids.
            if mod_name == "gut" or mod_name == "gut_dev" then label = "Interface" end
            local enabled = true
            if mod_obj and mod_obj.is_enabled then
                local ok_en, en = pcall(mod_obj.is_enabled, mod_obj)
                if ok_en then enabled = en and true or false end
            end
            -- #318 revised contract: retain installed disabled mods so synthesis can
            -- place an explained grey header in the normal merged section. An
            -- unsynthesized single-mod category retains the established disabled tab.
            out[#out + 1] = {
                mod_id = mod_name, label = label, widgets = list,
                mod_obj = mod_obj, enabled = enabled, _flat = true,
            }
        end
    end
    -- (#339) Fold Crosshair Kill Confirmation into gut's Interface tab under HUD (NOT a
    -- tab). No-op when CKC is absent. Before the sort (it mutates the existing gut cat).
    _inject_ckc_into_gut(out)
    -- (#312) Bridge gut's UI Tweaks toggles to the stock HideBuffs mod's live settings
    -- (own-or-pin) so the Mod Tweaker stays consistent with UI Tweaks' own VMF options.
    -- After CKC injection (it merges into any CKC-set _owner_mod_ids), before the sort.
    _bridge_uitweaks_to_stock(out)
    -- (#208) Fold the four inventory mods into one "Equipment" tab when 2+ are active
    -- (or relabel the N=1-only-CWV tab). Done BEFORE the sort so Equipment participates.
    out = _synthesize_equipment(out)
    table.sort(out, function(a, b)
        if a.enabled ~= b.enabled then return a.enabled end
        return tostring(a.label) < tostring(b.label)
    end)
    return out
end

HeroViewStateModTweaker = class(HeroViewStateModTweaker)
HeroViewStateModTweaker.NAME = "HeroViewStateModTweaker"

-- ---------------------------------------------------------------
-- STAGED-CHANGE model (v0.2.70-dev). Native Options stages every edit in
-- `changed_user_settings` and only writes live on APPLY (options_view.lua:1789-1939,
-- 3129-3196). gut used to write live via _cat_set on EVERY change. These four helpers
-- convert it to staged:
--   * stage_set   — a row edit writes here (NOT _cat_set), into the per-category buffer.
--   * get_staged  — a row read/repaint prefers the staged value, falling back to live.
--   * _update_apply_button — recomputes the APPLY button's enabled/greyed state from
--                            whether the ACTIVE category's buffer is non-empty.
--   * apply_pending — the APPLY click; the ONLY place _cat_set runs (commits the buffer).
-- The buffer is keyed by mod_id (stable string), so it survives the category-table
-- rebuild on a tab switch and isolates per category.
-- ---------------------------------------------------------------

-- Stable buffer key for a category (the category table is rebuilt on _rebuild; the
-- mod_id string is stable across rebuilds).
local function _cat_key(category)
    return category and category.mod_id or "?"
end

-- Stage one edit into the pending buffer (replaces the live _cat_set on every row edit).
-- Records the value + refreshes the APPLY button dirty state. (#208) The buffer is keyed by
-- the OWNER mod_id resolved from the node, so an Equipment edit to e.g. a cosmetics setting
-- buffers under "cosmetics_tweaker"; for a normal category _owner returns category.mod_id, so
-- the key is _cat_key(category) exactly as before.
function HeroViewStateModTweaker:stage_set(category, setting_id, value)
    local _, owner_id = _owner(category, setting_id)
    local key = owner_id or _cat_key(category)
    self._pending[key] = self._pending[key] or {}
    self._pending[key][setting_id] = value
    -- NOTE: do NOT set self._dirty here. self._dirty drives the auto-save-to-log on exit,
    -- which must reflect LIVE writes only — a pending (unapplied) edit was never written,
    -- so exiting with only-pending edits must NOT export. apply_pending sets _dirty.
    self:_update_apply_button()
end

-- Read a setting's EFFECTIVE value: the staged value if one is pending, else the live
-- value passed in (which the caller read via _cat_get). Mirrors native _get_setting
-- (assigned(pending, live)). (#208) Reads from the OWNER mod_id's buffer (see stage_set).
function HeroViewStateModTweaker:get_staged(category, setting_id, live_value)
    local _, owner_id = _owner(category, setting_id)
    local p = self._pending[owner_id or _cat_key(category)]
    if p and p[setting_id] ~= nil then return p[setting_id] end
    return live_value
end

-- True if the ACTIVE category has any pending edit (drives APPLY enabled/greyed). (#208) The
-- merged Equipment category buffers under EACH member mod_id, so it's dirty if ANY member's
-- buffer is non-empty; a normal category checks its single _cat_key buffer as before.
function HeroViewStateModTweaker:_active_category_dirty()
    local cat = self._categories and self._categories[self._selected]
    if not cat then return false end
    local ids = cat._owner_mod_ids
    if ids then
        for i = 1, #ids do
            local p = self._pending[ids[i]]
            if p and next(p) ~= nil then return true end
        end
        return false
    end
    local p = self._pending[_cat_key(cat)]
    return (p ~= nil) and (next(p) ~= nil)
end

-- Recompute the APPLY button's disabled flag from the active category's buffer.
function HeroViewStateModTweaker:_update_apply_button()
    if self._apply then self._apply.content.disabled = not self:_active_category_dirty() end
end

function HeroViewStateModTweaker:_profile_snapshot(category, defaults)
    local out = {}
    for i = 1, #(self._build_nodes or {}) do
        local node = self._build_nodes[i]
        local sid = _nf(node, "setting_id")
        local kind = _nf(node, "type")
        if sid and kind ~= "group" and kind ~= "keybind" then
            local _, owner_id = _owner(category, sid)
            local value = defaults and _nf(node, "default_value") or _cat_get(category, sid)
            if value == nil and defaults then value = _cat_get(category, sid) end
            if owner_id and value ~= nil then
                out[profiles.member_key(owner_id, sid)] = value
            end
        end
    end
    return out
end


function HeroViewStateModTweaker:_profile_ensure(category)
    if not category then return end
    local tab_id = _cat_key(category)
    self._profile_slot = profiles.get_active(mod, tab_id)
    local ready_key = tab_id .. ":" .. tostring(self._profile_slot)
    if self._profile_ready[ready_key] then return end
    if not profiles.load(mod, tab_id, self._profile_slot) then
        local use_defaults = self._profile_slot ~= 1
        profiles.save(mod, tab_id, self._profile_slot,
            self:_profile_snapshot(category, use_defaults))
        _printf("[gut:561] initialized tab=%s profile=%d source=%s",
            tostring(tab_id), self._profile_slot, use_defaults and "defaults" or "live")
    end
    self._profile_ready[ready_key] = true
end


function HeroViewStateModTweaker:_profile_capture(category)
    if not category then return end
    local tab_id = _cat_key(category)
    local slot = profiles.get_active(mod, tab_id)
    profiles.save(mod, tab_id, slot, self:_profile_snapshot(category, false))
    self._profile_ready[tab_id .. ":" .. tostring(slot)] = true
    self._profile_slot = slot
end


function HeroViewStateModTweaker:_switch_profile(slot)
    local category = self._categories and self._categories[self._selected]
    if not category then return end
    local tab_id = _cat_key(category)
    local current = profiles.get_active(mod, tab_id)
    if slot == current then return end
    if self:_active_category_dirty() then self:apply_pending(category) end
    self:_profile_capture(category)
    local values = profiles.load(mod, tab_id, slot)
    if not values then
        values = self:_profile_snapshot(category, true)
        profiles.save(mod, tab_id, slot, values)
    end
    profiles.set_active(mod, tab_id, slot)
    self._profile_ready[tab_id .. ":" .. tostring(slot)] = true
    self._profile_slot = slot
    local staged = 0
    for member, value in pairs(values) do
        local owner_id, sid = profiles.split_member_key(member)
        local _, actual_owner = _owner(category, sid)
        if owner_id and sid and actual_owner == owner_id then
            self:stage_set(category, sid, value)
            staged = staged + 1
        end
    end
    if staged > 0 then self:apply_pending(category) else self:_build_rows(category) end
    _printf("[gut:561] switched tab=%s profile=%d settings=%d",
        tostring(tab_id), slot, staged)
    _play_click()
end

-- APPLY: commit the whole pending buffer for `category` through the existing _cat_set
-- path (the ONLY place _cat_set runs on edit — a stray slider drag never takes effect
-- until clicked), clear the buffer, grey the button, and repaint the rows from the new
-- live values. Native handle_apply_button -> apply_changes (options_view.lua:1919).
-- (#208) For the merged Equipment category, flush EACH member mod_id's buffer (each edit
-- routes to its owner's mod_obj via _cat_set -> _owners), then clear them all.
function HeroViewStateModTweaker:apply_pending(category)
    local ids = category._owner_mod_ids
    if ids then
        local any = false
        for i = 1, #ids do
            local mid = ids[i]
            local p = self._pending[mid]
            if p and next(p) ~= nil then
                local count, batched, batch_err = transactions.commit(category, p, _owner, _cat_set)
                if batched then
                    printf("[gut:560] committed owner=%s settings=%d notifications=%d error=%s",
                        tostring(mid), count, batch_err and 0 or 1, tostring(batch_err or "none"))
                end
                self._pending[mid] = {}
                any = true
            end
        end
        if not any then return end
        self._dirty = true
        self:_update_apply_button()
        self:_build_rows(category)
        self:_profile_capture(category)
        _play_click()
        mod:debug("[mt:apply] committed Equipment buffers {%s}", table.concat(ids, ", "))
        return
    end
    local key = _cat_key(category)
    local p = self._pending[key]
    if not p or next(p) == nil then return end
    local count, batched, batch_err = transactions.commit(category, p, _owner, _cat_set)
    if batched then
        printf("[gut:560] committed owner=%s settings=%d notifications=%d error=%s",
            tostring(key), count, batch_err and 0 or 1, tostring(batch_err or "none"))
    end
    self._pending[key] = {}
    self._dirty = true   -- a LIVE write happened -> export the TOML on exit
    self:_update_apply_button()
    -- Rebuild the rows so each reads its new live value (the mod's on_setting_changed
    -- may have snapped/clamped further, e.g. ct's 25-coin rounding).
    self:_build_rows(category)
    self:_profile_capture(category)
    _play_click()
    mod:debug("[mt:apply] committed pending buffer for '%s'", tostring(key))
end

-- (v0.2.148-dev) RESTORE DEFAULTS: stage every setting in the CURRENT tab back to its
-- default_value, then repaint the rows so the staged defaults show. This does NOT write
-- live — it STAGES (like a manual edit); the user clicks Apply to commit, at which point
-- apply_pending flushes the buffer through _cat_set. Because stage_set routes each edit to
-- its OWNER mod_id (_owner), the Equipment tab resets every member mod correctly.
-- Skips groups/headers (no setting_id), settings with no default_value, and keybinds
-- (type=="keybind", whose default_value is an empty table).
function HeroViewStateModTweaker:reset_to_defaults()
    local nodes    = self._build_nodes
    local category = self._build_category
    if not nodes or not category then return end
    local n = 0
    for i = 1, #nodes do
        local node = nodes[i]
        local sid  = _nf(node, "setting_id")
        local dv   = _nf(node, "default_value")
        if sid and dv ~= nil and _nf(node, "type") ~= "keybind" then
            self:stage_set(category, sid, dv)
            n = n + 1
        end
    end
    self:_update_apply_button()
    self:_build_rows(category)
    _play_click()
    mod:debug("[mt:reset] staged %d default(s) for '%s'", n, tostring(_cat_key(category)))
end

-- (Fix 3, v0.2.151-dev) Show the native "restore defaults" CONFIRM popup before resetting.
-- Rendered by the game's own Managers.popup (its own manager + renderer — no borrowed-renderer
-- issue), the same mechanism vanilla OptionsView uses for its reset/apply confirms
-- (options_view.lua:3335). queue_popup(text, topic, result_1, button_1, result_2, button_2);
-- query_result later returns the chosen result key. Only the CONFIRM ("reset_values") result
-- runs reset_to_defaults (current tab only). Falls back to an immediate reset if the popup
-- manager is unavailable, so the button never dead-ends.
function HeroViewStateModTweaker:_queue_reset_popup()
    _play_click()
    if self._reset_popup_id then return end   -- already showing
    if not (Managers and Managers.popup and Managers.popup.queue_popup) then
        self:reset_to_defaults()
        return
    end
    -- Mirror the VANILLA reset-settings popup (options_view.lua:3335) VERBATIM: the engine
    -- Localizes popup text, so RAW English strings render as `<raw string>`. Real vanilla loc
    -- keys (reset_settings_popup_text / popup_discard_changes_topic / button_ok / popup_choice_cancel)
    -- resolve correctly. CONFIRM result = "reset_values"; cancel = "revert_changes".
    local ok, id = pcall(function()
        local text = Localize("reset_settings_popup_text")
        return Managers.popup:queue_popup(text, Localize("popup_discard_changes_topic"), "reset_values", Localize("button_ok"), "revert_changes", Localize("popup_choice_cancel"))
    end)
    if ok and id then self._reset_popup_id = id else self:reset_to_defaults() end
end

-- (Fix 3, v0.2.151-dev) Poll the reset-confirm popup each frame; run the reset ONLY on the
-- CONFIRM ("reset_values") result. Any other result (cancel / click-away) just dismisses.
function HeroViewStateModTweaker:_check_reset_popup()
    local id = self._reset_popup_id
    if not id then return end
    if not (Managers and Managers.popup) then self._reset_popup_id = nil; return end
    local result = Managers.popup:query_result(id)
    if result then
        Managers.popup:cancel_popup(id)
        self._reset_popup_id = nil
        if result == "reset_values" then self:reset_to_defaults() end
    end
end

-- ---------------------------------------------------------------
-- Lifecycle (sub-state contract — driven by HeroView, NOT IngameUI)
-- ---------------------------------------------------------------
-- on_enter reads the borrowed renderer from params.ingame_ui_context and captures
-- the parent (HeroView) for input + close. NEVER creates a renderer, NEVER pushes
-- the cursor (HeroView owns it), NEVER makes its own modal input service.

HeroViewStateModTweaker.on_enter = function (self, params)
    self.parent = params.parent
    local ctx = params.ingame_ui_context
    self.ingame_ui_context = ctx
    self.ui_renderer       = ctx.ui_renderer
    self.ui_top_renderer   = ctx.ui_top_renderer or ctx.ui_renderer
    self.input_manager     = ctx.input_manager
    self.voting_manager    = ctx.voting_manager
    self.ingame_ui         = ctx.ingame_ui
    self.render_settings   = { alpha_multiplier = 1, snap_pixel_positions = false }

    self.ui_scenegraph = UISceneGraph.init_scenegraph(defs.scenegraph_definition)

    -- Static chrome built once (the native window).
    self._chrome    = defs.build_chrome()
    self._exit      = defs.build_exit_button()
    self._scrollbar = defs.build_scrollbar_rect()
    -- (v0.2.70-dev) STAGED-CHANGE model. Edits write to a per-category PENDING buffer
    -- (self._pending[mod_id][setting_id] = staged_value) instead of live; the APPLY
    -- button (bottom-right) commits the whole buffer via _cat_set. Keyed by mod_id (a
    -- stable string) NOT the category table — category tables are rebuilt on every
    -- _rebuild (_vmf_categories re-creates them), so keying by the table would lose the
    -- buffer on a tab switch. mod_id survives, and gives per-category isolation for free.
    self._pending   = self._pending or {}
    self._apply     = defs.create_apply_button()
    -- (v0.2.148-dev) RESTORE DEFAULTS button (bottom bar, to the LEFT of Apply). Clicking it
    -- STAGES every current-tab setting back to its default_value (see reset_to_defaults) — the
    -- user then clicks Apply to commit, exactly like a normal staged edit.
    self._reset     = defs.create_default_button()
    self._profiles_label, self._profile_buttons = defs.create_profile_controls()
    self._profile_slot = 1
    self._profile_ready = {}
    -- (#207) Reusable hover-info popup widget (rect bg + frame + title/desc text). The draw
    -- loop sets its content + geometry + fade alpha each frame via defs.layout_tooltip.
    self._tooltip   = defs.create_tooltip_popup()
    -- v0.2.65-dev: no "MOD TWEAKER" title widget — native Options has none and the
    -- tab strip now spans the full top band (see defs: mt_title node + build_title
    -- factory removed).
    -- (Fix 5, v0.2.149-dev) The bottom "Click a tab to pick a mod..." hint was removed to
    -- match the vanilla Options menu (no bottom hint). build_hint/self._hint are gone.

    self._tabs = {}
    self._rows = {}
    self._selected = 1

    -- Scroll state (the list scrolls like the vanilla settings menu: a pixel offset
    -- on the mt_list node + position-culling against list_mask + the rect scrollbar).
    self._scroll_y = 0        -- pixel offset applied to mt_list.offset[2]
    self._max_scroll = 0      -- content_height - visible_height (>= 0)
    self._content_h = 0       -- total stacked row height
    self._visible_h = 0       -- list_mask height (read at runtime)
    self._sb_dragging = false -- scrollbar thumb being dragged
    self._drill = nil         -- gear drill-down state: nil = normal list; { setting_id, label } = drilled in

    self._draw_frames = 0
    self._dirty = false

    -- DEFENSIVE re-pin LA's atlas + instrument on every open (sub-state site).
    -- Even though a sub-state never recreates hero_view's renderer (the whole point
    -- of this build), the keepalive re-pin is cheap and pcall-guarded, and keeps the
    -- has_loaded force-load guard intact (NEVER force-loads a non-resident LA
    -- package). `self` here is the HeroViewStateModTweaker, whose
    -- ui_renderer/ui_top_renderer are logged by the probe to prove the borrowed
    -- renderer is the SAME instance across opens (it is, because we never recreate it).
    if mod._gut_mt_repin_la then pcall(mod._gut_mt_repin_la, self, "substate_on_enter") end

    self:_rebuild()
    if dx12_diag then dx12_diag:enter(dx12_diag_module.runtime_info(self, "hero_substate")) end
    self:_dump_state("substate_on_enter"); self:_dump_scrollbar("substate_on_enter"); _wwise_probe()
    -- Native menu-open feedback — the exact event both vanilla OptionsView.on_enter
    -- (options_view.lua:1615) and the VMF options view fire when the settings menu
    -- opens. Routed through the parent hero_view's play_sound (its wwise_world is the
    -- reliable handle at the keep). pcall-guarded, so a missing/renamed Wwise event is
    -- silent, never a crash. Matches the view twin's _play_open() for parity.
    pcall(function() self:play_sound("Play_hud_button_open") end)
    mod:info("[mt] HeroViewStateModTweaker entered (sub-state)")
end

HeroViewStateModTweaker.update = function (self, dt, t)
    local input_service = self:input_service()
    if not input_service then return end

    if dx12_diag then dx12_diag:before_draw(dx12_diag_module.runtime_info(self, "hero_substate")) end
    self:_draw(dt, input_service)
    if dx12_diag then dx12_diag:after_draw() end

    self._draw_frames = (self._draw_frames or 0) + 1
    if self._draw_frames % 120 == 1 then
        local ok_sb, sbp = pcall(UISceneGraph.get_world_position, self.ui_scenegraph, defs.scrollbar_sg)
        local sbc = self._scrollbar and self._scrollbar.content
        local sbhs = sbc and sbc.hotspot
        mod:debug("[mt:dump] heartbeat frame=%d rows=%d scroll=%d/%d vis_h=%s cont_h=%d thumb_frac=%s scroll_value=%s sb_world=%s sb_hover=%s sb_held=%s",
            self._draw_frames, #self._rows, math.floor(self._scroll_y or 0), math.floor(self._max_scroll or 0),
            tostring(self._visible_h), math.floor(self._content_h or 0),
            sbc and tostring(sbc.thumb_frac) or "nil", sbc and tostring(sbc.scroll_value) or "nil",
            (ok_sb and sbp) and string.format("{%d,%d}", sbp[1], sbp[2]) or "?",
            tostring(sbhs and sbhs.is_hover), tostring(sbhs and sbhs.is_held))
    end

    -- (Fix 3, v0.2.151-dev) While the reset-confirm popup is up, it's MODAL: only poll its
    -- result (the game popup owns input + renders itself); don't process ESC / row input.
    if self._reset_popup_id then
        self:_check_reset_popup()
        return
    end

    -- A mission-start vote closes the menu (matches the compendium).
    if self:_has_active_level_vote() then
        self:close_menu(true)
        return
    end

    -- ESC / back / toggle closes the SUB-STATE (returns to whatever hero_view screen
    -- we came from). This is the key difference vs the standalone view: NO
    -- transition_with_fade("ingame_menu") — that's what produced the deprecated look.
    if input_service:get("toggle_menu", true) or input_service:get("back", true) then
        -- (v0.2.69-dev) ESC priority while a DROPDOWN POPUP is open: the FIRST ESC closes
        -- the popup (no commit) instead of closing the menu / leaving the drill.
        if self._open_dropdown then
            self:_close_dropdown_popup()
            _play_click()
            return
        end
        -- ESC priority while TYPE-EDITING (v0.2.66-dev): the FIRST ESC cancels the active
        -- numeric edit (restores the value) instead of closing the menu / leaving the drill.
        if self._editing_row then
            self:_cancel_edit(self._editing_row)
            return
        end
        -- ESC priority: if drilled into a setting's advanced options, the FIRST ESC
        -- drills OUT (back to the normal list); only a second ESC closes the menu.
        if self._drill then
            self._drill = nil
            self._scroll_y = 0
            _play_click()
            self:_build_rows(self._categories[self._selected])
            return
        end
        self:close_menu()
        return
    end

    self:_handle_input(input_service)
end

HeroViewStateModTweaker.post_update = function (self, dt, t) end

HeroViewStateModTweaker.input_service = function (self)
    -- The SHARED hero_view input service (HeroView manages devices + the cursor);
    -- we never make our own. Exactly the compendium pattern.
    return self.parent:input_service()
end

HeroViewStateModTweaker.play_sound = function (self, event)
    if self.parent and self.parent.play_sound then self.parent:play_sound(event) end
end

HeroViewStateModTweaker._has_active_level_vote = function (self)
    local vm = self.voting_manager
    if not vm then return false end
    local active = vm:vote_in_progress()
    local is_mission = active == "game_settings_vote" or active == "game_settings_deed_vote"
    return is_mission and not vm:has_voted(Network.peer_id())
end

HeroViewStateModTweaker.close_menu = function (self, ignore_sound)
    -- (v0.2.82-dev — ITEM 1) Native menu-close feedback to match the standalone view +
    -- the real OptionsView (options_view.lua:1691/:2594 fire Play_hud_button_close). Was
    -- Play_gui_achivements_menu_close (a different, achievements-screen close sound); use
    -- the settings-menu event so both Mod Tweaker presentations close with the same sound.
    if not ignore_sound then pcall(function() self:play_sound("Play_hud_button_close") end) end
    if self.parent and self.parent.close_menu then
        self.parent:close_menu(nil, true)
    end
end

HeroViewStateModTweaker.on_exit = function (self)
    if dx12_diag then dx12_diag:leave("on_exit", self) end
    -- Auto-save: if any setting changed while open, emit the TOML to the log so the
    -- companion watcher writes gut_mod_settings.toml (the mod can't write directly).
    -- PRESERVED from the standalone view's on_exit — exiting the sub-state must still
    -- persist edits.
    if self._dirty then
        self._dirty = false
        pcall(function()
            if mod._export_settings_to_log then mod._export_settings_to_log(true) end
        end)
    end
    self._widgets = nil
    self._widgets_by_name = nil
    self.ui_scenegraph = nil
    self._chrome = nil
    self._tabs = nil
    self._rows = nil
    self._scrollbar = nil
    self._exit = nil
    self._apply = nil
    self._reset = nil   -- (v0.2.148-dev) RESTORE DEFAULTS button
    self._profiles_label = nil
    self._profile_buttons = nil
    self._profile_ready = nil
    -- (Fix 3, v0.2.151-dev) Cancel a dangling reset-confirm popup so it can't outlive the menu.
    if self._reset_popup_id then
        pcall(function()
            if Managers and Managers.popup then Managers.popup:cancel_popup(self._reset_popup_id) end
        end)
        self._reset_popup_id = nil
    end
    self._tooltip = nil   -- (#207) hover-info popup widget
    self._tt_row = nil
    -- (v0.2.70-dev) DISCARD pending edits on exit. Nothing was written live (staged-change
    -- model), so discard = drop the buffer — no native apply_changes(original_*) re-apply
    -- is needed (that exists only for native's live video-preview). Unapplied edits vanish.
    self._pending = {}
end

-- ---------------------------------------------------------------
-- Build the row widgets for a category. VMF categories carry a FLAT node array;
-- gut's own dogfood category is NESTED (walk it). Every factory call is pcall'd
-- so one bad node can't blank the view. Editable: checkbox, numeric (stepper),
-- dropdown (option cycler). Read-only: group titles, keybind, text, unknown.
-- ---------------------------------------------------------------
-- Build ONE row widget for a single settings node `w`. Factored out of _build_rows
-- so both the normal list AND the gear drill-down view (Back + parent + children)
-- build child rows through the identical path (no new persistence — _cat_get/_cat_set
-- and the same checkbox/slider/dropdown factories). Returns (row, err); row may be nil
-- (header) — that's not an error. `base_offset` is decremented by the factory.
-- `depth` (0-based nesting level) is threaded into the factories so nested child rows
-- get a per-depth LEFT-label indent (v0.2.67-dev). Defaults to 0 for the unindented
-- top level; the controls (arrows/value/track/gear) stay column-aligned regardless.
-- (v0.2.75-dev) Stable group expand/collapse key for a node, shared by _build_node_row
-- (which stores it on the group row) AND the drill planner's is_expanded predicate (which
-- must agree on the EXACT same key, or an expanded group reads as collapsed and its
-- children — incl. nested dropdowns — never render). Mirrors the original inline gid.
function HeroViewStateModTweaker:_group_key(w, category)
    local setting_id = _nf(w, "setting_id")
    -- (#208) Localize against the node's OWNER mod (Equipment members belong to four mods);
    -- _owner returns category.mod_obj for normal categories, so this is unchanged there.
    local label = category._flat and _vmf_label(w, (_owner(category, setting_id)))
                  or tostring(w.label or w.text or w.setting_id or "?")
    return (category.mod_id or "?") .. ":" .. tostring(setting_id or label)
end

function HeroViewStateModTweaker:_build_node_row(w, category, base_offset, depth)
    depth = depth or 0
    local setting_id = _nf(w, "setting_id")
    local wtype = _nf(w, "type")
    -- (#208) Resolve the node's OWNER mod_obj for label/tooltip localization (the merged
    -- Equipment tab spans four mods); for a normal category _owner returns category.mod_obj.
    local owner_mod_obj = _owner(category, setting_id)
    local label = category._flat and _vmf_label(w, owner_mod_obj)
                  or tostring(w.label or w.text or w.setting_id or "?")
    -- (#207) The node's localized tooltip DESCRIPTION (mod_obj may be nil for gut's own
    -- nested categories — _vmf_tooltip then just uses the raw string). Stored on the row
    -- below so the draw loop can show a hover popup; nil = no popup for this row.
    -- (#208) Localize against the node's OWNER mod (see owner_mod_obj above).
    local tooltip = _vmf_tooltip(w, owner_mod_obj)
    local row, err

    if wtype == "header" then
        row = nil  -- VMF synthesizes a per-mod header; the tab already names the mod.
    elseif wtype == "group" then
        -- Collapsible group header (default COLLAPSED). The caller handles expand state.
        local gid = self:_group_key(w, category)
        local expanded = self._expanded[gid] and true or false
        local ok, r = pcall(defs.create_group_header, label, expanded, base_offset, depth)
        if ok and r then row = r; row._is_group = true; row._group_key = gid else err = r end
    elseif wtype == "checkbox" or wtype == "boolean" then
        local ok, r = pcall(defs.create_checkbox, label, base_offset, depth)
        if ok and r then
            row = r
            -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
            local live = _cat_get(category, setting_id)
            row.content.flag = self:get_staged(category, setting_id, live) and true or false
            row._last_flag = row.content.flag
        else err = r end
    elseif wtype == "slider" or wtype == "numeric" then
        local ok, r = pcall(defs.create_slider, label, "", base_offset, depth)
        if ok and r then
            row = r
            local range = _nf(w, "range")
            local min = (range and range[1]) or _nf(w, "min") or 0
            local max = (range and range[2]) or _nf(w, "max") or 1
            local dec = _nf(w, "decimals_number") or _nf(w, "num_decimals") or _nf(w, "decimals") or 0
            -- (v0.2.70-dev) buffer-first: show the staged value if an edit is pending.
            local val = self:get_staged(category, setting_id, _cat_get(category, setting_id))
            if type(val) ~= "number" then val = min end
            row.content.min, row.content.max, row.content.num_decimals = min, max, dec
            row.content.value = val
            row.content.internal_value = (max > min) and math.clamp((val - min) / (max - min), 0, 1) or 0
            -- ±step for the [<]/[>] glyphs: ~range/40 (coarse), at least the natural
            -- increment. The track gives fine/continuous control; after a commit we
            -- re-read the value so any mod-side snapping (ct rounds starting_coins to
            -- 25 in its on_setting_changed) is reflected — matching VMF's own slider.
            local step = _resolve_step(w, category and category.mod_id, setting_id, dec)
            row.content.step = step
            mod:debug("[mt:num] '%s' bounds=%s..%s dec=%s step=%s val=%s",
                tostring(setting_id), tostring(min), tostring(max), tostring(dec), tostring(step), tostring(val))
            row.content.value_text = string.format("%." .. dec .. "f", val)
            row._last_value = val
        else err = r end
    elseif wtype == "dropdown" then
        -- (v0.2.69-dev) REAL dropdown: a collapsed row (label + selected value + single
        -- down arrow) that opens a popup option list on click. Was a slider-arrow carousel.
        local options = _nf(w, "options")
        local ok, r = pcall(defs.create_dropdown, label, base_offset, depth)
        if ok and r and type(options) == "table" and #options > 0 then
            row = r
            -- (v0.2.70-dev) buffer-first: show the staged selection if an edit is pending.
            local cur = self:get_staged(category, setting_id, _cat_get(category, setting_id))
            local values, texts, idx = {}, {}, 1
            for k = 1, #options do
                local o = options[k]
                values[k] = _nf(o, "value")
                texts[k] = tostring(_nf(o, "text") or values[k])
                if values[k] == cur then idx = k end
            end
            row._options_values, row._options_texts, row._option_idx = values, texts, idx
            row.content.value_text = texts[idx]
            row.content.active = false        -- popup closed at build time
        elseif ok and r then
            row = r; row._readonly = true; row.content.value_text = "?"
        else err = r end
    else
        -- keybind / text / unknown: read-only label + current value.
        local val = setting_id and _cat_get(category, setting_id)
        local suffix = (val ~= nil) and (": " .. tostring(val))
                       or (wtype and ("  [" .. tostring(wtype) .. "]") or "")
        local ok, r = pcall(defs.create_section_title, label .. suffix, base_offset, depth)
        if ok and r then row = r; row._readonly = true else err = r end
    end

    if row then
        if _nf(w, "disabled") == true then
            row._readonly = true
            row._disabled_in_vmf = true
            local color = row.style and row.style.label and row.style.label.text_color
            if color then color[1], color[2], color[3], color[4] = 128, 128, 128, 128 end
        end
        row._mod_id = category.mod_id
        row._setting_id = setting_id
        row._wtype = wtype
        row._category = category
        row._list_y = base_offset[2]  -- this row's Y (factory just decremented to it)
        -- (#207) Hover-popup text: TITLE = the row label, DESC = the localized tooltip.
        row._tip_title = label
        row._tip_desc = tooltip
        -- (v0.2.157-dev diag, temp) Farm any residual "<...>" marker. If the RAW node data or the
        -- RESOLVED label/desc still contains a "<", printf it so the exact culprit + owning mod are
        -- named next time the menu opens. With the _vmf_label/_vmf_tooltip hardening this should
        -- fire ZERO times; if it does not fire yet the user still sees "<>", the marker is coming
        -- from some OTHER element (value/dropdown/etc.), which this rules in or out.
        local _rt = _nf(w, "tooltip")
        local _rtt = _nf(w, "title") or _nf(w, "text")
        local function _hasmark(x) return type(x) == "string" and string.find(x, "<") end
        if _hasmark(_rt) or _hasmark(_rtt) or _hasmark(label) or _hasmark(tooltip) then
            printf("[gut:desc] MARKER mod=%s sid=%s type=%s raw_title=%q raw_tt=%q -> label=%q desc=%q",
                tostring(category.mod_id), tostring(setting_id), tostring(wtype),
                tostring(_rtt), tostring(_rt), tostring(label), tostring(tooltip))
        end
    end
    return row, err, wtype, setting_id, label
end

-- Append a row (+ optional gear) to self._rows and log build failures. Shared tail
-- of every row append so the drill view and normal list stay byte-identical.
function HeroViewStateModTweaker:_append_row(row, err, wtype, category, setting_id, base_offset, has_gear, parent_label)
    if row then
        self._rows[#self._rows + 1] = row
        if has_gear then
            -- Advanced-option parents are navigation/selection headers as well
            -- as settings. Give every enabled gear parent the same warm-tan
            -- accent as the menu chrome so a select-all master is visually
            -- distinct from the individual rows inside its drill view (#611).
            -- Keep disabled VMF rows grey instead of falsely advertising them.
            -- (#717) Twin-parity fix: 7d31174 added this accent ONLY to the
            -- mission twin (_mod_tweaker_view.lua), so every gear-parent row in
            -- the keep Mod Tweaker rendered plain font_default while the same
            -- rows in-mission were tan. Both twins now color identically.
            local accent = not row._disabled_in_vmf and row.style
                and row.style.label and row.style.label.text_color
            if accent then
                accent[1], accent[2], accent[3], accent[4] = 255, 160, 146, 101
            end
            row._advanced_parent_accent = true
            -- Shrink the parent's full-width whole-row hotspot so it stops BEFORE the
            -- gear column — otherwise a click on the gear ALSO lands on the parent row's
            -- hotspot (they overlap) and would e.g. toggle a parent checkbox while
            -- drilling. The arrow/track hotspots sit left of the gear and are untouched.
            if row.style and row.style.hotspot and row.style.hotspot.size then
                row.style.hotspot.size[1] = math.max(1, (defs.row_w or 800) - (defs.gear_col_w or 50))
            end
            -- 3rd-column gear: a SEPARATE widget at the SAME row Y; clicking it drills in.
            local ok, g = pcall(defs.create_gear_button, base_offset[2])
            if ok and g then
                g._is_gear = true
                g._list_y = base_offset[2]
                g._drill_setting = setting_id
                g._drill_label = parent_label or tostring(setting_id)
                g._category = category
                self._rows[#self._rows + 1] = g
            end
        end
    elseif wtype ~= "header" then
        mod:warning("[mt] row build failed for %s.%s (type=%s): %s",
            tostring(category.mod_id), tostring(setting_id), tostring(wtype), tostring(err))
    end
end

local function _order_category_nodes(category, nodes, depths)
    return ordering.order_flat(nodes, depths, {
        preserve_all = category.mod_id == "gut_equipment",
        get_type = function(node) return _nf(node, "type") end,
        is_generated_header = function(node) return _nf(node, "mod_name") ~= nil end,
        get_label = function(node)
            local owner = _owner(category, _nf(node, "setting_id"))
            return _vmf_label(node, owner or category.mod_obj)
        end,
        has_explicit_order = function(node)
            return _nf(node, "mod_tweaker_preserve_order") == true
                or _nf(node, "mod_tweaker_order") ~= nil
                or _nf(node, "mod_tweaker_before") ~= nil
                or _nf(node, "mod_tweaker_after") ~= nil
                or _nf(node, "depends_on") ~= nil
                or _nf(node, "dependency") ~= nil
        end,
    })
end

function HeroViewStateModTweaker:_build_rows(category)
    self._rows = {}
    -- Any in-progress type-edit is abandoned on a rebuild (tab switch / drill / collapse):
    -- the old row widget is discarded here, so drop the dangling editor reference too.
    self._editing_row = nil
    -- (v0.2.69-dev) An open dropdown popup is likewise abandoned on a rebuild — its
    -- collapsed row widget is being discarded, so drop the dangling open-dropdown refs.
    self._open_dropdown = nil
    self._dd_list = nil
    -- (#207) The hovered tooltip row is one of the rows being discarded; drop the dangling
    -- reference so a stale widget can't be redrawn (the fade machine re-acquires next frame).
    self._tt_row = nil
    if not category or type(category.widgets) ~= "table" then return end
    self._expanded = self._expanded or {}   -- group_key -> true (expanded); default collapsed

    -- Flatten into parallel node + depth arrays. The VMF flat list ships its own
    -- `depth`; the gut nested tree gets a synthesized depth from _walk_nested. Both
    -- then feed the SAME drill-detection ("the next node is deeper") + inline-skip.
    -- (#208) The synthesized Equipment category is flat too but carries a precomputed
    -- `_depths` array (its section headers + depth-shifted member nodes); use it when
    -- present, else fall back to each node's own `depth` field. (0 is truthy in Lua, so a
    -- depth-0 entry survives the `or` fallback.)
    local nodes, depths = {}, {}
    if category._flat then
        local pd = category._depths
        -- A plain VMF tab (no synthesized _depths) carries VMF's natural per-node `depth`,
        -- which starts at 1 for the mod's top-level content — indenting the WHOLE tab one level
        -- for no reason. Rebase by the tab's MINIMUM natural setting depth (excluding the
        -- non-rendered per-mod header) so its top-level rows render at depth 0 (no indent), the
        -- same as the Equipment tab. Equipment supplies its own already-rebased `_depths`. (#208)
        local min_d
        if not pd then
            for i = 1, #category.widgets do
                local w = category.widgets[i]
                if _nf(w, "type") ~= "header" then
                    local d = _nf(w, "depth")
                    if type(d) == "number" and (not min_d or d < min_d) then min_d = d end
                end
            end
            min_d = min_d or 0
        end
        for i = 1, #category.widgets do
            nodes[#nodes + 1] = category.widgets[i]
            if pd then
                depths[#depths + 1] = pd[i] or _nf(category.widgets[i], "depth") or 0
            else
                depths[#depths + 1] = (_nf(category.widgets[i], "depth") or 0) - min_d
            end
        end
    else
        for i = 1, #category.widgets do _walk_nested(category.widgets[i], nodes, depths, 0) end
    end
    nodes, depths = _order_category_nodes(category, nodes, depths)

    -- (v0.2.148-dev) Keep the flattened node/depth/category refs so the RESTORE DEFAULTS
    -- button (reset_to_defaults) can iterate the current tab's settings. Mirrors the view twin
    -- (_mod_tweaker_view.lua stores these for its auto-collapse handler + the reset button).
    self._build_nodes, self._build_depths, self._build_category = nodes, depths, category
    self:_profile_ensure(category)

    local base_offset = { 0, -10, 0 }

    -- DRILLED-IN advanced view: render only Back + parent + that parent's children.
    if self._drill then
        local ok_b, back = pcall(defs.create_back_row, self._drill.label, base_offset)
        if ok_b and back then
            back._is_back = true
            back._list_y = base_offset[2]
            self._rows[#self._rows + 1] = back
        end
        -- Re-locate the parent node by setting_id (the widget list is stable across
        -- rebuilds), render it (no gear — we're already inside it), then its children.
        local p_idx
        for i = 1, #nodes do
            if _nf(nodes[i], "setting_id") == self._drill.setting_id then p_idx = i; break end
        end
        if p_idx then
            -- Drilled-in: the parent + its descendants are shown as a flat list with the
            -- parent at depth 0 (the Back row supplies the context). (v0.2.75-dev) The
            -- child rows come from the SHARED plan_drill_children planner, which walks the
            -- WHOLE subtree with the normal list's group-collapse / gear-parent rules — so a
            -- dropdown nested THREE deep (VMF wt anim picker: checkbox -> set-group ->
            -- per-attack dropdown) is finally built and its options surface. The old loop
            -- rendered the parent's DIRECT children only (`depths[j] == pdepth + 1`), so the
            -- depth-3 dropdown nodes never existed as rows (the "no options" symptom).
            -- (v0.2.153-dev) The parent's OWN toggle row is NOT re-rendered here — you
            -- already toggle it on the main list and the "Advanced: <name>" Back row gives
            -- context, so repeating it was redundant. Children rebase to depth 0 below.
            local pdepth = depths[p_idx]
            local plan = defs.plan_drill_children(nodes, depths, p_idx, pdepth,
                function(node) return _nf(node, "type") end,
                function(node, _flat_depth, _row_depth)
                    -- A group is expanded iff the user toggled its [+]/[-]. Use the SAME
                    -- _group_key _build_node_row stamps onto the group row, so the planner
                    -- and the rendered row agree. Default collapsed.
                    return self._expanded[self:_group_key(node, category)] and true or false
                end)
            for k = 1, #plan do
                local p = plan[k]
                local crow, cerr, cwtype, csid, clabel =
                    self:_build_node_row(nodes[p.index], category, base_offset, math.max(0, p.depth - 1))
                self:_append_row(crow, cerr, cwtype, category, csid, base_offset, p.has_gear, clabel)
            end
        end
        self._content_h = math.abs(base_offset[2]) + 20
        self:_recompute_scroll_bounds()
        self._scroll_y = math.clamp(self._scroll_y or 0, 0, self._max_scroll)
        return
    end

    -- NORMAL list. A node has children when the NEXT node is deeper (flat) or it's a
    -- non-group node with sub_widgets (nested → _walk_nested already deepened them, so
    -- the same "next is deeper" test holds). A group COLLAPSES its children inline (the
    -- existing [+]/[-] behaviour); a non-group PARENT skips its children inline and
    -- shows a GEAR that drills into them.
    local skip_below = nil   -- depth: while set, skip deeper nodes (collapsed group OR gear parent)
    for i = 1, #nodes do
        local w = nodes[i]
        local depth = depths[i]
        local skip = skip_below and depth > skip_below

        -- Inside a collapsed group / gear parent: render nothing until we climb out.
        if not skip then
            skip_below = nil
            local wtype = _nf(w, "type")
            local has_children = (depths[i + 1] ~= nil) and (depths[i + 1] > depth)
            -- (#208) No special top-section gap — sections/groups stack with the same row
            -- rhythm as every other tab, so the Equipment tab's spacing matches other menus.
            local row, err, _wt, setting_id, label = self:_build_node_row(w, category, base_offset, depth)

            if wtype == "group" then
                -- Group: collapsible (no gear). Skip descendants inline while collapsed.
                local expanded = row and self._expanded[row._group_key] and true or false
                self:_append_row(row, err, wtype, category, setting_id, base_offset, false)
                if not expanded then skip_below = depth end
            -- Exclude "header": the VMF per-mod header node is immediately followed by
            -- ALL the mod's (deeper) setting nodes, so without this guard the header is
            -- treated as a gear-parent and skip_below hides EVERY setting -> rows=0 blank
            -- menu (build-4 gear regression; fixed v0.2.61-dev).
            elseif has_children and wtype ~= "header" then
                -- Non-group parent with nested options: GEAR + skip children inline.
                self:_append_row(row, err, wtype, category, setting_id, base_offset, true, label)
                skip_below = depth
            else
                self:_append_row(row, err, wtype, category, setting_id, base_offset, false)
            end
        end
    end

    -- Total content height (origin -10 down to the last row's Y, + bottom pad), then
    -- recompute how far we can scroll and clamp the current offset into range.
    self._content_h = math.abs(base_offset[2]) + 20
    self:_recompute_scroll_bounds()
    self._scroll_y = math.clamp(self._scroll_y or 0, 0, self._max_scroll)
end

-- Visible window height = list_mask height (read at runtime); max scroll is how far
-- the content overflows it.
--
-- (v0.2.80-dev) BOTTOM SCROLL PADDING. A dropdown opened on a row near the bottom of
-- the list drops DOWNWARD from its row (create_dropdown_list anchors the popup one
-- ROW_H below the collapsed row and descends); the popup is drawn outside the row-cull
-- loop so it's NOT clipped to list_mask, but when the row is already at the bottom of
-- the scroll range there's no headroom to scroll that row UP into view, so the open
-- popup hangs past the panel's bottom edge with nothing behind it. Burned the wt anim
-- picker's per-attack dropdown (Sienna's Mace). Fix: extend the scrollable content by a
-- fixed empty-space pad so max_scroll grows and any near-bottom row can be scrolled up
-- far enough that its open popup fits inside the visible list. The pad is empty space
-- below the last real row (the user scrolls into it). Sized to comfortably clear the
-- tallest popup (DD_MAX_ROWS * DD_ROW_H ~= 10*24 = 240px) plus a margin — TUNABLE.
-- _content_h itself is extended so the scrollbar thumb_frac (visible/_content_h, draw
-- path) stays correct: the thumb just gets a bit smaller, which is fine.
local BOTTOM_SCROLL_PAD = 300   -- px of empty scroll headroom below the last row (tunable)
function HeroViewStateModTweaker:_recompute_scroll_bounds()
    local ok, s = pcall(UISceneGraph.get_size, self.ui_scenegraph, defs.list_mask_sg)
    self._visible_h = (ok and s and s[2]) or 700
    -- Add the empty-space pad ONLY when the real row stack already overflows the visible
    -- window — so a short list whose rows all fit doesn't grow a spurious scrollbar / phantom
    -- scroll into empty space. When it does overflow, the pad gives the headroom to scroll a
    -- near-bottom row (and its open dropdown) up into view. Idempotent per rebuild: _build_rows
    -- resets _content_h to the unpadded row-stack height immediately before calling this, so
    -- the pad is applied exactly once per recompute, never compounded.
    if (self._content_h or 0) > self._visible_h then
        self._content_h = self._content_h + BOTTOM_SCROLL_PAD
    end
    self._max_scroll = math.max(0, (self._content_h or 0) - self._visible_h)
    -- (v0.2.77-dev) Fire the scrollbar probe once per overflow-state TRANSITION (none ->
    -- overflow or back) so the next in-game repro captures the OVERFLOW state — on_enter
    -- alone often samples before the list has overflowed. Guarded so it fires on the edge,
    -- not every recompute (this runs on every row rebuild).
    local overflowing = self._max_scroll > 0
    if overflowing ~= self._sb_probe_overflowing then
        self._sb_probe_overflowing = overflowing
        self:_dump_scrollbar(overflowing and "scroll-bound:overflow" or "scroll-bound:fits")
    end
end

local function _truncate(s, n)
    s = tostring(s or "")
    if #s > n then return string.sub(s, 1, n - 1) .. "." end
    return s
end

function HeroViewStateModTweaker:_rebuild()
    -- Every VMF mod becomes a category (gut included, via its real settings);
    -- then any controller-registered category VMF didn't already provide.
    local cats = {}
    local seen = {}
    local ok_vmf, vmf_cats = pcall(_vmf_categories)
    if ok_vmf and type(vmf_cats) == "table" then
        for _, c in ipairs(vmf_cats) do cats[#cats + 1] = c; seen[c.mod_id] = true end
    end
    local MT = _mt()
    for _, c in ipairs((MT and MT:list_categories()) or {}) do
        if not seen[c.mod_id] then cats[#cats + 1] = c; seen[c.mod_id] = true end
    end

    -- Pin priority mods to the front of the tab strip (v0.2.56). General Tweaker
    -- ("gt" stable / "gt_dev" dev) is the leftmost tab regardless of the source
    -- ordering above; everything else keeps its existing relative order. Implemented
    -- as a STABLE partition keyed by an explicit priority list so it's trivial to
    -- extend later (lower index = further left). A mod gets the priority of whichever
    -- of its ids is present; non-listed mods sort after all listed ones, order kept.
    local TAB_PRIORITY = { "gt", "gt_dev" }
    local _prio_rank = {}
    for i = 1, #TAB_PRIORITY do _prio_rank[TAB_PRIORITY[i]] = i end
    do
        local pinned, rest = {}, {}
        for _, c in ipairs(cats) do
            if _prio_rank[c.mod_id] then pinned[#pinned + 1] = c else rest[#rest + 1] = c end
        end
        -- Stable order among pinned mods follows the priority list index.
        table.sort(pinned, function(a, b)
            return (_prio_rank[a.mod_id] or math.huge) < (_prio_rank[b.mod_id] or math.huge)
        end)
        local ordered = {}
        for _, c in ipairs(pinned) do ordered[#ordered + 1] = c end
        for _, c in ipairs(rest) do ordered[#ordered + 1] = c end
        cats = ordered
    end

    self._all_categories = cats

    -- (v0.2.71-dev) Paginate the top tab strip ONLY when the MEASURED total tab width
    -- overflows the strip — NOT on a fixed tab COUNT. Tabs are text-aware (variable width,
    -- see _layout_tabs), so the old `total > MAX_TABS` over-paginated (showed a "More 1/2"
    -- tab) even when every label comfortably fit. Pre-measure each label the SAME way
    -- _layout_tabs does (the create_tab text style is hell_shark / size 20 / upper_case;
    -- UIFontByResolution + UIRenderer.text_size + a literal 20px gap each) and sum; if the
    -- sum fits the usable strip (panel width minus the x0 anchor minus a right margin for
    -- the exit-X / More tab), DON'T paginate — show all tabs (per_page = total). The
    -- measure is pcall-guarded; a borrowed-renderer failure falls back to "fits" (measured
    -- stays 0 -> not paged), the desired default now that the set fits. MAX_TABS survives
    -- only as the per-page size for the rare genuine overflow.
    local total = #cats
    local TAB_X0, RIGHT_MARGIN, GAP = 65, 120, 20
    local strip_w = (defs.window and defs.window.w or 1400) - TAB_X0 - RIGHT_MARGIN
    local measured = 0
    pcall(function()
        local renderer = self.ui_top_renderer or self.ui_renderer
        if not renderer then return end
        -- Match create_tab's text style exactly (defs create_tab: hell_shark/20/upper_case).
        local ts = { font_type = "hell_shark", font_size = 20, upper_case = true }
        local font, scaled = UIFontByResolution(ts)
        for _, c in ipairs(cats) do
            local override = tab_labels.exact(c.mod_id)
            local lbl
            if override then
                lbl = override
            else
                local raw = tostring(c.label or c.mod_id):gsub("^Tweaker:%s*", "")
                lbl = _truncate(raw, 16)
            end
            if c.enabled == false then lbl = lbl .. "*" end
            if TextToUpper then lbl = TextToUpper(lbl) end
            measured = measured + UIRenderer.text_size(renderer, lbl, font[1], scaled) + GAP
        end
    end)
    local paged = measured > strip_w
    local per_page = paged and (MAX_TABS - 1) or total
    self._page_count = paged and math.ceil(total / per_page) or 1
    self._page = math.clamp(self._page or 0, 0, math.max(0, self._page_count - 1))

    self._categories = {}
    local start_i = self._page * per_page
    for k = 1, per_page do
        local c = cats[start_i + k]
        if c then self._categories[k] = c end
    end
    self._selected = math.clamp(self._selected or 1, 1, math.max(1, #self._categories))

    self._tabs = {}
    for i = 1, #self._categories do
        local cat = self._categories[i]
        -- A label override (e.g. cim/cim_dev -> "CRAFTING") wins outright and is
        -- applied BEFORE the prefix-strip/truncate so the tab reads exactly the
        -- override; otherwise drop the "Tweaker: " prefix (this menu is all my
        -- tweaker mods) and truncate to fit the tab.
        local override = tab_labels.exact(cat.mod_id)
        local lbl
        if override then
            lbl = override
        else
            local raw = tostring(cat.label or cat.mod_id):gsub("^Tweaker:%s*", "")
            lbl = _truncate(raw, 16)
        end
        if cat.enabled == false then lbl = lbl .. "*" end
        local tab = defs.create_tab(lbl, i)
        if tab then self._tabs[i] = tab end
    end
    self._more_tab_index = nil
    if paged then
        local idx = #self._categories + 1
        local more = defs.create_tab(string.format("More %d/%d >", self._page + 1, self._page_count), idx)
        if more then self._tabs[idx] = more; self._more_tab_index = idx end
    end

    -- (v0.2.67-dev) Text-aware tab widths: measure each label + pack left-to-right with a
    -- 20px gap, exactly like native (options_view.lua:986-994). Replaces the fixed-width
    -- TAB_W slots so short mod names don't leave huge dead gaps between tabs.
    self:_layout_tabs()

    self:_build_rows(self._categories[self._selected])

    -- (Fix 5, v0.2.149-dev) The bottom hint text was removed (native Options has no hint).

    mod:debug("[mt] rebuild: total=%d page=%d/%d displayed=%d selected=%d rows=%d",
        total, self._page + 1, self._page_count, #self._categories, self._selected, #self._rows)
end

-- ---------------------------------------------------------------
-- (v0.2.67-dev) Measure each tab's label width and pack the tabs left-to-right with a
-- 20px gap, mirroring native OptionsView._setup_text_buttons_width (options_view.lua:986-
-- 994 / 997-1027): width = first return of UIRenderer.text_size(renderer, text, font[1],
-- scaled_font_size) where font,scaled = UIFontByResolution(text_style); x = running total;
-- running += width + 20. We write each tab scenegraph node's size[1] (= measured width)
-- and local_position[1] (= packed x). The whole thing is pcall-guarded — a borrowed-
-- renderer measure failure leaves the fixed-width fallback layout untouched.
-- ---------------------------------------------------------------
function HeroViewStateModTweaker:_layout_tabs()
    local renderer = self.ui_top_renderer or self.ui_renderer
    local sg = self.ui_scenegraph
    if not (renderer and sg and self._tabs) then return end
    pcall(function()
        -- Anchor: the first tab node's original packed x (= TAB_X0 = 65 from the defs).
        local first_node = sg["mt_tab_1"]
        local total = (first_node and first_node.local_position and first_node.local_position[1]) or 65
        for i = 1, #self._tabs do
            local tab = self._tabs[i]
            local node = sg["mt_tab_" .. i]
            if tab and node then
                local ts = tab.style and tab.style.text
                local text = tostring(tab.content.text or "")
                -- Match the rendered string: tabs are upper_case (TextToUpper), no localize.
                if ts and ts.upper_case and TextToUpper then text = TextToUpper(text) end
                local font, scaled = UIFontByResolution(ts)
                local w = UIRenderer.text_size(renderer, text, font[1], scaled)
                node.size[1] = w
                node.local_position[1] = total
                total = total + w + 20   -- literal 20px gap (options_view.lua:993)
            end
        end
    end)
end

-- ---------------------------------------------------------------
-- Render-state probe (debug-gated). Logs on-screen geometry so the log alone
-- shows whether elements are positioned/sized/visible — no screenshot needed.
-- ---------------------------------------------------------------
function HeroViewStateModTweaker:_dump_state(reason)
    local sg = self.ui_scenegraph
    local function wp(id)
        local ok, p = pcall(UISceneGraph.get_world_position, sg, id)
        if ok and p then return string.format("{%.0f,%.0f,%.0f}", p[1], p[2], p[3]) end
        return "?"
    end
    local function sz(id)
        local ok, s = pcall(UISceneGraph.get_size, sg, id)
        if ok and s then return string.format("{%.0f,%.0f}", s[1], s[2]) end
        return "?"
    end
    mod:info("[mt:dump] (%s) substate categories=%d selected=%d tabs=%d rows=%d chrome=%d exit=%s scrollbar=%s",
        tostring(reason),
        #(self._categories or {}), self._selected or -1, #(self._tabs or {}), #(self._rows or {}),
        #(self._chrome or {}), tostring(self._exit ~= nil), tostring(self._scrollbar ~= nil))
    mod:info("[mt:dump] world: background=%s(%s) top_panel=%s(%s) list_mask=%s(%s) list_start=%s | screen=1920x1080",
        wp("background"), sz("background"), wp("background_top_panel"), sz("background_top_panel"),
        wp("list_mask"), sz("list_mask"), wp("mt_list_start"))
    for i = 1, math.min(#(self._tabs or {}), 8) do
        mod:info("[mt:dump]   tab[%d] '%s' world=%s", i, tostring(self._tabs[i].content.text_field), wp("mt_tab_" .. i))
    end
    for i = 1, math.min(#(self._rows or {}), 12) do
        local row = self._rows[i]
        local off = row.style and row.style.offset
        mod:info("[mt:dump]   row[%d] type=%s id=%s flag=%s value=%s offset=%s",
            i, tostring(row._wtype), tostring(row._setting_id),
            tostring(row.content.flag), tostring(row.content.value),
            off and string.format("{%.0f,%.0f}", off[1], off[2]) or "?")
    end
end

-- ---------------------------------------------------------------
-- Scrollbar probe (v0.2.73-dev, debug-gated, INSTRUMENT ONLY — no behavior change).
-- TWIN of ModTweakerView:_dump_scrollbar (standalone in-mission view). Logs the REAL
-- runtime scrollbar render-state so the next in-game repro reveals (a) the actual menu
-- background color to contrast the bar against (the prior "fix" INFERRED ~{10,10,10}
-- from a comment — never measured; the real `background` chrome rect is {255,15,15,15},
-- panels are {10,10,10}), (b) whether the bar is drawn at all and WHERE (on-screen vs
-- off-panel / behind a widget), and (c) whether the thumb height is sane. Fired once per
-- open from the SAME site as _dump_state.
-- ---------------------------------------------------------------
function HeroViewStateModTweaker:_dump_scrollbar(reason)
    local sg = self.ui_scenegraph
    local function wp(id)
        local ok, p = pcall(UISceneGraph.get_world_position, sg, id)
        if ok and p then return string.format("{%.0f,%.0f,%.0f}", p[1], p[2], p[3]) end
        return "?"
    end
    local function sz(id)
        local ok, s = pcall(UISceneGraph.get_size, sg, id)
        if ok and s then return string.format("{%.0f,%.0f}", s[1], s[2]) end
        return "?"
    end
    local function color_of(style_tbl)
        if type(style_tbl) ~= "table" then return "?" end
        local c = style_tbl.color
        if type(c) == "table" and c[1] then
            return string.format("{A%d,R%d,G%d,B%d}", c[1], c[2] or 0, c[3] or 0, c[4] or 0)
        end
        return "?"
    end

    -- (a) BACKGROUND chrome rect = the contrast baseline (CHROME_ORDER[1], color at style.rect.color).
    local bg = self._chrome and self._chrome[1]
    local bg_style = bg and bg.style and bg.style.rect
    mod:info("[mt:scrollbar] (%s) BACKGROUND chrome[1] color=%s sg_world=%s sg_size=%s",
        tostring(reason), color_of(bg_style), wp("background"), sz("background"))
    mod:info("[mt:scrollbar]   top_panel=%s(%s) bottom_panel=%s(%s) list_mask=%s(%s)",
        wp("background_top_panel"), sz("background_top_panel"),
        wp("background_bottom_panel"), sz("background_bottom_panel"),
        wp("list_mask"), sz("list_mask"))

    -- (b) The scrollbar widget: track + thumb color, node world pos/size, styles' z (offset[3]).
    local sb = self._scrollbar
    local st = sb and sb.style
    local track_z = st and st.track and st.track.offset and st.track.offset[3]
    local thumb_z = st and st.thumb and st.thumb.offset and st.thumb.offset[3]
    mod:info("[mt:scrollbar]   TRACK color=%s sg=%s world=%s size=%s track_z=%s thumb_z=%s",
        color_of(st and st.track), defs.scrollbar_sg, wp(defs.scrollbar_sg), sz(defs.scrollbar_sg),
        tostring(track_z), tostring(thumb_z))
    -- THUMB style.size[2] is the RESOLVED height AFTER the local_offset pass mutated it
    -- (v0.2.77-dev). If this still reads the full track_h on an overflowing menu, the
    -- offset_function isn't running (the exact bug fixed in v0.2.77). _resolved_thumb_h
    -- in content is written by that same pass as a cross-check.
    local resolved_h = sb and sb.content and sb.content._resolved_thumb_h
    local resolved_off = sb and sb.content and sb.content._resolved_thumb_off
    mod:info("[mt:scrollbar]   THUMB color=%s style_size=%s style_off=%s resolved_h=%s resolved_off=%s",
        color_of(st and st.thumb),
        (st and st.thumb and st.thumb.size) and string.format("{%.0f,%.0f}", st.thumb.size[1], st.thumb.size[2]) or "?",
        (st and st.thumb and st.thumb.offset) and string.format("{%.0f,%.0f,%.0f}", st.thumb.offset[1], st.thumb.offset[2], st.thumb.offset[3]) or "?",
        resolved_h and string.format("%.1f", resolved_h) or "nil(pass-not-run)",
        resolved_off and string.format("%.1f", resolved_off) or "nil")
    -- (v0.2.78-dev) THUMB WORLD-Y top+bottom so position is verifiable from data. The
    -- node is +Y-up; the thumb's bottom-left origin sits `resolved_off` above the node
    -- world Y, the top is +resolved_h further up. Compare against the track world-Y span
    -- (node_y .. node_y + track_h): on overflow the thumb should be flush at the TOP
    -- (scroll=0) i.e. thumb_top ~= track_top, and flush at the BOTTOM (scroll=1) i.e.
    -- thumb_bottom ~= track_bottom, never outside [track_y, track_y + track_h].
    do
        local ok_n, np = pcall(UISceneGraph.get_world_position, sg, defs.scrollbar_sg)
        local track_h = (st and st.track and st.track.size and st.track.size[2]) or 0
        if ok_n and np and resolved_off and resolved_h then
            local node_y = np[2]
            local thumb_bottom = node_y + resolved_off
            local thumb_top = thumb_bottom + resolved_h
            mod:info("[mt:scrollbar]   THUMB world-Y bottom=%.1f top=%.1f vs TRACK span [%.1f, %.1f] scroll_value=%s",
                thumb_bottom, thumb_top, node_y, node_y + track_h,
                sb and sb.content and tostring(sb.content.scroll_value) or "nil")
        else
            mod:info("[mt:scrollbar]   THUMB world-Y=? (node world pos or resolved thumb values unavailable — pass not run yet?)")
        end
    end

    -- (c) Scroll math: drawn only when _max_scroll>0; thumb_frac = visible/content; thumb_px = track_h * clamp(frac,0.06,1).
    local content_h = self._content_h or 0
    local visible_h = self._visible_h or 0
    local max_scroll = self._max_scroll or 0
    local track_h = (sb and sb.style and sb.style.track and sb.style.track.size and sb.style.track.size[2]) or 0
    local thumb_frac = (content_h > 0) and (visible_h / content_h) or 1
    local clamped = math.clamp(thumb_frac, 0.06, 1)
    local thumb_px = track_h * clamped
    mod:info("[mt:scrollbar]   content_h=%.0f visible_h=%.0f max_scroll=%.0f track_h=%.0f thumb_frac=%.3f (clamped %.3f) thumb_px=%.1f will_draw=%s",
        content_h, visible_h, max_scroll, track_h, thumb_frac, clamped, thumb_px, tostring(max_scroll > 0))

    -- On-screen check: is the mt_scrollbar node inside the VISIBLE panel box?
    --
    -- (v0.2.74-dev) Test the bar's CENTRE against `background_frame` (the decorated
    -- panel the player sees), NOT its bottom-left origin against `list_mask`. list_mask
    -- is a 1400px LEFT-aligned node whose right edge juts ~18px off-panel, and
    -- math.point_is_inside_2d_box uses STRICT inequalities so a shared edge reports a
    -- FALSE on_screen=false. Centre-vs-frame is the unambiguous test. (The old probe's
    -- on_screen=false in BOTH states was this strict-edge artifact, not proof the bar
    -- was off-screen.) Kept in sync with the view twin.
    local ok_sbp, sbp = pcall(UISceneGraph.get_world_position, sg, defs.scrollbar_sg)
    local ok_sbs, sbs = pcall(UISceneGraph.get_size, sg, defs.scrollbar_sg)
    local ok_fp, fp = pcall(UISceneGraph.get_world_position, sg, "background_frame")
    local ok_fs, fs = pcall(UISceneGraph.get_size, sg, "background_frame")
    if ok_sbp and sbp and ok_sbs and sbs and ok_fp and fp and ok_fs and fs then
        local cx, cy = sbp[1] + sbs[1] * 0.5, sbp[2] + sbs[2] * 0.5
        local inside = math.point_is_inside_2d_box({ cx, cy }, fp, fs)
        mod:info("[mt:scrollbar]   on_screen=%s sb_centre={%.0f,%.0f} vs frame origin={%.0f,%.0f} size={%.0f,%.0f}",
            tostring(inside), cx, cy, fp[1], fp[2], fs[1], fs[2])
    else
        mod:info("[mt:scrollbar]   on_screen=? (world/size lookup failed)")
    end
end

-- ---------------------------------------------------------------
-- Input (hotspot flags are populated during the draw pass)
-- ---------------------------------------------------------------

-- ---------------------------------------------------------------
-- TYPE-TO-EDIT a slider's numeric value (v0.2.66-dev). Click the value box to focus,
-- type digits (+ optional "." / "-" per the slider's decimals/range), commit on Enter
-- or focus-loss, cancel on Escape. ADDITIVE over the existing drag + arrow stepping —
-- those are suppressed only while THIS row is the active editor. Only ONE row edits at
-- a time (self._editing_row). Filter mirrors VMF (vmf_options_view.lua:4532-4556):
-- digits capped at num_decimals after the dot, "-" gated on min<0, "." once when
-- decimals>0, Backspace, 16-char cap. PORTED VERBATIM from _mod_tweaker_view.lua so the
-- standalone view (in-mission) and this HeroView sub-state (keep) behave identically.
local Interaction = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_state_interaction")
Interaction.install(HeroViewStateModTweaker, {
    defs = defs,
    UIRenderer = UIRenderer,
    UISceneGraph = UISceneGraph,
    UIInverseScaleVectorToResolution = UIInverseScaleVectorToResolution,
    math = math,
    cat_set = _cat_set,
    play_click = _play_click,
    play_hover = _play_hover,
})
return { class_name = "HeroViewStateModTweaker" }
