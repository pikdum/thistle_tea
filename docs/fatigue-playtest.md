# Ocean fatigue

Deep ocean starts a 60-second Fatigue bar. Coastal water restores the reserve
at ten times the drain rate; returning offshore retains any partial recovery.
Leaving water clears it. Expiration deals one-fifth of maximum health plus a
roll from zero to level minus one, then repeats every two seconds. Late ticks
apply one pulse rather than accumulated damage. Stationary players keep ticking.

God mode, taxi flights, attached transports, Spirit of Redemption, and unreleased
bodies stop fatigue. Water Breathing does not protect against it. Ghosts retain
the countdown but return to the appropriate graveyard on expiration without
losing health. Rescue rechecks ghost state at the owner boundary, so a stale
request cannot relocate a resurrected player.

## Terrain data

The pinned MaNGOS Zero extractor produces build-5875 `MAPSz1.5` tiles. New map
bakes include them. Existing installations can generate just the terrain data:

```sh
nix run .#terrain-data -- "$WOW_DIR" ./maps/terrain
```

Restart the server afterward. The local extraction completed all 2,429 tiles:
1,421 contained liquid and 1,008 were dry. Wet tiles are loaded into ETS at boot;
gameplay performs no file or database queries. Namigator continues to own
navigation. Missing terrain data produces a startup warning and disables
fatigue in the uncovered locations.

The pure decoder validates sections and samples liquid flags, cropped surface
grids, terrain holes, and all four terrain triangles in float, 16-bit, or 8-bit
height encodings. MaNGOS area values are exploration bits; a cached DBC mapping
resolves them to area IDs. Graveyard selection uses that mapping when Namigator
has no area information offshore.

The player behavior tree receives liquid data through its immutable context.
Pure fatigue logic emits typed mirror timer, environmental damage, and rescue
effects. Health loss and death use the existing environmental damage lifecycle;
rescue uses the existing corpse travel boundary. No architecture allowlist
entries were added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`, `Player.cpp`
(`UpdateMirrorTimers`, environmental flags, expiration pulses), `MirrorTimer.cpp`,
and `World.cpp` (60-second fatigue setting). Tile format and area-bit semantics
come from the pinned MaNGOS Zero extractor at
`43a7fcc5bc27bde5fa7bdfb3d0e3caf201c81e7d`.

## Loading-screen fix

Initial native acceptance found that a countdown could start while the client
was loading another map, leaving its bar hidden after arrival. Acknowledging
the active mover now projects current breath and fatigue bars again. It does
not reset reserves, advance damage, or change the next damage deadline.
Regression coverage includes repeated and invalid mover acknowledgements,
an exhausted fatigue timer, and an extended breath timer recovering at 10x.

## Native acceptance

The final run used GPU-rendered build 5875, level-50 Debughunter (GUID 7), and
gameplay source `c53d3f31`. No gameplay source changed during the run. All
teleports, movement, spirit release, and login actions came through the client;
Tidewave probes were read-only.

- First cross-map travel from Programmer Isle to `-10000 2500 0` on map 0
  displayed the Fatigue bar. The server started at 60,000 ms and health remained
  2,072. `final-cross-map.png` records the previously missing presentation.
- Moving to coastal water at `-10000 2400 0` switched the reserve to `scale: 10`.
  Samples rose from 40,029 to 49,969 to 59,989 ms, then cleared. Health stayed
  2,072; `final-coastal-recovered.png` shows the bar gone.
- Holding the ordinary strafe key swam from y=2400 through the boundary. The
  timer remained absent at y=2433.056 and started at y=2435.417. The character
  stopped at y=2437.778 and continued counting down without movement.
- The first stationary hit arrived 60,827 ms after timer creation. Four captured
  hits dealt 416, 431, 441, and 445 damage, with deadlines advancing by about
  2,001 ms. Normal regeneration added 31 health between hits. Subsequent death
  cleared fatigue and removed the pet presentation; `final-death.png` shows
  the Release Spirit dialog. Clicking it released the ghost at Sentinel Hill.
- A native developer command sent as a self-whisper moved the ghost to
  `-10000 3500 0`, where Namigator returned no area. Terrain resolved Westfall
  and The Great Sea (`{40, 2364}`). The client displayed Fatigue, while the
  corpse remained at the death position and ghost health stayed at one.
- At expiration the owner returned to Sentinel Hill near
  `-10546.900 1197.240 31.724`, with fatigue cleared and health still one.
  The corpse remained offshore. `final-ghost-ocean.png` and
  `final-ghost-rescued.png` show both ends of the transition; the timed trace
  captures the last 859 ms of reserve and then the graveyard arrival.
- Logging out while offshore removed the player from the entity registry,
  metadata, and spatial index. Reconnecting restored the ghost, retained the
  corpse, and displayed the active countdown. Returning to dry land cleared
  fatigue again without changing ghost health.

The final WoW process (PID 1763555, DRM client 5326) increased its graphics
counter from 1,000,005,649 to 16,632,516,510 ns. Duplicate descriptors for that
DRM client were counted once. Both helper-owned client services and both
retained server processes were stopped, with artifacts retained.

## Validation

`mix test.all`: 6,683 passed. `mix compile --warnings-as-errors`,
`mix credo --strict`, formatting, and diff checks passed. Tests cover malformed
terrain, liquid axes and encodings, timer transitions and protections, damage
cadence, death, owner-local rescue, stationary scheduling, real terrain queries,
offshore graveyard selection, and mirror bar restoration.

The accepted server log had no gameplay errors. Existing unsupported
account-data, ticket, and meeting-stone requests remained. An attempted Lua
movement call was blocked by the client's protected UI rules; actual swimming
used the strafe key. Earlier attempts to query `GetMirrorTimerInfo` and to send
ghost developer commands through local say were unsuccessful and are not
counted as acceptance. The successful ghost commands used self-whispers.

Artifacts are retained under:

- `/home/pikdum/.cache/thistle-wow-playtest.OcG1X4/screenshots/`
- `/tmp/thistle-fatigue-server-final.log`
- `/tmp/thistle-fatigue-final-recovery.txt`
- `/tmp/thistle-fatigue-final-swim.txt`
- `/tmp/thistle-fatigue-final-damage.txt`
- `/tmp/thistle-fatigue-final-expiration.txt`
- `/tmp/thistle-fatigue-final-ghost-start.txt`
- `/tmp/thistle-fatigue-final-ghost-rescue.txt`
- `/tmp/thistle-fatigue-final-ghost-state.txt`
- `/tmp/thistle-fatigue-final-rescued-state.txt`
- `/tmp/thistle-fatigue-final-logout.txt`
- `/tmp/thistle-fatigue-final-reconnected.txt`
- `/tmp/thistle-fatigue-final-cleanup.txt`
- `/tmp/thistle-fatigue-tests-final.log`
- `/tmp/thistle-fatigue-credo-final.log`
- `/tmp/thistle-terrain-extract.log`
