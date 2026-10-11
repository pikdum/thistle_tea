# Server optimization experiments

Measured on 2026-10-11 against `9f26c3c5`, after the Firelord overload
investigation. These experiments use fixed populations rather than recurring
summons. Each server runs in an owned four-GiB cgroup with swap disabled and
four Erlang schedulers. Measurements run sequentially on the same machine.

## Changes retained

An AI observation previously read a target's movement projection three times,
computed its position twice, and reloaded its full metadata for grounding and
recent movement. `Position.snapshot/2` now captures position and motion from
one movement record. `World.position_snapshot/3` reuses the observation's
fresh metadata for airborne grounding and the recent-movement deadline. The
perception remains immutable and is rebuilt for each context; it introduces
no cache across ticks.

`Metadata.update/3` skips the compare-and-swap write when merging the owner's
publication leaves the row exactly unchanged. Changed rows retain the
existing retry loop. Exact comparison preserves changes between integers
and floats. The concurrent counter/owner regression remains in the suite.

The population fixture now completes the intro cinematic after selecting
its active mover. Otherwise the cinematic camera can leave the relocated
player with empty visibility and invalidate the benchmark. The runner also
starts its application explicitly, allowing baseline modules to be loaded
before any entity owners start.

## Measurements

The combat eprof run identified ETS lookup as the largest individual entry
(9% of profiled time), with substantial list processing around proximity
events. Profiling changes timings; those measurements are only used to
choose experiments.

The spatial hot-path workload uses 600 mobs, 30% on two-node splines, with
synthetic twenty-field metadata. Both observation variants consume the same
position, grounded position, and motion information. Benchee reports bytes
allocated by an invocation, rather than retained VM memory.

The production-owner comparison uses twelve players, 320 mobs, three pets,
two copies, three seconds of warmup, and ten seconds of combat. Baseline
modules come directly from `9f26c3c5` and are compiled before application
startup. The same repaired fixture is used for both variants. Repeat order
is baseline, optimized, optimized, baseline.

The actor experiment sets `message_queue_data` to `off_heap` only on the
fixture's owners and connection sinks. The benchmark exposes this as
`POPULATION_BENCH_MESSAGE_QUEUE_DATA`; production defaults remain unchanged.

| Direct work per 600 mobs | Before | After |
| --- | ---: | ---: |
| Motion observation mean | 983.14 us | 400.53 us |
| Motion observation allocated memory | 1,766.08 KB | 699.13 KB |
| Unchanged publication mean | 1,200 us | 182.75 us |
| Unchanged publication allocated memory | 633.50 KB | 475.71 KB |

Observation time fell 59% and allocation fell 60%. Avoiding unchanged writes
cut publication time about 85% and allocation about 25%. Publication baseline
uses the original `Metadata` module with the same hot-path harness. The
rounded baseline timing comes from Benchee's millisecond display.

| Dense combat, two fresh runs | Before | After |
| --- | ---: | ---: |
| Mean running AI tick | 858–870 us | 823–826 us |
| Mean packet handling | 1,438–1,471 us | 1,438–1,460 us |
| Owner memory at end | 541–582 MB | 505–509 MB |
| Sampled queue peak | 16–17 messages | 16–19 messages |

Mean running AI time improved about 5%; the sampled owner heaps averaged
about 10% smaller. Packet handling stayed broadly unchanged. Each run retained
all 347 fixture processes, processed 1,188–1,200 movement inputs, drained the
sampled queues, and passed copy isolation. Raw population reports are in
[server-optimization.json](../bench/results/server-optimization.json).

The one off-heap mailbox run ended at 506 MB of owner memory, with mean
packet handling 1,440 us, running AI 799 us, and sampled queue peak 17. It
retained all owners and passed isolation, but did not establish a clear
memory or packet-latency improvement over the optimized default. Its active
AI and packet counts differ from the other runs. Production mailbox defaults
are left alone; the fixture option supports future controlled burst tests.

## Reproduction

```console
ERL_FLAGS='+S 4:4' MIX_ENV=bench HOT_PATHS_GROUPS=spatial \
  devenv shell mix run --no-start bench/hot_paths.exs

ERL_FLAGS='+S 4:4' MIX_ENV=bench \
  POPULATION_BENCH_PLAYERS=12 POPULATION_BENCH_MOBS=320 \
  POPULATION_BENCH_COPIES=2 POPULATION_BENCH_WARMUP_MS=3000 \
  POPULATION_BENCH_DURATION_MS=10000 POPULATION_BENCH_SCENARIOS=combat \
  devenv shell mix run bench/population.exs
```

Add `POPULATION_BENCH_MESSAGE_QUEUE_DATA=off_heap` to repeat the actor
experiment. Wrap server runs in `systemd-run --user --scope` with
`-p MemoryMax=4G -p MemorySwapMax=0` to retain the investigation's hard bound.

The population harness uses completion-paced input and a connection sink.
It checks owner survival, queue drainage, and copy isolation, but does not
measure real TCP backpressure or client rendering. AI choices are random,
so packet counts and active tick counts can vary between repeats. Heap
snapshots also depend on garbage collection; allocation improvements must
not be presented as an identical reduction in whole-server memory.

These changes reduce repeated work without changing AI deadlines or creature
mechanics. They do not bound exponential summon populations. Dense proximity
fanout, perception construction, navigation, and packet delivery still scale
with nearby activity.

## Verification

- `devenv shell mix test.all`: 8,859 passed, including airborne grounding,
  falling and legacy splines, client-motion expiry, immutable perception,
  numeric metadata types, and concurrent counter/owner publication.
- Compilation with warnings as errors, strict Credo, formatting, and
  `git diff --check` passed.
- Separate 320-mob idle, movement, combat, and stealth scenarios each retained
  all 347 fixture processes, drained their queues, and passed copy isolation.
  Their raw reports are included in the results file.

All experiment servers and their owned scopes exited. No native client or
screenshots were used in these experiments.
