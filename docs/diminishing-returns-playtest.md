# Crowd-control diminishing returns

Repeated crowd control now applies at full, half, and quarter duration, then
reports immunity. History belongs to the target and group, so changing casters
or refreshing an existing aura advances the same sequence. Recovery begins
15 seconds after the last holder in that group leaves. Immune attempts do not
extend that window. Death clears the history.

The rules follow the pinned VMangos references:

- `refs/vmangos/src/game/Spells/SpellEntry.cpp`,
  `GetDiminishingReturnsGroup`: mechanic priority, family exceptions, separate
  controlled/proc stuns and roots, Kidney Shot, Warlock Fear/Seduction, and
  Freezing Trap. Blind and Ice Block are exempt; Charge and Intercept retain
  the controlled-stun group.
- `refs/vmangos/src/game/Spells/SpellEntry.h`,
  `GetDiminishingReturnsGroupType` and `GetDiminishingRate`: stuns also diminish
  against creatures; other groups diminish in player-controlled combat.
- `refs/vmangos/src/game/Objects/Unit.cpp`, `GetDiminishing`,
  `ApplyDiminishingToDuration`, and `ApplyDiminishingAura`: group history,
  duration reduction, and recovery after the last aura ends.

`Spell.DiminishingReturns` classifies spells; `Logic.DiminishingReturns` owns
pure target-local history. Aura application advances once per holder, after
rank and immunity checks. The existing aura transition funnel handles expiry,
dispels, damage breaks, replacement, and removal. Aura-triggered casts carry
their provenance through the existing effect resolver. Reduced durations use
the existing aura-duration projection; exhausted groups use the existing
immune combat-log message. No gameplay database queries, boundary dependencies,
or additional runtime timers were introduced.

This implements duration diminishing returns. Separate PvP duration limits
and random heartbeat breaks are outside this change.

## Automated coverage

Tests cover spell/effect mechanic classification and vanilla exceptions;
independent groups; full/half/quarter/immunity; cross-caster replacement;
multiple effects counting once; overlapping holders; exact recovery boundaries;
immune attempts during recovery; dispels and damage breaks; death cleanup;
creature/PvP eligibility and player pets; reflected self-targeted spells;
permanent auras with negative monotonic timestamps; client duration effects;
and preserving damage when a mixed spell's control aura is immune.

## Real-client acceptance

Used two isolated build-5875 clients with level-50 Debugshaman and Debugmage
on Programmer Isle. All casts and duel actions originated in the clients.
A temporary read-only observer sampled the mage owner every 100 ms, recording
holder application/expiry timestamps and group history. It did not change
entity state or random rolls.

1. Log in both characters. On the shaman, `.learn 56`, `/target Debugmage`,
   and `/duel`. On the mage, `/script AcceptDuel()` and wait for the countdown.
2. Cast `/cast Stun` four times from the shaman.
3. Observe the mage's stun debuff and disabled actions; the fourth cast shows
   `Immune` on the shaman's client.
4. After recovery, cast Stun again and observe the full-duration debuff.
5. Learn spell 339 and cast `/cast Entangling Roots` four times, allowing
   each cast to finish. Observe the root debuff and final `Immune` feedback.

The owner trace recorded:

| Spell | First application | Second | Third | Fourth |
| --- | ---: | ---: | ---: | --- |
| Stun (56) | 3,000 ms | 1,500 ms | 750 ms | Immune, no holder |
| Entangling Roots (339) | 12,000 ms | 6,000 ms | 3,000 ms | Immune, no holder |

The stun group began recovery at monotonic time `-576460613856`, with deadline
`-576460598856`. A later client cast at `-576460584155` applied a full 3,000 ms
stun and reset the application count to one. Roots tracked their own group
independently of that stun history.

An additional Polymorph attempt was rejected with `bad_targets` before aura
application because player metadata lacked the creature type required by mask
validation. That issue and a stale expiry timer discovered in the follow-up
duel are fixed and covered in [Polymorph acceptance](polymorph-playtest.md).
The duration table above records holder timestamps; the follow-up also checks
the actual removal time after a shortened refresh. There were no owner crashes
or movement/projection errors during the accepted stun and root sequences.

One temporary observer task ended with `:noproc` after its client disconnected
during cleanup. Client combat logging was enabled, but its on-disk log did not
flush this session; acceptance relies on screenshots, server input logs, and
the owner trace.

Evidence retained locally:

- `/home/pikdum/.cache/thistle-wow-playtest.g8grrm/screenshots/stun-immunity.png`
- `/home/pikdum/.cache/thistle-wow-playtest.g8grrm/screenshots/roots-immunity.png`
- `/home/pikdum/.cache/thistle-wow-playtest.EfVTaU/screenshots/recovered-stun.png`
- `/home/pikdum/.cache/thistle-wow-playtest.EfVTaU/screenshots/roots-first.png`
- `/tmp/thistle-diminishing-observer.log`
- `/tmp/thistle-diminishing-server.log`

Final code validation: `mix compile --warnings-as-errors`, `mix test.all`
(2,833 passing tests), `mix credo --strict` (zero issues), formatting, and diff
checks. The first full run exposed three partial-entity fixture failures; the
reconciliation hook was corrected and the full suite passed afterward.
Both clients, private X servers, and the local game server were stopped.
