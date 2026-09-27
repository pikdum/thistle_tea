# Spell amount modifiers

Implementation: `03707b4d`.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`SpellCaster::CalculateSpellEffectValue`, `MeleeDamageBonusDone`,
`SpellDamageBonusDone`, `SpellHealingBonusDone`, and the periodic handlers in
`SpellAuras.cpp`.

Flat spell modifiers previously became percentages by applying them to a
synthetic value of 100. A +45 Frostbolt modifier therefore produced +45%
damage. All-effects modifiers also missed resource gains and were applied
too late to several damage and healing calculations.

The shared amount calculation now applies all-effects modifiers to the base
effect value. Direct damage and healing apply damage modifiers after caster
bonuses; periodic damage and healing apply dot modifiers at that stage.
Resource gains use the modified base value. Cast snapshots retain actual
modifier auras, and only genuine percentage bonuses occupy multiplier fields.
Charge selection includes healing and resource operations and distinguishes
periodic mana drains from periodic damage. Fixed and ignored-caster effects
retain their separate bypass rules.

## Native acceptance

A fresh server ran two isolated build-5875 clients on Programmer Isle:

- Debugbidder, level-60 mage, GUID 11,
  `/home/pikdum/.cache/thistle-wow-playtest.aySvJs`.
- Debugwarrior, level-60 warrior, GUID 1,
  `/home/pikdum/.cache/thistle-wow-playtest.0g8jnp`.

Existing GM commands staged the characters and taught modifier spells. Native
casts, duels, buff cancellation, logout, and reconnect exercised the gameplay
paths. God mode remained disabled; Tidewave only read entity owners.

| Case | Client and owner evidence |
| --- | --- |
| Rank-one Frostbolt baseline | Both casts dealt 22 damage. Warrior health changed 3719 → 3697 → 3675. |
| Frostbolt modifier 21229 | The caster held a flat +45 damage modifier. Casts dealt 66 and 68 damage, within the normal 21–23 range plus 45. Warrior health changed 3719 → 3653 → 3585. |
| Bloodrage baseline | Immediate rage changed 0 → 100 internally, displayed as 10 rage. Ten subsequent ticks added 10 internal units each. |
| Improved Bloodrage rank two, 12818 | Immediate rage changed 0 → 150, displayed as 15 rage. The periodic amount remained 10 internal units; the holder expired after its final tick. |
| Fireball periodic modifier 21230 | Rank-one Fireball dealt 22 direct damage and stored a 25-damage periodic amount, producing two 25-damage ticks. |
| Modifier cancelled during a burn | The existing burn retained its 25-damage snapshot for the remaining tick. A later cast stored 1 and produced two 1-damage ticks. Both holders expired normally. |
| Mage logout and reconnect | The owner disappeared during logout. After reconnect, Frostbolt retained +45 and dealt 68. Fireball retained no cancelled modifier and produced two 1-damage ticks. |
| Duel cleanup | Both owners were alive at maximum health, with no duel, active cast, Frostbolt slow, Fireball burn, Bloodrage holder, or cancelled Fireball modifier. |

Both clients' combat logs showed matching damage and rage events. Learned
passive modifiers remained learned; the cancelled active modifier stayed
absent across reconnect. This acceptance used the modifier spells directly,
not item-equipping or talent-point purchases.

Evidence is retained under `/tmp/thistle-effect-amount-` with suffixes
`bloodrage-base.log`, `bloodrage-boost.log`, `frost-base.log`, `frost-boost.log`,
`fireball-boost.log`, `fireball-removal.log`, `logout.log`, `reconnect.log`, and
`cleanup.log`. Compact copies of the two baseline logs omit unrelated auras.
Client screenshot names include `bloodrage-baseline`, `bloodrage-boosted`,
`frost-baseline`, `frost-boosted`, `fireball-boosted`,
`fireball-after-removal`, and `reconnect-casts`.

## Verification and cleanup

`mix test.all` passed all 7028 tests. Compilation passed with warnings as errors;
strict Credo reported no issues. Regressions cover mixed flat and percentage
modifiers, caster and recipient bonuses, chain attenuation, direct and periodic
healing, resource gains, periodic snapshots and replacement, charge selection,
and bypass rules. DBC cases cover Frostbolt ranks, Imp Firebolt, Revenge,
Improved Bloodrage ranks, and Fireball. Warrior mask fixtures are verified in
separate VMangos tests, preserving mutually exclusive database tags.

Check logs use the same prefix with `all.log`, `compile.log`, `credo.log`, and
`commit.log`. The architecture dependency allowlist was unchanged.

Both WoW processes used hardware rendering: DRM graphics counters increased
from 1956244881 to 16762219604 ns for mage PID 2232100 and from 970566306 to
15592495640 ns for warrior PID 2233093. `server.log` contained no gameplay
errors or cast validation failures. Existing account-data and ticket-query
warnings appeared at login.

Both helper-owned services were stopped, their cgroups emptied, and both WoW
PIDs exited. The retained server PTY exited successfully; ports 4000, 3724, and
8085 were released. No changes were pushed.
