# Pet command and return movement acceptance

Validated on 2026-09-27 with the native build-5875 client. Implementation:
`2a29d4b4`. Cast scheduling follow-up: `b202b556`.

## Behavior

Stay/Follow is the pet's persistent movement command. An explicit Attack is a
separate flag, so a pet can chase a commanded target without forgetting where it
was told to Stay. After combat it returns to that anchor or its owner. Stay
captures the current interpolated position, stops travel and pending navigation,
and retains an existing victim. Automatic Stay attacks do not chase targets that
leave melee reach.

Typed `Blackboard.Pet` state distinguishes a Follow recall from a normal combat
return. Proximity acquisition waits for either return to finish. A commanded
recall also suppresses owner-defense reactions and damage-triggered retaliation;
an explicit Attack can interrupt it. Natural returns permit defensive reactions.
Death clears return progress and the Attack flag.

Return movement uses the existing navigation intent/resolver and movement
transitions. Reaching a partial path endpoint does not count as reaching the Stay
anchor. The tree also retains the blackboard produced by combat cleanup instead
of restoring the preceding combat snapshot.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Unit::HandlePetCommand`, `PetAI::HandleReturnMovement`, `MovementInform`,
`CanAttack`, `MoveInLineOfSight`, and `AttackStart`.

## Native scenarios

Debughunter (level 50) and its level-49 Prairie Wolf Alpha used the existing
Defias Thug fixture on map 451. The pet was placed on passive/Stay at
`{16353.2, 16298.1, 69.444}`. Native autorun moved the owner to
`{16389.4805, 16298.0996, 69.4440}`, approximately 36.28 yards away. The fixture
had 86 health in this server run.

| Scenario | Observed result |
| --- | --- |
| Explicit Attack from Stay | The pet retained `:stay` and its saved anchor while its Attack flag became true. It chased the Thug and reduced health from 86 to 40 to zero. |
| Return after the kill | Thirty-one observations captured the combat return. The pet then stopped at `{16353.2002, 16298.0996, 69.4444}`, within navigation tolerance of the saved anchor, while its owner remained 36 yards away. Target, combat, Attack, and return progress were cleared. |
| Follow recall during an aggressive chase | Follow cleared the victim and Attack flag near `{16335.7367, 16298.0738}`. Twenty observations over approximately three seconds showed return mode `:command`, no victim, and no combat despite the nearby live Thug. |
| Arrival resumes aggression | Return mode cleared within about 2.9 yards of the owner. The next observation acquired a nearby Defias Evoker, with command still Follow and Attack false. The original Thug remained at 86 health throughout the recall. |
| Logout and reconnect | Logout removed the old pet's registry entry, world position, and metadata, saving its level-49 progression and aggressive stance. Reconnect created a new GUID in Follow mode with no target, combat, Attack flag, return progress, or Stay anchor. |

Client actions used `PetWait()`, `PetAttack()`, `PetFollow()`, and the stance
commands. Runtime probes were read-only. Screenshots show the pet staying apart
from its owner and then arriving beside the owner during recall.

## Verification

`mix test.all`: **7,133 passed**. Compilation with warnings as errors and strict
Credo passed. Tests cover interpolated Stay anchors, attack overrides, actual and
partial path arrival, recall suppression, resumed acquisition, damage during
recall, natural-return defense, Stay combat, and death cleanup. Existing targeting,
spell autocast, charge, possession, engagement, and architecture tests also pass.
No architecture allowlist changes were needed. A follow-up regression also verifies
that a newly commanded spell advances before return movement; the cast does not
wait for arrival at the owner.

Logs: `/tmp/thistle-pet-return-complete-{all,compile,credo}.log`.

## Evidence

- Client: `/home/pikdum/.cache/thistle-wow-playtest.hQMfGO`.
- Screenshots: `owner-separated.png`, `stay-attacking.png`, `stay-returned.png`,
  `stay-facing-pet.png`, `recalled-moving.png`, `recalled-arrived.png`,
  `logged-out.png`, and `reconnected.png`.
- Samples: `/tmp/thistle-pet-return-stay.log` and
  `/tmp/thistle-pet-return-recall.log`.
- Lifecycle: `/tmp/thistle-pet-return-before-logout.log`,
  `/tmp/thistle-pet-return-logout.log`, and `/tmp/thistle-pet-return-reconnect.log`.
- Server: `/tmp/thistle-pet-return-server.log`.
- WoW PID 2366449 used `amdgpu` in the helper-owned service cgroup. Its graphics
  counter increased from 1,084,676,671 to 13,260,868,309 ns.

The first client attempt preceded server readiness and produced authentication
failures; that session was stopped and excluded from acceptance. Vanilla blocked
the attempted movement Lua calls, so the actual owner movement used the native
autorun key.

After successful login, no gameplay handler or AI errors appeared. The only
warnings concerned existing account-data and GM-ticket opcodes. Both client
services and the retained server session were stopped; evidence was retained.
