return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local catalog = assert(loadfile(root .. "_cim_ranalds_catalog.lua"))()
    local firestore = assert(loadfile(root .. "_cim_ranalds_firestore.lua"))()

    local function plain_document(overrides)
        local fields = {
            careerId = 1, name = "A Build", username = "Builder", likeCount = 12,
            dateModified = "2026-08-23T00:00:00Z",
            talent1 = 1, talent2 = 2, talent3 = 3,
            talent4 = 1, talent5 = 2, talent6 = 3,
            primaryWeapon = { id = 15, property1Id = 1, property2Id = 4, traitId = 6 },
            secondaryWeapon = { id = 56, property1Id = 1, property2Id = 3, traitId = 2 },
            necklace = { property1Id = 1, property2Id = 3, traitId = 1 },
            charm = { property1Id = 1, property2Id = 4, traitId = 2 },
            trinket = { property1Id = 1, property2Id = 2, traitId = 3 },
        }
        for key, value in pairs(overrides or {}) do fields[key] = value end
        return { name = "projects/x/databases/(default)/documents/builds/abc", fields = fields }
    end

    H.test("Ranald catalogue pins the complete current career and weapon vocabularies", function()
        H.equal(catalog.SOURCE_COMMIT,
            "50f8ca93ecc74f95f806e424827c30b6b107cc1f")
        local careers, weapons = 0, 0
        for _ in pairs(catalog.CAREERS) do careers = careers + 1 end
        for _ in pairs(catalog.WEAPONS) do weapons = weapons + 1 end
        H.equal(careers, 20)
        H.equal(weapons, 83)
        H.equal(catalog.CAREERS[16], "es_questingknight")
        H.equal(catalog.CAREERS[20], "bw_necro")
        H.equal(catalog.WEAPONS[69], "es_deus_01")
        H.equal(catalog.WEAPONS[83], "bw_soulsteal")
        H.equal(catalog.property_key("melee", 5), "crit_boost")
        H.equal(catalog.property_key("ranged", 2), "crit_boost")
        H.equal(catalog.property_key("ring", 2), "crit_boost")
        H.equal(catalog.trait_key("defence_accessory", 1),
            "necklace_damage_taken_reduction_on_heal")
        H.equal(catalog.trait_key("offence_accessory", 4), "ring_potion_spread")
        H.equal(catalog.trait_key("utility_accessory", 2),
            "trinket_not_consume_grenade")
        H.equal(catalog.trait_key("trollhammer_torpedo", 3),
            "ranged_increase_power_level_vs_armour_crit")
    end)

    H.test("Ranald document normalization produces one bounded semantic build", function()
        local build, err = catalog.normalize_document(plain_document({
            name = "  Build\nName  ", username = "Author\tName",
        }))
        H.equal(err, nil)
        H.equal(build.document_id, "abc")
        H.equal(build.career_name, "es_mercenary")
        H.equal(build.name, "Build Name")
        H.equal(build.username, "Author Name")
        H.equal(build.talents[3], 3)
        H.equal(build.slots.slot_melee.weapon_id, 15)
        H.equal(build.slots.slot_trinket_1.trait_id, 3)
    end)

    H.test("Ranald normalizer rejects malformed identity, talents, and rolls", function()
        local build, err = catalog.normalize_document(plain_document({ careerId = 999 }))
        H.equal(build, nil); H.equal(err, "career_id")
        build, err = catalog.normalize_document(plain_document({ talent4 = 4 }))
        H.equal(build, nil); H.equal(err, "talent4")
        build, err = catalog.normalize_document(plain_document({
            primaryWeapon = { id = 999, property1Id = 1, property2Id = 2, traitId = 1 },
        }))
        H.equal(build, nil); H.equal(err, "primaryWeapon:weapon_id")
        build, err = catalog.normalize_document(plain_document({
            charm = { property1Id = 2, property2Id = 2, traitId = 1 },
        }))
        H.equal(build, nil); H.equal(err, "charm:duplicate_properties")

        build = assert(catalog.normalize_document(plain_document({
            likeCount = math.huge,
            dateModified = string.rep("2", 100),
        })))
        H.equal(build.like_count, 0)
        H.equal(#build.date_modified, 48)

        build = assert(catalog.normalize_document(plain_document({
            likeCount = 2147483647,
        })))
        H.equal(build.like_count, 999999999)
    end)

    H.test("Ranald sort is deterministic for likes and recent", function()
        local a = { document_id = "a", like_count = 1, date_modified = "2026-01" }
        local b = { document_id = "b", like_count = 9, date_modified = "2025-01" }
        local c = { document_id = "c", like_count = 9, date_modified = "2026-02" }
        H.deep_equal(catalog.sort({ a, b, c }, "likes"), { c, b, a })
        H.deep_equal(catalog.sort({ a, b, c }, "recent"), { c, a, b })
    end)

    H.test("Firestore query filters one career and uses a bounded field mask", function()
        local query = firestore.query(8, firestore.BATCH_SIZE).structuredQuery
        H.equal(query.where.fieldFilter.field.fieldPath, "careerId")
        H.equal(query.where.fieldFilter.value.integerValue, "8")
        H.equal(query.limit, 100)
        H.equal(#query.select.fields, 16)
        H.equal(#query.from, 1)
        H.equal(query.orderBy[1].field.fieldPath, "__name__")
        H.equal(query.orderBy[1].direction, "ASCENDING")
        local cursor = firestore.query(8, 25,
            "projects/x/databases/(default)/documents/builds/abc").structuredQuery
        H.equal(cursor.startAt.before, false)
        H.equal(cursor.startAt.values[1].referenceValue,
            "projects/x/databases/(default)/documents/builds/abc")
    end)

    H.test("Firestore decoder unwraps typed fields and rejects oversized payloads", function()
        local typed = { {
            document = { name = plain_document().name, fields = {} },
        } }
        for key, value in pairs(plain_document().fields) do
            if type(value) == "table" then
                local children = {}
                for child_key, child in pairs(value) do children[child_key] = { integerValue = tostring(child) } end
                typed[1].document.fields[key] = { mapValue = { fields = children } }
            elseif type(value) == "number" then
                typed[1].document.fields[key] = { integerValue = tostring(value) }
            else
                local tag = key == "dateModified" and "timestampValue" or "stringValue"
                typed[1].document.fields[key] = { [tag] = value }
            end
        end
        local builds, err, rejected, meta = firestore.decode_rows("ok", function() return typed end, catalog)
        H.equal(err, nil); H.equal(rejected, 0); H.equal(#builds, 1)
        H.equal(builds[1].career_name, "es_mercenary")
        H.equal(meta.document_count, 1)
        H.equal(meta.last_name, plain_document().name)
        local huge = string.rep("x", firestore.MAX_RESPONSE_BYTES + 1)
        builds, err = firestore.decode_rows(huge, function() return {} end, catalog)
        H.equal(builds, nil); H.equal(err, "response_too_large")
    end)

    H.test("Firestore client ignores stale callbacks and reports current response", function()
        local callbacks = {}
        local fake_curl = { post = function(_, url, body, headers, callback)
            callbacks[#callbacks + 1] = callback
        end }
        local fake_json = { encode = function() return "{}" end, decode = function() return {} end }
        local client = firestore.new({ catalog = catalog,
            get_curl = function() return fake_curl end,
            get_json = function() return fake_json end })
        local seen = {}
        H.equal(client.fetch(1, function(builds, err) seen[#seen + 1] = err or #builds end), true)
        H.equal(client.fetch(2, function(builds, err) seen[#seen + 1] = err or #builds end), true)
        callbacks[1](true, 200, {}, "[]")
        H.equal(#seen, 0, "superseded request callback was not ignored")
        callbacks[2](true, 200, {}, "[]")
        H.deep_equal(seen, { 0 })
        H.equal(client.pending, false)
    end)

    H.test("Firestore client combines cursor pages before returning a career catalogue", function()
        local function typed_rows(count, first)
            local rows = {}
            for index = 1, count do
                local plain = plain_document()
                plain.name = "projects/x/databases/(default)/documents/builds/" .. tostring(first + index)
                local fields = {}
                for key, value in pairs(plain.fields) do
                    if type(value) == "table" then
                        local children = {}
                        for child_key, child in pairs(value) do
                            children[child_key] = { integerValue = tostring(child) }
                        end
                        fields[key] = { mapValue = { fields = children } }
                    elseif type(value) == "number" then
                        fields[key] = { integerValue = tostring(value) }
                    else
                        local tag = key == "dateModified" and "timestampValue" or "stringValue"
                        fields[key] = { [tag] = value }
                    end
                end
                rows[index] = { document = { name = plain.name, fields = fields } }
            end
            return rows
        end

        local posts, queries = 0, {}
        local fake_json = {
            encode = function(query) queries[#queries + 1] = query; return "{}" end,
            decode = function(body)
                return body == "page1" and typed_rows(100, 0) or typed_rows(1, 100)
            end,
        }
        local fake_curl = { post = function(_, url, body, headers, callback)
            posts = posts + 1
            callback(true, 200, {}, posts == 1 and "page1" or "page2")
        end }
        local client = firestore.new({ catalog = catalog,
            get_curl = function() return fake_curl end,
            get_json = function() return fake_json end })
        local returned, returned_meta
        H.equal(client.fetch(1, function(builds, err, meta)
            H.equal(err, nil); returned, returned_meta = builds, meta
        end), true)
        H.equal(posts, 2)
        H.equal(#queries, 2)
        H.equal(queries[2].structuredQuery.startAt.values[1].referenceValue,
            "projects/x/databases/(default)/documents/builds/100")
        H.equal(#returned, 101)
        H.equal(returned_meta.truncated, false)
        H.equal(client.pending, false)
    end)
end
