# Detect Magic

Detect Magic now reveals an enemy's beneficial auras in the vanilla client.
DBC aura 100 loads as `:auras_visible`; the shared aura recomputation derives
`UNIT_FLAG_AURAS_VISIBLE` (`0x08000000`) from the remaining holders. This works
for creatures and players, preserves unrelated flags, and stays active until
the last reveal source ends. Ordinary public unit updates carry the flag to
observers; the client uses it to expose enemy buffs.

Reference: `Aura::HandleAurasVisible` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp` and `UNIT_FLAG_AURAS_VISIBLE` in
`refs/vmangos/src/game/Objects/UnitDefines.h`.

The support manifest no longer lists this aura or the already implemented
reputation-gain modifier as deferred.

## Automated validation

- `mix test.all`: **4,364 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

Tests cover player and creature application, observer flag serialization,
refreshing the deadline, overlapping reveal sources, dispel, expiry, death,
and stale projection cleanup. The DBC test verifies spell 2855's aura,
two-minute duration, hostile target, and magic dispel category.

Logs: `/tmp/thistle-detect-magic-{all,compile,credo}.log`.

## Native client acceptance

Used two isolated build-5875 clients against a fresh server: level-50
Debugpriest (GUID 4) and Debugbidder, a Mage (GUID 11), on map 451. God mode
was off. Both players entered a normal duel. Spell casts used the client;
existing `.go xyz` and `.die` commands handled staging and the death case.
Tidewave probes only read live state.

| Scenario | Observed result |
| --- | --- |
| Before revelation | The Priest retained Power Word: Fortitude 10937. The Mage's `UnitCanAttack` returned 1 and `UnitBuff("target", 1)` returned nil. |
| Detect Magic 2855 | The Priest gained the negative aura in slot 32. Flags changed from 36872 to 134254600. The Mage's target frame displayed Fortitude, and `UnitBuff` returned its icon. |
| Dispel Magic 988 | The Priest dispelled the reveal. Fortitude remained active, flags returned to 36872, and the Mage's buff icon and `UnitBuff` result disappeared while the target remained hostile. |
| Buff added during revelation | After another Detect Magic, the Priest cast Inner Fire 10951. Both Inner Fire and Fortitude appeared on the Mage's target frame and through `UnitBuff`. |
| Natural expiry | The two-minute Detect Magic expired without another dispel or retarget. Both beneficial auras remained on the Priest, while the Mage's buff icons disappeared and `UnitBuff` returned nil. The reveal flag cleared. |
| Death | With another Detect Magic still active and about 117 seconds remaining, `.die` killed the Priest. Health became zero, the reveal holder and flag cleared, and the client displayed the corpse and release prompt. |

The native run exercises player targets. Creature application and overlapping
sources are covered by automated tests. No gameplay owner errors or cast
validation failures appeared in the server log. Existing unimplemented
account-data, raid-info, GM-ticket, and meeting-stone notifications remain.

## Retained evidence

- Server log: `/tmp/thistle-detect-magic-server.log`.
- State probes: `/tmp/thistle-detect-magic-{before,active,dispelled,second-active,expiry-midpoint,expiry-late,before-death,death}.txt`.
- Mage screenshots: `/home/pikdum/.cache/thistle-wow-playtest.TOkLFX/screenshots/`,
  including `detect-revealed.png`, `detect-dispelled.png`,
  `detect-new-buff.png`, and `detect-expired.png`.
- Priest death screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.DXY6Uc/screenshots/detect-death.png`.

Both helper-owned clients and their displays, and the retained server, were
stopped after acceptance. No changes were pushed.
