# Scripted companion commands and events

Creature script command 88 now supports stay, follow, attack, and dismiss through
the existing companion command path. Scripts use current owner and target
observations, retain the current script blackboard, and validate attack targets,
owner pacification, world membership, and transport compatibility. Invalid
creature commands leave the script running; non-creature sources honor its abort
flag, matching VMangos.

Stay retains an existing attack while stopping movement. Follow stops attacks
and casting through the engagement funnel and returns to the owner. Possessed
creatures retain client-controlled movement. Dismiss uses the normal despawn
effect for summons, releases charmed creatures through the control lifecycle,
and leaves hunter pets to their dismissal spell.

Guardians, mini-pets, and NPC-owned pets now tick imported EventAI events.
Mini-pets honor their command state while idle. Player-controlled hunter and
summoned pets, charmed creatures, and possessed creatures suppress template
EventAI callbacks, following the reference AI-selection rules.

The tracker playtest exposed missing target-relative movement. Command 3 now
also supports coordinate offsets from a target and stopping at a distance from
its bounding radius. Random angles come from the injected AI context; authored
negative orientation chooses the target-to-source angle. Navigation retains
travel time, gait, facing, and point-completion identity. Missing targets,
foreign worlds, dead sources, and movement inhibition honor script aborts.

Reference: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Map::ScriptCommand_SetCommandState`, `Unit::HandlePetCommand`,
`FactorySelector::selectAI`, `PetEventAI::UpdateAI`,
`Map::ScriptCommand_MoveTo`, and `WorldObject::GetNearPoint`.

## Native acceptance

An isolated build-5875 client used Debugwarrior and the
[drive-client-playtest skill](../.agents/skills/drive-client-playtest/SKILL.md).
All gameplay actions used native chat, Lua, movement keys, or existing developer
commands. Tidewave supplied read-only state snapshots. The final server ran
commit `a0071c66` without hot reloads. God mode protected the player during the
Azshara movement checks.

Felhound Tracker was summoned using Fel Orb item 10831 and its normal spell
12851. The successful tracker was entry 8668, GUID `17383894707079217503`,
owned throughout both trips by `#PID<0.5238.0>`. The active Azsharite formation
was entry 152631 at `{2441.85, -5797.37, 109.119}` on map 1. The player stood
at approximately `{2441.85, -5815.0, 112.65}`.

| Native action | Observed result |
| --- | --- |
| Summon beside the formation | Passive guardian, follow command, phase 0, stationary beside its owner. |
| Select tracker and `/roar` | Client displayed its search message and the tracker running toward the crystal. State changed to stay, phase 1, and an active movement spline. |
| Allow the movement script to finish | The same creature returned to within 2.02 yards of the owner, with follow command and phase 0 restored. |
| `/roar` again | The same creature repeated the search and returned, with the second search message visible in chat. |
| Roar with no formation in range | No search, movement, command, or phase change. Spawn pools selected different formations after the restart; the active formation was located before the successful check. |
| Teleport away | Tracker process, metadata, and spatial position all became nil. |

For timer scheduling, the client learned and cast spell 18634, Target Dummy -
Event 001, on Programmer's Isle. Mortar Team Target Dummy entry 11875, GUID
`17383894760883749251`, owner `#PID<0.5346.0>`, ran its imported out-of-combat
timer and entered stay. Its non-repeatable event became disabled. The client
selected the dummy and walked 15.52 yards away. The dummy remained stationary
at `{16303.2002, 16318.0996, 69.4400}`. Teleporting to another map removed its
process, metadata, and spatial position.

Automated coverage additionally exercises all four commands, passive attack
overrides, invalid targets and owners, casts, combat timers, possession,
control release, hunter dismissal, blackboard preservation, controlled-pet
event suppression, mini-pet stay/follow events, imported scripts, target-relative
movement geometry, movement options, and abort behavior.

## Validation

- `mix test.all`: 7,529 passed, seed 891677, in 69.7 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,627 files.
- Logs: `/tmp/thistle-companion-final-{tests,compile,credo}.log`.

## Artifacts and cleanup

- Final client: `/home/pikdum/.cache/thistle-wow-playtest.UIxUQb`.
- Screenshots: `tracker-running.png`, `tracker-returned.png`,
  `tracker-formation.png` (second return), and `dummy-stays.png`.
- Final server log: `/tmp/thistle-companion-final-server.log`.
- State evidence: `/tmp/thistle-companion-final-*.log`, particularly
  `ready`, `active-outbound`, `active-return`, `arrived` (second return),
  `dummy-spawn`, `dummy-stay`, `dummy-events`, and both cleanup snapshots.
- Native WoW PID 2999420 used `amdgpu`; its graphics-engine counter increased
  from 10,612,405,927 to 17,927,367,916 ns during the final checks.
- Initial client: `/home/pikdum/.cache/thistle-wow-playtest.KeMPGb`;
  `/tmp/thistle-companion-server.log` records the unsupported movement that
  prompted the follow-up fix.
- Both owned client services are inactive. Both retained servers exited, and
  ports 4000, 3724, and 8085 were closed before the final test suite.
- The final native server logged no errors or unsupported script commands.
