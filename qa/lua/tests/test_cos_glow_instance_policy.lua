-- Issue 48: per-instance glow policy. A committed glow belongs to ONE exact
-- inventory instance wearing ONE exact illusion, never to the template family.
return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_instance_policy.lua"
    local Policy = dofile(path)

    -- ---------------------------------------------------------------
    -- Exact-instance identity
    -- ---------------------------------------------------------------

    H.test("Cosmetics glow identity is keyed by exact backend instance", function()
        local a = Policy.identity_key("bid-a", { skin = "es_sword_skin_runed_01" })
        local b = Policy.identity_key("bid-b", { skin = "es_sword_skin_runed_01" })
        H.equal(a, "backend:bid-a|skin:es_sword_skin_runed_01")
        -- Same illusion, different instance -> different key. This is the whole
        -- point of the issue: no family-wide bleed.
        H.truthy(a ~= b)
    end)

    H.test("Cosmetics glow identity narrows by illusion on one instance", function()
        local runed = Policy.identity_key("bid-a", { skin = "skin_runed_01" })
        local magic = Policy.identity_key("bid-a", { skin = "skin_magic_01" })
        H.truthy(runed ~= magic)
    end)

    H.test("Cosmetics glow identity fails closed without a backend id", function()
        H.equal(Policy.identity_key(nil, { skin = "skin_runed_01" }), nil)
        -- Missing slot data still yields a stable, instance-scoped key.
        H.equal(Policy.identity_key("bid-a", nil), "backend:bid-a|skin:")
    end)

    -- ---------------------------------------------------------------
    -- Runtime rebind: the local illusion-swap leak
    -- ---------------------------------------------------------------

    H.test("Cosmetics glow runtime binds a persisted exact-instance override", function()
        local decision = Policy.resolve_runtime(
            { rune = { r = 255, g = 0, b = 0, intensity = 1 } }, "bid-a", "backend:bid-a|skin:x")
        H.equal(decision.action, "bind")
        H.equal(decision.backend_id, "bid-a")
        H.equal(decision.identity, "backend:bid-a|skin:x")
    end)

    H.test("Cosmetics glow runtime clears on a persisted miss", function()
        -- The runtime paint map is keyed by bare backend id while persistence is
        -- keyed by backend id AND skin. Bailing without clearing left the old
        -- illusion's override painting after a swap on the same instance.
        local decision = Policy.resolve_runtime(nil, "bid-a", "backend:bid-a|skin:new")
        H.equal(decision.action, "clear")
        H.equal(decision.backend_id, "bid-a")
    end)

    H.test("Cosmetics glow runtime ignores an unidentifiable instance", function()
        H.equal(Policy.resolve_runtime({ rune = {} }, nil, nil).action, "ignore")
    end)

    -- ---------------------------------------------------------------
    -- Remote match: the peer family-wide bleed
    -- ---------------------------------------------------------------

    local function peer(fields)
        local base = { active_per_item_glow_skin = "skin_magic_01" }
        for k, v in pairs(fields or {}) do base[k] = v end
        return base
    end

    H.test("Cosmetics glow remote match binds the exact illusion", function()
        H.truthy(Policy.remote_match({ skin = "skin_magic_01" }, peer()))
        H.equal(Policy.remote_match({ skin = "skin_runed_01" }, peer()), false)
    end)

    H.test("Cosmetics glow remote match resolves skin from the identity string", function()
        local state = {
            active_per_item_glow_identity = "backend:bid-a|skin:skin_magic_01",
        }
        H.truthy(Policy.remote_match({ skin = "skin_magic_01" }, state))
        H.equal(Policy.remote_match({ skin = "other" }, state), false)
    end)

    H.test("Cosmetics glow remote match fails closed on an unconstrained payload", function()
        -- Regression guard for the family-wide bleed: a payload carrying no skin
        -- and no parseable identity previously matched EVERY glow-capable unit
        -- on that wearer. Resident vanilla is the correct fallback.
        H.equal(Policy.remote_match({ skin = "skin_magic_01" }, {}), false)
        H.equal(Policy.remote_match({ skin = "skin_magic_01" },
            { active_per_item_glow_identity = "no-skin-segment" }), false)
        H.equal(Policy.remote_match({}, {}), false)
    end)

    H.test("Cosmetics glow remote match rejects non-table inputs", function()
        H.equal(Policy.remote_match(nil, peer()), false)
        H.equal(Policy.remote_match({ skin = "skin_magic_01" }, nil), false)
    end)

    H.test("Cosmetics glow remote match honours declared slot refinements", function()
        local state = peer({ active_per_item_glow_slot = "slot_melee" })
        H.truthy(Policy.remote_match({ skin = "skin_magic_01", slot_name = "slot_melee" }, state))
        H.equal(Policy.remote_match(
            { skin = "skin_magic_01", slot_name = "slot_ranged" }, state), false)
        -- Receiver has no slot evidence: unproven, not contradicted.
        H.truthy(Policy.remote_match({ skin = "skin_magic_01" }, state))
    end)

    H.test("Cosmetics glow remote match honours name and template refinements", function()
        local state = peer({
            active_per_item_glow_item_name = "sword_a",
            active_per_item_glow_item_template = "tpl_a",
        })
        H.truthy(Policy.remote_match(
            { skin = "skin_magic_01", item_name = "sword_a", item_template = "tpl_a" }, state))
        H.equal(Policy.remote_match(
            { skin = "skin_magic_01", item_name = "sword_b" }, state), false)
        H.equal(Policy.remote_match(
            { skin = "skin_magic_01", item_template = "tpl_b" }, state), false)
    end)

    H.test("Cosmetics glow remote match treats an empty skin as a real constraint", function()
        -- An item with no illusion commits identity "...|skin:". That empty
        -- string must still bind, not degrade into a wildcard.
        local state = { active_per_item_glow_identity = "backend:bid-a|skin:" }
        H.truthy(Policy.remote_match({ skin = "" }, state))
        H.truthy(Policy.remote_match({}, state))
        H.equal(Policy.remote_match({ skin = "skin_magic_01" }, state), false)
    end)

    -- ---------------------------------------------------------------
    -- Durable per-item disable
    -- ---------------------------------------------------------------

    H.test("Cosmetics glow disable survives the shape round trip", function()
        local shaped = Policy.carry_disabled({ rune = {} }, { disabled = true })
        H.equal(shaped.disabled, true)
        H.truthy(Policy.is_disabled(shaped))
    end)

    H.test("Cosmetics glow disable is cleared when the base is active", function()
        local shaped = Policy.carry_disabled({ rune = {} , disabled = true }, { rune = {} })
        H.equal(shaped.disabled, nil)
        H.equal(Policy.is_disabled(shaped), false)
    end)

    H.test("Cosmetics glow disable predicate rejects non-table state", function()
        H.equal(Policy.is_disabled(nil), false)
        H.equal(Policy.is_disabled("disabled"), false)
        H.equal(Policy.is_disabled({ disabled = "yes" }), false)
    end)
end
