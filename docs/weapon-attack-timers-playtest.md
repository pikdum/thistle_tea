# Combat weapon attack timers

Implemented in `62c5f25e` and tested on 2026-09-27 with the native build-5875
client, Debughunter (GUID 7, level 50), and a fresh local server.

## Rules and ownership

Changing a usable weapon during combat restarts that hand's full attack period.
Mainhand, offhand, and ranged timers are independent. The reset uses the new
weapon's derived speed, including haste. Mainhand removal starts the unarmed
period; changing between broken and usable equipment also resets the affected
timer. Feral forms and disarmed mainhands retain their natural attack timing.
Peaceful changes, unchanged equipment, non-weapon changes, and dead characters
do not reset attack timers.

Ordinary haste and slow changes preserve an in-progress swing's deadline. The
new speed applies when the next period starts. This follows VMangos
`8f4e608450460efe1e38743e4da74397d4773a3a`: `Player::_ApplyItemBonuses` resets
combat weapon timers for builds after 1.6.1, while
`Unit::ApplyAttackTimePercentMod` leaves the running timer untouched.

The pure `AttackTimers` transition compares the old and new character snapshots
after the shared inventory commit resynchronizes equipment. It needs no item
store lookup, including when the old item has already been destroyed. Existing
Blackboard deadlines remain the melee timer owner. Ranged resets update both
the retained timer and active Auto Shot state, invalidating an older queued
launch before it can consume ammunition. Equipment resets request the normal
player projection so tick scheduling observes an earlier new deadline.
Spell launch swing resets reuse the same mainhand/offhand helper.

## Automated acceptance

All **7,254 tests** passed, including database/map integration tests and the
architecture dependency ratchet. Compilation with warnings as errors passed;
strict Credo found zero issues across 2,564 source files.

Regressions cover individual hands, another instance of the same weapon,
negative monotonic times, haste, two-handed replacement, unarmed timing,
broken/repair transitions, feral and disarm exclusions, stop/start behavior,
ordinary aura speed changes, and both inventory commit forms. A behavior-tree
test proves damage cannot be delivered before the restarted melee deadline.
A boundary test proves an old ranged launch consumes no ammunition, while a
fresh launch at the new deadline consumes one arrow and schedules the next
period.

## Native melee acceptance

The hunter used `.tgm`, kept its pet passive, and attacked the seeded Blackrock
Warlock near `{16653.2, 16198.1}` on map 451. Staves and Daggers were learned
through existing GM commands. Bent Staff (35, 2,900-ms delay) was obtained
through `.additem` and equipped using the native backpack cursor.

The first run was facing the wrong way; it established the inventory/timer
change but was excluded from damage acceptance. After correcting facing to
approximately 3.21 radians, the accepted 25-ms owner sampler recorded:

| Relative time | Authoritative result |
| --- | --- |
| 4,342 ms | Barman Shanker swing schedules its next attack at `-576460269407` |
| 5,390 ms | Bent Staff replaces it; the new deadline is `-576460267450` |
| 8,298 ms | First staff swing executes after the restarted deadline |
| 11,190 ms | Next staff swing reduces target health from 2,631 to 2,624 |
| 14,108 ms | Following swing executes at the staff cadence |

The swap was first observed 18 ms after its 2,900-ms timer started. The first
staff swing dealt no damage; the next dealt a 7-point glancing hit. With the
newly learned weapon skill, the client showed misses and glancing damage.
Native combat messages showed successive results at 315059.28, 315062.20,
and 315065.10 seconds, and
the client reported a 2.9-second attack period. The offhand deadline remained
unchanged in this accepted mainhand-only swap. The earlier two-handed equip
also stowed the original offhand and reset its timer, matching automated
coverage.

## Native ranged acceptance

At roughly 30 yards, the hunter started Auto Shot with Bow of Searing Arrows
(2825, 2,700-ms base delay) and swapped to Short Ash Bow (3039, 1,900-ms base
delay). Both bows' bind confirmations were completed before the accepted run.
The existing 10% quiver bonus produced derived periods of 2,454 and 1,727 ms.

| Relative time | Authoritative result |
| --- | --- |
| 5,555 ms | Original bow launches; 170 arrows remain, next deadline `-576459926735` |
| 6,665 ms | New bow equips; both ranged deadlines become `-576459926357` |
| 8,388 ms | First new-bow launch consumes one arrow after the reset deadline |
| 9,154 ms | Projectile lands for 74 damage; target health becomes 2,282 |
| 10,119 ms | Next shot launches and consumes one arrow |
| 10,886 ms | Projectile lands for 75 damage |

The first swap observation was 26 ms after its full 1,727-ms timer started.
No ammunition was consumed between the swap and its new deadline. Mainhand
and offhand deadlines remained unchanged. Later launch intervals were roughly
1,729 ms, with one arrow consumed per launch. Native combat messages showed
the new bow's damage and cadence, and `UnitRangedDamage` displayed 1.727 seconds.
The screenshot also shows the bow firing and the target losing health.
Queued-launch invalidation is covered deterministically by the boundary test;
the native sample establishes the actual inventory, timer, ammunition, and
projectile paths.

## Cleanup and rendering

After retreat, the owner had no combat, melee auto attack, or Auto Shot state.
Normal logout removed the owner process, world position, and metadata; stored
character state also had no combat or active attacks. The client returned to
character selection. The helper-owned client and retained server were stopped.

WoW PID 2505092's own amdgpu graphics counter advanced from 2,915,557,475 to
26,431,806,245 ns. No server errors occurred. Warnings were the existing
unimplemented account-data updates and GM-ticket query.

## Retained local evidence

- Session: `/home/pikdum/.cache/thistle-wow-playtest.AhkJ7S`.
- Screenshots: `screenshots/melee-accepted.png`, `screenshots/ranged-completed.png`,
  and `screenshots/logged-out.png`.
- Melee owner samples: `/tmp/thistle-weapon-timers-melee-accepted-sample.log`.
- Ranged owner samples: `/tmp/thistle-weapon-timers-ranged-completed-sample.log`.
- Cleanup: `/tmp/thistle-weapon-timers-retreated.log` and
  `/tmp/thistle-weapon-timers-logout.log`.
- Server, warning audit, GPU proof, and final gates:
  `/tmp/thistle-weapon-timers-{server,warnings,gpu-before,gpu-after,all,compile,credo}.log`.
