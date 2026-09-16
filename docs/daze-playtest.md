# Rear-hit daze

Uncontrolled creatures can now daze targets with damaging melee attacks from
behind. `Logic.Daze` rolls independently of the melee attack table and emits
a typed trigger for spell 1604. The ordinary spell and aura lifecycle handles
the 50% movement slow, four-second duration, refresh, immunity, and expiry.
Players, pets, charmed creatures, ranged attacks, fully absorbed hits, dead
targets, and invincible targets do not qualify.

The rules follow `Unit::RollDazeOutcome` in the pinned
`refs/vmangos/src/game/Objects/Unit.cpp`:

- Below target level 30, base chance is `0.65 * level + 0.5` percent.
- At level 30 and above, base chance is 20%.
- Add 0.2 percentage points per attacker melee skill minus target defense.
- Clamp to 0–40%.

All local vanilla ChrRaces rows use spell 1604, also the reference's default.
There are no gameplay database queries or new timers.

Inspection also found that the existing melee table ignored defensive skill
auras. `Skills.defense_value/1` now combines trained defense with matching
`mod_skill` and `mod_skill_talent` bonuses for both melee and daze calculations.
Its regression failed before the fix: +20 defense left daze chance at 20%
instead of 16%. It also verifies that the same bonus moves a melee roll into
the miss range, while bonuses to another skill have no effect.

## Real-client acceptance

Used an isolated build-5875 client and the seeded level-50 Debugwarrior on
Programmer Isle, with god mode disabled. Moving through the client command
`.go xyz 16260 16338 69.44 451` attracted the seeded Skeletal Flayers behind
the character, whose orientation was 0. No attack or aura was injected.

The client displayed `<Dazed>` and the debuff icon/countdown. Read-only owner
samples recorded repeated application, refresh, and natural expiry. Selected
server monotonic milliseconds from the first run:

| Time | Run speed | Daze expiry | Health |
| --- | --- | --- | --- |
| -576460594804 | 3.5 | -576460591015 | 1978 |
| -576460593738 | 3.5 | -576460589764 | 1921 |
| -576460590145 | 3.5 | -576460589764 | 1792 |
| -576460589636 | 7.0 | absent | 1724 |

Later rear swings applied Daze again. The unattended warrior eventually died;
the expiry evidence above was captured while alive. The server logged no
errors. Existing unsupported login/query/account-data packet warnings remain
outside this feature's acceptance.

Retained evidence:

- `/home/pikdum/.cache/thistle-wow-playtest.8tn9r7/screenshots/combat.png`
- `/tmp/thistle-daze-samples.txt`
- `/tmp/thistle-daze-server.log`

After the defense correction, a fresh server repeated the rear-hit check.
The client again displayed Dazed; the owner recorded speed 3.5, health 2033,
and aura timestamps `{-576460646794, -576460642794}`. After moving and
teleporting back to the safe starting point, Daze expired naturally: speed
returned to 7.0, health was 1770, and god mode remained false. The screenshots
`daze-final.png` and `recovered-final.png` in the same session directory,
`/tmp/thistle-daze-samples-final.txt`, and
`/tmp/thistle-daze-server-final.log` retain this final-revision check.

Automated tests cover eligibility, geometry, probability boundaries, level
protection, skill differences, defense bonuses, damage/absorb/death handling,
spell attribution, and the real DBC slow/refresh/expiry lifecycle.

Final validation: `mix compile --warnings-as-errors`, `mix test.all` (2,853
passing tests), `mix credo --strict`, formatting, and diff checks. The isolated
client and local server were stopped after acceptance.
