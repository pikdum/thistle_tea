# Scaling racial combat buffs

Validated on 2026-09-25 against the native build-5875 client and VMangos
`8f4e60845`. Implementation commit: `7dc337a4`.

## Behavior and reference

Berserking's three resource variants now trigger its melee, ranged, and casting
haste together. The bonus captures the caster's whole health percentage:
10% at full health, increasing to 30% at 40% health or below. Subsequent healing
does not change the captured amount. All three effects end after ten seconds.
The normal spell path retains the mana, rage, or energy cost and three-minute
cooldown.

Blood Fury captures 25% of stat-derived melee attack power, excluding separate
flat attack-power bonuses. It grants that amount for 15 seconds and applies a
50% healing-received penalty for 25 seconds. Fractional bonuses use the
reference's probabilistic rounding. Canceling the positive buff does not remove
the penalty; death removes both. Its normal cooldown remains two minutes.

These rules follow `Spell::EffectDummy` in VMangos `SpellEffects.cpp`: spell
20572 for Blood Fury and generic spell icon 1661 for Berserking. The older
post-expiration Blood Fury penalty in `spell_warrior.cpp` is gated to earlier
client builds and does not apply to build 5875.

The shared typed trigger effect now accepts a map from effect index to custom
base points. One trigger can therefore override all three Berserking effects
without changing the cached spell. Unspecified effects retain their original
values; overridden effects have their dice cleared. The existing single-effect
option remains supported. Forwarding a trigger to its caster owner now retains
both these custom values and its duration override; duration previously went
missing at that boundary.

Racial logic emits typed effects and keeps database lookups at the existing
resolver boundary. Stat-derived attack power is exposed by the same pure
function used during normal recomputation. No architecture allowlist changed.

## Native acceptance

Two GPU sessions were used:

- `/home/pikdum/.cache/thistle-wow-playtest.AQigjC`: Debugshaman and Debugrogue.
- `/home/pikdum/.cache/thistle-wow-playtest.U2QXs1`: Debugrival, an Orc Warrior.

All characters were level 50 on Programmer Isle. The Orc Shaman and Warrior
used their existing Blood Fury. Native `.learn` commands gave the seeded
Shaman, Warrior, and Rogue their respective Berserking variants for testing;
this acceptance did not test creation of new Troll characters. All casts,
healing, health changes, logout/login, and death were driven through the client.
Tidewave only read owner state and sampled transitions at 100 ms intervals.

WoW's own GPU graphics counters advanced from 1,250,000,176 to 2,009,448,036 ns
for PID 1055916, and from 1,566,228,146 to 6,784,016,884 ns for PID 1057807.

| Berserking variant | Health when applied | Bonus on all three effects | Main-hand period | Cost observed |
| --- | --- | --- | --- | --- |
| Mana, spell 20554 | 2,765 / 2,765 | 10% | 2,400 → 2,181 ms | 87 mana, 7% of 1,255 base mana |
| Rage, spell 26296 | 1,900 / 2,699 | 20% | 2,100 → 1,750 ms | 50 internal rage units, or five rage |
| Energy, spell 26297 | 588 / 2,248 | 30% | 2,000 → 1,538 ms | Ten energy |

Client `UnitAttackSpeed("player")` output independently reported 1.75 seconds
for the Warrior and 1.538 seconds for the Rogue. Restoring the Rogue to full
health retained all three 30% effects and the 1,538 ms period. Each ten-second
expiry restored the original period and casting-speed multiplier.

After the Shaman's real cooldown elapsed, another low-health cast captured 30%
haste at 525 / 2,765 health. The native client then cast Healing Wave, spell
10395. Its authoritative cast duration was 2,307 ms instead of 3,000 ms. The
heal landed for 1,172 health, raising health from 574 to 1,746, while the haste
remained at 30% until expiry. The cast bar and Berserking buff were visible in
`hasted-healing-wave.png`.

Blood Fury raised the Shaman's client-displayed attack power from 364 to 455,
with a captured 91-point aura. Both the positive buff and healing penalty were
visible with their separate timers. Rank-one Healing Wave landed for 22 health
while the penalty was active. At 15 seconds attack power returned to 364 while
the penalty remained; at 25 seconds the penalty disappeared.

The Warrior's Blood Fury added 111 attack power, taking its total from 492 to
603. Its stat-derived base was 444; the other 48 attack power did not contribute
to the racial bonus. Native `.die` removed both holders and restored attack
power to 492 at health zero. The two- and three-minute cooldown entries remained
after death. Shaman logout/login after expiration retained baseline stats and
no racial holders; a subsequent cast started a fresh three-minute cooldown.

Evidence is retained in the session `screenshots/` directories, including
`berserking-full-health.png`, `berserking-mid-health.png`,
`berserking-low-health.png`, `blood-fury-active.png`, `blood-fury-death.png`, and
`hasted-healing-wave.png`. Timed owner samples and probes are in
`/tmp/thistle-racial-*.log`; the server log is `/tmp/thistle-racial-server.log`.

No owner crashes, spell-validation failures, or network errors occurred. Login
warnings were the existing account-data, GM-ticket, and meeting-stone requests.
Both helper-owned client services and the retained server were stopped after
acceptance. Logs and screenshots remain available.

## Automated checks

- `mix test.all`: 6,222 passed; `/tmp/thistle-racial-final-tests.log`.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.
- Formatting and `git diff --check`: passed.

The regressions cover custom effect values, zero and negative overrides,
unchanged effects and cached data, owner handoff, duration retention, health
thresholds, fractional rounding, stat versus flat attack power, all three
actual DBC variants, resource costs, captured values after healing or stat
changes, expiry, cancellation, and death cleanup. DBC coverage is separately
tagged; default tests do not read the generated databases. Only this acceptance
record was added after the final code checks and native run.
