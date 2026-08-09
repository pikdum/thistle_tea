# Quest scripting coverage

This inventory covers the VMangos data in `db/vmangos.sqlite` as of August 8,
2026. The primary acceptance set is `quest_start_scripts` and
`quest_end_scripts`, with recursively referenced `generic_scripts` and
`creature_movement_scripts` included when judging escort and event behavior.

## Coverage summary

- Direct quest start/end data: 2,355 rows across 314 quest script IDs.
- Implemented direct rows: 2,351.
- Blocked direct rows: 4 across three quests.
- Combined quest, generic, and movement data: 7,142 rows.
- Commands with no numeric runtime mapping in that combined set: 111 rows.

The direct-row number describes command availability, not a claim that every
quest is end-to-end complete. A quest can enter generic or waypoint scripts
that use a partial target selector or an unsupported secondary command.

## Implemented command families

- Presentation: talk, emote, sound, stand state, sheath state, facing, morph by
  display ID, mount, custom game-object animation, and game-object state.
- Movement and escort control: point movement, idle/random/waypoint/home
  movement modes, run/walk, flee, home position, waypoint routes, same-world
  server-controlled creature teleports, and map-event escort lifecycle.
- Combat and unit state: attack start, combat stop, cast interruption, aura
  add/remove, spell casts, temporary faction, typed flag changes, melee and
  combat-movement capabilities, phase changes, and invincibility health floors.
- Quest objectives: exploration/event credit, kill credit, talk credit, group
  failure, item creation, and timed quest failure.
- Spawning and object lifecycle: temporary creatures, summoned objects,
  scripted game-object spawn/load/despawn, creature respawn, object removal,
  trap activation, and door/button operation.
- Script orchestration: nested generic scripts, weighted script selection,
  ordered cancellable delays, creature-presence termination, condition
  termination, map-event commands and source/target/extra-target selection, and
  script fanout to nearby objects. Final-target forwarding makes the receiving
  creature the teleport source. Registered instance-data commands cross a typed
  effect boundary into the instance owner.
- Creature presentation: per-slot scripted equipment set, clear, preserve, and
  reset-to-default behavior.

## Blocked direct quest rows

| Command | Rows | Quests | Missing capability |
| --- | ---: | --- | --- |
| 27 `UPDATE_ENTRY` | 2 | 434, 4505 | Atomic runtime creature archetype replacement. A correct implementation must replace template-derived stats, faction, display, equipment, spells, loot, AI, metadata, and the respawn snapshot through one transition. |
| 55 `CREATURE_SPELLS` | 2 | 5713 | Runtime spell-list replacement backed by a unified preloaded spell cache. Quest script loading is VMangos-data-only in CI, while spell construction requires DBC data; querying DBC during gameplay is not acceptable. |

These commands are intentionally left unsupported instead of implementing a
partial mutation that would leave stale derived state.

## Remaining generic and waypoint command inventory

The combined quest/generic/movement data contains these unmapped commands:

| Command | Rows | Required work |
| --- | ---: | --- |
| 27 update entry | 15 | Atomic creature archetype replacement. |
| 90 start script on group | 13 | Runtime group/formation ownership and member enumeration. |
| 91 load creature spawn | 12 | Script-addressable creature spawn blueprints and forced pool activation. |
| 49 zone combat pulse | 10 | Zone-scoped combat participant enumeration and engagement fanout. |
| 33 enter evade | 8 | A single semantic evade transition shared with AI reset. |
| 59 react state | 8 | Canonical aggressive/defensive/passive AI state in behavior context. |
| 78 join creature group | 8 | Runtime creature formations and ownership. |
| 75 add threat | 7 | Remote semantic threat delivery to the target owner. |
| 77 set fly | 7 | Flight movement capability and spline flag projection. |
| 79 leave creature group | 5 | Runtime creature formations and ownership. |
| 92 start script on zone | 5 | Zone membership index and player/pet fanout. |
| 55 creature spells | 4 | Unified preloaded spell cache and runtime list replacement. |
| 48 deal damage | 3 | Remote typed damage delivery with source attribution. |
| 88 command state | 3 | Pet/controlled-creature command-state ownership. |
| 84 gossip menu | 2 | Mutable per-creature gossip-menu state. |
| 2 field set | 1 | A typed field abstraction; raw update-field writes are intentionally not exposed. |

## Partial selectors and parameter modes

- Command 37 `SET_INST_DATA` has 19 combined quest, generic, and movement rows
  with numeric decoding. Only quest-end script 5122's Stratholme field-7 write
  is registered end to end. Other maps and fields are rejected until their
  `SetData` callbacks are audited and implemented. A later condition row in the
  same pure script batch does not observe an earlier write from that batch.

- Owner-only target type 9 and nearest-player target types 25 and 27 are
  implemented.
- `MOVE_TO` coordinate modes 1 and 2 have 13 rows; mode 0 is implemented.
- Movement type 15 (follow) has six rows; idle, random, waypoint, and home are
  implemented.
- Initial source/target swap without a final buddy-owner swap has 35 rows.
- Whisper and boss-whisper talk modes have seven rows.
- Morph-by-creature-entry has 28 movement rows. Morph-by-display-ID is
  implemented; entry-based morphing needs a preloaded template display choice.
- Command 6 `TELEPORT_TO` is mapped for ordinary server-controlled creature
  sources. It interrupts the old spline, preserves the exact current
  `WorldRef`, and projects the relocation to old and new observers. Player and
  client-controlled source modes remain unsupported because they require the
  acknowledgement and attachment lifecycle.
- Creature command 6 retains the declared map and option fields for auditing
  but does not use them as relocation policy. Magistrate Barthilas is the
  pinned regression: his row declares map 0 while his runtime world remains map
  329 and the same instance copy.

## Validation gates

Every committed slice runs focused unit/integration tests, the default
`mix test` suite, and `mix credo --strict`. Final acceptance additionally
requires `mix test.all` so VMangos, DBC, and Namigator-backed suites run
together.
