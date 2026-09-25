# Controlled creature spell targets

Validated on 2026-09-25 with the native build-5875 client and local Thistle Tea.
Implementation: `7e02d0e8`; control-release fix: `d857eb38`.

## Behavior

`CMSG_PET_CAST_SPELL` decodes the vanilla GUID, spell ID, and target payload.
It and spell actions from `CMSG_PET_ACTION` dispatch through one creature cast
boundary. That boundary rechecks the current controller, published controlled
GUID, world, controller health, known spell, and passive flag. The ordinary
creature casting pipeline then validates and executes the spell. Rejected casts
report the pet error and clear only a speculative client cooldown.

Explicit ground selections retain their coordinates through preparation and
delivery. Player and controlled-creature admission validates ground distance,
minimum range, range modifiers, and supplied line-of-sight observations. Range
uses bounding radius, with the reference's 1.25-yard player admission allowance;
combat reach does not extend ground range. Unit selections retain the existing
unit validation rules.

Charm and possession release interrupt pending casts through `Casting.interrupt/2`.
This also tears down channels, emits the interruption projection, and clears a
global cooldown reserved by an unfinished preparation. Permanent pets retain
their original ownership and behavior on possession release.

Reference paths:

- `refs/wow_messages/wow_message_parser/wowm/world/pet/cmsg_pet_cast_spell.wowm`
- `refs/vmangos/src/game/Handlers/PetHandler.cpp`: `HandlePetCastSpellOpcode`
- `refs/vmangos/src/game/Spells/Spell.cpp`: `CheckPetCast`, `CheckRange`, ground LOS admission
- `refs/vmangos/src/game/Spells/SpellAuras.cpp`: `HandleModCharm`, `HandleModPossess`

## Automated validation

All 6,102 tests passed with `mix test.all`. Compilation with warnings as errors,
strict Credo, formatting, and `git diff --check` passed. The dependency allowlist
was unchanged.

Regressions cover packet registration and decoding, pet-relative self selection,
ground-coordinate retention, stale ownership and replacement, world mismatch,
dead controllers, unknown/passive spells, overlapping casts, insufficient power,
cooldown preservation, destination geometry and modifiers, one-time power payment,
and cast/channel teardown for charm, possession, and possession of a permanent pet.

Logs: `/tmp/thistle-pet-casting-focused.log`, `/tmp/thistle-pet-release-focused.log`,
and `/tmp/thistle-pet-release-{all,compile,credo}.log`.

## Native acceptance

Session: `/home/pikdum/.cache/thistle-wow-playtest.PAXyM6`.
Character: Debugshaman, GUID 8, level 50, Programmer Isle, open world 451.
The seeded Defias Evoker is entry 1729, low GUID 992300, full GUID
17379390991031542828, at `{16393.2, 16258.1, 70.00762176513672}`.

The client learned Mind Control rank 3 with `.learn 10912`, approached with
`.go xyz 16382 16258 75`, targeted the Evoker, and cast Mind Control normally.
`CastPetAction(3)` opened Flamestrike's ground cursor; an actual left click at
screen coordinate `{750, 350}` selected
`{16401.064453125, 16255.40234375, 69.94863891601562}`.

The final successful trace recorded these UTC times:

| Time | Evidence |
| --- | --- |
| 14:16:26.152 | Real `CmsgPetCastSpell`, spell 11829, explicit destination mask `0x40`. |
| 14:16:26.155 | `SmsgSpellStart`, 3,000 ms, with the selected coordinates. |
| 14:16:29.157 | `SmsgSpellGo` retained exactly the same coordinates; the client displayed the Flamestrike impact there. |
| 14:16:29.158 | Creature cast cleared and mana changed from 2,040 to 1,780, matching the 260-point cost. |

The location contained no enemies: the native trace has empty hit and miss lists.
This acceptance proves controlled casting, destination projection, resource
payment, and release; it does not claim new native damage or multi-client coverage.
Flamestrike has no recovery timer in this data; cooldown rejection is covered by
the automated tests.

A separate cancellation run started Flamestrike at 14:15:09.535. Right-clicking
the Mind Control buff sent `CmsgCancelAura{spell_id: 10912}` at 14:15:10.420,
before its three-second preparation completed. By 14:15:10.433, the creature had
no owner or cast and retained all 2,040 mana. `SmsgSpellFailedOther` for 11829
followed at 14:15:10.435. The remaining trace contained no spell-go or mana
payment. The client restored its ordinary controls and removed the pet bar.

Useful captures in the session's `screenshots` directory:

- `evoker-control.png`: actual possession and creature spell bar.
- `flamestrike-final-impact.png`: the selected ground impact.
- `control-cancelled.png`: restored player view and released Evoker.

Evidence logs:

- `/tmp/thistle-pet-casting-final-success.log`
- `/tmp/thistle-pet-casting-cancel-sample.log`
- `/tmp/thistle-pet-casting-native-server.log`
- `/tmp/thistle-pet-casting-return.log`
- `/tmp/thistle-pet-casting-cleanup.log`
- `/tmp/thistle-pet-casting-gpu-{before,after}.log`

WoW PID 874667 used AMD device `0000:0c:00.0`; its graphics-engine counter
advanced from 3,264,612,334 to 18,968,057,288 ns. No pet-casting, owner, or spell
errors appeared. Login reported existing unsupported account-data, GM-ticket,
and meeting-stone requests.

The character returned to the seed location with no controlled GUID or channel;
the Evoker had no pet component or cast. Normal logout removed both the player
owner and world position. The helper-owned service and retained server PTY were
stopped, with no remaining test WoW or BEAM process. Artifacts were retained.
