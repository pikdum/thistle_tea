# VMangos condition coverage

This report is generated from `db/vmangos.sqlite` by
`mix condition.coverage`. Run `mix condition.coverage --check` to verify it.

Numeric mapping and end-to-end evaluation are separate measurements. A
semantic name does not imply that the runtime can collect every fact or that
every consumer has migrated.

## Coverage summary

- Discovered condition consumer columns: 29.
- Direct conditioned rows: 8388.
- Distinct direct condition roots: 977.
- Reachable condition IDs: 1776.
- Reachable definitions with known VMangos numeric mappings: 1776.
- Reachable definitions handled end to end by the shared evaluator: 626.
- Missing child IDs: none.
- Cycles: none.

## Direct consumers

| Table and column | Rows |
| --- | ---: |
| `creature_loot_template.condition_id` | 3655 |
| `gossip_menu.condition_id` | 1280 |
| `gossip_menu_option.condition_id` | 1151 |
| `reference_loot_template.condition_id` | 665 |
| `npc_vendor.condition_id` | 424 |
| `creature_ai_events.condition_id` | 373 |
| `fishing_loot_template.condition_id` | 287 |
| `generic_scripts.condition_id` | 196 |
| `creature_ai_scripts.condition_id` | 111 |
| `quest_template.RequiredCondition` | 76 |
| `gameobject_loot_template.condition_id` | 34 |
| `quest_start_scripts.condition_id` | 23 |
| `quest_end_scripts.condition_id` | 20 |
| `spell_scripts.condition_id` | 18 |
| `areatrigger_teleport.required_condition` | 16 |
| `gameobject_scripts.condition_id` | 13 |
| `gossip_scripts.condition_id` | 12 |
| `spell_script_target.conditionId` | 11 |
| `skinning_loot_template.condition_id` | 9 |
| `creature_movement_scripts.condition_id` | 8 |
| `event_scripts.condition_id` | 3 |
| `disenchant_loot_template.condition_id` | 2 |
| `creature_spells_scripts.condition_id` | 1 |
| `areatrigger_scripts.condition_id` | 0 |
| `areatrigger_template.condition_id` | 0 |
| `item_loot_template.condition_id` | 0 |
| `mail_loot_template.condition_id` | 0 |
| `npc_vendor_template.condition_id` | 0 |
| `pickpocketing_loot_template.condition_id` | 0 |

## Reachable condition types

| ID | Semantic type | Definitions | Runtime status | Missing dependency |
| ---: | --- | ---: | --- | --- |
| -1 | `and` | 412 | evaluable | - |
| 8 | `quest_rewarded` | 351 | unmapped | - |
| 23 | `item_with_bank` | 140 | blocked | bank inventory |
| 9 | `quest_taken` | 108 | unmapped | - |
| -2 | `or` | 76 | evaluable | - |
| 22 | `quest_none` | 73 | unmapped | - |
| 52 | `db_guid` | 66 | evaluable | - |
| 2 | `item` | 59 | unmapped | - |
| 7 | `skill` | 54 | unmapped | - |
| 1 | `aura` | 45 | unmapped | - |
| 5 | `reputation_rank_min` | 41 | evaluable | - |
| 14 | `race_class` | 35 | partial | - |
| 15 | `level` | 31 | unmapped | - |
| 34 | `instance_data` | 31 | blocked | instance data |
| 17 | `spell` | 30 | unmapped | - |
| 20 | `nearby_creature` | 25 | unmapped | - |
| 12 | `active_game_event` | 21 | unmapped | - |
| 36 | `map_event_active` | 19 | partial | - |
| 16 | `source_entry` | 17 | evaluable | - |
| 24 | `content_patch` | 16 | unmapped | - |
| -3 | `not` | 12 | evaluable | - |
| 4 | `area_id` | 12 | unmapped | - |
| 19 | `quest_available` | 7 | unmapped | - |
| 21 | `nearby_game_object` | 7 | partial | - |
| 50 | `object_fit_condition` | 7 | unmapped | - |
| 11 | `saved_variable` | 5 | blocked | global saved-variable owner |
| 18 | `instance_script` | 5 | blocked | instance-script callbacks |
| 33 | `map_id` | 5 | unmapped | - |
| 57 | `creature_group_member` | 5 | blocked | creature formation owner |
| 6 | `team` | 4 | partial | - |
| 29 | `skill_below` | 4 | unmapped | - |
| 35 | `map_event_data` | 4 | partial | - |
| 41 | `health_percent` | 4 | unmapped | - |
| 51 | `pvp_rank` | 4 | blocked | authoritative honor rank |
| 53 | `local_time` | 4 | unmapped | - |
| 28 | `is_player` | 3 | unmapped | - |
| 38 | `distance_to_target` | 3 | unmapped | - |
| 43 | `in_combat` | 3 | unmapped | - |
| 46 | `alive` | 3 | partial | - |
| 54 | `distance_to_position` | 3 | unmapped | - |
| 27 | `gender` | 2 | unmapped | - |
| 30 | `reputation_rank_max` | 2 | evaluable | - |
| 39 | `moving` | 2 | unmapped | - |
| 45 | `in_group` | 2 | unmapped | - |
| 48 | `object_spawned` | 2 | unmapped | - |
| 55 | `object_go_state` | 2 | unmapped | - |
| 10 | `argent_dawn_commission_aura` | 1 | unmapped | - |
| 13 | `cannot_path_to_victim` | 1 | blocked | authoritative path-failure state |
| 31 | `has_flag` | 1 | blocked | typed update-field capability |
| 37 | `line_of_sight` | 1 | unmapped | - |
| 40 | `has_pet` | 1 | unmapped | - |
| 44 | `reaction` | 1 | unmapped | - |
| 47 | `map_event_targets` | 1 | partial | - |
| 49 | `object_loot_state` | 1 | unmapped | - |
| 58 | `creature_group_dead` | 1 | blocked | creature formation owner |
| 59 | `area_explored` | 1 | unmapped | - |

## Consumer integration

| Consumer | Integration status | Unknown policy |
| --- | --- | --- |
| Gossip menus and options | Partial special-case evaluator | Legacy open for unsupported leaves |
| EventAI and loaded scripts | Partial shared evaluator | Legacy open for unsupported leaves |
| Area-trigger teleports | Condition tree not loaded | Reject every nonzero condition |
| Vendors | Condition ID discarded | Not evaluated |
| Loot | Condition ID discarded | Not evaluated |
| Quest availability | Condition ID not integrated | Not evaluated |
| Remaining discovered consumers | Inventory only | Not integrated |

## Dependency-ranked backlog

1. Player-owned state and catalogs: aura, items, quests, skills, spells,
   reputation, team, race/class, level, gender, group, exploration, and time.
2. Existing world projections: game events, nearby objects and players,
   distance, line of sight, reaction, game-object state, and scripted events.
3. Consumer migrations: gossip/scripts, vendors/teleports, then actor-aware
   loot with reservation and commit revalidation.
4. Explicitly blocked owners: bank inventory, saved variables, instance
   scripts/data, raw flags, honor rank, and creature formations.

The inventory includes every schema column whose normalized name is
`condition_id`, `conditionId`, `required_condition`, or `RequiredCondition`.
Combinator traversal follows `NOT`, `AND`, `OR`, map-event target conditions,
and game-object fit-condition children.
