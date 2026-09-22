# Creature-owned summon combat clocks

This extends [shared creature leashes](creature-leashes-playtest.md). The reference is `refs/vmangos` revision `8f4e60845`, specifically `Creature::OnEnterCombat`, `GetLastLeashExtensionTimePtr`, `Unit::SetInCombatWithAggressor`, and the damage path preceding death.

## Behavior

A creature-owned summon adopts its owner's clock when entering combat. Ownership takes precedence over an assistance source, and each creature retains its own combat origin. Direct incoming contact extends the shared time in either direction. A creator GUID alone does not establish ownership; player owners do not participate in creature-clock inheritance.

The pure transition carries an ownership request in its typed leash event. The boundary resolves the owner from the entity registry, world position, and incarnation metadata, without querying another actor's state. The clock owner validates the world, process, and incarnation. If a summon fights before its owner, an idle owner membership retains the shared clock for the owner's eventual engagement. A later owner stop detaches that relationship; an old surviving summon cannot refresh a replacement owner fight. Death, despawn, process exit, and world shutdown release membership.

A separate correction preserves a lethal hit's queued extension before the victim's stop event. Previously the effect drain rejected every non-stop event once the victim was dead, losing that final update for surviving helpers. Starts still require the entity's current active reference; extensions and stops retain their captured references and are validated by the clock owner.

Implementation commits are `ac2ef85b` and `98c4a093`.

## Automated acceptance

`mix test.all` passed **4,789 tests**. Compilation passed with `--warnings-as-errors`, and strict Credo found zero issues across **1,866 files**. The architecture dependency allowlist was unchanged.

Coverage includes active and idle creature owners, independent origins, inheritance over an existing assistance clock, bidirectional refresh, lethal-contact ordering, owner death with surviving summons, separate later fights, idle-owner despawn, stale incarnation/process rejection, world-copy isolation, non-owner creator relationships, player-owner exclusion, and final monitor/clock cleanup. Idle-owner and stale-reference cases are automated acceptance, not claims from the native run.

## Native client acceptance

The isolated build-5875 client session is `/home/pikdum/.cache/thistle-wow-playtest.92GmHX`. The character is level-60 `Debugwarlock`, GUID 6, with `.tgm` enabled. Travel, targeting, and casts used native client commands; Tidewave probes only read state.

Ilkrud Magthrull, database spawn 32439 and entry 3664, began at 792 health in Fire Scar Shrine, Ashenvale. Native rank-four Shadow Bolts lowered him to 248 health, triggering his existing 50%-health event and spell 6487, Ilkrud's Guardians. Two level-24 Voidwalkers appeared, with GUIDs `17383894592859930793` and `17383894592859930794`, each at 490 health. Both carried Ilkrud's summoner GUID and targeted the player. The owner and both summons published the same shared timestamp. `ilkrud-guardians.png` shows the client summon presentation; the models overlap, and the owner read establishes the count.

A rank-one Shadow Bolt hit only the first Voidwalker for 14 damage. Ilkrud remained at 248 health, the struck guardian had 476 health, and its sibling retained 490 health. All three shared a clock age of 4,074 ms, while Ilkrud's original contact age was 36,382 ms and the untouched guardian's was 34,857 ms. This establishes refresh from the summon back to the owner and across to its sibling.

Native Death Touch then killed Ilkrud. His clock membership disappeared. Both Voidwalkers remained alive and in combat, retaining a shared timestamp corresponding to the owner's lethal-contact transition. `guardians-owner-dead.png` shows the surviving summon presentation. The isolated automated regression distinguishes lethal-hit effect ordering from the owner's concurrent defend notifications.

After the player returned to Programmer Isle and the guardians' one-minute lifetime window had elapsed, both GUIDs had no actor, position, metadata row, or clock entry. Ilkrud's guardian collection was empty. These final reads establish complete cleanup; they do not distinguish the exact ordering of duration expiry and target loss during world transfer.

The server log contained no errors or owner crashes. Existing account-data, raid-info, GM-ticket, and meeting-stone opcode warnings occurred during login. The helper-owned client, X server, and BEAM server were stopped afterward.

Artifacts:

- Server log: `/tmp/thistle-owned-leashes-server.log`.
- Initial summon state: `/tmp/thistle-owned-leashes-summoned.json`.
- Guardian hit: `/tmp/thistle-owned-leashes-child-hit.json`.
- Owner death: `/tmp/thistle-owned-leashes-owner-dead.json`.
- Owner collection after world transfer: `/tmp/thistle-owned-leashes-after-worldport.json`.
- Complete guardian cleanup: `/tmp/thistle-owned-leashes-cleanup.json`.
- Final checks: `/tmp/thistle-owned-leashes-final-tests.log`, `-final-compile.log`, and `-final-credo.log`.
- Screenshots: the client session's `screenshots/` directory.

## Follow-up

This run uncovered an unsupported NPC combat-pet path: spell effect 56 produced `SummonPet`, but its boundary implementation only accepted player characters. Ilkrud's spawn-time Summon Succubus, spell 8722, exercised the gap. [Creature-owned combat pets](creature-pets-playtest.md) now records its implementation and native acceptance, including the single pet relationship alongside the independent guardian collection. Full vanilla parity remains ongoing.
