local M = {}

-- A CWV pickup name is safe on the vanilla wire only after every human peer
-- has positively acknowledged CWV. Until then the caller must use the declared
-- vanilla fallback. Returning nil means "keep the original CWV pickup name".
function M.wire_fallback(pickup_name, fallback_by_name, all_peers_have_cwv)
    local fallback = fallback_by_name and fallback_by_name[pickup_name]

    if not fallback or all_peers_have_cwv == true then
        return nil
    end

    return fallback
end

return M
