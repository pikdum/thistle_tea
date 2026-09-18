# Shield block bonuses

Shield block value now has one entity-level calculation used by defensive
melee blocks and the Shield Slam cast snapshot. Player value is the equipped
shield and equipment spell bonuses, plus flat aura bonuses and strength / 20
minus one, multiplied by active percentage bonuses. The final result is
truncated and clamped to zero. Fractional strength is retained until that
final step. Creature block values retain their existing level/strength rule.

The spell loader now distinguishes aura 150 (percentage block value) from
aura 158 (flat block value). This enables the Shaman and Paladin Shield
Specialization ranks, block-value equipment spells, Presence of Might, and
Glyph of Deflection. Previously, aura 158 was unmapped, and aura 150 was
incorrectly treated as a flat Shield Slam bonus while defensive blocks
ignored it.

Equipped flat block bonuses are collected through EquipmentStats; temporary
bonuses and talents use the ordinary aura lifecycle. Both paths read current
inputs, so replacing equipment or refreshing, cancelling, expiring, and
removing auras cannot restore stale block values. Independent percentage
holders multiply, and holder stacks scale their amounts.

Related fixes make block chance include equipped and active aura bonuses in
both the attack table and character sheet. An unequipped shield now prevents
blocking even when positive block bonuses or a defense-skill advantage remain.
The existing Shield Block test fixture was updated to equip a shield.

## References

- `Player::GetShieldBlockValue` and `Player::HandleBaseModValue` in
  `refs/vmangos/src/game/Objects/Player.cpp`.
- `Aura::HandleShieldBlockValue` and the aura handler table in
  `refs/vmangos/src/game/Spells/SpellAuras.cpp`.
- `Unit::GetUnitBlockChance` in `refs/vmangos/src/game/Objects/Unit.cpp`.
- `Creature::GetShieldBlockValue` in `refs/vmangos/src/game/Objects/Creature.h`.

## Automated acceptance

Tests cover flat and percentage composition, fractional strength, stacks,
independent multipliers, negative modifiers, current equipment and strength,
creature behavior, block subtraction after armor, complete blocks, the Shield
Slam snapshot, refresh, cancellation, expiry, death, equip/unequip idempotence,
on-use exclusion from passive gear bonuses, and shield-dependent chances.
DBC-tagged tests exercise every active Shaman and Paladin Shield Specialization
rank plus representative equipment, enchantment, and trinket spells.

## Real-client acceptance

An isolated build-5875 client used Debugwarrior on Programmer Isle, raised to
level 60 through the existing developer command. The character learned the
30% Shield Specialization passive with `.learn 20150` to exercise percentage
scaling alongside warrior abilities. All equipment changes, casts, and item
uses came from the client. Tidewave samples read the entity owner only.

- With Crusader's Shield (29 block), 155 strength, the talent, and Glyph of
  Deflection equipped (+23 block and +3% block chance), authoritative block
  value was 76 and the client reported 8% block chance.
- Using Glyph applied spell 28773, displayed its timed buff, and raised block
  value to 381. The sampled transition occurred at 2,338 ms; it returned to
  76 at 22,428 ms, consistent with the 20-second duration.
- Shield Block raised the displayed and authoritative chance to 83% while
  the trinket was equipped, returning to 8% on expiry.
- Removing the shield left the trinket's bonuses present but dropped block
  chance to zero in the owner and client. Re-equipping the shield and removing
  the trinket left block value 46 and chance 5%.
- Against level-50 Skeletal Flayers, Shield Block raised chance to 80% without
  the trinket. The client combat log recorded “Skeletal Flayer attacks. You
  block.” The retained screenshot also shows normal hits and dodges, and the
  active Shield Block buff.

The initial combat attempts included rear attacks, which correctly could not
be blocked. The successful block check used a target in front. Equipment
re-equipping required confirming the client's bind-on-equip dialog. A Glyph
reuse attempted during cooldown was rejected by the client; the timed sample
above used a later successful activation.

Shield Slam damage integration, cancellation/death cleanup, and blocking
with an active bonus after shield removal were covered by automated tests.
A second observer client was not used. No owner errors or server cast-validation
failures occurred. The helper-owned client and local server were stopped.

## Evidence

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.eSD9z4/screenshots/`,
  especially `glyph-active.png`, `no-shield.png`, and `verified-block.png`.
- Exact timed changes: `/tmp/thistle-shield-block-glyph-transitions.txt`.
- Equipment removal samples: `/tmp/thistle-shield-block-no-shield.txt` and
  `/tmp/thistle-shield-block-trinket-removed.txt`.
- Server log: `/tmp/thistle-shield-block-server.log`.
- Final gates: `/tmp/thistle-shield-block-final-{tests,compile,credo}.log`.

Final validation passed: 3,242 tests with `mix test.all`,
`mix compile --warnings-as-errors`, and zero issues from `mix credo --strict`.
