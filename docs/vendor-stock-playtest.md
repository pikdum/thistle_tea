# Limited vendor stock

Limited merchandise now depletes for every buyer of the same merchant.
Availability belongs to the merchant GUID, world copy, and item entry, so
separate spawns and instances have independent supplies. Unlimited items use
the protocol's `0xFFFFFFFF` count; sold-out limited items use zero. Listings
show the current count, successful purchases update the buyer's merchant
row, and stale purchase requests receive the native sold-out error.

Stock replenishes lazily when listed or purchased. Each elapsed interval
restores the item's `buy_count`, capped at `maxcount`. Partial replenishment
and successful purchases reset the interval timestamp, matching VMangos.
Full stock needs no retained record. Seed flags can randomize intervals to
80–120% and scale them above 2,500 active world accounts. Each calculation
stage truncates to whole seconds, with a one-second minimum.

`World.Loader.Vendor` now retains `incrtime`, `itemflags`, and explicit vendor
slots. It combines `npc_vendor` with the creature's `npc_vendor_template`
inventory, preserving direct-row precedence and cached conditions. Production
startup preloads the combined inventory; listing and purchasing do not query
Mangos. Reputation and condition filtering still produce compact client row
indices.

## Ownership and transactions

`Logic.VendorStock` owns the pure stock and replenishment rules.
`Player.VendorPurchase` plans the complete payment and legal inventory stacks
through `Inventory.Batch` and `Inventory.plan`. A world coordinator serializes
the final stock check for competing customers while their player owners remain
blocked. One ETS insertion commits stock, item rows, and a purchase receipt
containing the resulting inventory and money. The player then projects the
committed `Inventory.ChangeSet` through `InventoryUpdate.apply_committed/3`.

Receipts survive coordinator failure. Login recovers an interrupted purchase,
and a recorded receipt identifier prevents an already applied inventory from
being applied again. Exact acknowledgement removes the pending receipt.
Capacity, money, and sold-out failures do not charge or deliver items. World
copy cleanup removes its stock without deleting committed purchases or
receipts. Stock and character data remain in memory only.

The purchase response now reports purchase bundles separately from delivered
units. For example, buying ten bundles of five creates 50 items, reports ten
bundles in `SMSG_BUY_ITEM`, and reports 50 items in `SMSG_ITEM_PUSH_RESULT`.
Selling and buying back an item does not replenish merchant merchandise or
reset its restock deadline.

`Network.Sessions` tracks authenticated world connections through Registry
ownership. Character selection still counts as an active session; disconnect
removes it automatically, and concurrent connections for one account count
once. The auth-key cache retains disconnected accounts and is deliberately
not the source of the population used for restock scaling.

## References

- `refs/vmangos/src/game/Objects/Creature.cpp`:
  `GetVendorItemCurrentCount` and `UpdateVendorItemCurrentCount` define
  per-creature counts, interval advancement, bundle-sized replenishment,
  random restocking, and population scaling.
- `refs/vmangos/src/game/Objects/Player.cpp`:
  `BuyItemFromVendorSlot` checks stock against total delivered units and
  reports remaining stock with the compact visible row and bundle count.
- `refs/vmangos/src/game/Handlers/ItemHandler.cpp`: vendor listing combines
  direct and template inventories and projects current availability.
- `refs/vmangos/src/game/Objects/CreatureDefines.h` and
  `refs/vmangos/src/game/SharedDefines.h`: restock flags and the 2,500-session
  scaling threshold.

## Native client acceptance

Two isolated World of Warcraft 1.12.1 build-5875 clients used level-50
Debugwarrior and Debugbuyer against a fresh server at commit `0e2bcf3b`.
The debug playground now contains two Plugger Spazzring spawns. Their actual
seed inventory supplies ten Dark Iron Ale Mugs, replenishing one every
60 seconds, plus unlimited Grim Guzzler Boar sold in bundles of five.

Stand near the first merchant with
`.go xyz 16311.2 16317.1 69.44 451`, or the second with
`.go xyz 16317.2 16317.1 69.44 451`, then right-click its world model.
Mutations used the native merchant UI, client Lua merchant functions, chat
teleports, and logout/login. Tidewave probes only read live state.

- Both clients initially saw ten mugs. Debugwarrior used
  `BuyMerchantItem(2,10)` and received ten mugs for exactly 6,000 copper.
  His row immediately became sold out. Debugbuyer, still holding the earlier
  listing, attempted a purchase and saw “That item is currently sold out.”
  His inventory and 100,000,000-copper balance did not change. Reopening the
  merchant showed the depleted row on that client too.
- Reopening after 66.410 seconds showed one replenished mug. Debugbuyer
  bought it for 600 copper, returning stock to zero and starting a new
  60-second interval.
- Debugwarrior bought ten bundles of Grim Guzzler Boar for 40,000 copper.
  The 50 items arrived in legal stacks of 20, 20, and 10. After the mug and
  food purchases his balance was 99,954,000 copper.
- Selling Debugwarrior's ten mugs paid 1,500 copper, and buying them back
  restored the original GUID, ten items, and the prior balance. Both probes
  retained exactly the same zero merchant stock and restock timestamp.
- The second Plugger still had ten mugs. Debugbuyer bought one there,
  independently reducing that merchant to nine and merging it into his
  original mug stack. He now had two mugs and 99,998,800 copper.
- Logout and reconnect retained those two mugs, their GUID, the balance,
  and the second merchant's nine remaining mugs. After its interval elapsed,
  reopening showed ten and the depleted-stock record was removed.

After correcting population tracking, a fresh server and clients at final
code commit `a5c06310` confirmed an ordinary purchase changing stock from
ten to nine, delivering one mug and charging exactly 600 copper. They also
verified two authenticated accounts with only one character in world, then
two accounts with both characters at selection. Closing the clients reduced
the active-account count to one and zero while the auth-key cache stayed at
two. No pending purchase receipt remained after any accepted purchase.

Neither acceptance server logged gameplay owner or network errors. Existing
unimplemented account-data, raid-info, GM-ticket, and meeting-stone requests
appeared during normal client activity.

## Automated coverage and evidence

Tests cover simultaneous buyers competing for the last item, stale owners,
receipt acknowledgement, interrupted purchase recovery, coordinator restart,
world and merchant isolation, instance-stock cleanup, insufficient money,
full inventory, bundle counts, exact restock boundaries, elapsed intervals,
maximum caps, random/population scaling, unlimited inventory, zero-stock
packet encoding, explicit seed slots, and combined template inventories.
Concurrent races, high population, random intervals, and instance cleanup
were tested deterministically rather than through additional native clients.

- Main buyer screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.TaDwfA/screenshots/`.
- Second buyer screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.gKxyfZ/screenshots/`
  (`stock-sold-out`, `stock-refreshed-empty`, `stock-replenished`,
  `stock-restock-purchased`, `stock-independent`, `stock-reconnected`, and
  `stock-full-again`).
- Final code purchase screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.OW8xZd/screenshots/stock-final-purchase.png`.
- Authenticated character selection screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.tkXYJQ/screenshots/stock-authenticated.png`.
- Runtime probes: `/tmp/thistle-stock-*.txt`.
- Server logs: `/tmp/thistle-vendor-stock-server.log` and
  `/tmp/thistle-vendor-stock-session-server.log`.
- Final checks: `/tmp/thistle-vendor-stock-{all,compile,credo}.log`.

`mix test.all` passed all 4,261 tests. `mix compile --warnings-as-errors`
passed, `mix credo --strict` found no issues, and pre-commit formatting and
lint checks passed. All helper-owned clients and local servers were stopped;
logs and screenshots remain available.
