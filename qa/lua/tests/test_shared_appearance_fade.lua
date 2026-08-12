local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(H, repo_root)
    local canonical_path = repo_root .. "/tools/shared_lib/_lib_appearance_fade.lua"
    local Library = dofile(canonical_path)

    local function unit(name, live)
        return setmetatable({ name = name, live = live ~= false }, {
            __tostring = function(value) return value.name end,
        })
    end

    local function alive(value) return value and value.live == true end

    H.test("appearance fade collector submits one complete deterministic snapshot", function()
        local right, right_ammo = unit("right"), unit("right_ammo")
        local left, dead = unit("left"), unit("dead", false)
        local hat, frame = unit("hat"), unit("frame")
        local units = Library.collect({
            equipment = {
                right_hand_wielded_unit_3p = right,
                right_hand_ammo_unit_3p = right_ammo,
                left_hand_wielded_unit_3p = left,
                left_hand_ammo_unit_3p = dead,
            },
            attachments = { slots = {
                slot_frame = { unit = frame },
                slot_hat = { unit = hat },
            } },
            extra_units = { hat, right, dead },
        }, alive)
        H.equal(#units, 5)
        H.equal(units[1], right)
        H.equal(units[2], right_ammo)
        H.equal(units[3], left)
        H.equal(units[4], frame)
        H.equal(units[5], hat)
    end)

    H.test("appearance fade enrollment dedupes unchanged lifecycle replays", function()
        local owner, sword, hat = unit("owner"), unit("sword"), unit("hat")
        local calls = {}
        local inventory = { _equipment = {
            right_hand_wielded_unit_3p = sword,
        } }
        local attachments = { _attachments = { slots = {
            slot_hat = { unit = hat },
        } } }
        local fade = { new_linked_units = function(_, got_owner, units)
            calls[#calls + 1] = { owner = got_owner, units = units }
        end }
        local adapter = Library.new({
            alive = alive,
            get_extension = function(_, name)
                if name == "inventory_system" then return inventory end
                if name == "attachment_system" then return attachments end
                if name == "fade_system" then return {} end
            end,
            get_fade_system = function() return fade end,
        })
        local ok1, first = adapter:enroll(owner, "spawn", {})
        local ok2, second = adapter:enroll(owner, "wield", {})
        H.equal(ok1, true)
        H.equal(first.reason, "applied")
        H.equal(ok2, true)
        H.equal(second.reason, "unchanged")
        H.equal(#calls, 1)
        H.equal(#calls[1].units, 2)
        H.equal(calls[1].units[1], sword)
        H.equal(calls[1].units[2], hat)

        local shield = unit("shield")
        inventory._equipment.left_hand_wielded_unit_3p = shield
        local ok3, changed = adapter:enroll(owner, "style_change", {})
        H.equal(ok3, true)
        H.equal(changed.reason, "applied")
        H.equal(#calls, 2)
        H.equal(#calls[2].units, 3)

		local ok4, forced = adapter:enroll(owner, "post_native_replace", {
			force = true,
		})
		H.equal(ok4, true)
		H.equal(forced.reason, "applied")
		H.equal(#calls, 3)
    end)

    H.test("appearance fade failures stay fail-open and retryable", function()
        local owner, sword = unit("owner"), unit("sword")
        local attempts, reports = 0, {}
        local fade = { new_linked_units = function()
            attempts = attempts + 1
            if attempts == 1 then error("transient") end
        end }
        local adapter = Library.new({
            alive = alive,
            get_extension = function(got_owner, name)
                if got_owner == owner then
                    if name == "inventory_system" then
                        return { _equipment = { right_hand_wielded_unit_3p = sword } }
                    end
                    if name == "fade_system" then return {} end
                end
                error("foreign extension unavailable")
            end,
            get_fade_system = function() return fade end,
            diag_budget = 4,
            report = function(row) reports[#reports + 1] = row.reason end,
        })
        local ok1, first = adapter:enroll(owner, "spawn", {})
        local ok2, second = adapter:enroll(owner, "spawn", {})
        H.equal(ok1, false)
        H.equal(first.reason, "apply_failed")
        H.equal(ok2, true)
        H.equal(second.reason, "applied")
        H.equal(attempts, 2)
        H.deep_equal(reports, { "apply_failed", "applied" })

        local foreign = unit("pusfume_or_foreign_owner")
        local ok3, third = adapter:enroll(foreign, "foreign_spawn", {})
        H.equal(ok3, false)
        H.equal(third.reason, "no_linked_units")
        H.equal(attempts, 2)
    end)

    H.test("appearance fade rejects an unregistered owner before the native boundary", function()
        local owner, sword = unit("foreign_owner"), unit("foreign_sword")
        local native_calls = 0
        local adapter = Library.new({
            alive = alive,
            get_extension = function(_, name)
                if name == "inventory_system" then
                    return { _equipment = { right_hand_wielded_unit_3p = sword } }
                end
                return nil
            end,
            get_fade_system = function()
                return { new_linked_units = function() native_calls = native_calls + 1 end }
            end,
        })
        local ok, report = adapter:enroll(owner, "foreign_spawn", {})
        H.equal(ok, false)
        H.equal(report.reason, "owner_fade_extension_unavailable")
        H.equal(native_calls, 0)
    end)

    H.test("appearance fade forced reapply survives vanilla husk linked-set reset (#922)", function()
        -- Vanilla wield calls `_reapply_fade` AFTER `_wield_slot`
        -- (simple_husk_inventory_extension.lua:319 then :353) and REPLACES the
        -- fade system's linked set with only the four inventory fields
        -- (:292-311), evicting the wield-edge enrollment. The fingerprint
        -- dedup must not swallow the post-replacement re-enroll.
        local owner, sword, hat = unit("owner"), unit("sword"), unit("hat")
        local linked
        local fade = { new_linked_units = function(_, _, units) linked = units end }
        local inventory = { _equipment = { right_hand_wielded_unit_3p = sword } }
        local attachments = { _attachments = { slots = { slot_hat = { unit = hat } } } }
        local adapter = Library.new({
            alive = alive,
            get_extension = function(_, name)
                if name == "inventory_system" then return inventory end
                if name == "attachment_system" then return attachments end
                if name == "fade_system" then return {} end
            end,
            get_fade_system = function() return fade end,
        })
        -- wield-edge enrollment (the _wield_slot / spawn-path hook)
        local ok1, first = adapter:enroll(owner, "remote_husk_wield", {})
        H.equal(ok1, true)
        H.equal(first.reason, "applied")
        H.equal(#linked, 2)
        -- vanilla _reapply_fade replaces the linked set behind the adapter
        linked = { sword }
        -- an unforced replay is fingerprint-deduped: the eviction would stick
        local ok2, second = adapter:enroll(owner, "remote_husk_wield", {})
        H.equal(ok2, true)
        H.equal(second.reason, "unchanged")
        H.equal(#linked, 1, "the dedup skip must leave vanilla's reset visible")
        -- the post-_reapply_fade hook re-enrolls with force=true
        local ok3, third = adapter:enroll(owner, "remote_husk_reapply", { force = true })
        H.equal(ok3, true)
        H.equal(third.reason, "applied")
        H.equal(#linked, 2, "forced reapply must restore the complete snapshot")
    end)

    H.test("appearance fade adapter owns no RPC hook or per-frame loop", function()
        local source = read(canonical_path):lower()
        H.equal(source:find("network_register", 1, true), nil)
        H.equal(source:find("network_send", 1, true), nil)
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("function m.update", 1, true), nil)
    end)

    H.test("all custom render owners load and invoke the canonical fade adapter", function()
        local consumers = {
            {
                copy = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_lib_appearance_fade.lua",
                entry = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_world_equipment_owner.lua",
                marker = "_om.appearance_fade.created",
            },
            {
                copy = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_appearance_fade.lua",
                entry = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_appearance_fade_runtime.lua",
                marker = "adapter:enroll",
            },
            {
                copy = repo_root .. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_appearance_fade.lua",
                entry = repo_root .. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua",
                marker = "_appearance_fade:enroll",
            },
        }
        local canonical = read(canonical_path)
        local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
        for _, consumer in ipairs(consumers) do
            H.equal(read(consumer.copy), canonical,
                "consumer drifted from canonical fade adapter")
            local relative = consumer.copy:sub(#repo_root + 2):gsub("\\", "/")
            H.truthy(manifest:find('"' .. relative .. '"', 1, true),
                "consumer missing from shared-library manifest")
            H.truthy(read(consumer.entry):find(consumer.marker, 1, true),
                "custom render owner does not enroll its units")
        end
        local cosmetics_runtime = read(consumers[2].entry)
        H.truthy(cosmetics_runtime:find("owns_dynamic_hat(item_name)", 1, true),
            "Cosmetics owner enrollment is not exact-identity gated")
        local cosmetics_entry = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        -- #1159: the fade runtime is configured from the attachment-slot LA
        -- spawn/sync owner now, because its enroll point is that owner's husk hat
        -- hook and the install must keep its exact sequence position.
        local cosmetics_attachment_sync = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua")
        H.truthy(cosmetics_attachment_sync:find("APPEARANCE_FADE_RUNTIME.install", 1, true)
            and cosmetics_runtime:find('"_reapply_fade"', 1, true)
            and cosmetics_runtime:find("force = true", 1, true),
            "Cosmetics does not restore attachments after vanilla husk replacement")
        H.equal(cosmetics_entry:find("APPEARANCE_FADE_RUNTIME.install", 1, true), nil,
            "the fade runtime must be installed exactly once, by its owner")
        H.truthy(cosmetics_attachment_sync:find(
            "APPEARANCE_FADE_RUNTIME.enroll_husk_attachment(husk_unit, self, spawned_hat)", 1, true),
            "the husk hat spawn seam must still enroll the spawned attachment")
		local woc = read(consumers[3].entry)
		H.truthy(woc:find('"SimpleInventoryExtension", "_wield_slot"', 1, true)
			and woc:find('"owner_wield"', 1, true),
			"WOC owner does not enroll the final post-wield snapshot")
        -- #922 husk-fade eviction: vanilla `_reapply_fade` runs AFTER
        -- `_wield_slot` (simple_husk_inventory_extension.lua:319 then :353)
        -- and resets the linked set, so BOTH custom-render husk owners must
        -- post-hook it and re-enroll with force=true (the Cosmetics pattern).
        local cwv_fade = read(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_fade.lua")
        H.truthy(cwv_fade:find('"SimpleHuskInventoryExtension", "_reapply_fade"', 1, true)
            and cwv_fade:find("M.husk_reapply(self, equipment)", 1, true)
            and cwv_fade:find('"remote_husk_reapply"', 1, true)
            and cwv_fade:find("force = true", 1, true),
            "CWV does not force re-enrollment after vanilla husk fade replacement (#922)")
        H.truthy(woc:find('"SimpleHuskInventoryExtension", "_reapply_fade"', 1, true)
            and woc:find('"remote_husk_reapply"', 1, true)
            and woc:find("force = true", 1, true),
            "WOC does not force re-enrollment after vanilla husk fade replacement (#922)")
    end)
end
