# Purchases into selected inventory slots

Dragging merchant goods into a backpack, equipped bag, bag bar, or equipment
slot now dispatches `CMSG_BUY_ITEM_IN_SLOT`. The build-5875 payload contains
the vendor GUID, item entry, destination bag GUID, slot, and bundle count.
The player's GUID denotes the base inventory; other GUIDs must identify a
currently equipped, owned bag. Bank destinations are rejected.

`Inventory.Batch.add/3` carries the requested destination into the shared
planner. Storage fills the selected slot first, then merges and places in
the same bag, then uses other carried storage. An explicitly occupied slot
must contain a compatible partial stack. Slot 255 requests any space in the
selected bag. Equipment purchases require one item, an empty compatible
slot, and the usual level, class, proficiency, reputation, and combat checks.
Two-handed purchases move the offhand into available storage atomically.

Payment, all item changes, and limited stock use the existing merchant
receipt transaction. Failed placement cannot spend money or stock or leave
partial item changes. Successful equipment purchases use the shared stat,
equip-cooldown, and attack-timer transitions. Receipt projection now retains
the previous inventory until those transitions run; interrupted-purchase
recovery applies the same transitions once before marking the receipt.

## References

Compared with VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`:

- `refs/vmangos/src/game/Server/Packets/Item.cpp`: vanilla packet layout.
- `refs/vmangos/src/game/Handlers/ItemHandler.cpp`:
  `HandleBuyItemInSlotOpcode` resolves owned equipped bag GUIDs.
- `refs/vmangos/src/game/Objects/Player.cpp`: `BuyItemFromVendor`,
  `_CanStoreItem`, `_CanStoreItem_InSpecificSlot`, and `CanEquipItem`
  define destination priority, stack failures, and empty equipment slots.
- `refs/wow_messages/wow_message_parser/wowm/world/item/cmsg_buy_item_in_slot.wowm`:
  the 22-byte vanilla request has no vendor-slot field.

## Native acceptance

A fresh server at `d330173c` and an isolated build-5875 client used level-50
Debugpaladin on Programmer Isle. Mutations used merchant dragging, native
Lua inventory functions, developer chat commands, and logout/login.
Tidewave probes only read owner state and retained character data.

- Added and equipped Small Brown Pouch (4496). Opened the first Plugger
  Spazzring near `.go xyz 16311.2 16317.1 69.44 451`.
- Physically dragged Dark Iron Ale Mug into backpack slot 8. The item appeared
  there, stock changed from ten to nine, and coinage changed from 100,000,000
  to 99,999,400. The owner retained position `{255, 30}`.
- `PickupMerchantItem(1); PickupContainerItem(1,4)` bought five Grim Guzzler
  Boar into pouch slot 4 for 4,000 copper. Its `contained` GUID matched the
  pouch. Dropping another bundle onto occupied backpack slot 1 showed
  "This item cannot stack" and left the entire owner inventory and money
  snapshot unchanged.
- Repeated purchases filled the selected food stack to 20. Split two into
  backpack slot 9, then bought five more into pouch slot 4. The result was
  20 in the selected slot, three in pouch slot 1, and the unchanged two in
  the backpack. All five food purchases charged 20,000 copper total.
- At Corina Steele near `.go xyz 16307.2 16317.1 69.44 451`, moved the old
  mainhand to backpack slot 10. `PickupMerchantItem(6); PickupInventoryItem(16)`
  bought Wooden Mallet directly into the mainhand for 701 copper. The shield
  moved to backpack slot 4 with its original GUID, and the character model
  displayed the mallet. Final coinage was 99,978,699.
- Repeating the mallet purchase showed "No equipment slot is available for
  that item." Trying Gladius showed the missing-proficiency error. Both
  requests left the complete inventory and money snapshot unchanged.
- Logout removed the live owner and retained the mallet and money with no
  pending receipt. Re-entry restored every item GUID, position, stack count,
  container GUID, and the exact coinage. The client displayed the restored
  equipment and both bags.

Telemetry recorded ten `CMSG_BUY_ITEM_IN_SLOT` requests: seven successful
purchases and three rejected placements. There were no owner or inventory
errors. Existing unrelated unimplemented account-data and GM-ticket requests
appeared during login. Full-backpack equipment, combat restrictions, unique
limits, equip cooldowns, and interrupted receipts were verified by automated
tests; those cases were not all reproduced in the native client.

## Evidence and validation

Client session: `/home/pikdum/.cache/thistle-wow-playtest.EKBATC`.
Screenshots include `selected-backpack.png`, `selected-bag.png`,
`occupied-slot.png`, `bag-overflow.png`, `equipment-purchase.png`,
`occupied-equipment.png`, `proficiency-rejected.png`, and `reconnected.png`.
The renderer reported RX 7900 XT hardware OpenGL. WoW PID 2848741 used
`amdgpu`, and its own graphics-engine counter increased during the run.

Server log: `/tmp/thistle-vendor-slot-server.log`. Compact owner snapshots
are `/tmp/thistle-vendor-slot-*.log`, including before/after overflow,
rejected purchases, logout, and reconnect. The client service and server
were stopped after acceptance; evidence was retained.

- Focused regressions: 108 passed.
- `mix test.all`: 7,457 passed, seed 949852, 83.7 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Gate logs: `/tmp/thistle-vendor-final-{tests,compile,credo}.log`.
