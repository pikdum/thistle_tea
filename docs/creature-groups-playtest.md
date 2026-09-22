# Creature-group combat acceptance

Implemented in `945d88dd`. This increment supplies creature-group membership and combat lifecycle behavior. Formation following is still pending.

The boot loader caches `creature_groups`, validates that each leader and member exist on the same map, and indexes the definitions by map and spawn ID. Runtime membership belongs to a single boundary owner and is partitioned by `WorldRef`. Cell unloading and spawn reincarnation retain membership; deleting a world removes its group state. Temporary summons use runtime identities.

The pure group model follows VMangos group-wide option aggregation. A leader's self row does not contribute flags, and removing a follower does not erase options already accumulated by the group.

| Option | Behavior |
| --- | --- |
| `0x02` | An attack recruits living, present companions without an existing engagement. |
| `0x04` | Evade propagates to engaged companions through the normal engagement, aura, home-movement, and EventAI cleanup path. |
| `0x08` | Respawn requests revive dead, present companions. |
| `0x10`, `0x20` | Master or any-member evade can respawn dead companions. |
| `0x40`, `0x80` | Death notifies the original leader or other followers through EventAI event 32, with entry and leader-status filters. |

Script commands 78 and 79 join and leave groups through typed effects and an explicit entity-owner context. Leaving as the original leader disbands the group. Membership tokens invalidate queued commands after departure, disbanding, rejoining, or reincarnation. Forced respawn refreshes the owner's registration before spawn scripts run.

Conditions 57 and 58 collect facts through the existing scripted-event boundary and shared condition evaluator. The group-dead condition excludes its evaluating member and unloaded companions. A registered ungrouped creature has no group member match and satisfies group-dead; a missing or wrong-world source remains unknown.

References at VMangos revision `8f4e60845`:

- `CreatureGroups.h` and `CreatureGroups.cpp`: options, membership, assistance, evade, respawn, and death notification.
- `Objects/Creature.cpp`: `JoinCreatureGroup` and `LeaveCreatureGroup`.
- `Maps/ScriptCommands.cpp`: commands 78 and 79.
- `Conditions.cpp`: conditions 57 and 58.
- `AI/CreatureEventAI.cpp`: `GroupMemberJustDied`.

## Native client acceptance

Build-5875 session `/home/pikdum/.cache/thistle-wow-playtest.U6g1WO` ran against `945d88dd`. Debugwarlock, GUID 6, was level 60 with god mode enabled. Native commands supplied rank-1 Shadow Bolt and moved the character to the encounter. Tidewave probes were read-only.

Den Mother, entry 6788 and spawn 37523, and Thistle Cubs 37566 through 37569 loaded into the same flags-6 group. The initial owner snapshots showed all five alive, idle, and without victims. Their health values were 561, 220, 248, 220, and 248.

From `{6678, -438, 80}` on map 1, the client selected a Thistle Cub and cast `Shadow Bolt(Rank 1)`, spell 686. The server recorded the native cast against spawn 37568. A 100 ms sampler captured one transition: that cub lost 18 health, and all five creatures entered combat with victim GUID 6. Subsequent owner and metadata reads agreed on combat state and the combat unit flag. The client showed the bears converging and attacking. `den-mother-pull.png` and `walk2.png` record the visible encounter.

The client then used `.go xyz 6790 -438 100` to leave the encounter area. The reset sampler captured all five clearing combat and their victims together, 1,895 ms after sampling began. The injured cub returned from 202 to 220 health. Later reads showed cleared combat flags and metadata, Den Mother back at her spawn, and the cubs resuming idle movement. `outside-cave.png` shows the client out of combat. This reset used the client teleport command; it is not evidence of outrunning the group on foot.

The initial scouting coordinate `{6689, -449, 75}` placed the character below local ground. The character was repositioned onto the cave floor before the accepted cast. That initial screenshot is not combat evidence.

The Stormwind children at spawns 79815 through 79817 also completed their initial dock positioning. Their first waypoint script, 7981501, includes command 79 followed by the two positioning commands. The log no longer reported command 79 as unsupported. They begin ungrouped, so this visit verifies the initial script path, not removal from an active group or the later walking formation.

Artifacts:

- Server log: `/tmp/thistle-groups-server.log`.
- Initial and engaged owners: `/tmp/thistle-groups-before.txt`, `/tmp/thistle-groups-engaged.txt`.
- Cast transition: `/tmp/thistle-groups-proximity.txt`.
- Reset transition and final owners: `/tmp/thistle-groups-reset.txt`, `/tmp/thistle-groups-after-reset.txt`.
- Stormwind state: `/tmp/thistle-groups-stormwind.txt`.
- Screenshots: the session's `screenshots/` directory.

The retained server log contained no errors, owner crashes, or unsupported-command messages during the acceptance run. The helper-owned client, X server, and local BEAM server were stopped afterward.

## Automated verification and remaining work

`mix test.all` passed **4,752 tests**. `mix compile --warnings-as-errors` passed, and `mix credo --strict` reported zero issues across **1,852 files**. Tests cover option aggregation, coordinated combat/evade/respawn/death, same-world membership, instance isolation, stale owners and queued commands, forced respawn, cell unloading, disbanding, dynamic joins, script codecs and effect delivery, conditions, and actual Den Mother database rows. The architecture allowlist was unchanged.

Shared respawn, death notifications, instance isolation, and removal from an active group are automated acceptance here; they were not separately demonstrated in this native client run. Formation movement and temporary-leader waypoint continuation are covered in the subsequent [formation acceptance](creature-formations-playtest.md), and shared leash timing in the [combat leash acceptance](creature-leashes-playtest.md). `creature_groups_entry_limit` spawn composition remains separate work. This increment does not establish full creature-group or vanilla feature parity.
