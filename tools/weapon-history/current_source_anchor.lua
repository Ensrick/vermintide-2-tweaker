-- Canonical current-source identity for every generated weapon-history catalog.
--
-- content_revision is the semantic game-source commit. observed_default_tip is
-- recorded separately so release freshness checks can compare the live remote
-- HEAD without fetching into any repository. Schema 2 records the common case
-- where the semantic content revision is itself the observed default tip.
return {
    canonical_url = "https://github.com/Aussiemon/Vermintide-2-Source-Code",
    content_revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    default_ref = "refs/heads/master",
    game_version = "6.12.1",
    observed_at_utc = "2026-09-03T22:09:45Z",
    observed_default_tip = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    observed_tip_content_relation = "same_commit",
    observed_tip_metadata_paths = {},
    schema = 2,
}
