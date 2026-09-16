# Mechanic resistance

Mechanic-resistance auras now protect against their matching spell mechanics.
This enables Orc Hardiness and resistance talents using aura type 117.
Mechanics are identifiers (stun is 12), not bit masks; matching bonuses add.

The implementation follows the pinned VMangos reference:

- `Objects/SpellCaster.cpp`, `MagicSpellHitChance`: subtract mechanic
  resistance from magic hit chance before the final 1–99% hit limits.
- `Objects/SpellCaster.cpp`, `RollMeleeOutcomeAgainst`: check spell mechanic
  resistance after miss, before ordinary avoidance, without shifting the
  existing dodge/parry/block thresholds.
- `Objects/Unit.cpp`, `IsEffectResist`, and `Spells/Spell.cpp`,
  `DoSpellHitOnUnit`: roll individual effect mechanics separately only when
  they differ from the spell mechanic. Keep unrelated effects.

Effect mechanics now survive DBC loading and VMangos overrides, including
explicit zero overrides. Player and creature owners publish resistance
values in their existing metadata updates; spell launches read that cache.
Melee abilities and individual effects use the target's current aura data.
There are no new gameplay database queries or timers.

A fully resisted effect group reports a resist and applies no flat spell
threat. Partial resistance preserves the other effects, including other
auras in the same holder. Magic-class spells report a resist even when
using the physical school; melee avoidance retains its separate outcomes.

## Real-client acceptance

Used two isolated build-5875 clients on Programmer Isle: level-50
Debugwarrior and level-50 Orc Debugshaman. The warrior learned test spell
56 (`Stun`) through the existing `.learn` command. All casts and duel
operations came from the clients. Gameplay state was not changed through
Tidewave.

1. Log in the warrior and shaman in separate clients.
2. On the warrior, `.learn 56`, `/target Debugshaman`, and `/duel`.
3. On the shaman, `/script AcceptDuel()`, then wait for the countdown.
   `StaticPopup_Hide("DUEL_REQUESTED")` dismisses the remaining client dialog.
4. Cast `/cast Stun` repeatedly from the warrior.
5. Inspect the shaman's stun debuff and the warrior's resisted-spell messages.

Owner inspection found passive spell 20573 with the aura tuple
`{:mechanic_resistance, 25, 12}` and metadata `[{12, 25}]`.
A temporary read-only call trace captured 12 magic hit rolls against that
25% resistance: nine hits and three resists. Rolls 9,431 and 7,570 were
above the adjusted 7,100 hit threshold but below the ordinary 9,600
threshold, demonstrating failures specifically due to Hardiness. The third
resisted roll, 9,881, would also fail without Hardiness.

A subsequent client run after the physical-school feedback fix displayed
`Your Stun was resisted by Debugshaman.` three times. The saved client log
records these at 03:03:54.910, 03:03:56.502, and 03:04:01.567. Screenshots also
show the normal stun debuff and the victim's `<Stun>` combat text.
The observer trace did not alter random rolls or entity state and disabled
itself after 60 seconds. Melee roll boundaries, partial effect resistance,
metadata removal, and loader overrides are covered by automated tests.

The first duel attempt was cancelled before acceptance; those casts were rejected
by the client as invalid targets and were excluded. The second login
initially selected the already-online warrior and produced an existing
`already_started` login error. No gameplay owner errors occurred during the
accepted duel.

Evidence retained locally:

- `/home/pikdum/.cache/thistle-wow-playtest.gV7Gwv/screenshots/corrected-resist-feedback.png`
- `/home/pikdum/.cache/thistle-wow-playtest.Ry25LP/screenshots/accepted-stun.png`
- `/home/pikdum/.cache/thistle-wow-playtest.gV7Gwv/combat-log.txt`
- `/tmp/thistle-mechanic-trace.log`
- `/tmp/thistle-mechanic-owner.log`
- `/tmp/thistle-mechanic-server.log`

Initial full-suite runs overlapped server/client startup and another test
process. They encountered a loot-cache timeout, a short instance-cleanup
assertion timeout, and an interrupted SQLite query. Final validation was
run separately after stopping the playtest.

Final validation: `mix compile --warnings-as-errors`, `mix credo --strict`
(zero issues), `mix test.all` (2,811 passing tests in 27 seconds), formatting,
and diff checks. Both isolated clients, X servers, and the game server were
stopped; evidence was retained. The successful suite log is
`/tmp/thistle-mechanic-isolated-tests.log`.
