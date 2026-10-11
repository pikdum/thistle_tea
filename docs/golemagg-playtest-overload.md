# Firelord summon overload investigation

Investigated on 2026-10-11 after completing Golemagg's Trust acceptance.

## Confirmed failure

The earlier interrupted playtest was an actual BEAM OOM, separate from the
Codex image-history problem. The kernel killed BEAM PID 191327 on 2026-10-10
at 21:06:11 local time with anonymous RSS 19,183,040 KiB. Its last telemetry
reported 17,053,439,584 bytes of runtime memory, 3,165 mobs, and run queue
1,574. That historical snapshot alone cannot identify the original allocation
path.

A fresh native Trust acceptance ran for 224 seconds with two Molten Core
copies and no runaway growth. Memory declined from approximately 2.98 GB to
1.45 GB while the boss continued refreshing Trust. After saving acceptance,
the existing boundary damage API engaged a Firelord against the headless
god-mode player in copy 3. That reproduced growing mob population, process
memory, queued work, and CPU saturation independently of Trust recipients.

Lava Spawn population reached 1, 5, 23, 79, 101, and 136 in successive retained
samples. Later observation found 272. Runtime memory initially rose from
1.47 GB to 1.95 GB, then sharply to 18.87 GB; shutdown telemetry recorded
21.22 GB and run queue 1,804. Of the 18.87 GB sample, 18.00 GB was process
memory, while ETS used 351 MB and reference-counted binaries used 152 MB.
The headless player owner had 18,029 queued messages. This was population
and work overload, rather than growth of the global spell/data caches.

The cooperative six-GB monitor did not provide a hard bound: under saturated
scheduling its next sample arrived after the threshold had been exceeded.
The server was stopped. Subsequent probes ran in the owned
`thistle-trust-investigation.scope` with a hard four-GiB cgroup memory limit
and a CPU quota of two cores, preventing another whole-host overload.

## Summon lifecycle and reclamation

Current VMangos data provides two Lava Spawn events:

- Event 1226502 repeats every ten seconds in combat, casts Split 19569, and
  announces the split.
- Non-repeatable summoned-unit event 1226503 casts Split 19570 and despawns
  the parent.

Each spell summons one Lava Spawn. The reference non-repeatable event is
disabled before its actions execute in `CreatureEventAI::ProcessEvent`;
the Elixir EventAI implementation follows the same order. Firelord also adds
new first-generation spawns every 15–20 seconds after its initial summon.
An invulnerable target with no damage against the adds permits this living
population to grow exponentially.

A smaller reproduction used one Firelord on Programmer Isle, without a
native client or Golemagg. It reached 45 living Lava Spawns. Removing the
creating Firelord and the exact owned summons through `World.stop_entity/1`
returned runtime memory from 881,679,864 to approximately 825,378,992 bytes
without forcing garbage collection. The sampled summons had roughly
54–59 KB of flattened entity state, no pending script continuations, and
process heaps between approximately 0.4 and 1.8 MB.

The final isolated probe started one fighting Lava Spawn without a recurring
Firelord. It recorded 1, 2, 4, and 8 living summons at approximately 0, 11,
22, and 33 seconds. Each replaced parent owner disappeared. Removing the
remaining eight left zero Lava Spawn owners and 830,969,480 bytes of runtime
memory. This checks the intended split lifecycle separately from the
large-population failure.

The 30.5 MB flattened waypoint catalog in an AI context is shared through
`persistent_term`; that logical flattened size is not a per-owner allocation.
It must not be added to every mob's memory estimate. The sampled perception
portion was 114 KB for 22 observations. The high-population reproduction
showed inflated process heaps and growing delivery queues, while the small
population reclaimed memory after owner removal.

These observations establish a reproducible summon-driven overload. They
do not establish a fixed-population memory leak or prove the exact allocator
history of the original killed process. No gameplay population cap, altered
split mechanic, or speculative memory optimization was introduced. Dense
population scheduling, perception allocation, and outbound queue costs remain
a separate scalability concern; ordinary god-mode playtests must isolate
unrelated Firelords and stop their summons explicitly.

## Evidence

The accepted client session at
`/home/pikdum/.cache/thistle-wow-playtest.qOoOel` retains the acceptance traces
and the separate investigation logs:

- `thistle-golemagg-trust-verified-server.log`
- `thistle-trust-memory-watch.log`
- `thistle-trust-summon-repro.jsonl`
- `thistle-trust-generations.jsonl`
- `thistle-trust-single-generation.jsonl`
- `thistle-trust-generation-summary.json`
- `thistle-trust-context-fields.json`
- `thistle-trust-investigation-server.log`

The kernel evidence for the original failure is retained in
`/home/pikdum/.cache/thistle-wow-playtest.EtdcRa/kernel-oom.txt`.
All owned clients, headless connections, and servers were stopped after
evidence collection.
