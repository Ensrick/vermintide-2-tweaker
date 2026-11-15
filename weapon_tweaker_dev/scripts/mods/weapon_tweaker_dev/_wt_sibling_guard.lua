-- _wt_sibling_guard.lua -- WP-WT-03: at most one Weapon Tweaker stream runs.
--
-- Public `wt` and friends-only `wt_dev` hook the same engine methods and both
-- rewrite ItemMasterList[*].can_wield from their own settings, and VMF calls
-- mods in `pairs` order (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/
-- modules/core/events.lua:44-51), so running both is not deterministic. When
-- both are enabled, public `wt` yields; `wt_dev` never does.
--
-- Re-entrancy: the disable is issued only from `update` (one tick of VMF's
-- update loop, events.lua:48-50), never from on_enabled / on_disabled /
-- on_all_mods_loaded. VMF's set_mod_state writes the saved disabled list
-- after it ran the lifecycle callback (core/toggling.lua:9-35), so a disable
-- issued inside on_enabled would be overwritten. mod_state_changed
-- (core/toggling.lua:55-66) is the same path the VMF options menu uses.
--
-- Pure module: reads no globals at load. The caller passes get_mod and a print
-- function. The tick accumulator is module-local, one per loaded tree.

local M = {}

local PUBLIC_ID = "wt"
local SIBLING = { wt = "wt_dev", wt_dev = "wt" }
local INTERVAL = 1

local _elapsed = 0

function M.sibling_id(self_id)
    return SIBLING[self_id]
end

function M.public_must_yield(self_id, self_enabled, sibling)
    if self_id ~= PUBLIC_ID or self_enabled ~= true then return false end
    if type(sibling) ~= "table" or type(sibling.is_enabled) ~= "function" then return false end
    local ok, enabled = pcall(sibling.is_enabled, sibling)
    return ok and enabled == true
end

function M.tick(mod, dt, get_mod_fn, print_fn)
    _elapsed = _elapsed + (tonumber(dt) or 0)
    if _elapsed < INTERVAL then return false end
    _elapsed = 0
    local self_id = mod:get_name()
    local sibling_id = M.sibling_id(self_id)
    if not sibling_id then return false end
    local sibling = get_mod_fn(sibling_id)
    if not M.public_must_yield(self_id, mod:is_enabled() == true, sibling) then return false end
    print_fn("[wt:SIBLING] wt and wt_dev are both enabled; disabling public wt")
    mod:echo("Weapon Tweaker (dev) is enabled. The public Weapon Tweaker was turned off to avoid conflicts.")
    get_mod_fn("VMF").mod_state_changed(self_id, false)
    return true
end

return M
