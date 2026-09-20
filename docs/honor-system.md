# Honor system implementation

The calculation layer, player and creature kills, Warsong bonuses, honor
spells, and rank requirements are implemented. Automatic Honorless Target
application remains to be connected. Player kills, repeat penalties, gray rejection, party and pet
credit, inspection, and reconnect retention have real-client acceptance in
[honor-playtest.md](honor-playtest.md). Creature kills, honor spells, Warsong
captures and victories, scoreboard refresh, and exit retention are validated
in [honor-rewards-playtest.md](honor-rewards-playtest.md). Team kill sharing,
pet killing blows, dead teammate credit, Spirit of Redemption, and exit
resurrection are validated in
[honor-battleground-playtest.md](honor-battleground-playtest.md).

## Implemented rules

- Honor uses the vanilla 1.12 killer-level coefficients, victim-rank scaling,
  gray-level cutoff, and level-difference modifier.
- Repeated kills of one player lose ten percent of credit per kill, reaching
  zero after ten credited kills that day. Zero-credit awards do not add kills.
- Damage history expires after one minute without damage. Nonplayer damage
  remains in the denominator. Nearby living enemies receive individual or
  group shares, including eligible party members who did not deal damage.
- Battleground honor shares use the admitted team roster, including raid-size
  scaling. Scoreboard kills independently credit the killer and nearby online
  teammates, including dead players near the victim or with a nearby corpse.
  Pet killing blows credit their controlling player. Spirit of Redemption
  credits the initial defeat and drops the flag immediately, then records one
  death when the form expires. Warsong scoring requires an active match.
- Voluntary, exit-trigger, and timed battleground exits share owner cleanup:
  dead players and ghosts regain full health and resources, corpses disappear,
  and Spirit of Redemption ends without a delayed suicide outside the match.
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
- Equipment and item use require the highest rank ever earned. Vendor
  purchases require the current rank and the item's required level; losing
  rank preserves use of already-earned equipment but prevents new purchases.
  Ranked merchandise remains visible and rejected purchases spend no money.
- Condition 51 compares current visible ranks, from zero through fourteen,
  with equality or inclusive bounds. Player, AI, and published condition
  snapshots use the same rank conversion.

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
honor-reward paths in `Objects/Unit.cpp` and `Objects/Player.cpp`. Item gates
follow `Player::CanUseItem` and `Player::BuyItemFromVendorSlot` for patch 1.12;
condition ranks follow `Conditions.cpp`.

For testing, `.debug honor` reports current and highest rank, and
`.debug honor points <0..65000>` sets rank points through the realm ledger.
The command respects level caps, preserves earned rank and contribution
history, and follows the normal owner projection and change-notice paths.

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

1. Connect automatic Honorless Target application during world-entry transitions.
2. Extend client acceptance to automatic Honorless Target protection. Calendar/ranking tests cover
   settlement without waiting for a real weekly reset.

Honorless Target rejection has automated coverage; its real-client acceptance
will accompany automatic application during world-entry transitions.
