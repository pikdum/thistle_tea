# Target-trigger talent acceptance

Aura 109 (`SPELL_AURA_ADD_TARGET_TRIGGER`) now snapshots eligible talent
triggers into the cast context and resolves them at a successful recipient
impact. Triggered spells use the same path, so Improved Blizzard's Chilled
spell can trigger Frostbite. Direct channels roll at their initial impact,
without repeating the cast's roll on every channel tick.

## Reference and behavior

Reference: `refs/vmangos` revision
`8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell.cpp::HandleAddTargetTriggerAuras`, and
[CMaNGOS's aura-owner trigger check](https://github.com/cmangos/mangos-classic/blob/master/src/game/Spells/Spell.cpp#L6846).

Relentless Strikes and Revealed Flaw store zero base chance plus a per-combo-point
chance. The cast retains its original combo points before consumption:
Relentless Strikes gains 20% per point, and Revealed Flaw gains 5% per point.
The loader now applies VMangos class-mask overrides to target-trigger auras;
Revealed Flaw consequently matches Eviscerate rather than every finisher.

The DBC's class-trigger flag belongs to the proc aura. Following CMaNGOS's
explicit aura-owner check, these two talents roll only on the finisher's
caster-side impact. This prevents duplicate rolls from enemy and caster
effects. The local VMangos implementation checks the incoming spell's flag
instead, so that particular conditional was not copied.

Successful hits, including triggered hits and resolved reflections, can proc.
Resisted, immune, and already-dead recipient impacts cannot. Triggered enemy
effects require a living resolved target; a caster-only energy refund still
works when the finishing damage kills the victim. Trigger identity and casting
item survive dispatch. Family-mask matching includes all 64 bits and rejects
missing or zero masks.

## Native client

Session: `/home/pikdum/.cache/thistle-wow-playtest.I1uBW3`, hardware-rendered
build 5875. All learning, movement, and casts used the client. Tidewave probes
were read-only. Characters were level 50 with god mode enabled; energy costs
and regeneration remained active.

### Relentless Strikes

Debugrogue (GUID 3) learned Relentless Strikes 14179. The completed sequence
targeted the seeded Skeletal Flayer, entry 1783, low GUID 990102, at
`{16248.2, 16343.1, 69.44444}` on map 451. The rogue stood at
`{16245.2, 16343.1, 69.44660}`.

Cheap Shot and Sinister Strike built five combo points. The client displayed
the points, then showed `+25 Energy` after Eviscerate. A 100 ms owner sampler
recorded:

| Relative time | Energy | Combo points | Combo target |
| --- | --- | --- | --- |
| 0 ms | 100 | 5 | Skeletal Flayer |
| 2,222 ms | 90 | 0 | Cleared |
| 3,030 ms | 100 | 0 | Cleared |

Eviscerate costs 35 energy: the observed net loss of 10 proves exactly one
25-energy refund. The later increase is ordinary energy regeneration. Earlier
setup attempts were out of range or requested an unavailable spell rank;
neither was counted as acceptance. The completed sequence used the learned
rank through its unqualified spell name.

### Frostbite from Improved Blizzard

Debugmage (GUID 5) learned Improved Blizzard rank 3 (12488) and Frostbite rank
3 (12497). A read confirmed Frostbite's unmodified aura amount of 15. The
mage teleported to `{16375, 16258.1, 75}` on map 451 and settled at height
69.87605, targeting the seeded Defias Evoker, entry 1729, low GUID 992300.
Rank-1 Blizzard was cast through its ground cursor.

The first channel's 100 ms owner sampler recorded:

| Relative time | Authoritative result |
| --- | --- |
| 1 ms | Health 1,062; speed 8.00002; no root. |
| 2,937 ms | Blizzard channel and periodic holder active. |
| 3,975 ms | First 25 damage; Chilled 12486; speed 2.800007. |
| 9,941 ms | Seventh tick; health 887; Frostbite 12494 present; rooted. |
| 10,972 ms | Eighth tick retained; health 862; channel and Blizzard holder gone. |
| 12,427 ms | Chilled expired; speed restored to 8.00002; root still active. |
| 14,928 ms | Frostbite expired; rooted state cleared. |

The ordinary 15% roll succeeded without changing talent amounts or injecting a
trigger. The root survived the final damage tick and expired approximately five
seconds after application. Frost Armor and the evoker's separate Flame Ward
remained independent of the tested effects.

A second channel produced Frostbite after its third tick. A read-only sampler
detected the root at health 787 and immediately captured `frostbite-rooted.png`:
the client showed Chilled and Frostbite icons together, the root's frost
visual, Blizzard damage, and the active channel bar.

## Automated validation

- `mix test.all`: 6,378 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,349 files.
- Regressions cover combo snapshots, aura-owner filtering, family masks,
  successful and rejected impacts, lethal hits, reflected and triggered
  spells, channel repetition, living-target resolution, and real DBC and
  VMangos override data.

Relentless Strikes and Frostbite have native acceptance recorded here.
Revealed Flaw has automated data and probability coverage only.

## Lifecycle and retained evidence

After logout, player owners, world positions, and metadata for GUIDs 3, 5, and
6 were absent. Reconnecting Debugmage restored both talents, including
Frostbite's amount of 15, with no active channel or transient Blizzard, Chilled,
or Frostbite holders. The saved rogue retained Relentless Strikes with zero
combo points and no combo target.

WoW PID 1321445 used `amdgpu`; its graphics counter increased from
3,123,213,611 to 27,240,889,370 ns. The server logged the intended casts without
errors or cast-validation failures. Existing unsupported account-data,
GM-ticket, and meeting-stone login requests remained.

Screenshots in the session directory include `rogue-five`, `rogue-refund`,
`blizzard-frostbite-early`, `blizzard-frostbite-late`, `frostbite-rooted`, and
`mage-reconnect`. Read-only results and validation logs remain under
`/tmp/thistle-target-trigger-*`, including `rogue-refund.txt`,
`frostbite-1.txt`, `first-root.txt`, `mage-talents.txt`, `logout.txt`, and
`reconnect.txt`.

The helper-owned client service was stopped and confirmed inactive. A final
read again found no player owners, positions, or metadata for GUIDs 3, 5, and
6. The retained server was then stopped. No changes were pushed.
