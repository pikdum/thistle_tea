# Database spell destinations

Implemented and accepted on 2026-09-27 in `9ac1af15`.

## Shared behavior

DBC target 17 now resolves coordinates from the boot-loaded
`spell_target_position` cache through the shared location boundary. A matching
map replaces the cast destination before unit selection and effect delivery.
Wild, guardian, and object summons, persistent ground effects, destination areas,
and triggered casts receive that position. The caster retains its current
`WorldRef`; a database map ID cannot redirect these effects into another copy.
The resolved coordinates also reach the spell launch packet.

As in VMangos, an absent row or a row for another map leaves the current
destination unchanged. This differs from target 46, whose missing scripted
location rejects the cast. Neither path queries Mangos during gameplay.

Ordinary teleports keep their separate destination path, which permits travel
between maps. The cache now retains the configured orientation, and teleport
resolution and event delivery preserve it. Native testing caught the second
handoff discarding that orientation; the regression now covers the complete path
from cached spell destination to the player owner's teleport command. Effects
without an explicit facing retain the existing owner-side fallback.

This supplies shared destination behavior, not complete scripted encounters for
every spell using target 17. Ground auras, area recipients, wrong-map fallback,
and copy isolation have automated coverage; the native cases below exercise
summoning and player teleports.

## Native acceptance

Genuine build-5875 client, Debugmage GUID 5, GPU rendering, fresh local servers.
Commands and spell casts used native client input. Tidewave observations were
read-only.

| Action | Client and authoritative result |
| --- | --- |
| Learn Target Dummy - Event 001, spell 18634; move to `-6076 -220 450` on map 0 and let the player land | Caster settles at `{-6076, -220, 425.049835}` |
| Cast the spell and select Mortar Team Target Dummy | Visible guardian 11875 appears at the exact database point `{-6076, -215, 424}`, distinct from the caster; a sampler confirms owner 5, spell 18634, and open map 0 |
| Leave the stationary dummy in view | Its current position and spawn position remain at that database point |
| Teleport from Dun Morogh to Stormwind | Dummy process, metadata, world position, and owner guardian reference are removed |
| On a fresh server, move to Darnassus at `{9660.81, 2513.64, 1331.66}` on map 1, then cast Teleport: Stormwind | Arrival is `{-9003.46, 870.031, 29.6206, 5.28}` on map 0; the client loads Wizard's Sanctum and faces its portal; Rune of Teleportation count changes from 20 to 19 |
| Turn to facing `4.690951`, then cast Teleport: Stormwind again | The same-map teleport restores facing `5.28000021`; rune count changes from 19 to 18 |
| Log out normally and reconnect | Logout removes the player owner, metadata, and position; reconnect retains map 0, destination, facing, and 18 runes, with no active cast, channel, guardian, or script run |

The first teleport run exposed the discarded-facing bug. Both the cross-map and
same-map cases were repeated successfully after its fix. Editing the live module
also caused transient module-unavailable errors during a subsequent development
reload in the first server. Acceptance was repeated on the restarted server
without further code edits. Its log contains the existing unimplemented
account-data and GM-ticket packet warnings, with no runtime errors or
spell-validation failures.

## Automated coverage

`mix test.all`: **6,928 passed** in 72.6 seconds. Compilation with warnings as
errors, strict Credo, and the commit's format hook passed. The architecture
allowlist is unchanged.

Regressions cover cached coordinate replacement, missing and wrong-map rows,
ordinary teleport separation, three summon families, power costs, launch-packet
coordinates, persistent ground effects, per-effect destination-area delivery,
copy isolation, triggered casts and original-caster routing, and teleport facing
through the explicit owner context. Separate DBC and VMangos tests check real
spell target decoding and target-position rows.

## References and evidence

Reference checkout: `refs/vmangos`, commit
`8f4e608450460efe1e38743e4da74397d4773a3a`, especially
`Spell::SetTargetMap` for `TARGET_LOCATION_DATABASE` and
`Spell::EffectTeleportUnits`. Live generated data was checked for spells 18634,
18907, 19723, 17475, 29237, 22191, 3561, and 3565.

Summon session: `/home/pikdum/.cache/thistle-wow-playtest.8Tbn6L`, owned unit
`thistle-wow-playtest.8Tbn6L.service`, invocation
`de809ea83fdf4ce2afb4039b5a3f6f71`. WoW PID 2109124 belonged to that cgroup;
its own DRM graphics counter advanced from 2.426 to 5.934 billion nanoseconds.
The selected dummy is visible in `screenshots/dummy-facing.png`.

Final teleport session: `/home/pikdum/.cache/thistle-wow-playtest.NRrgkY`, owned
unit `thistle-wow-playtest.NRrgkY.service`, invocation
`dfd635f1e9a8492e88b40ee2036de41b`. WoW PID 2114866 belonged to that cgroup;
its own DRM graphics counter advanced from 1.392 to 4.894 billion nanoseconds.
Screenshots include `darnassus-before.png`, `stormwind-facing.png`,
`same-map-facing.png`, and `reconnect.png`.

Summon repetition on the final server:
`/home/pikdum/.cache/thistle-wow-playtest.u4CoXc`, owned unit
`thistle-wow-playtest.u4CoXc.service`, invocation
`801bab787cab4f2586770982afab5339`. WoW PID 2118468 belonged to that cgroup;
its own DRM graphics counter advanced from 1.224 to 5.221 billion nanoseconds.
Guardian GUID 17383894760883749743 again used `{-6076, -215, 424}` while its
owner stood at `{-6076, -220, 425.050232}`. Its facing came from the caster;
the table's orientation is used by teleports, not ordinary destination selection.
Another native Stormwind teleport removed that guardian's process, metadata,
position, and owner reference, while arriving with the correct facing.

Server logs, runtime samples, and gates are retained under
`/tmp/thistle-fixed-locations-*`.

All three helper-owned client units are inactive with empty cgroups, and their
WoW PIDs are gone. The final disconnect removed the player owner and presence.
Both server PTYs were stopped; ports 4000, 3724, and 8085 were free. No push was
performed.
