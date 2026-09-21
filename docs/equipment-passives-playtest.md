# Passive on-equip item spells

Equipped items now supply supported passive aura effects through the shared
equipment-aura lifecycle. Previously, on-equip spells contributed only the
stat types recognized by `EquipmentStats`; crit, hit, dodge, mana regeneration,
skill bonuses, and proc holders were otherwise skipped.

`EquipmentSpells` identifies all five on-equip spell slots. Existing aggregate
effects remain canonical equipment bonuses; remaining effects become hidden
passive holders identified by item GUID and spell ID. This keeps attack power,
spell power, and other existing bonuses from applying twice. Identical effects
from different items stack independently, and unrelated inventory changes or
slot moves retain proc cooldowns. Ordinary auras, enchantments, and set bonuses
keep their separate identities.

Equipment synchronization excludes broken items, includes equipped bags, and
honors spell form restrictions for both aggregate stats and aura holders.
Unequipping removes the corresponding source, repair restores it, and reconnect
reconciles it from equipped items. Passives survive death and cannot be canceled
through the buff interface. Crit, dodge, and parry aura bonuses now reach the
player's displayed combat percentages as well as the combat consumers.

The proc follow-up treats ordinary weapon swings as physical damage when
checking a proc's school restriction. Heart of Wyrmthalak otherwise received its
holder but could not proc on an ordinary swing. References were
`Player::ApplyItemEquipSpell`, `Player::ApplyEquipSpell`,
`Player::UpdateEquipSpellsAtFormChange`, and
`SpellMgr::IsSpellProcEventCanTriggeredBy` in `refs/vmangos/src/game/`.

This change connects item passives to aura types supported by the shared engine.
Arbitrary non-aura on-equip effects remain outside this implementation.

## Native client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client exercised native inventory,
merchant, casting, shapeshift, combat, and logout/login actions. Read-only
Tidewave probes checked the owning entities. Warrior combat used `.tgm`; mage
casts used normal resource costs. Characters were raised to level 60 through
the existing developer command.

### Equipment, durability, and reconnect

Debugwarrior equipped Blackhand's Breadth (13965), Savage Gladiator Chain
(11726), and Verek's Collar (11755). The chest and trinket each supplied a
separate hidden spell-7598 holder with 2% crit. The necklace supplied 1% dodge.
The retained Dawn's Edge supplied another 1% crit.

| State | Client crit | Client dodge | Authoritative result |
| --- | ---: | ---: | --- |
| Equipped | 10.75% | 6.75% | Both crit sources and the necklace active |
| All durable equipment broken | 6.00% | 5.00% | Chest and weapon effects removed; trinket and necklace retained |
| Merchant repair-all | 10.75% | 6.75% | Durability and equipment effects restored |
| Trinket and necklace unequipped | 8.75% | 5.75% | Exactly the removed sources disappeared |
| Logout/login | 8.75% | 5.75% | Remaining sources, repaired durability, and money restored |

The Attack spell tooltip and `GetDodgeChance()` agreed with the server fields.
Corina Steele's repair-all charged 53,812 copper. Logout removed the player
owner while the runtime character store retained the equipment state; login
restored the same sources and 99,946,188 copper.

### Proc, mana regeneration, and form restrictions

- Heart of Wyrmthalak (22321) loaded spell 27656 with its physical-school
  restriction and one-proc-per-minute rule. Ordinary melee combat against
  Skeletal Flayers produced the native message, "Your Flame Lash hits Skeletal
  Flayer for 142 Fire damage." Unequipping removed its holder while preserving
  the other item passives. This checks an actual proc, not a statistical rate
  estimate; deterministic tests cover the chance calculation and cooldowns.
- Debugmage's seeded equipment supplied 22 MP5. After a real rank-1 Arcane
  Intellect cast spent 60 mana, regeneration during the five-second rule was
  8 mana per two-second tick. Equipping Tooth of Gnarr (13141) raised MP5 to 25:
  mana went 4,443 -> 4,383 -> 4,393 -> 4,403 before ordinary spirit regeneration
  resumed. Unequipping restored 22 MP5 and the 8-mana ticks. Native `UNIT_MANA`
  events and timed owner samples agreed; interrupted spirit regeneration was
  zero throughout these comparisons.
- Debugdruid learned One-Handed Maces and equipped Hammer of Bestial Fury
  (20580). Its 154 feral attack power was absent in humanoid form, active in Cat
  Form, and absent again after leaving Cat Form. `UnitAttackPower()` and the
  owner both reported total AP 182 -> 567 -> 182. The canonical equipment AP
  contribution changed 0 -> 154 -> 0.

No gameplay owner or network errors appeared. Ordinary login activity emitted
the existing unimplemented account-data, raid-info, GM-ticket, and meeting-stone
warnings. All helper-owned clients and local servers were stopped afterward.

## Validation and evidence

`mix test.all` passed all 4,318 tests. `mix compile --warnings-as-errors` passed,
and `mix credo --strict` reported no issues. Regression coverage includes mixed
stat/aura spells, independent stacking and removal, bags versus storage,
break/repair transactions, death and reconnect, form changes at the owner
publication boundary, skill projection, hit/crit consumers, proc cooldown
preservation, and missing spell data. DBC and VMangos tests remain separately
tagged; the DBC proc test uses a rule fixture verified by the VMangos test.

- Implementation: `ad53fb87`; physical-school proc fix: `d71ddf35`.
- Equipment screenshots: `/home/pikdum/.cache/thistle-wow-playtest.ZhnBuI/screenshots/`.
- Proc, mana, and form screenshots: `/home/pikdum/.cache/thistle-wow-playtest.TM0ZoM/screenshots/`.
- Server logs: `/tmp/thistle-equip-server.log` and `/tmp/thistle-equip-final-server.log`.
- Equipment probes: `/tmp/thistle-equip-{equipped,broken,repaired,removed,logout,reconnected}.txt`.
- Mana probes: `/tmp/thistle-equip-mana-{without,equipped,removed}.txt`.
- Form probes: `/tmp/thistle-equip-form-{humanoid,cat,restored}.txt`.
- Final gates: `/tmp/thistle-equip-proc-final-{all,compile,credo}.log`.
