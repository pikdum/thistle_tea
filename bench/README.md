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
