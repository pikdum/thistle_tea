# Received damage bonuses

Implementation: `5932fc2d`.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Unit::SpellDamageBonusTaken`, `Unit::MeleeDamageBonusTaken`,
`Spell::CalculateSpellDamage`, and `Spell::EffectPowerDrain`.

`Logic.DamageReceived` now supplies the shared target calculation for direct
spells, periodic effects, weapon abilities, swings, and resource drains.
School and attack-specific flat bonuses use the receiving effect's coefficient
where applicable. Magic flat reductions cannot remove more than half the
incoming damage. Target percentages apply before critical hits, physical armor,
resistance, and absorption. Callers mark the target calculation as applied so
the health funnel does not apply it twice. Fractional damage uses shared
unbiased rounding at the damage boundary.

The loader recognizes the target-modifier bypass attribute. It skips target
flat and percentage bonuses while retaining resistance and absorption. Direct
physical spells also respect armor and the existing custom armor-bypass flag.
Power burns retain their original effect for coefficient lookup, including
periodic burns whose runtime input is an aura snapshot.

## Native acceptance

A fresh server ran two isolated build-5875 clients on Programmer Isle:

- Debugpriest, GUID 4, `/home/pikdum/.cache/thistle-wow-playtest.azb4aM`.
- Debugbidder, GUID 11, `/home/pikdum/.cache/thistle-wow-playtest.F9M7DG`.

Both characters were raised to level 60 through existing GM commands. The mage
learned Dampen Magic 10174 and Amplify Magic 10170. They entered a native duel
on the north slope, about seven yards apart. God mode remained disabled. Every
cast, buff cancellation, and duel action came from a client; Tidewave only read
owner state and existing spell data.

Rank-one Smite 585 had coefficient 0.123, zero caster holy spell power, and
unit caster damage multipliers. Its noncritical base damage was 15–19.
Dampen's -90 flat modifier therefore reached the half-damage reduction cap;
Amplify's +75 modifier added 9.225 before rounding.

| Case | Client and owner-state result |
| --- | --- |
| Baseline Smite | Hits dealt 16 and 15. The intervening cast was resisted, appeared in the attacker's combat log, and caused no health loss. |
| Dampen Magic, rank 5 | Hits dealt 8, 8, and 10. Target health changed 2350 → 2342 → 2334 → 2324. |
| Amplify Magic, rank 4 | Dampen faded and Amplify replaced it. Hits dealt 25, 25, and 25; health changed 2350 → 2325 → 2300 → 2275. |
| Amplify cancelled | The buff disappeared; hits returned to 17, 17, and 16. Health changed 2350 → 2333 → 2316 → 2300. |
| Duel ended | Both owners remained alive with no duel, cast, Dampen, or Amplify state. Health subsequently regenerated to maximum. |

The target's combat log displayed matching damage, buff gain, replacement,
and cancellation. The attacker's log also displayed the damage and resisted
cast. Owner samples distinguish later regeneration from individual damage
events. Native acceptance covered normal hits; critical, resistance, armor,
block, and absorption ordering are covered by automated regressions.

Evidence:

- `/tmp/thistle-damage-received-initial.log`
- `/tmp/thistle-damage-received-context.log`
- `/tmp/thistle-damage-received-baseline.log`
- `/tmp/thistle-damage-received-dampen.log`
- `/tmp/thistle-damage-received-amplify.log`
- `/tmp/thistle-damage-received-removal.log`
- `/tmp/thistle-damage-received-cleanup.log`
- Target screenshots `smite-baseline.png`, `smite-dampen.png`,
  `smite-amplify.png`, and `smite-after-removal.png`.
- Priest screenshots `smite-attacker.png` and
  `smite-attacker-after-removal.png`.

## Verification and cleanup

`mix test.all` passed all 7006 tests. Compilation passed with warnings as errors,
and strict Credo found no issues. Added coverage exercises coefficient and stack
scaling, school masks, fixed damage, zero-damage weapon hits, the magic reduction
cap, critical ordering, armor bypass, resistance, absorption, power burns, and
shield block without duplicate target percentages. DBC tests cover every
Dampen and Amplify rank, removal, and Decimate's target-modifier bypass flag.
The Decimate test covers the flag, not its parent scripted encounter mechanic.
No architecture allowlist was expanded.

Check logs: `/tmp/thistle-damage-received-all.log`,
`/tmp/thistle-damage-received-compile.log`,
`/tmp/thistle-damage-received-credo.log`, and
`/tmp/thistle-damage-received-commit.log`.

Both clients used hardware rendering. WoW's own DRM graphics counter increased
from 781948050 to 8535557673 ns for PID 2214044 and from 399014785 to
7594033521 ns for PID 2215016. The server log
`/tmp/thistle-damage-received-server.log` contained no gameplay errors or cast
validation failures. Existing account-data and ticket-query warnings appeared
at login.

Both helper-owned services are inactive with empty cgroups, and both WoW PIDs
are gone. The retained server PTY exited successfully; ports 4000, 3724, and 8085
are free. Logs and screenshots were retained. Nothing was pushed.
