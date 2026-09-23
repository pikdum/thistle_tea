# Dungeon corpse return

A ghost outside its corpse's dungeon receives the outdoor entrance as the
corpse marker, while the query packet retains the actual corpse map. Inside
that map, the marker uses the body's real coordinates. Missing bodies produce
the normal not-found reply.

Dungeon portals reject ghosts without a corpse in that dungeon or a linked
descendant. When parent metadata permits an outer entrance, the route selects
the inner dungeon's entrance. Level and quest conditions still apply. An
eligible ghost revives at half health and mana, removes its corpse, and uses
normal instance admission. A later admission failure, such as a raid-group
requirement, leaves the player alive outside. The ordinary corpse reclaim
countdown does not delay this portal recovery.

Map identities, names, parent links, and ghost entrances come from the cached
VMangos map data. The pinned map rows currently have no dungeon parent links;
ancestry routing is covered with fixtures rather than inferred content links.
`Logic.CorpseTravel` owns the pure routing rules, `Player.Corpses` handles
projection and resurrection, and the existing area-trigger boundary enforces
portal requirements and instance admission.

Graveyard links and safe locations are preloaded at boot, filtered for the
supported patch. Release first considers area links, then zone links. It
prefers the nearest eligible graveyard on the corpse map, then the nearest
one on the entrance map using horizontal entrance distance, then a stable
fallback. Faction restrictions apply at every step. Spirit release does not
query Mangos or DBC for graveyard data.

When navigation geometry has no area label, dungeon release falls back to the
map's linked zone. The native playtest exposed this at Ragefire Chasm's entry,
where release previously left the ghost beside its corpse. A map integration
regression covers that position and both factions' graveyard choices.

References: VMangos `HandleAreaTriggerOpcode`, `HandleCorpseQueryOpcode`,
`Player::TeleportTo`, `GetMapEntranceTrigger`, `AreaEntry::GetByAreaFlagAndMap`, and
`ObjectMgr::GetClosestGraveYardForArea`; the Vanilla `MSG_CORPSE_QUERY_Server`
layout is in `refs/wow_messages`.

Automated coverage includes dungeon ancestry and malformed cycles, separate
marker and corpse maps, missing-body replies, entrance height projection,
wrong-dungeon rejection without instance allocation, level restrictions,
resurrection before denied copy admission, normal instance entry, graveyard
faction filtering, entrance-distance ranking, and cache loading.

## Native acceptance

Used the GPU-rendered build-5875 client with Debugshaman, an Orc shaman, on a
fresh server. Developer teleports shortened outdoor travel; both dungeon
entry attempts used the real client area triggers.

- Entered Ragefire Chasm through trigger 2230, receiving map 389, copy 1.
- Died and used the native release action. The ghost appeared at Northern
  Durotar graveyard 850, `(1177.780, -4464.240, 21.354)` on map 1. The body
  remained in copy 1, whose active membership became empty.
- The corpse response displayed map 1 at `(1816.76, -4423.37, -19.717)` while
  retaining corpse map 389. The client showed the marker in Orgrimmar's Cleft
  of Shadow; `GetCorpseMapPosition()` returned approximately `(0.52956, 0.48868)`.
- Trigger 228 displayed "You cannot enter Wailing Caverns while in ghost
  form." The player stayed outside, the corpse survived, and total copy count
  remained one.
- Returning through trigger 2230 resurrected the player before transfer.
  A 100 ms owner sampler captured health `1207/2415`, mana `1215/2430`, no
  corpse, and no release timestamp. After acknowledgement the player was
  alive in the original map 389, copy 1, with membership `[8]`. The corpse
  query returned not found and total copy count remained one.

Evidence: screenshots under
`/home/pikdum/.cache/thistle-wow-playtest.XdA4SI/screenshots/` (`graveyard`,
`wrong-dungeon`, `corpse-marker`, and `revived`); owner snapshots in
`/tmp/thistle-corpse-travel-final-{entry,release,wrong,revival-first,return}.txt`;
server log `/tmp/thistle-corpse-travel-server-final.log`. WoW PID 2056609 used
`amdgpu`, with its graphics counter increasing from `1994619899` to
`3772254377` ns. The initial failed release and its screenshots remain in
session `rh0mkO` for comparison.

No gameplay errors or owner crashes occurred. Existing login/UI warnings
remained for account data, raid info, GM tickets, and meeting-stone info.
Both helper-owned client units and their retained server processes were
stopped after acceptance.

Final checks: `mix test.all` passed all 5,004 tests;
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check` passed.
