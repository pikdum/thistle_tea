# Honor system implementation

The calculation layer is implemented. Gameplay awards and client delivery are
still being integrated; honor is not yet awarded by live combat.

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
- Weekly ranking requires fifteen honorable kills, separates factions, uses
  population-sized brackets and interpolation, applies twenty-percent decay,
  halves net losses, caps losses at 2,500 points, and enforces level caps.
- The pure realm ledger settles every registered character together, handles
  multiple missed weeks, and retains lifetime totals and the highest rank.
  Its default week starts Tuesday; the reset weekday is configurable.
- Client projection covers today's packed kill counts, yesterday, this week,
  last week, lifetime totals, rank, highest rank, and rank progress.

The core modules have no database, process, clock, metadata, or packet-send
dependencies. A runtime coordinator will own the realm ledger; player owners
will apply the resulting field projections and publish their own metadata.

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

Core tests cover repeat victims, day changes, zero awards, contribution shares,
group eligibility, faction separation, tied scores, rank boundaries, decay,
level caps, idempotent weekly settlement, and missed weeks.

## Remaining integration and acceptance

1. Add the runtime ledger coordinator and retained ETS state, with serialized
   awards and weekly settlement, login synchronization, and offline rankings.
2. Capture effective damage and controlling-player identity at the receiving
   boundary. Use the shared death transition to distribute credit exactly
   once; preserve the Honorless Target fact before death removes auras.
3. Connect racial-leader and civilian kills, battleground bonus rewards, and
   honor-granting spells. Keep battleground scoreboards and character totals
   consistent without counting the same kill twice.
4. Deliver PvP-credit and honor-inspection messages, project rank metadata,
   and apply honor-rank conditions and equipment/vendor requirements.
5. Exercise real opposing players: shared and pet kills, repeat penalties,
   gray and honorless rejection, client honor totals and combat feedback,
   reconnect retention, and lifecycle cleanup. Calendar/ranking tests cover
   settlement without waiting for a real weekly reset.

No real-client acceptance has been performed for honor yet.
