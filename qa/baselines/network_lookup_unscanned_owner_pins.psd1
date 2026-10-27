@{
    schema = 2
    issue = 428
    coverage = 'explicit-source-pins-not-complete-census'
    rows = @(
        @{
            path = 'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_runtime.lua'
            axis = 'damage_profiles'
            count = 0
            sha256 = '4fe2ab23d675182cc59480f64fb17f60957c9e14a3e7686d2db4790bceaa5cf6'
            historical_count = 1
            migration = 'history-batch-composite-v1'
            transaction_path = 'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_profile_transaction.lua'
            transaction_sha256 = '64a8bbf77eafa250713d535fd856eabc2bd7732e53063018e614c87dfdf91298'
            composition_path = 'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_owner.lua'
            composition_sha256 = '0e1e62c72e41420089de254627e4e504d2ae1c9c30921f9a1beba4013070bf84'
        }
        @{
            path = 'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_history_runtime.lua'
            axis = 'damage_profiles'
            count = 0
            sha256 = '4fe2ab23d675182cc59480f64fb17f60957c9e14a3e7686d2db4790bceaa5cf6'
            historical_count = 1
            migration = 'history-batch-composite-v1'
            transaction_path = 'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_history_profile_transaction.lua'
            transaction_sha256 = 'b5c5fbea23cd43d862e3f67ca763e36e75890e4e19392508ff02a3a3051e0fea'
            composition_path = 'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_history_owner.lua'
            composition_sha256 = '0e1e62c72e41420089de254627e4e504d2ae1c9c30921f9a1beba4013070bf84'
        }
    )
}
