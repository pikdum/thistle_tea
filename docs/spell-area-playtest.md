# Spell area rules acceptance

Validated on 2026-09-24 with the native build-5875 client and a fresh local server.
Implementation: `579edbcb`.

## Behavior and reference

The 71 VMangos `spell_area` rows are loaded into ETS at boot and attached to
internal spells. Rules combine zone/subarea, race, gender, active or rewarded
quests, and positive or negative prerequisite-aura checks. Multiple rows for a
spell are alternatives. The reference is `SpellArea::IsFitToRequirements` and
`GetSpellAllowedInLocationError` in `refs/vmangos/src/game/Spells/SpellMgr.cpp`,
plus the dependent-aura hooks in `SpellAuras.cpp` and `Player.cpp`.

Player and creature cast admission use immutable area snapshots. The shared cast
requirements also recheck at launch, and triggered casts validate at their
caster's boundary. The cast-failure packet includes the required area ID.

Player-owner reconciliation removes invalid holders through the shared aura
lifecycle and applies eligible automatic auras through spell reception. A
snapshot prevents repeated applications for unchanged requirements. There are
no gameplay Mangos queries or architecture-allowlist additions.

## Native evidence

- Character: Debugpaladin, GUID 2, level 50 human paladin.
- Session: `/home/pikdum/.cache/thistle-wow-playtest.xqZmM4`.
- Unit: `thistle-wow-playtest.xqZmM4.service`.
- Actual WoW PID: 389181. Its `amdgpu` graphics counter rose from
  1,913,465,874 ns to 18,592,372,842 ns; the client used hardware rendering.
- Server log: `/tmp/thistle-spell-area-server.log`.
- Screenshots are in the session's `screenshots/` directory.
- Tidewave was used only for read-only owner-state and terrain inspection.

### Form of the Moonstalker

Learned spell 6298 through `.learn`, then cast through the ordinary client spell
command. On Programmer Isle the client displayed **You need to be in Darkshore**
(`moonstalker-rejected.png`). The server logged `requires_area`; no transformation
was applied.

At Auberdine, `{6501.4, 481.607, 6.27062}` on map 1, the same cast succeeded.
The owner reported zone 148, area 442, aura 6298, and display 11450 instead of
native display 50. The client showed the cat model, portrait, and aura
(`moonstalker-applied.png`).

Teleporting to Stormwind removed the aura and restored display 50 in both the
owner and client (`moonstalker-left-darkshore.png`). The read-only snapshots are
`/tmp/thistle-spell-area-darkshore.log` and `/tmp/thistle-spell-area-exit.log`.

### Lordaeron's Blessing

Learned and cast source spell 30238 in Stormwind. Only the source aura was
present. Entering Light's Hope Chapel in Eastern Plaguelands automatically
applied spell 31906, whose aura grants 5% maximum health. The owner reported
zone 139, area 2268, both holders, and maximum health 2914.

At the Thondroril bridge, `{1925.08, -2621.31, 62.2875}` on map 0, strafed west
across the zone border with normal client movement, then back east. No spell
was manually cast during either crossing:

| Location | Blessing holders | Maximum health |
| --- | --- | --- |
| Eastern Plaguelands, zone 139 | 30238 and 31906 | 2914 |
| Western Plaguelands, zone 28 | 30238 only | 2776 |
| Returned to Eastern Plaguelands | 30238 and 31906 | 2914 |

Client `UnitHealthMax` output matched the owner values
(`blessing-west-health.png`, `blessing-walked-east.png`). Timed owner samples are
`/tmp/thistle-spell-area-walk-out.log` and `/tmp/thistle-spell-area-walk-in.log`.

Right-clicking the source blessing removed both holders and restored maximum
health 2776 (`blessing-cancelled.png`, `/tmp/thistle-spell-area-cancelled.log`).
After recasting, a full logout to character selection and login restored both
holders and maximum health 2914 (`blessing-relogged.png`,
`/tmp/thistle-spell-area-relogged.log`). Finally, disabling god mode and using
`.die` left health 0, maximum health 2776, and neither blessing aura
(`blessing-death.png`, `/tmp/thistle-spell-area-death.log`).

No owner, cast-completion, aura, or network errors occurred. The server's existing
unimplemented account-data, GM-ticket, and meeting-stone requests still appeared
on login; these were unrelated to the tested spell paths. One read-only probe
referenced a nonexistent base-health field; subsequent probes used the actual
health fields and the failed probe did not change state.

## Automated coverage

Tests cover all rule predicates, alternative rows, cast admission and launch
rechecking, area-ID packet encoding, all four Lordaeron area alternatives in the
generated VMangos data, prerequisite removal, quest acceptance/reward, death and
resurrection eligibility, reconnect reconciliation, controlling-player facts,
and rejecting stale area caches from another map. Data-dependent tests retain
the `vmangos_db` tag; default tests use fixtures.

This validates the shared rule system and representative native behaviors.
It does not establish acceptance for every one of the 71 content rows.

Final gates passed: `mix test.all` (5795 tests),
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix format --check-formatted`, and `git diff --check`. Logs are
`/tmp/thistle-spell-area-final-{tests,compile,credo}.log`.

The isolated client service is inactive, WoW PID 389181 exited, and the retained
server PTY was stopped. Screenshots and logs were retained. Commits are local;
nothing was pushed.
