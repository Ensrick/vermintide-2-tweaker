return function(H, repo_root)
    local status = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")

    H.test("WT #108 confirmed redirects survive baking", function()
        H.equal(status.redirect_target("es_mercenary", "we_2h_axe"), "Empire Greathammer")
        H.equal(status.redirect_target("es_knight", "we_dual_wield_daggers"), "Empire Mace & Sword")
        H.equal(status.redirect_target("es_huntsman", "wh_flail_shield"), "Empire Mace & Shield")
        H.equal(status.redirect_target("we_waywatcher", "dr_2h_pick"), "Elf 2H Axe/Glaive")
        H.equal(status.redirect_target("we_shade", "es_dual_wield_hammer_sword"), "Sword & Dagger")
        H.equal(status.state("es_mercenary", "we_2h_axe"), "working")
    end)

    H.test("WT #108 shipped model substitutes are labelled", function()
        H.equal(status.model_substitute("es_mercenary", "wh_brace_of_pistols"), "Repeater Handgun")
        H.equal(status.model_substitute("es_knight", "wh_repeating_pistols"), "Repeater Handgun")
        H.equal(status.model_substitute("wh_captain", "es_longbow"), "Crossbow")
        H.equal(status.model_substitute("wh_zealot", "we_longbow"), "Crossbow")
        H.equal(status.state("wh_captain", "es_longbow"), "working")
    end)

    H.test("WT port lifecycle remains internal and untagged", function()
        H.equal(status.state("es_mercenary", "wh_brace_of_pistols"), "working")
        H.equal(status.state("es_mercenary", "es_1h_mace"), "working")
        H.equal(status.tag, nil)
        H.equal(status.decorate_tag, nil)
    end)
end
