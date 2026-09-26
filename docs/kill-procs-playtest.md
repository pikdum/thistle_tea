# Fatal-blow kill proc acceptance

Validated with the build-5875 client on 2026-09-26 (America/Chicago).
Implementation: `424a5dd8`.
Reference: `refs/vmangos` at `8f4e608450460efe1e38743e4da74397d4773a3a`,
particularly `Unit::DealDamage`, `Player::IsHonorOrXPTarget`,
`SpellMgr::IsSpellProcEventCanTriggeredBy`, and `UnitAuraProcHandler.cpp`.

## Behavior

Kill procs now originate at the victim's lethal health transition and reach
the entity that dealt the fatal blow. They no longer depend on the solo
experience reward callback, so group kills and player deaths use the same
path. A pet's killing blow is not redirected to its owner, and the creature's
original tap does not determine who gets the proc.

Player killers must defeat a non-gray reward target. Pets, totems,
zero-experience creatures, and creatures marked for no experience are excluded.
Reaching level 60 does not disable procs. NPC killers use the same feedback
without the player-specific reward-target restriction.

Kill events bypass school, spell-family, and hit-outcome requirements while
retaining the cast-end distinction. Kill-proc chance now includes the caster's
spell modifiers: Improved Drain Soul raises Drain Soul's zero base chance to
50% or 100%, enabling Soul Siphon. Existing aura transitions own cooldowns,
charge consumption, expiry, and channel cleanup.

The core captures a typed victim snapshot and queues `KillOutcome`; the
event sink delivers it to the owning player or mob process. No database or
world dependency was added to pure logic, and the architecture allowlist is
unchanged.

## Native acceptance

A fresh server ran the committed implementation. Two isolated hardware-rendered
clients used existing developer setup commands, ordinary casts, and normal
group/logout/release actions. Tidewave probes were read-only.

| Scenario | Client and authoritative evidence |
| --- | --- |
| Grouped fatal blow | Level-55 Debugbidder tapped a Skeletal Flayer with Fire Blast. Debugpriest killed it with Smite. The corpse retained tap player 11/group 1 and recorded killer 4. Both players gained 110 XP, but only the priest gained Spirit Tap (15271); spirit rose from 222 to 445. The mage's spirit stayed 150 and it received no proc. |
| Spirit Tap expiry | The priest's visible buff expired, spell 15271 disappeared, and spirit returned to 222. |
| Max-level PvP channel kill | Level-60 Debugwarlock channeled rank-4 Drain Soul (11675) on level-60 Debugrival, whose health was prepared with the existing `.modify hp` command. The warlock knew Improved Drain Soul rank 2 and additionally learned Spirit Tap for this acceptance check. The rival died with killer 6 while the warlock's XP stayed zero. |
| Channel-to-proc transition | Samples captured one-charge Drain Soul holders on caster and victim. After the lethal tick, the victim's temporary aura disappeared; the caster's holder was consumed, its channel field became zero, and casting became nil. The client displayed “Drain Soul fades”, “Soul Siphon”, “Spirit Tap”, and a Soul Shard reward. |
| Proc lifetime | Soul Siphon (18371) expired after 10 seconds. Spirit Tap expired after 15 seconds, restoring the warlock's spirit from 302 to 151. Neither buff nor the channel remained. |
| Release, logout, reconnect | Releasing the rival left the warlock without renewed procs. Logout removed all four used characters from entity registration, metadata, and world presence. Reconnecting the warlock restored the learned passive talents with normal spirit, no channel, and no expired proc buffs. |

The initial level-60 Flayer setup used gray targets (the level-60 gray cutoff
is 51); the positive group test therefore used level-55 characters. Max-level
proc behavior was verified with the PvP kill above.

WoW's own `amdgpu` graphics counters increased from 1,691,182,932 to
32,123,258,480 ns for PID 1367496, and from 563,495,509 to 29,380,331,220 ns
for PID 1369043. Duplicate file descriptors were not summed.

## Automated validation

`mix test.all`: **6,407 passed**. `mix compile --warnings-as-errors` and
`mix credo --strict` passed; Credo reported zero issues across 2,354 files.
Formatting and commit hooks passed.

Regressions cover single lethal transitions, corpse/nonlethal/self/environmental
damage, actual attacker versus original tap, pet attribution, player victims,
gray and excluded creatures, max-level eligibility, dead attackers, NPC procs,
typed delivery, and player-owner handling. DBC tests verify Spirit Tap's derived
stat and expiry, Remorseless Attacks and Spinal Reaper triggers, Improved Drain
Soul's two talent chances, charge consumption, expiry, and absent/canceled
channel holders. Remorseless Attacks and Spinal Reaper were not separately
exercised in the native client during this acceptance run.

## Retained evidence

- Priest/warlock client: `/home/pikdum/.cache/thistle-wow-playtest.8SUwzt`.
  Screenshots include `grouped-spirit-tap-active.png`,
  `grouped-spirit-tap-tooltip.png`, `drain-channel.png`,
  `drain-kill-procs.png`, `warlock-logged-out.png`, and
  `warlock-reconnected.png`.
- Mage/rival client: `/home/pikdum/.cache/thistle-wow-playtest.6rugkg`.
  Screenshots include `grouped-observer.png`, `drain-victim-death.png`,
  and `released-spirit.png`.
- Group evidence: `/tmp/thistle-kill-procs-group-before.log`,
  `/tmp/thistle-kill-procs-group-success.log`, and
  `/tmp/thistle-kill-procs-group-expired.log`.
- Channel and lifecycle evidence: `/tmp/thistle-kill-procs-drain-success.log`,
  `/tmp/thistle-kill-procs-drain-after.log`, `/tmp/thistle-kill-procs-release.log`,
  `/tmp/thistle-kill-procs-logout-cleanup.log`, and
  `/tmp/thistle-kill-procs-reconnect.log`.
- GPU evidence: `/tmp/thistle-kill-procs-first-gpu-before.txt`,
  `/tmp/thistle-kill-procs-second-gpu-before.txt`, and
  `/tmp/thistle-kill-procs-gpu-after.txt`.
- Server and checks: `/tmp/thistle-kill-procs-server.log`,
  `/tmp/thistle-kill-procs-all.log`, `/tmp/thistle-kill-procs-compile.log`,
  and `/tmp/thistle-kill-procs-credo.log`.

The server recorded no owner crashes, kill-proc failures, or unsupported
aura/effect errors. Existing account-data, GM-ticket, and meeting-stone
message warnings remain outside this gameplay path.

Both helper-owned client services and the retained acceptance server were
stopped. Logs and screenshots remain available locally. No push or deployment
was performed.
