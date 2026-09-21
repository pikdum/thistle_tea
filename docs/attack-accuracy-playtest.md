# Weapon attack accuracy

White melee swings now include the vanilla 19 percentage-point dual-wield miss
penalty when the attacker has a usable offhand weapon. Both hands receive the
penalty. Specials and ranged attacks do not. Queued next-swing attacks and
active physical casts suppress it; consuming or cancelling the queue restores
it. The snapshot uses canonical equipment inputs, so shields, broken weapons,
unequipped offhands, and player natural-weapon forms do not enable the penalty.
Creature offhands use their virtual equipment class.

Hit bonuses apply after low-level creature scaling. Against a defense advantage
greater than ten points, the first positive attacker hit point is ignored.
Incoming melee and ranged hit modifiers are applied separately afterward.
Aura 184 now maps to the melee incoming-hit modifier; the local build-5875 DBC
contains no spells using that aura, so its behavior is covered by pure fixtures.

Player attacks use a player's trained maximum defense, plus both skill bonuses,
for miss and critical adjustments. Creature attacks use current defense. The
character's current defense still supplies displayed dodge, parry, and block.
Glancing frequency, creature parry, and negative creature critical adjustments
cap weapon skill at the attacker's level maximum. Extra weapon skill still
improves glancing damage. Priests, mages, and warlocks receive their glancing
damage penalty. Ranged attacks cannot glance or be blocked.

The client test exposed a related queueing bug: Heroic Strike was rejected
outside melee range. The loader now retains the combat-range classification,
and validation permits next-swing combat-range attacks to queue before reaching
their target. Other range types, world separation, target validity, resources,
and line of sight retain their checks. The combat behavior tree waits for melee
reach before consuming the queue, spending rage, and delivering the attack.
It recalculates and checks the power cost at consumption. An unaffordable
queued attack clears, emits the normal cast failure, and falls back to a white
swing with the dual-wield penalty restored.

## Reference

The local VMangos reference was `8f4e60845`:

- `Objects/SpellCaster.cpp`: `GetMeleeMissChance`, `GetDefenseSkillValue`, and
  `RollMeleeOutcomeAgainst`.
- `Objects/Unit.cpp`: `GetUnitCriticalChance` and
  `GetGlancingBlowDamageMultiplier`.
- `StatSystem.cpp`: defense-derived avoidance fields.
- `Spells/Spell.cpp`: `CheckRange` for next-swing combat-range spells.
- `Spells/Spell.cpp` and `Objects/Unit.cpp`: final power checks and white-swing
  fallback after an unsuccessful queued attack.
- Build-5875 `SpellRange` rows distinguish combat range from other five-yard
  ranges; tagged loader tests cover Heroic Strike, Cleave, Maul, and contrast
  them with an ordinary short-range next-swing spell.

## Automated coverage

- `mix test.all`: **4,488 passed**.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Gate logs: `/tmp/thistle-accuracy-final-{all,compile,credo}.log`.

Deterministic boundary rolls cover both hands, specials, ranged attacks,
low-level scaling, the first hit point, incoming-hit modifiers, PvP and PvE
defense, capped skill adjustments, and caster glancing damage. Behavior-tree
tests exercise an out-of-range queue, an offhand swing while queued, and the
subsequent main-hand consumption and offhand penalty. Owner-boundary durability
tests prove that breaking and repairing an offhand updates the penalty, while a
shield does not add it.

## Native build-5875 acceptance

The initial client session, running `072daa30`, used Debugwarrior at level 50
with a Worn Shortsword and Worn Dagger against a level-51 Skeletal Flayer.
The live weapon snapshots had 255 Sword skill and 250 Dagger skill, with miss
boundaries of 24% and 24.5%. These are deterministic evaluations of the live
snapshots, not estimates from a small sample of random attacks.

Attempting to queue Heroic Strike at range displayed “You are too far away!”
and produced an `out_of_range` rejection. The queue remained empty. This
reproduction prompted the follow-up queueing fix and a fresh-server retest.

Initial artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.NTc98A/screenshots/dual-equipped.png`
- `/home/pikdum/.cache/thistle-wow-playtest.NTc98A/screenshots/queue-at-range.png`
- `/tmp/thistle-accuracy-equipped.txt`
- `/tmp/thistle-accuracy-queued.txt`
- `/tmp/thistle-accuracy-server.log`

The initial helper-owned client, X server, and game server were stopped before
retesting the fix.

A development retest in `/home/pikdum/.cache/thistle-wow-playtest.L29YhL`
confirmed that Heroic Strike rank 8 (`11566`) queued against a level-50 Flayer
without damaging it. Live miss thresholds became 4.5% for the sword and 5% for
the dagger. Native `SpellStopCasting()` cleared the queue and restored 23.5%
and 24%. A zero-rage queue also cleared at the next actual swing after the
power-check fix, restoring the penalty without consuming power.

The power-check change was loaded through the development web reloader. Its
temporary module replacement produced four rescued mob-tick errors. The
loaded module hash matched the compiled file afterward. This server and client
were stopped; the final acceptance uses a fresh server with the committed code.

Development retest artifacts:

- `/tmp/thistle-accuracy-final-queued.txt`
- `/tmp/thistle-accuracy-final-cancelled.txt`
- `/tmp/thistle-accuracy-rage-fixed-before.txt`
- `/tmp/thistle-accuracy-rage-fixed-transitions.txt`
- `/tmp/thistle-accuracy-code-version.txt`
- `/tmp/thistle-accuracy-final-server.log`

## Final acceptance

A fresh server and `/home/pikdum/.cache/thistle-wow-playtest.DtFUop` ran
`04267e31`, with no development reloads. The level-50 warrior again used the
shortsword and dagger, now against a level-51 Flayer. God mode kept the warrior
alive; rage costs still applied. A temporary client Lua listener echoed native
combat and UI-error events into General chat for the screenshots. All gameplay
actions used native chat, inventory, and casting APIs; Tidewave only read state.

| Scenario | Observed result |
| --- | --- |
| Heroic Strike queued at range | Queue `11566` retained, target health 2,980 unchanged, penalty suppressed; live miss boundaries 5% and 5.5%. |
| Entering melee and starting attacks | Client combat event: Heroic Strike hit for **102**. The sampled owner transition showed rage **540 → 390**, queue cleared, and penalty restored. Subsequent miss boundaries were **24% and 24.5%**. |
| Queue retained after rage dropped to zero | Client displayed **“Not enough rage”** at the attempted swing. The queue cleared, ordinary attacks generated rage, and the penalty returned. No free Heroic Strike was delivered. |
| Native offhand removal and re-equipping | The visible entry changed `2092 → 0 → 2092`; the canonical offhand input changed `2.0 → nil → 2.0`; the penalty changed `true → false → true`. Owner and stored equipment agreed. |
| Equipment worn to zero durability | Client displayed the red broken-equipment indicator. Weapon appearances remained `{25, 2092}`, but the offhand input became nil and the penalty became false. |
| Completed logout and re-entry | Owner and stored character retained the broken equipment, nil offhand input, disabled penalty, and empty queued attack. The native client retained the broken-equipment indicator. |

The client can still report an out-of-range white swing while a spell remains
queued; that message does not mean queue validation failed. Teleporting clears
the selected target, so the test reselected the Flayer and started attacks
after moving into melee.

Final artifacts:

- `/home/pikdum/.cache/thistle-wow-playtest.DtFUop/screenshots/heroic-consumed.png`
- `/home/pikdum/.cache/thistle-wow-playtest.DtFUop/screenshots/no-rage-fallback.png`
- `/home/pikdum/.cache/thistle-wow-playtest.DtFUop/screenshots/broken-weapons.png`
- `/home/pikdum/.cache/thistle-wow-playtest.DtFUop/screenshots/logged-out.png`
- `/home/pikdum/.cache/thistle-wow-playtest.DtFUop/screenshots/reconnected.png`
- `/tmp/thistle-accuracy-acceptance-{queued,consumed,after}.txt`
- `/tmp/thistle-accuracy-acceptance-{starved-before,starved,starved-after}.txt`
- `/tmp/thistle-accuracy-acceptance-{unequipped,reequipped,broken,reconnect}.txt`
- `/tmp/thistle-accuracy-acceptance-server.log`

The fresh server log contained no errors or spell-validation failures. Existing
login warnings remained for account-data updates, raid information, GM tickets,
and meeting-stone information. All three helper-owned clients and X servers,
and all three retained game servers, were stopped. Reconnect persistence here
means the running server's in-memory character store; a server restart resets it.

Implementation commits:

- `072daa30`: dual-wield accuracy, hit ordering, defense, and skill caps.
- `e756e6c9`: next-swing queueing outside melee range.
- `04267e31`: final power validation and white-swing fallback.
- `edb74668`: correction of the prior redundant enchanted-entry decode and its
  inaccurate bug note; the regression test remains.
