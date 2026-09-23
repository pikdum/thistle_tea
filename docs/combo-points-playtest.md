# Combo point builders and temporary points

Combo point effects now award their caster after the recipient resolves the
effect. This supports Premeditation and the triggered builders used by
Initiative, Ruthlessness, Seal Fate, Setup, and Blood Frenzy. Melee builders
use the same award path, including effect immunity and avoidance checks.

`Logic.ComboPoints` owns additions, consumption, and temporary-point removal.
Premeditation's retention aura is installed alongside the successful award on
the caster owner. Natural expiry subtracts its amount; a subsequent builder
removes the timer without subtracting points. Successful finishers consume
points normally, while avoided finishers retain them. Death clears points and
retention, and delayed awards cannot grant points to dead players or ghosts.

Native testing exposed duplicate melee proc delivery: Seal Fate received both
spell-damage and attack-outcome feedback for one critical builder. Melee
abilities now use one attack outcome for procs and finisher consumption.
Damage packets retain their combat-log information. This also supplies the
previously missing successful-outcome feedback for Druid melee finishers.

Reference behavior comes from `Player::AddComboPoints`,
`Player::ClearComboPoints`, `Aura::HandleAuraRetainComboPoints`, and
`Spell::EffectAddComboPoints` in `refs/vmangos/`.

## Native acceptance

Used Debugrogue on Programmer Isle, an isolated GPU-rendered build-5875 client,
and local servers. Native chat learned the test abilities, enabled god mode,
and positioned the rogue near seeded Skeletal Flayers. Casts, target selection,
death, and spirit release came from client input. Tidewave sampled owner state.

The final server ran the committed feature and proc fix from a fresh process.
The first attempt had encountered a transient missing module during live
recompilation; that process was stopped before acceptance.

| Check | Observed result |
| --- | --- |
| Premeditation | Granted two points on the selected Flayer while remaining stealthed. Natural expiry removed them after 10,011 ms in the expiry sample. |
| Subsequent builder | Premeditation granted two points; Sinister Strike granted one more and removed the retention aura. Three points remained 15.6 seconds after Premeditation, beyond its original expiry. The client printed `COMBO=3`. |
| Finisher | Eviscerate changed three points to zero, cleared the internal combo target, and spent 35 energy. |
| Seal Fate | Cold Blood followed by Sinister Strike changed zero points to exactly two. The client printed `COMBO=2`; the owner sample agreed. Before the follow-up fix this sequence incorrectly produced three points. |
| Target death | The points and target cleared after the Flayer died, with kill experience and reputation feedback visible. |
| Player death | After another builder, the client printed `BEFORE DEATH=1`. Disabling god mode and using `.die` changed health to zero, points to zero, and the combo target to nil. The client printed `AFTER DEATH=0`. |
| Spirit release | Native release left health at one, ghost state true, zero points, no combo target, and no retention aura. |

The final server log contained no errors or spell-validation warnings during
these checks. Existing unrelated login opcode warnings remain outside this
feature. WoW's own AMD graphics-engine counter increased from 6,912,562,279 to
31,029,463,180 ns. Screenshots came from Gamescope.

## Regression coverage

Pure tests cover natural expiry, earlier points, the five-point cap, subsequent
builders, target changes, removal without expiry, successful and avoided
finishers, death, and delayed awards to dead players and ghosts. Effect tests
cover ordinary and melee builders, resistance, dead recipients, and creature
casters. Event-sink coverage verifies caster routing and explicit owner context.

DBC tests exercise the six non-melee builders, exactly one Seal Fate or Blood
Frenzy proc per critical builder, and Druid Rip finisher consumption. Warrior
damage regressions also assert the single outcome accompanying each damage log.

After the final source and test edits, `mix test.all` passed all 4,941 tests.
Compilation with warnings as errors, strict Credo, formatting, and diff checks
passed. The client and local server were stopped after acceptance.

Retained local evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.5vX6gP/screenshots/accepted-*.png`
- `/tmp/thistle-combo-final-expiry.txt`
- `/tmp/thistle-combo-accepted-{retention,retained-state,seal-fate,death,death-state}.txt`
- `/tmp/thistle-combo-accepted-server.log`
- `/tmp/thistle-combo-final-{tests,credo}.log`
