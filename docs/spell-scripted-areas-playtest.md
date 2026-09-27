# Scripted spell areas and configured cones

Implemented and accepted on 2026-09-27 in `1248b8e1`.

## Shared behavior

DBC targets 7, 8, and 60 now select units around the spell's source, destination,
or caster-facing cone. They reuse the cached `spell_script_target` selectors and
per-effect delivery introduced for nearest-creature target 38. Entry, life state,
conditions, and inverse effect masks remain independent for each effect.

Source and destination coordinates are distinct. Caster-origin modes always use
the caster's current position, overriding coordinates supplied by the client.
Source areas and cones exclude their caster; destination areas can include it.
Selection respects the current world copy, owner presence, three-dimensional
distance, modified effect radius, creature combat reach, line of sight, and
target caps. Empty areas are valid. Destination summon and persistent ground
effects retain their existing execution paths instead of executing on each
nearby unit.

Without database selectors, source areas enumerate nearby units, destination
areas check targetability and life state, and damaging cones use hostile area
selection. An effect excluded by every selector does not become unrestricted.
Area casts also preserve their original selected target rather than replacing it
with the first area recipient.

The loader caches `spell_cone` overrides at boot. Both ordinary and scripted cones
use the same pure geometry: a 60-degree default, configured forward angles, and
negative angles for rear arcs. This supports Cannon's 7-degree cone, Shoot
Rocket's 90-degree cone, and negative rear cones without gameplay database calls.

This milestone covers unit casts and triggered spells.
[Scripted destinations](spell-scripted-locations-playtest.md) subsequently added
target 46. Game-object spell entry points remain separate work.

## Native acceptance

Fresh server, genuine build-5875 client, Debugmage GUID 5, Programmer Isle map
451. All casts were sent through the native spellbook API with selection cleared.
The fixtures are reproducible through `dev_seed.ex`; Steam Tonks use a template
fallback because their template has no ordinary creature spawn row.

| Action | Client and authoritative result |
| --- | --- |
| Cast Gnarlpine Vengeance 5628 near the Ursa 2006, Gardener 2007, and Squirrel 1412 | Visible spell effect; both Gnarlpines gain aura 5628, while the squirrel and caster do not |
| Cast Elune's Blessing 26393 at the same location | Native blessing animation and buff icon; both Gnarlpines, the squirrel, and caster gain aura 26393 |
| Cast Cannon 24933 facing east toward four Steam Tonks | Combat log reports one hit for 20; only the centered tonk falls from 41 to 21 health |
| Cast Flamethrower 25029 from the same position and orientation | Combat log reports hits for 18 and 22; the centered and slightly offset tonks burn and fall to 3 and 19 health; the wide-angle and rear tonks stay at 41 |
| Allow Flamethrower's periodic effect to finish | Both affected tonks die and remove aura 25029; the two excluded tonks remain unharmed |
| Log out and reconnect with Elune's Blessing | Buff icon and stat panel retain the blessing; no active cast, channel, or script run |
| Right-click the blessing icon | The buff disappears and the stat panel returns to the baseline values |

The caster stood at `{16523.2, 16398.1, 69.44}` with orientation zero for both
cone casts. Tonk offsets were `{5, 0}`, `{5, 1}`, `{5, 4}`, and `{-5, 0}`. Their
bearings are approximately 0, 11.3, 38.7, and 180 degrees, distinguishing the
7-degree and 60-degree full cone angles.

The blessing changed strength/agility/stamina/intellect/spirit from
`28/32/122/195/137` to `30/35/133/214/150`, and maximum health from 1995 to 2105.
The native character panel and owner state agreed before and after reconnect.
Cancelling the buff restored every baseline value. Normal logout removed the
player owner, metadata, and world position.

God mode was enabled after the first Gnarlpine cast to keep the stationary caster
alive. This acceptance verifies target selection, delivery, and lifecycle; it
does not use these casts to verify resource costs. There were no runtime errors.
The only server warnings were the existing unimplemented account-data and
GM-ticket packets.

## Automated coverage

`mix test.all`: **6,894 passed** in 65.2 seconds. Compilation with warnings as
errors and strict Credo both passed. The architecture allowlist is unchanged.

Coverage includes separate and forced caster origins, selector masks, corpse
selection, target caps, empty areas, actual per-recipient healing, cone rotation
and angular wraparound, narrow/wide/rear arcs, and destination summon/ground
exceptions. Separate DBC and VMangos tests verify real target modes and cached
cone overrides.

## References and evidence

Reference checkout: `refs/vmangos`, commit
`8f4e608450460efe1e38743e4da74397d4773a3a`:

- `SpellDefines.h`: target modes 7, 8, and 60.
- `Spell.cpp`: `SetTargetMap` and `SpellNotifierCreatureAndPlayer`.
- `SpellMgr.h`: `GetSpellCone`.
- Generated `spell_script_target` and `spell_cone` rows for the accepted spells.

Native session: `/home/pikdum/.cache/thistle-wow-playtest.U3cloY`, GPU renderer,
owned unit `thistle-wow-playtest.U3cloY.service`, invocation
`78c6f751fd1c4da4886d4742f1e5f618`. WoW PID 2063146 belonged to that cgroup; its
own DRM graphics counter advanced from 4.503 to 15.316 billion nanoseconds.

Screenshots: `gnarlpine-area.png`, `elunes-blessing.png`, `cannon-cone.png`,
`flamethrower-cone.png`, `logged-out.png`, `blessing-reconnect.png`,
`blessing-stats.png`, and `blessing-cancelled.png`. Logs and final gate results
are retained under `/tmp/thistle-area-targets-*`.

The helper stopped the owned client unit; it is inactive with an empty cgroup and
WoW PID 2063146 is gone. The player owner, metadata, and position were absent
after disconnect. The server PTY was stopped and ports 4000, 3724, and 8085 were
free. No push was performed.
