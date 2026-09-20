# Honor system implementation

The calculation layer, player and creature kills, Warsong bonuses, and honor
spells are implemented. Rank requirements and automatic Honorless Target
application remain to be connected. Player kills, repeat penalties, gray rejection, party and pet
credit, inspection, and reconnect retention have real-client acceptance in
[honor-playtest.md](honor-playtest.md).

## Implemented rules

- Honor uses the vanilla 1.12 killer-level coefficients, victim-rank scaling,
  gray-level cutoff, and level-difference modifier.
- Repeated kills of one player lose ten percent of credit per kill, reaching
  zero after ten credited kills that day. Zero-credit awards do not add kills.
- Damage history expires after one minute without damage. Nonplayer damage
  remains in the denominator. Nearby living enemies receive individual or
  group shares, including eligible party members who did not deal damage.
- Daily records distinguish honorable kills, dishonorable kills, and bonus
  contribution. Dishonorable kills immediately reduce rank points without
  subtracting weekly contribution or the highest rank previously earned.
- Gray civilians and civilians with zero XP multiplier impose the vanilla
  level-dependent dishonorable penalty. Racial leaders award 488 honor per
  eligible player, without group division or the player repeat-kill penalty.
- Creature rewards follow the original tag and its surviving group, including
  when another player lands the killing blow. Honor excludes dead or distant
  group members, pets, totems, and Honorless Target victims.
- Spell effect 45 awards its unscaled DBC amount without a kill. Warsong flag
  captures and victories award bonus honor to players inside the match;
  the scoreboard and ledger use the same captured recipient list.
- Weekly ranking requires fifteen honorable kills, separates factions, uses
  population-sized brackets and interpolation, applies twenty-percent decay,
  halves net losses, caps losses at 2,500 points, and enforces level caps.
- The pure realm ledger settles every registered character together, handles
  multiple missed weeks, and retains lifetime totals and the highest rank.
  Its default week starts Tuesday; the reset weekday is configurable.
- Client projection covers today's packed kill counts, yesterday, this week,
  last week, lifetime totals, rank, highest rank, and rank progress.

The core modules have no database, process, clock, metadata, or packet-send
dependencies. `World.System.Honor` owns the realm ledger, retained in an
application-owned ETS table across coordinator restarts. Calendar settlement
precedes each request and runs during idle periods. Player owners fetch the
current projection for change notices, login, and level changes, then save
their own character and publish rank metadata through `World.Presence`.

The damage funnel captures effective damage, overkill, and Honorless Target
before death removes auras. The receiving boundary resolves pets to their
controlling players. A lethal request consumes damage history once, resolves
nearby living group recipients in the same world, and submits their shares
together. Duels do not produce lethal credit; Spirit of Redemption consumes
the original kill history before its final self-inflicted death.

Recipients receive `SMSG_PVP_CREDIT` and updated honor fields. Honor inspection
uses the build-5875 packet layout and requires an online target within ten
yards in the same world who cannot be attacked by the inspecting player.

## References and validation

References are local VMangos `HonorMgr.cpp`, `Formulas.h`, and the damage and
honor-reward paths in `Objects/Unit.cpp` and `Objects/Player.cpp`.

An independent executable compiled the ranking functions extracted from
`HonorMgr.cpp`. Across 1,613 standings in pools of 1, 2, 10, 100, 500, and
1,000 players, the maximum difference was 0.000334 rank points, attributable
to single- versus double-precision arithmetic. In particular, a one-player
eligible pool earns 3,000 points, rather than the full-pool maximum of 13,000.
The temporary oracle source and output are `/tmp/thistle-honor-rank-oracle.cpp`
and `/tmp/thistle-honor-rank-oracle.txt`.

Tests cover repeat victims, day changes, zero awards, contribution shares,
group eligibility, faction separation, tied scores, rank boundaries, decay,
level caps, idempotent weekly settlement, missed weeks, coordinator restart,
pet ownership, absorption and overkill, one-time death credit, Honorless
Target, Spirit of Redemption, current player projections, and packet dispatch.

## Remaining integration and acceptance

1. Complete battleground team sharing and scoreboard kill semantics, including
   nearby allies, pet killing blows, and Spirit of Redemption. Scoreboard HKs
   and honor-ledger HKs follow different vanilla eligibility rules.
2. Apply honor-rank conditions and equipment/vendor requirements, and connect
   automatic Honorless Target application during world-entry transitions.
3. Extend client acceptance to the new reward sources, rank requirements, and
   automatic Honorless Target protection. Calendar/ranking tests cover
   settlement without waiting for a real weekly reset.

Honorless Target rejection has automated coverage; its real-client acceptance
will accompany automatic application during world-entry transitions.
