# Class trainer talent resets

Implementation: `211e9796` and `e0b1541f`. Acceptance fixes: `5250a252`
(immediate return mail) and `afe8ecb6` (owner spell modifiers on pets).

The build-5875 client exercised these changes against the local server with
Debughunter and Debugshaman, both level 50. The isolated client session was
`/home/pikdum/.cache/thistle-wow-playtest.IkAhGb`; server output was retained in
`/tmp/thistle-talent-reset-server.log`. Runtime probes were read-only. Talent
spending, trainer interactions, equipment changes, and resets used client actions.

## Hunter

- Learned five ranks of Endurance Training through the talent UI API. The client
  displayed five spent points and 36 remaining points.
- Einris Brightspear exposed the existing two-stage gossip conversation and a
  one-gold confirmation. Cancelling retained the talent, all money, and the pet.
- Accepting refunded all 41 points and charged exactly 10,000 copper. Talent
  spell 19587 and its owner aura disappeared. The pet frame and action bar
  disappeared; its process, world position, and metadata entry were removed.
- Call Pet restored the level-49 wolf with its three trained spells, experience,
  loyalty, and training-point balance retained.
- Learning one rank and resetting again charged 50,000 copper. The next offer
  displayed ten gold. Accepting with no allocated points displayed
  "You have not spent any talent points" and left money/history unchanged.
- Reconnecting retained 99,940,000 copper, 41 unspent points, no talent spells,
  reset multiplier two, and the next price of 100,000 copper.

Screenshots: `hunter-talents-learned`, `hunter-price-one-gold`,
`hunter-reset-one`, `hunter-price-five-gold`, `hunter-price-ten-gold`, and
`hunter-empty-reset`. Probe files use `/tmp/thistle-talent-reset-hunter-*.txt`.

## Shaman

- Learned five ranks each of Ancestral Knowledge and Shield Specialization, then
  Two-Handed Axes and Maces. Equipped Large Axe (entry 2491) using the bag item.
- Visited Beram Skychaser at Spirit Rise in Thunder Bluff. The trainer offered
  the same confirmation flow and charged exactly one gold.
- Reset removed all 11 allocated points and spells 16269, 197, and 199. Both
  two-handed weapon skills disappeared from visible skills and were retained
  in the forgotten-skill map. The equipped axe moved into the backpack, keeping
  its original item GUID. The client displayed the axe in its new bag slot and
  the authoritative main-hand field was cleared.
- Relearning the talent restored both skill values and allowed the original axe
  to be equipped again. Filling all five remaining bag slots and resetting again
  detached the axe into a return mail without destroying or replacing its GUID.

Screenshots: `shaman-trainer-menu`, `shaman-price-one-gold`, and
`shaman-reset-weapon-bag`. Probe files use `/tmp/thistle-talent-reset-shaman-*.txt`.

## Automated coverage

After the acceptance fixes, `mix test.all` passed 3,692 tests, compilation with
warnings as errors passed, and strict Credo reported zero issues. Coverage
includes pricing escalation, cap and monthly decay; trainer and offer validation;
insufficient funds and replay rejection; class-specific removal and dependent
spells; triggered aura cleanup; pet dismissal and summon reagent refund; atomic
inventory relocation and overflow mail; and restoration of previously trained
weapon skill values.

## Follow-up found during acceptance

Endurance Training did not update the active pet's maximum health. The family
passive was present, but its amount did not inherit the owner's spell modifiers.
Pets now receive a snapshot through typed effects when owner modifiers change,
refresh affected permanent self-cast passives, and inherit modifiers at creation.
Regression coverage checks real DBC spells, rank replacement, removal, restoration,
stale-owner rejection, unrelated spells, and corpse safety.

The first full-bag return also inherited the usual one-hour attachment delivery
delay. Automatic weapon returns now supply an immediate delivery time explicitly.

## Acceptance after fixes

A fresh server and isolated client session
`/home/pikdum/.cache/thistle-wow-playtest.tV8efL` repeated the affected paths.
Server output is `/tmp/thistle-talent-reset-fixed-server.log`; probes use
`/tmp/thistle-talent-reset-fixed-*.txt`.

- The Shaman filled every carried slot, reset at Beram, and immediately found
  the return mail at the Thunder Bluff mailbox. After freeing one slot, the
  client retrieved the axe. Its GUID remained 4611686018427388092, it occupied
  backpack position `{255, 34}`, and the mail attachment was removed.
- Learning Endurance Training rank five with an active pet changed its maximum
  health from 2,138 to 2,458. Client `UnitHealthMax("pet")` and the entity owner
  agreed, with the original family passive spell 19581 still present once.
- Dismiss Pet followed by Call Pet retained 2,458 maximum health. The free debug
  talent reset then changed the same active pet back to 2,138, proving removal
  refreshes an existing pet without relying on despawn.
- Relearning the five ranks and paying Einris one gold refunded all 41 points
  and dismissed the pet. Calling it again produced 2,138 maximum health with
  its trained spells and progression retained. The earlier pet GUIDs had no
  process, world position, or metadata entry.

Screenshots: `fixed-shaman-mail-list`, `fixed-shaman-mail-retrieved`, and
`fixed-hunter-five-ranks`, `fixed-hunter-live-removal`,
`fixed-hunter-reset-offer`, and `fixed-hunter-after-paid-reset`.

Both server logs were free of error-level entries, crashes, and unsupported
gameplay messages. Both helper-owned clients and retained server processes were
stopped after acceptance. No source changes followed the final successful gates.
