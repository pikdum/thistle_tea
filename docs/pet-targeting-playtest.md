# Automatic pet targeting acceptance

Validated on 2026-09-27 with the native build-5875 client. Implementation:
`c616a49a`.

## Shared rules

`BT.Pet.Targeting` applies pet attack permissions to proximity acquisition,
owner-defense reactions, and harmful autocasts. Stay permits automatic acquisition
only within melee reach. Unflagged player pets avoid automatically engaging PvP
flagged targets. Owner defense preserves a living victim. Explicit Attack commands
retain their override for the commanded target.

Aura holders determine whether damage-breakable crowd control protects a target:
confusion, stun, or transformation must also have the damage-cancellation flag.
Owners publish that derived fact through existing metadata updates. Polymorph,
Gouge, Freezing Trap, Sap, and Repentance qualify; Frost Nova, Hammer of Justice,
and Fear do not. Aggressive guardians retain their separate reference behavior.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`PetAI::CanAttack`, `PetAI::OwnerAttackedBy`, `ScriptedPetAI`, and
`Unit::HasAuraPetShouldAvoidBreaking`. This change governs automatic selection
and autocasting; it does not introduce a new rule stopping ongoing melee when
crowd control arrives.

## Native acceptance

Debughunter (level 50), its level-49 Prairie Wolf Alpha, and the existing level-3
Defias Thug fixture were used on map 451. The owner stood at
`.go xyz 16353.2 16298.1 69.444`. Polymorph was learned with the existing GM
command and cast through the normal client spell path. Runtime probes were
read-only.

| Scenario | Observed result |
| --- | --- |
| Aggressive Stay | Thirty observations over 14.9 seconds showed target zero and combat false with a live enemy about 25.08 yards away. The NPC stayed at 71 health. |
| Aggressive Follow while Polymorph is active | Thirteen half-second observations showed the protected target at 71 health, pet target zero, and combat false. The client displayed the sheep portrait and aura while the pet waited beside its owner. |
| Explicit Attack against that sheep | Command state changed to `:attack` and the pet chased while Polymorph was still active. The first damage removed the aura and reduced health from 71 to 19; the next hit killed the NPC. |
| Automatic acquisition after Polymorph expires | Rank 1 remained projected for approximately 20 seconds. The aggressive pet stayed idle through 33 protected observations, then acquired the NPC with command state still `:follow` as protection cleared. Health subsequently fell from 71 to 13 to zero. No Attack command was sent in this run. |
| Teleport and logout cleanup | Both transitions removed the previous pet's registry entry, world position, and metadata. Logout saved a suspended level-49 hunter pet in aggressive stance. |
| Reconnect | Created a new pet GUID at level 49 in aggressive/Follow state, with no victim or combat and no stale crowd-control projection. The previous pet remained absent. |

The Stay result corrects the distant acquisition recorded in the earlier
[proximity acceptance](proximity-acquisition-playtest.md).

## Automated checks

`mix test.all`: **7,123 passed**. Compilation with warnings as errors and strict
Credo passed. Regressions cover Stay reach, crowd control, automatic PvP entry,
explicit Attack, passive/broken/possessed pets, owner-defense victim retention,
server callback delivery, and aura removal, expiry, and death. Tagged DBC tests
verify the actual vanilla spell rows. The architecture dependency allowlist is
unchanged.

PvP gating and owner-defense victim retention were verified by automated tests;
the native scenarios above exercised acquisition, explicit commands, and lifecycle
cleanup.

Logs: `/tmp/thistle-pet-targeting-{all,compile,credo}.log`.

## Evidence

- Client: `/home/pikdum/.cache/thistle-wow-playtest.oIzh01`.
- Screenshots: `stay-idle.png`, `control-protected.png`,
  `control-commanded.png`, `control-finished.png`, `expiry-protected.png`,
  `expiry-reacquired.png`, `logged-out.png`, and `reconnected.png`.
- Authoritative samples: `/tmp/thistle-pet-targeting-stay-confirmed.log` and
  `/tmp/thistle-pet-targeting-control-confirmed.log`. Expiry is recorded in
  `/tmp/thistle-pet-targeting-expiry.log`; lifecycle evidence is in
  `/tmp/thistle-pet-targeting-before-logout.log` and
  `/tmp/thistle-pet-targeting-logout.log` and
  `/tmp/thistle-pet-targeting-reconnect.log`.
- Server: `/tmp/thistle-pet-targeting-server.log`.
- WoW PID 2354388 used `amdgpu`; its own graphics counter increased from
  1,010,417,302 to 2,931,627,485 ns in the recorded helper-owned service cgroup.

Earlier exploratory captures missed the target transition after client selection
cleared. The acceptance samples above track the fixture GUID directly.

No gameplay handler or AI errors appeared. Existing account-data and GM-ticket
opcode warnings were the only server warnings. The helper-owned client service
and retained server session were stopped; evidence was retained.
