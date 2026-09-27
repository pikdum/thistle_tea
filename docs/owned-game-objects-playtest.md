# Owned game-object acceptance

Spell effects 104–107 now use four independent object slots on their caster.
Casting another object into the same slot removes the previous object first.
Hunter traps therefore replace one another even when the old trap has not
triggered or expired. Other slots, other casters, and unslotted objects remain
independent.

`Entity.Server.GameObjectSummons` owns creation, replacement, and dismissal.
Player boundary state retains typed monitor records; creature boundary state
uses the same operations. Each object monitors its exact owner process.
Expiry clears the monitor record, while logout, world transfer, creature
corpse removal, and owner process loss remove owned objects and their linked
children. Death alone preserves them. Wild objects retain their independent
lifetimes.

Effects carry the source world, resolved position, and deferred-cooldown
receipt through explicit `EventSink.Context` delivery. A queued request from
an old world is rejected without replacing current objects. Templates come
from the existing cache, and temporary incarnations do not restart after
removal. No protocol messages or architecture allowlist entries were added.

The work also fixed logout ordering for deferred cooldowns. Dismissal obtains
the object's final cooldown event and applies it before saving the character.
An unfinished ritual cancels its cooldown; a completed ritual activates it.
The captured receipt prevents delayed events from changing a newer cast.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spells/SpellEffects.cpp:5119` (`EffectSummonObject`), and
`Objects/Unit.cpp` object ownership, death, and world-departure transitions.
The DBC slot-two examples, Battle Standard spells 22996 and 23005, are legacy
spells. Usable Battle Standard items use separate totem spells; this change
does not introduce those items' behavior.

## Native acceptance

Two isolated build-5875 GPU clients ran against implementation commit
`420ca415`: Debughunter (GUID 7, level-50 dwarf hunter) and Debugbidder
(GUID 11, level-50 human mage). The observer remained on Programmer Isle,
map 451. The trap site was near `{16303.2, 16257.1, 69.44}`, away from targets.
All gameplay mutations used native client input; Tidewave probes were
read-only. The existing seeded hunter already knew the rank-one trap spells.

- Native Immolation Trap (13795, object entry 164638) occupied slot one.
  Freezing Trap (1499, entry 2561) replaced it 23.634 seconds later, before
  its 60-second expiry. The old process stopped, its registry, position, and
  metadata disappeared, and the observer stopped tracking its GUID. The
  replacement occupied the sole slot and appeared in both clients. Nearby
  teleports on the same map preserved the object. See
  `replacement-settled.png` and `replacement-owner-settled.png`.
- The replacement expired naturally. A one-second sampler observed its
  process, position, metadata, owner slot, and observer tracking disappear
  together. Both clients showed the empty ground afterward. See
  `expired-observer.png` and `expired-owner.png`.
- A fresh Freezing Trap remained visible during the native 20-second logout
  countdown. At logout, about 23 seconds after creation, both the owner and
  object left the world; the observer lost the trap before its natural
  deadline. Reconnect created a new player owner with no summon records or
  restored traps. See `logout-countdown.png`, `logged-out-observer.png`, and
  `reconnected.png`.
- Another fresh trap was removed when the hunter transferred to Northshire
  on open map 0 at `{-8949.95, -132.493, 83.5312}`. The hunter's slot list
  became empty, and the observer on map 451 lost the object. Its process,
  registry entry, position, and metadata were absent before expiry. See
  `northshire.png` and `transferred-observer.png`.
- After returning to map 451, the hunter placed a trap and used native
  `.die`. Health fell from 2,072 to zero while the same object GUID, process,
  owner monitor, slot, position, and arming timestamp remained. Both clients
  still displayed the trap. Stopping the hunter client then removed the dead
  owner and trap, about 36 seconds after creation. The observer saw empty
  ground. See `death-retained.png`, `death-retained-observer.png`, and
  `disconnected-observer.png`.

The live log contains no errors or summon-related warnings. Existing
unsupported account-data, ticket, and meeting-stone requests were the only
warnings. Native coverage exercises hunter slot one; other slots, linked
children, multiple casters, wild-object independence, ritual outcomes, and
deferred-cooldown persistence are covered by automated tests.

## Automated checks

- `mix test.all`: 6,794 passed in 76.7 seconds.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues across 2,456 source files.
- Focused summon, ritual, cooldown, and wild-object checks: 44 passed.
- Formatting and pre-commit checks passed.

The 17 added tests cover all four slots, caster-only execution with
a foreign selected target, explicit zero coordinates, same-slot replacement,
independent slots and casters, stale monitor events, expiry, linked cleanup,
owner loss, death retention, creature corpse removal, previous-world requests,
failed creation, player and creature ownership records, logout, world transfer,
saved cooldown activation, and final ritual outcomes. Default tests use
synthetic cached templates; actual spell mappings use the DBC-tagged test.

Build and runtime used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

## Retained evidence and cleanup

Client sessions, including their `screenshots/` directories:

- Hunter: `/home/pikdum/.cache/thistle-wow-playtest.C1NHOZ`.
- Observer: `/home/pikdum/.cache/thistle-wow-playtest.AJyrvs`.

Evidence uses `/tmp/thistle-owned-objects-`: `server.log`, `initial.txt`,
`first-trap.txt`, `replaced.txt`, `replaced-cleanup.txt`, `expiry.txt`,
`before-logout.txt`, `logout-trace.txt`, `reconnected.txt`,
`before-transfer.txt`, `after-transfer.txt`, `transfer-cleanup.txt`,
`before-death.txt`, `after-death.txt`, `death-disconnect.txt`, and
`cleanup.txt`. Gate logs, launch and stop records, and GPU counters use the
same prefix.

Hunter WoW PID 1889175 used AMD DRM client 5686; its graphics counter advanced
from 1,977,219,002 ns to 21,921,917,065 ns. Observer WoW PID 1890186 used DRM
client 5714, advancing from 900,172,066 ns to 16,848,554,943 ns. Duplicate
descriptors were counted once.

The helper stopped matching service invocations
`1e2d72c10aed41e990b7d19f50208f63` and
`a1dd97f13e3c45049819e6d9b3b7b9dd`. Both units became inactive with empty
cgroups. Both players and all five observed trap GUIDs were absent from
registry, position, and metadata projections. Server PTY shutdown completed;
server PID 1888448 and both WoW PIDs were absent, and ports 4000, 3724, and
8085 were free. All evidence was retained.
