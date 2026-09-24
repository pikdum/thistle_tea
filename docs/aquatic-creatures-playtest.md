# Aquatic creature navigation

Creature habitat flags now constrain movement and proximity aggro. Animated
swimmers preserve underwater depth, pursue three-dimensional target positions,
and wander above the lakebed. Direct underwater paths require clear collision
and water throughout the segment. Ground detours remain available when their
points satisfy the creature's habitat; water-only creatures cannot travel onto
dry land. Destination height is limited to the liquid surface.

The template's water inhabit bit and swim-animation flag remain separate.
Bottom-walking creatures retain mesh navigation. Hunter and summoned pets can
use both land and water, while charmed creatures retain their original habitat.
Minimum water depth comes from the creature's scaled collision height. Existing
walk/run spline speeds and the swim-animation unit flag remain responsible for
client presentation; underwater travel does not acquire flight flags.

Failed pursuit, including a partial path, starts a victim-specific timer.
Successful routing, melee contact with line of sight, control restrictions,
victim changes, and leaving combat clear it. After more than 24 seconds of
continued failure, the normal evade transition clears combat and threat, heals,
and returns the creature home. Player-controlled companions, stationary
casters, and creatures with the no-unreachable-evade flag are exempt.

Terrain queries and path resolution stay at the owner boundary. Behavior trees
consume immutable water observations and enqueue navigation intents; the pure
unreachable-target module retains its state in the typed navigation blackboard.

Reference behavior comes from `Creature::CanWalk`, `Creature::CanSwim`,
`Creature::Update`, `Unit::IsInAccessablePlaceFor`, underwater handling in
`PathFinder`, and `Map::GetSwimRandomPosition` under `refs/vmangos/src/game/`.

## Native acceptance

Server commit `b411376a` stayed fixed throughout the run. Two isolated,
hardware-rendered build-5875 clients controlled level-50 Debugmage and
Debugbuyer. Developer commands supplied starting positions, god mode, and
Death Touch; combat and swimming actions came from the clients. Runtime probes
were read-only.

The main subject was natural Loch Frenzy spawn 8283, entry 1193, on map 0.
Its home is `{-4798.74, -3383.09, 290.05}` and its GUID during this run was
`17379390982037971035`.

- Idle samples retained `z=290.05` while the lakebed varied below it, including
  heights near 285.48 and 285.95. Both clients displayed the fish suspended
  underwater, and the owner emitted underwater spline endpoints at its
  retained depth.
- Rank-one Frostbolt dealt 21 damage, reducing health from 273 to 252. The fish
  pursued the mage from `z=290.05` to `z=293.0`, targeted the mage, and reached
  melee range without an unreachable timer. The observer saw the spell impact
  and subsequent movement.
- Ordinary swimming and forward controls took the mage onto the bank at
  approximately `{-4850.95, -3374.76, 302.37}`. The fish stopped underwater at
  `{-4835.65, -3374.98, 296.21}`. Its first failed route was recorded at
  monotonic time `-576460219415`. It remained damaged and engaged through the
  sample 24,580 ms later; by 25,081 ms it had healed to 273, cleared threat and
  target, cleared the failure timer, and begun returning home. It subsequently
  resumed wandering at its original depth.
- A second Frostbolt pull reduced health to 250. Leaving the water again
  started a failed-route timer. Backward movement into the water cleared that
  timer within roughly three seconds, and pursuit resumed without healing or
  losing the victim. Combat continued beyond the original timeout.
- Holding the pitch-down and forward controls produced a dive from about
  `z=296.15` to `z=292.30`. The fish replanned and followed to the new depth.
  The exact depth-only repath case also has deterministic behavior-tree
  coverage.
- Death Touch killed the fish underwater. Both clients displayed the body.
  The owner retained zero health, an empty movement path and threat map,
  target zero, combat false, and no failed-pursuit timer. Public metadata
  reported it dead and out of combat. Both player owners and their metadata
  subsequently reported combat false.

Artifacts remain in `thistle-wow-playtest.YlM44a` and
`thistle-wow-playtest.lLdATJ` under the local cache. Curated samples and server
logs are in `/tmp/thistle-aquatic-*.log`. Both WoW processes had matching owned
systemd cgroups, AMD DRM activity, and allocated VRAM. Both helper sessions and
the retained server were stopped after acceptance.

No entity-owner, movement, or spell failures appeared in the server log.
Existing unsupported account-data, GM-ticket, and meeting-stone requests
appeared during login and map changes. Native acceptance used open water and
did not wait for the natural spawn's respawn timer. Habitat exceptions,
rejected detours, partial paths, control restrictions, and exact timeout
boundaries are covered by automated tests.

## Validation

- `mix test.all`: 5,865 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Formatting and `git diff --check`: passed.
