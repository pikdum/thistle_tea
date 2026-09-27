# Pet combat participation acceptance

Gameplay commit: `ac26f3fa`, validated on 2026-09-27.

## Behavior

Pets now track combat independently of choosing a victim. Stay, Passive, and
Follow can stop attacks and preserve movement commands while hostile contact or
an incoming threat reference keeps the pet in combat. Health regeneration uses
that combat state through the existing shared regeneration rules.

`Engagement` owns the transitions. Its pure `PetCombat` component accepts contact
and incarnation-scoped threat references, then reconciles immutable observations
before regeneration. Missing, dead, evading, inactive, moved, and reincarnated
opponents are pruned. Death clears references and contact timing. Ending combat
also releases the pet's outgoing threat references.

Incoming attacks, hostile spells, periodic damage, and outgoing melee outcomes
refresh contact without selecting a victim. The short contact window covers PvP
and actions without an NPC threat reference. Repeated and stale reference messages
are idempotent. Pet flags are projected with ordinary combat flags, and charm
release removes the pet-specific flag.

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Unit::SetInCombatState`, the player/pet combat timer, and `Pet::RegenerateAll`.
These distinguish combat membership from `AttackStop` and disallow ordinary pet
health regeneration while hostile references remain.

## Initial native regression

The build-5875 client used Debughunter, level 50, and its level-49 Prairie Wolf
Alpha on map 451. All commands came through the client; Tidewave probes were
read-only. Session: `/home/pikdum/.cache/thistle-wow-playtest.HgX6Da`.

The hunter stood at `{16681.2, 16198.1, 69.44}` and sent the pet at Blackrock
Warlock, then issued Follow, Stay, Passive, and Defensive. The pet settled at
`{16679.0852, 16199.8918, 69.6445}` with victim zero and retained its incoming
reference to caster `17379391079934011414`, incarnation 65. During thirty seconds
of Fireballs its health fell from 2,138 to 1,706 without regenerating. The client
reported `Pet health 1934 combat 1`; pet metadata and its owning process both
showed combat.

The pet was then made Passive. When the hunter drew the caster's attacks, the
pet stayed at 858 health through the remaining fight despite receiving no further
damage. At sample time 30,108 ms the caster died, the pet's references emptied,
and flags changed from 530,488 to 4,152. Health rose to 1,570 at 32,431 ms and
2,138 at 37,481 ms. The client reported full health and no combat.

Logout removed pet `17383894611314868325`, including its process, position, and
metadata. Reconnect created pet `17383894611314868406` with Follow, Passive,
empty references, no victim, and no combat flags.

Evidence:

- `/tmp/thistle-pet-participation-{ranged,release,kill}.log`
- `/tmp/thistle-pet-participation-{logout-final,reconnect}.log`
- `/tmp/thistle-pet-participation-server.log`
- Screenshots `ranged-combat.png`, `recovered.png`, `logged-out.png`, and
  `reconnected.png` in the session's `screenshots` directory.

An intermediate melee run triggered a development recompilation through
Tidewave after an additional source edit. One AI tick observed the temporarily
unavailable Combat module. That run is excluded from final acceptance; its log
is `/tmp/thistle-pet-participation-final-server.log`.

## Committed-build repeat

Fresh server and client session `/home/pikdum/.cache/thistle-wow-playtest.DbjPb4`
ran commit `ac26f3fa` after the checks completed. No source changes or live
recompilation occurred during this acceptance.

| Scenario | Observed result |
| --- | --- |
| Ranged Stay | Pet `17383894611314868324` stayed at `{16673.8321, 16199.3755, 69.9789}` with victim zero. Repeated Fireballs reduced health from 2,138 to 1,616. Its combat flags and incarnation-65 threat reference remained present. The client reported `Pet health 1924 combat 1`. |
| Recovery after caster death | The same passive pet had no references or combat flags after the caster died. A recovery sample showed health 851, then 1,563 at 2,931 ms, then 2,138 at 7,981 ms. |
| Caster respawn | At 26,273 ms the same waiting pet entered combat with a new reference to incarnation 154. It retained victim zero and Passive/Stay while subsequent Fireballs reduced health. |
| Melee contact and expiry | After teleporting to the Defias pair, pet `17383894611314868392` killed the Cutpurse. The last-contact timestamp advanced from `-576460380914` at Attack to `-576460376991` on the fatal swing. Combat cleared on the scheduled tick 5,997 ms later, with victim zero and no references. The client reported full pet health and no combat. |
| Removal and reconnect | Both prior pet GUIDs lost their process, position, and metadata. The caster had empty threat and no victim or combat. Reconnect created pet `17383894611314868426` with full health, Defensive/Follow, empty references, nil last contact, and no combat flags in either state or metadata. |

The hunter used Auto Shot, Serpent Sting, and Arcane Shot to kill the caster.
Initial facing validation rejected Auto Shot until the client turned toward the
target. Two overlong read-only samplers exceeded the CLI transport timeout;
their files are excluded. The accepted samplers below completed normally.

Evidence:

- `/tmp/thistle-pet-participation-accepted-ranged.log`
- `/tmp/thistle-pet-participation-accepted-cleanup.log`
- `/tmp/thistle-pet-participation-accepted-melee.log`
- `/tmp/thistle-pet-participation-accepted-{logout,reconnect}.log`
- `/tmp/thistle-pet-participation-accepted-server.log`
- Screenshots `ranged-stay.png`, `melee-complete.png`, `logged-out.png`, and
  `reconnected.png` in the final session. `recovered.png` was captured after
  the caster respawned and shows the renewed combat state.

WoW PID 2401821 belonged to `thistle-wow-playtest.DbjPb4.service`, invocation
`b26008eeb12f4ec6a64ca04637fb1486`. Its own `amdgpu` graphics counter increased
from 2,060,200,932 to 19,022,355,376 ns. The final server log contained no gameplay
handler or AI errors and no recompilation. Warnings were the existing account
data/GM-ticket opcodes and the expected Auto Shot facing rejections.

Both helper-owned client services are inactive, both WoW processes are gone, and
all three retained server sessions exited successfully. Logs and screenshots
were retained.

## Automated verification

`mix test.all`: **7,163 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` passed. The dependency ratchet was unchanged. Regressions
cover regeneration ordering, contact without damage or retaliation, recalled
outgoing hits, reference identity and cleanup, death, observer snapshots beyond
the acquisition radius, both client flags, and charm release.

Logs: `/tmp/thistle-pet-participation-final-{all,compile,credo}.log`.
