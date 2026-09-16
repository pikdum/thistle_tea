# Ground mounts

Mount spells now use the ordinary cast and aura lifecycle. The loader resolves
creature entries into mount displays; gameplay logic reads the translated aura
and never queries the creature database. The aura transition owns replacement,
cancellation, interruption, death cleanup, and display projection. Unrelated
aura changes preserve taxi and script-owned displays.

Movement is recomputed from base speeds. Mounted and unmounted bonuses are
separate; mounted equipment bonuses multiply, and the strongest nonstacking
bonus competes with their product. Snares apply afterward. Forward speed
bonuses no longer accelerate backward movement. Reference rules come from
`Unit::UpdateSpeed`, `Aura::HandleAuraMounted`, and mount interruption flags in
`refs/vmangos/`.

Entering water removes mounts whose spell data carries the water interruption
flag. Ordinary player casts dismount through the aura transition; spells marked
usable while mounted preserve the mount. Taxi boarding removes ground mounts.
Existing combat and shapeshift validation applies, and dungeon-map restrictions
include the reference's outdoor-instance exceptions. Indoor geometry checks,
area-specific mounts, and mount-specific pet suppression are outside this slice.

## Real-client acceptance

An isolated build-5875 client logged into the seeded Debugwarrior. Learned and
cast Brown Horse (458) and Swift Palomino (23227) through client commands. The
client displayed both models and their buff icons. Read-only owner inspection
confirmed:

| State | Mount display | Run speed | Backward speed |
| --- | --- | --- | --- |
| Brown Horse | 2404 | 11.2 | 4.5 |
| Right-click cancellation | 0 | 7.0 | 4.5 |
| Swift Palomino | 14582 | 14.0 | 4.5 |

The initial autorun macro was blocked by the vanilla UI, so it provides no
movement-distance evidence. The client also blocked Bloodrage while mounted;
cast-triggered dismount is covered by automated tests, not that client attempt.
A first Crystal Lake teleport used a height below terrain and was discarded.
Repeating above terrain produced a real `MSG_MOVE_START_SWIM`, removed the
mount, and restored run speed to 7.0.

Evidence is retained in:

- `/home/pikdum/.cache/thistle-wow-playtest.5rUwuC/screenshots/`
- `/tmp/thistle-mount-server.log`
- `/tmp/thistle-mount-cancelled.txt`
- `/tmp/thistle-mount-swift.txt`
- `/tmp/thistle-mount-lake.txt`
- `/tmp/thistle-mount-swim-transitions.txt`

## Bugs fixed during implementation

Death cleanup captured movement before removing auras and restored that stale
snapshot afterward. It now preserves recalculated movement; a regression covers
snare removal independently of mounts.

A login before debug seeding completed crashed the auth connection on an unknown
account. Unknown logins and reconnects now receive protocol failures. Inspection
of the same reconnect path found a missing retained account and a 32-byte salt
where the protocol requires 16 bytes; both are fixed. Auth tests cover fragmented
login challenges and a complete reconnect challenge/proof exchange.

Validation: `mix compile --warnings-as-errors`, `mix test.all` (2,870 passing
tests), `mix credo --strict`, formatting, and diff checks. Mount tests cover
speed stacking, replacement, snares, cancellation, interruption, death, casting,
swimming restrictions, and taxi cast rejection. Existing taxi tests also pass.
