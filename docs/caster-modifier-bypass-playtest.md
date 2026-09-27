# Caster modifier bypass

Implementation: `d6129906`.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`SpellCaster::CalculateSpellDamage`, `SpellDamageBonusDone`,
`MeleeDamageBonusDone`, `SpellHealingBonusDone`, and `Player::ApplySpellMod`.

Spells with `SPELL_ATTR_EX3_IGNORE_CASTER_MODIFIERS` now bypass outgoing spell
power, target-dependent caster bonuses, damage and healing multipliers, and
periodic aura amount adjustments. Damage cannot gain critical amplification;
melee outcome feedback also reports a normal hit. Incoming target modifiers,
resistance, absorption, resource consumption, and ordinary healing criticals
retain their separate rules.

The shared spell-modifier selector rejects flagged spells before modifiers can
alter costs, durations, intervals, and other operations. Charged modifiers are
not selected for consumption by these casts. Periodic snapshots preserve the
base effect amount and retain the existing expiry and removal lifecycle.

## Native acceptance

A fresh server ran two isolated build-5875 clients on Programmer Isle:

- Debugpriest, GUID 4, `/home/pikdum/.cache/thistle-wow-playtest.xVNGGI`.
- Debugbidder, GUID 11, `/home/pikdum/.cache/thistle-wow-playtest.mTnCNc`.

Both characters were raised to level 60. Existing GM commands taught the priest
Volatile Infection 3585, Gnomish Death Ray 13493, and Berserk 26662. A native
duel allowed Smite against the mage. God mode remained disabled. Casts, buff
cancellation, and duel termination came from the clients; Tidewave only read
the owners.

Berserk supplied +500% damage done, giving a sixfold multiplier. Smite served
as the ordinary-spell control. Volatile Infection selected the priest through
its party-area targeting; the mage observed its damage without taking it.
Gnomish Death Ray 13493 is the four-second self-damage effect; this acceptance
does not cover the engineering item's entire activation sequence.

| Case | Visible result and authoritative state |
| --- | --- |
| Before Berserk | Smite dealt 16 to the mage. Volatile Infection dealt 180 to the priest. |
| Berserk active | Smite dealt 96 to the mage. Two Volatile Infection casts still dealt 180 each, reducing priest health 2207 → 2027 → 1847. |
| Periodic effect under Berserk | Gnomish Death Ray stored 150 and dealt four 150-damage ticks. The holder disappeared after its final tick. |
| Berserk cancelled | Smite returned to 15 damage. Volatile Infection remained 180. |
| Duel ended | Both owners remained alive, with no duel, cast, Berserk, or Death Ray holder. Health regenerated to maximum. |

Both combat logs displayed the matching direct and periodic damage. The priest
also displayed Death Ray fading and Berserk cancellation. One periodic sample
combined a 150-damage tick with a 38-point regeneration event; the combat logs
show all four ticks individually. Later samples contained regeneration only.

Evidence:

- `/tmp/thistle-caster-modifiers-baseline.log`
- `/tmp/thistle-caster-modifiers-berserk.log`
- `/tmp/thistle-caster-modifiers-periodic.log`
- `/tmp/thistle-caster-modifiers-removal.log`
- `/tmp/thistle-caster-modifiers-cleanup.log`
- Priest screenshots `berserk-direct.png`, `berserk-periodic.png`, and
  `after-berserk-removal.png`.
- Mage screenshots `baseline.png`, `berserk-observer.png`,
  `periodic-observer.png`, and `after-removal-observer.png`.

## Verification and cleanup

`mix test.all` passed all 7016 tests. Compilation passed with warnings as errors,
and strict Credo found no issues. Added regressions cover damage classes,
weapon groups and feedback, leech, healing, power drains and burns, periodic
snapshots and removal, target bonuses, absorption, costs, timing, and charged
modifier selection. DBC regressions compare unmodified and boosted contexts
for all ten flagged spells and retain an ordinary Smite control. No architecture
allowlist was expanded.

Check logs: `/tmp/thistle-caster-modifiers-all.log`,
`/tmp/thistle-caster-modifiers-compile.log`,
`/tmp/thistle-caster-modifiers-credo.log`, and
`/tmp/thistle-caster-modifiers-commit.log`.

Both clients used hardware rendering. WoW's own DRM graphics counter increased
from 1505776917 to 9556008341 ns for PID 2222134 and from 896422523 to
8568723059 ns for PID 2223195. The server log
`/tmp/thistle-caster-modifiers-server.log` contained no gameplay errors or cast
validation failures. Existing account-data and ticket-query warnings appeared
at login.

Both helper-owned services are inactive with empty cgroups; both WoW PIDs are
gone. The retained server PTY exited successfully, and ports 4000, 3724, and 8085
are free. Logs and screenshots were retained. Nothing was pushed.
