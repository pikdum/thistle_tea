# Alterac Valley named air assaults

This milestone adds the six supplied wing commanders' named air attacks.
Planted beacons and their generic attackers are covered by
[the beacon acceptance notes](alterac-beacon-playtest.md).
Reference behavior comes from
`refs/vmangos/src/scripts/battlegrounds/battleground_alterac.cpp` and
`refs/vmangos/src/game/Battlegrounds/BattleGroundAV.cpp`.

A rescued commander with enough supplies offers the reference launch dialogue
to an admitted friendly player in an active match. Neutral or better standing
qualifies, matching the reference's final reputation check. Ordering a launch
retains the supplies and prevents a second order for that fleet in the match,
including after death, respawn, or another rescue. Each fleet remains independent.

Five seconds after the order, the commander removes quest service, transforms
into a flying mount, and ascends thirty yards. At ten seconds she becomes
permanently invisible and summons the appropriate named attacker at her current
position. The attacker flies to the opposing base, then patrols a circle with
a radius of fifty-five yards and acquires hostiles within fifty yards.

| Commander | Named attacker | Entry | Mount display |
| --- | --- | --- | --- |
| Guse | Guse's War Rider | 14943 | 11012 |
| Jeztor | Jeztor's War Rider | 14944 | 11012 |
| Mulverick | Mulverick's War Rider | 14945 | 11012 |
| Slidore | Slidore's Gryphon | 14946 | 1148 |
| Vipore | Vipore's Gryphon | 14948 | 1148 |
| Ichman | Ichman's Gryphon | 14947 | 1148 |

Horde attackers approach `{618.4, -87.97, 85.77}`; Alliance attackers approach
`{-1311.53, -355.28, 130.93}`. Their spell kit is Fireball (22088), Fireball
Volley (15285), and Stun Bomb Attack (21188), available initially at zero,
eight, and thirteen seconds and repeated at five, seven-and-a-half, and nine
seconds respectively. Successful casts restart the timers; casting failures
retry. The kit requires a victim within thirty yards.

The shared behavior tree now supports a script-supplied caster chase distance.
These attackers stop at twenty-five yards, preserve altitude during their
approach, face their victim, and approach closer when line of sight is blocked.
Respawn clears the script override before spawn events reapply it.

## Automated acceptance

Pure tests cover all six launch choices, eligibility, insufficient supplies,
duplicate orders, independent fleets, preserved stockpiles, death and respawn,
transformation and summon timing, approach destinations, arrival activation,
target acquisition, spell range, flight altitude, caster stopping, blocked
sight, foreign worlds, and override reset. VMangos-tagged tests verify all six
attacker templates and launch texts, including the boot text cache.

Native testing found two shared script defects. A delayed summon used the
owner's stale movement position, which placed the attacker too low for its
approach path. Script receipts now synchronize the current spline before
building observations and executing steps. The aura command also ignored the
reference's permanent flag; it now carries a permanent duration through the
triggered spell resolver without modifying the cached spell. Regressions cover
both failures.

The full suite also exposed a telemetry test race: unrelated background metrics
can add rows to the shared collector during the concurrency check. The test
now checks the tested histogram's fixed storage size and all eight thousand
updates, rather than assuming that the entire collector remains unchanged.

## Native acceptance

An isolated build-5875 GPU client entered a live Alterac Valley match as a
Horde shaman. Guse completed her full rescue route without teleporting the NPC
or advancing waypoints through runtime probes. Ninety real quest exchanges
consumed ninety Soldier's Flesh and credited ninety supplies and ninety
Frostwolf reputation. A temporary client frame handled the ordinary quest
progress and reward events for the repeated exchanges.

The player selected the visible launch dialogue. A read-only sampler recorded
the transformation about five seconds after the order and one named summon
about ten seconds after it. Guse completed her ascent from `91.0533` to
`121.0533` yards; the rider spawned at that height and followed its flight
approach. The client displayed her transformed mount and lost the invisible
commander as a target. Her invisibility holder remained present well beyond
the spell's normal twenty-second duration, with expiry `-1`.

The attacker reached the Alliance base, became aggressive, and acquired
Stormpike defenders. It held exactly twenty-five yards from its victim while
casting, with no movement during those samples. A temporary receive trace on
the native player's owner recorded repeated Spell Go packets for all three
abilities, plus Fireball and Stun Bomb damage packets delivered to that client.
Fireball damage samples ranged from 773 to 1,027 and Stun Bomb from 672 to 776;
the victim's authoritative health fell. Fireball Volley cast successfully with
an empty hit list: its twenty-yard caster radius contained no enemies from
the twenty-five-yard stopping position. Screenshots also show the attacker as
the player's target and its current Stormpike victim.

Logout and reconnect retained the supplies, launch state, invisible commander,
and exactly one rider. The client dev command `.damage 200000` applied lethal
damage to the selected rider; its corpse-despawn rule removed its owner and
world presence without respawning it. The fleet remained launched with ninety
supplies. Leaving the match returned the player to Programmer Isle, removed
the match, and left zero entities in its instance. The final native server log
contained no errors or warnings.

Guse received native acceptance. The other five fleets, their faction approach
destinations, duplicate-order rules, and commander death and respawn received
automated coverage. An earlier idle-client attempt went AFK during the rescue
and exercised normal solo-match cleanup; the final run used periodic client
input while waiting. All helper-owned clients and retained servers were stopped.

Final validation: `mix test.all` passed all 8,711 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
`git diff --check` passed.

## Local evidence

- First native server: `/tmp/thistle-av-flight-native-server.log`.
- First isolated GPU client: `/home/pikdum/.cache/thistle-wow-playtest.Wv4wbR/`.
- Corrected native server: `/tmp/thistle-av-flight-native-fixed-server.log`.
- Corrected isolated GPU client: `/home/pikdum/.cache/thistle-wow-playtest.lX6xxJ/`.
- Final native server: `/tmp/thistle-av-flight-native-final-server.log`.
- Final isolated GPU client: `/home/pikdum/.cache/thistle-wow-playtest.uqgNLo/`.
- WoW's own hardware counters: `/tmp/thistle-av-flight-final-gpu.log`.
- Shared regressions: `/tmp/thistle-av-flight-fixes.log`.
- Launch timing: `/tmp/thistle-av-flight-final-launch.log`.
- Native combat packets: `/tmp/thistle-av-flight-final-combat-spells.log`.
- Combat poses: `/tmp/thistle-av-flight-combat-result.txt`.
- Reconnect, death, and cleanup: `/tmp/thistle-av-flight-final-reconnect.log`,
  `/tmp/thistle-av-flight-final-death.log`, and
  `/tmp/thistle-av-flight-final-cleanup.log`.
- Final gates: `/tmp/thistle-av-flight-final-tests.log`,
  `/tmp/thistle-av-flight-final-compile.log`, and
  `/tmp/thistle-av-flight-final-credo.log`.
- Final client captures include `air-launch-dialogue.png`,
  `air-transformation.png`, `rider-from-distance.png`, `reconnect.png`,
  `rider-despawn.png`, and `match-cleanup.png` under its `screenshots/` directory.
