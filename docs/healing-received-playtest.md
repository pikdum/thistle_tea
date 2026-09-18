# Healing received

Percentage healing-received auras now share a pure rule across direct heals,
maximum-health heals, HoTs, percentage-health ticks, and transferred life-leech
healing. Each holder's stacks contribute to its strength. Only the strongest
reduction and strongest increase apply, multiplied together, regardless of
school mask. Complete suppression clamps healing to zero.

Periodic healing reads the recipient's current modifiers at every tick; the
stored caster-side amount and tick schedule stay intact. Removing the strongest
reduction lets a weaker reduction resume. This change handles
percentage modifiers (aura 118); it does not redesign flat healing bonuses or
natural health regeneration.

References: `Unit::SpellHealingBonusTaken` in
`refs/vmangos/src/game/Objects/Unit.cpp`, the periodic-heal branch in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`, and `Spell::EffectHealMaxHealth`
in `refs/vmangos/src/game/Spells/SpellEffects.cpp`.

## Related fixes

- Stacked HoTs now heal for their remaining stack count.
- Percentage-health ticks generate threat from actual healing, capped by
  missing health, like ordinary HoTs.
- Delayed life-leech transfers cannot restore health to a dead player or
  creature. Tests exercise both receiving owners directly.
- Direct healing previously notified proc handling but sent no combat-log
  packet. `SMSG_SPELLHEALLOG` now reports the resolved amount and critical flag
  to the recipient and nearby observers. Maximum-health heals also emit this
  feedback. Periodic healing keeps its existing periodic log without duplicates.
  The codec follows the 1.12 specification in
  `refs/wow_messages/wow_message_parser/wowm/world/spell/smsg_spellheallog.wowm`.

## Automated acceptance

Pure and boundary tests cover strongest positive/negative selection, ignored
school masks, stack scaling, full suppression, direct/max-health healing,
periodic feedback and effective threat, live modifier changes without snapshot
mutation, partial dispels, expiry, weaker-effect restoration, death cleanup,
and transfers to player and creature owners. Projection tests cover recipient
and observer delivery and absence of duplicate periodic heal logs; packet tests
check packed GUIDs, little-endian fields, and the critical byte.

Separate DBC-tagged tests load Hex of Weakness, Gehennas' Curse, Blood Fury, and
Mortal Wound, including ten applications of Mortal Wound reaching zero healing.

## Real-client acceptance

An isolated build-5875 client controlled level-50 Debugpriest (GUID 4) on
Programmer Isle. Setup used existing `.learn` and `.modify hp` commands; casts
came through the client. Tidewave probes only read owner state.

- Rank-1 Renew stored 9 healing per tick. Applying Blood Fury (23230) changed
  subsequent ticks to 4, including a client combat-log line and floating +4.
  The holder retained amount 9 and its three-second cadence.
- Lesser Heal landed for 25 during suppression; the owner sample separated
  that gain from Renew ticks and ordinary regeneration.
- A second sequence cast Renew near Blood Fury's expiry. At 25.97 seconds in
  the sampler, the tick healed 4 (697 to 701). Blood Fury expired at 28.31
  seconds. The same Renew then healed 9 (767 to 776) at 28.96 seconds, with no
  recast or change to the stored amount. The client displayed the 4-to-9
  transition and floating +9. Renew expired normally after its final tick.

Initial evidence:

- `/tmp/thistle-healing-transition.txt` contains the complete expiry sequence.
- `/tmp/thistle-healing-live.txt` contains the initial suppression sequence;
  its final output was truncated, so the complete transition sample above is
  the authoritative expiry evidence.
- `/tmp/thistle-healing-server.log` records the client casts.
- `/home/pikdum/.cache/thistle-wow-playtest.LOI6k4/screenshots/` contains
  `suppression.png`, `healing-log.png`, and `expiry-restores-renew.png`.

The missing direct-heal packet was discovered in that first playtest and fixed
before the final client pass.

## Final client pass

The restarted server included the direct-heal packet fix. The client combat
log showed Lesser Heal healing for 53 before suppression and 26 with Blood
Fury active. The owner sampler recorded the suppressed heal as 584 to 610,
separate from regeneration. Renew again displayed 4-point ticks while its
stored amount remained 9.

At 21.88 seconds in the final sampler, `.die` changed health from 890 to zero
while both Renew and Blood Fury were still active. Both disappeared, the
healing-received percentage returned to normal, and health stayed at zero for
the rest of the 40-second sample. A separate read confirmed only racial
passives remained and `Aura.next_event_at/1` returned nil. The client displayed
the release-spirit prompt.

- Final server: `/tmp/thistle-healing-final-server.log`.
- Final samples: `/tmp/thistle-healing-final-live.txt` and
  `/tmp/thistle-healing-final-death.txt`.
- Final screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.jbmZIC/screenshots/`, including
  `direct-heal.png`, `suppressed-heal-log.png`, and `death-cleanup.png`.

No owner errors or cast-validation failures occurred. Login emitted existing
unsupported account-data, raid-info, GM-ticket, time-query, and meeting-stone
warnings. Observer delivery, critical packet encoding, positive amplification,
partial dispels, and life-leech transfer behavior were verified by automated
tests, not additional client sessions. Both clients and servers were stopped;
logs and screenshots were retained.

## Final validation

- `mix test.all`: 3,161 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Logs: `/tmp/thistle-healing-final-{tests,compile,credo}.log`.
