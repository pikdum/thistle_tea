# Pet attack stops and aura cancellation

Accepted against source commit `fe945f05` on 2026-09-25.

`CMSG_PET_STOP_ATTACK` now stops a living, currently controlled creature or
player. The shared melee transition clears the victim and queued next-swing
spell while retaining combat, threat, ordinary casts, and ranged repetition.
`CMSG_PET_CANCEL_AURA` removes a spell's holders from the current pet or charmed
creature through the shared aura transition. Remote possession cannot cancel
pet auras. Both requests recheck control at the entity owner.

Regular `CMSG_ATTACKSTOP` also uses the shared melee stop. This fixes queued
Heroic Strike surviving an attack stop and routes its interruption feedback
through the player's explicit event context.

## References and automated validation

- `refs/vmangos/src/game/Handlers/PetHandler.cpp`: `HandlePetStopAttack`.
- `refs/vmangos/src/game/Handlers/SpellHandler.cpp`: `HandlePetCancelAuraOpcode`.
- `refs/vmangos/src/game/Objects/Unit.cpp`: `AttackStop` interrupts the current
  melee spell; full combat cleanup belongs to `CombatStop`.

Focused tests passed **70 tests**. `mix test.all` passed **6,116 tests**;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and diff
checks passed. The source remained unchanged throughout native acceptance.

Regressions cover codecs and dispatch, current and stale controllers, replacement,
world mismatch, possession, dead-pet feedback, queued melee interruption,
ordinary-cast and auto-shot preservation, timer scheduling, and stop packets.
Aura cancellation also removes an externally applied armor buff, recomputes
armor, and preserves an unrelated periodic holder and its schedule.
Controlled-player stops and rejection cases have automated coverage; the native
stop exercise below used a possessed creature.

## Native client acceptance

The isolated build-5875 client used session
`/home/pikdum/.cache/thistle-wow-playtest.USBmIF` against the local server.
WoW PID 895414 used `amdgpu` on `0000:0c:00.0`; its own graphics counter increased
from 6,398,742,596 to 56,626,545,947 ns. Actions came from normal client chat,
Lua APIs, and mouse clicks. Tidewave only observed state and packet traffic.

| Exercise | Client evidence | Authoritative evidence |
| --- | --- | --- |
| Debughunter attacks a Skeletal Flayer, casts Eyes of the Beast, attacks through the possession bar, then calls `PetStopAttack()` | Possessed viewpoint and channel remain; attack button switches off | At 15:14:58.466 UTC, `CMSG_PET_STOP_ATTACK` names pet 17383894611314868476. `SMSG_ATTACKSTOP` follows; target becomes 0, melee stops, and combat, threat, mover, and channel spell 1002 remain |
| Release Eyes of the Beast with `/wave`, then `PetFollow()` | Hunter viewpoint and normal pet bar return; living wolf returns to its owner | Same pet GUID remains, possession clears, mover returns to 7, and follow clears combat and threat |
| Debugwarrior uses Bloodrage, starts attacking a distant target, queues Heroic Strike, then toggles `AttackTarget()` | Heroic Strike loses its queued highlight; client displays `Interrupted` | Spell 11566 changes from queued to nil, melee switches off, target becomes 0, and rage remains 180 at the stop transition. `CMSG_ATTACKSTOP`, `SMSG_ATTACKSTOP`, and interrupted `SMSG_CAST_RESULT` are observed |
| Debugwarlock clicks the Imp's Phase Shift button, then clicks it again | Phase Shift buff icon and active button appear, then clear | At 15:21:05.683 UTC, `CMSG_PET_CANCEL_AURA` names pet 17383894568633631041 and spell 4511. The `mod_unattackable` holder disappears; flags change from 69640 to 4104. Health stays 558, autocast stays disabled, and the holder remains absent through the 25-second sample |
| Normal logout | Character selection returns | Hunter, warrior, warlock, and their tested pet processes are absent; corresponding world positions and metadata are nil |

The initial normal Voidwalker `PetStopAttack()` attempt did not emit a packet.
Read-only inspection of this client's executable showed that the Lua action
requires its possession attack flag; the successful runs used Eyes of the Beast.
An early possessed-pet run verified the stop but allowed the enemies to kill the
pet afterward. The repeat above verifies living release and return as well.
No client binary or runtime state was modified to trigger these actions.

There were no server errors or unsupported warnings for the new opcodes.
Existing account-data, ticket, and meeting-stone warnings appeared during login.
An exploratory Revive Pet cast without an active corpse was rejected as
`target_not_dead`; Call Pet followed by Revive Pet restored the dead wolf.
Two initial diagnostic samplers failed on a removed process and an incorrect
holder-field assumption; the final samples completed normally.

## Retained evidence

- `/tmp/thistle-pet-commands-native-server.log`.
- `/tmp/thistle-possessed-pet-stop-final.log`.
- `/tmp/thistle-melee-stop-native.log`.
- `/tmp/thistle-pet-aura-cancel-final.log`.
- `/tmp/thistle-pet-commands-{logout,final-logout,gpu-before,gpu-after}.log`.
- `/tmp/thistle-pet-commands-{focused,tests,credo}.log`.
- Session screenshots: `final-possessed-attacking.png`,
  `final-possessed-stopped.png`, `final-pet-returned.png`,
  `heroic-strike-queued.png`, `heroic-strike-stop-attempt.png`,
  `final-phase-shift-active.png`, and `final-phase-shift-cancelled.png`.

The helper-owned client unit is inactive, the server PTY exited, and artifacts
were retained. Nothing was pushed.
