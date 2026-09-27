# Selected-unit spell destinations

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell.cpp` target-map handling for targets 53 and 63, `SpellEntry.h`
target classification, and `SpellEffects.cpp` teleport and wild-summon effects.

Target 53 now resolves the selected enemy's live position and retains its
direct recipient. An additional area selector, such as target 16, controls
splash enumeration. Target 63 resolves a selected unit's position independently
of recipient selection: caster plus unit-location Blink moves the caster.
Admission checks use the shared live unit snapshot, including ownership,
world copy, visibility, targetability, hostility, range, and line of sight.
Resolution runs again at launch before costs and cooldowns are committed.

Ordinary destination teleports retain orientation and combat state through the
existing movement transition. Void Zone 28863 retains its 0.3-yard height
adjustment. Onyxia's Fireball 18392 retains its internal splash center while
omitting destination coordinates from start/go packets for its client visual.

## Native checks

Build 5875, Debugpriest on Programmer Isle, hardware-rendered isolated clients.
GM level, learning, god mode, and relocation commands prepared the cases;
spell activation used native client casts. Runtime inspection used read-only
Tidewave queries and samplers.

### Shard of the Fallen Star, 26789

Session `/home/pikdum/.cache/thistle-wow-playtest.3jsHoU`.
From `{16069.2, 16138.1, 69.44}`, select Urok Ogre Magus and cast the learned
spell. The selected Magus and the Enforcer four yards beside it took damage
in the same sampler interval, before either moved:

| Unit | Health before | Health after | Position at impact |
| --- | ---: | ---: | --- |
| Urok Ogre Magus | 10130 | 9711 | `{16043.2, 16138.1, 69.44424}` |
| Urok Enforcer | 13070 | 12645 | `{16039.2, 16138.1, 69.44424}` |

The server recorded `CMSG_CAST_SPELL` 26789 with the Magus selected. The
client showed the selected health-bar change and both mobs entering combat.
God mode was enabled, so this case makes no native cost assertion.
Evidence: `screenshots/prepared.png`, `screenshots/shard-hit.png`,
`/tmp/thistle-unit-locations-shard.log`, `/tmp/thistle-unit-locations-server.log`.
WoW PID 2128354's own DRM graphics counter increased from 3,642,638,563 ns
to 6,432,696,495 ns; the session renderer was the AMD RX 7900 XT.

The accepted final session `fTpVcd` repeated the cast from the west, with
both targets in view. `screenshots/shard-impact.png` shows the meteor and
433/437 damage numbers. The sampler independently recorded Magus health
10455 to 10022 and Enforcer health 12665 to 12228 in adjacent milliseconds,
both still at their spawn positions. See
`/tmp/thistle-unit-locations-shard-accepted.log`.

### Massive Geyser, 22421

The first session's native cast created entry 14122 exactly at the selected
Magus's coordinates, with summoner GUID 4 and a two-second death deadline.
Owner inspection later confirmed health zero and finalized death. A remaining
owner was its ordinary corpse, not a still-living summon: VMangos wild summons
use timed death followed by corpse removal, and defer death while in combat.

The final session repeated the cast from `{16017.2, 16138.1}`. Summon GUID
17379391198954782817 appeared at `{16043.2, 16138.1, 69.44424}` with health
3052, summoner 4, and no respawn timer. The sampler observed finalized death
1,989 ms after first seeing the summon. `screenshots/geyser-active.png` shows
its water effect under the selected Magus; the compact lifecycle evidence is
`/tmp/thistle-unit-locations-geyser-accepted.log`.

### NPC Blink, 28401

Learning this NPC spell on a player is insufficient acceptance: the native
client sends a self-target cast. The dev seed therefore includes a separate
Defias Evoker at `{16043.2, 16088.1}` with a victim-targeted Blink spell list.
Pull it from 26 yards away with Shadow Word: Pain to exercise normal AI,
requirements, effect delivery, teleport projection, and observer packets.

The first NPC attempt in session `2P0IMw` exposed a queued chase projection
after the teleport had cleared its spline. Encoding that empty movement path
disconnected the observing player. The movement boundary now discards stale
movement projections when the current path is empty. The regression retains
combat and teleport delivery, rejects the obsolete move packet, and preserves
the existing case where a new valid spline follows a teleport.

Fresh-server session `/home/pikdum/.cache/thistle-wow-playtest.fTpVcd`
accepted the fix. The client pulled the seeded Evoker with Shadow Word: Pain.
Its first Blink moved it from `{16043.2, 16088.1, 69.44444}` to the player's
exact `{16017.20020, 16088.09961, 68.27303}`. Mana changed from 2040 to 1965;
combat remained active with victim GUID 4 in open world 451. The player's
position remained unchanged and the connection stayed alive.
`screenshots/evoker-before.png` and `screenshots/evoker-blink.png` show the
distant NPC and its arrival on the player. State evidence is
`/tmp/thistle-unit-locations-blink-accepted.log`.

## Automated coverage

The selected-unit tests cover moving targets, absent owners, foreign copies,
dead/friendly/unselectable targets, range, summon placement, splash recipient
deduplication, failed launch without cost, caster-only teleport delivery,
triggered and object-origin casts, Void Zone height, and Fireball packet
projection. DBC coverage checks actual spell rows 22421, 26789, and 28401.

An unrelated concurrent PvP fixture collided with a store-allocated character
ID during the full suite. Its ID now uses a separate test range. Another run
overlapping playtest startup hit a script-delivery monitor timing failure;
the following quiet full-suite run passed all 6,940 tests.

After the movement fix, `mix test.all` again passed all 6,940 tests, and
`mix compile --warnings-as-errors` and `mix credo --strict` passed. Logs are
`/tmp/thistle-unit-locations-all-accepted.log`,
`/tmp/thistle-unit-locations-compile-accepted.log`, and
`/tmp/thistle-unit-locations-credo-accepted.log`. No architecture dependency
allowlist was expanded.

## Reconnect and cleanup

Native logout removed player GUID 4's owner, metadata, and world position.
The stored character had no cast, channel, combat, or script run. Native
re-entry restored Debugpriest to open world 451 at the saved playground
position, again with no active cast, channel, combat, or script run.
Evidence: `screenshots/logged-out.png` and `screenshots/reconnected.png`.

The accepted server log is `/tmp/thistle-unit-locations-accepted-server.log`.
It contains no gameplay or observer errors. The existing login warnings for
`CMSG_UPDATE_ACCOUNT_DATA` and `CMSG_GMTICKET_GETTICKET` remain unrelated to
these casts. The final WoW PID 2138212's own graphics counter increased
from 1,967,760,982 ns to 6,474,600,914 ns on the RX 7900 XT.

After its ordinary corpse period, the Geyser's owner, metadata, and world
position were all absent at a read 337,349 ms after its death deadline.
No forced corpse removal or runtime mutation was used. See
`/tmp/thistle-unit-locations-corpse-cleanup.log`; the earlier long-running CLI
watch exceeded its HTTP timeout, so this evidence is a subsequent direct read.

All three helper-owned client services were stopped with the helper. The
accepted session's service was inactive, its cgroup empty, and WoW PID
2138212 absent. Stopping that client also removed player GUID 4's owner,
metadata, and world position. Screenshots and logs were retained.
The retained server PTY exited; ports 4000, 3724, and 8085 were free.
