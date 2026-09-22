# Environmental fire damage

Implemented in `07ca81be`, with world-loaded trap initialization fixed in
`c822bf4a`. Automated and native acceptance ran on 2026-09-21.

## Behavior and reference

DBC effect 7 now applies environmental fire damage through a shared pure
`EnvironmentalDamage` function. All eight current DBC spells load with this
semantic, including Flames, Intense Heat, Building Fire, and Big Bonfire Damage.
Their no-threat attribute prevents the trap from initiating combat.

Fire uses the victim's fire resistance, level, and resistance-penetration
modifiers, then consumes matching school absorbs and mana shields. It bypasses
ordinary spell-power, critical-strike, received-damage, and redirection bonuses.
The environmental log reports final health damage, absorption, and resistance,
including fully absorbed hits. Feedback reaches the victim and nearby observers
in the same world. Damage grants no taken-damage rage or trap combat credit.

The same function handles falling and drowning while preserving their shield
bypass. Its lava, slime, and exhaustion variants provide the matching school and
packet semantics; terrain detection and timers for those hazards are not added
by this change. Environmental damage breaks stealth and sitting, preserves
Feign Death, and enters the existing health/death and durability transitions.
Environmental self-damage no longer shortens damage-delayed channels; channels
whose flags require cancellation still cancel.

Reference: `refs/vmangos` at `8f4e60845`, specifically
`Spell::EffectEnvironmentalDMG`, `Player::EnvironmentalDamage`,
`SpellCaster::GetSpellResistChance`, and the damage reactions in
`Unit::DealDamage`. The reference's nonplayer effect-7 behavior consumes shields
and emits spell feedback without subtracting health; this implementation and its
regression retain that distinction.

World-loaded and summoned traps now initialize the same typed trap state.
The first native run exposed the missing world-loaded initialization: the inn's
campfire objects existed and resolved the player as a spell target but had no
trap state. The proximity regression now builds a seeded world object and
checks actual discovery and delivery.

## Automated acceptance

`mix test.all` passed **4,634 tests** after the world-trap fix.
`mix compile --warnings-as-errors` passed, and `mix credo --strict` reported zero
issues across 1,812 source files. The architecture ratchet passed without an
allowlist change.

Coverage includes resistance ordering, successive shield depletion, mana costs,
school masks, physical hazard shield bypass, immunity, dead and ghost players,
god mode, stealth/posture, lethal durability effects, cast/channel interruption,
caster damage bonuses, nonplayer behavior, packet encoding, recipient isolation,
all eight DBC spells, and world-loaded campfire proximity activation.

## Native client acceptance

Debugmage (GUID 5, level 60) used an isolated build-5875 client and a fresh server.
God mode remained off. The character had 2,350 maximum health and 22 fire
resistance. Existing development chat commands supplied the level, position,
and a one-health lethal setup; Fire Ward, movement, release, and corpse recovery
used native client actions. Tidewave probes only read state.

The location was the Lion's Pride Inn fireplace at
`{-9455.6, 23.0, 56.9157}` on map 0. Its four entry-2061 campfires have database
GUIDs 26245, 26248, 26254, and 26258.

- Repeated fire pulses reduced authoritative health while `in_combat` remained
  false. The client displayed fire damage and partial resistance, including
  six damage with six resisted. Regeneration continued between pulses.
- Native rank-one Fire Ward (543) displayed fully absorbed fire hits. A sampler
  started before reentry recorded shield capacity
  `165 -> 122 -> 74 -> 55 -> 31 -> removed`. Health stayed at 2,350 until depletion,
  then fell to 2,332. Removal preceded the original expiry by about six seconds.
- Walking backward out of the fireplace stopped the pulses. Sampled health rose
  from 2,003 to 2,143 without another damage step. All nine durable equipped
  items retained full durability after nonlethal exposure.
- Setting current health to one allowed the next real fire pulse to kill the
  character. The client showed the death dialog and 10% durability-loss message.
  The staff changed from 100/100 to 90/100, the vest from 70/70 to 63/70, and the
  helm from 50/50 to 45/50. Later corpse snapshots were identical.
- Native release created a ghost. Returning the ghost to the fireplace left
  health at one and durability unchanged across repeated snapshots. Walking
  outside and accepting the native corpse-recovery dialog restored the player.
  Reentering the fire produced damage and resistance feedback again.

The initial diagnostic session was `thistle-wow-playtest.F4iOKu`; final acceptance
used `thistle-wow-playtest.a2cdEc`. Screenshots remain under the final session's
`screenshots/` directory, including `fire-damage-visible.png`, `fire-ward.png`,
`fire-death.png`, `ghost-in-fire.png`, and `fire-after-reclaim.png`. Read-only
samples and server logs are retained as `/tmp/thistle-environmental-*`.

The final server log contained no errors or fire/trap failures. Existing login
warnings remained for account-data updates, raid-info requests, GM tickets, and
meeting-stone information. Both helper-owned clients, X servers, and server
processes were stopped. Observer delivery and cross-world isolation were tested
automatically; a second native observer client was not used.
