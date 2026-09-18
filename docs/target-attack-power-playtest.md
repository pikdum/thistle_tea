# Target-dependent attack power

Weapon attacks now use creature-specific melee and ranged attack power from
slaying equipment and consumables. The loader recognizes auras 102 and 131,
including Elixir of Demonslaying, Seal of the Dawn, Argent Avenger, and Champion
of the Dawn. Aura 165 supplies the corresponding target-side melee bonus;
Hunter's Mark continues to supply the ranged bonus through aura 127.

A pure rule snapshots the attacker's creature masks and stack counts. Each
recipient combines matching bonuses with its current target-side debuffs.
The result contributes weapon-speed damage without changing displayed attack
power or weapon damage. Normalized weapon abilities use normalized speed;
auto-attacks use unhasted weapon speed, with off-hand penalties and outgoing
damage modifiers. Armor, avoidance, critical hits, absorption, and death still
run through the existing damage paths. Flat school-damage abilities do not
gain an extra weapon-speed term.

The VMangos reference is `SpellCaster::MeleeDamageBonusDone` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`. Its target-dependent term is
added after weapon-percentage scaling, which also corrects the previous
Hunter's Mark ordering for percentage weapon abilities.

## Related fixes

Existing damage-versus and critical-versus rules read `creature_type` from a
top-level field absent from actual mob structs. The new shared mask lookup
reads the creature component and uses the existing character shapeshift rule.
Real mobs now receive their matching bonuses, and druids in beast forms use
the beast mask.

Client testing exposed an unsupported `CMSG_AUTOSTORE_BAG_ITEM` packet when
using `PutItemInBackpack` to unequip a weapon. The packet now dispatches through
the player inventory boundary and a pure inventory transaction. It honors the
requested bag, stack merging, capacity and bag-family rules, nonempty-bag
restrictions, and live banker authorization for either end of a bank transfer.
No partial inventory mutation is committed on failure. The packet and behavior
references are the local wow_messages specification and VMangos
`WorldSession::HandleAutoStoreBagItemOpcode`.

## Automated acceptance

Tests use real entity structs and cover multi-type masks, separate melee and
ranged amounts, stack scaling, target debuffs, shapeshift masks, weapon speed,
normalization, off-hand scaling, outgoing multipliers, armor, critical hits,
misses, cancellation, expiry, death, and unchanged displayed stats. DBC-tagged
tests exercise four real slaying spells across all nine creature types.
Additional regressions cover actual mob types in existing damage and critical
modifiers, and the new inventory packet's transfer and authorization paths.

## Real-client acceptance

An isolated build-5875 client controlled level-50 Debugwarlock on Programmer
Isle. Existing `.learn`, `.debug skills`, and god-mode commands provided setup;
all casts, attacks, and inventory actions came through the client. Runtime
probes only read entity-owner state.

The final client used `PickupInventoryItem(16); PutItemInBackpack()` to unequip
the weapon. The owner moved GUID 4611686018427388019 to backpack slot `inv6`,
cleared `mainhand`, changed attack time from 2,900 to 2,000 ms, and recomputed
weapon damage from 112.007–166.007 to 5.143–6.143. The packet reached the new
handler without an unsupported-command warning.

Against the level-50 Skeletal Flayer (GUID 17379390991937510294), ordinary
unarmed hits removed 3–4 health. Argent Avenger activated at 2.07 seconds in
the sampler, adding 200 target-dependent attack power. Five consecutive hits
removed 21 health each. At 12.03 seconds the aura expired; subsequent hits
returned to 3–4 damage. Displayed attack power stayed 29 and displayed weapon
damage stayed 5.143–6.143 throughout. The client displayed the cast effect and
combat damage while the owner sample independently recorded the health loss.

The first inventory pass exposed the missing dispatch registration after the
codec and transaction were implemented. The regression now enters through
`Dispatch.to_message/1`, and the final server includes that correction.

## Validation

- `mix test.all`: 3,212 passed, including DBC, VMangos, and map integrations.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Validation logs: `/tmp/thistle-target-ap-accepted-{tests,compile,credo}.log`.
- Final server: `/tmp/thistle-target-ap-accepted-server.log`.
- Inventory proof: `/tmp/thistle-target-ap-accepted-inventory.txt`.
- Combat sequence: `/tmp/thistle-target-ap-accepted-combat.txt`.
- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.lAkGJj/screenshots/`.

Off-hand, ranged, shapeshift, multi-mask, stack, and armor/critical combinations
were verified by automated tests rather than additional client sessions.

A second client sequence cancelled Argent Avenger 5.57 seconds after applying
it. The owner immediately lost the 200-point bonus, and the next hit returned
to 3 damage. A separate death sequence disabled god mode, cast the buff, then
used `.die` while it was active. At 4.54 seconds health became zero, combat
became false, the bonus became zero, only racial passives remained, and
`Aura.next_event_at/1` returned nil. This state persisted for the remaining
sample. The client displayed the release-spirit prompt and a combat-log line
for the preceding 21-damage hit.

- Cancellation sample: `/tmp/thistle-target-ap-accepted-cleanup.txt`.
- Death sample: `/tmp/thistle-target-ap-accepted-death.txt`.
- Visible combat evidence: `boosted-hits.png` and `death-confirmed.png` in
  the final screenshot directory.

No owner errors or cast-validation failures occurred in the final session.
Login still emitted existing account-data, raid-info, GM-ticket, time-query,
and meeting-stone unsupported-message warnings. All helper-owned clients and
servers were stopped; evidence files were retained.
