# Armor and resistance modifiers

Implementation commit: `e9f8598e`.

## Behavior

The shared resistance calculation now includes flat base resistance (aura 83),
agility armor, and independent percentage factors. Players and hunter pets gain
two armor per agility; ordinary creatures gain one. Equipment and flat base
bonuses receive base percentage modifiers before agility and ordinary flat
bonuses are added. Total percentage modifiers apply last, with one final
truncation. Exclusive resistance bonuses still select the strongest positive
and strongest negative contribution per school.

Debuffs cannot produce negative resistance unless the creature's base value is
already negative. Recalculation always starts from canonical inputs, so removing
gear, buffs, or forms cannot retain their armor. Creature construction computes
the same initial armor that later aura updates use. Hunter pet progression now
uses the explicit creature stat model while preserving its level-derived health.

The reference is VMangos's `Player::UpdateArmor`, `Creature::UpdateArmor`, and
`Pet::UpdateArmor` in `StatSystem.cpp`, `Unit::GetTotalResistanceValue` and
`Unit::HandleStatModifier` in `Unit.cpp`, and the base resistance handlers in
`SpellAuras.cpp`.

## Automated verification

- `mix test.all`: **5,477 passed**.
- `mix compile --warnings-as-errors` and `mix credo --strict`: passed.
- Formatting and whitespace checks: passed.

Regressions cover player, creature, and pet agility ratios; school masks; base
and total modifier ordering; independent percentages; holder stack changes;
fractional contributions; negative resistance rules; equipment removal; and
repeated recomputation. Aura application, replacement, expiry, and removal also
exercise actual attack mitigation: the controlled 1,000-damage attack changes
from 983 damage at 100 armor to 834 damage at 1,100 armor.

DBC tests verify Toughness 819 and the raw base-resistance effects of Demonic
Ally 21740 and Nature's Ally 21925. The latter two have VMangos runtime overrides
to ordinary resistance; the tests isolate raw DBC loading and restore those
overrides afterward.

## Native build-5875 acceptance

An isolated GPU client used level-50 Debugdruid (GUID 9) on Programmer Isle,
map 451, near `{16303.2, 16275.1, 69.44}`. Debug chat commands learned Agility
8115, Toughness 819, and Thick Hide 16933. Casts, talent reset, buff cancellation,
logout, and character entry went through the client. Tidewave probes only read
owner state.

The character had 896 equipment armor and no separate base armor. Every row
below agreed between the character panel and authoritative owner state.

| State | Agility | Armor |
| --- | ---: | ---: |
| Initial humanoid | 140 | 1,176 |
| Agility buff, +5 agility | 145 | 1,186 |
| Toughness passive, +15 base armor | 145 | 1,201 |
| Dire Bear Form, +360% base armor | 145 | 4,480 |
| Thick Hide, another +10% base armor | 145 | 4,899 |
| Talent reset removes Thick Hide | 145 | 4,480 |
| Agility buff cancelled | 140 | 4,470 |
| Dire Bear Form cancelled | 140 | 1,191 |
| Logout and reconnect | 140 | 1,191 |
| Fresh Dire Bear Form after reconnect | 140 | 4,470 |
| Form cancelled again | 140 | 1,191 |

The combined form and talent result is
`trunc((896 + 15) * 4.6 * 1.1 + 145 * 2) = 4899`. This distinguishes
multiplicative base modifiers from adding their percentages, and leaves agility
outside the base armor multiplier. Reconnect retained Toughness and discarded
the cancelled buffs and reset talent. Fresh form entry and removal reproduced
the same values without accumulating armor.

## Evidence and cleanup

Client session: `/home/pikdum/.cache/thistle-wow-playtest.5n5qd1`.
Its `screenshots/` directory contains `armor-base.png`, `armor-agility.png`,
`armor-base-flat.png`, `armor-bear.png`, `armor-thick-hide.png`,
`armor-agility-removed.png`, `armor-form-removed.png`, `armor-reconnect.png`,
`armor-reconnect-bear.png`, and `armor-final.png`.

Compact runtime samples are `/tmp/thistle-resistance-*.txt`; server log:
`/tmp/thistle-resistance-server.log`. No server errors or spell-validation
failures occurred. Existing warnings concerned account-data, GM-ticket, and
meeting-stone messages.

WoW PID 61018 used `amdgpu` on `0000:0c:00.0`; its own graphics counter rose
from 1,041,914,136 to 19,665,864,478 ns. The fdinfo snapshots are
`/tmp/thistle-resistance-gpu-{start,end}.txt`. The helper-owned client service
and retained server were stopped after acceptance.
