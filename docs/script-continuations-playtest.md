# Script continuations and random ground movement

Validated on 2026-09-25 with the native build-5875 client. Source commits:

- `bbfdc3ab`: acknowledge script commands across entity and world owners.
- `09b2be22`: resolve scripted random ground destinations discovered during acceptance.

## Reference and behavior

VMangos `Maps/Map.cpp` retains script identity and original source/target GUIDs
when terminating scheduled work. `CreatureEventAI.cpp` executes independent
action groups and retries result-checked events when an action terminates.
`Maps/ScriptCommands.cpp` rejects duplicate map-event starts and mutations of
missing map events, honoring the command's abort flag.

The original entity owner now retains a typed continuation containing the
remaining steps and original due times. Forwarded commands and map-event
commands suspend that continuation until acknowledged. Receipts identify the
run, wait, and world; resumption reads current entity state and observations.
It does not restore an entity or blackboard snapshot.

Remote delivery monitors the caller and receiver and bounds all forwarding
hops by one five-second deadline. Expired requests cannot mutate a receiver.
Failure terminates the caller's tail when requested, including matching
scheduled invocations with the same script/source/target identity. EventAI
aggregates independent pending action groups before deciding whether to retry.
Combat resets reject stale EventAI continuations; world transfer, logout, and
corpse removal clear retained runs. Clearing preserves the receipt sequence.

`ScriptCommand_MoveTo` coordinate mode 3 uses the authored XYZ as the center
and O as the random radius. `WorldObject::GetRandomPoint` falls back to that
center when it cannot find a point. The follow-up fix supplies random ground
points through immutable navigation observations for EventAI, waypoint
scripts, explicit scripts, and resumed commands. It preserves pathfinding,
travel time, movement mode, and point callbacks without interpreting the
radius as final facing. All six imported mode-3 rows are covered: Horde
Defender, Horde Axe Thrower, and Mindless Undead scripts.

Automated coverage includes remote termination, failed conditions, missing or
wrong-world receivers, a swap back to the original owner, duplicate receipts,
recipient/caller death, absolute timing, current-state resumption, matching
script cancellation, world transfers, EventAI resets and retry aggregation,
competing map-event starts, and independent instance event keys. The random
movement checks include real Barrens map geometry and imported VMangos rows;
these remain separately tagged.

## Native Counterattack startup

Both runs used Debugshaman, GUID 8, level 50. Quest 4021 was added through
`.addquest 4021`; no creature state was changed for acceptance. The client
visited Regthar Deathgate at `-307 -1970 96.6` on open map 1, right-clicked his
model, and selected **Where is Warlord Krom'zar?** in the real gossip window.
Regthar's DB spawn is 13979, runtime GUID `17379391018880743067`.

The initial run on `bbfdc3ab` proved the acknowledgement chain and exposed
skipped coordinate-mode-3 commands in defender scripts 945704 and 945804.
That server and client were stopped before the movement fix. Initial evidence
uses `/tmp/thistle-script-continuations-` and client session
`/home/pikdum/.cache/thistle-wow-playtest.RhJDFq`.

The fresh run on `09b2be22` recorded these UTC transitions:

| Time | Observation |
| --- | --- |
| 13:43:07.931 | No scripted map events, no retained Regthar runs, no event summons. |
| 13:43:08.930 | Actual `CMSG_GOSSIP_SELECT_OPTION`, option 0, on Regthar. |
| 13:43:08.947 | First map-event command acknowledged successfully. |
| 13:43:08.950 | Client receives Regthar's warning to look west. |
| 13:43:10.122 | Events 4021, 4022, and 4023 exist; continuation waits for its original two-second step. |
| 13:43:12.126 | Regthar has no retained runs; event 4021 has 35 registered targets. |

The final snapshot counted 9 Horde Defenders, 3 Horde Axe Throwers,
7 Kolkar Stormseers, and 16 Kolkar Invaders. The client displayed the summoned
defenders and their subsequent movement. The gossip option disappeared while
the event was active. The client moved to `-300 -1905 93` within the same
world to observe the field.

The player's owner received these ordinary movement splines for Horde
Defenders, with random endpoints inside the corresponding five-yard regions:

| UTC time | Creature GUID | Start | Destination | Duration |
| --- | --- | --- | --- | --- |
| 13:43:12.993 | 17379391120689070503 | -245.677, -1935.890, 92.728 | -217.934, -1934.605, 93.908 | 3474 ms |
| 13:43:13.117 | 17379391120689070505 | -245.365, -1925.840, 92.453 | -219.513, -1928.469, 93.337 | 3250 ms |
| 13:43:14.241 | 17379391120689070497 | -285.394, -1906.730, 91.750 | -287.005, -1872.999, 92.764 | 4223 ms |

The first two later movement packets start at those exact destinations,
showing arrival before subsequent combat movement. The third move was
interrupted by combat and is not counted as completed. Owner inspection at
13:43:42 retained the current world and movement state, with empty script
continuations and navigation-intent queues on the observed defenders.

Evidence:

- `/tmp/thistle-script-random-sample.log`: client input, map-event transitions,
  summon counts, acknowledgements, dialogue, and movement packets.
- `/tmp/thistle-script-random-owners.log`: authoritative defender states.
- `/tmp/thistle-script-random-native-server.log`: no error-level messages,
  crashes, unsupported commands, or cast-validation warnings.
- `/home/pikdum/.cache/thistle-wow-playtest.c0bSqc/screenshots/`:
  `regthar-gossip.png`, `counterattack-start.png`, `counterattack-defenders.png`,
  and `counterattack-movement.png`.

## Validation, cleanup, and scope

The final source passed `mix test.all` with **6,087 tests**,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`. Logs use the
`/tmp/thistle-script-random-` prefix with `all.log`, `compile.log`,
`credo.log`, and `format.log` suffixes. An earlier continuation-suite run hit
an existing login timeout while verification jobs overlapped; its standalone
rerun passed all 6,081 tests before the movement follow-up.

The client returned to Programmer Isle with combat false and no retained
player script runs, then logged out. `/tmp/thistle-script-random-return.log`
and `-cleanup.log` record an absent player owner and empty player lists in
both open worlds after logout. Both helper-owned client services were stopped
and both retained server PTYs exited. No push was performed.

Both native clients used the GPU renderer. In the final session WoW PID
863546's own graphics counter on AMDGPU `0000:0c:00.0` advanced from
862,823,650 to 10,833,298,600 ns. Samples are
`/tmp/thistle-script-random-gpu-before.log` and `-gpu-after.log`.

Acceptance covers script continuation control, Counterattack startup, and
random ground movement. It does not establish full quest completion, flying
random-point behavior, or vanilla parity. Deferred player/triggered casts
and summons still have their existing effect-specific completion semantics;
this change does not make every script command result-aware. Duplicate-start
failure and instance isolation are established by automated owner tests;
the native run exercises the successful content path.
