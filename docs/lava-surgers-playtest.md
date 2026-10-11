# Lava Surger acceptance

Tested on 2026-10-10 with the native 1.12.1 build-5875 client against a
fresh local server. The reference is `mob_lava_surgerAI` in
`refs/vmangos/src/scripts/eastern_kingdoms/burning_steppes/molten_core/molten_core.cpp`,
plus `Creature::SelectAttackingTarget` and `SpellEntry::IsTargetInRange`.

## Implemented behavior

Lava Surgers (entry 12101) cast Surge (19196) at their farthest player on
the threat list who is in line of sight and spell range. Selection uses
combat distance, including both combat reaches. Spell range includes the
minimum and excludes the maximum, before choosing a target. The selected
player must also be more than seven yards away horizontally after both
bounding radii are subtracted. A due timer waits if that check fails.

The first Surge occurs after 1–2 seconds of combat; successful casts repeat
after 5–6 seconds. Stun and Banish preserve the remaining cooldown. The
ordinary melee system still runs, and the generic spell list is disabled
on aggro. Existing instance guards suppress these spawns after Garr dies.

Shared script targeting now applies spell range before selection and can
require a minimum horizontal surface distance afterward. Source review also
found that selectors excluding top threat filtered first, dropping a valid
second target when the original top target was ineligible. They now exclude
the original top threat before filtering, matching VMangos.

## Native acceptance

Debugshaman (GUID 8, level 60, god mode) entered Blackrock Depths through
its real entrance, then walked through the Molten Core portal in a raid.
The resulting world was map 409, instance 2. Debugwarrior (GUID 1, god mode)
was logged in with a headless connection and admitted through the normal
instance destination API to hold the victim's position. Nearby unrelated
enemies were cleared with the existing damage API.

The test used seeded DB GUID 56845, runtime GUID 17379391165056422527.
The tank stood near `{760, -710, -213.438}`; the native player started the
repeat run near `{780, -680, -213.988}`. Native `.damage 1` added the ranged
player to the threat list without taking the victim from the tank.

- The accepted 25-second trace recorded Surges at 1.959, 8.055, 14.328,
  and 20.791 seconds, each hitting GUID 8. Intervals were within the
  5–6-second range plus the one-second EventAI tick's resolution.
- Every cast projected a charge movement packet, then a knockback packet
  to GUID 8. The client displayed the Surger moving into melee; its own
  character moved from `{780, -680}` to approximately `{789.716, -665.402}`
  after four knockbacks. The Surger returned toward the tank each time.
- The owner retained victim GUID 1 throughout that trace. Both players
  stayed in the same instance copy, and the Surger remained visible.
- The native player learned Banish (18647) and used `/cast Banish`. In a
  separate 45-second trace, Surge fired at 2.640 seconds and Banish landed
  at 6.127 seconds. Stun was observed from 6.340 through 35.950 seconds;
  the source position stayed constant throughout those samples.
- While banished, the remaining cooldown stayed between 1,457 and 2,429 ms,
  reflecting the scheduler's one-second ticks. No Surge occurred during
  Banish. The first unstunned sample was at 36.127 seconds; Surge resumed
  at 38.133 and repeated at 44.134 seconds. Victim GUID 1 remained intact.
- Native `.damage 200000` caused ordinary death: health zero, finalized
  death, and combat cleared. The existing `respawn_creature` script command
  restored all 97,110 health in the same copy, cleared death and auras, and
  retained the pausing event. The native client selected the living Surger
  with a full target health bar; the owner confirmed visibility.
- The fresh server log contained no warnings or errors.

The first timing attempt was excluded because the headless tank's direct
world-reference teleport bypassed admission and caused an eviction. The
accepted run used the normal destination route and confirmed membership.

## Validation and evidence

Focused script, combat, range, EventAI, and architecture checks: 217 passed.
Final validation: `mix test.all` passed all 8,823 tests,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.

Targeting: `1479f594`; timer pausing: `981aa441`; Surger script: `5fd7c359`.

GPU session: `/home/pikdum/.cache/thistle-wow-playtest.A1JulP`, unit
`thistle-wow-playtest.A1JulP.service`. WoW PID 141507 belonged to that service
cgroup and used amdgpu client 410. Its graphics counter increased from
1,219,138,132 to 25,888,665,591 ns. The helper-owned client service, headless
connection, and retained server PTY were stopped after acceptance.

The session retains `server.log`, GPU ownership and counter records,
the focused and final validation logs,
screenshots including `surger-charge-accepted.png`, `surger-banished.png`,
`surger-resumed.png`, `surger-dead.png`, and `surger-respawned.png`, and:

- `thistle-lava-surger-repeating-accepted.json`
- `thistle-lava-surger-banish-accepted.json`
- `thistle-lava-surger-life-native.json`
