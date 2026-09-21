# Learned defensive capabilities

Implementation: `0c89ea3d`.

Parry and block now come from learned spell effects in the canonical spellbook.
Class alone no longer grants parry, and equipping a shield does not teach Block.
The shared proficiency reducer recognizes trainer Parry, the separate Shaman
talent ability, and Block without maintaining duplicate capability flags.

Parry requires a usable main-hand or off-hand weapon. Broken weapons, disarm,
and feral forms follow the same availability rules used by combat. Blocking
requires a usable shield and is disabled during the unarmed sheath state;
melee and ranged sheath states permit it. Casting, stun, facing, and creature
restrictions remain part of attack resolution.

Displayed dodge, parry, and block include the difference between current
Defense and level times five, at 0.04 percentage points per skill point.
The attack table adjusts those projected chances for the attacker's weapon
skill once. Skill gains, learned abilities, talent resets, and login refresh
the projection even when the aura list does not change. Creature avoidance
also includes its applicable aura modifiers while retaining block caps.

## Reference behavior

The implementation follows the local VMangos references:

- `Spells/SpellEffects.cpp`: `EffectParry` and `EffectBlock` grant capabilities.
- `Objects/Player.cpp`: `GetWeaponForParry` selects a usable, unbroken weapon.
- `Objects/Unit.cpp`: `GetUnitParryChance` and `GetUnitBlockChance` apply combat
  restrictions, including classic sheath behavior.
- `StatSystem.cpp`: defense skill adjusts all three avoidance percentages.
- `Objects/SpellCaster.cpp`: attack resolution separates actual defense skill
  from the level-based skill comparison used with projected player avoidance.

DBC coverage verifies Block 107, trainer Parry 3127, and the Shaman talent
16268, which teaches the separate Parry ability 18848.

## Build-5875 client acceptance

A fresh local server and an isolated client exercised ordinary inventory,
talent, combat, and logout/login paths on Programmer Isle. Native Lua reads
of `GetDodgeChance`, `GetParryChance`, and `GetBlockChance` were compared with
the player owner's fields and pure combat projection. Tidewave probes were
read-only. God mode remained disabled.

### Warrior defense and weapon availability

| State at level 60 | Dodge | Parry | Block |
| --- | ---: | ---: | ---: |
| Defense 250 | 5.25% | 3% | 3% |
| Defense raised to 300 | 7.25% | 5% | 5% |
| Main-hand weapon removed | 7.25% | 0% | 5% |
| Weapon restored and binding confirmed | 7.25% | 5% | 5% |

The shield remained equipped during weapon removal. Re-equipping Dawn's Edge
required accepting the client's bind-on-equip confirmation before the owner
and displayed parry returned to 5%.

Live incoming attacks from Skeletal Flayers produced ordinary health loss,
dodges, blocks, and parries. Native combat-message samples recorded 23 blocks
in melee sheath state 1 and 10 in ranged sheath state 2, with Shield Block
casts during those samples. After restoring the weapon and selecting unarmed
sheath state 0, the sample contained five parries and zero blocks. The owner
retained sheath state 0 and a 5% baseline block field. These counts are bounded
observations; deterministic tests verify exact attack-table boundaries.

### Shaman talent lifecycle

| State | Dodge | Parry | Block |
| --- | ---: | ---: | ---: |
| No talents, Defense 300 | 7.15% | 0% | 5% |
| Twenty prerequisite points | 12.15% | 0% | 10% |
| Parry talent purchased | 12.15% | 5% | 10% |
| Logout/login | 12.15% | 5% | 10% |
| Talent reset | 7.15% | 0% | 5% |
| Second logout/login | 7.15% | 0% | 5% |

Prerequisite points went into Ancestral Knowledge, Thundering Strikes,
Anticipation, and Shield Specialization through native `LearnTalent` calls.
Purchasing Parry through the same client API produced the learned-ability
message and stored both 16268 and 18848. During logout the player owner was
absent while the runtime character store retained 5% parry and both spells.

Talent reset displayed the unlearned-Parry message, removed both spells from
the owner and character store, and immediately projected 0% parry. Reconnecting
after reset retained that result and restored the baseline dodge/block values.

No gameplay-owner or network errors appeared. Login emitted only the existing
unimplemented account-data, raid-info, GM-ticket, and meeting-stone warnings.
The helper-owned client, X server, and retained BEAM server were stopped.

## Automated validation and retained evidence

- `mix test.all`: 4,330 passed, including DBC, VMangos, and map integrations.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Commit hooks: passed.

Regression coverage includes capability source reduction, learn/unlearn,
weapon removal and breakage, disarm/off-hand fallback, feral forms, shield
requirements, sheath states, defense below and above the level cap, temporary
and permanent skill bonuses, exact auto-attack and ability boundaries, defense
skill gains, creature aura modifiers, and existing proc/parry-haste consumers.

Local evidence is retained at:

- `/home/pikdum/.cache/thistle-wow-playtest.077dzF/screenshots/defense-*.png`
- `/tmp/thistle-defense-server.log`
- `/tmp/thistle-defense-*.log` for owner/store snapshots and validation logs

Representative screenshots are `defense-unarmed.png`,
`defense-combat-drawn.png`, `defense-sheath-zero-counts.png`,
`defense-shaman-trained.png`, `defense-shaman-reset.png`, and
`defense-shaman-reset-reconnected.png`.
