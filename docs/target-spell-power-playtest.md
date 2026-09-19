# Creature-specific spell power

Aura 180 (`mod_flat_spell_damage_versus`) now supplies spell power against
matching creature types. This enables Rune of the Dawn, undead/demon slaying
spell gear, Champion of the Dawn, and Holy Mightstone through the shared
spell-damage calculation.

The caster snapshot combines conditional equipment bonuses and active auras,
including holder stacks. Each recipient selects its creature mask, adds the
matching amount to ordinary school spell power, and applies the existing
coefficient once to the combined total. This preserves coefficient rounding,
low-rank penalties, fixed-damage exclusions, and ordinary critical-hit,
resistance, absorption, and life-leech handling. Players use their current
humanoid or shapeshifted creature type.

Direct damage reads the recipient when the spell lands. Periodic damage and
leech retain the amount calculated at application. New casts and refreshed
periodic effects use the new caster snapshot after equipment or aura changes.
Healing and displayed unconditional school damage do not gain the bonus.

Equipment uses `EquipmentStats` and `unit.equipment_bonuses`; active buffs use
the normal aura lifecycle. Both feed the pure `TargetSpellPower` calculation.
No new database queries, runtime stores, or development commands were needed.
The reference is `SpellCaster::SpellDamageBonusDone` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`, especially the creature-mask
addition to `DoneAdvertisedBenefit` before `SpellBonusWithCoeffs`.

## Automated acceptance

Focused tests cover stacked and overlapping masks, equipment plus active
buffs, school selection, player shapeshifts, independent recipients,
coefficient rounding, critical hits, fixed damage, healing exclusion, direct
and periodic leech, overkill healing, periodic snapshots and refreshes,
expiry, cancellation, death, and equip/unequip resynchronization.

DBC-tagged tests verify eight real aura-180 spells across all nine creature
types, and load Rune of the Dawn's actual equip spell into equipment bonuses.

Validation passed on the feature commit:

- `mix test.all`: 3,272 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Real-client acceptance

An isolated build-5875 client controlled Debugwarlock on Programmer Isle.
Existing development commands set level 60, enabled god mode, added item
19812, and moved between the seeded enemies. Inventory actions and casts came
from the client. Tidewave probes only read entity-owner state and loaded spell
records; they did not mutate gameplay state.

- Equipping Rune of the Dawn populated trinket slot 1 and the conditional
  snapshot `[{32, 48}]`. Ordinary shadow spell power remained 12.
- Rank-1 Corruption on a Skeletal Flayer stored a 14-point periodic amount:
  `10 + trunc((12 + 48) * 0.08)`. Four ticks reduced health from 2,824 to
  2,768 in steps of 14, and the aura then expired. The client combat log and
  floating damage numbers displayed 14.
- Rank-1 Death Coil dealt 312 damage to the same undead target, reducing
  health from 2,768 to 2,456. Its level-adjusted base was 300 and its
  coefficient was 0.214: `300 + trunc(60 * 0.214)`. Its fear aura expired
  normally. The player was at full health, so this live case establishes
  leech damage; automated tests establish actual healing and overkill limits.
- With the trinket still equipped, rank-1 Corruption on the humanoid Defias
  Thug stored 10 damage per tick. Four ticks reduced health from 71 to 31.
  The client combat log displayed 10, proving the undead mask did not apply.
- Unequipping through `PickupInventoryItem(13); PutItemInBackpack()` cleared
  the trinket slot and conditional snapshot. A new Corruption cast on a
  Skeletal Flayer returned to 10-point ticks.

No gameplay crashes or cast-validation failures appeared. The server logged
existing unimplemented client housekeeping requests for account data, raid
information, tickets, time, meeting stones, and trade cancellation. These did
not affect the tested inventory or spell paths. A second observer client was
not used. The helper-owned client and local server were stopped afterward.

## Evidence

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.vDF90d/screenshots/`,
  including `corruption-equipped.png`, `corruption-humanoid.png`, and
  `corruption-unequipped.png`.
- Authoritative samples: `/tmp/thistle-spell-power-equipped.txt`,
  `/tmp/thistle-spell-power-leech.txt`, `/tmp/thistle-spell-power-humanoid.txt`,
  and `/tmp/thistle-spell-power-unequipped.txt`.
- Server log: `/tmp/thistle-target-spell-power-server.log`.
- Validation logs: `/tmp/thistle-target-spell-power-tests.log`,
  `/tmp/thistle-target-spell-power-compile.log`, and
  `/tmp/thistle-target-spell-power-credo.log`.
