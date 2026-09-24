# Attack-power and haste aura modifiers

Implementation: `677d05ec`. Fractional bonus correction: `eecd06eb`.
Logout race correction found during acceptance: `9e4e0265`.

## Shared behavior

Spell-modifier operations 3 (attack power) and 23 (haste) now affect their
corresponding aura amounts. Family masks select the caster's modifiers, and
the cast context carries that snapshot into aura creation. The same mapping
determines whether a charged modifier is consumed. Flat and percentage melee
and ranged attack-power auras, general attack speed, melee/ranged haste, and
casting speed use this shared path.

Generic effect calculation precedes these aura-specific modifiers. Fractional
bonuses remain in the holder until the final stat or timing projection. This
matters for Bonescythe Breastplate: its six-percent improvement changes Slice
and Dice's 30% haste to **31.8%**, not 31%.

Casting speed now multiplies independent aura factors. Positive haste uses
`100 / (100 + amount)`; a negative slow uses `(100 - amount) / 100`. The derived
`UNIT_MOD_CAST_SPEED` field and actual cast preparation use the same calculation.
Abilities and professions ignore ordinary casting haste; ranged abilities use
ranged attack speed. Channel duration and tick spacing remain unchanged.

References are VMangos's attack-power and haste handlers in `SpellAuras.cpp`,
the floating-point `Modifier::m_amount` in `SpellAuras.h`, `Unit::UpdateCastSpeed`
for builds after 1.11.2, and `SpellEntry::GetCastTime`.

## Automated verification

- `mix test.all`: **5,503 passed**.
- `mix compile --warnings-as-errors`, `mix credo --strict`: passed.
- Formatting, whitespace checks, and commit hooks: passed.

Tests cover all eight aura types, family/mask exclusion, generic-effect ordering,
signed penalties, fractional aggregation, charge eligibility, replacement,
expiry, stable recomputation, owner/observer cast-speed serialization, actual
cast scheduling, profession/ability exemptions, and unchanged active casts when
an aura expires. DBC tests verify Improved Seal of the Crusader, Improved Enslave
Demon, Bonescythe, and the profession attribute. Improved Enslave Demon changes
its melee/casting penalties from -40%/-30% to -30%/-20%.

## Native build-5875 acceptance

The final isolated GPU session used Debugpaladin (GUID 2) and Debugrogue (GUID 3),
both raised to level 60 with the existing development commands. Talents and
the Bonescythe passive were learned with `.learn`; this checks the shared spell
modifier path rather than item acquisition. Casts, targeting, logout, and entry
were native client actions. Tidewave only read live owner state.

| Check | Authoritative and client-visible result |
| --- | --- |
| Seal of the Crusader 20308 without talent | Aura AP 325; character sheet AP 887 |
| Improved Seal of the Crusader 20337, fresh seal | Aura AP 373.75; character sheet AP 935 |
| Seal haste before/after talent | 40%; weapon period unchanged at 1,714 ms |
| Improved seal across inn logout/reconnect | AP 373.75 and both holder timestamps unchanged |
| Talent reset followed by recast | Aura AP 325; displayed AP restored to 887 |
| Seal expiry | AP 562 and weapon period 2,400 ms |
| Holy Light 10329, ordinary cast | 2,500 ms; cast-speed field 1.0 |
| Holy Light under Mind Quickening 23723 | 1,879 ms; cast-speed field 0.7518796992481203 |
| Mind Quickening expiry | Subsequent Holy Light restored to 2,500 ms and field 1.0 |
| Slice and Dice 6774 with Bonescythe 28107 | Aura haste 31.8%; server period 1,517 ms; client reports 1.517 seconds |
| Slice and Dice expiry | Aura removed; server period 2,000 ms; client reports 2.0 seconds |

The retained improved seal had application/expiry timestamps
`-576460620932` / `-576460590932` before and after reconnect. Holy Light's normal
and accelerated casts both completed and restored health. Premeditation against
a playground Rabbit supplied the rogue's combo points through normal spell
execution. Slice and Dice consumed them and expired normally.

## Logout regression

An earlier native run disconnected when logging out just after teleporting to
Lion's Pride Inn. A late `CMSG_QUESTGIVER_STATUS_QUERY` called the player owner
while it exited with `{:shutdown, :logout}`, crashing the network connection.

The connection now tolerates that expected call exit and an already stopped
owner. Its existing monitor remains the single path that detaches the player
and sends logout completion. Deterministic tests cover both arrival orders,
multiple queued queries, exactly one completion, and propagation of unexpected
failures.

The final client completed paladin logout/re-entry, paladin-to-rogue switching,
and rogue logout/re-entry immediately after the same inn teleport. All four
player logins used the same live network process, with no connection crash.

## Evidence and cleanup

Final session: `/home/pikdum/.cache/thistle-wow-playtest.5cDc6g`.
Useful files under `screenshots/`:

- `crusader-baseline.png`, `crusader-improved.png`, `crusader-reconnected.png`, `crusader-reset.png`
- `holy-light-baseline.png`, `holy-light-quickened.png`, `holy-light-restored.png`
- `bonescythe-period.png`, `bonescythe-expired.png`
- `logout-selection.png`, `rogue-logout-selection.png`, `rogue-reconnected.png`

Server log: `/tmp/thistle-aura-modifiers-accepted-server.log`.
Final test output: `/tmp/thistle-aura-modifiers-logout-tests.log`.
The accepted server run had no errors or spell-validation failures. Its warnings
were the existing account-data, GM-ticket, and meeting-stone unimplemented
messages. The earlier logout failure remains recorded in
`/tmp/thistle-aura-modifiers-final-server.log`.

WoW PID 91410 used `amdgpu`, DRM client 347. Its graphics counter increased from
1,436,609,682 to 11,774,430,765 ns. All three helper-owned client sessions and
their retained servers were stopped; screenshots and logs were retained.
