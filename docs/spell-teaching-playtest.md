# Teaching spells and recipe books

Player-targeted effect 36 now teaches spells through the owning player's
shared learning boundary. Previously, normal recipe books could finish their
item cast and consume a charge without teaching their recipe. Pet teaching
keeps its existing training path.

Effect 44 now applies skill steps, preserving earned points and stable skill
slots while setting the exact trained cap. Vanilla teaching spells place
their learned-spell effects before their skill-step effect; both are carried
in one typed owner request. This also handles spells that teach multiple
abilities. Learned-spell effect 118 grants now run only for newly learned
spells, so later unrelated learning does not reapply an older skill cap.

Recipe-book casts defer book and reagent consumption to the teaching
transaction. At admission and completion, the boundary checks the exact
owned, carried book, charges, item requirements, taught spell data, and
whether the taught spells are already known. It prepares learning without
publishing, plans costs with `Inventory.Batch`, and commits the resulting
`Inventory.ChangeSet` once. Interrupted casts never enqueue teaching. Missing
or banked books and lost requirements cannot cause partial learning or
consumption. Trade preparation settles already queued teaching costs before
freezing its inventory snapshot.

The item review also found that `required_spell` was enforced by auction
filtering but missing from ordinary item-use and equipment checks. The shared
proficiency snapshot now enforces that requirement, including profession
specializations such as Armorsmithing. Auction filtering uses the shared rule.
Known spell IDs remain sufficient when a spellbook entry has not been loaded.

References:

- `refs/vmangos/src/game/Spells/SpellEffects.cpp`: `EffectLearnSpell` and
  `EffectLearnSkill`.
- `refs/vmangos/src/game/Objects/Player.cpp`: `UpdateSpellTrainedSkills` and
  `CanUseItem`.
- DBC spells 7756 and 19886: Brilliant Smallfish recipe teaching and the
  Expert Cookbook's combined learning and skill-step effects.
- VMangos item 11612: Dark Iron Plate plans require Blacksmithing 285 and
  Armorsmithing spell 9788.

## Automated validation

- `mix test.all`: **4,428 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Commit formatting and lint hooks: passed.

Tests cover combined and multiple teaching effects, NPC-to-player teaching,
recipient ownership, explicit `EventSink.Context` delivery, exact skill steps,
invalid steps, recipe consumption, duplicates, cancellation, missing and
banked books, skill and specialization loss during casting, invalid taught
spells, missing reagents, queued trade costs, stored character state, and
learning notifications. Existing pet training and architecture tests pass.

The specialization follow-up also verifies shared equipment and auction
requirements. The full suite exposed an auction fixture whose known spell ID
had no loaded spellbook entry; the shared snapshot was corrected to honor
both representations. Test-fixture mistakes and lint findings from the first
runs were corrected before the final full validation.

Implementation commits:

- `b454b95b`: player teaching effects and transactional recipe books.
- `287a1cb6`: shared required-spell checks for items and equipment.

Final gates: `/tmp/thistle-teaching-final-{all,compile,credo}.log`.
Commit logs: `/tmp/thistle-teaching-commit.log` and
`/tmp/thistle-teaching-specialization-commit.log`.

## Native client acceptance

The final run used an isolated build-5875 client and level-50 Human
Debugwarlock, GUID 6, on Programmer Isle with god mode off. Existing development
commands supplied books, materials, profession ranks, and Armorsmithing.
`.debug skills` staged Cooking 150/150 and Blacksmithing 300/300 for the
advanced-book checks; those values were not earned during this test.

Books were activated through the client's `UseContainerItem` API. Crafting
used the native Cooking window's Create button beside a player-created Basic
Campfire. Cancellation used the client's `SpellStopCasting` API and produced
`CMSG_CANCEL_CAST`. Tidewave probes only read the owner and CharacterStore.

| Scenario | Native and authoritative result |
| --- | --- |
| Read Recipe: Brilliant Smallfish 6325 | One of two scrolls was consumed after its cast. Recipe 7751 appeared in Cooking and in the owner and stored spell lists. |
| Craft the learned recipe | One raw fish became one Brilliant Smallfish. Cooking rose from 1/75 to 2/75 in the client, owner, and stored character. |
| Try the spare recipe | The client displayed “You already know Brilliant Smallfish.” The remaining scroll was preserved. |
| Try Expert Cookbook at Cooking 2/75 | The client displayed “You can't use that item.” The book and skill were unchanged. |
| Try Dark Iron Plate plans without Armorsmithing | Blacksmithing was 300/300, but the client rejected the book. The plan remained and recipe 15296 was absent. |
| Learn Armorsmithing, then read the plans | The cast completed, the plan was consumed, and Dark Iron Plate appeared in the native Blacksmithing window and authoritative spell lists. The armor itself was not crafted. |
| Interrupt the Expert Cookbook | The native Expert Cook cast bar was visible and the owner reported cast 19886. Cancellation displayed “Interrupted,” preserved the book, and left Cooking at 150/150 with Journeyman spell 3102. |
| Finish reading the Expert Cookbook | Its 20-second cast completed, one book was consumed, and Expert spell 3413 replaced Journeyman. Cooking became 150/225 while retaining skill slot 10. |
| Logout and re-enter the character | Cooking remained 150/225. Both learned recipes, Armorsmithing, remaining raw and cooked fish, and the spare duplicate recipe were retained. Consumed books remained absent. |

The native client rejected duplicate and ineligible item actions locally;
automated packet and boundary tests separately prove server enforcement.
Missing-book, bank-movement, and mid-cast requirement-loss cases were tested
automatically. No owner crashes, unexpected spell failures, or unsupported
teaching messages appeared. Existing unimplemented account-data, raid-info,
GM-ticket, and meeting-stone notifications remain.

## Retained evidence

- Final server log: `/tmp/thistle-teaching-final-server.log`.
- State probes:
  `/tmp/thistle-teaching-final-{before,recipe,crafted,rejected,specialization-required,specialization-learned,reading,cancelled,expert,reconnected}.txt`.
- Screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.rXEytV/screenshots/`, including
  `teaching-crafted.png`, `teaching-duplicate.png`, `teaching-low-skill.png`,
  `teaching-specialization-required.png`, `teaching-dark-iron-plate.png`,
  `teaching-expert-reading.png`, `teaching-expert-cancelled.png`,
  `teaching-expert-learned.png`, and `teaching-reconnected.png`.
- An earlier recipe-only acceptance run is retained under
  `/home/pikdum/.cache/thistle-wow-playtest.lWIB5f/` and
  `/tmp/thistle-teaching-server.log`.

Both helper-owned clients and displays and their retained servers were stopped.
Changes were committed locally; nothing was pushed.
