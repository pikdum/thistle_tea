# Spell resurrection

Resurrection spells resolve a released player's owned corpse for range,
visibility, line of sight, and world identity. The spell is delivered to the
player even when the ghost is at a distant graveyard. Explicit corpse targets
and player targets use the same projection. Ownership and target conditions
are checked again at cast completion, so a removed body cannot receive a
late offer.

A player retains one typed resurrection offer, including the caster's world,
position, facing, health, and mana. Another cast cannot overwrite it. Decline
clears it; acceptance requires the offering caster and a valid response.
Accepted offers travel while dead and revive only after the matching
teleport counter or pending worldport is acknowledged. Competing travel,
logout, or any other resurrection clears the pending recovery. An accepted
offer also cancels a queued graveyard transfer.

Player offers use normal instance admission. If the original copy is no longer
the player's destination, recovery uses the admitted copy's entrance rather
than coordinates deep inside the previous copy. An admission failure retains
the normal error and revives at the current location, matching VMangos's
failed-teleport behavior. Non-player offers revive in place.

Successful spell recovery restores the offered health and mana within current
maxima, resets rage, fills energy, clears the release countdown and offer,
and removes the corpse and its world projections. Rebirth carries the DBC
attribute that bypasses the client's corpse countdown; ordinary resurrection
requests retain that countdown.

The packet handler only decodes and dispatches. `Logic.Resurrection` owns pure
offer transitions, `World.ResurrectionTarget` projects the body,
`Player.Resurrection` coordinates acceptance, and existing movement packet
sequencing binds recovery to arrival. No database calls were added to casts.

References: VMangos `EffectResurrect`, `EffectResurrectNew`,
`HandleResurrectResponseOpcode`, `ResurrectUsingRequestData`,
`SendResurrectRequest`, and `ResurrectRequest::AppendBodyTo`. The VMangos packet
implementation documents the sickness and delay bytes; the local
`wow_messages` definition omits the second control byte.

Automated regressions cover first-offer retention, decline, foreign and
invalid replies, released body targeting, missing and mismatched bodies,
range and copy isolation, cast-completion revalidation, near and cross-map
arrival sequencing, stale acknowledgement rejection, logout cleanup, changed
copy entrances, resource restoration, packet flags, and real Rebirth DBC rows.

## Native acceptance

Two isolated build-5875 clients used Debugpriest (GUID 4) and Debugbuyer
(GUID 10). They formed a party and entered Ragefire Chasm through area trigger
2230, receiving map 389, copy 1, owned by party 1. The buyer died inside that
copy. An initial Resurrection offer on the unreleased body displayed normally;
declining cleared the offer and allowed another cast.

After release, the buyer was a ghost at Razor Hill on map 1 while the body
remained at `{3, -13, -17.207096}` in Ragefire copy 1. The priest cast
Resurrection rank 1 by clicking that body. A read-only cast probe confirmed
spell 2006 with explicit target `{:corpse, 17366161638117343242, 10}`.
The buyer received the offer at the graveyard. A repeat death displayed a
43-second countdown with Accept disabled.

A fresh offer was accepted through the native dialog. A 20 ms owner sampler
captured the complete transfer, before regeneration could change the result:

| Stage | World | Ready | Ghost | Health | Offer | Corpse exists |
| --- | --- | --- | --- | --- | --- | --- |
| Offered | map 1 | yes | yes | 1 | offered | yes |
| Travel queued | map 389, copy 1 | no | yes | 1 | transferring, unarmed | yes |
| World packet sent | map 389, copy 1 | no | yes | 1 | awaiting worldport | yes |
| Arrival acknowledged | map 389, copy 1 | yes | no | 70 | cleared | no |

Recovery used the priest's cast position
`{0.797643, -8.234290, -15.528800}`. Mana and energy remained zero, matching
this warrior's zero maxima. The buyer's normal view and action bar returned;
the priest saw the living buyer. The release timestamp, pending offer, corpse
process, corpse position, and corpse metadata were all cleared. The observer
tracked the player and no longer tracked the corpse.

Both clients used their own AMD GPU context. WoW's DRM graphics counters
advanced from 2,887,200,834 to 15,372,589,363 ns for the priest and from
2,072,476,898 to 16,681,773,432 ns for the buyer. Both helper-owned systemd
sessions and the retained server were stopped after acceptance.

No server errors occurred. Existing unrelated login/UI warnings remain for
account data, raid information, GM tickets, and meeting-stone information.
Rebirth's countdown bypass, changed-copy fallback, denied admission, stale
acknowledgements, and competing travel are covered by automated checks;
the native run exercised the priest's ordinary resurrection path.

Local evidence is retained in:

- `/home/pikdum/.cache/thistle-wow-playtest.mVhu2u/screenshots/`:
  `dead-body.png`, `released-body.png`, `final-observer.png`.
- `/home/pikdum/.cache/thistle-wow-playtest.U6W0RK/screenshots/`:
  `dead-offer.png`, `ghost-graveyard.png`, `final-ghost-offer.png`,
  `resurrection-countdown.png`, `repeat-offer.png`, `repeat-revived.png`.
- `/tmp/thistle-resurrection-final-cast.txt`,
  `/tmp/thistle-resurrection-final-arrival-compact.txt`,
  `/tmp/thistle-resurrection-final-cleanup-2.txt`, and
  `/tmp/thistle-resurrection-server-final.log`.

Final checks: `mix test.all` passed 5,020 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.
