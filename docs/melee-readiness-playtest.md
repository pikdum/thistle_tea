# Melee readiness and swing timing

Ordinary melee swings and queued extra attacks now share readiness checks for
living attackers and victims, world membership, detection, range, facing, and
combat controls. The facing arc is 120 degrees, with the vanilla exception
within 1.4 yards of the victim's center. Stun, confusion, active fear,
pacification, and Feign Death prevent swings. Root and silence alone do not;
fear suppressed by a prevent-fleeing aura also permits attacks.

A ready hand retries an invalid attack after 100 ms without consuming a queued
melee ability or its resources. A hand whose deadline is still in the future
keeps that deadline. Player facing and range errors are sent once per changed
error through typed messages and the explicit owner context. Successful swings
and attack-stop transitions clear the remembered error.

Normal main-hand and off-hand swings have at least 200 ms between them. Each
successful swing delays the other hand if its deadline is closer than that.
Creature scheduling now considers both hands. Stationary creatures and pets
turn toward a valid melee victim before swinging. Ordinary swings wait for
casting; extra attacks retain their existing casting exception.

The behavior tree uses its immutable perception snapshot for these checks.
Removing the obsolete alternate melee entry point also removed two World and
Metadata exceptions from the architecture dependency ratchet.

## References and automated checks

Compared against VMangos `8f4e60845`, chiefly `Unit.cpp`'s
`CanAutoAttackTarget`, `DelayAutoAttacks`, and `UpdateMeleeAttackingState`, plus
the unable-to-react states in `UnitDefines.h`. The empty bad-facing and
out-of-range message payloads match the build-5875 `wow_messages` definitions.

Tests cover angle wrapping and the facing boundary, overlap tolerance,
off-hand-only retries, future deadline preservation, both directions of the
200 ms delay, queued ability and resource preservation, error deduplication
and reset, combat controls, dead and concealed entities, ordinary versus
extra attacks during casting, creature and pet turning, and exact packet
opcodes, payloads, and owner delivery.

On implementation commit `52cd8209`:

- Focused checks: 114 passed, one map-tagged test excluded.
- `mix test.all`: 4,531 passed, including map integration tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Native client acceptance

Fresh server on `52cd8209`, build-5875 client, Debugwarrior GUID 1 on Programmer
Isle. Native commands raised the character to 60, maximized weapon skills,
enabled god mode, and added/equipped Worn Dagger 2092 in the off hand. The owner
confirmed attack times of 2,100 ms and 1,600 ms and nonzero damage for both
weapons. Actions used native keyboard, chat, attack, and inventory input;
Tidewave only read owner state.

The character stood at `{16256.2, 16343.1, 69.44}`, two yards from Skeletal
Flayer `17379390991937510292`. Native keyboard turning changed orientation
from zero to 3.18548 radians. Starting Attack displayed the red client error
`You are facing the wrong way!`. Both ready hand deadlines retried together,
the owner retained `last_swing_error: :bad_facing`, and the target stayed at
2,980 health across two probes separated by six seconds.

A read-only sampler started before native keyboard turning back to 0.01571
radians. The first observed main-hand hit was followed by the off-hand hit
214 ms later. Subsequent swings followed the separate weapon periods, with
the shared delay applied when the two deadlines approached one another:

| Elapsed ms | Target health | Observation |
| --- | --- | --- |
| 2 | 2,980 | Facing error, no damage |
| 1,629 | 2,899 | Main hand hits; error clears |
| 1,843 | 2,880 | Off hand hits |
| 3,465 | 2,861 | Next off-hand hit |
| 3,755 | 2,774 | Next main-hand hit |
| 5,060 | 2,738 | Off-hand critical hit |
| 5,863 | 2,655 | Main-hand hit |

The client showed the corresponding combat messages and floating damage.
Its first two self-hit event timestamps were 155852.00 and 155852.28, for
81 and 19 damage respectively. The sampler and client timestamps are separate
observations; the deterministic tests assert the exact 200 ms rule.

At `{16330, 16318, 69.44}`, about 76 yards from the restored Flayer, starting
Attack displayed `You are too far away!`. The owner recorded
`:not_in_range`, both hands had matching retry deadlines, and the victim had
2,980 health. Toggling Attack off then clearing the target left auto-attack
false, target zero, pending extra attacks zero, and the remembered error nil.

No server errors or spell-validation failures appeared. The only warning
types were the existing account-data, raid-info, GM-ticket, and meeting-stone
requests during login. The helper-owned client, Xvfb, and server were stopped
after acceptance. Control combinations and creature/pet turning were covered
by automated tests, not individually reproduced in this native session.

## Local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.Q5OT6T`.
- Server log: `/tmp/thistle-melee-ready-server.log`.
- Owner probes: `/tmp/thistle-melee-ready-{equipped,facing-start,facing-wait,range,cleanup}.txt`.
- Turn sampler: `/tmp/thistle-melee-ready-turn-sample.txt`.
- Screenshots: session `screenshots/bad-facing.png`, `resumed-swings.png`, and
  `out-of-range.png`.
- Gates: `/tmp/thistle-melee-ready-{focused,all,compile,credo}.log`.
