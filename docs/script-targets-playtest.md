# Script source and target routing acceptance

Validated on 2026-09-25 with the native build-5875 client. Implementation:
`0047f799`; the persistent-emote cleanup found during acceptance is fixed in
`9144ee50`. No runtime code was edited while either acceptance server was live.

## Reference and boundaries

`refs/vmangos/src/game/Maps/Map.cpp`, `FindScriptFinalTargets`, applies the
initial source/target swap, target selection, final swap, and self-target flag
in that order. Conditions use the resulting pair. `GetTargetByType` in
`ScriptMgr.cpp` specifies which selectors can use the original target when
the initial source is absent.

The pure interpreter now forwards an initially swapped step to its receiving
owner before selection. Final swaps resolve the selected owner and forward a
provided-target step. Creatures, players, and game objects can receive these
steps. Forwarding clears the elapsed delay; the original owner schedules
later steps. Conditions use the selected target's immutable facts, batched at
the environment boundary. Receivers reject forwarded and delayed work from
another world or instance.

The live-owner regression also exposed a facing bug: target-facing packets
were sent without changing the authoritative orientation. The interpreter
now updates that orientation from its perception snapshot.

Automated coverage includes the flag combinations, selection from the swapped
source's victim, self targeting after selection, absent targets, delayed
forwarding, selected-target conditions, player and game-object delivery, world
isolation, facing state, and observer emote packets. Imported-data tests cover
the reveler conversation and Estelle's player-cast step. These cases do not
establish all script-command behavior or cancellation of a caller's remaining
steps by a separately forwarded termination command.

## New Year reveler conversation

The earlier world-event run logged unsupported initial swaps in generic script
1569406. That script is a conversation between revelers. Its EventAI parent
selects another reveler within 30 yards and swaps the final source. The nested
script turns both participants toward each other and plays the initially
swapped talk emote after one second.

On `0047f799`, Debugmage (GUID 5, level 50) started event 34 through the existing
`.debug events start 34` command, then visited
`-9075 496 76.3` on open map 0. The native client displayed the revelers turning
and gesturing. A bounded receive trace on the player's owner captured:

| UTC time | Client packet |
| --- | --- |
| 11:55:17.480 | Creature 17379391225324578381 faces 17379391225324578379 |
| 11:55:17.484 | Creature 17379391225324578379 faces 17379391225324578381 |
| 11:55:18.492 | Creature 17379391225324578379 plays emote 1 |

The owners retained these poses in the same open world, with no queued effects:

| Creature DB GUID | Position and orientation |
| --- | --- |
| 206411 | `{-9071.54, 500.753, 75.906, -2.042898944552446}` |
| 206413 | `{-9072.43, 499.01, 76.2405, 1.098693709037347}` |

Evidence: `/tmp/thistle-script-targets-reveler-talk.log`,
`/tmp/thistle-script-targets-reveler-final-poses.log`, and
`/home/pikdum/.cache/thistle-wow-playtest.gwgNJF/screenshots/reveler-talk.png`.
The earlier broad trace was truncated by the evaluator's default inspection
limit; the focused trace above contains the complete relevant exchange.

## Player casting and emote cleanup

Estelle Gendry's gossip script 161 removes gossip temporarily, speaks, moves
to the crates, crafts, stops crafting, returns home, and makes the player cast
9949 on themselves. This uses initial swap plus self targeting. The spell
creates item 5060, Thieves' Tools.

The first native run used Debugmage, quest 1999 added through `.addquest`, and
debug reputation changes to open Estelle's gossip. Clicking the actual gossip
option produced a forwarded step from NPC 17379391072181976360 at
12:00:24.085 UTC, an owner-local cast targeting player 5 at .091, and a spell-go
packet with caster 5 and hit list `[5]` at .110. The client displayed the spell
and item-creation message. Inventory changed from zero to one tool and retained
it after logout/login.

This run revealed that Estelle remained in crafting emote 69 after finishing,
with combat false and no pending effects. `ScriptStep.emote_ids/1` discarded
zero. VMangos retains the first emote even when it is zero, and reads later
alternatives only until the first zero. The follow-up implements that rule.
The regression checks the live owner's `69 -> 0` transition and the zero field
in a fresh observer update.

Final acceptance on `9144ee50` used a fresh server and Debugshaman (GUID 8,
level 50, Orc), with ordinary Horde interaction. Setup was `.addquest 1999`
and `.go xyz 1389 121 -62.2 0`. No reputation changes were needed.

After clicking the native gossip option:

- The client displayed both dialogue lines and `You create: [Thieves' Tools]`.
- The player owned exactly one tool, had no pending effects, and remained in
  open map 0.
- Estelle restored gossip flag 1, cleared her emote to 0, and returned to
  `{1389.8299560546875, 122.75499725341797, -62.45298767089844, 6.24828}`.
- Reopening gossip showed no tool-request option while the item was owned.
- Logout removed the player owner and saved one tool. Reentry created owner
  `#PID<0.4252.0>` with one tool, no active cast, and no pending effects.
  Estelle still had emote 0, and the native gossip option remained absent.

The long transition sampler exceeded the evaluator's timeout; it provides no
timing evidence. Final acceptance uses the completed-sequence owner reads,
client frames, reconnect reads, and automated transition/packet regression.

Final evidence:

- `/tmp/thistle-script-emote-before.log`, `-after.log`, `-logout.log`,
  `-reconnect.log`, and `-cleanup.log` under the same prefix.
- `/home/pikdum/.cache/thistle-wow-playtest.uaAhqA/screenshots/estelle-gossip.png`,
  `estelle-complete.png`, `estelle-option-consumed.png`, and
  `estelle-reconnected.png`.
- `/tmp/thistle-script-emote-native-server.log`: no error-level entries,
  unsupported-command messages, crashes, or spell-validation failures.

## Validation and cleanup

Final source passed `mix test.all` (6,041 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`. Logs use the
`/tmp/thistle-script-emote-` prefix with `all.log`, `compile.log`, `credo.log`,
and `format.log` suffixes.

Both clients used the GPU renderer. WoW's own AMDGPU graphics counter on
`0000:0c:00.0` advanced from 949,630,163 to 24,096,766,684 ns in the first
session, and from 855,416,509 to 11,587,015,844 ns in the final session. Samples
are `/tmp/thistle-script-targets-gpu-{before,after}.log` and
`/tmp/thistle-script-emote-gpu-{before,after}.log`.

Both helper-owned client services were stopped, and both retained server PTYs
exited. Final cleanup reported no player owner and empty player lists in open
map 0 and Programmer Isle. Logs and screenshots are retained in the exact
session directories above. No push was performed. This is scoped script
acceptance, not whole-holiday or vanilla parity acceptance.
