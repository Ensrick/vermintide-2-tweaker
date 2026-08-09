-- _ct_boon_preview_helpers.lua -- CT-dev Starting-Boon Preview helper owner.
--
-- Behavior-neutral extraction from the entry. The shared #461/#533 draw hook
-- remains at the manifest seam because VMF permits only one owner per pair.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: one ordered mod:dofile installer call and the entry-owned
-- IngamePlayerListUI preview hooks; guarded by
-- qa/lua/tests/test_ct_boon_preview_helpers.lua.
return function(ctx)
    assert(type(ctx) == "table", "CT boon-preview helper owner requires context")
    local mod = assert(ctx.mod, "CT boon-preview helper owner requires mod")

-- TRUE while this peer's party is queued for a Chaos Wastes expedition (host pressed
-- host/start on a CW journey; not yet transitioned out of the keep). Direct port of
-- vanilla MatchmakingManager.is_matchmaking_versus (matchmaking_manager.lua:1256-1266)
-- retargeted at mechanism "deus":
--  * host path: set_matchmaking_data writes lobby_data.mechanism = "deus"
--    (matchmaking_manager.lua:985) for public AND private games; host state leaves
--    MatchmakingStateIdle while hosting the search.
--  * client path: rpc_set_matchmaking always sends is_matchmaking=true to party
--    clients (matchmaking_manager.lua:1083), putting them in
--    MatchmakingStateFriendClient (non-idle), and they read the host lobby's
--    replicated "mechanism" field like vanilla does.
--  * reset path: loading into any hub level rewrites matchmaking="false" and
--    refreshes the mechanism field (state_loading.lua:2584/:2597), and cancel sends
--    rpc_set_matchmaking(false) -> Idle, so the block disappears after a cancel or a
--    finished run. Whole body pcall-bracketed: any nil seam = just no preview.
function mod._ct_preparing_cw_expedition()
    local ok, res = pcall(function()
        local mm = Managers.matchmaking
        if not mm then return false end
        local state = mm._state
        local is_matchmaking = state and state.NAME ~= "MatchmakingStateIdle"
        local lobby = mm.lobby
        local lobby_client = (state and state.lobby_client)
            or (Managers.lobby and (Managers.lobby:query_lobby("matchmaking_session_lobby")
                or Managers.lobby:query_lobby("matchmaking_join_lobby")))
        local lobby_mechanism = lobby and lobby.lobby_data and lobby:lobby_data("mechanism")
        local client_mechanism = lobby_client and lobby_client.lobby_data and lobby_client:lobby_data("mechanism")
        local is_lobby_matchmaking = lobby and lobby.lobby_data and lobby:lobby_data("matchmaking") == "true"
        local is_client_matchmaking = lobby_client and lobby_client.lobby_data and lobby_client:lobby_data("matchmaking") == "true"
        return ((is_matchmaking or is_lobby_matchmaking or is_client_matchmaking)
            and (lobby_mechanism == "deus" or client_mechanism == "deus")) or false
    end)
    return (ok and res) or false
end

-- Resolve the same career-specific identity vanilla uses for a talent power-up.
-- Generic talent templates intentionally have no display_name/icon of their own;
-- vanilla routes them through these helpers (deus_power_up_utils.lua:298-322).
-- Kept on `mod` so the runtime regression suite can exercise the real resolver.
function mod._ct_start_boon_identity(name, rarity, profile_index, career_index)
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local template = type(templates) == "table" and rawget(templates, name) or nil
    local display = mod._ct_boon_display_name(name)
    local icon = template and template.icon or nil

    if template and template.talent and profile_index and career_index then
        local utils = rawget(_G, "DeusPowerUpUtils")
        if utils and type(utils.get_power_up_name_text) == "function" then
            local ok, resolved = pcall(utils.get_power_up_name_text, name,
                template.talent_index, template.talent_tier, profile_index, career_index)
            if ok and type(resolved) == "string" and resolved ~= "" then display = resolved end
        end
        if utils and type(utils.get_power_up_icon) == "function" then
            local ok, resolved = pcall(utils.get_power_up_icon,
                { name = name, rarity = rarity }, profile_index, career_index)
            if ok and type(resolved) == "string" and resolved ~= "" then icon = resolved end
        end
    end

    return display, icon
end

-- Resolve the same localized description used by vanilla boon cards. The
-- canonical helper covers vanilla, career-derived talents, and power-ups
-- registered with the native Deus runtime. Do not reconstruct description
-- values from DeusPowerUpTemplates: that can look correct while disagreeing
-- with get_trait/talent description. A rejected registration fails neutral.
function mod._ct_start_boon_description(name, rarity, profile_index, career_index)
    local utils = rawget(_G, "DeusPowerUpUtils")
    local unavailable = mod:localize("ct_boon_preview_description_unavailable")
    return mod._ct_boon_preview_tooltip.resolve_description({
        instance = { name = name, rarity = rarity },
        profile_index = profile_index,
        career_index = career_index,
        canonical = utils and utils.get_power_up_description,
        unavailable = unavailable ~= "ct_boon_preview_description_unavailable"
            and unavailable or "Description unavailable.",
    })
end

-- Ordered, de-duplicated list of the starting boons the run will grant, host-effective.
-- Each entry: { name, rarity, display, description, icon, modded }. On `mod` (not a file-local) per
-- the Lua 5.1 200-locals cap; shared by the Tab panel + `/ct_preview_boons`.
function mod._ct_collect_start_boons()
    local out = {}
    local arr = rawget(_G, "DeusPowerUpsArray")
    if type(arr) ~= "table" then return out end
    local eff = mod._ct_effective_setting or function(k) return mod:get(k) end
    local is_modded = mod._ct_is_modded_power_up
    local profile_index, career_index
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player()
    if player then
        local ok, profile, career = pcall(function()
            return player:profile_index(), player:career_index()
        end)
        if ok then profile_index, career_index = profile, career end
    end
    local seen = {}
    for _, entry in ipairs(arr) do
        local name = entry and entry.name
        if name and not seen[name] and eff("start_boon_" .. name) then
            seen[name] = true
            local display, icon = mod._ct_start_boon_identity(
                name, entry.rarity, profile_index, career_index)
            local description = mod._ct_start_boon_description(
                name, entry.rarity, profile_index, career_index)
            out[#out + 1] = {
                name = name,
                rarity = entry.rarity,
                display = display,
                description = description,
                icon = icon,
                modded = (is_modded and is_modded(name)) or false,
            }
        end
    end
    table.sort(out, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
    return out
end

-- Header widget for the boon-preview block, anchored to the reward_divider scenegraph
-- node (where vanilla's reward header sits, above the icon rows on banner_right).
function mod._ct_build_boon_preview_header(title)
    return UIWidget.init(UIWidgets.create_simple_text(title, "reward_divider", 22, nil, {
        horizontal_alignment = "left",
        vertical_alignment = "center",
        localize = false,
        word_wrap = false,
        font_size = 22,
        font_type = "hell_shark",
        text_color = { 255, 255, 214, 138 },
        offset = { 4, 0, 3 },
    }))
end

-- One icon widget + one name widget per boon. Icon and name are SEPARATE widgets so a
-- boon whose icon texture will not resolve still shows its name (see risk posture
-- above). ALL rows are anchored on the SIZED "reward_divider" scenegraph node -- the
-- node the header provably renders on -- never on the sizeless "reward_item" node (the
-- v0.7.251 off-screen bug; see the follow-up note in the banner comment). Layout:
-- 2 columns x 9 rows below the header, 28px row pitch, 330px column pitch, inside the
-- band (screen y ~340 down to ~90 at 1080p reference) that is empty while a CW
-- expedition is queued (no deed rewards, no keep collectibles). Overflow past 18
-- becomes a "+N more" line; /ct_preview_boons always lists everything.
function mod._ct_build_boon_preview_widgets(boons)
    -- UTF-8 safe truncation (cut on a codepoint boundary so a curly quote or accented
    -- glyph can never be split into an invalid byte sequence). Function-scoped local:
    -- the file's top-level chunk is near the Lua 5.1 200-locals cap.
    local function trunc(s, max_bytes)
        if type(s) ~= "string" or #s <= max_bytes then return s end
        local cut = max_bytes
        while cut > 1 do
            local b = s:byte(cut + 1)
            if not b or b < 0x80 or b >= 0xC0 then break end -- next byte starts a codepoint (or end)
            cut = cut - 1
        end
        return s:sub(1, cut) .. "..."
    end
    local out = {}
    local ICON, ROW_H, COL_W, NUM_ROWS = 24, 28, 330, 9
    local MAX = NUM_ROWS * 2
    local n = math.min(#boons, MAX)
    local function has_icon(content)
        return type(content.icon) == "string" and content.icon ~= ""
    end
    for i = 1, n do
        local b = boons[i]
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 4 + col * COL_W
        -- Offsets are relative to the reward_divider node (origin y ~348, center ~364
        -- at 1080p reference): text is v-centered in the node's 32px box then pushed
        -- down per row; the icon (drawn from its bottom-left corner by the texture
        -- pass) gets +4 so its center matches the text center.
        local row_center_offset = -(34 + row * ROW_H)
        local icon_widget = UIWidget.init({
            scenegraph_id = "reward_divider",
            element = {
                passes = {
                    { pass_type = "hotspot", style_id = "hotspot", content_id = "hotspot" },
                    {
                        pass_type = "texture", style_id = "icon", texture_id = "icon",
                        content_check_function = has_icon,
                    },
                },
            },
            content = { hotspot = {}, icon = b.icon },
            style = {
                hotspot = {
                    offset = { x, row_center_offset + 4, 4 },
                    size = { ICON, ICON },
                },
                icon = {
                    color = { 255, 255, 255, 255 },
                    offset = { x, row_center_offset + 4, 1 },
                    texture_size = { ICON, ICON },
                },
            },
            offset = { 0, 0, 0 },
        })
        icon_widget._ct_boon_hover_target = true
        -- Layout and UIWidget construction are intentionally deferred until
        -- this icon is first hovered. The one-time work is hard-bounded by the
        -- tooltip policy and never touches unhovered rows.
        icon_widget._ct_boon_tooltip_data = b
        icon_widget._ct_boon_tooltip_attempted = false
        out[#out + 1] = icon_widget
        out[#out + 1] = UIWidget.init(UIWidgets.create_simple_text(
            trunc(b.display or b.name, 30), "reward_divider", 16, nil, {
                horizontal_alignment = "left",
                vertical_alignment = "center",
                localize = false,
                word_wrap = false,
                font_size = 16,
                font_type = "hell_shark",
                text_color = { 255, 235, 235, 235 },
                offset = { x + ICON + 8, row_center_offset, 2 },
            }))
    end
    if #boons > n then
        out[#out + 1] = UIWidget.init(UIWidgets.create_simple_text(
            string.format("+%d more", #boons - n), "reward_divider", 16, nil, {
                horizontal_alignment = "left",
                vertical_alignment = "center",
                localize = false,
                word_wrap = false,
                font_size = 16,
                font_type = "hell_shark",
                text_color = { 255, 200, 200, 200 },
                offset = { 4, -(34 + NUM_ROWS * ROW_H), 2 },
            }))
    end
    return out
end
end
