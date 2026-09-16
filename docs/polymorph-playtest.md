# Polymorph player targeting and expiry

Polymorph's creature mask was rejecting players because their metadata lacked
`creature_type`. Both cast validation and target resolution read that field.
Player presence now publishes the type from the current character snapshot on
entry, synchronization, and movement. Normal players are humanoid (including
Undead players); animal shapeshifts publish beast. Returning to normal form
restores humanoid without retaining an outdated metadata value.

The mapping follows the local build-5875 `ChrRaces` and `SpellShapeshiftForm`
data and VMangos `Unit::GetCreatureType`: positive form types override the race
type, while zero/negative form types fall back to humanoid. All playable races
in this client use humanoid. Polymorph ranks use mask `0xC1`, accepting beasts,
humanoids, and critters. Other spell masks continue to reject incompatible types.

A second bug allowed Ghost Wolf's model to overwrite Polymorph's sheep model.
Aura display recomputation now starts from the native display, applies the
shapeshift display, then applies the transform. Removing Polymorph restores the
active shapeshift; removing that form restores the native model. This matches
VMangos `Aura::HandleAuraTransform` and its restoration of active shapeshifts.
Druid forms retain their existing mechanic-17 immunity from the spell data;
Ghost Wolf has no such immunity.

Regression tests exercise published metadata through both cast validation and
target resolution, preserve incompatible-mask rejection, check form changes,
verify Ghost Wolf/sheep/native display restoration, and verify Cat Form rejects
Polymorph without consuming a diminishing-returns step.

The first duel exposed another lifecycle bug: refreshing a 40-second Polymorph
to 20 and then 10 seconds updated the holder, but retained the player's original
40-second tick timer. The debuff reached zero while the victim remained confused.
`Player.TickScheduler` now compares the existing timer with the current tick
policy and brings it forward for earlier deadlines. It preserves earlier wakes
and already-delivered ticks. Regression tests cover shortened aura expiry,
regeneration becoming due, and idle-to-active scheduling.

## Real-client acceptance

Used two isolated build-5875 clients with level-50 Debugmage (GUID 5) and
Debugshaman (GUID 8) in a duel on Programmer Isle. All actions originated in
the clients. A read-only sampler recorded the shaman's aura holders, diminishing
history, display, form, and published creature type every 100 ms.

1. Cast Polymorph four times from the mage. The shaman displayed the sheep
   model and debuff; the fourth cast displayed `Immune` on the mage's client.
2. Wait for the shortened third aura to expire, then cast Ghost Wolf from the
   shaman. The cast succeeds, proving the victim is no longer confused.
3. After diminishing recovery, cast Polymorph on Ghost Wolf. The sheep model
   overrides the wolf while the underlying form remains active.
4. Cast Fire Blast from the mage. Damage breaks Polymorph and restores the
   wolf, including its portrait on both clients.
5. Cancel Ghost Wolf. The native display and humanoid creature type return.

The repeat duel with the scheduler fix recorded:

| Application | Applied at | Expires at | Duration |
| --- | ---: | ---: | ---: |
| First | -576460486149 | -576460446149 | 40,000 ms |
| Second | -576460479584 | -576460459584 | 20,000 ms |
| Third | -576460474588 | -576460464588 | 10,000 ms |
| Fourth | — | — | Immune |

The third aura actually left at `-576460464526`, 62 ms after its deadline,
with recovery scheduled for `-576460449526`. The sampler saw the restored
native display 10 ms later. This is materially different from the initial
run, which retained the victim until the original 40-second timer fired.

After recovery, Polymorph applied for the full 40 seconds to Ghost Wolf at
`-576460440418`. The owner retained form 16 and beast type 1 while displaying
sheep model 856. Fire Blast removed the aura at `-576460431203` and restored
wolf display 4613. Cancelling the form later restored native display 52,
form 0, and humanoid type 7.

No owner, movement, or projection errors appeared during the repeat sequence.
Login emitted existing unsupported account-data, raid-info, GM-ticket, time,
and meeting-stone requests. The earlier run also confirmed that attempting
Ghost Wolf while Polymorphed is rejected as `confused`.

Evidence retained locally:

- `/home/pikdum/.cache/thistle-wow-playtest.o91EAI/screenshots/fixed-sheep-first.png`
- `/home/pikdum/.cache/thistle-wow-playtest.j07VWt/screenshots/fixed-sheep-immunity.png`
- `/home/pikdum/.cache/thistle-wow-playtest.o91EAI/screenshots/wolf-polymorphed.png`
- `/home/pikdum/.cache/thistle-wow-playtest.o91EAI/screenshots/wolf-restored-after-damage.png`
- `/home/pikdum/.cache/thistle-wow-playtest.j07VWt/screenshots/wolf-restored-visible.png`
- `/tmp/thistle-polymorph-fixed-observer.log`
- `/tmp/thistle-polymorph-fixed-server.log`

## Final validation

`mix test.all --seed 287354` passed all 2,842 tests. Strict Credo reported zero
issues, compilation with warnings treated as errors passed, and formatting and
diff checks passed. Both clients, their private X servers, and the game server
were stopped.

An initial concurrent run was stopped after game-event timing and database
timeouts while the clients and server startup were also active. The first
isolated run passed 2,841 tests but failed the existing cell-activator sweep
test because its first deactivation message contained only neighboring cells.
The identical seed passed on rerun without code changes. These intermittent
validation failures are separate from the Polymorph regressions covered here.
