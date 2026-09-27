# Shared proximity acquisition acceptance

Validated on 2026-09-27 with the native build-5875 client. Implementation commit:
`29851a4a`.

## Behavior and reference

Ordinary creatures, aggressive pets, and engineering guardians now select targets
through `BT.Acquisition`, using immutable observations prepared by `AIEnvironment`.
Selection accounts for level-scaled detection distance, detection-range auras,
concealment, hostility, habitat, line of sight, and vertical separation. Equal-distance
ties use GUID order. Player-owned or charmed targets use their controller's observed
level for aggro distance; their own level remains available for other mechanics.

Aggressive pets and guardians exclude civilians from automatic acquisition. Explicit
pet attack commands continue through their existing validation and engagement path.
Ground creatures allow three yards between bounding surfaces; flight-capable
creatures retain their vertical exception. Hunter and summoned combat pets remain
grounded according to `CreatureMovement`.

The boundary also captures nearby line of sight for idle aggressive pets and expands
their observation range beyond the former fixed 20 yards. Movement-triggered mob
probes now honor the published detection-range modifier.

Reference: local VMangos revision `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Creature::GetAttackDistance`, `BasicAI::MoveInLineOfSight`,
`ScriptedPetAI::MoveInLineOfSight`, `PetAI::MoveInLineOfSight`, and
`WorldObject::GetDistanceZ`. The civilian rule follows the patch-1.8 behavior noted
in `PetAI`; `GetDistanceZ` subtracts both bounding radii.

## Native acceptance

| Scenario | Observed result |
| --- | --- |
| Explosive Sheep, level 30, summoned through item 4384 | Acquired a Prairie Wolf Alpha about 35.7 yards away, chased it, detonated, and killed it. The guardian reached zero health and cleared combat, then disappeared from its registry, world position, and metadata. |
| Hunter pet, level 49, on passive/Stay | Stayed idle with a live Defias Thug 36.45 yards away. Native `PetAggressiveMode()` selected that enemy without an Attack command. Stay kept the pet in place; passive/follow cleared combat and returned it to the owner. |
| Aggressive hunter pet near Vharr | Stayed idle for 20 observations over 10 seconds, at 20 yards from a hostile, visible level-40 civilian. Target remained zero and combat stayed false. |
| Explicit `PetAttack()` against Vharr | Entered combat with command state `:attack`; Vharr's health fell from 1,753 to 1,515 during the observation window. The client displayed the reduced health and Vharr targeting the pet. |
| Aggressive hunter pet below an elevated Defias Thug | Stayed idle for 20 observations over 10 seconds despite hostility and clear line of sight. Pet height was 69.685; enemy height was 79.9976, with 10 yards of horizontal separation. |
| Aggressive Explosive Sheep below the same enemy | Stayed alive at 1,003 health with no target or combat for 69 observations over approximately 10 seconds. Line of sight remained clear. |
| Logout and reconnect | Logout removed both pet and guardian processes, world positions, and metadata. The saved owner had no guardians and retained a suspended level-49 hunter pet in aggressive stance. Reconnect created a new pet GUID with that level and stance, no target or combat, and no guardian. |

The civilian and elevation checks use isolated development fixtures: Vharr at
`{16603.2, 16358.1}` and a Defias Thug eight yards above local terrain at
`{16603.2, 16438.1}`, both on map 451. Test positions were respectively
`.go xyz 16603.2 16338.1 69.444` and `.go xyz 16603.2 16428.1 69.685`.
Use `PetWait()` for the vanilla Stay action.

## Automated checks

`mix test.all`: **7,107 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` passed. Focused regressions cover concealment and marks,
obstructed targets, civilian projection, controller-level snapshots, minimum and
disabled detection range, positive and negative range modifiers, habitat, flight
exceptions, bounding-radius thresholds, blocked attackers, and deterministic ties.
An environment trace verifies that aggressive pets actually request nearby LOS
checks beyond 20 yards. The architecture dependency allowlist is unchanged.

Logs: `/tmp/thistle-acquisition-final-{all,compile,credo}.log`.

## Evidence

- First client: `/home/pikdum/.cache/thistle-wow-playtest.T8vGbQ`.
  Screenshots include `sheep-chasing.png`, `hunter-acquiring.png`, and
  `hunter-stay.png`.
- Fixture client: `/home/pikdum/.cache/thistle-wow-playtest.ncWy0W`.
  Screenshots include `civilian-idle.png`, `civilian-commanded-attack.png`,
  `elevated-idle.png`, and `elevated-final.png`.
- Read-only samples: `/tmp/thistle-acquisition-sheep-samples.log`,
  `/tmp/thistle-acquisition-sheep-cleanup.log`,
  `/tmp/thistle-acquisition-hunter-samples.log`,
  `/tmp/thistle-acquisition-civilian-{idle,command}.log`, and
  `/tmp/thistle-acquisition-elevated-{idle,guardian}.log`. Lifecycle evidence is in
  `/tmp/thistle-acquisition-{logout,reconnect}.log` and `reconnected.png`.
- Server logs: `/tmp/thistle-acquisition-server.log` and
  `/tmp/thistle-acquisition-fixtures-server.log`. No gameplay handler or AI errors
  appeared. Existing account-data and GM-ticket opcode warnings remain unrelated
  to these checks.
- Both clients used the helper's isolated GPU sessions. WoW PID 2340250's own
  `amdgpu` graphics counter increased from 1,404,829,809 to 7,088,222,003 ns;
  PID 2345733's increased from 3,064,794,944 to 9,525,088,164 ns. Each belonged to
  its recorded helper-owned service cgroup.

Both helper-owned client services and retained server sessions were stopped after
acceptance. Logs and screenshots were retained.
