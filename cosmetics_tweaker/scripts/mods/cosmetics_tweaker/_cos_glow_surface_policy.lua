-- _cos_glow_surface_policy.lua -- pure surface-repaint policy for glow parity
-- on the preview and score surfaces (#1147, #660 descriptor consumers).
--
-- Owns, engine-free: (1) resolution of a wearer's authoritative glow payload
-- (transported _glow_by_peer state first, live local active payload as the
-- local wearer's fallback -- score rows carry wearer identity but NO
-- owner-local backend ids, so every score row routes through the same
-- render-identity descriptors the husk consumers use); (2) the per-item glow
-- paint math (component clamps, HDR scaling, variable spans) with an injected
-- write primitive so the offline suite drives the REAL repaint; (3) the
-- surface repaint executor; (4) the postcondition classifier: success is
-- painted-mesh identity (named mesh exposing a glow variable), never call
-- completion.
--
-- Invariant: fail closed. No payload, no identity match, or an unnameable
-- mesh degrades to the resident baked glow -- never a family-wide paint
-- (the #48 bleed class).
--
-- Owned by: _cos_glow.lua (dofile'd there, like _cos_glow_instance_policy).
-- Consumed via: mod:dofile; pure module, no engine globals, offline-tested by
-- qa/lua/tests/test_cos_glow_surface_policy.lua.

local M = {}

-- Authoritative payload for a wearer on a backend-id-free surface.
-- Returns state, source: "transport" | "local_active" | nil reason.
function M.resolve_wearer_state(glow_by_peer, wearer_peer, wearer_is_local, local_payload)
    if wearer_peer == nil then return nil, "no-wearer" end
    local state = type(glow_by_peer) == "table" and glow_by_peer[wearer_peer] or nil
    if type(state) == "table" then return state, "transport" end
    -- The local wearer's loopback echo may not have landed (client before the
    -- host rebroadcast); the live active payload is the same data the
    -- transport would carry (_cos_glow_transport.collect_local_glow_state).
    if wearer_is_local and type(local_payload) == "table"
            and local_payload.active_per_item_glow ~= nil then
        return local_payload, "local_active"
    end
    return nil, "no-payload"
end

-- The per-item glow paint, verbatim math from _cos_glow.lua's
-- _apply_glow_to_unit per-item section (v0.9.8 component contract):
-- disabled paints zeros on every variable and claims the unit; each active
-- component writes user RGB clamped 0-255, intensity clamped 0-5, scaled by
-- the variable's native template brightness / 255; lower spans
-- color_glow_high+low, upper spans color_smoke_high+low. Returns true when
-- the per-item state fully handled the unit (global override must not run).
-- deps: var_brightness = _GLOW_VAR_BRIGHTNESS shape { var = { brightness } },
--       write(unit, var_name, x, y, z) -- the engine (or test) write primitive.
function M.paint_per_item(unit, pi, deps)
    if type(pi) ~= "table" then return false end
    local vars = deps.var_brightness
    local write = deps.write
    if pi.disabled then
        for var_name in pairs(vars) do
            write(unit, var_name, 0, 0, 0)
        end
        return true
    end
    local function paint_var(var_name, r, g, b, intensity)
        local info = vars[var_name]
        if not info then return end
        -- Peer payloads are untrusted. Ignore malformed component values
        -- rather than allowing arithmetic on strings/tables.
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
            or type(intensity) ~= "number" then return end
        r = math.max(0, math.min(255, r))
        g = math.max(0, math.min(255, g))
        b = math.max(0, math.min(255, b))
        intensity = math.max(0, math.min(5, intensity))
        local scale = (info.brightness or 1) * intensity / 255
        write(unit, var_name, r * scale, g * scale, b * scale)
    end
    local function component_active(component)
        return type(component) == "table"
            and type(component.intensity) == "number"
            and component.intensity > 0
    end
    if component_active(pi.rune) then
        paint_var("rune_emissive_color",
            pi.rune.r or 0, pi.rune.g or 0, pi.rune.b or 0, pi.rune.intensity)
    end
    if component_active(pi.lower) then
        paint_var("color_glow_high",
            pi.lower.r or 0, pi.lower.g or 0, pi.lower.b or 0, pi.lower.intensity)
        paint_var("color_glow_low",
            pi.lower.r or 0, pi.lower.g or 0, pi.lower.b or 0, pi.lower.intensity)
    end
    if component_active(pi.upper) then
        paint_var("color_smoke_high",
            pi.upper.r or 0, pi.upper.g or 0, pi.upper.b or 0, pi.upper.intensity)
        paint_var("color_smoke_low",
            pi.upper.r or 0, pi.upper.g or 0, pi.upper.b or 0, pi.upper.intensity)
    end
    if component_active(pi.dots) then
        paint_var("color_dots",
            pi.dots.r or 0, pi.dots.g or 0, pi.dots.b or 0, pi.dots.intensity)
    end
    return component_active(pi.rune)
        or component_active(pi.lower)
        or component_active(pi.upper)
        or component_active(pi.dots)
end

-- Surface repaint executor: paint the wearer's active per-item payload onto
-- exactly the units whose bound render identity matches it.
-- deps additionally: is_unit(unit), match(unit, peer_state).
-- Returns painted, considered, matched.
function M.repaint(units, peer_state, deps)
    local pi = type(peer_state) == "table" and peer_state.active_per_item_glow or nil
    if type(pi) ~= "table" then return 0, 0, 0 end
    local painted, considered, matched = 0, 0, 0
    for _, unit in pairs(units or {}) do
        if unit and deps.is_unit(unit) then
            considered = considered + 1
            if deps.match(unit, peer_state) then
                matched = matched + 1
                if M.paint_per_item(unit, pi, deps) then
                    painted = painted + 1
                end
            end
        end
    end
    return painted, considered, matched
end

-- Postcondition classifier (the #1147 success predicate). facts:
--   alive        -- unit passed the liveness primitive AFTER the paint
--   mesh_name    -- authored unit_name read from the painted unit
--   glow_capable -- at least one material on the unit exposes a glow variable
-- "verified" requires a NAMED mesh with a glow-capable material; a mesh the
-- surface cannot even name is never reported as success (the exact
-- match=false outcome=true dishonesty this issue records).
function M.classify_postcondition(facts)
    if type(facts) ~= "table" or facts.alive ~= true then return "dead-unit" end
    local mesh = facts.mesh_name
    if type(mesh) ~= "string" or mesh == "" or mesh:sub(1, 1) == "<" then
        return "unnamed-mesh"
    end
    if facts.glow_capable ~= true then return "no-glow-material" end
    return "verified"
end

return M
