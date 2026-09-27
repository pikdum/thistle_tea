# Spell range modifiers

Spell-family range bonuses now apply to unit cast admission, active channel
checks, Auto Shot and wand repeats, charmed-player spell selection, and creature
healing and pet target discovery. Ground destinations use the same pure
`Spell.Range` calculation. Base spell data remains unchanged, so removing a
bonus restores subsequent checks immediately.

Flat bonuses apply before percentage bonuses, using the existing family and
64-bit effect masks and inherited pet modifiers. Minimum range, combat reach,
world isolation, and existing cast leeway remain separate. A reduction to zero
does not disable range checks. Channels apply hostile or friendly grace before
the modifiers, matching VMangos `SpellAuraHolder::Update`; ordinary casts follow
`Spell::CheckRange`. The reference checkout is
`8f4e608450460efe1e38743e4da74397d4773a3a`.

Implementation: `58104823 feat(spells): apply range modifiers to unit casting and attacks`.
The native-discovered channel correction is
`7bdc7bde fix(spells): validate pet channels against their recipient`.

## Regression coverage

Six new regressions failed before the range implementation: extended unit
casts, combat reach, range reductions, channel grace, inherited pet observation
range, and Auto Shot. Tests also cover unrelated family masks, unchanged
minimum range, world isolation, bonus removal, and absent base ranges.

DBC coverage checks Flame Throwing, Arctic Reach, Nature's Reach, Shadow Reach,
Destructive Reach, Grim Reach, Hawk Eye, Improved Mend Pet, Improved Lightning
Bolt, Improved Smite and Holy Fire, Holy Reach, and Storm Reach. Grim Reach and
Storm Reach use VMangos mask fixtures verified against the generated database;
the DBC-tagged test does not query that database.

## Native acceptance

Build-5875 GPU clients use Debughunter, GUID 7, on Programmer Isle. Existing
debug commands provide spells and positioning; casts, pet commands, movement,
and reconnect use native client input. Tidewave observations are read-only.

The first session, `thistle-wow-playtest.8SrWdE`, established these facts:

- At about 39.2 yards from a rabbit, base-range Auto Shot displayed `Out of
  range` and retained all 200 arrows.
- Learning Hawk Eye rank 3, spell 19500, increased the authoritative maximum
  from 35 to 41 yards. Auto Shot consumed one arrow and killed the rabbit.
  Combat distance was about 36.7 yards, beyond the old repeat check's limit.
  Client and server positions agreed independently.
- Talent reset restored 35 yards and rejected the same shot, preserving 199
  arrows. Relearning restored the shot. A 50 ms sampler recorded ammunition
  falling to 198, target health reaching zero, repeat cleanup, and respawn.
- A pet held on Stay about 28.2 yards away caused ordinary Mend Pet to fail
  admission with `out_of_range`. Learning the Improved Mend Pet equipment
  passive, spell 23560, increased cast range from 20 to 30 yards and friendly
  channel range from 21.25 to 31.875 yards.

That last attempt exposed a separate channel bug: the native client selects
the caster for Mend Pet, but its resolved recipient is the pet. Channel
validation compared the caster GUID with the hit list and immediately
cancelled. The correction validates pet channels against their recorded pet
recipient. Its regression covers Mend Pet, Health Funnel, cancellation cleanup,
and refusal when only the caster appears in the hit list.

The final session, `thistle-wow-playtest.WsL0p7`, ran a fresh server after that
correction. Extended-range Auto Shot again spent one arrow. Native backward
movement left the pet on Stay about 28.0 yards away. Mend Pet retained its pet
channel object for the full five seconds and cleared the channel afterward.
With god mode disabled, a repeat cast paid 210 mana, remained active for
5,027 ms in the 50 ms sampler, and then cleared both channel fields. The pet
was at full health; this checks channel admission, duration, cost, and cleanup,
not an injured pet's healing amount.

Logout removed the player owner, metadata, and position, while the runtime
character store retained both learned bonuses and 199 arrows. Reconnect
created a new owner with 41-yard Auto Shot and 30-yard Mend Pet, no active
repeat or cast, and cleared channel fields. Another native extended-range
Auto Shot consumed one arrow. The previous pet owner and position were gone.

## Checks and evidence

- `mix test.all`: 6,864 passed in 75.9 seconds after the final code edit.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues; commit formatting checks passed.

Runtime and checks used
`NAMIGATOR_SRC=/nix/store/3nds85i5fyjgpqcgjnk03fdfgs798vfn-namigator-with-wmo-metadata`.

Evidence files use `/tmp/thistle-spell-range-`. The final run retained
`final-server.log`, `final-setup.txt`, `final-mend-watch.txt`,
`final-paid-mend-watch.txt`, `final-logout.txt`, `final-retained.txt`,
`final-reconnected.txt`, `final-reconnected-shot.txt`, and `final-cleanup.txt`.
Gate logs use `final-all.log`, `final-compile.log`, and `final-credo.log`.
Earlier evidence includes `client-position.json`, `reset.txt`, and
`shot-repeat-watch.txt`.

The final session retains `mend-channel-start.png`, `mend-channel-completed.png`,
`mend-paid-channel.png`, `logged-out.png`, and `reconnected-shot.png` under its
`screenshots/` directory. Initial range rejection screenshots are
`base-range-rejected.png`, `reset-range-rejected.png`, and
`mend-base-range-rejected.png` in the first session.

The final server log contains no errors; warnings are limited to existing
unsupported account-data and GM-ticket requests. WoW PID 2036856 used hardware
rendering, with its own graphics counter increasing from 2,737,967,712 to
13,409,205,671 ns. Final logout again removed the player owner, metadata, and
position. Both helper services were stopped through their recorded
invocations (`5f0b0809b95440fdbcccb8e46f31a9b1` and
`2ae87bf4d3ce4505b3ab37935ecf472f`), became inactive, and had empty cgroups.
Both WoW PIDs disappeared, both retained server PTYs exited, and ports 4000,
3724, and 8085 were free. Artifacts were retained.
