# EventAI coverage

This inventory covers the VMangos data in `db/vmangos.sqlite` as of August 8,
2026. Trigger coverage and action coverage are measured independently: an event
can fire while one of its action scripts still contains an unsupported command,
selector, or parameter mode.

## Coverage summary

- Event data: 6,256 rows across 3,474 creature entries.
- Supported trigger rows: 6,220.
- Blocked trigger rows: 36.
- EventAI action data: 7,409 rows across 6,215 script IDs.
- Mapped action-command rows: 7,250.
- Unmapped action-command rows: 159.

The command number measures interpreter availability, not end-to-end creature
behavior. The partial-mode inventory below remains part of the backlog even
when the command itself is mapped.

## Supported trigger families

- Timers and thresholds: combat and out-of-combat timers, health, mana, range,
  target health and mana, and victim rooted.
- Combat lifecycle: aggro, kill, death, evade, leave combat, reached home, and
  spawned.
- Spell and aura observation: hit by spell with school masks, spell hit target,
  self and target aura presence, and self and target aura absence.
- Nearby-unit observation: out-of-combat line of sight, friendly health,
  friendly crowd control, and friendly missing buff.
- External callbacks: receive emote and script event.

This pass closed 442 imported trigger rows. Aura stacks, rooted and crowd-control
state, mana percentage, and combat state are projected through world metadata
so timer evaluation stays pure. Text emotes and successful outgoing spells now
enter EventAI through owner-local callbacks.

## Supported action additions

The shared script interpreter now covers these EventAI-heavy commands:

| Command | Rows | Runtime behavior |
| --- | ---: | --- |
| 42 `SET_MELEE_ATTACK` | 49 | Typed behavior capability that gates automatic melee attacks. |
| 43 `SET_COMBAT_MOVEMENT` | 49 | Typed behavior capability that gates combat chasing. |
| 50 `CALL_FOR_HELP` | 40 | Existing call-for-help world system with the scripted radius. |
| 29 `MODIFY_THREAT` | 22 | Percent modification of one threat entry or the complete threat list. |
| 85 `SEND_SCRIPT_EVENT` | 6 | Owner-local EventAI script-event delivery. |
| 37 `SET_INST_DATA` | 107 | Typed instance-owner command. Stratholme fields 0 through 8 are registered, including abomination, undead, Black Guard, Baron, and Aurius scripts. |
| 6 `TELEPORT_TO` | 1 | Highlord Taelan Fordring's server-controlled same-world teleport, including spline interruption and old/new observer projection. |

Hostile threat-list selectors now distinguish second, last, random, random
excluding top, nearest, and farthest targets. Owner, nearest-player, and random
game-object selectors are also resolved from immutable script context.

## Blocked trigger inventory

These rows require lifecycle information or ownership models that do not yet
exist at the EventAI boundary:

| Event | Rows | Required work |
| --- | ---: | --- |
| 29 `MOVEMENT_INFORM` | 21 | Navigation completion must retain the VMangos motion type and point identity through the movement resolver. |
| 17 `SUMMONED_UNIT` | 7 | Summon ownership needs a reliable owner-local spawn callback. |
| 25 `SUMMONED_JUST_DIED` | 3 | Summon death must notify its owning creature without ambient process coupling. |
| 35 `STEALTH_ALERT` | 2 | Stealth detection needs an authoritative alert transition, not a proximity approximation. |
| 13 `TARGET_CASTING` | 1 | Cross-entity metadata needs an authoritative active-cast projection with correct start and finish timing. |
| 32 `GROUP_MEMBER_DIED` | 1 | Runtime creature group or formation ownership and member-death fanout. |
| 34 `HIT_BY_AURA` | 1 | Incoming spell resolution must preserve the applied aura-type identity in the owner callback. |

## Unmapped action-command inventory

The remaining commands are ordered by imported frequency, with related missing
dependencies called out explicitly:

| Command | Rows | Required work |
| --- | ---: | --- |
| 2 `FIELD_SET` | 30 | Typed update-field transitions; raw update-field mutation is intentionally not exposed. |
| 49 `ZONE_COMBAT_PULSE` | 26 | Zone membership and engagement fanout. |
| 27 `UPDATE_ENTRY` | 20 | Atomic runtime creature archetype replacement. |
| 55 `CREATURE_SPELLS` | 14 | Unified preloaded spell-list replacement. |
| 56 `REMOVE_GUARDIANS` | 9 | Summon ownership and guardian enumeration. |
| 88 `SET_COMMAND_STATE` | 8 | Controlled-creature command-state ownership. |
| 33 `ENTER_EVADE_MODE` | 7 | One semantic owner-local evade transition shared with behavior reset. |
| 54 `SET_SERVER_VARIABLE` | 7 | Global script-variable ownership and reset semantics. |
| 59 `SET_REACT_STATE` | 7 | Canonical aggressive, defensive, and passive behavior state. |
| 91 `LOAD_CREATURE_SPAWN` | 7 | Script-addressable spawn blueprints and forced pool activation. |
| 84 `SET_GOSSIP_MENU` | 6 | Mutable per-creature gossip-menu state. |
| 78 `JOIN_CREATURE_GROUP` | 5 | Runtime creature formations and ownership. |
| 48 `DEAL_DAMAGE` | 4 | Remote typed damage delivery with source attribution. |
| 72 `ASSIST_UNIT` | 4 | Selected-target attacker and helper projections plus engagement delivery. |
| 79 `LEAVE_CREATURE_GROUP` | 2 | Runtime creature formations and ownership. |
| 38 `SET_INST_DATA64` | 1 | Instance script GUID fields and entity-lifetime cleanup. |
| 77 `SET_FLY` | 1 | Flight movement capability and spline-flag projection. |
| 90 `START_SCRIPT_ON_GROUP` | 1 | Group or formation ownership and script fanout. |

## Partial selectors and parameter modes

These counts are separate dimensions and must not be added to the 159 unmapped
command rows:

- Command 37 has 107 numerically mapped EventAI rows. Stratholme fields 0
  through 8 are registered; commands for other instance scripts remain
  mapped-but-unregistered and fail closed. Same-batch read-after-write is not
  provided.
- Target type 12, creature GUID from instance data: 9 rows.
- `MOVE_TO` coordinate types 2 and 3: 18 rows; coordinate type 0 is supported.
- `MOVEMENT` types 6, 15, and 19: 45 rows; idle, random, waypoint, and home are
  supported.
- Initial source/target swap without a final buddy-owner swap: 16 rows.
- Command 6 is numerically mapped only for ordinary server-controlled creature
  sources. Player and client-controlled source modes remain unsupported; the
  mapped-row count does not claim those source modes.

## Validation gates

Every EventAI slice runs focused unit tests, the default `mix test` suite, and
`mix credo --strict`. Final acceptance additionally requires `mix test.all` so
VMangos, DBC, and Namigator-backed suites run together.
