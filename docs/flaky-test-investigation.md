# Flaky test investigation

The failures recorded during Polymorph acceptance had three distinct causes.
No database or assertion timeout was increased to address them.

## Cell activation

The injected cell loader sent `{:loaded, cell}` to the test before returning.
The owner records a completed cell only after receiving the worker's monitor
`:DOWN` message. Receiving the worker's notification therefore did not prove
that the owner's loaded-cell set included that cell. Sweeping immediately could
deactivate completed neighboring cells first, producing the partial set seen in
the failing assertion.

The sweep tests now wait for the owner to record the specific loaded cell before
testing completed-cell cleanup. This waits for a condition, rather than assuming
that a fixed delay is sufficient.

Investigation also exposed a production lifecycle gap: invalidation killed
running workers but retained only completed cells in the orphan cleanup set.
A worker can spawn entities before it finishes, so those partial loads must also
remain eligible for cleanup. Invalidation now retains both completed and running
cells, while discarding cells that were only queued.

The regression test blocks a worker, queues a second cell, invalidates, observes
the worker's termination, and sweeps. It requires cleanup of exactly the started
cell and verifies that the cell can be activated again. This controlled sequence
failed before the fix; it does not depend on winning a scheduling race.

## Game events

The fixture constructed a real wall-clock event that had already been active
for one second out of a two-second window. Recurrence calculations use whole
seconds, so the remaining time could be substantially less than one second.
If startup crossed that boundary, there was no initial active-event notification
to receive. Increasing the assertion timeout would not recover that notification.

The test now uses the existing injectable clock. It holds the event inside its
active window while checking startup and status, then advances to the exact
transition. The real process timer still delivers the transition, but scheduler
delays cannot invalidate the fixture before its assertions run.

## Fishing data

`Loot.load_fishing/0` delegated to `load_all/0`, and the fishing test module called
it before every test, including trainer and skill-level tests. The timeout logs
showed Exqlite fetching the entire creature-loot table, not waiting for a fishing
query or reporting a SQLite lock.

The local seed contains 227,235 creature-loot rows, 13,804 game-object-loot rows,
2,484 fishing rows, and 9,976 reference rows. The repeated full preload was
unnecessary. Under the simultaneous client/server load, fetching creature rows
exceeded the default 15-second database checkout deadline.

Fishing preload now loads fishing rows and follows only their reachable loot
references, with a visited set to handle cycles. It preloads the associated
items and conditions, caches missing references, and leaves the full-preload
marker unchanged. Skill and trainer tests no longer preload unrelated loot.
The skill and loot cases carry the VMangos tag independently of the DBC trainer
case, so they run in the VMangos CI phase.

The fishing regression checks that preload queries exclude creature/game-object
loot, that fishing items are cached, that area and zone fallback produce actual
catches, and that catch generation issues no further Mangos queries. A focused
run completed the fishing case in 118.6 ms.

The ExUnit ETS errors at the end of the interrupted earlier log occurred during
termination of that test run; they were not additional independently observed
test failures.

## Validation

- The controlled invalidation test failed before the owner fix and passes after it.
- Cell/game-event tests passed 101 consecutive runs with a single Erlang scheduler:
  `ERL_FLAGS='+S 1:1' mix test test/game/world/system/cell_activator_test.exs test/game/world/system/game_event_test.exs --repeat-until-failure 100`.
- The VMangos fishing cases passed 21 consecutive runs with
  `mix test test/game/world/loader/fishing_integration_test.exs --only vmangos_db --repeat-until-failure 20`.
- `mix test.all --seed 287354` and `mix test.all --seed 600776` each passed all
  2,842 tests. These are the seeds from the two earlier failing full runs.
- The separate CI-style `mix test --only vmangos_db` phase passed 69 tests.
- Strict Credo, compilation with warnings treated as errors, formatting, and
  diff checks passed.

Logs are retained under `/tmp/thistle-flakes-`: `cell-before.log`,
`single-scheduler.log`, `fishing-stress.log`, `fishing.log`, `all.log`,
`final-all.log`, `vmangos-phase.log`, `final-credo.log`, and `final-compile.log`.
