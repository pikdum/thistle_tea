# Shared creature combat leashes

This extends the [creature-group combat](creature-groups-playtest.md) and [formation](creature-formations-playtest.md) systems. The reference is `refs/vmangos` revision `8f4e60845`, principally `Creature::IsOutOfThreatArea`, `Creature::CanRespondToCallForHelpAgainst`, `Unit::SetInCombatWith`, and the assistance paths in `CreatureGroups.cpp` and `Creature.cpp`.

## Implemented behavior

Each creature records its interpolated position when combat begins. Its ordinary threat area is the larger of 50 yards and 150% of its detection distance against the victim. Either the creature or its victim remaining inside that area prevents a soft leash reset. Outside it, combat expires more than 12 seconds after the latest qualifying hostile contact. Explicit template leash distances remain independent hard limits. Dungeons and the no-leash template flag bypass the soft limit.

Accepted group assistance and initial same-faction assistance share an extension clock while retaining separate combat origins. Later hostile contact with any linked member refreshes the clock for all members. Periodic friendly assistance pulses recruit without linking their clocks. Ordinary damage-over-time ticks do not extend the clock; channeled damage does. Rooted, stunned, confused, or fleeing creatures maintain their clocks every three seconds.

The pure combat lifecycle emits typed clock events. A supervised world boundary owns shared clocks and publishes their times through a read-only ETS projection consumed by the behavior-tree context. References include world copy, creature incarnation, and engagement generation. Departing or dying members release their membership without invalidating surviving members' clocks. Owner exit and world shutdown also clean up membership; stale events cannot alter a replacement fight.

Two lifecycle fixes accompany this work. Scripted persistent despawn now clears combat, victim, threat, and the shared clock before hiding the corpse. Combat entry is rejected while return-home movement is active, so queued assistance cannot interrupt an evade.

## Native client acceptance

The character is level-60 `Debugwarlock`, GUID 6, with `.tgm` enabled, in an isolated build-5875 client. The test targets Fozruk, database spawn 14514, and followers Sleeby 14515, Znort 14516, and Feeboz 14517. Attacks target only Fozruk, using rank-one Shadow Bolt and incidental melee in the final pull. Tidewave probes only read state. Client teleports establish the starting position; the accepted pulls use ordinary keyboard movement.

The first session, `/home/pikdum/.cache/thistle-wow-playtest.TAnHwu`, established clock sharing while the group was beyond its combat origins. A 27.65-second sample retained all four in combat at distances of 116.0, 105.5, 100.0, and 66.4 yards respectively. The followers' original hostile-contact ages increased from about 70.55 seconds to 98.20 seconds while the shared clock followed hits on Fozruk. Their health remained unchanged. `fozruk-held-outside-origin.png` shows the group attacking the player and the Shadow Bolt cast bar.

That run also exposed an evade bug: nearby assisting creatures recruited the group again during its return home. The group had healed and advanced to another engagement generation rather than staying reset. The follow-up fix places the rejection in the shared engagement transition, covering assistance and other combat-entry callers. A regression verifies both rejection during return and successful entry after arrival.

The fresh-server replay uses `/home/pikdum/.cache/thistle-wow-playtest.Yk2anK`. Its first pull placed the four creatures 118.61, 112.94, 109.12, and 72.23 yards from their origins. Only Fozruk lost health; all four had the same 1,749 ms shared-clock age, while the followers' original contact ages exceeded 41 seconds. After the casts stopped, all four returned to their patrol at full health. Each retained engagement generation 1, had an inactive leash, no shared-clock entry, empty threat, target zero, and completed return-home movement. The player also left combat.

The first replay sampler exceeded its 30-second evaluation limit under software-rendered client load. Its later cleanup read is accepted evidence of the final state, not precise reset timing. The timing replay uses a 60-second probe limit.

During the final pull, camera input enabled melee auto-attack, which continued refreshing the clock after the casts stopped. Ordinary backward movement placed all four outside their origins again. A 25.55-second sample showed all four remaining engaged at distances of about 91.8, 91.7, 95.6, and 56.9 yards, while the followers' original contact ages exceeded 159 seconds. Their health remained unchanged and their shared clock followed Fozruk's incoming attacks.

Fozruk died from the incidental melee before attacking stopped. The subsequent sampler first observed him at 57 health, then dead. The followers kept their shared clock after his death and subsequently evaded; the first sample with all four out of combat was 13,482 ms after the last observed shared extension. This is acceptance of surviving-member expiry after leader death, not a second all-living reset measurement. The final read showed all four owner processes alive, all combat flags clear, targets zero, empty threat, inactive leashes, no shared-clock entries, and completed return-home movement. The three survivors were at full health, Fozruk remained dead, and the player was out of combat.

Artifacts:

- Initial server log: `/tmp/thistle-leashes-server.log`.
- Initial sustained shared-clock sample: `/tmp/thistle-leashes-shared-far-sample.json`.
- Re-entry bug state: `/tmp/thistle-leashes-after-reset.json`.
- Fixed server log: `/tmp/thistle-leashes-fixed-server.log`.
- Fixed pull state: `/tmp/thistle-leashes-fixed-midpull.json`.
- First fixed cleanup: `/tmp/thistle-leashes-fixed-cleanup-first.json`.
- Final sustained pull: `/tmp/thistle-leashes-fixed-reset-final-sample.json`.
- Leader death and survivor expiry: `/tmp/thistle-leashes-fixed-stopped-sample.json`.
- Final cleanup: `/tmp/thistle-leashes-fixed-cleanup-final.json`.
- Screenshots: each client session's `screenshots/` directory.

The fixed server log contained no errors or owner crashes. Login emitted the existing unimplemented account-data, raid-info, GM-ticket, and meeting-stone opcode warnings. Both helper-owned clients, their X servers, and both BEAM servers were stopped afterward.

## Automated verification and limits

`mix test.all` passed **4,782 tests**. `mix compile --warnings-as-errors` passed. `mix credo --strict` reported zero issues across **1,865 files**. The architecture dependency allowlist was unchanged.

Coverage includes combat origins, strict timeout boundaries, victim position, hard and soft limits, crowd-control maintenance, periodic and channeled damage, shared clock propagation, delayed assistance, stale incarnations and engagements, owner exit, world cleanup, group death, scripted despawn, and return-home re-entry.

Creature-owned clock inheritance and lethal-hit extension ordering are covered by the subsequent [owner leash acceptance](creature-owner-leashes-playtest.md). `creature_groups_entry_limit` spawn composition and exact VMangos formation walk-hit clipping remain separate work. This increment does not establish full creature-group or vanilla feature parity.
