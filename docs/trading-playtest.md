# Player trading

Implemented vanilla player trade negotiation, six transferred-item slots, gold
offers, and the seventh slot for permanent enchants, temporary coatings, and
[lockpicking or consumable keys](trade-opening-playtest.md).
Changing an offer clears both acceptances and starts the 200 ms acceptance
delay. Changing the seventh-slot target clears its queued spell.

Both player owners prepare their current inventory snapshots before completion.
The coordinator plans both inventories and commits items and recovery receipts
in one atomic ETS insertion. Each owner projects its own result. Receipts cover
player or coordinator failure during completion and are acknowledged after the
character store has the result. This is runtime ETS state, not disk persistence.

Preparation settles queued spell item costs. An item used by an unfinished cast,
its item target, or its reagents cannot be offered. Enchant costs exclude items
offered for transfer. Failed inventory plans, stale items, insufficient money,
invalid enchants, disconnection, death, and separation leave the exchange
uncommitted.

If a queued spell fails final validation, both acceptances and the failed
preview clear while the trade stays open. A new preparation identity prevents
delayed messages from the failed attempt from affecting a retry.

References: `refs/vmangos/src/game/Handlers/TradeHandler.cpp`,
`Objects/Item.cpp::CanBeTraded`, `Spells/Spell.cpp::CheckCast` and `TakeCastItem`,
and the vanilla trade packet definitions in `refs/wow_messages/`.

## Item and gold exchange

Two isolated build-5875 clients used Debughunter (GUID 7) and Debugpaladin
(GUID 2) on Programmer Isle. Gameplay actions went through the clients;
Tidewave probes read authoritative owner and store state.

- Both clients displayed matching offers: five Linen Cloth for three
  Peacebloom, with gold in both directions.
- After the hunter accepted, the paladin changed the price. The hunter's
  acceptance cleared. With only the paladin accepted, the server retained
  `[{2, 3345, true}, {7, 12345, false}]` and the trade stayed open.
- After both accepted again, the same item GUIDs changed owners and appeared
  in the recipients' backpacks. Hunter coinage changed from 100,000,000 to
  99,991,000; paladin coinage changed from 100,000,000 to 100,009,000.
  Both character stores matched their owners and neither receipt remained.
- Walking beyond trade range displayed "Trade cancelled." and closed the
  trade. Logging out during another accepted offer also canceled it without
  transferring the offered 50,000 copper.
- Reconnecting retained the completed transfer and balance. A separate
  exchange with an equipped item in slot seven kept the item with its owner.

Artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.fuPyrf/`
- `/home/pikdum/.cache/thistle-wow-playtest.MchFr6/`
- `/tmp/thistle-trade-playtest-server.log`
- `/tmp/thistle-trade-{before-compact,acceptance,after,logout,reconnect}.txt`

## Paid permanent enchantment

A fresh server used Debugpaladin as the enchanter and level-60 Debughunter as
the recipient. The hunter equipped Wristguards of Stability (19146), a
bind-on-pickup item. Its instance had owner 7 and soulbound flag 1.

- The wristguards could not enter a transferred-item slot. They appeared in
  the seventh slot without being unequipped or changing ownership.
- The enchanter selected Minor Health (7418) in the actual Enchanting window,
  then clicked the recipient's seventh-slot item. The trade window displayed
  "Enchant Bracer - Minor Health". Before acceptance, enchantment was absent
  and all five Strange Dust remained.
- Canceling this offer left the item, reagents, gold, and maximum health
  unchanged.
- Repeating and accepting committed enchantment 41 to the same wristguard
  GUID, `4611686018427388094`. One dust was consumed, and the recipient paid
  10,000 copper. Maximum health rose from 2,597 to 2,602. The item retained
  owner 7 and its soulbound flag.
- The recipient's client displayed maximum health 2,602. After logout and
  login, the owner, enchantment, balance, and health bonus were unchanged.

These characters learned the recipe through debug commands. Recipe skill
progression is covered by the pure exchange tests; this pass did not train
Enchanting through a profession trainer.

Artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.JZyDpN/`
- `/home/pikdum/.cache/thistle-wow-playtest.cr5X7T/`
- `/tmp/thistle-trade-enchant-server.log`
- `/tmp/thistle-enchant-{before,queued,canceled,completed,reconnect}.txt`

## Temporary coating and item charges

A fresh server used the same two characters and one Minor Wizard Oil (20744),
whose template supplies five charges. The paladin applied it to their own
weapon through the client before using that same bottle in trade.

- The first application put temporary enchantment 2623 on the paladin's
  weapon. Bottle GUID `4611686018427388092` remained with four charges.
- The hunter offered their equipped Barman Shanker in the seventh slot.
  Clicking it with the oil selected displayed "Minor Wizard Oil" in the
  trade preview. The weapon was still unmodified and the bottle still had
  four charges before acceptance.
- Accepting both sides coated weapon GUID `4611686018427388041`, retaining
  owner 7. The same bottle remained with owner 2 and three charges. Neither
  recovery receipt nor trade session remained.
- The recipient's weapon tooltip displayed "Minor Wizard Oil (30 min)".
  Both players logged out and back in; the same item GUIDs, ownership,
  remaining charges, and active coating survived. The remaining duration
  continued decreasing rather than restarting. The bottle's client tooltip
  displayed "3 Charges" after reconnecting.

This pass verified application and reconnect behavior. Expiry and depletion
are covered by deterministic tests; the client pass did not wait 30 minutes
or use all five charges.

Artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.m9jCjc/`
- `/home/pikdum/.cache/thistle-wow-playtest.bJpMcj/`
- `/tmp/thistle-trade-coating-server.log`
- `/tmp/thistle-oil-{owned,queued,completed,reconnect}.txt`

## Related fixes

Inventory placement previously reloaded an existing item instance and could
restore its former owner or pre-merge stack count. Placement now uses the
incoming snapshot throughout the operation. Tests cover complete and partial
stack merges, item identity, and swaps between full backpacks.

New bind-on-pickup and quest item instances now receive their soulbound flag.
They previously depended on equipment binding, which left carried items
tradeable. Bind-on-equip and bind-on-use items retain their separate rules.

Item use now spends signed charges instead of destroying a multi-charge item
on its first use. Negative-charge items disappear on their final application;
positive-charge items remain empty and reject further casts. Ordinary item
use, owned-item enchants, and trade enchants share the charge planner.

## Validation

Final checks after stopping both clients and the local server:

- `mix test.all`: 3,725 passed, including DBC, VMangos, and map integration tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: passed with zero issues.
- `mix format --check-formatted`: passed.

Automated trade coverage includes packet registration and encoding, acceptance
invalidation, capacity and money limits, stack merging, bound items, stale
inventory snapshots, spell costs, temporary and permanent enchants, owner or
coordinator failure, and idempotent receipt recovery. The architecture
dependency allowlist was not expanded.

The playtest clients and server are stopped. Session artifacts were retained.
