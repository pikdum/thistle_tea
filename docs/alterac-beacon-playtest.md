# Alterac Valley beacons

The six rescued wing commanders now offer a beacon alongside their named air
assault order. Reference behavior comes from
`refs/vmangos/src/scripts/battlegrounds/battleground_alterac.cpp`, the seeded
item and object templates, and the build-5875 spell and lock records.

## Issuing and planting

An admitted friendly player with Neutral or better standing can take a beacon
from a rescued, supplied commander in an active match. Issuance resets that
fleet's entire supply count. Inventory planning precedes the serialized match
claim, so full bags, an existing unique beacon in the bank, or a stale selection
cannot spend supplies or create another item. The successful transaction sends
the normal item receipt and closes gossip. Refilling the fleet permits another
grant; a named assault already ordered for that fleet prevents further grants.

| Commander | Granted item | Plant spell | Beacon object |
| --- | --- | --- | --- |
| Guse | 17324 | 21355 | 178545 |
| Jeztor | 17325 | 21370 | 178547 |
| Mulverick | 17323 | 21371 | 178549 |
| Slidore | 17506, Vipore's Beacon | 21730 | 178724 |
| Vipore | 17507, Slidore's Beacon | 21729 | 178725 |
| Ichman | 17505 | 21728 | 178726 |

The crossed Slidore and Vipore item names follow the reference gossip handlers.
Items are unique and consumed on successful planting. All six share item
cooldown category 951: thirty minutes per player. The reference defines fleet
timer values but never calls the method that returns them; this implementation
does not add a fleet cooldown. Planting uses the existing five-second item cast
and spell focus checks, and also requires an active Alterac match and the
beacon's matching team.

## Beacon lifecycle

Planted objects publish level zero, empty ownership, and faction 83 for Alliance
or 84 for Horde. They outlive the planter's logout and the ordinary summoned
object duration. After sixty seconds, a waiting beacon summons one Aerie
Gryphon (13161) or War Rider (13178) thirty yards above its position, then removes
itself. These generic creatures use their seed templates and existing mob AI;
the named attackers' separate spell kit is documented in
[the named assault notes](alterac-air-assault-playtest.md). Their corpse despawns
after ten seconds.

An enemy can right-click the beacon to cast Attacking (8386), the client's
five-second open-lock spell for lock type 14. Movement interrupts that cast and
preserves the beacon. Completion rechecks the actor's world, actual range,
living state, active match admission, team, lock, and beacon deadline before
removing it. Direct object use cannot bypass the cast. A disabled beacon never
summons its attacker. Match teardown removes independent beacons with the rest
of the instance.

## Automated acceptance

Pure tests cover all six mappings, faction and ownership projection, exact
deadlines, one summon, enemy-only disarming, and planting restrictions. Inventory
tests cover successful receipts, duplicate selection, full bags, bank uniqueness,
and concurrent stockpile claims. An owner-process test proves that an early timer,
caster departure, and player-owned summon cleanup leave an independent beacon
intact. Separate VMangos and DBC tests verify item charges and cooldowns, spell
overrides, templates, gossip texts, locks, and the disarm cast time.

## Native acceptance

Two isolated build-5875 GPU clients exercised a live match. The Horde shaman
rescued Guse through her full seventy-four-point route. Ninety ordinary quest
exchanges consumed ninety Soldier's Flesh, credited ninety fleet supplies and
ninety Frostwolf reputation, and exposed the beacon dialogue. A temporary client
frame handled the normal quest progress and reward events during those exchanges.
Selecting that visible dialogue produced one carried beacon and reset supplies
to zero.

Planting at the base correctly failed with Requires Eastern Crater and preserved
the item. At the crater, successful planting consumed it. A read-only sampler
observed a waiting beacon with no owner after the shaman logged out, followed by
one generic rider approximately sixty seconds after beacon creation. Reconnect
retained match state and the item cooldown. The rider appeared at beacon height
plus thirty yards; the native target frame and model confirmed visibility.
Lethal damage through the existing developer command removed its corpse after
ten seconds.

Additional disarm fixtures used the existing `.additem` and `.debug cooldowns`
commands to avoid waiting thirty minutes between attempts. A fresh Alliance mage
right-clicked a Horde beacon and displayed the Attacking cast bar. Movement
cancelled the first cast; the owner retained its waiting beacon. A second cast
completed and removed it, and no attacker appeared after the original deadline.
An earlier attempt made after an Alliance character went AFK and left the match
was discarded. Both clients remained active during the successful repeat.

The final fresh match repeated the rescue, ninety turn-ins, item receipt, plant,
interruption, and completed disarm with the corrected fleet state. Another ninety
turn-ins permitted an immediate second grant while planting still displayed Item
is not ready yet. After clearing the item cooldown for the fixture, leaving both
clients with a waiting beacon removed the match and every entity in its instance,
more than fifty-seven seconds before that beacon's deadline. A carried spare
beacon remained outside Alterac; this exposed missing shared zone-bound inventory
cleanup and is being fixed in the following inventory milestone.

For reproducible crater positioning, teleport above the terrain with
`.go xyz -285 -320 35` and allow the client to land before planting. The enemy
used `-281 -320 35`, within four yards. Supplying a below-terrain height to the
developer teleport can make the client fall through the ground.

Evidence is retained under the helper-owned sessions
`/home/pikdum/.cache/thistle-wow-playtest.RbLf97` and
`/home/pikdum/.cache/thistle-wow-playtest.LUHW8A`, with the server log at
`/tmp/thistle-av-beacon-native-server.log`. A live code replacement invalidated
an existing match callback, so that update attempt was discarded and the final
code was tested after a server restart. The fresh run is logged separately at
`/tmp/thistle-av-beacon-final-native-server.log`. Screenshots include the granted item,
visible rider, enemy cast bar, and completed disarm. WoW's own DRM counters
confirmed hardware rendering for both clients. The only validation warning was
the deliberately attempted plant outside its required focus area in the first
run; the final fresh server log contained no errors or warnings.
