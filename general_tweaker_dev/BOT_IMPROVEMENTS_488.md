# Issue 488: additional bot improvement families

The request contains two independent engine families. They must not share a
toggle or be treated as one generic bot-AI change.

## Gas and warpfire resistance: potential fix

The damage identities are source-backed:

- Globadier area ticks use source `skaven_poison_wind_globadier`; Versus gas
  also uses damage type `gas`.
- Warpfire ground and face buff ticks use `warpfire_ground` and
  `warpfire_face` respectively.
- Both authoritative funnels consume `DamageUtils.apply_buffs_to_damage` before
  writing health. GT already owns that singleton hook for Godmode outgoing power.

`gt_bot_hazard_resistance` is a default-on child of the default-off Bot Behavior
Improvements master. On the host, each bot has independent gas and warpfire
expiry arrays held under weak unit keys. A positive matching hit is reduced by
the stacks active before that hit, then adds one stack expiring two seconds
later. Each stack is 20% and the oldest expiry is refreshed at the five-stack
cap. The first hit is unchanged. No custom buff, lookup, RPC, maximum-resource
write, or update loop exists.

Milestone diagnostics write only the first and full-stack observations per bot
and hazard, capped globally at 16 `[gt:488] bot-hazard` rows.

## Shield block against Ratling fire: diagnostics armed

Vanilla `PlayerBotBase._in_line_of_fire` decides whether to seek cover. Returning
false there does not request melee wield, hold block, manage stamina, or decide
when incoming Ratling bullets justify abandoning another bot task. Therefore no
block behavior is guessed yet.

The existing singleton hook observes ordinary Ratling cover evaluations before
any Improved Bot Combat gate. It records at most 12 distinct state shapes:

- current wielded slot/template and `shield_block` capability;
- melee-slot template and shield capability;
- current blocking state and input-extension presence;
- whether `hit_by_projectile` attributes damage to that Ratling;
- whether the Ratling targets this bot and is already an active cover threat.

Rows end in `mutation=0`. A representative log should include a shield bot with
ranged and melee slots wielded, both before and after its first attributed hit.
That evidence determines whether a bounded BT condition/action override can
reuse vanilla wield/block behavior. Any eventual behavior change requires co-op
verification because the host owns bots but peers render their actions.

## Source evidence

- `scripts/unit_extensions/weapons/area_damage/area_damage_templates.lua:6-64`
- `scripts/unit_extensions/weapons/area_damage/area_damage_templates_vs.lua:85`
- `scripts/unit_extensions/default_player_unit/buffs/buff_function_templates.lua:1401-1414,1890-1905`
- `scripts/unit_extensions/human/player_bot_unit/player_bot_base.lua:1321-1377`
- `scripts/settings/equipment/weapon_templates/1h_swords_shield.lua:1361-1376`
