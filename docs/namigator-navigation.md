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
