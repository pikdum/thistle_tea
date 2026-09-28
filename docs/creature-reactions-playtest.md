# Creature reaction modes

Creature scripts now support command 59 (`SET_REACT_STATE`): passive (0),
defensive (1), and aggressive (2). Seven imported EventAI rows use it,
including Thornling, Timbermaw Ancestor, and Felhound Tracker.

`CreatureReaction` reads the pet's existing control state or an ordinary
creature's scripted override and template defaults. Invisible triggers,
creatures with no target, totems, and templates with `IGNORE_COMBAT` default
to passive. `NO_AGGRO` defaults to defensive. Other creatures default to
aggressive. Critters retain their separate escape behavior.

Proximity acquisition requires aggressive mode. Defensive creatures can
retaliate and answer assistance requests. Passive creatures refuse new victims
and assistance requests. Changing a script mode preserves an existing fight;
the player's passive pet command still stops the pet's attack. Pet reaction
changes use the existing owner notification and companion retention path.

Scripted modes survive combat exit and ordinary respawn. Replacing or restoring
the creature entry initializes the new template's defaults. Invalid command
parameters and non-creature sources honor the script's abort flag.

Reference: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Creature::InitializeReactState`, `CreatureAI::AttackStart`,
`Creature::CanInitiateAttack`, `Creature::CanRespondToCallForHelpAgainst`,
`Map::ScriptCommand_SetReactState`, and `Unit::SelectHostileTarget`.

## Combat correction found during playtesting

The first implementation also refused combat participation when a passive
creature received damage. Native Rend testing showed health returning to full
between ticks. VMangos enters combat separately from selecting a victim.

Hostile contact now enters the shared engagement funnel with victim selection
preserved. Passive creatures retain combat flags and threat, suppress health
regeneration, and decline new victims. The behavior tree keeps pruning their
threat observations and uses the existing reset path when attackers disappear.
Changing to defensive or aggressive permits selecting the retained attacker.
Passive creatures with an existing victim retain it while valid, then stop
attacking instead of acquiring a replacement. Automatic assistance calls
require a victim. That final assistance guard has focused automated coverage.

## Native acceptance

An isolated build-5875 client used the ordinary Debugwarrior, level 50, with
god mode disabled. It entered Northshire on map 0 and exercised Defias Thug
entry 38, spawn 80147, GUID `17379390962660358419`, owned throughout by
`#PID<0.3067.0>`. The creature stood at `{-8994.59, -312.364, 71.9033}`;
the player stood about two yards away.

The new `.debug reaction <passive|defensive|aggressive>` command routes a
script step to the selected creature's owner. Gameplay damage came from
native Rend rank 1 (772), with rage supplied through `.modify rage 1000`.
Tidewave was used only for compact read-only snapshots.

| Action | Observed result |
| --- | --- |
| Set passive and stand nearby | No combat or victim; proximity and assistance projections both false. |
| Apply Rend while passive | Health fell from 71 to 56 and stayed there after the bleed expired, including a second read 18 seconds later. Combat and threat were retained, with no victim or retaliation. |
| Leave for Programmer's Isle, map 451 | The same owner cleared combat and threat, restored 71 health, and retained passive mode. |
| Return and set defensive | Remained idle at two yards; assistance available, proximity acquisition disabled. |
| Apply Rend while defensive | Selected player GUID 1, retained 12 threat, and visibly attacked. The client showed dodge feedback and the player as the creature's target. |
| Switch that fight to passive | Kept victim 1 and continued attacking. The client combat log displayed hits, misses, blocks, and parries. |
| Leave, return, and set aggressive | Acquired player GUID 1 without another attack. Health remained 71 and initial threat was zero. The client displayed melee hits. |
| Leave again | Combat false, victim zero, empty threat and aura lists, full health, and aggressive mode retained. |

The name-target command selected a different distant thug on the first return.
The creature was then selected by clicking its visible model, and its GUID was
verified before the defensive and aggressive checks. No evidence from the
distant selection is counted as acceptance.

Automated tests additionally cover template defaults, pet commands and owner
notification, acquisition, assistance, mode changes during combat, invalid
script inputs, imported script rows, entity-process metadata publication,
respawn, and entry replacement/restoration.

## Validation and artifacts

- `mix test.all`: 7,515 passed, seed 216536, in 71.6 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,623 files.
- Logs: `/tmp/thistle-creature-reaction-final-{tests,compile,credo}.log`.

- Client artifacts: `/home/pikdum/.cache/thistle-wow-playtest.aSG7uG`.
- Screenshots: `passive-damaged.png`, `defensive-retaliation.png`,
  `retained-fight.png`, and `aggressive-acquisition.png`.
- Server log: `/tmp/thistle-creature-reaction-final-server.log`.
- Owner snapshots: `/tmp/thistle-creature-reaction-final-*.log`, including
  passive damage/retention/reset, defensive proximity/damage, mode changes
  during combat, and aggressive acquisition/reset.
- WoW PID 2982360 used `amdgpu`; its graphics counter increased from
  1,696,085,603 to 17,108,594,755 ns. Evidence is in
  `/tmp/thistle-creature-reaction-final-drm-{before,after}.log`.
- Initial reproduction: `/home/pikdum/.cache/thistle-wow-playtest.vO1pus` and
  `/tmp/thistle-creature-reaction-server.log`.

There were no owner, script, or movement errors. Expected warnings were two
Rend attempts before facing the target and the existing unsupported
account-data and GM-ticket client messages. Both helper-owned client sessions
and retained server processes were stopped; ports 4000, 3724, and 8085 were
closed afterward. Artifacts remain available.
