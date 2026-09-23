# Blink terrain acceptance

Build-5875 acceptance on 2026-09-23 used a fresh server and two isolated GPU
clients. References were VMangos `TARGET_LOCATION_CASTER_FRONT_LEAP` in
`Spell.cpp`, `Map::GetWalkHitPosition`, `PathInfo::FindWalkPoly`, and
`Spell::EffectLeapForward`.

## Reproduced problem and change

Blink previously followed an ordinary A* route, stopping after its distance
budget. At Northshire, a cast from `(-8930, -150, 82)` toward heading
`5.105088` ended at approximately `(-8913.778, -141.609, 82.234)`: 18.20 yards
sideways and 1.54 yards backward relative to the requested direction.

The native navigation boundary now exposes a straight walkable trace using
Detour raycast. It excludes steep polygons, searches within 20 vertical yards,
rejects a starting surface more than three yards above the source, stops at
the first mesh boundary, and refines height only within the selected surface's
1.5-yard tolerance. Query scratch remains worker-local, and the existing shared
map lock protects tiles throughout each query. Missing geometry and exhausted
buffers return no destination.

`World.SpellMovement` selects ground, submerged, or falling behavior. Ground
casts use the walkable trace and reject destinations outside the forward
90-degree arc. Submerged casts retain depth and clip solid geometry with a
half-yard clearance, including doodads. Falling casts can use a floor within
40 yards below the source. Player and creature leap requests use this same
boundary; taxi passengers are rejected. The resulting teleport retains the
existing combat-preserving owner transition.

This uses the current Namigator mesh and collision data. It does not add
transport-local meshes or dynamic game-object insertion into that data, and it
does not change ordinary pathfinding or the separate caster-relative summon
placement policy.

## Native results

Debugmage (GUID 5) cast the actual Blink spell, 1953. Debugwarlock (GUID 6)
observed. Both used developer positioning and god mode; all casts and movement
input came through the clients. Tidewave only read state. All casts remained
in open map 0.

| Check | Observed result |
| --- | --- |
| Obstruction at Northshire Abbey | From `(-8930, -150, 81.80724)`, Blink stopped at `(-8922.02344, -150, 81.28190)`. Both clients showed the mage stopping directly ahead near the wall and vegetation, with no sideways detour. |
| Movement after clipping | Native backward input moved the mage to `(-8924.27344, -150, 81.35286)`, confirming normal movement after the teleport. |
| Open ground | From `(-8980, -132.49001, 84.26762)`, Blink reached `(-8960, -132.49001, 82.83968)`, the full 20 horizontal yards. |
| Submerged depth | In Faldir's Cove, the mage moved from `(-2180, -1867.58997, -5)` to `(-2160, -1867.58997, -5)`. The initial swimming flag was present, depth stayed at -5, and the observer saw the mage remain underwater. |
| Falling | Before Blink, a sampler observed `(-8959.5, -132.49001, 117.41438)` with flags `24577`, including falling-far. Blink reached `(-8939.5, -132.49001, 83.63928)` with motion flags cleared. Both clients subsequently showed the mage on the ground. |
| Final projection | The final authoritative and public positions matched exactly, and both player owners remained alive. |

The first open-ground setup used height 83.53 where the measured floor was
84.26723, causing the client to fall below terrain. That setup was corrected
before the accepted open-ground cast. A first falling attempt cast too early
after a 60-yard developer teleport and produced no displacement. The accepted
attempt used a 40-yard starting height and native movement input; the sampler
confirmed the falling flag and the actual height before relocation. God mode
means this run is not evidence about fall-damage accounting.

## Evidence and checks

- Caster session: `/home/pikdum/.cache/thistle-wow-playtest.3adYNI`.
- Observer session: `/home/pikdum/.cache/thistle-wow-playtest.Qo1BPn`.
- Both clients: `wall-before`, `wall-after`, `water-ready`, `water-after`,
  `open-verified`; caster additionally `open-ready` and `falling-settled`,
  observer `falling-verified`.
- Server log: `/tmp/thistle-blink-server.log`.
- Read-only samples: `/tmp/thistle-blink-wall-sample.log`,
  `/tmp/thistle-blink-water-sample.log`, `/tmp/thistle-blink-open-verified.log`,
  `/tmp/thistle-blink-falling-verified.log`, `/tmp/thistle-blink-final-state.log`.
- The earlier `open-after` and caster `falling-verified` captures are setup or
  transitional frames, not the accepted settled result.
- WoW's own gfx counters on PCI `0000:0c:00.0` increased from 1156413318 to
  17437443035 ns for caster PID 2363501 and 717465394 to 19500699145 ns for
  observer PID 2364224.

The server logged the expected duplicate-character login rejection and existing
unsupported account-data, raid-info, ticket, and meeting-stone requests. No
navigation, teleport, owner, or visibility errors occurred. Both helper-owned
client services and the retained server were stopped.

Automated coverage includes the sideways/backward regression, full-distance
ground casts, blocked collision rays, retained underwater depth, falling height
limits, missing geometry, creature targets, taxi rejection, concurrent queries
across maps, and ADT unload/reload with active readers. These tests are tagged
`:namigator_maps` and do not query generated databases.

Final source validation: `mix test.all` passes 5,257 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
`git diff --check` pass. No architecture allowlist entries were added.
