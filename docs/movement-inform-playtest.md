# Scripted movement completion

## Implementation

EventAI event 29 now matches the motion type and point ID and uses parameters
3 and 4 for repeat timers. Phase, chance, condition, one-shot, and casting gates
remain in the shared EventAI interpreter.

Absolute `MOVE_TO` scripts retain point identity, walk/run/fly mode, direct or
pathfound movement, travel time, and final facing. Only moves carrying the
point-generator flag produce point motion type 9. Completion is attached to
the active spline and delivered through a typed effect and explicit owner
context. It fires once on arrival, survives speed retiming, and is discarded
when an unfinished move is stopped, teleported, or replaced. Failed paths and
paths ending short of the destination do not report arrival. Navigation checks
allow Namigator's floor refinement without accepting another floor.

Waypoint routes produce motion type 2 with the original point ID. An interrupted
or unsuccessful waypoint move cannot advance its route or run arrival scripts.
Idle patrols wait for active scripted point movement, and combat positioning
respects scripts that disable combat movement. Arrival deadlines wake idle
owners. Observers arriving during a spline receive its final-facing option.

Script command 33, Enter Evade, now requests the existing mob reset transition.
That transition owns threat, target, combat, health restoration, home movement,
and leave-combat/evade callbacks. Dead creatures cannot be revived by the command.
Creature sources take precedence; scripts with another source can select a
creature target, matching VMangos.

Relative, distance-from-target, and random-point `MOVE_TO` coordinate modes
remain outside this change, as do cyclic and falling movement generators.

## Reference behavior

- `refs/vmangos/src/game/AI/CreatureEventAI.cpp`: `MovementInform` and
  `EVENT_T_MOVEMENT_INFORM` repeat parameters.
- `refs/vmangos/src/game/Movement/PointMovementGenerator.cpp`: completion versus
  interruption, point identity, and facing.
- `refs/vmangos/src/game/Movement/WaypointMovementGenerator.cpp`: original
  waypoint IDs and one arrival per waypoint.
- `refs/vmangos/src/game/Maps/ScriptCommands.cpp`: `MOVE_TO` and Enter Evade.
- `refs/vmangos/src/game/Maps/ScriptCommands.h`: movement flags and data fields.

## Native acceptance and discovered cleanup bug

The first run used commit `5a79cad5`, debug mage 5, a fresh server, and the GPU
client session `/home/pikdum/.cache/thistle-wow-playtest.WVYpcE`.
WoW PID 2438634 used `amdgpu` device `0000:0c:00.0`; its graphics counter advanced
from 818,046,948 to 1,780,375,854 ns.

The client entered Shadowfang Keep through area trigger 145 from map 0 at
`{-229.49, 1576.35, 78.89}`. The authoritative destination was map 33, instance 1.
Deathstalker Vincent, entry 4444 / DB spawn 16260, had runtime GUID
`17379391036593275442` in that copy.

The client cast Fireball 10151 after targeting Vincent. The packet log confirms
that spell and GUID. A read-only 50 ms sampler recorded:

1. 531 HP, phase 0, at `{-217.991, 2150.77, 81.1327}`.
2. 5 HP and standing, then phase 1 with point motion 9 / ID 1 active.
3. Arrival at `{-219.311, 2147.68, 80.9921}`, facing `3.63082`, stand state 7,
   with no active movement options. The callback followed the start of the
   retreat by approximately 0.8 seconds.

The screenshots show the living NPC before the spell and the play-dead pose
afterward, including his scripted "Arrgh!" text. Health remained 5; this was an
arrival animation, not a creature death.

The subsequent one-minute combat timer exposed unsupported script command 33.
After the timer had fired and disabled its event, Vincent still had target 5,
threat `%{5 => 780.0}`, and combat enabled. This is the regression fixed by the
shared Enter Evade command above. The server and client were stopped before
changing or recompiling source.

A second fresh run on `ba2ef6c1` reproduced arrival and exposed an independent
deadline bug. After the Fireball damage-over-time aura expired, combat movement
remained disabled with `next_chase_at: 0`. `Blackboard.ready_for?/3` treated that
sentinel as ready, but `delay_until/3` subtracted the negative monotonic clock
from it. The owner consequently scheduled a 576,460,474,974 ms wait, leaving
EventAI's one-minute timer overdue. `/tmp/thistle-vincent-deadline-bug.txt`
records the stalled owner; this run used session
`/home/pikdum/.cache/thistle-wow-playtest.Z36eUb` and
`/tmp/thistle-movement-final-server.log`.

Both deadline helpers now agree that zero and nil mean ready. Negative-clock
regressions failed with the old code and passed with the correction. The shared
scheduling rule now works for every consumer of blackboard deadlines.

Initial evidence:

- `/tmp/thistle-movement-server.log`
- `/tmp/thistle-vincent-arrival.txt`
- `/tmp/thistle-vincent-missing-evade.txt`
- Session screenshots `entrance.png`, `vincent-before.png`, and `vincent-after.png`.

## Automated coverage

Regressions cover exact event matching, cooldowns, dead recipients, one-shot
completion, zero-distance points, interrupted/replaced/teleported movement,
retiming, partial paths and floor refinement, waypoint advancement, idle-owner
wakes, observer facing packets, explicit owner delivery, and scripted evade
cleanup. A separately tagged database test checks Vincent's actual movement,
arrival, and one-minute cleanup rows.

Final source validation on `f56edf2e` passed:

- `mix test.all`: 5,328 tests passed.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`, `git diff --check`, and commit hooks.

Logs: `/tmp/thistle-deadline-tests-final.log` and
`/tmp/thistle-deadline-credo.log`. The negative-clock red/green checks are in
`/tmp/thistle-deadline-red.log` and `/tmp/thistle-deadline-green.log`.
The playtest clients and native server were stopped during these gates.
Subsequent edits affect only this evidence note.

## Final native acceptance

The final run used `f56edf2e`, a fresh server, debug mage 5, and session
`/home/pikdum/.cache/thistle-wow-playtest.r2H4kY`. WoW PID 2449020 used `amdgpu`
device `0000:0c:00.0`; its graphics counter advanced from 775,429,171 to
9,050,084,287 ns. The client again entered through area trigger 145 into map 33,
instance 1. Vincent's runtime GUID was `17379391036593275453`.

Client Fireball 10151 produced the same retreat and arrival pose. Two short
read-only samplers captured the actual transitions without changing owner state:

| Transition | Monotonic time (ms) | Authoritative state |
| --- | --- | --- |
| Combat and retreat | -576460628067 | 5/531 HP, phase 1, target 5, point motion 9 / ID 1 |
| Arrival | -576460627199 | Stand state 7, facing 3.63082, no active spline |
| One-minute evade | -576460567963 | 531/531 HP, combat false, target 0, empty threat, stand state 7 |

After damage-over-time expiration, the AI still had ordinary sub-second wakes.
The evade transition occurred about 60.1 seconds after combat began. The client
showed Vincent lying down with a restored full health bar. A later owner read
confirmed the reset remained stable, with phase 1 and no pending movement.

The player returned to Programmer Isle and issued `.instance reset`. The client
reported map 33 / instance 1 reset with no occupied copies. Vincent's process,
world position, metadata, and spawn mapping were all absent afterward. No owner,
movement, script, or spell validation errors appeared in the accepted server log.

Final evidence:

- `/tmp/thistle-movement-accepted-server.log`
- `/tmp/thistle-vincent-accepted-arrival.txt`
- `/tmp/thistle-vincent-accepted-cleanup.txt`
- `/tmp/thistle-vincent-accepted-removal.txt`
- Session screenshots `entrance.png`, `arrival.png`, `reset-complete.png`,
  `outside.png`, and `instance-reset.png`.

All three helper-owned clients and their retained servers were stopped. No
source changed after the final gates and accepted native run.
