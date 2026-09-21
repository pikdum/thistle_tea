# Spell focus requirements

Player spells now honor the DBC `requires_spell_focus` field. A qualifying
object must have type 8, the required focus ID, live spawned presence in the
caster's world, and sufficient range. Range uses the template's distance plus
the object and caster bounding radii, including vertical separation. Nearby
objects of another focus type do not qualify.

Template loading indexes the maximum radius for each focus ID. Casting uses
that cached index, cached templates, spatial presence, and owner-published
metadata; it performs no new database queries. Selection is deterministic by
distance and GUID. This also supports long-range quest focuses in the seed
data, whose ranges reach 100 yards.

The initial cast validates its focus before starting. At launch, the pure
casting state machine emits a typed request for a fresh boundary check before
spending power, consuming reagents or item charges, applying effects, or
starting the spell cooldown. A result for a cancelled or replaced cast is
ignored. A vanished focus cancels the cast and supplies the required focus ID
in the native failure response.

Triggered player spells use the same requirement. A trigger interpreted by
another entity returns to its original player owner for validation. Creature
casts and passive spells remain exempt, matching VMangos's `CheckItems` path.
This requirement does not implement the content scripts associated with each
quest focus.

References:

- `refs/vmangos/src/game/Spells/Spell.cpp`: `CheckItems` and focus failure data.
- `refs/vmangos/src/game/Maps/GridNotifiers.h`: `GameObjectFocusCheck`.
- `refs/vmangos/src/game/Objects/GameObject.cpp`: object bounding radius.
- `refs/wow_messages/wow_message_parser/wowm/world/spell/smsg_cast_result.wowm`:
  failure reason `0x5E` and its focus ID payload.

## Automated validation

- `mix test.all`: **4,405 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Commit formatting and lint hooks: passed.

Tests cover mismatched types and IDs, spawned-state changes, despawn, instance
isolation, vertical distance and bounding radii, long-range templates, nearest
selection, absent and matching initial requirements, launch revalidation,
uncharged failure, exactly-once successful launch, stale results, exemptions,
trigger routing, and the native failure payload. DBC tests verify forge,
cooking fire, Black Anvil, and quest-focus requirements and exercise a real
triggered spell with an anvil requirement.

The first triggered-spell test exposed an incomplete test fixture with no
player component; the fixture was corrected and the full suite rerun.

Implementation: `de266d5a`.
Logs: `/tmp/thistle-focus-final-{all,compile,credo}.log` and
`/tmp/thistle-focus-commit.log`.

## Native client acceptance

Used an isolated build-5875 client with level-50 Human Debugwarlock (GUID 6).
God mode was off. Existing development commands granted recipes, profession
menu spells, and materials and staged positions. Craft requests came from the
native profession window's Create button. Basic Campfire used the native spell
action. Tidewave probes only read state. Profession training and skill gains
were outside this acceptance run.

| Scenario | Native and authoritative result |
| --- | --- |
| No forge on Programmer Isle | Smelt Copper 2657 reached the server and failed with visible “Requires Forge.” Five Copper Ore remained and no Copper Bar was created. |
| No cooking fire | Charred Wolf Meat 2538 reached the server and failed with visible “Requires Cooking Fire.” Five Stringy Wolf Meat remained and no cooked meat was created. |
| Basic Campfire 818 | The campfire appeared, consumed one Simple Wood, and retained the Flint and Tinder tool. The server found focus ID 4 and no forge focus. |
| Cooking beside the campfire | The native cast bar completed. Stringy Wolf Meat decreased from five to four and Charred Wolf Meat increased from zero to one. The client displayed the created item. |
| Smelting beside the campfire | The server still rejected the request with “Requires Forge”; all five ore remained. |
| Goldshire forge | At approximately `{-9460, 90, 58.32}` on map 0, the server selected seeded Forge 4090 at `{-9460.03, 94.2031, 56.5335}`, focus ID 3. The native smelting cast completed; ore decreased from five to four and Copper Bar increased from zero to one. |
| Leaving the forge | At approximately `{-9460, 65, 55.96}`, neither tested focus was available. Smelting again displayed “Requires Forge.” Four ore and the one completed bar remained. |

Focus loss during a cast, stale replies, instance isolation, and triggered-spell
requirements were covered by automated tests. No owner crashes or unexpected
cast failures occurred. Expected missing-focus failures were logged. Existing
unimplemented account-data, raid-info, GM-ticket, and meeting-stone
notifications remain.

## Retained evidence

- Server: `/tmp/thistle-focus-server.log`.
- State probes:
  `/tmp/thistle-focus-{before,rejected,campfire,cooked,forge,smelted,left-forge}.txt`.
- Screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.TGL078/screenshots/`, including
  `focus-requires-forge.png`, `focus-requires-fire.png`,
  `focus-cooking-cast.png`, `focus-cooked.png`, `focus-wrong-object.png`,
  `focus-smelting-cast.png`, `focus-smelted.png`, and `focus-left-forge.png`.

The helper-owned client, display, and retained server were stopped. No changes
were pushed.
