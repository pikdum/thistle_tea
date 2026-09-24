# Random item properties

Random-property equipment now selects a suffix and its associated enchantments
from the template's VMangos probability pool. Selection happens once when an
item is prepared or a loot slot is generated. The selected property travels
with the loot reservation and item instance, including failed inventory
attempts, group awards, vendor buyback, and reconnects within the running
server. Runtime storage remains in memory.

The boundary preloads patch-10 probability pools and DBC property definitions.
The selector is pure and accepts a supplied random sample. Item construction
packs the property's three enchantments into slots 3 through 5, leaving
permanent and temporary enchants independent. Existing equipment enchantment
consumers apply the bonuses and exclude broken gear. Equipment visibility,
loot windows, group rolls, award receipts, and auction name searches include
the selected property.

## References

- `refs/vmangos/src/game/ItemEnchantmentMgr.cpp`: valid chance bounds and
  weighted selection when the pool does not total 100.
- `refs/vmangos/src/game/Objects/Item.cpp`: `GenerateItemRandomPropertyId`,
  `SetItemRandomProperties`, property enchantment slots, and retained properties
  when cloning an item.
- `refs/vmangos/src/game/Objects/Player.cpp`: `SetVisibleItemSlot` projects the
  random property separately from permanent and temporary enchantments.
- `refs/wow_messages`: build-5875 loot and item-push packet field ordering.
- Local DBC property 25 is `of Intellect`, with enchantment 80. Property 755
  is `of the Owl`, with enchantments 80 and 82. Aboriginal Sash, entry 14113,
  uses VMangos property pool 875.

## Automated verification

Source commit `e775337b` passed `mix test.all` with 5,431 tests,
`mix compile --warnings-as-errors`, and `mix credo --strict` with zero issues.
Formatting and commit hooks also passed. The focused regressions cover:

- Weighted selection, invalid weights, empty pools, and sample endpoints.
- Property packing, independent applied enchants and expiry, visible property
  clearing, gift naming, and replacement items keeping their own property.
- Independently rolled grants and vendor receipts, fixed quest reward receipts,
  full-bag retry without rerolling, and explicitly property-free loot.
- Equipment stat application, removal while broken or unequipped, and repair.
- Loot reservations and group-roll identity, packet fields, and auction suffix
  searches.
- DBC definitions and VMangos patch filtering in separately tagged tests.

## Native client acceptance

Acceptance used a fresh local server at `e775337b` and two isolated World of
Warcraft 1.12.1 build-5875 clients. Level-50 Debugmage and Debugbuyer entered
Programmer Isle through their ordinary login flow. All mutations used native
chat commands, spell casts, inventory actions, merchant interactions, group
votes, and logout/login. Tidewave probes only read authoritative state.

The development Squirrel at spawn 991500, near
`16313.2 16328.1 69.44` on map 451, drops one Aboriginal Sash and respawns
after 180 seconds. It gives a reproducible random-equipment source without
depending on a rare world drop.

### Solo loot and equipment

1. Debugmage filled the ten empty backpack slots with `.additem 25 10`,
   teleported near the Squirrel, and killed it with Fire Blast.
2. The ordinary loot window displayed **Aboriginal Sash of Intellect**,
   including **+2 Intellect** in its tooltip. The server loot slot held
   property 25 with enchantments `[80, 0, 0]`.
3. Clicking the item displayed **Inventory is full**. The slot remained
   unlooted, the reservation map was empty, and the player held zero sashes.
4. Deleting one filler sword, closing and reopening the corpse, then clicking
   the item produced the same suffix in the loot receipt. The awarded item
   GUID was `4611686018427388143`, property 25, enchantment 80 in slot 3.
5. After clearing the remaining filler swords and unequipping Ban'thok Sash,
   the mage had 184 Intellect and 3,528 maximum mana. Equipping the new sash
   through the normal binding confirmation raised these to **186 Intellect**
   and **3,558 maximum mana**. The character panel and tooltip agreed with
   authoritative state.

### Buyback, inspection, and durability

- Selling the sash to Corina Steele and buying it back retained the exact
  GUID, property, enchantment, binding flag, and 18/18 durability. The buyback
  row and tooltip displayed the suffix and +2 Intellect, priced at 139 copper.
- After re-equipping, Debugbuyer inspected Debugmage. The second client's
  inspection tooltip displayed **Aboriginal Sash of Intellect** and
  **+2 Intellect**. The mage's visible waist property field was 25.
- `.debug durability 100 carried` broke the carried equipment. The sash still
  had property 25 but supplied no bonus: Intellect was 102 both with the broken
  sash equipped and after unequipping it. The client showed 0/18 durability.
- Re-equipping and using the merchant's native repair action restored 18/18
  durability, 186 Intellect, and 3,558 maximum mana.

### Group loot and reconnect

- Debugmage invited Debugbuyer, then killed the respawned Squirrel. The group
  loot slot selected property **755**, `of the Owl`, with enchantments
  `[80, 82, 0]`. Both clients displayed that suffix in their roll windows.
- Debugmage selected Need and Debugbuyer passed. The native vote, winning
  roll, winner, and loot receipt messages all named the same suffix. The mage
  received GUID `4611686018427388144`, property 755, with enchantments 80 and
  82 in slots 3 and 4. The completed corpse loot session was cleared.
- A normal logout removed the mage's live entity. The character store retained
  visible property 25 and the equipped stats. Logging back in restored the
  original equipped Intellect sash and the bagged Owl sash with their exact
  GUIDs, properties, and enchantments. The client again showed 186 Intellect,
  3,558 maximum mana, and the equipped sash's suffix and +2 Intellect tooltip.

## Local artifacts

- Mage screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.RSo6wx/screenshots/`
  (`loot-before`, `full-bags-rejected`, `collected`, `equipped-stats-tooltip`,
  `buyback-tooltip`, `broken-stats`, `grouped-kill`, `group-awarded`, `relogged`).
- Observer screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.UEvjdz/screenshots/`
  (`observer-suffix`, `observer-roll`).
- State probes: `/tmp/thistle-properties-*.txt`; server log:
  `/tmp/thistle-properties-server.log`. No server errors were observed.
- Gate logs: `/tmp/thistle-properties-tests-final.log`,
  `/tmp/thistle-properties-compile-final.log`, and
  `/tmp/thistle-properties-credo-final.log`.
- Both owned `WoW.exe` processes used `amdgpu` on `0000:0c:00.0`. Their own
  graphics counters advanced from 8,740,905,503 to 24,555,542,097 ns for the
  mage and from 8,340,474,949 to 9,142,957,755 ns for the observer. Samples
  are in `/tmp/thistle-properties-*gpu*.txt`.

Both isolated clients and the retained local server were stopped after
acceptance. No deployment or push was performed.
