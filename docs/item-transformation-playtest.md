# Spell item transformation

Implemented in `2c1ddefb`, with the instant-use cost fix in `a78df260`, and tested
on 2026-09-21. The shared DBC effect 34 replaces the item
used to cast a spell. Actual data includes Shadowstrike/Thunderstrike,
Benediction/Anathema, and Filled/Empty Festive Mug transformations.

## Behavior and reference

The replacement has a fresh GUID and the destination template's charges and
binding rules. Permanent and temporary enchants transfer, including remaining
temporary charges and the original expiry deadline. Durability loss transfers
proportionally, rounding loss down with a minimum of one point for worn items.
Fully broken items remain broken; undamaged items remain undamaged.

`Inventory.Batch.replace/3` keeps the current carried, bank, or equipped slot.
The planner validates ownership, container compatibility, unique limits,
equipment requirements, and offhand relocation before producing a change set.
Reagents and replacement commit together through `InventoryUpdate.apply/2`.
Failures retain the source and materials. Replacement does not require an empty
slot unless changing to a two-handed weapon requires storing an offhand item.

Casting emits one owner-directed `TransformItem` effect for the casting item.
The boundary revalidates the item's spell and current ownership, loads the cached
destination template, commits the transaction, and schedules enchantment expiry
for the new GUID. Old expiry messages cannot affect the replacement. Queued
transformations settle before trade snapshots. Ordinary item-use charges are
deferred for both instant and cast-time transformations.

Reference: `refs/vmangos` at `8f4e60845`,
`src/game/Spells/SpellEffects.cpp:EffectSummonChangeItem` and
`src/game/Objects/Player.cpp:DurabilityLoss`.

## Automated acceptance

Coverage includes full backpacks, carried and bank containers, unique limits,
equipment and reputation restrictions, offhand storage, nonempty bags, reagent
rollback, chained replacements, interruption, repeat requests, lost ownership,
expired enchants, broken items, reconnect restoration, trade settlement, packet
projection, and owner-context delivery. DBC tests load all six transformation
spells. The instant charged-item regression exercises `CMSG_USE_ITEM` directly.

`mix test.all` passed **4,617 tests** after the instant-use fix. Compilation with
warnings as errors passed; strict Credo reported zero issues across 1,809 source
files. The dependency ratchet passed without allowlist changes.

## Native client acceptance

Debugwarrior (GUID 1) used an isolated build-5875 client on Programmer Isle.
Native commands trained polearms and Enchanting and supplied the weapon, rod,
and reagents. The crafting window applied Crusader; native item use applied
Wizard Oil. `.debug durability 25` supplied controlled wear. God mode was not
enabled. Tidewave probes read state only.

| Stage | Entry | Item GUID | Durability |
| --- | ---: | ---: | ---: |
| Shadowstrike before use | 17074 | 4611686018427388132 | 90/120 |
| Thunderstrike after use | 17223 | 4611686018427388138 | 90/120 |
| Thunderstrike after reconnect | 17223 | 4611686018427388138 | 90/120 |
| Shadowstrike after reverse use | 17074 | 4611686018427388139 | 90/120 |

All stages retained Crusader 1900, Wizard Oil 2627, and the same absolute oil
deadline. Client tooltips showed both enchants and wear, with the oil countdown
decreasing. The weapon model changed in each direction. The immediate reverse
attempt displayed **Item is not ready yet** and the shared one-minute cooldown;
the reverse cast succeeded after it elapsed. Final owner and CharacterStore
equipment GUIDs matched, both superseded GUIDs were absent, and exactly one
weapon variant remained.

A second scenario filled all 16 backpack slots without equipped bags. Native
use changed Filled Festive Mug 21171 (GUID 4611686018427388140) into Empty
Festive Mug 21174 (GUID 4611686018427388149) in backpack slot 4. The inventory
remained full, every other slot was unchanged, and the client showed the empty
mug with its 24-hour lifetime. Refilling at a festive keg and the priest staff
pair were not exercised natively.

The first session encountered a development hot-reload race while code was
being compiled: a background rabbit called temporarily unavailable
`Casting.cancel/1`. The server and client were stopped before final compilation.
A fresh server acceptance run separated fixed-build behavior from that reload
artifact.

The second session ran against `a78df260` without runtime compilation. It repeated
the worn weapon and full-backpack mug transformations. With all 16 slots occupied,
Shadowstrike became equipped Thunderstrike (GUID 4611686018427388145) at 90/120
durability. Filled Festive Mug became Empty Festive Mug (GUID 4611686018427388146)
in backpack slot 5, with an 86,400-second lifetime. Both source GUIDs were absent;
the owner and saved equipment GUID matched, no cast remained, and no inventory
slot became free. The client showed the new weapon and the empty mug in the full
backpack. No error-level log entries or runtime recompilations occurred in this
run. Routine unsupported account-data, raid-info, ticket, and meeting-stone
requests remain outside this feature.

Both client sessions and their X servers were stopped, as were both retained
server processes. No server or client process was left running.

Evidence for the first session is retained at
`/home/pikdum/.cache/thistle-wow-playtest.CvjKeo`, with probes and logs under
`/tmp/thistle-transformation-*`. Screenshots include `before-transform`,
`thunderstrike-cooldown`, `reverse-transform`, and `full-backpack-mug`.
The fixed-build repeat is retained at
`/home/pikdum/.cache/thistle-wow-playtest.dM2OXA`, including
`screenshots/clean-transformations.png`. Its evidence uses
`/tmp/thistle-transformation-clean-*`; final gate logs use
`/tmp/thistle-transformation-final-*`.
