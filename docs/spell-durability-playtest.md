# Spell-driven durability damage and repair

Spell effects 111 and 115 now apply flat and percentage durability changes through the existing inventory transaction boundary. This enables Melt Weapon, Force Reactive Disk's shield wear, Shredder Armor Melt, and Corrupt Weapon without introducing another equipment-state writer. Negative flat amounts repair items, including Corrupt Weapon's restoration spell.

Implementation commit: `cb34f418`. Reference: `refs/vmangos` revision `8f4e60845`, `Spell::EffectDurabilityDamage`, `Spell::EffectDurabilityDamagePCT`, `Player::DurabilityPointsLoss`, and the corresponding all-items methods. The build-5875 execution-log layout comes from `refs/wow_messages/wow_message_parser/wowm/world/spell/smsg_spelllogexecute.wowm`.

## Behavior

The spell's signed miscellaneous value selects its inventory scope: `-1` means equipped items, values below `-1` include carried inventory and bag contents, and nonnegative values select equipment or equipped-bag slots. Backpack and bank indices are invalid as individual spell selectors. Bank contents are excluded from carried-item effects.

Positive flat amounts subtract points, negative flat amounts restore points, and both clamp to the item's durability bounds. Positive percentages use maximum durability, round down, and remove at least one point. Indestructible items remain unchanged. Empty slots and non-player targets do nothing.

Typed durability requests retain the target, caster, and spell identities through explicit owner-context delivery. Each request plans its affected items together using `Inventory.Batch` and commits once through `InventoryUpdate`. Existing equipment synchronization removes or restores stats, enchants, procs, and weapon usability. Spell repairs do not charge money. Durability effects remain applicable to dead players, including when an earlier effect in the same spell kills the target.

Flat effects emit `SMSG_SPELLLOGEXECUTE` with a packed caster GUID, full target GUID, selected item entry (or the all-items sentinel), and the reference payload's unknown-field sentinel. Percentage effects do not emit that log. Testing exposed a separate broadcast issue: integer GUID sources lost source attribution and self-exclusion. Commit `f2f70911` fixes that while preserving world isolation.

## Automated acceptance

`mix test.all` passed **4,813 tests**. Compilation passed with `--warnings-as-errors`, and strict Credo found zero issues across **1,872 files**. The architecture dependency allowlist is unchanged.

Tests cover loaded DBC effect types, signed amounts and selectors, flat/percentage calculations, equipped versus carried/banked items, invalid and empty slots, non-player targets, dead targets, lethal-effect ordering, broken-equipment stat/proc restoration, no repair payment, runtime-store updates, explicit owner routing, mismatched-owner rejection, exact packet bytes, and broadcast source/world handling. Force Reactive Disk, Melt Weapon, and Corrupt Weapon's specific repair spell have DBC-backed coverage; their original NPC/item trigger chains were not played through in this native run.

## Native client acceptance

Session: `/home/pikdum/.cache/thistle-wow-playtest.jyV7SN`, isolated WoW 1.12.1 build 5875. Character: level-50 `Debughunter`, GUID 7, on Programmer Isle. All mutations used native casts, existing developer spell-learning commands, and logout/login. Tidewave reads inspected authoritative state only.

The initial Bow of Searing Arrows (entry 2825, item GUID `4611686018427388043`) had 90/90 durability and server ranged damage 145.5534–186.5534. Native Corrupt Weapon, spell 23437, reduced only that bow to 0/90. The remaining sampled equipment stayed at full durability, ranged damage became zero, and both the player owner and `CharacterStore` marked only `:ranged` as broken. The native character sheet rendered its zero-damage fallback as 1–1.

After a complete logout, the player actor was absent while the runtime store retained the same broken item. Re-entry restored the same item GUID, 0/90 durability, zero authoritative ranged damage, and unchanged ammo selection. The actual inventory tooltip visibly displayed red **Durability 0 / 90** in `reconnected-bow.png`.

Casting the existing repair spell `rf` (5978, negative flat damage across carried items) restored the bow to 90/90 and restored ranged damage to 145.5534–186.5534. Broken-equipment state cleared in the owner and store. The tooltip displayed **Durability 90 / 90** in `repaired-bow.png`. Money stayed at 100,000,000 copper and selected ammunition stayed at entry 11285.

The native test spell Durability Damage (PT), 16722, then applied its three effects in order: five points across carried gear, 50% of maximum durability from the main hand, and one point from equipped gear. The client cast used its spellbook index because the ordinary name command did not resolve the parenthesized name. The server logged the accepted spell ID, and the resulting values were:

| Slot | Before | After |
| --- | ---: | ---: |
| Head | 50/50 | 44/50 |
| Chest | 100/100 | 94/100 |
| Main hand | 65/65 | 27/65 |
| Off hand | 65/65 | 59/65 |
| Ranged | 90/90 | 84/90 |

The main-hand result is `65 - 5 - floor(65 × 0.5) - 1 = 27`. Its native tooltip confirms **Durability 27 / 65** in `worn-mainhand.png`. A final `rf` cast restored every sampled item to maximum without payment. The final owner/store read had no broken equipment and restored ranged damage.

The server log contained no errors or cast-validation failures. Existing login warnings were limited to account-data, raid-info, GM-ticket, and meeting-stone requests. The helper-owned client, X server, and BEAM server were stopped after acceptance. A second observer client was not used; observer packet attribution and world isolation are automated evidence.

Artifacts:

- Server log: `/tmp/thistle-spell-durability-server.log`.
- State reads: `/tmp/thistle-spell-durability-{baseline,broken,offline,reconnected,repaired,multiple-effects,final}.json`.
- Checks: `/tmp/thistle-spell-durability-{focused,tests,compile,credo}.log`.
- Screenshots: the session's `screenshots/` directory, especially `reconnected-bow.png`, `repaired-bow.png`, and `worn-mainhand.png`.

Full vanilla feature parity remains ongoing.
