# Spatial grid benchmark

This harness compares spatial-hash cell sizes against the same deterministic workload built from the VMangos creature spawn corpus. It measures exact projected-position query batches and spatial publication batches, then reports the metrics needed to interpret the timings:

- average broad-phase candidates by query radius;
- percentage of relocations crossing a cell boundary;
- the safety margin implied by each cell size;
- the available projection horizon at 70 yards per second.

Generate `db/vmangos.sqlite` first if it is absent, then run:

```console
nix run .#vmangos-db
MIX_ENV=bench mix run --no-start bench/spatial_grid.exs
```

The defaults compare 32, 48, 64, 96, 125, 160, and 250-yard cells using creature spawns from maps 0 and 1. Each Benchee invocation contains 256 queries or 1,024 relocations, so compare timings only within the same invocation type.

The workload can be adjusted with environment variables:

| Variable | Default | Meaning |
| --- | ---: | --- |
| `SPATIAL_BENCH_CELL_SIZES` | `32,48,64,96,125,160,250` | Candidate cell sizes in yards |
| `SPATIAL_BENCH_QUERY_RADII` | `2,10,30,60,100,250` | Exact query radii in yards |
| `SPATIAL_BENCH_MAPS` | `0,1` | VMangos map IDs included in the corpus |
| `SPATIAL_BENCH_ENTITY_LIMIT` | unset | Optional deterministic spawn limit for quick runs |
| `SPATIAL_BENCH_QUERY_COUNT` | `256` | Queries per measured invocation |
| `SPATIAL_BENCH_RELOCATION_COUNT` | `1024` | Relocations per measured invocation |
| `SPATIAL_BENCH_PROJECTED_PERCENT` | `30` | Percentage of entities with projected positions |
| `SPATIAL_BENCH_PROJECTION_DRIFT` | `10` | Projected displacement in yards |
| `SPATIAL_BENCH_RELOCATION_DISTANCE` | `7` | Distance of each alternating relocation in yards |
| `SPATIAL_BENCH_TIME` | `1` | Benchee measurement time per scenario |
| `SPATIAL_BENCH_WARMUP` | `0.5` | Benchee warmup time per scenario |

For a quick smoke run:

```console
SPATIAL_BENCH_CELL_SIZES=64,125 \
SPATIAL_BENCH_QUERY_RADII=10,30 \
SPATIAL_BENCH_ENTITY_LIMIT=10000 \
SPATIAL_BENCH_QUERY_COUNT=32 \
SPATIAL_BENCH_RELOCATION_COUNT=128 \
SPATIAL_BENCH_TIME=0.1 \
SPATIAL_BENCH_WARMUP=0 \
MIX_ENV=bench mix run --no-start bench/spatial_grid.exs
```

Cell size should be selected from the complete profile, not query throughput alone. Smaller cells generally reduce candidates but increase membership churn and may shorten the bounded high-speed projection horizon.

# Hot path benchmarks

This harness times the per-tick and per-recipient work that scales with population, using synthetic fixtures so it needs no generated database:

- `update_object`: SMSG_UPDATE_OBJECT encoding for mob and player values/create blocks, for the owner and for another player, plus `Network.Send.compress/1` on the resulting packets;
- `movement`: `Math.distance/2`, `Math.movement_duration/2`, and `Movement.position_at/4` on active and finished splines;
- `spatial`: `World.position/2` across every mob and exact 30-yard `World.nearby_units_exact/5` queries over a populated `SpatialHash`.

```console
MIX_ENV=bench mix run --no-start bench/hot_paths.exs
```

Update fixtures fill every update field a component declares, so they measure the largest block each object type can produce; real entities leave many fields nil and encode faster.

| Variable | Default | Meaning |
| --- | ---: | --- |
| `HOT_PATHS_GROUPS` | `update_object,movement,spatial` | Groups to run |
| `HOT_PATHS_ENTITIES` | `600` | Mobs inserted for the spatial group |
| `HOT_PATHS_SPACING` | `4.0` | Grid spacing between spatial mobs in yards |
| `HOT_PATHS_MOVING_PERCENT` | `30` | Percentage of spatial mobs on active splines |
| `HOT_PATHS_TIME` | `2` | Benchee measurement time per scenario |
| `HOT_PATHS_WARMUP` | `0.5` | Benchee warmup time per scenario |
| `HOT_PATHS_MEMORY_TIME` | `0.5` | Benchee memory measurement time per scenario |

Compare runs on the same machine and commit range; the dev environment does not consolidate protocols, so profile a running dev server only for relative weight, not absolute Enumerable cost.

# Population workload

The population harness runs the production player, mob, and pet processes,
visibility subscriptions, behavior trees, packet batching, encoding, compression,
and header encryption. It creates synthetic copies of Programmer Isle and
places each cohort in the same coordinates to check visibility isolation.
Fixture relocation uses the normal presence and visibility funnels inside the
owner process; these copies do not exercise instance admission or persistence.
Players are level 60 rogues with invulnerability enabled, creatures are level 50,
and a configurable fraction of players receive an Imp guardian. Each scenario
starts a fresh population and cleans up its owners afterwards.

```console
MIX_ENV=bench mix run bench/population.exs
```

The default workload uses 12 players, 80 mobs, two copies, 25% pets, a one-second
warmup and five seconds of measurement for each of `idle,movement,combat,stealth`.
Movement inputs follow the same trajectory at a target of 10 batches per second.
Inputs are synchronous and completion paced: an overloaded batch lowers the
achieved input rate. Compare the packet count and elapsed time against the target
rate; this is not a fixed-arrival-rate capacity test. Combat enables hostile
creatures and starts melee through client input. Stealth casts the real spell
before measurement, then moves the rogues through one another's detection range.

The connection sink discards successful writes after the real network send path.
Wire bytes include compressed payloads and headers, but do not measure TCP,
kernel backpressure, or an actual client's rendering. Whole-VM telemetry includes
normal server background work; owner reductions, GC, memory and mailbox samples
cover only the benchmark population and its connection sinks.

Reports include histogram p95/p99 upper bounds in microseconds, successful wire
bytes, reductions and GC, sampled queue peaks, owner counts, timer counts, and
copy isolation. Histograms use powers-of-two buckets: a reported 4096us means the
quantile is no higher than 4096us, rather than an exact 4.096ms observation. Queue
peaks are sampled every input interval and can miss shorter bursts. Timer counts
are snapshots taken outside the measured interval. A stopped owner or visibility
leak fails the run.

All numeric options use the `POPULATION_BENCH_` prefix:

| Suffix | Default | Meaning |
| --- | ---: | --- |
| `PLAYERS` | 12 | Player owners |
| `MOBS` | 80 | Creature owners, excluding pets and normal server spawns |
| `COPIES` | 2 | Synthetic isolated worlds |
| `PET_PERCENT` | 25 | Deterministic fraction receiving guardians |
| `DURATION_MS` | 5000 | Measurement window per scenario |
| `WARMUP_MS` | 1000 | Warmup per scenario |
| `INTERVAL_MS` | 100 | Target interval between input batches |

`POPULATION_BENCH_SCENARIOS` selects comma-separated scenarios and
`POPULATION_BENCH_OUTPUT` selects the JSON report path (default
`/tmp/thistle-population.json`). Positive counts and intervals are required;
use `PET_PERCENT=0` to omit pets.

For diagnostic function timing, set `POPULATION_BENCH_PROFILE` to one scenario.
This runs eprof on the population owners and prints its table. If the development
Erlang excludes tools from its code path, set `POPULATION_BENCH_ERLANG_TOOLS` to the
`tools-*/ebin` directory from the matching Erlang package. Profiled runs carry a
`profiled: true` marker and should not be compared with ordinary latency runs.

To sample a running server without resetting counters:

```elixir
before = ThistleTea.Telemetry.checkpoint()
ThistleTea.Telemetry.report(before)
ThistleTea.Telemetry.Runtime.owners([player_pid, mob_pid])
```

The collector owns its telemetry subscriptions, so supervision restarts reattach
them. Storage grows with the finite metric labels, rather than the event count.
