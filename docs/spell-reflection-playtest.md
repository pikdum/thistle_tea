# Spell reflection

General spell reflection (aura 28) now combines additively with matching
school-specific reflection (aura 74). This enables Magic Reflection and Sheen
of Zanza, including the potion's separate guaranteed first reflection and
its remaining 3% chance afterward.

Only harmful magic-class spells can reflect. Abilities, passive spells,
`NO_REFLECTION`, and `NO_IMMUNITIES` bypass reflection. Immunity takes
precedence. Reflected spells retain their original caster and record the
reflector separately for duel attribution; they cannot bounce repeatedly.
A reflected multi-effect cast spends one eligible proc charge per holder,
through the existing aura transition. School-specific holders only consume
charges for their own schools. Unrelated holders and unlimited reflection
remain intact.

References: `SpellCaster::SpellHitResult` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`,
`SpellEntry::IsReflectableSpell` in `refs/vmangos/src/game/Spells/SpellEntry.cpp`,
and the reflection outcome in `spell_proc_event` for spell 30003.

## Hit-order correction

Exploratory client testing found that the launch-time hit roll could announce
a resist before the receiving owner had a chance to reflect the spell.
Reflectable resisted casts now carry their saved outcome to the target.
The owner checks immunity and reflection before applying that outcome, and
sends the final reflection/resist feedback. Reflected delivery clears the
original target's resist outcome. The hit roll is still made once at launch;
this does not introduce another roll or database access at impact.

Launch bookkeeping retains its original hit/miss snapshot. Deferred resisted
impacts are not replayed on subsequent channel ticks. As with the existing
school-reflection path, reflection feedback is sent at impact using
`SMSG_SPELLLOGMISS`; a reflected return projectile is not encoded into the
launch packet.

Deterministic tests cover a saved resist becoming a reflection, a saved resist
remaining a resist without protection, caster attribution, no repeated bounce,
all seven schools, additive chances, bypass flags, immunity, multi-effect
charge spending, school filtering, removal, expiry, death, and channel ticks.

## Real-client acceptance

Two isolated build-5875 clients controlled Debugmage (GUID 5) and Debugwarlock
(GUID 6) in a duel on Programmer Isle. God mode was disabled. All setup,
potion use, casts, cancellation, and death came through the clients; runtime
probes only read the owning processes. The final server ran the ordering fix.

- The level-60 mage used an actual Sheen of Zanza item (20080). The server
  retained a 3% holder (24417) and a separate one-charge, 100% holder (30003).
  A level-10 warlock's first Frostbolt reflected. Mage health stayed at 2,350;
  the warlock fell from 898 to 876 health and acquired Frostbolt's slow, with
  run speed falling from 7.0 to 4.2. The first-reflection holder disappeared,
  while the 3% holder remained. The slow expired and run speed returned to 7.0.
  The caster's combat log explicitly showed reflection and 22 damage to self.
- With both characters subsequently at level 60, refreshed Magic Reflection
  (20223) returned Frostbolt, Fireball, and Shadow Bolt. Mage health stayed
  at 2,350 throughout that sequence. The caster displayed the returned damage
  and debuffs, including Fireball's subsequent periodic damage. Fireball
  crit for 31 and Shadow Bolt hit for 18. Refresh retained one Magic Reflection
  holder and extended its expiration.
- Magic Reflection lasts ten seconds in the loaded DBC. Owner samples observed
  its automatic removal. An initial three-school attempt ran after that short
  buff had expired and correctly produced ordinary hits/resists; the accepted
  reflection sequence refreshed the buff before each cast.
- Frost Nova hit through an active Magic Reflection, dealing 31 damage and
  rooting the mage. Both the reflection holder and root were present together
  in the authoritative sample. Reflection and root then expired, leaving only
  Sheen's 3% holder; the client showed the root and both fade events.
- Client cancellation removed Sheen's remaining 3% holder. The concurrently
  active Magic Reflection remained in the immediate sample and then expired.
  A subsequent unprotected Frostbolt hit the mage for 22. This sequence proves
  cancellation of Sheen and expiry of Magic Reflection; it does not claim
  immediate cancellation of both buffs by the helper's Lua loop.
- A fresh potion and Magic Reflection produced all three reflection holders,
  including the unused one-charge guarantee. `.die` reduced health to zero,
  removed all three, and cancelled the duel. A later sample still had zero
  health and no non-passive auras. The client showed the release-spirit prompt.

The first exploratory item-use attempt was rejected because the level-50
character did not meet the potion's level-55 requirement. After raising the
character's level, real item use succeeded. The earlier resist-before-reflect
finding was fixed and regression-tested before the final server was launched.

No player-owner, cast-validation, or packet errors occurred on the final
server. Login emitted the existing unsupported account-data, raid-info,
GM-ticket, time-query, and meeting-stone warnings. Those auxiliary messages
were outside this gameplay change. The clients and server were stopped before
final validation.

## Evidence

- Final server log: `/tmp/thistle-reflection-final-server.log`.
- Runtime samples: `/tmp/thistle-reflection-final-first.txt`,
  `final-schools.txt`, `final-nova.txt`, `final-before-cancel.txt`,
  `final-after-cancel.txt`, `final-unprotected.txt`, `final-before-death.txt`,
  `final-death.txt`, and `final-death-later.txt`, all with the
  `/tmp/thistle-reflection-` prefix.
- Mage screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.k3xtXN/screenshots/`, especially
  `final-sheen-ready.png`, `final-charge-spent.png`, `final-nova-bypass.png`,
  `final-cancelled-hit.png`, and `final-death.png`.
- Caster screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.pnhitJ/screenshots/`, especially
  `final-first-reflected.png` and `final-schools-reflected.png`.

## Final validation

- `mix test.all`: 3,137 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Logs: `/tmp/thistle-reflection-final-{tests,compile,credo}.log`.
