# Engineering transporters and Evil Twin

Implementation: `adc3160e`. Native cooldown reset: `0e2c02a7` and
`1a21e776`. Ritual recipient correction: `820bf7ca`.
Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Spells/SpellEffects.cpp`, `src/scripts/spells/spell_item.cpp`,
and `src/scripts/spells/spell_warlock.cpp`.

## Behavior

The Ultrasafe Transporter: Gadgetzan previously reached an unimplemented
dummy effect. It now chooses the ordinary destination with probability
1/2, the malfunction arrival spell with probability 1/4, or the high fall
destination with probability 1/4. A malfunction arrival then chooses a
ten-second transform and stun with probability 1/6, Evil Twin with
probability 4/6, or no additional effect with probability 1/6.

The Dimensional Ripper: Everlook retains its teleport and adds the scripted
arrival roll: 7/12 ordinary, 3/12 Evil Twin, and 2/12 fire. These weights
follow the actual VMangos branch ranges; its adjacent percentage comments
disagree with those ranges. Fire uses the existing percentage-damage aura:
10% of maximum health every two seconds for 24 seconds. Evil Twin lasts
two hours and silently suppresses incoming summon offers.

Pure engineering logic returns typed random choices, ordinary triggered
spells, and teleport requests. Existing destination caches, item cooldowns,
aura transitions, and owner delivery handle their execution. No new
architecture exceptions or durable stores were added.

Native acceptance also found Ritual of Summoning sending its offer to the
warlock. The client sends a caster-targeted packet for this spell, while
the recipient is the character's selected player. Object creation now
prefers that selection, matching the existing validation and VMangos.
The `.debug cooldowns` command clears spell and item timers and sends
cooldown-clear packets through an explicit owner context; it allows repeat
uses of equipped devices without selecting or changing their random roll.

## Automated validation

Tests enumerate every random-choice branch and check destination requests,
trigger ownership, item provenance, invalid delivery, actual DBC child
chains, transformation and stun expiry, fire ticks and death cleanup,
Evil Twin expiry, and summon request suppression followed by a normal
request after expiry. Separate VMangos tests verify destination rows and
the Everlook script label. The ritual regression exercises a caster-targeted
cast with a different selected recipient through object creation.

The final `mix test.all` run passed all 7,442 tests in 80.0 seconds with
the clients and server stopped. Compilation with warnings treated as
errors passed. Strict Credo checked 2,606 source files and found no issues.
Logs are `/tmp/thistle-transporter-final-tests.log`,
`/tmp/thistle-transporter-final-compile.log`, and
`/tmp/thistle-transporter-final-credo.log`.

## Native acceptance

Three isolated build-5875 clients ran against a fresh server containing
the final source commits: Debugpaladin (2), Debugmage (5), and Debugwarlock
(6). Native commands prepared levels, engineering, items, positions, and
the summoning spell and reagents. The engineer equipped items 18986 and
18984 in trinket slots 13 and 14 and used them through `UseInventoryItem`.
Tidewave only read small owner snapshots and sampled transitions.

- Before Evil Twin, a real Ritual of Summoning with both helpers produced
  an offer on the paladin's client. The owner retained summoner 6 and the
  portal destination. Accepting cleared the pending request and moved the
  paladin to that destination.
- Everlook uses reached map 1 at `{6755.33, -4658.09, 724.8, 3.4049}` and
  recorded item 18984's 14,400,000 ms cooldown. The first two uses applied
  fire; the client displayed the malfunction and its timed debuff, which
  expired normally. Those initial fire rolls occurred with god mode on.
  The third use had no malfunction; the fourth applied Evil Twin, visible
  as a two-hour debuff and retained as aura 23445 by the owner.
- Returning the paladin to the helpers preserved Evil Twin. Repeating the
  same ritual consumed both contributions, removed the portal, and ended
  the warlock's channel. Neither client showed a summon offer; the
  paladin's pending request remained nil throughout the sampled interval.
  The warlock also displayed the paladin's debuff in the target frame.
- The first Gadgetzan use selected the fall branch. Sampling captured the
  exact initial destination `{-7341.38, -3908.11, 150.7, 0.51}` on map 1,
  subsequent descending client movement, and landing at height 13.586.
  God mode was on for this fall; its damage is not an acceptance claim.
- A second Gadgetzan use reached `{-7109.1, -3825.21, 10.151, 2.8331}`
  and stored item 18986's four-hour cooldown. It refreshed Evil Twin's
  deadline, exercising the malfunction arrival's nested trigger chain.
- The ninth Everlook use applied fire with god mode already disabled.
  Owner sampling recorded twelve 337-point ticks at two-second intervals
  against 3,371 maximum health, with ordinary regeneration between ticks.
  `everlook-9` shows the 337-point hit and timed debuff in the client.
  A native health command restored health during the burn to keep the
  character alive; the last tick and aura removal occurred at 24 seconds.
  Evil Twin remained after fire expired.
- Logging out and reconnecting preserved Evil Twin's exact expiry and the
  Everlook item's exact cooldown start and ready timestamps. The client
  still showed the two-hour debuff and rejected another item use with
  "Item is not ready yet."

The rare Gadgetzan transformation was covered through deterministic DBC
tests, including stun and appearance restoration; it was not rolled in
these native sessions.

## Evidence

- Paladin: `/home/pikdum/.cache/thistle-wow-playtest.SvUDij`.
- Mage: `/home/pikdum/.cache/thistle-wow-playtest.dwdNc9`.
- Warlock: `/home/pikdum/.cache/thistle-wow-playtest.3ipVtU`.
- Screenshots include `ritual-fixed-offer`, `everlook-1` through
  `everlook-4`, `evil-twin-no-offer`, `evil-twin-ritual-completed`, and
  `gadgetzan-landed`; `everlook-9` records damaging fire.
- Owner snapshots and samples: `/tmp/thistle-transporter-native-*.log`.
- Final server log: `/tmp/thistle-transporter-accepted-server.log`.
- `/tmp/thistle-transporter-accepted-drm.log` records `amdgpu`, allocated
  VRAM, and nonzero graphics counters on WoW processes 2819903, 2820763,
  and 2821648 themselves.

Earlier runs retained the ordinary Gadgetzan destination and four-hour
cooldown in `/tmp/thistle-transporter-native-gadgetzan-use.log`, plus an
Everlook arrival with Evil Twin in `native-arrived.log`. The initial
`native-everlook-use.log` sampler timed out and supplies no evidence.
The final run's two rejected logins were attempts to enter the already
connected mage before selecting the other characters. Existing account-data
and GM-ticket warnings also appeared.

All three helper-owned client services and server process 2819391 were
stopped. Their services were inactive, their WoW processes were gone, and
ports 3724, 8085, and 4000 were closed. Earlier helper sessions were also
stopped. Logs and screenshots were retained. No changes were pushed.
