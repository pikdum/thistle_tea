# Area spell target limits

The spell loader now retains the DBC's maximum affected target count.
Unit target selection applies that limit after eligibility and exclusion
checks, retaining an eligible explicit primary target and choosing the
remaining slots randomly. Zero remains unlimited. Selection happens before
hit rolls, and the cast resolution supplies the same recipients to launch
packets and effect delivery. Caster execution effects have their own target;
chain jumps retain their separate effect-specific count and order.

Triggered areas, query deliveries, and dynamic-object pulses use the same
boundary selection. Game-object spells apply the limit independently to
each effect's eligible objects. Their existing distance order is preserved.

The investigation also found that Intimidating Shout's primary-target stun
trigger was being delivered to secondary targets. It now applies only to
the primary target; secondary recipients receive the fear effects.

## References and automated validation

- `refs/vmangos/src/game/Spells/Spell.cpp`, `SetTargetMap`: maximum affected
  targets, random removal of excess unit targets, retention of the explicit
  primary target, and the chain-target override.
- The same file's `AddGOTarget`: maximum object targets per effect.
- `refs/vmangos/src/scripts/spells/spell_warrior.cpp`,
  `WarriorIntimidatingShoutScript`: the primary target does not receive the
  secondary fear effects. Its DBC effect 0 targets that unit directly.
- Local DBC rows provide rank-specific Psychic Scream limits, four targets
  for Thunder Clap and Whirlwind, five for War Stomp and Howl of Terror,
  and the object limit for Hatch Eggs.

Commit `9cf738b3` passed `mix test.all` (5,596 tests),
`mix compile --warnings-as-errors`, `mix credo --strict` (zero issues),
formatting, and whitespace checks. Eleven new tests cover selection,
eligibility before counting slots, ground and cone areas, caster execution,
friendly exclusions, object effects, launch/delivery agreement, and both
individual and bulk DBC loading. Existing chain and Intimidating Shout
regressions now exercise the cap override and secondary-trigger exclusion.

## Native client acceptance

A fresh server on the implementation commit served the isolated build-5875
GPU client. Debugmage (GUID 5) and Debugwarrior (GUID 1) tested at level 60.
All setup and casts used native client commands; Tidewave only read state.
God mode was off for the four measured casts below. It was briefly enabled
between the mage trials while inspecting a wolf-applied debuff, then turned
off again before War Stomp. The warrior remained in normal combat.

The reusable development seed now includes six closely grouped Prairie
Wolf Alphas west of the playground. Their entry is 2960 and their low GUIDs
are 991700 through 991705. The test center is map 451 at
`{16153.2, 16298.1, 52.16}` after terrain snapping. A live spatial read
confirmed all six within eight yards. Initial health was 198 for four
wolves and 176 for the other two.

| Spell | Native result |
| --- | --- |
| Psychic Scream rank 1, 8122 | Exactly two wolves received fear. Four remained uncontrolled. Both holders and control states cleared after approximately eight seconds. |
| War Stomp, 20549 | Exactly five wolves received stun. The sixth stayed uncontrolled. All five holders and control states cleared after approximately two seconds. The client showed the stomp effect, stun rings, and the selected target's debuff. |
| Thunder Clap rank 5, 11580 | Wolves 991702 through 991705 each lost 82 health and received the melee-haste reduction. Wolves 991700 and 991701 retained full health and had no aura. The client showed the area effect and selected target's slow. |
| Intimidating Shout, 5246 | Selected wolf 991704 received only stun 20511. Four other wolves received fear 5246; wolf 991705 remained uncontrolled. No secondary wolf received the stun. All five controls expired after approximately eight seconds. |

The control samplers ran at roughly 20 ms intervals and retained state
changes. Psychic Scream appeared at 9,801 ms and cleared at 17,799 ms;
War Stomp appeared at 14,828 ms and cleared at 16,827 ms; Intimidating Shout
appeared at 2,292 ms and cleared at 10,284 ms. Each timestamp belongs to its
own sampler. Thunder Clap used a full-health baseline and an immediate
post-cast owner read; its earlier timed sampler finished before the cast.

After the warrior transferred to Northshire, the owner was ready, alive,
out of combat, and had god mode off. All six wolves had reset to full
health with no remaining auras. The helper-owned client cgroup and server
were stopped. WoW process 162288 had its own amdgpu rendering counters.
There were no server errors or cast-validation failures; unsupported
requests were limited to the existing account-data, GM-ticket, and
meeting-stone login messages.

There was no second observer client. Object caps, cone and destination
selection, friendly exclusions, and chain interactions have automated
coverage; the four trials above exercised native unit area casts.

## Retained evidence

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.t6D66j/`.
- Screenshots in its `screenshots/`: `psychic-scream-two.png`,
  `scream-expired.png`, `war-stomp-five.png`, `stomp-expired.png`,
  `thunder-clap-four.png`, `intimidating-shout-five.png`, and
  `shout-expired.png`.
- Control samples: `/tmp/thistle-target-limit-{scream,stomp,shout}.txt`.
- Thunder Clap baseline: `/tmp/thistle-target-limit-clap.txt`;
  immediate result: `/tmp/thistle-target-limit-clap-auras.txt`.
- Nearby eligibility, warrior setup, selected target, and cleanup:
  `/tmp/thistle-target-limit-between.txt`,
  `/tmp/thistle-target-limit-warrior.txt`,
  `/tmp/thistle-target-limit-shout-caster.txt`, and
  `/tmp/thistle-target-limit-final-state.txt`.
- Server and GPU evidence: `/tmp/thistle-target-limit-server.log` and
  `/tmp/thistle-target-limit-gpu.txt`.
- Final gates: `/tmp/thistle-target-limit-{tests,compile,credo}.log`.
