# Trade-slot unlocking

The seventh trade slot accepts Pick Lock and consumable opening keys while
retaining the target item's owner. Enchantments and opening spells share
`Trade.Spells`, the two inventory plans, and the existing recovery receipts.
Previewing validates requirements without spending charges, gold, or skill
gains. Final preparation revalidates both current player snapshots and commits
the unlock, costs, payment, and skill gain together.

The caster does not open the other player's loot. The owner opens the unlocked
container later through the normal private inventory-loot path. Item-instance
flags, ownership, and the original item GUID survive the service.

## Reference behavior

- `refs/vmangos/src/game/Spells/Spell.cpp::CheckCast` accepts opening another
  player's item through `TRADE_SLOT_NONTRADED`, validates the lock, and queues
  the spell until acceptance.
- `Handlers/TradeHandler.cpp::HandleAcceptTradeOpcode` revalidates triggered
  trade spells and clears failed spell offers and acceptance without closing
  the trade window. Triggered trade casts skip the ordinary timed opening
  attempt's orange-difficulty failure roll.
- `Spells/SpellEffects.cpp::EffectOpenLock` sets the instance unlock flag and
  excludes item casts from skill gain. `Objects/Player.cpp::SendLoot` resolves
  an inventory item's loot from the caster's own inventory, so a service must
  not expose the partner's container contents to the caster.

## Native acceptance

Two isolated build-5875 clients used Debugrogue (GUID 3) and Debugwarrior
(GUID 1) on Programmer Isle against commit `e53a85ab`. All gameplay actions
went through the clients. Tidewave probes only read owner and store state.
Debug commands supplied boxes and tools and raised the rogue to level 60.

### Paid lockpicking and retry

- The warrior offered Heavy Junkbox `4611686018427388133` in the seventh
  slot and one gold. The rogue selected Pick Lock and clicked that item.
  Both clients displayed the spell preview. The item remained locked with
  owner 1, contents remained ungenerated, balances remained 100,000,000 copper,
  and Lockpicking remained 250/300.
- Canceling retained the same locked item, balances, and skill.
- After queuing again, the rogue deleted Thieves' Tools through the client.
  Accepting both sides displayed "Item is gone", cleared the spell preview
  and both acceptances, and kept both trade windows open. The item stayed
  locked and no payment or skill gain occurred.
- Restoring the tools, selecting Pick Lock again, and accepting completed the
  service. The same item retained owner 1 and gained unlocked flag 4. The
  warrior had 99,990,000 copper and the rogue had 100,010,000; Lockpicking rose
  to 251. Both clients displayed completion. No trade session or recovery
  receipt remained, and neither player had a loot session.
- Both players logged out and back in. Item identity, ownership, unlock flag,
  balances, and skill remained unchanged. The warrior then opened the box,
  collected 565 copper and its three material stacks, and released the empty
  container. The source item was consumed. The rogue never received its loot.

### Consumable key

- The rogue trained Apprentice Blacksmith through Dane Lindgren's actual
  gossip and trainer windows, then used `.debug professions` to raise the
  trained skill to 300. The fixture supplied two Silver Skeleton Keys.
- Using a Silver Skeleton Key on the warrior's other Heavy Junkbox displayed
  "Skill not high enough". Its strength was evaluated independently of the
  rogue's 251 Lockpicking. Both keys remained and no spell was queued.
- Offering Ornate Bronze Lockbox `4611686018427388135` instead displayed
  "Silver Skeleton Key" in the preview. Canceling kept it locked and retained
  both keys.
- A subsequent valid exchange unlocked that same Bronze Lockbox with owner 1,
  consumed exactly one key from stack `4611686018427388140`, and left
  Lockpicking at 251. Its contents remained ungenerated until the owner opened
  it. No recovery receipt remained.
- Reconnecting both players retained the unlocked box and one remaining key.
  The warrior opened the box, received its Short Ash Bow through the normal
  loot window, and released it. The box was consumed and both loot sessions
  were clear.

Artifacts retained:

- `/home/pikdum/.cache/thistle-wow-playtest.fgWYs7/` (rogue)
- `/home/pikdum/.cache/thistle-wow-playtest.n4ZpWy/` (warrior)
- `/tmp/thistle-trade-opening-server.log`
- `/tmp/thistle-trade-opening-{initial,preview,canceled,retry-live,completed,reconnect,owner-loot,looted}.txt`
- `/tmp/thistle-trade-opening-{weak-key,key-preview,key-canceled,key-ready,key-unlocked,key-retained,keyed-loot,final}.txt`

No owner or network errors or unsupported trade/opening messages appeared.
Existing unrelated account-data, raid-info, ticket, and meeting-stone warnings
remain. Both clients and the server were stopped before documentation changes.

## Automated validation

- `mix test.all`: 4,186 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`: passed.

Regression tests cover bound target ownership, deferred payment and skill,
missing tools, unlearned spells, death, lost skill and key proficiency, stale
items and lock metadata, key strength and charges, offered-cost exclusion,
full-inventory rollback, disconnect during preparation, coordinator-loss
recovery, and exactly-once receipt application. Retry tests also reject stale
queued casts, preparation replies, aborts, and timeouts from the failed attempt.
Existing permanent-enchant and coating tests remain green. The architecture
dependency allowlist was not expanded.
