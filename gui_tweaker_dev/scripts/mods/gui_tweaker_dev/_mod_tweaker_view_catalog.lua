-- _mod_tweaker_view_catalog.lua - deferred shared presentation category assembly.
--
-- Owns VMF discovery, CKC/UI Tweaks folds and Equipment synthesis. The parent
-- binds its existing collaborators once; discovery still runs only inside the
-- rebuild pcall. No hooks, lifecycle, settings writes or eager live-tree reads.
-- Owned by: entry manifest. Consumed via private independent View/State binders.
local M = {}

function M.bind(deps)
    local mod, get_mod, _nf = deps.mod, deps.get_mod, deps.nf
    local disabled_sections, external_group = deps.disabled_sections, deps.external_group
    local _printf, math = deps.printf, deps.math

    -- Third-party mod whose options fold into a gut category (NOT a tab). #339.
    local _CKC_NAME = "Crosshair Kill Confirmation"

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
    -- the owning mod object (see _owner + the staged-change helpers). TWIN of the HeroView
    -- sub-state's identical block — keep both in sync.
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

    -- (#312) Fold the STOCK UI Tweaks (HideBuffs) live VMF widget tree into GUT and
    -- route its setting get/set calls to the stock mod, never GUT's private fallback
    -- copies. This is a dynamic tree splice, not a copied setting-id allow-list, so a
    -- future supported widget type appears without editing GUT. Reads show HideBuffs'
    -- live value; Apply commits through HB:set(id, v, true), firing its ordinary VMF
    -- callback and persistence path. The per-node _owners model is shared with the
    -- Equipment merge (#208) and CKC injection (#339).
    -- HideBuffs becomes the single owner of its live tree. No-op when HideBuffs is absent
    -- or disabled: gut's own copies drive its absorbed hb/ fork exactly as before. Runs AFTER
    -- _inject_ckc_into_gut so it MERGES into any CKC-set _owner_mod_ids. Marker
    -- [UITWEAKS-BRIDGE-312]. Byte-parallel twin with the one in _mod_tweaker_state.lua.
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
        local gut_cat
        for _, c in ipairs(out) do
            if c.mod_id == "gut" or c.mod_id == "gut_dev" then gut_cat = c; break end
        end
        if not gut_cat or type(gut_cat.widgets) ~= "table" then return end

        -- Consume the stock mod's CURRENT VMF widget list, not the old absorbed fork's
        -- copied checkbox catalogue. A future UI Tweaks group, slider, dropdown, or
        -- keybind therefore appears without a GUT code change. The planner shallow-copies
        -- every VMF node, rebases it under hb_group, removes stale mirrored rows, and
        -- preserves GUT's own Sync & Vanilla Mirrors subgroup. [UITWEAKS-LIVE-TREE-312]
        local vmf = get_mod("VMF")
        local live = external_group.find_mod_list(vmf and vmf.options_widgets_data,
            "HideBuffs", _nf)
        local plan = external_group.replace_group_children({
            widgets = gut_cat.widgets,
            live_list = live,
            group_id = "hb_group",
            preserve_group_ids = { gut_uitweaks_integration_group = true },
            field = _nf,
            owners = gut_cat._owners,
            owner_mod_ids = gut_cat._owner_mod_ids,
            base_owner_id = gut_cat.mod_id,
            owner_id = "HideBuffs",
            owner_obj = HB,
            profile_excluded_owners = gut_cat._profile_excluded_owners,
            exclude_owner_from_profiles = true,
        })
        if not plan.changed then
            if not mod._gut_uitweaks_live_tree_missing_logged then
                mod._gut_uitweaks_live_tree_missing_logged = true
                _printf("[gut:312] live UI Tweaks tree unavailable reason=%s; keeping authored fallback",
                    tostring(plan.reason))
            end
            local fallback = external_group.bridge_known_fallback({
                widgets = gut_cat.widgets,
                setting_names = HB.SETTING_NAMES,
                field = _nf,
                owners = gut_cat._owners,
                owner_mod_ids = gut_cat._owner_mod_ids,
                base_owner_id = gut_cat.mod_id,
                owner_id = "HideBuffs",
                owner_obj = HB,
                profile_excluded_owners = gut_cat._profile_excluded_owners,
                exclude_owner_from_profiles = true,
            })
            if fallback.changed then
                gut_cat._owners = fallback.owners
                gut_cat._owner_mod_ids = fallback.owner_mod_ids
                gut_cat._profile_excluded_owners = fallback.profile_excluded_owners
            end
            return
        end
        gut_cat.widgets = plan.widgets
        gut_cat._owners = plan.owners
        gut_cat._owner_mod_ids = plan.owner_mod_ids
        -- UI Tweaks owns its own profiles. Its live rows remain editable here, but
        -- GUT's ten per-tab profile slots never capture or restore HideBuffs values.
        gut_cat._profile_excluded_owners = plan.profile_excluded_owners
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

    return _vmf_categories
end

-- Entry-only fixed State tuple adapter; never loads a module or caches a class.
local bind_catalog = M.bind
function M.bind_state_result(status, ...)
    if not status or type((...)) ~= "table" then return status, ... end
    local metadata, binder = ...
    if type(binder) ~= "function" then return false, "private state category binder unavailable" end
    local bound, err = pcall(binder, bind_catalog)
    if not bound then return false, err end
    return status, metadata, select(3, ...)
end

return M
