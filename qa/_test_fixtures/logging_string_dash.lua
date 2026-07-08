-- Fixture for check_logging.ps1 -SelfTest — regression guard for the
-- `--`-inside-a-string-literal hazard. The hook-body warning string below
-- contains BOTH a block keyword (`while`) and a `--`. If string interiors are
-- not blanked before the comment split, the `while` leaks into the block-depth
-- counter, the hook's scope floor never clears, and the command-body echoes
-- underneath get falsely flagged.
-- Expected: exactly 1 echo finding (the hook-body echo). The two command-reply
-- echoes must stay clean.
local MOD_VERSION = "0.1.0-dev"

mod:hook("StateLoading", "create_popup", function(func, self)
    if self._popup_up then
        mod:warning("[fx] intercept while popup already up -- skipping enrichment, deferring")
        return func(self)
    end
    mod:echo("[fx] hook fired")   -- FLAG: echo in a hook body
end)

mod:command("fx_probe", "probe a lobby -- no join", function(arg)
    mod:echo("[fx] probe reply 1")
    mod:echo("[fx] probe reply 2")
end)
