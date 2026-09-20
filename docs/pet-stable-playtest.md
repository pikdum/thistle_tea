# Hunter pet stables

Hunters can purchase the two vanilla stable slots, store their current pet,
retrieve a stored pet, and swap the current pet with a stored one. Both active
and dismissed pets can be stored. Dead pets retain their death state and need
Revive Pet after retrieval. Slot prices come from the startup DBC cache: 500
and 50,000 copper. Stable operations validate a living hunter, a nearby living
stable master, matching world, reputation, and combat state on every request.

`Logic.PetStable` owns pure purchases and atomic transfers. The player's
`Internal.pet_stable` retains suspended `Companion` records, including a stable
pet number, health, happiness, experience, loyalty, training points, learned
spells, reaction stance, and autocast choices. Records are distinguished by pet
number rather than creature entry, so hunters can keep multiple pets of the
same species. Runtime retention uses `CharacterStore` and resets on server
restart, like the rest of the server.

The player boundary validates and prepares retrieval before stopping the old
pet. Suspension captures the final snapshot and clears the old process monitor.
The replacement is owned before asynchronous client attachment; delayed
attachments from stopped pets and stale progress or death notifications cannot
restore a stored pet. A failed build or start leaves both slots unchanged.

The same snapshot now preserves health across Dismiss Pet, Call Pet, and
reconnect. Call Pet no longer grants a free full heal. Revive Pet still applies
its spell's health percentage. Forced corpse cleanup also handles creatures
without a loot component.

The client run exposed a taming cleanup defect: the wild creature synchronously
asked its supervisor to stop itself, preventing its termination callback from
removing world and metadata projections. Its stale threat reference kept the
hunter in combat. Taming now sends an owner-local stop request through
`EventSink.Context`, leaves combat through `Engagement`, and stops asynchronously.
A live-process regression checks threat release, termination, and removal of
metadata and spatial presence.

Packet formats follow the stable `.wowm` files in `refs/wow_messages/`. Slot
prices and operation rules follow `NPCHandler.cpp`, and health retention follows
`Pet::LoadPetFromDB` in `refs/vmangos/`. The existing gossip loader now supports
stable option 14. Jenova Stoneshield is seeded beside the debug characters on
Programmer Isle for repeatable client testing.

Automated coverage checks slot limits and prices, insufficient funds, full
stables, missing and foreign pet numbers, same-species swaps, dead pets, current
pet preconditions, snapshot ordering, failed retrieval, stale attachments,
interaction authorization, retained health and identity, packet dispatch, and
the complete vanilla listing payload.

## Real-client acceptance

The final run used an isolated build-5875 client and a fresh server with all code
changes already loaded. Debughunter interacted with Jenova's normal stable
window; transfers used its drag-and-drop controls. Runtime probes read state.

- Purchasing both slots reduced money from 100,000,000 to 99,949,500 copper.
  The client displayed the 5-silver and 5-gold prices and both unlocked slots.
- The level-49 wolf was stored, then a level-6 Stonetusk Boar was tamed through
  the full Tame Beast channel. The old wild creature's process, metadata, and
  spatial position disappeared. Threat references emptied, combat cleared, and
  the stable opened normally. Both pets could be stored simultaneously.
- The wolf was retrieved, trained in Great Stamina, and swapped with the boar.
  Its record retained spell 4187, 44 remaining training points, 34,800 XP,
  loyalty rank two, passive stance, Growl autocast, and 2,168 maximum health.
  Retrieval and swaps displayed the correct names without an Unknown label.
- The boar died while attacking a Skeletal Flayer. Its retained record had
  zero health and `dead?: true`. Storage and retrieval preserved that state
  without creating a live pet. Call Pet displayed the dead-target error.
  Revive Pet then created the boar with 18/120 health, preserving its pet number.
- Swapping back restored the wolf's learned passive, displayed stats, stance,
  autocast, and progression. Pet numbers remained 4194319 for the wolf and
  4194322 for the boar despite new live GUIDs on every summon.
- Logout retained both purchased slots and both pet records in CharacterStore.
  The previous wolf and revived boar processes were absent, and no owned pet
  remained in the spatial index. Reconnect restored the wolf as GUID
  17383894611314868265 with the same number, four spells, 44 training points,
  34,800 XP, stance, autocast, and 2,168 health. The stored boar retained its
  number, two spells, six training points, happiness, and 98 saved health.
  Exactly one owned pet was present after reconnect.

Full-stable rejection, insufficient funds, foreign pet numbers, same-species
identity, failed spawning, and injured-pet health clamping are covered by
automated tests. The final live run emitted no error-level logs or unsupported
stable-command warnings. The helper-owned client and server were stopped.

Evidence is retained in `/tmp/thistle-stable-final-server.log`,
`/tmp/thistle-stable-final-*.txt`, and
`/home/pikdum/.cache/thistle-wow-playtest.ZOpRbO/screenshots/`.

An interrupted development session also exposed a connection error-path bug:
the player-crash notification returned a ThousandIsland callback tuple from a
GenServer callback. It now returns a valid stop tuple and clears the player
reference; the connection regression checks that contract.

## Final validation

- `mix test.all`: 3,636 passed, including DBC, VMangos, and map integration.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `git diff --check`: passed.
- Logs: `/tmp/thistle-stable-final-{tests,compile,credo}.log`.
