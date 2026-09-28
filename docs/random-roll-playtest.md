# Manual party and raid rolls

`/random`, `/roll`, and the native `RandomRoll` API now dispatch the vanilla
`MSG_RANDOM_ROLL` request. The client supplies two unsigned 32-bit bounds;
the server selects one uniformly distributed integer from the inclusive
range and supplies the authenticated roller's GUID. Valid bounds satisfy
`0 <= minimum <= maximum <= 1_000_000`. Invalid requests are ignored.

`Player.Groups` resolves current membership and uses `Party.Notifier` to
deliver the same result to every online member, including the roller. Raid
subgroups, distance, and map boundaries do not restrict this notification.
Solo results go only to the roller. Rolls do not change membership, loot
settings, or inventory, and they do not create pending state for offline
members. Need/greed loot rolls remain a separate system.

References: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`refs/vmangos/src/game/Handlers/GroupHandler.cpp:HandleRandomRollOpcode`,
and the client/server `msg_random_roll` specifications under
`refs/wow_messages/wow_message_parser/wowm/world/loot/`. The server response
contains minimum, maximum, result, and the full 64-bit GUID, in that order.

## Native acceptance

Three isolated build-5875 clients used a fresh server at `f7efa19c`:
Debugpaladin (2), Debugbuyer (10), and unrelated nearby Debugbidder (11).
All actions used native chat commands, Lua APIs, and login/logout. Tidewave
only read membership, owner PIDs, and world positions.

Each client installed a temporary `CHAT_MSG_SYSTEM` observer that counted
messages containing `" rolls "`. Screenshots show the native roll text plus
the observer's count and last result. The buyer's observer was reset after
logging back in.

| Action | Verified result |
| --- | --- |
| Paladin uses `/roll` while solo | Paladin sees `59 (1-100)` once; buyer and outsider counts stay zero. |
| Form a party; buyer rolls 10–20 | Both party clients see the same `18 (10-20)` once; outsider stays zero. |
| Convert to raid, separate subgroups, and teleport buyer to Northshire | Read model shows paladin in subgroup 7 on map 451 and buyer in subgroup 0 on map 0. Both receive buyer's `264 (200-300)` result. |
| Paladin rolls 1,000,000–1,000,000 | Client displays the full `1000000 (1000000-1000000)` result. |
| Buyer logs out; paladin rolls 42–42 | Buyer owner and world position are absent, membership remains, and paladin receives `42 (42-42)` without an owner error. |
| Buyer logs back in and rolls 77–77 | New buyer owner retains the same raid/subgroup and both clients see `77 (77-77)`. |
| Buyer leaves and rolls 88–88 | Membership lookups for both former members become nil. Buyer sees `88 (88-88)` privately; paladin's counter stays at six and its last roll stays 77. |
| Inspect unrelated client after the entire sequence | Its count remains zero and its last roll remains `none`. |

Telemetry recorded seven `MSG_RANDOM_ROLL` requests. No owner or roll errors
occurred. Login emitted the existing unrelated account-data and GM-ticket
unsupported-opcode warnings. Zero, reversed, and oversized ranges were
covered by automated boundary tests; the native API filtered those attempted
requests before they appeared in server telemetry.

## Evidence

- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.BrsCko`
- Buyer: `/home/pikdum/.cache/thistle-wow-playtest.KwMxNE`
- Unrelated observer: `/home/pikdum/.cache/thistle-wow-playtest.kxN2KZ`
- Screenshots: `solo.png`, `party.png`, `cross-map-raid.png`, `bounds.png`,
  `offline-roll.png`, `reconnected.png`, and `after-leave.png` where applicable.
- Server log: `/tmp/thistle-random-roll-server.log`.
- Read-only snapshots: `/tmp/thistle-random-roll-{party,raid,offline,reconnected,after-leave}.log`.
- Each WoW process used `amdgpu` with increasing graphics-engine counters;
  snapshots are `/tmp/thistle-random-roll-drm-{before,after}.log`.
- All three owned client services and the server were stopped; artifacts remain.

## Fishing regression found during the audit

The fishing-hole handler previously generated another catch when its use
count was already zero. Since depletion is delivered asynchronously to the
game-object owner, queued catches could consume the exhausted pool again.
Commit `51e51eb4` requires a positive use count before loot generation and
rejects depleted pools without changing their state. It also rejects bobbers
that have no fishing-hole loot/count data. The focused five-test suite covers
the last successful catch, the rejected next catch, and bobber rejection.
This fix was verified automatically, without a native fishing run.

## Validation

The focused group and codec suite passed ten tests. Final gates after native
acceptance passed: `mix test.all` reported 7,465 tests, seed 620836, in 69.0
seconds; compilation with warnings as errors passed; strict Credo reported
zero issues. Logs are `/tmp/thistle-random-roll-final-{tests,compile,credo}.log`.
