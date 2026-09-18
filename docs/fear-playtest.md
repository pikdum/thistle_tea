# Creature fear movement

Creatures and pets now run while feared instead of using the four-yard
confusion wander. Each run starts at the current position; caster proximity
controls the distance of the next randomly directed destination. Runs use
strict slope filtering, stop after at most 30 yards of traversed path, and
pause for 800–1,500 ms before the next run. Failed navigation retries after
a bounded delay without allowing the creature to attack during fear.

The creature owner supplies caster observations and reachable destination
points. Behavior-tree nodes consume that snapshot and enqueue navigation
intents. The shared aura transition stops old movement, clears pending
navigation, derives the fleeing flag, and restores the previous running mode
when fear ends. Roots, stuns, confusion, source replacement, dispels, expiry,
and death use those same transitions. Existing threat and patrol configuration
survive the control period.

Curse of Recklessness suppresses fear without removing the fear aura. Replacing
the curse restores fear for its remaining duration. Suppressed fear permits
casting; ending suppression interrupts an in-progress cast. This work adds
creature and pet movement; it does not add server-driven fear movement for
player characters.

References: `FleeingMovementGenerator.cpp`, `Unit::SetFeared`,
`Unit::ModConfuseSpell`, and `Aura::HandlePreventFleeing` under
`refs/vmangos/src/game/`. Destination selection follows the reference's
random panic runs and distance bands; this is not a complete port of its
collision, transport, and assistance behavior.

## Automated acceptance

Tests cover creature and pet behavior-tree selection, run speed, run/pause
cadence, unavailable points, failed paths, path-length clipping across bends,
roots and stuns, confusion precedence, caster replacement, dispels, expiry,
death, curse suppression and restoration, and preservation of threat and
patrol settings. An owner-boundary test observes the fear caster outside the
ordinary perception radius. DBC tests exercise Fear, Psychic Scream, Scare
Beast, and replacement of Curse of Recklessness with Curse of Weakness.

Two lifecycle fixes accompany the feature: aura maintenance now preserves AI
memory changes made by aura transitions, and fear suppression consistently
affects casting and crowd-control queries.

## Client validation

The initial isolated build-5875 client pass used level-50 Debugwarlock and the
seeded Defias Thug on Programmer Isle. Fear visibly sent the creature running
and cleared on expiry; the creature then returned to its spawn. Attempts to
apply curses from the original position correctly showed “Out of range.”

That pass exposed random navigation points outside the requested search radius
on large polygons. The follow-up fix limits actual traversed path length, with
a regression covering a bent path. The server was restarted before the final
acceptance pass.

Initial evidence: `/tmp/thistle-fear-initial-live.txt`,
`/tmp/thistle-fear-server.log`, and screenshots under
`/home/pikdum/.cache/thistle-wow-playtest.vl7Iaa/screenshots/`.

### Final client sequence

On the restarted server, the same level-50 warlock moved close to the thug
(GUID `17379390962661268572`). All spells were cast through the client;
Tidewave sampled the owning process and public world position without changing
gameplay state.

- At 3.37 seconds, Fear (6213) was active and the creature was running. Its
  flags were `8912896` (combat plus fleeing), with the warlock still targeted.
- At 5.64 seconds, Curse of Recklessness (704) had joined the retained Fear
  holder. Effective fear became false, fear memory cleared, flags returned to
  `524288` (combat), and the creature chased the warlock.
- At 10.56 seconds, Curse of Weakness (702) had replaced Recklessness. The
  original Fear holder resumed driving movement without another fear cast.
- At 18.49 seconds, Fear had expired. Only Weakness remained; fear memory and
  the fleeing flag were cleared, and the creature resumed chasing its retained
  target. At the end of the 40-second sample it remained alive and in combat.

Evidence: `/tmp/thistle-fear-final-live.txt`,
`/tmp/thistle-fear-final-server.log`, and `final-suppressed.png`,
`final-restored.png`, and `final-expiry.png` in the screenshot directory above.

### Death and respawn

The existing `.learn 17877` command supplied rank-1 Shadowburn, which the
trainer-spell seed does not include. A new client Fear cast started a capped
run (3,999 ms at the aura-modified running speed). Shadowburn killed the thug
while that run was active, at 4.51 seconds in the sampler. Health became zero,
holders emptied, flags cleared, fear memory became nil, and the spline stopped.

At 34.56 seconds it respawned with its original 86 health, no holders or fear
memory, and normal combat behavior. The client showed the corpse and then the
living thug attacking the warlock again.

Evidence: `/tmp/thistle-fear-death-live.txt`, `final-death.png`, and
`final-respawn.png`. No owner crashes, server errors, or cast-validation
failures occurred in the final pass. Login emitted existing unimplemented
account-data, raid-info, GM-ticket, time-query, and meeting-stone warnings.

Pet movement, root/stun handling, dispels, and caster replacement were verified
by automated tests rather than additional client sessions. Both server runs
and the helper-owned client/X server were stopped; artifacts were retained.

## Final validation

- `mix test.all`: 3,196 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

Logs: `/tmp/thistle-fear-final-{tests,compile,credo}.log`.
