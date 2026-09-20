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
The subsequent investigation identified and fixed object-update removal
ordering, as detailed below. The fresh player-combat, death, pet reconnect,
inspection, and assistance sequences did not reproduce the crash.

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

## Object-update crash diagnosis and fix

The paladin's minidump retained the decompressed packet on its stack at
`0x0100f6b8`: 1,666 bytes containing eight update blocks. The fifth block, at
payload offset 1,000, removed transport `0x1fc000000002b0b6` between creature
creates. Build 5875 consumes an out-of-range block only at the beginning of an
update packet. Its later dispatch loop skips that block's type byte without
consuming the count and GUIDs.

Following the actual decoder from that point reproduces all three crash
values exactly: movement flags `0xb6c70000`, spline node count `0xce000000`, and
allocation size `0xa8000000`. The apparent movement corruption came from
reading the removal count as another block type. VMangos also emits one
leading removal block in `Server/Packets/ObjectUpdate.cpp`.

`UpdateObject.normalize/1` now combines removals into one leading block and
drops updates preceding a later removal of the same GUID. A subsequent create
is retained. The batcher returns that same normalized order for visibility
tracking, so the owner and client agree about removed and recreated objects.
Regression tests cover direct encoding, interleaved mailbox removals,
transport headers, stale creates, and remove/recreate tracking.

Two fresh clients then exercised Northshire relocation, guard combat and
death, nearby creature refreshes, and departures of transport 176310 using
the existing debug commands. Both clients stayed running without another
crash. All 229 captured updates passed a decoder that now also requires
removals to be first. The precise mailbox interleaving did not recur in this
live pass; automated tests exercise it deterministically. The earlier 3,240
captured packets also pass the stricter decoder, while the recovered crash
packet fails it at the exact offending block.

Follow-up artifacts:

- Clients: `/home/pikdum/.cache/thistle-wow-playtest.tn0guN/` and
  `/home/pikdum/.cache/thistle-wow-playtest.o1tQdI/`; both contain
  `screenshots/update-order-final.png`.
- Server log: `/tmp/thistle-update-order-playtest.log`, with no error-level
  entries. Both clients and the server were stopped afterward.
- Authority probe: `/tmp/thistle-update-order-final-state.txt`.
- Packet capture: `/tmp/thistle-update-order-capture.bin`.
- Recovered crash packet: `/tmp/thistle-pvp-crash-update.bin`, prefixed by its
  32-bit little-endian length for the diagnostic decoder.

## Automated validation after spell and packet corrections

- `mix test.all`: 3,770 passed, including DBC, VMangos, and map integration tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: passed with zero issues.
- `mix format --check-formatted`: passed.

Coverage includes codec dispatch, timer pausing and expiry, reconnects, death,
late contact ordering, realm and territory rules, pet/totem ownership, charm
release, duel assistance, free-for-all parties, and area-attack protection.
The architecture dependency allowlist was not expanded.
