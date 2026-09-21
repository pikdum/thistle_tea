# Rested experience and logout

Rested experience now settles both online and offline time through the pure
`Logic.Rest` lifecycle. World departure flushes pending online rest and records
one offline interval. Login consumes that interval and saves the result before
publishing the character. Cancellation does not begin offline rest.

At the default vanilla rates, a rest area earns `next_level_xp / 1,152,000`
bonus XP per second. Offline wilderness time earns one quarter of that rate.
The pool retains fractions, caps at 75% of the next level's XP requirement,
and clears when there is no next level. The client displays the reserve
doubled. Rest-area growth now has a ten-second deadline in the player behavior
tree, so an idle player's client projection updates without another action.

The runtime character store remains in memory. Offline means time away from
the character while the server is running; server restarts still wipe it.

The related logout review found a hardcoded one-second delay with no admission
checks. Logout now rejects combat, airborne movement, and GM freeze, allows
instant logout in rest areas and on taxi flights, and otherwise schedules a
twenty-second countdown. The countdown uses the native sitting, root, stun,
and logging-out fields. Cancellation restores movement while preserving
overlapping aura controls and the death root. Tokens reject stale completion
messages after cancellation or a replacement request. Session teardown and
login normalization clear temporary logout state.

References:

- `refs/vmangos/src/game/Objects/Player.cpp`: `ComputeRest`, `SetRestBonus`,
  online rest updates, and offline settlement in character loading.
- `refs/vmangos/src/game/Handlers/MiscHandler.cpp`: logout request and cancel.
- `refs/vmangos/src/game/Objects/UnitDefines.h`: free-movement restrictions.

## Automated validation

- `mix test.all`: **4,450 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Formatting and commit hooks: passed.

Tests cover rest-area and wilderness rates, online settlement, fractional
retention, caps, backward timestamps, duplicate restore, idle tick deadlines,
actual player-owner disconnect and connection loss, login publication,
logout response packets, countdown cancellation, replacement tokens, movement
restoration, and overlapping roots, stuns, and death.

Implementation commits:

- `8d971938`: offline rested XP and scheduled online growth.
- `1291893e`: vanilla logout timing and restrictions.
- `42a030d3`: safe handling of late logout packets at character selection.

Final gate logs: `/tmp/thistle-rest-logout-final-{all,compile,credo}.log`.

## Native client acceptance

The runs used isolated build-5875 clients and Human Debugwarlock, GUID 6,
staged at level 59 with god mode off. Native chat commands and client APIs
drove logout and cancellation. Tidewave probes read the player owner and
CharacterStore; they did not alter gameplay state or timestamps.

The first run established these facts before the late-packet follow-up:

- On Programmer Isle, `/logout` displayed the native countdown at 19 seconds.
  The owner was sitting and rooted, with no offline timestamp.
- `CancelLogout()` sent `CMSG_LOGOUT_CANCEL`, cleared the timer and temporary
  flags, and restored standing. A subsequent native walk moved 6.78 yards.
  The owner remained online after the original deadline.
- In Stormwind, idle rest grew from 0 to 13 bonus XP and changed the rest-state
  byte to rested. The client displayed its resting portrait and "You feel
  rested." Its `GetXPExhaustion()` readout reflected the doubled reserve.
- `/logout` in Stormwind returned to character selection immediately. The
  owner was gone, and the saved character had 14.476382 bonus XP and an offline
  timestamp, with no temporary logout restriction.
- After 69.315 seconds offline in the city, login settled the pool to
  27.099895 XP: exactly the prior pool plus `69.315 * 209800 / 1152000`.
  Online accrual then resumed, and the client displayed a reserve of 58 when
  the owner's integral pool was 29.

The first completed wilderness countdown exposed a late-packet race. The
client sent `CMSG_LOGOUT_CANCEL` after its player owner had left; dispatching it
with connection state crashed the strict player boundary and disconnected the
client. The follow-up ignores logout requests and cancels received without a
player owner. A regression test covers both messages at character selection.

The final run used `42a030d3` with a fresh server and client. The full
wilderness countdown completed at its scheduled deadline, removed the owner,
and returned to character selection. The same late cancel packet appeared in
the connection log without an error or disconnect. The saved character had
no temporary root, stun, sitting pose, or logout state.

| Final-code scenario | Observed result |
| --- | --- |
| City logout and re-entry | The stored pool increased from 5.868572 to 16.687113 over 59.404 seconds offline, matching `59.404 * 209800 / 1152000`. Idle growth resumed after login. |
| Completed wilderness countdown | The owner remained rooted during the countdown, with no offline timestamp. World departure matched the scheduled deadline and preserved the 25.293648 pool. |
| Wilderness re-entry | The owner and store both held 27.508022 bonus XP and a cleared offline marker. The client displayed 54 XP of reserve. Remaining online outside a rest area did not grow the pool. |
| Logout in combat | The client displayed "You can't logout now." The owner remained in combat with no logout timer or restriction. |
| Death and corpse reclamation | A pull attracted several Skeletal Flayers and killed the character. Native spirit release and corpse reclamation preserved the 27.508022 pool without awarding kill XP. |
| Spend the earned reserve | With the character staged at level 5, a native Corruption cast killed a level-4 Defias Thug. XP rose from 0 to 83: 56 base plus 27 rested. The owner and store retained the remaining 0.508022 fraction, projected zero reserve, and returned to normal rest state. The client displayed "You feel normal" and `XP: 83 Rest XP: nil`. |
| Pool cap | Back at level 59, `.rested 9999999` staged an excessive grant. The owner and store clamped it to 157350, 75% of the 209800 next-level requirement. The client displayed 314700. |
| Maximum-level cleanup | `.character level 60` cleared the owner and stored bonus, projected reserve, and next-level XP. The client displayed `Max-level rest: nil`. |

Character levels and the cap-test grant were staged through existing development
commands. Offline accrual used real elapsed time. The kill consumed that earned
reserve; the later cap-test grant was not used for the kill.

No player-owner or connection errors appeared in the final server run. Existing
unsupported account-data, raid-info, GM-ticket, and meeting-stone messages
remain unrelated to this feature. Taxi and GM-freeze admission, overlapping
controls, exact rate arithmetic, and duplicate restoration were verified by
automated tests rather than separate native scenarios.

The first manually chosen city coordinate was below the intended walkable
surface. Acceptance moved to the VMangos `game_tele` Stormwind location,
`{-8833.38, 628.628, 94.0066}`, where the client rendered the city normally.

## Retained evidence

- Server log: `/tmp/thistle-rest-server.log`.
- Read-only probes: `/tmp/thistle-rest-*.txt`.
- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.CiAsOb/screenshots/`.
- Final server log: `/tmp/thistle-rest-final-server.log`.
- Final probes: `/tmp/thistle-rest-final-*.txt`.
- Final screenshots: `/home/pikdum/.cache/thistle-wow-playtest.qogjbO/screenshots/`.

Both helper-owned clients, displays, and retained server processes were stopped.
The work was committed locally; nothing was pushed.
