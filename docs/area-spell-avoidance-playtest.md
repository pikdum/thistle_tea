# Area spell Avoidance and persistent ground effects

Validated on 2026-09-25 with the native build-5875 client and local VMangos
references. Implementation commits are `a607af5c` and `dcbf8c35`.

## Rules and implementation

Vanilla aura 160 reduces area magic hit chance. Avoidance (23198) supplies
25 percentage points; it does not reduce damage from a successful hit.
The area classification follows the original implicit target codes and survives
recipient effect filtering. Player and creature owners publish the same pure
defense projection for ordinary casts, triggers, proc damage, and heartbeat checks.
The projection also corrects the heartbeat path's incoming spell-hit aura lookup.

Persistent ground damage rolls hit chance on each due tick. A resisted tick
advances its deadline, reports a resist, and leaves the holder available for
later ticks. Direct damage-over-time auras retain their existing hit behavior.
Ground recipients carry the caster snapshot and source object's footprint,
periodic schedule, and fixed expiry. Source cancellation removes its recipients;
an old source cannot remove a replacement. Recipient owners check the footprint
and source availability every 250 ms and before due ticks. Refreshing a ground
aura does not extend the object's lifetime or restart its periodic deadline.

Reference paths:

- `refs/vmangos/src/game/Objects/SpellCaster.cpp`: area avoidance in magic hit chance.
- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: persistent periodic hit checks and range removal.
- `refs/vmangos/src/game/Objects/DynamicObject.cpp`: ground lifetime and final channel tick.

## Native acceptance

Debugwarrior (GUID 1) and Debugbidder (GUID 11), both level 50, dueled near
Northshire at `{-8949, -132, 83.5}` and `{-8944, -132, 83.5}` on map 0.
The warrior learned 23198 through `.learn`. Both had god mode disabled during
combat. The mage's equipment supplied 1% spell hit.

| Check | Observed result |
| --- | --- |
| Current owner and metadata | Avoidance 25; hit chance 72% for Arcane Explosion and Blizzard, 97% for Fireball. |
| Twelve rank-1 Arcane Explosions | Native casts, visible resists, and successful damage in authoritative health. |
| Five rank-1 Fireballs | Native direct casts and damage; the avoidance modifier did not enter their hit calculation. |
| Full rank-1 Blizzard | Eight scheduled ticks, six damaging and two resisted; landed ticks dealt 25 damage. |
| Final tick and expiry | Final damage was retained; the holder and dynamic object cleared, then health stopped decreasing. |
| Caster movement interruption | `CMSG_CANCEL_CHANNELLING`, zero-time channel update, cleared cast/object/holder, and no later damage. |
| Target movement out | The holder cleared while the channel and object continued; health remained unchanged outside. |
| Target re-entry | The holder returned and damage resumed; expiry remained tied to the original object. |
| Logout and reconnect | Owner, position, and metadata disappeared on logout. Re-entry restored Avoidance 25 and the same 72%/97% hit chances. |

Ground targeting needs a rendered frame between `/cast Blizzard(Rank 1)` and
the ground click. The acceptance sequence waited 300 ms. Cancellation evidence
uses caster movement; Escape and `SpellStopCasting()` attempts did not establish
channel cancellation in this client.

The caster client displayed the area animation, channel bar, damage, and resists.
Packet traces recorded periodic damage and full-resist feedback to both clients.
Both WoW processes used `amdgpu`; their graphics counters increased during the run.
Both helper-owned services were stopped and confirmed inactive. The player
owners, positions, metadata, and Blizzard registry entries were absent before
the retained server was stopped. No owner crashes or unhandled protocol errors
appeared during acceptance.

## Validation and evidence

`mix test.all`: 6,137 passed. `mix compile --warnings-as-errors` and
`mix credo --strict`: passed. Tests cover classification, hit boundaries and
modifier ordering, aura lifecycle, owner projections, real DBC rows, triggered
delivery, ground refresh/expiry, cancellation identity, source disappearance,
world changes, late delivery, and the dynamic-object boundary.

Retained evidence:

- `/tmp/thistle-avoidance-projection.log`
- `/tmp/thistle-avoidance-ground-trace.log`
- `/tmp/thistle-avoidance-ground-packets.log`
- `/tmp/thistle-avoidance-movement-packets.log`
- `/tmp/thistle-avoidance-interrupt-owner.log`
- `/tmp/thistle-avoidance-exit-owner.log`
- `/tmp/thistle-avoidance-reentry-verified.log`
- `/tmp/thistle-avoidance-logout.log` and `/tmp/thistle-avoidance-reconnect.log`
- `/tmp/thistle-avoidance-server.log`
- `/tmp/thistle-avoidance-cleanup.log`
- `/home/pikdum/.cache/thistle-wow-playtest.w2lEOv/screenshots/`
- `/home/pikdum/.cache/thistle-wow-playtest.bZHlDc/screenshots/`
