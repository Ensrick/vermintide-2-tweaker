-- Cosmetics lifecycle owner for shared FadeSystem snapshots (issue #922).
-- Keeps adapter construction and both attachment lifecycle hooks out of the
-- entry module while preserving exact Cosmetics identity ownership.

local M = {}

function M.new(mod, deps)
    deps = deps or {}
    local custom_hats = deps.custom_hats or {}
    local gk_set = deps.gk_set or {}
    local la_bridge = deps.la_bridge or {}
    local adapter = mod:dofile(
        "scripts/mods/cosmetics_tweaker/_lib_appearance_fade").new({
        alive = function(unit) return Unit and Unit.alive and Unit.alive(unit) end,
        get_extension = function(owner, name)
            return ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(owner, name) or nil
        end,
        get_fade_system = function()
            local entity = Managers and Managers.state and Managers.state.entity
            return entity and entity:system("fade_system") or nil
        end,
        diag_budget = 16,
        report = function(row)
            pcall(printf, "[cos:922] fade edge=%s result=%s linked=%d error=%s",
                tostring(row.edge), tostring(row.reason), tonumber(row.count) or 0,
                tostring(row.error))
        end,
    })

    local function owns_dynamic_hat(item_name)
        return item_name and (custom_hats.is_custom_identity(item_name)
            or item_name == gk_set.HAT_ITEM_KEY
            or (la_bridge.backend_to_armoury
                and la_bridge.backend_to_armoury[item_name] ~= nil))
    end

    local api = { adapter = adapter, owns_dynamic_hat = owns_dynamic_hat }

    function api.enroll_husk_attachment(owner, attachment_extension, hat_unit)
        return adapter:enroll(owner, "remote_husk_attachment", {
            attachment_extension = attachment_extension,
            extra_units = { hat_unit },
        })
    end

    function api.install(lifecycle)
        if api._installed then return end
        lifecycle = lifecycle or {}

        -- One owner-side hook retains the existing GK/custom-hat surface work,
        -- then submits the complete post-attachment FadeSystem snapshot.
        mod:hook("PlayerUnitAttachmentExtension", "create_attachment",
            function(func, self, slot_name, item_data)
                local r1, r2, r3, r4 = func(self, slot_name, item_data)
                local item_name = item_data and item_data.name
                local slot = slot_name == "slot_hat" and self._attachments
                    and self._attachments.slots
                    and self._attachments.slots[slot_name]
                local hat_unit = slot and slot.unit
                if item_name == gk_set.HAT_ITEM_KEY then
                    gk_set.apply_variant_to_unit(gk_set.HAT_VARIANT_KEY,
                        hat_unit, "local_attachment")
                end
                if item_name and custom_hats.is_custom_identity(item_name) then
                    custom_hats.apply_surface(hat_unit, "local-attachment")
                end
                if hat_unit and owns_dynamic_hat(item_name) then
                    adapter:enroll(self and self._unit, "owner_attachment", {
                        attachment_extension = self,
                        extra_units = { hat_unit },
                    })
                end
                return r1, r2, r3, r4
            end)

        -- Vanilla outer wield calls _reapply_fade after _wield_slot and replaces
        -- the list with four inventory fields. Compose once after that native
        -- replacement, forcing only an exact Cosmetics-owned attachment.
        mod:hook("SimpleHuskInventoryExtension", "_reapply_fade",
            function(func, self, equipment)
                local result = func(self, equipment)
                local owner = self and self._unit
                local ext = owner and ScriptUnit.has_extension(owner, "attachment_system")
                local hat = ext and ext._attachments and ext._attachments.slots.slot_hat
                local item_name = hat and hat.item_data and hat.item_data.name
                local owned = owns_dynamic_hat(item_name) or false

                if not owned and owner and lifecycle.identity and Managers
                        and Managers.player then
                    local player = lifecycle.identity.player_for_unit(
                        Managers.player, owner)
                    local store = lifecycle.get_store and lifecycle.get_store()
                    local cached = player and store and store[player.peer_id]
                        and store[player.peer_id].slot_hat
                    owned = cached and cached.kind == "hat" and cached.armoury_key
                        and lifecycle.identity.validate_live_entry(cached, owner,
                            ScriptUnit, Managers, lifecycle.la_persist) == true or false
                end

                if owned then
                    adapter:enroll(owner, "remote_husk_reapply", {
                        inventory_extension = self,
                        attachment_extension = ext,
                        equipment = equipment,
                        force = true,
                    })
                end
                return result
            end)
        api._installed = true
    end

    return api
end

return M
