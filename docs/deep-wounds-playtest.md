# Deep Wounds acceptance

Deep Wounds' three passive talent ranks already emitted their critical-hit
triggers, but the triggered dummy spells had no handler. They now snapshot
weapon damage and trigger the real bleed through the shared spell resolver and
aura lifecycle.

## Rules and reference

Reference: `refs/vmangos` revision
`8f4e608450460efe1e38743e4da74397d4773a3a`,
`SpellEffects.cpp::EffectDummy`, cases 12162, 12850, and 12868.

| Talent | Trigger | Total weapon-damage percentage |
| --- | --- | --- |
| 12834 | 12162 | 20% |
| 12849 | 12850 | 40% |
| 12867 | 12868 | 60% |

The average damage includes attack power, flat damage bonuses, and applicable
weapon damage multipliers. Swing procs retain the hand that dealt the critical
hit, including queued attacks such as Heroic Strike. VMangos resolves those
procs before resetting the swing timer; this server receives defender feedback
after resetting it, so comparing the new deadlines would select the wrong hand.
The typed trigger retains the hand through owner routing.

For other ability procs, the local reference's timer comparison selects an
equipped, usable off-hand when its remaining swing delay is shorter. Unset and
expired timers both have zero remaining delay, including with negative monotonic
timestamps. Ties use the main hand. The shared off-hand damage calculation
includes its normal penalty. Each tick is the truncated total divided by four.

Spell 12721 supplies the bleed's twelve-second duration and three-second
cadence. It uses normal periodic damage, threat, packet feedback, immunity,
replacement, and death cleanup. A fresh proc replaces the previous bleed;
it does not accumulate Ignite-style stacks. A dead recipient or missing damage
snapshot cannot create a new bleed.

VMangos stores the critical-only proc restriction on talent 12834. The existing
DBC talent lineage supplies inheritance for ranks two and three. Tests keep the
VMangos rule lookup separate from the DBC chain and combat checks.

## Automated validation

- `mix test.all`: 6,392 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,351 source files.
- Focused checks cover all ranks, attack-power and weapon bonuses, off-hand
  selection and broken equipment, delayed hand feedback, unset and expired
  deadlines, immutable damage snapshots, critical swings
  and abilities, owner routing, four armor-ignoring ticks, refresh, bleed
  immunity, expiry, and death cleanup.

## Native acceptance

Validated on 2026-09-26 with native build 5875, implementation `ff51945f` and
hand-selection correction `50e33895`. All gameplay actions used the client;
Tidewave probes only observed entity state.

Debugwarrior (GUID 1, level 50) learned rank three (12867), entered Berserker
Stance, and used Recklessness. With Dawn's Edge and a shield equipped, the final
fresh-server damage range was 125.6–172.6, giving `trunc(149.1 * 0.6 / 4) = 22`
damage per tick.

The warrior attacked the seeded Defias Evoker (entry 1729, spawn 992300) at
`{16390.2, 16258.1, 69.995}` on Programmer Isle. A critical hit reduced the
evoker from 1062 to 798 health and applied spell 12721 with one stack, caster
GUID 1, twelve-second duration, and three-second ticks. After clearing the target
to stop autoattack and selecting it again, health changed
`798 → 776 → 754 → 732 → 710`; the fourth tick also removed the bleed. The client
showed the debuff and all four 22-damage combat messages. A small client Lua event
listener copied the client's actual periodic-damage messages into its chat
frame for the screenshots.

The initial session targeted a Skeletal Flayer, which correctly rejected the
bleed: its creature mechanic-immunity mask includes bleed immunity. No gameplay
state or proc chance was changed through a runtime probe.

For dual-wield acceptance, the warrior equipped a second Dawn's Edge through
the client and fought the seeded level-55 Devilsaur (entry 6498, spawn 990200).
The warrior was raised to level 55 and trained weapon skill to 275 through the
existing debug commands. At level 50, the target's avoidance and glancing-blow
table had crowded out dual-wield critical swings. Its knockbacks also required
repositioning and restarting attacks before the final sample.

The final main-hand range was 128.75–175.75, and the off-hand range was
64.375–87.875 after its normal penalty. Main-hand crits produced 22-damage
ticks while dual-wielding. An off-hand crit applied an 11-damage bleed at
4944 target health; one subsequent main-hand swing landed before autoattack
stopped, leaving 4858 health. The bleed then ticked
`4858 → 4847 → 4836 → 4825 → 4814` and expired. The client displayed all four
11-damage messages and removed the debuff icon. The owner retained no bleed
and the player had autoattack disabled.

## Evidence

The final client session is
`/home/pikdum/.cache/thistle-wow-playtest.4Wttxt`. Screenshots include
`final-bleed-visible`, `final-bleed-expiry`, `final-offhand-visible`, and
`final-offhand-expiry`. WoW PID 1348372 used `amdgpu`; its graphics-engine counter
increased from 417,359,858 to 24,783,949,652 ns.

The fresh-server log is `/tmp/thistle-deep-wounds-final-server.log`. It contains
the real casts and attacks without owner errors or failed spell validation.
Existing account-data, GM-ticket, and meeting-stone login warnings remain.
State evidence is in `/tmp/thistle-deep-wounds-final-{gear,first,watch}.txt`,
`/tmp/thistle-deep-wounds-dual-{gear-final,combat-watch,offhand-first,offhand-watch,expiry}.txt`,
and `/tmp/thistle-deep-wounds-final-gpu-{before,after}.txt`.

The earlier session `/home/pikdum/.cache/thistle-wow-playtest.rjkzIc` retains
the bleed-immunity investigation and initial Evoker acceptance. After that
client disconnected, a Tidewave cleanup probe recompiled edited modules and
the old server logged transient missing-module errors. Final acceptance used
the fresh server above with no source edits during the session.

The warrior logged out through the client. Its entity process, metadata, and
world position were absent afterward (`/tmp/thistle-deep-wounds-final-cleanup.txt`).
Both helper-owned client services were stopped and confirmed inactive, with
their artifacts retained. The final local server was stopped as well.
