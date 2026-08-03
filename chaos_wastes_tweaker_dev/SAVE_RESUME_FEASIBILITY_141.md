# Save/Resume Feasibility (#141)

The native rejoin path proves that a Chaos Wastes run can be reconstructed from its compact run configuration and host-owned shared state. The graph is regenerated from `run_seed`; it does not need to be serialized as geometry.

The deployed diagnostic inventories seven run-configuration getters, four progress getters, the shared-state full-sync boundary, and the three per-player read/write families: power-ups, currency, and loadout. It performs no writes and captures at most six times per session (automatic StateIngame reports stop at four, reserving two captures for manual `/ct_resume_audit` calls); each report also names the missing getters (`config_missing=` / `progress_missing=`, bounded).

Run `/ct_resume_audit` during an expedition. A complete Phase 1 candidate reports `config=7/7`, `progress=4/4`, all player read/write fields true, and `mutation=false`. Missing values identify timing gaps separately from missing methods.

Implementation remains phased: first prove host-only restore onto the map-vote screen; then remap saved player records by profile/career and rely on native full sync; finally add slots and injected-map graph metadata. Never restore a live mission mid-level.
