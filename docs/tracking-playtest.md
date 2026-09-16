# Resource tracking

Find Herbs, Find Minerals, and Find Treasure now project active tracking auras
into `PLAYER_TRACK_RESOURCES`. Creature and resource masks combine every valid
active bit and are recomputed through the shared aura transition. This also
fixes creature tracking previously retaining only the first active type.
Normal tracking spells remain exclusive through the existing spell category.
Cancellation and other aura removal causes clear the corresponding projection.

Reference: `refs/vmangos/src/game/Spells/SpellAuras.cpp`,
`HandleAuraTrackCreatures` and `HandleAuraTrackResources`.

## Validation

- `mix test.all`: 2,916 passed.
- `mix compile --warnings-as-errors` and `mix credo --strict`: passed.
- Regression coverage includes combined masks, invalid bit indices, switching
  resource and creature modes, all shared removal causes, and real spell data
  for herbs, minerals, and treasure.

The isolated build-5875 client session is
`/home/pikdum/.cache/thistle-wow-playtest.xWnXn5`; server output is retained in
`/tmp/thistle-tracking-server.log`. Final test and lint output are retained in
`/tmp/thistle-tracking-tests-final.log` and
`/tmp/thistle-tracking-credo-final.log`.

Debugshaman learned the tracking spells through `.learn` and cast them through
the client near Elwynn Forest coordinates `-9183.36, 114.578, 74.95`.

- Find Herbs displayed yellow herb markers on the minimap. Owner state had
  aura 2383, resource mask 2, and creature mask 0 (`herbs-ground.png`).
- Find Minerals replaced the herb markers with a mineral marker and changed
  the tracking icon. Owner state retained 2580 instead of 2383 and resource
  mask 4 (`minerals.png`).
- Client `CancelTrackingBuff()` removed the icon and markers. Owner state had
  neither tracking aura and both masks zero (`cancelled.png`).
- Find Treasure applied aura 2481 and resource mask 32. A treasure chest
  marker was not separately exercised.
- Track Beasts replaced Find Treasure, with aura 1494, resource mask 0, and
  creature mask 1 (`beasts.png`). Switching back to Find Herbs restored mask
  2 and cleared creature tracking.

The initial teleport screenshot was taken before terrain settled; teleporting
just above the node and allowing the client to land produced the ground view.
No tracking, aura, movement, or owner errors appeared. Startup requests still
log unrelated unimplemented account-data, raid-info, GM-ticket, query-time,
meeting-stone, and cancel-trade messages.
