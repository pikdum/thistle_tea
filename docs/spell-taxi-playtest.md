# Spell-driven taxi flights

Implementation commits:

- `08bb918c`: connect taxi spell effects to the shared flight system.
- `097f569e`: land at the final spline point and reset fall tracking.
- `8f94ca63`: exclude taxi passengers from hostile targeting.

## Behavior

DBC effect 123 now compiles to the movement semantic `:send_taxi`. It emits
`SendTaxiPath` with the affected player's GUID, route ID, and originating spell
ID. Owner-local delivery uses `EventSink.Context`; cross-owner script delivery
retains the typed command. Creature targets and non-positive path IDs produce no
flight request.

Spell and script flights use the existing player flight owner, route cache,
movement spline, progress timer, visibility publication, arrival, and disconnect
transitions. They do not require discovered nodes. Route fares are validated
and charged; all six vanilla spell routes have a zero fare. Script starts can
use the other faction's mount, and spell starts can use a mountless route.
Positioned departure nodes still require the player to be nearby on the same
map. A zero-position scripted source does not impose that distance check.

The transition preserves the spell delivering the flight, interrupts other
casts and auto-repeat, cancels trade, suspends the companion, removes stealth
and incompatible shapeshift forms, and removes a ground mount. Warrior stances
and Shadowform remain compatible. Busy, dead, logging-out, already-flying, and
client-control-disabled players cannot start a flight. Invalid starts return
the taxi error response without charging or moving the player.

Flight completion uses the last spline point, which can differ from the
destination marker. Both boarding and landing clear stale fall tracking. Taxi
flags reject hostile targeting through the shared attackability check, so
movement-triggered aggro and ordinary hostile selection use the same rule.
Helpful targeting remains available, and normal attackability returns on
landing.

References are local VMangos `8f4e60845`: `Spell::EffectSendTaxi`,
`Player::ActivateTaxiPathTo`, `Unit::IsInDisallowedMountForm`,
`Unit::IsTargetableBy`, and `FlightPathMovementGenerator::Finalize`.

## Automated acceptance

- `mix test.all`: **4,829 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 1,873 source files.

Regressions cover all six DBC spells, living-player routing, explicit owner
delivery, fares, opposite-faction mounts, mountless spell flights, source
validation, cast preservation/interruption, form and stealth removal, compatible
stances, landing coordinates, fall cleanup, and hostile targeting before and
after landing. Existing gossip routing, acknowledgement, and disconnect tests
remain green. The DBC `Filming` route 472 has no spline nodes in the supplied
data; it loads as a taxi spell but cannot launch an empty route. Mountless
behavior is verified with a complete fixture route.

## Native build-5875 acceptance

Debugdruid (GUID 9) and Debugpaladin (GUID 2), both level 60, used isolated native
clients. God mode was disabled. The paladin learned spell 29931, Flight Path,
which selects route 494 from Plaguewood Tower to Northpass Tower on map 0.

Casting it on Programmer Isle produced the native message that the player was
too far from the taxi stand. At the real departure point, the druid cast Cat
Form 768 and Prowl 6783. Its initial authoritative state was form 1, energy,
both auras active, 2,373 health, 100,000,000 copper, and known nodes `{26, 27}`.
The paladin targeted the druid and cast Flight Path through the native client.

The first flight exposed an existing attackability defect: a creature added a
threat reference to the flying player. After the shared flag fix, a fresh server
and two fresh clients repeated the route. Screenshots show the druid in normal
form riding spectral gryphon display 17328, then standing beside the observer
at Northpass Tower.

A timed read-only sampler captured the final repeat from 0.4 seconds after
launch until three seconds after landing:

| Stage | Authoritative result |
| --- | --- |
| Launch | Route `[494]`, 17 spline nodes, 46,466 ms duration, mount 17328, form 0, Cat Form and Prowl removed |
| Mid-flight | Position approximately `{3228.806, -3560.759, 204.935}`; no combat or threat references |
| Flight end | `{3099.185547, -4273.440918, 108.158058}`, exactly the final spline point; mount and flight cleared |
| Ground settling | Client landed at the same x/y, z=103.2491; health remained 2,373 |
| Control restored | Native forward input moved the druid to `{3099.679443, -4278.393555, 105.058662}` |
| Relog | Character store, owner, and public world position agreed at the walked-to location |

No sampled state had combat or threat references. Money and discovered taxi
nodes stayed unchanged. Final and reconnected state had no taxi timer, spline
nodes, mount, cast, fall tracking, or client movement lock. The 20-second logout
completed before re-entry; the owner was absent and the stored position was
verified while offline.

No gameplay, movement, owner, or visibility errors appeared. Only the existing
account-data, raid-info, GM-ticket, and meeting-stone request warnings remained.
Both clients, their private X servers, and the retained server were stopped.

## Retained evidence

- Druid: `/home/pikdum/.cache/thistle-wow-playtest.eeCQfA/screenshots/`, including
  `in-flight.png`, `mid-flight.png`, `landed.png`, `walking-after-flight.png`,
  `logged-out.png`, and `reconnected.png`.
- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.kHl5zI/screenshots/`, including
  `observer-arrival.png`.
- Initial rejection screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.7nK6g3/screenshots/too-far.png`.
- Fixed server log: `/tmp/thistle-spell-taxi-fixed-server.log`.
- State: `/tmp/thistle-spell-taxi-fixed-{before,airborne,landed}.json`,
  `/tmp/thistle-spell-taxi-final-sample.json`, `/tmp/thistle-spell-taxi-final-walk.json`,
  `/tmp/thistle-spell-taxi-offline.json`, and `/tmp/thistle-spell-taxi-reconnected.json`.
- Gates: `/tmp/thistle-spell-taxi-{tests,compile,credo,focused,final-focused}.log`.

An earlier continuous sampler failed on an incorrect boolean expression in the
read-only probe. The corrected final sampler completed successfully; the failed
output is not used as acceptance evidence.
