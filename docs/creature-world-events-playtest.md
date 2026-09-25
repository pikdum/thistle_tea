# World-event creature variants

## Implementation

`fafc75ce` adds `game_event_creature_data` support through cached definitions
and a pure `CreatureEvent` transition. Boot loading selects the latest supported
patch independently for each spawn and event; the current database supplies
576 records. Entry, display, equipment, and event start/end spells share the
existing creature-entry and typed-effect pipelines.

Each creature owner subscribes to its relevant event topics and reconciles
against the event manager's published cache. Publication precedes spawn-pool
refresh, allowing newly started owners to read current activity without calling
back into the manager that is starting them. Existing copies update in place;
initialization and respawn use the same transition. The lowest active event ID
wins when multiple definitions apply. Repeated notifications do not reroll an
unchanged variant.

The original archetype remains the restoration source. Entry changes retain
identity, resource proportions, engagement, loot sessions, and spawn lifecycle.
Equipment resets use the current archetype, active transforms are reapplied,
and removing an event restores an empty original spell list when appropriate.
Start/end spells remove the opposite aura and emit triggered casts. No
architecture dependency allowlist was expanded.

Native acceptance exposed two additional bugs, both fixed before the final run:

- `32039438`: `.debug events` passed options to the pattern argument of
  `String.split/2`, disconnecting the player. Command-path coverage now exercises
  status, start/stop parsing, unknown IDs, and malformed input.
- `8eea3412`: creature initialization omitted the weapon-drawn state and used
  database extra flags as client aura-display flags. Creatures now publish the
  reference melee stance and aura flag. Empty equipment explicitly publishes
  zero fields so entry changes can clear previous weapons.

The event command accepts `.debug events [start|stop <id>]`. Manual changes last
until the next scheduled transition and preserve unrelated active events.

References: `refs/vmangos/src/game/GameEventMgr.cpp` creature-data loading and
update workers; `refs/vmangos/src/game/Objects/Creature.cpp` `UpdateEntry`,
`ApplyGameEventSpells`, display/equipment selection, and default weapon stance;
`refs/vmangos/src/game/Objects/UnitDefines.h` client aura flags.

## Automated validation

All source checks passed on `8eea3412` before the final client/server launch:

- `mix test.all`: 6,022 passed, including database and map integration.
- `mix compile --warnings-as-errors`.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted` and commit hooks.

Coverage includes two simultaneous live copies, stable owner identity and
client fields, initial activity, respawn, start/end auras, overlapping event
selection, patch selection, resource preservation, corpse safety, equipment
restoration after an expired transform, exact spell-list restoration, and
event-cache publication ordering. Logs are
`/tmp/thistle-creature-events-{all,compile,credo,format}.log`.

One earlier full run exceeded an existing cell-activation test's 100 ms receive
deadline while compiler and lint jobs were competing for CPU. The subsequent
full runs completed without competing compiler jobs and passed. An unrelated
unused Alterac Valley test binding was cleaned up in `b6ef9b7a`.

## Native acceptance, September 25

The final server used `8eea3412` with an isolated build-5875 client, Debugmage
(GUID 5, level 50), and god mode. Chat commands changed event activity and
position; native targeting, casts, and loot clicks exercised gameplay.
Tidewave probes were read-only. No source changed during the final run.

### Night patrol equipment

At `-8530.34 691.554 97.6074` on map 0, event 27 changed Stormwind City Patroller
DB GUID 12088 from its normal weapon to the night weapon. The corrected client
visibly held the event weapon. Stopping the event restored the original
equipment. GUID 17379390995174534968, owner `#PID<0.3047.0>`, incarnation 105,
health 5228/5228, entry 1976, and aura 18950 remained unchanged. The packed
equipment projection changed from 196845206019488157277499 to 8933531983140
and back.

### Festival form and spell

Event 34 was activated before visiting Booty Bay at
`-14439 432.395 20.5088` on map 0. DB GUID 76 loaded as Drunken Bruiser, entry
15724, display 7104, with sleep aura 26115. The client showed the sleeping
creature, its changed name, and the sleep visual.

Stopping the event restored Booty Bay Bruiser, entry 4624, display 7102, and
its original aura 18950. The client visibly woke it. Restarting the event put
the same actor back to sleep. GUID 17379391039600590924, owner
`#PID<0.5850.0>`, incarnation 591, and health 5568/5568 remained stable.

### Pyrewood death, loot, and natural respawn

Event 49 was active before visiting `-381.301 1648 17.7911` on map 0. DB GUID
57461 loaded as Moonrage Watcher, entry 1892, display 574, with health 900/900.
The client showed the wolf form. Native Fireball, Fire Blast, and Scorch killed
it. At 11:14:41.667 UTC, the owner reported health zero, finalized death, and
421,978 ms remaining on its naturally selected 424,000 ms respawn timer.

Stopping the event changed the corpse to the human Pyrewood Watcher without
reviving it. Restarting restored its night form while it remained dead. The
original owner `#PID<0.6441.0>`, GUID 17379390993748516981, and incarnation 679
remained intact during these changes. The corpse retained player 5's tap and
loot session. Native icon clicks collected three Linen Cloth and 30 copper;
the client displayed both loot messages, inventory contained three Linen Cloth,
coinage was 100000030, and the corpse's loot session cleared.

The client stayed nearby for the real respawn timer. At 11:20:59.975 UTC the
creature was still dead with 43,670 ms remaining. By 11:22:07.891 UTC it had
respawned naturally as a full-health Moonrage Watcher, with the same GUID,
new owner `#PID<0.7448.0>`, and incarnation 947. The previous owner was dead;
tap and loot session were absent. Fresh proximity combat with the nearby Mage
had already begun, with zero initial threat. The sampler began after respawn,
so this establishes the before/after lifecycle, not the exact first live tick.

Stopping event 49 after respawn restored the living human watcher, entry 1891,
display 2565, health 819/819, and original equipment. An earlier run also
observed the scheduled 11:00 UTC transition override temporary event activity.

## Evidence and cleanup

Final session: `/home/pikdum/.cache/thistle-wow-playtest.FBIYHQ`.
Screenshots include `patrol-day`, `patrol-night`, `patrol-restored`,
`festival-asleep`, `festival-awake`, `pyrewood-night`, `pyrewood-dead`,
`pyrewood-loot`, `pyrewood-looted`, `pyrewood-respawned`, and `pyrewood-restored`.

The final server log is `/tmp/thistle-creature-events-accepted-server.log`.
Runtime evidence uses `/tmp/thistle-creature-events-` with suffixes
`accepted-patrol-{day,night,restored}.log`, `festival-{start,restored,restarted}.log`,
`accepted-pyrewood-{start,damage,death}.log`, `accepted-corpse-restored.log`,
`respawn-timer.log`, `respawn-transition.log`, `post-respawn-restored.log`,
`corpse-loot.log`, `loot-collected.log`, `inventory.log`, `owner-cleanup.log`,
and `client-cleanup.log`. The sampler's `last_dead` key contains an already-live
sample; its timestamps and health values above are the applicable evidence.

WoW's own AMDGPU graphics counter advanced from 756,120,466 to 29,517,592,409 ns
on device `0000:0c:00.0`; samples are `accepted-gpu.log` and
`accepted-gpu-end.log` under the same `/tmp/thistle-creature-events-` prefix.

The final server had no error-level entries or spell-validation failures.
Existing debug-level unsupported `swap-initial-targets` messages for script
1569406 appeared in the visited world content; fireworks scripting was not
validated by these creature-variant checks. This is not whole-holiday or vanilla
parity acceptance.

The final client and both earlier clients were stopped through their exact
helper-owned services. All three retained server PTYs exited. After final
client shutdown, the player owner was absent and both map 0 and Programmer Isle
had no players. Artifacts remain local. Nothing was pushed.
