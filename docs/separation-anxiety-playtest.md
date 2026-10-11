# Separation Anxiety acceptance

Tested on 2026-10-10 with the native 1.12.1 build-5875 client against a
fresh local server. References are the Separation Anxiety cases in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`, `WorldObject::IsWithinDist`,
and the aggro handlers in `boss_garr.cpp` and `boss_majordomo_executus.cpp`.

## Implemented behavior

Garr binds nearby living Firesworn with spell 23487; Majordomo binds Flamewaker
Elites and Healers with 21094. The boss remains the aura caster. Both hidden
bindings tick every five seconds despite their zero DBC amplitude.

Each tick reads the boss's current availability, position, and bounding radius.
When the living boss and add share a world and their three-dimensional center
distance is at least the spell radius plus both bounding radii, the add casts
the corresponding buff on itself. The radius is 100 yards in current data.
Garr's buff 23492 increases physical damage by 300%, giving a 4x multiplier;
Majordomo's 21095 increases it by 200%, giving a 3x multiplier. Both last five
seconds. Returning inside the radius stops refreshes, allowing normal expiry.
Missing, dead, or unavailable bosses also stop refreshes.

The shared creature-script helper preserves the boss as caster when casting
through a recipient's script. The AI's missing-aura flag now checks other
targets' observed aura stacks and continues to enforce additional flags,
including melee restrictions, when the aura is absent.

The initial roster search uses 150 yards. Generated VMangos spell overrides
make these bindings source-area casts; their separate radius and line-of-sight
filters still apply, matching the reference spell targeting.

## Native acceptance

Debugshaman (GUID 8, level 60, god mode) entered Blackrock Depths through its
real entrance, then walked through the Molten Core portal in a raid. The world
was map 409, instance 2. Debugwarrior (GUID 1, god mode) used a headless
connection and the normal instance destination route to provide a second
opponent. Existing script commands stopped combat movement and teleported the
boss within that copy to control the distance, then returned it.

Garr's seeded DB GUID was 56609, runtime GUID 17379391164318224925. All eight
Firesworn received 23487 with Garr as caster. The accepted 35-second trace
sampled one visible Firesworn 174 times and recorded 44 projected packets.

- The initial physical multiplier was 1x at a surface distance of 2.825 yards.
- At 2.436 seconds, spell 23492 was active at 207.690 yards and the multiplier
  was 4x. The native player's connection received NPC self-cast packets at
  2.437 seconds and an aura update containing 23487 and 23492 at 2.439 seconds.
- After Garr returned, the buff was absent at 22.509 seconds and the multiplier
  was 1x. The final aura update contained only 23487. The add stayed visible
  in instance 2 throughout the trace.
- Leaving combat reset all nine units: full health, no combat, no binding,
  and no empowerment. After a complete home reset, a new native pull bound
  all eight Firesworn again. Two recorded binding casts hit all eight without
  misses.

Majordomo's fixture used public instance commands to mark the seven rune
bosses complete and the normal rune-use API to summon him. This acceptance
does not cover natural boss kills or the full rune progression. All four
Elites and four Healers received 21094 with Majordomo as caster.

The accepted 25-second trace sampled one visible Elite 125 times and recorded
34 projected packets. A script returned Majordomo after twelve seconds while
the two-player fight stayed active.

- The multiplier started at 1x. At 3.448 seconds, spell 21095 was active at a
  surface distance of 462.473 yards and the multiplier was 3x.
- NPC self-cast packets arrived at 3.450 seconds, followed by an aura update
  containing 21094 and 21095 at 3.452 seconds.
- At 13.389 seconds, the boss was back within 15.321 yards, empowerment was
  absent, and the multiplier was 1x. The final update retained binding 21094
  and the existing Reflection buff 20619, with no 21095.
- A wipe removed the eight old guard owners and spawned eight replacements.
  The boss returned to phase zero; all replacements were out of combat and
  unbound. The headless player disconnected normally.

An early Garr repull sampled five bindings before the complete-reset repeat;
it is retained separately and is not the accepted roster check. An earlier
solo Majordomo attempt reset after his victim teleport and is not the accepted
return check. Enemy positive buffs were not exposed by the client's
`UnitBuff("target")`; acceptance uses actual connection spell/aura packets,
visible entity state, and the damage calculation rather than a buff icon.
The fresh gameplay server log contained no warnings or errors.

## Validation and evidence

Focused script, aura, world reception, AI flags, and architecture checks:
97 passed. After extracting the caster-context refresh helpers, the affected
aura and reception checks passed all 24 tests. Regression coverage includes
the exact distance boundary, vertical distance, both bounding radii, buff
expiry, dead/missing/cross-instance sources, and recipient casting ownership.

Final validation: `mix test.all` passed all 8,833 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.

Aura implementation: `0e705b17`; AI flag fix: `52bf1433`;
encounter bindings: `ef235f94`.

GPU session: `/home/pikdum/.cache/thistle-wow-playtest.tjTa68`, unit
`thistle-wow-playtest.tjTa68.service`, invocation
`11574b5f9efe48209b6d3659bdbece3b`. WoW PID 156416 belonged to that service
cgroup and used amdgpu client 439. Its graphics counter increased from
811,467,053 to 51,903,246,806 ns. The helper-owned service, headless connection,
and retained server PTY were stopped after acceptance.

The session retains the server log, GPU ownership records, validation logs,
screenshots of binding/separation/return, and these accepted traces:

- `thistle-garr-separation-projection.json`
- `thistle-garr-separation-wipe.json`
- `thistle-garr-separation-repull-cause.json`
- `thistle-majordomo-separation-binding.json`
- `thistle-majordomo-separation-accepted.json`
- `thistle-majordomo-separation-wipe.json`
