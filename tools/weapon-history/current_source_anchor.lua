-- Canonical current-source identity for every generated weapon-history catalog.
--
-- content_revision is the semantic game-source commit. observed_default_tip is
-- recorded separately because the canonical default branch currently has one
-- later README-only commit. Release freshness checks compare the live remote
-- HEAD with observed_default_tip without fetching into any repository.
return {
    canonical_url = "https://github.com/Aussiemon/Vermintide-2-Source-Code",
    content_revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    default_ref = "refs/heads/master",
    game_version = "6.12.0",
    observed_at_utc = "2026-08-28T23:45:18Z",
    observed_default_tip = "fd46866fe4d9aad8a1f1480fad4be6b960d4f83e",
    observed_tip_content_relation = "direct_parent",
    observed_tip_metadata_paths = { "README.md" },
    schema = 1,
}
