# Lava exposure

Touching lava starts a one-second grace period, followed by 605–610 fire damage
every two seconds. Stationary players remain scheduled; a late owner tick deals
one pulse. Leaving the liquid clears exposure. Briefly moving above its surface
recovers the grace reserve at ten times normal speed, retaining partial recovery
on reentry. Lava has no client mirror timer bar.

Damage uses the shared environmental damage path: fire resistance and school
immunity apply, absorb shields are consumed, and lethal damage enters the normal
death and durability lifecycle. Dead bodies, ghosts, god mode, and Spirit of
Redemption stop exposure. Water Breathing does not protect against lava.

The pure logic receives sampled liquid and random rolls from movement and
behavior-tree boundaries. It returns updated entity state and typed effects;
it performs no world queries, process sends, or database access. No architecture
allowlist entries were added.

Reference: VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`, `Player.cpp`
(`UpdateMirrorTimers`, environmental flags, expiration pulses), `MirrorTimer.cpp`,
`World.cpp`, and the vmap extractor's `wmo.cpp`. Ordinary slime has no generic
damage pulse there. Naxxramas liquid entry 21 applies spell 28801 through the
separate [liquid-spell lifecycle](liquid-spells-playtest.md).

## Liquid data

Outdoor lava uses the cached build-5875 terrain tiles introduced for
[ocean fatigue](fatigue-playtest.md). WMO lava needs additional metadata:

```sh
nix run .#terrain-data -- "$WOW_DIR" ./maps/terrain
nix run .#namigator-mapbuilder -- --wmo-metadata \
  --data "$WOW_DIR/Data" --output ./maps
```

Use the same client data as the existing bake and restart the server afterward.
New map bakes include both. The local metadata upgrade updated 616 baked WMOs
and skipped 16 index entries without baked geometry; it did not rebuild
navigation or change `.bvh` files or `bvh.idx`.

The pinned Namigator patch retains actual MLIQ heights, triangle diagonals,
hidden tiles, and normalized water, ocean, magma, and slime entries. Geometry
hashes bind atomic `.bvh.liquids` sidecars to the existing collision model.
Missing sidecars remain compatible with legacy bakes; malformed or mismatched
files are rejected. See [terrain interiors](terrain-interiors.md) for setup.

The runtime uses WMO instance transforms and collision floors to distinguish
lava below a bridge from the bridge itself. Movement prefers WMO liquid, then
falls back to ADT terrain. Existing navigation and breathing surface queries
are unchanged. Read queries share the map lock and remain safe during unloads.

## Native acceptance

The GPU-rendered build-5875 client used level-50 Debughunter (GUID 7), maximum
health 2,122, and gameplay source `6dee99cb`. No gameplay code changed during
the run. All travel, spells, spirit release, logout, and login actions came
through the client; Tidewave probes only read state.

- Blackrock Mountain's bridge at map 0, `-7580 -1140 239`, produced no exposure.
  Moving to `-7580 -1140 167.2` entered WMO lava where ADT liquid was absent.
  The first 606-point hit arrived after 1,001 ms; the next arrived 2,002 ms
  later. Returning to the bridge cleared exposure and stopped further damage.
  `lava-damage.png` shows the hit; `lava-escaped.png` shows the safe return.
- Casting Fire Ward rank 4 provided a 675-point shield. The first 605-point
  pulse left 70 absorb and full health. The next 609-point pulse removed the
  holder and dealt 539 damage. A later pulse dealt damage without restoring
  the shield. `lava-ward.png` shows `Absorb` and `0 (605 absorbed)`.
- Outdoor lava at `-7483.3333 -850 265.7` settled the player at z=265.097168.
  The first hit arrived after 1,001 ms, with later deadlines advancing by
  2,001 ms. Four pulses killed the character and cleared exposure. The client
  displayed Release Spirit and removed the pet frame; `lava-outdoor.png`
  and `lava-death.png` record both states. The active breath reserve had not
  expired, so these were lava deaths rather than drowning.
- Clicking Release Spirit moved the ghost to the graveyard at
  `-7490.450 -2132.620 142.186`, with one health and no exposure. A developer
  command sent through a native self-whisper returned the ghost to its corpse
  in lava. Health stayed at one, no lava timer started, and the client offered
  normal corpse recovery (`lava-ghost.png`).
- Logging out in lava removed the player from the entity registry, metadata,
  and spatial index. Reconnecting restored the ghost at the same position,
  with one health, no exposure, and an available corpse recovery dialog
  (`lava-reconnected.png`).
- Accepting corpse recovery restored 1,061 health. A fresh one-second grace
  started, followed by a 610-point hit after 1,007 ms; the next pulse killed
  the character and cleared exposure again. `lava-reclaimed.png` shows the
  hit and `lava-reclaimed-death.png` shows the second Release Spirit dialog.

WoW PID 1784058, DRM client 5355, increased its graphics counter from
2,405,865,972 to 22,415,001,694 ns. Duplicate descriptors for that DRM client
were counted once. The helper-owned client service was stopped and became
inactive; the player registry, metadata, and spatial entries were absent.
The retained server process was also stopped. Artifacts remain available.

## Validation

`mix test.all`: 6,693 passed. `mix compile --warnings-as-errors`,
`mix credo --strict`, formatting, and diff checks passed. The native Nix build
passed `WmoLiquidsTests` and `WmoGroupFlagsTests`.

Regression coverage includes contact thresholds, partial recovery, exact
stationary deadlines, late pulses, shield depletion, immunity and resistance,
death protections, WMO bridge and floor selection, terrain fallback, and
concurrent queries during unload/reload. Native metadata tests cover liquid
entry normalization, sloped triangles, hidden tiles, malformed and stale
sidecars, and rejected writes preserving previous metadata.

The accepted server log contained no gameplay errors. Existing unsupported
account-data, ticket, and meeting-stone requests remained. An initial diagnostic
probe used the wrong owner-state field and was corrected; it changed no state
and is not acceptance evidence.

Artifacts are retained under:

- `/home/pikdum/.cache/thistle-wow-playtest.9gSyGz/screenshots/`
- `/tmp/thistle-lava-server.log`
- `/tmp/thistle-lava-native-escape.txt`
- `/tmp/thistle-lava-native-ward.txt`
- `/tmp/thistle-lava-native-death.txt`
- `/tmp/thistle-lava-native-release.txt`
- `/tmp/thistle-lava-native-ghost.txt`
- `/tmp/thistle-lava-native-logout.txt`
- `/tmp/thistle-lava-native-reconnected.txt`
- `/tmp/thistle-lava-native-reclaimed.txt`
- `/tmp/thistle-lava-native-cleanup.txt`
- `/tmp/thistle-lava-tests-all.log`
- `/tmp/thistle-lava-credo.log`
- `/tmp/thistle-lava-native-build-checks.log`
- `/tmp/thistle-wmo-liquid-extract.log`
