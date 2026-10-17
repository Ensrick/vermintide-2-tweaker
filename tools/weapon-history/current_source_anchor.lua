-- Canonical current-source identity for every generated weapon-history catalog.
--
-- content_revision is the semantic game-source commit. observed_default_tip is
-- recorded separately so release freshness checks can compare the live remote
-- HEAD without fetching into any repository. Schema 2 records the common case
-- where the semantic content revision is itself the observed default tip.
return {
    canonical_url = "https://github.com/Aussiemon/Vermintide-2-Source-Code",
    content_revision = "93dea911a4cc464a0eb51cfdc3a443297bfc4550",
    default_ref = "refs/heads/master",
    game_version = "6.13.0",
    observed_at_utc = "2026-10-17T12:23:08Z",
    observed_default_tip = "93dea911a4cc464a0eb51cfdc3a443297bfc4550",
    observed_tip_content_relation = "same_commit",
    observed_tip_metadata_paths = {},
    schema = 2,
}
