# Weapon-dependent offensive bonuses

Weapon restrictions now apply to hit, crit, and white-attack damage bonuses.
Equipment sync supplies canonical main-hand, off-hand, and ranged templates;
the pure combat paths distinguish equipped identity from usability. Attack
snapshots no longer load item templates from the behavior tree.

Hit bonuses follow the attacking hand. As in VMangos, restricted hit talents
inspect the equipped weapon even while it is broken, disarmed, or suppressed
by a form. Crit and damage bonuses require a usable matching weapon. Class,
subclass, and inventory-type masks all participate.

Melee crit talents follow the main hand. Off-hand attacks share that melee
crit value, while retaining their own weapon skill for target adjustments.
Restricted crit enchants can contribute from either melee hand, but only from
the particular item that owns the aura. Ranged bonuses use the ranged weapon.
Generic crit bonuses remain shared across both channels.

The displayed crit fields and outgoing snapshots use the same calculation:
class/agility crit, eligible auras, and 0.04 percentage points per weapon skill
above or below the level cap, clamped at zero. Spell snapshots compute from
canonical inputs rather than reading a possibly stale client-display field.
Feral forms use natural main-hand skill and suppress equipped weapon crit
bonuses. Disarm preserves usable off-hand and ranged weapons.

White attacks now filter both flat and percentage damage bonuses by weapon.
Target-side damage and attack-power additions use the same per-hand
multipliers. The off-hand penalty also scales flat outgoing damage bonuses.

References were checked in `refs/vmangos` at `8f4e60845`:
`Player::GetWeaponBasedAuraModifier`, `Player::UpdateCritPercentage`,
`Player::CalculateMinMaxDamage`, `Player::_ApplyWeaponDependentAuraCritMod`,
`Player::_ApplyWeaponDependentAuraDamageMod`, `Player::GetWeaponForAttack`,
`Unit::GetUnitCriticalChance`, and `SpellCaster::GetWeaponSkillValue`.

## Native client acceptance

Build 5875 ran against a fresh server on implementation commit `a8e7441e`.
The level-60 human Debugwarrior used Worn Shortsword 25, Worn Dagger 2092,
and Worn Shortbow 2504. Agility remained 97 during the weapon and skill checks.
All state changes used native client inventory actions, item use, or existing
developer chat commands. Tidewave probes only read owner and runtime-store
state. The native Attack tooltip provided the visible crit measurement.

- Baseline sword crit was 5.05%; bow crit was 4.85%. Human Sword Specialization
  supplied five skill points and the additional 0.2 percentage points.
- Learning Dagger Specialization 13807 with the dagger only in the off hand
  left the Attack tooltip at 5.05%. Learning Lethal Shots 19431 raised ranged
  crit to 9.85% without changing melee crit.
- Precision 13845 supplied five hit points in both melee hand snapshots and
  the Heroic Strike snapshot, with zero added hit in the bow snapshot.
- Moving the dagger into the main hand raised the native Attack tooltip to
  9.85%. Lowering dagger skill from 300 to 250 reduced it to 7.85%; restoring
  maximum skill restored 9.85%. Owner fields and spell snapshots agreed.
- Applying Elemental Sharpening Stone 18262 to a second, off-hand dagger added
  aura 22755 with that exact item's source GUID. The Attack tooltip rose to
  11.85%; ranged crit remained 9.85%. Unequipping the enchanted dagger removed
  its holder and restored 9.85% melee crit.
- Re-equipping the enchanted dagger restored its source. Native white attacks
  against a level-50 Skeletal Flayer produced ordinary hits and a visible
  38-damage critical hit. The sampled target health fell from 2,880 to 1,363.
  These observations demonstrate resolved attacks, not a statistical estimate
  of the crit rate.
- Breaking all equipped gear removed the enchant's active holder and all
  weapon-dependent crit bonuses. Naked agility was 80; the native Attack
  tooltip showed 4.00%, while ranged crit was zero. Main-hand skill switched
  to Unarmed 300; unusable off-hand and ranged skills were zero. Both daggers
  retained their equipped identity and Precision's five hit points.
- A full native logout and re-entry retained the broken items, 4.00% visible
  melee crit, zero ranged crit, absent enchant aura, and per-hand hit bonuses.
  The new player owner and `CharacterStore` agreed.
- Right-clicking Corina Steele and using the merchant's Repair All button
  restored both daggers to 16/16 durability and the bow to 20/20. The original
  off-hand enchant source reactivated. The Attack tooltip returned to 11.85%,
  ranged crit returned to 9.85%, and owner/store snapshots agreed.

The 1.12 client has no `GetCritChance` or `GetRangedCritChance` Lua API. The
Attack spell tooltip was shown using its real spellbook entry. Shoot Bow's
tooltip does not expose ranged crit, so ranged values above are owner and
snapshot evidence, not a claim about visible tooltip text.

The acceptance server logged no errors or spell-validation failures. Existing
login warnings for `CMSG_UPDATE_ACCOUNT_DATA`, `CMSG_REQUEST_RAID_INFO`,
`CMSG_GMTICKET_GETTICKET`, and `CMSG_MEETINGSTONE_INFO` remained. The isolated
client, X server, and retained game server were stopped after acceptance.

## Automated validation

`mix test.all`: 4,504 passed. `mix compile --warnings-as-errors` passed.
`mix credo --strict`: zero issues across 1,776 files. The dependency ratchet
lost the behavior-tree combat exception for `World.Loader.Item`.

Coverage includes loaded DBC talent requirements, per-hand hit, shared melee
crit, exact enchant sources, inventory masks, skill progression, disarm,
feral forms, broken/repair transitions, stale display inputs, enchanted visible
item packing, white damage restrictions, and off-hand flat-damage scaling.

Artifacts:

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.GSLRTg`.
- Server log: `/tmp/thistle-weapon-bonuses-server.log`.
- State probes: `/tmp/thistle-weapon-bonuses-*.txt`.
- Gate logs: `/tmp/thistle-weapon-bonuses-final-{all,compile,credo}.log`.

Useful screenshots include `baseline.png`, `talents-sword.png`,
`dagger-mainhand.png`, `dagger-skill250.png`, `offhand-enchanted.png`,
`offhand-removed.png`, `combat-resolved.png`, `broken.png`,
`broken-reconnected.png`, and `repaired.png` under the session's `screenshots/`.
The critical-hit combat text is visible in `broken.png`, retained in chat after
leaving combat.
