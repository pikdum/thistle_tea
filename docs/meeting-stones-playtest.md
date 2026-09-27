# Meeting Stone matchmaking acceptance

Vanilla Meeting Stones now queue solo players and incomplete parties for a
dungeon. Matching separates factions and destinations, assigns one tank,
one healer, and three damage slots using vanilla class priorities, and
fills existing parties before forming new ones. A compatible cohort needs
at least five available solo applicants before initial party creation.
Applicants waiting 30 minutes receive priority; queued parties receive
five-minute progress notices.

The pure `MeetingStone` core owns tickets and matching decisions. The
existing party process serializes queue changes with normal membership
changes. Automatic joins use `Party.matchmake/4`, existing party projection,
and the instance membership hook. Queue matching reads cached characters
and live presence. It performs no gameplay database queries.

Players can queue by interacting with a nearby visible stone or through
existing innkeeper gossip scripts. Script command 36 emits a typed queue
effect with an explicit player recipient and source world. Join, leave,
and info messages are registered in the actual packet dispatcher; queue,
failure, member-added, progress, and completion replies use packet structs.
Party queueing requires the leader of a nonraid, incomplete group. Offline
solo tickets retain their original wait time and cannot match until the
player returns. Pending invitations also exclude automatic joining.

Voluntary departures continue the remaining party's search. Kicking a
member withdraws the party and requeues the removed player. Leader departure,
disbanding, raid conversion, and completion clear the appropriate tickets;
explicit leadership transfer preserves the queue under the new leader.

This implements default class-based vanilla matching. VMangos's optional
talent-based matching mode is not included. No developer commands, seed
characters, durable persistence, or architecture allowlist entries were added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/LFG/LFGHandler.cpp`, `LFGMgr.cpp`, and `LFGQueue.cpp`,
`src/game/Group/Group.cpp`, `src/game/Maps/ScriptCommands.cpp`, and
`src/game/Objects/GameObjectDefines.h`. Packet layouts also follow
`refs/wow_messages/wow_message_parser/wowm/world/meetingstone/`.

## Native acceptance

Five simultaneous isolated build-5875 GPU clients ran against implementation
commit `c2cac9f3`. Native `.character level 25` commands set their levels.
All gameplay changes used native client input; Tidewave probes were read-only.

| Character | GUID | Class | Matched role |
| --- | --- | --- | --- |
| Debugpriest | 4 | Priest | Healer |
| Debugbuyer | 10 | Warrior | Tank |
| Debugbidder | 11 | Mage | Damage |
| Debugrogue | 3 | Rogue | Damage |
| Debugwarlock | 6 | Warlock | Damage |

The Deadmines Meeting Stone uses template 178834, spawn 32320, area 1581,
and live GUID `17370386763104681536`. The clients stood on map 0 at
`{-11086, 1563, 49.44}` and right-clicked its world model. Its tooltip showed
The Deadmines and levels 17–26. This acceptance did not enter an instance.

- The priest queued alone and saw the native queue message and minimap icon.
  Logout removed the player owner and position while retaining the ticket.
  Reconnect created a new owner and restored queue status with the original
  `queued_at` value, `-576460447101`. See `solo-queued`, `offline-queued`,
  and `restored` probes and `queue-restored.png`.
- Four queued players did not form a party. The fifth stone interaction
  produced group 1, led by the priest, with members `[4, 10, 11, 3, 6]`.
  All five clients displayed four party frames and the native completion
  message. Both queue maps were empty. See `four-queued.txt`, `matched.txt`,
  and each client's `matched.png`.
- Clicking with a full group showed the native full-group rejection.
  After the warlock left, the priest queued the remaining four members.
  Kicking the rogue withdrew the party and retained the rogue's solo ticket.
  The leader saw the removal message; the rogue saw the new-party search
  message. The buyer's subsequent interaction showed the nonleader error.
  See `party-queued.txt`, `kicked.txt`, `kicked-party.png`, `kicked-solo.png`,
  and `nonleader-confirmed.png`.
- Requeueing the three-player party automatically restored the rogue.
  The buyer then left voluntarily; the leader saw the renewed-search message.
  The warlock joined through the stone, leaving the party waiting for a tank.
  The buyer's next interaction filled that slot, completed the group, and
  cleared the queue again. See `refilled.txt`, `awaiting-tank.txt`,
  `rematched.txt`, and `voluntary-departure.png`.
- Native `CancelMeetingStoneRequest()` cleared an incomplete party's queue
  while preserving its roster. Requeueing and then having the leader leave
  cleared the queue and promoted the remaining party's next leader. See
  `cancelled.txt`, `leader-departed.txt`, `queue-cancelled.png`, and
  `leader-departed.png`.
- A sixth isolated client session repeated the warlock's innkeeper path at
  Innkeeper Heather, entry 8931, in Sentinel Hill. Clicking **Tell me about
  dungeons I could explore**, **Deadmines**, and **Join a group going to this
  dungeon** executed gossip script 2001 and queued GUID 6 for area 1581.
  The client displayed the queue message and icon. Native cancellation
  removed both. See `fresh-gossip.png`, `fresh-dungeons.png`,
  `fresh-deadmines.png`, `innkeeper-queued.png`, `innkeeper-cancelled.png`,
  and the corresponding probes.

The initial innkeeper attempt used an old `npccache.wdb` containing an empty
female text for greeting 820. The client parsed the choices but kept the
gossip window hidden. A private reflink copy with a fresh WDB cache displayed
the current greeting and completed the entire click sequence without server
changes. The original automation client directory was preserved.

Native coverage establishes complete and partial matching, recipient UI,
solo reconnect, queue cancellation, kicks, voluntary and leader departure,
and scripted innkeeper entry. Faction/destination partitioning, alternate
class priorities, long-wait priority, progress timing, pending invitations,
offline leaders, raid conversion, explicit leadership transfer, and invalid
stone interactions are covered by automated tests.

The live log contains no errors or Meeting Stone warnings. Existing
unsupported account-data and GM-ticket requests were the only warnings.

## Automated checks

- `mix test.all`: 6,827 passed in 74.4 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,475 source files.
- Focused queue, party, boundary, packet, script, and VMangos checks: 65 passed.
- Formatting and pre-commit checks passed.

The 21 added tests cover pure queue transitions, matching rules, actual
party-owner integration, explicit effect delivery, native packet dispatch,
and the shared Deadmines stone/innkeeper destination. The VMangos lookup
test is tagged `:vmangos_db`; default tests use synthetic data.

Build and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence and cleanup

Client directories use `/home/pikdum/.cache/thistle-wow-playtest.` plus
the suffix below. Screenshots are in each directory's `screenshots/` folder.
GPU counters are nanoseconds from each WoW process's AMD DRM client;
duplicate descriptors were counted once.

| Session | Character | WoW PID | DRM client | Graphics start | Graphics end |
| --- | --- | --- | --- | --- | --- |
| `9plxvv` | Priest | 1924849 | 5798 | 7,261,172,206 | 36,936,578,572 |
| `VxEFJ7` | Buyer | 1926431 | 5826 | 6,179,182,141 | 38,840,293,310 |
| `ua1vgs` | Bidder | 1927490 | 5854 | 4,272,966,938 | 34,944,451,935 |
| `7f6c0J` | Rogue | 1928639 | 5882 | 3,303,580,905 | 37,889,620,630 |
| `5p7wKL` | Warlock | 1930052 | 5910 | 1,790,080,387 | 37,314,417,493 |
| `ewlypw` | Warlock, fresh cache | 1943835 | 5938 | 3,666,121,569 | 4,721,646,735 |

Probe, gate, server, ownership, and GPU evidence uses
`/tmp/thistle-meeting-stone-`. The fresh client copy is retained at
`/storage/games/Thistle-meeting-stone-playtest.6tEm9Q`; its previous cache is
retained as `WDB.pre-existing`. Earlier `innkeeper-*` screenshots in `5p7wKL`
record the stale-cache diagnosis, not successful innkeeper acceptance.

The helper stopped each recorded service invocation:

- `9plxvv`: `663f34b13dc441cebebf1c629359a1f9`.
- `VxEFJ7`: `f0407ede48684cb19d72713da64083d6`.
- `ua1vgs`: `834b75f322a540fa889c8d1ef5c3a733`.
- `7f6c0J`: `3a553772b6a641328e05d0c0d3c7bab2`.
- `5p7wKL`: `7e6e4278ff1840159d5569aef1aa88d8`.
- `ewlypw`: `93fb1a6c8b604eb9a47163ab65f3b8ea`.

All six units became inactive with empty cgroups. Native departures and
cancellation left the party and queue maps empty. After client shutdown,
all five character GUIDs were absent from registry, position, and metadata.
Server PTY shutdown completed; BEAM PID 1925710 and all six WoW PIDs were
absent, and ports 4000, 3724, and 8085 were free. All evidence was retained.
