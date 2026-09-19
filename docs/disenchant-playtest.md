# Disenchanting and recoverable item loot

Disenchant now completes through the normal three-second spell lifecycle.
Admission and completion both require a living enchanter and an eligible,
currently owned item. Vanilla permits any trained enchanter to disenchant
eligible equipment regardless of its level. Items without a disenchant table,
items flagged against disenchanting, foreign items, and malformed equipment
stacks are rejected.

The selected item GUID is consumed through `Inventory.Batch`, so another
instance of the same equipment cannot be removed instead. Completion rolls
the preloaded VMangos disenchant table and can grant one Enchanting point.
The vanilla skill thresholds are yellow at 20, green at 40, and gray at 60;
the trained cap still applies. Failed or interrupted attempts grant nothing.

Pending material loot belongs to the character. Claims plan inventory
placement before clearing a loot slot. Closing the window automatically
stores remaining materials when possible. Full bags retain the same rolled
rewards, which reopen on login or another Disenchant attempt. They follow
the project's existing in-memory lifetime and reset with the server.

The consumed item is absent from inventory and `ItemStore`. Pending loot
retains its snapshot solely to project the client loot source. The 1.12 client
requires that source object to exist, including after reconnecting. Opening
the window creates the detached source for its owner; closing or exhausting
the window destroys the projection. This does not restore an equippable,
tradeable, or disenchantable item.

References: `Spell::CheckCast` and `Spell::EffectDisEnchant` in
`refs/vmangos/src/game/Spells/`, `Player::UpdateCraftSkill` and
`Player::SendLoot` in `Objects/Player.cpp`, and disenchant release handling in
`Handlers/LootHandler.cpp`. Unlike VMangos's full-bag release path, unclaimed
materials are retained instead of discarded.

## Related fixes

Normal profession training previously omitted automatic starter spells.
Training now learns the DBC skill rewards appropriate to the skill value,
race, and class. Apprentice Enchanting grants Disenchant, Runed Copper Rod,
and its starter enchants. Separately trained recipes remain separate, and
rank upgrades preserve existing skill progress.

Item grants previously allowed oversized stacks, including multiple copies
of non-stackable equipment in one slot. Grants now prepare legal stacks and
commit the entire batch only if it fits. This also covers normal item grants
and loot transfers using `Player.Items.store/3`.

## Real-client acceptance

An isolated build-5875 client used level-50 Debugdruid, GUID 9. Actions went
through the client; Tidewave probes read owner and store state. Final
acceptance ran on a fresh server without live code reloads.

- Trained Apprentice Enchanting through Betty Quin's actual gossip and
  trainer UI in Stormwind. The client received the profession and starter
  spells with skill 1/75.
- Added two Aboriginal Sashes (14113). They occupied separate inventory
  slots with distinct GUIDs and stack counts of one.
- Disenchanted the first sash. The client displayed the cast bar, then two
  Strange Dust (10940) in its loot window and Enchanting increasing to 2.
  The other sash remained; the consumed item had no `ItemStore` entry.
- Closed the window without clicking the dust. Both dust were automatically
  stored, and pending loot cleared.
- Filled that dust stack to 20, then disenchanted the second sash. This roll
  produced one dust and raised Enchanting to 3. Filled the seven available
  backpack slots with separate Worn Shortswords. Clicking the dust displayed
  "Inventory is full" and retained the reward.
- Closed the window and logged out. The player owner stopped; the character
  store retained the same one-dust reward and consumed-item snapshot, with
  no source item in inventory.
- Logged back in. The loot window reopened visibly with the retained dust.
  Deleted one filler sword through the client and collected the dust.
  Final state: 21 dust, zero sashes, Enchanting 3/75, no pending loot in the
  owner or character store, both source items absent from `ItemStore`, and
  no active loot window.

An earlier client pass also interrupted a second Disenchant by moving.
The client displayed "Interrupted" and sent `CMSG_CANCEL_CAST`; the sash
remained, skill stayed at 2, and neither a cast nor pending loot remained.
Retrying succeeded. Manual collection was verified in that pass as well.

Automated coverage includes cancellation, stale and foreign targets, death
admission, empty loot tables, skill thresholds and caps, exact GUID removal,
duplicate completion and claims, full bags, source projection and cleanup,
login restoration, legal stack splitting, and transaction rollback. DBC tests
check the real spell, skill thresholds, and profession starter rewards.

## Validation and evidence

- `mix test.all`: 3,357 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Client artifacts: `/home/pikdum/.cache/thistle-wow-playtest.VpoCen/`.
- Fresh acceptance server log: `/tmp/thistle-disenchant-server-acceptance.log`.
- Owner probes: `/tmp/thistle-disenchant-acceptance-*.txt`.
- Final checks: `/tmp/thistle-disenchant-final-{tests,compile,credo}.log`.

The final server log contained no error-level entries. The isolated client
and server were stopped after acceptance. No second observer client was used;
item loot and inventory packets are private to the owning player.
