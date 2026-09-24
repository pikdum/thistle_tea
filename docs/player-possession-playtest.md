# Player possession

## Implementation

Priest Mind Control can now possess another player. Incoming control is a
target-owned `Possession` value; the controller retains the existing canonical
companion relationship. Aura transitions grant and release control, preserve
the original faction, and stop casting, combat, and movement. Typed effects
project the camera, active mover, attack-only possession bar, and client control.

Movement is routed through the possessed player's owner and the shared player
movement path. The victim observes the movement but cannot issue gameplay
actions while controlled. Movement acknowledgements validate the actual mover;
root and speed instructions reach the controller. Attack commands use the
ordinary player melee system, and kill credit follows the controller.

The owner monitors the controller. Aura removal, death, teleport, target logout,
controller loss, channel cancellation, and expiry converge on the same cleanup.
Possession rank limits and existing control relationships are validated before
casting. NPC charm of players remains separate from player possession.

VMangos references are `Unit::ModPossess` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`, `PossessSpellInitialize` and
`InitPossessCreateSpells` in `Objects/Player.cpp` and `Objects/Unit.cpp`, and
`Handlers/MovementHandler.cpp`. The implementation uses Thistle
Tea's aura transitions, typed effects, explicit owner contexts, and presence
publication rather than importing VMangos ownership mechanisms.

## Initial native acceptance

The initial run used source commit `ca21e124`, a fresh server, and two genuine
build-5875 clients: debug priest 4 and debug mage 5, both level 60 on Programmer
Isle. The priest learned Mind Control rank 3, spell 10912. They requested and
accepted a duel through the clients before casting.

Sessions:

- Priest: `/home/pikdum/.cache/thistle-wow-playtest.YKPxMI`.
- Mage: `/home/pikdum/.cache/thistle-wow-playtest.GkXsff`.
- Reconnected mage: `/home/pikdum/.cache/thistle-wow-playtest.AhHWPI`.

Priest WoW PID 2463523 used `amdgpu` device `0000:0c:00.0`; its graphics counter
advanced from 1,297,603,035 to 19,492,340,249 ns. Reconnected mage PID 2469914 used
the same device and advanced from 1,403,325,391 to 4,658,396,712 ns.

Accepted behavior:

1. The priest's camera and mover changed to GUID 5 with an attack-only action
   bar. The mage's gameplay buttons became unavailable. Authoritative state
   showed the priest channeling and the mage possessed by GUID 4.
2. Priest keyboard movement moved the mage 3.5 yards, from x=16303.2 to
   x=16306.7, while the priest's body stayed in place. The mage client observed
   that movement. Sending movement from the mage client did not move its body.
3. Natural expiry cleared the channel, companion, camera, incoming control, and
   monitors. Mage keyboard movement then moved its body another 2.1 yards.
4. Clicking the possession attack button against Defias Thug entry 38 produced
   ordinary mage melee. Target GUID 17379390962661268572 went from 71 HP to zero;
   its authoritative tap credited priest 4. The server recorded the mage's
   `CMSG_ATTACKSWING` and attack stopped after the kill.
5. Disconnecting the possessed mage restored the priest's camera, mover, and
   channel state. The saved mage had no charmer or possession and faction 1.
   Reconnecting restored a normal, controllable mage.
6. Teleporting the possessed mage through its client GM command released both
   sides and completed the teleport to `{16326.2, 16298.1, 69.44}`.

Evidence includes `/tmp/thistle-player-possession-server.log` and
`/tmp/thistle-possession-{controller-move,victim-input,expiry,restored-move,
melee-accepted,cancel,target-disconnect,reconnect,teleport}.txt`.
Screenshots include priest `first-control.png`, `controlled-move.png`,
`controlled-melee.png`, `cancelled.png`; mage `possessed.png` and
`controlled-move-observer.png`; and reconnected mage `reconnected.png`.

## Discovered disconnect regression

Disconnecting the priest during another possession exposed a real bug: duel
cleanup interpreted metadata's controlled GUID as a creature pet and sent
`{:drop_threat, 5}` to the mage's owner. That unsupported creature command
crashed the mage process. The failed run is preserved in the initial server log
and `AhHWPI/screenshots/controller-disconnected.png`; it is not acceptance.

The correction filters creature recipients at the command source. Duel cleanup,
PvP flag propagation, defensive pet notification, and pet talent links now
distinguish creature companions from possessed players. PvP contact attribution
also resolves a possessed player's controller. Regression tests exercise both
possessed-player exclusion and preserved creature-pet behavior.

The rerun on `f1cf15a1` used priest session `bI8YmG` and mage session `be4R9X`.
Disconnecting the priest left the mage's original owner alive and ready, with
charmer 0, faction 1, no possession or monitor, and mover 5. Mage keyboard input
then moved x=16303.2 to x=16306.7. The client stayed in the world with restored
buttons. No player-owner crash appeared.

That same check found a second cleanup omission: the saved priest still had
farsight 5 despite having no companion or channel. Reconnecting priest session
`aweqdx` confirmed `{ready: true, mover: 4, farsight: 5, companion: nil}`. The
camera release is now shared between normal detachment and companion suspension,
so it runs before logout retains the character. A regression checks camera,
mover, companion, and target-release message together.

Intermediate evidence:

- `/tmp/thistle-player-possession-fixed-server.log`.
- `/tmp/thistle-possession-fixed-{before-disconnect,disconnect,restored-move}.txt`.
- `/tmp/thistle-possession-stale-camera-reconnect.txt`.
- `be4R9X/screenshots/before-disconnect.png` and `restored-movement.png`.
- `aweqdx/screenshots/stale-camera.png`.

## Automated validation

Coverage includes possession grant, replacement, rank limits, cancellation,
expiry, lethal damage, fear overlap, controller process loss, stale messages,
movement observers, blocked victim input, root/speed recipients, mover-specific
acknowledgements, attack-only bar encoding, kill credit, PvP attribution, duel
cleanup, and camera release before retaining the character.

Final source gates passed with every playtest client and server stopped:

- `mix test.all`: 5,351 tests passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`, `git diff --check`, and commit hooks.

The final source commit is `0963d914`. Logs are `/tmp/thistle-possession-camera-tests-final.log` and
`/tmp/thistle-possession-camera-credo-final.log`.

## Final native acceptance

A fresh server on `0963d914` used priest session `eWADtW`, mage session `enjig4`,
and reconnected priest session `argFSX`, all under
`/home/pikdum/.cache/thistle-wow-playtest.*`.

The priest's WoW PID 2482092 used `amdgpu` device `0000:0c:00.0`; its graphics
counter advanced from 1,538,247,250 to 10,398,300,901 ns. Mage PID 2482844 used
the same device and advanced from 665,133,401 to 16,689,339,676 ns.

After another native duel and rank-3 cast, the priest moved the mage from
x=16303.2 to x=16306.7 while its own body stayed at x=16303.2. The mage client
displayed the movement with its gameplay buttons disabled.

Native `PetDismiss()` released a confirmed active possession. Both monitors,
the incoming/outgoing relationships, and the priest's channel cleared; camera
became 0 and mover returned to 4. This is the verified cancellation path.
The separate `SpellStopCasting()` attempt did not establish cancellation and
is not counted as acceptance.

After a further confirmed possession, stopping only the priest's client left
the mage's original owner PID alive and ready. Its charmer was 0, faction 1,
possession and monitor nil, and mover 5. Its own keyboard input then moved
x=16306.7 to x=16310.2. The client remained in the world with restored controls.
The saved priest now had `{companion: nil, channel_spell: 0, charm: 0, farsight: 0}`.

Reconnecting the priest confirmed mover 4, camera 0, charm 0, no companion, and
no cast. Priest keyboard movement then moved its own body from x=16303.2 to
x=16306.7. Screenshots show normal controls and camera on both restored clients.

No owner exceptions or crashes appeared in the final server log. It still logs
unimplemented `CMSG_FAR_SIGHT` and `CMSG_MOVE_NOT_ACTIVE_MOVER` notifications
during control changes, plus the existing account-data, ticket, and meeting-stone
login requests. Those protocol gaps remained at this milestone; the accepted
movement and lifecycle behavior above did not establish support for them or
complete Vanilla parity. They were subsequently implemented in `6432a6ab` and
`ef018b16`; see [camera and mover acceptance](camera-mover-playtest.md).

Final evidence:

- `/tmp/thistle-player-possession-accepted-server.log`.
- `/tmp/thistle-possession-accepted-{grant,move,before-dismiss,dismiss}.txt`.
- `/tmp/thistle-possession-accepted-{before-disconnect,disconnect,restored-move}.txt`.
- `/tmp/thistle-possession-accepted-{reconnect,reconnect-move}.txt`.
- `/tmp/thistle-possession-accepted-gpu-*.txt`.
- `eWADtW/screenshots/dismissed.png`.
- `enjig4/screenshots/controlled-movement.png`, `before-controller-disconnect.png`,
  and `restored-movement.png`.
- `argFSX/screenshots/restored-camera.png` and `reconnected-movement.png`.

Every helper-owned client and retained server from these runs was stopped.
No source changed after the final gates and native run; subsequent edits only
record the evidence here. Nothing was pushed.
