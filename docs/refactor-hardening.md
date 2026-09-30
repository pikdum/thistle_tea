# Refactor and performance hardening

Validated locally on 2026-09-30. The recent refactor has useful, enforced
boundaries: pure rules, entity owners, loaders, inbound messages, and packet
encoders. The follow-up work closes missed notifications and lifecycle races,
provides bounded measurement, and establishes a repeatable population workload.

## Changes

- Proximity announcements now watch every published stealth/detection input,
  including stationary detection bonuses and caster-specific marks. A regression
  compares the watch keys with the metadata projection itself.
- Each owner holds one pending contact check per target and role. Duplicate
  announcements coalesce; replacement, departure, and death cancel work.
  Delivered callbacks must match their timer reference, world, movement path,
  process, and creature incarnation. A respawn in the same process cannot consume
  an old contact check.
- Quest refresh watches come from the visible quests' condition requirements.
  Learning, health, aura, group, and other owner inputs use a cheap fingerprint;
  saved variables use targeted Group subscriptions; local-time conditions use
  their next boundary. Scripted-event data and target changes publish world facts.
  Inventory continues through its existing refresh funnel.
- Player wake scheduling now has one scheduler and reference-bearing callbacks.
  A previously delivered callback cannot tick a replacement schedule.
- Telemetry stores fixed-size cumulative histograms and counters instead of raw
  samples. Checkpoint reports do not delete concurrent measurements. Quantiles
  are bucket upper bounds; successful wire bytes, failures, owner queues, GC,
  reductions, and timer activity have distinct measurements. The supervised
  collector owns and restores its event subscriptions.
- Proc chance, loot rolls, and cast pushback accept named rolls. The ambient
  randomness allowlist shrank from 23 files to 20. No architecture allowance grew.
- The [population harness](../bench/README.md#population-workload) exercises the
  actual owners, behavior trees, visibility, input handling, and packet send path.

## Population measurements

These are local, completion-paced workloads, not a server capacity claim.
Connections discard writes after encoding, compression, and encryption; they
do not measure TCP backpressure or client rendering. Worlds are synthetic copies
of Programmer Isle, so instance admission is outside this harness. Queue peaks
are sampled, not continuous. Background server work is included in whole-VM
metrics; scoped owner measurements are reported separately.

The saved reports record the then-current Git HEAD (`045a9de5`) while the harness
was still uncommitted. The harness was subsequently committed as `8f6d8485`.
Do not interpret that HEAD field as a pristine release checkout or a before/after
performance comparison. Measurements used Elixir 1.20.3, OTP 29, and 12 schedulers.

| Population and scenario | Movement inputs / elapsed | Input p99 upper bound | Running AI p99 upper bound | Sampled queue peak | Wire bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 12 players, 80 mobs, 3 pets, 2 copies: movement | 1,200 / 10.104 s | 4.096 ms | 8.192 ms | 1 | 429,085 |
| Same population: combat | 1,188 / 10.003 s | 4.096 ms | 4.096 ms | 58 | 1,152,732 |
| Same population: first stealth run | 1,104 / 10.096 s | 16.384 ms | 262.144 ms | 12 | 239,685 |
| Same population: fresh stealth repeat | 1,200 / 10.103 s | 4.096 ms | 8.192 ms | 11 | 283,949 |
| 48 players, 300 mobs, 11 pets, 4 copies: movement | 2,880 / 6.068 s | 4.096 ms | 8.192 ms | 12 | 2,040,692 |
| Same larger population: combat | 2,880 / 6.069 s | 4.096 ms | 8.192 ms | 15 | 2,765,194 |
| Same larger population: stealth | 2,880 / 6.072 s | 4.096 ms | 16.384 ms | 4 | 1,269,206 |

All final sampled mailboxes were empty, all scoped owners survived, and every
copy-isolation assertion passed. The idle baseline retained three pet ticks and
12 player maintenance timers; the 80 dormant creatures had no tick timers.
Pending contact checks were zero at each final timer snapshot. Active combat
retained ordinary AI schedules, rather than requiring all creature timers to end.

The first stealth run's long tail is retained as an unresolved observation.
It did not reproduce in a fresh 10-second run or the larger population. A short
eprof diagnostic put ETS lookup and line of sight among the largest aggregate
costs, but did not establish the cause of that tail. Profiled latency is not
directly comparable with ordinary runs. Further performance changes should
start by reproducing this observation over longer windows.

Raw reports:

- [Baseline](../bench/results/hardening-baseline.json)
- [Larger population](../bench/results/hardening-stress.json)
- [Fresh stealth repeat](../bench/results/hardening-stealth-repeat.json)

## Native client acceptance

Two isolated GPU-rendered build-5875 clients exercised Debugrogue (GUID 3) and
Debugbuyer (GUID 10) on map 451. Screenshots and owner probes were correlated;
the clients and server were stopped after acceptance.

1. A temporary cached quest fixture required Fireball and saved variable 700001.
   The rogue learned Fireball through the existing developer command. Opening
   the variable gate displayed the yellow quest icon while both players remained
   stationary; the observer remained ineligible. The fixture was needed because
   the current quest corpus does not exercise this combination of conditions.
2. At 20 yards, the observer could not see the stealthed rogue. Casting the real
   human Perception racial added 50 detection, revealed the rogue without
   movement, and hid it again when the aura expired. A 500 ms owner sampler
   recorded the detection and visibility transitions at unchanged positions.
3. A spawned Defias Thug received Perception through the normal triggered-spell
   path. It acquired the stationary rogue and entered combat before either
   position changed. Incoming damage broke stealth and eventually killed the
   rogue. Release cleared pending contacts. Real movement to the Spirit Healer
   and the resurrection dialog restored the character.
4. After resurrection, god mode prevented another death during attack acceptance.
   Client auto-attack and Sinister Strike reduced the creature from 2,215 to
   2,155 health and spent energy. The owner retained a live player tick schedule.
5. Logout removed the rogue's owner, metadata, and spatial position. Reconnect
   created a new owner, retained Fireball, restored the variable subscription,
   and projected quest status 5 then 0 as the gate opened and closed. No pending
   contacts survived. Stopping both clients removed both owners and all members
   of `server_variable/700001`.

Spell unlearning, local-time boundaries, stale callbacks, same-process respawn,
and concurrent telemetry writers have automated regressions. Live acceptance
does not claim to exercise every condition type or real instance admission.
The server log contained no error or owner-termination entries. Existing
unimplemented account-data and GM-ticket packets emitted warnings.

Local evidence is retained in
`/home/pikdum/.cache/thistle-wow-playtest.NfKjTU/screenshots/` and
`/home/pikdum/.cache/thistle-wow-playtest.hW63B0/screenshots/`, with owner probes
under `/tmp/thistle-hardening-*.txt` and the server log at
`/tmp/thistle-hardening-server.log`. Representative captures are
`quest-eligible.png`, `stealth-hidden.png`, `perception-revealed.png`,
`stationary-detection-combat.png`, `resurrection-prompt.png`,
`combat-restored.png`, and `reconnect-quest-{eligible,ineligible}.png`.

## Validation and next work

The completion gates are `mix test.all`, `mix compile --warnings-as-errors`, and
`mix credo --strict`. Focused regressions additionally cover notification keys,
quest conditions and subscriptions, timer ownership, named rolls, bounded
histograms, wire accounting, and collector restart.

Resume a coherent gameplay feature after these gates pass. Keep the population
harness as a regression check and investigate the stealth tail if it recurs.
Further broad module splitting or speculative optimization has less value than
shipping behavior through the existing boundaries and measuring its cost.
