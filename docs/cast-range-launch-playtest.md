# Spell range and target checks at launch

Implemented in `5e2dcee5` and tested on 2026-09-27 with the native build-5875
client and a fresh local server.

## Shared rules

Ordinary casts now revalidate fresh target facts before paying costs, resolving
ammunition, starting recovery cooldowns, or launching effects. Admission and
launch share target selection, including implicit pets, resurrection bodies,
and battleground corpses. The existing requirements boundary builds the
snapshot; pure validation runs against the owner's current caster state.
Target movement, death, disappearance, faction changes, and facing changes can
reject launch. Ground destinations also use the launch range allowance.

The former flat five-yard unit-cast allowance has been replaced with vanilla
rules:

| Caster | Admission allowance | Launch allowance |
| --- | ---: | ---: |
| Player | 1.25 yards | 6.25 yards |
| Creature | 0 yards | 2.25 yards |

Ranged spells subtract both units' combat reach from three-dimensional center
distance. Range modifiers apply to the maximum before the allowance; minimum
range stays separate. Combat-range abilities instead use horizontal distance,
minimum 1.5-yard reaches, the melee spell reach formula, and a strict outer
boundary. They receive no extra launch allowance. Queued melee swings defer
distance to swing readiness; triggered spells bypass range admission.

Both units moving faster than 4.97 yards per second adds 2.66 yards when at
least one is a player. Owners publish the speed implied by current translation
flags, including walking, backward movement, swimming, and airborne movement.
Game objects remain valid spell casters without a unit component.

Compared against VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`:
`Spell::CheckRange`, `WorldObject::CanReachWithMeleeSpellAttack`,
`WorldObject::GetLeewayBonusRange`, `Unit::GetCombatReachToTarget`, and
`Unit::GetXZFlagBasedSpeed`.

## Automated acceptance

All **7,286 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo reported zero issues across 2,569 source files.

Coverage includes exact admission and launch boundaries, range modifiers,
minimum range, world isolation, zero-range reductions, melee height/reach,
movement thresholds, triggered exceptions, current movement publication,
implicit pet selection, and target changes during preparation. Boundary tests
prove failed launch retains mana and recovery cooldowns, while movement within
grace spends power once and starts the configured cooldown. Existing channel,
ranged ammunition, resurrection, corpse removal, and object-caster tests pass.

## Native acceptance

Debugmage (GUID 5, level 50, godmode disabled) cast rank-one Pyroblast (11366):
35-yard range, six-second preparation, and 125-mana cost. Both mage and target
had 1.5-yard combat reach, giving center-distance limits of 39.25 yards at
admission and 44.25 yards at launch. The stationary caster receives no movement
bonus. The seeded level-three Defias Thug `17379390962661271572` started with
71 health at `{16653.2, 16268.1, 69.444}` on map 451.

The `.move [x y z]` extension directed the selected creature through its normal
point movement at 2.5 yards per second. Native client commands began movement
after preparation started. Read-only 25-ms samples observed both owners and
the target's projected world position.

| Case | Authoritative result |
| --- | --- |
| Grace | Cast starts at 32 yards; launches at 43.14 yards after about six seconds; mana falls from 3,963 to 3,838. |
| Impact | Projectile hits for 202, target health becomes zero, and combat clears about 1.2 seconds later. The creature subsequently respawns at home. |
| Rejection | Cast starts at 34.5 yards; fails at 45.62 yards after about six seconds; mana remains 3,963, health remains 71, and neither cooldown nor combat starts. |

The successful client showed `SPELLCAST_START`, `SPELLCAST_STOP`, the projectile,
and the 202-point hit. The rejection showed `SPELLCAST_START` at 320090.751
seconds, then `SPELLCAST_FAILED` and **Out of range** at 320096.754, with a red
Failed cast bar. A later owner read confirmed no active cast, full mana, no
combat, unchanged target health, and no spell recovery cooldown.

An initial Fireball attempt was refused by the client before any cast began.
A later name-based selection picked another Defias Thug and was also refused
before casting. Neither is counted as launch acceptance. The final rejection
used a native model click and verified the selected GUID before casting.

## Retained evidence

Normal logout returned to character selection and removed the player's owner,
position, and metadata. Stored state retained full mana, no cast, and no combat.
The helper-owned client and local server were stopped. The server logged no
errors; warnings were the existing account-data and GM-ticket requests.

WoW PID 2544546 ran in the helper's owned service. Its own amdgpu graphics
counter advanced from 4,870,390,578 to 12,484,461,987 ns during acceptance.

- Session: `/home/pikdum/.cache/thistle-wow-playtest.qIrrdh`.
- Screenshots: `screenshots/pyro-range-failure.png` contains the successful
  projectile despite its preliminary filename; `pyro-grace-success.png`
  contains the hit; `pyro-range-rejected-verified.png` contains the failed cast.
- Grace samples: `/tmp/thistle-cast-range-pyro-failure-sample.log`.
- Rejection samples: `/tmp/thistle-cast-range-pyro-rejection-verified.log`.
- Initial and final facts: `/tmp/thistle-cast-range-native-{before,after}.log`
  and `/tmp/thistle-cast-range-pyro-before-verified.log`. Logout evidence:
  `/tmp/thistle-cast-range-logout.log` and `screenshots/logged-out.png`.
- Server, GPU counters, and gates:
  `/tmp/thistle-cast-range-{server,gpu-before,gpu-after,all,compile,credo}.log`.
