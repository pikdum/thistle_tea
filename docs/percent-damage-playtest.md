# Percentage-based periodic damage

Aura 89 (`periodic_damage_percent`) now deals a percentage of the recipient's
current maximum health on each tick. This enables Transporter Malfunction,
Death's Door, Seething Plague, Corruption of the Earth, and the percentage
component of Smothering Sands through the shared aura and damage systems.

The percentage remains separate from ordinary spell-power and outgoing
damage bonuses. Each tick multiplies the current maximum health by the
nonnegative percentage and holder stacks, with deterministic integer
truncation. Application, independent caster holders, scheduling, immunity,
resistance, absorption, combat feedback, dispel, expiry, and death use the
existing lifecycle. No content-specific scripts or development commands
were added.

The references are `Aura::HandlePeriodicDamagePCT`, `Aura::CalculatePeriodic`,
and the `SPELL_AURA_PERIODIC_DAMAGE_PERCENT` case in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`.

## Bugs fixed during acceptance

The periodic scheduler previously rebuilt holders from its pre-tick snapshot.
This restored partially consumed shields after damage ticks. It now merges
advanced deadlines into the current holders, preserving consumed amounts,
removed holders, and other lifecycle changes. Regression tests cover both
ordinary and percentage damage with the shield before or after the damaging
holder.

Combat feedback also used damage from before the core applied damage-received
percentages and redirection. For example, a 100-point hit reduced by 50% and
then absorbed for 30 actually removed 20 health but reported 70. The core now
exposes the modified damage and absorbed amount together. Periodic damage,
direct spells, weapon abilities, and autoattacks use that result for their
feedback. The existing two-value absorption API remains compatible.
Overkill continues to report the hit amount rather than remaining health.

## Automated acceptance

Focused tests cover players and creatures, current maximum health, caster
bonus exclusion, stacking and independent casters, negative percentages,
state and school damage immunity, resistance, shield consumption, delayed
ticks, final ticks, dispel, expiry, and death. A lethal effect cannot be undone
by a later heal in the same holder. Retained passive percentage damage on a
corpse advances its deadline without applying damage.

DBC-tagged tests load all five vanilla spells using aura 89 and verify their
percentages, effect indexes, and tick intervals. Feedback regressions cover
damage reduction, amplification, complete suppression, absorption, overkill,
god mode, direct spells, weapon abilities, and melee/ranged autoattacks.

Final validation on `21b4ac6e`: `mix test.all` passed 3,288 tests,
`mix compile --warnings-as-errors` passed, and `mix credo --strict` reported
zero issues.

## Real-client acceptance

An isolated build-5875 client controlled level-50 Debugwarlock on Programmer
Isle, with 2,059 maximum health. Existing `.learn` and `.modify hp` commands
prepared the scenario; all casts came from the client. Tidewave samplers only
read the player owner during acceptance.

- Transporter Malfunction (23449) stored a 10% aura with a two-second cadence
  and 24-second duration. The client displayed 205-point damage ticks and the
  debuff. Natural out-of-combat regeneration also ran between self-damage
  ticks, so sampled net health loss was smaller than the individual hits.
- On a fresh server running the final implementation, Fire Ward rank 4
  (10223) initially absorbed 675 damage. Successive ticks left 470, 265, and
  60 in the authoritative shield. The next tick removed the shield and the
  client displayed `145 (60 absorbed)` and `Fire Ward fades`.
- Later ticks dealt damage normally. Transporter Malfunction expired at its
  deadline; its holder and next periodic deadline disappeared, and subsequent
  samples showed only normal health regeneration.
- For a fresh lethal cast, `.modify hp 100` lowered health. Regeneration raised
  it to 132 before the first tick killed the character. The client displayed
  the release-spirit prompt. The authoritative health remained zero, the aura
  was absent, and the next deadline stayed nil for the remaining samples.

A code-reload attempt during the preliminary run briefly unloaded the periodic
module and logged a rescued player-tick error. Final acceptance used a fresh
server without live recompilation and had no gameplay errors or cast-validation
failures. Existing unsupported login housekeeping messages remained. No second
observer client was used. The helper-owned client and local server were stopped
before the final full suite.

## Evidence

- Screenshots: `/home/pikdum/.cache/thistle-wow-playtest.VfP6xm/screenshots/`,
  especially `damage-ticks.png`, `shield-absorbing.png`, `expired.png`, and
  `final-death.png`.
- Runtime samples: `/tmp/thistle-percent-damage-client-shield-expiry.txt` and
  `/tmp/thistle-percent-damage-final-client-death.txt`.
- Final server log: `/tmp/thistle-percent-damage-final-server.log`.
- Validation logs: `/tmp/thistle-percent-damage-final-tests.log`,
  `/tmp/thistle-percent-damage-final-compile.log`, and
  `/tmp/thistle-percent-damage-final-credo.log`.
