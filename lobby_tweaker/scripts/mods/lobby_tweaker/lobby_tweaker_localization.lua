return {
    mod_description = {
        en = "Host-side lobby controls and modded-realm mod-list notifications. Reserve slots, ignore griefers, kick idle players, post a MOTD, and (in modded) tell joiners which of your mods they're missing when their join fails.",
    },

    -- Slot Reservations
    group_slot_reservations = { en = "Slot Reservations" },
    slot_reservations_enabled = { en = "Enable slot reservations" },

    -- Session Ignore List
    group_session_ignore = { en = "Session Ignore List" },
    session_ignore_enabled = { en = "Enable ignore list" },

    -- Kick on Idle
    group_kick_idle = { en = "Kick on Idle" },
    kick_idle_enabled = { en = "Auto-kick idle players in keep" },
    kick_idle_threshold_minutes = { en = "Idle threshold (minutes)" },
    ki_warn_seconds = { en = "Warning lead time (seconds)" },

    -- Message of the Day
    group_motd = { en = "Message of the Day" },
    motd_enabled = { en = "Send MOTD to joiners" },
    motd_text = { en = "MOTD text (use \\n for line breaks)" },
    motd_send_chat = { en = "Send via chat" },
    motd_send_popup = { en = "Send via popup" },
    motd_once_per_peer_per_session = { en = "Only greet each peer once per session" },
    motd_popup_topic = { en = "Message of the Day" },

    -- Modded Lobby Manifest  (Phase 2)
    group_modded_manifest = { en = "Modded Lobby Manifest" },
    manifest_broadcast_enabled = { en = "Broadcast my mod list (as host)" },
    manifest_failnotify_enabled = { en = "Show missing mods when a join fails" },

    -- Failed-join manifest reveal
    failnotify_title              = { en = "Cannot join — modded host" },
    failnotify_required_header    = { en = "You are missing %%d mods required by the host:" },
    failnotify_version_header     = { en = "%%d mods have a version mismatch:" },
    failnotify_cosmetic_footer    = { en = "Host also has %%d cosmetic mods you don't (gameplay unaffected)." },
    failnotify_button_workshop    = { en = "Open Workshop" },
    failnotify_button_cancel      = { en = "Close" },
}
