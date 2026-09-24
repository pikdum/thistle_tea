# Healing received, spell coefficients, and chain scaling

Incoming flat healing bonuses now use the healing spell's coefficient and
school at application time. Each HoT tick reads the recipient's current
bonuses without changing its stored caster contribution. Negative flat
bonuses cannot remove more than half the incoming heal; existing percentage
modifiers follow the flat calculation. Healing Way stacks now amplify
Healing Wave, and Blessing of Light uses the appropriate Holy Light or
Flash of Light effect through the same coefficient calculation.

Related fixes apply caster healing percentages to the full caster amount,
attenuate spell-power contributions on chain jumps, and load the triggered
heal's coefficient for every flattened Flash of Light rank. Amplify and
Dampen Magic now share an exclusive aura category across ranks and casters.
These changes reuse the existing aura transitions, pure calculation paths,
cached loaders, healing feedback, and threat effects.

## References and automated validation

- `refs/vmangos/src/game/Objects/Unit.cpp`, `SpellHealingBonusTaken`:
  current target bonuses, school filtering, Healing Way, Blessing of Light,
  coefficient scaling, the negative half-heal limit, and percentage ordering.
- `refs/vmangos/src/game/Objects/SpellCaster.cpp`, healing bonus calculation:
  caster flat contributions precede caster healing percentages.
- `refs/vmangos/src/game/Spells/SpellAuras.cpp`, periodic healing:
  caster contributions are stored while recipient bonuses are evaluated
  when each tick lands.
- `refs/vmangos/src/game/Spells/SpellEntry.cpp`: chain-jump coefficient
  attenuation.
- `refs/vmangos/src/game/Spells/SpellEffects.cpp`: Flash of Light's special
  effect invokes heal 19993 with its rolled base amount. The VMangos cache
  supplies coefficient 0.429 for that heal; the wrapper ranks have zero.
- `refs/vmangos/src/game/Spells/SpellMgr.cpp`, `IsNoStackSpellDueToSpell`,
  and the DBC's shared Mage family flag 0x2000: Amplify and Dampen exclusion.

Regression coverage includes direct heal amounts, crit ordering, threat and
combat messages, school filtering, signed bonuses, the negative cap,
low-rank coefficients, explicit zero coefficients, stacks, non-spell heals,
current HoT modifiers, unchanged tick snapshots, Healing Way expiry,
Blessing effect selection, chain damage/healing power, and all Flash of
Light ranks in individual and bulk loads. Separate DBC and VMangos tests
verify the real spell rows and cached coefficients. Amplify/Dampen tests
check every rank's category and replacement across different casters.

Implementation commits `122b40ee` and `3f487986` passed `mix test.all`
(5,562 tests), `mix compile --warnings-as-errors`, `mix credo --strict`
(zero issues), formatting, and whitespace checks.

## Native client acceptance

A fresh server with both implementation commits served the isolated
build-5875 GPU client. Debugpriest (GUID 4) tested at level 60 on Programmer
Isle, map 451, near `{16303.2, 16318.1, 69.44}`. God mode stayed off.
Learning spells from other classes, equipping, changing starting health,
casting, and cancelling buffs all used native client commands. Tidewave
only read state. Client event callbacks echoed actual healing messages.

The first trial had zero caster healing bonus. One continuous rank-9 Renew
(10929) retained amount 162 and its original 15-second lifetime throughout:

| Sample time | Current recipient state | Tick healing |
| --- | --- | --- |
| 5,233 ms | No flat bonus | 162 |
| 8,229 ms | Amplify Magic 10170, +150 | 192 |
| 11,229 ms | Dampen Magic 10174, -180 | 126 |
| 14,231 ms | Dampen still active | 126 |
| 17,235 ms | Dampen cancelled | 162 |

Amplify arrived at 6,683 ms. Dampen replaced it at 11,052 ms, leaving only
the negative modifier. Native cancellation removed Dampen at 15,461 ms.
The final tick also removed Renew. Client messages matched each tick's
authoritative health increase; separate natural-regeneration samples were
excluded from those amounts.

For direct healing, the priest learned Staves (227) and equipped Benediction
(18608), providing +106 healing. An initial equip attempt correctly failed
before the proficiency was learned. Flash of Light rank 6 (19943) healed for
396 without Blessing and 458 with Blessing of Light rank 3 (19979). Both
client messages matched the owner health changes. At level 60, the expected
noncritical ranges are 393–433 and 442–482 respectively: caster power adds
45, and the Blessing's 115-point Flash benefit adds 49 after scaling.
The Blessing holder retained its separate 400/115 dummy effects.

Healing Way rank 3 (29202) then triggered normally from four native rank-1
Healing Wave casts. Owner samples and client messages agreed on heals of
54, 61, 63, and 67, with recipient stacks progressing `absent → 1 → 2 → 3`.
The fourth cast retained three stacks and refreshed the 15-second expiry.
The client displayed three applications, then lost the buff after expiry;
a subsequent owner read confirmed 29203 absent while the permanent talent
remained. Deterministic tests separately prove family filtering and the
exact multiplier independently of healing rolls.

Final state had no active test buffs, no cast, god mode off, and a live
owner. No server errors or cast-validation failures occurred. The only
unsupported requests were the known account-data, GM-ticket, and
meeting-stone login messages. WoW process 138453 had its own amdgpu DRM
rendering counters. The helper-owned client cgroup and server were stopped.
No second observer client or native chain-jump trial was used; chain
amounts, threat, and packet effects have automated regression coverage.

## Retained evidence

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.NZrOd4/`.
- Screenshots in its `screenshots/`: `renew-current-bonuses.png`,
  `flash-healing-bonuses.png`, `healing-way-stacked.png`,
  `healing-way-expired.png`, and `healing-final.png`.
- Owner samples: `/tmp/thistle-healing-bonus-renew.txt`,
  `/tmp/thistle-healing-bonus-flash.txt`, and
  `/tmp/thistle-healing-bonus-way.txt`. The last output is truncated after
  the stacking/refresh evidence; the separate post-expiry read is
  `/tmp/thistle-healing-bonus-way-expired.txt`.
- Direct-heal inputs: `/tmp/thistle-healing-bonus-flash-context.txt`.
- Final owner state: `/tmp/thistle-healing-bonus-final-state.txt`.
- Server and GPU evidence: `/tmp/thistle-healing-bonus-server.log` and
  `/tmp/thistle-healing-bonus-gpu.txt`.
- Gates: `/tmp/thistle-healing-bonus-final-{tests,compile,credo}.log`.
