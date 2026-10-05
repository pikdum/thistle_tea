# Map- and zone-bound inventory cleanup

The Alterac beacon playtest exposed a carried beacon surviving departure from
its permitted zone. All six items bind to zone 2597. The shared inventory system
now removes items whose template map or zone differs from the player's current
location. Reference behavior is `Item::IsLimitedToAnotherMapOrZone`,
`Player::DestroyZoneLimitedItem`, and the inventory login check in
`refs/vmangos/src/game/Objects/Item.cpp` and `Player.cpp`.

## Rules and ownership

Both template restrictions must match when nonzero. Online cleanup includes
equipment, equipped bags, backpack slots, keyring slots, and carried bag contents.
Bank storage remains untouched by online zone transitions, matching the reference.
Login checks all owned storage, including the bank.

Corpses and ghosts retain their items outside the permitted location. Becoming
alive triggers revalidation through the player's existing publication funnel.
This applies to the shared resurrection transitions rather than individual
resurrection entry points. Terrain observations also recheck zone changes, and
login checks precede the initial inventory packets and derived equipment stats.

The pure rule produces one `Inventory.Batch` and one planned change set. Children
are removed before a restricted bag, including unrestricted contents. Exact
consumption bypasses manual destruction restrictions. The player owner commits
once through `InventoryUpdate`, which updates quest counts, item destruction,
visible equipment, derived stats, metadata, and timers. Removing a cast item
cancels its cast; removing an open item closes its loot window.

An owner-local snapshot avoids repeated scans when inventory, location, and life
state are unchanged. Inventory publication invalidates it even when an item's
template changes without altering the player's slot fields. Zone lookup uses
terrain and the cached authoritative parent area or sole map zone; it does not
query gameplay seed data or trust a client-supplied zone for destruction.

## Automated acceptance

Tests cover combined map and zone restrictions, online versus login storage,
equipment, keys, backpack stacks, bag contents, restricted containers, foreign
ownership, corpse and ghost preservation, resurrection through the owner funnel,
cast cancellation, loot closure, client destruction, equipment stat recomputation,
snapshot invalidation, changed terrain observations, and cached parent zones.
VMangos-tagged beacon tests verify the six real zone restrictions.

## Native acceptance

An isolated build-5875 GPU client entered a fresh Alterac Valley match as
Debugwarrior through the visible Enter Battle button. An ordinary developer item
grant placed Guse's Beacon in the open backpack. Leaving the match returned the
player to Programmer Isle, removed its icon, and left an authoritative count of
zero. This reproduces and fixes the retained-item failure recorded in
[the beacon milestone](alterac-beacon-playtest.md).

For the ghost case, the developer teleport placed the player in the Alterac zone
on map 30 and another grant supplied one beacon. The existing `.die` command and
the client's Release Spirit button created a genuine ghost. Teleporting that
ghost to Programmer Isle retained the same item instance and count one, with
health one and the ghost flag set. The existing `.revive` command restored life;
the backpack then contained only its ordinary food and hearthstone, and the
beacon count became zero with its `ItemStore` row removed. This fixture exercises
inventory and death lifecycle rules and does not replace battleground gameplay
acceptance. Logout and reconnect retained the zero count in both the player
owner and `CharacterStore`, with the removed item still absent.

Screenshots and client logs remain under
`/home/pikdum/.cache/thistle-wow-playtest.r4T3ej`. The server log is
`/tmp/thistle-item-location-native-server.log`, and read-only state captures use
the `/tmp/thistle-item-location-native-*.log` paths. WoW's own AMD DRM counters
confirmed hardware rendering. The native server log contained no errors or
warnings during the accepted scenarios.
