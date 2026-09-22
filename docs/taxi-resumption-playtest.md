# Taxi flight resumption

Implementation: `dfa2ffa3`.

## Behavior

Disconnecting during a taxi flight now saves the current interpolated position,
remaining waypoints, and remaining travel time in the runtime character store.
The movement projection and progress timer stop. Offline time does not advance
the route, and reconnecting does not charge the fare again or change discovered
nodes. This applies to both purchased and spell-driven routes.

The client resumes after its initial active-mover message, with a fresh spline
ID and timer token. Repeated ready messages and callbacks from the previous
flight cannot restart or finish the resumed route. The taxi mount and passenger
protection remain active; a suspended pet returns after landing. A checkpoint
already within movement tolerance of the endpoint finishes without sending an
empty spline. Dead passengers cannot resume a flight.

World teardown checkpoints the taxi before generic movement cleanup discards
the spline. Explicit teleports instead cancel the itinerary at the current
position. Character storage remains the project's ordinary restart-ephemeral
ETS store.

Reference: local VMangos `8f4e60845`, `Player::ContinueTaxiFlight` in
`refs/vmangos/src/game/Objects/Player.cpp`. It selects the next route segment from
the saved position; this implementation retains the exact unfinished spline.

## Automated acceptance

- `mix test.all`: **4,840 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 1,873 source files.

Regressions exercise stationary offline state, trimmed waypoints, repeated
pause/resume, paid-fare preservation, stale timer and spline rejection, the
active-mover dispatch, teardown ordering, projection cleanup, explicit
cancellation, dead passengers, endpoint tolerance, and pet restoration after
landing. The pet restoration integration test is tagged `:dbc_db`.

## Native build-5875 acceptance

Debugwarlock (GUID 6) and observer Debugdruid (GUID 9), both level 60, used
isolated clients with god mode disabled. The warlock summoned an imp with spell
688 and cast Flight Path 29931 at the actual Plaguewood departure point. Route
494 ends at Northpass Tower on map 0.

### Logout and re-entry

The native logout returned to character selection while airborne. The player
owner and public world presence disappeared; the saved character retained mount
17328 and a suspended imp, with no movement projection or active spline.

| Stage | Result |
| --- | --- |
| Departure | Health 2,594; 100,000,000 copper; discovered nodes `{2}`; live imp |
| Saved checkpoint | `{3263.887966, -3277.430264, 196.419473}`, nine waypoints and 34,144 ms remaining |
| Offline recheck | The full diagnostic output was byte-identical 81 seconds later, exceeding the remaining flight time |
| Re-entry | Native screenshot shows the warlock riding the spectral gryphon along the remaining route, with the imp suspended |
| Landing | Endpoint x/y `{3099.185547, -4273.440918}`; client settled from spline z=108.158058 to ground z=103.249535 |
| Cleanup | Flight, timer, projection, mount, spline nodes, and fall tracking cleared; imp restored as a live owned actor |
| Walking | Forward input moved the player to `{3099.739990, -4278.999512, 105.293648}` |

Health, money, and discovered nodes remained unchanged. The observer saw the
landed warlock, and the passenger client displayed the restored imp and pet bar.
The initial 55-second diagnostic sampler exceeded its HTTP deadline; the above
results use completed state probes and native screenshots.

### Connection loss

A second flight was interrupted by stopping its isolated client while airborne.
The owner disappeared and saved `{3223.314730, -3215.725854, 197.017426}` with ten
remaining waypoints and 36,452 ms left. A fresh client and Wine prefix logged the
same character back in and resumed that remainder with a new spline.

A completed 30-second sampler captured the resumed route through arrival. It
observed no active pet or combat during flight, exact arrival at
`{3099.185547, -4273.440918, 108.158058}`, and a newly restored imp. Health stayed
2,594, money stayed 100,000,000 copper, and known nodes stayed `{2}`. The final
native screenshot shows the landed warlock and imp; the owner and public
position agree after ground settling. Flight, mount, timer, and projection are
cleared.

No gameplay, movement, visibility, or owner errors appeared. The only warnings
were the existing account-data, raid-info, GM-ticket, and meeting-stone requests.

## Retained evidence

- Server log: `/tmp/thistle-taxi-resume-server.log`.
- State probes: `/tmp/thistle-taxi-resume-{before,airborne,offline,offline-later,landed,walked,disconnected}.txt`.
- Completed sampler: `/tmp/thistle-taxi-resume-disconnect-sample.txt`.
- Passenger sessions: `/home/pikdum/.cache/thistle-wow-playtest.42Thsp` and
  `/home/pikdum/.cache/thistle-wow-playtest.nHXSBg`.
- Observer session: `/home/pikdum/.cache/thistle-wow-playtest.DvqO8M`.
- Gates: `/tmp/thistle-taxi-resume-{tests,compile,credo}.log`.
