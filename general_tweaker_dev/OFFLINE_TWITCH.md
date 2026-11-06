# Offline Twitch mode (#333)

General Tweaker does not implement a second vote protocol. When the host enables
**Offline Twitch Mode**, it creates the same `TwitchGameMode` used by Fatshark's
`twitch_debug_voting` path and lets vanilla own vote timing, random tie-breaking,
vote game objects, UI, effects, and RPCs. No Twitch account or IRC connection is
required. The option takes effect when the next supported mission activates its
Twitch manager.

Event controls compose the existing `TwitchGameMode._in_whitelist` candidate
gate with the native standard-ballot selector. Native candidate B does not
consult that gate, so the enabled feature uses the same source-qualified
condition, cost, used-vote and boss-match rules while applying the composed
gate to B and both breed-package replacements. Disabled mode calls the native
method unchanged, including for a live Twitch connection. No shared lookup or
instance method is temporarily replaced: condition callbacks and reentrant
selection cannot observe a temporary global filter.

The candidate lookup is snapshotted once per call. Rejected replacements are
tracked by lookup key, not a possibly aliased template name. The owned selector
has a finite initial-candidate budget and clears native used votes at most
once before deferring an impossible ballot. Native package loading still owns
its original locks, errors and internal retries; this does not claim to bound
that separate engine loader. Behavioral tests run the actual Dev and official
hooks against the retained native selection/package-loader oracle in
`qa/lua/tests/fixtures/gt_native_standard_vote.lua`.

Item templates begin with `twitch_give_`; spawn templates begin with
`twitch_spawn_` or declare a breed/boss/special; mutators use vanilla mutator
localization prefixes; remaining and future templates are grouped as buffs and
effects. Vanilla's own game-mode whitelist is evaluated first and cannot be
overridden. These controls also apply when a real Twitch account is connected.

The host is authoritative. Clients receive only vanilla Twitch vote traffic and
need no new RPC schema. Verify with two players: enable the mode on the host,
leave Twitch disconnected, load a supported mission, observe votes resolve and
apply, then disable one category and confirm later ballots contain none of that
category. Repeat with a vanilla client and confirm its vote UI/effects remain in
sync. Run `/gt_regression_test` and confirm `issue333_offline_twitch_policy`
passes.
