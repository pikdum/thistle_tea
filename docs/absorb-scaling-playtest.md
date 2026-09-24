# Absorb shield scaling

Implementation commit: `3546baf6`.

## Behavior and reference

Power Word: Shield now receives ten percent of the caster's healing bonus.
Fire Ward, Frost Ward, and Shadow Ward receive ten percent of the caster's
spell power for the ward's casting school. Ranks learned below level 20 apply
the existing vanilla level penalty. Base-amount spell modifiers, including
Improved Power Word: Shield, apply before this added bonus. Mana Shield and
unrelated absorbs retain their zero spell-power coefficient.

The bonus enters the aura only when it is created or refreshed. Changes to the
caster's equipment or buffs cannot refill a partly consumed shield, and login
does not apply the bonus again. Damage consumption, school filtering, expiry,
cancellation, and death use the existing shared aura transitions.

The reference is VMangos's `Aura::HandleSchoolAbsorb` and `Aura::HandleManaShield`
in `SpellAuras.cpp`, plus `SpellCaster::CalculateLevelPenalty`. The latter
Mana Shield handler explicitly identifies its zero vanilla coefficient.
Shadow Ward's current DBC and VMangos template rows use the generic spell family,
although the reference's scaling branch sits inside the warlock family case.
The implementation accepts both families using its shadow school, icon 207, and
category 56, so those actual ranks receive the intended ward bonus.

## Automated verification

- `mix test.all`: **5,483 passed**.
- `mix compile --warnings-as-errors` and `mix credo --strict`: passed.
- Formatting, whitespace checks, and commit hooks: passed.

Regressions exercise caster versus recipient bonuses, healing versus damage
power, low-rank penalties, base talent ordering, unrelated shields, Mana Shield
capacity and mana consumption, school filtering, partial absorption, snapshot
retention, refresh with changed caster bonuses, exhaustion, expiry, cancellation,
and death. DBC coverage checks fifteen shield and ward ranks, including all four
Shadow Ward ranks and Mana Shield's zero coefficient.

## Native build-5875 acceptance

An isolated GPU client used Debugpriest (GUID 4), raised to level 60 through the
existing development command. Spell learning used `.learn`; casts, buff
cancellation, logout, and character entry used native client actions. Ward
spells were learned on this same character for controlled comparisons. Tidewave
only read owner state.

The character rested in Lion's Pride Inn near `{-9463, 20, 56.9}` on map 0.
Damage checks used the inn's real fireplace at `{-9455.6, 23, 56.9157}`.
Teleports between the two positions used the existing debug command.

| Spell and caster state | Authoritative capacity |
| --- | ---: |
| Power Word: Shield 10901, no healing bonus | 942 |
| Existing shield after learning +300 healing | 942 |
| Fresh shield with +300 healing | 972 |
| Improved Power Word: Shield rank 3 and +300 healing | 1,113 |
| Fire Ward 543, 26 fire spell power | 167 |
| Existing ward after Supreme Power raises fire power to 176 | 167 |
| Fresh ward at 176 fire spell power | 182 |
| Shadow Ward 6229, 150 shadow spell power | 305 |

The talent result is `trunc(942 * 1.15 + 300 * 0.1) = 1113`. Shadow Ward
loaded with spell family zero and still gained the expected fifteen capacity.

Power Word: Shield visibly absorbed fireplace pulses without losing health.
A partially consumed shield retained exactly **870** capacity across immediate
inn logout and reconnect, with identical application and expiry timestamps.
An earlier timed sample also observed ordinary expiry followed by health damage.
The final reconnect sample waited for the new player owner to exist; an earlier
probe during the loading screen was too early and is not used as acceptance.

The scaled Fire Ward consumed capacity
**182 → 136 → 86 → 37 → removed**. Health remained at 2,357 during the fully
absorbed pulses, then fell to 2,341 when the ward ran out. Exhaustion occurred
about seventeen seconds before its scheduled expiry. The client showed the
ward icon, zero-damage absorbed hits, removal, and subsequent damage.

## Evidence and cleanup

Client session: `/home/pikdum/.cache/thistle-wow-playtest.GAq9Yy`.
Useful files in its `screenshots/` directory:

- `priest-base.png`, `priest-shield-fire.png`, `priest-partial-reconnect.png`
- `ward-power-snapshot.png`, `ward-absorbing.png`, `ward-depleted.png`
- `shadow-ward.png`

Compact state evidence is `/tmp/thistle-absorb-priest-{base,new-bonus,scaled,talent}.txt`,
`/tmp/thistle-absorb-priest-{partial2,reconnect2}.txt`,
`/tmp/thistle-absorb-ward-{base,new-power,scaled,depletion}.txt`, and
`/tmp/thistle-absorb-shadow-ward.txt`. Server log:
`/tmp/thistle-absorb-server.log`.

No server errors or spell-validation failures occurred. Existing warnings were
limited to account-data, GM-ticket, and meeting-stone messages. The initial
setup commands sent during login/teleport loading were repeated after the client
was ready; acceptance uses the subsequent verified casts.

WoW PID 69706 used `amdgpu` on `0000:0c:00.0`; its graphics counter rose from
936,775,506 to 17,695,172,402 ns, recorded in
`/tmp/thistle-absorb-gpu-{start,end}.txt`. The helper-owned client service and
retained server were stopped after acceptance.
