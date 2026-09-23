# Triggered spell hits and channel target retention

Harmful magical triggered spells now roll hit chance for each target. Previously,
only binary triggers used this path, so ordinary triggered damage bypassed the
caster's miss chance. Each trigger retains its roll through projectile travel;
its launch packet separates hit and resisted targets. Immunity and reflection
keep their existing priority when the target receives the spell.

Foreign-source periodic and scripted triggers carry the original caster's hit
inputs and resistance penetration. Family-specific hit modifiers are matched
against the child spell rather than copied from the parent's already-filtered
bonus. Owner-local triggers use the owner's current inputs. Beneficial, self,
and damage-class-0 spells bypass the magical hit roll; weapon spells retain
their attack-table path. Dead targets also bypass the magical hit roll.

The reference behavior is `SpellHitResult` and `MagicSpellHitResult` in
`refs/vmangos/src/game/Objects/SpellCaster.cpp`, plus the stored target outcome
in `Spell::AddUnitTarget` in `refs/vmangos/src/game/Spells/Spell.cpp`.

Native acceptance also exposed a final-channel-tick bug. A queued missile could
resolve after channel cleanup had cleared `channel_object`, then fall back to
the player's new selection. Channel triggers now record the original channel
target in the effect before cleanup.

## Native acceptance

Used a fresh local server and the GPU-rendered build-5875 client, with
Debugbidder on Programmer Isle. Native chat commands enabled god mode, set
level 1, restored mana, and moved to `{16285, 16343, 69.44}`. Spells and target
changes came from client input; Tidewave only sampled state and traced packets.

Rank-1 Arcane Missiles (`5143`, damage class 0) channels for three seconds and
triggers Arcane Missile (`7268`, magical damage class) once per second. The
level gap against the seeded Skeletal Flayers makes both hit and resist
outcomes practical to observe without modifying runtime randomness.

Final source validation used session
`/home/pikdum/.cache/thistle-wow-playtest.PHCyJu`:

| Check | Observed result |
| --- | --- |
| Mixed outcomes | Parent channel started; missiles hit, resisted, then hit. Each hit dealt 7 damage with 18 partially resisted. Target health changed from 2880 to 2873 to 2866. The fully resisted missile changed no health. |
| Packet agreement | Each `7268` launch had either the target in `hits` or a reason-2 miss. Impact produced the matching damage or resist packet. |
| Changed selection | During the next channel, `/target Rabbit` changed selection to GUID `17379390974120106802`. All three missiles, including the final one, retained Skeletal Flayer GUID `17379390991937510292`. All three resisted, leaving its health unchanged. |
| Cancellation | Native forward input interrupted another channel 1,697 ms after it began, following one resisted missile. No second or third missile launched. |
| Cleanup | Channel spell/object became zero and casting became nil. No more missiles appeared during the following 39 seconds. |
| Presentation | Screenshots show the channel bar, a 7-damage number, resist feedback while the rabbit is selected, and the interrupted channel. |

The first GPU session independently verified WoW's AMD graphics-engine counter
increasing from 2,161,119,857 to 3,176,866,376 ns. GPU screenshots came from
Gamescope. Both sessions were stopped through their own systemd unit and
invocation record; every PID recorded from the final session's cgroup was gone
after cleanup. The local server and read-only sampler were stopped as well.
No relevant errors appeared in the final server log.

## Regression coverage and gates

The DBC regressions cover saved nonbinary outcomes, per-target area rolls,
reflection priority, bypass classifications, family-mask filtering on foreign
triggers, retained periodic snapshots, removal cleanup, and a final channel
trigger resolved after the channel target has been cleared and selection has
changed. Existing casting tests now explicitly distinguish magical spells from
damage-class-0 spells. Binary resistance coverage includes dead-target bypass.

After the final source edit, all 4,869 tests passed with `mix test.all`.
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.

Retained local evidence:

- `/tmp/thistle-trigger-final-summary.txt` and `/tmp/thistle-trigger-final-evidence.txt`.
- `/tmp/thistle-trigger-final-server.log`.
- `/tmp/thistle-trigger-final-{tests,compile,credo}.log`.
- Final session screenshots: `changed-target.png`, `rabbit-target.png`, and `cancelled.png`.
- Initial session: `/home/pikdum/.cache/thistle-wow-playtest.okqBC7`.
- `/tmp/thistle-trigger-gpu-{before,after}.txt`.
