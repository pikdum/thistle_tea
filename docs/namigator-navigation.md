# Namigator navigation changes

## Concurrent queries

Namigator commit `80ee2a1` separates caller-owned search scratch from shared map
data. Thistle Tea keeps one query context per native worker and uses shared map
locks for ordinary queries. Tile loading and unloading retain exclusive locks.
The existing `nil` result on native search failures is preserved. Both Nix lock
files pin the published fork revision.

This lets mobs search the same loaded map concurrently. It does not speed up A*
itself or remove the pauses caused by loading an ADT. Each worker adds about
2.66 MiB of scratch at the existing 65,535-node capacity: about 32 MiB for twelve
workers, shared across their map queries rather than allocated per mob.

The native audit and synchronization contract are in Namigator's
[THREADING.md](https://github.com/pikdum/namigator/blob/80ee2a1/THREADING.md).
The older serial API remains available; its search scratch still needs exclusive
access. An area-name lookup that could secretly insert into a shared table now
performs a read-only lookup.

### Measurements

On the Ryzen 5 5600X, twelve dirty CPU schedulers, warm maps, 500 callers per
burst, and the saved moving-target traces from `wip/bend2`:

| Workload | Original NIF | Concurrent production NIF |
| --- | ---: | ---: |
| Northshire | 15.9 ms | 5.7 ms |
| Deadmines corridor | 71.2 ms | 8.9 ms |
| Deadmines long routes | 307.9 ms | 32.1 ms |

These are median burst times over fifteen frames, following five warmup frames.
Three measured rounds alternate implementation order. The new side includes
the public native-module map lookup; both return complete paths. Neither side
includes cold loading or the rest of the game server. The experiments and saved
traces remain on `wip/bend2`; production does not depend on them.

### Validation

- All 150,000 recorded queries retain their original path hashes and reachability.
  A further 30,000 comparisons check full coordinate lists for both slope filters.
  The known 89 Deadmines failures remain identical at this commit.
- ThreadSanitizer finds no races in eight readers across two maps, including
  random queries, geometry queries, and twelve unload/reload transitions. An
  intentionally unsafe shared-scratch control triggers the expected race report.
- Namigator smoke tests pass against maps built from the bundled test archive.
- The production NIF has integration tests for repeated concurrent queries,
  switching maps, and unload/reload while readers are active.
- `mix compile --warnings-as-errors`, `mix test.all` (3,140 tests), and
  `mix credo --strict` pass using the pinned Nix source.

The full suite also exposed a pre-existing test-order dependency in the spell
reflection fixture. Its VMangos assertion now lives in the VMangos test that
explicitly loads that data, rather than depending on another test running first.

Queries still need the shared lock to keep tiles and their links alive. A loaded
tile check does not pin that tile across subsequent calls, and loading still
pauses readers. The tests do not establish writer fairness under unbounded load
or NIF hot-unloading safety.

## Deadmines endpoint ambiguity

Namigator commit `185394d` fixes the reproduced Deadmines failure without rebuilding
maps. A mob near `(-192.037, -592.948, 39.148)` could have a valid route, move a
fraction of a yard, then lose it. The nearest-surface lookup selected a disconnected
polygon overlapping the connected floor. Both polygons scored equally under
Detour's one-yard climb allowance.

Choosing the physically closest polygon everywhere was insufficient: it recovered
the 89 failures but broke seven other queries. At measured ground height the wrong
polygon can even be closer. The shipped policy therefore preserves successful
searches and, only after an incomplete search, tries a bounded set of equally
scored endpoint surfaces. It accepts only a complete graph route. The existing
search radius, slope rules, and final height correction remain in force.

There are at most four candidate polygons per endpoint and sixteen extra searches.
Node/buffer exhaustion stops the retry. The normal successful path incurs no extra
candidate search. This is an explicit ambiguity policy for the approximate mesh,
not a repair to its underlying geometry or a guarantee about exact collision.

### Results

- All 89 saved Deadmines failures now succeed. Every previously successful path in
  the 150,000-query replay remains coordinate-for-coordinate identical.
- Rerunning the moving-target simulation with the new returned paths produces
  zero failed queries: 500 mobs × 100 frames in each of three scenarios.
- Four focused simulations, including the measured ground position, repeatedly
  replan and advance 0.3 yards until within 1.5 yards of the requested destination.
  The height tolerance accommodates the existing final ground correction.
- Synthetic native tests, 40 real bidirectional/filter regression cases,
  Thistle Tea movement/path fixtures, smoke tests, and sanitizer checks pass.
- Final integration validation uses the published `185394d` Nix source:
  compilation with warnings as errors, all 3,144 tests, and strict Credo.

### What remains wrong in caves

The same comparison checked every ordered pair among selected creature spawns in
RFC and the Elwynn mine areas, with strict and steep-permitted movement. All 53,680
results were unchanged, including existing failures. Counts below are per filter;
both filters produced the same reachability in this sample.

| Area | Successful pairs | Total pairs |
| --- | ---: | ---: |
| Fargodeep | 3,660 | 3,660 |
| Jasperlode | 1,260 | 1,332 |
| Echo Ridge area | 2,340 | 4,556 |
| RFC | 14,852 | 17,292 |

These are generated-map queries between database spawn coordinates, not a claim
that every pair ought to be reachable. The failures nevertheless provide concrete
investigation targets:

- RFC: `(-157.268,-21.7249,-57.2708)` → `(-244.743,150.085,-18.7494)`.
- Echo Ridge: `(-8530.41,-200.263,83.8498)` → `(-8671.72,-124.325,92.6409)`.
- Jasperlode: `(-9326.82,-713.03,67.5269)` → `(-9256.46,-711.838,62.856)`.

Each example selects a unique nearest surface at both ends, in different mesh
components, even with steep traversal enabled. The broad Jasperlode diagnostic
also exhausts its node pool searching the large outside component. The Deadmines
ambiguity retry cannot supply missing graph connections.

Namigator's updated `MapDiag --allow-steep --path=...` prints tied endpoint
candidates and separates the legacy endpoint search from the final query result.
The detailed explanation and reproduction commands are in
[NAVIGATION.md](https://github.com/pikdum/namigator/blob/185394d/NAVIGATION.md).

The next useful cave investigation is at the bake: inspect compact-heightfield
connections and polygon boundaries around these specific breaks, and rebuild a
small area separately. This work has not identified which earlier baking commit
caused them. Raising the climb limit globally could reconnect regions while also
reintroducing paths onto cave ceilings, so that needs geometry-level evidence.
