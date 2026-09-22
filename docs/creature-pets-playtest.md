# Creature-owned combat pets

NPC spell effect 56 now creates a single combat pet. This completes the missing summon path found during [creature-owned leash acceptance](creature-owner-leashes-playtest.md). Implementation commit: `53b26da1`.

## Reference and behavior

The reference is `refs/vmangos` revision `8f4e60845`: `Spell::EffectSummonPet`, `Unit::EffectSummonPet`, `Unit::UnsummonOldPetBeforeNewSummon`, and `Pet::InitStatsForLevel` / `Pet::Update`.

A living NPC pet blocks subsequent pet summons. A dead pet can be replaced with the same entry; a different entry remains blocked until the old pet is removed. The canonical companion relationship owns the identity, and the owning mob boundary monitors the child. The unit summon field and metadata pet GUID project that identity. Independent guardian collections continue to coexist with this single pet slot.

The loader uses the owner's level plus the spell's signed adjustment, floored at level one. It applies cached pet-level data where present, falls back to creature class/template inputs, retains template spell timing, and initializes pet passives before filling health and mana. NPC pets use aggressive reaction and the existing combat/follow behavior. They inherit creature-owner leash clocks through the existing ownership path.

A fighting pet may survive its owner's death. An idle pet with a dead owner, a pet whose owner is missing or in another world, a pet beyond 120 yards, or a pet no longer named by its owner's slot despawns. Pet death leaves a corpse for the existing 15-second creature summon cleanup interval. Owner process termination stops its child; child termination clears only the matching monitored relationship. Owner respawn restores the summon-field projection when a live relationship remains.

## Automated acceptance

`mix test.all` passed **4,802 tests**. Compilation passed with `--warnings-as-errors`; strict Credo found zero issues across **1,871 files**. The architecture dependency allowlist is unchanged.

Coverage includes explicit owner-context delivery, level adjustments, cached stat fallbacks, spell timing and passives, duplicate rejection, same-entry replacement after death, rejection of a different entry while a corpse remains, stale monitor rejection, child/owner termination, rejected summons from dead owners, and respawn projection. Pure behavior tests cover the 120-yard boundary, owner death during combat, corpse retention, missing owners, world mismatch, and replaced owner slots. Replacement and respawn assertions are automated evidence, not native-client claims.

## Native client acceptance

The isolated build-5875 client session is `/home/pikdum/.cache/thistle-wow-playtest.aFJBlD`. The character was level-60 `Debugwarlock`, GUID 6, with `.tgm` enabled. Client commands performed travel, targeting, and casts; Tidewave probes only read state.

At Fire Scar Shrine, Ashenvale, Ilkrud Magthrull (spawn 32439, entry 3664) cast his existing spawn-time Summon Succubus spell, 8722. The level-24 Succubus Minion (entry 10928, GUID `17383894744995725405`) appeared with 400 health and aggressive reaction. The native target frame and nameplate displayed “Succubus Minion” and “Ilkrud Magthrull's Minion.” The pet acquired the player while Ilkrud remained idle at 792 health. Canonical companion identity, unit summon field, and metadata pet GUID all agreed.

Five native rank-four Shadow Bolts lowered Ilkrud to 265 health, triggering his existing spell 6487 and two independent Voidwalker guardians. Their GUIDs were `17383894592859930787` and `17383894592859930788`; each had 490 health and level 17. The Succubus remained in the single pet slot at 400 health. All three summons targeted the player, and the owner plus all three summons shared one leash timestamp. The screenshot shows the Succubus and overlapping Voidwalker models; the owner read establishes the count and distinct relationships.

Native Death Touch killed Ilkrud. His clock membership cleared, while the Succubus and both Voidwalkers remained alive, targeting the player and retaining their shared clock. After the player returned to Programmer Isle, the pet and guardian relationships cleared. Each of the three summoned GUIDs had no actor, position, metadata row, or clock entry. Ilkrud's companion identity and metadata slot were nil, and his unit summon field was zero. The final cleanup read does not distinguish the guardians' duration expiry from target loss during world transfer.

There were no server errors or creature-pet failures. Existing account-data, raid-info, GM-ticket, and meeting-stone opcode warnings occurred during login. The helper-owned client, X server, and BEAM server were stopped afterward.

Artifacts:

- Server log: `/tmp/thistle-creature-pets-server.log`.
- Spawn-time pet: `/tmp/thistle-creature-pets-summoned.json`.
- Pet plus guardians: `/tmp/thistle-creature-pets-guardians.json`.
- Owner death: `/tmp/thistle-creature-pets-owner-dead.json`.
- Cleared owner slots: `/tmp/thistle-creature-pets-after-worldport.json`.
- Actor, projection, and clock cleanup: `/tmp/thistle-creature-pets-cleanup.json`.
- Checks: `/tmp/thistle-creature-pets-tests.log`, `-compile.log`, and `-credo.log`.
- Screenshots: `succubus-target.png`, `pet-and-guardians.png`, and `pet-owner-dead.png` in the session's `screenshots/` directory.

Full vanilla feature parity remains ongoing.
