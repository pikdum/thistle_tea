# Runtime server variables

VMangos script command 54 (`SET_SERVER_VARIABLE`) now writes unsigned 32-bit
indices and values into an application-owned ETS store. Missing indices read
as zero. Values survive creature, map, and player lifetimes and reset when the
server restarts, following the project's runtime-only persistence policy.

Condition 11 (`SAVED_VARIABLE`) compares a captured value using equality,
greater-or-equal, or less-or-equal. AI, player interactions, scripted events,
and loot actors receive snapshots through their existing boundary layers.
Pure condition evaluation performs no ETS reads. Missing snapshots stay
unknown, including under negation.

Assignments use the acknowledged script-command path. The script resumes
with a fresh condition context after the write completes, so an immediate
conditioned tail sees the new value. Invalid assignments honor abort behavior;
expired requests cannot overwrite current state.

References: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Maps/ScriptCommands.cpp:Map::ScriptCommand_ServerVariable`, and
`src/game/Conditions.cpp:CONDITION_SAVED_VARIABLE`.

## Native acceptance

An isolated build-5875 client used Debugwarrior (GUID 1) and a fresh server at
`2ec54285`. The development seed places The Windreaver (entry 14454, spawn
993400) on Programmer Isle at `{16383.2, 16398.1}`, retaining its original AI,
spells, and death script. The initially chosen position was outside usable
terrain; the final position was verified by client movement settling at
ground height 74.169.

All mutations used ordinary client login/logout, native spellcasting, and
existing `.tgm`, `.learn`, and `.go` commands. `.debug variable <index>` is a
new read-only diagnostic. Tidewave only read positions, variables, entity
identity, health, and pending script counts.

| Action | Verified result |
| --- | --- |
| Read variable 30011 on the fresh server | Client reports 0; Windreaver has 15,260 health. |
| Teleport to `{16383.2, 16398.1, 80.0}` and target Windreaver | Character settles on the hillside and engages the original boss AI. |
| Cast Death Touch (spell 5) | Initial attempt is blocked by the boss's stun; retry emits `CMSG_CAST_SPELL` and kills the boss. |
| Read variable after the death | Client displays the original death message and variable 30011 equals 6. Authoritative boss health is zero, with zero pending script runs. |
| Travel to Northshire on map 0 | Client and runtime diagnostic both retain variable 6 on the other map. |
| Log out normally | Player owner and world position become nil; variable remains 6. |
| Log back in | New player owner `#PID<0.4284.0>` replaces `#PID<0.2965.0>`; client again reports variable 6. |

No owner, script, condition, or movement errors occurred in the final run.
The only warnings were the existing unsupported account-data and GM-ticket
client messages.

This verifies the shared variable mechanism and the original Windreaver
death assignment. It does not verify complete elemental-invasion scheduling,
AQ war-effort progression, or fishing-contest winner orchestration. An earlier
attempt to start invasion event 73 returned `Unknown world event`: that row is
hardcoded, while the current event loader admits scheduled events. The native
acceptance therefore uses the development encounter. Imported AQ and fishing
conditions are covered by database integration tests.

## Automated validation and artifacts

Tests cover unsigned limits, zero defaults, snapshot isolation, reset after
table recreation, immediate script continuations, access from another
world after writer despawn, invalid assignments, expired requests, condition
comparisons and negation, and fresh player/AI/loot contexts. VMangos tests load
the four elemental boss death assignments and actual war-effort and fishing
conditions. The generated condition report now marks all five saved-variable
definitions evaluable.

Final gates after the terrain correction passed:

- `mix test.all`: 7,489 passed, seed 340202, in 78.3 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,617 files.
- Logs: `/tmp/thistle-world-variables-final-{tests,compile,credo}.log`.

Native evidence:

- Client artifacts: `/home/pikdum/.cache/thistle-wow-playtest.TtS1ZJ`.
- Screenshots: `windreaver-before.png`, `windreaver-dead.png`,
  `variable-on-another-map.png`, `offline.png`, and `reconnected.png`.
- Server log: `/tmp/thistle-world-variables-acceptance-server.log`.
- Read-only snapshots:
  `/tmp/thistle-world-variables-acceptance-{before,dead,travel,offline,reconnected}.log`.
- WoW PID 2956290 used `amdgpu`; its graphics counter increased from
  390,394,815 to 4,512,355,236 ns. Evidence:
  `/tmp/thistle-world-variables-acceptance-drm-{before,after}.log`.
- The owned client service and retained server were stopped. Ports 4000,
  3724, and 8085 were closed afterward; artifacts remain available.
