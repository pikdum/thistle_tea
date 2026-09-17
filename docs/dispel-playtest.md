# Stack-aware dispelling

Dispels now spend one attempt per aura stack, preserving remaining stacks,
their expiry, and their next tick. Multiple attempts can remove several stacks
from the same holder. The existing aura transition recomputes derived stats
and client aura fields after partial removal. Independent caster holders stay
separate. Devour Magic heals after a successful partial removal as well as
after removing a whole holder.

Dispel All (type 7 or a negative effect misc value) covers magic, curses,
diseases, and poisons. Magic and poison respect friendly/hostile polarity;
the other categories follow the reference's category-only selection. Cast
validation and removal share the same matching rules. Successful removals
emit the vanilla `SMSG_SPELLDISPELLOG` to the target and nearby observers.

Reference behavior: `Spell::EffectDispel` in
`refs/vmangos/src/game/Spells/SpellEffects.cpp`, and `GetDispellMask` in
`SpellEntry.h`. The packet layout is verified against the vanilla definition
in `refs/wow_messages/wow_message_parser/wowm/world/spell/smsg_spelldispellog.wowm`.
Talent-based resistance is covered by the subsequent
[dispel resistance implementation and playtest](dispel-resistance-playtest.md).

Testing also exposed that ordinary periodic-damage auras ignored their stack
count. Their damage now scales with remaining stacks. Ignite keeps its
existing accumulated damage calculation and is not multiplied twice.

## Real-client acceptance

Two isolated build-5875 clients ran Debugwarlock (GUID 6) and Debugpaladin
(GUID 2), dueling on Programmer Isle with god mode disabled. The warlock
learned Localized Toxin (7947) through `.learn` and cast it normally. The
paladin used Purify (1152). Tidewave sampled owner state without changing it.

- Three Localized Toxin stacks appeared on the paladin and dealt 57 damage
  per five-second tick (19 per stack).
- Purify reduced three stacks to two. Owner samples retained the exact expiry
  and next-tick timestamps, while subsequent ticks dealt 38 damage. Ordinary
  regeneration is visible separately in the health timeline.
- Both clients visibly showed two stacks after the partial cure. The target
  also received the native combat-log text, "Your Localized Toxin is removed."
- Further cures reduced the stack count to one and then removed the holder.
  The client showed the aura fading, and a read-only owner snapshot confirmed
  no poison holder before its original expiry deadline.
- In a separate round, one remaining stack expired at its original deadline,
  leaving no holder or subsequent damage ticks.
- Purify with no remaining eligible aura returned `nothing_to_dispel`.

Early setup attempts used a different NPC poison and a duplicated duel-accept
action; these were not acceptance evidence. One toxin cast resisted normally
and was repeated. An initial long sampler exceeded the CLI HTTP timeout;
the retained successful samples use twenty-second windows. No gameplay owner
or network exceptions occurred. Existing unsupported login requests remain
outside this feature. Both clients and the server were stopped before final
automated validation.

Automated coverage additionally checks derived-stat restoration, repeated
attempts against one holder, independent casters, category/polarity matching,
Dispel All cast validation, Devour Magic's partial-removal heal, packet bytes,
owner/observer delivery, periodic damage after cures, expiry, and Ignite.

## Final validation

- `mix test.all`: 3,047 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Evidence

- Target screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.9dLeFi/screenshots/toxin-three-stacks.png`,
  `partial-cure-confirmed.png`, and `full-cure-confirmed.png`.
- Observer screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.0H5bqp/screenshots/partial-cure-observer.png`.
- Owner samples: `/tmp/thistle-dispel-client-timeline.txt`,
  `/tmp/thistle-dispel-client-cleared.txt` (natural expiry),
  `/tmp/thistle-dispel-client-final-cures.txt`, and
  `/tmp/thistle-dispel-client-cleared-state.txt`.
- Server log: `/tmp/thistle-dispel-server.log`.
- Final validation logs: `/tmp/thistle-dispel-final-{tests,compile,credo}.log`.
