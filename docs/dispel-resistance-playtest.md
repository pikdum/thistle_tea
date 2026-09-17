# Dispel resistance and spell modifier masks

Dispels now respect the original aura caster's current resistance modifiers.
Vanilla Vile Poisons provides up to 40% resistance for affected rogue poisons.
The target boundary reads the caster's published modifier projection, or the
owner's projection for a pet-cast aura, and supplies plain chances to the pure
dispel logic. Self dispels use the same receiving boundary. Missing casters
provide no resistance; owner-local state takes precedence over cached metadata.

Each attempt selects and spends one candidate stack, even on failure. Failed
stacks remain on the target and cannot be retried during that same dispel effect.
Successful attempts remove only their selected stacks through the shared aura
transition. Failures emit `SMSG_DISPEL_FAILED` with full caster/target GUIDs and
one spell ID per failure; successful removals retain `SMSG_SPELLDISPELLOG`.
Devour Magic heals only when at least one removal succeeds.

Investigation also found that spell modifiers were missing VMangos's family
masks. The loader now preloads the latest supported `spell_template` masks for
flat and percent modifiers, retaining explicit `spell_effect_mod` precedence.
Matching includes both halves of the 64-bit spell-family flags. Empty masks no
longer match every spell. Vile Poisons therefore affects its intended poison
abilities rather than every rogue spell. Item identifiers remain separate from
these modifier masks.

References: `Spell::EffectDispel` in
`refs/vmangos/src/game/Spells/SpellEffects.cpp`, `SpellModifier::IsAffectedOnSpell`
in `SpellModifier.cpp`, `GetSpellAffectMask` in `SpellMgr.h`, and the vanilla
packet definition in
`refs/wow_messages/wow_message_parser/wowm/world/spell/smsg_dispel_failed.wowm`.

## Real-client acceptance

Two isolated build-5875 clients ran Debugrogue (GUID 3) and Debugpaladin
(GUID 2), dueling on Programmer Isle with god mode disabled. The rogue learned
Vile Poisons rank 5 (16720) and the Deadly Poison rank 1 debuff spell (2818)
through `.learn`, then cast the poison through the client. This exercised spell
application and dispelling directly; weapon-enchant proc delivery was not tested.
The paladin self-cast Purify (1152). Read-only Tidewave samplers recorded owner
state every 100 ms, retaining changes in poison stacks, expiry, next tick,
health, and the rogue's published resistance.

- The loaded talent projected `{family: 8, amount: 40, mask: 268550144}`.
  Calculated resistance was 40% for Deadly Poison and 0% for Garrote.
- A successful Purify reduced two stacks to one without changing expiry or the
  next scheduled tick. Damage changed from 24 to 12 per tick.
- Two subsequent Purifies failed. The paladin displayed “You fail to dispel
  your Deadly Poison,” and the rogue's combat log displayed the corresponding
  observed failure. The remaining stack continued ticking and expired at its
  original deadline. One earlier poison application resisted normally; that
  application failure is distinct from dispel resistance.
- In another round, `.talents reset` removed the rogue's resistance while three
  poison stacks were already active. The existing holder retained its expiry
  and tick schedule. Three successive Purifies then reduced the count from
  three to two to one to zero, completing over three seconds before expiry.
  No further poison damage occurred during the sampling window.
- Relearning Vile Poisons restored the 40% projection. With two protected
  poison stacks active, `.die` removed both immediately, cancelled the duel,
  and displayed the release-spirit prompt. Health stayed at zero with no
  remaining poison holder or subsequent ticks.

An initial automatic login selected the already-connected rogue in the second
client and was rejected; selecting the paladin resolved setup. Earlier
exploratory sessions were discarded after correcting the family-mask loader.
No gameplay owner or packet exceptions occurred during the accepted scenarios.
All helper clients and the retained server were stopped before final validation.

Automated coverage additionally checks mixed success/failure within one cast,
attempt exhaustion, independent casters, pet-owner lookup, missing casters,
current owner state, Devour Magic, full packet bytes, owner/observer delivery,
self-dispel routing, modifier stacking, family selection, empty masks, and high
mask bits. DBC and VMangos data tests use separate tags and fixtures.

## Validation

- `mix test.all`: 3,064 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Evidence

- Paladin screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.d6Sl8S/screenshots/`, especially
  `resistance-attempt-1.png`, `resistance-attempt-3.png`, `talent-reset-cure.png`,
  and `death-cleanup.png`.
- Rogue observer screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.9FBBOI/screenshots/resistance-observer.png`.
- Runtime evidence: `/tmp/thistle-dispel-resistance-source.txt`,
  `/tmp/thistle-dispel-resistance-round2.txt`,
  `/tmp/thistle-dispel-resistance-reset.txt`, and
  `/tmp/thistle-dispel-resistance-death.txt`.
- Server log: `/tmp/thistle-dispel-resistance-server.log`.
- Final gates: `/tmp/thistle-dispel-resistance-final-{tests,compile,credo}.log`.
