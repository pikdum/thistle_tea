# EventAI failure and retry acceptance

Validated on 2026-09-25 with the native build-5875 client. Source commits:

- `452d21e2`: local script failure results and EventAI retries.
- `ac6928ae`: target orientation in creature cast validation.
- `52d27471`: creature power and equipped-item validation rules.

## Reference and behavior

`CreatureEventAI::ProcessEvent` and `ProcessAction` in
`refs/vmangos/src/game/AI/CreatureEventAI.cpp` run action rows directly, ignoring
row delays. A terminating action stops its own remaining rows; later action
groups still execute. If any action terminates and the event carries
`EFLAG_CHECK_RESULT` (0x08), the event is re-enabled with an immediately ready
timer. This includes otherwise non-repeatable events. A chance miss still
consumes the event. The imported database has 1,035 events with this flag.

The local interpreter now retains `SCRIPT_FLAG_ABORT_ON_FAILURE` (0x08) and
returns termination when local target selection, a condition, or a normal
creature cast fails. A scheduled local failure also cancels the rest of that
invocation's delayed steps. Nested generic scripts retain independent results.
EventAI consumes the explicit result and retries on its next eligible tick or
edge without adding a second scheduling mechanism.

The cast-facing regression uses an immutable perception snapshot. It fails
before `ac6928ae` with `:not_behind` even when the target faces away, and passes
after forwarding the snapshot's orientation to shared cast validation.

The first native encounter exposed two additional blockers for Hillsbrad
Tailor's Backstab (2590): its energy cost and equipped dagger requirement.
`Spell::CheckPower` in `refs/vmangos/src/game/Spells/Spell.cpp` allows non-pet
creatures to cast non-mana spells, and mana spells when they have no base mana.
Health costs and pet power costs still apply. `Spell::CheckItems` checks creature
disarm restrictions but reserves inventory requirements for players. The
follow-up preserves shared disarm validation, power spending, player costs,
pet costs, and mana checks for creatures that have base mana.

These changes do not establish general asynchronous script cancellation.
Results from forwarded commands, triggered casts, player casts, summons, and
world-system commands still need acknowledgement before they can terminate a
caller's remaining steps. Cancellation across separate invocations of the
same script/source/target pair also remains unproven.

## Native encounter

Final acceptance used a fresh server on `52d27471` and level-50 Orc
Debugshaman, GUID 8. Setup teleported the player to
`-546 -114 46.59` on open map 0, near Hillsbrad Tailors 16326 and 16327.
Proximity started ordinary combat. No NPC state or scripts were changed.
The existing `.character level 50` command restored player health once during
the extended observation, before the successful trace below. God mode was not
enabled. Client camera controls and keyboard turning supplied the facing
changes; Trip stuns initially prevented those changes from reaching the owner.

Primary observed creature:

| Fact | Value |
| --- | --- |
| Entry / DB GUID | 2264 / 16326 |
| Runtime GUID | 17379391000006377414 |
| Position | `{-544.192, -111.727, 46.5798}` |
| Event / spell | 226401 / Backstab 2590 |
| Event repeat range | 7,000–9,000 ms |

With player orientation 0, a read-only evaluation of the same cast path
returned `:not_behind`. A 16-second owner/packet trace showed the ready timer
advancing on successive EventAI ticks and no Backstab spell-go or damage packet
from this creature. The other tailor and Trip continued ordinary combat.

The successful keyboard-turn trace recorded:

| UTC time | Observation |
| --- | --- |
| 12:50:37.487 | Player orientation 0; Backstab timer already due; health 1,938 |
| 12:50:38.330 | Native damage packet: attacker 17379391000006377414, target 8, spell 2590, damage 32, no absorption/resist/block |
| 12:50:38.337 | Owner health 1,906; orientation 4.831810474395752; cooldown has 8,343 ms remaining; no queued effects |
| 12:50:40.751 | Continued keyboard turning faces the tailor again, orientation 1.1028473377227783; the success cooldown remains unchanged |
| 12:50:47.355 onward | Cooldown expires; failed front-facing attempts return to ready timers on subsequent ticks |

The final client combat-history screenshot visibly includes a later
`Hillsbrad Tailor's Backstab hits you for 36` entry. This establishes native
combat-log rendering; the exact 32-damage hit above is established by its
packet trace and matching authoritative health delta. Indoor camera placement
obscured the creature model during part of the encounter, so the screenshots
are not used as evidence of precise facing or animation timing.

Returning to Programmer Isle removed the target and combat state from the
tailor, with no active cast or queued effects. The event timers remain stored
while out of combat; their range trigger cannot fire without combat and a
victim. Combat-entry timer reset is covered by the existing EventAI tests.

## Evidence and validation

Final session: `/home/pikdum/.cache/thistle-wow-playtest.wVUVLP`.

- `/tmp/thistle-event-retry-front.log`: owner state and `:not_behind` diagnosis.
- `/tmp/thistle-event-retry-front-sample.log`: repeated failures without a cast.
- `/tmp/thistle-event-retry-success-sample.log`: turn, damage, health, cooldown,
  and return to retries. The bounded trace removes itself in an `after` block.
- `/tmp/thistle-event-retry-reset.log`: combat and cast cleanup after leaving.
- Session screenshots: `front-facing.png`, `turning-away.png`, and
  `combat-history.png`.
- `/tmp/thistle-event-retry-final-server.log`: no error-level entries,
  unsupported commands, crashes, or spell-validation warnings during acceptance.

Final source passed `mix test.all` (6,060 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`. Validation logs use
`/tmp/thistle-creature-cost-` with `all.log`, `compile.log`, `credo.log`, and
`format.log` suffixes. The tests include local/delayed aborts, nested-script
independence, repeatable and one-shot retries, action-group independence,
random actions, chance misses, negative monotonic time, imported Goretusk
flags, orientation snapshots, and creature/player/pet cost distinctions.

WoW PID 842094 used AMDGPU `0000:0c:00.0`; its graphics counter advanced from
1,267,371,776 to 9,256,023,848 ns. Counter samples are
`/tmp/thistle-event-retry-final-gpu-{before,after}.log`.

The earlier diagnosis session was `thistle-wow-playtest.y73z6F`. A subsequent
launch, `thistle-wow-playtest.EoCVlD`, timed out before a visible game window;
its owned service was stopped before the successful final launch. No source
was edited while either acceptance server was running. No push was performed.

Native logout removed player owner 8 and left no players in open map 0 or
Programmer Isle (`/tmp/thistle-event-retry-cleanup.log`). Both acceptance
servers exited, and all three helper-owned client services were stopped.
Their logs and screenshots were retained.
