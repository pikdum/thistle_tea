# Summoned creature lifecycle and friendly area targeting

Date: 2026-09-23

## Shared behavior

EventAI now handles `SUMMONED_UNIT` (17), `SUMMONED_JUST_DIED` (25), and
`SUMMONED_JUST_DESPAWN` (26). Entries match exactly; zero is not a wildcard.
Repeat timers use parameters two and three, independently for each event.
Conditions, phases, chance, and one-shot disabling use the existing EventAI
interpreter. The summon is the action invoker.

Temporary script summons, wild spell summons, totems, guardians, and creature
pets retain their creating entity separately from control ownership. The mob
owner emits birth, finalized death, and process-departure notifications. Death
and departure are distinct edges. The notification retains a final observation
so despawn conditions can read the summon after its world projections disappear;
receivers reject notifications from another instance copy.

Reference behavior comes from `refs/vmangos/src/game/AI/CreatureEventAI.cpp`,
`Objects/TemporarySummon.cpp`, `Objects/Totem.cpp`, and `Objects/Unit.cpp`.
The existing data contains seven spawn-event rows and three death-event rows.
No dungeon-specific implementation was added.

## Bug found during acceptance

Stonevault Oracle's Healing Ward was healing the hostile player. The loader
mapped target 22 to an enemy-area selector, although VMangos defines it as the
caster's source position. Healing Aura combines that position with target 30,
the friendly source-area selector. Target 30 was previously left numeric and
ignored, making the heal both hostile and aimed at enemies.

Target 22 now denotes a source position. Friendly area selectors 30 and 31
resolve around the appropriate source or destination and select living friends
in the same world. Enemy area selectors remain independent. The DBC regression
failed before this correction and covers all four Healing Aura variants;
Arcane Explosion and Inferno retain their enemy-area behavior.

Reference: `refs/vmangos/src/game/Spells/SpellDefines.h` and the
`TARGET_LOCATION_CASTER_SRC`, `TARGET_ENUM_UNITS_FRIEND_AOE_AT_SRC_LOC`, and
`TARGET_ENUM_UNITS_FRIEND_AOE_AT_DEST_LOC` cases in `Spells/Spell.cpp`.

## Initial native run

Build-5875 Debugmage entered Uldaman through area trigger 286 at
`{-6053.73, -2954.63, 213.686}` on map 0. Acceptance used Stonevault Oracle
entry 4852, database spawn 27534, at `{-233.957, 161.19, -44.6296}` inside the
allocated copy. `.tgm` kept the character alive; `.learn 5` enabled native
Death Touch casts against the selected totems.

In copy 2, Oracle `17379391043438381791` held phase 1 and Healing Ward
`17379391021753831408`. After a mouse selection confirmed entry 3560, the client
cast spell 5 at that exact GUID. The Oracle immediately entered phase 2 and
created Lava Spout Totem `17379391062975451124` while remaining alive at 3405 HP.

A confirmed native kill of Lava Spout `17379391062975451163` changed the Oracle
back to phase 1. Healing Ward `17379391021753831459` appeared in the same slot,
with 5 HP and the correct creator and world. Both killed totems had no entity
process, position, or metadata afterwards. Client screenshots show the changed
totem models and names.

Session: `/home/pikdum/.cache/thistle-wow-playtest.IwaECW`.
Server log: `/tmp/thistle-summon-lifecycle-server.log`.
Screenshots: `ward-confirmed.png`, `ward-real-death.png`, `lava-accepted.png`,
and `ward-returned.png` in the session's `screenshots` directory.

WoW process 2418361 used DRM device `0000:0c:00.0`; its graphics counter grew
from 1,031,230,913 ns to 2,079,862,850 ns. The renderer reported the RX 7900 XT.
The helper-owned client service and retained server PTY were stopped before the
targeting correction was compiled.

Test setup corrections: an offset from the database spawn landed below the
floor, so the run used the exact spawn coordinates. Name targeting initially
reported `Unknown unit`; later selections expired as the Oracle replaced its
short-lived totems. These attempts are excluded from acceptance. The successful
casts used direct mouse selection, a server read confirming the selected GUID,
and prompt casting against a fresh summon. Automatic self-casting was disabled
for the final target checks and restored before client shutdown.

## Final native run after the targeting fix

A fresh server and client repeated real portal entry into Uldaman copy 1.
Oracle `17379391043438379446` summoned Healing Ward `17379391021753829168`.
The live area-target resolver returned only the Oracle and ward for spell 5607;
hostile player GUID 5 was absent. Native Shadow Bolt 686 hit the Oracle, and a
50 ms read-only sampler recorded its health as `3279 -> 3265 -> 3279` while it
remained in combat. The ward now heals its ally.

The final replacement sequence used confirmed mouse selections and native spell
5 packets, with the exact target GUID present in the server log:

| Action | Owner phase | Replacement in slot 1 |
| --- | --- | --- |
| Kill Healing Ward `17379391021753829197` | 1 -> 2 | Lava Spout `17379391062975448916` |
| Kill fresh Lava Spout `17379391062975448927` | 2 -> 1 | Healing Ward `17379391021753829220` |

The Oracle remained alive at 3279 HP. Both killed summons returned nil from
`Entity.pid`, `World.position`, and `Metadata.get`. After the player left for
Programmer Isle, the remaining ward expired, the owner's slot map became empty,
and its phase remained 1 outside combat. Expiry did not produce a death callback.

Session: `/home/pikdum/.cache/thistle-wow-playtest.sVkXnz`.
Server log: `/tmp/thistle-summon-lifecycle-final-server.log`.
Health sampler: `/tmp/thistle-friendly-ward-healing.txt`.
Screenshots: `fresh-ward.png`, `oracle-healing.png`, `ward-selected.png`,
`lava-replacement.png`, `lava-selected.png`, and `ward-replacement.png`.

WoW process 2428690 used DRM device `0000:0c:00.0`; its graphics counter grew
from 558,632,117 ns to 6,715,694,604 ns. The helper-owned client and retained
server PTY were stopped, and automatic self-casting was restored. A command
sent before the loading screen finished initially became keybind input; the
run resumed only after the client was ready. That setup cast of Arcane Explosion
is not part of the acceptance sequence.

Neither native run produced an owner, lifecycle, targeting, or movement error.
Existing unrelated warnings were limited to account-data updates, GM-ticket
queries, and meeting-stone information.

## Automated validation

- `mix test.all`: 5,308 passed, including DBC, VMangos, and map integration tests.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- `mix format --check-formatted`: passed.
- Commit hooks: passed.

The lifecycle tests cover all three callbacks, exact entry matching, one-shot
and repeat behavior, condition gating, final death observations, ordinary
temporary corpses, pet and totem death, living timed removal, and copy isolation.
Friendly-area tests cover source and destination centers, enemy exclusion,
dead/out-of-range/cross-copy exclusion, and real DBC polarity.

One suite run overlapped strict linting and exceeded an existing 100 ms
pet-login attachment assertion. The isolated full-suite rerun passed all tests.
The final test log is `/tmp/thistle-summon-lifecycle-tests-final.log`.
