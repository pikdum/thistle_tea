# Vendor sales and buyback

Merchants retain the player's last 12 sold items in session buyback slots
69–80. Buying back pays the recorded sale price. Full-item sales preserve the
original item GUID and instance state; partial-stack sales clone only the sold
quantity. Repurchased stacks can merge into carried inventory, retiring the
sold GUID when the entire stack merges. A thirteenth sale evicts the oldest
entry. Logout destroys retained buyback items and clears all private slot,
price, and timestamp fields.

Sale prices account for remaining expendable charges and undiscounted repair
costs. Live vendor validation requires a living player, a living merchant in
the same world within five yards, and acceptable reputation. Foreign items,
banked items, nonempty bags, actively looted items, expired items, excessive
counts, unsellable templates, and money overflow are rejected. Capacity and
payment failures leave buyback items available. Pending item costs settle
before a sale, and selling an active cast item interrupts that cast.

Item durations and temporary enchantment durations pause while held in
buyback. Repurchasing resumes the remaining budget and arms the ordinary
owner timers. Buyback items are excluded from carried inventory, quest item
counts, equipment bonuses, and owned-item expiration scans.

`Logic.Buyback` produces pure plans through `Inventory.Batch`,
`Inventory.plan`, and `Inventory.ChangeSet`. `Player.Buyback` validates the
live interaction and commits money, inventory, ItemStore rows, and client
projections together through `InventoryUpdate.apply/2`. Packet handlers only
decode and dispatch. The ItemStore row remains the canonical item; buyback
metadata stores its GUID, price, and sale timing.

The accompanying vendor purchase fix creates legal stacks through the shared
item storage path and charges once after the entire purchase can fit. The
previous path could create an oversized single stack.

## References and client corrections

- `refs/vmangos/src/game/Handlers/ItemHandler.cpp`:
  `HandleSellItemOpcode` and `HandleBuybackItemOpcode` supply the sale,
  ownership, count, pricing, and buyback rules.
- `refs/vmangos/src/game/Objects/Player.cpp`:
  `AddItemToBuyBackSlot`, `RemoveItemFromBuyBackSlot`, inventory removal, and
  inventory saving define slot replacement, paused item/enchantment timers,
  and session-only retention.
- `refs/vmangos/src/game/Objects/UnitDefines.h`: vanilla's vendor flag is
  `0x4`. The initial validation used `0x80`, which is the innkeeper flag.
  Native interaction with Corina Steele exposed the mistake. A VMangos-tagged
  regression checks her actual `0x4004` flags.
- The build-5875 client values an 18/20 Worn Shortsword at 5 copper.
  VMangos-style repair-cost truncation initially paid 6. Sales now reuse the
  existing client-matched, undiscounted repair rounding, with a DBC-backed
  regression for this exact item. See [durability acceptance](durability-playtest.md)
  for the repair rounding evidence.

## Native client acceptance

Final acceptance used source commit `2f069a55`, a fresh local server, and an
isolated World of Warcraft 1.12.1 build-5875 client. Level-50 Debugwarrior
interacted with Corina Steele on Programmer Isle. All mutations entered
through native chat, item use, merchant actions, and logout/login. Tidewave
probes only read authoritative state.

Setup used `.go xyz 16307.2 16323.1 69.44 451`, `.additem 20744`,
`.additem 25`, and `.additem 118 5`. Applying Minor Wizard Oil to the Worn
Shortsword consumed one charge. `.debug durability 10 carried` then reduced
the sword to 18/20 durability. Right-clicking Corina's world model opened the
ordinary merchant window.

- Selling the oil with four charges paid 400 copper; selling the enchanted
  sword paid 5. The Buyback tab displayed both items, the sword's enchant and
  18/20 durability, and the corrected price matching its tooltip. Money moved
  from 100,000,000 to 100,000,405 copper.
- Buying both items back restored exactly 100,000,000 copper and both original
  GUIDs. The oil retained four charges, and the sword retained enchant 2623
  and 18/20 durability. Its enchant deadline advanced by exactly 32.239
  seconds, the time spent in buyback.
- `SplitContainerItem(0,5,2); PickupMerchantItem(0)` sold two of five Minor
  Healing Potions for 10 copper. The original stack retained three. Native
  buyback merged the two back into the original GUID, restored five potions
  and the starting balance, and deleted the sold clone's ItemStore row. The
  client compacts occupied entries visually even when internal slots have
  gaps.
- A Shadowforge Torch, shortened with `.debug item duration 11885 30`, sold
  for 711 copper with 26.359 seconds remaining. Two probes 45.512 seconds
  apart found exactly the same remaining budget in buyback. Repurchase
  restored the original GUID, returned money to the starting balance, and
  displayed a resumed countdown. Natural expiration removed the torch from
  the backpack and ItemStore and cleared the owner's item-duration timer.
- Selling the oil again and logging out retained 100,000,400 copper, deleted
  the sold item, emptied buyback metadata, and zeroed every buyback GUID,
  price, and timestamp field. Reconnecting retained the sword, its enchant
  and durability, the five potions, and the sale proceeds. The native Buyback
  tab was empty; deleted item rows and timers remained absent.

No gameplay owner or network errors occurred in the final server log. The
client also sent existing unimplemented account-data, raid-info, GM-ticket,
and meeting-stone requests. No second observer client was used.

## Automated coverage and evidence

Deterministic tests cover the complete 12-slot cycle, thirteenth-item
eviction, reuse of slot 69 when it is the only hole, replay and slot bounds,
full and partial identity preservation, stack merging, money/capacity
failures, nonempty bags, ownership and carried-item restrictions, charge and
durability pricing, pending costs, active casts, quest/equipment updates,
packed private fields, and logout cleanup. Timer coverage includes real-time
items and temporary enchantments. Vendor tests cover world, range, alive
state, vanilla NPC flags, and splitting a purchase of 12 into stacks of
5, 5, and 2 with one payment. These failure, eviction, real-time timer, and
multi-stack purchase cases were automated rather than replayed in the client.

- Final screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.bxxjOk/screenshots/`
  (`sold-tooltip`, `restored`, `partial-sold`, `partial-restored`,
  `timed-sold`, `timed-restored`, `timed-expired`, `logged-out`, and
  `reconnected-buyback`).
- Initial pricing mismatch screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.iMIDbp/screenshots/buyback-sword-tooltip.png`.
- State probes: `/tmp/thistle-buyback-acceptance-*.txt`.
- Final server log: `/tmp/thistle-buyback-acceptance-server.log`.
- Verification logs: `/tmp/thistle-buyback-all.log`,
  `/tmp/thistle-buyback-compile.log`, and `/tmp/thistle-buyback-credo.log`.

`mix test.all` passed all 4,244 tests. `mix compile --warnings-as-errors`
passed and `mix credo --strict` reported no issues. Pre-commit formatting and
lint checks passed. The helper-owned client and local server were stopped;
logs and screenshots remain available.
