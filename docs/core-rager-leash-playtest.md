# Core Rager leash acceptance

Tested on 2026-10-10 with the native 1.12.1 build-5875 client against a fresh
local server. References are the Core Rager combat events and Golemagg reset
handlers in `refs/vmangos/src/scripts/eastern_kingdoms/burning_steppes/molten_core/boss_golemagg.cpp`
and `WorldObject::GetDistance2d` in `refs/vmangos/src/game/Objects/Object.cpp`.

## Implemented behavior

A fighting Core Rager checks Golemagg after three seconds and every three
seconds thereafter. It resolves instance target slot 12 to Golemagg's seeded
DB GUID 56684 in its own world copy. If their horizontal surface distance is
strictly greater than 100 yards, it requests that boss's evade transition.
The distance subtracts both bounding radii and ignores vertical separation.
An idle rager, missing boss, dead boss, or boss in another copy does not trigger
the reset.

Golemagg's aggro marks encounter field 3 in progress. His spawn and evade
transitions clear that encounter and immediately restore both seeded ragers,
DB GUIDs 56685 and 56699, at their home positions with full health and fresh
incarnations. A completed encounter stays complete and does not restore adds.
The generated-data check confirms the boss and both rager identities in map
409 and that both rager spawns lie within the reference's 150-yard aggro roster
search. This acceptance covers the leash and reset lifecycle; the remaining
Golemagg's Trust periodic-aura behavior still needs parity work.

Forced respawn now leaves engagement and projects its cleanup before rebuilding
the mob. Previously, forcing a living attacker to respawn cleared its local
target without releasing the victim's attacker count. The new regression failed
with count 1 instead of 0 before this fix. It now verifies release, subsequent
re-engagement, and another clean release through the shared lifecycle.

## Native acceptance

Debugshaman (GUID 8, level 60, god mode) entered Blackrock Depths through its
real entrance and walked through the Molten Core portal in a raid, reaching
map 409, instance 2. Debugwarrior (GUID 1) supplied the raid partner through an
owned headless connection and stayed on Programmer Isle; he did not tank or
enter Molten Core.

The native player selected Golemagg and used `.damage 10000` to pull him.
The existing boundary damage API added the player to each rager's threat and
removed 1,000 health. Existing creature script commands stopped combat movement
and teleported the rager to controlled distances. These probes test the leash
without relying on natural kiting or a full raid clear. Unrelated nearby trash
was removed between the first reset and the accepted repeat.

| Unit | Seed DB GUID | Runtime GUID in copy 2 |
| --- | --- | --- |
| Golemagg | 56684 | 17379391163160597494 |
| Core Rager | 56685 | 17379391157858997235 |
| Core Rager | 56699 | 17379391157858997217 |

The first native trace collected 174 samples and 119 projected packets over
35 seconds. All three units were fighting the native player at 2.037 seconds.
The first rager remained inside the leash, finishing at a horizontal surface
distance of 99.105 yards. At 35.078 seconds the encounter remained in progress,
Golemagg had 816,088/826,088 health, both ragers had 79,925/80,925 health, and
all three retained the player as victim.

The following 25-second reset trace collected 125 samples and 74 packets:

- The first rager crossed to 101 yards at 10.348 seconds. All three units
  still fought the player immediately after that move.
- At 13.186 seconds, less than three seconds later, Golemagg was back at
  826,088 health and both ragers at 80,925. The encounter was not started,
  and all three had no victim, threat, or combat state.
- The native connection received Golemagg's restored health and both ragers'
  `create_object2` packets, with full health and cleared combat flags. The
  rager creation packets were recorded at 13.387 seconds.
- At 25.147 seconds, all three were visible at their seeded home positions,
  with no pending home return. The rager incarnations had changed from
  5180/5179 to 5558/5559; Golemagg retained incarnation 5111.
- The player's attacker count fell from seven to four. The remaining four
  were actual unrelated Lava Surger, Lava Reaver, Flameguard, and Firewalker
  attackers, which were cleared before the repeat.

The accepted repeat used the other rager, DB GUID 56699. Its trace collected
124 samples and 94 packets over 25 seconds:

- All three units were fighting the native player by 3.468 seconds, with
  the encounter in progress and attacker count three.
- The second rager reached exactly 101 yards at 13.427 seconds.
- At 15.462 seconds, the trace recorded that rager's leash request arriving
  at Golemagg, followed by Golemagg's evade message. Both ragers received
  forced-respawn messages at 15.463 seconds.
- Golemagg's full-health update and both ragers' full-health creation packets
  arrived on the native connection at that reset. By the next sample at
  15.465 seconds, the encounter was not started and attacker count was zero.
- The final sample at 25.029 seconds showed full health, no combat, no victim
  or threat, and all three visible at home. Rager incarnations changed from
  6381/6382 to 6403/6404.

A second raid used owned headless connections for Debugpaladin (GUID 2) and
Debugrogue (GUID 3). Debugpaladin entered Molten Core through normal instance
destination and worldport acknowledgement, reaching copy 3; Debugrogue stayed
on Programmer Isle. Copy 3's boss and ragers retained full health, idle combat
state, and incarnations 5688/5704/5905 throughout the repeat. None appeared in
the native player's visible roster, and the native connection received zero
packets for their runtime GUIDs.

The native client's target-health query showed 816,088/826,088 before the
reset and 826,088/826,088 afterward. Screenshots retain the selected boss,
ragers, Molten Core minimap, and raw health text. An earlier repeat had no
selected boss after a player teleport and is retained separately as
`thistle-rager-leash-idle-boss-native.json`; it is not the accepted boss repull.
The fresh gameplay server log contained no warnings or errors.

## Validation and evidence

The respawn, movement-inform, and architecture checks passed all 27 tests.
The leash, Molten Core scripts, generated spawn data, respawn, and architecture
checks passed all 49 tests. Coverage includes the first and repeated timer,
strict distance boundary, both bounding radii, vertical separation, correct
boss ownership, dead/missing/other-copy bosses, reset roster, and completed
encounter preservation.

Final validation: `mix test.all` passed all 8,843 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.

Respawn fix: `95439cbf`; leash and encounter lifecycle: `c29a46eb`.

GPU session: `/home/pikdum/.cache/thistle-wow-playtest.Ao7j3x`, unit
`thistle-wow-playtest.Ao7j3x.service`, invocation
`132870392a7e43d1b74d0312327b85e0`. WoW PID 177707 belonged to that service
cgroup and used amdgpu client 546. Its graphics counter increased from
1,085,959,180 to 35,964,320,202 ns. All three headless owners and their owned
connection processes were disconnected, the helper stopped its recorded
service invocation, and the retained server PTY exited afterward.

The session retains the server log, GPU ownership records, regression and
validation logs, screenshots, and the three accepted traces:

- `thistle-rager-leash-first-native.json`
- `thistle-rager-leash-reset-native.json`
- `thistle-rager-leash-repeat-native.json`
