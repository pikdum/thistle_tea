# Creature formations acceptance

Formation movement extends the [creature-group combat system](creature-groups-playtest.md). The reference is `refs/vmangos` revision `8f4e60845`, principally `CreatureGroups.cpp`, `PatrolMovementGenerator`, and `WaypointMovementGenerator`.

## Implemented behavior

The group owner publishes immutable formation membership by world copy. Behavior-tree nodes follow the leader's current spline endpoint with the configured distance and angle. Navigation resolves the actual follower path before choosing its speed to match the leader's remaining travel time, capped at 130% of run speed. Followers finish their current leg before choosing another; stopped or fighting leaders do not start new formation movement. Followers beyond 100 yards use the existing creature teleport effect.

A formation leader's death promotes the first living, present follower in runtime GUID order. A temporary leader continues the original route at its last reached waypoint after the reference's initial one-second delay. The original leader reclaims leadership on respawn. Evading followers return relative to the current leader, while leaders return to the last reached waypoint. Shared respawn places dead formation members relative to the original leader. Dynamic removal clears membership and restores personal patrol data.

Cell activation expands static formations so members whose database spawns lie in distant cells can join the patrol. Spawn pools retain their normal selection and observer-sensitive unloading rules. A separate fix gives return-home movement explicit state: reaching a waypoint at the spawn coordinates no longer incorrectly invokes the evade-home path and stalls route advancement.

## Native client run

The isolated build-5875 client session is `/home/pikdum/.cache/thistle-wow-playtest.88h7kX`. The character is the level-60 human `Debugwarlock`, GUID 6, with `.tgm` enabled. Movement and casts used client commands; Tidewave probes only read existing state.

The Ironforge mountaineer group has leader 4481 and followers 4479 and 4480. Both followers' database spawns are more than 400 yards from the leader. Visiting the leader's patrol loaded all three. The followers caught up, then walked at their configured two-yard offsets. One recorded leg had 4,385 ms remaining for the leader and one follower, and 4,384 ms for the other. Their resolved endpoints differed by the configured angles. The first camera angle was obstructed; a later scouting teleport placed the player below local ground and was abandoned. These screenshots do not establish a clear visual view of the mountaineers.

Fozruk's group has original leader 14514, Sleeby 14515, Znort 14516, and Feeboz 14517. The followers' database spawns are about 500 yards away. All four loaded and followed the patrol. A recorded leg had exactly 9,556 ms remaining for all four, including Znort's longer, multi-segment path.

The client cast Death Touch, spell 5, on Fozruk. His authoritative health became zero, Sleeby became leader, and the original group's last reached waypoint was 7. After combat, Sleeby returned toward waypoint 7; later reads showed all survivors out of combat and advancing through points 9 and 12. The inherited route advanced while both followers remained attached to Sleeby and finished their movement legs within one millisecond of his. `sleeby-patrol.png` records the client view of the continuing patrol and Sleeby's target frame.

A second native Death Touch killed Sleeby. Znort then became leader, continued the same route through point 16 toward 17, and Feeboz followed him. Fozruk and Sleeby remained dead with their original respawn timers pending.

The test waited for Fozruk's normal 400-second timer. The last pre-respawn read had 25,584 ms left on Fozruk and 132,224 ms on Sleeby. After Fozruk's timer fired, both were alive: Fozruk's incarnation changed from 287 to 734 and Sleeby's from 288 to 735. Sleeby's own timer was therefore bypassed by shared respawn. Fozruk was leader again, all three members were followers, all respawn timers were clear, and the original patrol had resumed at waypoint 1. Znort and Feeboz retained incarnations 290 and 291. All four were now together near the original route, rather than leaving the survivors at their distant temporary patrol location. `fozruk-restored.png` shows Fozruk and a follower back in the client.

Artifacts:

- Server log: `/tmp/thistle-formations-server.log`.
- Mountaineer owners and movement: `/tmp/thistle-formations-mountaineers-second.json` and `-third.json`.
- Original Fozruk formation: `/tmp/thistle-formations-fozruk-first.json`.
- First promotion and evade: `/tmp/thistle-formations-fozruk-after-kill.json`.
- Resumed patrol: `/tmp/thistle-formations-fozruk-resumed.json` and `/tmp/thistle-formations-sleeby-patrol.json`.
- Second promotion and pending timers: `/tmp/thistle-formations-respawn-pending.json`.
- Before and after normal respawn: `/tmp/thistle-formations-respawn-pending3.json` and `/tmp/thistle-formations-restored.json`.
- Final authoritative movement: `/tmp/thistle-formations-final-owners.json`.
- Screenshots: the session's `screenshots/` directory.

The initial high-volume lifecycle sampler exceeded Tidewave's output limit. A long-running respawn sampler hit the HTTP client's timeout; the bounded reads immediately before and after respawn supplied the accepted evidence. No sub-second promotion or respawn timing is claimed from those failed samplers.

The final owner read showed all four out of combat, with Fozruk leading toward waypoint 7 and exactly 7,818 ms remaining on every movement leg. `fozruk-restored-formation.png` shows the restored leader walking away in the client. The server log contained no errors, owner crashes, or unsupported-command messages. The helper-owned client, X server, and BEAM server were stopped afterward.

## Automated verification and limits

`mix test.all` passed **4,767 tests**. `mix compile --warnings-as-errors` passed. `mix credo --strict` reported zero issues across **1,859 files**. Coverage includes actual-path speed calculation and caps, stopped/combat leaders, distant recovery, route ownership, promotion and original-leader restoration, disbanding, same-world projections, original-leader respawn positions, distant activation and unloading, and the architecture dependency ratchet. The allowlist was unchanged.

Shared leash timing is covered by the subsequent [combat leash acceptance](creature-leashes-playtest.md). `creature_groups_entry_limit` composition remains separate work. Navigation uses the existing Namigator path resolution; exact VMangos walk-hit endpoint clipping is not independently established by this run. This increment does not establish full creature-group or vanilla feature parity.
