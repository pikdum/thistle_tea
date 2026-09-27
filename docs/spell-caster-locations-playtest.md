# Caster-relative spell destinations

Reference: local VMangos `8f4e608450460efe1e38743e4da74397d4773a3a`,
`Spell.cpp` target-map handling for targets 32, 41–44, and 47–50,
`SpellEffects.cpp` leap and summon effects, and
`Player::SummonPossessedMinion` in `Player.cpp`.

The shared location resolver now computes compass offsets from the caster's
current pose and the modified effect radius, then clips against terrain.
An absent radius means zero distance. Explicit destinations, including zero
coordinates, take precedence; later directional selectors reuse an already
resolved destination. Duel's minion-position selector is excluded.

Recipient selection remains separate from placement. Directional caster spells
ignore an unrelated selected unit, while explicit unit and area selectors keep
their recipients. Cast completion resolves the live pose again. Triggered casts
and object origins use the same location boundary.

Directional leaps preserve facing, combat, and the current world through the
existing teleport transition. Ordinary player Blink's target 55 retains its
separate walking, falling, and swimming geometry. Totems and companion pets
retain their own placement rules.

Portals and Lightwell now carry their resolved destination into object creation.
Possessed and demon summons no longer replace resolved minion coordinates with
a half-yard forward offset. Object creation preserves explicit zero coordinates;
script object summons translate their legacy zero-as-unspecified fields to nil.

## Native checks

Build 5875, Debugpriest, isolated hardware-rendered clients. GM learning, level,
item, and relocation commands prepared the cases; activation used native casts.
Tidewave probes only inspected runtime state. No god mode was used.

### Directional Blink and collision

Session `/home/pikdum/.cache/thistle-wow-playtest.qWmcwa`.
Each open-ground cast began at `{16303.20020, 16318.09961}` on map 451,
facing zero. The server logged the following native spell IDs:

| Spell | Direction | Final X | Final Y |
| --- | --- | ---: | ---: |
| 29208 | Front | 16323.20020 | 16318.09961 |
| 29209 | Back | 16283.20020 | 16318.09961 |
| 29210 | Left | 16303.20020 | 16338.09961 |
| 29211 | Right | 16303.20020 | 16298.09961 |

All four retained facing zero and open world 451. Ground height resolved to
approximately 69.44444. Evidence: `screenshots/blink-{front,back,left,right}.png`
and `/tmp/thistle-caster-locations-blink-{front,back,left,right}.log`.
These NPC spells share the same client name; verify the ID in the server log
when choosing among learned spellbook entries, especially after a map transfer.

At Northshire Abbey, a front Blink from `{-8930, -164, 82.46}` stopped at
`{-8925.18066, -164, 82.68143}`, about 4.82 yards along its intended 20-yard
line. The caster retained facing zero and map 0. Evidence:
`screenshots/wall-before.png`, `screenshots/wall-clipped.png`, and
`/tmp/thistle-caster-locations-wall-{before,after}.log`.

WoW PID 2150850's own DRM graphics counter increased from 4,115,513,112 ns
to 10,819,524,039 ns. The renderer was the AMD RX 7900 XT.

### Possession regression and accepted repeat

The first session's Eye of Kilrogg cast exposed a `unique_limit` KeyError.
Its summon request incorrectly opted into script-wide proximity limits without
the script fields. Possession now uses the owner's control lifecycle, matching
VMangos. A boundary regression creates two nearby possessed summons for distinct
owners and verifies each actor and control attachment.

Fresh-server session `/home/pikdum/.cache/thistle-wow-playtest.BkzMwa`
accepted commit `b4a8eae9`. From the same starting position and facing zero,
Eye of Kilrogg 126 created GUID `17379391033783091295` at
`{16304.61441, 16319.51382, 69.44444}`: a two-yard front-left offset.
The loaded VMangos override supplies radius two for this spell. Owner GUID 4
remained stationary; the client showed the eye, its unit frame, viewpoint, and
channel. After the 45-second channel expired, charm and channel fields were
zero, casting was nil, and the eye's process, world position, and metadata were
gone. Evidence: `screenshots/eye-active.png`,
`/tmp/thistle-caster-locations-eye-accepted.log`, and
`/tmp/thistle-caster-locations-eye-cleanup.log`.

### Portals, Lightwell, and lifetime

The fresh session repeated both object spells from the same pose:

| Spell | Object | GUID | Position |
| --- | --- | --- | --- |
| Portal: Stormwind 10059 | 176296 | 17370386720536658029 | `{16306.20020, 16318.09961, 69.44444}` |
| Lightwell 724 | 181102 | 17370386801167958134 | `{16305.20020, 16318.09961, 69.44444}` |

The client displayed both objects. Their owners were GUID 4, their orientation
was zero, and their world was open map 451. They appeared exactly three and two
yards ahead, respectively. The first session also verified these offsets with
nonzero facing 6.23292 radians. Native mana snapshots were taken after
regeneration, so they do not establish exact costs.

Portal expiry removed its actor, position, metadata, and owner monitor while
leaving Lightwell alive. Evidence: `screenshots/portal-active.png`,
`screenshots/lightwell-active.png`, `screenshots/portal-expired.png`, and
`/tmp/thistle-caster-locations-{portal-accepted,lightwell-accepted,portal-expiry}.log`.

Logout removed the still-live Lightwell actor, world position, and metadata.
Reconnecting restored no object monitors, charm, or channel; both former object
GUIDs remained absent. The client showed the original scene without the summons.
Evidence: `/tmp/thistle-caster-locations-logout.log`,
`/tmp/thistle-caster-locations-reconnect.log`, and `screenshots/reconnected.png`.

WoW PID 2159305's own DRM graphics counter increased from 2,081,639,251 ns
to 11,674,984,726 ns on the AMD RX 7900 XT. The fresh server log,
`/tmp/thistle-caster-locations-server-accepted.log`, contained no gameplay errors
or cast validation failures. Only the existing account-data and ticket-query
opcode warnings appeared at login.

## Automated checks

After the possession fix, `mix test.all` passed all 6,962 tests,
`mix compile --warnings-as-errors` passed, and strict Credo passed in the commit
hook. Coverage includes rotated compass offsets, radius modifiers, absent
radii, explicit zero destinations, sequential selectors, recipient selection,
cast completion, collision maps, triggered and object-origin casts, actual DBC
rows, summon boundaries, script defaults, and separate possession owners.
No architecture allowlist entries were added.

Logs: `/tmp/thistle-caster-locations-all-accepted.log`,
`/tmp/thistle-caster-locations-compile-accepted.log`, and
`/tmp/thistle-caster-locations-possession-tests.log`.

Both helper-owned client services were stopped and their WoW PIDs disappeared.
Both retained server PTYs exited; ports 4000, 3724, and 8085 were free. Logs and
screenshots were retained. No changes were pushed.
