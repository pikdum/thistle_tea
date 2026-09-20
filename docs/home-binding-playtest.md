# Innkeeper home binding

Innkeepers now offer their home-binding gossip option and the Vanilla
confirmation dialog. Accepting triggers Bind (3286) from the innkeeper.
The spell returns a typed effect to the player's owner, which revalidates
the living, friendly innkeeper, five-yard distance, matching world, and
non-instance map before saving the player's current position and area.
Cancellation leaves the home unchanged.

`HomeBind` keeps map, area, and position together in the runtime character
store. Login and world transfers send the retained home to the client.
Previously they sent the current location instead. Hearthstone (8690) and
Astral Recall (556) now resolve the shared home-destination target from
spell data through the normal teleport lifecycle.

Bind also replaces a missing Hearthstone through its item-creation effect.
Inventory storage now enforces template unique-item limits against all
owned items, including bank storage and earlier additions in a batch.
Spell creation silently skips items already at their limit, and clips
larger requests to the remaining allowance. Removing and replacing a
unique item in one atomic transaction remains valid.

Client testing exposed an unlabelled floor surface inside Lion's Pride
Inn: the native area query returned `{0, 0}` at the client's standing
height. Area lookup now retries just below nearby geometry surfaces when
the original result has no area. The search is bounded to three yards;
valid results are retained and missing geometry still returns no area.
This restores the Goldshire home label without changing the destination.

References: `HandleBinderActivateOpcode`, `SendBindPoint`, `SetBindPoint`,
`EffectBind`, and `DoCreateItem` in `refs/vmangos/`; Vanilla binder and
player-bound packet definitions in `refs/wow_messages/`.

## Acceptance

Build-5875 client, isolated session
`/home/pikdum/.cache/thistle-wow-playtest.REQNL8`:

- Debugrogue opened Innkeeper Farley's real gossip at Lion's Pride Inn.
  Cancelling the confirmation preserved the starting home. Accepting
  saved map 0, area 87, and approximately `{-9461.5, 16.19, 56.963}`.
- Rebinding retained exactly one Hearthstone. The client reported
  `GetBindLocation()` as `Goldshire`.
- After travel to map 451 and logout, the runtime store retained the
  Goldshire home. Reconnecting on map 451 still displayed `Goldshire`.
- The client used the actual inventory Hearthstone. Movement interrupted
  its ten-second cast without teleporting or starting its category
  cooldown. A subsequent completed cast returned to the saved inn
  position and started category 89's cooldown.
- Deleting the Hearthstone through the client reduced the owned count to
  zero. Binding again restored exactly one while preserving the active
  return-home cooldown.

The first session briefly reloaded the area-query module while mobs were
running, producing transient module-unavailable errors. Final runtime
acceptance uses a fresh server with the compiled code.

Fresh-server session
`/home/pikdum/.cache/thistle-wow-playtest.OOrfUU`:

- Debugshaman bound through Innkeeper Boorand Plainswind at the Crossroads.
  The client displayed `The Crossroads`; the owner retained map 1, area
  380, and approximately `{-407.0, -2644.0, 96.223}`.
- Astral Recall completed its ten-second cast from map 451 and returned
  to that position. A separate trip used the inventory Hearthstone and
  reached the same position. Public world presence and owner state agreed,
  the player was ready, casting had ended, and one Hearthstone remained.
- Both cooldowns remained active independently: category 511 for Astral
  Recall and category 89 for Hearthstone. The fresh server log contained
  no error-level messages or home-binding failures. Existing unimplemented
  account-data, raid-info, ticket, query-time, meeting-stone, and
  cancel-trade packets were unrelated service warnings.

Automated coverage includes packet encoding and dispatch, confirmation
without mutation, delayed requests after death or NPC removal, dead and
ghost players, distance and world separation, dungeon and battleground
rejection, stored-home projection, explicit owner routing, both return
spells, unique-item batch rollback and replacement, banked items, DBC
spell data, VMangos gossip data, and real inn geometry.

Final gates after all code changes: `mix test.all` passed **3,536 tests**;
`mix compile --warnings-as-errors` and `mix credo --strict` passed.
Both isolated clients and retained servers were stopped after acceptance.
