# Periodic timing and totem duration modifiers

Implementation: `d0367319`.

Spell-modifier operation 19 now adjusts periodic aura intervals and channel
trigger schedules. Family masks select modifiers, flat changes precede percentage
changes, and intervals are truncated to positive milliseconds. The cast snapshots
the interval before spending modifier charges. Refresh retains a pending tick;
immediate-first-pulse spells retain that first pulse. Tick magnitude and duration
are independent of the activation-time operation.

Totem summoning also applies operation 1 to lifetime. This completes Improved Fire
Totems: its separate masks shorten Fire Nova's periodic trigger and summon lifetime
together. A rank-two totem fires after two seconds and lasts three seconds, leaving
no opportunity for a second explosion. Totems inherit owner modifiers through the
existing snapshot path.

Totem maintenance is bounded by its expiry timestamp and skipped when the owner
is unavailable. A final tick due exactly at expiry is preserved, but a delayed
owner update cannot produce a pulse scheduled after expiry. The tick plan wakes
at the lifetime deadline; the behavior tree still owns the despawn transition.

References: `Aura::CalculatePeriodic` in
`refs/vmangos/src/game/Spells/SpellAuras.cpp`, the final update before expiry in
`refs/vmangos/src/game/Objects/Totem.cpp`, and the VMangos spell-template masks for
16086 and 16544: `0x20` for activation time, `0x08000000` for duration. Fire Nova's
DBC periodic aura uses 4,000 ms and the summon uses 5,000 ms without talents.

## Automated verification

- `mix test.all`: **5,516 passed**.
- `mix compile --warnings-as-errors`, `mix credo --strict`: passed.
- Formatting, whitespace checks, and commit hooks: passed.

Coverage includes periodic aura types, channel scheduling, family/mask exclusion,
flat/percentage ordering, interval clamping, default regeneration intervals,
charged modifier consumption, refresh, immediate pulses, late updates, expiry,
owner loss, and inherited totem modifiers. DBC tests verify both Improved Fire
Totems ranks across all five Fire Nova ranks. Database tags remain separate.

## Native build-5875 acceptance

Debugshaman (GUID 8), raised to level 60 with existing development commands,
cast Fire Nova Totem V (11315) on Programmer Isle. Talents were learned through
`.learn`, and `.talents reset` tested removal. Casts, targeting, death, and
Reincarnation used the real client. Tidewave only read runtime state.

Read-only samplers ran before each cast, checking every 50 ms and retaining only
state changes. Timings below are measured from aura application, so observations
include up to one sampling interval of delay.

| Check | Observed result |
| --- | --- |
| No talent | Interval 4,000 ms, lifetime 5,000 ms |
| Rank one, 16086 | Interval 3,000 ms, lifetime 4,000 ms; damage observed at 3,023 ms |
| Rank two, 16544 | Interval 2,000 ms, lifetime 3,000 ms; damage observed at 2,021 ms |
| Talent reset | Restored 4,000/5,000 ms; damage observed at 4,015 ms |
| Rank-two natural expiry, away from enemies | One pulse; removal observed 11 ms after expiry |
| Owner death before baseline pulse | Totem removed about 1.2 seconds after creation; no blast damage |

Rank two changed two nearby Flayers' health from 1,977 to 1,525 and from 2,113 to
1,659. A subsequent baseline cast dealt 435 and 425 damage. The rank-one repeat
dealt 431 and 432 damage, exactly matching the floating combat numbers captured
with the visible fire ring. Client `UnitHealth` reported the selected Flayer's
health changing from 1,090/2,880 to 659/2,880. A third Flayer outside the blast
remained at 2,880. Each cast produced one health decrease per affected enemy.

Combat totems were attacked after their blast, so natural expiry was separately
measured in clear terrain. That totem retained five health, pulsed once, and
disappeared at its three-second lifetime. Owner-death acceptance removed another
totem before its first tick; enemies returned home and recovered without taking
additional blast damage. Reincarnation then restored the shaman through the
normal client action.

All seven observed totem GUIDs were absent from the entity registry, world
position projection, and metadata at final inspection. The player's totem slots
were empty. No server errors or spell-validation failures appeared. The only
warnings were existing unsupported account-data, GM-ticket, and meeting-stone
messages at login.

## Evidence and cleanup

Session: `/home/pikdum/.cache/thistle-wow-playtest.2yRU7a`.
The native WoW process used AMD GPU rendering, verified through its DRM counters.
The helper-owned client service and retained server were stopped after acceptance.

Useful screenshots under the session's `screenshots/` directory:

- `fire-nova-rank1-explosion.png`: fire ring and matching 431/432 damage numbers.
- `fire-nova-rank1-health.png`: client target health before and after damage.
- `fire-nova-rank2-expiring.png`, `fire-nova-expired.png`: pulse and natural cleanup.
- `fire-nova-owner-death.png`: owner death before the pending pulse.

Retained logs and read-only observations:

- `/tmp/thistle-periodic-timing-server.log`
- `/tmp/thistle-periodic-test-all.log`
- `/tmp/thistle-periodic-rank1-damage.json`, `/tmp/thistle-periodic-rank2.json`
- `/tmp/thistle-periodic-reset.json`, `/tmp/thistle-periodic-expiry.json`
- `/tmp/thistle-periodic-owner-death.json`, `/tmp/thistle-periodic-cleanup.json`
- `/tmp/thistle-periodic-sample.exs`, `/tmp/thistle-periodic-gpu.txt`

The `.json` observation files contain the CLI's rendered Elixir inspection output.
