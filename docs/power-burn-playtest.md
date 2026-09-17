# Periodic power burns

Aura 162 now consumes the target's active power on its DBC tick interval and
converts the amount actually consumed into spell damage. Ignite Mana and Soul
Tap deal one damage per mana; Brood Affliction: Blue has a zero conversion and
only drains mana. A mana burn skips energy/rage forms without consuming their
hidden mana. Shields protect health without refunding the resource loss.

Direct and periodic burns share a pure power-consumption path and the existing
spell-damage calculation, including school mitigation, absorption, criticals,
and combat feedback. Direct burns also honor spell-modifier conversion bonuses.
Periodic burns retain the cast-time caster snapshot, consistent with the
project's spell context model; VMangos instead consults the live caster for
some tick calculations. No database reads or process lookups occur in the core.

The shared aura lifecycle owns refresh, dispel/removal, expiry, and death.
Refresh preserves the already scheduled tick while extending the duration.
Lethal ticks do not resurrect their holder after death cleanup. The existing
Mana Burn implementation also no longer hardcodes the mana field, treats zero
conversion as one, or loses absorption in its damage event.

`.modify mana <value>` sets current mana between zero and the character's maximum
for client-driven resource tests.

References: `Spell::EffectPowerBurn` in
`refs/vmangos/src/game/Spells/SpellEffects.cpp` and the
`SPELL_AURA_POWER_BURN_MANA` branch of `Aura::PeriodicTick` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`.

## Bugs found during acceptance

The first shielded live tick consumed 500 mana, exhausted a 454-point Ice
Barrier, and removed 46 health. The client incorrectly reported 500 damage plus
454 absorbed. The shared spell-damage packet projection now subtracts absorbed
damage, with regression coverage for no absorption, partial absorption, and
full absorption on both the target and observer connections.

Live samples also showed health regeneration and the client leaving combat
while Soul Tap was still ticking. Incoming sourced damage and outgoing harmful
spell feedback now refresh the existing player combat timer. A zero-damage
power burn refreshes it when it actually consumes power and emits zero-damage
feedback for the caster. Environmental/self damage, healing, dead players, and
empty-resource burns do not establish a new hostile contact.

A simultaneous reconnect of the two clients also exposed a pre-authentication
failure: sending `SMSG_AUTH_RESPONSE` after a rejected session attempted to
measure a nil encryption key and crashed the connection. Header encryption now
passes bytes through until a key exists, matching VMangos `AuthCrypt::EncryptSend`.
The no-key rejection header and initialized rolling cipher have regression tests.
This does not change the account's single pending authentication-session model;
the acceptance clients logged in sequentially after that rejected reconnect.

## Real-client acceptance

Two isolated build-5875 clients controlled level-50 Debugmage (GUID 5) and
Debugwarlock (GUID 6) in a duel on Programmer Isle, with god mode disabled.
All spells, resource setup, dispels, and death commands came through the client.
Read-only owner samples captured health, mana, aura amounts and deadlines, and
both participants' combat flags. Ordinary regeneration remained enabled.

- Soul Tap consumed 500 mana and dealt 500 shadow damage on its first unshielded
  tick. With only 358 mana left on the next tick, it consumed and dealt 358.
  Later ticks consumed the 43 mana restored by each regeneration tick. The
  client's combat log matched those amounts and displayed the aura fading.
- After both gameplay fixes, a 500-mana Soul Tap tick exhausted a 454-point Ice
  Barrier and dealt exactly 46 health damage. The client displayed
  `46 (454 absorbed)`. Both participants remained in combat through all six
  ticks; no health regenerated during that interval. Soul Tap and its silence
  expired after 12 seconds. Combat cleared about five seconds after the final
  tick, and health regeneration resumed afterward.
- Brood Affliction: Blue consumed 50 mana each second while health remained
  exactly 1,875. Recasting retained a single holder, extended its expiration by
  approximately 6.3 seconds, and preserved the next tick. Both players' combat
  timers refreshed while the mana drain succeeded. The mage's actual Dispel
  Magic cast removed the holder, its movement/casting penalties, and its future
  ticks; the client displayed removal and mana began accumulating again.
- Direct Mana Burn consumed 210 mana while Ice Barrier absorbed all 105 damage.
  Health remained 1,875 and barrier capacity fell from 454 to 349. The mage's
  combat log reported absorption; the caster's independent client also reported
  that Mana Burn was absorbed.
- A fresh Blue affliction was active when the mage used `.die`. Health became
  zero, mana stayed at 322, the burn and barrier were removed, and the duel
  cancelled. A later read still showed zero health, 322 mana, no pending aura
  tick, and no combat state. Only the character's permanent racial passives
  remained. The client showed the release-spirit prompt.

Automated tests additionally cover wrong/invalid power types, hidden mana while
in energy form, resuming after returning to mana form, conversion modifiers,
critical hits, spell power exclusion, immunity, empty resources, lethal burns,
and target/observer packet projection. Those variants were not all exercised
in the live clients. Ignite Mana's DBC mapping and cadence were verified by the
DBC test; the live damaging periodic spell was Soul Tap.

The first server launch timed out loading waypoints while other validation was
running. A subsequent development code reload interrupted an exploratory client
session. Neither session was used to accept the fixes. On the fresh final
server, the only connection error was the pre-authentication rejection described
above, before gameplay acceptance. No player-owner, spell, or packet errors
occurred during the accepted gameplay sequence. Clients and the server were
stopped before the final validation run.

## Validation and evidence

- `mix test.all`: 3,123 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Final gate logs: `/tmp/thistle-burn-final-{tests,compile,credo}.log`.
- Mage screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.YIu3ED/screenshots/`, particularly
  `soul-tap-expired.png`, `final-shield-active.png`, `final-blue-active.png`,
  `final-blue-dispelled.png`, `final-direct-absorbed.png`, and `final-death.png`.
- Caster screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.Wav5qt/screenshots/final-caster-log.png`.
- Accepted runtime samples: `/tmp/thistle-burn-final-{shield,blue,direct,dead}.txt`.
  Initial unshielded samples: `/tmp/thistle-burn-expiry.txt`.
- Final server log: `/tmp/thistle-burn-server-final.log`.

One full-suite attempt timed out in the cell-retry test while the two software
renderers saturated the CPU. With the isolated clients paused/stopped, the full
suite passed. No test timeout or production retry behavior was changed.
