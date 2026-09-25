# Terrain interiors

`World.Pathfinding.outdoors/2` uses the WMO group flags of the nearest collision
floor below the player. Bit `0x8000` marks an outdoor group. WMO membership alone
does not imply an interior: Stormwind streets and building interiors use
different group flags. Intervening ADT terrain takes precedence over a buried
WMO floor, matching VMangos `TerrainInfo::GetAreaInfo` and `IsOutdoors`.

The query returns `true` outdoors, `false` indoors, and `nil` when the map or the
hit WMO's group metadata is unavailable. Missing metadata is never guessed from
zone names or ceiling visibility.

## Generating metadata

The pinned Namigator source is patched by `nix/namigator-source.nix` for both
the runtime NIF and the map builder. New `nix run .#maps` bakes include metadata.
An existing bake can be upgraded without rebuilding navigation:

```bash
nix run .#namigator-mapbuilder -- --wmo-metadata \
  --data "$WOW_DIR/Data" --output ./maps
```

Use the same client data that produced the original bake. The upgrade checks
the existing collision vertices against the client before writing metadata,
leaves `.bvh` files and `bvh.idx` untouched, and skips index entries whose geometry
has not been baked. Restart the server after upgrading loaded maps.

Each `<WMO>.bvh.groups` sidecar contains a format signature, face count, geometry
hash, and one group flag per collision triangle in the serialized tree's order.
Writes use a temporary file followed by a rename. The runtime rejects malformed
or mismatched sidecars. Legacy bakes without sidecars remain loadable.

Outside the devenv shell, obtain the matching source with
`nix build .#namigator-source --no-link --print-out-paths` and set `NAMIGATOR_SRC`
to the resulting path before compiling the NIF.

## Verification

`nix build .#namigator-mapbuilder` runs the native metadata tests, covering face
order, geometry roundtrips, missing sidecars, stale geometry, truncated metadata,
and rejected writes preserving valid metadata.

`mix test test/game/world/pathfinding_test.exs test/native/namigator_concurrency_test.exs --include namigator_maps`
covers Northshire Abbey, Goldshire's inn, outdoor Stormwind groups, an Elwynn
mine, Undercity, Deadmines, unavailable maps, concurrent queries, and ADT unloads.
These tests require an upgraded or freshly generated bake.
