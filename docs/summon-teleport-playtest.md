# Caster-relative spell teleport acceptance

Build-5875 acceptance on 2026-09-23 used a fresh local server and three isolated
GPU clients. References were VMangos `Spell::EffectTeleUnitsFaceCaster`, database
and front-of-caster target selection in `Spell.cpp`, and collision placement in
`Object.cpp`.

## Implementation

Spell effect 43 now relocates player and creature targets through typed movement
effects. Explicit destinations take precedence; database destinations require the
caster's map, caster-origin selectors use the caster position, and forward
selectors use the effect radius. Missing database destinations fall back near the
caster. Facing uses normalized negative caster orientation, matching VMangos.

The receiver and resolver reject another world copy or a taxi passenger. Player
relocation uses the existing combat-preserving owner transition, retaining pets
and threat references. Creature relocation stops the current spline, clears its
movement target, and uses the shared teleport projection while retaining
engagement. Spell target coordinates are preloaded at boot into ETS.

Forward placement snaps to local geometry and clips blocked sight lines. The
geometry helper uses Thistle Tea's existing height and line-of-sight queries;
it does not reproduce VMangos's full pathfinder, transport geometry, or steep-drop
placement rules. Wall clipping has automated map coverage, not native coverage
in this session.

## Native results

Debugshaman (GUID 8) cast learned spell 15734, Summon. Debugwarlock (GUID 6) was
the hostile player target with an Imp; Debugmage (GUID 5) independently observed.
All remained in open map 451, Programmer Isle. Developer commands positioned the
characters and taught the spells; casts, pet controls, turning, and subsequent
movement went through the native client. Tidewave probes were read-only.

| Check | Observed result |
| --- | --- |
| Player relocation | From caster position `(16320, 16340, 69.44)`, Summon moved the warlock from `(16345, 16340, 69.44)` to `(16325, 16340, 69.44444)`. Caster, target, and observer views showed the new position. |
| Pet and combat | The first changed owner snapshot retained live Imp GUID `17383894568633630802` and combat remained active. The Imp followed to the new position. |
| Repeated cast and facing | With caster orientation `5.943892`, a second cast moved the target to `(16324.71495, 16338.33590, 69.44444)` and orientation `0.3392933`. Both the initial and changed snapshots were in combat with the same live pet. |
| Movement afterward | Native forward input moved the target to `(16328.015625, 16339.500977, 69.44444)`. A later sample retained that position and the same live Imp. |
| Creature relocation | Entangling Roots held Prairie Wolf Alpha GUID `17379391011684294224` while the caster backed away. Summon moved it from `(16314.24316, 16323.50195, 69.44444)` to `(16306.22765, 16326.33101, 69.44444)`, five yards ahead of the caster. The observer showed the rooted model jumping with the spell visual. |
| Creature engagement | Before and after relocation, the wolf remained alive, in combat, targeting GUID 8, with its threat entry intact. A root tick changed threat from 57 to 62 and health from 151 to 146 between samples. After roots expired, it resumed chasing; public position matched owner position. |

Native acceptance did not exercise database-position spells, another instance
copy, or taxi flight. Automated tests cover cached database selection, copy and
taxi rejection, owner orientation, pet retention, creature threat and spline
cleanup, observer packets, and real Northshire wall clipping.

## Evidence and validation

- Caster session: `/home/pikdum/.cache/thistle-wow-playtest.8lnIQr`.
- Target session: `/home/pikdum/.cache/thistle-wow-playtest.0wjWLX`.
- Observer session: `/home/pikdum/.cache/thistle-wow-playtest.5pmQhj`.
- Captures: caster `player-before`, all clients `player-settled`, caster and
  target `player-facing`, observer `creature-before-verified` and
  `creature-after-verified`. Earlier `player-after` captures were taken during
  the cast and are not the settled result.
- Server log: `/tmp/thistle-summon-teleport-server.log`.
- Read-only samples: `/tmp/thistle-summon-player-sample.log`,
  `/tmp/thistle-summon-player-facing-sample.log`,
  `/tmp/thistle-summon-creature-sample.log`, `/tmp/thistle-summon-followup.log`.
- WoW gfx counters on RX 7900 XT PCI `0000:0c:00.0` increased from
  7989870433 to 16380612943 ns for caster PID 2348997, 4920864958 to
  13315197748 ns for target PID 2350046, and 4811916140 to 12704212065 ns
  for observer PID 2350887.

Logs contain the expected duplicate-character login rejections during selection
and existing unsupported account-data, raid-info, ticket, and meeting-stone
requests. No teleport, movement, owner, or visibility failures occurred. The
Vanilla client did not recognize `/petpassive`; the native pet bar supplied
passive/follow controls. Two exploratory read-only probes used an incorrect
field or a cleared selection and were corrected before the recorded samples.
All three helper-owned client services and the retained server were stopped.

Validation on the accepted source: `mix test.all` passes 5,246 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`, formatting, and
`git diff --check` pass. Database and geometry tests use their respective
exclusive tags. No architecture allowlist entries were added.
