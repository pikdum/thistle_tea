# Creature flight and continuous patrols

Creatures retain their template's air inhabit flag through loading, entry
changes, and respawn. Flight-capable wild creatures preserve altitude during
movement and use a direct three-dimensional path when collision checks allow
it. Blocked paths require a collision-safe detour. Hunter and summoned pets use
ground navigation even when their original creature template can fly.

Flying random movement follows a continuous circle at the spawn altitude.
Movement type 3 follows the complete authored waypoint loop without stopping
at each point. Both behaviors enqueue navigation intents through the shared
resolver and yield to combat, control effects, and ordinary lifecycle changes.
The existing waypoint behavior remains responsible for routes with per-point
waits and scripts.

Airborne deaths start a falling spline toward the highest surface below the
corpse. Authoritative interpolation and public position projection use the same
acceleration and terminal velocity. Landing clears movement scheduling; respawn
restores the original position and flight capability. Movement cleanup retains
independent hover, root, and walking flags.

Reference behavior comes from `Creature::CanFly`, `Unit::SetFly`, creature
death handling, `RandomMovementGenerator`, `CyclicMovementGenerator`,
`PathFinder`, and spline fall utilities under `refs/vmangos/src/game/`.

## Channel completion regression

Native taming exposed a separate completion bug: shared upkeep expired the
caster's Tame Beast aura before advancing the channel. Aura reconciliation
treated that normal expiry as cancellation and discarded the final ownership
tick. Reconciliation now receives the removal cause and permits natural expiry
at the channel's deadline. An earlier aura expiry, explicit removal, or other
interruption still cancels the channel, even when upkeep runs late.

The regression test first reproduced the failure through `BehaviorRunner`.
Coverage includes exact and late completion, early expiry with a late callback,
explicit removal at the deadline, and the existing cancellation, resource-cost,
and shortened-channel cases. Cannibalize's expiry test also advances the channel
after aura upkeep, matching the owner scheduling order.

## Native acceptance

Isolated hardware-rendered build-5875 clients controlled Debughunter and
Debugbuyer. The server code stayed fixed throughout each run. Developer commands
set up position, level, and god mode; combat, casts, and pet actions came from
the client. Runtime inspection was read-only.

The first server, at `c0de5920`, established:

- The seeded Highperch Soarer completed repeated 20-point circles at
  `z = 87.5061`, with 7,821 ms splines and both players observing it. Captures
  from the second client showed the creature airborne at successive positions.
- Death Touch killed the Bloodseeker Bat at `z = 87.4444`. A 50 ms sampler
  recorded the falling corpse descending to `z = 69.4444` in approximately
  1.37 seconds. Both clients saw the landed body. The landed owner had no
  movement deadline or active AI timer and its public position was stationary.
- After the 30-second respawn, the bat had full health at its original airborne
  position and its flight flags were restored.
- Frostbolt made the bat descend to the hunter and enter melee range. Moving
  away caused a reset; the bat returned to full health at its airborne home.
- Tame Beast visibly channeled for 20 seconds but failed to create a pet,
  leading to the channel regression above. A copied-state diagnostic showed
  aura expiry clearing the channel before its completion tick.

Artifacts for that run remain in the `thistle-wow-playtest.f4SdHe` and
`thistle-wow-playtest.XgonVj` directories under the local cache, with sampled
state in `/tmp/thistle-flight-*.log`.

A fresh server at `16f21c4f` then verified the fix and remaining lifecycle cases:

- Tame Beast maintained channel 1515 with no pet for the full 20 seconds.
  The next 100 ms sample showed channel zero and a new level-60 hunter pet
  (entry 11368), positioned at ground height with movement flags zero. The
  original wild creature process was gone. The client displayed the pet
  portrait, action bar, and ownership tooltip.
- Holding the forward key moved the hunter approximately 28 yards. The bat
  followed at ground height (`z = 69.4400–69.4444`) using ground movement flags
  `0x00400001`, then stopped with flags zero. Its model's wing animation remains
  visible, but its navigation has no flight capability.
- Logout removed the pet process. Login restored a new pet GUID with the same
  entry, level 60, passive stance, ground position, and no flight flags. The
  client again displayed its pet portrait and action bar.
- At the natural Highperch Soarer spawn 21707 on map 1, the owner retained
  movement type 3 and its 11 authored waypoints. The movement spline contained
  all 11 points plus the closing point, with flight spline flag `0x200` and
  authored heights from approximately 50.7 to 72.5 yards. Both clients saw it
  airborne; the hunter arrived while the first loop was still running.
- A 100 ms sampler captured spline 1 changing to spline 2 at the loop boundary,
  with movement active in every sample. The repeated loop lasted 185,638 ms;
  its first loop took 188,554 ms because it also started at the spawn position.
  Subsequent samples advanced along the second loop.

The final sessions are `thistle-wow-playtest.1Y2sZI` and
`thistle-wow-playtest.MuFXLA`. Their WoW processes had matching owned systemd
cgroups and active AMD GPU counters. Both sessions and the retained server were
stopped after acceptance. No entity-owner, movement, or spell failures appeared
in the final server log. Existing unsupported account-data, GM-ticket, and
meeting-stone requests still appeared during login and map changes.

## Validation

- `mix test.all`: 5,850 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: no issues.
- Formatting and `git diff --check`: passed.

Automated movement coverage includes blocked flight paths, closed loops,
combat interruption, entry changes, pet grounding, respawn, fall duration and
interpolation, public position projection, and corpse landing cleanup. Collision
detours and explicit early channel interruption use automated coverage rather
than a claimed native acceptance result.
