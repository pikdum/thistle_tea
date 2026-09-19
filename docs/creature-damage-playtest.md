# Creature-specific flat damage

DBC aura 59 now loads as `mod_damage_done_creature`. Beastslayer, Elemental
Slayer, and other slaying passives contribute damage only against matching
creature types. Ordinary equipment bonuses and independent enchantment aura
sources share the same caster snapshot. The target's current creature type
selects the bonus without changing displayed weapon damage or spell power.

Weapon attacks add the bonus after weapon-percentage scaling, then apply
outgoing modifiers, the off-hand penalty where applicable, armor, and attack
outcomes. Non-weapon melee/ranged damage uses the effect coefficient. Magic
damage adds the flat amount independently of coefficient-scaled spell power.
Periodic damage and leech capture their recipient's bonus at application;
healing and percentage-health damage receive none. Fixed damage, spells that
ignore caster modifiers, and Ignite exclude the new bonus.

Reference: `SpellCaster::MeleeDamageBonusDone` and
`SpellCaster::SpellDamageBonusDone` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`.

## Client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled level-50
Debugdruid on Programmer Isle against a fresh local server. Existing debug
commands supplied the recipes, Enchanting window, rod, and materials. Both
enchants used the real crafting window and equipped Barman Shanker target;
god mode was disabled during crafting and enabled during combat. Tidewave
probes only read state.

- Unenchanted rank-1 Moonfire dealt three 4-damage ticks to the level-55
  Devilsaur. Client combat-log messages matched authoritative health changes.
- Lesser Beastslayer stored permanent enchantment 853 and produced the
  `{beast mask 1, +6}` snapshot. The weapon tooltip displayed `Beastslaying +6`.
  Displayed server weapon damage stayed at 70.42857–114.42857.
- Moonfire then dealt three 10-damage ticks. One direct hit dealt 12 damage
  with 4 resisted, which the client reported separately.
- Unequipping during a subsequent successful Moonfire removed the caster's
  bonus immediately. The already-applied DoT retained its 10-damage ticks:
  health fell from 7,774 to 7,764 and then 7,754 after removal.
- A new cast without the weapon returned to three 4-damage ticks. Re-equipping
  restored the enchant, visible tooltip, and its passive source.
- The client's replacement dialog exchanged Beastslayer for Lesser Elemental
  Slayer. The snapshot changed to `{elemental mask 8, +6}`. Moonfire against
  the same beast returned to three 4-damage ticks, with no stale beast bonus.
- Logout removed the player owner while retaining enchantment 854 in the
  runtime store. Reconnecting created a new owner with exactly one enchant
  source, spell 13651, the elemental bonus, and the `Elemental Slayer +6`
  tooltip. No Beastslayer source returned.

The high-level Devilsaur resisted two attempted casts; the successful repeat
provided the unequip evidence. Weapon attack arithmetic, ranged abilities,
critical hits, independent enchant stacking, broken-equipment removal, durability
restoration, and death are covered by automated tests. No second observer or
positive elemental-target combat scenario was exercised in the client.

No error-level server logs occurred. Existing unsupported account-data,
raid-info, GM-ticket, time-query, meeting-stone, and cancel-trade UI requests
appeared as warnings. The isolated client and retained server were stopped.

## Evidence and validation

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.yTSJ91/screenshots/`.
- Server log: `/tmp/thistle-target-damage-server.log`.
- Owner samples: `/tmp/thistle-target-damage-{baseline,beastslayer,unequip-dot-repeat,without-weapon,elemental-vs-beast}.txt`.
- Reconnect: `/tmp/thistle-target-damage-{logged-out,reconnected}.txt`.
- `mix test.all`: 3,459 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.

The full suite initially exposed randomness in the new periodic refresh test:
its synthetic stun flag had been recomputed away, allowing an avoidance roll
to reject the refresh. The snapshot test now uses the aura application boundary;
separate spell-reception tests retain hit-path coverage.
