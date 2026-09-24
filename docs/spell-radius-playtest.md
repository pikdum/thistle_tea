# Spell radius modifiers

Implementation commit: `765ee66c`.

## Behavior

Spell-family flat and percentage radius modifiers now affect the shared area
target query, including hostile circles, cones, ground areas, friendly areas,
party buffs, and class-wide raid buffs. The calculation adds flat yards before
applying the percentage and clamps the result to zero. Base spell data remains
unchanged.

Area aura holders retain their modified radius for periodic recipient refresh.
Totems inherit their owner's spell modifiers when summoned, so Totemic Mastery
and Increased Totem Radius reach their aura spells. Resummoning after a talent
reset captures the new owner state. Existing aura radii remain snapshots.

Persistent ground effects retain their radius before modifier charges are
consumed. Their dynamic object publishes and queries that same radius throughout
its lifetime. Radius modifiers participate in charged-modifier eligibility.

The reference is VMangos's `Spell::SetTargetMap` in `Spell.cpp`, `AreaAura`'s
constructor in `SpellAuras.cpp`, and `Spell::EffectPersistentAA` in
`SpellEffects.cpp`. All three apply `SPELLMOD_RADIUS`. The existing VMangos
spell-template cache supplies Totemic Mastery's corrected class mask.

## Automated verification

- `mix test.all`: **5,469 passed**.
- `mix compile --warnings-as-errors` and `mix credo --strict`: passed.
- Formatting and whitespace checks: passed.

Regressions cover shape selection, family and mask exclusion, spatial inclusion
in the added ring, removal, nonnegative radii, charged ground effects, totem
inheritance and replacement, retained refresh queries, and recipient expiry.
DBC tests check Arctic Reach, Booming Voice, Totemic Mastery, Increased Totem
Radius, Increased Area, and Holy Reach. The DBC test uses a fixture for the
VMangos Totemic Mastery mask instead of querying both databases.

## Native build-5875 acceptance

An isolated GPU client used Debugmage (GUID 5) and Debugshaman (GUID 8) on
Programmer Isle, map 451. Setup used normal debug chat commands; casts, movement,
corpse reclaim, logout, and character entry went through the client. Tidewave
probes only read owner state and public projections.

### Mage

Frost Nova 122 with Arctic Reach rank 2 hit Rabbit spawn 990000 for **22 frost
damage** at approximately **11 yards**. The caster remained at
`{16309.2002, 16335.0996, 69.4400}`, and the rabbit at
`{16309.2, 16324.1, 69.4444}`. The base query was a ten-yard circle with no
recipient at that position; the modified query uses twelve yards. A timed
sample retained the rabbit's health transition and respawn, alongside the
visible combat-log hit. Earlier setup casts involved other playground NPCs and
were not used as the isolated boundary comparison.

With Increased Area 23549, Flamestrike rank 1 created a dynamic object with a
**6.25-yard** radius at `{16313.4688, 16328.3115, 69.4444}`. The client showed
the cast's damage; the object disappeared from `AreaEffects` after expiry.
Its unmodified DBC radius is five yards.

### Shaman

Strength of Earth Totem rank 1 (8075) cast its aura 8076 from
`{16304.6144, 16293.6854, 69.4444}`. Native Num Lock autorun and a forward-key
stop moved the owner along the plateau; no runtime state was injected.

| State | Radius | Owner distance | Strength of Earth | Strength |
| --- | ---: | ---: | --- | ---: |
| Totemic Mastery learned, summoned | 30 yd | about 24.5 yd | Present | 138 |
| Same totem, walked farther | 30 yd | about 36.3 yd | Expired | 128 |
| Talent reset, replacement summoned | 20 yd | about 24.4 yd | Absent | 128 |
| Talent relearned, logout then reconnect | No totem | — | Absent | 128 |
| New summon after reconnect | 30 yd | Near source | Present | 138 |

The buff icon agreed with the owner aura list and derived strength. Logout
removed the recorded totem process and saved empty totem slots. Reconnect kept
Totemic Mastery but discarded the expired remote buff; a fresh summon inherited
the thirty-yard radius again.

## Evidence and cleanup

Client session: `/home/pikdum/.cache/thistle-wow-playtest.PPvV9B`.
Useful screenshots in its `screenshots/` directory:

- `nova-eleven-base-final.png` and `nova-eleven-modified.png`
- `flamestrike-modified.png`
- `totem-modified-outer.png`, `totem-beyond.png`, `totem-reset-outer.png`
- `totem-reconnect.png`

Compact runtime samples are `/tmp/thistle-radius-nova-{base,modified}.txt`,
`/tmp/thistle-radius-flamestrike{,-expired}.txt`, and
`/tmp/thistle-radius-totem-*.txt`. Server log:
`/tmp/thistle-radius-server.log`.

WoW PID 47848 used `amdgpu` on `0000:0c:00.0`; its own graphics counter rose
from 1,538,771,967 to 27,873,016,795 ns. The start and end fdinfo snapshots are
`/tmp/thistle-radius-gpu-{start,end}.txt`. The helper-owned client service and
retained server were stopped after acceptance.

No server errors or spell-validation failures occurred. Existing login warnings
were limited to account-data, GM-ticket, and meeting-stone messages. The client
rejected scripted autorun during setup; the measured movement checks used the
native Num Lock binding.
