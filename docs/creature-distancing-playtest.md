# Creature distancing and help alarms

Script command 20 now supports movement mode 19. A creature can run to a
specified distance from another unit without changing its victim, threat, or
combat ownership. The destination includes the target's bounding radius.
Script mana thresholds and conditions remain in force.

The behavior tree proposes a navigation intent. The owner checks ground height,
target-to-destination line of sight, and a complete path before replacing the
current movement or interrupting a movement-sensitive cast. Failed validation
preserves both. Arrival releases normal spell-list casting; roots, stuns,
control takeover, victim changes, and target loss cancel the retreat. Speed
changes can replace its spline without cancelling the behavior. Death and
combat exit use the existing engagement cleanup.

Friendly calls for help also reach wandering creatures with the faction's
flee-from-help flag. An eligible recipient within ten yards of the enemy
retreats without entering combat. Initial delayed assistance still recruits
only attacking helpers. The recipient owner rechecks eligibility, and publishes
its availability through the existing metadata writer.

References include `Creature::MoveAwayFromTarget`, `MotionMaster::MoveDistance`,
`DistancingMovementGenerator`, `Creature::CanFleeFromCallForHelp`, the help grid
visitor, and the movement script command under `refs/vmangos/src/game/`.
This implementation uses a radial destination and requires a complete path;
it does not implement VMangos's alternate-angle occupied-position search.

## Bugs found during native acceptance

- Victim-rooted EventAI checks previously treated all movement immobilization
  as a root. Sleep therefore triggered root-only scripts. Owners now publish
  a separate root-aura observation, preserving stun and logout immobilization
  for movement while excluding them from this event.
- Detour's random-circle query restricts the polygons visited, but its final
  point can lie outside the circle. A Trogg with a two-yard wander radius
  reached more than eighteen yards from home. The boundary now brings an
  outlying sample inside the requested radius through a walkable mesh trace.
  The relevant Detour contract is documented in
  `refs/namigator/recastnavigation/Detour/Include/DetourNavMeshQuery.h`.

## Native acceptance

The final server build was commit `844b5a69`, including feature `0fcc7a10` and
root-event correction `083f696a`. No source edits or compilation occurred while
that server was running. Two isolated build-5875 clients used hardware rendering;
both WoW processes had the matching helper-owned systemd cgroup, AMD DRM activity,
and allocated VRAM. Inputs came from clients. Tidewave only read state.

The map-451 debug fixtures retain their template spells and EventAI scripts,
with controlled positions and thirty-second respawns:

| Creature | Entry | GUID | Home XY |
| --- | --- | --- | --- |
| Marisa du'Paige | 599 | 17379390972073288548 | 16463.2, 16398.1 |
| Rockjaw Trogg | 707 | 17379390973885227976 | 16463.2, 16468.1 |
| Burly Rockjaw Trogg | 724 | 17379390974170440649 | 16479.2, 16468.1 |

Debugmage used level 18 for Marisa, retaining trained spells, and level 50 for
the Troggs. Debugbuyer observed at level 50. Damage protection was enabled for
the final movement recording. Earlier unprotected attempts ended in ordinary
player death and corpse reclaim; Marisa's normal respawn supplied the fresh
encounter used below.

- Three client-cast Arcane Explosions dealt 196, 188, and 194 damage, leaving
  Marisa at 484/1062 health. Her real health event cast Chains of Ice (512).
  Once its root was published, script 59901 requested a twelve-yard retreat.
- The 250 ms sampler first observed the retreat at 42,387 ms and arrival at
  43,432 ms. Marisa moved from approximately `x=16463.20` to `x=16472.41`,
  about 12.208 yards from the mage including the mage's bounding radius.
  Her authoritative victim stayed player 5; casting was absent during the
  run and Fireball (9053) was already casting at the first arrival sample.
  Public position interpolation and both clients showed the changed spacing.
- Sleep was separately observed with movement immobilized, root-aura false,
  and no retreat. A prolonged encounter also reached less than twenty percent
  mana, where the script declined further retreat requests.
- A nineteen-second idle Trogg sample recorded eight distinct positions with
  a maximum horizontal radius of 1.996656 yards around its two-yard anchor.
- Curse of Weakness pulled the stationary Trogg without damaging it. As it
  passed the wandering Trogg, a help pulse started the latter's retreat at
  3,333 ms; it arrived by 3,535 ms. The destination was about 10.208 yards from
  the mage. The helper retained full health, no victim or threat entries, and
  combat false throughout. Both clients displayed it as neutral. Availability
  became false while retreating and returned on arrival.
- Death Touch killed the caller. The helper resumed ordinary wandering, with
  no retreat state and no combat entry. A later Death Touch killed the helper;
  its owner had health zero, target zero, empty threat and path, and both
  assistance availability projections false.
- Normal respawn restored both Troggs to full health and restored the wandering
  helper's alarm eligibility. Marisa reset at home with full health, no target,
  empty threat and path, and no retreat state. Both player owners and their
  metadata ended out of combat.

Deterministic tests additionally cover rejected geometry and incomplete paths,
mana thresholds, forced casts, arrival deadlines, speed retiming, root/stun/fear
cancellation, replacement movement, target loss, combat exit, death, faction
eligibility, and initial-assistance exclusion. Native acceptance used the open
debug area; obstructed retreat destinations and cancellation during movement
were covered by automated tests rather than a separate native scenario.

Artifacts remain in `thistle-wow-playtest.OrGLpn` and
`thistle-wow-playtest.wNAnTT` under the local cache. Curated samples and logs are
in `/tmp/thistle-distancing-*.log`; the fresh Marisa, pulled Trogg, wandering,
resume, and lifecycle logs contain the final acceptance evidence. Both client
sessions and retained server processes were stopped; no WoW or BEAM process
remained.

No entity-owner or movement failures appeared. An attempted cast while stunned
produced the expected validation rejection. Existing unsupported account-data,
GM-ticket, and meeting-stone requests remain visible in the log.

Validation: `mix test.all` passed 5,905 tests. Compilation with warnings as
errors, strict Credo, formatting, and the diff whitespace check passed.
