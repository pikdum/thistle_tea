# Contextual creature and hunter pet XP

Implemented against VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
with native build-5875 acceptance on September 26, 2026.

## Rules and boundaries

Kill XP uses the creature's static `NO_XP` flag, `0x2`. The unrelated extra flag
`0x40` means `ALWAYS_RUN`; treating it as no-XP incorrectly suppressed rewards
from creatures such as Warlord Krom'zar and Magistrate Barthilas.

Elites multiply XP by 2.5 in non-raid dungeons and by 2 elsewhere. Ordinary
creatures receive no dungeon multiplier. `KillReward.experience_options/2`
reads the cached map template at the boundary and supplies the same context
to solo, party, and hunter pet reward paths. `Experience` remains pure.

Solo hunter pet XP uses the owner's level for the base amount and the pet's
level for the victim-level factor. The kill must still grant base XP to the
owner. Group pets retain the owner's weighted share and the existing
independent pet eligibility check. Rested player XP does not increase pet XP.

Spell-created critters, unspecified creatures, totems, and creatures whose
template health multiplier is at most 0.1 grant no XP. The loader retains the
health multiplier as creature data; the pure formula reads no database.

Base XP keeps its fractional part through elite, template, and damage-origin
modifiers. Intermediate operations use the reference core's float32 precision;
the final result rounds to the nearest integer with ties to even. For example,
a level-30 player killing a level-32 ordinary creature receives 214, while a
level-60 player killing a level-63 open-world elite receives 794.

Reference locations are `Formulas.h` (`BaseGainLevelFactor`, `BaseGain`, `Gain`),
`Objects/CreatureDefines.h` (types and flags), `Objects/Player.cpp`
(`RewardSinglePlayerAtKill`), and `Group/Group.cpp` (party rewards).

## Automated checks

Tests cover static flags versus always-run, spell-created exclusions and the
health boundary, ordinary and elite dungeon rewards, fractional and ties-even
rounding, owner/pet level differences, gray kills, party shares, map types,
loader translation, and forwarding contextual options to the pet owner.

A separate C++ oracle used the reference formulas with float arithmetic and
`std::nearbyint`. Comparing owners 1–60, pets 1–owner level, victims 1–64, and
elite multipliers 1, 2, and 2.5 checked 351,360 combinations. Double-precision
arithmetic produced 1,068 mismatches; the final implementation produced zero.
This sweep covered base and elite arithmetic; template and damage modifiers
also have focused Elixir regressions. Local oracle artifacts are
`/tmp/thistle-xp-oracle.cpp`, `/tmp/thistle-xp-oracle.tsv`, and
`/tmp/thistle-xp-compare.exs`.

## Native acceptance

The fresh server used Debughunter, GUID 7, and GPU client session
`/home/pikdum/.cache/thistle-wow-playtest.C6ZKLS`.
Setup used developer level changes, god mode, teleports, and learning Death
Touch. Kills were casts from the real client. Taming, revival, feeding, passive
mode, logout, and login used client actions. Tidewave probes only read state.

The hunter abandoned the seeded wolf and completed Tame Beast on a level-6
Stonetusk Boar. Nearby high-level enemies killed the boar during setup, and
Revive Pet restored it. Before reward testing it had zero XP and passive stance.

| Kill | Owner level | Victim level | Owner XP gained | Pet XP gained |
| --- | ---: | ---: | ---: | ---: |
| Seeded Defias Evoker, Programmer Isle | 20 | 18 | 237 | 348 |
| Defias Evoker, Deadmines copy 1 | 20 | 18 | 297 | 435 |
| Magistrate Barthilas, Stratholme copy 2 | 50 | 58 | 1,770 | 0; pet died before the kill |
| Skeletal Flayer, Programmer Isle | 50 | 50 | 295 | 354 |

Both dungeon entries passed through their actual client area triggers: 78 for
Deadmines and 2214 for Stratholme. Teleports inside each dungeon retained the
existing instance. Exploration added 125 owner XP before the Deadmines kill,
so its owner total changed from 362 to 659. Changing the owner to level 50
reset that total before the Stratholme measurement.

The client and entity owners agreed on each reward. The two Defias kills moved
the pet from 0 to 348 to 783/900 XP. Its combat death after the Deadmines reward
retained 783 XP. The dead pet correctly received nothing from Barthilas, while
the hunter received 1,770 XP. Barthilas's live template had extra flags 64,
static flags 4096, and XP multiplier 2.0.

After revival, the Skeletal Flayer reward crossed the pet's 900-XP threshold:
783 + 354 became level 7 with 237/1,125 XP and 142 maximum health. The client
displayed this alongside the hunter's final 2,065 XP.

Logout retained both totals, the learned pet spell 7371, and passive stance.
The old pet GUID `17383894563550137491` lost its process and world position.
Both dungeon copies had empty member lists. Login created pet GUID
`17383894563550137517`, restoring level 7, 237/1,125 XP, 142 health, and passive
stance; the client still displayed 2,065 owner XP.

WoW process 1252603 used amdgpu, with its graphics counter increasing from
877,219,321 to 21,137,949,020 ns. Screenshots include `open-after`,
`dungeon-after`, `barthilas-after`, `level-after`, and `reconnected` in the
session's `screenshots` directory. The client service and retained server were
stopped after acceptance.

No error-level server logs appeared. Two Call Pet attempts on the dead boar
correctly returned `targets_dead`. An unrelated Stratholme patrol logged
unsupported script command 90 (`START_SCRIPT_ON_GROUP`); it was identified for
the immediate follow-up. The XP run does not establish support for that command.

Final XP gates: `mix test.all` passed 6,323 tests;
`mix compile --warnings-as-errors` passed; `mix credo --strict` found no issues.
Logs are `/tmp/thistle-xp-context-{tests,compile,credo,server}.log`.
