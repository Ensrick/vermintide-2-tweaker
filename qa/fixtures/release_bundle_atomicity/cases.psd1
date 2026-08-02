@{
    Cases = @(
        @{
            Name = 'docs only'
            Changes = @(@{ Path = 'example_mod/DEVELOPMENT.md' })
            ExpectedErrors = 0
        }
        @{
            Name = 'tests only'
            Changes = @(@{ Path = 'qa/lua/tests/test_example.lua' })
            ExpectedErrors = 0
        }
        @{
            Name = 'runtime without root bundle'
            Changes = @(@{ Path = 'example_mod/scripts/mods/example_mod/example_mod.lua' })
            ExpectedErrors = 1
        }
        @{
            Name = 'runtime with root bundle'
            Changes = @(
                @{ Path = 'example_mod/scripts/mods/example_mod/example_mod.lua' },
                @{ Path = 'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle' }
            )
            ExpectedErrors = 0
        }
        @{
            Name = 'sidecar bundle cannot stand in for root'
            Changes = @(
                @{ Path = 'example_mod/scripts/mods/example_mod/example_mod.lua' },
                @{ Path = 'example_mod/bundleV2/cccccccccccccccc.mod_bundle' }
            )
            ExpectedErrors = 1
        }
        @{
            Name = 'deleted root bundle is not an update'
            Changes = @(
                @{ Path = 'example_mod/scripts/mods/example_mod/example_mod.lua' },
                @{ Path = 'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle'; Status = 'D' }
            )
            ExpectedErrors = 1
        }
        @{
            Name = 'declared active root retirement still fails'
            Changes = @(@{ Path = 'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle'; Status = 'D' })
            DeclaredBundleRetirements = @('example_mod/aaaaaaaaaaaaaaaa.mod_bundle')
            ExpectedErrors = 1
        }
        @{
            Name = 'undeclared sibling bundle deletion fails'
            Changes = @(@{ Path = 'example_mod/bundleV2/cccccccccccccccc.mod_bundle'; Status = 'D' })
            ExpectedErrors = 1
        }
        @{
            Name = 'newest-release sibling retirement passes'
            Changes = @(@{ Path = 'example_mod/bundleV2/cccccccccccccccc.mod_bundle'; Status = 'D' })
            DeclaredBundleRetirements = @('example_mod/cccccccccccccccc.mod_bundle')
            ExpectedErrors = 0
        }
        @{
            Name = 'item config without root bundle'
            Changes = @(@{ Path = 'example_mod/itemV2.cfg' })
            ExpectedErrors = 1
        }
        @{
            Name = 'newest changelog release without root bundle'
            Changes = @(@{ Path = 'example_mod/CHANGELOG.md' })
            TopReleaseChanged = @('example_mod')
            ExpectedErrors = 1
        }
        @{
            Name = 'historical changelog prose only'
            Changes = @(@{ Path = 'example_mod/CHANGELOG.md' })
            ExpectedErrors = 0
        }
        @{
            Name = 'bundle only reconciliation'
            Changes = @(@{ Path = 'example_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle' })
            ExpectedErrors = 0
        }
        @{
            Name = 'trusted stable metadata-only promotion'
            Changes = @(
                @{ Path = 'stable_mod/itemV2.cfg' },
                @{ Path = 'stable_mod/CHANGELOG.md' }
            )
            TopReleaseChanged = @('stable_mod')
            TrustedPromotions = @('stable_mod')
            ExpectedErrors = 0
        }
        @{
            Name = 'promotion trailer never exempts runtime'
            Changes = @(@{ Path = 'stable_mod/scripts/mods/stable_mod/stable_mod.lua' })
            TrustedPromotions = @('stable_mod')
            ExpectedErrors = 1
        }
    )
}
