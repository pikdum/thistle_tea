# Client camera selection and mover handoffs

## Implementation

`6432a6ab` implements `CMSG_FAR_SIGHT`. The authorized remote target remains in
`player.farsight`; `State.viewpoint_guid` records the camera the client selected.
Selecting the body retains the authorized target without letting visibility
refreshes or stale watcher notifications restore the remote view. Remote
selection validates that the target exists in the viewer's world and instance.
Camera changes share the existing visibility subscriptions and chase watcher.

`ef018b16` implements `CMSG_MOVE_NOT_ACTIVE_MOVER` and separates the client's
acknowledged mover from the server's control authority. `Player.Mover` validates
selection and routes final movement snapshots to the entity's owner. A
target-owned `MovementHandoff` permits one final snapshot from the previous
controller for at most four seconds, while the target remains alive, in the same
world and position, and without authoritative movement. Accepted movement, new
control, path starts, teleports, and logout invalidate stale permissions.

The shared movement path still handles transport, environment, observer updates,
and presence publication. A final body snapshot during a possession grant does
not cancel the channel that just started. Player and creature recipients validate
the previous controller themselves. Client acknowledgements cannot grant control.

References:

- `refs/vmangos/src/game/Handlers/MiscHandler.cpp`: `HandleFarSightOpcode`.
- `refs/vmangos/src/game/Handlers/MovementHandler.cpp`:
  `HandleSetActiveMoverOpcode` and `HandleMoveNotActiveMoverOpcode`.
- `refs/wow_messages/wow_message_parser/wowm/world/spell/cmsg_far_sight.wowm`.
- `refs/wow_messages/wow_message_parser/wowm/world/movement/cmsg/cmsg_move_not_active_mover.wowm`.

## Automated validation

Tests cover both codecs and dispatcher registration, body/remote camera selection,
stale watcher events, missing and foreign-instance viewpoints, unauthorized mover
selection, controlled-player input restrictions, and final-snapshot routing.
The handoff tests cover one-use consumption, wrong senders, expiry, death, newer
movement, world changes, path movement, and same-position teleportation. Boundary
tests verify presence publication, channel preservation, player routing, and
creature release without relocating the controller.

All source gates passed on `ef018b16` before launching the native clients:

- `mix test.all`: 5,364 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`, `git diff --check`, and commit hooks.

Logs: `/tmp/thistle-mover-tests-accepted.log` and
`/tmp/thistle-mover-credo-accepted.log`.

## Native acceptance

A fresh server on `ef018b16` used genuine build-5875 clients on Programmer Isle:
debug priest 4 and debug mage 5, both level 60. The clients requested and accepted
duels before player possession. Native chat casts, keyboard movement, and
`PetDismiss()` drove the checks; read-only runtime probes checked owner state.

Sessions under `/home/pikdum/.cache/thistle-wow-playtest.*`:

- Priest: `8j42XH`.
- Mage: `9ngqNi`.
- Reconnected priest: `mfumXi`.

Both initial clients used `amdgpu` device `0000:0c:00.0`. Priest WoW PID 2496395's
graphics counter advanced from 3,333,156,606 to 33,209,317,817 ns; mage PID 2497226's
advanced from 1,635,184,181 to 28,903,763,692 ns.

### Player possession

Mind Control rank 3 (10912) changed the priest's authoritative and acknowledged
movers to GUID 5 and selected camera 5. The mage relinquished its acknowledged
mover and its gameplay buttons became unavailable. The priest's final body
snapshot was consumed without cancelling the channel.

Priest keyboard input moved the mage from x=16303.2 to x=16306.7 while the priest
stayed at x=16303.2. The mage client displayed that movement. Native dismissal
restored both clients' own movers and cleared the priest's camera and channel.
Mage keyboard input then moved its own body to x=16310.2 and cleared the pending
former-controller handoff.

The client does not always send a former remote unit's final snapshot on release.
Automated tests separately establish remote routing and recipient validation. An
unused handoff may remain as expired data; it grants no authority after four
seconds, and subsequent movement clears it.

### Mind Vision

Native `/cast Mind Vision` selected learned rank 2 (10909). While the priest
channeled, the mage teleported from x=16310.2 to x=16603.2, 300 yards from the
priest's unchanged body. The selected and authorized camera remained GUID 5, and
the priest's visibility subscriptions moved to the remote cells. A screenshot
showed the mage near the distant temple. Natural expiry cleared camera, farsight,
and channel, restoring the body's visibility cells and view.

### Creature possession

Mind Control on Defias Thug entry 38, GUID 17379390962661268572, changed the
priest's acknowledged mover and camera to the creature. Keyboard input moved the
creature to `{16331.1045, 16298.0996, 69.4444}`. Native dismissal restored mover 4
and the body camera, cleared the channel and creature charmer, removed the
possession pet state, and restored creature faction 17 at its final position.

### Disconnect and reconnect

Stopping the priest client during another confirmed player possession left the
mage ready, with authoritative and acknowledged mover 5, no incoming possession,
and no controller monitor. Mage keyboard input moved x=16325.2 to x=16328.7.
The saved priest had farsight 0, charm 0, channel 0, and no movement handoff.

Reconnecting the priest restored authoritative and acknowledged mover 4, normal
camera, no companion, no channel, and no handoff. Keyboard movement moved its body
from x=16322.2 to x=16325.7. Both restored clients displayed normal controls.

The log contains processed `CMSG_FAR_SIGHT` and `CMSG_MOVE_NOT_ACTIVE_MOVER`
entries with no unimplemented warnings for either opcode and no owner crashes.
One `CMSG_PLAYER_LOGIN` error came from accidentally selecting the already-online
mage in the reconnect client; duplicate login was rejected, and selecting the
priest completed the reconnect check. Existing account-data, ticket, and
meeting-stone requests remain outside this change.

## Evidence and cleanup

- Server: `/tmp/thistle-camera-mover-server.log`.
- GPU counters: `/tmp/thistle-camera-mover-gpu-{start,end}.txt`.
- Player control: `/tmp/thistle-camera-mover-{movement,dismiss,restored}.txt`.
- Remote vision: `/tmp/thistle-camera-vision-{crossing,confirmed,expiry}.txt`.
- Creature control: `/tmp/thistle-camera-mover-creature-{grant,move,release}.txt`.
- Disconnect: `/tmp/thistle-camera-mover-{before-disconnect,disconnect,disconnect-movement}.txt`.
- Reconnect: `/tmp/thistle-camera-mover-{reconnect,reconnect-movement}.txt`.
- Priest screenshots: `8j42XH/screenshots/remote-camera-settled.png`,
  `vision-restored.png`, `controlled-creature.png`, and `creature-released.png`.
- Mage screenshots: `9ngqNi/screenshots/possessed-movement.png`,
  `restored-movement.png`, `before-controller-disconnect.png`, and
  `disconnect-restored.png`.
- Reconnected priest: `mfumXi/screenshots/reconnected-movement.png`.

Every helper-owned client and the retained server from this run was stopped.
No source changed after the final gates or native acceptance; subsequent edits
only record these results. Nothing was pushed. This closes the two protocol gaps
identified in the player-possession notes, not the broader Vanilla parity goal.
