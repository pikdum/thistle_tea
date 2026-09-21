# Item-started quest acceptance

Build 5875, September 21, 2026. Starter rules: `7de84475`; owner and protocol
integration: `31cbddf5`. The client run used `31cbddf5` throughout. No repository
edits, builds, tests, or commit hooks ran while the playtest server was live.

All 4,050 tests pass, along with compilation with warnings as errors, strict
Credo, and formatting. The client proof contains 30 passing assertions.

## Behavior and ownership

The current item cache contains 214 templates that start quests. Right-clicking
such an item uses `CMSG_QUESTGIVER_QUERY_QUEST` and then
`CMSG_QUESTGIVER_ACCEPT_QUEST`. Details identify the actual item instance as the
questgiver. `CMSG_USE_ITEM` continues to handle item spells.

`Logic.QuestItems.starter/4` requires the requested quest to match the item
template, the runtime item owner to match the character, and the exact instance
to occupy owned inventory. This includes equipped items, carried bags, bank
storage, and bank bags, matching VMangos's item lookup. Acceptance resolves the
item again and checks that the character is alive, quest requirements and
conditions pass, and the quest log has room. An item that was moved out of owned
storage, destroyed, or transferred cannot be accepted through a stale dialog.

An accepted starter remains when the quest needs it as a source or objective
item. Other starters are consumed by exact GUID. Missing source items are
prepared and combined with starter consumption in one `Inventory.Batch` plan
and one `InventoryUpdate.apply/2` commit. Source counts include bank storage.
Source capacity is checked before consuming the starter, following VMangos:
a full backpack rejects a starter exchange even if that exchange would free a
slot. Rejection creates no item instances and leaves the quest and inventory
unchanged.

Inventory updates can change progress in other active quests. Acceptance now
merges its newly reserved entry into the updated quest log, preserving those
changes. Previously, it could restore the quest-log snapshot from before the
inventory update. Regression tests cover both completion after a source grant
and loss of completion after starter consumption.

Items are not world objects, so item acceptance does not run a world-object
start script. Party-accept flag `0x2` uses the existing monitored confirmation
flow. `CMSG_QUESTGIVER_CANCEL` is also registered as an empty native request and
closes the dialog without changing quests, inventory, or an unrelated offer.
Its codec and dispatch are covered by automated tests.

References: local VMangos `Handlers/QuestHandler.cpp`, `Objects/Item.h`,
`Objects/Player.cpp` (`GetItemByGuid`, `CanInteractWithQuestGiver`, `CanAddQuest`,
and `AddQuest`), and `QuestDef.h`.

## Real-client checks

Debugpaladin (GUID 2) and Debugbuyer (GUID 10) used separate accounts and isolated
clients, limited to CPU cores 0–1 and 2–3. Fixture items were created with
`.additem`; quest interactions used native dialogs and controls. Tidewave read
stored characters, inventory, world state, and private offer/monitor fields.
Tracing recorded incoming quest codecs and outgoing quest and inventory packets.

| Action | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Right-click Gold Pickup Schedule (1307), then decline | The Collector dialog appeared with the item's name; decline closed it | Quest 123 absent; exact inventory and starter GUID unchanged |
| Reopen and accept | Quest log showed The Collector complete; The Collector's Schedule appeared | Starter instance consumed; exactly one item 2223 and complete quest 123 |
| Abandon and accept again | Native abandonment confirmation removed the objective and returned the starter | Item 2223 removed; fresh item 1307 GUID; reacceptance exchanged it again |
| Turn in to Marshal Dughan in Goldshire | Native request-items and reward dialogs; chat reported 21 XP and 85 copper | Item 2223 consumed, quest removed, rewarded set includes 123, coinage increased by exactly 85 |
| Accept An Old History Book (2794 → quest 337), log out, and reconnect | Complete quest and book returned after a real offline interval | Same book GUID throughout; exactly one item; quest retained in `CharacterStore` |
| Abandon the book quest | Quest disappeared while the book stayed | Same book GUID and count, no active quest 337 |
| Fill every backpack slot, then accept Westfall Deed (1972 → quest 184) | Red “Inventory is full” message | Error code 50; exact inventory and quest log unchanged; no prepared item leaked into `ItemStore` |
| Delete one filler shirt and retry | Furlbrow's Deed appeared and quest log showed complete | One item 1971, no item 1972, complete quest 184 |
| Abandon Furlbrow's Deed | Source disappeared and Westfall Deed returned | One fresh starter, no source, no quest 184 |
| Accept Glowing Shard (10441 → quest 6981) while grouped | Buyer saw the native party confirmation popup | Buyer initially had only a monitored offer, with no quest or shard |
| Click Yes on the buyer | Quest and shard appeared in the buyer's log and backpack | Native `CMSG_QUEST_CONFIRM_ACCEPT`; leader retained original shard; buyer received one distinct owned instance; offer and monitor cleared |
| Abandon both shard quests | Both logs emptied while each shard remained | One shard per character, no duplicate grants; the quests had correctly remained incomplete pending their exploration objective |
| Delete retained fixture items and leave the group | Empty quest logs, ordinary backpacks, no party frames | No quests, offers, monitors, group, or fixture instances; equipment, food, and hearthstones unchanged |

The Collector was turned in to the actual NPC at approximately
`-9465.52, 74.01, 56.78` on map 0. The other checks ran in Northshire or
Goldshire. The Glowing Shard's exploration and NPC turn-in chain were outside
this acceptance run.

Automated coverage additionally checks foreign and detached instances,
mismatched quests, moved or destroyed starters, duplicate acceptance, retained
objective-only starters, banked starters, full quest logs, death and ghost
state, level/race/class/prerequisite/condition failures, and script isolation.
The ownership and acceptance fixtures are database-free.

There were no server runtime errors, timeouts, or unimplemented item-quest
requests. The first read-only snapshot helper had an invalid nested Elixir
capture; it was corrected before collecting the baseline. Existing account-data,
raid-info, GM-ticket, and meeting-stone warnings remain outside this feature.

## Retained evidence

- Leader: `/home/pikdum/.cache/thistle-wow-playtest.BX9nmd`
- Buyer: `/home/pikdum/.cache/thistle-wow-playtest.cTXWyM`
- Leader screenshots: `collector-details.png`, `collector-accepted.png`,
  `collector-abandon-confirm.png`, `collector-turnin.png`,
  `collector-reward.png`, `book-details.png`, `book-reconnected.png`,
  `bags-full-rejected.png`, `deed-accepted.png`, `shard-details.png`,
  `shard-leader-log.png`, and `cleanup.png`
- Buyer screenshots: `shard-confirmation.png`, `shard-confirmed.png`, and
  `cleanup.png`
- Packet trace: `/tmp/thistle-item-quest-packets.log`
- State samples: `/tmp/thistle-item-quest-state-<phase>.term`
- Assertions: `/tmp/thistle-item-quest-proof.exs` and
  `/tmp/thistle-item-quest-proof.log`, with `accepted: true`, `count: 30`
- Server log: `/tmp/thistle-item-quest-playtest.log`
- Gates: `/tmp/thistle-item-quest-all.log`,
  `/tmp/thistle-item-quest-compile.log`, `/tmp/thistle-item-quest-credo.log`,
  and `/tmp/thistle-item-quest-format.log`

Both clients and the server were stopped, with artifacts retained.
