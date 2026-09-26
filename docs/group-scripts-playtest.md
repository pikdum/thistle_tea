# Scripts shared by creature groups and player parties

Implemented against VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
with native build-5875 acceptance on September 26, 2026.

The [contextual XP playtest](contextual-experience-playtest.md) exposed an
unsupported `START_SCRIPT_ON_GROUP` command in Stratholme movement script
52124. That command starts generic script 5 on the whole patrol, assigning each
creature's current location as its home. Skipping it left the stored homes at
the original spawn locations.

## Shared behavior

Command 90 now selects one weighted generic script and runs those same resolved
steps on its source, creature leader and members, or player party/raid members.
Selection happens once in the pure interpreter. Nested scripts load recursively
through the existing cycle-guarded loader. Delays, conditions, target selection,
and target swaps retain the ordinary script behavior. A missed roll or non-unit
source honors the abort-on-failure flag.

The interpreter emits `StartGroupScript`; `EventSink.GroupScripts` performs the
membership lookup and delivery. Source delivery uses the explicit owner context.
Other recipients receive world-scoped script starts through their normal owners,
which reject messages from another world copy. Unloaded creatures and offline
players receive nothing. Present dead creatures remain eligible, matching the
reference's group enumeration. The source runs once even when ungrouped.

Creature membership comes from the existing world-copy group owner and follows
runtime joins, departures, and spawn reincarnation. Player membership comes from
the party cache and includes all raid subgroups. No gameplay database queries
or architecture-allowlist entries were added.

References: `Maps/ScriptCommands.cpp::ScriptCommand_StartScriptOnGroup`,
`Maps/ScriptCommands.h`, and the generic script loader in `ScriptMgr.cpp`.

## Native acceptance

A fresh local server and GPU client session
`/home/pikdum/.cache/thistle-wow-playtest.qRkR1H` used Debugwarrior, GUID 1,
at level 60 with god mode. The client entered Stratholme through area trigger
2214, creating map 329 / instance 1. Later developer teleports retained that
world copy. Tidewave probes only read state.

Before visiting the patrol, a 100-ms sampler watched leader spawn 52124 and
followers 52125–52128. It captured all five original home positions, followed
by all five changes when the leader reached waypoint 5. The first changed sample
was 42,803 ms after sampling began, including the wait for cell activation.

| Spawn | Original home X / Y | Updated home X / Y |
| --- | --- | --- |
| 52124 | 3643.180 / -3130.850 | 3653.070 / -3095.740 |
| 52125 | 3641.670 / -3131.310 | 3653.141 / -3097.739 |
| 52126 | 3640.150 / -3132.190 | 3651.383 / -3096.813 |
| 52127 | 3643.770 / -3133.260 | 3653.213 / -3099.738 |
| 52128 | 3642.420 / -3134.070 | 3649.695 / -3097.887 |

Each updated home matched that creature's current position when the command ran;
the followers were not assigned the leader's coordinates. Their stored home
positions remained distinct throughout the following combat check.

The player then approached the group. The client rendered both Skeletal
Berserkers and three Skeletal Guardians in combat, and all five owners reported
combat. Teleporting back to the entrance ended that engagement. The leader
returned exactly to its updated home, every creature retained its updated home,
and all five cleared threat, victim, and combat state at full health.

Followers did not all finish exactly at their stored homes. The reference's
`PatrolMovementGenerator::GetResetPosition` computes their evade destinations
relative to the leader's current position; `StartMove` does not begin another
leg once the leader's spline is finalized. Accordingly, the observed followers
settled 2.77–14.88 yards from their stored homes as the leader returned. A sampler
requiring exact equality for every member ran to its 40-second limit; it is not
reported as a successful exact-position check. Follow-up reads confirmed stable,
out-of-combat positions and empty threat tables. This change does not alter
formation movement rules.

Early observation teleports produced obstructed camera views. The combat
screenshot clearly shows the group. For the final view the player learned and
cast Stealth, then approached without restarting combat; `returned-observed.png`
shows the idle creatures. The authoritative final read still had zero victims,
empty threat tables, and unchanged stored homes for all five.

WoW process 1266764 used amdgpu, with its graphics counter increasing from
1,394,862,348 to 19,240,644,622 ns. The server emitted no error-level logs,
unsupported-command messages, or spell-validation failures. The owned client
service and retained server were stopped after acceptance.

Artifacts:

- `/tmp/thistle-group-script-home-transition.txt`: initial and updated homes.
- `/tmp/thistle-group-script-combat.txt`: active group combat.
- `/tmp/thistle-group-script-evade.txt`: bounded return sampler.
- `/tmp/thistle-group-script-final.txt`: final home, position, threat, and victim state.
- `/tmp/thistle-group-script-server.log`: server log.
- The session's `screenshots/` directory: `instance-entry`, `group-combat`, and
  `returned-observed`.

## Automated verification

Tests cover one shared weighted choice, nested-script delays and loading,
abort-on-failure, non-unit rejection, explicit source-owner delivery, leader and
member inclusion without duplicates, solo sources, offline members, raid
subgroups, world-copy rejection, unloaded creatures, membership changes, and
spawn reincarnation. A VMangos-tagged test loads the actual movement script and
its generic home-position script. Party/raid distribution and cross-instance
rejection are automated acceptance, not separate native multiplayer runs.

Final gates: `mix test.all` passed 6,331 tests;
`mix compile --warnings-as-errors` passed; `mix credo --strict` found no issues.
Logs are `/tmp/thistle-group-script-{tests,compile,credo}.log`.
