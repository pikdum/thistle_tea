# Caster-limited auras

Spells carrying the single-target aura flag now replace the same caster's
matching aura on another target. Matching follows spell family and icon,
with shared categories for Polymorph variants and paladin judgements.
Different casters and unrelated spell groups retain independent claims.

Pure aura transitions publish typed claims only after an application is
accepted. A supervised registry serializes replacements and sends removals
to the recipient owner. Each application has a generation, so delayed
removals cannot erase a refreshed holder. The registry compares successive
publications so an unchanged, displaced holder cannot reclaim its slot
while its removal is queued.

Expiry, dispels, death, logout, world transfer, corpse removal, respawn, and
owner exit use the shared transition and cleanup paths. Caster death
removes stalked auras such as Hunter's Mark while leaving other controls
active. World departure removes foreign incoming auras and outgoing claims;
self-cast holders are retained and republished where appropriate.

## References and automated validation

- `refs/vmangos/src/game/Objects/Unit.cpp`: accepted-holder registration,
  `RemoveNotOwnSingleTargetAuras`, `RemoveAllAurasOnDeath`, and world removal.
- `refs/vmangos/src/game/Spells/SpellEntry.cpp`, `IsSingleTargetSpells`:
  family/icon matching and the judgement/Polymorph categories.
- `refs/vmangos/src/game/Spells/SpellAuras.cpp`,
  `UnregisterSingleCastHolder`: exact holder unregistration.
- The existing VMangos custom-flag cache supplies the single-target flag;
  separate DBC and VMangos tests verify real ranks, variants, and flags.

The 23 added regressions cover accepted versus blocked applications,
same-millisecond refreshes, stale removals and publications, lifecycle
cleanup, independent casters and groups, owner replacement and process
exit, instance isolation, real player/mob handlers, and ten concurrent
recipients producing exactly one winning claim and nine removals.

Implementation commit `a9ef32f9` passed `mix test.all` (5,585 tests),
`mix compile --warnings-as-errors`, `mix credo --strict` (zero issues),
formatting, and whitespace checks. Native acceptance used this final code
on a fresh server without live reloads.

## Native client acceptance

The isolated build-5875 GPU client used Debugmage (GUID 5), level 60, with
god mode off. Native commands learned the test spells, cast them, moved
between maps, logged out, reconnected, and killed the caster. Tidewave only
read state. The initial location was Programmer Isle, map 451, near
`{16303.2, 16318.1, 69.44}`.

The two targets were Prairie Wolf Alpha (entry 2960, GUID
17379391011684294224) and Mottled Worg (entry 1766, GUID
17379390991652298420). Each timed sampler retained changes in their aura
holders, application generations, display IDs, and crowd-control state.
Times below are relative to each separate sampler.

| Trial | Observed result |
| --- | --- |
| Polymorph variants | Rank 4 (12826) landed on the Alpha at 3,807 ms, changing display 161 to sheep 856. Polymorph: Pig (28272) landed on the Worg at 8,980 ms, changing display 246 to pig 16358 while restoring the Alpha's display and clearing its crowd control. |
| Hunter's Mark ranks | Rank 1 (1130) landed on the Alpha at 3,885 ms. Rank 4 (14325) landed on the Worg at 8,256 ms and removed the Alpha's mark. |
| Map transfer | Moving the mage to Northshire on map 0 removed the Worg's mark at 2,526 ms, before expiry. The caster had no remaining claims. |
| Logout and reconnect | After returning to Programmer Isle and marking the Alpha, normal logout removed the mark at 22,386 ms. The client reached character selection and the owner exited. Reconnecting restored a ready owner with health 2,470, god mode off, and no claims. |
| Caster death | Polymorph landed on the Alpha at 5,315 ms and Hunter's Mark landed on the Worg at 8,759 ms. After native `.die`, the mark disappeared at 11,264 ms while the same Polymorph holder, generation, expiry, sheep display, and control state remained through the rest of the sampler. |

Client screenshots showed the changed target portraits and debuffs, the
old target's cleared debuff, the destination map, character selection,
and the caster's death dialog. The Alpha resumed attacking after its
Polymorph was replaced. The two unrelated aura groups coexisted before
caster death.

No server errors or cast-validation failures occurred. Unsupported requests
were limited to the known account-data, GM-ticket, and meeting-stone login
messages. WoW process 152932 had its own amdgpu DRM rendering counters.
The helper-owned client cgroup and server were stopped. A final read after
client shutdown found no player owner, no caster claims, and neither test
creature carrying a test aura.

There was no second observer client. Concurrent casters, copy isolation,
abrupt owner exit, refresh races, dispels, and forced respawn have automated
coverage; the native trials above exercised Polymorph and Hunter's Mark.

## Retained evidence

- Client session: `/home/pikdum/.cache/thistle-wow-playtest.mWc7H4/`.
- Screenshots in its `screenshots/`: `polymorph-first.png`,
  `polymorph-second.png`, `polymorph-old-target-cleared.png`,
  `mark-second.png`, `mark-old-target-cleared.png`, `transferred.png`,
  `mark-before-logout.png`, `logged-out.png`, `two-independent-limits.png`,
  and `caster-death.png`.
- Timed samples: `/tmp/thistle-single-target-polymorph.txt`,
  `/tmp/thistle-single-target-mark.txt`,
  `/tmp/thistle-single-target-worldport.txt`,
  `/tmp/thistle-single-target-logout.txt`, and
  `/tmp/thistle-single-target-death.txt`.
- Reconnect and final cleanup: `/tmp/thistle-single-target-reconnect.txt`
  and `/tmp/thistle-single-target-cleanup.txt`.
- Server and GPU evidence: `/tmp/thistle-single-target-server.log` and
  `/tmp/thistle-single-target-gpu.txt`.
- Gates: `/tmp/thistle-single-target-{tests,compile,credo}.log`.
