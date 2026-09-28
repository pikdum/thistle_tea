# Cast movement and fishing acceptance

Implemented in `d76381dc` and `5d622436`, checked with the native build-5875
client on 2026-09-27.

## Shared movement rules

`Spell.CastMovement` records the caster's position when preparation starts and
again when a channel begins. Movement compares each coordinate with that
anchor, using transport-relative coordinates while aboard a transport. A
displacement greater than half a yard interrupts only spells with the relevant
flags. Translation flags alone do not interrupt preparation.

Channels also honor turning flags and always stop on jumping. Hidden channel
bars, first-effect Stuck recovery during a long fall, triggered preparation,
and self-rooted or self-stunned channels retain their appropriate exceptions.
Both movement packets and cast advancement use this pure rule and the existing
cast cancellation transition. Costs and launch effects cannot run after a
preparation is interrupted.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell::UpdateCastStartPosition` and `Spell::update` in
`refs/vmangos/src/game/Spells/Spell.cpp`.

## Fishing follow-up

Native acceptance exposed a pending requirements snapshot being invalidated by
the old fishing duration adjustment. A bobber appeared while the cast remained
in preparation. Fishing now drains its launch requirements before creating the
bobber and changing the channel duration. Failed requirements create no bobber.
The generic summon path excludes fishing targets, preventing a duplicate when
the cast successfully launches.

Bobbers attach to the existing owned channel-object state. Cancellation removes
them through shared cleanup. A successful catch completes the channel while
retaining the bobber's loot session until the player collects or releases it.

## Automated evidence

- `mix test.all`: **7,325 passed**, 72.8 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,581 source files.
- Pure tests cover exact distance thresholds, accumulated small steps,
  transport motion and boarding changes, preparation and channel flags,
  turning, jumping, self roots, hidden bars, Stuck recovery, pre-launch costs,
  channel aura cleanup, owner packets, and owned-object cancellation/completion.
- DBC tests exercise Fireball, Mind Vision, Eagle Eye, Arcane Missiles, Blood
  Siphon, Ranshalla Waiting's self root, and Stuck.
- Map tests send encoded movement packets through `Player.Movement.handle/2`
  and cover fishing's pending requirements, single-bobber ownership, failed
  launch, movement cancellation, and process/spatial cleanup.

## Native acceptance

Used Debugmage, GUID `5`, first on Programmer Isle and then at Crystal Lake,
map `0`, near `{-9530, -240, 58}`. Fishing setup used the existing `.learn 18248`,
`.debug skill 356 300`, and `.additem 6256` commands, followed by equipping the
pole through the client. Runtime inspection was read-only.

| Action | Client and owner evidence |
| --- | --- |
| Move during Heal | The client displayed `Interrupted`. Its own `CMSG_CANCEL_CAST` also participated, so the precise server distance threshold is established by automated tests. |
| Turn during Mind Vision | Spell `2096` was channeling on Prairie Wolf Alpha. Orientation changed from `0.9958555` to `0.0031415` with identical XYZ coordinates. The cast and aura disappeared, and channel fields became `{0, 0}`. The client left the target's view and stopped channeling. |
| Turn while fishing | Spell `18248` remained in `:channel_tick` as orientation changed from `0` to `0.3644140`. The same bobber remained attached, matching fishing's flags. |
| Step forward while fishing | Channel ownership cleared. Bobber `17370384359898481246` disappeared from the entity registry, position cache, and metadata. |
| Catch a fish | A native right-click after bobber `17370384359898481356` became ready opened a loot window containing Raw Brilliant Smallfish, item `6291`. The cast was nil and channel fields were `{0, 0}`, while the consumed bobber retained its loot session and player viewer. |
| Collect the loot | Clicking the item added one fish to the inventory and cleared the loot GUID. The bobber's process, position, and metadata were absent. |
| Logout and reconnect | The fish remained in the runtime character inventory, with no cast or channel ownership restored. Normal logout removed the player owner, position, and metadata. |

Transport movement, hidden channels, self-root exceptions, and exact distance
thresholds were tested automatically, not exercised with the native client.
The final server log contained no gameplay, owner, visibility, or movement errors. The
existing unsupported `CMSG_UPDATE_ACCOUNT_DATA` and `CMSG_GMTICKET_GETTICKET`
warnings occurred during login and map transitions.

The initial server logged one attack-reception failure reporting that `Casting`
was unavailable while the fishing follow-up was being compiled. Acceptance was
repeated on a fresh server after compilation; that error did not recur.

## Retained artifacts

Initial session: `/home/pikdum/.cache/thistle-wow-playtest.67FpxD`.
Screenshots include `heal-moving.png`, `vision-wolf.png`, and
`vision-cancelled.png`. Server log: `/tmp/thistle-cast-movement-server.log`.

Final session: `/home/pikdum/.cache/thistle-wow-playtest.iYSIIP`.
Screenshots include `fishing-active.png`, `fishing-turned.png`,
`fishing-cancelled.png`, `caught-loot.png`, `fish-collected.png`, and
`logged-out.png`. Server log:
`/tmp/thistle-cast-movement-fishing-server.log`.

Read-only samples and final gates:

- `/tmp/thistle-cast-movement-native-vision-turn.log`
- `/tmp/thistle-cast-movement-native-fishing-cancel.log`
- `/tmp/thistle-fishing-cancel-cleanup.log`
- `/tmp/thistle-fishing-bite-ready.log`
- `/tmp/thistle-fishing-success-state.log`
- `/tmp/thistle-fishing-looted-state.log`
- `/tmp/thistle-fishing-saved.log`
- `/tmp/thistle-fishing-reconnected.log`
- `/tmp/thistle-fishing-logout.log`
- `/tmp/thistle-cast-movement-final-{compile,credo,all}.log`

Both sessions used their own systemd units and private display `:1`.
WoW PID `2574874` belonged to the first session's cgroup and reported amdgpu
graphics work. Final-session PID `2581377` belonged to its recorded cgroup;
its graphics counter increased from `1,042,146,440` to `3,426,214,910` ns.
The helper-owned clients and retained server PTYs were stopped after acceptance.
