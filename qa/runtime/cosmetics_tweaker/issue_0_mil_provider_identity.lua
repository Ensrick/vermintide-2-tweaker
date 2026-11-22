-- qa/runtime/cosmetics_tweaker/issue_0_mil_provider_identity.lua
-- WP-COS-05 rig case (audit findings A3-F03, A3-F08): MoreItemsLibrary
-- resolves through get_mod (standalone first, else the cosmetics_tweaker
-- embed, _la_prefix_embedded.lua), and when the embed is the provider its
-- backend-mirror hook is installed. The embed prints
-- "[cos:mil] backend mirror hooked provider=embedded owner=cosmetics_tweaker"
-- once the hook lands; host_expect_log asserts that line, so run this case
-- with the standalone MoreItemsLibrary disabled (provider state "embedded").
-- T.expect_rt and host_expect_log are CONVENTIONS API; the driver adds them in WP-H-06.
-- Stop condition (card): a FAIL with the mirror not hooked in the keep means
-- the items interface was created before the hook; record the log and stop.

local MOD_ID = "cosmetics_tweaker"

return {
    id = "cos-mil-provider-identity",
    issue = 0,
    class = "R",
    covers = "WP-COS-05 RIG acceptance: MoreItemsLibrary provider identity and mirror hook",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 60,
    host_expect_log = { "[cos:mil] backend mirror hooked" },

    run = function(T)
        T.step("preconditions")
        local cos = get_mod(MOD_ID)
        T.require(cos ~= nil, "cosmetics_tweaker loaded")
        local provider = cos._cos_mil_provider
        T.note("provider_state", tostring(provider and provider.state))
        T.note("provider_owner", tostring(provider and provider.owner))
        T.note("mirror_hooked", tostring(cos._cos_mil_mirror_hooked and cos._cos_mil_mirror_hooked()))

        T.step("MoreItemsLibrary resolves")
        local mil = get_mod("MoreItemsLibrary")
        T.expect(mil ~= nil and type(mil.add_mod_items_to_masterlist) == "function",
            "get_mod(\"MoreItemsLibrary\") exposes add_mod_items_to_masterlist")
        T.expect_rt(MOD_ID, "mil_provider_identity")
    end,
}
