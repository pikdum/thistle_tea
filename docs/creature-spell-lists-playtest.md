# Runtime creature spell lists

VMangos command 55 (`CREATURE_SPELLS`) now switches or clears a creature's
combat spell list. It supports four weighted choices, explicit zero entries,
and the VMangos rule that uncovered percentage rolls clear the list. Missing
list definitions preserve the current list. Non-creature sources honor the
script's abort flag.

Template and script loading share `CreatureSpellList` definitions. Script
steps carry their resolved candidates, and the existing spell preparation
boundary loads their spell dependencies, including commands received from
another owner. The interpreter and behavior-tree nodes perform no database,
world, or process calls.

The active override belongs to the typed spell blackboard. Template spells
remain unchanged. Every assignment starts new initial-delay timers at the
assignment time and removes the old list's polling deadline. An already
running cast continues. Existing combat exit, death, and respawn transitions
clear the override. Creature archetype replacement also clears it when the
new archetype supplies a spell list. Friendly-target observation and totem
target selection use the active list.

Reference: VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`src/game/Maps/ScriptCommands.cpp:Map::ScriptCommand_CreatureSpells`, and
`src/game/AI/CreatureAI.cpp:CreatureAI::SetSpellsList`, `OnCombatStop`, and
`JustRespawned`. Fourteen imported EventAI rows use command 55.

## Creature Bear Form correction

The first native run at `1f096eb6` showed the Naturalist changing to list 77261,
applying Demoralizing Roar, and restoring its caster list on combat exit.
However, its Bear Form aura retained the tauren appearance. A DBC regression
reproduced the missing form-14 model projection before the fix.

Creature Bear Form now selects the bear display from the native model:
night elf models 55/56 select 2281; tauren models 59/60 select 2289; other
models select 902. Model identity is loaded with existing appearance data and
retained as a canonical unit input. Pure aura projection selects preloaded
model geometry, and removal restores the original appearance and scale.
This follows `src/game/Spells/SpellAuras.cpp:GetShapeshiftDisplayInfo`.

Regression evidence is in
`/tmp/thistle-creature-spell-lists-bear-{red,green}.log`. The initial client
session is `/home/pikdum/.cache/thistle-wow-playtest.WivSwx`, with runtime
snapshots in `/tmp/thistle-creature-spell-lists-{caster,bear,player-effects,reset}.log`.
The file named `caster.log` was sampled after the first form transition and
contains the bear override; it is not evidence of the initial caster state.

## Final native acceptance

A fresh server at `1f0b9690` and isolated build-5875 client used Debugwarrior
(GUID 1) with god mode enabled. Normal map loading supplied Grimtotem
Naturalists from the Feralas spawn pools. No development encounters or altered
creature AI were needed. Native movement, targeting, and `.go` drove the run;
Tidewave only read the resulting owner state.

The tracked female-model Naturalist was spawn 50018, GUID
`17379391091643564898`, owner `#PID<0.3192.0>`. Another nearby male-model
Naturalist, GUID `17379391091643564895`, was selected in the bear and restored
caster screenshots.

| Stage | Client and owner evidence |
| --- | --- |
| Before combat | Tracked Naturalist has default spells 12160/9739, no override, no active auras, display 6831, and native model 60. |
| Move into melee range near `{-4515.23, 729.556, 65.0}` on map 1 | Original EventAI selects list 77261, containing Demoralizing Roar (15727) and Rend (12161), and applies Bear Form (19030). |
| Bear phase | Both Naturalists visibly use bear display 2289. The tracked owner retains its original template spell list while scheduling the replacement spells. Demoralizing Roar is present on the player and visible in the client. |
| Leave for map 0 | The same tracked owner leaves combat, restores spells 12160/9739 and display 6831, removes Bear Form, and has no list override, cast, spell timers, or pending script runs. Health and mana are restored. |
| Return near `{-4533.0, 729.556, 65.0}` on map 1 | Both inspected owners remain out of combat with their template lists and native displays. The selected target portrait is a tauren again. |

Native acceptance proves replacement, visible appearance, a spell from the new
list reaching the player, and combat-exit cleanup. Weighted selection, explicit
list removal during an active cast, and death/respawn restoration are covered
by automated tests. Rend landing was not separately verified in the client.

There were no owner, script, movement, or appearance errors in the final run.
The only warnings were the existing unsupported account-data and GM-ticket
client messages.

## Validation and artifacts

- `mix test.all`: 7,502 passed, seed 914757, in 69.6 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,621 files.
- Final logs: `/tmp/thistle-creature-spell-lists-final-{tests,compile,credo}.log`.
- Client artifacts: `/home/pikdum/.cache/thistle-wow-playtest.rbIRBC`.
- Screenshots: `bear-form.png` and `restored-caster.png`.
- Server log: `/tmp/thistle-creature-spell-lists-final-server.log`.
- Owner snapshots:
  `/tmp/thistle-creature-spell-lists-final-{caster,bear,reset,returned,selected,selected-reset,player-effects}.log`.
- WoW PID 2969190 used `amdgpu`; its graphics counter increased from
  508,423,964 to 7,542,790,123 ns. Evidence:
  `/tmp/thistle-creature-spell-lists-final-drm-{before,after}.log`.
- Both helper-owned client sessions and their retained servers were stopped;
  ports 4000, 3724, and 8085 were closed afterward. Artifacts remain available.

The first full suite, run alongside compilation and lint, timed out waiting
1.5 seconds for a player logout. That test passed 16 isolated runs; the full
suite passed with the same seed when run alone, and the final suite after the
appearance fix also passed. No timeout was increased. Investigation logs are
`/tmp/thistle-creature-spell-lists-first-full-tests.log` and
`/tmp/thistle-creature-spell-lists-logout-check.log`.
