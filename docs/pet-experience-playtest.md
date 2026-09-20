# Hunter pet experience and level growth

Hunter pets gain experience from eligible creature kills and level up to the
owner's level, with a maximum of 60. Each level costs one quarter of the
corresponding player XP requirement. Solo rewards use the pet's level after
checking that the kill grants XP to the owner; group rewards use the owner's
unrested share. Dead pets, suspended pets, grey kills, and controlled victims
do not grant pet experience. Overflow can cross several levels and is discarded
when the pet reaches its owner-level cap.

The behavior follows `Pet::GivePetXP`, `Pet::GivePetLevel`, and
`Pet::InitStatsForLevel` in `refs/vmangos/src/game/Objects/Pet.cpp`,
`ObjectMgr::GetXPForPetLevel` in `ObjectMgr.h`, and the solo/group reward
paths in `Objects/Player.cpp` and `Group/Group.cpp`.

`World.Loader.PetLevel` preloads translated growth data at startup. The pure
`Logic.PetProgression` transition consumes that catalogue, replaces canonical
stat inputs, and runs the shared stat recomputation. Level growth restores
health and focus while preserving happiness and active auras. XP fields are
projected to the pet owner, while level and health remain visible to observers.

Taming preserves the wild creature's level. The companion relationship retains
level, XP, and learned spell IDs through dismissal, death, revival, teleport,
and reconnect. Recreating a pet does not scale it to the owner's level or
automatically teach new spell ranks. This uses the existing in-memory character
store; server restart still resets runtime state. [Loyalty progression and
training-point earnings](pet-loyalty-playtest.md) are now implemented; spending
points on trained pet abilities remains separate.

The debug Hunter starts with a level-49 Prairie Wolf Alpha at 34,800/35,300 XP,
500 XP below its next level, to make normal kill acceptance repeatable.

## Lifecycle fixes

- Pets use temporary supervisor children. Atomically stopping and snapshotting
  a suspended pet cannot restart it from its original creation arguments.
- Passive, defensive, and aggressive reaction states survive companion
  restoration and are projected correctly on the client pet bar. Live testing
  found passive pets reverting to defensive after teleport or recall.
- Suspension captures the final progress and reaction state before stopping
  the pet. Notifications from replaced pets or completed player sessions are
  ignored.
- Channel completion now delivers a periodic trigger scheduled exactly at the
  end of the channel. Tame Beast previously skipped its only tick and never
  created a pet. Cancelled or shortened channels cannot deliver that pending
  tick, and Tame Beast validates the creature and existing companion before
  starting its channel.
- Tame Beast's final tick resolves the reference core's scripted completion
  directly to ownership spell 13481 on the original creature. This avoids
  routing its caster-targeted dummy spell through an already-finished channel.
  A DBC-backed test covers the real channel and ownership effect data.
- Initial channel impact no longer executes periodic triggers immediately.
  They run only at their scheduled ticks; Tame Beast must complete the whole
  channel before ownership changes.

## Automated coverage

Tests cover partial and multi-level XP, exact thresholds, caps and resumed
growth, dead pets, solo/group rewards, active buff recomputation, owner
notifications, stale messages, suspension under supervision, retained spell
ranks and reaction state, taming level delivery, and private XP projection.
Channel regressions cover exact and delayed completion callbacks, interruption,
shortened channels, and the final tick's resource cost.

## Real-client acceptance

An isolated build-5875 client controlled Debughunter on Programmer Isle. The
progression server included both pet lifecycle fixes. Setup used developer
teleport, god mode, and level commands. Kills in this run used client casts of the
existing developer Death Touch spell; the exploratory run also earned 319 XP
from ordinary melee combat. Runtime probes only read state.

- Initial owner level 50, pet level 49, and 34,800/35,300 XP agreed between
  `GetPetExperience()` and the pet process. The first level-51 Skeletal Flayer
  awarded 319 XP, producing 35,119/35,300.
- Dismiss Pet stopped the old pet and retained 35,119 XP. Call Pet created a
  new GUID at level 49 with the same XP, spells, and passive stance. Passive
  mode also survived teleporting.
- The next kill raised the pet to level 50 and cleared overflow XP. A 100-ms
  sampler observed health change from 2,115/2,138 to 2,215/2,215, armor from
  2,963 to 3,018, and unhappy minimum damage from 31.0629375 to 31.696875.
  The client showed level 50, 0/36,875 XP, and 2,215 maximum health.
- Another Skeletal Flayer kill at the owner-level cap left XP at zero. After
  the owner was raised to 51, a Devilsaur kill granted 708 XP at pet level 50.
- Logout stored a suspended level-50 pet with 708 XP, passive stance, and
  learned spells 14919, 17260, and 24603. The old pet process was removed.
  Login restored exactly those values under a new GUID, with the client
  showing owner level 51, pet level 50, and 708/36,875 XP.

A fresh server then exercised the channel fixes. A newly created level-10
Hunter tamed a wild level-5 Stonetusk Boar. A 100-ms sampler recorded no pet
throughout the channel, followed by a level-5 pet after 20,007 ms. The client
displayed the pet portrait and action bar. The original creature process was
removed; the new pet had 102 maximum health, 126 armor, and 0/700 XP. A Skeletal
Flayer kill then granted 84 XP, with the client and both entity owners agreeing
on level 5 and 84/700 XP. The pet retained passive mode through teleport.

Cancellation and shortened-channel acceptance use the automated regressions;
the attempted live interruption checks did not establish a clean result.

The exploratory run also exercised combat death and Revive Pet: level 49 and
34,800 XP survived both. Its later live code reload produced a transient
undefined-module tick error, so that server is not the final acceptance run.

## Final checks

- `mix test.all`: 3,582 passed, including DBC, VMangos, and map integration tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.

The accepted progression and taming servers emitted no error-level logs. The
isolated clients and servers were stopped, with screenshots and logs retained.
