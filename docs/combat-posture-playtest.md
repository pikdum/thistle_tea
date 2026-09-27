# Combat posture and critical procs

Implemented in `837d4f0b` and tested on 2026-09-27 with the native build-5875
client, Debugwarrior (GUID 1, level 50), and a fresh local server.

## Rules and ownership

Forced critical white attacks against a seated player retain their critical
damage and client combat result, but cannot trigger the victim's critical-hit
talents. Attacker procs and other incoming result flags, including absorption,
remain available. Physical spell abilities retain their critical-hit proc
eligibility, including when posture forces the critical result. Abilities
marked unable to crit respect that restriction, and ordinary magic spells do
not gain a seated-target critical bonus.

Direct damage stands a living, unmounted player through the existing pure
posture transition. That transition removes sitting-only auras and emits the
typed stand-state effect. Periodic damage and mounted players keep their
posture. The incoming attack snapshots posture before damage so standing up
does not accidentally restore critical proc eligibility. Damage reads current
health after posture-related aura removal, avoiding stale health restoration.
Environmental damage reuses the same posture transition.

The reference is VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`:
`Unit::ProcDamageAndSpell` suppresses seated white-attack critical procs for
builds after 1.7.1, `Unit::DealDamage` stands unmounted players on non-periodic
damage, and `Unit::GetSpellCritChance` gives physical abilities their seated
critical bonus. `SpellCaster::RollMeleeOutcomeAgainst` places the forced
critical result after miss/mechanic resistance and before avoidance.

## Automated acceptance

All **7,265 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo found zero issues across 2,565 source files.

Eleven new regressions cover seated and standing critical proc eligibility,
attacker feedback, preserved absorb flags, defensive charges/cooldowns,
sit/sleep/chair/kneel transitions, sitting-only aura removal, periodic and
mounted exclusions, immunity, godmode, creature/dead poses, ability attack-table
precedence, zero-base-critical physical abilities, and cannot-crit rules.
Full spell-effect paths verify melee/ranged ability damage and defensive procs;
magic remains unaffected by posture.

## Native seated acceptance

The warrior learned rank-five Enrage (13048) and rank-three Blood Craze (16492)
through existing `.learn` commands. Both inherited their critical-only proc
rule (`proc_ex = 2`), confirmed on the live owner. Godmode remained disabled.

The character waited seated approximately 25 yards east of the seeded level-48
Land Walker (5357) on map 451. The existing `.move` command brought the selected
creature to the player; normal creature AI started combat. A read-only owner
sampler ran every 25 ms before movement began.

| Relative time | Authoritative result |
| --- | --- |
| 1 ms | Health 2,729; seated; neither talent buff present |
| 7,102 ms | Combat starts; still seated |
| 8,113 ms | Health becomes 2,591; standing; neither talent buff present |
| 10,699 ms | Next ordinary hit leaves 2,504 health |
| 12,947 ms | Retreat clears combat |

The native combat message at 316658.66 seconds reported a **138-point critical
hit**. The next hit dealt 87 damage. Enrage and Blood Craze remained absent
throughout the sampled sequence. Health regenerated fully after retreat.

## Native standing control

Defense was temporarily lowered with `.debug skill 95 1` to increase the chance
of a natural critical hit. This also produced crushing blows and ordinary
Defense skill gains. The warrior remained standing, with godmode disabled.
`.modify hp 99999` restored health between sampling windows, clamped to the
unchanged 2,729 maximum. No player attacks were started.

The accepted control sample captured a new critical hit after the preceding
Enrage had expired:

| Relative time | Authoritative result |
| --- | --- |
| 2,235 ms | Prior Enrage expires; neither talent buff present |
| 5,853 ms | Critical hit deals 142; Enrage and Blood Craze both appear |
| 7,851 ms | Blood Craze restores 27 health |
| 9,852 ms | Blood Craze restores another 27 health |
| 11,868 ms | Final 27-point heal; Blood Craze expires |
| 17,845 ms | Enrage expires |
| 20,161 ms | Retreat clears combat; both buffs remain absent |

The client log at 316910.81 seconds reported the critical hit, followed by
both buff gains at 316910.84. Subsequent native messages displayed all three
27-point heals. The screenshot captured Blood Craze fading and Enrage's
remaining duration. A larger native chat frame retained the critical result,
both gains, and healing messages together after retreat. The two durations
were approximately six and twelve seconds. Known skills were restored with
`.debug skills` before logout.

## Cleanup and rendering

After retreat the owner was standing, fully healed, out of combat, and without
either temporary talent buff. Normal logout returned to character selection
and removed the owner, world position, and metadata. Stored character state
retained standing posture, no combat, and neither temporary buff. The owned
client service and retained server were stopped.

WoW PID 2520383's own amdgpu graphics counter advanced from 2,199,637,592 to
16,277,901,905 ns. No server errors occurred. Warnings were the existing
unimplemented account-data updates and GM-ticket query.

## Retained local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.LuYRyR`.
- Screenshots: `screenshots/seated-ready.png`, `screenshots/seated-hit.png`,
  `screenshots/standing-accepted.png`, `screenshots/standing-combat-log.png`,
  and `screenshots/logged-out.png`.
- Owner samples: `/tmp/thistle-combat-posture-seated-sample.log` and
  `/tmp/thistle-combat-posture-standing-accepted-sample.log`.
- Setup and cleanup: `/tmp/thistle-combat-posture-native-before.log`,
  `/tmp/thistle-combat-posture-retreated.log`, and
  `/tmp/thistle-combat-posture-logout.log`.
- Server, warning audit, GPU proof, and final gates:
  `/tmp/thistle-combat-posture-{server,warnings,gpu-before,gpu-after,all,compile,credo}.log`.
