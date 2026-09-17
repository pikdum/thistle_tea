# Mana-based absorption and Improved Mana Shield

Mana shields now use their effect's school mask and mana conversion value.
Vanilla Mana Shield protects against physical damage at two mana per point.
Improved Mana Shield reduces that conversion by 10% or 20%, using the shielded
unit's current spell-family modifiers on each hit. Learning or resetting the
talent therefore affects an already-active shield.

Ordinary school absorbs resolve before mana shields, independently of the
order in which the spells were applied. Available mana and remaining shield
capacity both limit absorption. Running out of mana leaves the remaining shield
active; later mana recovery lets it absorb again. Exhausted shields are removed
through the shared aura transition. Capacity rounds down and mana expenditure
rounds to the nearest integer, bounded by available mana. Fractional conversion
uses deterministic rounding rather than VMangos's randomized dithering.

Related fixes:

- Melee combat feedback reports damage remaining after absorption, so a fully
  absorbed hit displays as absorbed and partial hits report only the overflow.
- `.die` uses the existing environmental damage path to bypass shields and
  damage reductions. Previously a shield could leave the character alive while
  the command reported death. God mode still requires explicit disabling.

References: `Unit::CalculateAbsorbAndResist`, `Unit::SendAttackStateUpdate`, and
`Aura::HandleManaShield` in `refs/vmangos/src/game/Objects/Unit.cpp` and
`refs/vmangos/src/game/Spells/SpellAuras.cpp`. The reference records ordinary
shield priority as the patch 1.11 behavior. DBC data confirms school mask 1 and
conversion 2.0 for every Mana Shield rank. VMangos talent masks select the mage
Mana Shield family flag `0x8000`.

## Real-client acceptance

Two isolated build-5875 clients ran level-50 Debugmage (GUID 5) and Debugwarlock
(GUID 6) in a duel on Programmer Isle, with god mode disabled. Spells, melee
attacks, talent learning/resetting, and aura cancellation came through client
commands. Read-only Tidewave samples recorded health, mana, shield capacities,
expiration times, and the current conversion every 100 ms. Regeneration was
left enabled and appears separately in the recorded samples.

- Rank 1 absorbed a 109-point melee hit, spending 218 mana and leaving health
  unchanged. The next hit consumed its final 11 capacity and 22 mana, then
  removed the shield and dealt 118 damage. The client's combat log showed full
  absorption followed by “118 (11 absorbed).”
- Rank 4 was cast before learning Improved Mana Shield rank 2 (12605). A
  subsequent 111-point hit spent 178 mana and reduced capacity from 390 to 279.
  Resetting talents changed conversion from 1.6 to 2.0 without changing the
  shield's expiration or remaining capacity. The next 119-point absorbed hit
  spent 238 mana. A later hit exhausted the shield and dealt only overflow.
- Shadow Bolt rank 1 dealt 18 shadow damage while Mana Shield's 390 capacity
  and the mage's mana were unchanged at impact. The client displayed shadow
  damage and retained the shield buff.
- Ice Barrier was cast after Mana Shield. A 113-point melee hit reduced Ice
  Barrier from 454 to 341 while Mana Shield stayed at 390 and mana stayed at
  3388. Both clients displayed complete absorption. One preceding swing missed.
- Mana Shield expired at the end of its normal duration, with the client
  showing its fade and the owner retaining no mana-shield holder afterward.
  A newly cast shield was then cancelled by right-clicking its buff; samples
  showed immediate removal without an additional mana charge.
- The first `.die` attempt exposed the debug-command bug: the shield absorbed
  390 damage, leaving 390 health and consuming 780 mana. After loading the fix,
  the repeated client command changed health from 1020 to zero, removed the
  active shield, and left mana at 3593. The duel cancelled and the client showed
  the release-spirit prompt. Subsequent samples stayed dead with no shield.
- The warlock's combat log independently displayed full absorption, partial
  damage, Shadow Bolt damage, and shield gains. Both client sessions and the
  retained server were stopped before final validation.

An attempted rank-5 cast was unavailable to the level-50 mage; the accepted
talent checks used rank 4. The first server launch hit a waypoint-query timeout
while the commit hook was running. A fresh launch completed normally. No
gameplay owner or packet errors appeared in the accepted server log.

Automated coverage additionally verifies both talent ranks, all Mana Shield
DBC ranks, unrelated family/mask rejection, custom school masks and conversion,
zero-cost shields, fractional mana limits, mana exhaustion and recovery, both
shield application orders, and full/partial melee feedback. Mana exhaustion
and recovery were checked with deterministic tests, not in the live duel.

## Validation

- `mix test.all`: 3,082 passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: zero issues.

## Evidence

- Mage screenshots:
  `/home/pikdum/.cache/thistle-wow-playtest.R9639L/screenshots/`, especially
  `baseline-hit.png`, `talented2-hit.png`, `magic-bypass.png`,
  `barrier-priority.png`, `cancelled.png`, and `death-fixed.png`.
- Observer screenshot:
  `/home/pikdum/.cache/thistle-wow-playtest.dU2mO5/screenshots/observer-log.png`.
- Runtime samples: `/tmp/thistle-mana-baseline.txt`,
  `/tmp/thistle-mana-talented2.txt`, `/tmp/thistle-mana-schools-priority.txt`,
  `/tmp/thistle-mana-lifecycle.txt`, `/tmp/thistle-mana-cancel-death.txt`, and
  `/tmp/thistle-mana-death-fixed.txt`.
- Accepted server log: `/tmp/thistle-mana-server.log`.
- Final gates: `/tmp/thistle-mana-final-{tests,compile,credo}.log`.
