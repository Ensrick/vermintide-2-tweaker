# Issue #221: Subgroup-master audit and the armor cluster master

#445 already supplies Career Tweaker's safe whole-family controls. The remaining historical proposal is not one setting family: it combines armor hooks, Unchained overcharge hooks, native rework template mutations, and Tourney/native per-career catalogs.

The public beta runs the census once at startup and `/crt_umbrella_audit`
runs it on demand. Each invocation records one bounded `[crt:221]` line with:

- active/total counts for the complete Ensrick and Tourney catalogs;
- Unchained native-rework and separate runtime-overcharge counts;
- Outcast Engineer native-rework counts;
- the two armor-hook settings;
- `cluster_gates=N/4`, derived from the cluster families registered in
  `_crt_rework_master_policy.lua` (currently `1/4`: armor), and
  `mutation=false`.

The census registers no hooks and never writes a setting; `mutation=false` is a
contract enforced offline and by `/crt_regression_test`.

## Armor cluster master (CRT 0.4.30-beta with GUI Dev 0.2.346-dev)

`M.FAMILIES.armor` in `_crt_rework_master_policy.lua` registers the explicit
leaf list `armor_gromril_ignore_chip` and `armor_specials_dont_break_gromril`
under the master control `rework_master_armor` (**Enable all Armor Controls**
in `Talent Reworks > Master Toggles`). It is a cluster family, not an
authorship family: it carries no `[Ensrick]`/`[TB]` label prefix and is not a
member of the #445 radio group.

Why it is safely reversible: both leaves are live `mod:get` reads inside the
two unconditional hooks in `career_tweaker_armor_overcharge.lua`
(`DamageUtils.apply_buffs_to_damage`, `PlayerUnitHealthExtension.add_damage`).
Every entry point reads the leaf at hit time, so the bounded VMF setting batch
alone gates the feature; there is no template mutation to apply or restore, and
the transaction passes deliberate no-op reconcilers to `apply_bounded_master`.

Transaction contract (pure plan, `policy:plan("armor", enabled, current)`):

1. First ON: snapshot the exact current leaf values into private
   `rework_master_armor_saved_<leaf>` rows, raise `rework_master_armor_snapshot`,
   enable both leaves, raise the master. Only differing values are written.
   Repeated ON while the snapshot is held preserves that original preimage;
   OFF-then-ON staged before a single Apply is not a new transaction.
2. OFF with a held snapshot: restore each leaf to its saved value, release the
   snapshot flag, clear the master. Leaves already at their saved value are
   not rewritten.
3. OFF without a held snapshot: clear only the master flag. Saved leaf choices
   are never rewritten by a bare master flip.
4. Hand edit of either leaf (`policy:plan_cluster_custom`): clear the master
   and the snapshot flag without writing any leaf, so the indicator reflects a
   custom state and the player's new choice stands exactly as made.

Runtime receipts: `[crt:221] cluster=armor enabled=<bool> writes=<n> held=<bool>`
per master flip and `[crt:221] cluster=armor custom=true writes=<n>` when a hand
edit closes an open transaction.

### Profile replay ownership

Independent review (issue comment `5559346579`) reproduced profile replay
losing the master/snapshot while ordinary ON/OFF and restart restoration work.
The former GUT `_profile_snapshot` enumerated visible widgets only: it captured
the armor master and two leaves, but none of `rework_master_armor_saved_*` or
the snapshot flag. Its `Transaction.commit` sent CRT individual callbacks;
an unchanged leaf callback is indistinguishable from a manual edit and closes
the held transaction. Mixed master/child commits can also overwrite explicit
children depending on callback order.

The repair is the optional `mod_tweaker_settings_owner` v1 protocol (see
`MOD_DEPENDENCIES.md`). The existing GUT profile runtime now owns replay for
both presentations. It validates/prepares every owner before any setting or
profile write, carries an opaque bounded owner envelope, then stages only
registered visible setting members. The armor provider alone knows its private
setting IDs. A post-write `on_settings_batch_changed(ids)` cannot reconstruct
an overwritten preimage and is deliberately not used for this cluster.

Since 0.4.31-beta (#1575) CRT exposes that protocol through one composite
provider (`_crt_settings_owner.lua`): the armor owner plus ownership of the
derived family masters and Tourney career presets (consumed during replay,
ordered preset commands during Apply). Later cluster owners join the same
composite, because GUT reads one provider per mod.

- New armor metadata binds schema 1, owner `crt`, cluster `armor`, an exact
  Boolean held flag and both Boolean saved leaf values. Held profiles must also
  carry master ON and both visible leaves ON. Capture includes explicit false.
- Legacy profiles with no owner metadata preserve their visible leaves as a
  custom configuration (master/held OFF); no absent preimage is fabricated.
  Malformed, foreign, oversized or incomplete metadata rejects before writes.
- Master-only edits retain snapshot/restore semantics. A transaction with an
  explicit leaf edit preserves that edit and becomes custom, irrespective of
  hash iteration order. Other settings retain their existing callback paths.
- Opening writes establish the saved values/held flag before touching leaves;
  closing releases held state last. Failed replay retains the prepared plan,
  pending settings and old active slot. Retry must use unchanged inputs; a
  changed draft is rejected until restored or explicitly discarded. Already
  persisted partial writes are not claimed to be rolled back on menu exit.
- Successful replay saves the normalized target snapshot before changing its
  active slot. Failed owner work never captures over the previous profile.

Existing bug-class references: class 26 (false/nil pseudo-ternaries) and class
79 / #1002 (owner-bounded profile transactions). Both view `_cat_get` readers
and default snapshot selection now use explicit branches so false cannot turn
into absence or an enabled live default. No other talent system is redesigned.

Independent review also reproduced the automatic initialization bypass: a
foreign armor metadata cluster plus a missing member caused two live writes in
both actual `_profile_ensure` methods. They now share `Runtime.ensure_profile`.
Initialization and explicit switching use the same read-only provider/envelope
preparation; automatic initialization discards full replay plans and commits
only absent members. Validation also runs with zero additions, before schema
migration or persistence. Invalid state remains stored unchanged and unready;
pending drafts survive. Modern/legacy additions-only controls and interrupted
migration/commit/profile-save retries execute through both installed methods.

The missing-master boundary has its own regression: treating a missing legacy
master as an ordinary OFF edit restored existing leaves from the live held
preimage (three live writes, one stored-profile write, false readiness). The
actual addition plans now use `kind="reconcile"` and are prepared before schema
writes. CRT applies absent leaf defaults only and retires master/held ownership
as custom without restoring any present leaf. Reusing the full validated plan
is unsafe because stored leaves may differ from current live leaves. Stored
present leaf values remain unchanged; automatic initialization is not replay.
Both installed entrypoints cover all four preimages, differing stored values,
and partial master/held-write retries. Ordinary explicit OFF still restores.

The independently reviewed candidate (freeze `66b73a91`) was reconciled onto
master with all #998 Dialogue/GUT guards retained and landed as Careers
0.4.30-beta plus GUI Dev 0.2.346-dev under fresh broker allocations (the
unbuilt .29 draft number stays burned). Users of the older GUT profile consumer,
including public Tweaker: GUI 0.2.289, do not gain this protocol merely from
updating CRT: their profile switches still omit the private preimage, so a later
OFF cannot restore the pre-toggle choices there. Public GUT promotion and live
verification remain separate gates.

## Promotion criteria for the remaining subgroups

1. Define the exact leaf and non-leaf owner catalog.
2. Gate every feature entry point, including hook-owned behavior.
3. Restore exact vanilla/template state when the master is disabled.
4. Preserve saved child choices while the master is off.
5. Apply or restore each owner once, with nested callbacks suppressed.
6. Prove default behavior is unchanged and peer/network registration is independent of the toggle.

Unchained (reworks plus runtime overcharge reads), Outcast Engineer, and
per-career clusters remain deferred until an owner meets those criteria. This
candidate implements only the armor cluster, not all of #221.
