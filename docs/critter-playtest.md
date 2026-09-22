# Critter escape acceptance

Verified on 2026-09-22 with the native build-5875 client against commit `56e7c8b3`, following implementation commit `4601c811`.

Ordinary critters now flee after surviving damage or receiving a harmful non-damage spell. They do not acquire proximity targets, assist other creatures, select combat victims, or retaliate. Explicit AI assignments and owned companion behavior retain their existing selection. A surviving hit refreshes the 30-second combat escape deadline without restarting an already active 30-second flee. Escape clears threat, tap, and ordinary auras, restores health, and returns the creature home.

Spell fear and timed fleeing share terrain observations, paths bounded to 30 yards, and pauses between runs. Movement memory remains separate. Roots, stuns, confusion, and fleeing prevention suppress movement. Death clears escape state and queued movement through the shared death transition; respawn restores the normal spawn state.

The references are `refs/vmangos/src/game/AI/CritterAI.cpp`, `CritterAI.h`, `CreatureAISelector.cpp`, `Movement/FleeingMovementGenerator.cpp`, and `Objects/Creature.cpp:RemoveAurasAtReset`, at VMangos revision `8f4e60845`. The reset path preserves the reference's timed positive player buffs, explicit `not_removed_on_evade` spells, and the creature flag that retains positive auras.

## Native scenario

The final session was `/home/pikdum/.cache/thistle-wow-playtest.jzxKip`, with server log `/tmp/thistle-critter-final-server.log`. Debugwarlock was level 50, with equipment deliberately broken through the existing durability command to keep rank-1 damage small. The naturally spawned level-3 Sheep was entry `1933`, database spawn `80784`, runtime GUID `17379390994453183376`, near `-9895.36, -293.901, 34.4` in open-world Elwynn Forest. Its maximum health was 14.

| Client action | Authoritative result |
| --- | --- |
| Cast rank-1 Drain Soul (`1120`) | Initial application started fleeing at full health. One periodic tick dealt 11 damage, leaving 3/14 health. The channel ended before another damage tick. |
| Observe the surviving sheep | It alternated runs and pauses, never selected a victim, and retained 3 health. The damage tick moved the combat escape deadline about three seconds beyond the original flee deadline. |
| Let both deadlines expire | Fleeing stopped first, followed by a short stationary combat wait. At the refreshed escape deadline, health returned to 14, combat and flee flags cleared, and homeward movement began. |
| Cast rank-1 Curse of Weakness (`702`) | The sheep fled with 14/14 health. The curse remained during the escape and was removed on reset. The return sampler recorded arrival near the spawn followed by ordinary wandering. |
| Apply another curse, then cast Death Coil (`6789`) while it fled | Health reached zero. Combat, auras, escape memory, flee deadline, and pending navigation cleared. Metadata reported `alive?: false`; the corpse retained the same position in the later inspection. |

The player's health remained 1419/1419 throughout the accepted scenarios. Native spell packets were recorded for Drain Soul, Curse of Weakness, and Death Coil. The final server log contained no errors, crashes, or failed-operation messages.

Evidence retained locally:

- `surviving-drain.png`, `curse-flee.png`, and `death-confirmed.png` in the final session's `screenshots/` directory. The screenshots establish client actions and presentation; the sampled owner state establishes damage, timers, and cleanup.
- `/tmp/thistle-critter-final-damage.txt` and `/tmp/thistle-critter-final-damage-return.txt`, including the 14 → 3 → 14 health sequence and separate flee/combat deadlines.
- `/tmp/thistle-critter-final-curse.txt`, `/tmp/thistle-critter-final-curse-return.txt`, and `/tmp/thistle-critter-final-curse-recovered.txt`.
- `/tmp/thistle-critter-final-death-confirmed.txt` and `/tmp/thistle-critter-final-dead-state.txt`.

An earlier low-level setup was abandoned after a nearby Young Forest Bear killed the test character. A subsequent run exposed excessive straight-line fleeing; that led to the shared panic-movement correction in `56e7c8b3`. Neither earlier run substitutes for the final acceptance above. Death Coil was placed explicitly on the action bar before the final kill; the debug layout compacts unavailable abilities, so fixed key positions cannot be inferred from the layout list.

## Automated validation

The regression tests cover classification and explicit AI exclusions, surviving and lethal damage, harmful/helpful/resisted spells, periodic deadline refresh, independent movement and combat timers, navigation pauses and failures, roots, fleeing prevention, home recovery, tap cleanup, death, respawn, and aura reset exceptions. Existing fear, scripted fleeing, and architecture tests also pass.

Final gates, run with the isolated client and server stopped: `mix test.all` (4,705 passed), `mix compile --warnings-as-errors`, and `mix credo --strict` (zero issues). Natural corpse decay and respawn were covered by the existing lifecycle and new respawn regressions rather than waiting for a full native respawn cycle.
