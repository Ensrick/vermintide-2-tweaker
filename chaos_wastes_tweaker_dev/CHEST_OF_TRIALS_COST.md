# Chest of Trials Activation Cost (#63)

CT dev 0.7.284-dev adds an optional, host-controlled Pilgrim's Coin cost to
start a Chest of Trials. It applies to both native Chaos Wastes chests and the
same `DeusCursedChestExtension` spawned on CT-injected Adventure missions.

## Behavior

**Charge Coins to Start a Chest of Trials** defaults off, preserving vanilla.
When enabled, the configured 25-1000 cost is rounded to the nearest 25 and shown
in the activation prompt; an underfunded local player sees a clear “Need N” prompt.
Only the human who completes the activation pays.
Insufficient balance leaves the chest in WAITING and spends nothing. Trial
completion and reward collection remain free.

The cost composes with **Open Reward at Trial Start**: activation is charged once
at WAITING -> RUNNING; accessing either the early or ordinary reward never charges
again.

## Authority and transaction

Vanilla calls `DeusCursedChestExtension.on_server_interact` with the true
interactor unit and performs the sole WAITING -> RUNNING state change there. CT
uses that server boundary and resolves `Managers.player:owner(interactor_unit)`;
the client never supplies a buyer id and no new RPC is registered.

The host reserves the charge in the buyer's existing `DeusRunState` soft-currency
row, calls vanilla exactly once, and commits only if the chest leaves WAITING.
A vanilla error or failed transition restores the exact prior balance. Successful
charges use vanilla's coin-tracking ledger. Missing owner, run state, balance, or
debit authority fails closed without starting the chest.

The existing host-setting broadcast automatically includes both new settings.
The existing cursed-chest interaction hook owns the prompt key, and CT's single
global `Localize` hook renders the effective host cost; no duplicate hook shadows
the early-reward feature.

## Verification

Lifecycle: `verify-fix-coop` only.

1. Host and client run CT dev 0.7.284-dev. Enable the cost and set 100 coins.
2. Have a client with 99 coins activate a native chest: it must remain idle and
   spend nothing.
3. Give that client exactly 100 coins. Confirm the prompt shows 100, activation
   starts, and only that client reaches zero.
4. Race host/client activation once; exactly one player pays exactly once.
5. Repeat on a CT-injected Adventure chest.
6. Enable early reward access and confirm neither reward opening nor ordinary
   completion charges a second time.
7. Disable the feature and confirm activation is free. Run `/ct_regression_test`
   and require `issue63_cot_cost_transaction` to pass.
