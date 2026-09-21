# Timed items

Item lifetimes now run through shared inventory and player lifecycle paths.
Ordinary timed items spend their remaining lifetime while the owner is online;
items with `ITEM_FLAG_REAL_DURATION` also age offline. Login removes conjured
items after more than fifteen minutes offline, including banked items.

`ItemLifetime` keeps pure deadline and pause/resume rules in a typed
`ItemDuration` value on the item. The active deadline survives movement,
splitting, wrapping, and transfer. Logout saves ordinary items' remaining
milliseconds without rounding away their budget. These are monotonic runtime
timestamps; the existing restart-wipes-runtime-data policy is unchanged.

`Player.ItemDurations` owns one timer for the earliest owned item deadline.
Inventory publication registers newly held items and sends
`SMSG_ITEM_TIME_UPDATE` with the current remaining seconds. Timer tokens and
ownership checks prevent stale owner messages from removing transferred items.
Trade settlement also rejects expired offers, including expiry while owners
are waiting for the coordinator.

Expiry plans exact-item removals through `Inventory.Batch` and
`Inventory.plan`, then commits one change set through `InventoryUpdate`.
Equipment bonuses, visible slots, quest needs, and destroy packets follow the
existing inventory projection. Expiry cancels a cast using the removed item
and closes its container loot window. Bag children are removed before their
expired bag; duration changes use the planned bag state so logout cannot
restore an expired child's slot.

An accompanying inventory fix makes splitting copy the source item instance
under a new GUID. Previously it rebuilt the split from the template, losing
remaining duration, binding, creator, and other instance fields.

## References

- `refs/vmangos/src/game/Objects/Item.cpp`: `UpdateDuration`, `SendTimeUpdate`,
  and `CloneItem` define expiration, the client timer, and split preservation.
- `Objects/Player.cpp`: `UpdateItemDuration`, `AddItemDurations`, inventory
  loading, and `DestroyItem` define online/offline rules and cleanup.
- `Objects/ItemPrototype.h`: conjured flag `0x2` and real-duration flag
  `0x10000`.
- `refs/wow_messages/wow_message_parser/wowm/world/item/smsg_item_time_update.wowm`:
  opcode `0x1EA`, item GUID followed by unsigned 32-bit remaining seconds.

## Native acceptance

Two isolated build-5875 clients used Debugwarrior (GUID 1) and Debugrogue
(GUID 3) on Programmer Isle against `9d47cd5a`. Debug commands granted seed
items and shortened their real deadlines with
`.debug item duration <entry> <seconds>`. Splitting, trading, equipping, logout,
and login used the clients. Tidewave probes only read state.

- Speckled Tastyfish (`19807`) displayed its countdown. Splitting six fish
  into four and two retained deadline `-576460483465` on GUIDs
  `4611686018427388133` and `4611686018427388134`. Both disappeared from the
  bag and ItemStore when the deadline passed. Its soulbound trade rejection
  was also retained.
- Hardpacked Snowballs (`21038`, unique limit five) were split from four into
  two and two. The warrior traded one stack to the rogue. GUIDs
  `4611686018427388137` and `4611686018427388138` both retained deadline
  `-576460369103`; the latter changed owner to GUID 3. The recipient tooltip
  showed 18 seconds remaining. Both stacks expired and both timers cleared.
- Durnan's Scalding Mornbrew (`10439`) expired normally while online. A new
  Mornbrew later logged out with exactly 112,220 ms remaining and no active
  deadline. It retained that budget through an observed 88.828 seconds
  offline. Tastyfish held at the same logout retained its deadline and
  reached zero offline. On reconnect, Tastyfish was absent and Mornbrew
  resumed with its saved budget; its tooltip showed two minutes. Shortening
  the resumed item to ten seconds then removed it normally.
- The warrior equipped Andonisus (`22736`) through native item use. Before
  expiry, mainhand GUID `4611686018427388140` supplied base weapon damage
  159–296 and total attack power 1,070. Expiry cleared the equipped GUID,
  removed the item record, restored base unarmed damage 1–2, and reduced
  attack power to 470. The client updated its item presentation, and the
  empty mainhand persisted through logout and reconnect.
- Final probes found no tested timed items and no item-duration timer on
  either player. All expired item GUIDs were absent from ItemStore. There
  were no server errors or new gameplay warnings. Existing unsupported
  login requests for account data, raid information, GM tickets, and
  meeting-stone information remained.

Both clients and the server were stopped after acceptance. Retained evidence:

- Warrior: `/home/pikdum/.cache/thistle-wow-playtest.8S02Ie/screenshots/`
  (`duration-fish-tooltip`, `duration-fish-expired`, `duration-snowball-trade`,
  `duration-logged-out`, `duration-resumed-tooltip`, `duration-final-expired`).
- Rogue: `/home/pikdum/.cache/thistle-wow-playtest.NfGamn/screenshots/`
  (`duration-received-tooltip`, `duration-received-expired`).
- Runtime reads: `/tmp/thistle-duration-*.txt`.
- Server log: `/tmp/thistle-item-duration-server.log`.

## Automated validation

The final implementation passed 4,222 tests through `mix test.all`, including
DBC, VMangos, and navigation integration tests. Compilation with warnings as
errors, strict Credo, formatting, and the architecture dependency ratchet
passed.

Focused tests cover exact deadlines, sub-second pause/resume, stale timers,
ownership transfer, split and gift preservation, equipment/stat cleanup,
cast interruption, quest needs, container loot closure, bank storage, timed
bags, and the native timer packet. A VMangos-tagged test checks seed duration
and flags. The strict fifteen-minute conjured threshold and bank cleanup are
automated coverage; native acceptance did not wait sixteen minutes or operate
a bank.
