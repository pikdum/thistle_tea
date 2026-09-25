# Indoor and outdoor spell acceptance

Date: 2026-09-25. Terrain implementation: `4e1e2949`. Spell rules: `3ba37a42`.

Player casts now enforce the DBC `ONLY_INDOORS` and `ONLY_OUTDOORS` attributes
at cast start and again through the existing launch-time requirements snapshot.
Walking indoors removes outdoor-only auras through the shared aura lifecycle.
Learned outdoor passives return when their terrain and form requirements hold;
equipment bonuses retain their item, enchantment, or set source.

The reference is VMangos `8f4e60845`: `Spell::CheckCast`,
`Player::CheckAreaExploreAndOutdoor`, `Player::IsOutdoorOnTransport`, and
`TerrainInfo::GetAreaInfo` / `IsOutdoors`. Creature casts remain exempt.
Ship and zeppelin checks use the reference's supported local mounting spots;
animated transports are treated as outdoors. Those transport cases were checked
by automated tests, not a native voyage in this run.

## Terrain and ownership

The [terrain query and upgrade instructions](terrain-interiors.md) describe
the WMO group metadata required by existing map bakes. The local upgrade
processed 616 WMO index entries, skipping 16 without baked geometry. SHA-256
checks confirmed that all existing `.bvh` files and `bvh.idx` stayed unchanged.
The native metadata tests passed through the Nix map-builder derivation.

Terrain queries stay at the boundary. The player owner caches the resolved
position and terrain state, while cast completion obtains a fresh snapshot.
Pure validation and aura reconciliation do not query the world. Equipment
resynchronization includes terrain among its requirements. Login, movement,
teleports, form changes, and spell learning use the existing owner update path.
Dead players and released ghosts do not restore outdoor passives.

Unknown terrain is permissive and does not remove active auras. Indoor-only
spell failure is covered with synthetic fixtures because this client DBC has
no spells bearing that attribute. Indoor-only auras are not removed on exit;
the reference's automatic removal rule specifically targets outdoor-only auras.

## Native setup

Fresh local server and genuine WoW 1.12.1 build 5875. Level-50 Debugdruid
performed the casts and movement; Debugbidder observed the mount transition.
Spell learning, travel, casting, movement, and logout all used the native client.
Runtime probes only read existing owners and projections.

GPU sessions:

- Debugdruid: `/home/pikdum/.cache/thistle-wow-playtest.YTgNwY`.
- Debugbidder: `/home/pikdum/.cache/thistle-wow-playtest.EKeKE1`.

WoW's own amdgpu graphics counters advanced for both processes. PID 1011547
increased from 652,508,743 to 30,724,786,465 ns; PID 1016384 increased from
8,379,157,342 to 14,201,934,219 ns. Both sessions used the RX 7900 XT.

## Observed behavior

1. Travel Form worked outside Northshire Abbey at speed 9.8, form 3, display
   632. Walking onto the abbey's indoor WMO floor removed spell 783, restored
   form 0 / display 56, and returned speed to 7.0. The client showed the fade.
2. Recasting Travel Form indoors sent `CMSG_CAST_SPELL`; the server rejected
   it with `only_outdoors`, and the client displayed “Can only use outside”.
   Brown Horse and Ghost Wolf produced the same server rejection indoors.
3. Cat Form remained usable inside with speed 7.0 and no Feline Swiftness aura.
   Walking outside restored learned rank 24866 and speed 9.1. Reentry removed
   that passive without removing Cat Form. Published form and display metadata
   matched the owning player throughout.
4. Brown Horse mounted outdoors with display 2404 and speed 11.2. Walking
   indoors cleared the mount display and spell 458 and restored speed 7.0.
   The observer saw the horse disappear and the target's mount buff clear.
5. Ghost Wolf completed outdoors with form 16, display 4613, and speed 9.8.
   Walking indoors removed spell 2645, cleared the form, and restored speed 7.0.
6. While mounted on Programmer Isle, transferred to the abbey interior at
   `{-8914, -164, 82}` on map 0. The destination owner and client were unmounted,
   with `outdoors?: false`, normal appearance, and speed 7.0.
7. Logged out indoors in Cat Form. The saved character retained form 1 and
   speed 7.0 without Feline Swiftness; its actor, metadata, and world position
   were removed. Reconnecting deeper inside the abbey restored Cat Form,
   display 892, and speed 7.0 with `outdoors?: false` and no Feline Swiftness.

Screenshots are retained in each session's `screenshots` directory. Useful
primary frames include `travel-outside.png`, `doorway-align.png`,
`travel-rejected-inside.png`, `cat-inside.png`, `cat-exit.png`,
`cat-reconnect-confirmed.png`, `mount-rejected-inside.png`, `wolf-removed.png`, and
`worldport-inside.png`. Observer frames are `observed-mounted-clear.png` and
`observed-dismounted.png`.

Read-only evidence is retained as `/tmp/thistle-spell-environment-*.log`;
the server log is `/tmp/thistle-spell-environment-server.log`.
Both helper-owned client sessions and the retained server were stopped after
acceptance. Both players had no remaining actor, metadata, or world position.
No server errors occurred. Warnings were the three intentional outdoor cast
rejections and existing unimplemented account-data, GM-ticket, and meeting-stone
login requests.

## Automated verification

`mix test.all`: 6,185 passing tests, including DBC, VMangos, and map integration
coverage. `mix compile --warnings-as-errors` and `mix credo --strict` passed.
No architecture allowlist was expanded.

Coverage includes real terrain and DBC attributes, both protocol errors,
unchanged mana on rejected casts, completion after moving indoors, dismount
speed events, learned passive restoration, form exit, death and ghosts,
unlearning, equipment sources and canonical stat bonuses, login restoration,
and unknown terrain. Native metadata tests cover legacy files, triangle order,
roundtrips, corruption, geometry mismatch, and atomic replacement.
