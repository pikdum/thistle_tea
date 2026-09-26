# Scripted guardian removal

Implementation: `e85ebced`. Native NPC-pet reward acceptance exposed unsupported
command 56 in Ilkrud Magthrull's evade script, 366401. The shared interpreter
now supports `REMOVE_GUARDIANS` for mob and player sources.

Reference: `refs/vmangos` revision `8f4e60845`,
`Map::ScriptCommand_RemoveGuardians`, `Unit::RemoveGuardians`, and
`Unit::RemoveGuardiansWithEntry`. A zero entry removes every guardian; a
positive entry removes only matching guardians. Invalid source types honor
the script abort flag.

The command uses the existing pure guardian lifecycle, immediately removing
canonical references and enqueuing typed despawn effects. Existing entity
owners remove children and retire their monitors. Combat pets and cosmetic
companions remain independent. No new boundary dependency or architecture
allowlist entry was introduced.

## Automated checks

`mix test.all` passed 6,345 tests. Compilation with warnings as errors passed;
strict Credo reported no issues across 2,343 files. Tests cover decoding,
both unit owner types, selective and complete removal, idempotence,
companion preservation, invalid-source abort behavior, actual child process
and world-projection cleanup, and the generated VMangos evade script.

## Native acceptance

A fresh server used level-60 Debughunter, GUID 7, and GPU session
`/home/pikdum/.cache/thistle-wow-playtest.L3CTTp`. Native rank-four Shadow
Bolts lowered Ilkrud to trigger his existing Voidwalker summons. Native
teleport to Programmer Isle removed the combat target, causing normal evade.
Tidewave samplers only read state.

The first long sampler exceeded the HTTP timeout, so its timing is excluded.
A second encounter used a short sampler started while both guardians were
alive. At its initial observation:

- Ilkrud had 207/792 health, target 7, and active combat.
- Guardians `17383894592859930881` and `17383894592859930882` each had 490 health
  and approximately 18,280 ms before their scheduled expiry.
- The owner retained two guardian monitors and Succubus GUID
  `17383894744995725472`.

At 2,526 ms, Ilkrud had 792 health, target zero, and no combat. The guardian
collection and monitor table were empty. Both guardian GUIDs had no process,
position, or metadata. This occurred over 15 seconds before normal expiry.
The same Succubus remained attached throughout the transition.

Screenshots `guardians-active.png` and `guardians-cleared.png` show the summons
in combat and the reset shrine. The timing and child cleanup are established
by the owner/projection sampler, not by screenshots alone.

WoW process 1293701 used amdgpu; its graphics counter increased from
5,688,725,778 to 15,502,353,420 ns. No error, unsupported-command, or
spell-validation logs appeared during the measured encounters.
The helper-owned client and retained BEAM server were stopped afterward.

Artifacts: `/tmp/thistle-guardian-script-{focused,tests,compile,credo,server}.log`,
`/tmp/thistle-guardian-script-evade-short.txt`, and the session screenshots.
