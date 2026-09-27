# Periodic damage ramps and refresh timing

Implementation: `ce327389`. Refresh follow-up: `6bd9cf27`.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Aura::PeriodicTick`, `Aura::Refresh`, and `Aura::CalculatePeriodic` in
`SpellAuras.cpp`, plus `Unit::SpellDamageBonusTaken` in `Unit.cpp`.

Starshards now increases its damage every two executed ticks. Curse of Agony
increases every four. Both offset the stored caster snapshot by a fraction of
effect zero's simple base amount: one third for Starshards and one half for
Agony. Spell-power and caster damage bonuses therefore remain independent of
the ramp. The previous Agony implementation scaled the whole snapshot and
inferred the stage from elapsed deadlines.

The shared periodic damage calculator applies target flat bonuses, coefficients,
the half-damage cap on flat reductions, and target percentage modifiers before
unbiased fractional rounding and resistance. The damage funnel then applies
absorption, sharing, health changes, and lifecycle effects once. Tick-state
merging preserves consumed shields and removed holders.

Native refresh inspection exposed an older timing error. Ordinary refreshes
now restart the interval as VMangos specifies. The listed totem, trap, mark,
and Stoneclaw exceptions retain their pending timer. Adding stacks preserves
both timer and executed count. Ground effects retain their source-owned
schedules through their existing merge path. The rotating-cone acceptance note
was corrected to reflect the ordinary refresh behavior.

## Native damage and lifecycle acceptance

A fresh server ran two isolated build-5875 clients on Programmer Isle:

- Debugpriest, GUID 4, `/home/pikdum/.cache/thistle-wow-playtest.i8DG5y`.
- Debugbuyer, GUID 10, `/home/pikdum/.cache/thistle-wow-playtest.ZE2QzJ`.

Both were raised to level 60. The priest learned Starshards 19305, Curse of
Agony 11713, and Power Infusion 10060 through existing GM commands. A native
duel made the warrior attackable. God mode remained disabled. Casts, movement,
and recasts came from the clients; Tidewave only sampled owner state.

| Case | Observed result |
| --- | --- |
| Full Starshards channel | Six ticks: 104, 104, 156, 156, 208, 208. Health fell from 3559 to 2623. Channel and target aura ended at six seconds. |
| Movement during Starshards | Two 104-damage ticks, then the client displayed “Interrupted.” Channel and remote aura cleared; subsequent samples showed only regeneration. |
| Full Agony duration | Twelve ticks: 44, 43, 44, 43, 87, 87, 87, 87, 131, 130, 130, 131. The holder expired after its final tick. |
| Agony under Power Infusion | Stored amount was 104. Early ticks were 61, 60, 60, 61; middle ticks were 104. The stored bonus remained after Power Infusion expired. |
| Agony recast after six ticks | The count returned to zero and the first two new ticks dealt 43 and 44. The new holder used a fresh two-second interval. |

The warrior's combat log displayed the matching spell names and damage.
Agony samples also show separate health-regeneration events; net health loss
over its full duration is therefore smaller than total spell damage.

Evidence:

- `/tmp/thistle-periodic-ramps-starshards.log`
- `/tmp/thistle-periodic-ramps-movement-cancel.log`
- `/tmp/thistle-periodic-ramps-agony-first.log`
- `/tmp/thistle-periodic-ramps-agony-second.log`
- `/tmp/thistle-periodic-ramps-bonus-first.log`
- `/tmp/thistle-periodic-ramps-refresh-accepted.log`
- Priest screenshots `starshards-channel.png` and `starshards-movement-cancel.png`.
- Warrior screenshots `starshards-complete.png`, `agony-complete.png`, and
  `agony-refresh-accepted.png`.

The initial `/stopcasting` and `SpellStopCasting()` attempts did not cancel
this vanilla channel. Their samples show completed casts and are not
cancellation evidence; the accepted interruption used native movement.

## Native refresh follow-up

After the timing fix, a fresh server and client
`/home/pikdum/.cache/thistle-wow-playtest.07XE6x` used level-50 Debugpriest.
The existing health command created room for healing. Two native rank-one
Renew casts occurred 2119 ms apart, before the original first tick.

Owner samples show the old deadline being replaced by a deadline exactly
3000 ms after the second cast. No heal occurred at the old deadline. The first
9-point heal arrived 3014 ms after the refresh; subsequent heals followed the
three-second cadence. The client displayed five 9-point heals and Renew fading.
A final probe confirmed no holder, no upcoming aura event, no cast, and a live
player owner.

Evidence: `/tmp/thistle-periodic-refresh-renew.log`,
`/tmp/thistle-periodic-refresh-cleanup.log`, and the client's
`screenshots/renew-refresh.png`.

## Verification and cleanup

Final checks: `mix test.all` passed all 6993 tests, compilation passed with
warnings as errors, and strict Credo found no issues. Coverage includes all
thirteen player ranks, caster bonuses, fractional rounding, unrelated family
masks, delayed ticks, refresh, stacking, timer exceptions, resistance,
absorption, death, expiry, and damage packets to both clients. Actual DBC tests
also exercise Renew and Corruption refreshes. No dependency allowlist was added.

Logs: `/tmp/thistle-periodic-refresh-all-accepted.log`,
`/tmp/thistle-periodic-refresh-compile.log`,
`/tmp/thistle-periodic-refresh-credo.log`, and
`/tmp/thistle-periodic-refresh-commit.log`. The earlier full run found three
tests expecting retained deadlines; those expectations were corrected before
the accepted run.

All three clients used hardware rendering. WoW's own DRM graphics counters
increased from 596445427 to 4041338002 ns for PID 2198594, from 316800417 to
3680468756 ns for PID 2199425, and from 1611616209 to 4851030520 ns for
PID 2206772.

Both server logs contain no gameplay errors or cast-validation failures.
Existing account-data and ticket-query opcode warnings appeared at login.
Every helper-owned service was stopped with an empty cgroup; all three WoW
PIDs disappeared. Both retained server PTYs exited and ports 4000, 3724, and
8085 were free. Logs and screenshots were retained. Nothing was pushed.
