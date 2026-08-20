return function(H, repo_root)
    local module_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_appearance.lua"
    local main_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
    local Policy = assert(loadfile(module_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CWV #579 resolves the exact saved dual-axes skin from backend identity", function()
        local appearance = Policy.resolve({
            backend_id = "cwv_es_dual_axes_001",
            skin_from_backend = function() return "dual_red" end,
            weapon_skins = { dual_red = {
                right_hand_unit = "axe_red_right",
                left_hand_unit = "axe_blue_left",
            } },
        })
        H.equal(appearance.skin, "dual_red")
        H.equal(appearance.right_hand_unit, "axe_red_right")
        H.equal(appearance.left_hand_unit, "axe_blue_left")
    end)

    H.test("CWV #579 all render surfaces preserve both exact hands", function()
        local appearance = {
            skin = "dual_exact", right_hand_unit = "axe_right", left_hand_unit = "axe_left",
        }
        local resident = function(unit) return unit .. "_3p" end
        for surface, adapter in pairs(Policy.SURFACES) do
            if adapter == "item_units" then
                local result = { right_hand_unit = "base_r", left_hand_unit = "base_l" }
                H.equal(Policy.apply_item_units(appearance, result), 2, surface)
                H.equal(result.right_hand_unit, "axe_right", surface)
                H.equal(result.left_hand_unit, "axe_left", surface)
            else
                local recipe = {
                    { right_hand = true, unit_name = "base_r_3p" },
                    { left_hand = true, unit_name = "base_l_3p" },
                }
                H.equal(Policy.apply_spawn_data(appearance, recipe, resident), 2, surface)
                H.equal(recipe[1].unit_name, "axe_right_3p", surface)
                H.equal(recipe[2].unit_name, "axe_left_3p", surface)
            end
        end
    end)

    H.test("CWV #237/#419 spawn targets honor the residency resolver, never blind concat", function()
        -- The historical collapsed guard (`resolver or base .. "_3p"`) rewrote
        -- the spawn target even when the resolver declined, voiding the
        -- documented degrade-to-base safety contract on both preview adapters.
        local descriptor = assert(Policy.resolve_spawn_descriptor({
            variant = { item_key = "cwv_gate", right_hand_unit = "variant_right" },
            base = { right_hand_unit = "base_right" },
        }))
        local inventory = { { right_hand = true, unit_name = "base_right_3p" } }
        local browser = { { unit_name = "base_right_3p" } }
        H.equal(Policy.apply_spawn_descriptor(descriptor, inventory, nil, "hand_flags"), 0,
            "missing resolver must fail closed (no spawn-target rewrite)")
        H.equal(Policy.apply_spawn_descriptor(descriptor, browser,
            function() return nil end, "base_identity"), 0,
            "resolver decline must degrade to the base mesh")
        H.equal(inventory[1].unit_name, "base_right_3p")
        H.equal(browser[1].unit_name, "base_right_3p")
        -- Legacy surface API carries the same contract.
        local legacy = { { right_hand = true, unit_name = "base_right_3p" } }
        H.equal(Policy.apply_spawn_data(
            { right_hand_unit = "variant_right" }, legacy), 0,
            "apply_spawn_data without a resolver must not blind-concat")
        H.equal(legacy[1].unit_name, "base_right_3p")
    end)

	H.test("CWV #597 resource fallback rows cannot be re-admitted by either preview adapter", function()
		local descriptor = assert(Policy.resolve_spawn_descriptor({
			variant = {
				item_key = "cwv_fallback_guard", right_hand_unit = "variant_right",
				no_ammo_unit = true,
			},
			base = { right_hand_unit = "base_right" },
		}))
		for _, adapter in ipairs({ "hand_flags", "base_identity" }) do
			local row = {
				right_hand = adapter == "hand_flags" or nil,
				is_ammo_unit = true,
				unit_name = "base_right_3p",
				[Policy.PREVIEW_FALLBACK_MARKER] = "base_right_3p",
			}
			H.equal(Policy.apply_spawn_descriptor(descriptor, { row },
				function(unit) return unit .. "_3p" end, adapter), 0, adapter)
			H.equal(row.unit_name, "base_right_3p", adapter)
			H.equal(row.is_ammo_unit, true,
				"fallback lock must preserve the exact vanilla row shape: " .. adapter)
		end

		local stale_marker = {
			right_hand = true, unit_name = "base_right_3p",
			[Policy.PREVIEW_FALLBACK_MARKER] = "another_generation_3p",
		}
		H.equal(Policy.apply_spawn_descriptor(descriptor, { stale_marker },
			function(unit) return unit .. "_3p" end, "hand_flags"), 1)
		H.equal(stale_marker.unit_name, "variant_right_3p",
			"only an exact current-row fallback marker may suppress a later generation")
	end)

    H.test("CWV #237/#419 preview gate: sentinel/non-resident degrade, packaged families resolve", function()
        local gate = Policy.resolve_preview_3p
        local yes = function() return true end
        local no = function() return false end
        -- 1. The husk resolver's answer is final (co-op unchanged); the spawn
        --    floor must not even be consulted.
        H.equal(gate("units/weapons/player/w/w", function(u) return u .. "_3p" end,
            function() error("spawn floor must not be consulted") end),
            "units/weapons/player/w/w_3p")
        -- 2. Collapsed-guard shape must fail: silent resolver + declined floor.
        H.equal(gate("units/weapons/player/w/w", nil, no), nil)
        -- 3. Sentinel degrades even when spawnable.
        H.equal(gate("units/weapons/player/wpn_invisible_weapon/wpn_invisible_weapon", nil, yes), nil)
        -- 4. Arbitrary non-player prefixes degrade even when spawnable.
        H.equal(gate("units/beings/player/x/x", nil, yes), nil)
        -- 5. Floor-confirmed vanilla targets resolve (preview swap preserved).
        H.equal(gate("units/weapons/player/w/w", nil, yes), "units/weapons/player/w/w_3p")
        -- 6. Packaged units/cwv_ families resolve through the floor...
        H.equal(gate("units/cwv_crowbill/imperial_01/imperial_01", nil, yes),
            "units/cwv_crowbill/imperial_01/imperial_01_3p")
        H.equal(gate("units/cwv_es_greataxe/axe_01/axe_01", nil, yes),
            "units/cwv_es_greataxe/axe_01/axe_01_3p")
        -- ...and the musket-class floor decline (#474 donor gate) degrades.
        H.equal(gate("units/cwv_es_musket_custom/cwv_es_musket_custom", nil, no), nil)
        -- 7. A missing floor fails closed.
        H.equal(gate("units/weapons/player/w/w", nil, nil), nil)
        H.equal(gate(nil, nil, yes), nil)
    end)

    H.test("CWV #660 preview adapters consume one immutable unit descriptor", function()
        local descriptor = assert(Policy.resolve_spawn_descriptor({
            variant = {
                item_key = "cwv_test",
                right_hand_unit = "variant_right",
                left_hand_unit = "variant_left",
            },
            base = {
                right_hand_unit = "base_right",
                left_hand_unit = "base_left",
            },
        }))
        H.equal(descriptor.fingerprint:sub(1, 3), "a1:")
        H.equal(#descriptor.fingerprint, 19)
        local fingerprint = descriptor.fingerprint

        local inventory = {
            { right_hand = true, unit_name = "anything_right_3p" },
            { left_hand = true, unit_name = "anything_left_3p" },
            { right_hand = true, is_ammo_unit = true, unit_name = "ammo" },
        }
        local browser = {
            { unit_name = "base_left_3p" },
            { unit_name = "base_right_3p" },
            { unit_name = "unrelated_3p" },
        }
        local resident = function(unit) return unit .. "_3p" end
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, inventory, resident, Policy.SPAWN_ADAPTERS.inventory_mannequin), 2)
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, browser, resident, Policy.SPAWN_ADAPTERS.athanor_preview), 2)
        H.equal(inventory[1].unit_name, "variant_right_3p")
        H.equal(inventory[2].unit_name, "variant_left_3p")
        H.equal(inventory[3].unit_name, "ammo")
        H.equal(browser[1].unit_name, "variant_left_3p")
        H.equal(browser[2].unit_name, "variant_right_3p")
        H.equal(browser[3].unit_name, "unrelated_3p")
        H.equal(descriptor.fingerprint, fingerprint,
            "surface adapters mutated the canonical descriptor")
    end)

    H.test("CWV #279 no-ammo variants clear inherited ammo flags on WEAPON rows", function()
        local descriptor = assert(Policy.resolve_spawn_descriptor({
            variant = {
                item_key = "cwv_es_outrider_grenade_launcher",
                right_hand_unit = "launcher_right",
                no_ammo_unit = true,
            },
            base = {
                right_hand_unit = "trollhammer_right",
            },
        }))
        H.equal(descriptor.no_ammo_unit, true)

        -- Real engine shape: vanilla stamps `is_ammo_unit = ammo_unit ~= nil`
        -- onto the WEAPON rows themselves (world_hero_previewer.lua:707/731);
        -- there is never a dedicated ammo-only row. Deleting flagged rows would
        -- vanish the weapon from the preview.
        local inventory = {
            { right_hand = true, is_ammo_unit = true,
                unit_name = "trollhammer_right_3p" },
        }
        -- LootItemUnitPreviewer rows carry only unit_name
        -- (loot_item_unit_previewer.lua:290/308) -- no ammo or hand flags.
        local browser = {
            { unit_name = "trollhammer_right_3p" },
        }
        local resident = function(unit) return unit .. "_3p" end
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, inventory, resident, "hand_flags"), 2)
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, browser, resident, "base_identity"), 1)
        H.equal(#inventory, 1, "the weapon row must survive")
        H.equal(#browser, 1, "the weapon row must survive")
        H.equal(inventory[1].is_ammo_unit, nil,
            "inherited ammo identity must be cleared, not the row deleted")
        H.equal(inventory[1].unit_name, "launcher_right_3p")
        H.equal(browser[1].unit_name, "launcher_right_3p")
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, inventory, resident, "hand_flags"), 0,
            "descriptor application must be idempotent")
    end)

    H.test("CWV #279 no-ammo state participates in descriptor identity", function()
        local function descriptor(no_ammo_unit)
            return assert(Policy.resolve_spawn_descriptor({
                variant = {
                    item_key = "cwv_es_outrider_grenade_launcher",
                    right_hand_unit = "launcher_right",
                    no_ammo_unit = no_ammo_unit,
                },
                base = { right_hand_unit = "trollhammer_right" },
            }))
        end
        H.truthy(descriptor(true).fingerprint ~= descriptor(false).fingerprint,
            "remote identity must detect ammo-mesh suppression drift")
    end)

    H.test("CWV #660 exact skin composes independent offhand on both preview adapters", function()
        local descriptor = assert(Policy.resolve_spawn_descriptor({
            explicit_skin = "skin_red",
            weapon_skins = { skin_red = {
                right_hand_unit = "skin_right",
                left_hand_unit = "skin_left",
            } },
            variant = {
                item_key = "cwv_test",
                right_hand_unit = "variant_right",
                left_hand_unit = "variant_left",
            },
            base = {
                right_hand_unit = "base_right",
                left_hand_unit = "base_left",
            },
        }))
        local resident = function(unit) return unit .. "_3p" end
        local inventory = {
            { right_hand = true, unit_name = "variant_right_3p" },
            { left_hand = true, unit_name = "cosmetics_offhand_3p" },
        }
        local browser = {
            { unit_name = "variant_right_3p" },
            { unit_name = "cosmetics_offhand_3p" },
        }
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, inventory, resident, "hand_flags"), 1)
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, browser, resident, "base_identity"), 1)
        H.equal(inventory[1].unit_name, "skin_right_3p")
        H.equal(inventory[2].unit_name, "cosmetics_offhand_3p")
        H.equal(browser[1].unit_name, "skin_right_3p")
        H.equal(browser[2].unit_name, "cosmetics_offhand_3p")
    end)

    H.test("CWV #660 browser hand flags disambiguate identical base units", function()
        local descriptor = assert(Policy.resolve_spawn_descriptor({
            variant = {
                item_key = "cwv_dual",
                right_hand_unit = "right_authored",
                left_hand_unit = "left_authored",
            },
            base = {
                right_hand_unit = "same_base",
                left_hand_unit = "same_base",
            },
        }))
        local recipe = {
            { left_hand = true, unit_name = "same_base_3p" },
            { right_hand = true, unit_name = "same_base_3p" },
        }
        H.equal(Policy.apply_spawn_descriptor(
            descriptor, recipe, function(unit) return unit .. "_3p" end,
            "base_identity"), 2)
        H.equal(recipe[1].unit_name, "left_authored_3p")
        H.equal(recipe[2].unit_name, "right_authored_3p")
    end)

    H.test("CWV #660 unresolved explicit skin fails closed before variant fallback", function()
        local descriptor, reason = Policy.resolve_spawn_descriptor({
            explicit_skin = "missing_skin",
            weapon_skins = {},
            variant = { item_key = "cwv_test", right_hand_unit = "variant" },
            base = { right_hand_unit = "base" },
        })
        H.equal(descriptor, nil)
        H.equal(reason, "skin_unresolved")

        descriptor, reason = Policy.resolve_spawn_descriptor({
            backend_id = "cwv_test_001",
            skin_from_backend = function() return "missing_backend_skin" end,
            weapon_skins = {},
            variant = { item_key = "cwv_test", right_hand_unit = "variant" },
            base = { right_hand_unit = "base" },
        })
        H.equal(descriptor, nil)
        H.equal(reason, "skin_unresolved")
    end)

    H.test("CWV #579 adapters route unit and preview recipes through canonical policy", function()
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            "_om.exact_appearance.resolve({",
            "_om.exact_appearance.apply_item_units(exact, result, true)",
            "_om._cwv_resolve_spawn_descriptor = function",
            "_om.exact_appearance.resolve_spawn_descriptor({",
            "_om.exact_appearance.apply_spawn_descriptor(",
            '"hand_flags"',
            '"base_identity"',
            'issue660_preview_descriptor_adapter_parity',
            'mod:hook("HeroPreviewer", "_spawn_item"',
            'mod:hook("MenuWorldPreviewer", "_spawn_item"',
            'mod:hook("LootItemUnitPreviewer", "spawn_units"',
            '_om._husk_preselect_units(result, item_data, backend_id, skin, career_name)',
            -- #237/#419: both preview adapters must receive the gated preview
            -- resolver, never the raw HUSK_OVERRIDE_REF resident check (whose
            -- nil answer the old call sites collapsed into blind base.."_3p").
            '_om._preview_override_3p, "hand_flags"',
            '_om._preview_override_3p, "base_identity"',
            '_om._preview_override_3p = function',
        }) do
            H.truthy(source:find(marker, 1, true), "missing canonical surface route: " .. marker)
        end
        H.equal(source:find('_om._resident_override_3p, "', 1, true), nil,
            "raw resident resolver must never be passed to a preview adapter (#237/#419)")
    end)

    H.test("CWV #579 explicit render identity wins over stale stores", function()
        local appearance = Policy.resolve({
            explicit_skin = "selected", stored_skin = "stale", backend_id = "bid",
            skin_from_backend = function() return "backend" end,
            weapon_skins = { selected = { right_hand_unit = "chosen" } },
        })
        H.equal(appearance.skin, "selected")
    end)

    H.test("CWV #579 composes Cosmetics independent offhand without clobbering", function()
        local appearance = { right_hand_unit = "runed", left_hand_unit = "runed" }
        local fallback = { right_hand_unit = "base", left_hand_unit = "base" }
        local recipe = {
            { right_hand = true, unit_name = "base_3p" },
            { left_hand = true, unit_name = "independent_offhand_3p" },
        }
        local resident = function(unit) return unit .. "_3p" end
        H.equal(Policy.apply_spawn_data(appearance, recipe, resident, fallback), 1)
        H.equal(recipe[1].unit_name, "runed_3p")
        H.equal(recipe[2].unit_name, "independent_offhand_3p")

        local units = { right_hand_unit = nil, left_hand_unit = "independent_offhand" }
        H.equal(Policy.apply_item_units(appearance, units, true), 1)
        H.equal(units.right_hand_unit, "runed")
        H.equal(units.left_hand_unit, "independent_offhand")
    end)
end
