# World PvP flags

World PvP now has an owner-local state machine for voluntary flagging, territory
rules, the five-minute PvP cooldown, and the thirty-second contested flag.
The client opcode accepts the vanilla toggle packet and explicit enable/disable
forms. Player preferences and remaining timers survive reconnects within the
running server; runtime stores remain ETS-only.

Enemy-player targeting requires a flagged target, an active duel, or applicable
free-for-all rules. Friendly faction players remain friendly outside duels and
free-for-all areas, and party members remain friendly in those areas. Area
attacks do not select enemy players when doing so would newly flag the caster.
External assistance cannot interfere with active duels.

Melee, hostile spells, spell outcomes, periodic damage, and beneficial spells
resolve controlling players through typed effects. Each player owner applies
its own flag transition and publishes through Presence. Pets, charmed units,
and totems inherit their owner's unit flag. Charmed creatures restore their
original flag on release. Creature templates also project the VMangos static
PvP-enabling flag.

References include `refs/vmangos/src/game/Handlers/MiscHandler.cpp`,
`Objects/Player.cpp` PvP timer and area transitions, `Objects/Unit.cpp` combat
participant transitions, and `Spells/Spell.cpp` targeting and assistance.

## Client facts recorded

Two isolated build-5875 clients used the debug characters on the default RP-PvP
realm. Gameplay input went through the clients; Tidewave probes only observed
authoritative state or captured outgoing update packets.

- Leaving contested Programmer Isle for friendly Northshire started the
  paladin's cooldown. Logout and reconnect preserved its remaining time.
- The hunter's `/pvp` command set the preference bit and held the timer at
  300,000 ms. The client reported `Player PvP=1 Pet PvP=1`; owner state and pet
  metadata agreed.
- After the paladin's natural cooldown expired, its unit flag and Presence
  projection both cleared. The opposing shaman's client reported the paladin
  unflagged and rejected Lightning Bolt with "Invalid target". Paladin health
  remained 2,516.
- Elwynn territory forced the Horde shaman's flag while allowing the Alliance
  paladin's timer to count down.
- In a fresh session, the paladin again reached an unflagged state naturally.
  Judgement followed by client auto-attack reduced the shaman's health from
  2,415 to 2,235 in the first sampled attack sequence. Both players entered
  combat with full PvP timers. Only the aggressor received the contested bit.
- Continued attacks held the aggressor's timers at 300,000 and 30,000 ms.
  The shaman subsequently died; combat ended and the contested timer expired,
  while the paladin's PvP flag remained with 248,936 ms left.
- A further hunter reconnect preserved 115,448 ms of cooldown and summoned a
  new flagged pet. The old pet's metadata was removed. When the cooldown ran
  out naturally, both owner and pet flags cleared; the client reported
  `Expired Player PvP=nil Pet PvP=nil` and pet unit flags returned to 8.
- The unflagged paladin cast Mind Vision on the voluntarily flagged hunter.
  The client showed the channel and `Inspection PvP=nil Target PvP=1`.
  Authoritative state confirmed viewpoint 7, no combat, and no paladin flag.
- The paladin then cast Blessing of Might on that hunter. The hunter received
  aura 19740 and the paladin became flagged with 297,268 ms remaining in the
  first sample. Neither player entered combat or gained a contested flag.
  The paladin's client reported `Buff PvP=1 Combat=nil` and the hunter's client
  displayed the received blessing.

Use Escape to stop auto-attack in this vanilla client. `/stopattack` did not
stop the attack in this pass; the death above was an observed consequence,
not a successful test of that command.

Reference review found and fixed additional spell cases: Beast Lore and Mind
Vision do not count as friendly assistance, no-threat spells can propagate
flags without entering combat when their attributes require it, misses use
their own hostility rules, and assisting a flagged ally in PvE combat does not
pause the PvP countdown. Tests cover the actual inspection-spell DBC records.

The first session also exposed a client crash during relocation while guards
were attacking the shaman. Both clients reported a vector allocation failure.
The client stack was decoding an object-update movement block with a malformed
node count. Repeated relocation, combat, death, release, and corpse recovery
have not reproduced it yet; an independent diagnostic decoder consumed 3,240
subsequently captured update packets across three captures without a framing
error. The crash remains unresolved. The fresh player-combat, death, pet
reconnect, inspection, and assistance sequences did not reproduce it.

## Artifacts

- Initial clients: `/home/pikdum/.cache/thistle-wow-playtest.Zd0nXK/` and
  `/home/pikdum/.cache/thistle-wow-playtest.0xxYPd/`.
- Diagnostic clients: `/home/pikdum/.cache/thistle-wow-playtest.M7OWev/` and
  `/home/pikdum/.cache/thistle-wow-playtest.i6Bsw2/`.
- Fresh combat clients: `/home/pikdum/.cache/thistle-wow-playtest.eElTzu/` and
  `/home/pikdum/.cache/thistle-wow-playtest.qkpiCu/`.
- Final assistance clients: `/home/pikdum/.cache/thistle-wow-playtest.9Dxfhp/`
  and `/home/pikdum/.cache/thistle-wow-playtest.TodNcj/`. Their `screenshots/`
  directories contain `pvp-mind-vision-flagged.png`, `pvp-friendly-buff.png`,
  `pvp-pet-expired.png`, and `pvp-buff-received.png`.
- Server logs: `/tmp/thistle-pvp-playtest-server.log`,
  `/tmp/thistle-pvp-playtest-server-2.log`, and
  `/tmp/thistle-pvp-playtest-server-3.log`.
- Flag probes: `/tmp/thistle-pvp-initial.txt`,
  `/tmp/thistle-pvp-manual-reconnect.txt`, and
  `/tmp/thistle-pvp-protected.txt`.
- Final probes: `/tmp/thistle-pvp-pet-reconnect.txt`,
  `/tmp/thistle-pvp-pet-expired.txt`,
  `/tmp/thistle-pvp-mind-vision-flagged.txt`, and
  `/tmp/thistle-pvp-friendly-buff.txt`.
- Packet captures: `/tmp/thistle-pvp-update-capture.bin` (2,199 packets),
  `/tmp/thistle-pvp-update-capture-2.bin` (348 packets), and
  `/tmp/thistle-pvp-update-capture-3.bin` (693 packets).

All playtest clients, their X displays, and the server were stopped after
acceptance. The final server log contained no error-level gameplay entries.

## Automated validation after spell corrections

- `mix test.all`: 3,767 passed, including DBC, VMangos, and map integration tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: passed with zero issues.
- `mix format --check-formatted`: passed.

Coverage includes codec dispatch, timer pausing and expiry, reconnects, death,
late contact ordering, realm and territory rules, pet/totem ownership, charm
release, duel assistance, free-for-all parties, and area-attack protection.
The architecture dependency allowlist was not expanded.
