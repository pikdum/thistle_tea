# Equipment set bonuses

Equipped item templates now contribute to DBC `ItemSet` thresholds. Each
eligible set spell becomes one passive aura source, separate from ordinary
buffs and from enchantments that grant the same spell. Set definitions are
preloaded into ETS; threshold and skill eligibility rules are pure.

`EquipmentAuras` replaces the enchantment-only reconciler and uses the shared
aura transition path for stats, combat procs, spell modifiers, and movement.
Retained sources keep their proc cooldowns. Removing pieces removes only the
bonuses whose thresholds are no longer met. Backpack and bank contents do not
count as armor pieces; broken equipped pieces still count, matching Vanilla.
Set passives survive death and are reconciled on equipment changes and login.
The player owner also rechecks skill and form requirements when publishing
state, including after client commands.

References: `AddItemsSetItem` / `RemoveItemsSetItem` in
`refs/vmangos/src/game/Objects/Item.cpp`, and `ApplyEquipSpell`,
`UpdateEquipSpellsAtFormChange`, and `_ApplyAllItemMods` in
`refs/vmangos/src/game/Objects/Player.cpp`.

This implements set activation and lifecycle using the existing spell engine;
it does not add bespoke scripts for every set-specific dummy effect.

## Playtest-discovered inventory fix

Equipping Bloodvine gear repeatedly prompted for binding because the server
never set the item-instance soulbound flag. Equipment and bag-slot inventory
transactions now bind eligible items as part of their successful result.
Unequipping retains the flag, unrelated instance flags are preserved, and a
failed equip leaves the original item untouched. Mail rejects bound
attachments without transferring the item or charging postage.

Reference: `Player::VisualizeItem` and the bag-position binding rule in
`Player::_StoreItem` in the same VMangos source.

## Automated coverage

- Cumulative thresholds, duplicate bonus rows, independent sets sharing a
  spell, unknown sets, profession requirements, and inventory scope.
- Independent ordinary/enchantment/set sources, idempotent reconciliation,
  uncancelable passives, death/resurrection, and proc cooldown preservation.
- Set procs through combat reactions, modifier application/removal, and form
  restrictions.
- Real DBC Gladiator armor/defense bonuses, Bloodvine's two percentage points
  of spell crit, Spider's Kiss's proc holder, and the feral movement bonus.
- Owner publication after profession changes and Cat Form entry/exit: the
  real form-restricted bonus changes run speed from 7.0 to 8.05 and back.
- Binding through equip/unequip/re-equip and bag equipment, failed equip
  atomicity, and rejection of bound mail attachments.

## Real-client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled Debugdruid
against a fresh local server after the binding fix. All training, equipment
changes, wear, logout, and death actions came from the client. Runtime probes
read the owning process and computed the normal spell-cast snapshot.

- At level 60, equipping Bloodvine Vest (19682), Leggings (19683), and Boots
  (19684) without Tailoring left the set inactive. The spell-crit snapshot was
  5.587147634174887%, with 135 Intellect.
- Trained Apprentice Tailoring through Eldrin's gossip and trainer UI, then
  used `.debug professions` to reach 300. The tooltip displayed the active
  green three-piece bonus. Exactly one set source `{421, 18382}` appeared,
  and spell crit rose to 7.587147634174887% without changing Intellect.
- The Boots tooltip displayed `Soulbound`. Unequipping removed the set
  source; re-equipping required no binding confirmation and restored exactly
  one source and the original crit value.
- `.debug durability 100` broke all three pieces. Their individual stats
  stopped contributing: Intellect fell to 100 and armor to 36. The set source
  remained and the spell-crit snapshot retained its two-point bonus at
  7.001961210499917%.
- Logout removed the owner process. Login created a different owner with
  the same broken pieces, Tailoring 300, and exactly one set source.
- `.die` reduced health to zero while retaining the set passive. Spirit
  release also retained the passive. After the reclaim delay, accepting corpse
  resurrection restored health, the normal character model, and run speed
  7.0; the broken pieces and single set bonus remained.

The client acceptance exercised Bloodvine's skill gate and lifecycle. Other
sets' thresholds, combat procs, modifier packets, skill loss, and form-dependent
speed are covered by automated tests; no second observer client was used.
No error-level server logs occurred during the final run. Existing unsupported
account-data, raid-info, GM-ticket, time-query, meeting-stone, and cancel-trade requests were
logged during ordinary client startup. The helper-owned client and retained
server were stopped after acceptance.

Final client artifacts:
`/home/pikdum/.cache/thistle-wow-playtest.x706Fo/screenshots/`.
Runtime evidence: `/tmp/thistle-item-sets-final-*.txt`.
Server log: `/tmp/thistle-item-sets-binding-server.log`.
The earlier run that exposed binding is retained under
`/home/pikdum/.cache/thistle-wow-playtest.ApIZQm/`.

## Validation

- `mix test.all`: 3,494 tests passed after the binding fix.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Full-suite log: `/tmp/thistle-item-sets-final-tests.log`.
