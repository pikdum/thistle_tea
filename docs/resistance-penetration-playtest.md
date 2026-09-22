# Armor and spell penetration

`mod_target_resistance` now participates in a shared school-masked damage
calculation. Melee swings, melee and ranged weapon abilities, direct magic
damage, periodic damage, and periodic leech use the caster's applicable
penetration. Equipment equip spells contribute alongside active auras, and
each aura's stack count scales its modifier.

Effective resistance is the target's current armor or school resistance plus
matching caster modifiers, clamped at zero. Penetration never changes the
target's displayed stats, benefits another attacker, or removes innate
resistance from a creature's level advantage. Armor-only bonuses no longer
affect magic damage; fire-only bonuses do not affect frost damage.

Caster modifiers are captured in the existing attack/cast snapshots. Periodic
holders retain their penetration until refreshed, while target resistance is
read at each tick. This follows the project's existing snapshot architecture;
VMangos reads the caster's current penetration at impact/tick. Physical
periodic damage retains its existing armor-bypassing behavior. A subsequent
[binary spell resistance change](binary-spells-playtest.md) adds school resistance
and caster penetration to the separate all-or-nothing spell-hit calculation.

Reference arithmetic: `SpellCaster::CalcArmorReducedDamage` and
`SpellCaster::GetSpellResistChance` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`.

## Playtest-discovered fix

Shield Slam previously failed with `nothing_to_dispel` against an unbuffed
enemy. Cast validation now requires an eligible aura only for spells whose
effects are exclusively single-target dispels. Damage-plus-dispel abilities
and area dispels can proceed. This matches `SpellInternal::IsNonPeriodicDispel`
in the VMangos reference. Regression tests retain the restrictions on ordinary
Cleanse and Purge casts.

## Real-client acceptance

An isolated World of Warcraft 1.12.1 build-5875 client controlled Debugwarrior
and Debugmage against a fresh local server. Client commands supplied the
test spells and item; casts, equipment changes, death, and logout used the
client. Runtime probes read owner state, and a temporary receive trace captured
outbound damage messages without changing gameplay state.

- Level-50 Debugwarrior used rank-1 Shield Slam against a level-51 Skeletal
  Flayer with 2,988 armor. Without penetration the outgoing packet reported
  162 damage.
- Three client casts of Bonereaver's Edge produced the visible three-stack
  buff and a `{physical mask 1, -2100}` snapshot. Shield Slam then dealt 220
  damage, shown in floating text and the combat log. The sampled target still
  had 2,988 armor; its effective armor for that attack was 888.
- Expiry removed the bonus. A subsequent Shield Slam against a nearby
  level-50 Flayer with 2,936 armor dealt 164 damage with an empty penetration
  snapshot. These values fit the spell's damage range and the armor formula.
- After leaving combat, disabling god mode, and applying Bonereaver again,
  `.die` produced zero health with no Bonereaver holder or penetration bonus.
- Debugmage equipped Rune of Perfection (21565). Its tooltip advertised 20
  spell penetration and the owner snapshot contained exactly `{124, -20}`.
  Read-only calculations against 100 resistance returned 80 for fire, frost,
  nature, shadow, and arcane, and 100 for holy and physical. Unequipping removed
  the bonus; re-equipping restored it.
- Logout removed the mage's owner process. Reconnecting created a new owner
  with the same equipped item and exactly one `{124, -20}` bonus.

School-specific magic mitigation, periodic snapshots and refresh, live target
resistance changes, leech healing, critical and off-hand attacks, gear break
and repair, and Serrated Blades level scaling are covered by automated tests.
The client damage comparison exercised armor penetration; it did not exercise
magic damage against a resistant target or a second observer client.

No error-level server logs occurred. The two pre-fix Shield Slam failures
disappeared after the validation fix. Existing unsupported account-data,
raid-info, GM-ticket, time-query, meeting-stone, and cancel-trade requests
appeared during client UI activity. The helper-owned client and retained server
were stopped after testing.

## Evidence

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.eX4qn1/screenshots/`.
- Server log: `/tmp/thistle-penetration-server.log`.
- Damage packets and state: `/tmp/thistle-penetration-client-hits-{baseline-fixed,stacked,expired}.txt`.
- Death: `/tmp/thistle-penetration-client-death.txt`.
- Equipment: `/tmp/thistle-penetration-gear-{equipped,removed,reequipped}.txt`.
- Reconnect: `/tmp/thistle-penetration-gear-{logged-out,reconnected}.txt`.

## Final validation

- `mix test.all`: 3,473 tests passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- `mix format --check-formatted`: passed.
- Logs: `/tmp/thistle-penetration-final-{tests,compile,credo}.log`.
